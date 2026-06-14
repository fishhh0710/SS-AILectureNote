from __future__ import annotations

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Any

from firebase_admin import firestore, storage
from firebase_functions import https_fn

from function_common import (
    json_response,
    openai_client,
    optional_string,
    request_payload,
    required_string,
    safe_storage_id,
)


PAGE_NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "pages": {
            "type": "array",
            "description": "One Markdown note for each PDF page.",
            "items": {
                "type": "object",
                "properties": {
                    "page_number": {
                        "type": "integer",
                        "description": "The 1-based page number in the PDF.",
                    },
                    "markdown": {
                        "type": "string",
                        "description": "Concise Markdown notes for this page.",
                    },
                },
                "required": ["page_number", "markdown"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["pages"],
    "additionalProperties": False,
}


def _pdf_notes_prompt() -> str:
    return """
You are an academic PDF note-taking assistant.

Task:
Read the entire PDF and generate concise Markdown notes for each page.

You must use:
- The page text
- Images, diagrams, charts, tables, formulas, arrows, and visual layout
- The spatial structure of each page

Output:
Return a JSON object with a "pages" array.
Each item must contain:
- page_number: the page number, starting from 1
- markdown: the Markdown note for that page

Markdown format for each page:

# Page <page_number>: <short inferred title>

## Main Idea
<Explain the main idea of this page in 2-4 concise sentences.>

## Key Terms
- **<term>**: <brief explanation based on this page>
- **<term>**: <brief explanation based on this page>

Rules:
- Generate one item for every page in the PDF.
- Do not skip pages.
- Focus on each page individually.
- Keep each page note concise.
- Explain only important technical terms, academic terms, formulas, methods, concepts, or abbreviations.
- Do not include obvious everyday words as key terms.
- If a page has no important technical terms, omit the "## Key Terms" section for that page.
- If a page is blank or contains almost no useful content, still create a short note saying that the page has limited content.
- Do not invent information that is not supported by the PDF.
- The markdown field should contain Markdown only.
- Do not wrap Markdown in markdown fences.
""".strip()


def _chat_prompt(notes: str, transcript: str, history: str, question: str) -> str:
    return f"""
You are an AI study assistant for a lecture-note app.

Answer the student's question using the lecture notes and transcript first.
If the provided context is insufficient, say what is missing and answer only at a high level.
Keep the answer concise, structured, and useful for studying.

AI notes:
{notes or "(none)"}

Lecture transcript:
{transcript or "(none)"}

Recent chat history:
{history or "(none)"}

Student question:
{question}
""".strip()


def _extract_output_text(response: Any) -> str:
    output_text = getattr(response, "output_text", None)
    if isinstance(output_text, str):
        return output_text

    parts: list[str] = []
    for item in getattr(response, "output", []) or []:
        for content in getattr(item, "content", []) or []:
            if getattr(content, "type", None) == "output_text":
                text = getattr(content, "text", None)
                if isinstance(text, str):
                    parts.append(text)
    return "".join(parts)


def _generate_page_notes(pdf_path: str) -> dict[str, Any]:
    client = openai_client()
    with open(pdf_path, "rb") as pdf_file:
        uploaded_file = client.files.create(file=pdf_file, purpose="user_data")

    try:
        response = client.responses.create(
            model=os.getenv("OPENAI_NOTE_MODEL")
            or os.getenv("OPENAI_MODEL")
            or "gpt-4o-mini",
            input=[
                {
                    "role": "user",
                    "content": [
                        {"type": "input_file", "file_id": uploaded_file.id},
                        {"type": "input_text", "text": _pdf_notes_prompt()},
                    ],
                }
            ],
            text={
                "format": {
                    "type": "json_schema",
                    "name": "pdf_page_notes",
                    "strict": True,
                    "schema": PAGE_NOTES_SCHEMA,
                }
            },
            max_output_tokens=20000,
        )
        result = json.loads(_extract_output_text(response))
        if not isinstance(result.get("pages"), list):
            raise ValueError("Model output is missing pages.")
        return result
    finally:
        try:
            client.files.delete(uploaded_file.id)
        except Exception:
            logging.exception("Failed to delete uploaded OpenAI file")


def _job_document(job_path: str, safe_id: str):
    segments = [segment for segment in job_path.split("/") if segment]
    database = firestore.client()
    if len(segments) % 2 == 0:
        return database.document(job_path)
    return database.collection("ai_note_jobs").document(safe_id)


def chat_handler(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return json_response({"message": "Only POST is supported."}, 405)
    try:
        payload = request_payload(req)
        question = required_string(payload, "question")
        response = openai_client().chat.completions.create(
            model=os.getenv("OPENAI_CHAT_MODEL")
            or os.getenv("OPENAI_MODEL")
            or "gpt-4o-mini",
            messages=[
                {
                    "role": "user",
                    "content": _chat_prompt(
                        optional_string(payload.get("notes")),
                        optional_string(payload.get("transcript")),
                        optional_string(payload.get("history")),
                        question,
                    ),
                }
            ],
            temperature=0.7,
        )
        answer = (response.choices[0].message.content or "").strip()
        if not answer:
            raise RuntimeError("OpenAI response did not include an answer.")
        return json_response({"answer": answer})
    except Exception as error:
        logging.exception("Chat function failed")
        return json_response({"message": str(error)}, 500)


def notes_handler(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return json_response({"message": "Only POST is supported."}, 405)

    temp_pdf_path: str | None = None
    job_ref = None
    try:
        payload = request_payload(req)
        storage_id = required_string(payload, "storageId")
        storage_bucket = optional_string(payload.get("storageBucket"))
        pdf_storage_path = required_string(payload, "pdfStoragePath")
        safe_id = safe_storage_id(storage_id)
        job_path = optional_string(payload.get("jobPath")) or f"ai_note_jobs/{safe_id}"
        bucket = storage.bucket(storage_bucket or None)
        job_ref = _job_document(job_path, safe_id)
        job_ref.set(
            {
                "status": "running",
                "storageBucket": bucket.name,
                "pdfStoragePath": pdf_storage_path,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as temp_file:
            temp_pdf_path = temp_file.name
        bucket.blob(pdf_storage_path).download_to_filename(temp_pdf_path)

        notes = _generate_page_notes(temp_pdf_path)
        notes_storage_path = f"ai_note_jobs/{safe_id}/notes/notes.json"
        notes_blob = bucket.blob(notes_storage_path)
        notes_blob.metadata = {"storageId": storage_id}
        notes_blob.upload_from_string(
            json.dumps(notes, ensure_ascii=False, indent=2),
            content_type="application/json",
        )

        job_ref.set(
            {
                "status": "completed",
                "notesStoragePath": notes_storage_path,
                "pageCount": len(notes["pages"]),
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        return json_response(
            {
                **notes,
                "status": "completed",
                "storageBucket": bucket.name,
                "jobPath": job_ref.path,
                "notesStoragePath": notes_storage_path,
            }
        )
    except Exception as error:
        logging.exception("PDF note generation failed")
        if job_ref is not None:
            try:
                job_ref.set(
                    {
                        "status": "failed",
                        "error": str(error),
                        "updatedAt": firestore.SERVER_TIMESTAMP,
                    },
                    merge=True,
                )
            except Exception:
                logging.exception("Failed to write failed job status")
        return json_response({"message": str(error)}, 500)
    finally:
        if temp_pdf_path:
            Path(temp_pdf_path).unlink(missing_ok=True)
