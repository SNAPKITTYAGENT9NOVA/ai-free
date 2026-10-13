import RV32.Isa
import WordDialect.Depth

/-!
# RV32.Lower

Lowering of Universal Word IR (32-bit words) to RISC-V (RV32IM).

Runtime conventions (all fixed here; the assembly runtime in `RV32.Emit` establishes them):

| register | role |
|----------|------|
| `s1`    | data-stack pointer; the stack grows downward, `[s1]` is the top, empty = `dEnd` |
| `s2`    | base of the virtual register file, cell `r` at `s2 + 4r` |
| `s3`    | base of IR memory; IR word address `a` is at `s3 + 4a` |
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
  /-- A depth certificate (`WordDialect.Depth`): at IR instruction `k` the data stack holds at
  least `cert k` words, so an operand-count guard for at most that many words is left out. -/
  cert : Nat → Nat := fun _ => 0
  /-- An upper bound on the data-stack depth at each IR instruction, and the data stack's
  capacity in words. Where `ub k + 1 ≤ dCap` the data-stack overflow guard is left out. The
  default capacity `0` leaves every guard in. -/
  ub : Nat → Nat := fun _ => 0
  dCap : Nat := 0

/-- What the lowering knows at one IR instruction: a lower bound on the data-stack depth, and
whether one more word is known to fit. -/
structure Facts where
  lo : Nat := 0
  noOvf : Bool := false

/-- The facts at IR instruction `k`. -/
def Layout.facts (L : Layout) (k : Nat) : Facts :=
  { lo := L.cert k, noOvf := decide (L.ub k + 1 ≤ L.dCap) }

/-- Stack-underflow guard for `k` operands: continue when `s1 ≤ dEnd - 4k`. -/
def uf (L : Layout) (k base : Nat) : List (Instr Nat) :=
  if k = 0 then []
  else [.movImm t0 (L.dEnd - BitVec.ofNat 32 (4 * k)), .bcc .ule s1 t0 (base + 3),
        .exitTrap .stackUnderflow]

def ufSize (k : Nat) : Nat := if k = 0 then 0 else 3

/-- The operand count an instruction popping `k` words still has to check when the data stack is
known to hold at least `g.lo` words: none if `k ≤ g.lo`. -/
def need (g : Facts) (k : Nat) : Nat := if k ≤ g.lo then 0 else k

theorem need_le (g : Facts) (k : Nat) : need g k ≤ k := by unfold need; split <;> omega

theorem need_of_lt {g : Facts} {k : Nat} (h : g.lo < k) : need g k = k := by
  unfold need; split <;> omega

/-- Data-stack overflow guard: exit 6 unless one more word fits. -/
def ovfD (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm t0 L.dLim, .bcc .uge s1 t0 (base + 3), .exitOvf]

/-- The data-stack overflow guard where it is needed: none when the facts say one more word fits. -/
def ovf (L : Layout) (g : Facts) (base : Nat) : List (Instr Nat) :=
  if g.noOvf then [] else ovfD L base

def ovfSize (g : Facts) : Nat := if g.noOvf then 0 else 3

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
def isize (g : Facts) : WordDialect.Instr 32 → Nat
  | .word _ | .ptr _ => ovfSize g + 3
  | .load => ufSize (need g 1) + 8
  | .store => ufSize (need g 2) + 9
  | .add | .sub | .mul | .and | .or | .xor => ufSize (need g 2) + 5
  | .div | .sdiv => ufSize (need g 2) + 7
  | .not => ufSize (need g 1) + 3
  | .shl | .shr => ufSize (need g 2) + 8
  | .rotl | .rotr => ufSize (need g 2) + 9
  | .cmp _ => ufSize (need g 2) + 7
  | .select => ufSize (need g 3) + 7
  | .jmp _ => 1
  | .branch _ => ufSize (need g 1) + 3
  | .call _ => 6
  | .ret => 3
  | .push _ => ovfSize g + 3
  | .pop _ => ufSize (need g 1) + 3
  | .dup => ufSize (need g 1) + ovfSize g + 3
  | .drop => ufSize (need g 1) + 1
  | .swap => ufSize (need g 2) + 4
  | .over => ufSize (need g 2) + ovfSize g + 3
  | .rot => ufSize (need g 3) + 6
  | .tor => ufSize (need g 1) + 7
  | .fromr => ovfSize g + 7
  | .rfetch => ovfSize g + 6
  | .halt => 1

/-- Code for one IR instruction placed at RV index `base`; `off t` is the RV index of IR
instruction `t` (clamped to the bad-pc stub for out-of-range targets). -/
def lowerInstr (L : Layout) (base : Nat) (off : Nat → Nat) (g : Facts) :
    WordDialect.Instr 32 → List (Instr Nat)
  | .word w => ovf L g base ++ [.movImm t0 w, .addImm s1 (-4), .store s1 0 t0]
  | .ptr p => ovf L g base ++ [.movImm t0 p.toWord, .addImm s1 (-4), .store s1 0 t0]
  | .load =>
    let b0 := base + ufSize (need g 1)
    uf L (need g 1) base ++
      [.load t0 s1 0, .movImm t1 (BitVec.ofNat 32 L.memSize), .bcc .ult t0 t1 (b0 + 4),
       .exitTrap .badAddress, .shlImm t0 2, .add t0 s3, .load t0 t0 0, .store s1 0 t0]
  | .store =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      [.load t0 s1 0, .load t1 s1 4, .movImm t2 (BitVec.ofNat 32 L.memSize), .bcc .ult t0 t2 (b0 + 5),
       .exitTrap .badAddress, .shlImm t0 2, .add t0 s3, .store t0 0 t1, .addImm s1 8]
  | .add => uf L (need g 2) base ++ [.load t1 s1 0, .load t0 s1 4, .add t0 t1, .store s1 4 t0, .addImm s1 4]
  | .sub => uf L (need g 2) base ++ [.load t1 s1 0, .load t0 s1 4, .sub t0 t1, .store s1 4 t0, .addImm s1 4]
  | .mul => uf L (need g 2) base ++ [.load t1 s1 0, .load t0 s1 4, .mul t0 t1, .store s1 4 t0, .addImm s1 4]
  | .and => uf L (need g 2) base ++ [.load t1 s1 0, .load t0 s1 4, .and t0 t1, .store s1 4 t0, .addImm s1 4]
  | .or => uf L (need g 2) base ++ [.load t1 s1 0, .load t0 s1 4, .or t0 t1, .store s1 4 t0, .addImm s1 4]
  | .xor => uf L (need g 2) base ++ [.load t1 s1 0, .load t0 s1 4, .xor t0 t1, .store s1 4 t0, .addImm s1 4]
  | .div =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      [.load t1 s1 0, .load t0 s1 4, .bnez t1 (b0 + 4), .exitTrap .divideByZero, .divu t0 t0 t1,
       .store s1 4 t0, .addImm s1 4]
  | .sdiv =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      [.load t1 s1 0, .load t0 s1 4, .bnez t1 (b0 + 4), .exitTrap .divideByZero, .div t0 t0 t1,
       .store s1 4 t0, .addImm s1 4]
  | .not => uf L (need g 1) base ++ [.load t0 s1 0, .not t0, .store s1 0 t0]
  | .shl =>
    uf L (need g 2) base ++
      [.load t1 s1 0, .load t0 s1 4, .sll t0 t1, .sltiu t2 t1 32, .neg t2, .and t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .shr =>
    uf L (need g 2) base ++
      [.load t1 s1 0, .load t0 s1 4, .srl t0 t1, .sltiu t2 t1 32, .neg t2, .and t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .rotl =>
    uf L (need g 2) base ++
      [.load t1 s1 0, .load t0 s1 4, .movRR t2 t0, .sll t0 t1, .neg t1, .srl t2 t1, .or t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .rotr =>
    uf L (need g 2) base ++
      [.load t1 s1 0, .load t0 s1 4, .movRR t2 t0, .srl t0 t1, .neg t1, .sll t2 t1, .or t0 t2,
       .store s1 4 t0, .addImm s1 4]
  | .cmp c =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      [.load t1 s1 0, .load t0 s1 4, .movImm t2 1#32, .bcc c t0 t1 (b0 + 5), .movImm t2 0#32,
       .store s1 4 t2, .addImm s1 4]
  | .select =>
    let b0 := base + ufSize (need g 3)
    uf L (need g 3) base ++
      [.load t1 s1 0, .load t0 s1 4, .load t3 s1 8, .beqz t1 (b0 + 5), .movRR t0 t3,
       .store s1 8 t0, .addImm s1 8]
  | .jmp t => [.jmp (off t)]
  | .branch t => uf L (need g 1) base ++ [.load t0 s1 0, .addImm s1 4, .bnez t0 (off t)]
  | .call t => ovfR L base ++ [.call (off t)]
  | .ret => [.bcc .ne s5 s4 (base + 2), .exitTrap .returnUnderflow, .ret]
  | .push r => ovf L g base ++ [.load t0 s2 (4 * (r : Int)), .addImm s1 (-4), .store s1 0 t0]
  | .pop r => uf L (need g 1) base ++ [.load t0 s1 0, .addImm s1 4, .store s2 (4 * (r : Int)) t0]
  | .dup =>
    uf L (need g 1) base ++ ovf L g (base + ufSize (need g 1)) ++ [.load t0 s1 0, .addImm s1 (-4), .store s1 0 t0]
  | .drop => uf L (need g 1) base ++ [.addImm s1 4]
  | .swap => uf L (need g 2) base ++ [.load t0 s1 0, .load t1 s1 4, .store s1 0 t1, .store s1 4 t0]
  | .over =>
    uf L (need g 2) base ++ ovf L g (base + ufSize (need g 2)) ++ [.load t0 s1 4, .addImm s1 (-4), .store s1 0 t0]
  | .rot =>
    uf L (need g 3) base ++
      [.load t0 s1 0, .load t1 s1 4, .load t2 s1 8, .store s1 0 t2, .store s1 4 t0,
       .store s1 8 t1]
  | .tor =>
    uf L (need g 1) base ++ ovfA L (base + ufSize (need g 1)) ++
      [.load t0 s1 0, .addImm s1 4, .addImm s6 (-4), .store s6 0 t0]
  | .fromr =>
    emptyA L base ++ ovf L g (base + 3) ++
      [.load t0 s6 0, .addImm s6 4, .addImm s1 (-4), .store s1 0 t0]
  | .rfetch =>
    emptyA L base ++ ovf L g (base + 3) ++ [.load t0 s6 0, .addImm s1 (-4), .store s1 0 t0]
  | .halt => [.exitHalt]

theorem uf_length (L : Layout) (k base : Nat) : (uf L k base).length = ufSize k := by
  unfold uf ufSize; split <;> simp

theorem ovf_length (L : Layout) (g : Facts) (base : Nat) : (ovf L g base).length = ovfSize g := by
  unfold ovf ovfSize; split <;> simp [ovfD]

theorem lowerInstr_length (L : Layout) (base : Nat) (off : Nat → Nat) (g : Facts)
    (i : WordDialect.Instr 32) : (lowerInstr L base off g i).length = isize g i := by
  cases i <;> simp [lowerInstr, isize, uf_length, ovf_length, ovfR, ovfA, emptyA] <;> omega

/-- Prefix sums of instruction sizes: `offs cf p k` is the code index of IR instruction `k`,
where `cf j` are the facts at instruction `j` (its guards depend on them). For `k` past
the end it is the index of the final bad-pc stub. -/
def offs (cf : Nat → Facts) : Prog 32 → Nat → Nat
  | _, 0 => 0
  | [], _ + 1 => 0
  | i :: is, k + 1 => isize (cf 0) i + offs (fun j => cf (j + 1)) is k

def lowerGo (L : Layout) (off : Nat → Nat) :
    (Nat → Facts) → Nat → List (WordDialect.Instr 32) → List (Instr Nat)
  | _, _, [] => [.exitTrap .badPc]
  | cf, b, i :: is => lowerInstr L b off (cf 0) i ++ lowerGo L off (fun j => cf (j + 1)) (b + isize (cf 0) i) is

/-- The whole program; the last instruction is the bad-pc stub, so jumping past the end of the
IR program traps `badPc` exactly as the IR semantics does. Instruction `k` leaves out the
guards that `L.facts k` makes redundant. -/
def lowerProg (L : Layout) (p : Prog 32) : List (Instr Nat) := lowerGo L (offs L.facts p) L.facts 0 p

end RV32
end WordDialect
