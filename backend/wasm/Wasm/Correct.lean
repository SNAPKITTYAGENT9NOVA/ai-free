import Wasm.SimExec

/-!
# Wasm.Correct

Whole-program preservation for the WebAssembly backend. The module's start function is the
dispatch loop `loop { pc := call_indirect table[pc] ; br 0 }` over the function table
`funcsOf L p`. Running it from a state related to the IR state `s` reaches the outcome the IR
semantics reaches from `s`:

* IR `halted s'`  ⇒  the loop halts (`exitHalt`) in a state `w'` with `Rel0 c s' w'`, so the data
  stack, virtual registers, IR memory and return stack agree with `s'`;
* IR `trapped t`  ⇒  the loop exits with code `trapCode t`.

Every instruction that grows a stack checks for room and exits with code 6 when the stack is
full, so there are two forms of the theorem:

* `lowerProg_correct_or_overflow` has no capacity hypothesis: the module reaches the IR outcome as
  above, or it exits with code 6 (the run needed more stack than the target provides);
* `lowerProg_correct` additionally assumes the IR run stays within the capacities (`Fits` at every
  reachable state); then no guard fires and the module reaches exactly the IR outcome.

Hypotheses of both (all explicit):
* `Geom c`         the memory regions are disjoint and inside the 32-bit linear memory, and each
                   stack can hold at least one word;
* `hn`             the program has fewer than `2^32` instructions (function indices are `i32`);
* `RegsOk`         every `push r`/`pop r` names a register inside the register file.
-/

namespace WordDialect
namespace Wasm

/-- Every register index used by the program lies in the virtual register file. -/
def RegsOk (c : Cfg) (p : Prog 64) : Prop :=
  ∀ (k : Nat) (i : WordDialect.Instr 64), p[k]? = some i →
    ∀ r : Nat, (i = .push r ∨ i = .pop r) → r < c.nregs

def loopBody : List WI := [.globalGet pcG, .callIndirect, .globalSet pcG, .br 0]

theorem mainBody_eq : mainBody = [.loop loopBody] := rfl

/-- The relation at the top of the dispatch loop: operand stack empty, the `pc` global holding the
IR `pc` clamped to `n` (a jump past the end is clamped at lowering time), and every return index
within the program. -/
def RelD (c : Cfg) (n : Nat) (s : State 64) (w : WState) : Prop :=
  Rel0 c s w ∧ w.stack = [] ∧ w.globals pcG = .i32 (ofN (min s.pc n)) ∧ ∀ a ∈ s.rstack, a ≤ n

/-- One IR step, seen from the top of the dispatch loop. -/
def LoopSim (c : Cfg) (fs : Funcs) (n : Nat) (w : WState) : Outcome 64 → Prop
  | .next s' => ∃ w', RelD c n s' w' ∧
      ∀ r, RunI fs (.loop loopBody) w' r → RunI fs (.loop loopBody) w r
  | .halted s' => ∃ w', RunI fs (.loop loopBody) w (.halted w') ∧ Rel0 c s' w'
  | .trapped t => RunI fs (.loop loopBody) w (.exit (trapCode t))

/-- The final-outcome form, for the loop. -/
def Final (c : Cfg) (fs : Funcs) (w : WState) : Outcome 64 → Prop
  | .next _ => False
  | .halted s' => ∃ w', RunI fs (.loop loopBody) w (.halted w') ∧ Rel0 c s' w'
  | .trapped t => RunI fs (.loop loopBody) w (.exit (trapCode t))

/-- Exit code 6: a stack overflow guard fired. -/
def overflowCode : Nat := 6

/-- The final-outcome form, for the module's start function. -/
def FinalMain (c : Cfg) (fs : Funcs) (w : WState) : Outcome 64 → Prop
  | .next _ => False
  | .halted s' => ∃ w', Run fs mainBody w (.halted w') ∧ Rel0 c s' w'
  | .trapped t => Run fs mainBody w (.exit (trapCode t))

section Loop

variable {c : Cfg} {fs : Funcs} {w : WState}

theorem funcs_at (L : Layout) (p : Prog 64) {j : Nat} (hj : j ≤ p.length) :
    (funcsOf L p)[j]? = some (instrCode L p j) := by
  simp [funcsOf, List.getElem?_range (show j < p.length + 1 by omega)]

theorem rgetPc {m : Nat} (hpc : w.globals pcG = .i32 (ofN m)) :
    RunI fs (.globalGet pcG) w (.normal { w with stack := .i32 (ofN m) :: w.stack }) :=
  .simple rfl (by simp [stepI, hpc])

/-- The dispatched function returned the next index `v`: one loop iteration, then the loop again
from the updated state. -/
theorem loop_next {m : Nat} {code : List WI} (hst : w.stack = [])
    (hpc : w.globals pcG = .i32 (ofN m)) (hf : fs[(ofN m).toNat]? = some code) {w' : WState} {v : W32}
    (hrun : Run fs code { w with stack := [] } (.normal w')) (hst' : w'.stack = [.i32 v]) {r : Res}
    (hr : RunI fs (.loop loopBody)
      { w' with stack := [], globals := setG w'.globals pcG (.i32 v) } r) :
    RunI fs (.loop loopBody) w r := by
  have h2 : RunI fs .callIndirect { w with stack := .i32 (ofN m) :: w.stack }
      (.normal { w' with stack := [.i32 v] }) := by
    have := RunI.callNormal (fs := fs) (s := { w with stack := .i32 (ofN m) :: w.stack }) (r := [])
      (by simp [hst]) hf hrun hst'
    exact this
  have h3 : RunI fs (.globalSet pcG) { w' with stack := [.i32 v] }
      (.normal { w' with stack := [], globals := setG w'.globals pcG (.i32 v) }) :=
    .simple rfl rfl
  have hb : Run fs loopBody w (.br 0 { w' with stack := [], globals := setG w'.globals pcG (.i32 v) }) :=
    .consNormal (rgetPc hpc) (.consNormal h2 (.consNormal h3 (.consAbrupt .br trivial)))
  refine .loopBr0 hb ?_
  rw [hst]
  exact hr

/-- The dispatched function exited or halted: so does the loop. -/
theorem loop_abrupt {m : Nat} {code : List WI} (hpc : w.globals pcG = .i32 (ofN m))
    (hf : fs[(ofN m).toNat]? = some code) {res : Res}
    (hrun : Run fs code { w with stack := [] } res) (hres : (∃ k, res = .exit k) ∨ (∃ w', res = .halted w')) :
    RunI fs (.loop loopBody) w res := by
  have h2 := RunI.callAbrupt (fs := fs) (s := { w with stack := .i32 (ofN m) :: w.stack })
    (r := w.stack) rfl hf hrun (by rcases hres with ⟨k, rfl⟩ | ⟨w', rfl⟩ <;> trivial)
  rcases hres with ⟨k, rfl⟩ | ⟨w', rfl⟩
  · exact .loopExit (.consNormal (rgetPc hpc) (.consAbrupt h2 trivial))
  · exact .loopHalted (.consNormal (rgetPc hpc) (.consAbrupt h2 trivial))

theorem loop_step (hg : Geom c) {p : Prog 64} (hn : p.length < 2 ^ 32) (hreg : RegsOk c p)
    {s : State 64} (hs : RelD c p.length s w) :
    LoopSim c (funcsOf c.layout p) p.length w (step p s) ∨
      (¬ Fits c s ∧ RunI (funcsOf c.layout p) (.loop loopBody) w (.exit overflowCode)) := by
  obtain ⟨h0, hst, hpc, hrs⟩ := hs
  have hm : min s.pc p.length ≤ p.length := Nat.min_le_right _ _
  have hf : (funcsOf c.layout p)[(ofN (min s.pc p.length)).toNat]? =
      some (instrCode c.layout p (min s.pc p.length)) := by
    rw [ofN_toNat (show min s.pc p.length < 2 ^ 32 by omega)]
    exact funcs_at c.layout p hm
  by_cases hlt : s.pc < p.length
  · have hi : p[s.pc]? = some p[s.pc] := List.getElem?_eq_getElem hlt
    have hcode : instrCode c.layout p (min s.pc p.length) = lowerInstr c.layout p.length s.pc p[s.pc] := by
      rw [Nat.min_eq_left (Nat.le_of_lt hlt)]
      simp [instrCode, hi]
    rw [hcode] at hf
    have hss := sim_step (fs := funcsOf c.layout p) hg (h0.setStack []) rfl hn hrs hi
      (hreg s.pc _ hi)
    rw [step_of_fetch hi]
    generalize exec p[s.pc] s = o at hss ⊢
    rcases hss with hss | ⟨hnf, h6⟩
    rotate_left
    · exact .inr ⟨hnf, loop_abrupt hpc hf h6 (.inl ⟨6, rfl⟩)⟩
    left
    cases o with
    | next s' =>
      obtain ⟨hrs', w', hr, h0', hst'⟩ := hss
      refine ⟨{ w' with stack := [], globals := setG w'.globals pcG (.i32 (ofN (min s'.pc p.length))) },
        ⟨?_, rfl, by simp [setG], hrs'⟩, fun r hr' => loop_next hst hpc hf hr hst' hr'⟩
      exact Rel0.congr (h0'.setStack []) rfl (by simp [setG, pcG, spG]) (by simp [setG, pcG, rpG])
        (by simp [setG, pcG, apG])
    | halted s' =>
      obtain ⟨w', hr, h0'⟩ := hss
      exact ⟨w', loop_abrupt hpc hf hr (.inr ⟨w', rfl⟩), h0'⟩
    | trapped t =>
      exact loop_abrupt hpc hf hss (.inl ⟨_, rfl⟩)
  · rw [step_pc_oob (by omega)]
    have hcode : instrCode c.layout p (min s.pc p.length) = [.exitTrap 4] := by
      rw [Nat.min_eq_right (by omega)]
      simp [instrCode]
    rw [hcode] at hf
    exact .inl (loop_abrupt hpc hf sim_stub (.inl ⟨4, rfl⟩))

/-- Whole-program preservation, for the dispatch loop. -/
theorem loop_correct (hg : Geom c) {p : Prog 64} (hn : p.length < 2 ^ 32) (hreg : RegsOk c p)
    {s : State 64} {o : Outcome 64} (h : Exec p s o) :
    ∀ {w : WState}, RelD c p.length s w → (∀ s', Steps p s s' → Fits c s') →
      Final c (funcsOf c.layout p) w o := by
  induction h with
  | @halt s s' hst =>
    intro w hs hb
    have := loop_step hg hn hreg hs
    rw [hst] at this
    rcases this with this | ⟨hnf, _⟩
    · exact this
    · exact absurd (hb s .refl) hnf
  | @trap s t hst =>
    intro w hs hb
    have := loop_step hg hn hreg hs
    rw [hst] at this
    rcases this with this | ⟨hnf, _⟩
    · exact this
    · exact absurd (hb s .refl) hnf
  | @next s s' o hst _ ih =>
    intro w hs hb
    have := loop_step hg hn hreg hs
    rw [hst] at this
    rcases this with this | ⟨hnf, _⟩
    rotate_left
    · exact absurd (hb s .refl) hnf
    obtain ⟨w', hs', hlift⟩ := this
    have hih := ih hs' (fun s'' hss => hb s'' (.cons hst hss))
    cases o with
    | next _ => exact hih.elim
    | halted s2 =>
      obtain ⟨w'', hr, h0⟩ := hih
      exact ⟨w'', hlift _ hr, h0⟩
    | trapped t => exact hlift _ hih

/-- Whole-program preservation for the dispatch loop, with no capacity hypothesis: the IR outcome,
or exit 6 when a stack overflow guard fires. -/
theorem loop_correct_or_overflow (hg : Geom c) {p : Prog 64} (hn : p.length < 2 ^ 32)
    (hreg : RegsOk c p) {s : State 64} {o : Outcome 64} (h : Exec p s o) :
    ∀ {w : WState}, RelD c p.length s w →
      Final c (funcsOf c.layout p) w o ∨ RunI (funcsOf c.layout p) (.loop loopBody) w (.exit overflowCode) := by
  induction h with
  | @halt s s' hst =>
    intro w hs
    have := loop_step hg hn hreg hs
    rw [hst] at this
    rcases this with this | ⟨_, h6⟩
    · exact .inl this
    · exact .inr h6
  | @trap s t hst =>
    intro w hs
    have := loop_step hg hn hreg hs
    rw [hst] at this
    rcases this with this | ⟨_, h6⟩
    · exact .inl this
    · exact .inr h6
  | @next s s' o hst _ ih =>
    intro w hs
    have := loop_step hg hn hreg hs
    rw [hst] at this
    rcases this with ⟨w', hs', hlift⟩ | ⟨_, h6⟩
    · rcases ih hs' with hih | h6
      · left
        cases o with
        | next _ => exact hih.elim
        | halted s2 =>
          obtain ⟨w'', hr, h0⟩ := hih
          exact ⟨w'', hlift _ hr, h0⟩
        | trapped t => exact hlift _ hih
      · exact .inr (hlift _ h6)
    · exact .inr h6

theorem final_main {p : Prog 64} {o : Outcome 64} (hl : Final c fs w o) : FinalMain c fs w o := by
  cases o with
  | next _ => exact hl.elim
  | halted s' =>
    obtain ⟨w', hr, h0⟩ := hl
    refine ⟨w', ?_, h0⟩
    rw [mainBody_eq]
    exact .consAbrupt hr trivial
  | trapped t =>
    show Run _ mainBody w _
    rw [mainBody_eq]
    exact .consAbrupt hl trivial

/-- Whole-program preservation for the module's start function, with no capacity hypothesis: the
module reaches the IR outcome, or exits with code 6 because a stack was full. -/
theorem lowerProg_correct_or_overflow (hg : Geom c) {p : Prog 64} (hn : p.length < 2 ^ 32)
    (hreg : RegsOk c p) {s : State 64} {o : Outcome 64} (h : Exec p s o) (hs : RelD c p.length s w) :
    FinalMain c (funcsOf c.layout p) w o ∨ Run (funcsOf c.layout p) mainBody w (.exit overflowCode) := by
  rcases loop_correct_or_overflow hg hn hreg h hs with hl | h6
  · exact .inl (final_main (p := p) hl)
  · right
    rw [mainBody_eq]
    exact .consAbrupt h6 trivial

/-- Whole-program preservation, for the module's start function `mainBody`. When the IR run stays
within the stack capacities, no overflow guard fires and the outcome is exactly the IR's. -/
theorem lowerProg_correct (hg : Geom c) {p : Prog 64} (hn : p.length < 2 ^ 32) (hreg : RegsOk c p)
    {s : State 64} {o : Outcome 64} (h : Exec p s o) (hs : RelD c p.length s w)
    (hb : ∀ s', Steps p s s' → Fits c s') :
    FinalMain c (funcsOf c.layout p) w o := by
  exact final_main (p := p) (loop_correct hg hn hreg h hs hb)

end Loop

/-- The state the runtime establishes before the dispatch loop (`Wasm.Emit`): empty operand stack,
`pc = 0`, `sp = dEnd`, `rp = rEnd`, `ap = aEnd` (empty auxiliary stack), and the register file and IR memory regions holding the IR
state's initial contents. `RelD` then holds at entry, so `lowerProg_correct` applies. -/
theorem init_rel {c : Cfg} (n : Nat) {s0 : State 64} {w0 : WState} (hg : Geom c)
    (hpc0 : s0.pc = 0) (hd : s0.dstack = []) (hr : s0.rstack = [])
    (hst : w0.stack = []) (hpc : w0.globals pcG = .i32 (ofN 0))
    (hsp : w0.globals spG = .i32 (ofN c.dEnd)) (hrp : w0.globals rpG = .i32 (ofN c.rEnd))
    (ha : s0.astack = []) (hap : w0.globals apG = .i32 (ofN c.aEnd))
    (hregs : RegRel c w0.mem s0.regs) (hmem : MemRel c w0.mem s0.mem)
    (hiv : ∀ a : Word 64, s0.mem.valid a = decide (a.toNat < c.M)) (hsize : w0.mem.size = c.msize) :
    RelD c n s0 w0 :=
  ⟨{ sp := by simpa [hd] using hsp
     rp := by simpa [hr] using hrp
     stack := by intro i v h; simp [hd] at h
     regs := hregs
     mem := hmem
     rs := by intro i a h; simp [hr] at h
     irvalid := hiv
     size := hsize
     capD := by simp [hd]; exact hg.dBase_le
     capR := by simp [hr]; exact hg.rBase_le
     ap := by simpa [ha] using hap
     aux := by intro i v h; simp [ha] at h
     capA := by simp [ha]; have := hg.aBase_8; omega },
   hst, by simpa [hpc0] using hpc, by simp [hr]⟩

end Wasm
end WordDialect
