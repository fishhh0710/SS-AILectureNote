# Python Server

> This directory is an early local FastAPI prototype and is not used by the current Flutter runtime.
> Production endpoints now live under `functions_python/`; `main.py` registers the Python 3.13 Firebase Functions and delegates to the feature modules.

This folder contains the temporary Python backend for the Flutter app.

The project currently uses this local `python_server` because Firebase is not connected yet. After Firebase is added, these Python APIs can be moved to Firebase / Cloud Functions / Cloud Run, and the Flutter app should call Firebase instead of this local Python server.

## What This Server Does

The FastAPI server exposes Python AI functions to the Flutter app.

Current main entrypoint:

```text
api_server.py
```

Main endpoints:

```text
GET  /health
POST /notes/from-pdf
POST /notes/from-pdf-path
POST /transcript/chunk
GET  /transcript/session/{session_id}
POST /transcript/analyze
POST /attention/analyze
```

## AI Agents

There are currently three AI-related components in this folder:

1. PDF note agent
   - File: `Agent/note_agent/note_agent.py`
   - Function: `generate_all_page_notes_json`
   - Purpose: read a PDF and generate Markdown notes for each page.
   - Status: currently connected to Flutter through `/notes/from-pdf`.

2. Lecture transcript agent
   - File: `Agent/note_agent/lecture_transcript_agent.py`
   - Function: `analyze_lecture_transcript`
   - Purpose: analyze new transcript segments and update Markdown notes.
   - Status: implemented on the Python side, but not fully connected to the Flutter workflow yet.

3. Distraction / attention agent
   - File: `Agent/distraction_agent/distraction_agent.py`
   - Function: `detraction_detect`
   - Purpose: determine whether the student is following, confused, behind, or distracted.
   - Status: implemented on the Python side, but not fully connected to the Flutter workflow yet.

At the moment, only the PDF note generation flow is actively used by the Flutter app.

## Setup

Use Python 3.11 or newer.

### Windows

From the project root:

```powershell
cd python_server
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

Set the OpenAI API key in the same PowerShell session:

```powershell
set OPENAI_API_KEY=your_openai_api_key_here
```

If you use PowerShell and `set` does not work for your session, use:

```powershell
$env:OPENAI_API_KEY="your_openai_api_key_here"
```

Start the server:

```powershell
uvicorn api_server:app --reload --host 0.0.0.0 --port 8000
```

### macOS

From the project root:

```bash
cd python_server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Set the OpenAI API key in the same terminal session:

```bash
export OPENAI_API_KEY=your_openai_api_key_here
```

Start the server:

```bash
uvicorn api_server:app --reload --host 0.0.0.0 --port 8000
```

## Check That It Is Running

Open this URL in a browser:

```text
http://127.0.0.1:8000/health
```

Expected response:

```json
{"status":"ok"}
```

## Flutter Connection

For Android emulator, Flutter calls:

```text
http://10.0.2.2:8000
```

For desktop or local machine targets, Flutter calls:

```text
http://127.0.0.1:8000
```

You can override the API URL when running Flutter:

```bash
flutter run --dart-define=PYTHON_API_BASE_URL=http://127.0.0.1:8000
```

## Notes

- Do not commit real OpenAI API keys.
- This server is a temporary local backend until Firebase is integrated.
- When Firebase is ready, the same responsibilities can be moved to Firebase services, and Flutter should stop depending on `python_server`.
