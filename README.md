# AI-Lecture-Note App 🧠

這個專案是一個基於 Flutter 開發的課堂學習筆記軟體。它提供了一個可以自由調整大小、拖曳排序的多面板工作區，幫助學生同時瀏覽投影片、逐字稿、AI 總結與聊天。

---

## 📂 檔案目錄與功能說明

這裏簡單介紹每個重要檔案所負責的功能，方便開發者快速上手：

### 🚀 核心入口與路由
*   **[`lib/main.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/main.dart)**：應用的進入點。負責初始化 App、設定綠色系主題，以及配置頁面跳轉的路由規則（`go_router`）。
*   **[`lib/widgets/layout_wrapper.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/widgets/layout_wrapper.dart)**：全域的畫面外殼。會自動幫一般頁面加上頂部標題和底部狀態列，並在進入課堂看筆記時自動隱藏它們，空出完整螢幕。

### 🖥️ 主頁面（Screens）
*   **[`lib/screens/dashboard.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/screens/dashboard.dart)**：首頁（儀表板）。用來展示目前的所有課程卡片。
*   **[`lib/screens/course_details.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/screens/course_details.dart)**：課程詳細頁面。展示該堂課的大綱、講義資料夾與課堂檔案。
*   **[`lib/screens/lecture_view.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/screens/lecture_view.dart)**：筆記本頁面。支援多面板並存、滑動拉桿調整大小、拖曳手把排序、以及防範螢幕太窄塞不下面板的提示功能。

### 🧩 工作區面板與組件（Widgets）
*   **[`lib/widgets/panel_header.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/widgets/panel_header.dart)**：每個工作面板（如投影片、逐字稿、AI總結）上方的通用標頭，附帶關閉按鈕與可以用來拖曳排序的手把。
*   **[`lib/widgets/slides_panel.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/widgets/slides_panel.dart)** & **`slide_page.dart`**：投影片面板，以漂亮的卡片比例展示課堂簡報。
*   **[`lib/widgets/transcript_panel.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/widgets/transcript_panel.dart)** & **`transcript_accordion.dart`**：課堂錄音逐字稿面板，包含可以點擊展開與收合。
*   **[`lib/widgets/summary_panel.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/widgets/summary_panel.dart)**：AI 自動課堂總結面板，整理出本課的重點提示與專有名詞。
*   **[`lib/widgets/chatbot_panel.dart`](file:///c:/Users/user/NTHU%20projects/software_studio/Lecture_note_app/lib/widgets/chatbot_panel.dart)**：AI 助手聊天面板，提供精緻的問答對話泡泡與文字輸入框。
