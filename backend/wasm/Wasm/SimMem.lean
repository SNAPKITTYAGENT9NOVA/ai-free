import Wasm.SimStack

/-!
# Wasm.SimMem

`load` and `store`: the bounds check `memAddr` (address below `M`, else exit 2 = `badAddress`),
the byte address `mb + 8a`, and the simulation of both instructions and of their traps.
-/

namespace WordDialect
namespace Wasm

section Sim

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs}

theorem memAddr_split (L : Layout) : memAddr L =
    (ldS 0 ++ [.i64const (BitVec.ofNat 64 L.M), .i64geu]) ++ [.ite [.exitTrap 2]] ++
      (ldS 0 ++ [.i32wrap, i32c 3, .i32shl, i32c L.mb, .i32add]) := by
  simp [memAddr, List.append_assoc]

theorem M_lt (hg : Geom c) : c.M < 2 ^ 32 := by
  have := hg.mb_le; have := hg.msize_lt; omega

theorem geu_M (hg : Geom c) (a : W) :
    (BitVec.ofNat 64 c.M).ule a = decide (c.M ≤ a.toNat) := by
  have hM := M_lt hg
  have : c.M % 2 ^ 64 = c.M := Nat.mod_eq_of_lt (by omega)
  simp [BitVec.ule_eq_decide, BitVec.toNat_ofNat, this]

theorem addr_eq (hg : Geom c) {a : W} (ha : a.toNat < c.M) :
    BitVec.setWidth 32 a <<< 3 + BitVec.ofNat 32 c.mb = ofN (c.mb + 8 * a.toNat) := by
  have hmb := hg.mb_le; have hsz := hg.msize_lt
  apply BitVec.eq_of_toNat_eq
  have h1 : a.toNat < 2 ^ 32 := by omega
  have h2 : a.toNat * 8 < 2 ^ 32 := by omega
  have h3 : c.mb < 2 ^ 32 := by omega
  have h4 : c.mb + 8 * a.toNat < 2 ^ 32 := by omega
  simp [ofN, BitVec.toNat_add, BitVec.toNat_shiftLeft, BitVec.toNat_setWidth, Nat.shiftLeft_eq,
    Nat.mod_eq_of_lt h1, Nat.mod_eq_of_lt h2, Nat.mod_eq_of_lt h3, Nat.mod_eq_of_lt h4]
  omega

/-- In-bounds address: `memAddr` leaves the byte address `mb + 8a` on the operand stack. -/
theorem memAddr_ok (hg : Geom c) {u : WState} {sp : Nat} (hsp : u.globals spG = .i32 (ofN sp))
    (hX : sp < 2 ^ 32) {a : W} (hr : u.mem.read64 sp = some a) (ha : a.toNat < c.M) :
    Run fs (memAddr c.layout) u (.normal { u with stack := .i32 (ofN (c.mb + 8 * a.toNat)) :: u.stack }) := by
  have hlt : ¬ c.M ≤ a.toNat := by omega
  have e1 : execL (ldS 0 ++ [.i64const (BitVec.ofNat 64 c.layout.M), .i64geu]) u =
      some { u with stack := .i32 0#32 :: u.stack } := by
    simp [ldS, execL, stepI, cmp64, hsp, ofN_toNat hX, hr, Cfg.layout, geu_M hg, hlt, bool32]
  have r1 := run_of_execL (fs := fs) (by simp [ldS, WI.isCtl]) e1
  have r2 := run_ite_false (fs := fs) (thn := [.exitTrap 2]) (w := { u with stack := .i32 0#32 :: u.stack })
    (r := u.stack) rfl
  have e3 : execL (ldS 0 ++ [.i32wrap, i32c 3, .i32shl, i32c c.layout.mb, .i32add]) { u with stack := u.stack } =
      some { u with stack := .i32 (ofN (c.mb + 8 * a.toNat)) :: u.stack } := by
    simp [ldS, execL, stepI, bin32, hsp, ofN_toNat hX, hr, i32c, Cfg.layout, addr_eq hg ha]
  have r3 := run_of_execL (fs := fs) (by simp [ldS, WI.isCtl, i32c]) e3
  rw [memAddr_split]
  exact run_append _ (run_append _ r1 r2) r3

/-- Out-of-bounds address: `memAddr` exits with code 2 (`badAddress`). -/
theorem memAddr_trap (hg : Geom c) {u : WState} {sp : Nat} (hsp : u.globals spG = .i32 (ofN sp))
    (hX : sp < 2 ^ 32) {a : W} (hr : u.mem.read64 sp = some a) (ha : c.M ≤ a.toNat) :
    Run fs (memAddr c.layout) u (.exit 2) := by
  have e1 : execL (ldS 0 ++ [.i64const (BitVec.ofNat 64 c.layout.M), .i64geu]) u =
      some { u with stack := .i32 1#32 :: u.stack } := by
    simp [ldS, execL, stepI, cmp64, hsp, ofN_toNat hX, hr, Cfg.layout, geu_M hg, ha, bool32]
  have r1 := run_of_execL (fs := fs) (by simp [ldS, WI.isCtl]) e1
  have r2 := run_ite_exit (fs := fs) (w := { u with stack := .i32 1#32 :: u.stack }) (r := u.stack)
    (c := 1#32) (k := 2) rfl (by decide)
  rw [memAddr_split]
  exact run_append_abrupt _ (run_append _ r1 r2) trivial

/-- `valid a` is exactly `a < M`. -/
theorem valid_iff (hs : Rel0 c s w) (a : W) : s.mem.valid a = true ↔ a.toNat < c.M := by
  rw [hs.irvalid a]; simp

theorem mem_cell (hs : Rel0 c s w) {a : W} (ha : a.toNat < c.M) :
    w.mem.read64 (c.mb + 8 * a.toNat) = some (s.mem.cell a) := by
  have := hs.mem a.toNat ha
  rwa [BitVec.ofNat_toNat, BitVec.setWidth_eq] at this

theorem addr_lt (hg : Geom c) {a : W} (ha : a.toNat < c.M) : c.mb + 8 * a.toNat < 2 ^ 32 := by
  have := hg.mb_le; have := hg.msize_lt; omega

theorem sim_load (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a : W} {d : List W}
    (hd : s.dstack = a :: d) (ha : a.toNat < c.M) :
    Sim1 c fs (lowerInstr c.layout n k .load) { s with dstack := s.mem.cell a :: d } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 1 := by simp [hd]
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.dEnd - 8 * s.dstack.length) (s.mem.cell a) = some m' :=
    write64_some (by rw [hs.size]; have := hg.dEnd_le; omega)
  have hA := addr_lt hg ha
  have rg : Run fs [.globalGet spG] w
      (.normal { w with stack := .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack }) :=
    run_of_execL (by simp [WI.isCtl]) (by simp [execL, stepI, hs.sp])
  have rm := memAddr_ok (fs := fs) hg (u := { w with stack := .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack })
    hs.sp hX hr0 ha
  have el : execL [.i64load 0, .i64store 0]
      { { w with stack := .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } with
        stack := .i32 (ofN (c.mb + 8 * a.toNat)) ::
          ({ w with stack := .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack } : WState).stack } =
      some { w with mem := m' } := by
    simp [execL, stepI, ofN_toNat hA, ofN_toNat hX, mem_cell hs ha, hm']
  have rl := run_of_execL (fs := fs) (by simp [WI.isCtl]) el
  have hrel := wr_stack hg hs (j := 0) (by omega) (v := s.mem.cell a) (m' := m') (by simpa using hm')
  have e : s.dstack.set 0 (s.mem.cell a) = s.mem.cell a :: d := by simp [hd]
  rw [e] at hrel
  refine ⟨{ w with mem := m', stack := [.i32 (ofN (k + 1))] }, ?_, hrel.setStack _, rfl⟩
  have := run_append _ (uf1_pass (fs := fs) hg hs hd)
    (run_append _ rg (run_append _ rm (run_append _ rl (run_finish (fs := fs) (k + 1)))))
  simpa [lowerInstr, List.append_assoc, hst] using this

theorem sim_load_trap (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) {a : W} {d : List W}
    (hd : s.dstack = a :: d) (ha : c.M ≤ a.toNat) :
    Run fs (lowerInstr c.layout n k .load) w (.exit 2) := by
  have hX := sp_lt hg hs
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  have rg : Run fs [.globalGet spG] w
      (.normal { w with stack := .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack }) :=
    run_of_execL (by simp [WI.isCtl]) (by simp [execL, stepI, hs.sp])
  have rm := memAddr_trap (fs := fs) hg (u := { w with stack := .i32 (ofN (c.dEnd - 8 * s.dstack.length)) :: w.stack })
    hs.sp hX hr0 ha
  have := run_append _ (uf1_pass (fs := fs) hg hs hd)
    (run_append _ rg (run_append_abrupt _ rm (b := [.i64load 0, .i64store 0] ++ [i32c (k + 1)]) trivial))
  simpa [lowerInstr, List.append_assoc] using this

theorem sim_store (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = []) {a v : W}
    {d : List W} (hd : s.dstack = a :: v :: d) {im : WordDialect.Memory 64}
    (hv : s.mem.write? a v = some im) :
    Sim1 c fs (lowerInstr c.layout n k .store) { s with dstack := d, mem := im } w (k + 1) := by
  have hlen : s.dstack.length = d.length + 2 := by simp [hd]
  have hX := sp_lt hg hs
  have hcap := hs.capD
  have hvalid : s.mem.valid a = true := by
    by_cases hh : s.mem.valid a = true
    · exact hh
    · have := (Memory.write?_none_iff s.mem a v).mpr (by simpa using hh); rw [hv] at this; simp at this
  have ha : a.toNat < c.M := (valid_iff hs a).mp hvalid
  have hA := addr_lt hg ha
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  have hr1 : w.mem.read64 (c.dEnd - 8 * s.dstack.length + 8) = some v := by
    have := hs.stack 1 v (by simp [hd]); simpa using this
  obtain ⟨m', hm'⟩ : ∃ m', w.mem.write64 (c.mb + 8 * a.toNat) v = some m' :=
    write64_some (by rw [hs.size]; have := hg.mb_le; omega)
  have rm := memAddr_ok (fs := fs) hg (u := w) hs.sp hX hr0 ha
  have hsp16 : ofN (c.dEnd - 8 * s.dstack.length) + 16#32 = ofN (c.dEnd - 8 * s.dstack.length + 16) :=
    ofN_add _ _
  have el : execL (ldS 8 ++ [.i64store 0] ++ spAdd 16)
      { w with stack := .i32 (ofN (c.mb + 8 * a.toNat)) :: w.stack } =
      some { w with mem := m', globals := setG w.globals spG (.i32 (ofN (c.dEnd - 8 * s.dstack.length + 16))) } := by
    simp [ldS, spAdd, execL, stepI, bin32, hs.sp, ofN_toNat hX, ofN_toNat hA, hr1, hm', i32c, hst, hsp16]
    unfold setG
    rfl
  have rl := run_of_execL (fs := fs) (by simp [ldS, spAdd, WI.isCtl, i32c]) el
  have hrel1 := wr_mem hg hs hv hm'
  have hrel2 := adj_sp hg hrel1 (n := 2) (by simp [hd])
  have e3 : ({ { s with mem := im } with dstack := ({ s with mem := im } : State 64).dstack.drop 2 } : State 64) =
      { s with dstack := d, mem := im } := by
    simp [hd]
  rw [e3] at hrel2
  have e2 : c.dEnd - 8 * s.dstack.length + 16 = c.dEnd - 8 * (s.dstack.length - 2) := by omega
  rw [e2] at rl
  refine ⟨_, ?_, hrel2.setStack [.i32 (ofN (k + 1))], rfl⟩
  have := run_append _ (uf2_pass (fs := fs) hg hs hd)
    (run_append _ rm (run_append _ rl (run_finish (fs := fs) (k + 1))))
  simpa [lowerInstr, List.append_assoc, hst] using this

theorem sim_store_trap (n k : Nat) (hg : Geom c) (hs : Rel0 c s w) {a v : W} {d : List W}
    (hd : s.dstack = a :: v :: d) (ha : c.M ≤ a.toNat) :
    Run fs (lowerInstr c.layout n k .store) w (.exit 2) := by
  have hX := sp_lt hg hs
  have hr0 : w.mem.read64 (c.dEnd - 8 * s.dstack.length) = some a := by
    have := hs.stack 0 a (by simp [hd]); simpa using this
  have rm := memAddr_trap (fs := fs) hg (u := w) hs.sp hX hr0 ha
  have := run_append _ (uf2_pass (fs := fs) hg hs hd)
    (run_append_abrupt _ rm (b := ldS 8 ++ [.i64store 0] ++ spAdd 16 ++ [i32c (k + 1)]) trivial)
  simpa [lowerInstr, List.append_assoc] using this

end Sim

end Wasm
end WordDialect
