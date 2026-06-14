from __future__ import annotations

import os
from typing import Any, Callable

from firebase_admin import initialize_app
from firebase_functions import https_fn, options

from lecture_ai import chat_handler, notes_handler
from realtime_agent import realtime_agent_handler
from speech import azure_token_handler

initialize_app()

REGION = os.getenv("FUNCTION_REGION", "us-central1")
CORS = options.CorsOptions(cors_origins="*", cors_methods=["post", "options"])


def _http_function(
    *, timeout_sec: int, memory: options.MemoryOption
) -> Callable[[Callable[[https_fn.Request], https_fn.Response]], Any]:
    return https_fn.on_request(
        region=REGION,
        timeout_sec=timeout_sec,
        memory=memory,
        cors=CORS,
    )


@_http_function(timeout_sec=120, memory=options.MemoryOption.MB_512)
def chat(req: https_fn.Request) -> https_fn.Response:
    return chat_handler(req)


@_http_function(timeout_sec=540, memory=options.MemoryOption.GB_1)
def generateNotesFromPdf(req: https_fn.Request) -> https_fn.Response:
    return notes_handler(req)


@_http_function(timeout_sec=60, memory=options.MemoryOption.MB_256)
def azureSpeechToken(req: https_fn.Request) -> https_fn.Response:
    return azure_token_handler(req)


@_http_function(timeout_sec=120, memory=options.MemoryOption.MB_512)
def realtimeAgent(req: https_fn.Request) -> https_fn.Response:
    return realtime_agent_handler(req)
