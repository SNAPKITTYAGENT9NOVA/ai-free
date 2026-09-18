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
* 參閱詳細規格書：[規格指南與參數手冊](./references/SPEC_GUIDELINES.md)
* 參閱相冊建置腳本：[寫真相冊建置器](./scripts/build_lookbook.py)
* 參閱活頁冊建置腳本：[活頁漫畫建置器](./scripts/build_binder.py)
