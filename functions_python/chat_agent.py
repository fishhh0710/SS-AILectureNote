from __future__ import annotations

import json
import logging
import os
from typing import Any, Literal

from agents import Agent, RunContextWrapper, Runner, function_tool
from firebase_functions import https_fn
from pydantic import BaseModel

from function_common import (
    authenticated_user_id,
    json_response,
    optional_string,
    request_payload,
    required_string,
)
from memory_service import MemoryService, MemoryWrite


class ChatAgentOutput(BaseModel):
    answer: str


class ChatAgentContext:
    def __init__(
        self,
        *,
        uid: str,
        course_id: str,
        lecture_id: str,
        memory_service: MemoryService,
    ) -> None:
        self.uid = uid
        self.course_id = course_id
        self.lecture_id = lecture_id
        self.memory_service = memory_service


def _serialize_memories(items: list[Any]) -> str:
    return json.dumps([item.to_dict() for item in items], ensure_ascii=False)


@function_tool
def search_memories(
    ctx: RunContextWrapper[ChatAgentContext],
    query: str,
    domain: Literal["learning", "preference", "all"] = "all",
) -> str:
    """Search durable user memories relevant to the current study question."""
    domains = None if domain == "all" else {domain}
    results = ctx.context.memory_service.search(
        uid=ctx.context.uid,
        query=query,
        domains=domains,
        course_id=ctx.context.course_id,
        lecture_id=ctx.context.lecture_id,
        limit=8,
    )
    return _serialize_memories(results)


@function_tool
def remember_preference(
    ctx: RunContextWrapper[ChatAgentContext],
    preference_key: str,
    content: str,
    scope: Literal["global", "course", "lecture"] = "global",
) -> str:
    """Store a durable preference only when the user explicitly states it."""
    memory = MemoryWrite(
        domain="preference",
        kind="user_preference",
        content=content,
        scope=scope,
        course_id=ctx.context.course_id if scope != "global" else None,
        lecture_id=ctx.context.lecture_id if scope == "lecture" else None,
        preference_key=preference_key,
        confidence=1,
        importance=0.8,
        explicit=True,
    )
    stored = ctx.context.memory_service.remember(
        uid=ctx.context.uid,
        memory=memory,
        source="chat_agent",
        source_ref=ctx.context.lecture_id,
    )
    return json.dumps(
        {"stored": True, "memory_id": stored["memory_id"]}, ensure_ascii=False
    )


@function_tool
def remember_learning_state(
    ctx: RunContextWrapper[ChatAgentContext],
    kind: Literal["confusion", "weak_topic", "mastery_progress"],
    content: str,
    confidence: float = 0.75,
) -> str:
    """Store an important learning state revealed by the conversation."""
    memory = MemoryWrite(
        domain="learning",
        kind=kind,
        content=content,
        scope="course",
        course_id=ctx.context.course_id,
        confidence=max(0, min(confidence, 1)),
        importance=0.75,
        metadata={"lectureId": ctx.context.lecture_id},
    )
    stored = ctx.context.memory_service.remember(
        uid=ctx.context.uid,
        memory=memory,
        source="chat_agent",
        source_ref=ctx.context.lecture_id,
    )
    return json.dumps(
        {"stored": True, "memory_id": stored["memory_id"]}, ensure_ascii=False
    )


@function_tool
def resolve_learning_state(
    ctx: RunContextWrapper[ChatAgentContext], memory_id: str, reason: str
) -> str:
    """Mark a learning memory resolved when the user demonstrates understanding."""
    ctx.context.memory_service.resolve(
        uid=ctx.context.uid, memory_id=memory_id, reason=reason
    )
    return json.dumps({"resolved": True, "memory_id": memory_id})


@function_tool
def forget_memory(
    ctx: RunContextWrapper[ChatAgentContext], memory_id: str, reason: str
) -> str:
    """Forget a memory only when the user explicitly asks to remove it."""
    ctx.context.memory_service.forget(
        uid=ctx.context.uid, memory_id=memory_id, reason=reason
    )
    return json.dumps({"forgotten": True, "memory_id": memory_id})


CHAT_AGENT_INSTRUCTIONS = """
You are the study assistant in a lecture-note application.

Answer from the provided lecture notes and transcript first. Clearly distinguish supplied course
content from general background knowledge. Match the user's language and requested level of
detail. Use durable memories to personalize explanations without treating uncertain memories as
facts about the course.

Memory policy:
- Call remember_preference only for an explicit, durable user preference, such as summary format,
  language, explanation style, examples, notification frequency, or desired level of detail.
- Call remember_learning_state only for an important, reusable learning state. Do not store every
  question, temporary task, greeting, answer, or sensitive personal information.
- Use kind confusion or weak_topic when the student still lacks understanding. Use mastery_progress
  when the conversation provides meaningful evidence that a prior weakness has improved.
- Call resolve_learning_state only when a retrieved memory is clearly resolved by new evidence.
- Call forget_memory only after an explicit user request to forget or remove a memory.
- Search memories when the prefetched set is insufficient. Never invent a memory ID.

After any tool calls, return a concise useful answer. Do not expose internal memory mechanics unless
the user asks about them.
""".strip()


chat_agent = Agent[ChatAgentContext](
    name="Memory-aware Study Assistant",
    model=os.getenv("OPENAI_CHAT_MODEL")
    or os.getenv("OPENAI_MODEL")
    or "gpt-4o-mini",
    instructions=CHAT_AGENT_INSTRUCTIONS,
    tools=[
        search_memories,
        remember_preference,
        remember_learning_state,
        resolve_learning_state,
        forget_memory,
    ],
    output_type=ChatAgentOutput,
)


def _limit(value: str, length: int) -> str:
    return value if len(value) <= length else value[-length:]


def build_chat_prompt(
    *,
    notes: str,
    transcript: str,
    history: str,
    question: str,
    memories: list[dict[str, Any]],
) -> str:
    return f"""
Prefetched durable memories:
{json.dumps(memories, ensure_ascii=False)}

AI lecture notes:
{_limit(notes, 24000) or "(none)"}

Lecture transcript:
{_limit(transcript, 16000) or "(none)"}

Recent chat history:
{_limit(history, 12000) or "(none)"}

Student question:
{question}
""".strip()


def chat_handler(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return json_response({"message": "Only POST is supported."}, 405)
    try:
        payload = request_payload(req)
        uid = authenticated_user_id(req)
        question = required_string(payload, "question")
        course_id = required_string(payload, "courseId")
        lecture_id = required_string(payload, "lectureId")
        memory_service = MemoryService()
        prefetched = memory_service.search(
            uid=uid,
            query=question,
            domains={"learning", "preference"},
            course_id=course_id,
            lecture_id=lecture_id,
            limit=8,
        )
        context = ChatAgentContext(
            uid=uid,
            course_id=course_id,
            lecture_id=lecture_id,
            memory_service=memory_service,
        )
        prompt = build_chat_prompt(
            notes=optional_string(payload.get("notes")),
            transcript=optional_string(payload.get("transcript")),
            history=optional_string(payload.get("history")),
            question=question,
            memories=[item.to_dict() for item in prefetched],
        )
        run_result = Runner.run_sync(chat_agent, prompt, context=context, max_turns=8)
        output = run_result.final_output
        if not isinstance(output, ChatAgentOutput):
            output = ChatAgentOutput.model_validate(output)
        answer = output.answer.strip()
        if not answer:
            raise RuntimeError("Chat Agent did not include an answer.")
        return json_response({"answer": answer})
    except PermissionError as error:
        return json_response({"message": str(error)}, 401)
    except Exception as error:
        logging.exception("Chat Agent function failed")
        return json_response({"message": str(error)}, 500)
