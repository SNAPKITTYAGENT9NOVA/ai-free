import CM.Run

/-!
# CM.Rel

The state relation between the IR machine and the Thumb-2 model, and the memory-frame lemmas used
by the per-instruction simulation proofs.

Memory regions (byte intervals, all below `2^32`, pairwise disjoint):
* data stack  `[dBase, dEnd)`, top at `dEnd - 4k` when `k` words are on the stack;
* register file `[rf, rf + 4 nregs)`;
* IR memory `[mb, mb + 4 M)`;
* return stack: the return stack (`.rstack`) below `sp0`;
* auxiliary stack `[aBase, aEnd)`, top at `aEnd - 4k` when `k` words are on it (pointer `r9`).

Everything is stated with `BitVec.ofNat 32` of natural-number addresses, so address arithmetic
is ordinary `omega` reasoning.
-/

namespace WordDialect
namespace CM

open Reg

structure Cfg where
  dEnd : Nat
  dBase : Nat
  rf : Nat
  nregs : Nat
  mb : Nat
  M : Nat
  sp0 : Nat
  rcap : Nat
  aEnd : Nat
  aBase : Nat

structure Geom (c : Cfg) : Prop where
  dEnd_lt : c.dEnd < 2 ^ 32
  rf_lt : c.rf + 4 * c.nregs ≤ 2 ^ 32
  mb_lt : c.mb + 4 * c.M ≤ 2 ^ 32
  sp0_lt : c.sp0 < 2 ^ 32
  dBase_le : c.dBase ≤ c.dEnd
  dEnd_ge : 12 ≤ c.dEnd
  rcap_le : 4 * c.rcap ≤ c.sp0
  dBase_8 : c.dBase + 4 ≤ c.dEnd
  rcap_ge : 2 ≤ c.rcap
  dS_F : c.dEnd ≤ c.rf ∨ c.rf + 4 * c.nregs ≤ c.dBase
  dS_M : c.dEnd ≤ c.mb ∨ c.mb + 4 * c.M ≤ c.dBase
  dS_K : c.dEnd ≤ c.sp0 - 4 * c.rcap ∨ c.sp0 ≤ c.dBase
  dF_M : c.rf + 4 * c.nregs ≤ c.mb ∨ c.mb + 4 * c.M ≤ c.rf
  dF_K : c.rf + 4 * c.nregs ≤ c.sp0 - 4 * c.rcap ∨ c.sp0 ≤ c.rf
  dM_K : c.mb + 4 * c.M ≤ c.sp0 - 4 * c.rcap ∨ c.sp0 ≤ c.mb
  aEnd_lt : c.aEnd < 2 ^ 32
  aBase_8 : c.aBase + 4 ≤ c.aEnd
  dS_A : c.dEnd ≤ c.aBase ∨ c.aEnd ≤ c.dBase
  dA_F : c.aEnd ≤ c.rf ∨ c.rf + 4 * c.nregs ≤ c.aBase
  dA_M : c.aEnd ≤ c.mb ∨ c.mb + 4 * c.M ≤ c.aBase
  dA_K : c.aEnd ≤ c.sp0 - 4 * c.rcap ∨ c.sp0 ≤ c.aBase

def ofN (a : Nat) : W := BitVec.ofNat 32 a

theorem ofN_inj {a b : Nat} (ha : a < 2 ^ 32) (hb : b < 2 ^ 32) (h : ofN a = ofN b) : a = b := by
  have := congrArg BitVec.toNat h
  simpa [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] using this

theorem ofN_add (a b : Nat) : ofN a + ofN b = ofN (a + b) := (BitVec.ofNat_add a b).symm

theorem ofN_sub {a b : Nat} (h : b ≤ a) : ofN a - ofN b = ofN (a - b) := by
  apply BitVec.eq_of_toNat_eq
  simp only [ofN, BitVec.toNat_sub, BitVec.toNat_ofNat]
  have h1 : (a - b) % 2 ^ 32 = ((2 ^ 32 - b % 2 ^ 32) + a % 2 ^ 32) % 2 ^ 32 := by
    omega
  exact h1.symm

/-- Reading after a write at a natural-number address. -/
theorem read_write_nat {mem mem' : Memory 32} {A B : Nat} {v : W}
    (hw : mem.write? (ofN A) v = some mem') (hA : A < 2 ^ 32) (hB : B < 2 ^ 32) :
    mem'.read? (ofN B) = if A = B then some v else mem.read? (ofN B) := by
  by_cases h : A = B
  · subst h; simp [Memory.read_write_same hw]
  · have hne : ofN B ≠ ofN A := by
      intro e; exact h (ofN_inj hA hB e.symm)
    rw [Memory.read_write_other hw hne]; simp [h]

def StackRel (c : Cfg) (mem : Memory 32) (d : List W) : Prop :=
  ∀ i v, d[i]? = some v → mem.read? (ofN (c.dEnd - 4 * d.length + 4 * i)) = some v

def AuxRel (c : Cfg) (mem : Memory 32) (as : List W) : Prop :=
  ∀ i v, as[i]? = some v → mem.read? (ofN (c.aEnd - 4 * as.length + 4 * i)) = some v

def RegRel (c : Cfg) (mem : Memory 32) (regs : Nat → W) : Prop :=
  ∀ r, r < c.nregs → mem.read? (ofN (c.rf + 4 * r)) = some (regs r)

def MemRel (c : Cfg) (mem : Memory 32) (m : Memory 32) : Prop :=
  ∀ a, a < c.M → mem.read? (ofN (c.mb + 4 * a)) = some (m.cell (ofN a))

def RsRel (c : Cfg) (p : Prog 32) (mem : Memory 32) (rs : List Nat) : Prop :=
  ∀ i a, rs[i]? = some a → mem.read? (ofN (c.sp0 - 4 * rs.length + 4 * i)) = some (ofN (offs p a))

/-- The Thumb-2 memory's addressable set covers every region. -/
def RegionsValid (c : Cfg) (v : W → Bool) : Prop :=
  (∀ a, c.dBase ≤ a → a < c.dEnd → v (ofN a) = true) ∧
  (∀ a, c.rf ≤ a → a < c.rf + 4 * c.nregs → v (ofN a) = true) ∧
  (∀ a, c.mb ≤ a → a < c.mb + 4 * c.M → v (ofN a) = true) ∧
  (∀ a, c.sp0 - 4 * c.rcap ≤ a → a < c.sp0 → v (ofN a) = true) ∧
  (∀ a, c.aBase ≤ a → a < c.aEnd → v (ofN a) = true)

structure Rel0 (c : Cfg) (p : Prog 32) (s : State 32) (x : M) : Prop where
  r4 : x.regs r4 = ofN (c.dEnd - 4 * s.dstack.length)
  r5 : x.regs r5 = ofN c.rf
  r6 : x.regs r6 = ofN c.mb
  r7 : x.regs r7 = ofN c.sp0
  r8 : x.regs r8 = ofN (c.sp0 - 4 * s.rstack.length)
  r9 : x.regs r9 = ofN (c.aEnd - 4 * s.astack.length)
  stack : StackRel c x.mem s.dstack
  regs : RegRel c x.mem s.regs
  mem : MemRel c x.mem s.mem
  rs : RsRel c p x.mem s.rstack
  aux : AuxRel c x.mem s.astack
  irvalid : ∀ a : Word 32, s.mem.valid a = decide (a.toNat < c.M)
  xvalid : RegionsValid c x.mem.valid
  capD : c.dBase + 4 * s.dstack.length ≤ c.dEnd
  capR : s.rstack.length + 1 ≤ c.rcap
  capA : c.aBase + 4 * s.astack.length ≤ c.aEnd

/-- Full relation: everything in `Rel0`, and the Thumb-2 pc is the start of the IR pc's code. -/
def Rel (c : Cfg) (p : Prog 32) (s : State 32) (x : M) : Prop :=
  Rel0 c p s x ∧ x.pc = offs p s.pc

/-- `Rel0` does not look at scratch registers or the pc. -/
theorem Rel0.congr {c : Cfg} {p : Prog 32} {s : State 32} {x x' : M} (h : Rel0 c p s x)
    (hm : x'.mem = x.mem) (h15 : x'.regs Reg.r4 = x.regs Reg.r4) (h14 : x'.regs Reg.r5 = x.regs Reg.r5)
    (h13 : x'.regs Reg.r6 = x.regs Reg.r6) (h12 : x'.regs Reg.r7 = x.regs Reg.r7)
    (hsp : x'.regs Reg.r8 = x.regs Reg.r8) (hbp : x'.regs Reg.r9 = x.regs Reg.r9) :
    Rel0 c p s x' where
  r4 := by rw [h15]; exact h.r4
  r5 := by rw [h14]; exact h.r5
  r6 := by rw [h13]; exact h.r6
  r7 := by rw [h12]; exact h.r7
  r8 := by rw [hsp]; exact h.r8
  r9 := by rw [hbp]; exact h.r9
  stack := by rw [hm]; exact h.stack
  regs := by rw [hm]; exact h.regs
  mem := by rw [hm]; exact h.mem
  rs := by rw [hm]; exact h.rs
  aux := by rw [hm]; exact h.aux
  irvalid := h.irvalid
  xvalid := by rw [hm]; exact h.xvalid
  capD := h.capD
  capR := h.capR
  capA := h.capA

/-- A write outside the auxiliary-stack region leaves the auxiliary-stack view unchanged. -/
theorem aux_write_other {c : Cfg} {mem mem' : Memory 32} {as : List W} (haE : c.aEnd < 2 ^ 32)
    (hcap : c.aBase + 4 * as.length ≤ c.aEnd) (h : AuxRel c mem as) {A : Nat} {v : W}
    (hw : mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 32) (hA : A < c.aBase ∨ c.aEnd ≤ A) :
    AuxRel c mem' as := by
  intro i w hi
  have hik : i < as.length := by
    by_cases hh : i < as.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  have hB : c.aEnd - 4 * as.length + 4 * i < 2 ^ 32 := by omega
  have hne : A ≠ c.aEnd - 4 * as.length + 4 * i := by omega
  rw [read_write_nat hw hAlt hB]
  simp only [hne, ite_false]
  exact h i w hi

end CM
end WordDialect
