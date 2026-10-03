import Wasm.Guard

/-!
# Wasm.SimAlu

Simulation of the binary operations: the generic `sim_binop` (operand guard, two loads, the
operation, a store into the second slot, pop one) and its instantiations.
-/

namespace WordDialect
namespace Wasm

section Sim

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

theorem run_finish {u : WState} (nxt : Nat) :
    Run fs [i32c nxt] u (.normal { u with stack := .i32 (ofN nxt) :: u.stack }) :=
  run_of_execL (by simp [WI.isCtl, i32c]) (by simp [execL, stepI, i32c, ofN])

theorem ctl_binBody {op : List WI} (hctl : ∀ i ∈ op, i.isCtl = false) :
    ∀ i ∈ binBody op, i.isCtl = false := by
  intro i hi
  simp only [binBody, ldS, spAdd, List.mem_append, List.mem_cons, List.mem_nil_iff, or_false] at hi
  rcases hi with ((((hi | hi | hi) | hi | hi) | hi) | hi) | hi | hi | hi | hi
  all_goals first | exact hctl i ‹_› | (subst_vars; rfl)

/-- Core of every instruction shaped `uf 2; <body>; next`: the body (given as an execution fact)
overwrites the second slot with `y` and pops one. -/
theorem sim_bin_core (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W} {pre : List WI}
    (hpre : Run fs pre w (.normal w))
    (hd : s.dstack = b :: a :: d) {B : List WI} {y : W} (hctlB : ∀ i ∈ B, i.isCtl = false)
    (hB : ∀ m', w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8) y = some m' →
      execL B w = some { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) })
    (nxt : Nat) :
    ∃ w', Run fs (pre ++ (B ++ [i32c nxt])) w (.normal w') ∧
      Rel0 c { s with dstack := y :: d } w' ∧ w'.stack = [.i32 (ofN nxt)] := by
  have hlen : s.dstack.length = d.length + 2 := by simp [hd]
  have hk : 2 ≤ s.dstack.length := by omega
  have hcap := hs.capD
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8) y = some m' :=
    write64_some (by rw [hs.size]; have := hg.dEnd_le; omega)
  have hbR := run_of_execL (fs := fs) hctlB (hB m' hm')
  have hrel1 := wr_stack hg hs (j := 1) (by omega) (v := y) (m' := m') (by simpa using hm')
  have hrel2 := adj_sp hg hrel1 (n := 1) (by simp [hd])
  have e3 : ({ { s with dstack := s.dstack.set 1 y } with dstack := ({ s with dstack := s.dstack.set 1 y } : State 64).dstack.drop 1 } : State 64) = { s with dstack := y :: d } := by
    simp [hd]
  rw [e3] at hrel2
  have e2 : c.dEnd - 8 * s.dstack.length + 8 = c.dEnd - 8 * (s.dstack.length - 1) := by omega
  rw [e2] at hbR
  refine ⟨_, run_append _ hpre (run_append _ hbR (run_finish nxt)), ?_, ?_⟩
  · refine Rel0.congr (hrel2.setStack []) rfl ?_ ?_
    · simp [setG, spG, List.length_set]
    · simp [setG, spG, rpG]
  · simp [hst]

theorem sim_binop (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W} {pre : List WI}
    (hpre : Run fs pre w (.normal w))
    (hd : s.dstack = b :: a :: d) {op : List WI} (hctl : ∀ i ∈ op, i.isCtl = false) {y : W}
    (hop : ∀ (u : WState) (r : List Val), u.stack = .i64 b :: .i64 a :: r →
      execL op u = some { u with stack := .i64 y :: r }) (nxt : Nat) :
    ∃ w', Run fs (pre ++ (binBody op ++ [i32c nxt])) w (.normal w') ∧
      Rel0 c { s with dstack := y :: d } w' ∧ w'.stack = [.i32 (ofN nxt)] := by
  have hlen : s.dstack.length = d.length + 2 := by simp [hd]
  have hX := sp_lt hg hs
  have hr1 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8) = some a := by
    have := hs.stack 1 a (by simp [hd]); simpa using this
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some b := by
    have := hs.stack 0 b (by simp [hd]); simpa using this
  refine sim_bin_core hg hs hst hpre hd (ctl_binBody hctl) ?_ nxt
  intro m' hm'
  have hsp8 : ofN (c.dEnd - 8 * s.dstack.length) + ofN 8 = ofN (c.dEnd - 8 * s.dstack.length + 8) :=
    ofN_add _ _
  have hpre : execL ([.globalGet spG] ++ ldS 8 ++ ldS 0) w = some { w with stack := .i64 b :: .i64 a :: .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } := by
    simp [ldS, execL, stepI, hs.sp, ofN_toNat hX, hr0, hr1]
  have hop' := hop { w with stack := .i64 b :: .i64 a :: .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } (.i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack) rfl
  have hstore : execL [.i64store 8] { w with stack := .i64 y :: .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } = some { w with mem := m' } := by
    simp [execL, stepI, ofN_toNat hX, hm']
  have hadd : execL (spAdd 8) { w with mem := m' } = some { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) } := by
    have hsp8' : ofN (c.dEnd - 8 * s.dstack.length) + 8#32 = ofN (c.dEnd - 8 * s.dstack.length + 8) := hsp8
    simp [spAdd, execL, stepI, bin32, hs.sp, i32c]
    unfold setG
    rw [hsp8']
  simp only [binBody, execL_append, hpre, Option.bind_some, hop', hstore, hadd]

theorem uf2_pass (hg : Geom c) (hs : Rel0 c s w) {b a : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    Run fs (uf c.layout 2) w (.normal w) :=
  uf_pass hg hs (k := 2) (by omega) (by simp [hd])

/-- Conclusion shared by every instruction simulation. -/
abbrev Sim1 (c : Cfg) (fs : Funcs) (body : List WI) (s' : State 64) (w : WState) (nxt : Nat) : Prop :=
  ∃ w', Run fs body w (.normal w') ∧ Rel0 c s' w' ∧ w'.stack = [.i32 (ofN nxt)]

macro "hop_tac" : tactic =>
  `(tactic| (intro u r h; simp [execL, stepI, bin64, cmp64, bool32, Word.rotl, Word.rotr, Word.ofBool, WordDialect.Cond.eval, cmpOp, h]))

theorem sim_add (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .add) { s with dstack := (a + b) :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64add]) (by simp [WI.isCtl]) (y := a + b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem sim_sub (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .sub) { s with dstack := (a - b) :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64sub]) (by simp [WI.isCtl]) (y := a - b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem sim_mul (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .mul) { s with dstack := (a * b) :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64mul]) (by simp [WI.isCtl]) (y := a * b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem sim_and (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .and) { s with dstack := (a &&& b) :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64and]) (by simp [WI.isCtl]) (y := a &&& b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem sim_or (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .or) { s with dstack := (a ||| b) :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64or]) (by simp [WI.isCtl]) (y := a ||| b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem sim_xor (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .xor) { s with dstack := (a ^^^ b) :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64xor]) (by simp [WI.isCtl]) (y := a ^^^ b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem sim_rotl (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .rotl) { s with dstack := Word.rotl a b :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64rotl]) (by simp [WI.isCtl]) (y := Word.rotl a b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem sim_rotr (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .rotr) { s with dstack := Word.rotr a b :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [.i64rotr]) (by simp [WI.isCtl]) (y := Word.rotr a b) (by hop_tac) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

theorem ext_bool (v : Bool) : BitVec.setWidth 64 (bool32 v) = Word.ofBool v := by
  cases v <;> simp [bool32, Word.ofBool]

theorem sim_cmp (n k : Nat) (cd : WordDialect.Cond) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = [])
    {a b : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k (.cmp cd)) { s with dstack := Word.ofBool (cd.eval a b) :: d } w (k + 1) := by
  have := sim_binop (fs := fs) hg hs hst (uf2_pass hg hs hd) hd (op := [cmpOp cd, .i64extu]) (by cases cd <;> simp [cmpOp, WI.isCtl])
    (y := Word.ofBool (cd.eval a b)) (by intro u r h; cases cd <;> simp [execL, stepI, bin64, cmp64, ext_bool, WordDialect.Cond.eval, cmpOp, h]) (k + 1)
  simpa [lowerInstr, binOp, List.append_assoc] using this

end Sim

end Wasm
end WordDialect
