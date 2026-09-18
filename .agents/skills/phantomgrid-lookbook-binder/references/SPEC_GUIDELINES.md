# PHANTOMGRID 相冊與活頁冊工程規格詳細指南

## 1. CSS 印刷樣式規格

`css
@page {
  size: 297mm 210mm; /* A4 Landscape */
  margin: 0;
}

body {
  font-family: 'Segoe UI', 'PingFang TC', 'Microsoft JhengHei', sans-serif;
  background: #060910;
  color: #f8fafc;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}

.sheet {
  width: 297mm;
  height: 210mm;
  page-break-after: always;
  display: flex;
  position: relative;
  overflow: hidden;
  background: #080d18;
}
`

## 2. 活頁五金環與沖孔參數

`css
/* 中央金屬活頁脊 */
.binder-spine {
  position: absolute;
  top: 0; bottom: 0; left: 50%;
  transform: translateX(-50%);
  width: 24mm;
  z-index: 100;
  display: flex;
  flex-direction: column;
  justify-content: space-evenly;
  align-items: center;
  background: linear-gradient(90deg, rgba(0,0,0,0.6) 0%, rgba(255,255,255,0.08) 50%, rgba(0,0,0,0.6) 100%);
  border-left: 1px solid rgba(255,255,255,0.08);
  border-right: 1px solid rgba(255,255,255,0.08);
}

/* Chrome 鍍鉻金屬活頁環 */
.ring {
  width: 18mm;
  height: 6mm;
  background: linear-gradient(180deg, #94a3b8 0%, #f8fafc 40%, #64748b 70%, #1e293b 100%);
  border-radius: 3mm;
  box-shadow: 0 2px 8px rgba(0,0,0,0.9), inset 0 1px 2px #fff;
  position: relative;
}

/* 沖孔 */
.hole-left, .hole-right {
  width: 5.5mm;
  height: 5.5mm;
  border-radius: 50%;
  background: #04060a;
  border: 1px solid rgba(255,255,255,0.2);
  box-shadow: inset 0 1px 4px rgba(0,0,0,0.9);
}
`

## 3. Playwright 渲染參數

`python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page()
    page.goto(html_uri)
    page.wait_for_timeout(2000)
    page.pdf(
        path=output_pdf_path,
        width='297mm',
        height='210mm',
        print_background=True,
        prefer_css_page_size=True
    )
    browser.close()
```

## 4. 30 頁分卷容量控制標準 (30-Page Capacity Protocol)

* 每本冊子物理上限：`MAX_PAGES_PER_VOLUME = 30`。
* 涵蓋範圍：封面、前言、目錄、跨頁內頁、封底，總頁數不可超過 30 頁。
* 當累計頁數到達 30 頁時，自動封版當前冊，並創建下一分卷（Volume Split），確保活頁環不會過載。

## 5. 3D 擬真活頁翻頁互動規格 (Interactive 3D Flipbook & Audio Mechanics)

* **翻頁核心感官原則**：線上互動版（`index.html`）必須給予使用者極致逼真的實體翻頁體感。
* **3D 空間透視與翻頁旋轉**：
  ```css
  .book-viewport {
    perspective: 2600px;
  }
  .flip-leaf {
    transform-style: preserve-3d;
    transform-origin: left center; /* 緊貼中央活頁脊樑 */
    animation: turnPageForward 0.65s cubic-bezier(0.25, 1, 0.5, 1) forwards;
  }
  ```
* **紙張捲曲陰影動效**：翻頁中途伴隨陰影加深至 `rgba(0,0,0,0.8)` 與亮度阻尼，落地平展時平滑回歸。
* **Web Audio API 擬真音訊合成**：
  ```javascript
  // 物理合成真實紙張摩擦空氣聲（粉紅噪聲 + 帶通/低通濾波 + 指數衰減）
  const buffer = audioCtx.createBuffer(1, bufferSize, audioCtx.sampleRate);
  // lowpass filter 1200Hz -> 280Hz, gain decay 0.32 -> 0.01 in 180ms
  ```
* **全功能操控**：點擊左右頁、鍵盤方向鍵 [← / →] / 空白鍵、滑桿直達頁面、全螢幕切換與高解析度 Lightbox 檢視。

