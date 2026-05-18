from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import json
import os

from openai import OpenAI


client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])

MODEL = "gpt-5-nano-2025-08-07"


TRANSCRIPT_AGENT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "page_number": {
            "type": "integer",
            "description": "The current professor page number supplied by the caller."
        },
        "has_new_points": {
            "type": "boolean",
            "description": "Whether the transcript contains important points not already covered in the current page notes."
        },
        "new_points": {
            "type": "array",
            "description": "Important points mentioned by the professor but missing from the existing Markdown notes.",
            "items": {
                "type": "object",
                "properties": {
                    "point": {
                        "type": "string",
                        "description": "A concise new point that should be added to the notes."
                    },
                    "suggested_markdown": {
                        "type": "string",
                        "description": "A concise Markdown bullet that can be appended to the page note."
                    }
                },
                "required": ["point", "suggested_markdown"],
                "additionalProperties": False
            }
        },
        "has_questions": {
            "type": "boolean",
            "description": "Whether the professor asked one or more questions in the transcript."
        },
        "questions": {
            "type": "array",
            "description": "Questions asked by the professor, if any.",
            "items": {
                "type": "object",
                "properties": {
                    "question": {
                        "type": "string",
                        "description": "The professor's question, rewritten clearly if the transcript is noisy."
                    },
                    "question_type": {
                        "type": "string",
                        "enum": ["rhetorical", "student_response_expected", "concept_check", "discussion", "unknown"],
                        "description": "The likely purpose of the question."
                    },
                },
                "required": ["question", "question_type"],
                "additionalProperties": False
            }
        }
    },
    "required": ["page_number", "has_new_points", "new_points", "has_questions", "questions"],
    "additionalProperties": False
}


@dataclass
class TranscriptAgentInput:
    """
    Input for one 30-second transcript update.

    current_page_note_md:
        The Markdown note of the professor's current page.

    professor_page_number:
        The page number where the professor currently is.

    transcript:
        The latest transcript segment, for example the last 30 seconds.
    """

    current_page_note_md: str
    professor_page_number: int
    transcript: str


def read_markdown_file(md_path: str | Path) -> str:
    """Read one Markdown note file."""
    return Path(md_path).read_text(encoding="utf-8")


def build_transcript_agent_prompt(agent_input: TranscriptAgentInput) -> str:
    return f"""
You are a lecture note update agent.

Goal:
Given the current page's existing Markdown note and the latest transcript segment, identify:
1. Important points the professor mentioned that are NOT already in the note.
2. Questions asked by the professor, if any.

Input:
- Current professor page number: {agent_input.professor_page_number}
- Existing Markdown note for this page
- Latest transcript segment

Decision rules:
- Compare the transcript against the existing note.
- Only output points that are both important and missing from the note.
- Do not repeat content already covered by the note.
- Do not add trivial filler, greetings, transitions, or speech disfluencies.
- If the transcript is too vague, noisy, or unrelated to the current page, return no new points.
- If the professor asks a question, extract it even if no new note point is needed.
- If a sentence is only phrased like a question but is not actually asking students anything, classify it as rhetorical.
- Keep all extracted content concise.
- Do not invent information not supported by the transcript.

Existing Markdown note:
---
{agent_input.current_page_note_md}
---

Latest transcript:
---
{agent_input.transcript}
---
""".strip()


def analyze_transcript_update(
    current_page_note_md: str,
    professor_page_number: int,
    transcript: str,
    model: str = MODEL,
) -> dict[str, Any]:
    """
    Analyze one transcript segment and return structured JSON-like dict.

    This function is intended to be called every 30 seconds by your outer loop.
    It does not handle scheduling or streaming by itself.

    Return format:
    {
      "page_number": 3,
      "has_new_points": true,
      "new_points": [
        {
          "point": "...",
          "evidence_from_transcript": "...",
          "suggested_markdown": "- ..."
        }
      ],
      "has_questions": true,
      "questions": [
        {
          "question": "...",
          "question_type": "concept_check",
          "evidence_from_transcript": "..."
        }
      ]
    }
    """
    agent_input = TranscriptAgentInput(
        current_page_note_md=current_page_note_md,
        professor_page_number=professor_page_number,
        transcript=transcript,
    )

    prompt = build_transcript_agent_prompt(agent_input)

    response = client.responses.create(
        model=model,
        input=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": prompt,
                    }
                ],
            }
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": "lecture_transcript_update",
                "strict": True,
                "schema": TRANSCRIPT_AGENT_SCHEMA,
            }
        },
    )

    try:
        result = json.loads(response.output_text)
    except json.JSONDecodeError as e:
        raise ValueError(
            f"Model did not return valid JSON. Raw output:\n{response.output_text}"
        ) from e

    return result


def analyze_transcript_update_from_file(
    md_path: str | Path,
    professor_page_number: int,
    transcript: str,
    model: str = MODEL,
) -> dict[str, Any]:
    """
    Convenience wrapper.

    Use this when you already have page_003.md etc. on disk.
    """
    current_page_note_md = read_markdown_file(md_path)

    return analyze_transcript_update(
        current_page_note_md=current_page_note_md,
        professor_page_number=professor_page_number,
        transcript=transcript,
        model=model,
    )


def append_update_to_note(
    md_path: str | Path,
    analysis_result: dict[str, Any],
    section_title: str = "Professor Additions",
) -> None:
    """
    Optional helper: append extracted new points and questions back to the page note.

    This is not required for the agent output itself, but is useful if you want
    the note file to be updated immediately after each 30-second analysis.
    """
    md_path = Path(md_path)
    original = md_path.read_text(encoding="utf-8")

    additions: list[str] = []

    if analysis_result.get("new_points"):
        additions.append(f"\n\n## {section_title}\n")
        for item in analysis_result["new_points"]:
            additions.append(item["suggested_markdown"])

    if analysis_result.get("questions"):
        additions.append("\n\n## Professor Questions\n")
        for item in analysis_result["questions"]:
            additions.append(f"- **{item['question_type']}**: {item['question']}")

    if additions:
        md_path.write_text(original.rstrip() + "\n" + "\n".join(additions).rstrip() + "\n", encoding="utf-8")

'''
if __name__ == "__main__":
    # Example usage.
    # Replace these values with your real current page and 30-second transcript.
    result = analyze_transcript_update_from_file(
        md_path="output_notes/notes/page_003.md",
        professor_page_number=3,
        transcript="So on this slide, remember that performance is not determined by just one factor. Instruction count is mostly affected by the ISA and compiler, but CPI and clock cycle time depend heavily on the processor implementation. One important point not shown explicitly here is that improving one factor may hurt another. For example, a pipelined processor can improve throughput, but it may introduce hazards that require extra control logic. Now, quick question: if a single-cycle processor finishes every instruction in one clock cycle, why might it still be slower than a pipelined processor overall?",
    )

    print(json.dumps(result, ensure_ascii=False, indent=2))
    '''
