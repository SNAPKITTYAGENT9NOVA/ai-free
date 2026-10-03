import Wasm.Frame

/-!
# Wasm.Guard

`execL` over appended lists, the operand-count guard `uf`, and small conveniences used by every
instruction proof.
-/

namespace WordDialect
namespace Wasm

theorem execL_append (a b : List WI) (s : WState) :
    execL (a ++ b) s = (execL a s).bind (execL b) := by
  induction a generalizing s with
  | nil => simp [execL]
  | cons i is ih =>
    simp only [List.cons_append, execL]
    cases stepI i s <;> simp [ih]

theorem Rel0.setStack {c : Cfg} {s : State 64} {w : WState} (h : Rel0 c s w) (x : List Val) :
    Rel0 c s { w with stack := x } :=
  { sp := h.sp, rp := h.rp, stack := h.stack, regs := h.regs, mem := h.mem, rs := h.rs,
    irvalid := h.irvalid, size := h.size, capD := h.capD, capR := h.capR }

/-- `Rel0` only looks at the globals `sp`, `rp` and the memory. -/
theorem Rel0.congr {c : Cfg} {s : State 64} {w w' : WState} (h : Rel0 c s w)
    (hm : w'.mem = w.mem) (hsp : w'.globals spG = w.globals spG)
    (hrp : w'.globals rpG = w.globals rpG) : Rel0 c s w' :=
  { sp := by rw [hsp]; exact h.sp, rp := by rw [hrp]; exact h.rp,
    stack := by rw [hm]; exact h.stack, regs := by rw [hm]; exact h.regs,
    mem := by rw [hm]; exact h.mem, rs := by rw [hm]; exact h.rs, irvalid := h.irvalid,
    size := by rw [hm]; exact h.size, capD := h.capD, capR := h.capR }

section Uf

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

theorem sp_lt (hg : Geom c) (hs : Rel0 c s w) : c.dEnd - 8 * s.dstack.length < 2 ^ 32 := by
  have := hg.dEnd_le; have := hg.msize_lt; omega

theorem spToNat (hg : Geom c) (hs : Rel0 c s w) {u : WState} (hu : u.globals = w.globals) :
    u.globals spG = .i32 (ofN (c.dEnd - 8 * s.dstack.length)) := by
  rw [hu]; exact hs.sp

theorem ult_ofN {a b : Nat} (ha : a < 2 ^ 32) (hb : b < 2 ^ 32) :
    (ofN a).ult (ofN b) = decide (a < b) := by
  simp [BitVec.ult_eq_decide, ofN_toNat ha, ofN_toNat hb]

/-- Enough operands: the guard falls through, changing nothing. -/
theorem uf_pass (hg : Geom c) (hs : Rel0 c s w) {k : Nat} (hk0 : 0 < k) (hk : k ≤ s.dstack.length) :
    Run fs (uf c.layout k) w (.normal w) := by
  have hk0' : k ≠ 0 := by omega
  have hX := sp_lt hg hs
  have hlim : c.dEnd - 8 * k < 2 ^ 32 := by have := hg.dEnd_le; have := hg.msize_lt; omega
  have hexec : execL [.globalGet spG, i32c (c.layout.dEnd - 8 * k), .i32gtu] w =
      some { w with stack := .i32 (bool32 false) :: w.stack } := by
    simp only [execL, stepI, hs.sp, i32c, Cfg.layout, Option.bind_some, bool32]
    rw [show BitVec.ofNat 32 (c.dEnd - 8 * k) = ofN (c.dEnd - 8 * k) from rfl, ult_ofN hlim hX]
    have hnum : ¬ (c.dEnd - 8 * k < c.dEnd - 8 * s.dstack.length) := by omega
    simp [hnum]
  have h3 : Run fs [.globalGet spG, i32c (c.layout.dEnd - 8 * k), .i32gtu] w
      (.normal { w with stack := .i32 (bool32 false) :: w.stack }) :=
    run_of_execL (by simp [WI.isCtl, i32c]) hexec
  simp only [uf, hk0', if_false]
  have h4 := run_ite_false (fs := fs) (thn := [.exitTrap 1])
    (w := { w with stack := .i32 (bool32 false) :: w.stack }) (r := w.stack) (by simp [bool32])
  exact run_append _ h3 h4

theorem uf_trap (hg : Geom c) (hs : Rel0 c s w) {k : Nat} (hk0 : 0 < k) (hk3 : k ≤ 3)
    (hk : s.dstack.length < k) :
    Run fs (uf c.layout k) w (.exit 1) := by
  have hk0' : k ≠ 0 := by omega
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hlim : c.dEnd - 8 * k < 2 ^ 32 := by have := hg.dEnd_le; have := hg.msize_lt; omega
  have hdG := hg.dEnd_ge
  have hexec : execL [.globalGet spG, i32c (c.layout.dEnd - 8 * k), .i32gtu] w =
      some { w with stack := .i32 (bool32 true) :: w.stack } := by
    simp only [execL, stepI, hs.sp, i32c, Cfg.layout, Option.bind_some, bool32]
    rw [show BitVec.ofNat 32 (c.dEnd - 8 * k) = ofN (c.dEnd - 8 * k) from rfl, ult_ofN hlim hX]
    have hnum : c.dEnd - 8 * k < c.dEnd - 8 * s.dstack.length := by omega
    simp [hnum]
  have h3 : Run fs [.globalGet spG, i32c (c.layout.dEnd - 8 * k), .i32gtu] w
      (.normal { w with stack := .i32 (bool32 true) :: w.stack }) :=
    run_of_execL (by simp [WI.isCtl, i32c]) hexec
  simp only [uf, hk0', if_false]
  have h4 := run_ite_exit (fs := fs) (w := { w with stack := .i32 (bool32 true) :: w.stack })
    (r := w.stack) (c := bool32 true) (k := 1) rfl (by simp [bool32])
  have := run_append _ h3 h4
  simpa using this

end Uf

end Wasm
end WordDialect
