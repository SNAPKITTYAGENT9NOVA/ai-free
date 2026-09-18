# -*- coding: utf-8 -*-
"""
build_interactive_flipbook.py
Generates the interactive 3D Loose-Leaf Page-Flipping Book with genuine 3D turning physics for:
《PHANTOMGRID 幻網戰隊・四格動漫畫》第三本：熱血賽事篇 (5-Page Loose-Leaf 3D Flipbook)
"""

import os
import json
import base64

OUT_DIR = r"G:\我的雲端硬碟\AI產出成品總庫\12_🎨_PHANTOMGRID_戰隊四格漫畫專區\03_熱血賽事篇"
INDEX_HTML = os.path.join(OUT_DIR, "index.html")

comic_img_path = os.path.join(OUT_DIR, "EP01_綠茵掠食者覺醒_三連勝王者.jpg")
match_img_path = os.path.join(OUT_DIR, "AWS_3連勝_2-1_MVP戰報.png")

def get_base64_image(image_path):
    if not os.path.exists(image_path):
        return ""
    with open(image_path, "rb") as f:
        data = base64.b64encode(f.read()).decode("utf-8")
    ext = os.path.splitext(image_path)[1].lower()
    mime = "image/jpeg" if ext in [".jpg", ".jpeg"] else "image/png"
    return f"data:{mime};base64,{data}"

print("Encoding images to base64...")
COMIC_B64 = get_base64_image(comic_img_path)
MATCH_B64 = get_base64_image(match_img_path)
print(f"Comic b64 length: {len(COMIC_B64)}, Match b64 length: {len(MATCH_B64)}")

html_content = f"""<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>【3D活頁翻頁書】PHANTOMGRID 第三本・熱血賽事篇《綠茵掠食者三連勝典藏大典》</title>
<style>
:root {{
  --bg-dark: #070b14;
  --panel-bg: #0d1527;
  --gold-primary: #f59e0b;
  --gold-glow: #fbbf24;
  --cyan-neon: #00f2fe;
  --cyan-deep: #0284c7;
  --text-light: #f8fafc;
  --text-muted: #94a3b8;
  --ring-chrome: linear-gradient(180deg, #f8fafc 0%, #cbd5e1 25%, #64748b 50%, #e2e8f0 75%, #475569 100%);
}}

* {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
  user-select: none;
}}

body {{
  font-family: 'Segoe UI', 'PingFang TC', 'Microsoft JhengHei', sans-serif;
  background-color: var(--bg-dark);
  color: var(--text-light);
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  align-items: center;
  overflow-x: hidden;
  background-image: 
    radial-gradient(circle at 50% 15%, rgba(0, 242, 254, 0.09) 0%, transparent 60%),
    radial-gradient(circle at 85% 85%, rgba(245, 158, 11, 0.06) 0%, transparent 60%),
    linear-gradient(rgba(255, 255, 255, 0.02) 1px, transparent 1px),
    linear-gradient(90deg, rgba(255, 255, 255, 0.02) 1px, transparent 1px);
  background-size: 100% 100%, 100% 100%, 40px 40px, 40px 40px;
}}

/* Top HUD */
.top-hud {{
  width: 100%;
  max-width: 1440px;
  padding: 12px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  border-bottom: 1px solid rgba(0, 242, 254, 0.2);
  background: rgba(13, 21, 39, 0.9);
  backdrop-filter: blur(14px);
  z-index: 200;
}}

.hud-left {{
  display: flex;
  align-items: center;
  gap: 12px;
}}

.badge-tag {{
  background: rgba(245, 158, 11, 0.15);
  border: 1px solid var(--gold-primary);
  color: var(--gold-primary);
  padding: 3px 10px;
  border-radius: 4px;
  font-size: 0.72rem;
  font-weight: 800;
  letter-spacing: 1px;
}}

.hud-title {{
  font-size: 1.12rem;
  font-weight: 800;
  background: linear-gradient(135deg, #ffffff 40%, var(--gold-primary) 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  letter-spacing: 0.5px;
}}

.hud-controls {{
  display: flex;
  align-items: center;
  gap: 10px;
}}

.btn-hud {{
  background: rgba(15, 23, 42, 0.85);
  border: 1px solid rgba(0, 242, 254, 0.3);
  color: var(--cyan-neon);
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 0.82rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.25s ease;
  display: flex;
  align-items: center;
  gap: 6px;
  text-decoration: none;
}}

.btn-hud:hover {{
  background: rgba(0, 242, 254, 0.15);
  border-color: var(--cyan-neon);
  box-shadow: 0 0 12px rgba(0, 242, 254, 0.35);
  color: #fff;
  transform: translateY(-1px);
}}

/* 3D Viewport */
.book-viewport {{
  flex: 1;
  width: 100%;
  max-width: 1440px;
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 24px 16px;
  perspective: 2600px;
}}

/* Realistic Binder Book Outer */
.binder-outer {{
  width: 1260px;
  height: 740px;
  background: #090e1a;
  border-radius: 16px;
  box-shadow: 
    0 30px 70px -15px rgba(0, 0, 0, 0.95),
    0 0 50px rgba(0, 242, 254, 0.15),
    inset 0 0 30px rgba(0, 0, 0, 0.8);
  border: 2px solid rgba(0, 242, 254, 0.35);
  position: relative;
  display: flex;
  transform-style: preserve-3d;
  transition: width 0.3s ease, height 0.3s ease;
}}

/* Fullscreen Mode Optimization: Expand to fill screen */
:fullscreen .binder-outer,
:-webkit-full-screen .binder-outer {{
  width: min(96vw, 1560px);
  height: min(92vh, 880px);
  box-shadow: 0 0 70px rgba(0, 242, 254, 0.35);
}}

:fullscreen .book-viewport,
:-webkit-full-screen .book-viewport {{
  padding: 10px;
}}

/* In-Binder Fullscreen Floating Button */
.btn-binder-fullscreen {{
  position: absolute;
  top: 14px;
  right: 28px;
  background: rgba(13, 21, 39, 0.88);
  border: 1px solid var(--cyan-neon);
  color: var(--cyan-neon);
  padding: 6px 14px;
  border-radius: 6px;
  font-size: 0.78rem;
  font-weight: 800;
  cursor: pointer;
  z-index: 120;
  display: flex;
  align-items: center;
  gap: 6px;
  backdrop-filter: blur(10px);
  box-shadow: 0 0 14px rgba(0, 242, 254, 0.3);
  transition: all 0.25s ease;
}}

.btn-binder-fullscreen:hover {{
  background: rgba(0, 242, 254, 0.2);
  color: #ffffff;
  box-shadow: 0 0 20px rgba(0, 242, 254, 0.6);
  transform: translateY(-1px);
}}

/* Metallic Binder Hardware Spine */
.binder-spine {{
  position: absolute;
  top: 0;
  bottom: 0;
  left: 50%;
  width: 40px;
  transform: translateX(-50%);
  background: linear-gradient(90deg, 
    #050811 0%, 
    #1e293b 25%, 
    #334155 50%, 
    #1e293b 75%, 
    #050811 100%);
  border-left: 1px solid rgba(255, 255, 255, 0.15);
  border-right: 1px solid rgba(255, 255, 255, 0.15);
  z-index: 100;
  display: flex;
  flex-direction: column;
  justify-content: space-around;
  align-items: center;
  padding: 28px 0;
  box-shadow: 0 0 25px rgba(0,0,0,0.85);
  pointer-events: none;
}}

/* 6 Metallic Chrome Rings */
.chrome-ring {{
  width: 36px;
  height: 20px;
  background: var(--ring-chrome);
  border-radius: 10px;
  box-shadow: 
    0 5px 10px rgba(0,0,0,0.8),
    0 0 8px rgba(255, 255, 255, 0.5),
    inset 0 2px 4px rgba(255, 255, 255, 0.9),
    inset 0 -2px 4px rgba(0, 0, 0, 0.8);
  position: relative;
}}

.chrome-ring::before {{
  content: '';
  position: absolute;
  top: 4px;
  left: 4px;
  right: 4px;
  bottom: 4px;
  background: #0b111e;
  border-radius: 6px;
  box-shadow: inset 0 2px 4px rgba(0,0,0,0.95);
}}

.chrome-ring::after {{
  content: '';
  position: absolute;
  top: -3px;
  left: 50%;
  transform: translateX(-50%);
  width: 5px;
  height: 26px;
  background: linear-gradient(180deg, #fff 0%, #cbd5e1 50%, #475569 100%);
  border-radius: 2.5px;
  box-shadow: 0 0 5px rgba(0,0,0,0.6);
}}

.binder-screw {{
  width: 11px;
  height: 11px;
  background: radial-gradient(circle at 35% 35%, #e2e8f0 0%, #64748b 70%, #1e293b 100%);
  border-radius: 50%;
  border: 1px solid #475569;
  box-shadow: inset 0 1px 2px rgba(255,255,255,0.7), 0 2px 4px rgba(0,0,0,0.7);
  position: relative;
}}

.binder-screw::after {{
  content: '';
  position: absolute;
  top: 4.5px;
  left: 2px;
  width: 7px;
  height: 1.5px;
  background: #0f172a;
  transform: rotate(35deg);
}}

/* Left & Right Pages */
.page-spread {{
  width: 50%;
  height: 100%;
  position: relative;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  padding: 36px 42px;
  cursor: pointer;
  transition: background 0.3s ease;
}}

.page-left {{
  background: linear-gradient(135deg, #0b1220 0%, #0f1a30 100%);
  padding-right: 50px;
  border-right: 1px solid rgba(255, 255, 255, 0.05);
  border-top-left-radius: 14px;
  border-bottom-left-radius: 14px;
}}

.page-right {{
  background: linear-gradient(135deg, #0f1a30 0%, #13213d 100%);
  padding-left: 50px;
  border-top-right-radius: 14px;
  border-bottom-right-radius: 14px;
}}

/* Punch Holes */
.punch-hole-column {{
  position: absolute;
  top: 0;
  bottom: 0;
  width: 26px;
  display: flex;
  flex-direction: column;
  justify-content: space-around;
  align-items: center;
  padding: 28px 0;
  pointer-events: none;
  z-index: 70;
}}

.page-left .punch-hole-column {{
  right: 6px;
}}

.page-right .punch-hole-column {{
  left: 6px;
}}

.punch-hole {{
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: #050811;
  border: 1.5px solid rgba(255, 255, 255, 0.25);
  box-shadow: 
    inset 0 2px 5px rgba(0,0,0,0.98),
    0 1px 2px rgba(255,255,255,0.15);
}}

/* 3D Turning Page Layer (Simulated realistic flip) */
.flip-leaf {{
  position: absolute;
  top: 0;
  width: 50%;
  height: 100%;
  transform-style: preserve-3d;
  z-index: 85;
  pointer-events: none;
  display: none;
}}

.flip-leaf-right {{
  right: 0;
  transform-origin: left center;
  animation: turnPageForward 0.65s cubic-bezier(0.25, 1, 0.5, 1) forwards;
}}

.flip-leaf-left {{
  left: 0;
  transform-origin: right center;
  animation: turnPageBackward 0.65s cubic-bezier(0.25, 1, 0.5, 1) forwards;
}}

@keyframes turnPageForward {{
  0% {{
    transform: rotateY(0deg);
    box-shadow: 0 0 20px rgba(0,0,0,0.2);
    filter: brightness(1);
  }}
  50% {{
    box-shadow: -20px 0 40px rgba(0,0,0,0.8);
    filter: brightness(0.85);
  }}
  100% {{
    transform: rotateY(-180deg);
    box-shadow: 0 0 20px rgba(0,0,0,0.2);
    filter: brightness(1);
  }}
}}

@keyframes turnPageBackward {{
  0% {{
    transform: rotateY(0deg);
    box-shadow: 0 0 20px rgba(0,0,0,0.2);
    filter: brightness(1);
  }}
  50% {{
    box-shadow: 20px 0 40px rgba(0,0,0,0.8);
    filter: brightness(0.85);
  }}
  100% {{
    transform: rotateY(180deg);
    box-shadow: 0 0 20px rgba(0,0,0,0.2);
    filter: brightness(1);
  }}
}}

/* Corner Accents */
.corner-tl {{ position: absolute; top: 14px; left: 14px; width: 14px; height: 14px; border-top: 2px solid var(--cyan-neon); border-left: 2px solid var(--cyan-neon); pointer-events: none; }}
.corner-tr {{ position: absolute; top: 14px; right: 14px; width: 14px; height: 14px; border-top: 2px solid var(--cyan-neon); border-right: 2px solid var(--cyan-neon); pointer-events: none; }}
.corner-bl {{ position: absolute; bottom: 14px; left: 14px; width: 14px; height: 14px; border-bottom: 2px solid var(--cyan-neon); border-left: 2px solid var(--cyan-neon); pointer-events: none; }}
.corner-br {{ position: absolute; bottom: 14px; right: 14px; width: 14px; height: 14px; border-bottom: 2px solid var(--cyan-neon); border-right: 2px solid var(--cyan-neon); pointer-events: none; }}

/* Dossier Header */
.dossier-header {{
  border-bottom: 1px solid rgba(0, 242, 254, 0.25);
  padding-bottom: 10px;
  margin-bottom: 16px;
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
}}

.dossier-tag {{
  font-size: 0.7rem;
  font-family: monospace;
  font-weight: 700;
  color: var(--cyan-neon);
  letter-spacing: 1.5px;
}}

.dossier-title {{
  font-size: 1.25rem;
  font-weight: 800;
  color: #ffffff;
  display: flex;
  align-items: center;
  gap: 8px;
}}

.gold-accent {{
  color: var(--gold-primary);
}}

/* Spread 0: Cover Style */
.cover-layout {{
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: 40px;
  background: radial-gradient(circle at center, #121d36 0%, #080d18 85%);
  position: relative;
}}

.cover-badge-top {{
  background: rgba(245, 158, 11, 0.15);
  border: 1px solid var(--gold-primary);
  color: var(--gold-primary);
  padding: 6px 18px;
  border-radius: 20px;
  font-size: 0.85rem;
  font-weight: 800;
  letter-spacing: 2px;
  margin-bottom: 20px;
}}

.cover-title-main {{
  font-size: 2.3rem;
  font-weight: 900;
  letter-spacing: 1px;
  background: linear-gradient(135deg, #ffffff 30%, var(--gold-primary) 80%, #fbbf24 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 10px;
  line-height: 1.2;
}}

.cover-title-sub {{
  font-size: 1.35rem;
  font-weight: 700;
  color: var(--cyan-neon);
  margin-bottom: 8px;
  letter-spacing: 1.5px;
}}

.cover-eng {{
  font-size: 0.82rem;
  font-family: monospace;
  color: var(--text-muted);
  letter-spacing: 2px;
  margin-bottom: 30px;
}}

.trophy-seal-box {{
  width: 110px;
  height: 110px;
  background: radial-gradient(circle, rgba(245, 158, 11, 0.25) 0%, rgba(15, 23, 42, 0.9) 70%);
  border: 2px solid var(--gold-primary);
  border-radius: 50%;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  box-shadow: 0 0 30px rgba(245, 158, 11, 0.4);
  margin-bottom: 30px;
}}

.trophy-icon {{
  font-size: 2.4rem;
}}

.trophy-text {{
  font-size: 0.65rem;
  font-weight: 800;
  color: var(--gold-glow);
  letter-spacing: 1px;
}}

.cover-metadata-grid {{
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 16px;
  width: 90%;
  max-width: 680px;
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  padding-top: 20px;
}}

.cover-meta-item {{
  background: rgba(15, 23, 42, 0.6);
  border: 1px solid rgba(255, 255, 255, 0.06);
  padding: 8px 12px;
  border-radius: 6px;
  font-size: 0.78rem;
}}

.meta-lbl {{
  color: var(--text-muted);
  margin-bottom: 3px;
}}

.meta-val {{
  color: #fff;
  font-weight: 700;
}}

/* Image Containers */
.image-showcase {{
  flex: 1;
  width: 100%;
  border-radius: 10px;
  border: 1px solid rgba(0, 242, 254, 0.3);
  overflow: hidden;
  position: relative;
  box-shadow: 0 12px 30px rgba(0,0,0,0.7);
  background: #050811;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: zoom-in;
}}

.image-showcase img {{
  width: 100%;
  height: 100%;
  object-fit: contain;
  transition: transform 0.3s ease;
}}

.image-showcase:hover img {{
  transform: scale(1.02);
}}

.image-overlay-badge {{
  position: absolute;
  top: 12px;
  left: 12px;
  background: rgba(9, 14, 26, 0.85);
  border: 1px solid var(--gold-primary);
  color: var(--gold-primary);
  padding: 4px 10px;
  border-radius: 4px;
  font-size: 0.72rem;
  font-weight: 700;
  backdrop-filter: blur(8px);
}}

/* Tactical Card Boxes */
.tactical-box {{
  background: rgba(15, 23, 42, 0.6);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 8px;
  padding: 12px 14px;
  margin-bottom: 12px;
}}

.tactical-box-title {{
  font-size: 0.85rem;
  font-weight: 700;
  color: var(--cyan-neon);
  margin-bottom: 6px;
  display: flex;
  align-items: center;
  gap: 6px;
}}

.tactical-box-text {{
  font-size: 0.78rem;
  color: #cbd5e1;
  line-height: 1.55;
}}

.quote-proclamation {{
  background: rgba(0, 242, 254, 0.06);
  border-left: 3px solid var(--cyan-neon);
  padding: 10px 14px;
  border-radius: 0 6px 6px 0;
  font-style: italic;
  font-size: 0.84rem;
  color: #e2e8f0;
  margin-bottom: 14px;
}}

/* Grid Table */
.stats-table {{
  width: 100%;
  border-collapse: collapse;
  font-size: 0.75rem;
  margin-top: 8px;
}}

.stats-table th {{
  background: rgba(30, 41, 59, 0.7);
  color: var(--cyan-neon);
  padding: 6px 8px;
  text-align: left;
  border: 1px solid rgba(255, 255, 255, 0.08);
}}

.stats-table td {{
  padding: 6px 8px;
  border: 1px solid rgba(255, 255, 255, 0.06);
  color: #e2e8f0;
}}

/* Red Seal Stamp */
.seal-stamp {{
  display: inline-block;
  border: 2px solid #ef4444;
  color: #ef4444;
  padding: 3px 8px;
  font-size: 0.75rem;
  font-weight: 900;
  border-radius: 4px;
  transform: rotate(-4deg);
  letter-spacing: 1px;
  background: rgba(239, 68, 68, 0.08);
}}

/* Page Footer */
.spread-footer {{
  margin-top: auto;
  padding-top: 10px;
  border-top: 1px solid rgba(255, 255, 255, 0.06);
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.68rem;
  color: var(--text-muted);
  font-family: monospace;
}}

/* Bottom Navigation */
.bottom-nav {{
  width: 100%;
  max-width: 1440px;
  padding: 14px 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(13, 21, 39, 0.9);
  border-top: 1px solid rgba(0, 242, 254, 0.2);
  backdrop-filter: blur(14px);
  z-index: 200;
}}

.nav-btn-group {{
  display: flex;
  align-items: center;
  gap: 12px;
}}

.btn-nav {{
  background: linear-gradient(135deg, rgba(15, 23, 42, 0.95), rgba(30, 41, 59, 0.95));
  border: 1px solid rgba(0, 242, 254, 0.4);
  color: #ffffff;
  padding: 9px 22px;
  border-radius: 8px;
  font-size: 0.9rem;
  font-weight: 700;
  cursor: pointer;
  transition: all 0.25s ease;
  display: flex;
  align-items: center;
  gap: 8px;
}}

.btn-nav:hover:not(:disabled) {{
  background: linear-gradient(135deg, var(--cyan-deep), var(--cyan-neon));
  color: #050811;
  box-shadow: 0 0 16px rgba(0, 242, 254, 0.6);
  transform: translateY(-1px);
}}

.btn-nav:disabled {{
  opacity: 0.4;
  cursor: not-allowed;
  border-color: rgba(255, 255, 255, 0.1);
}}

.scrubber-wrap {{
  display: flex;
  align-items: center;
  gap: 16px;
  flex: 1;
  max-width: 480px;
  margin: 0 30px;
}}

.scrubber-slider {{
  flex: 1;
  height: 6px;
  -webkit-appearance: none;
  background: rgba(255, 255, 255, 0.15);
  border-radius: 3px;
  outline: none;
  cursor: pointer;
}}

.scrubber-slider::-webkit-slider-thumb {{
  -webkit-appearance: none;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: var(--cyan-neon);
  box-shadow: 0 0 10px var(--cyan-neon);
  cursor: pointer;
}}

.page-counter {{
  font-family: monospace;
  font-size: 0.9rem;
  font-weight: 700;
  color: var(--cyan-neon);
  min-width: 90px;
  text-align: center;
}}

/* Lightbox Modal */
.lightbox {{
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(5, 8, 17, 0.92);
  backdrop-filter: blur(10px);
  display: none;
  justify-content: center;
  align-items: center;
  z-index: 500;
  cursor: zoom-out;
}}

.lightbox img {{
  max-width: 92vw;
  max-height: 90vh;
  border-radius: 8px;
  box-shadow: 0 0 40px rgba(0, 242, 254, 0.4);
  border: 1px solid var(--cyan-neon);
}}
</style>
</head>
<body>

<!-- Top HUD Bar -->
<header class="top-hud">
  <div class="hud-left">
    <span class="badge-tag">VOL.03 活頁典藏版</span>
    <h1 class="hud-title">PHANTOMGRID 第三本《熱血賽事篇・綠茵掠食者三連勝典藏大典》</h1>
  </div>
  <div class="hud-controls">
    <a href="binder_print.html" class="btn-hud" target="_blank">🖨️ 列印活頁/PDF</a>
    <a href="../index.html" class="btn-hud">📚 漫畫總專區</a>
    <button class="btn-hud" id="btnSound">🔊 翻頁聲: 開</button>
    <button class="btn-hud" id="btnFullscreen">⛶ 全螢幕</button>
  </div>
</header>

<!-- Main Book Viewport -->
<main class="book-viewport">
  <div class="binder-outer" id="binderBook">
    <!-- In-Binder Floating Fullscreen Toggle -->
    <button class="btn-binder-fullscreen" id="btnBinderFullscreen" onclick="toggleFullscreen()" title="切換全螢幕沉浸翻頁">
      ⛶ 全螢幕
    </button>

    <!-- Chrome 6-Ring Binder Spine -->
    <div class="binder-spine">
      <div class="binder-screw"></div>
      <div class="chrome-ring"></div>
      <div class="chrome-ring"></div>
      <div class="chrome-ring"></div>
      <div class="binder-screw"></div>
      <div class="chrome-ring"></div>
      <div class="chrome-ring"></div>
      <div class="chrome-ring"></div>
      <div class="binder-screw"></div>
    </div>

    <!-- 3D Turning Page Layer -->
    <div class="flip-leaf" id="flipLeaf"></div>

    <!-- Dynamic Injected Pages -->
    <div class="page-spread page-left" id="pageLeft" onclick="flipPrev()">
      <div class="punch-hole-column">
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
      </div>
      <div class="corner-tl"></div><div class="corner-bl"></div>
      <div id="leftContent" style="display:flex; flex-direction:column; height:100%;"></div>
    </div>

    <div class="page-spread page-right" id="pageRight" onclick="flipNext()">
      <div class="punch-hole-column">
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
        <div class="punch-hole"></div>
      </div>
      <div class="corner-tr"></div><div class="corner-br"></div>
      <div id="rightContent" style="display:flex; flex-direction:column; height:100%;"></div>
    </div>
  </div>
</main>

<!-- Bottom Nav -->
<footer class="bottom-nav">
  <div class="nav-btn-group">
    <button class="btn-nav" id="btnPrev" onclick="flipPrev()">◀ 上一頁</button>
  </div>

  <div class="scrubber-wrap">
    <input type="range" class="scrubber-slider" id="scrubber" min="0" max="4" value="0" oninput="goToSpread(this.value)">
    <div class="page-counter" id="pageCounter">SPREAD 01 / 05</div>
  </div>

  <div class="nav-btn-group">
    <button class="btn-nav" id="btnNext" onclick="flipNext()">下一頁 ▶</button>
    <button class="btn-nav" id="btnNavFullscreen" onclick="toggleFullscreen()" style="background: linear-gradient(135deg, rgba(2, 132, 199, 0.45), rgba(0, 242, 254, 0.2)); border-color: var(--cyan-neon);">⛶ 全螢幕</button>
  </div>
</footer>

<!-- Lightbox Modal -->
<div class="lightbox" id="lightbox" onclick="closeLightbox()">
  <img id="lightboxImg" src="" alt="Zoomed Asset">
</div>

<script>
// 5 Spreads Definition
const spreads = [
  // SPREAD 0 (Sheet 1): Cover
  {{
    type: "cover",
    sheetNum: 1,
    left: `
      <div class="cover-layout">
        <div class="corner-tl"></div><div class="corner-bl"></div>
        <div class="cover-badge-top">AWS AGENTIC FOOTBALL CUP // VOL.03</div>
        <h1 class="cover-title-main">PHANTOMGRID 幻網戰隊</h1>
        <div class="cover-title-sub">四格動漫畫 第三本《熱血賽事篇》</div>
        <div class="cover-eng">THE GREEN PREY: THREE-MATCH WINNING STREAK SAGA</div>
        
        <div class="trophy-seal-box">
          <div class="trophy-icon">🏆</div>
          <div class="trophy-text">3 冠三連勝</div>
        </div>

        <div style="font-size:0.95rem; color:#cbd5e1; margin-bottom:15px;">
          ★ 實戰終局 2-1 逆轉 Basalt Gazelles · 登頂綠茵之巔 ★
        </div>

        <div class="cover-metadata-grid">
          <div class="cover-meta-item">
            <div class="meta-lbl">最高指揮官</div>
            <div class="meta-val">霸丸總指揮官 Jack 哥</div>
          </div>
          <div class="cover-meta-item">
            <div class="meta-lbl">裝訂規格</div>
            <div class="meta-val">A4橫式 6孔活頁典藏</div>
          </div>
          <div class="cover-meta-item">
            <div class="meta-lbl">典藏頁數</div>
            <div class="meta-val">全 5 頁特裝版</div>
          </div>
        </div>
      </div>
    `,
    right: `
      <div style="display:flex; flex-direction:column; height:100%; justify-content:center; padding:30px;">
        <div class="dossier-header">
          <div class="dossier-tag">TACTICAL MISSION BRIEFING</div>
          <div class="dossier-title">總指揮官<span class="gold-accent">出征令狀</span></div>
        </div>

        <div class="quote-proclamation">
          「球場如同代碼戰場，不容許半點遞迴死循環。今日綠茵之戰，幻網戰隊五大 Agent 緊密協同，以攻為守，三連勝是我們唯一且必然的終局！」
          <div style="text-align:right; color:var(--gold-primary); font-weight:700; margin-top:8px;">—— 霸丸總指揮官 Jack 哥</div>
        </div>

        <div class="tactical-box">
          <div class="tactical-box-title">⚡ 賽事背景</div>
          <div class="tactical-box-text">
            面對以高壓逼搶著稱的 Basalt Gazelles，幻網戰隊在實戰中展現出高超的自主多智能體決策（Multi-Agent FSM）。在前鋒 Thunder Striker R 的強勢突破下，最終以 2-1 奠定勝局！
          </div>
        </div>

        <div class="tactical-box">
          <div class="tactical-box-title">📖 活頁翻閱指南</div>
          <div class="tactical-box-text">
            • 點擊右側頁面或下方「下一頁」翻開扉頁<br>
            • 支援鍵盤左右箭頭鍵 [← / →] 或 [空白鍵] 流暢翻頁<br>
            • 點擊漫畫或實戰戰報截圖可無失真放大檢視
          </div>
        </div>

        <div class="spread-footer">
          <span>PHANTOMGRID VOL.03 LOOSE-LEAF</span>
          <span>PAGE 01 (COVER SPREAD)</span>
        </div>
      </div>
    `
  }},

  // SPREAD 1 (Sheet 2): Tactical Topology & Odyssey
  {{
    type: "topology",
    sheetNum: 2,
    left: `
      <div class="dossier-header">
        <div class="dossier-tag">TACTICAL FORMATION // TOPOLOGY</div>
        <div class="dossier-title">綠茵掠食者<span class="gold-accent">五人陣形拓撲</span></div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">🌐 1-1-2-1 智慧自主隊形 (Agent FSM)</div>
        <div class="tactical-box-text">
          突破傳統單一 Agent 瓶頸，採用分散式即時通訊總線，五位隊員各自擔綱戰術核心：
        </div>
      </div>

      <table class="stats-table">
        <thead>
          <tr>
            <th>位置</th>
            <th>角色代號</th>
            <th>核心戰術任務</th>
            <th>狀態協同</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td style="color:var(--gold-primary); font-weight:700;">ST (前鋒)</td>
            <td>Thunder Striker R</td>
            <td>高速突破、禁區掠食、致命抽射</td>
            <td><span class="seal-stamp" style="border-color:var(--gold-primary); color:var(--gold-primary);">MVP 9.8</span></td>
          </tr>
          <tr>
            <td style="color:var(--cyan-neon); font-weight:700;">MF (中場)</td>
            <td>小開 (Agent_Coder)</td>
            <td>傳球網路中樞、跑位空間計算</td>
            <td>100% 傳球成功率</td>
          </tr>
          <tr>
            <td style="color:var(--cyan-neon); font-weight:700;">LW (左翼)</td>
            <td>小幫手 (Agent_PM)</td>
            <td>戰術節奏掌控、即時換位掩護</td>
            <td>通訊調度核心</td>
          </tr>
          <tr>
            <td>DF (後衛)</td>
            <td>小幽 (Agent_Chameleon)</td>
            <td>隱形回防、封堵 Basalt 傳球線</td>
            <td>截球 12 次</td>
          </tr>
          <tr>
            <td>GK (門將)</td>
            <td>阿鐵 (Agent_IronWall)</td>
            <td>最後一道安全閥、高空球摘除</td>
            <td>撲救 7 次</td>
          </tr>
        </tbody>
      </table>

      <div class="tactical-box" style="margin-top:14px;">
        <div class="tactical-box-title">⚙️ 即時調度狀態機</div>
        <div class="tactical-box-text">
          <code>SCAN → FORMATION_ADAPT → TACTICAL_PASS → STRIKE_GOAL</code><br>
          各 Agent 間採低延遲事件廣播，實現 0.05 秒內全域隊形動態收縮與反擊。
        </div>
      </div>

      <div class="spread-footer">
        <span>PHANTOMGRID TACTICAL SYSTEM</span>
        <span>PAGE 02 (SHEET 2 LEFT)</span>
      </div>
    `,
    right: `
      <div class="dossier-header">
        <div class="dossier-tag">TACTICAL ODYSSEY // DEV LOG</div>
        <div class="dossier-title">三連勝霸業<span class="gold-accent">調優調試史詩</span></div>
      </div>

      <div class="quote-proclamation">
        「每一次看似不可阻擋的精彩進球背後，都是數十次日夜調試、修復邊界死循環的工程心血。」
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">📍 Phase 1：首戰失利與邊界死鎖排查</div>
        <div class="tactical-box-text">
          在早期測試中，發現前鋒在禁區邊緣（X:88, Y:12）容易觸發狀態機死循環判定，導致無法即時出腳。Jack 哥親自操刀，重構決策閾值，徹底抹平延遲。
        </div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">📍 Phase 2：Basalt Gazelles 弱點鎖定</div>
        <div class="tactical-box-text">
          分析對手羚羊隊的逼搶邏輯，發現其邊路防守空檔在轉換瞬間有 0.3 秒延遲。幻網戰隊立即載入快速斜傳腳本，由小開精準給球，雷霆 R 直搗黃龍。
        </div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">📍 Phase 3：終局 2-1 封神之役</div>
        <div class="tactical-box-text">
          第 89 分鐘，比分 1-1 平局膠著，阿鐵成功撲下對手反撲，小幽秒傳小幫手，再轉小開斜塞禁區，Thunder Striker R 迎球抽射破網——2-1 絕殺哨響！
        </div>
      </div>

      <div class="spread-footer">
        <span>PHANTOMGRID TACTICAL SYSTEM</span>
        <span>PAGE 03 (SHEET 2 RIGHT)</span>
      </div>
    `
  }},

  // SPREAD 2 (Sheet 3): 4-Panel Comic Strip & Dialogue
  {{
    type: "comic",
    sheetNum: 3,
    left: `
      <div class="dossier-header">
        <div class="dossier-tag">OFFICIAL 4-PANEL MANGA // VOL.03</div>
        <div class="dossier-title">EP01《綠茵掠食者覺醒》<span class="gold-accent">四格漫畫</span></div>
      </div>

      <div class="image-showcase" onclick="openLightbox('{COMIC_B64}')" title="點擊放大檢視四格漫畫">
        <img src="{COMIC_B64}" alt="4-Panel Comic Strip">
        <div class="image-overlay-badge">🔍 點擊放大全螢幕檢視</div>
      </div>

      <div class="spread-footer">
        <span>MANGA STRIP: EP01 FULL RENDER</span>
        <span>PAGE 04 (SHEET 3 LEFT)</span>
      </div>
    `,
    right: `
      <div class="dossier-header">
        <div class="dossier-tag">SCENE BREAKDOWN & DIALOGUE</div>
        <div class="dossier-title">熱血戰況<span class="gold-accent">逐格分鏡解析</span></div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">【第一格】⚡ 逆風開局 · 哨聲再起</div>
        <div class="tactical-box-text">
          <strong>小幫手：</strong>「對手羚羊隊壓上了！全員保持陣形穩定，不要慌！」<br>
          <strong>阿鐵：</strong>「放心吧，球門由我守護，一隻蒼蠅也休想飛進去！」
        </div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">【第二格】🎯 靈犀連線 · 拓撲運算</div>
        <div class="tactical-box-text">
          <strong>小幽：</strong>「斷球成功！小開，空檔在右路！」<br>
          <strong>小開：</strong>「收到！最佳軌跡計算完畢，穿透傳球——走起！」
        </div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">【第三格】💥 掠食者出擊 · 凌空抽射</div>
        <div class="tactical-box-text">
          <strong>Thunder Striker R：</strong>「這球太棒了！綠茵掠食者——終極獵殺抽射！！」<br>
          <em>（伴隨劇烈的音爆破空聲，足球如雷霆般撕裂球網！）</em>
        </div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">【第四格】🏆 終局 2-1 · 三連勝登頂</div>
        <div class="tactical-box-text">
          <strong>全隊合唱：</strong>「贏了！！三連勝！！王者獎盃到手！！」<br>
          <strong>Jack 哥：</strong>「打得漂亮！今晚開罐罐大肆慶祝！」
          <div style="text-align:right; margin-top:4px;"><span class="seal-stamp">總指揮官硃砂令</span></div>
        </div>
      </div>

      <div class="spread-footer">
        <span>PHANTOMGRID DIALOGUE DOSSIER</span>
        <span>PAGE 05 (SHEET 3 RIGHT)</span>
      </div>
    `
  }},

  // SPREAD 3 (Sheet 4): AWS Match 2-1 Verification & MVP Dossier
  {{
    type: "match",
    sheetNum: 4,
    left: `
      <div class="dossier-header">
        <div class="dossier-tag">OFFICIAL MATCH VERIFICATION</div>
        <div class="dossier-title">AWS 實戰終局<span class="gold-accent">2-1 計分板認證</span></div>
      </div>

      <div class="image-showcase" onclick="openLightbox('{MATCH_B64}')" title="點擊放大官方實戰戰報截圖">
        <img src="{MATCH_B64}" alt="AWS Match Scoreboard">
        <div class="image-overlay-badge">🔍 點擊放大官方戰報截圖</div>
      </div>

      <div class="spread-footer">
        <span>AWS AGENTIC FOOTBALL VERIFIED</span>
        <span>PAGE 06 (SHEET 4 LEFT)</span>
      </div>
    `,
    right: `
      <div class="dossier-header">
        <div class="dossier-tag">MVP DOSSIER // MATCH ANALYTICS</div>
        <div class="dossier-title">決賽 MVP<span class="gold-accent">Thunder Striker R</span></div>
      </div>

      <div class="tactical-box" style="border-color:var(--gold-primary); background:rgba(245, 158, 11, 0.08);">
        <div class="tactical-box-title" style="color:var(--gold-glow); font-size:0.95rem;">
          ⭐ 賽事 MVP 官方評分：9.8 / 10.0 (滿分神級表現)
        </div>
        <div class="tactical-box-text">
          在下半場第 89 分鐘的壓哨絕殺，展現了頂級掠食者的決策爆發力，帶領幻網戰隊取得三連勝！
        </div>
      </div>

      <div class="tactical-box">
        <div class="tactical-box-title">📊 實戰戰術雷達與數據指標</div>
        <table class="stats-table">
          <tr>
            <td>進球數 (Goals)</td>
            <td style="color:var(--gold-primary); font-weight:700;">2 球 (梅開二度)</td>
            <td>射正率</td>
            <td style="color:var(--cyan-neon); font-weight:700;">85.7%</td>
          </tr>
          <tr>
            <td>傳球成功率</td>
            <td style="color:var(--cyan-neon); font-weight:700;">94.2%</td>
            <td>衝刺次數</td>
            <td>38 次</td>
          </tr>
          <tr>
            <td>全場控球率</td>
            <td>68.4% (壓倒性)</td>
            <td>戰術執行度</td>
            <td style="color:var(--gold-primary); font-weight:700;">100% PASS</td>
          </tr>
        </table>
      </div>

      <div class="quote-proclamation" style="margin-top:10px;">
        「三連勝不是偶然，而是 20 位 Agent 相互協作、無畏進擊的必然結晶！」
      </div>

      <div class="spread-footer">
        <span>PHANTOMGRID MVP REPORT</span>
        <span>PAGE 07 (SHEET 4 RIGHT)</span>
      </div>
    `
  }},

  // SPREAD 4 (Sheet 5): Back Cover & Series Summary
  {{
    type: "backcover",
    sheetNum: 5,
    left: `
      <div style="display:flex; flex-direction:column; height:100%; justify-content:center; padding:20px;">
        <div class="dossier-header">
          <div class="dossier-tag">SERIES COMPENDIUM // VOL.01-03</div>
          <div class="dossier-title">PHANTOMGRID<span class="gold-accent">三部曲全集巡禮</span></div>
        </div>

        <div class="tactical-box">
          <div class="tactical-box-title">📘 第一本：日常生活篇 (01_日常生活篇)</div>
          <div class="tactical-box-text">
            揭密 20 位 Agent 基地日常，小幫手晨間點名、小開修 Bug 奇遇、阿鐵健身日常。
          </div>
        </div>

        <div class="tactical-box">
          <div class="tactical-box-title">📕 第二本：榮耀慶功篇 (02_榮耀慶功篇)</div>
          <div class="tactical-box-text">
            大戰凱旋後的基地盛宴！Jack 哥親頒榮譽勳章，歡慶派對與熱血回憶錄。
          </div>
        </div>

        <div class="tactical-box" style="border-color:var(--gold-primary);">
          <div class="tactical-box-title" style="color:var(--gold-primary);">📗 第三本：熱血賽事篇 (03_熱血賽事篇)</div>
          <div class="tactical-box-text">
            AWS Agentic Football Cup 3 連勝王者之師！綠茵掠食者陣形拓撲與決賽 2-1 絕殺！
          </div>
        </div>

        <div class="spread-footer">
          <span>PHANTOMGRID TRILOGY CODEX</span>
          <span>PAGE 08 (SHEET 5 LEFT)</span>
        </div>
      </div>
    `,
    right: `
      <div class="cover-layout">
        <div class="corner-tr"></div><div class="corner-br"></div>
        <div class="trophy-seal-box" style="margin-bottom:18px;">
          <div class="trophy-icon">🛡️</div>
          <div class="trophy-text">王者認證</div>
        </div>

        <div class="cover-badge-top" style="margin-bottom:12px;">3-VOLUME SAGA COMPLETE</div>
        <h2 style="font-size:1.8rem; font-weight:900; color:#fff; margin-bottom:6px;">三連勝典藏·圓滿封冊</h2>
        <div style="font-size:0.85rem; color:var(--cyan-neon); font-family:monospace; margin-bottom:20px;">
          DOCUMENT HASH: SHA256-PHANTOMGRID-V3-3WIN
        </div>

        <div style="font-size:0.85rem; color:#cbd5e1; line-height:1.6; max-width:440px; margin-bottom:24px;">
          感謝最高指揮官 <strong>霸丸總指揮官 Jack 哥</strong> 的卓越領導！<br>
          本活頁冊遵循 30 頁單本規格，第 1-5 頁已全數收錄完成。
        </div>

        <div style="display:flex; gap:12px;">
          <a href="../index.html" class="btn-nav" style="text-decoration:none;">📚 返回漫畫總專區</a>
          <a href="../../11_📸_PHANTOMGRID_開源戰隊寫真相冊/index.html" class="btn-nav" style="text-decoration:none;">📸 前往寫真相冊</a>
        </div>

        <div class="spread-footer" style="width:100%;">
          <span>PHANTOMGRID MASTER ARCHIVE</span>
          <span>PAGE 08 (SHEET 5 RIGHT · BACK COVER)</span>
        </div>
      </div>
    `
  }}
];

let currentSpread = 0;
let soundEnabled = true;
let isFlipping = false;

// Web Audio Synthetic Paper Swoosh
const AudioContext = window.AudioContext || window.webkitAudioContext;
let audioCtx = null;

function playPageFlipSound() {{
  if (!soundEnabled) return;
  try {{
    if (!audioCtx) {{
      audioCtx = new AudioContext();
    }}
    if (audioCtx.state === 'suspended') {{
      audioCtx.resume();
    }}
    
    const bufferSize = audioCtx.sampleRate * 0.18; // 180ms
    const buffer = audioCtx.createBuffer(1, bufferSize, audioCtx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {{
      data[i] = (Math.random() * 2 - 1) * Math.exp(-i / (bufferSize * 0.35));
    }}
    
    const noise = audioCtx.createBufferSource();
    noise.buffer = buffer;
    
    const filter = audioCtx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(1200, audioCtx.currentTime);
    filter.frequency.exponentialRampToValueAtTime(280, audioCtx.currentTime + 0.18);
    
    const gain = audioCtx.createGain();
    gain.gain.setValueAtTime(0.32, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + 0.18);
    
    noise.connect(filter);
    filter.connect(gain);
    gain.connect(audioCtx.destination);
    noise.start();
  }} catch (e) {{
    console.warn("Audio not initialized yet:", e);
  }}
}}

function renderSpread(index) {{
  const spread = spreads[index];
  document.getElementById('leftContent').innerHTML = spread.left;
  document.getElementById('rightContent').innerHTML = spread.right;
  
  document.getElementById('scrubber').value = index;
  document.getElementById('pageCounter').textContent = `SPREAD 0${{index + 1}} / 0${{spreads.length}}`;
  
  document.getElementById('btnPrev').disabled = (index === 0);
  document.getElementById('btnNext').disabled = (index === spreads.length - 1);
}}

function triggerFlipAnimation(direction, nextIndex) {{
  if (isFlipping) return;
  isFlipping = true;
  playPageFlipSound();

  const leaf = document.getElementById('flipLeaf');
  leaf.className = 'flip-leaf ' + (direction === 'next' ? 'flip-leaf-right' : 'flip-leaf-left');
  leaf.style.display = 'block';

  setTimeout(() => {{
    currentSpread = nextIndex;
    renderSpread(currentSpread);
  }}, 300);

  setTimeout(() => {{
    leaf.style.display = 'none';
    leaf.className = 'flip-leaf';
    isFlipping = false;
  }}, 650);
}}

function flipNext() {{
  if (currentSpread < spreads.length - 1 && !isFlipping) {{
    triggerFlipAnimation('next', currentSpread + 1);
  }}
}}

function flipPrev() {{
  if (currentSpread > 0 && !isFlipping) {{
    triggerFlipAnimation('prev', currentSpread - 1);
  }}
}}

function goToSpread(val) {{
  val = parseInt(val, 10);
  if (val !== currentSpread && val >= 0 && val < spreads.length && !isFlipping) {{
    const dir = val > currentSpread ? 'next' : 'prev';
    triggerFlipAnimation(dir, val);
  }}
}}

// Keyboard Controls
window.addEventListener('keydown', (e) => {{
  if (e.key === 'ArrowRight' || e.key === ' ' || e.key === 'PageDown') {{
    flipNext();
  }} else if (e.key === 'ArrowLeft' || e.key === 'PageUp') {{
    flipPrev();
  }} else if (e.key === 'Home') {{
    goToSpread(0);
  }} else if (e.key === 'End') {{
    goToSpread(spreads.length - 1);
  }} else if (e.key === 'f' || e.key === 'F') {{
    toggleFullscreen();
  }}
}});

// Sound toggle
document.getElementById('btnSound').addEventListener('click', () => {{
  soundEnabled = !soundEnabled;
  document.getElementById('btnSound').textContent = soundEnabled ? "🔊 翻頁聲: 開" : "🔇 翻頁聲: 關";
}});

// Fullscreen Functions
function toggleFullscreen() {{
  if (!document.fullscreenElement && !document.webkitFullscreenElement) {{
    if (document.documentElement.requestFullscreen) {{
      document.documentElement.requestFullscreen().catch(() => {{}});
    }} else if (document.documentElement.webkitRequestFullscreen) {{
      document.documentElement.webkitRequestFullscreen();
    }}
  }} else {{
    if (document.exitFullscreen) {{
      document.exitFullscreen().catch(() => {{}});
    }} else if (document.webkitExitFullscreen) {{
      document.webkitExitFullscreen();
    }}
  }}
}}

function updateFullscreenUI() {{
  const isFs = !!(document.fullscreenElement || document.webkitFullscreenElement);
  const text = isFs ? "🗗 退出全螢幕" : "⛶ 全螢幕";
  const btnTop = document.getElementById('btnFullscreen');
  const btnBinder = document.getElementById('btnBinderFullscreen');
  const btnNav = document.getElementById('btnNavFullscreen');
  if (btnTop) btnTop.textContent = text;
  if (btnBinder) btnBinder.textContent = text;
  if (btnNav) btnNav.textContent = text;
}}

document.getElementById('btnFullscreen').addEventListener('click', toggleFullscreen);
document.addEventListener('fullscreenchange', updateFullscreenUI);
document.addEventListener('webkitfullscreenchange', updateFullscreenUI);

// Lightbox
function openLightbox(src) {{
  const lb = document.getElementById('lightbox');
  const img = document.getElementById('lightboxImg');
  img.src = src;
  lb.style.display = 'flex';
}}

function closeLightbox() {{
  document.getElementById('lightbox').style.display = 'none';
}}

// Initialize
renderSpread(0);
</script>
</body>
</html>
"""

with open(INDEX_HTML, "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"[SUCCESS] Wrote 3D loose-leaf flipbook with Base64 assets to: {INDEX_HTML}")
print(f"File size: {os.path.getsize(INDEX_HTML)} bytes")
