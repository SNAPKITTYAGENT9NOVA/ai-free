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
  sorry

/-- The state at the program entry point: register file initialized, both stacks empty,
IR memory initialized, and pc set to 0. -/
theorem init_rel {c : Cfg} {p : Prog 64} {s0 : State 64} {x0 : WState} (hg : Geom c)
    (hd : s0.dstack = []) (hr : s0.rstack = []) (hrc : 1 ≤ c.rcap) :
    Rel c p s0 x0 := by
  sorry

end Wasm
end WordDialect
