import X86.SimOps

/-!
# X86.SimStack

Single-instruction step lemmas (`load`/`store`/`addImm` on the data stack, `movImm`, `not`) and
the simulation theorems for the instructions that only move words on the data stack:
`word ptr not dup drop swap over rot`.
-/

namespace WordDialect
namespace X86

open Reg

section Steps

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}

theorem ld_step (hs : Rel0 c p s x) {j : Nat} {v : W} (hj : s.dstack[j]? = some v) {rd : Reg}
    (hrd : rd = rax ∨ rd = rcx ∨ rd = rdx ∨ rd = rbx) {disp : Int} (hd : disp = 8 * (j : Int))
    (hf : code[x.pc]? = some (.load rd Reg.r15 disp)) :
    ∃ x', XSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 1 ∧ x'.regs rd = v ∧
      (∀ r, r ≠ rd → x'.regs r = x.regs r) ∧ x'.mem = x.mem := by
  refine ⟨x.mov rd v, XSteps.single (by rw [xstep_of_fetch hf, ld_stack hs hj rd hd]),
    mov_rel0 hs rd (scratch_ne rd hrd) v, ?_, ?_, ?_, ?_⟩
  · simp [M.mov, M.setReg, M.adv]
  · simp [M.mov, M.setReg, M.adv]
  · intro r hr; simp [M.mov, M.setReg, M.adv, hr]
  · simp [M.mov, M.setReg, M.adv]

theorem st_step (hg : Geom c) (hs : Rel0 c p s x) {j : Nat} (hj : j < s.dstack.length) {rs : Reg}
    {disp : Int} (hd : disp = 8 * (j : Int)) (hf : code[x.pc]? = some (.store Reg.r15 disp rs)) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := s.dstack.set j (x.regs rs) } x' ∧
      x'.pc = x.pc + 1 ∧ x'.regs = x.regs := by
  obtain ⟨mem', e, hr⟩ := st_stack hg hs hj rs hd
  exact ⟨_, XSteps.single (by rw [xstep_of_fetch hf, e]), hr, by simp [M.adv], by simp [M.adv]⟩

theorem adj_step (hg : Geom c) (hs : Rel0 c p s x) {n : Nat} (hn : n ≤ s.dstack.length) {δ : Int}
    (hd : δ = 8 * (n : Int)) (hf : code[x.pc]? = some (.addImm Reg.r15 δ)) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := s.dstack.drop n } x' ∧
      x'.pc = x.pc + 1 ∧ (∀ r, r ≠ Reg.r15 → x'.regs r = x.regs r) := by
  obtain ⟨e, hr⟩ := adj_drop hg hs hn hd
  exact ⟨_, XSteps.single (by rw [xstep_of_fetch hf, e]), hr, by simp [M.arith, M.setReg],
    by intro r hr; simp [M.arith, M.setReg, hr]⟩

theorem movimm_step (hs : Rel0 c p s x) {rd : Reg} (hrd : rd = rax ∨ rd = rcx ∨ rd = rdx ∨ rd = rbx)
    {v : W} (hf : code[x.pc]? = some (.movImm rd v)) :
    ∃ x', XSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 1 ∧ x'.regs rd = v ∧
      (∀ r, r ≠ rd → x'.regs r = x.regs r) ∧ x'.mem = x.mem := by
  refine ⟨x.mov rd v, XSteps.single (by rw [xstep_of_fetch hf]; rfl),
    mov_rel0 hs rd (scratch_ne rd hrd) v, ?_, ?_, ?_, ?_⟩
  · simp [M.mov, M.setReg, M.adv]
  · simp [M.mov, M.setReg, M.adv]
  · intro r hr; simp [M.mov, M.setReg, M.adv, hr]
  · simp [M.mov, M.setReg, M.adv]

theorem not_step (hs : Rel0 c p s x) (hf : code[x.pc]? = some (.not rax)) :
    ∃ x', XSteps code x x' ∧ Rel0 c p s x' ∧ x'.pc = x.pc + 1 ∧ x'.regs rax = ~~~x.regs rax := by
  refine ⟨x.mov rax (~~~x.regs rax), XSteps.single (by rw [xstep_of_fetch hf]; rfl),
    mov_rel0 hs rax (scratch_ne rax (by simp)) _, ?_, ?_⟩
  · simp [M.mov, M.setReg, M.adv]
  · simp [M.mov, M.setReg, M.adv]

end Steps

/-- Placement of `ovfD L base ++ [i0, i1, i2]`. -/
theorem xat_ovf3 {code : List (Instr Nat)} {L : Layout} {base : Nat} {i0 i1 i2 : Instr Nat}
    (hat : XAt code base (ovfD L base ++ [i0, i1, i2])) :
    XAt code base (ovfD L base) ∧ code[base + 4]? = some i0 ∧ code[base + 4 + 1]? = some i1 ∧
      code[base + 4 + 1 + 1]? = some i2 := by
  obtain ⟨hato, hatr⟩ := xat_append.mp hat
  have hl : (ovfD L base).length = 4 := rfl
  rw [hl] at hatr
  obtain ⟨f0, f1, f2, _⟩ := hatr
  exact ⟨hato, f0, f1, f2⟩

/-- Placement of `uf L n base ++ ovfD L (base + ufSize n) ++ [i0, i1, i2]`. -/
theorem xat_uf_ovf {code : List (Instr Nat)} {L : Layout} {base n : Nat} (hn : 0 < n)
    {i0 i1 i2 : Instr Nat} {rest : List (Instr Nat)} (hrest : rest = [i0, i1, i2])
    (hat : XAt code base (uf L n base ++ ovfD L (base + ufSize n) ++ rest)) :
    XAt code base (uf L n base) ∧ XAt code (base + 4) (ovfD L (base + 4)) ∧
      code[base + 8]? = some i0 ∧ code[base + 8 + 1]? = some i1 ∧ code[base + 8 + 1 + 1]? = some i2 := by
  subst hrest
  rw [ufSize_pos hn] at hat
  obtain ⟨hatuo, hatr⟩ := xat_append.mp hat
  obtain ⟨hatuf, hato⟩ := xat_append.mp hatuo
  have hufl : (uf L n base).length = 4 := by rw [uf_eq L hn]; rfl
  rw [hufl] at hato
  have hl : (uf L n base ++ ovfD L (base + 4)).length = 8 := by simp [hufl, ovfD]
  rw [hl] at hatr
  obtain ⟨f0, f1, f2, _⟩ := hatr
  exact ⟨hatuf, hato, f0, f1, f2⟩

section Ops

variable {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
  {L : Layout} {base : Nat} {off : Nat → Nat}

theorem sim_not_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .not)) {a : W} {d : List W}
    (hd : s.dstack = a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (~~~a) :: d } x' ∧
      x'.pc = base + isize (.not : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 1 base ++ [.load rax Reg.r15 0, .not rax, .store Reg.r15 0 rax]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 1 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1 (j := 0) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3⟩ := not_step (code := code) hr2 (fetch_cast f1 (by omega))
  obtain ⟨x4, hs4, hr4, hpc4, _⟩ := st_step (code := code) hg hr3 (j := 0) (by simp [hd])
    (rs := rax) (disp := 0) (by simp) (fetch_cast f2 (by omega))
  have e : s.dstack.set 0 (x3.regs rax) = (~~~a) :: d := by simp [hd, hv3, hv2]
  rw [e] at hr4
  exact ⟨x4, ((hs1.trans hs2).trans hs3).trans hs4, hr4, by simp [isize, ufSize]; omega⟩

theorem sim_dup_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off .dup)) {a : W}
    {d : List W} (hd : s.dstack = a :: d) (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := a :: a :: d } x' ∧
      x'.pc = base + isize (.dup : WordDialect.Instr 64) := by
  obtain ⟨hatuf, hato, f0, f1, f2⟩ := xat_uf_ovf (L := L) (n := 1) (by decide) rfl hat
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfD_pass hg hr1 hLd hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1' (j := 0) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, _⟩ := push_pair hg hr2 rax (by decide) hfit
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩
  rw [hv2, hd] at hr3
  exact ⟨x3, ((hs1.trans hs1').trans hs2).trans hs3, hr3, by simp [isize, ufSize]; omega⟩

theorem sim_dup_ovf (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off .dup)) {a : W}
    {d : List W} (hd : s.dstack = a :: d) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    XExec code x .overflow := by
  obtain ⟨hatuf, hato, _⟩ := xat_uf_ovf (L := L) (n := 1) (by decide) rfl hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := uf_pass hg hs hL (by decide) (by decide) (by simp [hd]) hpc hatuf
  exact XExec.of_steps hs1 (ovfD_trap hg hr1 hLd h hpc1 hato)

theorem sim_drop_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .drop)) {a : W} {d : List W}
    (hd : s.dstack = a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := d } x' ∧
      x'.pc = base + isize (.drop : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 1 base ++ [.addImm Reg.r15 8]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 1 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, _⟩ := hatr
  have hk : 1 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, _⟩ := adj_step (code := code) hg hr1 (n := 1) (by simp [hd])
    (δ := 8) (by simp) (fetch_cast f0 (by omega))
  have e : (s.dstack).drop 1 = d := by simp [hd]
  rw [e] at hr2
  exact ⟨x2, hs1.trans hs2, hr2, by simp [isize, ufSize]; omega⟩

theorem sim_word_ok (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) (w : W)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off (.word w)))
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := w :: s.dstack } x' ∧
      x'.pc = base + isize (.word w : WordDialect.Instr 64) := by
  obtain ⟨hato, f0, f1, f2⟩ := xat_ovf3 (L := L) (by exact hat)
  obtain ⟨x0, hs0, hr0, hpc0, _, _⟩ := ovfD_pass hg hs hLd hfit hpc hato
  obtain ⟨x1, hs1, hr1, hpc1, hv1, _⟩ := movimm_step (code := code) hr0 (rd := rax) (by simp)
    (v := w) (by rw [hpc0]; exact f0)
  obtain ⟨x2, hs2, hr2, hpc2, _⟩ := push_pair hg hr1 rax (by decide) hfit
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩
  rw [hv1] at hr2
  exact ⟨x2, (hs0.trans hs1).trans hs2, hr2, by simp [isize]; omega⟩

theorem sim_word_ovf (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) (w : W)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off (.word w)))
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) : XExec code x .overflow := by
  obtain ⟨hato, _⟩ := xat_ovf3 (L := L) (by exact hat)
  exact ovfD_trap hg hs hLd h hpc hato

theorem sim_ptr_ok (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) (q : WordDialect.Ptr 64)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off (.ptr q)))
    (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := q.toWord :: s.dstack } x' ∧
      x'.pc = base + isize (.ptr q : WordDialect.Instr 64) :=
  sim_word_ok (L := L) (off := off) hg hs hpc q.toWord hLd hat hfit

theorem sim_ptr_ovf (hg : Geom c) (hs : Rel0 c p s x) (hpc : x.pc = base) (q : WordDialect.Ptr 64)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off (.ptr q)))
    (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) : XExec code x .overflow :=
  sim_word_ovf (L := L) (off := off) hg hs hpc q.toWord hLd hat h

theorem sim_swap_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .swap)) {b a : W} {d : List W}
    (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := a :: b :: d } x' ∧
      x'.pc = base + isize (.swap : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 2 base ++ [.load rax Reg.r15 0, .load rcx Reg.r15 8,
      .store Reg.r15 0 rcx, .store Reg.r15 8 rax]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 2 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, _⟩ := hatr
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1 (j := 0) (v := b)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := a)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  have hax3 : x3.regs rax = b := by rw [ho3 rax (by decide), hv2]
  obtain ⟨x4, hs4, hr4, hpc4, hreg4⟩ := st_step (code := code) hg hr3 (j := 0) (by simp [hd])
    (rs := rcx) (disp := 0) (by simp) (fetch_cast f2 (by omega))
  have hlen : 1 < ({ s with dstack := s.dstack.set 0 (x3.regs rcx) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x5, hs5, hr5, hpc5, _⟩ := st_step (code := code) hg hr4 (j := 1) hlen
    (rs := rax) (disp := 8) (by simp) (fetch_cast f3 (by omega))
  have hr5' : Rel0 c p { s with dstack := (s.dstack.set 0 (x3.regs rcx)).set 1 (x4.regs rax) } x5 := hr5
  have e : (s.dstack.set 0 (x3.regs rcx)).set 1 (x4.regs rax) = a :: b :: d := by
    simp [hd, hv3, hreg4, hax3]
  rw [e] at hr5'
  exact ⟨x5, (((hs1.trans hs2).trans hs3).trans hs4).trans hs5, hr5', by simp [isize, ufSize]; omega⟩

theorem sim_over_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off .over)) {b a : W}
    {d : List W} (hd : s.dstack = b :: a :: d) (hfit : c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := a :: b :: a :: d } x' ∧
      x'.pc = base + isize (.over : WordDialect.Instr 64) := by
  obtain ⟨hatuf, hato, f0, f1, f2⟩ := xat_uf_ovf (L := L) (n := 2) (by decide) rfl hat
  have hk : 2 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x1', hs1', hr1', hpc1', _, _⟩ := ovfD_pass hg hr1 hLd hfit hpc1 hato
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1' (j := 1) (v := a)
    (by simp [hd]) (rd := rax) (by simp) (disp := 8) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, _⟩ := push_pair hg hr2 rax (by decide) hfit
    ⟨fetch_cast f1 (by omega), fetch_cast f2 (by omega), trivial⟩
  rw [hv2, hd] at hr3
  exact ⟨x3, ((hs1.trans hs1').trans hs2).trans hs3, hr3, by simp [isize, ufSize]; omega⟩

theorem sim_over_ovf (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hLd : L.dLim = ofN (c.dBase + 8)) (hat : XAt code base (lowerInstr L base off .over)) {b a : W}
    {d : List W} (hd : s.dstack = b :: a :: d) (h : ¬ c.dBase + 8 * (s.dstack.length + 1) ≤ c.dEnd) :
    XExec code x .overflow := by
  obtain ⟨hatuf, hato, _⟩ := xat_uf_ovf (L := L) (n := 2) (by decide) rfl hat
  obtain ⟨x1, hs1, hr1, hpc1, _, _⟩ := uf_pass hg hs hL (by decide) (by decide) (by simp [hd]) hpc hatuf
  exact XExec.of_steps hs1 (ovfD_trap hg hr1 hLd h hpc1 hato)

theorem sim_rot_ok (hg : Geom c) (hL : L.dEnd = ofN c.dEnd) (hs : Rel0 c p s x) (hpc : x.pc = base)
    (hat : XAt code base (lowerInstr L base off .rot)) {cc b a : W} {d : List W}
    (hd : s.dstack = cc :: b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := a :: cc :: b :: d } x' ∧
      x'.pc = base + isize (.rot : WordDialect.Instr 64) := by
  have hat' : XAt code base (uf L 3 base ++ [.load rax Reg.r15 0, .load rcx Reg.r15 8,
      .load rdx Reg.r15 16, .store Reg.r15 0 rdx, .store Reg.r15 8 rax, .store Reg.r15 16 rcx]) := hat
  obtain ⟨hatuf, hatr⟩ := xat_append.mp hat'
  have hufl : (uf L 3 base).length = 4 := by simp [uf]
  rw [hufl] at hatr
  obtain ⟨f0, f1, f2, f3, f4, f5, _⟩ := hatr
  have hk : 3 ≤ s.dstack.length := by simp [hd]
  obtain ⟨x1, hs1, hr1, hpc1, hm1, _⟩ := uf_pass hg hs hL (by decide) (by decide) hk hpc hatuf
  obtain ⟨x2, hs2, hr2, hpc2, hv2, _, _⟩ := ld_step (code := code) hr1 (j := 0) (v := cc)
    (by simp [hd]) (rd := rax) (by simp) (disp := 0) (by simp) (fetch_cast f0 (by omega))
  obtain ⟨x3, hs3, hr3, hpc3, hv3, ho3, _⟩ := ld_step (code := code) hr2 (j := 1) (v := b)
    (by simp [hd]) (rd := rcx) (by simp) (disp := 8) (by simp) (fetch_cast f1 (by omega))
  obtain ⟨x4, hs4, hr4, hpc4, hv4, ho4, _⟩ := ld_step (code := code) hr3 (j := 2) (v := a)
    (by simp [hd]) (rd := rdx) (by simp) (disp := 16) (by simp) (fetch_cast f2 (by omega))
  have hax4 : x4.regs rax = cc := by rw [ho4 rax (by decide), ho3 rax (by decide), hv2]
  have hcx4 : x4.regs rcx = b := by rw [ho4 rcx (by decide), hv3]
  obtain ⟨x5, hs5, hr5, hpc5, hreg5⟩ := st_step (code := code) hg hr4 (j := 0) (by simp [hd])
    (rs := rdx) (disp := 0) (by simp) (fetch_cast f3 (by omega))
  have hl1 : 1 < ({ s with dstack := s.dstack.set 0 (x4.regs rdx) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x6, hs6, hr6, hpc6, hreg6⟩ := st_step (code := code) hg hr5 (j := 1) hl1
    (rs := rax) (disp := 8) (by simp) (fetch_cast f4 (by omega))
  have hl2 : 2 < ({ { s with dstack := s.dstack.set 0 (x4.regs rdx) } with
      dstack := (s.dstack.set 0 (x4.regs rdx)).set 1 (x5.regs rax) } : State 64).dstack.length := by
    simp [hd]
  obtain ⟨x7, hs7, hr7, hpc7, _⟩ := st_step (code := code) hg hr6 (j := 2) hl2
    (rs := rcx) (disp := 16) (by simp) (fetch_cast f5 (by omega))
  have hr7' : Rel0 c p { s with dstack := ((s.dstack.set 0 (x4.regs rdx)).set 1 (x5.regs rax)).set 2 (x6.regs rcx) } x7 := hr7
  have e : ((s.dstack.set 0 (x4.regs rdx)).set 1 (x5.regs rax)).set 2 (x6.regs rcx) =
      a :: cc :: b :: d := by
    simp [hd, hv4, hreg5, hreg6, hax4, hcx4]
  rw [e] at hr7'
  exact ⟨x7, (((((hs1.trans hs2).trans hs3).trans hs4).trans hs5).trans hs6).trans hs7, hr7',
    by simp [isize, ufSize]; omega⟩

end Ops

end X86
end WordDialect
