import os
import json
import base64
from pathlib import Path
from playwright.sync_api import sync_playwright

BASE_DIR = r"G:\我的雲端硬碟\AI產出成品總庫\12_🎨_PHANTOMGRID_戰隊四格漫畫專區"
V1_DIR = os.path.join(BASE_DIR, "01_日常生活篇")
OUTPUT_PDF = os.path.join(V1_DIR, "《PHANTOMGRID幻網戰隊・四格動漫畫》第一本_日常生活篇_活頁典藏大典.pdf")
PRINT_HTML = os.path.join(V1_DIR, "binder_print.html")
INDEX_HTML = os.path.join(V1_DIR, "index.html")

def get_base64_image(image_path):
    if not os.path.exists(image_path):
        return ""
    with open(image_path, "rb") as f:
        data = base64.b64encode(f.read()).decode("utf-8")
    ext = os.path.splitext(image_path)[1].lower()
    mime = "image/jpeg" if ext in [".jpg", ".jpeg"] else "image/png"
    return f"data:{mime};base64,{data}"

def build_binder():
    ep01_img_path = os.path.join(V1_DIR, "EP01_時尚與隱形.jpg")
    ep01_b64 = get_base64_image(ep01_img_path)
    
    # 1. Generate Print HTML (A4 Landscape Spreads with Loose-Leaf Ring Binder)
    print_html_content = f"""<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<title>PHANTOMGRID 四格動漫畫 第一本：日常生活篇 —— 活頁印刷典藏大典</title>
<style>
@page {{
  size: 297mm 210mm;
  margin: 0;
}}
* {{ box-sizing: border-box; margin: 0; padding: 0; }}
body {{
  font-family: 'Segoe UI', 'PingFang TC', 'Microsoft JhengHei', sans-serif;
  background: #060910;
  color: #f8fafc;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}}
.sheet {{
  width: 297mm;
  height: 210mm;
  page-break-after: always;
  display: flex;
  position: relative;
  overflow: hidden;
  background: #080d18;
}}

/* Binder Spine & Chrome Rings */
.binder-spine {{
  position: absolute;
  top: 0;
  bottom: 0;
  left: 50%;
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
}}
.ring {{
  width: 18mm;
  height: 6mm;
  background: linear-gradient(180deg, #94a3b8 0%, #f8fafc 40%, #64748b 70%, #1e293b 100%);
  border-radius: 3mm;
  box-shadow: 0 2px 8px rgba(0,0,0,0.9), inset 0 1px 2px #fff;
  position: relative;
}}
.ring::after {{
  content: '';
  position: absolute;
  top: 1.5mm; left: 2mm; right: 2mm; height: 1.5mm;
  background: rgba(255,255,255,0.6);
  border-radius: 1mm;
}}

/* Half Page */
.half {{
  width: 50%;
  height: 100%;
  padding: 12mm 15mm;
  position: relative;
  display: flex;
  flex-direction: column;
}}
.half-left {{
  background: linear-gradient(135deg, #090e1a 0%, #0d1526 100%);
  padding-right: 18mm;
  border-right: 1px dashed rgba(255,255,255,0.1);
}}
.half-right {{
  background: linear-gradient(135deg, #0d1526 0%, #111a2f 100%);
  padding-left: 18mm;
  border-left: 1px dashed rgba(255,255,255,0.1);
}}

/* Punch Holes */
.hole-left {{
  position: absolute;
  right: 4mm;
  width: 5.5mm; height: 5.5mm;
  border-radius: 50%;
  background: #04060a;
  border: 1px solid rgba(255,255,255,0.2);
  box-shadow: inset 0 1px 4px rgba(0,0,0,0.9);
}}
.hole-right {{
  position: absolute;
  left: 4mm;
  width: 5.5mm; height: 5.5mm;
  border-radius: 50%;
  background: #04060a;
  border: 1px solid rgba(255,255,255,0.2);
  box-shadow: inset 0 1px 4px rgba(0,0,0,0.9);
}}

/* Cover Styling */
.cover-sheet {{
  background: radial-gradient(circle at center, #10192e 0%, #060911 100%);
  justify-content: center;
  align-items: center;
  flex-direction: column;
}}
.cover-border {{
  width: 275mm;
  height: 188mm;
  border: 2px solid rgba(0, 242, 254, 0.4);
  border-radius: 8mm;
  position: relative;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  padding: 16mm;
  background: rgba(14, 21, 38, 0.7);
  box-shadow: 0 0 40px rgba(0,0,0,0.9);
}}
.cover-tag {{
  background: linear-gradient(90deg, #00f2fe, #9d4edd);
  color: #000;
  font-weight: 900;
  font-size: 13px;
  padding: 4px 18px;
  border-radius: 4px;
  letter-spacing: 2px;
  margin-bottom: 8mm;
}}
.cover-title {{
  font-size: 32px;
  font-weight: 900;
  letter-spacing: 3px;
  background: linear-gradient(90deg, #fff 0%, #00f2fe 50%, #f5a623 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 4mm;
  text-align: center;
}}
.cover-sub {{
  font-size: 19px;
  color: #9d4edd;
  font-weight: 700;
  letter-spacing: 4px;
  margin-bottom: 8mm;
}}
.cover-meta-grid {{
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8mm;
  width: 220mm;
  margin-top: 8mm;
  border-top: 1px solid rgba(255,255,255,0.1);
  padding-top: 6mm;
}}
.cover-meta-item {{
  text-align: center;
}}
.cover-meta-label {{
  font-size: 10px;
  color: #64748b;
  letter-spacing: 1px;
}}
.cover-meta-val {{
  font-size: 13px;
  font-weight: 700;
  color: #f8fafc;
  margin-top: 2px;
}}

/* Comic Spread */
.spread-header {{
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid rgba(0, 242, 254, 0.3);
  padding-bottom: 2.5mm;
  margin-bottom: 3.5mm;
}}
.spread-tag {{
  font-size: 10px;
  color: #00f2fe;
  font-weight: 800;
  letter-spacing: 1px;
}}
.spread-num {{
  font-size: 10px;
  color: #94a3b8;
}}
.comic-frame {{
  flex: 1;
  display: flex;
  justify-content: center;
  align-items: center;
  border-radius: 4mm;
  overflow: hidden;
  background: #000;
  border: 1px solid rgba(255,255,255,0.1);
}}
.comic-frame img {{
  max-width: 100%;
  max-height: 168mm;
  object-fit: contain;
  display: block;
}}

/* Right Notes Sheet */
.notes-container {{
  display: flex;
  flex-direction: column;
  gap: 2.5mm;
  height: 100%;
}}
.panel-note {{
  background: rgba(255, 255, 255, 0.03);
  border-left: 2.5px solid #00f2fe;
  padding: 2.5mm 3.5mm;
  border-radius: 0 2mm 2mm 0;
}}
.panel-note.p2 {{ border-left-color: #9d4edd; }}
.panel-note.p3 {{ border-left-color: #ff5e7e; }}
.panel-note.p4 {{ border-left-color: #f5a623; }}

.panel-note-head {{
  display: flex;
  justify-content: space-between;
  font-size: 10px;
  font-weight: 800;
  color: #94a3b8;
  margin-bottom: 1mm;
}}
.panel-note-speaker {{
  color: #fff;
  font-weight: 700;
}}
.panel-note-zh {{
  font-size: 11px;
  line-height: 1.45;
  color: #e2e8f0;
}}
.panel-note-en {{
  font-size: 9px;
  color: #64748b;
  font-style: italic;
}}

/* Commander Stamp */
.commander-decree-box {{
  margin-top: auto;
  background: rgba(245, 166, 35, 0.06);
  border: 1px solid rgba(245, 166, 35, 0.3);
  border-radius: 3mm;
  padding: 3mm 4mm;
  position: relative;
}}
.stamp-seal {{
  position: absolute;
  right: 4mm;
  bottom: 2mm;
  border: 1.5px solid #f5a623;
  color: #f5a623;
  padding: 1mm 3mm;
  font-size: 9px;
  font-weight: 900;
  border-radius: 1mm;
  transform: rotate(-5deg);
  opacity: 0.85;
}}
.decree-title {{
  font-size: 10px;
  font-weight: 800;
  color: #f5a623;
  letter-spacing: 1px;
  margin-bottom: 1mm;
}}
.decree-text {{
  font-size: 10.5px;
  color: #f8fafc;
  line-height: 1.4;
}}
</style>
</head>
<body>

<!-- SHEET 1: 活頁封面 -->
<div class="sheet cover-sheet">
  <div class="cover-border">
    <div class="cover-tag">OFFICIAL LOOSE-LEAF COMIC BINDER // 官方活頁典藏冊</div>
    <div class="cover-title">PHANTOMGRID 幻網戰隊・四格動漫畫大典</div>
    <div class="cover-sub">第一本：日常生活篇（VOL. 01 BASE LIFE）</div>
    <p style="font-size: 12.5px; color: #94a3b8; max-width: 170mm; text-align: center; line-height: 1.6;">
      本活頁冊遵循最高統帥軍令規範：特工五官面貌與骨架體態永久錨定，日常服裝妝容允許極致潮流與百變風格！真實收錄第二辦公室點滴、基地換裝、特工反差萌爆笑現場。
    </p>
    <div class="cover-meta-grid">
      <div class="cover-meta-item">
        <div class="cover-meta-label">SUPREME COMMANDER</div>
        <div class="cover-meta-val">👑 霸丸總指揮官（Jack 哥）</div>
      </div>
      <div class="cover-meta-item">
        <div class="cover-meta-label">CHIEF CHRONICLER</div>
        <div class="cover-meta-val">🌸 特助小幫手（Ping Assistant）</div>
      </div>
      <div class="cover-meta-item">
        <div class="cover-meta-label">SPECIFICATION</div>
        <div class="cover-meta-val">A4 橫式對開活頁相冊規格</div>
      </div>
    </div>
  </div>
</div>

<!-- SHEET 2: 第 1 話 對開跨頁 (左頁四格漫畫 + 中間金屬活頁環 + 右頁手札解析與長官批示) -->
<div class="sheet">
  <!-- Central Ring Binder Spine -->
  <div class="binder-spine">
    <div class="ring"></div>
    <div class="ring"></div>
    <div class="ring"></div>
    <div class="ring"></div>
    <div class="ring"></div>
    <div class="ring"></div>
  </div>

  <!-- Left Page: Manga Art -->
  <div class="half half-left">
    <!-- Punch Holes on left page right edge -->
    <div class="hole-left" style="top: 15%;"></div>
    <div class="hole-left" style="top: 32%;"></div>
    <div class="hole-left" style="top: 50%;"></div>
    <div class="hole-left" style="top: 68%;"></div>
    <div class="hole-left" style="top: 85%;"></div>

    <div class="spread-header">
      <div class="spread-tag">VOL.01 BASE LIFE // EPISODE 01</div>
      <div class="spread-num">PAGE 02 // 03</div>
    </div>
    <div class="comic-frame">
      <img src="{ep01_b64}" alt="EP01 時尚與隱形">
    </div>
  </div>

  <!-- Right Page: Field Notes & Commander Stamp -->
  <div class="half half-right">
    <!-- Punch Holes on right page left edge -->
    <div class="hole-right" style="top: 15%;"></div>
    <div class="hole-right" style="top: 32%;"></div>
    <div class="hole-right" style="top: 50%;"></div>
    <div class="hole-right" style="top: 68%;"></div>
    <div class="hole-right" style="top: 85%;"></div>

    <div class="spread-header">
      <div class="spread-tag">MISSION DOSSIER // SCENE BREAKDOWN</div>
      <div class="spread-num">LOOSE-LEAF ENTRY #001</div>
    </div>

    <div class="notes-container">
      <h3 style="font-size: 14px; color: #00f2fe; margin-bottom: 1mm;">第 1 話：特工的時尚與隱形</h3>
      <p style="font-size: 10.5px; color: #94a3b8; margin-bottom: 2mm;">
        【故事梗概】Jack 哥於第二辦公室頒布最高軍規，小幽興奮展現親自設計之 LED 柔光晚禮服，卻因害羞觸發深潛匿蹤，引發全場「洋裝飄在空中喝珍奶」之爆笑名場面。
      </p>

      <div class="panel-note">
        <div class="panel-note-head"><span>第 1 格【起・基地最高軍令】</span><span class="panel-note-speaker">👑 Jack 哥 & 🌸 小幫手</span></div>
        <div class="panel-note-zh">「全體注意！基地新規矩：未經授權禁止私改匿蹤裝備！」小幫手在旁勤奮筆記。</div>
        <div class="panel-note-en">"ATTENTION TEAM! NEW BASE RULE: NO UNAUTHORIZED MODIFICATIONS TO STEALTH GEAR!"</div>
      </div>

      <div class="panel-note p2">
        <div class="panel-note-head"><span>第 2 格【承・炫耀時尚新洋裝】</span><span class="panel-note-speaker">🦎 小幽 (Agent Chameleon)</span></div>
        <div class="panel-note-zh">「搭啦！看我這件內建 LED 柔光電路的自訂新洋裝！是不是超可愛！」隊員歡呼鼓掌。</div>
        <div class="panel-note-en">"TADA! Look at my new custom gown with built-in LED circuits! It's SO cute!"</div>
      </div>

      <div class="panel-note p3">
        <div class="panel-note-head"><span>第 3 格【轉・特工本能大暴走】</span><span class="panel-note-speaker">🦎 小幽 & 😱 全體隊員</span></div>
        <div class="panel-note-zh">「糟糕！不小心啟動了！」肉身全隱形，只剩洋裝浮在半空拿著珍珠奶茶！隊員嚇到冒汗：「洋裝自己活過來了！」</div>
        <div class="panel-note-en">"OH NO! Accidental trigger!" "EHH?! SHE DISAPPEARED! THE DRESS IS ALIVE!"</div>
      </div>

      <div class="panel-note p4">
        <div class="panel-note-head"><span>第 4 格【合・指揮官淡定吐槽】</span><span class="panel-note-speaker">☕ Jack 哥 (端著PG咖啡杯)</span></div>
        <div class="panel-note-zh">「規矩適用於未經授權的啟動，小幽。」小幽解除隱形紅著臉抓頭道歉。</div>
        <div class="panel-note-en">"Rules apply to unauthorized use, Xiao You." "Ugh... My mistake, Commander! It just... activated!"</div>
      </div>

      <!-- Commander Decree Stamp -->
      <div class="commander-decree-box">
        <div class="stamp-seal">COMMAND APPROVED</div>
        <div class="decree-title">👑 霸丸總指揮官（Jack 哥）親授準則手諭</div>
        <div class="decree-text">
          「全體特工 BODY 骨架面容定裝鎖死，服裝妝容允許極致潮流與百變風格！此活頁手札即刻歸檔列管，後續生活點滴按此相冊規格連續編號抽換！」
        </div>
      </div>
    </div>
  </div>
</div>

<!-- SHEET 3: 活頁封底 -->
<div class="sheet cover-sheet">
  <div class="cover-border" style="height: 155mm;">
    <div class="cover-tag">PHANTOMGRID BINDER BACK COVER</div>
    <h2 style="font-size: 20px; color: #fff; margin-bottom: 3mm;">《日常生活篇》活頁第一卷・待續</h2>
    <p style="font-size: 12px; color: #94a3b8; max-width: 150mm; text-align: center; line-height: 1.6; margin-bottom: 6mm;">
      本冊為活動式活頁相冊規格，未來只要指揮官頒布新生活日常，隨時可無縫插入新活頁跨頁！<br>
      100% Zero-Desktop Pollution // Total Cost: $0.00 USD
    </p>
    <div style="color: #00f2fe; font-size: 11px; letter-spacing: 2px;">
      PHANTOMGRID AGENTS ARCHIVE // LOOSE-LEAF SPECIFICATION
    </div>
  </div>
</div>

</body>
</html>"""

    with open(PRINT_HTML, "w", encoding="utf-8") as f:
        f.write(print_html_content)
    print("Binder Print HTML generated successfully!")

    # 2. Render PDF via Playwright
    print("Rendering Loose-Leaf PDF via Playwright...")
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto(Path(PRINT_HTML).as_uri())
        page.wait_for_timeout(2000)
        page.pdf(
            path=OUTPUT_PDF,
            width="297mm",
            height="210mm",
            print_background=True,
            prefer_css_page_size=True
        )
        browser.close()
    print("Loose-Leaf PDF generated successfully:", OUTPUT_PDF)

if __name__ == "__main__":
    build_binder()
