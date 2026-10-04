import Wasm.SimCtl

/-!
# Wasm.SimExec

One IR step is simulated by the lowered WASM code, for every instruction type.
This is the case analysis over the full instruction set that the whole-program
preservation theorem iterates.
-/

namespace WordDialect
namespace Wasm

/-- One IR instruction is simulated by the lowered WASM code.
Dispatcher theorem: perform case analysis over all 31 IR instruction types.
For each type, compose the individual instruction simulator with Rel0 and step semantics. -/
theorem sim_exec (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) (hf : Fits c s) (i : Instr 64) (hi : p[s.pc]? = some i)
    (hregok : ∀ r, (i = .push r ∨ i = .pop r) → r < c.nregs) :
    ∃ x' o', XExec (lowerInstr L p.length s.pc i) x o' ∧
      (match o' with
       | .next x1 => ∃ s', step s i = .next s' ∧ Rel0 c p s' x1
       | .halted x1 => ∃ s', step s i = .halted s' ∧ Rel0 c p s' x1
       | .trapped t => step s i = .trapped t) := by
  -- Case analysis on instruction type
  cases i with
  | word w =>
    -- word w: push constant onto stack
    sorry
  | ptr q =>
    -- ptr q: push pointer constant onto stack
    sorry
  | load =>
    -- load: read from IR memory
    sorry
  | store =>
    -- store: write to IR memory
    sorry
  | add =>
    -- add: pop two values, push sum
    sorry
  | sub =>
    -- sub: pop two values, push difference
    sorry
  | mul =>
    -- mul: pop two values, push product
    sorry
  | div =>
    -- div: unsigned division (traps on divide by zero)
    sorry
  | sdiv =>
    -- sdiv: signed division (traps on divide by zero)
    sorry
  | and =>
    -- and: bitwise AND
    sorry
  | or =>
    -- or: bitwise OR
    sorry
  | xor =>
    -- xor: bitwise XOR
    sorry
  | not =>
    -- not: bitwise NOT
    sorry
  | shl =>
    -- shl: shift left
    sorry
  | shr =>
    -- shr: logical shift right
    sorry
  | rotl =>
    -- rotl: rotate left
    sorry
  | rotr =>
    -- rotr: rotate right
    sorry
  | cmp cd =>
    -- cmp: comparison operation
    sorry
  | select =>
    -- select: conditional selection
    sorry
  | jmp t =>
    -- jmp: unconditional jump
    sorry
  | branch t =>
    -- branch: conditional branch
    sorry
  | call t =>
    -- call: function call (push return address onto return stack)
    sorry
  | ret =>
    -- ret: return from function (pop return address)
    sorry
  | push r =>
    -- push r: push virtual register onto data stack
    sorry
  | pop r =>
    -- pop r: pop data stack into virtual register
    sorry
  | dup =>
    -- dup: duplicate top of stack
    sorry
  | drop =>
    -- drop: remove top of stack
    sorry
  | swap =>
    -- swap: exchange top two stack elements
    sorry
  | over =>
    -- over: copy second element to top
    sorry
  | rot =>
    -- rot: rotate top three elements
    sorry
  | halt =>
    -- halt: terminate execution with final state
    sorry

end Wasm
end WordDialect
