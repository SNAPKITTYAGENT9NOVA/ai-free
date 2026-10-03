/-!
# WordDialect.Word

The machine word `Word n` is the only primitive value of the Universal Word Dialect.
`n` is the target word width; nothing here depends on any ISA.

A pointer is not a distinct physical type: `Ptr n` is an interpretation of a word as a
word-granular address. Conversion in both directions is the identity on representation.

Conventions fixed here and relied on by every other module:
* Arithmetic is modular (two's complement), exactly `BitVec` arithmetic.
* Unsigned division by zero is *not* defined here; the machine traps (see `Machine`).
* Shift counts are read as unsigned values; a count `>= n` shifts every bit out.
* Rotate counts are reduced modulo `n`.
-/

namespace WordDialect

abbrev Word (n : Nat) := BitVec n

/-- A word interpreted as a word-granular address. Same representation as `Word n`. -/
structure Ptr (n : Nat) where
  addr : Word n
  deriving DecidableEq

namespace Ptr

def ofWord {n : Nat} (w : Word n) : Ptr n := ⟨w⟩
def toWord {n : Nat} (p : Ptr n) : Word n := p.addr

/-- Pointer displacement, in words, modulo `2^n`. -/
def offset {n : Nat} (p : Ptr n) (k : Word n) : Ptr n := ⟨p.addr + k⟩

theorem toWord_ofWord {n : Nat} (w : Word n) : (ofWord w).toWord = w := rfl

theorem ofWord_toWord {n : Nat} (p : Ptr n) : ofWord p.toWord = p := rfl

theorem offset_zero {n : Nat} (p : Ptr n) : p.offset 0 = p := by
  cases p; simp [offset]

theorem offset_offset {n : Nat} (p : Ptr n) (j k : Word n) :
    (p.offset j).offset k = p.offset (j + k) := by
  cases p; simp [offset, BitVec.add_assoc]

theorem offset_injective {n : Nat} (p : Ptr n) {j k : Word n}
    (h : p.offset j = p.offset k) : j = k := by
  cases p with
  | mk a =>
    simp only [offset, Ptr.mk.injEq] at h
    exact (BitVec.add_right_inj a).mp h

end Ptr

/-- Comparison predicates. `CMP c` yields the word `1` when the predicate holds, else `0`. -/
inductive Cond where
  | eq | ne
  | ult | ule | ugt | uge
  | slt | sle | sgt | sge
  deriving DecidableEq, Repr

namespace Cond

def eval {n : Nat} : Cond → Word n → Word n → Bool
  | .eq,  a, b => a == b
  | .ne,  a, b => a != b
  | .ult, a, b => a.ult b
  | .ule, a, b => a.ule b
  | .ugt, a, b => b.ult a
  | .uge, a, b => b.ule a
  | .slt, a, b => a.slt b
  | .sle, a, b => a.sle b
  | .sgt, a, b => b.slt a
  | .sge, a, b => b.sle a

end Cond

namespace Word

def ofBool {n : Nat} (b : Bool) : Word n := if b then 1#n else 0#n

/-- Truthiness used by `BRANCH` and `SELECT`: a word is true iff it is nonzero. -/
def isTrue {n : Nat} (w : Word n) : Bool := w != 0#n

def shl {n : Nat} (a b : Word n) : Word n := if b.toNat < n then a <<< b.toNat else 0#n
def shr {n : Nat} (a b : Word n) : Word n := a >>> b.toNat
def rotl {n : Nat} (a b : Word n) : Word n := a.rotateLeft b.toNat
def rotr {n : Nat} (a b : Word n) : Word n := a.rotateRight b.toNat

theorem isTrue_ofBool {n : Nat} (h : 0 < n) (b : Bool) : isTrue (ofBool (n := n) b) = b := by
  cases b
  · simp [isTrue, ofBool]
  · simp [isTrue, ofBool]
    intro hc
    omega

theorem ofBool_isTrue {n : Nat} (w : Word n) (h : w = 0#n ∨ w = 1#n) :
    ofBool (isTrue w) = w := by
  rcases h with rfl | rfl <;> simp [ofBool, isTrue]

theorem shl_eq {n : Nat} (a b : Word n) : shl a b = a <<< b.toNat := by
  unfold shl
  split
  · rfl
  · rename_i h; exact (BitVec.shiftLeft_eq_zero (by omega)).symm

theorem shl_zero {n : Nat} (a : Word n) : shl a 0#n = a := by rw [shl_eq]; simp
theorem shr_zero {n : Nat} (a : Word n) : shr a 0#n = a := by simp [shr]

theorem shl_toNat {n : Nat} (a b : Word n) : (shl a b).toNat = (a.toNat * 2 ^ b.toNat) % 2 ^ n := by
  rw [shl_eq]; simp [BitVec.toNat_shiftLeft, Nat.shiftLeft_eq]

theorem shr_toNat {n : Nat} (a b : Word n) : (shr a b).toNat = a.toNat / 2 ^ b.toNat := by
  simp [shr, BitVec.toNat_ushiftRight, Nat.shiftRight_eq_div_pow]

theorem shr_le {n : Nat} (a b : Word n) : (shr a b).toNat ≤ a.toNat := by
  rw [shr_toNat]; exact Nat.div_le_self _ _

theorem rotl_zero {n : Nat} (a : Word n) : rotl a 0#n = a := by
  simp only [rotl, BitVec.toNat_ofNat, Nat.zero_mod]
  ext i hi
  simp [BitVec.getElem_rotateLeft]

theorem rotr_rotl {n : Nat} (a b : Word n) (h : b.toNat < n) : rotr (rotl a b) b = a := by
  simp only [rotl, rotr]
  ext i hi
  simp only [BitVec.getElem_rotateRight, BitVec.getElem_rotateLeft, Nat.mod_eq_of_lt h]
  split
  · split
    · omega
    · congr 1; omega
  · split
    · congr 1; omega
    · congr 1; omega

end Word

end WordDialect
