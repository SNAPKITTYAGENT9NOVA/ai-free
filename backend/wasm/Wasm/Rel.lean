import WordDialect
import Wasm.Lower
import Wasm.Mem

/-!
# Wasm.Rel

The relation between an IR state and a WebAssembly machine state.

Linear-memory regions (byte intervals, all within the memory and within the 32-bit address space,
pairwise disjoint):
* data stack   `[dBase, dEnd)`, with `k` words on it the top is at `dEnd - 8k`;
* register file `[rf, rf + 8 nregs)`;
* IR memory     `[mb, mb + 8 M)`, word `a` at `mb + 8a`;
* return stack  `[rBase, rEnd)`, with `k` entries the top is at `rEnd - 8k`; an entry is the IR index
  of the return instruction.
Everything is stated at natural-number byte addresses and `read64` on the byte memory.
-/

namespace WordDialect
namespace Wasm

structure Cfg where
  dEnd : Nat
  dBase : Nat
  rEnd : Nat
  rBase : Nat
  rf : Nat
  nregs : Nat
  mb : Nat
  M : Nat
  msize : Nat

def Cfg.layout (c : Cfg) : Layout :=
  { dEnd := c.dEnd, rEnd := c.rEnd, rf := c.rf, mb := c.mb, M := c.M, dBase := c.dBase,
    rBase := c.rBase }

structure Geom (c : Cfg) : Prop where
  msize_lt : c.msize < 2 ^ 32
  dEnd_le : c.dEnd ≤ c.msize
  rEnd_le : c.rEnd ≤ c.msize
  rf_le : c.rf + 8 * c.nregs ≤ c.msize
  mb_le : c.mb + 8 * c.M ≤ c.msize
  dBase_le : c.dBase ≤ c.dEnd
  rBase_le : c.rBase ≤ c.rEnd
  dBase_8 : c.dBase + 8 ≤ c.dEnd
  rBase_8 : c.rBase + 8 ≤ c.rEnd
  dEnd_ge : 24 ≤ c.dEnd
  dS_F : c.dEnd ≤ c.rf ∨ c.rf + 8 * c.nregs ≤ c.dBase
  dS_M : c.dEnd ≤ c.mb ∨ c.mb + 8 * c.M ≤ c.dBase
  dS_K : c.dEnd ≤ c.rBase ∨ c.rEnd ≤ c.dBase
  dF_M : c.rf + 8 * c.nregs ≤ c.mb ∨ c.mb + 8 * c.M ≤ c.rf
  dF_K : c.rf + 8 * c.nregs ≤ c.rBase ∨ c.rEnd ≤ c.rf
  dM_K : c.mb + 8 * c.M ≤ c.rBase ∨ c.rEnd ≤ c.mb

/-- A natural number as an `i32`. -/
def ofN (a : Nat) : W32 := BitVec.ofNat 32 a

theorem ofN_toNat {a : Nat} (h : a < 2 ^ 32) : (ofN a).toNat = a := by
  simp [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt h]

theorem ofN_inj {a b : Nat} (ha : a < 2 ^ 32) (hb : b < 2 ^ 32) (h : ofN a = ofN b) : a = b := by
  have := congrArg BitVec.toNat h
  simpa [ofN, BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] using this

theorem ofN_add (a b : Nat) : ofN a + ofN b = ofN (a + b) := (BitVec.ofNat_add a b).symm

theorem ofN_sub {a b : Nat} (h : b ≤ a) : ofN a - ofN b = ofN (a - b) := by
  apply BitVec.eq_of_toNat_eq
  simp only [ofN, BitVec.toNat_sub, BitVec.toNat_ofNat]
  have h1 : (a - b) % 2 ^ 32 = ((2 ^ 32 - b % 2 ^ 32) + a % 2 ^ 32) % 2 ^ 32 := by omega
  exact h1.symm

def StackRel (c : Cfg) (m : WMem) (d : List W) : Prop :=
  ∀ i v, d[i]? = some v → m.read64 (c.dEnd - 8 * d.length + 8 * i) = some v

def RegRel (c : Cfg) (m : WMem) (regs : Nat → W) : Prop :=
  ∀ r, r < c.nregs → m.read64 (c.rf + 8 * r) = some (regs r)

def MemRel (c : Cfg) (m : WMem) (im : WordDialect.Memory 64) : Prop :=
  ∀ a, a < c.M → m.read64 (c.mb + 8 * a) = some (im.cell (BitVec.ofNat 64 a))

def RsRel (c : Cfg) (m : WMem) (rs : List Nat) : Prop :=
  ∀ i a, rs[i]? = some a → m.read64 (c.rEnd - 8 * rs.length + 8 * i) = some (BitVec.ofNat 64 a)

/-- The relation, except for the operand stack and the `pc` global (those are added at the top of
the dispatch loop by `RelD` in `Wasm.Correct`). -/
structure Rel0 (c : Cfg) (s : State 64) (w : WState) : Prop where
  sp : w.globals spG = .i32 (ofN (c.dEnd - 8 * s.dstack.length))
  rp : w.globals rpG = .i32 (ofN (c.rEnd - 8 * s.rstack.length))
  stack : StackRel c w.mem s.dstack
  regs : RegRel c w.mem s.regs
  mem : MemRel c w.mem s.mem
  rs : RsRel c w.mem s.rstack
  irvalid : ∀ a : Word 64, s.mem.valid a = decide (a.toNat < c.M)
  size : w.mem.size = c.msize
  capD : c.dBase + 8 * s.dstack.length ≤ c.dEnd
  capR : c.rBase + 8 * s.rstack.length ≤ c.rEnd

end Wasm
end WordDialect
