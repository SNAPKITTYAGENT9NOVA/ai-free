import X86.Correct
import X86.Emit

/-!
# X86.Init

The state the emitted binary starts the lowered code in, and the end-to-end theorem from it.

The runtime prologue (`Emit.prologue`) is four instructions:

    mov r12, rsp ; lea r13, [rip + irmem] ; lea r14, [rip + regfile] ; movabs r15, dEnd

`prologueCode` is the same sequence in the model, with each `lea` as a `movImm` of the address the
linker resolves `irmem` / `regfile` to (that `lea` computes this address is the trusted reading of
the instruction). Its effect is proved (`prologue_run`), not assumed.

What the operating system's loader provides at `_start` cannot be derived inside the model, so it
is stated once, explicitly, as `Loader.Holds`:
* `rsp` is the entry stack pointer `sp0`;
* the zero-filled `.bss` register file reads as zeros, and `.data` holds the IR memory image word by
  word (the `.quad` directives `Emit.epilogue` prints);
* the data stack (`.dstack`, placed at `dBase` by the linker), register file, IR memory and the
  `rcap` return-stack entries below `sp0` are addressable;
* the placement is disjoint and in range (`Geom`).

`binary_correct`: under those loader facts, after the prologue the lowered code reaches the IR
outcome from `State.init` on the memory image, or exits with `overflow`. Its other hypotheses are
only about the program.
-/

namespace WordDialect
namespace X86
namespace Emit

open Reg

/-- Addresses fixed by the linker and the loader for one run. -/
structure Loader where
  mb : Nat      -- link address of `irmem` (`.data`)
  rf : Nat      -- link address of `regfile` (`.bss`)
  sp0 : Nat     -- `rsp` at `_start`

/-- The runtime placement for one run, as a `Cfg`. -/
def cfgOf (r : Runtime) (ld : Loader) : Cfg :=
  { dEnd := r.dEnd, dBase := r.dBase, rf := ld.rf, nregs := r.nregs, mb := ld.mb,
    M := r.memImage.length, sp0 := ld.sp0, rcap := r.rcap }

/-- What the loader guarantees about the machine state `x0` at `_start`. -/
structure Loader.Holds (r : Runtime) (ld : Loader) (x0 : M) : Prop where
  rsp : x0.regs Reg.rsp = ofN ld.sp0
  geom : Geom (cfgOf r ld)
  valid : RegionsValid (cfgOf r ld) x0.mem.valid
  regfile : ∀ k, k < r.nregs → x0.mem.read? (ofN (ld.rf + 8 * k)) = some 0#64
  image : ∀ a, a < r.memImage.length →
    x0.mem.read? (ofN (ld.mb + 8 * a)) = some (BitVec.ofNat 64 (r.memImage.getD a 0))

/-- The prologue in the model. -/
def prologueCode (r : Runtime) (ld : Loader) : List (Instr Nat) :=
  [.movRR r12 rsp, .movImm r13 (ofN ld.mb), .movImm r14 (ofN ld.rf), .movImm r15 (ofN r.dEnd)]

/-- The machine state after the prologue, entering the lowered code at index 0. -/
def entryState (r : Runtime) (ld : Loader) (x0 : M) : M :=
  { ((((x0.mov r12 (x0.regs rsp)).mov r13 (ofN ld.mb)).mov r14 (ofN ld.rf)).mov r15 (ofN r.dEnd))
    with pc := 0 }

theorem prologue_run (r : Runtime) (ld : Loader) (x0 : M) :
    xseq (prologueCode r ld) x0 =
      .next { entryState r ld x0 with pc := x0.pc + 4 } := by
  simp [prologueCode, entryState, xseq, exec, M.mov, M.setReg, M.adv]

theorem isize_le (i : WordDialect.Instr 64) : isize i ≤ 17 := by
  cases i <;> simp [isize, ufSize]

theorem sum_isize_le : ∀ l : Prog 64, (l.map isize).sum ≤ 17 * l.length
  | [] => by simp
  | i :: l => by
    have := isize_le i
    have := sum_isize_le l
    simp only [List.map_cons, List.sum_cons, List.length_cons]
    omega

/-- Code indices are bounded by the program length. -/
theorem offs_lt {p : Prog 64} (h : 17 * p.length < 2 ^ 64) (k : Nat) : offs p k < 2 ^ 64 := by
  have h1 := sum_isize_le (p.take k)
  have h2 : (p.take k).length ≤ p.length := by rw [List.length_take]; omega
  simp only [offs]
  omega

theorem layout_ok (r : Runtime) (ld : Loader) :
    r.layout.dEnd = ofN (cfgOf r ld).dEnd ∧ r.layout.memSize = (cfgOf r ld).M ∧
      r.layout.dLim = ofN ((cfgOf r ld).dBase + 8) ∧ r.layout.rGap = ofN (8 * (cfgOf r ld).rcap - 16) :=
  ⟨rfl, rfl, rfl, rfl⟩

/-- After the prologue, the machine is related to the IR's initial state. -/
theorem entry_rel (r : Runtime) (ld : Loader) {x0 : M} (h : ld.Holds r x0) (p : Prog 64) :
    Rel (cfgOf r ld) p (State.init (Memory.ofImage r.memImage)) (entryState r ld x0) := by
  have hg := h.geom
  refine init_rel hg rfl rfl (by have := hg.rcap_ge; simp [cfgOf] at this ⊢; omega)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ (fun _ => rfl) ?_ (by simp [entryState, offs, State.init])
  · simp [entryState, M.mov, M.setReg, M.adv, cfgOf]
  · simp [entryState, M.mov, M.setReg, M.adv, cfgOf]
  · simp [entryState, M.mov, M.setReg, M.adv, cfgOf]
  · simp [entryState, M.mov, M.setReg, M.adv, cfgOf, h.rsp]
  · simp [entryState, M.mov, M.setReg, M.adv, cfgOf, h.rsp]
  · intro k hk
    simpa [entryState, M.mov, M.setReg, M.adv, State.init, cfgOf] using h.regfile k hk
  · intro a ha
    have ha' : a < r.memImage.length := ha
    have hlt : a < 2 ^ 64 := by
      have := hg.mb_lt; simp [cfgOf] at this ha ⊢; omega
    simpa [entryState, M.mov, M.setReg, M.adv, State.init, Memory.ofImage, cfgOf, ofN,
      BitVec.toNat_ofNat, Nat.mod_eq_of_lt hlt] using h.image a ha'
  · simpa [entryState, M.mov, M.setReg, M.adv] using h.valid

/-- End to end: under the loader facts, the prologue runs, and from there the lowered code reaches
the outcome the IR reaches from `State.init` on the memory image, or exits with `overflow` (exit
code 6). Program hypotheses: code indices fit in 64 bits and register indices are in range. -/
theorem binary_correct (r : Runtime) (ld : Loader) (p : Prog 64) (hlen : 17 * p.length < 2 ^ 64)
    (hreg : RegsOk (cfgOf r ld) p) {o : Outcome 64}
    (hx : Exec p (State.init (Memory.ofImage r.memImage)) o) {x0 : M} (h : ld.Holds r x0) :
    xseq (prologueCode r ld) x0 = .next { entryState r ld x0 with pc := x0.pc + 4 } ∧
      (Final (cfgOf r ld) p (lowerProg r.layout p) (entryState r ld x0) o ∨
        XExec (lowerProg r.layout p) (entryState r ld x0) .overflow) := by
  obtain ⟨hL, hMs, hLd, hLr⟩ := layout_ok r ld
  exact ⟨prologue_run r ld x0,
    lowerProg_correct_or_overflow h.geom hL hMs hLd hLr (offs_lt hlen) hreg hx (entry_rel r ld h p)⟩

end Emit
end X86
end WordDialect
