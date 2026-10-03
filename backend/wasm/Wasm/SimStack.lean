import Wasm.SimAlu2

/-!
# Wasm.SimStack

`not`, `drop`, `dup`, `over`, `swap`, `rot`, `select`, `word`, `ptr`, `push`, `pop`.
-/

namespace WordDialect
namespace Wasm

section Sim

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

/-- Finish an instruction: given the execution of its body, append the next-pc push. -/
theorem core_gen {pre B : List WI} {s' : State 64} (hpre : Run fs pre w (.normal w))
    (hctl : ∀ i ∈ B, i.isCtl = false)
    (hB : ∃ w1, execL B w = some w1 ∧ Rel0 c s' w1 ∧ w1.stack = []) (nxt : Nat) :
    ∃ w', Run fs (pre ++ (B ++ [i32c nxt])) w (.normal w') ∧ Rel0 c s' w' ∧
      w'.stack = [.i32 (ofN nxt)] := by
  obtain ⟨w1, he, hr, hs1⟩ := hB
  exact ⟨{ w1 with stack := .i32 (ofN nxt) :: w1.stack },
    run_append _ hpre (run_append _ (run_of_execL hctl he) (run_finish nxt)), hr.setStack _, by simp [hs1]⟩

theorem uf1_pass (hg : Geom c) (hs : Rel0 c s w) {a : W} {d : List W} (hd : s.dstack = a :: d) :
    Run fs (uf c.layout 1) w (.normal w) :=
  uf_pass hg hs (k := 1) (by omega) (by simp [hd])

theorem uf3_pass (hg : Geom c) (hs : Rel0 c s w) {x y z : W} {d : List W} (hd : s.dstack = x :: y :: z :: d) :
    Run fs (uf c.layout 3) w (.normal w) :=
  uf_pass hg hs (k := 3) (by omega) (by simp [hd])

theorem ld_slot (hs : Rel0 c s w) {j : Nat} {v : W} (hj : s.dstack[j]? = some v) :
    w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8 * j) = some v := hs.stack j v hj

theorem xor_lit (a : W) : a ^^^ 18446744073709551615#64 = ~~~a := by
  have := BitVec.xor_allOnes (x := a)
  simpa using this

theorem sim_not (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : W} {d : List W}
    (hd : s.dstack = a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .not) { s with dstack := (~~~a) :: d } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 1 := by simp [hd]
  have hX := sp_lt hg hs
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.dEnd - 8 * s.dstack.length) (~~~a) = some m' :=
    write64_some (by rw [hs.size]; have := hg.dEnd_le; have := hs.capD; omega)
  have hexec : execL ([.globalGet spG] ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64xor, .i64store 0]) w = some { w with mem := m' } := by
    simp [ldS, execL, stepI, bin64, hs.sp, ofN_toNat hX, hr0, hm', xor_lit]
  have hrel := wr_stack hg hs (j := 0) (by omega) (v := ~~~a) (m' := m') (by simpa using hm')
  have e : s.dstack.set 0 (~~~a) = (~~~a) :: d := by simp [hd]
  rw [e] at hrel
  have := core_gen (fs := fs) (pre := uf c.layout 1) (uf1_pass hg hs hd)
    (B := [.globalGet spG] ++ ldS 0 ++ [.i64const (BitVec.allOnes 64), .i64xor, .i64store 0])
    (by simp only [ldS, List.append_assoc]; exact allSimple_spec (by decide)) ⟨_, hexec, hrel, hst⟩ (k + 1)
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_drop (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : W} {d : List W}
    (hd : s.dstack = a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .drop) { s with dstack := d } w (k + 1) := by
  have hX := sp_lt hg hs
  have hsp8 : ofN (c.dEnd - 8 * s.dstack.length) + 8#32 = ofN (c.dEnd - 8 * s.dstack.length + 8) :=
    ofN_add _ _
  have hexec : execL (spAdd 8) w = some { w with globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) } := by
    simp [spAdd, execL, stepI, bin32, hs.sp, i32c]
    unfold setG
    rw [hsp8]
  have hrel := adj_sp hg hs (n := 1) (by simp [hd])
  have e : s.dstack.drop 1 = d := by simp [hd]
  have e2 : c.dEnd - 8 * s.dstack.length + 8 = c.dEnd - 8 * (s.dstack.length - 1) := by
    have := hs.capD; have : s.dstack.length = d.length + 1 := by simp [hd]
    omega
  rw [e2] at hexec
  have hrel' : Rel0 c { s with dstack := d } { w with globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length - 1)))) } := by
    have e3 : ({ s with dstack := s.dstack.drop 1 } : State 64) = { s with dstack := d } := by rw [e]
    rw [e3] at hrel; exact hrel
  have := core_gen (fs := fs) (pre := uf c.layout 1) (uf1_pass hg hs hd) (B := spAdd 8)
    (allSimple_spec (by decide)) ⟨_, hexec, hrel', hst⟩ (k + 1)
  simpa [lowerInstr, List.append_assoc] using this

theorem push_gen (hg : Geom c) (hs : Rel0 c s w)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) {val : List WI} {v : W}
    (hctl : ∀ i ∈ val, i.isCtl = false)
    (hval : ∀ u : WState, u.globals spG = .i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1))) →
      u.mem = w.mem → execL val u = some { u with stack := .i64 v :: u.stack }) :
    ∃ w1, execL (pushWith val) w = some w1 ∧ Rel0 c { s with dstack := v :: s.dstack } w1 ∧
      w1.stack = w.stack := by
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hdE := hg.dEnd_le
  have hsz := hg.msize_lt
  have hlt : c.dEnd - 8 * (s.dstack.length + 1) < 2 ^ 32 := by omega
  have hsub : ofN (c.dEnd - 8 * s.dstack.length) - 8#32 = ofN (c.dEnd - 8 * (s.dstack.length + 1)) := by
    have : (8#32 : W32) = ofN 8 := rfl
    rw [this, ofN_sub (by omega)]
    congr 1
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.dEnd - 8 * (s.dstack.length + 1)) v = some m' :=
    write64_some (by rw [hs.size]; omega)
  have h1 : execL (spSub 8) w = some { w with globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) } := by
    simp [spSub, execL, stepI, bin32, hs.sp, i32c, hsub]
    rfl
  have hg1 : execL [.globalGet spG] { w with globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) } = some { w with stack := .i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1))) :: w.stack, globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) } := by
    simp [execL, stepI, setG, spG]
  have h2 := hval { w with stack := .i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1))) :: w.stack, globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) } (by simp [setG, spG]) rfl
  have h3 : execL [.i64store 0] { w with stack := .i64 v :: .i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1))) :: w.stack, globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) } = some { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) } := by
    simp [execL, stepI, ofN_toNat hlt, hm']
  refine ⟨{ w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length + 1)))) }, ?_, push_rel hg hs hfit hm', rfl⟩
  have e1 : pushWith val = spSub 8 ++ ([.globalGet spG] ++ (val ++ [.i64store 0])) := by
    simp [pushWith, List.append_assoc]
  rw [e1, execL_append, h1]
  simp only [Option.bind_some]
  rw [execL_append, hg1]
  simp only [Option.bind_some]
  rw [execL_append, h2]
  simp only [Option.bind_some]
  exact h3

theorem sim_word (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) (v : W)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Sim1 c fs (lowerInstr c.layout n k (.word v)) { s with dstack := v :: s.dstack } w (k + 1) := by
  have hB := push_gen hg hs hfit (val := [.i64const v]) (v := v) (by simp [WI.isCtl])
    (by intro u _ _; simp [execL, stepI])
  obtain ⟨w1, he, hr, hst1⟩ := hB
  have := core_gen (fs := fs) (pre := []) .nil (B := pushWith [.i64const v])
    (allSimple_spec (by simp [allSimple, pushWith, spSub, WI.isCtl, i32c])) ⟨w1, he, hr, by rw [hst1, hst]⟩ (k + 1)
  simpa [lowerInstr, pushWith, List.append_assoc] using this

theorem sim_ptr (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) (q : WordDialect.Ptr 64)
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Sim1 c fs (lowerInstr c.layout n k (.ptr q)) { s with dstack := q.toWord :: s.dstack } w (k + 1) :=
  sim_word n k hg hs hst q.toWord hfit

theorem sim_push (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {r : Nat}
    (hr : r < c.nregs) (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Sim1 c fs (lowerInstr c.layout n k (.push r)) { s with dstack := s.regs r :: s.dstack } w (k + 1) := by
  have hrf := hg.rf_le
  have hsz := hg.msize_lt
  have hB := push_gen hg hs hfit (val := [i32c (c.layout.rf + 8 * r), .i64load 0]) (v := s.regs r)
    (by simp [WI.isCtl, i32c])
    (by
      intro u _ hm
      have h1 := hs.regs r hr
      have h2 : c.rf + 8 * r < 2 ^ 32 := by omega
      simp [execL, stepI, i32c, Cfg.layout, hm, BitVec.toNat_ofNat, Nat.mod_eq_of_lt h2, h1])
  obtain ⟨w1, he, hr1, hst1⟩ := hB
  have := core_gen (fs := fs) (pre := []) .nil
    (B := pushWith [i32c (c.layout.rf + 8 * r), .i64load 0])
    (allSimple_spec (by simp [allSimple, pushWith, spSub, WI.isCtl, i32c])) ⟨w1, he, hr1, by rw [hst1, hst]⟩ (k + 1)
  simpa [lowerInstr, pushWith, List.append_assoc] using this

theorem sim_dup (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : W} {d : List W}
    (hd : s.dstack = a :: d) (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Sim1 c fs (lowerInstr c.layout n k .dup) { s with dstack := a :: a :: d } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 1 := by simp [hd]
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  have hsz := hg.msize_lt
  have hdE := hg.dEnd_le
  have hlt : c.dEnd - 8 * (s.dstack.length + 1) < 2 ^ 32 := by omega
  have hB := push_gen hg hs hfit (val := ldS 8) (v := a)
    (by simp [ldS, WI.isCtl])
    (by
      intro u hu hm
      have e : c.dEnd - 8 * (s.dstack.length + 1) + 8 = c.dEnd - 8 * s.dstack.length := by omega
      simp [ldS, execL, stepI, hu, ofN_toNat hlt, e, hm, hr0])
  obtain ⟨w1, he, hr, hst1⟩ := hB
  have e : a :: s.dstack = a :: a :: d := by rw [hd]
  rw [e] at hr
  have := core_gen (fs := fs) (pre := uf c.layout 1) (uf1_pass hg hs hd) (B := pushWith (ldS 8))
    (allSimple_spec (by simp [allSimple, pushWith, spSub, ldS, WI.isCtl, i32c])) ⟨w1, he, hr, by rw [hst1, hst]⟩ (k + 1)
  simpa [lowerInstr, pushWith, List.append_assoc] using this

theorem sim_over (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Sim1 c fs (lowerInstr c.layout n k .over) { s with dstack := a :: b :: a :: d } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 2 := by simp [hd]
  have hr1 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8) = some a := by
    have := hs.stack 1 a (by simp [hd]); simpa using this
  have hsz := hg.msize_lt
  have hdE := hg.dEnd_le
  have hlt : c.dEnd - 8 * (s.dstack.length + 1) < 2 ^ 32 := by omega
  have hB := push_gen hg hs hfit (val := [.globalGet spG, .i64load 16]) (v := a)
    (by simp [WI.isCtl])
    (by
      intro u hu hm
      have e : c.dEnd - 8 * (s.dstack.length + 1) + 16 = c.dEnd - 8 * s.dstack.length + 8 := by omega
      simp [execL, stepI, hu, ofN_toNat hlt, e, hm, hr1])
  obtain ⟨w1, he, hr, hst1⟩ := hB
  have e : a :: s.dstack = a :: b :: a :: d := by rw [hd]
  rw [e] at hr
  have := core_gen (fs := fs) (pre := uf c.layout 2) (uf2_pass hg hs hd)
    (B := pushWith [.globalGet spG, .i64load 16])
    (allSimple_spec (by simp [allSimple, pushWith, spSub, WI.isCtl, i32c])) ⟨w1, he, hr, by rw [hst1, hst]⟩ (k + 1)
  simpa [lowerInstr, pushWith, List.append_assoc] using this

end Sim

end Wasm
end WordDialect
