from __future__ import annotations

import hashlib
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Literal

from agents import Agent, RunContextWrapper, Runner, function_tool
from firebase_admin import firestore, messaging
from pydantic import BaseModel, Field

from memory_service import MemoryService, MemoryWrite


CHECK_SECONDS = 25
NOTIFICATION_COOLDOWN_SECONDS = 180
STAGNANT_SECONDS = 20


class AttentionAgentOutput(BaseModel):
    status: Literal["following", "behind", "distracted"]
    page_relevance: Literal[
        "same_topic", "related_previous_content", "unrelated", "unknown"
    ]
    reasoning_summary: str
    missed_content: list[str] = Field(default_factory=list)


@dataclass
class AttentionContext:
    uid: str
    session_id: str
    course_id: str
    lecture_id: str
    notification_token: str
    teacher_page: int
    page_summaries: dict[int, str]
    transcript_segments: list[str]
    student_state: dict[str, Any]
    now: datetime
    database: Any
    session_state: dict[str, Any]
    gate: dict[str, Any]
    gate_checked: bool = False
    evidence_loaded: bool = False
    memory_attempted: bool = False
    memory_writes: list[dict[str, Any]] = field(default_factory=list)
    notification_attempted: bool = False
    notification_sent: bool = False
    notification_message_id: str | None = None
    notification_reason: str | None = None
    saved_output: AttentionAgentOutput | None = None
    result_saved: bool = False
    event_saved: bool = False


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
                content="The student likely missed: " + "; ".join(missed),
                scope="lecture",
                course_id=course_id,
                lecture_id=lecture_id,
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

    last_checked_at = _parse_datetime(session_state.get("lastAttentionCheckedAt"))
    session_started_at = _parse_datetime(student_state.get("sessionStartedAt"))
    reference = last_checked_at or session_started_at
    interval_ready = (
        reference is None or (now - reference).total_seconds() >= CHECK_SECONDS
    )

    last_checked_teacher_page = _positive_int(
        session_state.get("teacherPageAtLastCheck")
    )
    page_mismatch = current_page is not None and current_page != teacher_page
    student_stagnant = duration_seconds >= STAGNANT_SECONDS
    teacher_moved = (
        last_checked_teacher_page is not None
        and abs(teacher_page - last_checked_teacher_page) >= 1
    )
    behind_signal = (
        current_page is not None
        and current_page < teacher_page
        and teacher_page - current_page >= 2
    )
    signals = {
        "page_mismatch": page_mismatch,
        "student_stagnant": student_stagnant,
        "teacher_moved": teacher_moved,
        "behind_signal": behind_signal,
    }
    return {
        "should_run": interval_ready and (current_page is not None or any(signals.values())),
        "interval_ready": interval_ready,
        "check_interval_seconds": CHECK_SECONDS,
        "signals": signals,
        "current_page": current_page,
        "duration_seconds": duration_seconds,
    }


def _page_content(page_summaries: dict[int, str], page: int | None) -> str:
    if page is None:
        return ""
    return page_summaries.get(page, "")[:6000]


def _list_value(value: Any, limit: int) -> list[Any]:
    return value[-limit:] if isinstance(value, list) else []


def _session_ref(context: AttentionContext) -> Any:
    return (
        context.database.collection("users")
        .document(context.uid)
        .collection("lecture_sessions")
        .document(context.session_id)
    )


def _attention_evidence(context: AttentionContext) -> dict[str, Any]:
    current_page = context.gate["current_page"]
    return {
        "student_current_page": current_page,
        "student_current_page_content": _page_content(
            context.page_summaries, current_page
        ),
        "teacher_current_page": context.teacher_page,
        "teacher_current_page_content": _page_content(
            context.page_summaries, context.teacher_page
        ),
        "recent_transcript": context.transcript_segments[-10:],
        "student_page_history": _list_value(
            context.student_state.get("pageHistory"), 20
        ),
        "current_page_duration_seconds": context.gate["duration_seconds"],
        "previous_status": context.session_state.get("lastAttentionStatus"),
        "trigger_signals": context.gate["signals"],
    }


def _notification_ready(session_state: dict[str, Any], now: datetime) -> bool:
    last_notification_at = _parse_datetime(session_state.get("lastNotificationAt"))
    return last_notification_at is None or (
        now - last_notification_at
    ).total_seconds() >= NOTIFICATION_COOLDOWN_SECONDS


def _notification_decision(
    context: AttentionContext, status: str
) -> tuple[bool, str]:
    if not context.evidence_loaded:
        return False, "attention_evidence_required"
    if status != "distracted":
        return False, "status_not_distracted"
    if not context.notification_token:
        return False, "missing_notification_token"
    if not _notification_ready(context.session_state, context.now):
        return False, "notification_cooldown"
    return True, "ready"


def _send_distraction_notification(token: str, teacher_page: int) -> str:
    message = messaging.Message(
        token=token,
        notification=messaging.Notification(
            title="課堂仍在進行",
            body=f"你目前看的內容可能和老師進度不同，老師目前正在講第 {teacher_page} 頁。",
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


def _persist_learning_memories(
    context: AttentionContext, output: AttentionAgentOutput
) -> list[dict[str, Any]]:
    if context.memory_attempted:
        return context.memory_writes
    context.memory_attempted = True
    service = MemoryService(database=context.database)
    for memory in attention_memory_writes(
        output,
        course_id=context.course_id,
        lecture_id=context.lecture_id,
    ):
        try:
            stored = service.remember(
                uid=context.uid,
                memory=memory,
                source_ref=context.session_id,
            )
            context.memory_writes.append(
                {
                    "memory_id": stored["memory_id"],
                    "status": stored["status"],
                }
            )
        except Exception as error:
            logging.exception("Failed to persist attention memory")
            context.memory_writes.append({"error": str(error)})
    return context.memory_writes


def _try_distraction_notification(
    context: AttentionContext, status: str
) -> dict[str, Any]:
    if context.notification_attempted:
        return {
            "sent": context.notification_sent,
            "message_id": context.notification_message_id,
            "reason": context.notification_reason or "already_attempted",
        }
    context.notification_attempted = True
    allowed, reason = _notification_decision(context, status)
    context.notification_reason = reason
    if not allowed:
        return {"sent": False, "reason": reason}
    try:
        context.notification_message_id = _send_distraction_notification(
            context.notification_token, context.teacher_page
        )
        context.notification_sent = True
        context.notification_reason = "sent"
        return {
            "sent": True,
            "message_id": context.notification_message_id,
        }
    except Exception as error:
        logging.exception("Failed to send distraction notification")
        context.notification_reason = "send_failed"
        return {"sent": False, "reason": "send_failed", "error": str(error)}


def _result_payload(
    context: AttentionContext, output: AttentionAgentOutput
) -> dict[str, Any]:
    return {
        "checked": True,
        **output.model_dump(mode="json"),
        "gate": context.gate,
        "notification_sent": context.notification_sent,
        "notification_message_id": context.notification_message_id,
        "notification_reason": context.notification_reason,
        "memory_writes": context.memory_writes,
    }


def _save_result(context: AttentionContext, output: AttentionAgentOutput) -> dict[str, Any]:
    result = _result_payload(context, output)
    update: dict[str, Any] = {
        "lastTeacherPage": context.teacher_page,
        "lastAttentionCheckedAt": context.now,
        "teacherPageAtLastCheck": context.teacher_page,
        "lastAttentionStatus": output.status,
        "lastAttentionResult": result,
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    if context.notification_sent:
        update["lastNotificationAt"] = context.now
        context.session_state["lastNotificationAt"] = context.now
    _session_ref(context).set(update, merge=True)
    context.saved_output = output
    context.result_saved = True
    return result


def _save_event(context: AttentionContext, result: dict[str, Any]) -> None:
    if context.event_saved:
        return
    context.database.collection("users").document(context.uid).collection(
        "attention_events"
    ).document().set(
        {
            "sessionId": context.session_id,
            "teacherPage": context.teacher_page,
            "studentPage": context.gate["current_page"],
            "result": result,
            "createdAt": firestore.SERVER_TIMESTAMP,
        }
    )
    context.event_saved = True


@function_tool
def evaluate_attention_gate(
    ctx: RunContextWrapper[AttentionContext],
) -> dict[str, Any]:
    """Read the deterministic timing and signal gate for this evaluation."""
    ctx.context.gate_checked = True
    return ctx.context.gate


@function_tool
def get_attention_evidence(
    ctx: RunContextWrapper[AttentionContext],
) -> dict[str, Any]:
    """Get student/teacher pages, slide content, history, timing, and transcript evidence."""
    if not ctx.context.gate_checked:
        return {"error": "evaluate_attention_gate_required_first"}
    ctx.context.evidence_loaded = True
    return _attention_evidence(ctx.context)


@function_tool
def remember_learning_state(
    ctx: RunContextWrapper[AttentionContext],
    status: Literal["following", "behind", "distracted"],
    missed_content: list[str],
) -> list[dict[str, Any]]:
    """Store missed lecture content in long-term learning memory."""
    if not ctx.context.evidence_loaded:
        return [{"error": "get_attention_evidence_required_first"}]
    output = AttentionAgentOutput(
        status=status,
        page_relevance="unknown",
        reasoning_summary="Stored through the attention agent memory tool.",
        missed_content=missed_content,
    )
    return _persist_learning_memories(ctx.context, output)


@function_tool
def send_distraction_notification(
    ctx: RunContextWrapper[AttentionContext],
    status: Literal["following", "behind", "distracted"],
) -> dict[str, Any]:
    """Send a distraction notification when server-side cooldown and token checks allow it."""
    return _try_distraction_notification(ctx.context, status)


@function_tool
def save_attention_result(
    ctx: RunContextWrapper[AttentionContext],
    status: Literal["following", "behind", "distracted"],
    page_relevance: Literal[
        "same_topic", "related_previous_content", "unrelated", "unknown"
    ],
    reasoning_summary: str,
    missed_content: list[str],
) -> dict[str, Any]:
    """Save the classified attention result into the current lecture session."""
    if not ctx.context.evidence_loaded:
        return {"saved": False, "reason": "get_attention_evidence_required_first"}
    output = AttentionAgentOutput(
        status=status,
        page_relevance=page_relevance,
        reasoning_summary=reasoning_summary,
        missed_content=missed_content,
    )
    return _save_result(ctx.context, output)


@function_tool
def save_attention_event(
    ctx: RunContextWrapper[AttentionContext],
) -> dict[str, Any]:
    """Append the saved attention result to the user's attention event history."""
    if ctx.context.saved_output is None:
        return {"saved": False, "reason": "save_attention_result_required_first"}
    _save_event(
        ctx.context,
        _result_payload(ctx.context, ctx.context.saved_output),
    )
    return {"saved": True}


ATTENTION_AGENT_INSTRUCTIONS = """
You are an Attention and Lecture Progress Evaluation Agent.

Your job is to classify the student's current lecture state using the available evidence.
There are only three valid status values:
- following: The student is viewing the same topic or closely related lecture content and appears to be keeping pace with the teacher.
- behind: The student is viewing older but still relevant lecture content while the teacher has moved ahead.
- distracted: The student is viewing content that is unrelated to what the teacher is currently explaining, or the student is **viewing non-core course pages such as Topics or Outlines**.

Treat the following as distracted when supported by the page content, teacher page, transcript, or page history:
- the student's current page is unrelated to the teacher's current page or recent transcript;
- **THIS IS IMPORTANT**: the student's current page is a **syllabus, outline, agenda, title page, cover page, table of contents, course information page, grading policy page**, or other non-core lecture page while the teacher is explaining actual lecture content;
- the student's page history suggests they are not following the lecture flow;
- the student remains on unrelated, unknown, or non-core content while the teacher continues the lecture.

Treat the following as behind rather than distracted:
- the student's page is older than the teacher's page but still directly related to the lecture topic;
- the student appears to be reviewing previous lecture content that is necessary for understanding the current teacher explanation.

Treat the following as following:
- the student's page is the same as the teacher's page;
- the student's page is not exactly the same but is semantically close to the teacher's current page or recent transcript;
- the student's page is nearby and relevant, with no clear evidence of unrelated or non-core content.


Special rules: 
- If the student's current page is a syllabus, outline, agenda, title page, cover page, table of contents, course information page, grading policy page, just treat it as the student being distracted.

Page relevance values:
- same_topic: The student's page is the same as, or semantically close to, the teacher's current content.
- related_previous_content: The student's page is older but still relevant to the current lecture.
- unrelated: The student's page is unrelated or is non-core course content such as syllabus, outline, title page, cover page, or course information.
- unknown: The evidence is too limited to determine page relevance.

Required tool workflow:
1. Call evaluate_attention_gate first.
2. Call get_attention_evidence before classifying.
3. Use all available evidence together: student page, teacher page, page content, transcript, page history, current page duration, previous status, and trigger signals.
4. If missed_content is non-empty, call remember_learning_state exactly once.
5. If and only if the final status is distracted, call send_distraction_notification. The tool will enforce token availability and notification cooldown.
6. Call save_attention_result with the exact classification that you will return.
7. Call save_attention_event after save_attention_result.
8. Return the same structured classification that was passed to save_attention_result.

Memory rules:
- missed_content should contain concise lecture points the student likely missed. Use an empty list if none can be inferred.
- Do not invent detailed missed content that is not supported by the page content or transcript.

Output rules:
- Do not recommend actions.
- Do not write a notification message yourself.
- Do not include extra prose outside the structured output.
- The final output must match the AttentionAgentOutput schema exactly.
""".strip()


attention_agent = Agent[AttentionContext](
    name="Student Attention Agent",
    model=os.getenv("OPENAI_ATTENTION_MODEL")
    or os.getenv("OPENAI_MODEL")
    or "gpt-4o-mini",
    instructions=ATTENTION_AGENT_INSTRUCTIONS,
    tools=[
        evaluate_attention_gate,
        get_attention_evidence,
        remember_learning_state,
        send_distraction_notification,
        save_attention_result,
        save_attention_event,
    ],
    output_type=AttentionAgentOutput,
)


def _register_notification_device(
    database: Any, uid: str, notification_token: str
) -> None:
    if not notification_token:
        return
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
    _register_notification_device(database, uid, notification_token)

    if not gate["should_run"]:
        session_ref.set(
            {
                "lastTeacherPage": teacher_page,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        return {"checked": False, "gate": gate}

    context = AttentionContext(
        uid=uid,
        session_id=session_id,
        course_id=course_id,
        lecture_id=lecture_id,
        notification_token=notification_token,
        teacher_page=teacher_page,
        page_summaries=page_summaries,
        transcript_segments=transcript_segments,
        student_state=student_state,
        now=current_time,
        database=database,
        session_state=session_state,
        gate=gate,
    )
    run_result = Runner.run_sync(
        attention_agent,
        "Evaluate the current student attention state using the required tool workflow.",
        context=context,
        max_turns=10,
    )
    output = run_result.final_output
    if not isinstance(output, AttentionAgentOutput):
        output = AttentionAgentOutput.model_validate(output)
    if context.saved_output is not None:
        output = context.saved_output
    if not context.evidence_loaded:
        output = AttentionAgentOutput(
            status="following",
            page_relevance="unknown",
            reasoning_summary="The agent did not inspect attention evidence, so the result defaults to following without notification.",
        )

    has_learning_memory = bool(output.missed_content)
    if has_learning_memory and not context.memory_attempted:
        _persist_learning_memories(context, output)
    if output.status == "distracted" and not context.notification_attempted:
        _try_distraction_notification(context, output.status)

    result = _save_result(context, output)
    if not context.event_saved:
        _save_event(context, result)
    return result
