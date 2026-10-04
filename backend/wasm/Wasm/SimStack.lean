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
  have := core_gen (fs := fs) (pre := ovf spG c.layout.dBase) (ovfD_pass hg hs hfit) (B := pushWith [.i64const v])
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
  have := core_gen (fs := fs) (pre := ovf spG c.layout.dBase) (ovfD_pass hg hs hfit)
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
  have := core_gen (fs := fs) (pre := uf c.layout 1 ++ ovf spG c.layout.dBase)
    (run_append _ (uf1_pass hg hs hd) (ovfD_pass hg hs hfit)) (B := pushWith (ldS 8))
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
  have := core_gen (fs := fs) (pre := uf c.layout 2 ++ ovf spG c.layout.dBase)
    (run_append _ (uf2_pass hg hs hd) (ovfD_pass hg hs hfit))
    (B := pushWith [.globalGet spG, .i64load 16])
    (allSimple_spec (by simp [allSimple, pushWith, spSub, WI.isCtl, i32c])) ⟨w1, he, hr, by rw [hst1, hst]⟩ (k + 1)
  simpa [lowerInstr, pushWith, List.append_assoc] using this

theorem sim_swap (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .swap) { s with dstack := a :: b :: d } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 2 := by simp [hd]
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hdE := hg.dEnd_le
  have hr1 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8) = some a := by
    have := hs.stack 1 a (by simp [hd]); simpa using this
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some b := by
    have := hs.stack 0 b (by simp [hd]); simpa using this
  obtain ⟨m1, hm1⟩ : ∃ m1, w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8) b = some m1 :=
    write64_some (by rw [hs.size]; omega)
  obtain ⟨hsz1, _⟩ := write64_size hm1
  obtain ⟨m2, hm2⟩ : ∃ m2, m1.write64 (c.dEnd - 8 * s.dstack.length) a = some m2 :=
    write64_some (by rw [hsz1, hs.size]; omega)
  have hexec : execL ([.globalGet spG] ++ ldS 8 ++ [.globalGet spG] ++ ldS 0 ++ [.i64store 8, .i64store 0]) w = some { w with mem := m2 } := by
    simp [ldS, execL, stepI, hs.sp, ofN_toNat hX, hr0, hr1, hm1, hm2]
  have hrel1 := wr_stack hg hs (j := 1) (by omega) (v := b) (m' := m1) (by simpa using hm1)
  have hrel2 := wr_stack_at hg hrel1 (j := 0) (by simp; omega) (v := a) (m' := m2) (A := c.dEnd - 8 * s.dstack.length)
    (by simp) (by simpa using hm2)
  have e : (({ s with dstack := s.dstack.set 1 b } : State 64).dstack.set 0 a) = a :: b :: d := by simp [hd]
  have e3 : ({ { s with dstack := s.dstack.set 1 b } with dstack := (({ s with dstack := s.dstack.set 1 b } : State 64).dstack.set 0 a) } : State 64) = { s with dstack := a :: b :: d } := by
    simp [hd]
  rw [e3] at hrel2
  have := core_gen (fs := fs) (pre := uf c.layout 2) (uf2_pass hg hs hd)
    (B := [.globalGet spG] ++ ldS 8 ++ [.globalGet spG] ++ ldS 0 ++ [.i64store 8, .i64store 0])
    (allSimple_spec (by simp [allSimple, ldS, WI.isCtl])) ⟨_, hexec, hrel2, hst⟩ (k + 1)
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_rot (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {cc b a : W} {d : List W}
    (hd : s.dstack = cc :: b :: a :: d) :
    Sim1 c fs (lowerInstr c.layout n k .rot) { s with dstack := a :: cc :: b :: d } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 3 := by simp [hd]
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hdE := hg.dEnd_le
  have hr2 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 16) = some a := by
    have := hs.stack 2 a (by simp [hd]); simpa using this
  have hr1 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8) = some b := by
    have := hs.stack 1 b (by simp [hd]); simpa using this
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some cc := by
    have := hs.stack 0 cc (by simp [hd]); simpa using this
  obtain ⟨m1, hm1⟩ : ∃ m1, w.mem.write64 (c.dEnd - 8 * s.dstack.length + 16) b = some m1 :=
    write64_some (by rw [hs.size]; omega)
  obtain ⟨hsz1, _⟩ := write64_size hm1
  obtain ⟨m2, hm2⟩ : ∃ m2, m1.write64 (c.dEnd - 8 * s.dstack.length + 8) cc = some m2 :=
    write64_some (by rw [hsz1, hs.size]; omega)
  obtain ⟨hsz2, _⟩ := write64_size hm2
  obtain ⟨m3, hm3⟩ : ∃ m3, m2.write64 (c.dEnd - 8 * s.dstack.length) a = some m3 :=
    write64_some (by rw [hsz2, hsz1, hs.size]; omega)
  have hexec : execL ([.globalGet spG] ++ ldS 16 ++ [.globalGet spG] ++ ldS 0 ++ [.globalGet spG] ++ ldS 8 ++ [.i64store 16, .i64store 8, .i64store 0]) w = some { w with mem := m3 } := by
    simp [ldS, execL, stepI, hs.sp, ofN_toNat hX, hr0, hr1, hr2, hm1, hm2, hm3]
  have hrel1 := wr_stack_at hg hs (j := 2) (by omega) (v := b) (m' := m1) (A := c.dEnd - 8 * s.dstack.length + 16) (by simp) hm1
  have hrel2 := wr_stack_at hg hrel1 (j := 1) (by simp; omega) (v := cc) (m' := m2) (A := c.dEnd - 8 * s.dstack.length + 8)
    (by simp) (by simpa using hm2)
  have hrel3 := wr_stack_at hg hrel2 (j := 0) (by simp; omega) (v := a) (m' := m3) (A := c.dEnd - 8 * s.dstack.length)
    (by simp) (by simpa using hm3)
  have e3 : ({ { { s with dstack := s.dstack.set 2 b } with dstack := (({ s with dstack := s.dstack.set 2 b } : State 64).dstack.set 1 cc) } with dstack := ((({ s with dstack := s.dstack.set 2 b } : State 64).dstack.set 1 cc).set 0 a) } : State 64) = { s with dstack := a :: cc :: b :: d } := by
    simp [hd]
  rw [e3] at hrel3
  have := core_gen (fs := fs) (pre := uf c.layout 3) (uf3_pass hg hs hd)
    (B := [.globalGet spG] ++ ldS 16 ++ [.globalGet spG] ++ ldS 0 ++ [.globalGet spG] ++ ldS 8 ++ [.i64store 16, .i64store 8, .i64store 0])
    (allSimple_spec (by simp [allSimple, ldS, WI.isCtl])) ⟨_, hexec, hrel3, hst⟩ (k + 1)
  simpa [lowerInstr, List.append_assoc] using this

/-- Core of instructions that overwrite slot `j` with `y` and then pop `n` words. -/
theorem sim_wa_core (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {pre : List WI}
    (hpre : Run fs pre w (.normal w)) {j n : Nat} {y : W} {L' : List W}
    (hj : j < s.dstack.length) (hn : n ≤ s.dstack.length) (hL' : (s.dstack.set j y).drop n = L')
    {B : List WI} (hctlB : ∀ i ∈ B, i.isCtl = false)
    (hB : ∀ m', w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8 * j) y = some m' →
      execL B w = some { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8 * n))) })
    (nxt : Nat) :
    ∃ w', Run fs (pre ++ (B ++ [i32c nxt])) w (.normal w') ∧
      Rel0 c { s with dstack := L' } w' ∧ w'.stack = [.i32 (ofN nxt)] := by
  have hcap := hs.capD
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.dEnd - 8 * s.dstack.length + 8 * j) y = some m' :=
    write64_some (by rw [hs.size]; have := hg.dEnd_le; omega)
  have hbR := run_of_execL (fs := fs) hctlB (hB m' hm')
  have hrel1 := wr_stack hg hs (j := j) hj (v := y) (m' := m') hm'
  have hrel2 := adj_sp hg hrel1 (n := n) (by simpa using hn)
  have e3 : ({ { s with dstack := s.dstack.set j y } with dstack := ({ s with dstack := s.dstack.set j y } : State 64).dstack.drop n } : State 64) = { s with dstack := L' } := by
    rw [← hL']
  rw [e3] at hrel2
  have e2 : c.dEnd - 8 * s.dstack.length + 8 * n = c.dEnd - 8 * (s.dstack.length - n) := by omega
  rw [e2] at hbR
  refine ⟨_, run_append _ hpre (run_append _ hbR (run_finish nxt)), ?_, ?_⟩
  · refine Rel0.congr (hrel2.setStack []) rfl ?_ ?_
    · simp [setG, spG, List.length_set]
    · simp [setG, spG, rpG]
  · simp [hst]

theorem sim_select (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {cc y x : W} {d : List W}
    (hd : s.dstack = cc :: y :: x :: d) :
    Sim1 c fs (lowerInstr c.layout n k .select) { s with dstack := (if Word.isTrue cc then x else y) :: d } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 3 := by simp [hd]
  have hX := sp_lt hg hs
  have hr2 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 16) = some x := by
    have := hs.stack 2 x (by simp [hd]); simpa using this
  have hr1 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8) = some y := by
    have := hs.stack 1 y (by simp [hd]); simpa using this
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some cc := by
    have := hs.stack 0 cc (by simp [hd]); simpa using this
  have hsp16 : ofN (c.dEnd - 8 * s.dstack.length) + 16#32 = ofN (c.dEnd - 8 * s.dstack.length + 16) :=
    ofN_add (c.dEnd - 8 * s.dstack.length) 16
  have := sim_wa_core (fs := fs) hg hs hst (uf3_pass hg hs hd) (j := 2) (n := 2)
    (y := if Word.isTrue cc then x else y) (L' := (if Word.isTrue cc then x else y) :: d)
    (by omega) (by omega) (by simp [hd]) (B := [.globalGet spG] ++ ldS 16 ++ ldS 8 ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select, .i64store 16] ++ spAdd 16)
    (allSimple_spec (by simp [allSimple, ldS, spAdd, WI.isCtl, i32c])) ?_ (k + 1)
  · simpa [lowerInstr, List.append_assoc] using this
  intro m' hm'
  by_cases hc : cc = 0#64
  · have hm2 : w.mem.write64 (c.dEnd - 8 * s.dstack.length + 16) y = some m' := by simpa [hc, Word.isTrue] using hm'
    simp [ldS, spAdd, execL_append, execL, stepI, cmp64, bin32, hs.sp, ofN_toNat hX, hr0, hr1, hr2, bool32, hc, hm2, i32c, hsp16]
    rfl
  · have hm2 : w.mem.write64 (c.dEnd - 8 * s.dstack.length + 16) x = some m' := by simpa [hc, Word.isTrue] using hm'
    simp [ldS, spAdd, execL_append, execL, stepI, cmp64, bin32, hs.sp, ofN_toNat hX, hr0, hr1, hr2, bool32, hc, hm2, i32c, hsp16]
    rfl

theorem sim_pop (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {r : Nat}
    (hr : r < c.nregs) {a : W} {d : List W} (hd : s.dstack = a :: d) :
    Sim1 c fs (lowerInstr c.layout n k (.pop r)) { s with dstack := d, regs := State.setReg s.regs r a } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 1 := by simp [hd]
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hrf := hg.rf_le
  have hsz := hg.msize_lt
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  have hrfl : c.rf + 8 * r < 2 ^ 32 := by omega
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.rf + 8 * r) a = some m' :=
    write64_some (by rw [hs.size]; omega)
  have hsp8 : ofN (c.dEnd - 8 * s.dstack.length) + 8#32 = ofN (c.dEnd - 8 * s.dstack.length + 8) :=
    ofN_add _ _
  have hexec : execL ([i32c (c.layout.rf + 8 * r)] ++ ldS 0 ++ [.i64store 0] ++ spAdd 8) w = some { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) } := by
    simp [ldS, spAdd, execL_append, execL, stepI, bin32, hs.sp, ofN_toNat hX, hr0, i32c, Cfg.layout, BitVec.toNat_ofNat, Nat.mod_eq_of_lt hrfl, hm', hsp8]
    unfold setG
    rfl
  have hrel1 := wr_regs hg hs hr hm'
  have hrel2 := adj_sp hg hrel1 (n := 1) (by simp [hd])
  have e3 : ({ { s with regs := State.setReg s.regs r a } with dstack := ({ s with regs := State.setReg s.regs r a } : State 64).dstack.drop 1 } : State 64) = { s with dstack := d, regs := State.setReg s.regs r a } := by
    simp [hd]
  rw [e3] at hrel2
  have hrel3 : Rel0 c { s with dstack := d, regs := State.setReg s.regs r a } { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 8))) } := by
    refine Rel0.congr (hrel2.setStack []) rfl ?_ ?_
    · have e2 : c.dEnd - 8 * s.dstack.length + 8 = c.dEnd - 8 * (s.dstack.length - 1) := by omega
      simp [setG, spG, e2]
    · simp [setG, spG, rpG]
  have := core_gen (fs := fs) (pre := uf c.layout 1) (uf1_pass hg hs hd)
    (B := [i32c (c.layout.rf + 8 * r)] ++ ldS 0 ++ [.i64store 0] ++ spAdd 8)
    (allSimple_spec (by simp [allSimple, ldS, spAdd, WI.isCtl, i32c])) ⟨_, hexec, hrel3, hst⟩ (k + 1)
  simpa [lowerInstr, List.append_assoc] using this

/-! Data-stack overflow: every instruction that grows the data stack exits 6 when it is full. -/

theorem sim_word_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (v : W)
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (lowerInstr c.layout n k (.word v)) w (.exit 6) := by
  have := run_append_abrupt (fs := fs) _ (ovfD_trap hg hs h)
    (b := pushWith [.i64const v] ++ [i32c (k + 1)]) trivial
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_ptr_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (q : WordDialect.Ptr 64)
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (lowerInstr c.layout n k (.ptr q)) w (.exit 6) := by
  have := run_append_abrupt (fs := fs) _ (ovfD_trap hg hs h)
    (b := pushWith [.i64const q.toWord] ++ [i32c (k + 1)]) trivial
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_push_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (r : Nat)
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (lowerInstr c.layout n k (.push r)) w (.exit 6) := by
  have := run_append_abrupt (fs := fs) _ (ovfD_trap hg hs h)
    (b := pushWith [i32c (c.layout.rf + 8 * r), .i64load 0] ++ [i32c (k + 1)]) trivial
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_dup_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) {a : W} {d : List W}
    (hd : s.dstack = a :: d) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (lowerInstr c.layout n k .dup) w (.exit 6) := by
  have := run_append (fs := fs) _ (uf1_pass hg hs hd) (run_append_abrupt _ (ovfD_trap hg hs h)
    (b := spSub 8 ++ [.globalGet spG] ++ ldS 8 ++ [.i64store 0] ++ [i32c (k + 1)]) trivial)
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_over_ovf (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) {a b : W} {d : List W}
    (hd : s.dstack = b :: a :: d) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    Run fs (lowerInstr c.layout n k .over) w (.exit 6) := by
  have := run_append (fs := fs) _ (uf2_pass hg hs hd) (run_append_abrupt _ (ovfD_trap hg hs h)
    (b := spSub 8 ++ [.globalGet spG, .globalGet spG, .i64load 16, .i64store 0] ++ [i32c (k + 1)]) trivial)
  simpa [lowerInstr, List.append_assoc] using this

end Sim

end Wasm
end WordDialect
