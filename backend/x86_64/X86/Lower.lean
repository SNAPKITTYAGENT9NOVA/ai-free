import X86.Isa

/-!
# X86.Lower

Lowering of Universal Word IR (64-bit words) to x86-64.

Runtime conventions (all fixed here; the assembly runtime in `X86.Emit` establishes them):

| register | role |
|----------|------|
| `r15`    | data-stack pointer; the stack grows downward, `[r15]` is the top, empty = `dEnd` |
| `r14`    | base of the virtual register file, cell `r` at `r14 + 8r` |
| `r13`    | base of IR memory; IR word address `a` is at `r13 + 8a` |
| `r12`    | value of `rsp` at entry; the native stack is the IR return stack |
| `rbp`    | auxiliary-stack pointer; grows downward, `[rbp]` is the top, empty = `aEnd` |
| `rax rcx rdx rbx` | scratch |

IR `call`/`ret` are native `call`/`ret`. IR memory is valid exactly on `[0, memSize)`; every
`load`/`store` is bounds-checked, so an invalid address traps as in the IR semantics. Operand
counts are checked against `dEnd` before every instruction that pops, so stack underflow
traps as in the IR semantics. Every instruction that grows the data stack first checks
`r15 ≥ dBase + 8`, and `call` first checks `rsp ≥ r12 - (8 rcap - 16)`; on overflow the code
exits 6 (`exitOvf`). `tor` likewise checks `rbp ≥ aBase + 8` before growing the auxiliary
stack, and `fromr`/`rfetch` trap `returnUnderflow` when `rbp = aEnd` (empty). IR stacks are unbounded, so this exit has no IR counterpart: it reports that
the run exceeded the target's stack capacity.

Every instruction's code has a size that depends only on the instruction, so jump targets are
absolute code indices computed from prefix sums (`offs`). One definition serves both the
model and the assembly text.
-/

namespace WordDialect
namespace X86

open Reg

structure Layout where
  dEnd : W
  memSize : Nat
  dLim : W        -- `dBase + 8`: the data stack has room for one more word iff `r15 ≥ dLim`
  rGap : W        -- `8 rcap - 16`: a call has room iff `rsp ≥ r12 - rGap`
  aEnd : W        -- empty auxiliary stack: `rbp = aEnd`
  aLim : W        -- `aBase + 8`: the auxiliary stack has room for one more word iff `rbp ≥ aLim`

/-- Stack-underflow guard for `k` operands. -/
def uf (L : Layout) (k base : Nat) : List (Instr Nat) :=
  if k = 0 then []
  else [.movImm rax (L.dEnd - BitVec.ofNat 64 (8 * k)), .cmp r15 rax, .jcc .be (base + 4),
        .exitTrap .stackUnderflow]

def ufSize (k : Nat) : Nat := if k = 0 then 0 else 4

/-- Data-stack overflow guard: exit 6 unless one more word fits. -/
def ovfD (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm rax L.dLim, .cmp r15 rax, .jcc .ae (base + 4), .exitOvf]

/-- Return-stack overflow guard: exit 6 unless a call has room on the native stack. -/
def ovfR (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movRR rax r12, .movImm rcx L.rGap, .sub rax rcx, .cmp rsp rax, .jcc .ae (base + 6), .exitOvf]

/-- Auxiliary-stack overflow guard: exit 6 unless one more word fits. -/
def ovfA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm rax L.aLim, .cmp rbp rax, .jcc .ae (base + 4), .exitOvf]

/-- Empty-auxiliary-stack guard: trap `returnUnderflow` when `rbp = aEnd`. -/
def emptyA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm rax L.aEnd, .cmp rbp rax, .jcc .ne (base + 4), .exitTrap .returnUnderflow]

def ccOf : WordDialect.Cond → Cc
  | .eq => .e | .ne => .ne | .ult => .b | .ule => .be | .ugt => .a | .uge => .ae
  | .slt => .l | .sle => .le | .sgt => .g | .sge => .ge

/-- Code size of one IR instruction. -/
def isize : WordDialect.Instr 64 → Nat
  | .word _ | .ptr _ => 7
  | .load => ufSize 1 + 7
  | .store => ufSize 2 + 8
  | .add | .sub | .mul | .and | .or | .xor => ufSize 2 + 5
  | .div => ufSize 2 + 9
  | .sdiv => ufSize 2 + 13
  | .not => ufSize 1 + 3
  | .shl | .shr => ufSize 2 + 8
  | .rotl | .rotr => ufSize 2 + 5
  | .cmp _ => ufSize 2 + 8
  | .select => ufSize 3 + 7
  | .jmp _ => 1
  | .branch _ => ufSize 1 + 4
  | .call _ => 7
  | .ret => 4
  | .push _ => 7
  | .pop _ => ufSize 1 + 3
  | .dup => ufSize 1 + 7
  | .drop => ufSize 1 + 1
  | .swap => ufSize 2 + 4
  | .over => ufSize 2 + 7
  | .rot => ufSize 3 + 6
  | .tor => ufSize 1 + 8
  | .fromr => 12
  | .rfetch => 11
  | .halt => 1

/-- Code for one IR instruction placed at x86 index `base`; `off t` is the x86 index of IR
instruction `t` (clamped to the bad-pc stub for out-of-range targets). -/
def lowerInstr (L : Layout) (base : Nat) (off : Nat → Nat) : WordDialect.Instr 64 → List (Instr Nat)
  | .word w => ovfD L base ++ [.movImm rax w, .addImm r15 (-8), .store r15 0 rax]
  | .ptr p => ovfD L base ++ [.movImm rax p.toWord, .addImm r15 (-8), .store r15 0 rax]
  | .load =>
    let b0 := base + ufSize 1
    uf L 1 base ++
      [.load rax r15 0, .movImm rcx (BitVec.ofNat 64 L.memSize), .cmp rax rcx,
       .jcc .b (b0 + 5), .exitTrap .badAddress, .loadIdx rax r13 rax, .store r15 0 rax]
  | .store =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load rax r15 0, .load rcx r15 8, .movImm rdx (BitVec.ofNat 64 L.memSize), .cmp rax rdx,
       .jcc .b (b0 + 6), .exitTrap .badAddress, .storeIdx r13 rax rcx, .addImm r15 16]
  | .add => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .add rax rcx, .store r15 8 rax, .addImm r15 8]
  | .sub => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .sub rax rcx, .store r15 8 rax, .addImm r15 8]
  | .mul => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .imul rax rcx, .store r15 8 rax, .addImm r15 8]
  | .and => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .and rax rcx, .store r15 8 rax, .addImm r15 8]
  | .or => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .or rax rcx, .store r15 8 rax, .addImm r15 8]
  | .xor => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .xor rax rcx, .store r15 8 rax, .addImm r15 8]
  | .div =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load rcx r15 0, .load rax r15 8, .test rcx rcx, .jcc .ne (b0 + 5),
       .exitTrap .divideByZero, .movImm rdx 0#64, .div rcx, .store r15 8 rax, .addImm r15 8]
  | .sdiv =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load rcx r15 0, .load rax r15 8, .test rcx rcx, .jcc .ne (b0 + 5),
       .exitTrap .divideByZero, .cmpImm rcx (-1), .jcc .ne (b0 + 9), .neg rax, .jmp (b0 + 11),
       .cqo, .idiv rcx, .store r15 8 rax, .addImm r15 8]
  | .not => uf L 1 base ++ [.load rax r15 0, .not rax, .store r15 0 rax]
  | .shl =>
    uf L 2 base ++
      [.load rcx r15 0, .load rax r15 8, .movImm rdx 0#64, .shlCl rax, .cmpImm rcx 64,
       .cmov .ae rax rdx, .store r15 8 rax, .addImm r15 8]
  | .shr =>
    uf L 2 base ++
      [.load rcx r15 0, .load rax r15 8, .movImm rdx 0#64, .shrCl rax, .cmpImm rcx 64,
       .cmov .ae rax rdx, .store r15 8 rax, .addImm r15 8]
  | .rotl => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .rolCl rax, .store r15 8 rax, .addImm r15 8]
  | .rotr => uf L 2 base ++ [.load rcx r15 0, .load rax r15 8, .rorCl rax, .store r15 8 rax, .addImm r15 8]
  | .cmp c =>
    uf L 2 base ++
      [.load rcx r15 0, .load rax r15 8, .movImm rdx 0#64, .movImm rbx 1#64, .cmp rax rcx,
       .cmov (ccOf c) rdx rbx, .store r15 8 rdx, .addImm r15 8]
  | .select =>
    uf L 3 base ++
      [.load rcx r15 0, .load rax r15 8, .load rbx r15 16, .test rcx rcx, .cmov .ne rax rbx,
       .store r15 16 rax, .addImm r15 16]
  | .jmp t => [.jmp (off t)]
  | .branch t => uf L 1 base ++ [.load rax r15 0, .addImm r15 8, .test rax rax, .jcc .ne (off t)]
  | .call t => ovfR L base ++ [.call (off t)]
  | .ret =>
    [.cmp rsp r12, .jcc .ne (base + 3), .exitTrap .returnUnderflow, .ret]
  | .push r => ovfD L base ++ [.load rax r14 (8 * (r : Int)), .addImm r15 (-8), .store r15 0 rax]
  | .pop r => uf L 1 base ++ [.load rax r15 0, .addImm r15 8, .store r14 (8 * (r : Int)) rax]
  | .dup =>
    uf L 1 base ++ ovfD L (base + ufSize 1) ++ [.load rax r15 0, .addImm r15 (-8), .store r15 0 rax]
  | .drop => uf L 1 base ++ [.addImm r15 8]
  | .swap => uf L 2 base ++ [.load rax r15 0, .load rcx r15 8, .store r15 0 rcx, .store r15 8 rax]
  | .over =>
    uf L 2 base ++ ovfD L (base + ufSize 2) ++ [.load rax r15 8, .addImm r15 (-8), .store r15 0 rax]
  | .rot =>
    uf L 3 base ++
      [.load rax r15 0, .load rcx r15 8, .load rdx r15 16, .store r15 0 rdx, .store r15 8 rax,
       .store r15 16 rcx]
  | .tor =>
    uf L 1 base ++ ovfA L (base + ufSize 1) ++
      [.load rax r15 0, .addImm r15 8, .addImm rbp (-8), .store rbp 0 rax]
  | .fromr =>
    emptyA L base ++ ovfD L (base + 4) ++
      [.load rax rbp 0, .addImm rbp 8, .addImm r15 (-8), .store r15 0 rax]
  | .rfetch =>
    emptyA L base ++ ovfD L (base + 4) ++ [.load rax rbp 0, .addImm r15 (-8), .store r15 0 rax]
  | .halt => [.exitHalt]

theorem lowerInstr_length (L : Layout) (base : Nat) (off : Nat → Nat) (i : WordDialect.Instr 64) :
    (lowerInstr L base off i).length = isize i := by
  cases i <;> simp [lowerInstr, isize, uf, ufSize, ovfD, ovfR, ovfA, emptyA] <;> (try split) <;> simp

/-- Prefix sums of instruction sizes: `offs p k` is the x86 index of IR instruction `k`.
For `k` past the end it is the index of the final bad-pc stub. -/
def offs (p : Prog 64) (k : Nat) : Nat := ((p.take k).map isize).sum

def lowerGo (L : Layout) (off : Nat → Nat) : Nat → List (WordDialect.Instr 64) → List (Instr Nat)
  | _, [] => [.exitTrap .badPc]
  | b, i :: is => lowerInstr L b off i ++ lowerGo L off (b + isize i) is

/-- The whole program; the last instruction is the bad-pc stub, so jumping past the end of the
IR program traps `badPc` exactly as the IR semantics does. -/
def lowerProg (L : Layout) (p : Prog 64) : List (Instr Nat) := lowerGo L (offs p) 0 p

end X86
end WordDialect
