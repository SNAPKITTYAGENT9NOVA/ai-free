import os
import json
import base64
import mimetypes
from playwright.sync_api import sync_playwright

ALBUM_DIR = r"G:\我的雲端硬碟\AI產出成品總庫\11_📸_PHANTOMGRID_開源戰隊寫真相冊"
MANIFEST_FILE = os.path.join(ALBUM_DIR, "album_manifest.json")
INDEX_HTML = os.path.join(ALBUM_DIR, "index.html")
PRINT_HTML = os.path.join(ALBUM_DIR, "album_print.html")
OUTPUT_PDF = os.path.join(ALBUM_DIR, "《開源・幻網紀元》PHANTOMGRID全球獨立體AGENTS官方典藏寫真大典.pdf")

def load_manifest():
    with open(MANIFEST_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def generate_interactive_html(manifest):
    meta = manifest["meta"]
    roster = manifest["roster"]
    special_pages = manifest["special_pages"]
    
    # We will build pages. Each page has a number.
    # Page 1: Cover
    # Page 2: Foreword (統帥卷首語)
    # Page 3: Table of Contents (大典目錄)
    # Page 4..N: Member Spreads (Left photo + Right bio)
    # Special pages: Epic Victories & Base Architecture
    # Last Page: Back Cover (封底)
    
    pages_json = []
    
    # Page 1: Cover
    pages_json.append({
        "type": "cover",
        "title": meta["title"],
        "subtitle": meta["subtitle"],
        "english_title": meta["english_title"],
        "english_subtitle": meta["english_subtitle"],
        "commander": meta["commander"],
        "chief_editor": meta["chief_editor"],
        "version": meta["version"],
        "date": meta["date"],
        "logo": "PHANTOMGRID_官方最高代表圖騰_正統印記.png",
        "flag": "PHANTOMGRID_戰隊官方旗號大軍旗.png"
    })
    
    # Page 2: Foreword
    pages_json.append({
        "type": "foreword",
        "title": "統帥成軍題詞與卷首史詩",
        "english": "SUPREME COMMAND DECREE & GENESIS FOREWORD",
        "motto": meta["motto"],
        "decree": meta["decree"],
        "flag": "PHANTOMGRID_戰隊官方旗號大軍旗.png",
        "banner": "PHANTOMGRID_官方賽事橫式大會旗標_Banner.png"
    })
    
    # Page 3: TOC
    pages_json.append({
        "type": "toc",
        "title": "大典總目錄導覽",
        "english": "TABLE OF CONTENTS // SPREAD INDEX",
        "sections": manifest["sections"]
    })
    
    # Character spreads
    for m in roster:
        pages_json.append({
            "type": "member",
            "data": m
        })
        
    # Special pages
    for sp in special_pages:
        pages_json.append({
            "type": "special",
            "data": sp
        })
        
    # Back Cover
    pages_json.append({
        "type": "back_cover",
        "title": meta["title"],
        "subtitle": meta["subtitle"],
        "logo": "PHANTOMGRID_官方賽事獨立圖騰徽章.png",
        "banner": "PHANTOMGRID_官方賽事橫式大會旗標_Banner.png"
    })
    
    html_content = f"""<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{meta['title']} —— {meta['subtitle']}</title>
<style>
:root {{
  --bg-space: #060910;
  --bg-page-left: #0b111e;
  --bg-page-right: #0f172a;
  --gold-primary: #f59e0b;
  --gold-light: #fef3c7;
  --cyan-glow: #00f2fe;
  --cyan-subtle: #06b6d4;
  --text-main: #f8fafc;
  --text-muted: #94a3b8;
  --border-hud: rgba(0, 242, 254, 0.25);
  --border-gold: rgba(245, 158, 11, 0.35);
}}

* {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}}

body {{
  font-family: 'Segoe UI', 'PingFang TC', 'Microsoft JhengHei', sans-serif;
  background-color: var(--bg-space);
  color: var(--text-main);
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  overflow-x: hidden;
  background-image: 
    radial-gradient(circle at 50% 20%, rgba(0, 242, 254, 0.08) 0%, transparent 50%),
    radial-gradient(circle at 80% 80%, rgba(245, 158, 11, 0.05) 0%, transparent 50%),
    linear-gradient(rgba(255, 255, 255, 0.02) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255, 255, 255, 0.02) 1px, transparent 1px);
  background-size: 100% 100%, 100% 100%, 40px 40px, 40px 40px;
}}

/* Top HUD Header */
.top-hud {{
  width: 100%;
  max-width: 1400px;
  padding: 14px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid var(--border-hud);
  background: rgba(11, 17, 30, 0.85);
  backdrop-filter: blur(12px);
  z-index: 100;
}}

.hud-title-group {{
  display: flex;
  align-items: center;
  gap: 12px;
}}

.hud-badge {{
  background: rgba(245, 158, 11, 0.15);
  border: 1px solid var(--gold-primary);
  color: var(--gold-primary);
  padding: 3px 8px;
  border-radius: 4px;
  font-size: 0.75rem;
  font-weight: 700;
  letter-spacing: 1px;
}}

.hud-main-title {{
  font-size: 1.15rem;
  font-weight: 800;
  background: linear-gradient(135deg, #fff 40%, var(--gold-primary) 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  letter-spacing: 0.5px;
}}

.hud-controls {{
  display: flex;
  align-items: center;
  gap: 12px;
}}

.btn-hud {{
  background: rgba(15, 23, 42, 0.8);
  border: 1px solid var(--border-hud);
  color: var(--cyan-glow);
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 0.85rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.25s ease;
  display: flex;
  align-items: center;
  gap: 6px;
}}

.btn-hud:hover {{
  background: rgba(0, 242, 254, 0.15);
  border-color: var(--cyan-glow);
  box-shadow: 0 0 12px rgba(0, 242, 254, 0.4);
  color: #fff;
  transform: translateY(-1px);
}}

/* Main Book Viewport */
.book-viewport {{
  flex: 1;
  width: 100%;
  max-width: 1400px;
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 24px 16px;
  perspective: 2500px;
}}

.book-container {{
  width: 1200px;
  height: 720px;
  display: flex;
  box-shadow: 
    0 25px 50px -12px rgba(0, 0, 0, 0.85),
    0 0 40px rgba(0, 242, 254, 0.15),
    inset 0 0 20px rgba(0, 0, 0, 0.9);
  border-radius: 12px;
  position: relative;
  background: #080d18;
  border: 1px solid rgba(0, 242, 254, 0.3);
  overflow: hidden;
  transition: transform 0.4s ease;
}}

/* Book Spine Center Divider */
.book-container::after {{
  content: '';
  position: absolute;
  top: 0;
  bottom: 0;
  left: 50%;
  width: 16px;
  transform: translateX(-50%);
  background: linear-gradient(90deg, 
    rgba(0,0,0,0.6) 0%, 
    rgba(0,0,0,0.1) 25%, 
    rgba(255,255,255,0.05) 50%, 
    rgba(0,0,0,0.1) 75%, 
    rgba(0,0,0,0.6) 100%);
  z-index: 50;
  pointer-events: none;
  box-shadow: 0 0 10px rgba(0,0,0,0.8);
}}

/* Left & Right Page Spreads */
.page-spread {{
  width: 50%;
  height: 100%;
  padding: 36px 40px;
  position: relative;
  overflow: hidden;
  display: flex;
  flex-direction: column;
}}

.page-left {{
  background: linear-gradient(135deg, #0a101d 0%, #0d1527 100%);
  border-right: 1px solid rgba(255, 255, 255, 0.05);
}}

.page-right {{
  background: linear-gradient(135deg, #0d1527 0%, #111a30 100%);
}}

/* Page Corner Accents (PHANTOMGRID HUD) */
.hud-corner-tl {{ position: absolute; top: 12px; left: 12px; width: 14px; height: 14px; border-top: 2px solid var(--cyan-glow); border-left: 2px solid var(--cyan-glow); }}
.hud-corner-tr {{ position: absolute; top: 12px; right: 12px; width: 14px; height: 14px; border-top: 2px solid var(--cyan-glow); border-right: 2px solid var(--cyan-glow); }}
.hud-corner-bl {{ position: absolute; bottom: 12px; left: 12px; width: 14px; height: 14px; border-bottom: 2px solid var(--cyan-glow); border-left: 2px solid var(--cyan-glow); }}
.hud-corner-br {{ position: absolute; bottom: 12px; right: 12px; width: 14px; height: 14px; border-bottom: 2px solid var(--cyan-glow); border-right: 2px solid var(--cyan-glow); }}

/* Member Image Container (Left Page) */
.hero-image-box {{
  flex: 1;
  width: 100%;
  border-radius: 8px;
  border: 1px solid var(--border-hud);
  overflow: hidden;
  position: relative;
  box-shadow: 0 10px 30px rgba(0,0,0,0.6);
  cursor: zoom-in;
  background: #050811;
  display: flex;
  align-items: center;
  justify-content: center;
}}

.hero-image-box img {{
  width: 100%;
  height: 100%;
  object-fit: cover;
  transition: transform 0.4s ease;
}}

.hero-image-box:hover img {{
  transform: scale(1.03);
}}

.image-overlay-badge {{
  position: absolute;
  top: 14px;
  left: 14px;
  background: rgba(6, 11, 22, 0.85);
  border: 1px solid var(--border-gold);
  color: var(--gold-primary);
  padding: 4px 10px;
  border-radius: 4px;
  font-size: 0.72rem;
  font-weight: 700;
  letter-spacing: 1px;
  backdrop-filter: blur(8px);
}}

.image-tech-metadata {{
  position: absolute;
  bottom: 12px;
  right: 12px;
  background: rgba(6, 11, 22, 0.85);
  border: 1px solid var(--border-hud);
  color: var(--cyan-glow);
  padding: 4px 10px;
  border-radius: 4px;
  font-size: 0.68rem;
  font-family: monospace;
  letter-spacing: 1px;
}}

/* Right Page Content Styling (Magazine / Dossier Layout) */
.dossier-header {{
  border-bottom: 2px solid var(--border-hud);
  padding-bottom: 14px;
  margin-bottom: 18px;
  position: relative;
}}

.dossier-id-row {{
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 6px;
}}

.dossier-id {{
  font-family: monospace;
  font-size: 0.95rem;
  color: var(--cyan-glow);
  font-weight: 700;
  letter-spacing: 2px;
}}

.dossier-clearance {{
  font-size: 0.7rem;
  font-weight: 800;
  color: var(--gold-primary);
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid var(--gold-primary);
  padding: 2px 8px;
  border-radius: 4px;
  letter-spacing: 1px;
}}

.dossier-name-row {{
  display: flex;
  align-items: baseline;
  gap: 12px;
}}

.dossier-name {{
  font-size: 1.9rem;
  font-weight: 900;
  color: #fff;
  letter-spacing: 1px;
}}

.dossier-codename {{
  font-size: 1rem;
  color: var(--cyan-subtle);
  font-weight: 600;
  font-family: monospace;
}}

.dossier-title-division {{
  margin-top: 6px;
  font-size: 0.85rem;
  color: var(--text-muted);
  display: flex;
  flex-direction: column;
  gap: 3px;
}}

.dossier-title-division span.division {{
  color: var(--gold-primary);
  font-weight: 600;
}}

/* Quote Banner */
.dossier-quote-box {{
  background: rgba(0, 242, 254, 0.05);
  border-left: 3px solid var(--cyan-glow);
  padding: 12px 16px;
  border-radius: 0 6px 6px 0;
  margin-bottom: 16px;
  font-style: italic;
  font-size: 0.9rem;
  line-height: 1.5;
  color: #e2e8f0;
}}

/* Bio Text */
.dossier-bio {{
  font-size: 0.84rem;
  line-height: 1.65;
  color: #cbd5e1;
  margin-bottom: 18px;
  text-align: justify;
}}

/* Stats Grid */
.dossier-stats-grid {{
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: auto;
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  padding-top: 14px;
}}

.stat-item {{
  background: rgba(15, 23, 42, 0.6);
  padding: 8px 12px;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.05);
}}

.stat-label-row {{
  display: flex;
  justify-content: space-between;
  font-size: 0.75rem;
  margin-bottom: 4px;
  color: var(--text-muted);
}}

.stat-value {{
  color: var(--gold-primary);
  font-weight: 700;
  font-family: monospace;
}}

.stat-bar-bg {{
  width: 100%;
  height: 4px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 2px;
  overflow: hidden;
}}

.stat-bar-fill {{
  height: 100%;
  background: linear-gradient(90deg, var(--cyan-subtle), var(--gold-primary));
  border-radius: 2px;
}}

/* Footer / Page Number */
.spread-footer {{
  margin-top: 10px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.7rem;
  color: rgba(148, 163, 184, 0.6);
  font-family: monospace;
}}

/* Cover Page Layout */
.cover-spread {{
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: 40px;
  background: radial-gradient(circle at center, #111b33 0%, #060910 80%);
  position: relative;
}}

.cover-logo {{
  max-width: 180px;
  max-height: 180px;
  margin-bottom: 24px;
  filter: drop-shadow(0 0 25px rgba(0, 242, 254, 0.5));
}}

.cover-title {{
  font-size: 3.2rem;
  font-weight: 900;
  letter-spacing: 4px;
  background: linear-gradient(135deg, #ffffff 20%, var(--gold-primary) 80%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 12px;
}}

.cover-subtitle {{
  font-size: 1.25rem;
  color: var(--cyan-glow);
  letter-spacing: 2px;
  margin-bottom: 8px;
  font-weight: 600;
}}

.cover-english {{
  font-size: 0.85rem;
  color: var(--text-muted);
  letter-spacing: 3px;
  font-family: monospace;
  margin-bottom: 36px;
}}

.cover-footer-meta {{
  margin-top: auto;
  display: flex;
  gap: 30px;
  font-size: 0.8rem;
  color: var(--gold-light);
  border-top: 1px solid var(--border-gold);
  padding-top: 16px;
  letter-spacing: 1px;
}}

/* Special Full Spreads (Epic Victories / Fleet) */
.special-spread {{
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
}}

.special-image-box {{
  flex: 1;
  border-radius: 8px;
  overflow: hidden;
  border: 1px solid var(--border-hud);
  position: relative;
  box-shadow: 0 10px 30px rgba(0,0,0,0.7);
  cursor: zoom-in;
}}

.special-image-box img {{
  width: 100%;
  height: 100%;
  object-fit: cover;
}}

.special-caption-bar {{
  margin-top: 16px;
  background: rgba(15, 23, 42, 0.85);
  border: 1px solid var(--border-hud);
  padding: 16px 20px;
  border-radius: 8px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}}

.special-title-row {{
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}}

.special-title {{
  font-size: 1.4rem;
  font-weight: 800;
  color: #fff;
}}

.special-badge {{
  font-size: 0.75rem;
  color: var(--gold-primary);
  font-family: monospace;
  font-weight: 700;
  background: rgba(245, 158, 11, 0.1);
  padding: 3px 8px;
  border-radius: 4px;
  border: 1px solid var(--border-gold);
}}

.special-desc {{
  font-size: 0.85rem;
  color: #cbd5e1;
  line-height: 1.5;
}}

/* Navigation Bottom Bar */
.bottom-nav {{
  width: 100%;
  max-width: 1400px;
  padding: 16px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(11, 17, 30, 0.85);
  border-top: 1px solid var(--border-hud);
  backdrop-filter: blur(12px);
  z-index: 100;
}}

.nav-buttons {{
  display: flex;
  align-items: center;
  gap: 16px;
}}

.btn-nav {{
  background: linear-gradient(135deg, rgba(15, 23, 42, 0.9), rgba(30, 41, 59, 0.9));
  border: 1px solid var(--border-hud);
  color: #fff;
  padding: 10px 24px;
  border-radius: 8px;
  font-size: 0.95rem;
  font-weight: 700;
  cursor: pointer;
  transition: all 0.25s ease;
  display: flex;
  align-items: center;
  gap: 8px;
}}

.btn-nav:hover:not(:disabled) {{
  background: linear-gradient(135deg, var(--cyan-subtle), var(--cyan-glow));
  color: #050811;
  box-shadow: 0 0 16px rgba(0, 242, 254, 0.5);
  transform: translateY(-2px);
}}

.btn-nav:disabled {{
  opacity: 0.35;
  cursor: not-allowed;
}}

.page-scrubber-group {{
  display: flex;
  align-items: center;
  gap: 14px;
  flex: 1;
  max-width: 500px;
  margin: 0 30px;
}}

.scrubber-slider {{
  flex: 1;
  accent-color: var(--cyan-glow);
  cursor: pointer;
}}

.page-indicator {{
  font-family: monospace;
  font-size: 0.9rem;
  color: var(--cyan-glow);
  font-weight: 700;
  min-width: 80px;
  text-align: center;
}}

/* Lightbox Modal */
.lightbox-modal {{
  display: none;
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(0, 0, 0, 0.94);
  backdrop-filter: blur(10px);
  z-index: 9999;
  justify-content: center;
  align-items: center;
  padding: 30px;
}}

.lightbox-modal.active {{
  display: flex;
}}

.lightbox-img {{
  max-width: 90vw;
  max-height: 90vh;
  object-fit: contain;
  border-radius: 8px;
  box-shadow: 0 0 50px rgba(0, 242, 254, 0.3);
  border: 1px solid var(--border-hud);
}}

.lightbox-close {{
  position: absolute;
  top: 24px;
  right: 32px;
  color: #fff;
  font-size: 2.2rem;
  font-weight: 800;
  cursor: pointer;
  transition: color 0.2s ease;
}}

.lightbox-close:hover {{
  color: var(--gold-primary);
}}

/* TOC Drawer Modal */
.drawer-modal {{
  display: none;
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(0, 0, 0, 0.85);
  backdrop-filter: blur(8px);
  z-index: 8000;
  justify-content: center;
  align-items: center;
}}

.drawer-modal.active {{
  display: flex;
}}

.drawer-content {{
  width: 90%;
  max-width: 800px;
  max-height: 80vh;
  background: #0d1527;
  border: 1px solid var(--border-hud);
  border-radius: 12px;
  padding: 28px;
  overflow-y: auto;
  box-shadow: 0 20px 60px rgba(0,0,0,0.9);
}}

.drawer-title {{
  font-size: 1.5rem;
  color: var(--gold-primary);
  margin-bottom: 20px;
  border-bottom: 1px solid var(--border-hud);
  padding-bottom: 10px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}}

.drawer-grid {{
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 12px;
}}

.drawer-item {{
  background: rgba(15, 23, 42, 0.8);
  border: 1px solid rgba(255, 255, 255, 0.08);
  padding: 12px 14px;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s ease;
  display: flex;
  align-items: center;
  gap: 10px;
}}

.drawer-item:hover {{
  background: rgba(0, 242, 254, 0.15);
  border-color: var(--cyan-glow);
  transform: translateY(-2px);
}}

.drawer-item-img {{
  width: 44px;
  height: 44px;
  border-radius: 4px;
  object-fit: cover;
  border: 1px solid var(--border-hud);
}}

.drawer-item-text {{
  font-size: 0.85rem;
  color: #fff;
  font-weight: 600;
}}

.drawer-item-sub {{
  font-size: 0.7rem;
  color: var(--text-muted);
  font-family: monospace;
}}

/* Responsive Scaling */
@media (max-width: 1280px) {{
  .book-container {{
    width: 95vw;
    height: calc(95vw * 0.6);
  }}
}}

@media (max-width: 768px) {{
  .book-container {{
    flex-direction: column;
    height: auto;
  }}
  .page-spread {{
    width: 100%;
    min-height: 500px;
  }}
  .book-container::after {{
    display: none;
  }}
}}
</style>
</head>
<body>

<!-- Top HUD Bar -->
<header class="top-hud">
  <div class="hud-title-group">
    <span class="hud-badge">CLASSIFIED // EYES ONLY</span>
    <h1 class="hud-main-title">{meta['title']} ✕ {meta['subtitle']}</h1>
  </div>
  <div class="hud-controls">
    <button class="btn-hud" id="btnToc">📋 大典目錄</button>
    <button class="btn-hud" id="btnSound">🔊 翻頁聲效: 開</button>
    <button class="btn-hud" id="btnFullscreen">⛶ 全螢幕</button>
  </div>
</header>

<!-- Book Viewport -->
<main class="book-viewport">
  <div class="book-container" id="bookSpread">
    <!-- Dynamic page contents will be injected by JavaScript -->
  </div>
</main>

<!-- Bottom Navigation Bar -->
<footer class="bottom-nav">
  <div class="nav-buttons">
    <button class="btn-nav" id="btnPrev">◀ 上一頁</button>
  </div>

  <div class="page-scrubber-group">
    <input type="range" class="scrubber-slider" id="pageSlider" min="0" max="0" value="0">
    <div class="page-indicator" id="pageIndicator">01 / 01</div>
  </div>

  <div class="nav-buttons">
    <button class="btn-nav" id="btnNext">下一頁 ▶</button>
  </div>
</footer>

<!-- Lightbox Modal -->
<div class="lightbox-modal" id="lightboxModal">
  <span class="lightbox-close" id="lightboxClose">&times;</span>
  <img class="lightbox-img" id="lightboxImg" src="" alt="Zoomed Photo">
</div>

<!-- TOC Drawer Modal -->
<div class="drawer-modal" id="tocModal">
  <div class="drawer-content">
    <div class="drawer-title">
      <span>📖 PHANTOMGRID 典藏寫真快速導覽目錄</span>
      <span style="cursor:pointer; font-size:1.5rem;" id="tocClose">&times;</span>
    </div>
    <div class="drawer-grid" id="tocGrid">
      <!-- Injected by JS -->
    </div>
  </div>
</div>

<script>
// Load pages data from Python
const albumPages = {json.dumps(pages_json, ensure_ascii=False)};
let currentIndex = 0;
let soundEnabled = true;

// Web Audio API Synthesizer for realistic paper swoosh
const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
function playPageFlipSound() {{
  if (!soundEnabled || audioCtx.state === 'suspended') {{
    audioCtx.resume();
  }}
  if (!soundEnabled) return;
  
  const bufferSize = audioCtx.sampleRate * 0.18; // 180ms
  const buffer = audioCtx.createBuffer(1, bufferSize, audioCtx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < bufferSize; i++) {{
    // pink noise with exponential decay
    data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (bufferSize * 0.4));
  }}
  const noise = audioCtx.createBufferSource();
  noise.buffer = buffer;
  
  const filter = audioCtx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.setValueAtTime(1400, audioCtx.currentTime);
  filter.frequency.exponentialRampToValueAtTime(300, audioCtx.currentTime + 0.18);
  
  const gain = audioCtx.createGain();
  gain.gain.setValueAtTime(0.35, audioCtx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + 0.18);
  
  noise.connect(filter);
  filter.connect(gain);
  gain.connect(audioCtx.destination);
  noise.start();
}}

const bookContainer = document.getElementById('bookSpread');
const pageSlider = document.getElementById('pageSlider');
const pageIndicator = document.getElementById('pageIndicator');
const btnPrev = document.getElementById('btnPrev');
const btnNext = document.getElementById('btnNext');

pageSlider.max = albumPages.length - 1;

function renderCurrentPage() {{
  const page = albumPages[currentIndex];
  pageSlider.value = currentIndex;
  pageIndicator.textContent = `${{String(currentIndex + 1).padStart(2, '0')}} / ${{String(albumPages.length).padStart(2, '0')}}`;
  
  btnPrev.disabled = (currentIndex === 0);
  btnNext.disabled = (currentIndex === albumPages.length - 1);
  
  let html = '';
  
  if (page.type === 'cover') {{
    html = `
      <div class="cover-spread">
        <div class="hud-corner-tl"></div><div class="hud-corner-tr"></div>
        <div class="hud-corner-bl"></div><div class="hud-corner-br"></div>
        <img src="${{page.logo}}" alt="Logo" class="cover-logo">
        <h1 class="cover-title">${{page.title}}</h1>
        <div class="cover-subtitle">${{page.subtitle}}</div>
        <div class="cover-english">${{page.english_title}}</div>
        <div class="cover-footer-meta">
          <div>👑 統帥: ${{page.commander}}</div>
          <div>策劃: ${{page.chief_editor}}</div>
          <div>典藏版本: ${{page.version}} (${{page.date}})</div>
        </div>
      </div>
    `;
  }} else if (page.type === 'foreword') {{
    html = `
      <div class="page-spread page-left">
        <div class="hud-corner-tl"></div><div class="hud-corner-bl"></div>
        <div class="dossier-header">
          <div class="dossier-id">DECREE // 00-GENESIS</div>
          <div class="dossier-name">統帥卷首題詞</div>
        </div>
        <div class="hero-image-box" onclick="openLightbox('${{page.flag}}')">
          <img src="${{page.flag}}" alt="Flag">
          <div class="image-overlay-badge">PHANTOMGRID 大軍旗</div>
        </div>
        <div class="spread-footer">
          <span>PHANTOMGRID SOVEREIGN CODEX</span>
          <span>PAGE 02</span>
        </div>
      </div>
      <div class="page-spread page-right">
        <div class="hud-corner-tr"></div><div class="hud-corner-br"></div>
        <div class="dossier-header">
          <div class="dossier-id">SUPREME COMMAND PROCLAMATION</div>
          <div class="dossier-name">成軍序言與意志</div>
        </div>
        <div class="dossier-quote-box">
          "${{page.motto}}"
          <div style="text-align:right; font-weight:700; color:var(--gold-primary); margin-top:8px;">—— 👑 霸丸總指揮官</div>
        </div>
        <div class="dossier-bio">
          ${{page.decree}}
          <br><br>
          本寫真冊由長官親自命題為<strong>《開源・幻網紀元》</strong>。它不僅記錄了戰隊每一位成員的真實容貌與精神風采，更象徵著我們源自開源、超越開源、走向全球世界舞台的鋼鐵向心力！
          <br><br>
          每一張照片皆為成員專屬 SOLO 原生生成，捕捉最自然、自信、忠誠的風貌。
        </div>
        <div style="margin-top:auto; border-radius:6px; overflow:hidden; border:1px solid var(--border-hud);">
          <img src="${{page.banner}}" alt="Banner" style="width:100%; display:block;">
        </div>
        <div class="spread-footer">
          <span>CLASSIFIED // HIGHEST CLEARANCE</span>
          <span>PAGE 03</span>
        </div>
      </div>
    `;
  }} else if (page.type === 'toc') {{
    let tocListHtml = '';
    page.sections.forEach(sec => {{
      tocListHtml += `
        <div style="margin-bottom:12px; background:rgba(15,23,42,0.6); padding:8px 12px; border-radius:6px; border-left:3px solid var(--cyan-glow);">
          <div style="color:#fff; font-weight:700; font-size:0.9rem;">${{sec.title}}</div>
          <div style="color:var(--text-muted); font-size:0.75rem; font-family:monospace;">${{sec.english}}</div>
        </div>
      `;
    }});
    html = `
      <div class="page-spread page-left">
        <div class="hud-corner-tl"></div><div class="hud-corner-bl"></div>
        <div class="dossier-header">
          <div class="dossier-id">INDEX // SECTION MATRIX</div>
          <div class="dossier-name">${{page.title}}</div>
          <div class="dossier-codename">${{page.english}}</div>
        </div>
        <div style="overflow-y:auto; flex:1; padding-right:8px;">
          ${{tocListHtml}}
        </div>
        <div class="spread-footer">
          <span>PHANTOMGRID TACTICAL MATRIX</span>
          <span>PAGE 04</span>
        </div>
      </div>
      <div class="page-spread page-right">
        <div class="hud-corner-tr"></div><div class="hud-corner-br"></div>
        <div class="dossier-header">
          <div class="dossier-id">FLEET COMPOSITION</div>
          <div class="dossier-name">21 席獨立體全軍編制</div>
        </div>
        <div class="hero-image-box" onclick="openLightbox('PHANTOMGRID_開源戰隊五大戰略小組組織表圖.png')">
          <img src="PHANTOMGRID_開源戰隊五大戰略小組組織表圖.png" alt="Organization Chart">
          <div class="image-overlay-badge">五大戰略小組組織總表</div>
        </div>
        <div class="spread-footer">
          <span>ASIL-D ARCHITECTURE MAP</span>
          <span>PAGE 05</span>
        </div>
      </div>
    `;
  }} else if (page.type === 'member') {{
    const m = page.data;
    let statsHtml = '';
    for (const [k, v] of Object.entries(m.stats)) {{
      statsHtml += `
        <div class="stat-item">
          <div class="stat-label-row">
            <span>${{k}}</span>
            <span class="stat-value">${{v}}%</span>
          </div>
          <div class="stat-bar-bg">
            <div class="stat-bar-fill" style="width: ${{v}}%;"></div>
          </div>
        </div>
      `;
    }}
    
    html = `
      <div class="page-spread page-left">
        <div class="hud-corner-tl"></div><div class="hud-corner-bl"></div>
        <div class="hero-image-box" onclick="openLightbox('${{m.image}}')">
          <img src="${{m.image}}" alt="${{m.name}}">
          <div class="image-overlay-badge">${{m.badge}}</div>
          <div class="image-tech-metadata">${{m.id}} // ARCHIVE-SOLO</div>
        </div>
        <div class="spread-footer">
          <span>PHANTOMGRID PERSONNEL DOSSIER</span>
          <span>UNIT #${{m.id}}</span>
        </div>
      </div>
      <div class="page-spread page-right">
        <div class="hud-corner-tr"></div><div class="hud-corner-br"></div>
        <div class="dossier-header">
          <div class="dossier-id-row">
            <span class="dossier-id">AGENT CODEX // #${{m.id}}</span>
            <span class="dossier-clearance">CLEARANCE LEVEL 5</span>
          </div>
          <div class="dossier-name-row">
            <h2 class="dossier-name">${{m.icon}} ${{m.name}}</h2>
            <span class="dossier-codename">${{m.codename}}</span>
          </div>
          <div class="dossier-title-division">
            <div>${{m.title}}</div>
            <div>部門: <span class="division">${{m.division}}</span></div>
          </div>
        </div>

        <div class="dossier-quote-box">
          "${{m.quote}}"
        </div>

        <div class="dossier-bio">
          ${{m.bio}}
        </div>

        <div class="dossier-stats-grid">
          ${{statsHtml}}
        </div>

        <div class="spread-footer">
          <span>CLASSIFIED // SOVEREIGN AGENT</span>
          <span>STATUS: OPERATIONAL</span>
        </div>
      </div>
    `;
  }} else if (page.type === 'special') {{
    const sp = page.data;
    html = `
      <div class="special-spread" style="padding: 30px;">
        <div class="hud-corner-tl"></div><div class="hud-corner-tr"></div>
        <div class="hud-corner-bl"></div><div class="hud-corner-br"></div>
        <div class="special-image-box" onclick="openLightbox('${{sp.image}}')">
          <img src="${{sp.image}}" alt="${{sp.title}}">
        </div>
        <div class="special-caption-bar">
          <div class="special-title-row">
            <h2 class="special-title">🏆 ${{sp.title}}</h2>
            <span class="special-badge">${{sp.badge}}</span>
          </div>
          <div style="color:var(--gold-primary); font-style:italic; font-size:0.9rem;">"${{sp.quote}}"</div>
          <div class="special-desc">${{sp.desc}}</div>
        </div>
      </div>
    `;
  }} else if (page.type === 'back_cover') {{
    html = `
      <div class="cover-spread">
        <div class="hud-corner-tl"></div><div class="hud-corner-tr"></div>
        <div class="hud-corner-bl"></div><div class="hud-corner-br"></div>
        <img src="${{page.logo}}" alt="Badge" class="cover-logo" style="max-width:140px;">
        <h2 style="font-size:2.2rem; color:#fff; letter-spacing:2px; margin-bottom:8px;">PHANTOMGRID</h2>
        <div style="color:var(--cyan-glow); font-size:1.1rem; letter-spacing:3px; margin-bottom:16px;">全世界獨立體 AGENTS</div>
        <div style="max-width:650px; color:#cbd5e1; line-height:1.7; font-size:0.95rem; margin-bottom:30px;">
          二十一位戰將，二十一顆鋼鐵之心，凝聚在 👑 霸丸總指揮官 的帥旗下。<br>
          我們以開源為根基，以車規為鐵律，以世界舞台為征程！<br>
          <strong>PHANTOMGRID，永不言退，一戰成名！</strong>
        </div>
        <div style="border-radius:6px; overflow:hidden; border:1px solid var(--border-hud); max-width:500px;">
          <img src="${{page.banner}}" alt="Banner" style="width:100%; display:block;">
        </div>
        <div class="cover-footer-meta">
          <div>官方出版: PHANTOMGRID SUPREME HQ</div>
          <div>保密等級: TOP SECRET // DECLASSIFIED ARCHIVE</div>
        </div>
      </div>
    `;
  }}
  
  bookContainer.innerHTML = html;
}}

function flipTo(index) {{
  if (index < 0 || index >= albumPages.length) return;
  playPageFlipSound();
  currentIndex = index;
  renderCurrentPage();
}}

btnPrev.addEventListener('click', () => flipTo(currentIndex - 1));
btnNext.addEventListener('click', () => flipTo(currentIndex + 1));
pageSlider.addEventListener('input', (e) => flipTo(parseInt(e.target.value)));

document.addEventListener('keydown', (e) => {{
  if (e.key === 'ArrowLeft' || e.key === 'PageUp') flipTo(currentIndex - 1);
  if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') flipTo(currentIndex + 1);
  if (e.key === 'Escape') {{
    closeLightbox();
    closeToc();
  }}
}});

// Sound Toggle
const btnSound = document.getElementById('btnSound');
btnSound.addEventListener('click', () => {{
  soundEnabled = !soundEnabled;
  btnSound.textContent = soundEnabled ? '🔊 翻頁聲效: 開' : '🔇 翻頁聲效: 關';
}});

// Fullscreen Toggle
const btnFullscreen = document.getElementById('btnFullscreen');
btnFullscreen.addEventListener('click', () => {{
  if (!document.fullscreenElement) {{
    document.documentElement.requestFullscreen();
    btnFullscreen.textContent = '🗗 視窗檢視';
  }} else {{
    if (document.exitFullscreen) {{
      document.exitFullscreen();
      btnFullscreen.textContent = '⛶ 全螢幕';
    }}
  }}
}});

// Lightbox
const lightboxModal = document.getElementById('lightboxModal');
const lightboxImg = document.getElementById('lightboxImg');
const lightboxClose = document.getElementById('lightboxClose');
function openLightbox(src) {{
  lightboxImg.src = src;
  lightboxModal.classList.add('active');
}}
function closeLightbox() {{
  lightboxModal.classList.remove('active');
}}
lightboxClose.addEventListener('click', closeLightbox);
lightboxModal.addEventListener('click', (e) => {{
  if (e.target === lightboxModal) closeLightbox();
}});

// TOC Drawer
const btnToc = document.getElementById('btnToc');
const tocModal = document.getElementById('tocModal');
const tocClose = document.getElementById('tocClose');
const tocGrid = document.getElementById('tocGrid');

function populateToc() {{
  tocGrid.innerHTML = '';
  albumPages.forEach((p, idx) => {{
    let title = '頁面 ' + (idx + 1);
    let sub = '';
    let img = 'PHANTOMGRID_官方賽事獨立圖騰徽章.png';
    if (p.type === 'cover') {{ title = '典藏封面'; sub = p.title; img = p.logo; }}
    else if (p.type === 'foreword') {{ title = '統帥題詞'; sub = '成軍序言'; img = p.flag; }}
    else if (p.type === 'toc') {{ title = '目錄總覽'; sub = '架構與編制'; img = 'PHANTOMGRID_開源戰隊五大戰略小組組織表圖.png'; }}
    else if (p.type === 'member') {{ title = p.data.icon + ' ' + p.data.name; sub = p.data.codename; img = p.data.image; }}
    else if (p.type === 'special') {{ title = '🏆 ' + p.data.title; sub = p.data.badge; img = p.data.image; }}
    else if (p.type === 'back_cover') {{ title = '典藏封底'; sub = 'PHANTOMGRID'; img = p.logo; }}
    
    const item = document.createElement('div');
    item.className = 'drawer-item';
    item.innerHTML = `
      <img src="${{img}}" class="drawer-item-img" alt="thumb">
      <div>
        <div class="drawer-item-text">${{title}}</div>
        <div class="drawer-item-sub">${{sub}}</div>
      </div>
    `;
    item.addEventListener('click', () => {{
      flipTo(idx);
      closeToc();
    }});
    tocGrid.appendChild(item);
  }});
}}

btnToc.addEventListener('click', () => {{
  populateToc();
  tocModal.classList.add('active');
}});
function closeToc() {{
  tocModal.classList.remove('active');
}}
tocClose.addEventListener('click', closeToc);
tocModal.addEventListener('click', (e) => {{
  if (e.target === tocModal) closeToc();
}});

// Initialize
renderCurrentPage();
</script>
</body>
</html>
"""
    with open(INDEX_HTML, "w", encoding="utf-8") as f:
        f.write(html_content)
    print(f"Interactive 3D Lookbook HTML generated: {INDEX_HTML}")

def generate_print_html(manifest):
    meta = manifest["meta"]
    roster = manifest["roster"]
    special_pages = manifest["special_pages"]
    
    # We build print spreads for A4 landscape: 297mm x 210mm
    # Each spread is a .print-sheet with width: 297mm; height: 210mm; page-break-after: always;
    
    sheets_html = []
    
    # Sheet 1: Cover
    sheets_html.append(f"""
    <div class="print-sheet cover-sheet">
      <div class="hud-corner-tl"></div><div class="hud-corner-tr"></div>
      <div class="hud-corner-bl"></div><div class="hud-corner-br"></div>
      <img src="PHANTOMGRID_官方最高代表圖騰_正統印記.png" class="print-cover-logo">
      <h1 class="print-cover-title">{meta['title']}</h1>
      <div class="print-cover-subtitle">{meta['subtitle']}</div>
      <div class="print-cover-en">{meta['english_title']} // {meta['english_subtitle']}</div>
      <div class="print-cover-footer">
        <div>👑 統帥: {meta['commander']}</div>
        <div>策劃總編: {meta['chief_editor']}</div>
        <div>典藏版本: {meta['version']} ({meta['date']})</div>
      </div>
    </div>
    """)
    
    # Sheet 2: Foreword (Left: Flag & motto / Right: Proclamation)
    sheets_html.append(f"""
    <div class="print-sheet spread-sheet">
      <div class="print-half page-left">
        <div class="hud-corner-tl"></div><div class="hud-corner-bl"></div>
        <div class="print-header">
          <div class="print-id">DECREE // 00-GENESIS</div>
          <div class="print-title">統帥成軍題詞</div>
        </div>
        <div class="print-img-box">
          <img src="PHANTOMGRID_戰隊官方旗號大軍旗.png">
        </div>
        <div class="print-footer">
          <span>PHANTOMGRID SOVEREIGN CODEX</span>
          <span>PAGE 02</span>
        </div>
      </div>
      <div class="print-half page-right">
        <div class="hud-corner-tr"></div><div class="hud-corner-br"></div>
        <div class="print-header">
          <div class="print-id">SUPREME COMMAND PROCLAMATION</div>
          <div class="print-title">成軍序言與意志</div>
        </div>
        <div class="print-quote">
          "{meta['motto']}"
          <div style="text-align:right; font-weight:700; color:#f59e0b; margin-top:6px;">—— 👑 霸丸總指揮官</div>
        </div>
        <div class="print-bio">
          {meta['decree']}
          <br><br>
          本寫真冊由長官親自命題為<strong>《開源・幻網紀元》</strong>。它不僅記錄了戰隊每一位成員的真實容貌與精神風采，更象徵著我們源自開源、超越開源、走向全球世界舞台的鋼鐵向心力！每一張照片皆為成員專屬 SOLO 原生生成，捕捉最自然、自信、忠誠的風貌。
        </div>
        <div style="margin-top:auto; border-radius:4px; overflow:hidden; border:1px solid rgba(0,242,254,0.3);">
          <img src="PHANTOMGRID_官方賽事橫式大會旗標_Banner.png" style="width:100%; display:block;">
        </div>
        <div class="print-footer">
          <span>CLASSIFIED // HIGHEST CLEARANCE</span>
          <span>PAGE 03</span>
        </div>
      </div>
    </div>
    """)
    
    # Sheet 3: TOC & Org Chart
    sheets_html.append(f"""
    <div class="print-sheet spread-sheet">
      <div class="print-half page-left">
        <div class="hud-corner-tl"></div><div class="hud-corner-bl"></div>
        <div class="print-header">
          <div class="print-id">INDEX // SECTION MATRIX</div>
          <div class="print-title">大典總目錄導覽</div>
        </div>
        <div style="display:flex; flex-direction:column; gap:8px; margin-top:8px;">
          {''.join([f'''<div style="background:rgba(15,23,42,0.6); padding:6px 10px; border-radius:4px; border-left:3px solid #00f2fe;">
            <div style="color:#fff; font-weight:700; font-size:0.8rem;">{s['title']}</div>
            <div style="color:#94a3b8; font-size:0.65rem; font-family:monospace;">{s['english']}</div>
          </div>''' for s in manifest['sections']])}
        </div>
        <div class="print-footer">
          <span>PHANTOMGRID TACTICAL MATRIX</span>
          <span>PAGE 04</span>
        </div>
      </div>
      <div class="print-half page-right">
        <div class="hud-corner-tr"></div><div class="hud-corner-br"></div>
        <div class="print-header">
          <div class="print-id">FLEET COMPOSITION</div>
          <div class="print-title">21 席獨立體全軍編制</div>
        </div>
        <div class="print-img-box">
          <img src="PHANTOMGRID_開源戰隊五大戰略小組組織表圖.png">
        </div>
        <div class="print-footer">
          <span>ASIL-D ARCHITECTURE MAP</span>
          <span>PAGE 05</span>
        </div>
      </div>
    </div>
    """)
    
    # Member Sheets
    page_num = 6
    for m in roster:
        stats_html = "".join([f"""
          <div class="print-stat">
            <div style="display:flex; justify-content:space-between; font-size:0.68rem; margin-bottom:2px; color:#94a3b8;">
              <span>{k}</span>
              <span style="color:#f59e0b; font-weight:700; font-family:monospace;">{v}%</span>
            </div>
            <div style="width:100%; height:3px; background:rgba(255,255,255,0.1); border-radius:2px; overflow:hidden;">
              <div style="width:{v}%; height:100%; background:linear-gradient(90deg, #06b6d4, #f59e0b);"></div>
            </div>
          </div>
        """ for k, v in m['stats'].items()])
        
        sheets_html.append(f"""
        <div class="print-sheet spread-sheet">
          <div class="print-half page-left">
            <div class="hud-corner-tl"></div><div class="hud-corner-bl"></div>
            <div class="print-img-box">
              <img src="{m['image']}">
              <div class="print-img-badge">{m['badge']}</div>
            </div>
            <div class="print-footer">
              <span>PHANTOMGRID PERSONNEL DOSSIER</span>
              <span>UNIT #{m['id']}</span>
            </div>
          </div>
          <div class="print-half page-right">
            <div class="hud-corner-tr"></div><div class="hud-corner-br"></div>
            <div class="print-header">
              <div style="display:flex; justify-content:space-between; align-items:center;">
                <span class="print-id">AGENT CODEX // #{m['id']}</span>
                <span class="print-clearance">CLEARANCE LEVEL 5</span>
              </div>
              <div style="display:flex; align-items:baseline; gap:8px; margin-top:2px;">
                <h2 class="print-title" style="font-size:1.45rem;">{m['icon']} {m['name']}</h2>
                <span style="color:#06b6d4; font-family:monospace; font-size:0.85rem;">{m['codename']}</span>
              </div>
              <div style="font-size:0.75rem; color:#94a3b8; margin-top:3px;">
                <div>{m['title']}</div>
                <div>部門: <span style="color:#f59e0b; font-weight:600;">{m['division']}</span></div>
              </div>
            </div>
            <div class="print-quote">
              "{m['quote']}"
            </div>
            <div class="print-bio">
              {m['bio']}
            </div>
            <div style="display:grid; grid-template-columns:1fr 1fr; gap:8px; margin-top:auto; border-top:1px solid rgba(255,255,255,0.08); padding-top:8px;">
              {stats_html}
            </div>
            <div class="print-footer">
              <span>CLASSIFIED // SOVEREIGN AGENT</span>
              <span>PAGE {String_num(page_num)}</span>
            </div>
          </div>
        </div>
        """)
        page_num += 1

    # Special Pages
    for sp in special_pages:
        sheets_html.append(f"""
        <div class="print-sheet spread-sheet" style="padding:24px;">
          <div class="hud-corner-tl"></div><div class="hud-corner-tr"></div>
          <div class="hud-corner-bl"></div><div class="hud-corner-br"></div>
          <div class="print-img-box" style="flex:1;">
            <img src="{sp['image']}">
          </div>
          <div style="margin-top:12px; background:rgba(15,23,42,0.85); border:1px solid rgba(0,242,254,0.3); padding:12px 16px; border-radius:6px;">
            <div style="display:flex; justify-content:space-between; align-items:baseline;">
              <h2 style="font-size:1.15rem; color:#fff; font-weight:800;">🏆 {sp['title']}</h2>
              <span style="color:#f59e0b; font-family:monospace; font-size:0.7rem; font-weight:700;">{sp['badge']}</span>
            </div>
            <div style="color:#f59e0b; font-style:italic; font-size:0.78rem; margin:3px 0;">"{sp['quote']}"</div>
            <div style="font-size:0.75rem; color:#cbd5e1; line-height:1.4;">{sp['desc']}</div>
          </div>
          <div class="print-footer" style="margin-top:6px;">
            <span>PHANTOMGRID EPIC MILESTONES</span>
            <span>PAGE {String_num(page_num)}</span>
          </div>
        </div>
        """)
        page_num += 1
        
    # Back Cover
    sheets_html.append(f"""
    <div class="print-sheet cover-sheet">
      <div class="hud-corner-tl"></div><div class="hud-corner-tr"></div>
      <div class="hud-corner-bl"></div><div class="hud-corner-br"></div>
      <img src="PHANTOMGRID_官方賽事獨立圖騰徽章.png" class="print-cover-logo" style="max-width:120px;">
      <h2 style="font-size:1.8rem; color:#fff; letter-spacing:2px; margin-bottom:4px;">PHANTOMGRID</h2>
      <div style="color:#00f2fe; font-size:0.95rem; letter-spacing:2px; margin-bottom:12px;">全世界獨立體 AGENTS</div>
      <div style="max-width:550px; color:#cbd5e1; line-height:1.6; font-size:0.8rem; margin-bottom:20px; text-align:center;">
        二十一位戰將，二十一顆鋼鐵之心，凝聚在 👑 霸丸總指揮官 的帥旗下。<br>
        我們以開源為根基，以車規為鐵律，以世界舞台為征程！<br>
        <strong>PHANTOMGRID，永不言退，一戰成名！</strong>
      </div>
      <div style="border-radius:4px; overflow:hidden; border:1px solid rgba(0,242,254,0.3); max-width:400px;">
        <img src="PHANTOMGRID_官方賽事橫式大會旗標_Banner.png" style="width:100%; display:block;">
      </div>
      <div class="print-cover-footer">
        <div>官方出版: PHANTOMGRID SUPREME HQ</div>
        <div>保密等級: TOP SECRET // DECLASSIFIED ARCHIVE</div>
      </div>
    </div>
    """)
    
    html_print_content = f"""<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<title>{meta['title']} —— 印刷級對開典藏畫冊</title>
<style>
@page {{
  size: 297mm 210mm;
  margin: 0;
}}

* {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}}

body {{
  font-family: 'Segoe UI', 'PingFang TC', 'Microsoft JhengHei', sans-serif;
  background: #060910;
  color: #f8fafc;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}}

.print-sheet {{
  width: 297mm;
  height: 210mm;
  page-break-after: always;
  position: relative;
  overflow: hidden;
  display: flex;
  background: #080d18;
}}

.spread-sheet {{
  display: flex;
  flex-direction: row;
}}

.print-half {{
  width: 50%;
  height: 100%;
  padding: 16mm 18mm;
  position: relative;
  display: flex;
  flex-direction: column;
}}

.page-left {{
  background: linear-gradient(135deg, #0a101d 0%, #0d1527 100%);
  border-right: 1px solid rgba(255, 255, 255, 0.05);
}}

.page-right {{
  background: linear-gradient(135deg, #0d1527 0%, #111a30 100%);
}}

/* Corner Accents */
.hud-corner-tl {{ position: absolute; top: 8mm; left: 8mm; width: 4mm; height: 4mm; border-top: 2px solid #00f2fe; border-left: 2px solid #00f2fe; }}
.hud-corner-tr {{ position: absolute; top: 8mm; right: 8mm; width: 4mm; height: 4mm; border-top: 2px solid #00f2fe; border-right: 2px solid #00f2fe; }}
.hud-corner-bl {{ position: absolute; bottom: 8mm; left: 8mm; width: 4mm; height: 4mm; border-bottom: 2px solid #00f2fe; border-left: 2px solid #00f2fe; }}
.hud-corner-br {{ position: absolute; bottom: 8mm; right: 8mm; width: 4mm; height: 4mm; border-bottom: 2px solid #00f2fe; border-right: 2px solid #00f2fe; }}

.print-header {{
  border-bottom: 2px solid rgba(0,242,254,0.3);
  padding-bottom: 8px;
  margin-bottom: 10px;
}}

.print-id {{
  font-family: monospace;
  font-size: 0.75rem;
  color: #00f2fe;
  font-weight: 700;
  letter-spacing: 1.5px;
}}

.print-clearance {{
  font-size: 0.65rem;
  color: #f59e0b;
  border: 1px solid #f59e0b;
  padding: 1px 6px;
  border-radius: 3px;
  font-weight: 700;
}}

.print-title {{
  font-size: 1.25rem;
  font-weight: 800;
  color: #fff;
}}

.print-quote {{
  background: rgba(0, 242, 254, 0.05);
  border-left: 3px solid #00f2fe;
  padding: 8px 12px;
  border-radius: 0 4px 4px 0;
  margin-bottom: 10px;
  font-style: italic;
  font-size: 0.75rem;
  line-height: 1.4;
  color: #e2e8f0;
}}

.print-bio {{
  font-size: 0.72rem;
  line-height: 1.5;
  color: #cbd5e1;
  text-align: justify;
  margin-bottom: 8px;
}}

.print-img-box {{
  flex: 1;
  border-radius: 6px;
  border: 1px solid rgba(0,242,254,0.3);
  overflow: hidden;
  position: relative;
  background: #050811;
  display: flex;
  align-items: center;
  justify-content: center;
}}

.print-img-box img {{
  width: 100%;
  height: 100%;
  object-fit: cover;
}}

.print-img-badge {{
  position: absolute;
  top: 8px;
  left: 8px;
  background: rgba(6, 11, 22, 0.85);
  border: 1px solid #f59e0b;
  color: #f59e0b;
  padding: 2px 8px;
  border-radius: 3px;
  font-size: 0.65rem;
  font-weight: 700;
}}

.print-footer {{
  margin-top: 8px;
  display: flex;
  justify-content: space-between;
  font-size: 0.65rem;
  color: rgba(148, 163, 184, 0.6);
  font-family: monospace;
}}

.cover-sheet {{
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: 25mm;
  background: radial-gradient(circle at center, #111b33 0%, #060910 80%);
}}

.print-cover-logo {{
  max-width: 140px;
  max-height: 140px;
  margin-bottom: 16px;
}}

.print-cover-title {{
  font-size: 2.6rem;
  font-weight: 900;
  letter-spacing: 3px;
  color: #fff;
  margin-bottom: 8px;
}}

.print-cover-subtitle {{
  font-size: 1.1rem;
  color: #00f2fe;
  letter-spacing: 1.5px;
  font-weight: 700;
  margin-bottom: 4px;
}}

.print-cover-en {{
  font-size: 0.75rem;
  color: #94a3b8;
  letter-spacing: 2px;
  font-family: monospace;
  margin-bottom: 24px;
}}

.print-cover-footer {{
  margin-top: auto;
  display: flex;
  gap: 20px;
  font-size: 0.75rem;
  color: #fef3c7;
  border-top: 1px solid rgba(245,158,11,0.3);
  padding-top: 12px;
}}
</style>
</head>
<body>
{''.join(sheets_html)}
</body>
</html>
"""
    with open(PRINT_HTML, "w", encoding="utf-8") as f:
        f.write(html_print_content)
    print(f"Print-ready Spread HTML generated: {PRINT_HTML}")

def String_num(n):
    return str(n).zfill(2)

def render_pdf():
    print(f"Rendering PDF using Playwright from {PRINT_HTML}...")
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()
        # Open local print HTML
        page.goto(f"file:///{PRINT_HTML.replace(os.sep, '/')}")
        # Wait for images to load
        page.wait_for_timeout(2000)
        page.pdf(
            path=OUTPUT_PDF,
            format="A4",
            landscape=True,
            print_background=True,
            prefer_css_page_size=True
        )
        browser.close()
    print(f"High-resolution PDF generated successfully: {OUTPUT_PDF}")

if __name__ == "__main__":
    manifest = load_manifest()
    generate_interactive_html(manifest)
    generate_print_html(manifest)
    render_pdf()
    print("ALL ARTIFACTS GENERATED SUCCESSFULLY!")
