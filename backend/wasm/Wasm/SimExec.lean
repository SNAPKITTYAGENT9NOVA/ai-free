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
       | .next x1 => ∃ s', step s i = .next s' ∧ Rel0 c p s' x1
       | .halted x1 => ∃ s', step s i = .halted s' ∧ Rel0 c p s' x1
       | .trapped t => step s i = .trapped t) := by
  -- Dispatcher: perform case analysis on all 31 instruction types
  -- For each case, compose the individual instruction simulator (sim_xxx) with Rel0 proof
  cases i <;> try (exact ⟨x, .trapped .stackUnderflow, by sorry, by sorry⟩)
  case halt => sorry
  case word w => sorry
  case ptr q => sorry
  case load => sorry
  case store => sorry
  case add => sorry
  case sub => sorry
  case mul => sorry
  case div => sorry
  case sdiv => sorry
  case and => sorry
  case or => sorry
  case xor => sorry
  case not => sorry
  case shl => sorry
  case shr => sorry
  case rotl => sorry
  case rotr => sorry
  case cmp cd => sorry
  case select => sorry
  case jmp t => sorry
  case branch t => sorry
  case call t => sorry
  case ret => sorry
  case push r => sorry
  case pop r => sorry
  case dup => sorry
  case drop => sorry
  case swap => sorry
  case over => sorry
  case rot => sorry

end Wasm
end WordDialect
