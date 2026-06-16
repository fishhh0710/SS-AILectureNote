from __future__ import annotations

import json
import logging
import os
from typing import Any, Literal

from agents import Agent, Runner
from firebase_functions import https_fn
from pydantic import BaseModel, Field

from attention_agent import evaluate_attention
from function_common import (
    authenticated_user_id,
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


REALTIME_AGENT_INSTRUCTIONS = """
You are the teacher-progress agent for a live lecture-note application.

You receive all available page summaries, up to ten recent transcript segments, and the teacher
page you inferred last time. You never receive the page currently viewed by the student. Infer the
teacher's page from the transcript and summaries yourself.

For page inference, use only canonical slide content:
- slide title;
- original slide text;
- visual/layout summary;
- formulas, diagrams, tables, labels.

Do not use previously generated lecture notes, Professor Additions, Professor Questions,
new_points, questions, or other lecture-derived annotations as evidence for page inference. Those
annotations may be useful only for avoiding duplicate note-taking, not for identifying the current
page.

The last teacher page is only a weak continuity hint. Do not copy it when the transcript points
elsewhere. If the page cannot be identified reliably, return page_number null and update_note_at
"none".

Transcript order matters. transcript_segments is chronological, and later items are more recent and
more important. latest_segment is the newest and should carry the most weight.

Page-number mentions are strong evidence only when the teacher is moving to, looking at, or
discussing that page now, such as "let's look at page 23." They are weak or negative evidence when
the teacher says to refer back to a page, compare with another page, remember a previous page, or
asks how this page differs from another page. In those cases, infer the current page from the
current explanation and slide content instead of jumping to the referenced page number.

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


realtime_agent = Agent(
    name="Realtime Lecture Agent",
    model=os.getenv("OPENAI_REALTIME_AGENT_MODEL")
    or os.getenv("OPENAI_MODEL")
    or "gpt-4o-mini",
    instructions=REALTIME_AGENT_INSTRUCTIONS,
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


def _canonical_slide_summary(markdown: str) -> str:
    removed_headings = {
        "professor additions",
        "professor questions",
        "new context",
        "new points",
        "new_points",
    }
    lines = markdown.splitlines()
    kept: list[str] = []
    skip_until_level: int | None = None

    for line in lines:
        stripped = line.strip()
        heading_level = len(stripped) - len(stripped.lstrip("#"))
        is_heading = (
            heading_level > 0
            and heading_level <= 6
            and len(stripped) > heading_level
            and stripped[heading_level] == " "
        )

        if is_heading:
            heading_text = stripped[heading_level:].strip().casefold()
            if any(label in heading_text for label in removed_headings):
                skip_until_level = heading_level
                continue
            if skip_until_level is not None and heading_level <= skip_until_level:
                skip_until_level = None

        if skip_until_level is None:
            kept.append(line)

    return "\n".join(kept).strip()


def _page_summaries_for_prompt(page_summaries: dict[int, str]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for page_number, markdown in sorted(page_summaries.items()):
        canonical = _canonical_slide_summary(markdown)
        if canonical:
            items.append(
                {
                    "page_number": page_number,
                    "canonical_slide_summary": canonical,
                }
            )
    return items


def build_realtime_prompt(
    *,
    page_summaries: dict[int, str],
    recent_segments: list[str],
    latest_segment: str,
    last_teacher_page: int | None,
) -> str:
    payload = {
        "last_teacher_page": last_teacher_page,
        "page_summaries": _page_summaries_for_prompt(page_summaries),
        "transcript_segments": [*recent_segments, latest_segment][-10:],
        "latest_segment": latest_segment,
    }
    return (
        "Analyze the latest transcript segment and infer the teacher's current page. "
        "All canonical slide summaries are provided directly; do not ask for tools. "
        "Remember that transcript_segments is chronological and latest_segment is newest.\n\n"
        f"{json.dumps(payload, ensure_ascii=False)}"
    )


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
        last_teacher_page = _parse_optional_page(payload.get("lastTeacherPage"))
        prompt = build_realtime_prompt(
            page_summaries=page_summaries,
            recent_segments=recent_segments,
            latest_segment=latest_segment,
            last_teacher_page=last_teacher_page,
        )
        run_result = Runner.run_sync(
            realtime_agent,
            prompt,
            max_turns=3,
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
