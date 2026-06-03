# Project Architecture

This document explains the current Flutter app structure and runtime data flow.

## 1. High-Level Layering

The project uses lightweight MVVM with manual `ChangeNotifier` listeners. No
Provider/Riverpod dependency has been added.

```mermaid
flowchart TD
  App["main.dart / MyApp"]
  Router["GoRouter"]
  Layout["LayoutWrapper"]
  Screens["screens/"]
  Widgets["widgets/"]
  ViewModels["viewmodels/"]
  Repositories["repositories/"]
  Services["services/"]
  Database["database / SQLite"]
  LocalFiles["App Documents: PDF / JSON / Markdown"]
  Firebase["Firebase Core / Storage / AI"]
  Functions["Firebase Functions"]
  Firestore["Firestore job state"]

  App --> Router
  Router --> Layout
  Layout --> Screens
  Screens --> Widgets
  Screens --> ViewModels
  Widgets --> ViewModels
  ViewModels --> Repositories
  Repositories --> Services
  Repositories --> Database
  Services --> LocalFiles
  Services --> Firebase
  Services --> Functions
  Functions --> Firestore
  Functions --> Firebase
```

Recommended boundaries:

- `models/`: plain data objects.
- `services/`: low-level integrations, HTTP, local file IO, Firebase SDKs.
- `repositories/`: application workflows that combine DB, cache, and services.
- `viewmodels/`: screen/panel state using `ChangeNotifier`.
- `screens/`: route-level page composition.
- `widgets/`: reusable UI and panel UI.
- `database/`: SQLite schema and low-level DB access.
- `functions/`: Firebase Functions backend runtime.

The old `python_server` folder is historical reference code only. Flutter no
longer calls it at runtime.

## 2. Navigation

```mermaid
flowchart TD
  Main["main.dart"]
  FirebaseInit["Firebase.initializeApp(firebase_options.dart)"]
  Router["GoRouter"]

  Dashboard["Dashboard: /"]
  CourseDetails["CourseDetails: /course/:courseId"]
  LectureView["LectureView: /lecture/:courseId/:fileId"]

  Main --> FirebaseInit
  Main --> Router
  Router --> Dashboard
  Router --> CourseDetails
  Router --> LectureView

  Dashboard -- "folder/course node id" --> CourseDetails
  Dashboard -- "root id + file node id" --> LectureView
  CourseDetails -- "folder/course node id" --> CourseDetails
  CourseDetails -- "parent node id + file node id" --> LectureView
```

Route parameters:

- `courseId`: string route parameter, usually an `items.id`.
- `fileId`: string route parameter, usually an `items.id` for a notebook,
  recording, or lecture file item.

## 3. Local SQLite Model

SQLite is accessed through `DatabaseHelper`.

```mermaid
erDiagram
  items {
    int id PK
    int parentId FK
    string type
    string name
    string content
    string filePath
    string cloudPath
    string createdAt
  }

  conversations {
    int id PK
    int courseId FK
    string createdAt
  }

  messages {
    int id PK
    int conversationId FK
    string role
    string content
    int sequenceNumber
    string createdAt
  }

  items ||--o{ items : "parentId"
  items ||--o{ conversations : "courseId/notebookId"
  conversations ||--o{ messages : "conversationId"
```

Important model classes:

- `AppNode`: maps to `items`.
- `ChatMessage`: maps to `messages`.

Important `items.type` values:

- `system_folder`
- `folder`
- `course`
- `notebook`
- `recording`
- `ai_note`

## 4. Dashboard, Course Browser, and File Path Flow

Dashboard and course browsing have been moved into MVVM.

```mermaid
flowchart TD
  Dashboard["screens/dashboard.dart"]
  CourseDetails["screens/course_details.dart"]
  SlidesPanel["widgets/slides_panel.dart"]

  DashboardVM["viewmodels/dashboard_view_model.dart"]
  CourseVM["viewmodels/course_details_view_model.dart"]
  SlidesVM["viewmodels/slides_view_model.dart"]

  FileRepo["repositories/file_tree_repository.dart"]
  DBHelper["database/database_helper.dart"]
  FirebaseUpload["services/firebase_upload_service.dart"]

  Dashboard --> DashboardVM
  CourseDetails --> CourseVM
  SlidesPanel --> SlidesVM

  DashboardVM --> FileRepo
  CourseVM --> FileRepo
  SlidesVM --> FileRepo

  FileRepo --> DBHelper
  FileRepo --> FirebaseUpload
```

Responsibilities:

- `DashboardViewModel`: root folder load, root children, create/rename/delete,
  backup progress.
- `CourseDetailsViewModel`: folder/course load, children, create/rename/delete.
- `SlidesViewModel`: load/save the PDF `filePath` for a lecture item.
- `FileTreeRepository`: coordinates SQLite tree operations and manual Firebase
  backup.
- `DatabaseHelper`: low-level SQL only.

## 5. Lecture Workspace Overview

`LectureView` coordinates panel visibility/order, recording lifecycle, and the
AI notes viewmodel.

```mermaid
flowchart TD
  LectureView["screens/lecture_view.dart"]

  SlidesPanel["widgets/slides_panel.dart"]
  TranscriptPanel["widgets/transcript_panel.dart"]
  SummaryPanel["widgets/summary_panel.dart"]
  ChatbotPanel["widgets/chatbot_panel.dart"]

  NotesVM["viewmodels/lecture_notes_view_model.dart"]
  SpeechService["services/gemini_live_speech_service.dart"]
  TranscriptExporter["services/transcript_export_service.dart"]

  LectureView -- "fileId, onPdfUploaded" --> SlidesPanel
  LectureView -- "liveTranscript, isRecording, onStartRecording" --> TranscriptPanel
  LectureView -- "notes, isGenerating, errorMessage, onRetry" --> SummaryPanel
  LectureView -- "notebookId, aiNotes string, transcript string" --> ChatbotPanel

  LectureView --> NotesVM
  LectureView --> SpeechService
  LectureView --> TranscriptExporter
```

Transcript recording/export is still coordinated directly by `LectureView`.
Moving it into `TranscriptViewModel` and `TranscriptRepository` is the main
remaining MVVM follow-up.

## 6. PDF Upload and AI Notes Flow

```mermaid
sequenceDiagram
  participant User
  participant SlidesPanel
  participant SlidesVM as SlidesViewModel
  participant LectureView
  participant NotesVM as LectureNotesViewModel
  participant NoteRepo as NoteRepository
  participant NoteService as NoteGenerationService
  participant Storage as Firebase Storage
  participant Fn as Firebase Function generateNotesFromPdf
  participant Firestore
  participant Local as App Documents

  User->>SlidesPanel: Pick PDF
  SlidesPanel->>Local: Copy to lecture_slides/{fileId}.pdf
  SlidesPanel->>SlidesVM: savePdfPath(savedPath)
  SlidesVM->>NoteRepo: none
  SlidesPanel->>LectureView: onPdfUploaded(savedPath)

  LectureView->>NotesVM: generateFromPdf(storageId=fileId, pdfPath=savedPath)
  NotesVM->>NoteRepo: generateAndSaveNotes(storageId, pdfPath)
  NoteRepo->>NoteService: clearSavedNotes(storageId)
  NoteRepo->>NoteService: generateNotesFromPdf(storageId, pdfPath)
  NoteService->>Storage: Upload PDF to ai_note_jobs/{fileId}/source/
  NoteService->>Fn: POST storageId, pdfStoragePath, jobPath
  Fn->>Firestore: status=running/completed/failed
  Fn->>Storage: Write notes JSON
  Fn-->>NoteService: pages or notesStoragePath
  NoteService-->>NoteRepo: List<AiPageNote>
  NoteRepo->>NoteService: saveNotes(storageId, notes)
  NoteService->>Local: ai_notes/{fileId}/notes.json and Markdown files
  NotesVM-->>LectureView: notifyListeners()
  LectureView-->>SummaryPanel: Render notes
```

Function request:

```json
{
  "storageId": "123",
  "pdfStoragePath": "ai_note_jobs/123/source/...",
  "jobPath": "ai_note_jobs/123",
  "requestedAt": "2026-06-03T02:00:00.000Z"
}
```

Function response:

```json
{
  "status": "completed",
  "jobPath": "ai_note_jobs/123",
  "notesStoragePath": "ai_note_jobs/123/notes/notes.json",
  "pages": [
    {
      "page_number": 1,
      "markdown": "..."
    }
  ]
}
```

## 7. Transcript Flow

Transcript is not yet moved into MVVM. It is coordinated directly by
`LectureView`.

```mermaid
sequenceDiagram
  participant User
  participant LectureView
  participant Gemini as GeminiLiveSpeechService
  participant FirebaseAI as Firebase AI Gemini Live
  participant Exporter as TranscriptExportService
  participant Local as App Documents
  participant DB as DatabaseHelper
  participant Panel as TranscriptPanel

  User->>LectureView: Press mic start
  LectureView->>Exporter: start()
  Exporter->>Local: Create transcripts/{sessionName}/
  Exporter->>DB: Insert AppNode(type=recording, filePath=sessionDir)

  LectureView->>Gemini: toggleListening()
  Gemini->>FirebaseAI: Stream microphone audio
  FirebaseAI-->>Gemini: Transcript text parts
  Gemini-->>LectureView: onUpdate(fullTranscript, listening)
  LectureView->>Exporter: tick(fullTranscript)
  LectureView-->>Panel: liveTranscript

  loop Every 10 seconds
    LectureView->>Exporter: exportSegment()
    Exporter->>Local: Write seg_NNN.json
    Exporter->>DB: Update recording.content = fullTranscript
  end

  User->>LectureView: Press mic stop
  LectureView->>Gemini: toggleListening()
  LectureView->>Exporter: stop(finalTranscript)
  Exporter->>Local: Flush final seg_NNN.json
  Exporter->>DB: Update final recording.content
```

## 8. Chatbot Flow

```mermaid
sequenceDiagram
  participant User
  participant Panel as ChatbotPanel
  participant VM as ChatViewModel
  participant Repo as ChatRepository
  participant DB as DatabaseHelper
  participant Service as ChatFunctionService
  participant Fn as Firebase Function chat

  Panel->>VM: load()
  VM->>Repo: loadLatestSession(notebookId)
  Repo->>DB: getLatestConversationId(notebookId)
  Repo->>DB: createConversation(notebookId) if needed
  Repo->>DB: getConversationMessages(conversationId)
  Repo-->>VM: ChatSession(conversationId, messages)
  VM-->>Panel: notifyListeners()

  User->>Panel: Submit question
  Panel->>VM: sendMessage(text)
  VM->>Repo: addUserMessage(conversationId, text)
  Repo->>DB: insertMessage(user)
  Repo-->>VM: user ChatMessage
  VM-->>Panel: notifyListeners()

  VM->>Repo: requestAssistantReply(aiNotes, transcript, question)
  Repo->>DB: getRecentMessages(conversationId)
  Repo->>Service: ask(notes, transcript, history, question)
  Service->>Fn: POST JSON
  Fn-->>Service: answer JSON
  Service-->>Repo: answer string
  Repo->>DB: insertMessage(assistant)
  Repo-->>VM: assistant ChatMessage
  VM-->>Panel: notifyListeners()
```

Chat request body:

```json
{
  "notes": "merged AI notes markdown",
  "transcript": "latest live transcript",
  "history": "recent user/assistant messages",
  "question": "user question"
}
```

## 9. Firebase Backup Flow

Manual backup from `Dashboard` uploads local files referenced by SQLite nodes to
Firebase Storage and writes `cloudPath` back into SQLite.

```mermaid
flowchart TD
  Dashboard["Dashboard backup button"]
  DashboardVM["DashboardViewModel"]
  FileRepo["FileTreeRepository"]
  Upload["FirebaseUploadService.uploadAllFiles(userId)"]
  SQLite["SQLite items"]
  Metadata["upload_metadata.json"]
  MD5["calculate MD5(file)"]
  Storage["Firebase Storage"]
  UpdateDB["DatabaseHelper.updateItem(cloudPath)"]

  Dashboard --> DashboardVM
  DashboardVM --> FileRepo
  FileRepo --> Upload
  Upload --> SQLite
  Upload --> Metadata
  Upload --> MD5
  SQLite -- "nodes with filePath" --> Upload
  Upload -- "putFile(file)" --> Storage
  Storage -- "users/{userId}/referenced_files/{node.id}_{fileName}" --> UpdateDB
  UpdateDB --> SQLite
  MD5 --> Metadata
```

## 10. Function URL Configuration

Flutter resolves HTTPS Function URLs through `FirebaseFunctionClient`.

- Default URL: `https://<region>-<projectId>.cloudfunctions.net/<functionName>`
- `FIREBASE_FUNCTIONS_REGION`: default `us-central1`
- `FIREBASE_FUNCTIONS_PROJECT_ID`: optional project override
- `FIREBASE_FUNCTIONS_BASE_URL`: optional emulator/custom base URL
- `FIREBASE_CHAT_FUNCTION_URL`: exact chat Function URL override
- `FIREBASE_NOTES_FUNCTION_URL`: exact notes Function URL override
- `FIREBASE_CHAT_FUNCTION_NAME`: default `chat`
- `FIREBASE_NOTES_FUNCTION_NAME`: default `generateNotesFromPdf`

For a Functions emulator, use a base URL shaped like:

```powershell
flutter run --dart-define=FIREBASE_FUNCTIONS_BASE_URL=http://127.0.0.1:5001/<projectId>/us-central1
```

## 11. File Relationship Table

| File | Role |
|---|---|
| `lib/main.dart` | App entry, Firebase init, router |
| `lib/firebase_options.dart` | Firebase platform config |
| `lib/screens/dashboard.dart` | Root dashboard UI wired to `DashboardViewModel` |
| `lib/screens/course_details.dart` | Folder/course UI wired to `CourseDetailsViewModel` |
| `lib/screens/lecture_view.dart` | Lecture workspace coordinator |
| `lib/widgets/slides_panel.dart` | PDF picker/preview wired to `SlidesViewModel` |
| `lib/widgets/transcript_panel.dart` | Transcript display UI |
| `lib/widgets/summary_panel.dart` | AI notes display UI |
| `lib/widgets/chatbot_panel.dart` | Chat UI wired to `ChatViewModel` |
| `lib/viewmodels/dashboard_view_model.dart` | Dashboard tree and backup state |
| `lib/viewmodels/course_details_view_model.dart` | Folder/course tree state |
| `lib/viewmodels/slides_view_model.dart` | Lecture PDF path persistence |
| `lib/viewmodels/lecture_notes_view_model.dart` | AI notes state |
| `lib/viewmodels/chat_view_model.dart` | Chat state |
| `lib/repositories/file_tree_repository.dart` | SQLite file tree workflows and Firebase backup boundary |
| `lib/repositories/note_repository.dart` | AI notes workflow |
| `lib/repositories/chat_repository.dart` | Chat persistence and prompt context workflow |
| `lib/services/firebase_function_client.dart` | Shared HTTPS Firebase Function client |
| `lib/services/chat_function_service.dart` | Chat Function integration |
| `lib/services/note_generation_service.dart` | PDF upload, note Function call, local note cache |
| `lib/services/firebase_upload_service.dart` | Manual Firebase Storage backup |
| `lib/services/gemini_live_speech_service.dart` | Live speech-to-text |
| `lib/services/transcript_export_service.dart` | 10-second transcript segment export |
| `functions/index.js` | Firebase Functions backend for chat and PDF notes |

## 12. Best Trace Entry Points

1. Dashboard and file tree:
   - `DashboardViewModel.loadData`
   - `CourseDetailsViewModel.loadData`
   - `FileTreeRepository`

2. PDF upload and AI notes:
   - `SlidesPanel._pickAndLoadPdf`
   - `SlidesViewModel.savePdfPath`
   - `LectureView._handlePdfUploaded`
   - `LectureNotesViewModel.generateFromPdf`
   - `NoteGenerationService.generateNotesFromPdf`
   - `functions/index.js: generateNotesFromPdf`

3. Live transcript:
   - `LectureView._handleRecordingToggle`
   - `GeminiLiveSpeechService.toggleListening`
   - `TranscriptExportService.exportSegment`

4. Chat:
   - `ChatbotPanel._sendMessage`
   - `ChatViewModel.sendMessage`
   - `ChatRepository.requestAssistantReply`
   - `ChatFunctionService.ask`
   - `functions/index.js: chat`

## 13. Remaining Migration TODOs

- Move transcript recording/export into `TranscriptViewModel` and
  `TranscriptRepository`.
- Deploy Firebase Functions and configure `OPENAI_API_KEY` in the Firebase
  runtime environment.
