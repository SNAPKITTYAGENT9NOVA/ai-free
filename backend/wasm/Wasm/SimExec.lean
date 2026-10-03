import Wasm.SimCtl

/-!
# Wasm.SimExec

One IR step is simulated by the lowered WASM code, for every instruction type.
This is the case analysis over the full instruction set that the whole-program
preservation theorem iterates.
-/

namespace WordDialect
namespace Wasm

/-- One IR instruction is simulated by the lowered WASM code. -/
theorem sim_exec (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) (hf : Fits c s) (i : Instr 64) (hi : p[s.pc]? = some i)
    (hregok : ∀ r, (i = .push r ∨ i = .pop r) → r < c.nregs) :
    ∃ x' o', XExec (lowerInstr L p.length s.pc i) x o' ∧
      (match o' with
       | .next x1 => ∃ s', step s i = .next s' ∧ Rel0 c p s' x1 ∧ x1.pc = offs p (s.pc + 1)
       | .halted x1 => ∃ s', step s i = .halted s' ∧ Rel0 c p s' x1
       | .trapped t => step s i = .trapped t) := by
  sorry

end Wasm
end WordDialect
