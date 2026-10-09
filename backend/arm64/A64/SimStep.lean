import A64.SimAux

/-!
# A64.SimStep

One IR step is simulated by the lowered AArch64 code, for every instruction and every outcome
(`next`, `halted`, `trapped`). This is the case analysis over the whole instruction set that the
whole-program theorem iterates.

Every instruction that grows the data stack or the auxiliary stack, and every `call`, first checks
for room and exits with `overflow` when the stack is full. So `sim_exec` has no capacity hypothesis: the code either
simulates the IR step, or the state lacks the headroom `Fits` describes and the code overflows.
-/

namespace WordDialect
namespace A64

open Reg

/-- Headroom for one step: room to push one data word, two return addresses. worth of
stack, and one auxiliary word. -/
def Fits (c : Cfg) (s : State 64) : Prop :=
  c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd ∧ s.rstack.length + 2 ≤ c.rcap ∧
    c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd

/-- What simulating an IR outcome means on the AArch64 side. -/
def Sim (c : Cfg) (p : Prog 64) (code : List (Instr Nat)) (x : M) : Outcome 64 → Prop
  | .next s' => ∃ x', ASteps code x x' ∧ Rel c p s' x'
  | .halted s' => ∃ x', AExec code x (.halted x') ∧ Rel0 c p s' x'
  | .trapped t => AExec code x (.trapped t)

theorem shape1 {l : List W} (h : 1 ≤ l.length) : ∃ a d, l = a :: d := by
  cases l with
  | nil => simp at h
  | cons a d => exact ⟨a, d, rfl⟩

theorem shape2 {l : List W} (h : 2 ≤ l.length) : ∃ b a d, l = b :: a :: d := by
  cases l with
  | nil => simp at h
  | cons b l =>
    cases l with
    | nil => simp at h
    | cons a d => exact ⟨b, a, d, rfl⟩

theorem shape3 {l : List W} (h : 3 ≤ l.length) : ∃ cc y v d, l = cc :: y :: v :: d := by
  cases l with
  | nil => simp at h
  | cons cc l =>
    cases l with
    | nil => simp at h
    | cons y l =>
      cases l with
      | nil => simp at h
      | cons v d => exact ⟨cc, y, v, d, rfl⟩

theorem lowerInstr_uf (L : Layout) (base : Nat) (off : Nat → Nat) (i : WordDialect.Instr 64)
    (h : 0 < i.pops) :
    ∃ rest, lowerInstr L base off i = uf L i.pops base ++ rest ∧ i.pops ≤ 3 := by
  cases i <;> first | exact ⟨_, rfl, by simp [Instr.pops]⟩ | exact absurd h (by simp [Instr.pops])

theorem Rel0.setPc {c : Cfg} {p : Prog 64} {s : State 64} {x : M} (h : Rel0 c p s x) (n : Nat) :
    Rel0 c p { s with pc := n } x :=
  { x19 := h.x19, x20 := h.x20, x21 := h.x21, x22 := h.x22, x23 := h.x23, x24 := h.x24,
    stack := h.stack, regs := h.regs, mem := h.mem, rs := h.rs, aux := h.aux, irvalid := h.irvalid,
    xvalid := h.xvalid, capD := h.capD, capR := h.capR, capA := h.capA }

section Step

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {L : Layout}

theorem sim_next {code : List (Instr Nat)} {s' : State 64}
    (h : ∃ x', ASteps code x x' ∧ Rel c p s' x') : Sim c p code x (.next s') := h

theorem sim_halted {code : List (Instr Nat)} {s' : State 64}
    (h : ∃ x', AExec code x (.halted x') ∧ Rel0 c p s' x') : Sim c p code x (.halted s') := h

theorem sim_trapped {code : List (Instr Nat)} {t : Trap} (h : AExec code x (.trapped t)) :
    Sim c p code x (.trapped t) := h

theorem rel_fall {i : WordDialect.Instr 64} (hi : p[s.pc]? = some i) {s' : State 64}
    {x' : M} (h0 : Rel0 c p s' x') (hpc : x'.pc = offs p s.pc + isize i) :
    Rel c p { s' with pc := s.pc + 1 } x' :=
  ⟨h0.setPc _, by rw [hpc, offs_succ hi]⟩

theorem sim_exec (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hMs : L.memSize = c.M)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hLr : L.rGap = ofN (8 * c.rcap - 16))
    (hLa : L.aEnd = ofN c.aEnd) (hLal : L.aLim = ofN (c.aBase + 8))
    (hsz : ∀ k, offs p k < 2 ^ 64) (hs : Rel c p s x)
    {i : WordDialect.Instr 64} (hi : p[s.pc]? = some i)
    (hreg : ∀ r, (i = .push r ∨ i = .pop r) → r < c.nregs) :
    Sim c p (lowerProg L p) x (WordDialect.exec i s) ∨
      (¬ Fits c s ∧ AExec (lowerProg L p) x .overflow) := by
  have nfD : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd → ¬ Fits c s := fun h hf => h hf.1
  have nfR : ¬ s.rstack.length + 2 ≤ c.rcap → ¬ Fits c s := fun h hf => h hf.2.1
  have nfA : ¬ c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd → ¬ Fits c s := fun h hf => h hf.2.2
  have hpc : x.pc = offs p s.pc := hs.2
  have hs0 : Rel0 c p s x := hs.1
  have hat := lowerProg_at L p s.pc i hi
  by_cases hk : s.dstack.length < i.pops
  · rw [exec_underflow i s hk]
    obtain ⟨rest, hlow, h3⟩ := lowerInstr_uf L (offs p s.pc) (offs p) i (by omega)
    rw [hlow] at hat
    exact .inl <| sim_trapped (sim_uf_trap hg hs0 hL (by omega) h3 hk hpc hat)
  · have hk' : i.pops ≤ s.dstack.length := by omega
    cases i with
    | word w =>
      by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
      rotate_left
      · exact .inr ⟨nfD hf, sim_word_ovf hg hs0 hpc w hLd hat hf⟩
      obtain ⟨x', hst, h0, hpc'⟩ := sim_word_ok hg hs0 hpc w hLd hat hf
      rw [exec_word]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | ptr q =>
      by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
      rotate_left
      · exact .inr ⟨nfD hf, sim_ptr_ovf hg hs0 hpc q hLd hat hf⟩
      obtain ⟨x', hst, h0, hpc'⟩ := sim_ptr_ok hg hs0 hpc q hLd hat hf
      rw [exec_ptr]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | load =>
      obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
      cases hm : s.mem.read? a with
      | none =>
        rw [exec_load_bad hd hm]
        exact .inl <| sim_trapped (sim_load_trap hg hL hMs hs0 hpc hat hd hm)
      | some v =>
        obtain ⟨x', hst, h0, hpc'⟩ := sim_load_ok hg hL hMs hs0 hpc hat hd hm
        rw [exec_load hd hm]
        exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | store =>
      obtain ⟨a, v, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      cases hm : s.mem.write? a v with
      | none =>
        rw [exec_store_bad hd hm]
        exact .inl <| sim_trapped (sim_store_trap hg hL hMs hs0 hpc hat hd hm)
      | some m =>
        obtain ⟨x', hst, h0, hpc'⟩ := sim_store_ok hg hL hMs hs0 hpc hat hd hm
        rw [exec_store hd hm]
        exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | add =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_add_ok hg hL hs0 hpc hat hd
      rw [exec_add hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | sub =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_sub_ok hg hL hs0 hpc hat hd
      rw [exec_sub hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | mul =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_mul_ok hg hL hs0 hpc hat hd
      rw [exec_mul hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | and =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_and_ok hg hL hs0 hpc hat hd
      rw [exec_and hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | or =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_or_ok hg hL hs0 hpc hat hd
      rw [exec_or hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | xor =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_xor_ok hg hL hs0 hpc hat hd
      rw [exec_xor hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | shl =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_shl_ok hg hL hs0 hpc hat hd
      rw [exec_shl hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | shr =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_shr_ok hg hL hs0 hpc hat hd
      rw [exec_shr hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | rotl =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_rotl_ok hg hL hs0 hpc hat hd
      rw [exec_rotl hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | rotr =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_rotr_ok hg hL hs0 hpc hat hd
      rw [exec_rotr hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | cmp cd =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_cmp_ok cd hg hL hs0 hpc hat hd
      rw [exec_cmp hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | div =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      by_cases hb : b = 0#64
      · subst hb
        rw [exec_div_zero hd]
        exact .inl <| sim_trapped (sim_div_zero hg hL hs0 hpc hat hd)
      · obtain ⟨x', hst, h0, hpc'⟩ := sim_div_ok hg hL hs0 hpc hat hd hb
        rw [exec_div hd hb]
        exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | sdiv =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      by_cases hb : b = 0#64
      · subst hb
        rw [exec_sdiv_zero hd]
        exact .inl <| sim_trapped (sim_sdiv_zero hg hL hs0 hpc hat hd)
      · obtain ⟨x', hst, h0, hpc'⟩ := sim_sdiv_ok hg hL hs0 hpc hat hd hb
        rw [exec_sdiv hd hb]
        exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | not =>
      obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_not_ok hg hL hs0 hpc hat hd
      rw [exec_not hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | select =>
      obtain ⟨cc, y, v, d, hd⟩ := shape3 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_select_ok hg hL hs0 hpc hat hd
      rw [exec_select hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | jmp t =>
      obtain ⟨x', hst, h0, hpc'⟩ := sim_jmp_ok hs0 hpc hat
      exact .inl <| sim_next ⟨x', hst, h0.setPc _, hpc'⟩
    | branch t =>
      obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_branch_ok hg hL hs0 hpc hat hd
      by_cases hc : Word.isTrue a = true
      · have e : WordDialect.exec (WordDialect.Instr.branch t) s = .next { s with pc := t, dstack := d } := by
          simp [WordDialect.exec, hd, hc]
        rw [e]
        simp only [hc, if_true] at hpc'
        exact .inl <| sim_next ⟨x', hst, h0.setPc _, hpc'⟩
      · have hc' : Word.isTrue a = false := by simpa using hc
        have e : WordDialect.exec (WordDialect.Instr.branch t) s = s.fall d := by simp [WordDialect.exec, hd, hc']
        rw [e]
        simp only [hc', Bool.false_eq_true, if_false] at hpc'
        exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | call t =>
      have hret : offs p s.pc + isize (.call t : WordDialect.Instr 64) = offs p (s.pc + 1) := by
        rw [offs_succ hi]
      by_cases hf : s.rstack.length + 2 ≤ c.rcap
      rotate_left
      · exact .inr ⟨nfR hf, sim_call_ovf hg hs0 hpc hLr hat hf⟩
      obtain ⟨x', hst, h0, hpc'⟩ := sim_call_ok hg hs0 hpc hLr hat hret hf
      exact .inl <| sim_next ⟨x', hst, h0.setPc _, hpc'⟩
    | ret =>
      cases hr : s.rstack with
      | nil =>
        have e : WordDialect.exec WordDialect.Instr.ret s = .trapped .returnUnderflow := by simp [WordDialect.exec, hr]
        rw [e]
        exact .inl <| sim_trapped (sim_ret_trap hs0 hpc hat hr)
      | cons a rs =>
        obtain ⟨x', hst, h0, hpc'⟩ := sim_ret_ok hg hs0 hpc hat hr (hsz a)
        have e : WordDialect.exec WordDialect.Instr.ret s = .next { s with pc := a, rstack := rs } := by simp [WordDialect.exec, hr]
        rw [e]
        exact .inl <| sim_next ⟨x', hst, h0.setPc _, hpc'⟩
    | push r =>
      by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
      rotate_left
      · exact .inr ⟨nfD hf, sim_push_ovf hg hs0 hpc hLd hat hf⟩
      obtain ⟨x', hst, h0, hpc'⟩ := sim_push_ok hg hs0 hpc (hreg r (Or.inl rfl)) hLd hat hf
      rw [exec_push]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | pop r =>
      obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_pop_ok hg hL hs0 hpc (hreg r (Or.inr rfl)) hat hd
      rw [exec_pop hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | dup =>
      obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
      by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
      rotate_left
      · exact .inr ⟨nfD hf, sim_dup_ovf hg hL hs0 hpc hLd hat hd hf⟩
      obtain ⟨x', hst, h0, hpc'⟩ := sim_dup_ok hg hL hs0 hpc hLd hat hd hf
      rw [exec_dup hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | drop =>
      obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_drop_ok hg hL hs0 hpc hat hd
      rw [exec_drop hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | swap =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_swap_ok hg hL hs0 hpc hat hd
      rw [exec_swap hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | over =>
      obtain ⟨b, a, d, hd⟩ := shape2 (by simpa [Instr.pops] using hk')
      by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
      rotate_left
      · exact .inr ⟨nfD hf, sim_over_ovf hg hL hs0 hpc hLd hat hd hf⟩
      obtain ⟨x', hst, h0, hpc'⟩ := sim_over_ok hg hL hs0 hpc hLd hat hd hf
      rw [exec_over hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | rot =>
      obtain ⟨cc, b, a, d, hd⟩ := shape3 (by simpa [Instr.pops] using hk')
      obtain ⟨x', hst, h0, hpc'⟩ := sim_rot_ok hg hL hs0 hpc hat hd
      rw [exec_rot hd]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | tor =>
      obtain ⟨a, d, hd⟩ := shape1 (by simpa [Instr.pops] using hk')
      by_cases hf : c.aBase + 8 * (s.astack.length + 1) ≤ c.aEnd
      rotate_left
      · exact .inr ⟨nfA hf, sim_tor_ovf hg hL hLal hs0 hpc hat (by simp [hd]) hf⟩
      obtain ⟨x', hst, h0, hpc'⟩ := sim_tor_ok hg hL hLal hs0 hpc hat hd hf
      have e : WordDialect.exec WordDialect.Instr.tor s =
          .next { s with pc := s.pc + 1, dstack := d, astack := a :: s.astack } := by
        simp [WordDialect.exec, hd]
      rw [e]
      exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | fromr =>
      cases ha : s.astack with
      | nil =>
        have e : WordDialect.exec WordDialect.Instr.fromr s = .trapped .returnUnderflow := by
          simp [WordDialect.exec, ha]
        rw [e]
        exact .inl <| sim_trapped (sim_fromr_trap hg hLa hs0 hpc hat ha)
      | cons a as =>
        by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
        rotate_left
        · exact .inr ⟨nfD hf, sim_fromr_ovf hg hLa hLd hs0 hpc hat (by simp [ha]) hf⟩
        obtain ⟨x', hst, h0, hpc'⟩ := sim_fromr_ok hg hLa hLd hs0 hpc hat ha hf
        have e : WordDialect.exec WordDialect.Instr.fromr s =
            .next { s with pc := s.pc + 1, dstack := a :: s.dstack, astack := as } := by
          simp [WordDialect.exec, ha]
        rw [e]
        exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | rfetch =>
      cases ha : s.astack with
      | nil =>
        have e : WordDialect.exec WordDialect.Instr.rfetch s = .trapped .returnUnderflow := by
          simp [WordDialect.exec, ha]
        rw [e]
        exact .inl <| sim_trapped (sim_rfetch_trap hg hLa hs0 hpc hat ha)
      | cons a as =>
        by_cases hf : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd
        rotate_left
        · exact .inr ⟨nfD hf, sim_rfetch_ovf hg hLa hLd hs0 hpc hat (by simp [ha]) hf⟩
        obtain ⟨x', hst, h0, hpc'⟩ := sim_rfetch_ok hg hLa hLd hs0 hpc hat ha hf
        have e : WordDialect.exec WordDialect.Instr.rfetch s = s.fall (a :: s.dstack) := by
          simp [WordDialect.exec, ha]
        rw [e]
        exact .inl <| sim_next ⟨x', hst, rel_fall hi h0 hpc'⟩
    | halt =>
      rw [exec_halt]
      exact .inl <| sim_halted ⟨x, sim_halt hs0 hpc hat, hs0⟩

end Step

end A64
end WordDialect
