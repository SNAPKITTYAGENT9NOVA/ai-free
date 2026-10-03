# Universal Word Dialect Stack: Implementation Plan
**Date:** 2026-10-03  
**Branch:** `ccr-b6868d11-15l9w2`  
**Vision:** Transform `ai-free` from Phantom Grid orchestration platform into a formally-verifiable Word Dialect compiler infrastructure.

---

## Phase 1: Architectural Foundation (Days 1-2)

### 1.1 Core Type System (`src/word_core/`)
```
word_core/
├── types.py              # WORD[N], PTR, Address primitives (Lean-style)
├── word_ir.py            # Universal Word IR AST
├── semantics.py          # Proof of semantic preservation
└── __init__.py
```

**Deliverables:**
- `WORD32`, `WORD64`, `WORD128` type definitions with invariant proofs
- PTR (pointer) as first-class citizen, representation-compatible with WORD
- Canonical IRNode enum: `WORD`, `PTR`, `LOAD`, `STORE`, `ADD`, `SUB`, `MUL`, `AND`, `OR`, `XOR`, `SHL`, `SHR`, `ROT`, `CMP`, `JMP`, `CALL`, `RET`, `ALLOC`
- Proof obligations for type safety

### 1.2 Word Machine Virtual Machine (`src/word_machine/`)
```
word_machine/
├── vm.py                 # Word machine state: W0..WN, P0..PN, memory, stack
├── memory_model.py       # Linear address space, allocation tracking
├── execution.py          # Deterministic instruction execution
└── __init__.py
```

**Deliverables:**
- Configurable register count (e.g., 16 general-purpose WORD registers)
- Unified memory model: ALLOC → pointer → LOAD/STORE
- Stack-based calling convention
- Halt-detect + cycle counting for termination

### 1.3 Intermediate Representation (`src/word_ir/`)
```
word_ir/
├── ir_ast.py            # AST definition for Word IR
├── ir_printer.py        # Pretty-print Word IR
├── ir_parser.py         # Parse text IR → AST
└── __init__.py
```

---

## Phase 2: Lowering Pipeline (Days 3-4)

### 2.1 Wolfram → Word IR Compiler (`src/compilers/wolfram_to_word_ir/`)
```
wolfram_to_word_ir/
├── wolfram_parser.py     # Parse Wolfram expressions (symbolic math)
├── tensor_lowering.py    # Matrix/tensor → scalar operations
├── ir_generator.py       # Generate Word IR from lowered AST
├── proofs.py             # Prove semantic correctness of lowering
└── __init__.py
```

**Deliverables:**
- Matrix multiplication C = A . B → loop of LOAD + MUL + ADD + STORE
- Tensor indexing → pointer arithmetic + LOAD
- Proof: Wolfram semantics ≡ generated Word IR semantics (modulo finite precision)

### 2.2 Word IR → Assembly Lowering (`src/compilers/word_ir_to_asm/`)
```
word_ir_to_asm/
├── register_allocator.py  # Word registers → machine registers
├── codegen_x86.py         # Word IR → x86-64 assembly
├── codegen_arm.py         # Word IR → ARM Thumb-2 assembly
├── codegen_riscv.py       # Word IR → RISC-V assembly
└── __init__.py
```

**Deliverables:**
- Language-independent register allocation (graph coloring)
- Proof: Assembly preserves Word IR semantics under ISA contract
- x86, ARM, RISC-V backends interchangeable

### 2.3 Language Frontends (`src/frontends/`)
```
frontends/
├── bcpl/
│   ├── bcpl_parser.py     # BCPL lexer + parser
│   ├── bcpl_to_word_ir.py # BCPL → Word IR
│   └── __init__.py
├── forth/
│   ├── forth_parser.py     # Forth interpreter
│   ├── forth_to_word_ir.py # Forth → Word IR
│   └── __init__.py
└── wolfram/
    ├── wolfram_parser.py
    └── wolfram_to_word_ir.py
```

---

## Phase 3: Testing & Verification (Days 5-6)

### 3.1 Unit Tests (`tests/unit/`)
```
tests/unit/
├── test_word_types.py         # WORD type invariants
├── test_word_machine.py        # VM execution correctness
├── test_wolfram_lowering.py    # Wolfram → Word IR preservation
├── test_word_ir_to_x86.py      # Code generation correctness
└── test_integration.py         # End-to-end: Wolfram → x86
```

### 3.2 Proof Artifacts (`proofs/`)
```
proofs/
├── word_type_safety.lean       # Lean proof: WORD type safety
├── semantic_preservation.lean  # Wolfram ≈ Word IR (w/ precision bounds)
├── register_allocation.lean    # Graph coloring termination
└── README.md                   # Proof status tracking
```

### 3.3 Benchmark Suite (`benchmarks/`)
```
benchmarks/
├── matrix_multiply.w           # Wolfram: C = A . B
├── matrix_multiply.wir         # Hand-written Word IR
├── matrix_multiply.x86.s       # Generated x86-64
├── perf_comparison.py          # Measure MIPS, cycle count
└── README.md
```

---

## Phase 4: Documentation & Artifacts (Days 7)

### 4.1 Architecture Specification (`docs/`)
```
docs/
├── ARCHITECTURE.md              # High-level design
├── WORD_DIALECT_SPEC.md         # Formal ISA spec
├── LOWERING_PIPELINE.md         # Transformation proofs
├── WOLFRAM_SEMANTICS.md         # Wolfram → Word IR mapping
├── ASSEMBLY_BACKENDS.md         # ISA-specific details
└── DEVELOPER_GUIDE.md           # How to extend
```

### 4.2 Interactive Playground
```
playground/
├── web_ui/                      # HTML + JS artifact
├── repl.py                      # REPL: enter Wolfram → see Word IR → run VM
└── README.md
```

---

## Directory Structure After Rebuild

```
ai-free/
├── README.md                    # Universal Word Dialect Stack
├── AGENTS.md                    # Updated: Word compiler agents
├── src/
│   ├── word_core/              # Type system, primitives
│   ├── word_machine/           # Virtual machine
│   ├── word_ir/                # Intermediate representation
│   ├── compilers/              # All lowering pipelines
│   │   ├── wolfram_to_word_ir/
│   │   ├── word_ir_to_asm/
│   │   └── __init__.py
│   ├── frontends/              # Language frontends
│   │   ├── bcpl/
│   │   ├── forth/
│   │   └── wolfram/
│   └── __init__.py
├── tests/
│   ├── unit/                   # Unit tests
│   ├── integration/            # End-to-end
│   └── conftest.py
├── proofs/                     # Lean/Agda proofs
│   ├── *.lean
│   └── README.md
├── benchmarks/                 # Performance benchmarks
│   ├── *.w (Wolfram)
│   ├── *.wir (Word IR)
│   └── perf_comparison.py
├── docs/                       # Architecture specs
│   ├── *.md
│   └── diagrams/
├── playground/                 # Interactive tools
│   ├── web_ui/
│   └── repl.py
├── .github/
│   └── workflows/
│       ├── ci_tests.yml        # Run pytest
│       ├── lean_proofs.yml     # Verify Lean proofs
│       └── benchmarks.yml      # Regression benchmarks
├── pyproject.toml              # Python project config
├── Lean.mk                     # Lean build rules
└── .gitignore                  # Exclude proofs, artifacts
```

---

## Key Design Decisions

| Decision | Rationale | Verification |
|----------|-----------|--------------|
| WORD = universal dialect | No privileged language level | Wolfram ≈ BCPL ≈ Forth (all → Word IR) |
| PTR as WORD subtype | Avoid ad-hoc pointer semantics | Type system + proof |
| Separate code gen per ISA | Isolate ISA-specific hacks | Backend tests per ISA |
| Proofs in Lean | Formal verification of lowering | CI runs `lean --check` |
| Interactive REPL | Debugging & pedagogy | Artifact-based UI |

---

## Migration of Existing Code

**Current State:** Phantom Grid (distributed systems, agents, orchestration)

**Decision:** Archive, don't delete
- Move to `legacy/phantom_grid_core/` 
- Preserve for reference but don't integrate into new pipeline
- Document handoff in `legacy/README.md`

---

## Success Criteria

- [ ] WORD types + VM implementation with deterministic execution
- [ ] Wolfram → Word IR compiler with semantic proof sketch
- [ ] Word IR → x86-64 code gen (working, tested)
- [ ] BCPL & Forth frontends (minimum viable)
- [ ] All unit tests passing (>90% coverage)
- [ ] Proof obligations in Lean (at least 3 core theorems)
- [ ] End-to-end demo: Wolfram matrix multiply → x86 → runs correctly
- [ ] Interactive REPL artifact (can enter expressions, see transformations)

---

## Timeline

- **Day 1-2:** Core type system, Word machine VM, IR definition
- **Day 3-4:** Compilers (Wolfram lowering, code generation)
- **Day 5-6:** Tests, proofs, benchmarks
- **Day 7:** Docs, REPL, final commit

---

## Agent Assignments (Swarm Pattern)

| Agent | Responsibility | Status |
|-------|-----------------|--------|
| **Architect (Agent 1)** | Design decisions, proof strategy, API contracts | Lead |
| **Compiler (Agent 2)** | Wolfram parser, IR generation, lowering proofs | Support |
| **Backend (Agent 3)** | Code generation (x86, ARM, RISC-V), ISA details | Support |
| **Verification (Agent 4)** | Tests, Lean proofs, benchmark harness | Support |

---

## Commit Message Template

```
type: commit message

[symbol] Wolfram → Word IR compiler scaffold
 - Implement WORD[N] type system with invariants
 - Define canonical Word IR nodes
 - Add semantic preservation proof sketch

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
```

---

**Next Step:** Await your approval. Then:
1. Clear out legacy code → `legacy/`
2. Initialize empty directory structure
3. Begin Phase 1: Core type system
