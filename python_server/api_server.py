from __future__ import annotations

from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any
import shutil

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

from Agent.distraction_agent.distraction_agent import WorkflowInput, detraction_detect
from Agent.note_agent.lecture_transcript_agent import analyze_transcript_update
from Agent.note_agent.note_agent import generate_all_page_notes_json


app = FastAPI(
    title="SS AI Lecture Note API",
    description="HTTP API wrapper for the Python lecture-note agents.",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class NotesFromPathRequest(BaseModel):
    pdf_path: str


class TranscriptAnalyzeRequest(BaseModel):
    current_page_note_md: str
    professor_page_number: int
    transcript: str


def _to_http_error(error: Exception) -> HTTPException:
    return HTTPException(
        status_code=500,
        detail={
            "error": type(error).__name__,
            "message": str(error),
        },
    )


def _validate_pdf_upload(file: UploadFile) -> None:
    filename = file.filename or ""

    if Path(filename).suffix.lower() != ".pdf":
        raise HTTPException(
            status_code=400,
            detail={
                "error": "InvalidFileType",
                "message": "Only .pdf files are supported.",
            },
        )


async def _save_upload_to_temp_pdf(file: UploadFile) -> str:
    _validate_pdf_upload(file)

    with NamedTemporaryFile(delete=False, suffix=".pdf") as temp_file:
        await run_in_threadpool(shutil.copyfileobj, file.file, temp_file)
        return temp_file.name


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/notes/from-pdf")
async def notes_from_pdf(file: UploadFile = File(...)) -> dict[str, Any]:
    temp_pdf_path: str | None = None

    try:
        temp_pdf_path = await _save_upload_to_temp_pdf(file)
        return await run_in_threadpool(generate_all_page_notes_json, temp_pdf_path)
    except HTTPException:
        raise
    except Exception as error:
        raise _to_http_error(error) from error
    finally:
        await file.close()

        if temp_pdf_path:
            try:
                Path(temp_pdf_path).unlink(missing_ok=True)
            except Exception:
                pass


@app.post("/notes/from-pdf-path")
async def notes_from_pdf_path(request: NotesFromPathRequest) -> dict[str, Any]:
    try:
        return await run_in_threadpool(generate_all_page_notes_json, request.pdf_path)
    except Exception as error:
        raise _to_http_error(error) from error


@app.post("/transcript/analyze")
async def transcript_analyze(request: TranscriptAnalyzeRequest) -> dict[str, Any]:
    try:
        return await run_in_threadpool(
            analyze_transcript_update,
            current_page_note_md=request.current_page_note_md,
            professor_page_number=request.professor_page_number,
            transcript=request.transcript,
        )
    except Exception as error:
        raise _to_http_error(error) from error


@app.post("/attention/analyze")
async def attention_analyze(request: WorkflowInput) -> dict[str, Any]:
    try:
        return await detraction_detect(request)
    except Exception as error:
        raise _to_http_error(error) from error
