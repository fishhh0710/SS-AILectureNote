# Attention Agent 與 Memory 系統技術報告

更新日期：2026-06-15  
目標閱讀時間：約 20 分鐘  
Firebase project：`ai-notes-555a6`

## 1. 完成範圍

本次工作把原本的 Realtime Agent 延伸成完整但彼此隔離的兩階段流程：

1. Realtime Agent 只根據投影片摘要、最近 10 份逐字稿與上次老師頁面，判斷老師目前在第幾頁，以及本段應更新 Summary、建立 bbox 或不處理。
2. 老師頁面確定後，Attention Agent 才取得學生頁面、停留時間、頁面歷史與 App lifecycle，判斷學生是跟上、困惑、落後、分心或資訊不足。
3. 只有真正判為 `distracted` 時才可能送出 FCM 通知，不再因 App 單純進入背景就通知。
4. Attention 的 `missed_content` 與 `confused_summary` 會保存到長期 Memory。
5. Chatbot 已改為 Agent，可自行判斷是否呼叫 Memory tools。
6. PDF Summary 生成前會讀取使用者的摘要偏好與相關學習狀況。

這不是只存一個字串的簡化版 Memory。系統同時保存來源證據與整理後的 canonical memory，支援 scope、狀態、信心、重要度、向量搜尋、語意去重、解決與刪除，後續可以加入帳號系統、Memory 管理 UI、複習 Agent 或跨課程個人化。

## 2. 系統架構

```text
Flutter
  ├─ StudentAttentionTracker
  │    ├─ current page / entered time / duration
  │    ├─ recent 20-page history
  │    ├─ foreground / background
  │    └─ SQLite student_page_events
  ├─ TranscriptExportService
  │    └─ one transcript segment every 10 seconds
  ├─ RealtimeAgentCoordinator
  │    ├─ latest segment + previous 9 segments
  │    ├─ page summaries + last teacher page
  │    └─ studentState + sessionId + FCM token
  ├─ NoteGenerationManager
  │    └─ PDF summary generation and local persistence
  └─ NotificationService
       └─ FCM token, foreground local notification, background handler

Firebase HTTP Functions (Python 3.13, 2nd Gen)
  ├─ realtimeAgent
  │    ├─ stage 1: Realtime Lecture Agent
  │    └─ stage 2: Attention Agent
  ├─ chat
  │    └─ Memory-aware Chat Agent
  ├─ generateNotesFromPdf
  │    └─ memory-personalized PDF notes
  └─ azureSpeechToken

Firestore
  ├─ ai_note_jobs
  └─ users/{uid}
       ├─ lecture_sessions
       ├─ attention_events
       ├─ devices
       ├─ memory_evidence
       └─ memories
```

## 3. 身分與資料隔離

Flutter 透過 `UserIdentityService` 建立或重用匿名 Firebase Auth 使用者。匿名登入有兩個目的：

- 每個使用者取得穩定 UID，Memory 與 Attention 資料不會互相混用。
- 未來加入 Google、Email 或其他登入時，可把匿名帳號 link 到正式 provider，保留同一 UID 下的既有資料。

`FirebaseFunctionClient` 在 HTTP request 加入：

```http
Authorization: Bearer <Firebase ID token>
```

後端以 Firebase Admin SDK 驗證 token。`chat` 與 `generateNotesFromPdf` 缺少有效 token 時回傳 401；Attention 只有在 Realtime request 帶有學生狀態時才要求 UID，因為沒有學生狀態的 Realtime 頁面判斷不需要讀寫個人資料。

## 4. 學生頁面如何取得與保存

`StudentAttentionTracker` 由 Lecture 畫面持有，觀察：

- `currentPage`：學生目前顯示的投影片頁碼。
- `currentPageEnteredAt`：進入本頁的 UTC 時間。
- `currentPageDurationSeconds`：停留秒數。
- `recentPageHistory`：最近 20 次頁面切換。
- `appLifecycle`：`foreground` 或 `background`。
- `backgroundedAt`：進入背景的時間。
- `sessionStartedAt`：本次 Lecture session 開始時間。

每次換頁會結束上一筆事件並寫入 SQLite `student_page_events`：

```text
lectureId
pageNumber
enteredAt
leftAt
durationSeconds
```

本機事件讓頁面紀錄不只存在記憶體，也為後續學習歷程分析保留資料。送給後端的 request 只包含最近必要狀態，不會把整個本機資料庫上傳。

## 5. 為什麼 Realtime Agent 看不到學生頁面

老師頁面必須由課堂內容判斷，而不是從學生目前看的頁面猜測。若 Realtime Agent 同時看到學生頁面，容易形成循環：

1. 系統假設學生頁面就是老師頁面。
2. Attention 再比較兩者，永遠得到相同頁面。
3. 分心與落後偵測因此失效。

目前流程先執行 Realtime Agent，輸出 `page_number` 後，後端才呼叫 Attention。Attention 可以看到老師頁面與學生頁面，但 Realtime Agent 永遠看不到學生頁面。

## 6. Realtime Agent 輸入與輸出

主要輸入：

```json
{
  "latestSegment": "最新 10 秒逐字稿",
  "recentSegments": ["前 9 份非空逐字稿"],
  "lastTeacherPage": 3,
  "pageSummaries": [
    {"page_number": 1, "markdown": "..."},
    {"page_number": 2, "markdown": "..."}
  ],
  "studentState": {
    "currentPage": 1,
    "currentPageDurationSeconds": 45,
    "appLifecycle": "background",
    "sessionStartedAt": "2026-06-15T04:00:00Z",
    "recentPageHistory": []
  },
  "sessionId": "lecture-session-id",
  "courseId": "course-id",
  "lectureId": "lecture-id",
  "notificationToken": "optional-fcm-token"
}
```

`recentSegments` 最多保留 9 份，再加上 `latestSegment`，所以模型總共看到最近 10 份非空 segment。

Realtime 輸出：

```json
{
  "page_number": 3,
  "new_points": ["- 新增重點"],
  "questions": ["老師提出的問題"],
  "targets": [],
  "update_note_at": "summary"
}
```

`update_note_at` 只允許：

- `summary`：只允許 `new_points`／`questions`，`targets` 會被清空。
- `slides`：只允許 `targets`，Summary 欄位會被清空。
- `none`：三個陣列都會被清空。

後端會再次正規化，不只相信模型輸出。若 Summary 對應頁面尚無既有 AI note，Flutter 會直接捨棄，不建立只有課堂補充的新 note。

## 7. Attention 執行 gate

不是每個 10 秒 segment 都呼叫 Attention。後端先做 deterministic gate，避免成本與誤判。

必要條件一：距離 session 開始或上次 Attention 檢查至少 30 秒。

必要條件二：至少出現一項訊號。

- 老師頁面與學生頁面不同。
- 學生停留同一頁至少 30 秒。
- 老師相較上次 Attention 檢查移動至少 2 頁。
- App 在背景。

這些訊號只決定是否值得判斷，不直接決定結果。例如 App 在背景是證據，但不是分心的充分條件；停留過久也可能是認真閱讀。

## 8. Attention Agent 輸出

```json
{
  "checked": true,
  "status": "behind",
  "page_relevance": "related_previous_content",
  "confidence": 0.84,
  "reasoning_summary": "學生仍在相關前置內容，但老師已進入下一頁。",
  "missed_content": [
    "老師補充的 cache hit rate 與平均存取時間關係"
  ],
  "confused_summary": null,
  "gate": {
    "should_run": true,
    "interval_ready": true,
    "signals": {
      "page_mismatch": true,
      "student_stagnant": true,
      "teacher_moved": false,
      "app_background": true
    }
  },
  "notification_sent": false,
  "notification_message_id": null,
  "memory_writes": [
    {
      "memory_id": "...",
      "kind": "missed_content",
      "status": "active"
    }
  ]
}
```

`status` 定義：

- `following`：學生正在相同或緊密相關內容並跟上進度。
- `confused`：仍專注於相關內容，但看起來卡在概念上。
- `behind`：正在複習相關舊內容，老師已往前。
- `distracted`：多項證據支持學生已離開課堂內容或注意力中斷。
- `unclear`：證據不足或互相矛盾。

`missed_content` 與 `confused_summary` 現在不直接改 UI，但會保存到 Memory，供未來複習、個人化摘要與學習分析使用。

## 9. 通知規則

後端必須同時滿足以下條件才送 FCM：

1. Attention 實際執行。
2. `status == distracted`。
3. `appLifecycle == background`。
4. request 有有效 FCM token。
5. 距離同一 session 上次通知至少 120 秒。

因此下列情況不通知：

- 使用者只是切到背景，但 AI 判定仍跟上或只是落後。
- 學生停在同頁閱讀，但沒有足夠分心證據。
- 狀態為 `confused` 或 `behind`。
- 前一次通知後尚未滿 120 秒。
- 沒有可用的裝置 token。

Android 已加入通知權限並可編譯。iOS 已宣告 `remote-notification` background mode，但正式推播仍要在 Apple Developer 與 Firebase Console 設定 APNs key，並在 Xcode 開啟 Push Notifications capability。

若 App process 已被完全終止，就不會再產生新的逐字稿 segment，也不會有新的 Attention 判斷。FCM 可以喚起通知顯示，但前提是後端先收到新的判斷 request。

## 10. Firestore Attention 資料

### `users/{uid}/lecture_sessions/{sessionId}`

保存目前 session 的狀態，例如：

- `lastAttentionCheckedAt`
- `teacherPageAtLastCheck`
- `lastAttentionStatus`
- `lastAttentionResult`
- `lastNotificationAt`

這份文件讓 gate 與 cooldown 不依賴單一 Function instance 的記憶體。

### `users/{uid}/attention_events/{eventId}`

保存每次實際判斷的老師頁面、學生頁面、gate、Agent output 與 Memory 寫入結果。用途是偵錯、行為分析與未來模型評估，不是前端即時狀態來源。

### `users/{uid}/devices/{tokenHash}`

保存 FCM token 與更新時間。document ID 使用 token 的 SHA-256 前 24 碼，避免直接把 token 當路徑。

## 11. Memory 資料模型

Memory 分成兩層：

1. `memory_evidence`：原始來源證據，不直接當作永久真相。
2. `memories`：整理、去重、可搜尋的 canonical memory。

canonical memory 主要欄位：

```json
{
  "domain": "learning",
  "kind": "confusion",
  "content": "學生容易混淆 cache hit rate 與 latency",
  "scope": "lecture",
  "courseId": "course-id",
  "lectureId": "lecture-id",
  "preferenceKey": null,
  "confidence": 0.86,
  "importance": 0.85,
  "explicit": false,
  "evidenceCount": 2,
  "status": "active",
  "provenance": [],
  "metadata": {},
  "embedding": "Firestore Vector(768)",
  "createdAt": "server timestamp",
  "updatedAt": "server timestamp"
}
```

### Domain

- `learning`：不熟、錯過、困惑、已掌握等學習狀況。
- `preference`：摘要格式、回答風格、詳細度等使用者偏好。

### Scope

- `global`：跨所有課程有效。
- `course`：只對指定課程有效。
- `lecture`：只對指定講次有效。

### Status

- `candidate`：尚未累積足夠證據的推論偏好。
- `active`：可供 Agent 與 Summary 使用。
- `resolved`：原本的學習問題已解決，保留歷史但不再注入 prompt。
- `superseded`：被更新版本取代。
- `deleted`：使用者要求忘記，不再使用。

## 12. Memory 寫入與去重

每次 `remember()` 都先建立 evidence，再更新 canonical memory。

偏好使用 `preference_key + scope + course + lecture` 形成穩定 document ID。例如 `summary.format` 不會因使用者重複說明而建立大量重複文件，而是增加 evidence count 並更新內容。

學習狀況先用正規化文字形成穩定 ID。若文字不同，系統再以 `text-embedding-3-small` 建立 768 維 embedding，透過 Firestore cosine KNN 搜尋相似項目；距離小於等於 0.15 時合併成既有 memory。

明確偏好 `explicit=true` 可立即成為 `active`。由模型推論的偏好先為 `candidate`，累積至少兩份 evidence 才變成 `active`，避免一次對話造成過度個人化。

## 13. Attention 如何寫入 Memory

Attention 不把所有輸出都保存成長期 Memory，只保存具未來價值的兩類資料：

- `missed_content`：合併成 lecture-scoped、kind=`missed_content` 的 learning memory，importance 0.75。
- `confused_summary`：寫成 lecture-scoped、kind=`confusion` 的 learning memory，importance 0.85。

兩者的 confidence 使用 Attention output 的 confidence，metadata 保存當時的 attention status，source 為 `attention_agent`，source reference 為 session ID。

## 14. Chatbot Agent 與 Tools

Chat Function 不再直接呼叫一般 Chat Completions。它使用 OpenAI Agents SDK 的 `Agent + Runner + output_type + function_tool`。

每次回答前，系統先依問題、courseId 與 lectureId 搜尋最多 8 筆相關 learning/preference memories，再把結果放入 prompt。Agent 可視需要呼叫：

- `search_memories`：查詢目前使用者的相關 Memory。
- `remember_preference`：保存明確、可重用的偏好。
- `remember_learning_state`：保存重要且未來有幫助的學習狀況。
- `resolve_learning_state`：有證據顯示已理解時，將項目標成 resolved。
- `forget_memory`：只有使用者明確要求忘記時刪除。

Agent 不應保存一般問候、一次性問題、當下任務或不必要的敏感個資。

Chat request：

```json
{
  "question": "請記住之後的摘要使用精簡編號清單",
  "notes": "目前 AI notes",
  "transcript": "目前逐字稿",
  "history": "recent chat history",
  "courseId": "course-id",
  "lectureId": "lecture-id"
}
```

Response contract 維持簡單：

```json
{"answer": "已記住你的摘要格式偏好。"}
```

## 15. Summary 如何使用 Memory

`NoteGenerationManager` 在 request 中傳送 `courseId` 與 `lectureId`。`generateNotesFromPdf` 驗證 UID 後，搜尋：

- active preference memories。
- 與目前課程／講次相關的 active learning memories。

這些 Memory 被放入 PDF notes prompt。偏好可以改變輸出形式，例如使用精簡編號清單，而不是固定 Main Idea／Key Terms；但 Memory 不可以：

- 改寫 PDF 中的事實。
- 跳過 PDF 頁面。
- 把其他課程內容混入目前講義。
- 取代 PDF 本身作為主要內容來源。

Function response 與 Firestore job 會保存 `memoryCount`，便於確認本次生成實際使用幾筆 Memory。

## 16. 未來可直接擴充的 Memory 使用點

目前資料模型可以延伸到：

- 複習 Agent：依 unresolved learning memory 產生個人化題目。
- 課前預習：在新講次開始前找出同課程相關弱點。
- 課後摘要：將本次 missed/confused 項目整理成補課清單。
- Chat 回答深度：依使用者偏好選擇簡短、詳細或例子導向回答。
- 教材導航：學生問問題時優先定位曾經困惑的頁面。
- 分心模式分析：統計哪些教材型態或時段最容易 behind/distracted。
- 正式帳號同步：匿名 UID link 後跨裝置共用 Memory。
- Memory 管理 UI：讓使用者查看、修改、resolve 或 forget。

## 17. 測試結果

已完成：

```text
Python Functions: 17 tests passed
Flutter:          10 tests passed
Dart analyze:     0 errors, 24 existing info lints
Android build:    app-debug.apk built successfully
```

正式環境部署：

```text
azureSpeechToken      Python 3.13, 2nd Gen
chat                  Python 3.13, 2nd Gen
generateNotesFromPdf  Python 3.13, 2nd Gen
realtimeAgent         Python 3.13, 2nd Gen
```

正式環境 smoke test：

- Realtime Agent 正確判斷老師在第 2 頁。
- Attention gate 執行，輸出 `behind`，並建立一筆 `missed_content` learning memory。
- 因狀態不是 `distracted` 且沒有真實裝置 token，`notification_sent=false`，符合規則。
- Chat Agent 接受「未來摘要使用精簡編號清單」偏好。
- 下一次 Chat 能正確取回該偏好。
- PDF Summary 使用同一 UID 的偏好，38 頁輸出採用編號清單，`memoryCount=1`。
- Chat 與 PDF Summary 在沒有 Firebase token 時都回傳 401。

## 18. 自動測試方式

Python：

```powershell
cd functions_python
.\venv\Scripts\python.exe -m pytest -q
```

Flutter：

```powershell
New-Item -ItemType Directory -Force build\unit_test_assets\assets | Out-Null
flutter test
dart analyze lib test
flutter build apk --debug
```

部署：

```powershell
firebase deploy --only functions:python --project ai-notes-555a6
firebase functions:list --project ai-notes-555a6
```

## 19. 手動測試情境

### 情境 A：不應通知

1. 開啟 Lecture 並開始 Demo 或麥克風逐字稿。
2. 學生停在老師正在講的同一頁。
3. 等待超過 30 秒。
4. 確認 Attention 可判為 following/unclear，沒有通知。

### 情境 B：落後但不應通知

1. 老師內容前進到第 4 頁。
2. 學生留在相關的第 2 或第 3 頁閱讀。
3. 等待下一個 segment。
4. 確認狀態偏向 behind/confused，不應只因頁面不同就通知。

### 情境 C：真正分心

1. 在 Android 實機允許通知權限並確認取得 FCM token。
2. 讓老師內容前進數頁。
3. 學生停在無關頁面或把 App 放到背景，並維持足夠長的歷史證據。
4. 確認 Attention 回傳 distracted。
5. 確認背景收到 FCM，且 120 秒內不重複通知。

### 情境 D：Memory 偏好

1. 在 Chat 說「請記住之後摘要使用精簡編號清單」。
2. 再問「我偏好的摘要格式是什麼」。
3. 確認 Agent 能回答偏好。
4. 匯入新的 PDF。
5. 確認生成摘要採用編號清單，且 job 的 `memoryCount` 大於 0。

### 情境 E：學習狀況

1. 讓 Attention 產生 confused 或 missed content。
2. 檢查 `users/{uid}/memories` 有 lecture-scoped learning memory。
3. 在 Chat 詢問自己可能不熟的內容。
4. 確認 Chat 能搜尋並利用該 Memory。

## 20. 已知限制與後續工作

- 尚未用真實 Android/iOS FCM token 驗證訊息實際送達；目前已完成後端規則、Flutter handler 與 Android build。
- iOS 仍需 APNs key、Push Notifications capability、provisioning profile 與實機測試。
- App 被完全關閉後不會繼續產生逐字稿，因此也不會產生新的 Attention request。
- 目前沒有 Memory 管理 UI；Chat Agent 已有 forget/resolve tools，但使用者無法從列表管理。
- 目前沒有排程式離線 Memory curator；每次寫入會即時做 evidence、canonical upsert 與語意去重。
- Dashboard Firebase 備份仍使用固定 userId，尚未與匿名 Auth UID 統一。
- App Check、CORS 限制、正式 Storage/Firestore rules 與 per-user rate limit 尚未完成。
- Attention 準確率仍需真實課堂資料評估；目前 prompt 已避免由單一背景或停留訊號直接判為分心。

## 21. Commit 列表

```text
f9678a8 feat: add attention monitoring and distraction alerts
ed59e81 feat: add persistent user memory core
98acd30 feat: persist attention learning memories
2f28433 feat: make chatbot memory aware
f3b8d64 feat: personalize summaries with user memory
5b8b4ee fix: enable iOS background notifications
```

文件 commit 會另外保存 `arch.html`、`update.md` 與本報告。
