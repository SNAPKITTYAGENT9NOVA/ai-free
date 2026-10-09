import WordIR

/-!
# Forth.Double

IR code for the double-cell words. `UM*` and `UM/MOD` are loops over the `n` bits of a word, built from single-word instructions only (shifts, `ADD`, `SUB`, `MUL`, `CMP`, `OR`) and
the IR's virtual registers, with `countedLoop` running the body `n` times. `Forth.DoubleCorrect`
proves that they compute `Op.sem`.

`UM* ( a b -- lo hi )`, shift-and-add from the top bit of `b` down. Registers: `0` = `a`,
`1` = `b` shifted left by the bits done so far, `2` = `lo`, `3` = `hi`, `4` = the loop counter.
Each round doubles `(hi, lo)` and adds `a` times the top bit of register `1`:

```
hi := (hi << 1) + (lo >> (n-1));  lo := lo << 1
x := a * (b >> (n-1));  lo := x + lo;  hi := (lo <u x) + hi
b := b << 1
```

`UM/MOD ( lo hi u -- rem quot )`, restoring division. Registers: `0` = `u`, `1` = the partial
remainder `r` (starting at `hi`), `2` = `lo` shifted left by the bits done so far, `3` = the
quotient, `4` = the loop counter. It first traps unless `hi <u u`, by dividing `1` by that flag.
Each round shifts `(r, lo)` left by one and subtracts `u` when the shifted remainder reaches `u`
or overflowed:

```
t := r >> (n-1);  r2 := (r << 1) + (lo >> (n-1));  lo := lo << 1
c := t | (r2 >=u u);  q := (q << 1) + c;  r := r2 - c * u
```
-/

namespace WordDialect
namespace Forth

open IR

/-- `UM*` before the loop: `b` and `a` into registers 1 and 0, `lo = hi = 0`. -/
def umStarPre {n : Nat} : List (Instr n) := [.pop 1, .pop 0, .word 0#n, .pop 2, .word 0#n, .pop 3]

/-- One round of `UM*`. -/
def umStarBody {n : Nat} : List (Instr n) :=
  [.push 3, .word 1#n, .shl, .push 2, .word (BitVec.ofNat n (n - 1)), .shr, .add, .pop 3,
   .push 2, .word 1#n, .shl, .pop 2,
   .push 0, .push 1, .word (BitVec.ofNat n (n - 1)), .shr, .mul,
   .dup, .push 2, .add, .dup, .pop 2, .swap, .cmp .ult, .push 3, .add, .pop 3,
   .push 1, .word 1#n, .shl, .pop 1]

/-- `UM*` after the loop: push `lo`, then `hi`. -/
def umStarPost {n : Nat} : List (Instr n) := [.push 2, .push 3]

def umStarFrag {n : Nat} : Frag n :=
  (Frag.ofCode umStarPre).seq ((countedLoop 4 n (Frag.ofCode umStarBody)).seq (Frag.ofCode umStarPost))

/-- `UM/MOD` before the loop: `u`, `hi`, `lo` into registers 0, 1, 2; trap unless `hi <u u`;
quotient `0`. -/
def umDivPre {n : Nat} : List (Instr n) :=
  [.pop 0, .pop 1, .pop 2, .word 1#n, .push 1, .push 0, .cmp .ult, .div, .drop, .word 0#n, .pop 3]

/-- One round of `UM/MOD`. -/
def umDivBody {n : Nat} : List (Instr n) :=
  [.push 1, .word (BitVec.ofNat n (n - 1)), .shr,
   .push 1, .word 1#n, .shl, .push 2, .word (BitVec.ofNat n (n - 1)), .shr, .add,
   .push 2, .word 1#n, .shl, .pop 2,
   .dup, .push 0, .cmp .uge, .rot, .or,
   .dup, .push 3, .word 1#n, .shl, .add, .pop 3,
   .push 0, .mul, .sub, .pop 1]

/-- `UM/MOD` after the loop: push the remainder, then the quotient. -/
def umDivPost {n : Nat} : List (Instr n) := [.push 1, .push 3]

def umDivFrag {n : Nat} : Frag n :=
  (Frag.ofCode umDivPre).seq ((countedLoop 4 n (Frag.ofCode umDivBody)).seq (Frag.ofCode umDivPost))

/-- `M*` before `UM*`: keep `b` in register 6 and `a` in register 5. -/
def mStarPre {n : Nat} : List (Instr n) := [.dup, .pop 6, .over, .pop 5]

/-- `M*` after `UM*`: `hi := hi - (a <s 0) * b - (b <s 0) * a` turns the unsigned product of the
bit patterns into the signed product. -/
def mStarPost {n : Nat} : List (Instr n) :=
  [.push 5, .word 0#n, .cmp .slt, .push 6, .mul, .sub,
   .push 6, .word 0#n, .cmp .slt, .push 5, .mul, .sub]

def mStarFrag {n : Nat} : Frag n :=
  (Frag.ofCode mStarPre).seq (umStarFrag.seq (Frag.ofCode mStarPost))

/-- `SM/REM` before `UM/MOD`: register 6 := the dividend's sign (`hi <s 0`), register 5 := the
quotient's sign (that xor `v <s 0`), register 7 := `|v|`; the dividend `(lo, hi)` is negated (two
words with a borrow) when it is negative, and `|v|` goes back on top. -/
def smRemPre {n : Nat} : List (Instr n) :=
  [.over, .word 0#n, .cmp .slt, .pop 6,
   .dup, .word 0#n, .cmp .slt, .push 6, .xor, .pop 5,
   .dup, .word 0#n, .swap, .sub, .swap, .dup, .word 0#n, .cmp .slt, .select, .pop 7,
   .swap, .word 0#n, .push 6, .sub, .xor, .push 6, .add, .dup, .push 6, .cmp .ult, .rot,
   .word 0#n, .push 6, .sub, .xor, .add,
   .push 7]

/-- `SM/REM` after `UM/MOD`: trap unless the unsigned quotient `q` fits the signed result
(`q <u 2^(n-1)`, or `q = 2^(n-1)` when the quotient is negative), by dividing `1` by that flag;
then give the quotient the sign in register 5 and the remainder the sign in register 6. -/
def smRemPost {n : Nat} : List (Instr n) :=
  [.dup, .word (BitVec.intMin n), .cmp .ult, .over, .word (BitVec.intMin n), .cmp .eq, .push 5,
   .and, .or, .word 1#n, .swap, .div, .drop,
   .word 0#n, .push 5, .sub, .xor, .push 5, .add,
   .swap, .word 0#n, .push 6, .sub, .xor, .push 6, .add, .swap]

def smRemFrag {n : Nat} : Frag n :=
  (Frag.ofCode smRemPre).seq (umDivFrag.seq (Frag.ofCode smRemPost))

/-- `FM/MOD` after `UM/MOD`, with the quotient `q` and remainder `r` of the absolute values in
registers 3 and 1. When the signs differ (register 5) and `r ≠ 0`, the floored result is
`q + 1` and `|v| - r` (register 7 holds `|v|`); register 2 holds that flag. Trap unless the
quotient fits: `q <u 2^(n-1)`, or `q = 2^(n-1)` with differing signs and `r = 0`. The remainder
takes the sign of `v` (registers 5 xor 6), the quotient that of register 5. -/
def fmModPost {n : Nat} : List (Instr n) :=
  [.pop 3, .pop 1,
   .push 1, .word 0#n, .cmp .ne, .push 5, .and, .pop 2,
   .push 3, .word (BitVec.intMin n), .cmp .ult,
   .push 3, .word (BitVec.intMin n), .cmp .eq, .push 5, .and, .push 1, .word 0#n, .cmp .eq, .and,
   .or, .word 1#n, .swap, .div, .drop,
   .push 7, .push 1, .sub, .push 1, .push 2, .select,
   .word 0#n, .push 5, .push 6, .xor, .sub, .xor, .push 5, .push 6, .xor, .add,
   .push 3, .push 2, .add,
   .word 0#n, .push 5, .sub, .xor, .push 5, .add]

/-- `FM/MOD ( lo hi v -- rem quot )`: `SM/REM`'s preparation, `UM/MOD`, then `fmModPost`. -/
def fmModFrag {n : Nat} : Frag n :=
  (Frag.ofCode smRemPre).seq (umDivFrag.seq (Frag.ofCode fmModPost))

/-- `*/MOD ( n1 n2 n3 -- rem quot )`: `n3` to the return-data stack, `M*`, `n3` back, `SM/REM`. -/
def starSlashModFrag {n : Nat} : Frag n :=
  (Frag.ofCode [.tor]).seq (mStarFrag.seq ((Frag.ofCode [.fromr]).seq smRemFrag))

/-- `*/ ( n1 n2 n3 -- quot )`: `*/MOD SWAP DROP`. -/
def starSlashFrag {n : Nat} : Frag n :=
  starSlashModFrag.seq (Frag.ofCode [.swap, .drop])

theorem umStarFrag_size {n : Nat} : (umStarFrag : Frag n).size = 51 := by
  simp [umStarFrag, Frag.seq_size, countedLoop_size, Frag.ofCode_size, umStarPre, umStarBody,
    umStarPost]

theorem mStarFrag_size {n : Nat} : (mStarFrag : Frag n).size = 67 := by
  simp [mStarFrag, Frag.seq_size, umStarFrag_size, Frag.ofCode_size, mStarPre, mStarPost]

theorem umDivFrag_size {n : Nat} : (umDivFrag : Frag n).size = 54 := by
  simp [umDivFrag, Frag.seq_size, countedLoop_size, Frag.ofCode_size, umDivPre, umDivBody,
    umDivPost]

theorem smRemFrag_size {n : Nat} : (smRemFrag : Frag n).size = 118 := by
  simp [smRemFrag, Frag.seq_size, umDivFrag_size, Frag.ofCode_size, smRemPre, smRemPost]

theorem starSlashModFrag_size {n : Nat} : (starSlashModFrag : Frag n).size = 187 := by
  simp [starSlashModFrag, Frag.seq_size, mStarFrag_size, smRemFrag_size, Frag.ofCode_size]

theorem starSlashFrag_size {n : Nat} : (starSlashFrag : Frag n).size = 189 := by
  simp [starSlashFrag, Frag.seq_size, starSlashModFrag_size, Frag.ofCode_size]

theorem fmModFrag_size {n : Nat} : (fmModFrag : Frag n).size = 141 := by
  simp [fmModFrag, Frag.seq_size, umDivFrag_size, Frag.ofCode_size, smRemPre, fmModPost]

end Forth
end WordDialect
