import Wolfram.MatrixDot

/-!
# Wolfram.MatrixExample

The preconditions of `dotProgram_correct` are satisfiable, and the theorem delivers the right
numbers on a concrete product:

    [[1,2],[3,4]] . [[5,6],[7,8]] = [[19,22],[43,50]]

`A` is stored at address 0, `B` at 4, and `C` is written at 8 (64-bit words).
-/

namespace WordDialect
namespace Wolfram

def tbl (q : Nat) : Int := [1, 2, 3, 4, 5, 6, 7, 8].getD q 0

def exMem : Memory 64 :=
  { cell := fun a => BitVec.ofInt 64 (tbl a.toNat), valid := fun a => decide (a.toNat < 12) }

def exA : Nat → Nat → Int := fun i j => tbl (i * 2 + j)
def exB : Nat → Nat → Int := fun i j => tbl (4 + i * 2 + j)

theorem ex_geom : DotGeom 64 2 2 2 0 4 8 where
  hn := by decide
  hm := by decide
  hk := by decide
  hp := by decide
  hA := by decide
  hB := by decide
  hC := by decide
  dA := Or.inr (by decide)
  dB := Or.inr (by decide)

theorem ex_hA : MatAt exMem 0 2 2 exA := by
  intro i j hi hj
  rcases (by omega : i = 0 ∨ i = 1) with rfl | rfl <;>
    rcases (by omega : j = 0 ∨ j = 1) with rfl | rfl <;> decide

theorem ex_hB : MatAt exMem 4 2 2 exB := by
  intro i j hi hj
  rcases (by omega : i = 0 ∨ i = 1) with rfl | rfl <;>
    rcases (by omega : j = 0 ∨ j = 1) with rfl | rfl <;> decide

theorem ex_hvC : ∀ q, q < 2 * 2 → exMem.valid (BitVec.ofNat 64 (8 + q)) = true := by
  intro q hq
  rcases (by omega : q = 0 ∨ q = 1 ∨ q = 2 ∨ q = 3) with rfl | rfl | rfl | rfl <;> decide

/-- Running the lowered program leaves `C[1][1] = 50` in memory (`3·6 + 4·8`). -/
theorem ex_entry_11 :
    ∃ s', WordDialect.Exec ((dotFrag 2 2 2 0 4 8 : IR.Frag 64).emit 0 ++ [.halt])
        (State.init exMem) (.halted s') ∧
      s'.mem.read? (BitVec.ofNat 64 (8 + 1 * 2 + 1)) = some (BitVec.ofInt 64 50) := by
  obtain ⟨s', hex, _, hmat, _, _⟩ := dotProgram_correct ex_geom ex_hA ex_hB ex_hvC
  refine ⟨s', hex, ?_⟩
  have := hmat 1 1 (by decide) (by decide)
  rw [this]
  simp [dotSum, exA, exB, tbl]

end Wolfram
end WordDialect
