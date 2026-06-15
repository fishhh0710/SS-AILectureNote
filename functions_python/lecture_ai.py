from __future__ import annotations

import json
import logging
import os
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from firebase_admin import firestore, storage
from firebase_functions import https_fn
from pypdf import PdfReader, PdfWriter

from function_common import (
    authenticated_user_id,
    json_response,
    openai_client,
    optional_string,
    request_payload,
    required_string,
    safe_storage_id,
)
from memory_service import MemoryService


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


@dataclass(frozen=True)
class PdfBatch:
    index: int
    start_page: int
    end_page: int
    path: str

    @property
    def page_count(self) -> int:
        return self.end_page - self.start_page + 1


def _pdf_notes_prompt(
    memory_context: list[dict[str, Any]] | None = None,
    *,
    start_page: int | None = None,
    end_page: int | None = None,
) -> str:
    memory_section = json.dumps(memory_context or [], ensure_ascii=False)
    page_range = (
        f"This PDF batch represents original pages {start_page} through {end_page}. "
        "Return one note for each page in the same order and use the original page numbers."
        if start_page is not None and end_page is not None
        else "Return one note for every page in the PDF."
    )
    return f"""
You are an academic PDF note-taking assistant.

Task:
Read the entire PDF and generate concise Markdown notes for each page.
{page_range}

You must use:
- The page text
- Images, diagrams, charts, tables, formulas, arrows, and visual layout
- The spatial structure of each page

Output:
Return a JSON object with a "pages" array.
Each item must contain:
- page_number: the page number, starting from 1
- markdown: the Markdown note for that page

Default Markdown format for each page, used only when memory does not request a different
presentation structure:

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

User memory context:
{memory_section}

Memory rules:
- Active preference memories must change language, formatting, detail level, examples, and
  explanation style when requested. They may override the default Main Idea / Key Terms layout.
- Preferences never override the requirement to return one accurate Markdown note per PDF page.
- Learning memories may suggest concepts that deserve clearer explanation when those concepts are
  actually present on a PDF page.
- Memory never overrides the PDF and must never introduce unsupported facts.
- Ignore memories unrelated to the PDF page being summarized.
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


def _normalize_batch_pages(
    result: dict[str, Any], *, start_page: int, expected_page_count: int
) -> list[dict[str, Any]]:
    pages = result.get("pages")
    if not isinstance(pages, list) or len(pages) != expected_page_count:
        raise ValueError(
            f"Expected {expected_page_count} page notes, received "
            f"{len(pages) if isinstance(pages, list) else 0}."
        )

    normalized: list[dict[str, Any]] = []
    for offset, page in enumerate(pages):
        if not isinstance(page, dict):
            raise ValueError("Model output contains an invalid page note.")
        markdown = page.get("markdown")
        if not isinstance(markdown, str) or not markdown.strip():
            raise ValueError("Model output contains an empty page note.")
        normalized.append(
            {
                "page_number": start_page + offset,
                "markdown": markdown.strip(),
            }
        )
    return normalized


def _generate_page_notes(
    pdf_path: str,
    memory_context: list[dict[str, Any]] | None = None,
    *,
    start_page: int = 1,
    expected_page_count: int,
) -> list[dict[str, Any]]:
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
                        {
                            "type": "input_text",
                            "text": _pdf_notes_prompt(
                                memory_context,
                                start_page=start_page,
                                end_page=start_page + expected_page_count - 1,
                            ),
                        },
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
            max_output_tokens=max(2000, expected_page_count * 800),
        )
        result = json.loads(_extract_output_text(response))
        return _normalize_batch_pages(
            result,
            start_page=start_page,
            expected_page_count=expected_page_count,
        )
    finally:
        try:
            client.files.delete(uploaded_file.id)
        except Exception:
            logging.exception("Failed to delete uploaded OpenAI file")


def _split_pdf_batches(
    pdf_path: str, output_dir: str, *, batch_size: int = 5
) -> tuple[list[PdfBatch], int]:
    reader = PdfReader(pdf_path)
    total_pages = len(reader.pages)
    if total_pages == 0:
        raise ValueError("PDF does not contain any pages.")

    batches: list[PdfBatch] = []
    for index, start_index in enumerate(range(0, total_pages, batch_size)):
        writer = PdfWriter()
        end_index = min(start_index + batch_size, total_pages)
        for page_index in range(start_index, end_index):
            writer.add_page(reader.pages[page_index])
        batch_path = str(Path(output_dir) / f"batch_{index:04d}.pdf")
        with open(batch_path, "wb") as batch_file:
            writer.write(batch_file)
        batches.append(
            PdfBatch(
                index=index,
                start_page=start_index + 1,
                end_page=end_index,
                path=batch_path,
            )
        )
    return batches, total_pages


def _run_batches_concurrently(
    batches: list[PdfBatch],
    worker: Callable[[PdfBatch], list[dict[str, Any]]],
    *,
    max_workers: int = 3,
) -> list[dict[str, Any]]:
    pages: list[dict[str, Any]] = []
    errors: list[str] = []
    with ThreadPoolExecutor(max_workers=min(max_workers, len(batches))) as executor:
        futures = {executor.submit(worker, batch): batch for batch in batches}
        for future in as_completed(futures):
            batch = futures[future]
            try:
                pages.extend(future.result())
            except Exception as error:
                errors.append(
                    f"pages {batch.start_page}-{batch.end_page}: {error}"
                )
    if errors:
        raise RuntimeError("PDF batch generation failed: " + "; ".join(errors))
    pages.sort(key=lambda page: page["page_number"])
    return pages


def _summary_memories(
    *, uid: str, course_id: str, lecture_id: str
) -> list[dict[str, Any]]:
    service = MemoryService()
    preferences = service.list_active(
        uid=uid,
        domains={"preference"},
        course_id=course_id,
        lecture_id=lecture_id,
        limit=12,
    )
    learning = service.list_active(
        uid=uid,
        domains={"learning"},
        course_id=course_id,
        lecture_id=lecture_id,
        limit=12,
    )
    return [item.to_dict() for item in [*preferences, *learning]]


def _batch_document(job_ref: Any, batch: PdfBatch):
    return job_ref.collection("batches").document(f"{batch.index:04d}")


def _initialize_batch_documents(
    *, job_ref: Any, batches: list[PdfBatch], total_pages: int
) -> None:
    for batch in batches:
        _batch_document(job_ref, batch).set(
            {
                "batchIndex": batch.index,
                "startPage": batch.start_page,
                "endPage": batch.end_page,
                "totalPages": total_pages,
                "status": "pending",
                "attempt": 0,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            }
        )


def _generate_and_persist_batch(
    *,
    batch: PdfBatch,
    memory_context: list[dict[str, Any]],
    job_ref: Any,
    database: Any,
) -> list[dict[str, Any]]:
    batch_ref = _batch_document(job_ref, batch)
    last_error: Exception | None = None
    for attempt in range(1, 3):
        batch_ref.set(
            {
                "status": "running",
                "attempt": attempt,
                "error": firestore.DELETE_FIELD,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        try:
            pages = _generate_page_notes(
                batch.path,
                memory_context,
                start_page=batch.start_page,
                expected_page_count=batch.page_count,
            )
            write = database.batch()
            write.set(
                batch_ref,
                {
                    "status": "completed",
                    "pages": pages,
                    "attempt": attempt,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
            write.set(
                job_ref,
                {
                    "completedBatches": firestore.Increment(1),
                    "completedPages": firestore.Increment(batch.page_count),
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
            write.commit()
            return pages
        except Exception as error:
            last_error = error
            logging.exception(
                "PDF batch %s failed on attempt %s", batch.index, attempt
            )

    error_message = str(last_error or "Unknown batch error")
    write = database.batch()
    write.set(
        batch_ref,
        {
            "status": "failed",
            "error": error_message,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )
    write.set(
        job_ref,
        {
            "failedBatches": firestore.Increment(1),
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
        merge=True,
    )
    write.commit()
    raise RuntimeError(error_message)


def notes_handler(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return json_response({"message": "Only POST is supported."}, 405)

    job_ref = None
    try:
        payload = request_payload(req)
        uid = authenticated_user_id(req)
        storage_id = required_string(payload, "storageId")
        course_id = required_string(payload, "courseId")
        lecture_id = required_string(payload, "lectureId")
        storage_bucket = optional_string(payload.get("storageBucket"))
        pdf_storage_path = required_string(payload, "pdfStoragePath")
        safe_id = safe_storage_id(storage_id)
        job_id = safe_storage_id(optional_string(payload.get("jobId")) or safe_id)
        bucket = storage.bucket(storage_bucket or None)
        database = firestore.client()
        job_ref = (
            database.collection("users")
            .document(uid)
            .collection("ai_note_jobs")
            .document(job_id)
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_pdf_path = str(Path(temp_dir) / "source.pdf")
            bucket.blob(pdf_storage_path).download_to_filename(temp_pdf_path)
            batches, total_pages = _split_pdf_batches(temp_pdf_path, temp_dir)
            memory_context = _summary_memories(
                uid=uid,
                course_id=course_id,
                lecture_id=lecture_id,
            )
            job_ref.set(
                {
                    "storageId": storage_id,
                    "courseId": course_id,
                    "lectureId": lecture_id,
                    "status": "running",
                    "storageBucket": bucket.name,
                    "pdfStoragePath": pdf_storage_path,
                    "totalPages": total_pages,
                    "batchSize": 5,
                    "totalBatches": len(batches),
                    "completedBatches": 0,
                    "completedPages": 0,
                    "failedBatches": 0,
                    "memoryCount": len(memory_context),
                    "createdAt": firestore.SERVER_TIMESTAMP,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                }
            )
            _initialize_batch_documents(
                job_ref=job_ref,
                batches=batches,
                total_pages=total_pages,
            )
            notes_pages = _run_batches_concurrently(
                batches,
                lambda batch: _generate_and_persist_batch(
                    batch=batch,
                    memory_context=memory_context,
                    job_ref=job_ref,
                    database=database,
                ),
            )
        notes = {"pages": notes_pages}
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
                "pageCount": len(notes_pages),
                "memoryCount": len(memory_context),
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        return json_response(
            {
                **notes,
                "status": "completed",
                "storageBucket": bucket.name,
                "jobId": job_id,
                "jobPath": job_ref.path,
                "notesStoragePath": notes_storage_path,
                "memoryCount": len(memory_context),
            }
        )
    except PermissionError as error:
        return json_response({"message": str(error)}, 401)
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
