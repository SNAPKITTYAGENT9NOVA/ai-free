import Wasm.SimCtl

/-!
# Wasm.SimExec

One IR step is simulated by the function the lowering emits for the instruction, for every
instruction and every outcome (`next`, `halted`, `trapped`). This is the case analysis over the
whole instruction set that the dispatch-loop theorem (`Wasm.Correct`) iterates.

Trap codes (the argument of `proc_exit`): 1 `stackUnderflow`, 2 `badAddress`, 3 `divideByZero`,
4 `badPc`, 5 `returnUnderflow`.

Every instruction that grows a stack first checks for room, and exits with code 6 when the stack
is full. So `sim_step` has no capacity hypothesis: the code either simulates the IR step, or the
stack lacks the headroom `Fits` describes and the code exits 6. Code 6 has no IR counterpart (IR
stacks are unbounded); it reports that the run exceeded the target's capacity.
-/

namespace WordDialect
namespace Wasm

def trapCode : Trap → Nat
  | .stackUnderflow => 1
  | .badAddress => 2
  | .divideByZero => 3
  | .badPc => 4
  | .returnUnderflow => 5

/-- Headroom for one step: room to push one data word and one return index. With this headroom no
overflow guard fires. -/
def Fits (c : Cfg) (s : State 64) : Prop :=
  c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd ∧ c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd

/-- What simulating one IR outcome means for the body of one dispatched function. On `next`, the
function returns the (clamped) next IR index, and every return index stays within the program. -/
def StepSim (c : Cfg) (fs : Funcs) (n : Nat) (body : List WI) (w : WState) : Outcome 64 → Prop
  | .next s' => (∀ a ∈ s'.rstack, a ≤ n) ∧
      ∃ w', Run fs body w (.normal w') ∧ Rel0 c s' w' ∧ w'.stack = [.i32 (ofN (min s'.pc n))]
  | .halted s' => ∃ w', Run fs body w (.halted w') ∧ Rel0 c s' w'
  | .trapped t => Run fs body w (.exit (trapCode t))

section Step

variable {c : Cfg} {s : State 64} {w : WState} {fs : Funcs} {n : Nat}

theorem Rel0.setPc (h : Rel0 c s w) (q : Nat) : Rel0 c { s with pc := q } w :=
  { sp := h.sp, rp := h.rp, stack := h.stack, regs := h.regs, mem := h.mem, rs := h.rs,
    irvalid := h.irvalid, size := h.size, capD := h.capD, capR := h.capR }

theorem next_sim {body : List WI} {s1 : State 64} {q : Nat} (hrs : ∀ a ∈ s1.rstack, a ≤ n)
    (h : Sim1 c fs body s1 w (min q n)) : StepSim c fs n body w (.next { s1 with pc := q }) := by
  obtain ⟨w', hr, h0, hst⟩ := h
  exact ⟨hrs, w', hr, h0.setPc q, hst⟩

theorem fall_sim {body : List WI} {d : List W} (hlt : s.pc < n) (hrs : ∀ a ∈ s.rstack, a ≤ n)
    (h : Sim1 c fs body { s with dstack := d } w (s.pc + 1)) : StepSim c fs n body w (s.fall d) := by
  rw [← Nat.min_eq_left (show s.pc + 1 ≤ n by omega)] at h
  exact next_sim (s1 := { s with dstack := d }) hrs h

theorem shape1 {l : List W} (h : 1 ≤ l.length) : ∃ a d, l = a :: d := by
  cases l with
  | nil => simp at h
  | cons a d => exact ⟨a, d, rfl⟩

theorem shape2 {l : List W} (h : 2 ≤ l.length) : ∃ b a d, l = b :: a :: d := by
  rcases l with _ | ⟨b, _ | ⟨a, d⟩⟩
  · simp at h
  · simp at h
  · exact ⟨b, a, d, rfl⟩

theorem shape3 {l : List W} (h : 3 ≤ l.length) : ∃ x y z d, l = x :: y :: z :: d := by
  rcases l with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩
  · simp at h
  · simp at h
  · simp at h
  · exact ⟨x, y, z, d, rfl⟩

/-- Every instruction that pops operands starts with the operand-count guard. -/
theorem lowerInstr_uf (L : Layout) (n k : Nat) (i : WordDialect.Instr 64) (h : 0 < i.pops) :
    ∃ rest, lowerInstr L n k i = uf L i.pops ++ rest ∧ i.pops ≤ 3 := by
  cases i <;> simp only [Instr.pops] at h ⊢ <;>
    first
    | exact absurd h (by decide)
    | exact ⟨_, by simp only [lowerInstr, binOp, shiftOp, List.append_assoc]; rfl, by decide⟩

theorem sim_step (hg : Geom c) (hs : Rel0 c s w) (hst : w.stack = [])
    {p : Prog 64} (hn : p.length < 2 ^ 32) (hrs : ∀ a ∈ s.rstack, a ≤ p.length)
    {i : WordDialect.Instr 64} (hi : p[s.pc]? = some i)
    (hreg : ∀ r, (i = .push r ∨ i = .pop r) → r < c.nregs) :
    StepSim c fs p.length (lowerInstr c.layout p.length s.pc i) w (exec i s) ∨
      (¬ Fits c s ∧ Run fs (lowerInstr c.layout p.length s.pc i) w (.exit 6)) := by
  have nfD : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd → ¬ Fits c s := fun h hf => h hf.1
  have nfR : ¬ c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd → ¬ Fits c s := fun h hf => h hf.2
  have hlt : s.pc < p.length := by
    by_cases h : s.pc < p.length
    · exact h
    · rw [List.getElem?_eq_none (by omega)] at hi; simp at hi
  by_cases hk : s.dstack.length < i.pops
  · rw [exec_underflow i s hk]
    obtain ⟨rest, hlow, h3⟩ := lowerInstr_uf c.layout p.length s.pc i (by omega)
    rw [hlow]
    exact .inl <| run_append_abrupt _ (uf_trap hg hs (by omega) h3 hk) trivial
  have hk' : i.pops ≤ s.dstack.length := by omega
  cases i with
  | word v =>
    by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
    · exact .inl <| fall_sim hlt hrs (sim_word _ _ hg hs hst v hf)
    · exact .inr ⟨nfD hf, sim_word_ovf _ _ hg hs v hf⟩
  | ptr q =>
    by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
    · exact .inl <| fall_sim hlt hrs (sim_ptr _ _ hg hs hst q hf)
    · exact .inr ⟨nfD hf, sim_ptr_ovf _ _ hg hs q hf⟩
  | load =>
    obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
    by_cases ha : a.toNat < c.M
    · have hv : s.mem.valid a = true := (valid_iff hs a).mpr ha
      have hex : exec .load s = s.fall (s.mem.cell a :: d) := by
        simp [exec, hd, Memory.read?, hv]
      rw [hex]
      exact .inl <| fall_sim hlt hrs (sim_load _ _ hg hs hst hd ha)
    · have hv : s.mem.valid a = false := by
        cases h : s.mem.valid a
        · rfl
        · exact absurd ((valid_iff hs a).mp h) ha
      have hex : exec .load s = .trapped .badAddress := by
        simp [exec, hd, Memory.read?, hv]
      rw [hex]
      exact .inl <| sim_load_trap _ _ hg hs hd (by omega)
  | store =>
    obtain ⟨a, v, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    cases hw : s.mem.write? a v with
    | none =>
      have hv : s.mem.valid a = false := (Memory.write?_none_iff s.mem a v).mp hw
      have ha : ¬ a.toNat < c.M := fun h => by rw [(valid_iff hs a).mpr h] at hv; simp at hv
      have hex : exec .store s = .trapped .badAddress := by simp [exec, hd, hw]
      rw [hex]
      exact .inl <| sim_store_trap _ _ hg hs hd (by omega)
    | some im =>
      have hex : exec .store s = .next { { s with dstack := d, mem := im } with pc := s.pc + 1 } := by
        simp [exec, hd, hw]
      rw [hex]
      have h := sim_store (fs := fs) p.length s.pc hg hs hst hd hw
      rw [← Nat.min_eq_left (show s.pc + 1 ≤ p.length by omega)] at h
      exact .inl <| next_sim hrs h
  | add =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .add s = s.fall ((a + b) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_add _ _ hg hs hst hd)
  | sub =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .sub s = s.fall ((a - b) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_sub _ _ hg hs hst hd)
  | mul =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .mul s = s.fall ((a * b) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_mul _ _ hg hs hst hd)
  | div =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    by_cases hb : b = 0#64
    · subst hb
      rw [show exec .div s = .trapped .divideByZero by simp [exec, hd]]
      exact .inl <| sim_div_trap _ _ hg hs hd
    · rw [show exec .div s = s.fall (a.udiv b :: d) by simp [exec, hd, hb]]
      exact .inl <| fall_sim hlt hrs (sim_div _ _ hg hs hst hd hb)
  | sdiv =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    by_cases hb : b = 0#64
    · subst hb
      rw [show exec .sdiv s = .trapped .divideByZero by simp [exec, hd]]
      exact .inl <| sim_sdiv_trap _ _ hg hs hd
    · rw [show exec .sdiv s = s.fall (a.sdiv b :: d) by simp [exec, hd, hb]]
      exact .inl <| fall_sim hlt hrs (sim_sdiv _ _ hg hs hst hd hb)
  | and =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .and s = s.fall ((a &&& b) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_and _ _ hg hs hst hd)
  | or =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .or s = s.fall ((a ||| b) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_or _ _ hg hs hst hd)
  | xor =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .xor s = s.fall ((a ^^^ b) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_xor _ _ hg hs hst hd)
  | not =>
    obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
    rw [show exec .not s = s.fall ((~~~a) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_not _ _ hg hs hst hd)
  | shl =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .shl s = s.fall (Word.shl a b :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_shl _ _ hg hs hst hd)
  | shr =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .shr s = s.fall (Word.shr a b :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_shr _ _ hg hs hst hd)
  | rotl =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .rotl s = s.fall (Word.rotl a b :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_rotl _ _ hg hs hst hd)
  | rotr =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .rotr s = s.fall (Word.rotr a b :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_rotr _ _ hg hs hst hd)
  | cmp cd =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec (.cmp cd) s = s.fall (Word.ofBool (cd.eval a b) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_cmp _ _ cd hg hs hst hd)
  | select =>
    obtain ⟨cc, y, x, d, hd⟩ := shape3 (by simpa [Instr.pops] using hk')
    rw [show exec .select s = s.fall ((if Word.isTrue cc then x else y) :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_select _ _ hg hs hst hd)
  | jmp t =>
    rw [show exec (.jmp t) s = .next { s with pc := t } by simp [exec]]
    exact .inl <| next_sim hrs (sim_jmp _ _ t hs hst)
  | branch t =>
    obtain ⟨cv, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
    have h := sim_branch (fs := fs) p.length s.pc t hg hs hst hd
    by_cases hc : Word.isTrue cv = true
    · rw [show exec (.branch t) s = .next { { s with dstack := d } with pc := t } by simp [exec, hd, hc]]
      simp only [hc, ↓reduceIte] at h
      exact .inl <| next_sim hrs h
    · rw [show exec (.branch t) s = s.fall d by simp [exec, hd, hc]]
      have hc' : Word.isTrue cv = false := by simpa using hc
      simp only [hc', Bool.false_eq_true, ↓reduceIte] at h
      exact .inl <| fall_sim hlt hrs h
  | call t =>
    rw [show exec (.call t) s = .next { { s with rstack := (s.pc + 1) :: s.rstack } with pc := t } by simp [exec]]
    by_cases hf : c.rBase + 8 * (s.rstack.length + 1) ≤ c.rEnd
    · refine .inl (next_sim ?_ (sim_call _ _ t hg hs hst hf))
      intro a ha
      simp only [List.mem_cons] at ha
      rcases ha with ha | ha
      · omega
      · exact hrs a ha
    · exact .inr ⟨nfR hf, sim_call_ovf _ _ t hg hs hf⟩
  | ret =>
    cases hr : s.rstack with
    | nil =>
      rw [show exec .ret s = .trapped .returnUnderflow by simp [exec, hr]]
      exact .inl <| sim_ret_trap _ _ hs hst hr
    | cons a rs =>
      rw [show exec .ret s = .next { { s with rstack := rs } with pc := a } by simp [exec, hr]]
      have ha : a ≤ p.length := hrs a (by simp [hr])
      have h := sim_ret (fs := fs) p.length s.pc hg hs hst hr (by omega)
      rw [← Nat.min_eq_left ha] at h
      exact .inl <| next_sim (fun b hb => hrs b (by simp [hr, hb])) h
  | push r =>
    rw [show exec (.push r) s = s.fall (s.regs r :: s.dstack) by simp [exec]]
    by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
    · exact .inl <| fall_sim hlt hrs (sim_push _ _ hg hs hst (hreg r (.inl rfl)) hf)
    · exact .inr ⟨nfD hf, sim_push_ovf _ _ hg hs r hf⟩
  | pop r =>
    obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
    rw [show exec (.pop r) s =
        .next { { s with dstack := d, regs := State.setReg s.regs r a } with pc := s.pc + 1 } by
      simp [exec, hd]]
    have h := sim_pop (fs := fs) p.length s.pc hg hs hst (hreg r (.inr rfl)) hd
    rw [← Nat.min_eq_left (show s.pc + 1 ≤ p.length by omega)] at h
    exact .inl <| next_sim hrs h
  | dup =>
    obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
    rw [show exec .dup s = s.fall (a :: a :: d) by simp [exec, hd]]
    by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
    · exact .inl <| fall_sim hlt hrs (sim_dup _ _ hg hs hst hd hf)
    · exact .inr ⟨nfD hf, sim_dup_ovf _ _ hg hs hd hf⟩
  | drop =>
    obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
    rw [show exec .drop s = s.fall d by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_drop _ _ hg hs hst hd)
  | swap =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .swap s = s.fall (a :: b :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_swap _ _ hg hs hst hd)
  | over =>
    obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
    rw [show exec .over s = s.fall (a :: b :: a :: d) by simp [exec, hd]]
    by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
    · exact .inl <| fall_sim hlt hrs (sim_over _ _ hg hs hst hd hf)
    · exact .inr ⟨nfD hf, sim_over_ovf _ _ hg hs hd hf⟩
  | rot =>
    obtain ⟨x, y, z, d, hd⟩ := shape3 (by simpa [Instr.pops] using hk')
    rw [show exec .rot s = s.fall (z :: x :: y :: d) by simp [exec, hd]]
    exact .inl <| fall_sim hlt hrs (sim_rot _ _ hg hs hst hd)
  | halt =>
    rw [show exec .halt s = .halted s by simp [exec]]
    exact .inl <| ⟨w, sim_halt _ _, hs⟩

end Step

end Wasm
end WordDialect
