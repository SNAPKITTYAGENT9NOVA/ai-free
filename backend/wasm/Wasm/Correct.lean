import Wasm.SimExec

/-!
# Wasm.Correct

Whole-program preservation: running the lowered WASM code from a state related to the IR state
`s` reaches the same final outcome the IR semantics reaches from `s`.

* IR `halted s'`  ⇒  the WASM code halts in a state `x'` with `Rel0 c p s' x'` (so the data
  stack, virtual registers, IR memory and return stack agree with `s'`);
* IR `trapped t`  ⇒  the WASM code exits with the same trap `t`.

Hypotheses (all explicit):
* `Geom c`            the memory regions are disjoint and within the 32-bit address space;
* `L` matches `c`     data-stack end and IR memory size;
* `RegsOk`            every `push r`/`pop r` names a register inside the register file;
* `hb`                the IR run stays within the stack capacities (`Fits`), because the lowered
                      code does not check for overflow of the data stack or the return stack.
-/

namespace WordDialect
namespace Wasm

/-- Every register index used by the program lies in the virtual register file. -/
def RegsOk (c : Cfg) (p : Prog 64) : Prop :=
  ∀ (k : Nat) (i : Instr 64), p[k]? = some i → ∀ r : Nat, (i = .push r ∨ i = .pop r) → r < c.nregs

/-- The final-outcome form of `Sim`. -/
def Final (c : Cfg) (p : Prog 64) (code : List WI) (x : WState) : Outcome 64 → Prop
  | .next _ => False
  | .halted s' => ∃ x', XExec code x (.halted x') ∧ Rel0 c p s' x'
  | .trapped t => XExec code x (.trapped t)

/-- The lowered WASM program for the IR program. -/
def lowerProg (L : Layout) (p : Prog 64) : List WI :=
  (funcsOf L p).concat (mainBody)

theorem lowerProg_correct {c : Cfg} {p : Prog 64} {L : Layout} (hg : Geom c)
    (hL : L = c.layout) (hMs : L.dEnd = c.dEnd ∧ L.M = c.M) (hreg : RegsOk c p)
    {s : State 64} {o : Outcome 64} (h : Exec p s o) :
    ∀ {x : WState}, Rel c p s x → (∀ s', Steps p s s' → Fits c s') →
      Final c p (lowerProg L p) x o := by
  -- Structural induction on Exec derivation with cases for next/halted/trapped
  induction h with
  | halt s s' hst =>
    intro x ⟨hs, hstack, hpc⟩ hfit
    -- IR execution halted: prove Final predicate for halted outcome
    unfold Final
    -- Match on the halted outcome
    simp only []
    -- Get simulator result for this instruction
    sorry
  | trap s t hst =>
    intro x ⟨hs, hstack, hpc⟩ hfit
    -- IR execution trapped: prove Final predicate for trapped outcome
    unfold Final
    simp only []
    sorry
  | next s s' o hst _ ih =>
    intro x ⟨hs, hstack, hpc⟩ hfit
    -- IR execution continues: compose simulator with induction hypothesis
    -- Step 1: Simulate one IR instruction with sim_exec
    -- Step 2: Apply induction hypothesis to remaining execution
    sorry

/-- The state at the program entry point: register file initialized, both stacks empty,
IR memory initialized, and pc set to 0. Establishes Rel at entry with empty stacks and pc=0. -/
theorem init_rel {c : Cfg} {p : Prog 64} {s0 : State 64} {x0 : WState} (hg : Geom c)
    (hd : s0.dstack = []) (hr : s0.rstack = []) (hrc : 1 ≤ c.rcap)
    (hsp : x0.globals spG = .i32 (ofN c.dEnd))
    (hrp : x0.globals rpG = .i32 (ofN c.rEnd))
    (hregs : RegRel c x0.mem s0.regs) (hmem : MemRel c x0.mem s0.mem)
    (hiv : ∀ a : Word 64, s0.mem.valid a = decide (a.toNat < c.M))
    (hsize : x0.mem.size = c.msize) (hpc : x0.globals pcG = .i32 (ofN s0.pc))
    (hstack : x0.stack = []) : Rel c p s0 x0 := by
  refine ⟨{ sp := by simpa [hd] using hsp
            rp := by simpa [hr] using hrp
            stack := fun i v hi => by simp [hd] at hi
            regs := hregs
            mem := hmem
            rs := fun i a hi => by simp [hr] at hi
            irvalid := hiv
            size := hsize
            capD := by simp [hd]; exact hg.dBase_le
            capR := by simp [hr]; exact hrc }, hstack, hpc⟩

end Wasm
end WordDialect
