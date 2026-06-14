from __future__ import annotations

import json
import os
import re
from typing import Any

from firebase_functions import https_fn
from openai import OpenAI


def json_response(payload: dict[str, Any], status: int = 200) -> https_fn.Response:
    return https_fn.Response(
        json.dumps(payload, ensure_ascii=False),
        status=status,
        content_type="application/json",
    )


def request_payload(req: https_fn.Request) -> dict[str, Any]:
    body = req.get_json(silent=True) or {}
    if not isinstance(body, dict):
        return {}
    data = body.get("data")
    return data if isinstance(data, dict) else body


def required_string(payload: dict[str, Any], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Missing required string field: {key}")
    return value.strip()


def optional_string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def safe_storage_id(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", value)


def openai_client() -> OpenAI:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured for Firebase Functions.")
    return OpenAI(api_key=api_key)
