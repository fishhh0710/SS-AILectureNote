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

---

## 💻 如何參與貢獻 (How to Contribute)

各位開發者好！這份指南將告訴你如何安全、流暢地提交代碼到本專案。

### 🚗 1. 複製專案 (Clone)
首先，把專案複製到你的本機電腦上：

```bash
git clone https://github.com/fishhh0710/SS-AILectureNote.git
cd Lecture_note_app
```

確認一下是否有成功下載並處於 `main` 分支：
```bash
git branch
# 應該會看到： * main
```

### 🌱 2. 建立你自己的分支 (Branch)
**千萬不要**直接把代碼 push 到 `main`！
請為你要開發的新功能或修復的 bug 建立專屬分支：

```bash
git checkout -b feature/chatbot-improvement
```

**分支命名規範**：
*   `feature/...` ➔ 開發新功能 (例如：`feature/login-page`)
*   `fix/...` ➔ 修復 Bug (例如：`fix/reorder-bug`)
*   `refactor/...` ➔ 程式碼重構、優化 (例如：`refactor/layout-math`)

### ✍️ 3. 修改程式碼並提交 (Commit)
做完修改後，將檔案暫存並提交。**請好好撰寫有意義的 commit message**：

```bash
git add .
git commit -m "Add message input field to chatbot panel"
```

### ⬆️ 4. 推送分支 (Push)
將你的分支推送到 GitHub 遠端倉庫（第一次推送請加上 `-u`）：

```bash
git push -u origin feature/chatbot-improvement
```

### 🔁 5. 建立 Pull Request (PR)
1. 前往本專案的 GitHub 頁面。
2. 你會看到一個黃色提示框顯示：`Compare & pull request` ➔ 點擊它。
3. 撰寫簡單明瞭的標題與說明（寫下你修改了什麼）。
4. 點擊 `Create pull request` ➔ 大功告成！🎉

### 🔄 6. 同步最新程式碼
在開始任何新工作之前，永遠記得更新你的本機 `main` 分支，並合併到你的分支中：

```bash
# 更新本機 main
git checkout main
git pull

# 合併最新 main 到你的開發分支
git checkout feature/chatbot-improvement
git merge main
```

### 💣 7. 避開常見錯誤
| ❌ 錯誤行為 | ✅ 正確做法 |
| :--- | :--- |
| 直接在 `main` 修改程式碼 | 絕對不要！請務必另外開分支。 |
| PR 合併後留著一堆舊分支 | PR 合併後，請隨手刪除本機與遠端的舊分支。 |
| 忘了拉取最新更新就動筆寫程式 | 開工前一定要先執行 `git pull`。 |
| 推送（Push）被拒絕 | 確認你當前是不是在自己的分支，而不是在 `main`。 |

### 💡 8. 實用 Git 常用指令 (Useful Git Commands)
這裡有一些日常開發非常實用的 Git 指令：

```bash
# 查看目前有哪些檔案被修改、哪些尚未暫存
git status

# 查看修改程式碼的詳細差異內容 (比對程式碼修改處)
git diff

# 查看過去的 commit 提交歷史紀錄
git log --oneline

# 切換到已經存在的其他分支
git checkout <分支名稱>

```

---

### 📘 完整工作流程範例 (Full Example)
```bash
# 1. 複製專案並進入資料夾
git clone https://github.com/fishhh0710/SS-AILectureNote.git
cd Lecture_note_app

# 2. 建立並切換到你的功能開發分支
git checkout -b feature/chatbot-integration

# 3. 編輯檔案，然後 commit 提交修改
git add .
git commit -m "Implement chatbot panel with message text field"

# 4. 推送到 GitHub
git push -u origin feature/chatbot-integration

```

---

<!-- NEW FEATURE START: PDF ANNOTATION OVERLAY -->
## 🎨 PDF 標記與筆跡儲存功能 (PDF Annotation Overlay)

本專案支援高效能、防溢出的 PDF 投影片標記與儲存系統。使用者可以在投影片面板疊加方框與文字標記，資料會完整持久化於本機 SQLite 資料庫中。

### 🚀 核心設計特點
1. **SQLite 樹狀子節點儲存**：
   * 每一頁的筆跡資料會打包成 JSON 字串，作為類型為 `'slide_annotation'` 的子節點儲存於 `items` 資料表中，其 `parentId` 指向對應的 PDF 節點。
   * **級聯刪除（ON DELETE CASCADE）**：當 PDF 檔案節點被刪除時，SQLite 資料庫會自動在底層一併清除該 PDF 所有的筆跡子節點，不留下髒資料。
2. **零延遲與局部重繪優化**：
   * **分頁 ValueNotifier 快取**：為每頁投影片配置獨立的狀態監聽器。修改筆跡時，記憶體資料會立即變更，從而實現一幀之內（16ms 內）的局部 Canvas 重繪。
   * **重繪邊界（RepaintBoundary）**：將繪圖 Canvas 封裝在獨立圖層。PDF 縮放與滾動時，Flutter 引擎會直接複用 GPU 快取的點陣圖，不重複繪製向量線條，確保操作極致流暢。
   * **非同步防抖儲存（Debounced I/O）**：使用者停止編輯 600ms 後，背景線程才非同步將快取資料寫入資料庫，完全釋放主線程（UI Thread）負擔。
3. **比例縮放與防溢出保護（Overflow Safety）**：
   * **相對座標與字型比例**：標記位置、尺寸以及字體大小（基於 850.0 寬度）皆採用相對比例計算。當 PDF 縮放時，標記與文字尺寸會同比例縮放，保證文字不移位或錯開。
   * **安全裁剪（ClipRect）**：繪圖疊加層外使用 `ClipRect` 包覆，超出 PDF 邊界的線條將自動在邊界裁剪。
   * **文字自動換行**：當文字標記長度超出投影片右側邊界時會自動向下折行（支援設定 `autoWrap` 參數），絕不產生黃黑相間的 `RenderFlex overflowed` 佈局錯誤，也不會導致程式崩潰。

### 🧩 檔案與核心程式碼
* **[`lib/data/annotation_model.dart`](file:///c:/Users/USER/Desktop/Now/SDS/final%20project/SS-AILectureNote/lib/data/annotation_model.dart)**：定義標記（Annotation）、方框（RectAnnotation）、與文字（TextAnnotation）的多型資料模型及渲染（draw）邏輯。
* **[`lib/services/annotation_manager.dart`](file:///c:/Users/USER/Desktop/Now/SDS/final%20project/SS-AILectureNote/lib/services/annotation_manager.dart)**：處理分頁筆跡快取更新、即時更新分發以及 SQLite 防抖非同步寫入。
* **[`lib/widgets/annotation_test_controls.dart`](file:///c:/Users/USER/Desktop/Now/SDS/final%20project/SS-AILectureNote/lib/widgets/annotation_test_controls.dart)**：**可隨時移除的測試控制組件**。提供一個懸浮按鈕與對話框（Dialog）供開發者手動新增方框/文字、查看標記清單、個別刪除標記或一鍵清除所有標記。
* **SQLite 擴充 API**：在 `DatabaseHelper` 中整合了 `getPageAnnotations`、`savePageAnnotations`、`deletePageAnnotationsNode` 以及 `clearAllPdfAnnotations` 以供專案中**任何其他的 `.dart` 檔案**直接存取。

### 🗑️ 如何移除測試控制 UI？
為了日後維護與上線的便利，本功能採用完全解耦的設計。當您想將測試控制 UI 拆除時，**只需進行以下兩步操作**即可不著痕跡地完美移除：
1. 開啟 **`lib/widgets/slides_panel.dart`**：
   * 移除頂部 import `annotation_test_controls.dart`
   * 移除 build 方法 Stack 中掛載的 `SlideAnnotationTestControls` 這一行程式碼。
2. 刪除 **`lib/widgets/annotation_test_controls.dart`** 實體檔案。

<!-- NEW FEATURE END -->



