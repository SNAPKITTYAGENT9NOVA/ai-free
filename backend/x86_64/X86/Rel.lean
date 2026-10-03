import X86.Run

/-!
# X86.Rel

The state relation between the IR machine and the x86 model, and the memory-frame lemmas used
by the per-instruction simulation proofs.

Memory regions (byte intervals, all below `2^64`, pairwise disjoint):
* data stack  `[dBase, dEnd)`, top at `dEnd - 8k` when `k` words are on the stack;
* register file `[rf, rf + 8 nregs)`;
* IR memory `[mb, mb + 8 M)`;
* return stack: the native stack below `sp0`.

Everything is stated with `BitVec.ofNat 64` of natural-number addresses, so address arithmetic
is ordinary `omega` reasoning.
-/

namespace WordDialect
namespace X86

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

structure Geom (c : Cfg) : Prop where
  dEnd_lt : c.dEnd < 2 ^ 64
  rf_lt : c.rf + 8 * c.nregs ≤ 2 ^ 64
  mb_lt : c.mb + 8 * c.M ≤ 2 ^ 64
  sp0_lt : c.sp0 < 2 ^ 64
  dBase_le : c.dBase ≤ c.dEnd
  dEnd_ge : 24 ≤ c.dEnd
  rcap_le : 8 * c.rcap ≤ c.sp0
  dS_F : c.dEnd ≤ c.rf ∨ c.rf + 8 * c.nregs ≤ c.dBase
  dS_M : c.dEnd ≤ c.mb ∨ c.mb + 8 * c.M ≤ c.dBase
  dS_K : c.dEnd ≤ c.sp0 - 8 * c.rcap ∨ c.sp0 ≤ c.dBase
  dF_M : c.rf + 8 * c.nregs ≤ c.mb ∨ c.mb + 8 * c.M ≤ c.rf
  dF_K : c.rf + 8 * c.nregs ≤ c.sp0 - 8 * c.rcap ∨ c.sp0 ≤ c.rf
  dM_K : c.mb + 8 * c.M ≤ c.sp0 - 8 * c.rcap ∨ c.sp0 ≤ c.mb

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

def RegRel (c : Cfg) (mem : Memory 64) (regs : Nat → W) : Prop :=
  ∀ r, r < c.nregs → mem.read? (ofN (c.rf + 8 * r)) = some (regs r)

def MemRel (c : Cfg) (mem : Memory 64) (m : Memory 64) : Prop :=
  ∀ a, a < c.M → mem.read? (ofN (c.mb + 8 * a)) = some (m.cell (ofN a))

def RsRel (c : Cfg) (p : Prog 64) (mem : Memory 64) (rs : List Nat) : Prop :=
  ∀ i a, rs[i]? = some a → mem.read? (ofN (c.sp0 - 8 * rs.length + 8 * i)) = some (ofN (offs p a))

/-- The x86 memory's addressable set covers every region. -/
def RegionsValid (c : Cfg) (v : W → Bool) : Prop :=
  (∀ a, c.dBase ≤ a → a < c.dEnd → v (ofN a) = true) ∧
  (∀ a, c.rf ≤ a → a < c.rf + 8 * c.nregs → v (ofN a) = true) ∧
  (∀ a, c.mb ≤ a → a < c.mb + 8 * c.M → v (ofN a) = true) ∧
  (∀ a, c.sp0 - 8 * c.rcap ≤ a → a < c.sp0 → v (ofN a) = true)

structure Rel0 (c : Cfg) (p : Prog 64) (s : State 64) (x : M) : Prop where
  r15 : x.regs r15 = ofN (c.dEnd - 8 * s.dstack.length)
  r14 : x.regs r14 = ofN c.rf
  r13 : x.regs r13 = ofN c.mb
  r12 : x.regs r12 = ofN c.sp0
  rsp : x.regs rsp = ofN (c.sp0 - 8 * s.rstack.length)
  stack : StackRel c x.mem s.dstack
  regs : RegRel c x.mem s.regs
  mem : MemRel c x.mem s.mem
  rs : RsRel c p x.mem s.rstack
  irvalid : ∀ a : Word 64, s.mem.valid a = decide (a.toNat < c.M)
  xvalid : RegionsValid c x.mem.valid
  capD : c.dBase + 8 * s.dstack.length ≤ c.dEnd
  capR : s.rstack.length + 1 ≤ c.rcap

/-- Full relation: everything in `Rel0`, and the x86 pc is the start of the IR pc's code. -/
def Rel (c : Cfg) (p : Prog 64) (s : State 64) (x : M) : Prop :=
  Rel0 c p s x ∧ x.pc = offs p s.pc

/-- `Rel0` does not look at scratch registers, flags or the pc. -/
theorem Rel0.congr {c : Cfg} {p : Prog 64} {s : State 64} {x x' : M} (h : Rel0 c p s x)
    (hm : x'.mem = x.mem) (h15 : x'.regs Reg.r15 = x.regs Reg.r15) (h14 : x'.regs Reg.r14 = x.regs Reg.r14)
    (h13 : x'.regs Reg.r13 = x.regs Reg.r13) (h12 : x'.regs Reg.r12 = x.regs Reg.r12)
    (hsp : x'.regs Reg.rsp = x.regs Reg.rsp) : Rel0 c p s x' where
  r15 := by rw [h15]; exact h.r15
  r14 := by rw [h14]; exact h.r14
  r13 := by rw [h13]; exact h.r13
  r12 := by rw [h12]; exact h.r12
  rsp := by rw [hsp]; exact h.rsp
  stack := by rw [hm]; exact h.stack
  regs := by rw [hm]; exact h.regs
  mem := by rw [hm]; exact h.mem
  rs := by rw [hm]; exact h.rs
  irvalid := h.irvalid
  xvalid := by rw [hm]; exact h.xvalid
  capD := h.capD
  capR := h.capR

end X86
end WordDialect
