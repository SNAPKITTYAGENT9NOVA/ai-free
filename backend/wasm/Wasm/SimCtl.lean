import Wasm.SimMem

/-!
# Wasm.SimCtl

Control-flow instructions: jmp, branch, call, ret, halt.
-/

namespace WordDialect
namespace Wasm

/-- Unconditional jump: set pc directly. -/
theorem sim_jmp (hc : c < p.length ∨ c = p.length) {code : List WI} {t : Nat}
    (hat : code = [i32c (min t n)]) :
    ∃ x', execL code x x' ∧ x'.pc = ofN (min t n) := by
  sorry

/-- Conditional branch: if nonzero, jump to target; else fall through. -/
theorem sim_branch_ok {code : List WI} {c_val d : Word 64} {t : Nat}
    (hstack : s.dstack = c_val :: d) (hc : Word.isTrue c_val = true)
    (hat : code = uf L 1 ++ [i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8) :
    ∃ x', execL code x x' ∧ x'.pc = ofN (min t n) := by
  sorry

theorem sim_branch_fall {code : List WI} {c_val d : Word 64} {t : Nat} (k : Nat)
    (hstack : s.dstack = c_val :: d) (hc : Word.isTrue c_val = false)
    (hat : code = uf L 1 ++ [i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8) :
    ∃ x', execL code x x' ∧ x'.pc = ofN (k + 1) := by
  sorry

/-- Call: push return address onto return stack, jump to target. -/
theorem sim_call_ok {code : List WI} {t : Nat}
    (hat : code = [.globalGet rpG, i32c 8, .i32sub, .globalSet rpG, .globalGet rpG, i64c (k + 1), .i64store 0, i32c (min t n)])
    (hrc : s.rstack.length + 1 ≤ c.rcap) :
    ∃ x', execL code x x' ∧ x'.pc = ofN (min t n) := by
  sorry

/-- Return: pop return address, jump. -/
theorem sim_ret_ok {code : List WI} {a : Nat} {rs : List Nat}
    (hstack : s.rstack = a :: rs)
    (hat : code = [.globalGet rpG, i32c c.layout.rEnd, .i32eq, .ite [.exitTrap 5],
                   .globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG]) :
    ∃ x', execL code x x' ∧ x'.pc = ofN a := by
  sorry

theorem sim_ret_trap {code : List WI}
    (hat : code = [.globalGet rpG, i32c c.layout.rEnd, .i32eq, .ite [.exitTrap 5],
                   .globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG])
    (hstack : s.rstack = []) :
    execI code x (.trapped .returnUnderflow) := by
  sorry

/-- Halt: call $halt helper which dumps state and exits. -/
theorem sim_halt {code : List WI}
    (hat : code = [.exitHalt]) :
    execI code x (.halted x) := by
  sorry

end Wasm
end WordDialect
