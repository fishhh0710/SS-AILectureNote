# 分心通知功能與使用指南

App 不再因為切到背景就立即通知。通知必須由 Attention Agent 判定為 `distracted` 才會發送。

## 資料流程

1. `StudentAttentionTracker` 記錄學生目前頁面、進入時間、最近 20 次翻頁與 App lifecycle。
2. 每個非空 10 秒 transcript segment 送到 `realtimeAgent`。
3. Realtime Agent 只看逐字稿與投影片摘要，自行判斷老師頁面。
4. 後端 30 秒 gate 根據頁面差異、停留時間、老師移動與背景狀態決定是否執行 Attention Agent。
5. Attention Agent 輸出 `following`、`confused`、`behind`、`distracted` 或 `unclear`。
6. 只有 `distracted` 會通知，兩次背景通知至少間隔 120 秒。

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
  "confidence": 0.91,
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
