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
python -m py_compile functions_python/main.py
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
- 新增 Python `realtimeAgent` Function，回傳 `targets` 與 `additional_summary`。
- realtime summary 由 `NoteGenerationManager.updateNotes()` 寫入本機 JSON／Markdown，再廣播給 Summary panel。
- 若該頁尚無 PDF summary，先建立只有 `Live Lecture Updates` 的頁面筆記。
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
