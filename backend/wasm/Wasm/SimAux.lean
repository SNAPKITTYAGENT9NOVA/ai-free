import Wasm.SimCtl

/-!
# Wasm.SimAux

The auxiliary data stack: `tor` (operand guard, aux overflow guard, move `[sp]` to the new aux top),
`fromr` and `rfetch` (empty-aux check exiting 5, data overflow guard, push `[ap]`; `fromr` also pops
the aux stack). Every outcome is covered: next, `returnUnderflow` (exit 5), and overflow (exit 6).
`tor` on an empty data stack is the generic operand-guard case of `sim_step`.
-/

namespace WordDialect
namespace Wasm

section Sim

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

theorem ap_lt (hg : Geom c) (hs : Rel0 c s w) : c.aEnd - 8 * s.astack.length < 2 ^ 32 := by
  have := hg.aEnd_le; have := hg.msize_lt; omega

/-- Auxiliary stack has room for one more word: the guard falls through. -/
theorem ovfA_pass (hg : Geom c) (hs : Rel0 c s w)
    (hfit : c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) :
    Run fs (ovf apG c.layout.aBase) w (.normal w) := by
  have := hg.aEnd_le; have := hg.msize_lt; have := hg.aBase_8
  exact ovf_pass hs.ap (ap_lt hg hs) (by simp [Cfg.layout]; omega) (by simp [Cfg.layout]; omega)

/-- Auxiliary stack full: the guard exits 6. -/
theorem ovfA_trap (hg : Geom c) (hs : Rel0 c s w)
    (h : ¬ c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) :
    Run fs (ovf apG c.layout.aBase) w (.exit 6) := by
  have := hg.aEnd_le; have := hg.msize_lt; have := hg.aBase_8; have := hs.capA
  exact ovf_trap hs.ap (ap_lt hg hs) (by simp [Cfg.layout]; omega) (by simp [Cfg.layout]; omega)

/-- The empty-auxiliary-stack check of `fromr`/`rfetch`. -/
def auxE (L : Layout) : List WI := [.globalGet apG, i32c L.aEnd, .i32eq, .ite [.exitTrap 5]]

/-- Non-empty auxiliary stack: the check falls through. -/
theorem auxE_pass (hg : Geom c) (hs : Rel0 c s w) {a : W} {as : List W} (ha : s.astack = a :: as) :
    Run fs (auxE c.layout) w (.normal w) := by
  have hcap := hs.capA
  rw [ha] at hcap
  simp only [List.length_cons] at hcap
  have hX : c.aEnd - 8 * (as.length + 1) < 2 ^ 32 := by have := ap_lt hg hs; rw [ha] at this; simpa using this
  have hE : c.aEnd < 2 ^ 32 := by have := hg.aEnd_le; have := hg.msize_lt; omega
  have hap : w.globals apG = .i32 (ofN (c.aEnd - 8 * (as.length + 1))) := by
    have := hs.ap; rw [ha] at this; simpa using this
  have hne : ofN (c.aEnd - 8 * (as.length + 1)) ≠ ofN c.aEnd := by
    intro h; have := ofN_inj hX hE h; omega
  have e1 : execL [.globalGet apG, i32c c.layout.aEnd, .i32eq] w =
      some { w with stack := .i32 0#32 :: w.stack } := by
    simp [execL, stepI, hap, i32c, Cfg.layout, bool32]
    exact hne
  have r1 := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c]) e1
  have r2 := run_ite_false (fs := fs) (thn := [.exitTrap 5])
    (w := { w with stack := .i32 0#32 :: w.stack }) (r := w.stack) rfl
  have := run_append _ r1 r2
  simpa [auxE] using this

/-- Empty auxiliary stack: the check exits 5 (`returnUnderflow`). -/
theorem auxE_trap (hs : Rel0 c s w) (ha : s.astack = []) :
    Run fs (auxE c.layout) w (.exit 5) := by
  have hap : w.globals apG = .i32 (ofN c.aEnd) := by
    have := hs.ap; rw [ha] at this; simpa using this
  have e1 : execL [.globalGet apG, i32c c.layout.aEnd, .i32eq] w =
      some { w with stack := .i32 1#32 :: w.stack } := by
    simp [execL, stepI, hap, i32c, Cfg.layout, bool32, ofN]
  have r1 := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c]) e1
  have r2 := run_ite_exit (fs := fs) (w := { w with stack := .i32 1#32 :: w.stack }) (r := w.stack)
    (c := 1#32) (k := 5) rfl (by decide)
  have := run_append _ r1 r2
  simpa [auxE] using this

theorem tor_split (L : Layout) (n k : Nat) : lowerInstr L n k .tor =
    uf L 1 ++ ovf apG L.aBase ++
      (([.globalGet apG, i32c 8, .i32sub, .globalSet apG, .globalGet apG] ++ ldS 0 ++ [.i64store 0] ++
        spAdd 8) ++ [i32c (k + 1)]) := by
  simp [lowerInstr, List.append_assoc]

theorem sim_tor (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : W} {d : List W}
    (hd : s.dstack = a :: d) (hfit : c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) :
    Sim1 c fs (lowerInstr c.layout n k .tor) { s with dstack := d, astack := a :: s.astack } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 1 := by simp [hd]
  have hX := sp_lt hg hs
  have hA := ap_lt hg hs
  have hcapA := hs.capA
  have hcapD := hs.capD
  have haE := hg.aEnd_le
  have hsz := hg.msize_lt
  have hlt : c.aEnd - 8 * (s.astack.length + 1) < 2 ^ 32 := by omega
  have hsub : ofN (c.aEnd - 8 * s.astack.length) - 8#32 = ofN (c.aEnd - 8 * (s.astack.length + 1)) := by
    have : (8#32 : W32) = ofN 8 := rfl
    rw [this, ofN_sub (by omega)]
    congr 1
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.aEnd - 8 * (s.astack.length + 1)) a = some m' :=
    write64_some (by rw [hs.size]; omega)
  have hsp8 : ofN (c.dEnd - 8 * s.dstack.length) + 8#32 = ofN (c.dEnd - 8 * s.dstack.length + 8) :=
    ofN_add _ _
  have hspa : w.globals 1 = .i32 (ofN (c.dEnd - 8 * s.dstack.length)) := hs.sp
  have hapa : w.globals 3 = .i32 (ofN (c.aEnd - 8 * s.astack.length)) := hs.ap
  have hexec : execL ([.globalGet apG, i32c 8, .i32sub, .globalSet apG, .globalGet apG] ++ ldS 0 ++
      [.i64store 0] ++ spAdd 8) w =
      some { w with mem := m', globals := setG (setG w.globals apG (.i32 (ofN (c.aEnd - 8 * (s.astack.length + 1))))) spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) } := by
    simp [ldS, spAdd, execL, stepI, bin32, hapa, hspa, i32c, hsub, apG, spG, hst,
      ofN_toNat hX, ofN_toNat hlt, hr0, hm', hsp8]
    unfold setG; rfl
  have hrel1 := push_aux hg hs hfit hm'
  have hrel2 := adj_sp hg hrel1 (n := 1) (by simp [hd])
  have e3 : ({ { s with astack := a :: s.astack } with
      dstack := ({ s with astack := a :: s.astack } : State 64).dstack.drop 1 } : State 64) =
      { s with dstack := d, astack := a :: s.astack } := by
    simp [hd]
  rw [e3] at hrel2
  have hrel3 : Rel0 c { s with dstack := d, astack := a :: s.astack }
      { w with mem := m', globals := setG (setG w.globals apG (.i32 (ofN (c.aEnd - 8 * (s.astack.length + 1))))) spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) } := by
    refine Rel0.congr (hrel2.setStack []) rfl ?_ ?_ ?_
    · have e2 : c.dEnd - 8 * s.dstack.length + 8 = c.dEnd - 8 * (s.dstack.length - 1) := by omega
      simp [setG, spG, e2]
    · simp [setG, spG, rpG]
    · simp [setG, spG, apG]
  have := core_gen (fs := fs) (pre := uf c.layout 1 ++ ovf apG c.layout.aBase)
    (run_append _ (uf1_pass hg hs hd) (ovfA_pass hg hs hfit))
    (B := [.globalGet apG, i32c 8, .i32sub, .globalSet apG, .globalGet apG] ++ ldS 0 ++ [.i64store 0] ++
      spAdd 8)
    (allSimple_spec (by simp [allSimple, ldS, spAdd, WI.isCtl, i32c])) ⟨_, hexec, hrel3, hst⟩ (k + 1)
  rw [tor_split]
  exact this

theorem sim_tor_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) {a : W} {d : List W}
    (hd : s.dstack = a :: d) (h : ¬ c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd) :
    Run fs (lowerInstr c.layout n k .tor) w (.exit 6) := by
  rw [tor_split, List.append_assoc]
  exact run_append _ (uf1_pass hg hs hd) (run_append_abrupt _ (ovfA_trap hg hs h) trivial)

theorem fromr_split (L : Layout) (n k : Nat) : lowerInstr L n k .fromr =
    auxE L ++ ovf spG L.dBase ++
      ((pushWith [.globalGet apG, .i64load 0] ++ [.globalGet apG, i32c 8, .i32add, .globalSet apG]) ++
        [i32c (k + 1)]) := by
  simp [lowerInstr, auxE, List.append_assoc]

theorem rfetch_split (L : Layout) (n k : Nat) : lowerInstr L n k .rfetch =
    auxE L ++ ovf spG L.dBase ++ (pushWith [.globalGet apG, .i64load 0] ++ [i32c (k + 1)]) := by
  simp [lowerInstr, auxE, List.append_assoc]

/-- Pushing the auxiliary top `[ap]` onto the data stack. -/
theorem push_atop (hg : Geom c) (hs : Rel0 c s w) {a : W} {as : List W} (ha : s.astack = a :: as)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ w1, execL (pushWith [.globalGet apG, .i64load 0]) w = some w1 ∧
      Rel0 c { s with dstack := a :: s.dstack } w1 ∧ w1.stack = w.stack := by
  have hA := ap_lt hg hs
  have hr0 : w.mem.read64 (c.aEnd - 8 * s.astack.length) = some a := by
    have := hs.aux 0 a (by simp [ha]); simpa using this
  exact push_gen hg hs hfit (val := [.globalGet apG, .i64load 0]) (v := a) (by simp [WI.isCtl])
    (by
      intro u _ hm hap
      simp [execL, stepI, hap, hs.ap, ofN_toNat hA, hm, hr0])

theorem sim_rfetch (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : W}
    {as : List W} (ha : s.astack = a :: as) (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Sim1 c fs (lowerInstr c.layout n k .rfetch) { s with dstack := a :: s.dstack } w (k + 1) := by
  obtain ⟨w1, he, hr, hst1⟩ := push_atop hg hs ha hfit
  have := core_gen (fs := fs) (pre := auxE c.layout ++ ovf spG c.layout.dBase)
    (run_append _ (auxE_pass hg hs ha) (ovfD_pass hg hs hfit))
    (B := pushWith [.globalGet apG, .i64load 0])
    (allSimple_spec (by simp [allSimple, pushWith, spSub, WI.isCtl, i32c])) ⟨w1, he, hr, by rw [hst1, hst]⟩
    (k + 1)
  rw [rfetch_split]
  exact this

theorem sim_fromr (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : W}
    {as : List W} (ha : s.astack = a :: as) (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Sim1 c fs (lowerInstr c.layout n k .fromr) { s with dstack := a :: s.dstack, astack := as } w
      (k + 1) := by
  obtain ⟨w1, he, hr, hst1⟩ := push_atop hg hs ha hfit
  have hcap := hs.capA
  rw [ha] at hcap
  simp only [List.length_cons] at hcap
  have hX : c.aEnd - 8 * (as.length + 1) < 2 ^ 32 := by have := ap_lt hg hs; rw [ha] at this; simpa using this
  have hap1 : w1.globals apG = .i32 (ofN (c.aEnd - 8 * (as.length + 1))) := by
    have := hr.ap; simp only [ha, List.length_cons] at this; exact this
  have hsp8 : ofN (c.aEnd - 8 * (as.length + 1)) + 8#32 = ofN (c.aEnd - 8 * as.length) := by
    rw [show (8#32 : W32) = ofN 8 from rfl, ofN_add]; congr 1; omega
  have e2 : execL [.globalGet apG, i32c 8, .i32add, .globalSet apG] w1 =
      some { w1 with globals := setG w1.globals apG (.i32 (ofN (c.aEnd - 8 * as.length))) } := by
    simp [execL, stepI, bin32, hap1, i32c, hsp8]
    unfold setG; rfl
  have hra : ({ s with dstack := a :: s.dstack } : State 64).astack = a :: as := ha
  have hrel := pop_aux hr hra
  have hB : execL (pushWith [.globalGet apG, .i64load 0] ++ [.globalGet apG, i32c 8, .i32add, .globalSet apG]) w =
      some { w1 with globals := setG w1.globals apG (.i32 (ofN (c.aEnd - 8 * as.length))) } := by
    rw [execL_append, he]
    exact e2
  have := core_gen (fs := fs) (pre := auxE c.layout ++ ovf spG c.layout.dBase)
    (run_append _ (auxE_pass hg hs ha) (ovfD_pass hg hs hfit))
    (B := pushWith [.globalGet apG, .i64load 0] ++ [.globalGet apG, i32c 8, .i32add, .globalSet apG])
    (allSimple_spec (by simp [allSimple, pushWith, spSub, WI.isCtl, i32c])) ⟨_, hB, hrel, by simp [hst1, hst]⟩
    (k + 1)
  rw [fromr_split]
  exact this

theorem sim_fromr_trap (n k : Nat) (hs : Rel0 c s w) (ha : s.astack = []) :
    Run fs (lowerInstr c.layout n k .fromr) w (.exit 5) := by
  rw [fromr_split, List.append_assoc]
  exact run_append_abrupt _ (auxE_trap hs ha) trivial

theorem sim_rfetch_trap (n k : Nat) (hs : Rel0 c s w) (ha : s.astack = []) :
    Run fs (lowerInstr c.layout n k .rfetch) w (.exit 5) := by
  rw [rfetch_split, List.append_assoc]
  exact run_append_abrupt _ (auxE_trap hs ha) trivial

theorem sim_fromr_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) {a : W} {as : List W}
    (ha : s.astack = a :: as) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (lowerInstr c.layout n k .fromr) w (.exit 6) := by
  rw [fromr_split, List.append_assoc]
  exact run_append _ (auxE_pass hg hs ha) (run_append_abrupt _ (ovfD_trap hg hs h) trivial)

theorem sim_rfetch_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) {a : W} {as : List W}
    (ha : s.astack = a :: as) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (lowerInstr c.layout n k .rfetch) w (.exit 6) := by
  rw [rfetch_split, List.append_assoc]
  exact run_append _ (auxE_pass hg hs ha) (run_append_abrupt _ (ovfD_trap hg hs h) trivial)

end Sim

end Wasm
end WordDialect
