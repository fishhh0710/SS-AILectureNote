from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
import json
import os
import re

from pydantic import BaseModel
from agents import Agent, RunContextWrapper, Runner, SQLiteSession, function_tool
from agents.memory import OpenAIResponsesCompactionSession

MODEL = os.getenv("LECTURE_TRANSCRIPT_AGENT_MODEL", "gpt-5-nano")


class NewPoint(BaseModel):
    suggested_markdown: str


class ProfessorQuestion(BaseModel):
    question: str


class TranscriptAgentOutput(BaseModel):
    page_number: int | None = None
    has_new_points: bool
    new_points: list[NewPoint]
    has_questions: bool
    questions: list[ProfessorQuestion]
    should_update_note: bool


@dataclass
class LectureContext:
    full_transcript_path: Path
    merged_markdown_path: Path
    cache: dict[str, str] = field(default_factory=dict)

    def read(self, key: str, path: Path) -> str:
        if key not in self.cache:
            self.cache[key] = path.read_text(encoding="utf-8")
        return self.cache[key]

    def transcript(self) -> str:
        return self.read("transcript", self.full_transcript_path)

    def markdown(self) -> str:
        return self.read("markdown", self.merged_markdown_path)


PAGE_RE = re.compile(r"(?im)^#{1,6}\s*(?:page\s*|p\.\s*|第\s*)?0*(\d+)\s*(?:頁)?\b.*$")
WORD_RE = re.compile(r"[A-Za-z0-9_\-]+|[\u4e00-\u9fff]")


def _limit(text: str, n: int = 4000) -> str:
    return text if len(text) <= n else text[: n - 20].rstrip() + "\n...[truncated]"


def _search(text: str, query: str, n: int = 4000) -> str:
    terms = {w.lower() for w in WORD_RE.findall(query)}
    if not terms:
        return _limit(text[-n:], n)

    chunks = re.split(r"\n\s*\n", text)
    ranked = []
    for i, chunk in enumerate(chunks):
        score = sum(chunk.lower().count(t) for t in terms)
        if score:
            ranked.append((score, -i, chunk.strip()))

    if not ranked:
        return _limit(text[-n:], n)

    ranked.sort(reverse=True)
    out = "\n\n".join(chunk for _, _, chunk in ranked[:6])
    return _limit(out, n)


def _page_spans(markdown: str) -> list[tuple[int, int, int]]:
    heads = list(PAGE_RE.finditer(markdown))
    return [
        (int(h.group(1)), h.start(), heads[i + 1].start() if i + 1 < len(heads) else len(markdown))
        for i, h in enumerate(heads)
    ]


def _page_text(markdown: str, page: int, n: int = 4000) -> str | None:
    for p, start, end in _page_spans(markdown):
        if p == page:
            return _limit(markdown[start:end].strip(), n)
    return None


@function_tool
async def get_transcript_context(ctx: RunContextWrapper[LectureContext], query: str) -> str:
    """Search the full lecture transcript. Use only when the latest transcript is ambiguous."""
    return _search(ctx.context.transcript(), query)


@function_tool
async def get_markdown_context(
    ctx: RunContextWrapper[LectureContext],
    query: str = "",
    page_number: int | None = None,
) -> str:
    """Read one page or search the merged Markdown notes."""
    markdown = ctx.context.markdown()
    if page_number is not None:
        found = _page_text(markdown, page_number)
        if found is not None:
            return found
    return _search(markdown, query)


agent = Agent[LectureContext](
    name="Lecture Transcript Agent",
    model=MODEL,
    tools=[get_transcript_context, get_markdown_context],
    output_type=TranscriptAgentOutput,
    instructions="""
You are a lecture transcript agent.

Input contains only the latest transcript segment.
Full transcript and merged Markdown are available through tools.

Task:
1. Infer the professor's current page.
2. Detect professor questions.
3. Detect important new points that are missing from the relevant Markdown page.
4. Return only the structured output.

Rules:
- Do not call tools by default; first use recent transcript and session memory.
- Use get_markdown_context to verify page or check whether a point already exists.
- Use get_transcript_context only when the recent transcript is too ambiguous.
- Avoid repeated tool calls for the same page/topic when memory is enough.
- New points must be important, supported by the latest transcript, and absent from the notes.
- Ignore filler, greetings, transitions, and repeated content.
- suggested_markdown must be one concise Markdown bullet.
- Extract questions as plain strings only.
- should_update_note is true if there are new points or questions to write into the local Markdown file.
""".strip(),
)


def _coerce_output(value: Any) -> TranscriptAgentOutput:
    if isinstance(value, TranscriptAgentOutput):
        output = value
    else:
        output = TranscriptAgentOutput.model_validate(value)

    output.has_new_points = bool(output.new_points)
    output.has_questions = bool(output.questions)
    output.should_update_note = bool(output.should_update_note)
    return output


def _append_to_markdown(path: Path, result: TranscriptAgentOutput) -> None:
    if not result.should_update_note:
        return

    md = path.read_text(encoding="utf-8")
    parts: list[str] = []

    if result.new_points:
        parts.append("\n\n## Professor Additions")
        parts.extend(p.suggested_markdown for p in result.new_points)

    if result.questions:
        parts.append("\n\n## Professor Questions")
        parts.extend(f"- {q.question}" for q in result.questions)

    block = "\n".join(parts).rstrip() + "\n"
    if block.strip() in md:
        return

    if result.page_number is not None:
        for page, _, end in _page_spans(md):
            if page == result.page_number:
                path.write_text(md[:end].rstrip() + "\n" + block + md[end:], encoding="utf-8")
                return

    path.write_text(md.rstrip() + "\n" + block, encoding="utf-8")


async def analyze_lecture_transcript(
    recent_transcript: str,
    full_transcript_path: str | Path,
    merged_markdown_path: str | Path,
    session_id: str = "lecture_transcript_agent",
    session_db_path: str | Path = "lecture_transcript_agent_sessions.db",
) -> dict[str, Any]:
    """
    External-call function.

    Model input: recent_transcript only.
    Tool context: full_transcript_path and merged_markdown_path.
    Side effects: update merged Markdown, write JSON for Flutter.
    """
    recent_transcript = recent_transcript.strip()
    if not recent_transcript:
        raise ValueError("recent_transcript cannot be empty")

    context = LectureContext(Path(full_transcript_path), Path(merged_markdown_path))
    session = OpenAIResponsesCompactionSession(
        session_id=session_id,
        underlying_session=SQLiteSession(session_id, str(session_db_path)),
    )

    run_result = await Runner.run(
        agent,
        f"Latest transcript segment:\n---\n{recent_transcript}\n---",
        context=context,
        session=session,
    )

    output = _coerce_output(run_result.final_output)
    _append_to_markdown(Path(merged_markdown_path), output)

    data = output.model_dump(mode="json")
    return data
