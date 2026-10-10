import RV32.Isa

/-!
# RV32.Lower

Lowering of Universal Word IR (32-bit words) to RISC-V (RV32IM).

Runtime conventions (all fixed here; the assembly runtime in `RV32.Emit` establishes them):

| register | role |
|----------|------|
| `s1`    | data-stack pointer; the stack grows downward, `[s1]` is the top, empty = `dEnd` |
| `s2`    | base of the virtual register file, cell `r` at `s2 + 8r` |
| `s3`    | base of IR memory; IR word address `a` is at `s3 + 8a` |
| `s4`    | the empty return stack (`s5` at entry) |
| `s5`    | return-stack pointer; grows downward, `[s5]` is the top return address |
| `s6`    | auxiliary-stack pointer; grows downward, `[s6]` is the top, empty = `aEnd` |
| `t0 t1 t2 t3` | scratch; `ra` is written by `call` and `ret` |

IR `call`/`ret` are the model's `call`/`ret` (fixed sequences on the `s5` stack, see `RV32.Isa`).
There are no condition flags: every guard is one compare-and-branch (`bcc`) over a trap stub.
IR memory is valid exactly on `[0, memSize)`; every
`load`/`store` is bounds-checked, so an invalid address traps as in the IR semantics. Operand
counts are checked against `dEnd` before every instruction that pops, so stack underflow
traps as in the IR semantics. Every instruction that grows the data stack first checks
`s1 ≥ dBase + 4`, and `call` first checks `s5 ≥ s4 - (4 rcap - 8)`; on overflow the code
exits 6 (`exitOvf`). `tor` likewise checks `s6 ≥ aBase + 4` before growing the auxiliary
stack, and `fromr`/`rfetch` trap `returnUnderflow` when `s6 = aEnd` (empty). IR stacks are unbounded, so this exit has no IR counterpart: it reports that
the run exceeded the target's stack capacity.

Every instruction's code has a size that depends only on the instruction, so jump targets are
absolute code indices computed from prefix sums (`offs`). One definition serves both the
model and the assembly text.
-/

namespace WordDialect
namespace RV32

open Reg

structure Layout where
  dEnd : W
  memSize : Nat
  dLim : W        -- `dBase + 4`: the data stack has room for one more word iff `s1 ≥ dLim`
  rGap : W        -- `4 rcap - 8`: a call has room iff `s5 ≥ s4 - rGap`
  aEnd : W        -- empty auxiliary stack: `s6 = aEnd`
  aLim : W        -- `aBase + 4`: the auxiliary stack has room for one more word iff `s6 ≥ aLim`

/-- Stack-underflow guard for `k` operands: continue when `s1 ≤ dEnd - 8k`. -/
def uf (L : Layout) (k base : Nat) : List (Instr Nat) :=
  if k = 0 then []
  else [.movImm t0 (L.dEnd - BitVec.ofNat 32 (4 * k)), .bcc .ule s1 t0 (base + 3),
        .exitTrap .stackUnderflow]

def ufSize (k : Nat) : Nat := if k = 0 then 0 else 3

/-- Data-stack overflow guard: exit 6 unless one more word fits. -/
def ovfD (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm t0 L.dLim, .bcc .uge s1 t0 (base + 3), .exitOvf]

/-- Return-stack overflow guard: exit 6 unless a call has room on the return stack. -/
def ovfR (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movRR t0 s4, .movImm t1 L.rGap, .sub t0 t1, .bcc .uge s5 t0 (base + 5), .exitOvf]

/-- Auxiliary-stack overflow guard: exit 6 unless one more word fits. -/
def ovfA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm t0 L.aLim, .bcc .uge s6 t0 (base + 3), .exitOvf]

/-- Empty-auxiliary-stack guard: trap `returnUnderflow` when `s6 = aEnd`. -/
def emptyA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm t0 L.aEnd, .bcc .ne s6 t0 (base + 3), .exitTrap .returnUnderflow]

/-- Code size of one IR instruction. -/
def isize : WordDialect.Instr 32 → Nat
  | .word _ | .ptr _ => 6
  | .load => ufSize 1 + 8
  | .store => ufSize 2 + 9
  | .add | .sub | .mul | .and | .or | .xor => ufSize 2 + 5
  | .div | .sdiv => ufSize 2 + 7
  | .not => ufSize 1 + 3
  | .shl | .shr => ufSize 2 + 8
  | .rotl | .rotr => ufSize 2 + 9
  | .cmp _ => ufSize 2 + 7
  | .select => ufSize 3 + 7
  | .jmp _ => 1
  | .branch _ => ufSize 1 + 3
  | .call _ => 6
  | .ret => 3
  | .push _ => 6
  | .pop _ => ufSize 1 + 3
  | .dup => ufSize 1 + 6
  | .drop => ufSize 1 + 1
  | .swap => ufSize 2 + 4
  | .over => ufSize 2 + 6
  | .rot => ufSize 3 + 6
  | .tor => ufSize 1 + 7
  | .fromr => 10
  | .rfetch => 9
  | .halt => 1

/-- Code for one IR instruction placed at RV index `base`; `off t` is the RV index of IR
instruction `t` (clamped to the bad-pc stub for out-of-range targets). -/
def lowerInstr (L : Layout) (base : Nat) (off : Nat → Nat) : WordDialect.Instr 32 → List (Instr Nat)
  | .word w => ovfD L base ++ [.movImm t0 w, .addImm s1 (-4), .store s1 0 t0]
  | .ptr p => ovfD L base ++ [.movImm t0 p.toWord, .addImm s1 (-4), .store s1 0 t0]
  | .load =>
    let b0 := base + ufSize 1
    uf L 1 base ++
      [.load t0 s1 0, .movImm t1 (BitVec.ofNat 32 L.memSize), .bcc .ult t0 t1 (b0 + 4),
       .exitTrap .badAddress, .shlImm t0 2, .add t0 s3, .load t0 t0 0, .store s1 0 t0]
  | .store =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load t0 s1 0, .load t1 s1 4, .movImm t2 (BitVec.ofNat 32 L.memSize), .bcc .ult t0 t2 (b0 + 5),
       .exitTrap .badAddress, .shlImm t0 2, .add t0 s3, .store t0 0 t1, .addImm s1 8]
  | .add => uf L 2 base ++ [.load t1 s1 0, .load t0 s1 4, .add t0 t1, .store s1 4 t0, .addImm s1 4]
  | .sub => uf L 2 base ++ [.load t1 s1 0, .load t0 s1 4, .sub t0 t1, .store s1 4 t0, .addImm s1 4]
  | .mul => uf L 2 base ++ [.load t1 s1 0, .load t0 s1 4, .mul t0 t1, .store s1 4 t0, .addImm s1 4]
  | .and => uf L 2 base ++ [.load t1 s1 0, .load t0 s1 4, .and t0 t1, .store s1 4 t0, .addImm s1 4]
  | .or => uf L 2 base ++ [.load t1 s1 0, .load t0 s1 4, .or t0 t1, .store s1 4 t0, .addImm s1 4]
  | .xor => uf L 2 base ++ [.load t1 s1 0, .load t0 s1 4, .xor t0 t1, .store s1 4 t0, .addImm s1 4]
  | .div =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load t1 s1 0, .load t0 s1 4, .bnez t1 (b0 + 4), .exitTrap .divideByZero, .divu t0 t0 t1,
       .store s1 4 t0, .addImm s1 4]
  | .sdiv =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load t1 s1 0, .load t0 s1 4, .bnez t1 (b0 + 4), .exitTrap .divideByZero, .div t0 t0 t1,
       .store s1 4 t0, .addImm s1 4]
  | .not => uf L 1 base ++ [.load t0 s1 0, .not t0, .store s1 0 t0]
  | .shl =>
    uf L 2 base ++
      [.load t1 s1 0, .load t0 s1 4, .sll t0 t1, .sltiu t2 t1 32, .neg t2, .and t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .shr =>
    uf L 2 base ++
      [.load t1 s1 0, .load t0 s1 4, .srl t0 t1, .sltiu t2 t1 32, .neg t2, .and t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .rotl =>
    uf L 2 base ++
      [.load t1 s1 0, .load t0 s1 4, .movRR t2 t0, .sll t0 t1, .neg t1, .srl t2 t1, .or t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .rotr =>
    uf L 2 base ++
      [.load t1 s1 0, .load t0 s1 4, .movRR t2 t0, .srl t0 t1, .neg t1, .sll t2 t1, .or t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .cmp c =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load t1 s1 0, .load t0 s1 4, .movImm t2 1#32, .bcc c t0 t1 (b0 + 5), .movImm t2 0#32,
       .store s1 4 t2, .addImm s1 4]
  | .select =>
    let b0 := base + ufSize 3
    uf L 3 base ++
      [.load t1 s1 0, .load t0 s1 4, .load t3 s1 8, .beqz t1 (b0 + 5), .movRR t0 t3,
       .store s1 8 t0, .addImm s1 8]
  | .jmp t => [.jmp (off t)]
  | .branch t => uf L 1 base ++ [.load t0 s1 0, .addImm s1 4, .bnez t0 (off t)]
  | .call t => ovfR L base ++ [.call (off t)]
  | .ret => [.bcc .ne s5 s4 (base + 2), .exitTrap .returnUnderflow, .ret]
  | .push r => ovfD L base ++ [.load t0 s2 (4 * (r : Int)), .addImm s1 (-4), .store s1 0 t0]
  | .pop r => uf L 1 base ++ [.load t0 s1 0, .addImm s1 4, .store s2 (4 * (r : Int)) t0]
  | .dup =>
    uf L 1 base ++ ovfD L (base + ufSize 1) ++ [.load t0 s1 0, .addImm s1 (-4), .store s1 0 t0]
  | .drop => uf L 1 base ++ [.addImm s1 4]
  | .swap => uf L 2 base ++ [.load t0 s1 0, .load t1 s1 4, .store s1 0 t1, .store s1 4 t0]
  | .over =>
    uf L 2 base ++ ovfD L (base + ufSize 2) ++ [.load t0 s1 4, .addImm s1 (-4), .store s1 0 t0]
  | .rot =>
    uf L 3 base ++
      [.load t0 s1 0, .load t1 s1 4, .load t2 s1 8, .store s1 0 t2, .store s1 4 t0,
       .store s1 8 t1]
  | .tor =>
    uf L 1 base ++ ovfA L (base + ufSize 1) ++
      [.load t0 s1 0, .addImm s1 4, .addImm s6 (-4), .store s6 0 t0]
  | .fromr =>
    emptyA L base ++ ovfD L (base + 3) ++
      [.load t0 s6 0, .addImm s6 4, .addImm s1 (-4), .store s1 0 t0]
  | .rfetch =>
    emptyA L base ++ ovfD L (base + 3) ++ [.load t0 s6 0, .addImm s1 (-4), .store s1 0 t0]
  | .halt => [.exitHalt]

theorem lowerInstr_length (L : Layout) (base : Nat) (off : Nat → Nat) (i : WordDialect.Instr 32) :
    (lowerInstr L base off i).length = isize i := by
  cases i <;> simp [lowerInstr, isize, uf, ufSize, ovfD, ovfR, ovfA, emptyA] <;> (try split) <;> simp

/-- Prefix sums of instruction sizes: `offs p k` is the RV index of IR instruction `k`.
For `k` past the end it is the index of the final bad-pc stub. -/
def offs (p : Prog 32) (k : Nat) : Nat := ((p.take k).map isize).sum

def lowerGo (L : Layout) (off : Nat → Nat) : Nat → List (WordDialect.Instr 32) → List (Instr Nat)
  | _, [] => [.exitTrap .badPc]
  | b, i :: is => lowerInstr L b off i ++ lowerGo L off (b + isize i) is

/-- The whole program; the last instruction is the bad-pc stub, so jumping past the end of the
IR program traps `badPc` exactly as the IR semantics does. -/
def lowerProg (L : Layout) (p : Prog 32) : List (Instr Nat) := lowerGo L (offs p) 0 p

end RV32
end WordDialect
