# AI Summary App-Level Manager Update
日期：2026-06-14

## 1. 目的
修正 PDF summary 尚未完成就離開 Lecture 頁面時，request 受頁面生命週期影響的問題。
這次採用 App-level `NoteGenerationManager`，生成方式維持單一長時間 HTTP request。
未加入 Firestore listener、polling、FCM，也未加入未來的逐字稿補充摘要功能。

## 2. 最終方案
Flutter 繼續呼叫既有 Cloud Function：
```text
generateNotesFromPdf
```
不建立 background job。
不建立 `jobId`。
不定時查詢狀態。
不使用 Firestore trigger。
長 HTTP request 由 singleton Manager 持有。
Lecture 頁面只訂閱 Manager 的狀態。

## 3. 為何離開頁面後仍能繼續
原本 request 由 `LectureNotesViewModel` 間接持有。
頁面關閉後 ViewModel 會 dispose，連帶終止其擁有的 notes service 與 HTTP client。
現在 `NoteGenerationManager.instance` 是 static singleton。
它的生命週期跟隨 Flutter process，並持有：
```text
FirebaseFunctionClient
FirebaseStorage
執行中的 Future
每個 lecture 的 notes 狀態
狀態 StreamController
```
ViewModel dispose 只取消自己的 stream subscription，不會 dispose Manager。
因此只要 Flutter process 還活著，離開 Lecture 不會中止 request。

## 4. 檔案變更
新增：
```text
lib/services/note_generation_manager.dart
test/lecture_notes_view_model_test.dart
```
移除：
```text
lib/services/note_generation_service.dart
lib/repositories/note_repository.dart
```
notes 流程不再拆成 Service、Repository 與 Manager 三層。
共用的 `FirebaseFunctionClient` 保留，Chat 與 Azure token 仍可繼續使用它。

## 5. Manager 責任
`NoteGenerationManager` 負責完整 PDF summary 流程：
1. 載入本機 notes。
2. 保存每個 `storageId` 的狀態。
3. 防止同一 lecture 重複送出 request。
4. 保存執行中的 Future。
5. 將 PDF 上傳 Firebase Storage。
6. 呼叫 `generateNotesFromPdf`。
7. 解析 Function response。
8. 必要時從 Storage 下載 notes JSON。
9. 保存本機 `notes.json`。
10. 保存逐頁 Markdown。
11. 廣播狀態。
12. 保存 retry 使用的最後 PDF path。

## 6. 狀態模型
```dart
enum NoteGenerationStatus {
  idle,
  generating,
  completed,
  failed,
}
```
每個 lecture 的 state 包含：
```text
storageId
status
notes
errorMessage
lastPdfPath
```
`idle`：沒有本機 notes，也沒有執行中的工作。
`generating`：PDF upload 或 HTTP Function 正在執行。
`completed`：notes 已成功保存並可顯示。
`failed`：流程失敗，可保留舊 notes 並重試。

## 7. Request 去重
Manager 使用：
```text
Map<String, Future<void>> _generationOperations
```
key 是 `storageId`。
同一 lecture 已有 operation 時，新呼叫會共用既有 Future。
因此連續點擊不會送出兩次 OpenAI request，不同 lecture 則可各自生成。

## 8. 本機載入
Manager 第一次看到 `storageId` 時讀取：
```text
ai_notes/{storageId}/notes.json
```
若 JSON 不存在，回退讀取：
```text
ai_notes/{storageId}/notes/page_NNN.md
```
已載入的 lecture 不會重複掃描檔案。
若該 lecture 正在生成，新 ViewModel 會直接取得 `generating` state。

## 9. Firebase Storage
PDF 上傳路徑：
```text
ai_note_jobs/{safeStorageId}/source/{timestamp}_{fileName}
```
PDF metadata：
```text
storageId
sourceFileName
```
Function 產生的 notes JSON：
```text
ai_note_jobs/{safeStorageId}/notes/notes.json
```
Function response 通常直接包含 `pages`。
若只有 `notesStoragePath`，Manager 也能下載並解析 JSON。

## 10. HTTP 與 Cloud Function
request 內容：
```text
storageId
pdfStoragePath
storageBucket
jobPath
requestedAt
```
HTTP timeout 維持 10 分鐘，底層 transport 由 `FirebaseFunctionClient` 負責。
`generateNotesFromPdf` 的資源設定：
```text
timeout: 540 seconds
memory: 1 GB
```
Function 流程：
1. 將 Firestore status 設為 running。
2. 從 Storage 下載 PDF。
3. 上傳 PDF 到 OpenAI Files。
4. 呼叫 OpenAI Responses API。
5. 以 strict JSON Schema 產生逐頁 notes。
6. 將 notes JSON 寫入 Storage。
7. 將 Firestore status 設為 completed。
8. 在同一 HTTP response 回傳 pages。
9. 清除暫存 PDF 與 OpenAI file。
失敗時 Firestore status 會設為 failed。

## 11. Firestore
後端紀錄使用：
```text
ai_note_jobs/{safeStorageId}
```
主要欄位：
```text
status
pdfStoragePath
notesStoragePath
pageCount
error
updatedAt
```
Flutter 不監聽也不輪詢這份 document。
它目前只提供後端狀態與除錯紀錄。

## 12. 本機保存安全性
新結果完成前不刪除舊 notes。
Manager 先建立：
```text
notes.json.next
notes_next/
```
全部寫入成功後才替換：
```text
notes.json
notes/
```
因此生成失敗時舊摘要仍存在。

## 13. ViewModel 與 UI
`LectureNotesViewModel` 只依賴 Manager。
它負責訂閱狀態、觸發生成與 retry，並在 dispose 時取消 subscription。
Summary panel 行為：
1. 無舊 notes 且 generating：顯示轉圈圈。
2. 有舊 notes 且 generating：保留內容並顯示 banner。
3. completed：顯示新 notes。
4. failed：保留舊 notes，顯示錯誤與 retry。
重新進入 Lecture 時，新 ViewModel 會取得 Manager 目前的狀態。
request 完成後也會收到新 notes。

## 14. 測試與驗證
測試涵蓋：
1. 生成期間保留舊 notes。
2. ViewModel dispose 後 generation 繼續。
3. 新 ViewModel 能取得完成結果。
4. 同一 lecture 同時只執行一次 request。
5. 失敗時保留舊 notes 並允許 retry。
已執行：
```text
dart format
flutter analyze
flutter test
python -m unittest discover -s functions_python
python -m compileall functions_python
git diff --check
```
`flutter test`：5 tests passed。
沒有新增 analyzer error。
21 個 analyzer 項目是專案原有 info lint。

## 15. 部署
Firebase project 已重新連線到：
```text
ai-notes-555a6
```
三個 Cloud Functions 已從 JavaScript／Node.js 20 遷移到 Python 3.13／2nd Gen：
```text
chat
generateNotesFromPdf
azureSpeechToken
```
Function 名稱與 HTTP contract 維持不變，因此 Flutter 不需要切換 URL。
Python source 位於：
```text
functions_python/main.py
functions_python/function_common.py
functions_python/lecture_ai.py
functions_python/realtime_agent.py
functions_python/speech.py
```
部署命令：
```bash
firebase deploy --only functions:python
```
舊 Node.js Functions、測試用 Python Functions 與 JavaScript source 已刪除。
`azureSpeechToken` 已部署，但在設定 `AZURE_SPEECH_KEY` 前會回傳設定錯誤。

## 16. 限制
此方案只能跨 Flutter 頁面生命週期，不能跨 App process 生命週期。
完全關閉 App、系統終止 process、裝置重啟，或長時間網路中斷時，request 仍可能失敗。
若未來要支援這些情境，仍需後端 background job 或可恢復的 realtime 狀態機制。

## 17. 本次未加入
- 老師逐字稿自動補充 Summary。
- Firestore realtime listener。

## 23. Merge：transcript agent 與 bbox

整合 feature/bbox 的 transcript segment consumer、自動 bbox 與 realtime agent。

- `RealtimeAgentCoordinator` 訂閱每 10 秒的非空 segment。
- segment 改以 queue 依序處理，不會因前一個 HTTP request 尚未完成而直接遺失。
- 新增 Python `realtimeAgent` Function；其初版回傳 `targets` 與 `additional_summary`，後續已由第 24 節的結構化 Agent contract 取代。
- realtime summary 由 `NoteGenerationManager.updateNotes()` 寫入本機 JSON／Markdown，再廣播給 Summary panel。
- 初版會在缺少 PDF summary 時建立 live note；第 24 節已改為直接捨棄，避免產生沒有基礎摘要的頁面筆記。
- 若 PDF summary 較晚完成，合併並保留已收到的 realtime updates，不讓完整摘要覆蓋課堂補充。
- `SlidesViewModel` 可呼叫 bbox Cloud Run API 進行全頁 detection，或只尋找 agent 指定 targets。
- bbox 座標由 image pixel 正規化後存成原有 annotation model。
- bbox generation status 存入 SQLite；已完成的 PDF 不重跑，未完成離頁會清除 partial annotations。
- 修正 PDF render image 在讀取寬高前就被 dispose，以及 `ui.Image` 未釋放的問題。
- 保留 Python Functions 架構，刪除 merge 帶回的 JavaScript `functions/index.js`。
- 保留 `NoteGenerationManager`，不恢復已淘汰的 `NoteRepository`。
- 新增 realtime note persistence、缺頁建立與 generation merge 測試。
- 定時 polling。
- FCM push notification。
- 跨 App 重啟的工作恢復。
- 後端工作取消。
- Auth 或 App Check。

## 24. Realtime Agent workflow

- 將 `realtimeAgent` 從直接 Chat Completions 改為 OpenAI Agents SDK。
- 使用單一 `Agent`、`Runner`、結構化 `output_type` 與一次性的 context `function_tool`。
- Agent 不接收學生目前頁面，只接收上次老師頁面作為弱參考。
- Coordinator 保存最近 10 份非空 transcript segments；最新一份是本次判斷內容，前 9 份只作上下文。
- Agent 自行搜尋 page summaries 並判斷老師頁面。
- 新輸出為 `page_number`、`new_points`、`questions`、`targets`、`update_note_at`。
- `update_note_at` 只允許 `summary`、`slides`、`none`。
- 後端強制 Summary 與 bbox 互斥，並過濾空字串與字串 `null`。
- `NoteGenerationManager` 統一處理 realtime Summary 持久化與去重。
- 新增內容分別寫入 `Professor Additions` 與 `Professor Questions`。
- Agent 選到沒有既有 AI note 的頁面時直接捨棄，不建立新 note。
- PDF Summary 較晚完成時，仍保留已寫入的 Professor 區段。

## 25. Python Functions 模組整理

- 保留 `main.py` 作為 Firebase Functions 唯一入口。
- `main.py` 只處理 Function 註冊及 region、timeout、memory、CORS 設定。
- 共用 request、response、驗證與 OpenAI client 移到 `function_common.py`。
- Chat 與 PDF notes 都屬於一般課程 AI 功能，集中到 `lecture_ai.py`。
- Realtime Agent 的 schema、tool、prompt、正規化與 handler 移到 `realtime_agent.py`。
- Azure Speech token 邏輯移到小型 `speech.py`。
- 四個已部署 Function 名稱、URL、HTTP contract 與資源設定維持不變。
- 測試改為直接測試各模組的公開 helper 與 handler。

## 26. Attention Agent 與學生頁面追蹤

- 新增 `StudentAttentionTracker`，追蹤學生目前頁面、進入時間、停留秒數、最近 20 次頁面歷史與 App lifecycle。
- SQLite schema 升級為 version 4，新增 `student_page_events` 保存頁面進出與停留時間。
- Realtime Agent 判斷老師頁面時仍看不到學生頁面；老師頁面決定後才進入 Attention 第二階段。
- Attention 至少間隔 30 秒，並要求頁面不同、停留過久、老師移動多頁或 App 背景其中一項訊號。
- Attention 輸出 `following`、`confused`、`behind`、`distracted` 或 `unclear`。
- 同時輸出 `missed_content` 與 `confused_summary`，即使 UI 現在不直接顯示也保留給 Memory。
- 每次實際判斷寫入 `users/{uid}/attention_events`。
- session 狀態寫入 `users/{uid}/lecture_sessions`，保存上次檢查、老師頁面與通知 cooldown。

## 27. 分心通知

- 移除「App 一進背景就通知」的舊 lifecycle notification。
- 新增 Firebase Messaging 與 local notifications。
- 只有 Attention status 為 `distracted`、App 在背景且有有效 FCM token 時才送出通知。
- 同一 session 的通知至少間隔 120 秒。
- FCM token 以 token hash 作為 Firestore device document ID。
- Android 已加入通知權限。
- iOS 已加入 `remote-notification` background mode；APNs key 與 Signing capability 仍需在 Apple/Firebase 設定。

## 28. Firebase 身分驗證

- 啟用 Firebase Anonymous Auth。
- 新增 `UserIdentityService` 建立或重用匿名使用者。
- `FirebaseFunctionClient` 自動附上 Firebase ID token。
- `chat` 與 `generateNotesFromPdf` 無 token 時回傳 401。
- Attention 的 Firestore、Memory 與通知資料使用驗證後 UID 隔離。
- 匿名帳號之後可連結正式登入 provider，保留同一 UID 下的資料。

## 29. Memory 系統

- 新增 `MemoryService`，區分 `learning` 與 `preference` domain。
- scope 支援 global、course、lecture。
- canonical memory 保存 importance、explicit、evidenceCount、status、provenance 與 metadata。
- 每次來源先寫入 `memory_evidence`，再合併到 `memories`。
- 所有偏好收到第一份 evidence 後立即 active；Agent policy 仍限制只保存持久且可重用的偏好。
- 偏好使用穩定 preference key 更新，不會每次建立重複文件。
- 學習狀況先做正規化內容比對，再使用 Firestore vector search 合併語意重複項目。
- embedding 使用 `text-embedding-3-small`，固定為 768 維。
- 建立 collection group `memories` 的 cosine vector index。
- status 支援 active、resolved、superseded、deleted；舊版 candidate preference 讀取時會自動升級。
- 支援搜尋、解決與忘記 Memory，方便未來加入管理 UI 或正式帳號同步。

## 30. Memory 整合點

- Attention 的 `missed_content` 寫入 lecture-scoped `missed_content` learning memory。
- Attention 的 `confused_summary` 寫入 lecture-scoped `confusion` learning memory。
- Chatbot 改為 OpenAI Agents SDK Agent。
- Chat Agent tools 包含搜尋、記住偏好、記住學習狀況、解決學習狀況與刪除 Memory。
- Chat 只保存明確且可重用的偏好或重要學習狀態，不保存一般問候與一次性問題。
- PDF Summary 生成前搜尋 active 的偏好與相關學習 Memory。
- 使用者偏好的摘要格式可以覆蓋預設 Main Idea／Key Terms 版型，但不能改寫 PDF 事實或略過頁面。
- Flutter 的 Chat 與 Summary request 現在都會傳送 courseId 與 lectureId。

## 31. 驗證與部署

- Python：19 tests passed。
- Flutter：10 tests passed。
- `dart analyze lib test` 沒有 error，保留 24 個既有 info lint。
- `flutter build apk --debug` 成功。
- 四個 Python 3.13 Functions 已完整部署到 `ai-notes-555a6`。
- 正式環境 Realtime smoke test 成功判斷老師頁面並執行 Attention、寫入 learning Memory。
- 正式環境 Chat smoke test 成功保存摘要格式偏好，下一次對話能取回。
- 正式環境 PDF smoke test 以同一使用者 Memory 生成 38 頁 notes，回傳 `memoryCount: 1`，輸出採用偏好的編號清單格式。
- 無驗證 token 的 Chat 與 PDF Summary request 均實測回傳 401。
- 尚未以真實 Android/iOS FCM token 驗證推播到實機；後端只有在 `distracted` 狀態才會嘗試送信。

## 32. Memory activation 與信心欄位簡化

- 使用者偏好收到第一份 evidence 後立即成為 `active`，不再等待第二份 evidence。
- `evidenceCount` 仍保留，用於追蹤來源次數與後續稽核，但不影響偏好是否生效。
- 移除 Attention Agent output 的 `confidence`。
- 移除 `MemoryWrite`、canonical memory、memory evidence 與 Chat Agent tool 的 `confidence`。
- 讀取舊版 `candidate` preference 時會視為 `active` 並回寫狀態，同時移除 canonical memory 的舊 confidence 欄位。
- 語音辨識服務本身的 confidence 屬於 Azure／speech recognition 結果，不是 Memory 信心程度，因此維持不變。

## 33. Android 實機 PDFium 與錄音關閉修正

- Android 實機啟動時，`pdfrx 2.3.x` 可能拋出 `Failed to load PDFium module: Native assets file not found`。
- 此問題與 pdfrx 官方 issue #645 的 Android 錯誤相同，因此將 `pdfrx` 精確固定為已知可用的 `2.2.24`。
- 執行 `flutter clean` 後重新取得 dependencies，避免 2.3.x Native Assets build cache 殘留。
- 新 APK 已確認包含 arm64-v8a、armeabi-v7a 與 x86_64 的 `libpdfium.so`。
- `AzureSpeechService.stopListening()` 改為可重入，同時間的 error、WebSocket close、按鈕停止與頁面 dispose 會共用同一個 stop future。
- 只有錄音實際啟動後才呼叫 `AudioRecorder.stop()`，避免 recorder 尚未建立時產生 PlatformException。
- `dispose()` 會等待 stop 完成後再關閉 streams 與 recorder，避免 stop/dispose race。
- Flutter 10 tests passed，Android debug APK build passed。
