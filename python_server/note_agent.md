# Note Agent Flutter Integration

這個檔案是文件，說明 Flutter 怎麼接 `python_server` 裡的 note agent，以及 `SummaryPanel` 的資料流和 UI 架構。

## 目前 Backend 有沒有用

專案裡有兩個不同的 backend 概念：

1. `backend/`
   - 用途：Flask server，提供 Azure Speech token。
   - Endpoint：`GET /api/azure-token`
   - 對應 Flutter：`lib/services/auth_service.dart` 和 `lib/views/azure_lecture_view.dart`
   - 現況：主 app flow 目前沒有走 `AzureLectureView`，所以接 AI note 時沒有用到這個資料夾。

2. `python_server/`
   - 用途：FastAPI server，把 Python AI agents 包成 HTTP API 給 Flutter 呼叫。
   - 主入口：`python_server/api_server.py`
   - 這次接上的功能：`POST /notes/from-pdf`
   - 真正做 PDF 筆記生成的函式：
     `python_server/Agent/note_agent/note_agent.py` 裡的 `generate_all_page_notes_json(pdf_path)`

## Note Agent 的實際輸出

`note_agent.py` 不會直接回傳多個 `.md` 檔案給 Flutter。
FastAPI endpoint `/notes/from-pdf` 回傳的是 JSON：

```json
{
  "pages": [
    {
      "page_number": 1,
      "markdown": "# Page 1: ...\n\n## Main Idea\n..."
    },
    {
      "page_number": 2,
      "markdown": "# Page 2: ...\n\n## Main Idea\n..."
    }
  ]
}
```

Python 端的 `save_notes(data, output_dir)` 有能力把結果存成：

- `notes.json`
- `notes/page_001.md`
- `notes/page_002.md`

但目前 HTTP API 沒有呼叫 `save_notes()`，所以 Flutter 端收到 JSON 後，自己在手機本地 app documents 裡存 `.md` 檔。

## Flutter 是怎麼接上的

### 1. 使用者上傳簡報

檔案：`lib/widgets/slides_panel.dart`

使用者按上傳後：

1. `FilePicker.pickFiles()` 選 PDF。
2. `_copyPdfToAppStorage()` 把 PDF 複製到 app documents：
   `lecture_slides/{fileId}.pdf`
3. `_savePdfPath()` 把 PDF path 寫進 SQLite 的 item `filePath`。
4. `_openPdf()` 在 `SlidesPanel` 裡顯示 PDF。
5. 呼叫 `onPdfUploaded(savedPath)` 通知 `LectureView`：新的 PDF 已經準備好，可以開始生成 AI 筆記。

### 2. LectureView 觸發 AI note generation

檔案：`lib/screens/lecture_view.dart`

`LectureView` 做 orchestration：

- 初始化時呼叫 `_loadSavedAiNotes()`，讀取已存在本機的 AI notes。
- 收到 `SlidesPanel.onPdfUploaded` 後呼叫 `_handlePdfUploaded(pdfPath)`。
- `_handlePdfUploaded()` 會：
  1. 打開 Summary panel。
  2. 清空目前畫面上的舊 notes。
  3. 設定 `_isGeneratingNotes = true`，讓 Summary panel 顯示 loading。
  4. 呼叫 `NoteGenerationService.generateNotesFromPdf(pdfPath)`。
  5. 成功後呼叫 `NoteGenerationService.saveNotes(widget.fileId, notes)`。
  6. 把 notes 放進 `_pageNotes`，Summary panel 會重新 render。

### 3. NoteGenerationService 呼叫 Python server

檔案：`lib/services/note_generation_service.dart`

主要責任：

- 呼叫 Python FastAPI endpoint。
- 解析 note agent 回傳的 JSON。
- 把 notes 存成本機 JSON 和 Markdown 檔。
- 下次打開同一個 lecture 時讀回來。

預設 API base URL：

- Android emulator：`http://10.0.2.2:8000`
- Desktop/local：`http://127.0.0.1:8000`
- 可用 dart define 覆蓋：

```bash
flutter run --dart-define=PYTHON_API_BASE_URL=http://127.0.0.1:8000
```

Android 另外在 `android/app/src/main/AndroidManifest.xml` 加了：

```xml
android:usesCleartextTraffic="true"
```

原因是目前 Python server 是本機 HTTP，不是 HTTPS；Android 預設會限制 cleartext traffic。

## IO

### Flutter -> Python Server

Endpoint：

```text
POST /notes/from-pdf
```

Request：

```text
multipart/form-data
field name: file
file type: PDF
```

來源：

```text
app documents/lecture_slides/{fileId}.pdf
```

也就是 SlidesPanel 存好的本機 PDF。

### Python Server -> Flutter

Response：

```json
{
  "pages": [
    {
      "page_number": 1,
      "markdown": "Markdown text for page 1"
    }
  ]
}
```

Flutter 解析成：

```dart
class AiPageNote {
  final int pageNumber;
  final String markdown;
}
```

### Flutter 本機儲存

每個 lecture item 用 `fileId` 當 storage key。

儲存位置：

```text
app documents/ai_notes/{fileId}/notes.json
app documents/ai_notes/{fileId}/notes/page_001.md
app documents/ai_notes/{fileId}/notes/page_002.md
...
```

`notes.json` 方便 Flutter 快速讀回完整結構。
每頁 `.md` 檔符合「一頁一個 md 檔」的需求，也方便未來做單頁更新或匯出。

### Load 行為

打開 lecture 時：

1. `LectureView.initState()` 呼叫 `_loadSavedAiNotes()`。
2. `NoteGenerationService.loadSavedNotes(fileId)` 先找：
   `ai_notes/{fileId}/notes.json`
3. 如果 `notes.json` 不存在，才 fallback 掃描：
   `ai_notes/{fileId}/notes/page_*.md`
4. 讀到後傳給 `SummaryPanel(notes: _pageNotes)` 顯示。

## SummaryPanel 架構

檔案：`lib/widgets/summary_panel.dart`

`SummaryPanel` 是純 UI component，不自己呼叫 Python、不自己讀寫檔案。
它只吃 `LectureView` 傳進來的 state。

### Input

```dart
SummaryPanel(
  width: width,
  index: index,
  onClose: ...,
  notes: _pageNotes,
  isGenerating: _isGeneratingNotes,
  errorMessage: _notesError,
  onRetry: _retryGeneratingNotes,
)
```

欄位用途：

- `notes`
  - 每頁 AI note。
  - 來源是 `NoteGenerationService` 解析後的 `List<AiPageNote>`。

- `isGenerating`
  - 控制 loading 圈圈。
  - 上傳 PDF 並等待 note agent 時是 `true`。

- `errorMessage`
  - note generation 或讀取本機檔案失敗時顯示。

- `onRetry`
  - 失敗時讓使用者用同一份 PDF 重試。

### UI State

`_buildContent()` 依照狀態切換畫面：

1. `isGenerating == true && notes.isEmpty`
   - 顯示中央 loading。
   - 文案：正在生成 AI 筆記。

2. `notes.isEmpty && errorMessage != null`
   - 顯示錯誤畫面。
   - 如果有 `onRetry`，顯示重試按鈕。

3. `notes.isEmpty`
   - 顯示 empty state。
   - 表示還沒有上傳簡報或尚未生成 notes。

4. `notes.isNotEmpty`
   - 用 `ListView.separated` 一頁一頁顯示。
   - 如果正在重新生成，頂部顯示 `_StatusBanner`。

### 子元件

- `_CenteredMessage`
  - 共用 empty/loading/error 中央提示 UI。

- `_StatusBanner`
  - 顯示「正在更新 AI 筆記」或非致命錯誤。

- `_PageNoteCard`
  - 顯示單頁 note。
  - 上方顯示 `Page {pageNumber}`。
  - 下方用 `flutter_markdown` 的 `MarkdownBody` render markdown。

### Markdown Rendering

現在已改用套件：

```dart
import 'package:flutter_markdown/flutter_markdown.dart';
```

每頁 note 用：

```dart
MarkdownBody(
  data: note.markdown,
  selectable: true,
  softLineBreak: true,
  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(...),
)
```

因此 headings、bold、bullet list、paragraph spacing 等 markdown 行為由 `flutter_markdown` 處理，不再使用手寫 parser。
