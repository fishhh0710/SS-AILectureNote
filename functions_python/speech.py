from __future__ import annotations

import logging
import os

import requests
from firebase_functions import https_fn

from function_common import json_response


def azure_token_handler(req: https_fn.Request) -> https_fn.Response:
    if req.method != "POST":
        return json_response({"message": "Only POST is supported."}, 405)
    try:
        key = os.getenv("AZURE_SPEECH_KEY", "").strip()
        region = os.getenv("AZURE_REGION", "eastasia").strip() or "eastasia"
        if not key or key == "AZURE_KEY_NOT_SET":
            raise RuntimeError("Azure Speech key is not configured for Firebase Functions.")
        response = requests.post(
            f"https://{region}.api.cognitive.microsoft.com/sts/v1.0/issueToken",
            headers={"Ocp-Apim-Subscription-Key": key},
            timeout=30,
        )
        if not response.ok:
            raise RuntimeError(
                f"Failed to fetch token from Azure: Status {response.status_code} - {response.text}"
            )
        return json_response({"token": response.text.strip()})
    except Exception as error:
        logging.exception("Azure token function failed")
        return json_response({"message": str(error)}, 500)
