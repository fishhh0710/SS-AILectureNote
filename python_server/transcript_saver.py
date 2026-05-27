from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any
import json
import re
import threading

from pydantic import BaseModel, Field


TRANSCRIPT_STORE_DIR = Path(__file__).resolve().parent / "transcript_store"

_lock = threading.Lock()


class TranscriptChunkRequest(BaseModel):
    session_id: str = Field(alias="sessionId")
    text: str
    start_time: str | None = Field(default=None, alias="startTime")
    end_time: str | None = Field(default=None, alias="endTime")
    chunk_index: int | None = Field(default=None, alias="chunkIndex")
    metadata: dict[str, Any] = Field(default_factory=dict)

    model_config = {
        "populate_by_name": True,
    }


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_session_id(session_id: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "_", session_id).strip("._")
    if not safe:
        raise ValueError("session_id cannot be empty.")
    return safe


def _session_dir(session_id: str) -> Path:
    path = TRANSCRIPT_STORE_DIR / _safe_session_id(session_id)
    path.mkdir(parents=True, exist_ok=True)
    return path


def _transcript_path(session_id: str) -> Path:
    return _session_dir(session_id) / "transcript.txt"


def _chunks_jsonl_path(session_id: str) -> Path:
    return _session_dir(session_id) / "chunks.jsonl"


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []

    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def _append_jsonl(path: Path, payload: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as file:
        file.write(json.dumps(payload, ensure_ascii=False) + "\n")


def _append_transcript_text(path: Path, chunk: dict[str, Any]) -> None:
    with path.open("a", encoding="utf-8") as file:
        if chunk["start_time"] or chunk["end_time"]:
            start_time = chunk["start_time"] or "unknown"
            end_time = chunk["end_time"] or "unknown"
            file.write(f"[{start_time} - {end_time}]\n")

        file.write(chunk["text"])
        file.write("\n\n")


def save_transcript_chunk(request: TranscriptChunkRequest) -> dict[str, Any]:
    text = request.text.strip()
    if not text:
        raise ValueError("Transcript chunk text cannot be empty.")

    with _lock:
        chunks_path = _chunks_jsonl_path(request.session_id)
        transcript_path = _transcript_path(request.session_id)
        chunk_number = len(_read_jsonl(chunks_path)) + 1

        chunk = {
            "chunk_number": chunk_number,
            "chunk_index": request.chunk_index,
            "start_time": request.start_time,
            "end_time": request.end_time,
            "text": text,
            "metadata": request.metadata,
            "received_at": _utc_now(),
        }

        _append_jsonl(chunks_path, chunk)
        _append_transcript_text(transcript_path, chunk)

    return {
        "session_id": request.session_id,
        "saved": True,
        "chunk_number": chunk_number,
        "chunk": chunk,
        "transcript_path": str(transcript_path),
    }


def get_transcript_session(session_id: str) -> dict[str, Any]:
    transcript_path = _transcript_path(session_id)

    return {
        "session_id": session_id,
        "transcript_path": str(transcript_path),
        "transcript_text": (
            transcript_path.read_text(encoding="utf-8")
            if transcript_path.exists()
            else ""
        ),
        "chunks": _read_jsonl(_chunks_jsonl_path(session_id)),
    }
