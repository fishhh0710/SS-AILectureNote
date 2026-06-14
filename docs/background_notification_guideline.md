# 背景通知功能與使用指南 (Background Notification Guide)

此指南說明 `LifecycleNotificationManager` Widget 的功能特性、安裝設定以及如何在專案中進行使用與自訂。

---

## 1. 功能簡介

`LifecycleNotificationManager` 是一個專門用來監聽應用程式生命週期（Lifecycle）變更的 Flutter Widget。當使用者：
* **切換至其他 App**
* **按下 Home 鍵返回桌面**

App 會進入 `paused` 狀態，此時該 Widget 會自動觸發系統的原生本機通知（Local Notification），向使用者提示 App 目前的背景運行狀態。當使用者重新點擊 App 返回前台（`resumed`）時，系統將會自動清除該通知，以提供乾淨的通知欄體驗。

---

## 2. 核心特點

* **自動生命週期監控**：基於 `WidgetsBindingObserver` 實現，免去手動在各個頁面監聽生命週期的複雜度。
* **原生權限自動引導**：整合 `permission_handler` 與 `flutter_local_notifications`，在初始化時自動向 Android 13+ 與 iOS 使用者申請通知發送權限。
* **通知防重複機制**：使用固定的通知 ID（預設為 `888`），多次切換背景時只會更新同一則通知，不會在通知欄產生多條重複堆疊。
* **高自訂性**：支援自訂標題、內文、是否自動清除，以及**預先預留的動態通知內容**功能。

---

## 3. 使用與整合說明

### 基本使用 (已整合於 `main.dart`)
在專案中，該 Widget 被包覆在最外層的 `MaterialApp.router` 外部，使得整個應用程式內的所有路由與頁面都能共享背景通知的監控服務。

```dart
// 引入 Widget
import 'widgets/lifecycle_notification_manager.dart';

@override
Widget build(BuildContext context) {
  return LifecycleNotificationManager(
    title: '您已離開 App',
    body: 'AI 教學助手仍在後台運作中',
    cleanOnResume: true, // 回到 App 時自動清除
    child: MaterialApp.router(
      // ... 相關設定
      routerConfig: _router,
    ),
  );
}
```

### 參數說明 (Parameters)

| 參數名 | 類型 | 預設值 | 說明 |
| :--- | :--- | :--- | :--- |
| `child` | `Widget` | **必填** | 子元件，通常為 `MaterialApp` 或頁面的根 Widget。 |
| `title` | `String` | `'您已離開 App'` | 當 App 進入背景時顯示的通知標題。 |
| `body` | `String` | `'AI 教學助手仍在後台運作中'` | 當 App 進入背景時顯示的通知內容。 |
| `cleanOnResume` | `bool` | `true` | 當 App 重新回到前台時，是否自動把該則背景通知清除。 |
| `enableDynamicContent`| `bool` | `false` | 是否啟用動態通知內容（若為 `true` 則會改從下方 builder 獲取內容）。 |
| `dynamicTitleBuilder` | `String Function()?` | `null` | 動態生成通知標題的回呼函式（例如可根據當前錄音狀態動態返回不同標題）。 |
| `dynamicBodyBuilder`  | `String Function()?` | `null` | 動態生成通知內容的回呼函式。 |

### 進階使用：動態通知內容
若未來需要根據使用者的特定操作（例如：是否正在錄音、是否正在下載講義）來顯示不同的背景提示，可以啟用 `enableDynamicContent` 並傳入 Builder：

```dart
LifecycleNotificationManager(
  enableDynamicContent: true, // 啟用動態內容
  dynamicTitleBuilder: () {
    if (RecordingService.isRecording) {
      return '語音錄製中...';
    }
    return '您已離開 App';
  },
  dynamicBodyBuilder: () {
    if (RecordingService.isRecording) {
      return 'AI 正在背景即時為您串流轉寫課堂筆記';
    }
    return '教學助手已在背景就緒';
  },
  child: MyAppBody(),
)
```

---

## 4. 原生平台配置

為了讓通知功能正常運作，以下原生設定已包含於專案中：

### Android 系統設定
1. **權限聲明**：
   在 `android/app/src/main/AndroidManifest.xml` 中已加入：
   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
   ```
2. **通知圖示**：
   Android 發送通知必須指定一個 drawable/mipmap 資源作為狀態列小圖示。預設初始化使用 `@mipmap/ic_launcher`（即 App 啟動圖示）。
   * *註：若未來需要更換專屬的通知圖示，可將圖示置於 `android/app/src/main/res/drawable/` 並更改 `lifecycle_notification_manager.dart` 中的 `AndroidInitializationSettings` 初始化設定。*

### iOS 系統設定
* iOS 不需要特別在 `Info.plist` 中新增專屬通知欄位，但會在首次運行時透過系統對話框詢問使用者「是否允許此 App 發送通知」。
