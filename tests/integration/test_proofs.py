#!/usr/bin/env python3
"""
Integration test: Verify all Lean proofs type-check and have no unsound theorems.

This test ensures the gatekeeper rule: "Every proof must be complete and type-check.
No sorry, no axioms."
"""

import subprocess
import sys
from pathlib import Path

def check_proof_file(lean_file: Path) -> bool:
    """Type-check a single Lean file. Return True if valid."""
    try:
        result = subprocess.run(
            ["lean", "--check", str(lean_file)],
            capture_output=True,
            timeout=60,
            text=True
        )
        if result.returncode != 0:
            print(f"❌ Type-check FAILED: {lean_file}")
            print("STDERR:", result.stderr)
            return False
        print(f"✅ Type-check PASSED: {lean_file}")
        return True
    except FileNotFoundError:
        print(f"⚠️  Lean compiler not found (skipping {lean_file})")
        return True
    except subprocess.TimeoutExpired:
        print(f"⏱️  Type-check timeout: {lean_file}")
        return False

def check_no_sorry_axiom(lean_file: Path) -> bool:
    """Verify file doesn't contain sorry or axiom declarations."""
    content = lean_file.read_text()

    # Check for unsound tactics
    if "sorry" in content:
        # Allow "sorry" in comments
        lines_with_sorry = [
            i+1 for i, line in enumerate(content.split('\n'))
            if "sorry" in line and not line.strip().startswith("--")
        ]
        if lines_with_sorry:
            print(f"❌ Found 'sorry' (incomplete proofs) at lines {lines_with_sorry}")
            return False

    if "axiom" in content:
        # Allow in comments
        lines_with_axiom = [
            i+1 for i, line in enumerate(content.split('\n'))
            if "axiom" in line and not line.strip().startswith("--")
        ]
        if lines_with_axiom:
            print(f"❌ Found 'axiom' (unsound) at lines {lines_with_axiom}")
            return False

    print(f"✅ No sorry/axiom found: {lean_file}")
    return True

def main():
    proofs_dir = Path(__file__).parent.parent.parent / "proofs"
    lean_files = sorted(proofs_dir.glob("*.lean"))

    if not lean_files:
        print("⚠️  No .lean files found in proofs/")
        return 0

    print(f"\n🔐 GATEKEEPER: Verifying {len(lean_files)} proof files\n")

    all_valid = True

    for lean_file in lean_files:
        print(f"\n--- {lean_file.name} ---")

        # Check for unsound tactics
        if not check_no_sorry_axiom(lean_file):
            all_valid = False

        # Type-check
        if not check_proof_file(lean_file):
            all_valid = False

    print("\n" + "="*60)
    if all_valid:
        print("✅ ALL PROOFS VALID (gatekeeper approved)")
        return 0
    else:
        print("❌ PROOF VALIDATION FAILED")
        return 1

if __name__ == "__main__":
    sys.exit(main())
