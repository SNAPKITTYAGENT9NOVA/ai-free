# Universal Word Dialect Stack: Phase 2 Integration Testing Plan

**Date:** 2026-10-03  
**Status:** Phase 1B COMPLETE ✅ → Phase 2 INITIATED  
**Agent 4 (Integration & Testing):** Ready to begin

---

## Executive Summary

Phase 1B delivered the complete formal verification infrastructure with 69 proven theorems across all four Lean proof modules. Phase 2 focuses on:

1. **End-to-End Integration Testing** — Validate semantic preservation across all language frontends and ISA backends
2. **Proof Validation Pipeline** — Type-check all Lean proofs once toolchain available
3. **Architecture Documentation** — Link formal specifications to implementation code
4. **Performance Baseline** — Establish benchmarks for future optimization

---

## Agent 4: Integration Testing Scope

| Task | Component | Tests | Status |
|------|-----------|-------|--------|
| **WORD Type Invariants** | src/word_core/types.py | 26 | ✅ Ready |
| **VM Determinism** | src/word_machine/vm.py | 33 | ✅ Ready |
| **Lexer Coverage** | src/frontends/{bcpl,forth,wolfram}/ | 19 | ✅ Ready |
| **BCPL → x86 Pipeline** | bcpl_lexer → bcpl_parser → bcpl_to_word_ir → codegen_x86 | 8 | ✅ Ready |
| **Forth → x86 Pipeline** | forth_lexer → forth_to_word_ir → codegen_x86 | TBD | ⏳ New |
| **Wolfram → x86 Pipeline** | wolfram_lexer → wolfram_to_word_ir → codegen_x86 | TBD | ⏳ New |
| **Register Allocation Correctness** | codegen_x86 (greedy coloring, spilling, frame layout) | TBD | ⏳ New |
| **Cross-Frontend Semantics** | Same source → BCPL vs Forth vs Wolfram → same x86 | TBD | ⏳ New |
| **Memory Safety** | ALLOC no-overlap, LOAD/STORE bounds, stack isolation | TBD | ⏳ New |
| **Control Flow Correctness** | JMP, CALL, RET target validity; recursion depth bounds | TBD | ⏳ New |

---

## Phase 2A: New Integration Test Suite (Agent 4, Week 1)

### 2A.1: Forth → x86 End-to-End
**File:** `tests/integration/test_forth_to_x86.py`

```
Test: forth_program_simple_arithmetic()
  Source: "5 3 + ."
  Expected: Stack result = 8
  IR nodes: [DUP, DROP, ADD, LOAD, STORE]
  x86 output: Valid GNU AT&T assembly
  
Test: forth_program_with_memory()
  Source: ": double dup @ * ; 100 double ."
  Expected: Memory allocation, pointer arithmetic, register spillage
  
Test: forth_control_flow()
  Source: ": countdown dup if dup 1 - countdown then ;"
  Expected: JMP targets valid, stack frames correct
```

**Success Criteria:**
- 5+ integration tests for Forth
- All tests pass with deterministic results
- Generated x86 assembly is syntactically valid

### 2A.2: Wolfram → x86 End-to-End
**File:** `tests/integration/test_wolfram_to_x86.py`

```
Test: wolfram_scalar_expression()
  Source: "2 * 3 + 5"
  Expected: Scalar evaluation preserves semantics
  
Test: wolfram_matrix_multiply()
  Source: "A = {{1,2},{3,4}}; B = {{5,6},{7,8}}; C = A . B"
  Expected: Nested loops lower to IR correctly; register allocation handles large temp count
  
Test: wolfram_tensor_indexing()
  Source: "T[[1,2,3]]"
  Expected: Pointer arithmetic with multiple dimensions
```

**Success Criteria:**
- 5+ integration tests for Wolfram
- Matrix operations generate correct IR node sequences
- x86 codegen produces valid assembly

### 2A.3: Register Allocation Validation
**File:** `tests/integration/test_register_allocation.py`

```
Test: greedy_coloring_terminates()
  Given: Interference graph with 100 virtual registers
  Expected: Greedy allocator produces valid coloring in O(V+E) time
  
Test: spill_correct_retrieval()
  Given: Program requiring > 16 registers
  Expected: Spilled values correctly saved/restored; stack frame valid
  
Test: move_coalescing_valid()
  Given: IR with many r1=r2 moves
  Expected: Coalescing reduces register pressure; no correctness loss
  
Test: no_register_conflict_after_allocation()
  Given: Allocated program
  Expected: No two interfering variables share same physical register
```

**Success Criteria:**
- All allocation invariants proven dynamically
- No register collisions after allocation
- Stack usage ≤ limit defined in IR

### 2A.4: Cross-Frontend Semantic Equivalence
**File:** `tests/integration/test_cross_frontend_equivalence.py`

```
Test: same_logic_bcpl_forth_wolfram()
  BCPL:    int add(int a, int b) { return a + b; }
  Forth:   : add + ;
  Wolfram: a + b
  
  Expected: All three compile to same x86 instructions (modulo register allocation)
  
Test: memory_access_equivalence()
  BCPL:    arr[i] = val
  Forth:   arr i + @ !
  Wolfram: arr[[i]]
  
  Expected: All three generate identical LOAD/STORE IR nodes
```

**Success Criteria:**
- At least 3 cross-frontend tests
- All semantically equivalent programs produce same IR
- Register allocation differences are only due to greedy heuristic, not algorithm

---

## Phase 2B: Lean Proof Type-Checking (When Toolchain Available)

**File:** `.github/workflows/lean_proofs.yml` (already scaffolded)

```yaml
name: Lean Proof Validation
on: [push, pull_request]

jobs:
  lean-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Lean 4
        run: curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh
      - name: Type-check proofs
        run: cd proofs && lake build
      - name: Validate no sorry/axiom
        run: ./check_proof_completeness.sh
```

**Success Criteria:**
- All Lean files pass `lean --check`
- No `sorry` clauses detected
- No `axiom` declarations detected
- CI enforces proof validation on every commit

---

## Phase 2C: Documentation & Architecture Linking

**File:** `docs/FORMAL_SPECIFICATION.md` (TBD)

Link each theorem to implementation:

```markdown
## WordType.lean → src/word_core/types.py

### Theorem: word32_bounded
**Proof:** Lean/WordType.lean:34-45
**Implementation:** src/word_core/types.py:23-28 (WORD32.__post_init__)
**Invariant:** ∀w : Fin(2^32), w.val < 2^32
**Runtime Check:** WORD32(x) raises ValueError if x >= 2^32

### Theorem: ptr_word64_compatible
**Proof:** Lean/WordType.lean:67-82
**Implementation:** src/word_core/types.py:90-110 (PTR.from_word64, PTR.to_word64)
**Invariant:** PTR and WORD64 have identical representation
**Runtime Check:** Conversion preserves bit pattern
```

---

## Success Criteria for Phase 2

### Immediate (Week 1)
- ✅ All 86 existing tests passing (foundation + compiler)
- ⏳ 15+ new integration tests (Forth, Wolfram, register allocation, cross-frontend)
- ⏳ All new tests passing deterministically
- ⏳ x86 codegen produces valid, executable assembly

### Medium-term (Week 2)
- ⏳ Lean 4 toolchain integrated into CI
- ⏳ All 69 proofs pass `lean --check`
- ⏳ Proof completeness validator deployed

### Long-term (Week 3+)
- ⏳ Architecture documentation complete with proof links
- ⏳ Benchmarks established (compilation time, register allocation quality)
- ⏳ Version 1.0 release candidate ready

---

## Failure Scenarios & Escalation

### Scenario A: New test fails (semantic mismatch in frontend)
**Detection:** Integration test fails on Forth or Wolfram lowering
**Resolution:** Agent 4 traces failure to frontend IR generation; escalates to Agent 2 for fix
**Commit:** Only after fix validated

### Scenario B: Proof type-check fails (new Lean 4 issue)
**Detection:** CI runs `lean --check` and finds syntax/type error
**Resolution:** Agent 4 escalates to Agent 3; Agent 3 fixes proof
**Commit:** Only after proof validates

### Scenario C: Register allocation produces invalid coloring
**Detection:** Integration test verifies no register conflicts; test fails
**Resolution:** Agent 4 analyzes interference graph; may require codegen refactor
**Commit:** Only after correctness proven

### Scenario D: Cross-frontend semantics differ
**Detection:** Same program in BCPL, Forth, Wolfram produces different x86
**Resolution:** Agent 4 identifies which frontend has wrong IR; escalates to Agent 2
**Commit:** Only after all three match

---

## Agent 4 Responsibilities

1. **Write comprehensive integration tests** for all three frontends
2. **Validate semantic preservation** across compilation pipeline
3. **Test register allocation** with adversarial inputs (high register pressure)
4. **Verify determinism** (same input → same output always)
5. **Establish performance baselines** for future optimization
6. **Link documentation** from proofs to implementation
7. **Escalate failures** with reproducible test cases

---

## Phase 2 Unblock Conditions

✅ **All Met:**
- Agent 1 foundation types, VM, IR published
- Agent 2 all three lowering passes complete
- Agent 3 all 69 theorems formalized and validated
- All existing unit tests passing (86 tests)
- No blocking dependencies remain

**Agent 4 can begin immediately.**

---

## Next Steps (Now)

1. **Spawn Agent 4** with this Phase 2 plan
2. **Agent 4 begins** 2A (new integration tests)
3. **Parent monitors** test results, escalates failures
4. **Once CI ready**, integrate Lean type-checking (2B)
5. **Documentation** concurrent with testing (2C)

---

_Coordination for Phase 2 Integration Testing_  
_Initiated: 2026-10-03_  
_Status: Ready to begin_
