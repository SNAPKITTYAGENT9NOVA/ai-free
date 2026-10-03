import X86.SimBin

/-!
# X86.SimOps

Per-instruction simulation theorems. Each states, for an IR instruction `i` whose lowered code
is placed at `base`:
* success: from a related state, the x86 model reaches a state related to the IR result;
* trap: when the IR traps with `t`, the x86 model exits with `t`.
-/

namespace WordDialect
namespace X86

open Reg

/-- Operand-count trap: any lowering that starts with `uf n` exits with `stackUnderflow`. -/
theorem sim_uf_trap {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base n : Nat} {rest : List (Instr Nat)} (hg : Geom c) (hs : Rel0 c p s x)
    (hL : L.dEnd = ofN c.dEnd) (hn : 0 < n) (hn3 : n ≤ 3) (hk : s.dstack.length < n)
    (hpc : x.pc = base) (hat : XAt code base (uf L n base ++ rest)) :
    XExec code x (.trapped .stackUnderflow) :=
  uf_trap hg hs hL hn hn3 hk hpc (xat_append.mp hat).1

macro "mid_tac" : tactic =>
  `(tactic| (intro m a b ha hb
             simp [xseq, exec, M.arith, M.mov, M.setReg, M.adv, ha, hb, MidSpec]))

theorem midspec_add : MidSpec [.add rax rcx] rax (· + ·) := by
  intro m a b ha hb
  refine ⟨m.arith rax (m.regs rax + m.regs rcx), by simp [xseq, exec], ?_⟩
  simp [M.arith, M.setReg, ha, hb]

theorem sim_add_ok {c : Cfg} {p : Prog 64} {s : State 64} {x : M} {code : List (Instr Nat)}
    {L : Layout} {base : Nat} {off : Nat → Nat} (hg : Geom c) (hL : L.dEnd = ofN c.dEnd)
    (hs : Rel0 c p s x) (hpc : x.pc = base) (hat : XAt code base (lowerInstr L base off .add))
    {b a : W} {d : List W} (hd : s.dstack = b :: a :: d) :
    ∃ x', XSteps code x x' ∧ Rel0 c p { s with dstack := (a + b) :: d } x' ∧
      x'.pc = base + isize (.add : WordDialect.Instr 64) := by
  have := sim_bin_ok hg hL hs hpc [.add rax rcx] rax (by simp) (· + ·) midspec_add
    (by simp [Instr.straightX]) (by simpa [lowerInstr] using hat) hd
  obtain ⟨x', h1, h2, h3⟩ := this
  exact ⟨x', h1, h2, by simpa [isize, ufSize] using h3⟩

end X86
end WordDialect
