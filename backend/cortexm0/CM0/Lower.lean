import CM0.Isa

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

Every instruction's code has a size that depends only on the instruction, so jump targets are
absolute code indices computed from prefix sums (`offs`). One definition serves both the
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

/-- Stack-underflow guard for `k` operands: continue when `r4 ≤ dEnd - 4k`. -/
def uf (L : Layout) (k base : Nat) : List (Instr Nat) :=
  if k = 0 then []
  else [.movImm r0 (L.dEnd - BitVec.ofNat 32 (4 * k)), .bcc .ule r4 r0 (base + 3),
        .exitTrap .stackUnderflow]

def ufSize (k : Nat) : Nat := if k = 0 then 0 else 3

/-- Data-stack overflow guard: exit 6 unless one more word fits. -/
def ovfD (L : Layout) (base : Nat) : List (Instr Nat) :=
  [.movImm r0 L.dLim, .bcc .uge r4 r0 (base + 3), .exitOvf]

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
def isize : WordDialect.Instr 32 → Nat
  | .word _ | .ptr _ => 6
  | .load => ufSize 1 + 8
  | .store => ufSize 2 + 9
  | .add | .sub | .mul | .and | .or | .xor => ufSize 2 + 5
  | .div => ufSize 2 + 21
  | .sdiv => ufSize 2 + 33
  | .not => ufSize 1 + 3
  | .shl | .shr => ufSize 2 + 8
  | .rotl => ufSize 2 + 6
  | .rotr => ufSize 2 + 5
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

/-- Code for one IR instruction placed at code index `base`; `off t` is the code index of IR
instruction `t` (clamped to the bad-pc stub for out-of-range targets). -/
def lowerInstr (L : Layout) (base : Nat) (off : Nat → Nat) : WordDialect.Instr 32 → List (Instr Nat)
  | .word w => ovfD L base ++ [.movImm r0 w, .addImm r4 (-4), .store r4 0 r0]
  | .ptr p => ovfD L base ++ [.movImm r0 p.toWord, .addImm r4 (-4), .store r4 0 r0]
  | .load =>
    let b0 := base + ufSize 1
    uf L 1 base ++
      [.load r0 r4 0, .movImm r1 (BitVec.ofNat 32 L.memSize), .bcc .ult r0 r1 (b0 + 4),
       .exitTrap .badAddress, .shlImm r0 2, .add r0 r8, .load r0 r0 0, .store r4 0 r0]
  | .store =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load r0 r4 0, .load r1 r4 4, .movImm r2 (BitVec.ofNat 32 L.memSize), .bcc .ult r0 r2 (b0 + 5),
       .exitTrap .badAddress, .shlImm r0 2, .add r0 r8, .store r0 0 r1, .addImm r4 8]
  | .add => uf L 2 base ++ [.load r1 r4 0, .load r0 r4 4, .add r0 r1, .store r4 4 r0, .addImm r4 4]
  | .sub => uf L 2 base ++ [.load r1 r4 0, .load r0 r4 4, .sub r0 r1, .store r4 4 r0, .addImm r4 4]
  | .mul => uf L 2 base ++ [.load r1 r4 0, .load r0 r4 4, .mul r0 r1, .store r4 4 r0, .addImm r4 4]
  | .and => uf L 2 base ++ [.load r1 r4 0, .load r0 r4 4, .and r0 r1, .store r4 4 r0, .addImm r4 4]
  | .or => uf L 2 base ++ [.load r1 r4 0, .load r0 r4 4, .or r0 r1, .store r4 4 r0, .addImm r4 4]
  | .xor => uf L 2 base ++ [.load r1 r4 0, .load r0 r4 4, .xor r0 r1, .store r4 4 r0, .addImm r4 4]
  | .div =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      ([.load r1 r4 0, .load r0 r4 4, .bnez r1 (b0 + 4), .exitTrap .divideByZero] ++
       udivSeq (b0 + 4) ++ [.store r4 4 r0, .addImm r4 4])
  | .sdiv =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      ([.load r1 r4 0, .load r0 r4 4, .bnez r1 (b0 + 4), .exitTrap .divideByZero] ++
       sdivSeq (b0 + 4) ++ [.store r4 4 r0, .addImm r4 4])
  | .not => uf L 1 base ++ [.load r0 r4 0, .not r0, .store r4 0 r0]
  | .shl =>
    uf L 2 base ++
      [.load r1 r4 0, .load r0 r4 4, .lsl r0 r1, .sltiu r2 r1 32, .neg r2, .and r0 r2,
       .store r4 4 r0, .addImm r4 4]
  | .shr =>
    uf L 2 base ++
      [.load r1 r4 0, .load r0 r4 4, .lsr r0 r1, .sltiu r2 r1 32, .neg r2, .and r0 r2,
       .store r4 4 r0, .addImm r4 4]
  | .rotl =>
    uf L 2 base ++
      [.load r1 r4 0, .load r0 r4 4, .neg r1, .ror r0 r1, .store r4 4 r0, .addImm r4 4]
  | .rotr =>
    uf L 2 base ++
      [.load r1 r4 0, .load r0 r4 4, .ror r0 r1, .store r4 4 r0, .addImm r4 4]
  | .cmp c =>
    let b0 := base + ufSize 2
    uf L 2 base ++
      [.load r1 r4 0, .load r0 r4 4, .movImm r2 1#32, .bcc c r0 r1 (b0 + 5), .movImm r2 0#32,
       .store r4 4 r2, .addImm r4 4]
  | .select =>
    let b0 := base + ufSize 3
    uf L 3 base ++
      [.load r1 r4 0, .load r0 r4 4, .load r3 r4 8, .beqz r1 (b0 + 5), .movRR r0 r3,
       .store r4 8 r0, .addImm r4 8]
  | .jmp t => [.jmp (off t)]
  | .branch t => uf L 1 base ++ [.load r0 r4 0, .addImm r4 4, .bnez r0 (off t)]
  | .call t => ovfR L base ++ [.call (off t)]
  | .ret => [.bcc .ne sp r9 (base + 2), .exitTrap .returnUnderflow, .ret]
  | .push r => ovfD L base ++ [.load r0 r5 (4 * (r : Int)), .addImm r4 (-4), .store r4 0 r0]
  | .pop r => uf L 1 base ++ [.load r0 r4 0, .addImm r4 4, .store r5 (4 * (r : Int)) r0]
  | .dup =>
    uf L 1 base ++ ovfD L (base + ufSize 1) ++ [.load r0 r4 0, .addImm r4 (-4), .store r4 0 r0]
  | .drop => uf L 1 base ++ [.addImm r4 4]
  | .swap => uf L 2 base ++ [.load r0 r4 0, .load r1 r4 4, .store r4 0 r1, .store r4 4 r0]
  | .over =>
    uf L 2 base ++ ovfD L (base + ufSize 2) ++ [.load r0 r4 4, .addImm r4 (-4), .store r4 0 r0]
  | .rot =>
    uf L 3 base ++
      [.load r0 r4 0, .load r1 r4 4, .load r2 r4 8, .store r4 0 r2, .store r4 4 r0,
       .store r4 8 r1]
  | .tor =>
    uf L 1 base ++ ovfA L (base + ufSize 1) ++
      [.load r0 r4 0, .addImm r4 4, .addImm r6 (-4), .store r6 0 r0]
  | .fromr =>
    emptyA L base ++ ovfD L (base + 3) ++
      [.load r0 r6 0, .addImm r6 4, .addImm r4 (-4), .store r4 0 r0]
  | .rfetch =>
    emptyA L base ++ ovfD L (base + 3) ++ [.load r0 r6 0, .addImm r4 (-4), .store r4 0 r0]
  | .halt => [.exitHalt]

theorem lowerInstr_length (L : Layout) (base : Nat) (off : Nat → Nat) (i : WordDialect.Instr 32) :
    (lowerInstr L base off i).length = isize i := by
  cases i <;> simp [lowerInstr, isize, uf, ufSize, ovfD, ovfR, ovfA, emptyA, udivSeq, sdivSeq, udivCode] <;> (try split) <;> simp

/-- Prefix sums of instruction sizes: `offs p k` is the code index of IR instruction `k`.
For `k` past the end it is the index of the final bad-pc stub. -/
def offs (p : Prog 32) (k : Nat) : Nat := ((p.take k).map isize).sum

def lowerGo (L : Layout) (off : Nat → Nat) : Nat → List (WordDialect.Instr 32) → List (Instr Nat)
  | _, [] => [.exitTrap .badPc]
  | b, i :: is => lowerInstr L b off i ++ lowerGo L off (b + isize i) is

/-- The whole program; the last instruction is the bad-pc stub, so jumping past the end of the
IR program traps `badPc` exactly as the IR semantics does. -/
def lowerProg (L : Layout) (p : Prog 32) : List (Instr Nat) := lowerGo L (offs p) 0 p

end CM0
end WordDialect
