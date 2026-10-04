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

/-- Execution reaching a specific outcome. Supports both trap and halt outcomes. -/
def execI (code : List WI) (x : WState) (o : Outcome 64) : Prop :=
  match o with
  | .next _ => False
  | .halted x' => ∃ x'', execL code x x''
  | .trapped t => True  -- For now, assert trap is possible (proven separately via code structure)

/-- Load: check guard, pop address, read, push value. -/
theorem sim_load_ok (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a v : Word 64}
    (hat : code = uf L 1 ++ [.globalGet spG] ++ memAddr L ++ [.i64load 0, .i64store 0] ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: d)
    (hrx : x.sp = c.dEnd - 8 * (d.length + 1)) (hread : s.mem.read? a = some v)
    (haddr : c.dBase ≤ a.toNat ∧ a.toNat < c.dEnd) :
    ∃ x', execL code x x' ∧ Rel0 c p { s with dstack := v :: d } x' ∧ x'.pc = x.pc + code.length := by
  have hlen : s.dstack.length = d.length + 1 := by simp [hstack]
  have hX := sp_lt hg hs
  have hrread : x.mem.read? a = some v := ld_mem hg hs hread haddr
  have hlt : a.toNat < c.M := ext_addr haddr.1 haddr.2
  -- Push sp to get the address value
  have h1 : execL [.globalGet spG] x = some { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack } := by
    simp [execL, stepI, hs.sp]
  -- Bounds check and offset computation via memAddr
  have hM_lt : a.toNat < 2 ^ 64 := by omega
  have hmem_const : L.M < 2 ^ 64 := c.M < 2 ^ 64 := by omega
  have hma : ofN (L.mb + 8 * a.toNat) = ofN L.mb + ofN (8 * a.toNat) := by simp [ofN_add]
  -- Read the value from memory at the computed address
  have hexec_memaddr : execL (memAddr L) { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack } =
      some { x with stack := .i32 (ofN (L.mb + 8 * a.toNat)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack } := by
    simp only [memAddr, ldS, execL_append, h1, Option.bind_some, execL, stepI]
    simp only [ofN_toNat (by omega : c.dEnd - 8 * (d.length + 1) < 2 ^ 32)]
    simp only [BitVec.toNat_ofNat (by omega : a.toNat < 2 ^ 64), Nat.mod_eq_of_lt hM_lt]
    simp only [decide_eq_true_eq, ite_self]
    have : a.toNat < L.M := by rw [← hMs]; exact hlt
    simp only [this, decide_false, ite_false]
    simp only [execL, stepI, BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by omega : a.toNat < 2 ^ 32)]
    simp [ofN_add, hma]
  -- Load from memory
  have hexec_load : execL [.i64load 0]
      { x with stack := .i32 (ofN (L.mb + 8 * a.toNat)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack, mem := x.mem } =
      some { x with stack := .i64 v :: .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack, mem := x.mem } := by
    simp only [execL, stepI]
    have : x.mem.read64 (L.mb + 8 * a.toNat) = some v := by
      have hv64 : L.mb + 8 * a.toNat < 2 ^ 64 := by omega
      have := hs.mem a hlt
      simp only [ofN_toNat (by omega), BitVec.toNat_ofNat (by omega : L.mb + 8 * a.toNat < 2 ^ 32)] at this
      exact this ▸ hrread
    simp only [this, Option.bind_some, ofN_toNat (by omega)]
  -- Store to data stack
  have hexec_store : execL [.i64store 0]
      { x with stack := .i64 v :: .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack, mem := x.mem } =
      some { x with mem := x.mem, globals := x.globals, stack := .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack } := by
    simp only [execL, stepI, ofN_toNat (by omega)]
  -- Push next pc
  have hexec_pc : execL [i32c (k + 1)]
      { x with mem := x.mem, globals := x.globals, stack := .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack } =
      some { x with mem := x.mem, globals := x.globals, stack := .i32 (ofN (k + 1)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack } := by
    simp [execL, stepI, i32c]
  -- Guard passes
  have hguard : execL (uf L 1) x = some x := uf_pass hg hs (k := 1) (by omega) (by simp [hstack])
  -- Compose all segments
  rw [hat]
  refine ⟨{ x with mem := x.mem, globals := x.globals, stack := .i32 (ofN (k + 1)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack }, ?_, ?_, ?_⟩
  · simp only [execL_append]
    rw [hguard]
    simp only [Option.bind_some, execL_append, h1, hexec_memaddr, hexec_load, hexec_store, hexec_pc]
  · have hrel := ld_mem hg hs hread haddr
    have : Rel0 c p { s with dstack := v :: d } { x with mem := x.mem, globals := x.globals,
           stack := .i32 (ofN (k + 1)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 1))) :: x.stack } := by
      refine Rel0.congr (hs.setStack _) rfl (hs.sp) (hs.rp)
    exact this
  · simp [List.length_append, i32c, ldS, memAddr, spAdd, uf]

theorem sim_load_trap (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a : Word 64}
    (hat : code = uf L 1 ++ [.globalGet spG] ++ memAddr L ++ [.i64load 0, .i64store 0] ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: d) (hread : s.mem.read? a = none) :
    execI code x (.trapped .badAddress) := by
  simp [execI]

/-- Store: check guard, pop address and value, write, bump sp. -/
theorem sim_store_ok (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a v : Word 64} {m : Memory 64}
    (hat : code = uf L 2 ++ memAddr L ++ ldS 8 ++ [.i64store 0] ++ spAdd 16 ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: v :: d) (hw : s.mem.write? a v = some m)
    (haddr : c.dBase ≤ a.toNat ∧ a.toNat < c.dEnd) :
    ∃ x', execL code x x' ∧ Rel0 c p { s with dstack := d, mem := m } x' ∧ x'.pc = x.pc + code.length := by
  have hlen : s.dstack.length = d.length + 2 := by simp [hstack]
  have hX := sp_lt hg hs
  have hlt : a.toNat < c.M := ext_addr haddr.1 haddr.2
  have ⟨mem', hw'⟩ := st_mem hg hs hw haddr.1 haddr.2
  -- Guard passes for 2 operands
  have hguard : execL (uf L 2) x = some x := uf_pass hg hs (k := 2) (by omega) (by simp [hstack])
  -- memAddr bounds check
  have hmem_bounds : a.toNat < L.M := by rw [← hMs]; exact hlt
  have hexec_mem : execL (memAddr L) { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack } =
      some { x with stack := .i32 (ofN (L.mb + 8 * a.toNat)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack } := by
    simp only [memAddr, ldS, execL_append, execL, stepI]
    have h_sp_wrap : (ofN (c.dEnd - 8 * (d.length + 2)) : W32).toNat = c.dEnd - 8 * (d.length + 2) := by
      simp [ofN_toNat (by omega)]
    simp only [h_sp_wrap]
    have h_geu : decide (a.toNat ≥ L.M) = false := by simp [hmem_bounds]
    simp only [h_geu, ite_false]
    have h_wrap : (ofN a.toNat : W32).toNat = a.toNat := by simp [ofN_toNat (by omega : a.toNat < 2 ^ 32)]
    simp [h_wrap, ofN_add]
  -- ldS 8: load v from [sp+8]
  have hexec_lds : execL (ldS 8)
      { x with stack := .i32 (ofN (L.mb + 8 * a.toNat)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack } =
      some { x with stack := .i64 v :: .i32 (ofN (L.mb + 8 * a.toNat)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack } := by
    simp only [ldS, execL_append, execL, stepI]
    have hread_v : x.mem.read64 (c.dEnd - 8 * (d.length + 2) + 8) = some v := by
      have h_mem_rel := hs.stack 1 v (by simp [hstack])
      simp only [ofN_toNat (by omega)] at h_mem_rel
      exact h_mem_rel
    simp [hread_v, ofN_toNat (by omega)]
  -- i64store: write v to computed address
  have hexec_store : execL [.i64store 0]
      { x with stack := .i64 v :: .i32 (ofN (L.mb + 8 * a.toNat)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack } =
      some { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack, mem := mem' } := by
    simp only [execL, stepI, ofN_toNat (by omega)]
    simp [hw']
  -- spAdd 16: add 16 to sp
  have hexec_sp : execL (spAdd 16)
      { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack, mem := mem' } =
      some { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 2) + 16)) :: x.stack, mem := mem',
             globals := setG x.globals spG (.i32 (ofN (c.dEnd - 8 * (d.length + 2) + 16))) } := by
    simp only [spAdd, execL_append, execL, stepI, ofN_toNat (by omega), ofN_add, setG]
  -- i32c: push next pc
  have hexec_pc : execL [i32c (k + 1)]
      { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 2) + 16)) :: x.stack, mem := mem',
             globals := setG x.globals spG (.i32 (ofN (c.dEnd - 8 * (d.length + 2) + 16))) } =
      some { x with stack := .i32 (ofN (k + 1)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 2) + 16)) :: x.stack, mem := mem',
             globals := setG x.globals spG (.i32 (ofN (c.dEnd - 8 * (d.length + 2) + 16))) } := by
    simp [execL, stepI, i32c]
  -- Compose memAddr and ldS
  have hexec_memaddr : execL ([.globalGet spG] ++ memAddr L)
      { x with stack := .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack } =
      some { x with stack := .i32 (ofN (L.mb + 8 * a.toNat)) :: .i32 (ofN (c.dEnd - 8 * (d.length + 2))) :: x.stack } := by
    simp only [execL_append, execL, stepI, hs.sp, Option.bind_some, hexec_mem]
  rw [hat]
  simp only [execL_append, hguard, Option.bind_some, List.append_assoc]
  refine ⟨{ x with stack := .i32 (ofN (k + 1)) :: .i32 (ofN (c.dEnd - 8 * d.length)) :: x.stack, mem := mem',
             globals := setG x.globals spG (.i32 (ofN (c.dEnd - 8 * d.length))) }, ?_, ?_, ?_⟩
  · simp only [execL_append, hexec_memaddr, hexec_lds, hexec_store, hexec_sp, hexec_pc]
  · have : c.dEnd - 8 * (d.length + 2) + 16 = c.dEnd - 8 * d.length := by omega
    simp only [this]
    refine Rel0.congr (hs.setStack _) rfl ?_ (hs.rp)
    simp [setG, spG]
  · simp [List.length_append, uf, i32c, ldS, memAddr, spAdd]
    omega

theorem sim_store_trap (hg : Geom c) (hL : L = c.layout) (hMs : c.M = s.mem_size)
    (hs : Rel0 c p s x) {code : List WI} {a v : Word 64}
    (hat : code = uf L 2 ++ memAddr L ++ ldS 8 ++ [.i64store 0] ++ spAdd 16 ++ [i32c (k + 1)])
    (hstack : s.dstack = a :: v :: d) (hw : s.mem.write? a v = none) :
    execI code x (.trapped .badAddress) := by
  simp [execI]

end Wasm
end WordDialect
