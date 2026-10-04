import Wasm.SimMem

/-!
# Wasm.SimCtl

Control flow: `jmp`, `branch`, `call`, `ret` (and its `returnUnderflow` exit 5), `halt`, and the
bad-pc stub (exit 4). Each leaves the next IR index on the operand stack, which the dispatch loop
stores into the `pc` global.
-/

namespace WordDialect
namespace Wasm

section Sim

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

theorem sim_jmp (n k t : Nat) (hs : Rel0 c s w) (hst : w.stack = []) :
    Sim1 c fs (lowerInstr c.layout n k (.jmp t)) s w (min t n) :=
  ⟨_, run_finish (min t n), hs.setStack _, by simp [hst]⟩

theorem sim_branch (n k t : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {cv : W}
    {d : List W} (hd : s.dstack = cv :: d) :
    Sim1 c fs (lowerInstr c.layout n k (.branch t)) { s with dstack := d } w
      (if Word.isTrue cv then min t n else k + 1) := by
  have hlen : s.dstack.length = d.length + 1 := by simp [hd]
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some cv := by
    have := hs.stack 0 cv (by simp [hd]); simpa using this
  have hsp8 : ofN (c.dEnd - 8 * s.dstack.length) + 8#32 = ofN (c.dEnd - 8 * s.dstack.length + 8) :=
    ofN_add _ _
  have e2 : c.dEnd - 8 * s.dstack.length + 8 = c.dEnd - 8 * (s.dstack.length - 1) := by omega
  have el : execL ([i32c (min t n), i32c (k + 1)] ++ ldS 0 ++ [.i64const 0#64, .i64ne, .select] ++ spAdd 8) w =
      some { w with stack := [.i32 (ofN (if Word.isTrue cv then min t n else k + 1))],
                    globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * (s.dstack.length - 1)))) } := by
    rw [← e2]
    by_cases hc : cv = 0#64
    · simp [ldS, spAdd, execL, stepI, cmp64, bin32, hs.sp, ofN_toNat hX, hr0, bool32, hc, i32c, hsp8,
        Word.isTrue, hst]
      exact ⟨rfl, rfl⟩
    · simp [ldS, spAdd, execL, stepI, cmp64, bin32, hs.sp, ofN_toNat hX, hr0, bool32, hc, i32c, hsp8,
        Word.isTrue, hst]
      exact ⟨rfl, rfl⟩
  have rl := run_of_execL (fs := fs) (by simp [ldS, spAdd, WI.isCtl, i32c]) el
  have hrel := adj_sp hg hs (n := 1) (by simp [hd])
  have e3 : ({ s with dstack := s.dstack.drop 1 } : State 64) = { s with dstack := d } := by simp [hd]
  rw [e3] at hrel
  refine ⟨_, ?_, hrel.setStack _, rfl⟩
  have := run_append _ (uf1_pass (fs := fs) hg hs hd) rl
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_call (n k t : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = [])
    (hfit : c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd) :
    Sim1 c fs (lowerInstr c.layout n k (.call t)) { s with rstack := (k + 1) :: s.rstack } w (min t n) := by
  have hcap := hs.capR
  have hrE := hg.rEnd_le
  have hsz := hg.msize_lt
  have hlt : c.rEnd - 8 * (s.rstack.length + 1) < 2 ^ 32 := by omega
  have hsub : ofN (c.rEnd - 8 * s.rstack.length) - 8#32 = ofN (c.rEnd - 8 * (s.rstack.length + 1)) := by
    have : (8#32 : W32) = ofN 8 := rfl
    rw [this, ofN_sub (by omega)]
    congr 1
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.rEnd - 8 * (s.rstack.length + 1)) (BitVec.ofNat 64 (k + 1)) = some m' :=
    write64_some (by rw [hs.size]; omega)
  have el : execL [.globalGet rpG, i32c 8, .i32sub, .globalSet rpG, .globalGet rpG, i64c (k + 1), .i64store 0,
      i32c (min t n)] w =
      some { w with mem := m', stack := [.i32 (ofN (min t n))],
                    globals := setG w.globals rpG (.i32 (ofN (c.rEnd - 8 * (s.rstack.length + 1)))) } := by
    simp [execL, stepI, bin32, hs.rp, i32c, i64c, hsub, setG, ofN_toNat hlt, hm', hst]
    exact ⟨rfl, rfl⟩
  have rl := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c, i64c]) el
  refine ⟨_, ?_, (push_rs hg hs hfit hm').setStack _, rfl⟩
  simpa [lowerInstr] using run_append _ (ovfR_pass (fs := fs) hg hs hfit) rl

theorem sim_call_ovf (n k t : Nat) (hg : Geom c) (hs : Rel0 c s w)
    (h : ¬ c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd) :
    Run fs (lowerInstr c.layout n k (.call t)) w (.exit 6) := by
  have := run_append_abrupt (fs := fs) _ (ovfR_trap hg hs h)
    (b := [.globalGet rpG, i32c 8, .i32sub, .globalSet rpG, .globalGet rpG, i64c (k + 1), .i64store 0,
      i32c (min t n)]) trivial
  simpa [lowerInstr] using this

theorem ret_split (L : Layout) : lowerInstr L n k .ret =
    [.globalGet rpG, i32c L.rEnd, .i32eq] ++ [.ite [.exitTrap 5]] ++
      [.globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG] := rfl

theorem sim_ret (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : Nat}
    {rs : List Nat} (hr : s.rstack = a :: rs) (ha : a < 2 ^ 32) :
    Sim1 c fs (lowerInstr c.layout n k .ret) { s with rstack := rs } w a := by
  have hcap := hs.capR
  rw [hr] at hcap
  simp only [List.length_cons] at hcap
  have hrE := hg.rEnd_le
  have hsz := hg.msize_lt
  have hX : c.rEnd - 8 * (rs.length + 1) < 2 ^ 32 := by omega
  have hE : c.rEnd < 2 ^ 32 := by omega
  have hrp : w.globals rpG = .i32 (ofN (c.rEnd - 8 * (rs.length + 1))) := by
    have := hs.rp; rw [hr] at this; simpa using this
  have hne : ofN (c.rEnd - 8 * (rs.length + 1)) ≠ ofN c.rEnd := by
    intro h; have := ofN_inj hX hE h; omega
  have hr0 : w.mem.read64 (c.rEnd - 8 * (rs.length + 1)) = some (BitVec.ofNat 64 a) := by
    have := hs.rs 0 a (by simp [hr]); rw [hr] at this; simpa using this
  have e1 : execL [.globalGet rpG, i32c c.layout.rEnd, .i32eq] w = some { w with stack := [.i32 0#32] } := by
    simp [execL, stepI, hrp, i32c, Cfg.layout, bool32, hst]
    exact hne
  have r1 := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c]) e1
  have r2 := run_ite_false (fs := fs) (thn := [.exitTrap 5]) (w := { w with stack := [.i32 0#32] }) (r := []) rfl
  have hsp8 : ofN (c.rEnd - 8 * (rs.length + 1)) + 8#32 = ofN (c.rEnd - 8 * rs.length) := by
    rw [show (8#32 : W32) = ofN 8 from rfl, ofN_add]; congr 1; omega
  have hwrap : BitVec.setWidth 32 (BitVec.ofNat 64 a) = ofN a := by
    apply BitVec.eq_of_toNat_eq
    have : a < 2 ^ 64 := by omega
    simp [ofN, BitVec.toNat_setWidth, Nat.mod_eq_of_lt this]
  have e3 : execL [.globalGet rpG, .i64load 0, .i32wrap, .globalGet rpG, i32c 8, .i32add, .globalSet rpG]
      { { w with stack := [.i32 0#32] } with stack := [] } =
      some { w with stack := [.i32 (ofN a)], globals := setG w.globals rpG (.i32 (ofN (c.rEnd - 8 * rs.length))) } := by
    simp [execL, stepI, bin32, hrp, ofN_toNat hX, hr0, i32c, hsp8, hwrap]
    unfold setG; rfl
  have r3 := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c]) e3
  refine ⟨_, ?_, (pop_rs hs hr).setStack _, rfl⟩
  rw [ret_split]
  exact run_append _ (run_append _ r1 r2) r3

theorem sim_ret_trap (n k : Nat) (hs : Rel0 c s w) (hst : w.stack = []) (hr : s.rstack = []) :
    Run fs (lowerInstr c.layout n k .ret) w (.exit 5) := by
  have hrp : w.globals rpG = .i32 (ofN c.rEnd) := by
    have := hs.rp; rw [hr] at this; simpa using this
  have e1 : execL [.globalGet rpG, i32c c.layout.rEnd, .i32eq] w = some { w with stack := [.i32 1#32] } := by
    simp [execL, stepI, hrp, i32c, Cfg.layout, bool32, hst, ofN]
  have r1 := run_of_execL (fs := fs) (by simp [WI.isCtl, i32c]) e1
  have r2 := run_ite_exit (fs := fs) (w := { w with stack := [.i32 1#32] }) (r := []) (c := 1#32) (k := 5)
    rfl (by decide)
  rw [ret_split]
  exact run_append_abrupt _ (run_append _ r1 r2) trivial

theorem sim_halt (n k : Nat) : Run fs (lowerInstr c.layout n k .halt) w (.halted w) :=
  .consAbrupt .exitHalt trivial

theorem sim_stub : Run fs [.exitTrap 4] w (.exit 4) :=
  .consAbrupt .exitTrap trivial

end Sim

end Wasm
end WordDialect
