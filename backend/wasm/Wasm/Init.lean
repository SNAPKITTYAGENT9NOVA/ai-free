import Wasm.Correct
import Wasm.Emit

/-!
# Wasm.Init

The state a module emitted by `Wasm.Emit.program` starts in, and the end-to-end theorem from it.

`initState r` is what WebAssembly instantiation produces for the module's declarations, built
from the same constants and byte encoding the emitter prints:
* globals `$pc $sp $rp` (indices 0 1 2) initialised to `0`, `dEnd`, `rEnd`;
* linear memory of `pages` pages, all zero except the data segment at `mb`, which holds the IR
  memory image word by word (`byteOf`, little-endian);
* an empty operand stack.
That an engine instantiates the module this way is the WebAssembly specification's instantiation
rule; like the rest of the model, it is trusted and checked by `wasmw`.

`module_correct`: for every program and memory image that fit the runtime's fixed layout, running
the module's start function from `initState` reaches the IR outcome from `State.init`, or exits 6.
The only remaining hypotheses are about the program itself.
-/

namespace WordDialect
namespace Wasm
namespace Emit

/-- Byte `p` of linear memory at instantiation: the data segment, else zero. -/
def imageByte (img : List Nat) (mb p : Nat) : Nat :=
  if mb ≤ p ∧ p < mb + 8 * img.length then byteOf (img.getD ((p - mb) / 8) 0) ((p - mb) % 8) else 0

/-- Globals at instantiation: `$pc = 0`, `$sp = dEnd`, `$rp = rEnd`. -/
def initGlobals (r : Runtime) : Nat → Val := fun j =>
  if j = pcG then .i32 (ofN 0) else if j = spG then .i32 (ofN r.dEnd)
  else if j = rpG then .i32 (ofN r.rEnd) else .i32 0#32

/-- The machine state of the instantiated module, before its start function runs. -/
def initState (r : Runtime) : WState :=
  { stack := [], globals := initGlobals r, mem := { bytes := imageByte r.memImage r.mb, size := r.msize } }

/-- The runtime's fixed placement, as a `Cfg`. -/
def Runtime.cfg (r : Runtime) : Cfg :=
  { dEnd := r.dEnd, dBase := r.dBase, rEnd := r.rEnd, rBase := r.rBase, rf := r.rf,
    nregs := r.nregs, mb := r.mb, M := r.memImage.length, msize := r.msize }

theorem cfg_layout (r : Runtime) : r.cfg.layout = r.layout := rfl

/-- The register file and IR memory fit below the data stack. -/
def Runtime.Fits (r : Runtime) : Prop := 8 * (r.nregs + r.memImage.length) ≤ 0x10000 - 0x1000

theorem msize_eq (r : Runtime) : r.msize = 655360 := by
  simp [Runtime.msize, Runtime.pages, Runtime.rEnd, Runtime.rBase, Runtime.dEnd, Runtime.dBase]

/-- The runtime's layout satisfies `Geom` whenever the register file and memory image fit. -/
theorem geom (r : Runtime) (h : r.Fits) : Geom r.cfg := by
  have hm := msize_eq r
  simp only [Runtime.Fits] at h
  constructor <;>
    simp only [Runtime.cfg, hm, Runtime.dEnd, Runtime.dBase, Runtime.rEnd, Runtime.rBase, Runtime.rf,
      Runtime.mb] <;> omega

theorem rdBytes_shift (b : Nat → Nat) (a : Nat) :
    ∀ n, rdBytes b a n = rdBytes (fun q => b (a + q)) 0 n := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih => simp only [rdBytes, ih, Nat.zero_add]

theorem rdBytes_zero (a : Nat) : ∀ n, rdBytes (fun _ => 0) a n = 0 := by
  intro n; induction n with
  | zero => rfl
  | succ n ih => simp [rdBytes, ih]

/-- Reading word `a` of the data segment gives the image's word `a`. -/
theorem read_image (r : Runtime) (h : r.Fits) {a : Nat} (ha : a < r.memImage.length) :
    (initState r).mem.read64 (r.mb + 8 * a) = some (BitVec.ofNat 64 (r.memImage.getD a 0)) := by
  have hm := msize_eq r
  simp only [Runtime.Fits] at h
  have hsz : r.mb + 8 * a + 8 ≤ (initState r).mem.size := by
    simp only [initState, hm, Runtime.mb, Runtime.rf]; omega
  simp only [WMem.read64, hsz, ↓reduceIte]
  congr 1
  rw [rdBytes_shift]
  have hc : rdBytes (fun q => (initState r).mem.bytes (r.mb + 8 * a + q)) 0 8 =
      rdBytes (fun q => (r.memImage.getD a 0 / 256 ^ q) % 256) 0 8 := by
    apply rdBytes_congr
    intro i hi
    have h1 : r.mb ≤ r.mb + 8 * a + i ∧ r.mb + 8 * a + i < r.mb + 8 * r.memImage.length := by
      omega
    have h2 : (r.mb + 8 * a + i - r.mb) / 8 = a := by omega
    have h3 : (r.mb + 8 * a + i - r.mb) % 8 = i := by omega
    simp only [initState, imageByte, Nat.zero_add]
    simp only [h1, and_self, ↓reduceIte, h2, h3]
    rfl
  rw [hc, rdBytes_pow]
  apply BitVec.eq_of_toNat_eq
  simp [BitVec.toNat_ofNat, Nat.mod_mod_of_dvd]

/-- Outside the data segment, linear memory reads as zero. -/
theorem read_zero (r : Runtime) (h : r.Fits) {A : Nat} (hA : A + 8 ≤ r.mb) :
    (initState r).mem.read64 A = some 0#64 := by
  have hm := msize_eq r
  simp only [Runtime.Fits] at h
  have hsz : A + 8 ≤ (initState r).mem.size := by
    simp only [initState, hm, Runtime.mb, Runtime.rf] at hA ⊢; omega
  simp only [WMem.read64, hsz, ↓reduceIte]
  congr 1
  have hc : rdBytes (initState r).mem.bytes A 8 = rdBytes (fun _ => 0) A 8 := by
    apply rdBytes_congr
    intro i hi
    have : ¬ (r.mb ≤ A + i ∧ A + i < r.mb + 8 * r.memImage.length) := by omega
    simp [initState, imageByte, this]
  rw [hc, rdBytes_zero]

/-- The instantiated module is related to the IR's initial state: `RelD` holds at the top of the
dispatch loop, for any program length. -/
theorem init_relD (r : Runtime) (h : r.Fits) (n : Nat) :
    RelD r.cfg n (State.init (Memory.ofImage r.memImage)) (initState r) := by
  have hg := geom r h
  have hm := msize_eq r
  have hF := h
  simp only [Runtime.Fits] at hF
  refine init_rel n hg rfl rfl rfl rfl ?_ ?_ ?_ ?_ ?_ ?_ ?_
  · simp [initState, initGlobals]
  · simp [initState, initGlobals, Runtime.cfg, spG, pcG]
  · simp [initState, initGlobals, Runtime.cfg, spG, pcG, rpG]
  · intro reg hr
    have hr' : reg < r.nregs := hr
    have := read_zero r h (A := r.rf + 8 * reg) (by simp only [Runtime.mb]; omega)
    simpa [State.init, Runtime.cfg] using this
  · intro a ha
    have ha' : a < r.memImage.length := ha
    have hlt : a < 2 ^ 64 := by omega
    have := read_image r h ha'
    simpa [State.init, Memory.ofImage, Runtime.cfg, BitVec.toNat_ofNat, Nat.mod_eq_of_lt hlt] using this
  · intro a
    rfl
  · simp [initState, Runtime.cfg]

/-- End to end: the module `Wasm.Emit.program r p` declares, instantiated, runs its start function
to the outcome the IR reaches from `State.init` on the memory image, or exits 6 (stack
overflow). Hypotheses are only about the program: it fits the layout, it has fewer than `2^32`
instructions, and its register indices are in range. -/
theorem module_correct (r : Runtime) (p : Prog 64) (h : r.Fits) (hn : p.length < 2 ^ 32)
    (hreg : RegsOk r.cfg p) {o : Outcome 64} (hx : Exec p (State.init (Memory.ofImage r.memImage)) o) :
    FinalMain r.cfg (funcsOf r.layout p) (initState r) o ∨
      Run (funcsOf r.layout p) mainBody (initState r) (.exit overflowCode) := by
  rw [← cfg_layout]
  exact lowerProg_correct_or_overflow (geom r h) hn hreg hx (init_relD r h p.length)

end Emit
end Wasm
end WordDialect
