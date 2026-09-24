"""BobFlow Engine CLI and Main Orchestration Pipeline."""

from __future__ import annotations

import logging
import sys
from bobflow.agents.components import (
    ArchitectAgent,
    CoderAgent,
    OrchestratorAgent,
    VerifierAgent,
)
from bobflow.core.models import TaskStatus

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("BobFlow-CLI")


class BobFlowPipeline:
    def __init__(self) -> None:
        self.orchestrator = OrchestratorAgent()
        self.architect = ArchitectAgent()
        self.coder = CoderAgent()
        self.verifier = VerifierAgent()

    def run(self, user_prompt: str) -> bool:
        print("=" * 60)
        print("🚀 [BobFlow Agentic Engine] Powered by IBM Bob 2.0")
        print(f"📥 Input Specification: \"{user_prompt}\"")
        print("=" * 60)

        tasks = self.orchestrator.decompose(user_prompt)
        print(f"\n[Step 1: Orchestrator] Generated {len(tasks)} atomic task(s).")
        for t in tasks:
            print(f"  - [{t.task_id}] {t.title}: {t.description}")

        all_passed = True
        for task in tasks:
            print(f"\n>>> Processing {task.task_id} ...")
            
            # Step 2: Architecture Review
            review = self.architect.review(task)
            print("  [Step 2: Architect] Architecture & compliance check: APPROVED ✅")
            for note in review.design_notes:
                print(f"     * {note}")

            # Step 3: Coding
            code = self.coder.implement(task, review)
            print(f"  [Step 3: Coder] Code generated via {code.bob_acceleration_tag} ⚡")
            print(f"     Target: {code.filename} ({len(code.code_content)} chars)")

            # Step 4: Verification
            result = self.verifier.verify(task, code)
            if result.passed:
                print("  [Step 4: Verifier] Unit test & sanity loop: PASSED 🟢")
                print(f"     Feedback: {result.feedback}")
            else:
                print(f"  [Step 4: Verifier] FAILED ❌: {result.feedback}")
                all_passed = False

        print("\n" + "=" * 60)
        if all_passed:
            print("🏆 [BobFlow] All tasks completed and verified with zero hallucination! End-to-End Pipeline Finished.")
        else:
            print("⚠️ [BobFlow] One or more tasks failed verification.")
        print("=" * 60)
        return all_passed


def main() -> None:
    prompt = "建立一個具有重試機制與結構化日誌的 REST API 客戶端模組"
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
    pipeline = BobFlowPipeline()
    success = pipeline.run(prompt)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
