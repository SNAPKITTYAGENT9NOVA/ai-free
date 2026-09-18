---
name: phantomgrid-lookbook-binder
description: >-
  Standard specifications, design guidelines, and automated toolchain for creating
  PHANTOMGRID official character lookbooks and loose-leaf 4-panel manga binders.
  Use this skill whenever generating, updating, or compiling A4 landscape print-ready
  PDF albums, 3D interactive flipbooks with metallic ring binders, or enforcing
  character visual consistency standards.
---

# PHANTOMGRID 相冊與活頁動漫畫大典規格技能 (Lookbook & Loose-Leaf Binder Skill)

本技能沉澱了 PHANTOMGRID 戰隊最高工程規格之「官方典藏寫真相冊」與「三大系列活頁四格動漫畫大典」的端到端管線架構、視覺規範與自動化建置工具鏈。

---

## 核心規格原則 (Core Principles)

### 1. 印刷級相冊版面規格 (Print Specification)
* **紙張尺寸**：標準 A4 橫式對開 (297mm x 210mm)。
* **邊界規範**：@page { size: 297mm 210mm; margin: 0; }。
* **色彩模式**：-webkit-print-color-adjust: exact; print-color-adjust: exact;。
* **背景調性**：賽博曜石黑 (#060910)、深海戰術海軍藍 (#080d18 ~ #10192e)，點綴青光 (#00f2fe)、魅紫 (#9d4edd) 與帝王金 (#f5a623)。

### 2. 活頁夾五金結構 (Loose-Leaf Hardware Mechanics)
* **中央金屬活頁脊（Spine）**：寬度 22mm ~ 24mm，6 孔或 4 孔 Chrome 銀色活頁環（立體金屬漸變 + 白色高光條 + 深色投影）。
* **精密沖孔（Punch Holes）**：直徑 5.0mm ~ 5.5mm 圓孔，內嵌陰影，沿對開內側邊距排列。
* **虛線撕裂引導（Perforation Line）**：order-right: 1px dashed rgba(255,255,255,0.1);。

### 3. 對開版面標準配置 (Spread Layout Standards)
* **左頁（視覺主體 Visual Centerpiece）**：
  - 角色寫真立繪 或 4-Panel 四格動漫畫。
  - 高解析滿版/微邊框，HUD 戰術四角括號與機密條碼。
* **右頁（手札檔案與指揮官批示 Field Notes & Dossier）**：
  - 特工情報 / 四格分鏡起承轉合剖析。
  - 中英雙語對白逐句導讀與發言人徽章。
  - **👑 霸丸總指揮官（Jack 哥）親授手諭與紅色/金色批准印章（COMMAND APPROVED Stamp）**。
  - 幕後八卦花絮與彩蛋解析。

### 4. 角色視覺一致性鐵律 (Character Consistency Canon)
* **絕對錨定項（Invariants - 嚴禁隨意變更）**：五官長相、骨架體態、性別、瞳色、標誌性特徵（如小幽的清秀臉龐與眼神、小安的感知環、專屬肩章 UNIT 編號）。
* **動態放飛項（Dynamic Variants - 鼓勵極致潮流）**：服裝款式（高訂晚禮服/潮流私服/戰術運動裝）、精緻妝容、髮型配飾、微表情與光影環境。

### 5. 30 頁容量上限與自動分冊規則 (30-Page Volume Splitting Rule)
* **每本上限**：每本活頁冊/寫真冊以 **30 頁（30 Sheets / 30 Spreads）** 為物理裝訂最高上限 (`MAX_PAGES_PER_VOLUME = 30`)。
* **物理裝訂考量**：考量 22~25mm 活頁五金扣環所能容納之紙張厚度，避免紙張卡頓、破孔或翻閱變形損壞。
* **自動分冊機制 (Auto Volume Split)**：
  - 當內容（含封面、前言、正文、內頁插圖、封底）累計達到第 30 頁時，系統自動封閉當前冊。
  - 後續產出自動建立並銜接下一冊，例如：《日常生活篇 第一本》滿額後，自動續編《日常生活篇 第二本》（即 Vol. 01-B）。
  - 編目清單自動記錄頁數，超越 30 頁即刻發出警報提醒並自動分冊。

### 6. 擬真 3D 活頁翻頁互動規範 (Interactive 3D Page-Flip Experience - 翻頁感必備條款)
* **翻頁核心感官原則**：活頁冊與寫真冊**絕不可僅是靜態展示或簡單幻燈片**，線上數位端（`index.html`）必須給予讀者**「宛如雙手翻開厚實實體活頁夾」**的極致沉浸式翻頁體驗！
* **3D 空間透視與雙頁展開 (Spread Viewport)**：
  - 視角容器必須設置深層立體透視（`perspective: 2500px ~ 2600px`），以雙頁橫式（A4 Landscape 2-Page Spread）自然攤平展開。
  - 書體正中央必須貫穿擬真 6 孔或 4 孔 Chrome 白銀高光金屬扣環脊樑，具備金屬漸層反射、立體陰影與固定螺絲槽，兩側紙張必須具備精確 5.5mm 沖壓裝訂打孔（Punch Holes），呈現鐵環真實穿透紙張之物理立體感。
* **物理紙張翻頁動力學 (Page Turning Dynamics)**：
  - 翻頁時必須觸發 3D 掀頁翻轉物理動效（CSS 3D `rotateY` 翻轉），旋轉軸心緊貼中央金屬扣環脊樑。
  - 伴隨紙張翻起時的動態捲曲陰影（Curling Shadow Dynamics）與紙背遮蔽，模擬真實重磅塗佈紙翻動的慣性與弧度。
* **Web Audio 物理合成紙張沙沙音效 (Paper Swoosh Audio)**：
  - 必須內置 Web Audio API 物理合成器，翻頁瞬間即時演算輸出紙張摩擦空氣與微弱環扣共振之「沙沙～刷！」真實翻頁音效。
  - 具備 HUD 音效開關切換（預設開啟），完全不依賴外部 mp3 檔案，保證離線 100% 穩定發聲。
* **全維度無障礙操控交互**：
  - 點擊左頁翻上一頁、點擊右頁翻下一頁。
  - 鍵盤快速鍵支援：[←] / [→] 方向鍵、[空白鍵]、[PageUp] / [PageDown]、[Home] / [End]、[F] 全螢幕。
  - 底部配備平滑進度拉桿（Scrubber Slider）與動態指示器（如 `SPREAD 01 / 05`）。
  - 提供 Lightbox 高解析度圖片點擊放大功能。
* **全螢幕沉浸翻頁功能鍵規範 (In-Binder Fullscreen Integration - 必備功能)**：
  - **活頁夾本體常駐鍵**：活頁夾外框右上角必須內嵌常駐浮動【⛶ 全螢幕】快捷按鈕，讓讀者在翻頁時一鍵切換沉浸視野。
  - **翻頁控制列雙軌按鈕**：底端翻頁控制列右側必須配置獨立【⛶ 全螢幕】按鈕（與「下一頁 ▶」並列），無論視線在書本或控制台皆隨手可及。
  - **全螢幕自適應最大化**：進入全螢幕時，活頁書必須自動等比縮放最大化鋪滿視窗（`min(96vw, 1560px)` x `min(92vh, 880px)`），杜絕過小黑邊。
  - **雙態文字切換與 F 鍵快捷**：所有全螢幕按鈕依全螢幕狀態即時切換文字（`⛶ 全螢幕` ⇄ `🗗 退出全螢幕`），鍵盤按下 `F` / `f` 即刻切換。
* **雙軌輸出交付**：
  1. 線上互動 3D 活頁翻頁書（`index.html`）：極致沉浸把玩。
  2. 實體列印版（`binder_print.html` + PDF）：無損輸出裝訂。

---

## ⚡ 官方入冊觸發語體系 (Official Ingestion Trigger Phrases)

只要長官下達以下任一核心指令或口吻，特助小幫手必須自動啟動本技能全套自動化管線，無須反覆確認：

### 1. 【四格漫入冊】觸發語庫
* **標準語**：「四格漫入冊」、「四格漫畫入冊」、「漫畫入冊」、「四格動漫入冊」
* **情境擴展**：「把今天的事列入四格漫並入冊」、「把慶功宴做成四格漫入冊」
* **自動化執行動作**：
  1. 解析四格分鏡與中英起承轉合對白手札。
  2. 生成/提取四格漫畫圖片，自動歸類至目標卷冊（`01_日常生活篇`, `02_榮耀慶功篇`, `03_熱血賽事篇`）。
  3. 依據「至尊冊子格調總綱」組裝 5 跨頁標準活頁夾：
     - Sheet 1: 典藏封面
     - Sheet 2: 卷首戰況/工程史詩手札
     - Sheet 3: 四格動漫畫對開（左圖右文 + Jack 哥手諭與印章）
     - Sheet 4: 數據高光分析與全員致意看板
     - Sheet 5: 典藏封底
  4. 生成 `binder_print.html` 並調用 Playwright 輸出無損向量 PDF。
  5. 生成 3D 擬真活頁翻頁書 `index.html`（內建 6 孔 Chrome 活頁環、Web Audio 沙沙聲、外框右上角常駐【⛶ 全螢幕】與底端控制列雙全螢幕鍵、鍵盤快速鍵）。
  6. 自動校驗 30 頁物理裝訂上限，更新 `manga_manifest.json` 與頂層漫畫大廳 `index.html`。

### 2. 【拍照入冊】觸發語庫
* **標準語**：「拍照入冊」、「拍照入相冊」、「寫真入冊」、「照片入冊」
* **情境擴展**：「給小安拍張照入冊」、「今日足球奪冠合影拍照入冊」、「把戰報截圖拍照入冊」
* **自動化執行動作**：
  1. 鎖定特工立繪/合影/戰報照片，校驗特工五官骨架錨定規範。
  2. 自動命名並歸檔至 `11_📸_PHANTOMGRID_開源戰隊寫真相冊/`。
  3. 更新 `album_manifest.json`（補齊中英文生平、戰術代號與五維雷達數值）。
  4. 重新自動編譯 `build_phantomgrid_album.py`，同步刷新 3D 翻頁相簿 `index.html`、印刷頁 `album_print.html` 與 27MB 印刷級 PDF。

---

## 📖 至尊冊子格調總綱 (Canonical Loose-Leaf Binder Style Bible)

依據**首席工程師 / 霸丸總指揮官（Jack 哥）**最高軍令，未來 PHANTOMGRID 旗下所有動漫畫活頁冊、寫真冊與特刊，必須**100% 統一遵循以下八大格調標準**，徹底杜絕單頁散落或風格割裂：

1. **統一紙張規格**：標準 A4 橫式對開尺寸（`297mm x 210mm`，`@page { size: 297mm 210mm; margin: 0; }`）。
2. **五金擬真結構**：中央貫穿 22~24mm 六孔鍍鉻 Chrome 白銀活頁扣環，具備金屬漸層反射、頂層高光線條與深色下沉投影；兩側對開頁面必備 5.5mm 沖壓圓形裝訂孔（Punch Holes）與內陰影。
3. **沉浸式 3D 掀頁動力學**：線上數位端必須提供 `perspective: 2600px` 3D 空間透視，翻頁時帶動 `rotateY` 掀頁動態弧度與捲曲背影。
4. **Web Audio 物理紙張沙沙音效**：內建原生無相依音效合成器，翻頁瞬間演算輸出紙張摩擦空氣與金屬環共振之「SWOOSH」真實沙沙聲，預設開啟。
5. **雙全螢幕無死角控制**：活頁外框右上角常駐【⛶ 全螢幕】膠囊按鈕，底端控制列右側常駐獨立【⛶ 全螢幕】按鈕，支援鍵盤 `F` 鍵一秒切換，全螢幕時自動等比放大鋪滿視窗。
6. **對開黃金佈局**：
   - 左頁為視覺中心（滿版高清四格動漫或角色寫真）。
   - 右頁為情報手札（分鏡詳解、中英對白、👑 霸丸總指揮官手諭、Approved 鋼印章）。
7. **標準 5 跨頁完備結構**：
   - Sheet 1: 典藏封面 (主題色彩漸層、封面大標、副標、3 欄統帥與特助檔案)
   - Sheet 2: 卷首史詩對開 (戰役手札 / 特工花名冊)
   - Sheet 3: 四格動漫畫對開 (主視覺與長官手諭)
   - Sheet 4: 高光數據看板 (賽後技術統計 / 特助手記 / 特工致敬)
   - Sheet 5: 典藏封底 (防偽標章、零桌面污染聲明、總成本 $0.00 USD)
8. **嚴格裝訂與安全鐵律**：
   - 每本上限 30 頁，滿 30 頁自動封閉並增開新卷（如 Vol 01-B）。
   - 恪守 Zero-Desktop Pollution，全量成果儲存於總庫，禁止外溢至本機桌面。
   - 商業成本永遠維持 $0.00 USD。

---

## 自動化輸出管線 (Automation Toolchain)

本技能提供全自動雙版本同步輸出：

1. **版本一：網頁互動 3D 翻頁相簿 / 條漫閱覽大典**
   - Web Audio API 原生擬真紙質翻頁聲效。
   - 點擊 Lightbox 高清全螢幕檢視。
   - 響應式手機/桌面自適應與 HUD 互動按鈕。

2. **版本二：印刷級 A4 橫式對開高畫質 PDF**
   - 調用 Playwright Chromium 引擎進行像素級渲染。
   - 執行參數：prefer_css_page_size=True, print_background=True。

---

## 相關參考與腳本
* 參閱四格漫自動入冊腳本：[四格漫入冊引擎](./scripts/ingest_manga_binder.py)
* 參閱寫真相冊自動入冊腳本：[拍照入冊引擎](./scripts/ingest_photo_lookbook.py)
* 參閱詳細規格書：[規格指南與參數手冊](./references/SPEC_GUIDELINES.md)
* 參閱相冊建置腳本：[寫真相冊建置器](./scripts/build_lookbook.py)
* 參閱活頁冊建置腳本：[活頁漫畫建置器](./scripts/build_binder.py)
