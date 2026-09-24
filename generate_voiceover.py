"""Generate voiceover audio for BobFlow Demo Video."""

import asyncio
import edge_tts

VOICE = "en-US-AndrewMultilingualNeural"  # Professional energetic technical presenter

SCRIPT = (
    "Welcome to the official demonstration of BobFlow Agentic Engine, powered by IBM Bob 2.0. "
    "In traditional software development, single Large Language Models suffer from hallucinations, "
    "lack of architectural constraints, and zero automated verification loops. "
    "To solve this, BobFlow introduces a deterministic four-agent orchestration pipeline. "
    "First, the Orchestrator Agent ingests high-level specifications and breaks them down into atomic task tickets. "
    "Second, the Architect Agent audits interface contracts and compliance rules to ensure structural integrity. "
    "Third, the Coder Agent generates modular, production-ready code accelerated by IBM Bob 2.0 developer patterns. "
    "Finally, the Verifier Agent executes an automated unit-test sanity loop, ensuring zero-defect output. "
    "As shown in our live run, all boundary conditions and unit tests passed with 100 percent reliability. "
    "BobFlow enables autonomous, verifiable software engineering for modern development teams. "
    "Built for the IBM Bob 2.0 Hackathon. Thank you!"
)

async def main():
    communicate = edge_tts.Communicate(SCRIPT, VOICE, rate="+5%")
    await communicate.save("bobflow_demo_assets/voiceover.mp3")
    print("Voiceover generated successfully: bobflow_demo_assets/voiceover.mp3")

if __name__ == "__main__":
    asyncio.run(main())
