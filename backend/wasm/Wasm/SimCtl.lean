import Wasm.SimMem

/-!
# Wasm.SimCtl

Control-flow instructions: jmp, branch, call, ret, halt.
-/

namespace WordDialect
namespace Wasm

section Sim

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs} {L : Layout} {p : Prog 64}

/-- Unconditional jump: set pc directly. -/
theorem sim_jmp {code : List WI} {t : Nat} {n : Nat}
    (hat : code = [i32c (min t n)]) :
    ∃ w', execL code w w' ∧ w'.stack = .i32 (ofN (min t n)) :: w.stack := by
  refine ⟨{ w with stack := .i32 (ofN (min t n)) :: w.stack }, by simp [hat, execL, stepI, i32c], rfl⟩

/-- Conditional branch: if nonzero, jump to target; else fall through. -/
theorem sim_branch_ok {code : List WI} {c_val d : Word 64} {t k n : Nat}
    (hstack : s.dstack = c_val :: d) (hc : Word.isTrue c_val = true)
    (hat : code = uf L 1 ++ [i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8) :
    ∃ w', execL code w w' ∧ w'.stack = .i32 (ofN (min t n)) :: w.stack := by
  have hc_ne : c_val ≠ 0#64 := Word.isTrue_iff.mp hc
  refine ⟨{ w with stack := .i32 (ofN (min t n)) :: w.stack }, by
    simp only [hat, execL_append, execL, stepI, i32c, ldS, spAdd, bin32]
    simp [hc_ne, bool32]
  , rfl⟩

theorem sim_branch_fall {code : List WI} {c_val d : Word 64} {t k n : Nat}
    (hstack : s.dstack = c_val :: d) (hc : Word.isTrue c_val = false)
    (hat : code = uf L 1 ++ [i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8) :
    ∃ w', execL code w w' ∧ w'.stack = .i32 (ofN (k + 1)) :: w.stack := by
  have hc_eq : c_val = 0#64 := Word.isTrue_iff.not.mp hc
  refine ⟨{ w with stack := .i32 (ofN (k + 1)) :: w.stack }, by
    simp only [hat, execL_append, execL, stepI, i32c, ldS, spAdd, bin32]
    simp [hc_eq, bool32]
  , rfl⟩

/-- Call: push return address onto return stack, jump to target. -/
theorem sim_call_ok {code : List WI} {t k n : Nat}
    (hat : code = [.globalGet rpG, i32c 8, .i32sub, .globalSet rpG, .globalGet rpG, i64c (k + 1), .i64store 0, i32c (min t n)])
    (hrc : s.rstack.length + 1 ≤ c.rcap) :
    ∃ w', execL code w w' ∧ w'.stack = .i32 (ofN (min t n)) :: w.stack := by
  refine ⟨{ w with stack := .i32 (ofN (min t n)) :: w.stack }, by
    simp only [hat, execL, stepI, i32c, i64c, setG, rpG, bin32]
  , rfl⟩

/-- Return: pop return address, jump. -/
theorem sim_ret_ok {code : List WI} {a : Nat} {rs : List Nat}
    (hstack : s.rstack = a :: rs)
    (hat : code = [.globalGet rpG, i32c c.layout.rEnd, .i32eq, .ite [.exitTrap 5],
                   .globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG]) :
    ∃ w', execL code w w' ∧ w'.stack = .i32 (ofN a) :: w.stack := by
  refine ⟨{ w with stack := .i32 (ofN a) :: w.stack }, by
    simp only [hat, execL, stepI, i32c, Cfg.layout, setG, rpG, bin32, bool32]
  , rfl⟩

theorem sim_ret_trap {code : List WI}
    (hat : code = [.globalGet rpG, i32c c.layout.rEnd, .i32eq, .ite [.exitTrap 5],
                   .globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG])
    (hstack : s.rstack = []) :
    execL code w = none := by
  simp only [hat, execL, stepI, i32c, Cfg.layout, bool32]

/-- Halt: call $halt helper which dumps state and exits. -/
theorem sim_halt {code : List WI}
    (hat : code = [.exitHalt]) :
    execL code w = some w := by
  simp [hat, execL, stepI]

end Sim

end Wasm
end WordDialect
