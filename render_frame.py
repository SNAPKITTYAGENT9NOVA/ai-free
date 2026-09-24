"""Render BobFlow 1080P demo screenshot with Playwright."""

import asyncio
import os
from playwright.async_api import async_playwright

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 1920, "height": 1080})
        html_path = os.path.abspath("bobflow_demo_assets/index.html")
        await page.goto(f"file:///{html_path}")
        await page.wait_for_timeout(1000)
        await page.screenshot(path="bobflow_demo_assets/frame.png")
        await browser.close()
        print("1080P Frame rendered: bobflow_demo_assets/frame.png")

if __name__ == "__main__":
    asyncio.run(main())
