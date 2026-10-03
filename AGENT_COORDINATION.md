# Three-Tower Agent Coordination

**Status:** All 3 agents active and coordinated.  
**Synchronization:** Dependency graph enforces ordering.  
**Gatekeeper:** Agent 3 (Proofs) blocks commits if semantic claims unproven.

---

## Agent Sessions

| Agent | Session ID | Tower | Role | Critical Path |
|-------|-----------|-------|------|----------------|
| **Agent 1** | `session_01DdR2DnBha5nM8Br7bsULns` | Foundation | Types, VM, IR | YES (blocks 2 & 3) |
| **Agent 2** | `session_01UG9GXKtQandKyXC8X7BcVP` | Compilers | Frontends, codegen | Depends on 1 |
| **Agent 3** | `session_01NrLba7FfMTj9bcFcDAZQzG` | Proofs | Lean theorems | Validates 1 & 2 |

---

## Dependency Graph

```
Agent 1: Foundation
  ├── types.py (WORD[N], PTR, invariants)
  ├── vm.py (RegisterFile, Memory, Stack, execute)
  ├── ir_ast.py (canonical nodes)
  └── tests/unit/
       ├── test_word_types.py
       └── test_word_machine.py
       
         ↓ PUBLISHES INTERFACES
         
Agent 2: Compilers (parallel)
  ├── bcpl_lexer.py (can start immediately)
  ├── forth_lexer.py (can start immediately)
  ├── wolfram_lexer.py (can start immediately)
  │
  └── [BLOCKED on Agent 1 ir_ast.py]
       ├── bcpl_to_word_ir.py
       ├── forth_to_word_ir.py
       ├── wolfram_to_word_ir.py
       └── codegen_x86.py (Word IR → asm)
       
         ↓ PUBLISHES LOWERING FUNCTIONS
         
Agent 3: Proofs (parallel from start, formalization when ready)
  ├── Lake project (can start immediately)
  ├── WordType.lean stubs (can start immediately)
  ├── WordMachine.lean stubs (can start immediately)
  │
  └── [BLOCKED on Agent 1 types.py semantics]
       ├── BcplLowering.lean
       ├── ForthLowering.lean
       ├── WolframLowering.lean
       └── [BLOCKED on Agent 2 codegen_x86.py]
            └── CodegenX86.lean
            
         ↓ VALIDATES ALL CLAIMS
         
CI Pipeline (blocks on proof failure)
  ├── lean --check (all .lean files must pass)
  ├── pytest (unit + integration tests)
  └── perf regression (benchmark suite)
```

---

## Synchronization Points

### Point 1: Agent 1 publishes `types.py`
- **When:** types.py complete + unit tests passing
- **Signal:** Agent 1 commits and pushes
- **Impact:** Agent 3 can formalize WORD type theorems

### Point 2: Agent 1 publishes `vm.py` + `ir_ast.py`
- **When:** vm.py + ir_ast.py complete + tests passing
- **Signal:** Agent 1 commits and pushes
- **Impact:** Agent 2 unblocks and implements lowering
- **Impact:** Agent 3 formalizes VM semantics

### Point 3: Agent 2 publishes `bcpl_to_word_ir.py`
- **When:** BCPL frontend complete + tests passing
- **Signal:** Agent 2 commits and pushes
- **Impact:** Agent 3 formalizes BCPL lowering proof

### Point 4: Agent 2 publishes `codegen_x86.py`
- **When:** x86-64 code generation complete
- **Signal:** Agent 2 commits and pushes
- **Impact:** Agent 3 formalizes code generation proof

### Point 5: Agent 3 completes all proofs
- **When:** All 7 Lean files type-check (no `sorry`, no axioms)
- **Signal:** Agent 3 commits and CI passes `lean --check`
- **Impact:** Build is validated; can ship

---

## Communication Protocol

### Agent 1 → Agent 2 & 3
```
publish(interface, message):
  "ir_ast.py is stable. Here's the canonical node types: [...]"
  
Agent 2 and 3 respond:
  "received. Integrating against your interface."
```

### Agent 2 → Agent 3
```
publish(lowering_function, message):
  "bcpl_to_word_ir.py is complete. Lowering semantics: [...]"
  
Agent 3 responds:
  "received. Writing formal proof for your lowering."
```

### Agent 3 → All
```
if any_proof_incomplete:
  escalate("Theorem X cannot be proven. Semantic claim is invalid.")
  BLOCK BUILD
else:
  publish("all proofs complete. system is validated.")
```

---

## Failure Scenarios

### Scenario A: Agent 1 changes `ir_ast.py` after Agent 2 integrates
- **Detection:** Agent 2's tests fail (import error or semantic mismatch)
- **Resolution:** Agent 2 revalidates against new interface; Agent 3 re-proves theorems
- **Escalation:** If re-validation fails, halt and notify parent session

### Scenario B: Agent 2's lowering violates semantic equivalence
- **Detection:** Agent 3 cannot prove the lowering theorem
- **Resolution:** Agent 3 escalates with counterexample; Agent 2 fixes lowering
- **Commit:** Only after proof succeeds

### Scenario C: Agent 3 discovers ISA leak in ir_ast.py
- **Detection:** Proof of codegen correctness fails because IR assumes x86-64 semantics
- **Resolution:** Agent 3 escalates; Agent 1 refactors ir_ast.py to be ISA-neutral
- **Impact:** May require Agent 2 to re-implement codegen

---

## Status Tracking

Each agent maintains a status checklist in their session. Parent session (this one) monitors:

```
Agent 1 (Foundation):
  [ ] types.py complete
  [ ] vm.py complete
  [ ] ir_ast.py complete
  [ ] tests passing

Agent 2 (Compilers):
  [ ] bcpl_lexer.py
  [ ] forth_lexer.py
  [ ] wolfram_lexer.py
  [ ] [await Agent 1]
  [ ] bcpl_to_word_ir.py
  [ ] forth_to_word_ir.py
  [ ] wolfram_to_word_ir.py
  [ ] codegen_x86.py
  [ ] tests passing

Agent 3 (Proofs):
  [ ] Lake project
  [ ] WordType.lean theorems
  [ ] WordMachine.lean theorems
  [ ] [await Agent 1]
  [ ] BcplLowering.lean
  [ ] [await Agent 2]
  [ ] ForthLowering.lean
  [ ] WolframLowering.lean
  [ ] CodegenX86.lean
  [ ] EndToEndEquivalence.lean
  [ ] CI rules
  [ ] all proofs pass `lean --check`
```

---

## Expected Timeline

- **Days 1-2:** Agent 1 unblocked, builds foundation
- **Day 2 afternoon:** Agent 2 unblocks (after Agent 1 publishes ir_ast.py)
- **Day 2 afternoon:** Agent 3 begins BCPL lowering proof (after Agent 1 publishes types.py)
- **Days 3-4:** Agent 2 implements all three frontends + codegen
- **Days 3-5:** Agent 3 formalizes all lowering + codegen theorems
- **Day 5-6:** Integration tests, end-to-end verification
- **Day 7:** CI validation, final commit

---

## Victory Condition

**All three agents report complete + CI passes:**

```
✓ Agent 1: Foundation types, VM, IR, unit tests passing
✓ Agent 2: BCPL + Forth + Wolfram frontends, x86-64 codegen, tests passing
✓ Agent 3: All 7 Lean proofs complete, no sorry, CI blocks on proof failure
✓ CI: pytest + lean --check + perf regression all passing
✓ Commit: Merge to main with clean history

RESULT: Universal Word Dialect Stack deployed
```

---

## Parent Session Responsibilities (Main Agent)

1. Monitor all three agent sessions for status updates
2. Detect blocked scenarios (e.g., Agent 2 waiting for Agent 1)
3. Escalate conflicts (e.g., proof cannot be completed)
4. Final integration + validation before merge
5. Create commit with attribution to all three agents

---

## Do Not Deviate From This Plan

The three towers are interdependent. Parallelization saves time only if:
- Dependencies are honored (no premature integration)
- Interfaces are published clearly
- Proofs block incomplete claims (no workarounds)
- CI enforces proof completion

**If any agent feels pressure to bypass formal verification, escalate immediately.**
