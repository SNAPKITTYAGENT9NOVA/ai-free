import X86.SimStep

/-!
# X86.Correct

Whole-program preservation: running the lowered x86 code from a state related to the IR state
`s` reaches the same final outcome the IR semantics reaches from `s`.

* IR `halted s'`  ⇒  the x86 code halts in a state `x'` with `Rel0 c p s' x'` (so the data
  stack, virtual registers, IR memory and return stack agree with `s'`);
* IR `trapped t`  ⇒  the x86 code exits with the same trap `t`.

Hypotheses (all explicit):
* `Geom c`            the memory regions are disjoint and within the 64-bit address space;
* `L` matches `c`     data-stack end and IR memory size;
* `hsz`               code indices fit in 64 bits;
* `RegsOk`            every `push r`/`pop r` names a register inside the register file;
* `hb`                the IR run stays within the stack capacities (`Fits`), because the native
                      code does not check for overflow of the data stack or the native stack.
-/

namespace WordDialect
namespace X86

open Reg

/-- Every register index used by the program lies in the virtual register file. -/
def RegsOk (c : Cfg) (p : Prog 64) : Prop :=
  ∀ (k : Nat) (i : WordDialect.Instr 64), p[k]? = some i → ∀ r : Nat, (i = WordDialect.Instr.push r ∨ i = WordDialect.Instr.pop r) → r < c.nregs

/-- The final-outcome form of `Sim`. -/
def Final (c : Cfg) (p : Prog 64) (code : List (Instr Nat)) (x : M) : Outcome 64 → Prop
  | .next _ => False
  | .halted s' => ∃ x', XExec code x (.halted x') ∧ Rel0 c p s' x'
  | .trapped t => XExec code x (.trapped t)

theorem offs_ge {p : Prog 64} {k : Nat} (h : p.length ≤ k) : offs p k = offs p p.length := by
  simp [offs, List.take_of_length_le h, List.take_length]

theorem lowerProg_correct {c : Cfg} {p : Prog 64} {L : Layout} (hg : Geom c)
    (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M) (hsz : ∀ k, offs p k < 2 ^ 64)
    (hreg : RegsOk c p) {s : State 64} {o : Outcome 64} (h : Exec p s o) :
    ∀ {x : M}, Rel c p s x → (∀ s', Steps p s s' → Fits c s') →
      Final c p (lowerProg L p) x o := by
  induction h with
  | @halt s s' hst =>
    intro x hs hb
    cases hi : p[s.pc]? with
    | none => simp [WordDialect.step, hi] at hst
    | some i =>
      have hsim := sim_exec hg hL hMs hsz hs (hb s Steps.refl) hi (fun r hr => hreg s.pc i hi r hr)
      simp only [WordDialect.step, hi] at hst
      rw [hst] at hsim
      exact hsim
  | @trap s t hst =>
    intro x hs hb
    cases hi : p[s.pc]? with
    | none =>
      simp [WordDialect.step, hi] at hst
      subst hst
      have hge : p.length ≤ s.pc := by
        by_cases hh : s.pc < p.length
        · rw [List.getElem?_eq_getElem hh] at hi; simp at hi
        · omega
      have hstub := lowerProg_stub L p
      obtain ⟨f0, _⟩ := hstub
      have hpc : x.pc = offs p p.length := by rw [hs.2, offs_ge hge]
      exact XExec.trap (by rw [xstep_of_fetch (by rw [hpc]; exact f0)]; rfl)
    | some i =>
      have hsim := sim_exec hg hL hMs hsz hs (hb s Steps.refl) hi (fun r hr => hreg s.pc i hi r hr)
      simp only [WordDialect.step, hi] at hst
      rw [hst] at hsim
      exact hsim
  | @next s s' o hst _ ih =>
    intro x hs hb
    cases hi : p[s.pc]? with
    | none => simp [WordDialect.step, hi] at hst
    | some i =>
      have hsim := sim_exec hg hL hMs hsz hs (hb s Steps.refl) hi (fun r hr => hreg s.pc i hi r hr)
      simp only [WordDialect.step, hi] at hst
      rw [hst] at hsim
      obtain ⟨x1, hsteps, hrel⟩ := hsim
      have hih := ih hrel (fun s'' hss => hb s'' (Steps.cons (by simp [WordDialect.step, hi, hst]) hss))
      cases o with
      | next _ => exact hih.elim
      | halted s2 =>
        obtain ⟨x', hx, hr⟩ := hih
        exact ⟨x', XExec.of_steps hsteps hx, hr⟩
      | trapped t => exact XExec.of_steps hsteps hih

/-- The state the runtime prologue establishes (`X86.Emit`): empty stacks, `r12 = rsp = sp0`,
`r13 r14 r15` at the conventions, and the register file and IR memory regions holding the IR
state's initial contents. `Rel` then holds at the entry point, so `lowerProg_correct` applies. -/
theorem init_rel {c : Cfg} {p : Prog 64} {s0 : State 64} {x0 : M} (hg : Geom c)
    (hd : s0.dstack = []) (hr : s0.rstack = []) (hrc : 1 ≤ c.rcap)
    (h15 : x0.regs Reg.r15 = ofN c.dEnd) (h14 : x0.regs Reg.r14 = ofN c.rf)
    (h13 : x0.regs Reg.r13 = ofN c.mb) (h12 : x0.regs Reg.r12 = ofN c.sp0)
    (hsp : x0.regs Reg.rsp = ofN c.sp0) (hregs : RegRel c x0.mem s0.regs)
    (hmem : MemRel c x0.mem s0.mem) (hiv : ∀ a : Word 64, s0.mem.valid a = decide (a.toNat < c.M))
    (hxv : RegionsValid c x0.mem.valid) (hpc : x0.pc = offs p s0.pc) : Rel c p s0 x0 :=
  ⟨{ r15 := by simpa [hd] using h15
     r14 := h14
     r13 := h13
     r12 := h12
     rsp := by simpa [hr] using hsp
     stack := by intro i v h; simp [hd] at h
     regs := hregs
     mem := hmem
     rs := by intro i a h; simp [hr] at h
     irvalid := hiv
     xvalid := hxv
     capD := by simp [hd]; exact hg.dBase_le
     capR := by simp [hr]; exact hrc }, hpc⟩

end X86
end WordDialect
