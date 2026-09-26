# -*- coding: utf-8 -*-
"""
Record high-definition live demonstration video using Playwright & FFmpeg.
Produces a dynamic, real-time 1080P MP4 with synchronized professional voiceover.
"""

import asyncio
import os
import shutil
import subprocess
import sys
from pathlib import Path

from playwright.async_api import async_playwright

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

WORKSPACE = Path("C:/Users/user/.gemini/antigravity/worktrees/260803_opencode/ping_assistant")
ASSETS_DIR = WORKSPACE / "bobflow_demo_assets"
HTML_PATH = (ASSETS_DIR / "live_demo.html").resolve()
AUDIO_PATH = (ASSETS_DIR / "voiceover.mp3").resolve()
TEMP_REC_DIR = ASSETS_DIR / "temp_rec"
OUTPUT_MP4 = (ASSETS_DIR / "bobflow_demo_1080p.mp4").resolve()
GDRIVE_VAULT = Path("G:/我的雲端硬碟/AI產出成品總庫/IBM_BOB2_HACKATHON_DELIVERY")


async def record_screen():
    print("🎬 [Stage 1/2] Recording real-time browser session via Playwright...")
    if TEMP_REC_DIR.exists():
        shutil.rmtree(TEMP_REC_DIR)
    TEMP_REC_DIR.mkdir(parents=True, exist_ok=True)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        context = await browser.new_context(
            record_video_dir=str(TEMP_REC_DIR),
            record_video_size={"width": 1920, "height": 1080},
            viewport={"width": 1920, "height": 1080},
        )
        page = await context.new_page()

        # Load live interactive HTML
        url = HTML_PATH.as_uri()
        print(f"   Navigating to: {url}")
        await page.goto(url)

        # Wait exactly 115.5 seconds to capture all live animations & terminal logs (>90s requirement)
        print("   Capturing live interaction stream (115.5 seconds)...")
        await page.wait_for_timeout(115500)

        # Close page and context to flush video to disk
        await page.close()
        await context.close()
        await browser.close()

    # Find the recorded webm file
    webm_files = list(TEMP_REC_DIR.glob("*.webm"))
    if not webm_files:
        raise FileNotFoundError("No recorded video found in temp directory!")
    raw_video = webm_files[0]
    print(f"✅ Stage 1 Complete: Captured raw video ({raw_video.stat().st_size} bytes)")
    return raw_video


def encode_with_audio(raw_video_path: Path):
    print("\n🎞️ [Stage 2/2] Encoding 1080P MP4 with synchronized Edge-TTS voiceover...")
    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(raw_video_path),
        "-i",
        str(AUDIO_PATH),
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-crf",
        "22",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-shortest",
        "-pix_fmt",
        "yuv420p",
        str(OUTPUT_MP4),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"❌ FFmpeg error: {res.stderr}")
        raise RuntimeError("FFmpeg encoding failed!")

    print(f"✅ Stage 2 Complete: Rendered {OUTPUT_MP4} ({OUTPUT_MP4.stat().st_size / 1024 / 1024:.2f} MB)")

    # Clean up temp webm
    if TEMP_REC_DIR.exists():
        shutil.rmtree(TEMP_REC_DIR)

    # Sync to G-Drive vault
    if GDRIVE_VAULT.exists():
        shutil.copy2(OUTPUT_MP4, GDRIVE_VAULT / OUTPUT_MP4.name)
        print(f"🏦 Synced to G-Drive Vault: {GDRIVE_VAULT / OUTPUT_MP4.name}")


async def main():
    raw_video = await record_screen()
    encode_with_audio(raw_video)
    print("\n🎉 [ALL COMPLETE] Dynamic 1080P live demonstration video generated successfully!")


if __name__ == "__main__":
    asyncio.run(main())
