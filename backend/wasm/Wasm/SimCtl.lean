import Wasm.SimMem

/-!
# Wasm.SimCtl

Control-flow instructions: jmp, branch, call, ret, halt.
-/

namespace WordDialect
namespace Wasm

/-- Unconditional jump: set pc directly. -/
theorem sim_jmp (hs : Rel0 c p s x) {code : List WI} {t : Nat}
    (hat : code = [i32c (min t n)])
    (hsz : t < p.length ∨ t = p.length) :
    ∃ x', execL code x x' ∧ x'.pc = t ∧ Rel0 c p { s with pc := t } x' := by
  sorry

/-- Conditional branch: if nonzero, jump to target; else fall through. -/
theorem sim_branch_ok (hs : Rel0 c p s x) {code : List WI} {c_val d : Word 64} {t : Nat}
    (hstack : s.dstack = c_val :: d) (hc : Word.isTrue c_val = true)
    (hat : code = uf L 1 ++ [i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8)
    (hsz : t < p.length ∨ t = p.length) :
    ∃ x', execL code x x' ∧ x'.pc = t ∧ Rel0 c p { s with pc := t, dstack := d } x' := by
  sorry

theorem sim_branch_fall (hs : Rel0 c p s x) {code : List WI} {c_val d : Word 64} {t : Nat} (k : Nat)
    (hstack : s.dstack = c_val :: d) (hc : Word.isTrue c_val = false)
    (hat : code = uf L 1 ++ [i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8) :
    ∃ x', execL code x x' ∧ x'.pc = x.pc + code.length ∧
      Rel0 c p { s with pc := s.pc + 1, dstack := d } x' := by
  sorry

/-- Call: push return address onto return stack, jump to target. -/
theorem sim_call_ok (hs : Rel0 c p s x) {code : List WI} {t : Nat}
    (hat : code = [.globalGet rpG, i32c 8, .i32sub, .globalSet rpG, .globalGet rpG, i64c (k + 1), .i64store 0, i32c (min t n)])
    (hsz : t < p.length ∨ t = p.length) (hrs : s.rstack.length + 1 ≤ c.rcap) :
    ∃ x', execL code x x' ∧ x'.pc = t ∧
      Rel0 c p { s with pc := t, rstack := (s.pc + 1) :: s.rstack } x' := by
  sorry

/-- Return: pop return address, jump. -/
theorem sim_ret_ok (hs : Rel0 c p s x) {code : List WI} {a : Nat} {rs : List Nat}
    (hstack : s.rstack = a :: rs)
    (hat : code = [.globalGet rpG, i32c c.layout.rEnd, .i32eq, .ite [.exitTrap 5],
                   .globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG]) :
    ∃ x', execL code x x' ∧ x'.pc = a ∧ Rel0 c p { s with pc := a, rstack := rs } x' := by
  sorry

theorem sim_ret_trap (hs : Rel0 c p s x) {code : List WI}
    (hat : code = [.globalGet rpG, i32c c.layout.rEnd, .i32eq, .ite [.exitTrap 5],
                   .globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG])
    (hstack : s.rstack = []) :
    execI code x (.trapped .returnUnderflow) := by
  sorry

/-- Halt: call $halt helper which dumps state and exits. -/
theorem sim_halt (hs : Rel0 c p s x) {code : List WI}
    (hat : code = [.exitHalt]) :
    execI code x (.halted x) := by
  sorry

end Wasm
end WordDialect
