from __future__ import annotations

import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Literal

from agents import Agent, Runner
from firebase_admin import firestore, messaging
from pydantic import BaseModel, Field

from memory_service import MemoryService, MemoryWrite


class AttentionAgentOutput(BaseModel):
    status: Literal["following", "confused", "behind", "distracted", "unclear"]
    page_relevance: Literal[
        "same_topic", "related_previous_content", "unrelated", "unknown"
    ]
    confidence: float = Field(ge=0, le=1)
    reasoning_summary: str
    missed_content: list[str] = Field(default_factory=list)
    confused_summary: str | None = None


ATTENTION_AGENT_INSTRUCTIONS = """
You are an Attention and Lecture Progress Evaluation Agent.

Classify the student's current state using all supplied evidence:
- following: viewing the same or closely related material and keeping pace.
- confused: focused on relevant material but apparently stuck on a concept.
- behind: reviewing older related material while the teacher has moved ahead.
- distracted: viewing unrelated material or leaving the lecture with strong evidence of disengagement.
- unclear: evidence is insufficient or contradictory.

Do not classify distraction from one signal alone. Staying on a page can mean careful reading.
App background state is evidence, not proof. Prefer confused or behind when the student's page
is relevant to the lecture. Use distracted only when the combined page, timing, history, and
lecture evidence supports it.

Always return useful future-memory fields even though the current UI does not display them:
- missed_content: concise lecture points the student likely missed; otherwise an empty list.
- confused_summary: concise description of a likely misunderstanding; otherwise null.

Do not recommend actions. Do not write notifications. Return only the structured output.
""".strip()


attention_agent = Agent(
    name="Student Attention Agent",
    model=os.getenv("OPENAI_ATTENTION_MODEL")
    or os.getenv("OPENAI_MODEL")
    or "gpt-4o-mini",
    instructions=ATTENTION_AGENT_INSTRUCTIONS,
    output_type=AttentionAgentOutput,
)


def attention_memory_writes(
    output: AttentionAgentOutput,
    *,
    course_id: str,
    lecture_id: str,
) -> list[MemoryWrite]:
    writes: list[MemoryWrite] = []
    missed = [item.strip() for item in output.missed_content if item.strip()]
    if missed:
        writes.append(
            MemoryWrite(
                domain="learning",
                kind="missed_content",
                content="\n".join(f"- {item}" for item in missed),
                scope="lecture",
                course_id=course_id,
                lecture_id=lecture_id,
                confidence=output.confidence,
                importance=0.75,
                metadata={"attentionStatus": output.status},
            )
        )
    confused = (output.confused_summary or "").strip()
    if confused:
        writes.append(
            MemoryWrite(
                domain="learning",
                kind="confusion",
                content=confused,
                scope="lecture",
                course_id=course_id,
                lecture_id=lecture_id,
                confidence=output.confidence,
                importance=0.85,
                metadata={"attentionStatus": output.status},
            )
        )
    return writes


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc)
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return None


def _positive_int(value: Any) -> int | None:
    return value if isinstance(value, int) and value > 0 else None


def attention_gate(
    *,
    student_state: dict[str, Any],
    teacher_page: int,
    session_state: dict[str, Any],
    now: datetime,
) -> dict[str, Any]:
    current_page = _positive_int(student_state.get("currentPage"))
    duration = student_state.get("currentPageDurationSeconds")
    duration_seconds = duration if isinstance(duration, int) and duration >= 0 else 0
    lifecycle = student_state.get("appLifecycle")
    lifecycle = lifecycle if lifecycle in {"foreground", "background"} else "foreground"

    last_checked_at = _parse_datetime(session_state.get("lastAttentionCheckedAt"))
    session_started_at = _parse_datetime(student_state.get("sessionStartedAt"))
    reference = last_checked_at or session_started_at
    interval_ready = reference is not None and (now - reference).total_seconds() >= 30

    last_checked_teacher_page = _positive_int(
        session_state.get("teacherPageAtLastCheck")
    )
    page_mismatch = current_page is not None and current_page != teacher_page
    student_stagnant = duration_seconds >= 30
    teacher_moved = (
        last_checked_teacher_page is not None
        and abs(teacher_page - last_checked_teacher_page) >= 2
    )
    app_background = lifecycle == "background"
    signals = {
        "page_mismatch": page_mismatch,
        "student_stagnant": student_stagnant,
        "teacher_moved": teacher_moved,
        "app_background": app_background,
    }
    return {
        "should_run": interval_ready and any(signals.values()),
        "interval_ready": interval_ready,
        "signals": signals,
        "current_page": current_page,
        "duration_seconds": duration_seconds,
        "app_lifecycle": lifecycle,
    }


def _page_content(page_summaries: dict[int, str], page: int | None) -> str:
    if page is None:
        return ""
    return page_summaries.get(page, "")[:6000]


def _list_value(value: Any, limit: int) -> list[Any]:
    return value[-limit:] if isinstance(value, list) else []


def _notification_ready(session_state: dict[str, Any], now: datetime) -> bool:
    last_notification_at = _parse_datetime(session_state.get("lastNotificationAt"))
    return last_notification_at is None or (now - last_notification_at).total_seconds() >= 120


def _send_distraction_notification(token: str, teacher_page: int) -> str:
    message = messaging.Message(
        token=token,
        notification=messaging.Notification(
            title="課堂仍在進行",
            body=f"你似乎暫時離開了課程，老師目前正在講第 {teacher_page} 頁。",
        ),
        data={
            "type": "attention_distraction",
            "teacherPage": str(teacher_page),
        },
        android=messaging.AndroidConfig(priority="high"),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(aps=messaging.Aps(sound="default")),
        ),
    )
    return messaging.send(message)


def evaluate_attention(
    *,
    uid: str,
    session_id: str,
    student_state: dict[str, Any],
    teacher_page: int,
    page_summaries: dict[int, str],
    transcript_segments: list[str],
    notification_token: str,
    course_id: str,
    lecture_id: str,
    now: datetime | None = None,
) -> dict[str, Any]:
    current_time = now or datetime.now(timezone.utc)
    database = firestore.client()
    session_ref = (
        database.collection("users")
        .document(uid)
        .collection("lecture_sessions")
        .document(session_id)
    )
    snapshot = session_ref.get()
    session_state = snapshot.to_dict() if snapshot.exists else {}
    gate = attention_gate(
        student_state=student_state,
        teacher_page=teacher_page,
        session_state=session_state,
        now=current_time,
    )

    session_update: dict[str, Any] = {
        "lastTeacherPage": teacher_page,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    if notification_token:
        token_id = hashlib.sha256(notification_token.encode()).hexdigest()[:24]
        database.collection("users").document(uid).collection("devices").document(
            token_id
        ).set(
            {
                "fcmToken": notification_token,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    if not gate["should_run"]:
        session_ref.set(session_update, merge=True)
        return {"checked": False, "gate": gate}

    current_page = gate["current_page"]
    prompt = json.dumps(
        {
            "student_current_page": current_page,
            "student_current_page_content": _page_content(
                page_summaries, current_page
            ),
            "teacher_current_page": teacher_page,
            "teacher_current_page_content": _page_content(
                page_summaries, teacher_page
            ),
            "recent_transcript": transcript_segments[-10:],
            "student_page_history": _list_value(
                student_state.get("pageHistory"), 20
            ),
            "current_page_duration_seconds": gate["duration_seconds"],
            "app_lifecycle": gate["app_lifecycle"],
            "backgrounded_at": student_state.get("backgroundedAt"),
            "previous_status": session_state.get("lastAttentionStatus"),
            "trigger_signals": gate["signals"],
        },
        ensure_ascii=False,
    )
    run_result = Runner.run_sync(attention_agent, prompt, max_turns=3)
    output = run_result.final_output
    if not isinstance(output, AttentionAgentOutput):
        output = AttentionAgentOutput.model_validate(output)

    notification_sent = False
    notification_message_id: str | None = None
    if (
        output.status == "distracted"
        and gate["app_lifecycle"] == "background"
        and notification_token
        and _notification_ready(session_state, current_time)
    ):
        try:
            notification_message_id = _send_distraction_notification(
                notification_token, teacher_page
            )
            notification_sent = True
            session_update["lastNotificationAt"] = current_time
        except Exception:
            logging.exception("Failed to send distraction notification")

    result = {
        "checked": True,
        **output.model_dump(mode="json"),
        "gate": gate,
        "notification_sent": notification_sent,
        "notification_message_id": notification_message_id,
    }
    memory_writes: list[dict[str, Any]] = []
    memory_service = MemoryService(database=database)
    for memory in attention_memory_writes(
        output,
        course_id=course_id,
        lecture_id=lecture_id,
    ):
        try:
            stored = memory_service.remember(
                uid=uid,
                memory=memory,
                source="attention_agent",
                source_ref=session_id,
            )
            memory_writes.append(
                {
                    "memory_id": stored["memory_id"],
                    "kind": memory.kind,
                    "status": stored["status"],
                }
            )
        except Exception as error:
            logging.exception("Failed to persist attention memory")
            memory_writes.append({"kind": memory.kind, "error": str(error)})
    result["memory_writes"] = memory_writes
    session_update.update(
        {
            "lastAttentionCheckedAt": current_time,
            "teacherPageAtLastCheck": teacher_page,
            "lastAttentionStatus": output.status,
            "lastAttentionResult": result,
        }
    )
    session_ref.set(session_update, merge=True)
    database.collection("users").document(uid).collection(
        "attention_events"
    ).document().set(
        {
            "sessionId": session_id,
            "teacherPage": teacher_page,
            "studentPage": current_page,
            "result": result,
            "createdAt": firestore.SERVER_TIMESTAMP,
        }
    )
    return result
