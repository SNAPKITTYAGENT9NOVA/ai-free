import RV.SimStep

/-!
# RV.Correct

Whole-program preservation: running the lowered RISC-V code from a state related to the IR state
`s` reaches the same final outcome the IR semantics reaches from `s`.

* IR `halted s'`  ⇒  the RISC-V code halts in a state `x'` with `Rel0 c p s' x'` (so the data
  stack, virtual registers, IR memory and return stack agree with `s'`);
* IR `trapped t`  ⇒  the RISC-V code exits with the same trap `t`.

Every instruction that grows the data stack or the auxiliary stack, and every `call`, checks for
room first and exits with `overflow` (exit code 6) when the stack is full, so there are two forms:

* `lowerProg_correct_or_overflow` has no capacity hypothesis: the RISC-V code reaches the IR outcome
  as above, or exits with `overflow` (the run needed more stack than the target provides);
* `lowerProg_correct` additionally assumes the IR run stays within the capacities (`Fits` at every
  reachable state); then no guard fires and the outcome is exactly the IR's.

Hypotheses of both (all explicit):
* `Geom c`            the memory regions (data stack, register file, IR memory, return stack,
                      auxiliary stack) are disjoint and within the 64-bit address space, the
                      data and auxiliary stacks hold at least one word each and the return stack
                      at least two;
* `L` matches `c`     data-stack end and limit, return-stack gap, auxiliary-stack end and limit,
                      and IR memory size;
* `hsz`               code indices fit in 64 bits;
* `RegsOk`            every `push r`/`pop r` names a register inside the register file.
-/

namespace WordDialect
namespace RV

open Reg

/-- Every register index used by the program lies in the virtual register file. -/
def RegsOk (c : Cfg) (p : Prog 64) : Prop :=
  ∀ (k : Nat) (i : WordDialect.Instr 64), p[k]? = some i → ∀ r : Nat, (i = WordDialect.Instr.push r ∨ i = WordDialect.Instr.pop r) → r < c.nregs

/-- The final-outcome form of `Sim`. -/
def Final (c : Cfg) (p : Prog 64) (code : List (Instr Nat)) (x : M) : Outcome 64 → Prop
  | .next _ => False
  | .halted s' => ∃ x', RExec code x (.halted x') ∧ Rel0 c p s' x'
  | .trapped t => RExec code x (.trapped t)

theorem offs_ge {p : Prog 64} {k : Nat} (h : p.length ≤ k) : offs p k = offs p p.length := by
  simp [offs, List.take_of_length_le h, List.take_length]

/-- One IR step from a related state: the bad-pc stub, or the dispatched instruction. -/
theorem step_sim {c : Cfg} {p : Prog 64} {L : Layout} (hg : Geom c)
    (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M) (hLd : L.dLim = ofN (c.dBase + 8))
    (hLr : L.rGap = ofN (8 * c.rcap - 16)) (hLa : L.aEnd = ofN c.aEnd)
    (hLal : L.aLim = ofN (c.aBase + 8)) (hsz : ∀ k, offs p k < 2 ^ 64) (hreg : RegsOk c p)
    {s : State 64} {x : M} (hs : Rel c p s x) :
    Sim c p (lowerProg L p) x (WordDialect.step p s) ∨
      (¬ Fits c s ∧ RExec (lowerProg L p) x .overflow) := by
  cases hi : p[s.pc]? with
  | none =>
    left
    have hst : WordDialect.step p s = .trapped .badPc := by simp [WordDialect.step, hi]
    rw [hst]
    have hge : p.length ≤ s.pc := by
      by_cases hh : s.pc < p.length
      · rw [List.getElem?_eq_getElem hh] at hi; simp at hi
      · omega
    obtain ⟨f0, _⟩ := lowerProg_stub L p
    have hpc : x.pc = offs p p.length := by rw [hs.2, offs_ge hge]
    exact RExec.trap (by rw [rstep_of_fetch (by rw [hpc]; exact f0)]; rfl)
  | some i =>
    have hst : WordDialect.step p s = WordDialect.exec i s := by simp [WordDialect.step, hi]
    rw [hst]
    exact sim_exec hg hL hMs hLd hLr hLa hLal hsz hs hi (fun r hr => hreg s.pc i hi r hr)

/-- Whole-program preservation, with no capacity hypothesis: the RISC-V code reaches the IR
outcome, or exits with `overflow` because a stack was full. -/
theorem lowerProg_correct_or_overflow {c : Cfg} {p : Prog 64} {L : Layout} (hg : Geom c)
    (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M) (hLd : L.dLim = ofN (c.dBase + 8))
    (hLr : L.rGap = ofN (8 * c.rcap - 16)) (hLa : L.aEnd = ofN c.aEnd)
    (hLal : L.aLim = ofN (c.aBase + 8)) (hsz : ∀ k, offs p k < 2 ^ 64) (hreg : RegsOk c p)
    {s : State 64} {o : Outcome 64} (h : Exec p s o) :
    ∀ {x : M}, Rel c p s x →
      Final c p (lowerProg L p) x o ∨ RExec (lowerProg L p) x .overflow := by
  induction h with
  | @halt s s' hst =>
    intro x hs
    have := step_sim hg hL hMs hLd hLr hLa hLal hsz hreg hs
    rw [hst] at this
    rcases this with this | ⟨_, h6⟩
    · exact .inl this
    · exact .inr h6
  | @trap s t hst =>
    intro x hs
    have := step_sim hg hL hMs hLd hLr hLa hLal hsz hreg hs
    rw [hst] at this
    rcases this with this | ⟨_, h6⟩
    · exact .inl this
    · exact .inr h6
  | @next s s' o hst _ ih =>
    intro x hs
    have := step_sim hg hL hMs hLd hLr hLa hLal hsz hreg hs
    rw [hst] at this
    rcases this with ⟨x1, hsteps, hrel⟩ | ⟨_, h6⟩
    · rcases ih hrel with hih | h6
      · left
        cases o with
        | next _ => exact hih.elim
        | halted s2 =>
          obtain ⟨x', hx, hr⟩ := hih
          exact ⟨x', RExec.of_steps hsteps hx, hr⟩
        | trapped t => exact RExec.of_steps hsteps hih
      · exact .inr (RExec.of_steps hsteps h6)
    · exact .inr h6

/-- Whole-program preservation. When the IR run stays within the stack capacities (`Fits` at
every reachable state), no overflow guard fires and the outcome is exactly the IR's. -/
theorem lowerProg_correct {c : Cfg} {p : Prog 64} {L : Layout} (hg : Geom c)
    (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M) (hLd : L.dLim = ofN (c.dBase + 8))
    (hLr : L.rGap = ofN (8 * c.rcap - 16)) (hLa : L.aEnd = ofN c.aEnd)
    (hLal : L.aLim = ofN (c.aBase + 8)) (hsz : ∀ k, offs p k < 2 ^ 64) (hreg : RegsOk c p)
    {s : State 64} {o : Outcome 64} (h : Exec p s o) :
    ∀ {x : M}, Rel c p s x → (∀ s', Steps p s s' → Fits c s') →
      Final c p (lowerProg L p) x o := by
  induction h with
  | @halt s s' hst =>
    intro x hs hb
    have := step_sim hg hL hMs hLd hLr hLa hLal hsz hreg hs
    rw [hst] at this
    rcases this with this | ⟨hnf, _⟩
    · exact this
    · exact absurd (hb s .refl) hnf
  | @trap s t hst =>
    intro x hs hb
    have := step_sim hg hL hMs hLd hLr hLa hLal hsz hreg hs
    rw [hst] at this
    rcases this with this | ⟨hnf, _⟩
    · exact this
    · exact absurd (hb s .refl) hnf
  | @next s s' o hst _ ih =>
    intro x hs hb
    have := step_sim hg hL hMs hLd hLr hLa hLal hsz hreg hs
    rw [hst] at this
    rcases this with ⟨x1, hsteps, hrel⟩ | ⟨hnf, _⟩
    · have hih := ih hrel (fun s'' hss => hb s'' (Steps.cons hst hss))
      cases o with
      | next _ => exact hih.elim
      | halted s2 =>
        obtain ⟨x', hx, hr⟩ := hih
        exact ⟨x', RExec.of_steps hsteps hx, hr⟩
      | trapped t => exact RExec.of_steps hsteps hih
    · exact absurd (hb s .refl) hnf

/-- The state the runtime prologue establishes (`RV.Emit`): empty stacks, `s4 = s5 = sp0`,
`s3 s2 s1 s6` at the conventions, and the register file and IR memory regions holding the IR
state's initial contents. `Rel` then holds at the entry point, so `lowerProg_correct` applies. -/
theorem init_rel {c : Cfg} {p : Prog 64} {s0 : State 64} {x0 : M} (hg : Geom c)
    (hd : s0.dstack = []) (hr : s0.rstack = []) (ha : s0.astack = []) (hrc : 1 ≤ c.rcap)
    (h15 : x0.regs Reg.s1 = ofN c.dEnd) (h14 : x0.regs Reg.s2 = ofN c.rf)
    (h13 : x0.regs Reg.s3 = ofN c.mb) (h12 : x0.regs Reg.s4 = ofN c.sp0)
    (hsp : x0.regs Reg.s5 = ofN c.sp0) (hbp : x0.regs Reg.s6 = ofN c.aEnd) (hregs : RegRel c x0.mem s0.regs)
    (hmem : MemRel c x0.mem s0.mem) (hiv : ∀ a : Word 64, s0.mem.valid a = decide (a.toNat < c.M))
    (hxv : RegionsValid c x0.mem.valid) (hpc : x0.pc = offs p s0.pc) : Rel c p s0 x0 :=
  ⟨{ s1 := by simpa [hd] using h15
     s2 := h14
     s3 := h13
     s4 := h12
     s5 := by simpa [hr] using hsp
     s6 := by simpa [ha] using hbp
     aux := by intro i v h; simp [ha] at h
     stack := by intro i v h; simp [hd] at h
     regs := hregs
     mem := hmem
     rs := by intro i a h; simp [hr] at h
     irvalid := hiv
     xvalid := hxv
     capD := by simp [hd]; exact hg.dBase_le
     capR := by simp [hr]; exact hrc
     capA := by have := hg.aBase_8; simp [ha]; omega }, hpc⟩

end RV
end WordDialect
