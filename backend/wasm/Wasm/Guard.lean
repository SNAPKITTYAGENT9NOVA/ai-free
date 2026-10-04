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

section Ovf

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

theorem ovf_cmp {u : WState} {g base p : Nat} (hp : u.globals g = .i32 (ofN p)) (hP : p < 2 ^ 32)
    (hb : base + 8 < 2 ^ 32) :
    execL [i32c (base + 8), .globalGet g, .i32gtu] u =
      some { u with stack := .i32 (bool32 (decide (p < base + 8))) :: u.stack } := by
  have hu := ult_ofN hP hb
  simp only [ofN] at hp hu
  simp [execL, stepI, i32c, hp, hu]

theorem ovf_pass {u : WState} {g base p : Nat} (hp : u.globals g = .i32 (ofN p)) (hP : p < 2 ^ 32)
    (hb : base + 8 < 2 ^ 32) (h : base + 8 ≤ p) : Run fs (ovf g base) u (.normal u) := by
  have h1 := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c]) (ovf_cmp hp hP hb)
  have hf : decide (p < base + 8) = false := by simp; omega
  rw [hf] at h1
  have h2 := run_ite_false (fs := fs) (thn := [.exitTrap 6])
    (w := { u with stack := .i32 (bool32 false) :: u.stack }) (r := u.stack) (by simp [bool32])
  have := run_append _ h1 h2
  simpa [ovf] using this

theorem ovf_trap {u : WState} {g base p : Nat} (hp : u.globals g = .i32 (ofN p)) (hP : p < 2 ^ 32)
    (hb : base + 8 < 2 ^ 32) (h : p < base + 8) : Run fs (ovf g base) u (.exit 6) := by
  have h1 := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c]) (ovf_cmp hp hP hb)
  have ht : decide (p < base + 8) = true := by simp; omega
  rw [ht] at h1
  have h2 := run_ite_exit (fs := fs) (w := { u with stack := .i32 (bool32 true) :: u.stack })
    (r := u.stack) (c := bool32 true) (k := 6) rfl (by simp [bool32])
  have := run_append _ h1 h2
  simpa [ovf] using this

/-- Data stack has room for one more word: the guard falls through. -/
theorem ovfD_pass (hg : Geom c) (hs : Rel0 c s w)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (ovf spG c.layout.dBase) w (.normal w) := by
  have := hg.dEnd_le; have := hg.msize_lt; have := hg.dBase_8
  exact ovf_pass hs.sp (sp_lt hg hs) (by simp [Cfg.layout]; omega) (by simp [Cfg.layout]; omega)

/-- Data stack full: the guard exits 6. -/
theorem ovfD_trap (hg : Geom c) (hs : Rel0 c s w)
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (ovf spG c.layout.dBase) w (.exit 6) := by
  have := hg.dEnd_le; have := hg.msize_lt; have := hg.dBase_8; have := hs.capD
  exact ovf_trap hs.sp (sp_lt hg hs) (by simp [Cfg.layout]; omega) (by simp [Cfg.layout]; omega)

theorem rp_lt (hg : Geom c) (hs : Rel0 c s w) : c.rEnd - 8 * s.rstack.length < 2 ^ 32 := by
  have := hg.rEnd_le; have := hg.msize_lt; omega

/-- Return stack has room for one more entry: the guard falls through. -/
theorem ovfR_pass (hg : Geom c) (hs : Rel0 c s w)
    (hfit : c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd) :
    Run fs (ovf rpG c.layout.rBase) w (.normal w) := by
  have := hg.rEnd_le; have := hg.msize_lt; have := hg.rBase_8
  exact ovf_pass hs.rp (rp_lt hg hs) (by simp [Cfg.layout]; omega) (by simp [Cfg.layout]; omega)

/-- Return stack full: the guard exits 6. -/
theorem ovfR_trap (hg : Geom c) (hs : Rel0 c s w)
    (h : ¬ c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd) :
    Run fs (ovf rpG c.layout.rBase) w (.exit 6) := by
  have := hg.rEnd_le; have := hg.msize_lt; have := hg.rBase_8; have := hs.capR
  exact ovf_trap hs.rp (rp_lt hg hs) (by simp [Cfg.layout]; omega) (by simp [Cfg.layout]; omega)

end Ovf

end Wasm
end WordDialect
