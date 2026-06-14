from __future__ import annotations

import json
import logging
import os
import re
from typing import Any, Literal

from agents import Agent, RunContextWrapper, Runner, function_tool
from firebase_functions import https_fn
from pydantic import BaseModel, Field

from attention_agent import authenticated_user_id, evaluate_attention
from function_common import (
    json_response,
    request_payload,
    required_string,
    safe_storage_id,
)


class RealtimeTarget(BaseModel):
    text: str
    color: Literal["red", "green", "blue", "orange"] = "orange"
    description: str = Field(
        description="The exact slide element or diagram component to locate."
    )


class RealtimeAgentOutput(BaseModel):
    page_number: int | None = None
    new_points: list[str] = Field(default_factory=list)
    questions: list[str] = Field(default_factory=list)
    targets: list[RealtimeTarget] = Field(default_factory=list)
    update_note_at: Literal["summary", "slides", "none"] = "none"


class RealtimeAgentContext:
    def __init__(
        self,
        *,
        page_summaries: dict[int, str],
        recent_segments: list[str],
        latest_segment: str,
        last_teacher_page: int | None,
    ) -> None:
        self.page_summaries = page_summaries
        self.recent_segments = recent_segments
        self.latest_segment = latest_segment
        self.last_teacher_page = last_teacher_page
        self.inspection_complete = False


def _search_terms(query: str) -> set[str]:
    normalized = query.lower()
    latin_terms = re.findall(r"[a-z0-9][a-z0-9_-]+", normalized)
    cjk = "".join(re.findall(r"[\u4e00-\u9fff]", normalized))
    cjk_terms = [cjk[index : index + 2] for index in range(max(0, len(cjk) - 1))]
    return {term for term in [*latin_terms, *cjk_terms] if len(term) >= 2}


def _context_tool_enabled(
    ctx: RunContextWrapper[RealtimeAgentContext], agent: Any
) -> bool:
    return not ctx.context.inspection_complete


@function_tool(is_enabled=_context_tool_enabled)
def inspect_lecture_context(
    ctx: RunContextWrapper[RealtimeAgentContext], query: str
) -> str:
    """Search slide summaries and return candidate pages plus ten transcript segments."""
    ctx.context.inspection_complete = True
    terms = _search_terms(query)
    ranked: list[tuple[int, int, str]] = []
    for page_number, markdown in ctx.context.page_summaries.items():
        lowered = markdown.lower()
        score = sum(lowered.count(term) for term in terms)
        if ctx.context.last_teacher_page == page_number:
            score += 1
        if score > 0:
            ranked.append((score, page_number, markdown))
    ranked.sort(key=lambda item: (-item[0], item[1]))
    segments = [*ctx.context.recent_segments, ctx.context.latest_segment]
    return json.dumps(
        {
            "last_teacher_page": ctx.context.last_teacher_page,
            "candidate_pages": [
                {"page_number": page, "summary": markdown[:5000]}
                for _, page, markdown in ranked[:5]
            ],
            "transcript_segments": segments[-10:],
        },
        ensure_ascii=False,
    )


REALTIME_AGENT_INSTRUCTIONS = """
You are the teacher-progress agent for a live lecture-note application.

You receive only the latest transcript segment and the teacher page you inferred last time.
You never receive the page currently viewed by the student. Infer the teacher's page yourself.

Call inspect_lecture_context exactly once. It returns relevant slide summaries and up to ten
recent transcript segments. After it returns, make the final structured decision without calling
another tool. The last teacher page is only a weak continuity hint. Do not copy it when the
transcript points elsewhere. If the page cannot be identified reliably, return page_number null
and update_note_at "none".

Evaluate only genuinely new information from the latest segment. Older segments are context and
must not be written again. Ignore filler, transitions, repeated explanations, and uncertain text.

Choose exactly one action:
- summary: return concise Markdown bullets in new_points and/or plain question strings in
  questions. targets must be empty.
- slides: return one or more precise visual targets that a bounding-box service can locate.
  new_points and questions must be empty.
- none: all arrays must be empty.

Use summary when the teacher adds important verbal context or asks a useful course question.
Use slides when the teacher is explicitly pointing out, comparing, tracing, or highlighting a
specific visible slide element. Never request both summary and slides for the same segment.
""".strip()


realtime_agent = Agent[RealtimeAgentContext](
    name="Realtime Lecture Agent",
    model=os.getenv("OPENAI_REALTIME_AGENT_MODEL")
    or os.getenv("OPENAI_MODEL")
    or "gpt-4o-mini",
    instructions=REALTIME_AGENT_INSTRUCTIONS,
    tools=[inspect_lecture_context],
    output_type=RealtimeAgentOutput,
)


def _parse_page_summaries(value: Any) -> dict[int, str]:
    if not isinstance(value, list):
        return {}
    summaries: dict[int, str] = {}
    for item in value:
        if not isinstance(item, dict):
            continue
        page = item.get("page_number", item.get("pageNumber"))
        markdown = item.get("markdown")
        if isinstance(page, int) and page > 0 and isinstance(markdown, str):
            text = markdown.strip()
            if text:
                summaries[page] = text
    return summaries


def parse_recent_segments(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item.strip() for item in value if isinstance(item, str) and item.strip()][-9:]


def _parse_optional_page(value: Any) -> int | None:
    return value if isinstance(value, int) and value > 0 else None


def _clean_text_items(items: list[str]) -> list[str]:
    cleaned: list[str] = []
    seen: set[str] = set()
    for item in items:
        text = item.strip()
        if not text or text.lower() in {"null", "none", "n/a"}:
            continue
        key = text.casefold()
        if key not in seen:
            seen.add(key)
            cleaned.append(text)
    return cleaned


def normalize_realtime_output(output: RealtimeAgentOutput) -> dict[str, Any]:
    page_number = output.page_number if output.page_number and output.page_number > 0 else None
    new_points = _clean_text_items(output.new_points)
    questions = _clean_text_items(output.questions)
    targets = [
        {
            "text": target.text.strip(),
            "color": target.color,
            "what to create the bounding box for": target.description.strip(),
        }
        for target in output.targets
        if target.text.strip() and target.description.strip()
    ]

    action = output.update_note_at
    if page_number is None:
        action = "none"
    if action == "summary":
        targets = []
        if not new_points and not questions:
            action = "none"
    elif action == "slides":
        new_points = []
        questions = []
        if not targets:
            action = "none"
    else:
        action = "none"

    if action == "none":
        new_points = []
        questions = []
        targets = []

    return {
        "page_number": page_number,
        "new_points": new_points,
        "questions": questions,
        "targets": targets,
        "update_note_at": action,
    }


def realtime_agent_handler(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return json_response({"message": "Only POST is supported."}, 405)
    try:
        payload = request_payload(req)
        latest_segment = required_string(payload, "latestSegment")
        page_summaries = _parse_page_summaries(payload.get("pageSummaries"))
        recent_segments = parse_recent_segments(payload.get("recentSegments"))
        context = RealtimeAgentContext(
            page_summaries=page_summaries,
            recent_segments=recent_segments,
            latest_segment=latest_segment,
            last_teacher_page=_parse_optional_page(payload.get("lastTeacherPage")),
        )
        prompt = (
            "Analyze the latest transcript segment. Use tools before choosing a page.\n\n"
            f"Last inferred teacher page: {context.last_teacher_page or 'unknown'}\n"
            f"Latest transcript segment:\n---\n{latest_segment}\n---"
        )
        run_result = Runner.run_sync(
            realtime_agent,
            prompt,
            context=context,
            max_turns=5,
        )
        output = run_result.final_output
        if not isinstance(output, RealtimeAgentOutput):
            output = RealtimeAgentOutput.model_validate(output)
        response = normalize_realtime_output(output)
        student_state = payload.get("studentState")
        session_id = payload.get("sessionId")
        if (
            response["page_number"] is not None
            and isinstance(student_state, dict)
            and isinstance(session_id, str)
            and session_id.strip()
        ):
            try:
                response["attention"] = evaluate_attention(
                    uid=authenticated_user_id(req),
                    session_id=safe_storage_id(session_id),
                    student_state=student_state,
                    teacher_page=response["page_number"],
                    page_summaries=page_summaries,
                    transcript_segments=[*recent_segments, latest_segment],
                    notification_token=(
                        payload.get("notificationToken", "").strip()
                        if isinstance(payload.get("notificationToken"), str)
                        else ""
                    ),
                    course_id=(
                        payload.get("courseId", "").strip()
                        if isinstance(payload.get("courseId"), str)
                        else ""
                    )
                    or "unknown-course",
                    lecture_id=(
                        payload.get("lectureId", "").strip()
                        if isinstance(payload.get("lectureId"), str)
                        else ""
                    )
                    or session_id,
                )
            except Exception as error:
                logging.exception("Attention evaluation failed")
                response["attention"] = {
                    "checked": False,
                    "error": str(error),
                }
        return json_response(response)
    except Exception as error:
        logging.exception("Realtime agent function failed")
        return json_response({"message": str(error)}, 500)
