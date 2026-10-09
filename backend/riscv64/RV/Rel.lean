import RV.Run

/-!
# RV.Rel

The state relation between the IR machine and the RISC-V model, and the memory-frame lemmas used
by the per-instruction simulation proofs.

Memory regions (byte intervals, all below `2^64`, pairwise disjoint):
* data stack  `[dBase, dEnd)`, top at `dEnd - 8k` when `k` words are on the stack;
* register file `[rf, rf + 8 nregs)`;
* IR memory `[mb, mb + 8 M)`;
* return stack: the return stack (`.rstack`) below `sp0`;
* auxiliary stack `[aBase, aEnd)`, top at `aEnd - 8k` when `k` words are on it (pointer `s6`).

Everything is stated with `BitVec.ofNat 64` of natural-number addresses, so address arithmetic
is ordinary `omega` reasoning.
-/

namespace WordDialect
namespace RV

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
  dEnd_lt : c.dEnd < 2 ^ 64
  rf_lt : c.rf + 8 * c.nregs ≤ 2 ^ 64
  mb_lt : c.mb + 8 * c.M ≤ 2 ^ 64
  sp0_lt : c.sp0 < 2 ^ 64
  dBase_le : c.dBase ≤ c.dEnd
  dEnd_ge : 24 ≤ c.dEnd
  rcap_le : 8 * c.rcap ≤ c.sp0
  dBase_8 : c.dBase + 8 ≤ c.dEnd
  rcap_ge : 2 ≤ c.rcap
  dS_F : c.dEnd ≤ c.rf ∨ c.rf + 8 * c.nregs ≤ c.dBase
  dS_M : c.dEnd ≤ c.mb ∨ c.mb + 8 * c.M ≤ c.dBase
  dS_K : c.dEnd ≤ c.sp0 - 8 * c.rcap ∨ c.sp0 ≤ c.dBase
  dF_M : c.rf + 8 * c.nregs ≤ c.mb ∨ c.mb + 8 * c.M ≤ c.rf
  dF_K : c.rf + 8 * c.nregs ≤ c.sp0 - 8 * c.rcap ∨ c.sp0 ≤ c.rf
  dM_K : c.mb + 8 * c.M ≤ c.sp0 - 8 * c.rcap ∨ c.sp0 ≤ c.mb
  aEnd_lt : c.aEnd < 2 ^ 64
  aBase_8 : c.aBase + 8 ≤ c.aEnd
  dS_A : c.dEnd ≤ c.aBase ∨ c.aEnd ≤ c.dBase
  dA_F : c.aEnd ≤ c.rf ∨ c.rf + 8 * c.nregs ≤ c.aBase
  dA_M : c.aEnd ≤ c.mb ∨ c.mb + 8 * c.M ≤ c.aBase
  dA_K : c.aEnd ≤ c.sp0 - 8 * c.rcap ∨ c.sp0 ≤ c.aBase

def ofN (a : Nat) : W := BitVec.ofNat 64 a

theorem ofN_inj {a b : Nat} (ha : a < 2 ^ 64) (hb : b < 2 ^ 64) (h : ofN a = ofN b) : a = b := by
  have := congrArg BitVec.toNat h
  simpa [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] using this

theorem ofN_add (a b : Nat) : ofN a + ofN b = ofN (a + b) := (BitVec.ofNat_add a b).symm

theorem ofN_sub {a b : Nat} (h : b ≤ a) : ofN a - ofN b = ofN (a - b) := by
  apply BitVec.eq_of_toNat_eq
  simp only [ofN, BitVec.toNat_sub, BitVec.toNat_ofNat]
  have h1 : (a - b) % 2 ^ 64 = ((2 ^ 64 - b % 2 ^ 64) + a % 2 ^ 64) % 2 ^ 64 := by
    omega
  exact h1.symm

/-- Reading after a write at a natural-number address. -/
theorem read_write_nat {mem mem' : Memory 64} {A B : Nat} {v : W}
    (hw : mem.write? (ofN A) v = some mem') (hA : A < 2 ^ 64) (hB : B < 2 ^ 64) :
    mem'.read? (ofN B) = if A = B then some v else mem.read? (ofN B) := by
  by_cases h : A = B
  · subst h; simp [Memory.read_write_same hw]
  · have hne : ofN B ≠ ofN A := by
      intro e; exact h (ofN_inj hA hB e.symm)
    rw [Memory.read_write_other hw hne]; simp [h]

def StackRel (c : Cfg) (mem : Memory 64) (d : List W) : Prop :=
  ∀ i v, d[i]? = some v → mem.read? (ofN (c.dEnd - 8 * d.length + 8 * i)) = some v

def AuxRel (c : Cfg) (mem : Memory 64) (as : List W) : Prop :=
  ∀ i v, as[i]? = some v → mem.read? (ofN (c.aEnd - 8 * as.length + 8 * i)) = some v

def RegRel (c : Cfg) (mem : Memory 64) (regs : Nat → W) : Prop :=
  ∀ r, r < c.nregs → mem.read? (ofN (c.rf + 8 * r)) = some (regs r)

def MemRel (c : Cfg) (mem : Memory 64) (m : Memory 64) : Prop :=
  ∀ a, a < c.M → mem.read? (ofN (c.mb + 8 * a)) = some (m.cell (ofN a))

def RsRel (c : Cfg) (p : Prog 64) (mem : Memory 64) (rs : List Nat) : Prop :=
  ∀ i a, rs[i]? = some a → mem.read? (ofN (c.sp0 - 8 * rs.length + 8 * i)) = some (ofN (offs p a))

/-- The RISC-V memory's addressable set covers every region. -/
def RegionsValid (c : Cfg) (v : W → Bool) : Prop :=
  (∀ a, c.dBase ≤ a → a < c.dEnd → v (ofN a) = true) ∧
  (∀ a, c.rf ≤ a → a < c.rf + 8 * c.nregs → v (ofN a) = true) ∧
  (∀ a, c.mb ≤ a → a < c.mb + 8 * c.M → v (ofN a) = true) ∧
  (∀ a, c.sp0 - 8 * c.rcap ≤ a → a < c.sp0 → v (ofN a) = true) ∧
  (∀ a, c.aBase ≤ a → a < c.aEnd → v (ofN a) = true)

structure Rel0 (c : Cfg) (p : Prog 64) (s : State 64) (x : M) : Prop where
  s1 : x.regs s1 = ofN (c.dEnd - 8 * s.dstack.length)
  s2 : x.regs s2 = ofN c.rf
  s3 : x.regs s3 = ofN c.mb
  s4 : x.regs s4 = ofN c.sp0
  s5 : x.regs s5 = ofN (c.sp0 - 8 * s.rstack.length)
  s6 : x.regs s6 = ofN (c.aEnd - 8 * s.astack.length)
  stack : StackRel c x.mem s.dstack
  regs : RegRel c x.mem s.regs
  mem : MemRel c x.mem s.mem
  rs : RsRel c p x.mem s.rstack
  aux : AuxRel c x.mem s.astack
  irvalid : ∀ a : Word 64, s.mem.valid a = decide (a.toNat < c.M)
  xvalid : RegionsValid c x.mem.valid
  capD : c.dBase + 8 * s.dstack.length ≤ c.dEnd
  capR : s.rstack.length + 1 ≤ c.rcap
  capA : c.aBase + 8 * s.astack.length ≤ c.aEnd

/-- Full relation: everything in `Rel0`, and the RISC-V pc is the start of the IR pc's code. -/
def Rel (c : Cfg) (p : Prog 64) (s : State 64) (x : M) : Prop :=
  Rel0 c p s x ∧ x.pc = offs p s.pc

/-- `Rel0` does not look at scratch registers or the pc. -/
theorem Rel0.congr {c : Cfg} {p : Prog 64} {s : State 64} {x x' : M} (h : Rel0 c p s x)
    (hm : x'.mem = x.mem) (h15 : x'.regs Reg.s1 = x.regs Reg.s1) (h14 : x'.regs Reg.s2 = x.regs Reg.s2)
    (h13 : x'.regs Reg.s3 = x.regs Reg.s3) (h12 : x'.regs Reg.s4 = x.regs Reg.s4)
    (hsp : x'.regs Reg.s5 = x.regs Reg.s5) (hbp : x'.regs Reg.s6 = x.regs Reg.s6) :
    Rel0 c p s x' where
  s1 := by rw [h15]; exact h.s1
  s2 := by rw [h14]; exact h.s2
  s3 := by rw [h13]; exact h.s3
  s4 := by rw [h12]; exact h.s4
  s5 := by rw [hsp]; exact h.s5
  s6 := by rw [hbp]; exact h.s6
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
theorem aux_write_other {c : Cfg} {mem mem' : Memory 64} {as : List W} (haE : c.aEnd < 2 ^ 64)
    (hcap : c.aBase + 8 * as.length ≤ c.aEnd) (h : AuxRel c mem as) {A : Nat} {v : W}
    (hw : mem.write? (ofN A) v = some mem') (hAlt : A < 2 ^ 64) (hA : A < c.aBase ∨ c.aEnd ≤ A) :
    AuxRel c mem' as := by
  intro i w hi
  have hik : i < as.length := by
    by_cases hh : i < as.length
    · exact hh
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  have hB : c.aEnd - 8 * as.length + 8 * i < 2 ^ 64 := by omega
  have hne : A ≠ c.aEnd - 8 * as.length + 8 * i := by omega
  rw [read_write_nat hw hAlt hB]
  simp only [hne, ite_false]
  exact h i w hi

end RV
end WordDialect
