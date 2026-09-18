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
`
