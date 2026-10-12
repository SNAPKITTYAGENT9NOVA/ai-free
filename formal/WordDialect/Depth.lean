import WordDialect.Exec
import WordDialect.Invariants
import WordDialect.Init

/-!
# WordDialect.Depth

A verified stack-depth analysis: the basis of the first verified optimisation.

Every backend guards each instruction that pops with an operand-count check, because the IR traps
`stackUnderflow` when the data stack is too short. Most of those checks can never fail: after
`5 7`, an `add` always has its two operands. A *depth certificate* `c : Nat → Nat` claims a lower
bound `c k` on the data-stack depth whenever control is at instruction `k`. A backend may drop the
guard of an instruction that pops at most `c k` words.

The certificate comes from an untrusted analysis (`analyse`) and is checked by a decidable
`certOk`, which is proved sound (`DepthInv.step`): from a state where the bounds hold, one step
leads to a state where they hold again. They hold at the start (`DepthInv.init`), so they hold in
every reachable state (`DepthInv.steps`). `safeCert` is `analyse`'s result when it checks, and the
trivial certificate `0` (which always checks, and drops no guard) when it does not; so the
analysis can only make code smaller, never wrong.

The rules `certOk` checks, for each instruction `i` at `k` with operand count `pops i` (`WordDialect.Stack`):
* each successor `t` of `i` (where control goes when `i` does not trap) gets
  `c t ≤ c k - pops i + pushes i`, the depth `i` leaves (with natural-number subtraction, which
  stays sound when `c k < pops i`: then the actual depth is at least `pops i`);
* the instruction after a `call` gets `c (k + 1) = 0`: control returns there from anywhere;
* `c 0 = 0`: the program starts with an empty stack.
-/

namespace WordDialect

variable {n : Nat}

/-- Where control can go next from instruction `i` at `k` without a trap (`ret` goes to a return
address, covered by the rule for `call`; `halt` stops). -/
def Instr.succs (k : Nat) : Instr n → List Nat
  | .jmp t => [t]
  | .branch t => [k + 1, t]
  | .call t => [t]
  | .ret | .halt => []
  | _ => [k + 1]

/-- The checker. -/
def certOk (p : Prog n) (c : Nat → Nat) : Bool :=
  c 0 == 0 &&
  p.zipIdx.all fun (i, k) =>
    (i.succs k).all (fun t => decide (c t ≤ c k - i.pops + i.pushes)) &&
    (match i with | .call _ => c (k + 1) == 0 | _ => true)

/-- The bounds hold in state `s`: the depth at the current instruction, and `0` at every return
address on the return stack (where control can come back with any depth). -/
structure DepthInv (c : Nat → Nat) (s : State n) : Prop where
  depth : c s.pc ≤ s.dstack.length
  rets : ∀ a ∈ s.rstack, c a = 0

theorem certOk_at {p : Prog n} {c : Nat → Nat} (h : certOk p c = true) {k : Nat} {i : Instr n}
    (hk : p[k]? = some i) :
    (∀ t ∈ i.succs k, c t ≤ c k - i.pops + i.pushes) ∧
      (∀ t, i = .call t → c (k + 1) = 0) := by
  simp only [certOk, Bool.and_eq_true, beq_iff_eq, List.all_eq_true, decide_eq_true_eq] at h
  have hmem : (i, k) ∈ p.zipIdx := by
    rw [List.mem_zipIdx_iff_getElem?]; simpa using hk
  obtain ⟨hs, hc⟩ := h.2 _ hmem
  refine ⟨hs, ?_⟩
  rintro t rfl
  simpa using hc

theorem DepthInv.init {c : Nat → Nat} (h : c 0 = 0) (mem : Memory n) :
    DepthInv c (State.init mem) where
  depth := by simp [State.init, h]
  rets := by simp [State.init]

/-- Where control goes when an instruction continues: to one of its successors with the return
stack unchanged, or (`call`) to its target with the return address pushed, or (`ret`) to the
return address it pops. -/
theorem exec_flow (i : Instr n) (s s' : State n) (h : exec i s = .next s') :
    (s'.pc ∈ i.succs s.pc ∧ s'.rstack = s.rstack) ∨
      (∃ t, i = .call t ∧ s'.pc = t ∧ s'.rstack = (s.pc + 1) :: s.rstack) ∨
      (i = .ret ∧ s.rstack = s'.pc :: s'.rstack) := by
  obtain ⟨pc, d, rs, as, regs, mem⟩ := s
  cases i <;> rcases d with _ | ⟨x, _ | ⟨y, _ | ⟨z, d⟩⟩⟩ <;>
    simp only [exec, State.fall] at h <;>
    (try split at h) <;> (try split at h) <;> (try cases h) <;>
    simp_all [Instr.succs]

/-- **Soundness of the checker:** one step keeps the bounds. -/
theorem DepthInv.step {p : Prog n} {c : Nat → Nat} (hok : certOk p c = true) {s s' : State n}
    (hi : DepthInv c s) (h : WordDialect.step p s = .next s') : DepthInv c s' := by
  unfold WordDialect.step at h
  split at h
  · cases h
  · rename_i i hk
    obtain ⟨hsucc, hcall⟩ := certOk_at hok hk
    have hdep := exec_depth i s s' h
    have hpops : i.pops ≤ s.dstack.length := by
      rcases Nat.lt_or_ge s.dstack.length i.pops with hlt | hge
      · rw [exec_underflow i s hlt] at h; cases h
      · exact hge
    have hd := hi.depth
    rcases exec_flow i s s' h with ⟨hpc, hrs⟩ | ⟨t, rfl, hpc, hrs⟩ | ⟨rfl, hrs⟩
    · refine ⟨?_, by rw [hrs]; exact hi.rets⟩
      have := hsucc _ hpc
      omega
    · refine ⟨?_, ?_⟩
      · have := hsucc t (by simp [Instr.succs])
        simp only [Instr.pops, Instr.pushes] at this hdep
        rw [hpc]; omega
      · rw [hrs]; intro a ha
        simp only [List.mem_cons] at ha
        rcases ha with rfl | ha
        · exact hcall t rfl
        · exact hi.rets a ha
    · refine ⟨?_, ?_⟩
      · rw [hi.rets _ (by rw [hrs]; simp)]; exact Nat.zero_le _
      · intro a ha; exact hi.rets a (by rw [hrs]; simp [ha])

/-- The bounds hold in every state reachable from one where they hold. -/
theorem DepthInv.steps {p : Prog n} {c : Nat → Nat} (hok : certOk p c = true) {s s' : State n}
    (hi : DepthInv c s) (h : Steps p s s') : DepthInv c s' := by
  induction h with
  | refl => exact hi
  | cons hs _ ih => exact ih (DepthInv.step hok hi hs)

/-! ## The analysis (untrusted) -/

/-- A fixpoint iteration for the least depth at each instruction: start from "unreached", give
the entry, every return point and every instruction unreachable from those depth `0`, and propagate each instruction's depth effect to
its successors until nothing changes (or the iteration budget runs out). Not trusted: its result
is used only when `certOk` accepts it. -/
def analyse (p : Prog n) : Array Nat := Id.run do
  let len := p.length
  let unreached := len * 3 + 1000000
  -- Reachability from the entry and the return points. An instruction nothing reaches is given
  -- depth `0` and propagated from like the entry, so its successors' entries stay consistent.
  let mut live : Array Bool := Array.replicate (len + 1) false
  let mut work : List Nat := [0]
  for (i, k) in p.zipIdx do
    if let .call _ := i then work := (k + 1) :: work
  for _ in List.range (4 * len + 4) do
    match work with
    | [] => break
    | k :: rest =>
      work := rest
      if k ≤ len && !live[k]! then
        live := live.set! k true
        if let some i := p[k]? then work := i.succs k ++ work
  let mut d : Array Nat := Array.replicate (len + 1) unreached
  d := d.set! 0 0
  for (i, k) in p.zipIdx do
    if let .call _ := i then d := d.set! (k + 1) 0
  for k in List.range (len + 1) do
    if !live[k]! then d := d.set! k 0
  for _ in List.range (4 * len + 4) do
    let mut changed := false
    for (i, k) in p.zipIdx do
      let dk := d[k]!
      if dk == unreached then continue
      let out := dk - i.pops + i.pushes
      for t in i.succs k do
        if t ≤ len && out < d[t]! then
          d := d.set! t out
          changed := true
    if !changed then break
  return d.map fun x => if x == unreached then 0 else x

/-- The checked table: the analysis when `certOk` accepts it, else empty (no claims). An array
rather than a function, so a compiled caller computes it once. -/
def certTable (p : Prog n) : Array Nat :=
  let a := analyse p
  if certOk p (fun k => a.getD k 0) then a else #[]

/-- The certificate the backends use: the checked table, reading `0` outside it. -/
def safeCert (p : Prog n) : Nat → Nat := fun k => (certTable p).getD k 0

theorem certOk_zero (p : Prog n) : certOk p (fun _ => 0) = true := by
  simp only [certOk, beq_self_eq_true, Bool.true_and, List.all_eq_true, Bool.and_eq_true,
    decide_eq_true_eq]
  intro x _
  refine ⟨fun _ _ => Nat.zero_le _, ?_⟩
  split <;> rfl

theorem certTable_ok (p : Prog n) : certOk p (fun k => (certTable p).getD k 0) = true := by
  unfold certTable
  simp only []
  by_cases h : (certOk p fun k => (analyse p).getD k 0) = true
  · rw [if_pos h]; exact h
  · rw [if_neg h]; simpa using certOk_zero p

theorem safeCert_ok (p : Prog n) : certOk p (safeCert p) = true := certTable_ok p

/-- A checked certificate claims nothing at the entry point. -/
theorem certOk_entry {p : Prog n} {c : Nat → Nat} (h : certOk p c = true) : c 0 = 0 := by
  simp only [certOk, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1

theorem safeCert_zero (p : Prog n) : safeCert p 0 = 0 := certOk_entry (safeCert_ok p)

end WordDialect
