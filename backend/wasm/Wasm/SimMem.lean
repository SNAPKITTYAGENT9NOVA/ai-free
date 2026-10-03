import Wasm.SimStack

/-!
# Wasm.SimMem

Memory operations (load, store) with address bounds checking and trap handling.
-/

namespace WordDialect
namespace Wasm

theorem ext_addr {c : Cfg} {s : State 64} {a : Word 64} (ha : c.dBase ≤ a.toNat) (hle : a.toNat < c.dEnd) :
    a.toNat < c.M := by omega

theorem ld_mem (hg : Geom c) (hs : Rel0 c p s x) {a v : Word 64} (hr : s.mem.read? a = some v) :
    c.dBase ≤ a.toNat ∧ a.toNat < c.dEnd → x.mem.read? a = some v := by
  intro ⟨hbase, hle⟩
  have hlt : a.toNat < c.M := ext_addr hbase hle
  exact hs.mem a hlt ▸ hr

theorem st_mem (hg : Geom c) (hs : Rel0 c p s x) {a v : Word 64} {m : Memory 64}
    (hw : s.mem.write? a v = some m) (hbase : c.dBase ≤ a.toNat) (hle : a.toNat < c.dEnd) :
    ∃ mem', x.mem.write? a v = some mem' ∧
      MemRel c mem' m := by
  have hlt : a.toNat < c.M := ext_addr hbase hle
  have hv : s.mem.valid a = true := (Memory.write?_some hw).1
  have hvalid : x.mem.valid a = true := hs.mem_valid a hlt ▸ hv
  have ⟨mem', hw'⟩ : ∃ m', x.mem.write? a v = some m' := by
    cases x.mem.write? a v with
    | none =>
      have := Memory.write?_none_iff x.mem a v
      simp only [hvalid, true_implies] at this
      exact absurd this (by simp [Memory.write?])
    | some m => exact ⟨m, rfl⟩
  refine ⟨mem', hw', ?_⟩
  intro a' ha'
  have hlt' : a' < c.M := ha'
  by_cases h : a' = a.toNat
  · subst h
    have : x.mem.read? a = some (x.mem.read a) := Memory.read?_getElem hvalid
    rw [← this]
    have hx := (Memory.read?_some (hs.mem a hlt)).2
    rw [← hx]
    simp only [Memory.cell_write_same hw']
    have hm := (Memory.read?_some hw).2
    rw [← hm]
    simp only [Memory.cell_write_same hw]
  · have : a' ≠ a.toNat := h
    rw [Memory.cell_write_other hw' (by simp [ofNat_eq_ofNat_iff]; omega)]
    simp only [ofNat_eq_ofNat_iff] at this
    have := hs.mem a' hlt'
    have := Memory.cell_write_other hw (by simp [ofNat_eq_ofNat_iff] at this; omega)
    simp only [ofNat_eq_ofNat_iff] at this ⊢
    exact this

/-- Load: check guard, pop address, read, push value. -/
theorem sim_load_ok (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a v : Word 64}
    (hat : code = uf L 1 ++ [.globalGet spG] ++ memAddr L ++ [.i64load 0, .i64store 0] ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: d)
    (hrx : x.sp = c.dEnd - 8 * (d.length + 1)) (hread : s.mem.read? a = some v)
    (haddr : c.dBase ≤ a.toNat ∧ a.toNat < c.dEnd) :
    ∃ x', execL code x x' ∧ Rel0 c p { s with dstack := v :: d } x' ∧ x'.pc = x.pc + code.length := by
  sorry

theorem sim_load_trap (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a : Word 64}
    (hat : code = uf L 1 ++ [.globalGet spG] ++ memAddr L ++ [.i64load 0, .i64store 0] ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: d) (hread : s.mem.read? a = none) :
    execI code x (.trapped .badAddress) := by
  sorry

/-- Store: check guard, pop address and value, write, bump sp. -/
theorem sim_store_ok (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a v : Word 64} {m : Memory 64}
    (hat : code = uf L 2 ++ memAddr L ++ ldS 8 ++ [.i64store 0] ++ spAdd 16 ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: v :: d) (hw : s.mem.write? a v = some m)
    (haddr : c.dBase ≤ a.toNat ∧ a.toNat < c.dEnd) :
    ∃ x', execL code x x' ∧ Rel0 c p { s with dstack := d, mem := m } x' ∧ x'.pc = x.pc + code.length := by
  sorry

theorem sim_store_trap (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a v : Word 64}
    (hat : code = uf L 2 ++ memAddr L ++ ldS 8 ++ [.i64store 0] ++ spAdd 16 ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: v :: d) (hw : s.mem.write? a v = none) :
    execI code x (.trapped .badAddress) := by
  sorry

end Wasm
end WordDialect
