from __future__ import annotations

import hashlib
import logging
import os
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal

from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from google.cloud.firestore_v1.base_vector_query import DistanceMeasure
from google.cloud.firestore_v1.vector import Vector
from pydantic import BaseModel, Field, model_validator

from function_common import openai_client


MemoryDomain = Literal["learning", "preference"]
MemoryScope = Literal["global", "course", "lecture"]
MemoryStatus = Literal["candidate", "active", "resolved", "superseded", "deleted"]


class MemoryWrite(BaseModel):
    domain: MemoryDomain
    kind: str = Field(min_length=1, max_length=80)
    content: str = Field(min_length=1, max_length=4000)
    scope: MemoryScope = "global"
    course_id: str | None = None
    lecture_id: str | None = None
    preference_key: str | None = None
    confidence: float = Field(default=0.7, ge=0, le=1)
    importance: float = Field(default=0.5, ge=0, le=1)
    explicit: bool = False
    metadata: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_scope_and_preference(self) -> "MemoryWrite":
        if self.scope in {"course", "lecture"} and not self.course_id:
            raise ValueError("course_id is required for course or lecture memory")
        if self.scope == "lecture" and not self.lecture_id:
            raise ValueError("lecture_id is required for lecture memory")
        if self.domain == "preference" and not self.preference_key:
            raise ValueError("preference_key is required for preference memory")
        return self


@dataclass(frozen=True)
class MemorySearchResult:
    memory_id: str
    data: dict[str, Any]
    distance: float | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "memory_id": self.memory_id,
            **_without_embedding(self.data),
            "distance": self.distance,
        }


def normalize_memory_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().casefold())


def memory_document_id(uid: str, memory: MemoryWrite) -> str:
    if memory.domain == "preference" and memory.preference_key:
        identity = memory.preference_key
    else:
        identity = normalize_memory_text(memory.content)
    raw = "|".join(
        [
            uid,
            memory.domain,
            memory.kind,
            memory.scope,
            memory.course_id or "",
            memory.lecture_id or "",
            identity,
        ]
    )
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def _without_embedding(data: dict[str, Any]) -> dict[str, Any]:
    return {
        key: _json_safe(value)
        for key, value in data.items()
        if key != "embedding"
    }


def _json_safe(value: Any) -> Any:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    return value


class MemoryService:
    def __init__(self, *, database: Any | None = None) -> None:
        self._database = database or firestore.client()
        self._embedding_model = os.getenv(
            "OPENAI_MEMORY_EMBEDDING_MODEL", "text-embedding-3-small"
        )
        self._embedding_dimensions = int(
            os.getenv("OPENAI_MEMORY_EMBEDDING_DIMENSIONS", "768")
        )

    def _collection(self, uid: str):
        return self._database.collection("users").document(uid).collection("memories")

    def _evidence_collection(self, uid: str):
        return (
            self._database.collection("users")
            .document(uid)
            .collection("memory_evidence")
        )

    def _embed(self, text: str) -> list[float]:
        response = openai_client().embeddings.create(
            model=self._embedding_model,
            input=text,
            dimensions=self._embedding_dimensions,
        )
        return response.data[0].embedding

    def remember(
        self,
        *,
        uid: str,
        memory: MemoryWrite,
        source: str,
        source_ref: str | None = None,
    ) -> dict[str, Any]:
        embedding = self._embed(memory.content)
        target_id = memory_document_id(uid, memory)

        if memory.domain == "learning":
            duplicates = self.search(
                uid=uid,
                query=memory.content,
                domains={"learning"},
                statuses={"active", "candidate"},
                course_id=memory.course_id,
                lecture_id=memory.lecture_id,
                limit=3,
                query_embedding=embedding,
            )
            semantic_match = next(
                (
                    item
                    for item in duplicates
                    if item.distance is not None
                    and item.distance <= 0.15
                    and item.data.get("kind") == memory.kind
                    and item.data.get("scope") == memory.scope
                ),
                None,
            )
            if semantic_match is not None:
                target_id = semantic_match.memory_id

        memory_ref = self._collection(uid).document(target_id)
        snapshot = memory_ref.get()
        existing = snapshot.to_dict() if snapshot.exists else {}
        evidence_count = int(existing.get("evidenceCount", 0)) + 1
        status: MemoryStatus
        if memory.domain == "preference" and not memory.explicit and evidence_count < 2:
            status = "candidate"
        else:
            status = "active"

        data = {
            "domain": memory.domain,
            "kind": memory.kind,
            "content": memory.content.strip(),
            "normalizedContent": normalize_memory_text(memory.content),
            "scope": memory.scope,
            "courseId": memory.course_id,
            "lectureId": memory.lecture_id,
            "preferenceKey": memory.preference_key,
            "confidence": max(float(existing.get("confidence", 0)), memory.confidence),
            "importance": max(float(existing.get("importance", 0)), memory.importance),
            "explicit": bool(existing.get("explicit", False)) or memory.explicit,
            "evidenceCount": evidence_count,
            "status": status,
            "embedding": Vector(embedding),
            "embeddingModel": self._embedding_model,
            "embeddingDimensions": self._embedding_dimensions,
            "lastSource": source,
            "metadata": {**existing.get("metadata", {}), **memory.metadata},
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "lastUsedAt": existing.get("lastUsedAt"),
        }
        if not snapshot.exists:
            data["createdAt"] = firestore.SERVER_TIMESTAMP
        memory_ref.set(data, merge=True)

        evidence_ref = self._evidence_collection(uid).document()
        evidence_ref.set(
            {
                "memoryId": target_id,
                "domain": memory.domain,
                "kind": memory.kind,
                "content": memory.content.strip(),
                "source": source,
                "sourceRef": source_ref,
                "confidence": memory.confidence,
                "importance": memory.importance,
                "explicit": memory.explicit,
                "metadata": memory.metadata,
                "createdAt": firestore.SERVER_TIMESTAMP,
            }
        )
        return {"memory_id": target_id, **_without_embedding(data)}

    def search(
        self,
        *,
        uid: str,
        query: str,
        domains: set[str] | None = None,
        statuses: set[str] | None = None,
        course_id: str | None = None,
        lecture_id: str | None = None,
        limit: int = 8,
        query_embedding: list[float] | None = None,
    ) -> list[MemorySearchResult]:
        if not query.strip():
            return self.list_active(
                uid=uid,
                domains=domains,
                course_id=course_id,
                lecture_id=lecture_id,
                limit=limit,
            )

        embedding = query_embedding or self._embed(query)
        try:
            vector_query = self._collection(uid).find_nearest(
                vector_field="embedding",
                query_vector=Vector(embedding),
                limit=max(limit * 4, 20),
                distance_measure=DistanceMeasure.COSINE,
                distance_result_field="vectorDistance",
            )
            candidates = [
                MemorySearchResult(
                    memory_id=document.id,
                    data=document.to_dict(),
                    distance=document.to_dict().get("vectorDistance"),
                )
                for document in vector_query.stream()
            ]
        except Exception:
            logging.exception("Vector memory search failed; using structured fallback")
            candidates = [
                MemorySearchResult(document.id, document.to_dict())
                for document in self._collection(uid).limit(100).stream()
            ]

        filtered = [
            item
            for item in candidates
            if self._matches(
                item.data,
                domains=domains,
                statuses=statuses or {"active"},
                course_id=course_id,
                lecture_id=lecture_id,
            )
        ][:limit]
        self._touch(uid, filtered)
        return filtered

    def list_active(
        self,
        *,
        uid: str,
        domains: set[str] | None = None,
        course_id: str | None = None,
        lecture_id: str | None = None,
        limit: int = 20,
    ) -> list[MemorySearchResult]:
        query = self._collection(uid).where(
            filter=FieldFilter("status", "==", "active")
        )
        results = [
            MemorySearchResult(document.id, document.to_dict())
            for document in query.limit(100).stream()
            if self._matches(
                document.to_dict(),
                domains=domains,
                statuses={"active"},
                course_id=course_id,
                lecture_id=lecture_id,
            )
        ][:limit]
        self._touch(uid, results)
        return results

    def resolve(self, *, uid: str, memory_id: str, reason: str = "") -> None:
        self._collection(uid).document(memory_id).set(
            {
                "status": "resolved",
                "resolutionReason": reason,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    def forget(self, *, uid: str, memory_id: str, reason: str = "") -> None:
        self._collection(uid).document(memory_id).set(
            {
                "status": "deleted",
                "deletionReason": reason,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    def _matches(
        self,
        data: dict[str, Any],
        *,
        domains: set[str] | None,
        statuses: set[str],
        course_id: str | None,
        lecture_id: str | None,
    ) -> bool:
        if data.get("status") not in statuses:
            return False
        if domains and data.get("domain") not in domains:
            return False
        scope = data.get("scope")
        if scope == "course" and data.get("courseId") != course_id:
            return False
        if scope == "lecture" and data.get("lectureId") != lecture_id:
            return False
        return True

    def _touch(self, uid: str, memories: list[MemorySearchResult]) -> None:
        for memory in memories:
            self._collection(uid).document(memory.memory_id).set(
                {"lastUsedAt": firestore.SERVER_TIMESTAMP}, merge=True
            )
