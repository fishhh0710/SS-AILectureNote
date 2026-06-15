# 分心通知功能與使用指南

App 不再因為切到背景就立即通知。通知必須由 Attention Agent 判定為 `distracted` 才會發送。

## 資料流程

1. `StudentAttentionTracker` 記錄學生目前頁面、進入時間、最近 20 次翻頁與 App lifecycle。
2. 每個非空 10 秒 transcript segment 送到 `realtimeAgent`。
3. Realtime Agent 只看逐字稿與投影片摘要，自行判斷老師頁面。
4. 後端 gate 在背景每 10 秒、前景每 25 秒檢查頁面差異、停留時間、老師移動與背景狀態。
5. Attention Agent 透過 tools 讀取 gate 與 evidence，再輸出 `following`、`confused`、`behind`、`distracted` 或 `unclear`。
6. Agent 可呼叫 tools 寫入 Memory、發送通知及保存結果；後端仍會驗證通知安全條件。
7. 只有 `distracted`、背景至少 15 秒且另有一項分心證據時才通知，兩次通知至少間隔 60 秒。

## 通知方式

- App 前景：`NotificationService` 使用 `flutter_local_notifications` 顯示本機通知。
- App 背景：Cloud Function 使用 Firebase Admin SDK 發送 FCM。
- Android 13 以上及 iOS 會要求通知權限。
- FCM token 儲存在 `users/{uid}/devices/{deviceId}`，使用者由 Firebase Anonymous Auth 識別。

## Attention 輸出

```json
{
  "checked": true,
  "status": "distracted",
  "page_relevance": "unrelated",
  "reasoning_summary": "學生已離開課堂畫面且目前頁面與老師內容無關。",
  "missed_content": ["老師正在說明 binary search 的停止條件。"],
  "confused_summary": null,
  "notification_sent": true
}
```

`missed_content` 與 `confused_summary` 目前不顯示在 UI，但會保留給 Memory 系統使用。

## 重要限制

- App 被作業系統完全終止後，Flutter 無法繼續錄音或產生新的 transcript segment。
- iOS 背景 FCM 仍需在 Apple Developer 與 Firebase Console 設定 APNs key/certificate。
- App lifecycle 是判斷證據，不會單獨被視為分心。
- 同一次 Agent run 的 Memory 與通知 tools 具有冪等保護，不會因重複 tool call 重複寫入或推播。
