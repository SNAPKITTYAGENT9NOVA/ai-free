import CM0.Isa
import WordDialect.Depth

/-!
# CM0.Lower

Lowering of Universal Word IR (32-bit words) to ARMv6-M (Cortex-M0, M0+, M1).

The structure is that of `CM.Lower` (the Cortex-M3 profile), with two changes ARMv6-M forces:
the return stack is `sp` (so a return is one `pop {pc}`), and division, which has no instruction,
is the loop `udivCode` (`udivSeq`, `sdivSeq`). Loads and stores use only the low registers `r4`,
`r5`, `r6` and the scratch registers as bases.

Runtime conventions (all fixed here; the assembly runtime in `CM0.Emit` establishes them):

| register | role |
|----------|------|
| `r4`    | data-stack pointer; the stack grows downward, `[r4]` is the top, empty = `dEnd` |
| `r5`    | base of the virtual register file, cell `r` at `r5 + 4r` |
| `r8`    | base of IR memory; IR word address `a` is at `r8 + 4a` |
| `r9`    | the empty return stack (`sp` at entry) |
| `sp`    | return-stack pointer; grows downward, `[sp]` is the top return address |
| `r6`    | auxiliary-stack pointer; grows downward, `[r6]` is the top, empty = `aEnd` |
| `r0 r1 r2 r3` | scratch; `r7` and `r10` are also scratch inside the division sequences |

IR `call`/`ret` are the model's `call`/`ret` (fixed sequences on the `sp` stack, see `CM0.Isa`).
Every guard is one compare-and-branch (`bcc`, `cmp` and a conditional branch) over a trap stub;
the flags are written and read only inside that sequence.
IR memory is valid exactly on `[0, memSize)`; every
`load`/`store` is bounds-checked, so an invalid address traps as in the IR semantics. Operand
counts are checked against `dEnd` before every instruction that pops, so stack underflow
traps as in the IR semantics. Every instruction that grows the data stack first checks
`r4 ≥ dBase + 4`, and `call` first checks `sp ≥ r9 - (4 rcap - 8)`; on overflow the code
exits 6 (`exitOvf`). `tor` likewise checks `r6 ≥ aBase + 4` before growing the auxiliary
stack, and `fromr`/`rfetch` trap `returnUnderflow` when `r6 = aEnd` (empty). IR stacks are unbounded, so this exit has no IR counterpart: it reports that
the run exceeded the target's stack capacity.

Two checked certificates (`WordDialect.Depth`) remove guards: where the data stack is known to
hold enough operands, the operand-count guard is left out, and where one more word is known to
fit, the overflow guard is. Every instruction's code has a size that depends only on the
instruction and those facts, so jump targets are absolute code indices computed from prefix sums
(`offs`). One definition serves both the
model and the assembly text.
-/

namespace WordDialect
namespace CM0

open Reg

structure Layout where
  dEnd : W
  memSize : Nat
  dLim : W        -- `dBase + 4`: the data stack has room for one more word iff `r4 ≥ dLim`
  rGap : W        -- `4 rcap - 8`: a call has room iff `sp ≥ r9 - rGap`
  aEnd : W        -- empty auxiliary stack: `r6 = aEnd`
  aLim : W        -- `aBase + 4`: the auxiliary stack has room for one more word iff `r6 ≥ aLim`
  /-- A depth certificate (`WordDialect.Depth`): at IR instruction `k` the data stack holds at
  least `cert k` words, so an operand-count guard for at most that many words is left out. -/
  cert : Nat → Nat := fun _ => 0
  /-- An upper bound on the data-stack depth at each IR instruction (`WordDialect.Bound`), and
  the data stack's capacity in words. Where `ub k + 1 ≤ dCap` the data-stack overflow guard is
  left out. The default capacity `0` leaves every guard in. -/
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

/-- Stack-underflow guard for `k` operands: continue when `r4 ≤ dEnd - 4k`. -/
def uf (L : Layout) (k base : Nat) : List (Instr Nat) :=
  if k = 0 then []
  else [.movImm r0 (L.dEnd - BitVec.ofNat 32 (4 * k)), .bcc .ule r4 r0 (base + 3),
        .exitTrap .stackUnderflow]

def ufSize (k : Nat) : Nat := if k = 0 then 0 else 3

/-- The operand count an instruction popping `k` words still has to check when the data stack is
known to hold at least `g` words: none if `k ≤ g`. -/
def need (g : Facts) (k : Nat) : Nat := if k ≤ g.lo then 0 else k

theorem need_le (g : Facts) (k : Nat) : need g k ≤ k := by unfold need; split <;> omega

theorem need_of_lt {g : Facts} {k : Nat} (h : g.lo < k) : need g k = k := by
  unfold need; split <;> omega

/-- Data-stack overflow guard: exit 6 unless one more word fits. -/
def ovfD (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm r0 L.dLim, .bcc .uge r4 r0 (base + 3), .exitOvf]

/-- The data-stack overflow guard where it is needed: none when the facts say one more word fits. -/
def ovf (L : Layout) (g : Facts) (base : Nat) : List (Instr Nat) :=
  if g.noOvf then [] else ovfD L base

def ovfSize (g : Facts) : Nat := if g.noOvf then 0 else 3

/-- Return-stack overflow guard: exit 6 unless a call has room on the return stack. -/
def ovfR (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movRR r0 r9, .movImm r1 L.rGap, .sub r0 r1, .bcc .uge sp r0 (base + 5), .exitOvf]

/-- Auxiliary-stack overflow guard: exit 6 unless one more word fits. -/
def ovfA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm r0 L.aLim, .bcc .uge r6 r0 (base + 3), .exitOvf]

/-- Empty-auxiliary-stack guard: trap `returnUnderflow` when `r6 = aEnd`. -/
def emptyA (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm r0 L.aEnd, .bcc .ne r6 r0 (base + 3), .exitTrap .returnUnderflow]

/-- Unsigned division without a divide instruction, as a loop placed at code index `q`.
On entry `r0 = a`, `r1 = b ≠ 0`; on exit (index `q + 14`) `r2 = a / b`. For `i = 31 … 0`: if
`(r0 >>> i) ≥ b`, subtract `b <<< i` from `r0` and add `1 <<< i` to `r2`. Proved in
`CM0/Divide.lean` (`udiv_loop`): before step `i`, `a = r2 · b + r0` and `r0 < b · 2^(i+1)`. -/
def udivCode (q : Nat) : List (Instr Nat) :=
  [.movImm r2 0#32, .movImm r3 31#32,
   .movRR r7 r0, .lsr r7 r3, .bcc .ult r7 r1 (q + 11),
   .movRR r7 r1, .lsl r7 r3, .sub r0 r7, .movImm r7 1#32, .lsl r7 r3, .add r2 r7,
   .beqz r3 (q + 14), .addImm r3 (-1), .jmp (q + 2)]

/-- `IR div`: the loop, then the quotient into `r0`. -/
def udivSeq (q : Nat) : List (Instr Nat) := udivCode q ++ [.movRR r0 r2]

/-- `IR sdiv`: remember the sign of the result (`r10 := a ^^^ b`), divide the absolute values
with the loop, and negate the quotient when the signs differ. This is `BitVec.sdiv` case by case
(`CM0/Divide.lean`, `sdiv_seq`); the most negative number divided by `-1` wraps, as there. -/
def sdivSeq (q : Nat) : List (Instr Nat) :=
  [.movRR r3 r0, .xor r3 r1, .movRR r10 r3, .movImm r2 0#32,
   .bcc .sge r0 r2 (q + 6), .neg r0, .bcc .sge r1 r2 (q + 8), .neg r1] ++ udivCode (q + 8) ++
  [.movRR r3 r10, .movImm r7 0#32, .bcc .sge r3 r7 (q + 26), .neg r2, .movRR r0 r2]

/-- Code size of one IR instruction. -/
def isize (g : Facts) : WordDialect.Instr 32 → Nat
  | .word _ | .ptr _ => ovfSize g + 3
  | .load => ufSize (need g 1) + 8
  | .store => ufSize (need g 2) + 9
  | .add | .sub | .mul | .and | .or | .xor => ufSize (need g 2) + 5
  | .div => ufSize (need g 2) + 21
  | .sdiv => ufSize (need g 2) + 33
  | .not => ufSize (need g 1) + 3
  | .shl | .shr => ufSize (need g 2) + 8
  | .rotl => ufSize (need g 2) + 6
  | .rotr => ufSize (need g 2) + 5
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

/-- Code for one IR instruction placed at code index `base`; `off t` is the code index of IR
instruction `t` (clamped to the bad-pc stub for out-of-range targets). -/
def lowerInstr (L : Layout) (base : Nat) (off : Nat → Nat) (g : Facts) :
    WordDialect.Instr 32 → List (Instr Nat)
  | .word w => ovf L g base ++ [.movImm r0 w, .addImm r4 (-4), .store r4 0 r0]
  | .ptr p => ovf L g base ++ [.movImm r0 p.toWord, .addImm r4 (-4), .store r4 0 r0]
  | .load =>
    let b0 := base + ufSize (need g 1)
    uf L (need g 1) base ++
      [.load r0 r4 0, .movImm r1 (BitVec.ofNat 32 L.memSize), .bcc .ult r0 r1 (b0 + 4),
       .exitTrap .badAddress, .shlImm r0 2, .add r0 r8, .load r0 r0 0, .store r4 0 r0]
  | .store =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      [.load r0 r4 0, .load r1 r4 4, .movImm r2 (BitVec.ofNat 32 L.memSize), .bcc .ult r0 r2 (b0 + 5),
       .exitTrap .badAddress, .shlImm r0 2, .add r0 r8, .store r0 0 r1, .addImm r4 8]
  | .add => uf L (need g 2) base ++ [.load r1 r4 0, .load r0 r4 4, .add r0 r1, .store r4 4 r0, .addImm r4 4]
  | .sub => uf L (need g 2) base ++ [.load r1 r4 0, .load r0 r4 4, .sub r0 r1, .store r4 4 r0, .addImm r4 4]
  | .mul => uf L (need g 2) base ++ [.load r1 r4 0, .load r0 r4 4, .mul r0 r1, .store r4 4 r0, .addImm r4 4]
  | .and => uf L (need g 2) base ++ [.load r1 r4 0, .load r0 r4 4, .and r0 r1, .store r4 4 r0, .addImm r4 4]
  | .or => uf L (need g 2) base ++ [.load r1 r4 0, .load r0 r4 4, .or r0 r1, .store r4 4 r0, .addImm r4 4]
  | .xor => uf L (need g 2) base ++ [.load r1 r4 0, .load r0 r4 4, .xor r0 r1, .store r4 4 r0, .addImm r4 4]
  | .div =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      ([.load r1 r4 0, .load r0 r4 4, .bnez r1 (b0 + 4), .exitTrap .divideByZero] ++
       udivSeq (b0 + 4) ++ [.store r4 4 r0, .addImm r4 4])
  | .sdiv =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      ([.load r1 r4 0, .load r0 r4 4, .bnez r1 (b0 + 4), .exitTrap .divideByZero] ++
       sdivSeq (b0 + 4) ++ [.store r4 4 r0, .addImm r4 4])
  | .not => uf L (need g 1) base ++ [.load r0 r4 0, .not r0, .store r4 0 r0]
  | .shl =>
    uf L (need g 2) base ++
      [.load r1 r4 0, .load r0 r4 4, .lsl r0 r1, .sltiu r2 r1 32, .neg r2, .and r0 r2,
       .store r4 4 r0, .addImm r4 4]
  | .shr =>
    uf L (need g 2) base ++
      [.load r1 r4 0, .load r0 r4 4, .lsr r0 r1, .sltiu r2 r1 32, .neg r2, .and r0 r2,
       .store r4 4 r0, .addImm r4 4]
  | .rotl =>
    uf L (need g 2) base ++
      [.load r1 r4 0, .load r0 r4 4, .neg r1, .ror r0 r1, .store r4 4 r0, .addImm r4 4]
  | .rotr =>
    uf L (need g 2) base ++
      [.load r1 r4 0, .load r0 r4 4, .ror r0 r1, .store r4 4 r0, .addImm r4 4]
  | .cmp c =>
    let b0 := base + ufSize (need g 2)
    uf L (need g 2) base ++
      [.load r1 r4 0, .load r0 r4 4, .movImm r2 1#32, .bcc c r0 r1 (b0 + 5), .movImm r2 0#32,
       .store r4 4 r2, .addImm r4 4]
  | .select =>
    let b0 := base + ufSize (need g 3)
    uf L (need g 3) base ++
      [.load r1 r4 0, .load r0 r4 4, .load r3 r4 8, .beqz r1 (b0 + 5), .movRR r0 r3,
       .store r4 8 r0, .addImm r4 8]
  | .jmp t => [.jmp (off t)]
  | .branch t => uf L (need g 1) base ++ [.load r0 r4 0, .addImm r4 4, .bnez r0 (off t)]
  | .call t => ovfR L base ++ [.call (off t)]
  | .ret => [.bcc .ne sp r9 (base + 2), .exitTrap .returnUnderflow, .ret]
  | .push r => ovf L g base ++ [.load r0 r5 (4 * (r : Int)), .addImm r4 (-4), .store r4 0 r0]
  | .pop r => uf L (need g 1) base ++ [.load r0 r4 0, .addImm r4 4, .store r5 (4 * (r : Int)) r0]
  | .dup =>
    uf L (need g 1) base ++ ovf L g (base + ufSize (need g 1)) ++ [.load r0 r4 0, .addImm r4 (-4), .store r4 0 r0]
  | .drop => uf L (need g 1) base ++ [.addImm r4 4]
  | .swap => uf L (need g 2) base ++ [.load r0 r4 0, .load r1 r4 4, .store r4 0 r1, .store r4 4 r0]
  | .over =>
    uf L (need g 2) base ++ ovf L g (base + ufSize (need g 2)) ++ [.load r0 r4 4, .addImm r4 (-4), .store r4 0 r0]
  | .rot =>
    uf L (need g 3) base ++
      [.load r0 r4 0, .load r1 r4 4, .load r2 r4 8, .store r4 0 r2, .store r4 4 r0,
       .store r4 8 r1]
  | .tor =>
    uf L (need g 1) base ++ ovfA L (base + ufSize (need g 1)) ++
      [.load r0 r4 0, .addImm r4 4, .addImm r6 (-4), .store r6 0 r0]
  | .fromr =>
    emptyA L base ++ ovf L g (base + 3) ++
      [.load r0 r6 0, .addImm r6 4, .addImm r4 (-4), .store r4 0 r0]
  | .rfetch =>
    emptyA L base ++ ovf L g (base + 3) ++ [.load r0 r6 0, .addImm r4 (-4), .store r4 0 r0]
  | .halt => [.exitHalt]

theorem uf_length (L : Layout) (k base : Nat) : (uf L k base).length = ufSize k := by
  unfold uf ufSize; split <;> simp

theorem ovf_length (L : Layout) (g : Facts) (base : Nat) : (ovf L g base).length = ovfSize g := by
  unfold ovf ovfSize; split <;> simp [ovfD]

theorem lowerInstr_length (L : Layout) (base : Nat) (off : Nat → Nat) (g : Facts)
    (i : WordDialect.Instr 32) : (lowerInstr L base off g i).length = isize g i := by
  cases i <;> simp [lowerInstr, isize, uf_length, ovf_length, ovfR, ovfA, emptyA, udivSeq,
    sdivSeq, udivCode] <;> omega

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

end CM0
end WordDialect
