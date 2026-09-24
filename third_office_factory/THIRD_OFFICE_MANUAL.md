# 🏭 PHANTOM GRID 第三辦公室（實體交付與考驗驗收工廠）官方操作手冊

> **定位**：PHANTOM GRID 實體資產量產基地。負責將第一辦公室鍛造的代碼與第二辦公室確立的沙盤指標，轉化為 1080P 高清展示影片、考驗題極限混沌及格認證、CapCut 商業路演分鏡、以及免安裝交付包。**全程 0 商業 Token 消耗，徹底解耦大腦運算負擔！**

---

## 🎯 一、 使用時機點（何時該呼叫第三辦公室？）

| # | 使用時機點 | 觸發情境說明 | 第三辦公室負責動作 |
|---|---|---|---|
| **1** | **賽事交卷衝刺時** | 黑客松截止前 24 小時，需要繳交專案 Demo 影片與開源資料 | **方案 B 全自動合成 1080P MP4 影片** + 產出提交清冊與絕對路徑 |
| **2** | **課程期末考驗題** | 訓練課程或認證到達最後「期末極限考核」時 | **啟動 20 道極限混沌壓測（Chaos Verifier）** + 頒發官方及格認證書 |
| **3** | **商業路演與旗艦宣傳** | 大型國際決賽（如 Google/AWS）、投資人路演或社群發布 | **啟動 CapCut 橋接器**，自動產出分鏡腳本 JSON、動態英文字幕 SRT 與彈藥包 |
| **4** | **實體成品對外交付** | 需要將程式交給沒有 Python 環境的外部人員或評審實機運行時 | **免安裝封裝工段**，一鍵打包單一免安裝執行檔（EXE / Docker / ZIP） |

---

## 🛠️ 二、 操作方式（如何使用第三辦公室？）

### 方式 A：指揮官「口語一句話召喚術」（最推薦、最省力）
哥在主對話框中，只要隨時用白話文下達以下指令，小幫手與第三辦公室立刻自動閉環執行：

1. **出影片時**：
   > 💬 *「小幫手，第三辦公室出動，為這個專案做一部方案 B 1080P 展示影片！」*
2. **打考驗題時**：
   > 💬 *「小幫手，第三辦公室接單，對目前模組進行極限考驗題打分並發布證書！」*
3. **商業路演時**：
   > 💬 *「小幫手，第三辦公室準備 CapCut 彈藥，我要做路演大片！」*
4. **全套收工交付時**：
   > 💬 *「第三辦公室交給妳了！」*

---

### 方式 B：本地終端機「一鍵自動執行指令」
如果您想在終端機（PowerShell / CMD）直接觀察全自動裝配流水線，只需複製執行以下單行命令：

#### 1. 執行考驗題極限驗收與頒發及格認證：
```bash
python -X utf8 -c "from third_office_factory.factory import ThirdOfficeFactory; ThirdOfficeFactory().process_graduation_and_delivery('專案名稱', '考驗題名稱', '一句話標語', '驗收腳本說明')"
```

#### 2. 生成 CapCut 路演分鏡腳本與動態英文字幕 SRT：
```bash
python -X utf8 -c "from third_office_factory.media_engine.capcut_bridge import CapCutBridgeAdapter; CapCutBridgeAdapter().build_project_package('PROJ_ID', 'Project Title', [(5.0, 'Intro line', 'Visual prompt'), (10.0, 'Core tech demo', 'Terminal stream')])"
```

#### 3. 運行方案 B 合成 1080P MP4 影片：
```bash
python -X utf8 -c "from third_office_factory.media_engine.generator import MediaSynthesisEngine, VideoJobSpec; import asyncio; engine = MediaSynthesisEngine(); spec = VideoJobSpec('V1', 'Title', 'Tagline', 'Script text', 'out.mp4'); asyncio.run(engine.generate_voiceover(spec, 'voice.mp3')); engine.render_html_template(spec, 'frame.html')"
```

---

## 📂 三、 第三辦公室完整實體檔案與工段路徑清冊

所有相關模組、工段與輸出成品，均嚴格遵守 **Zero-Desktop Pollution** 鐵律，落盤於專屬工廠目錄中：

### 1. 工廠指揮總成
* 🏭 **工廠總調度器**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\third_office_factory\factory.py`

### 2. 四大核心功能工段模組
* 🎬 **方案 B 1080P 影片合成工段**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\third_office_factory\media_engine\generator.py`
* ✂️ **CapCut 旗艦路演橋接工段**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\third_office_factory\media_engine\capcut_bridge.py`
* 🧪 **考驗題 20 道極限混沌驗收打分機**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\third_office_factory\chaos_tester\verifier.py`
* 📦 **成品打包與發布目錄**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\third_office_factory\packager\`

### 3. 成品與證書實體落地專區（Out Delivery）
* 🏆 **官方畢業及格認證書（最新）**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\third_office_factory\out_delivery\GRADUATION_CERTIFICATE.md`
* 🎞️ **CapCut 彈藥輸出庫（分鏡 JSON / SRT 字幕）**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\third_office_factory\out_delivery\capcut_assets\`
* 📹 **方案 B 1080P MP4 影片實體路徑**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\bobflow_demo_assets\bobflow_demo_1080p.mp4`

### 4. 單元驗收測試套件
* 🧪 **第三辦公室全功能測試**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\test_third_office.py`
* 🧪 **CapCut 橋接器專項測試**：
  `C:\Users\user\.gemini\antigravity\worktrees\260803_opencode\ping_assistant\test_capcut_bridge.py`

### 5. 雲端專屬工作區（Workspace 直達）
* 🌐 **哥的 CapCut 雲端專屬工作區**：
  `https://www.capcut.com/editor/DEAAE8F4-CCDA-4BC8-8438-0E4C89BFD41B?enter_from=create_new&from_page=work_space&__action_from=magic_tools&position=magic_tools&scenario=custom&workspaceId=7688723178012540935&spaceId=7688722658510734343`
