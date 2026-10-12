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


/-! ## Upper bounds

The dual question: how deep can the data stack get? IR stacks are unbounded, so every backend
guards each instruction that grows the data stack with an overflow check (exit 6 when the target's
stack is full). A *bound* `b` claims an upper bound `b.bound k` on the depth at instruction `k`;
where `b.bound k + 1` words fit, the check cannot fire and a backend may drop it.

Unlike lower bounds, an upper bound has no trivial value in the IR, where recursion can grow the
stack without limit. The target's capacity `cap` supplies one: a backend only runs while the
depth is at most `cap` (its other guards see to that), so the checker reasons from
`min (b.bound k) cap`, and a bound of `cap + 3` everywhere (`Bound.top`) always checks.

Returns are handled context-insensitively: `b.ret` bounds the depth at every `ret`, and every
return point (the instruction after a `call`) must allow `b.ret`.

The rules `boundOk` checks, for each instruction `i` at `k`:
* each successor `t` gets `min (b.bound k) cap - pops i + pushes i ≤ b.bound t`;
* a `call` at `k` gets `b.ret ≤ b.bound (k + 1)`;
* a `ret` at `k` gets `min (b.bound k) cap ≤ b.ret`.
No rule is needed at the entry: the stack starts empty.
-/

theorem Instr.pushes_le (i : Instr n) : i.pushes ≤ 3 := by cases i <;> simp [Instr.pushes]

/-- An upper-bound certificate: a bound per instruction, and one for every `ret`. -/
structure Bound where
  bound : Nat → Nat
  ret : Nat

/-- The bound that claims nothing beyond the capacity. -/
def Bound.top (cap : Nat) : Bound := ⟨fun _ => cap + 3, cap + 3⟩

/-- The checker for upper bounds against capacity `cap`. -/
def boundOk (p : Prog n) (cap : Nat) (b : Bound) : Bool :=
  p.zipIdx.all fun (i, k) =>
    (i.succs k).all (fun t => decide (min (b.bound k) cap - i.pops + i.pushes ≤ b.bound t)) &&
    (match i with
     | .call _ => decide (b.ret ≤ b.bound (k + 1))
     | .ret => decide (min (b.bound k) cap ≤ b.ret)
     | _ => true)

/-- The upper bounds hold in state `s`: at the current instruction, and every return address on
the return stack allows `b.ret`. -/
structure BoundInv (b : Bound) (s : State n) : Prop where
  depth : s.dstack.length ≤ b.bound s.pc
  rets : ∀ a ∈ s.rstack, b.ret ≤ b.bound a

theorem boundOk_at {p : Prog n} {cap : Nat} {b : Bound} (h : boundOk p cap b = true) {k : Nat}
    {i : Instr n} (hk : p[k]? = some i) :
    (∀ t ∈ i.succs k, min (b.bound k) cap - i.pops + i.pushes ≤ b.bound t) ∧
      (∀ t, i = .call t → b.ret ≤ b.bound (k + 1)) ∧
      (i = .ret → min (b.bound k) cap ≤ b.ret) := by
  simp only [boundOk, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq] at h
  have hmem : (i, k) ∈ p.zipIdx := by
    rw [List.mem_zipIdx_iff_getElem?]; simpa using hk
  obtain ⟨hs, hc⟩ := h _ hmem
  refine ⟨hs, ?_, ?_⟩
  · rintro t rfl; simpa using hc
  · rintro rfl; simpa using hc

theorem boundOk_top (p : Prog n) (cap : Nat) : boundOk p cap (Bound.top cap) = true := by
  simp only [boundOk, Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq]
  intro x _
  refine ⟨fun _ _ => ?_, ?_⟩
  · have := Instr.pushes_le x.1
    simp only [Bound.top]
    omega
  · split <;> simp [Bound.top]

theorem BoundInv.init (b : Bound) (mem : Memory n) : BoundInv b (State.init mem) where
  depth := by simp [State.init]
  rets := by simp [State.init]

/-- **Soundness of the checker:** one step from a state within the capacity keeps the bounds. -/
theorem BoundInv.step {p : Prog n} {cap : Nat} {b : Bound} (hok : boundOk p cap b = true)
    {s s' : State n} (hi : BoundInv b s) (hcap : s.dstack.length ≤ cap)
    (h : WordDialect.step p s = .next s') : BoundInv b s' := by
  unfold WordDialect.step at h
  split at h
  · cases h
  · rename_i i hk
    obtain ⟨hsucc, hcall, hret⟩ := boundOk_at hok hk
    have hdep := exec_depth i s s' h
    have hd := hi.depth
    have hm : s.dstack.length ≤ min (b.bound s.pc) cap := Nat.le_min.mpr ⟨hd, hcap⟩
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
    · have hr := hret rfl
      simp only [Instr.pops, Instr.pushes] at hdep
      refine ⟨?_, ?_⟩
      · have := hi.rets s'.pc (by rw [hrs]; simp)
        omega
      · intro a ha; exact hi.rets a (by rw [hrs]; simp [ha])

/-- An untrusted analysis for upper bounds: the least solution of the `boundOk` rules, by
iteration from `0` (it exists, every value being at most `cap + 3`). Its result is used only
when `boundOk` accepts it. -/
def analyseBound (p : Prog n) (cap : Nat) : Array Nat × Nat := Id.run do
  let len := p.length
  let mut u : Array Nat := Array.replicate (len + 1) 0
  let mut r := 0
  for _ in List.range (4 * len + 2 * cap + 16) do
    let mut changed := false
    for (i, k) in p.zipIdx do
      let m := min u[k]! cap
      let out := m - i.pops + i.pushes
      for t in i.succs k do
        if t ≤ len && u[t]! < out then
          u := u.set! t out
          changed := true
      match i with
      | .call _ =>
        if u[k + 1]! < r then
          u := u.set! (k + 1) r
          changed := true
      | .ret =>
        if r < m then
          r := m
          changed := true
      | _ => pure ()
    if !changed then break
  return (u, r)

/-- The checked bound: the analysis when `boundOk` accepts it (reading `cap + 3` outside its
table), else `Bound.top`. -/
def boundTable (p : Prog n) (cap : Nat) : Bound :=
  let a := analyseBound p cap
  let b : Bound := ⟨fun k => a.1.getD k (cap + 3), a.2⟩
  if boundOk p cap b then b else Bound.top cap

theorem boundTable_ok (p : Prog n) (cap : Nat) : boundOk p cap (boundTable p cap) = true := by
  unfold boundTable
  simp only []
  split
  · assumption
  · exact boundOk_top p cap

/-! ## Sound upper bounds, and how to combine them

`UbSound p cap u` says `u` is an upper bound on the data-stack depth that some invariant
guarantees: it holds initially, it is kept by every step taken from a state within the capacity
`cap`, and it implies `depth ≤ u pc`. This is all a backend needs to drop an overflow guard where
`u k + 1 ≤ cap`. Sound bounds combine by `min` (`UbSound.min`), so independent analyses can be
used together.
-/

/-- An upper bound backed by an invariant. -/
def UbSound (p : Prog n) (cap : Nat) (u : Nat → Nat) : Prop :=
  ∃ I : State n → Prop, (∀ mem, I (State.init mem)) ∧
    (∀ s s', I s → s.dstack.length ≤ cap → WordDialect.step p s = .next s' → I s') ∧
    (∀ s, I s → s.dstack.length ≤ u s.pc)

theorem boundOk_sound {p : Prog n} {cap : Nat} {b : Bound} (h : boundOk p cap b = true) :
    UbSound p cap b.bound :=
  ⟨BoundInv b, fun mem => BoundInv.init b mem, fun _ _ hi hc hs => BoundInv.step h hi hc hs,
    fun _ hi => hi.depth⟩

theorem UbSound.min {p : Prog n} {cap : Nat} {u v : Nat → Nat} (hu : UbSound p cap u)
    (hv : UbSound p cap v) : UbSound p cap (fun k => Nat.min (u k) (v k)) := by
  obtain ⟨I, i0, is, ib⟩ := hu
  obtain ⟨J, j0, js, jb⟩ := hv
  exact ⟨fun s => I s ∧ J s, fun m => ⟨i0 m, j0 m⟩,
    fun s s' h hc hs => ⟨is s s' h.1 hc hs, js s s' h.2 hc hs⟩,
    fun s h => Nat.le_min.mpr ⟨ib s h.1, jb s h.2⟩⟩

theorem UbSound.mono {p : Prog n} {cap : Nat} {u v : Nat → Nat} (hu : UbSound p cap u)
    (hle : ∀ k, u k ≤ v k) : UbSound p cap v := by
  obtain ⟨I, i0, is, ib⟩ := hu
  exact ⟨I, i0, is, fun s h => Nat.le_trans (ib s h) (hle _)⟩

/-- Within the capacity, one step adds at most three words. -/
theorem ubSound_top (p : Prog n) (cap : Nat) : UbSound p cap (fun _ => cap + 3) := by
  refine ⟨fun s => s.dstack.length ≤ cap + 3, fun _ => by simp [State.init], ?_, fun _ h => h⟩
  intro s s' _ hc h
  unfold WordDialect.step at h
  split at h
  · cases h
  · rename_i i _
    have := exec_depth i s s' h
    have := Instr.pushes_le i
    omega

/-! ## Per-word stack effects

The bound above treats every return alike, so one recursive word, whose depth is unbounded,
saturates the bound after every call in the program. A *frame certificate* tracks depth relative
to the frame of the word being executed instead. For each live instruction `k` it gives the word
`fn k` it belongs to (the entry of that word) and a bound `rel k` on the depth relative to the
depth at the word's entry; for each word `f` it gives `eff f`, a bound on that relative depth at
its `ret`s (its net stack effect), and `base f`, a bound on the depth at its entry. The absolute
bound at `k` is `base (fn k) + rel k`.

A call then leaves the caller at `rel` plus the callee's effect, whatever the callee does in
between. Even a recursive word with a balanced effect (`sum.fs`) leaves its callers bounded: only
the word's own body, whose `base` saturates at the capacity, keeps its guards.

The checker `frameOk` checks, for every live instruction `i` at `k` (with `m = min (rel k) cap`):
* a `call t`: `t` is live, is the entry of its own word (`fn t = t`), `rel t ≥ 0`; the return
  point `k + 1` is live in the caller's word, with `rel (k + 1) ≥ m + eff t`; and
  `base t ≥ min cap (base (fn k) + rel k)`;
* a `ret`: `m ≤ eff (fn k)`;
* any other instruction: each successor `t` is live, in the same word, with
  `rel t ≥ m - pops + pushes`;
and at the entry: `0` is live, `rel 0 ≥ 0` and `base (fn 0) ≥ 0`.

`FrameInv` carries the actual entry depth of every active word, one per return-stack entry
(`Frames.chain`), and `FrameInv.step` proves the checker sound.
-/

/-- A frame certificate. -/
structure Frames where
  live : Nat → Bool
  fn : Nat → Nat
  rel : Nat → Int
  eff : Nat → Int
  base : Nat → Int

/-- The absolute upper bound a frame certificate gives at instruction `k`. -/
def Frames.ub (fr : Frames) (k : Nat) : Nat := (fr.base (fr.fn k) + fr.rel k).toNat

/-- The local rule for one live instruction. -/
def frameStep (cap : Nat) (fr : Frames) (k : Nat) : Instr n → Bool
  | .call t => fr.live t && decide (fr.fn t = t) && decide (0 ≤ fr.rel t) && fr.live (k + 1) &&
      decide (fr.fn (k + 1) = fr.fn k) &&
      decide (min (fr.rel k) (cap : Int) + fr.eff t ≤ fr.rel (k + 1)) &&
      decide (min (cap : Int) (fr.base (fr.fn k) + fr.rel k) ≤ fr.base t)
  | .ret => decide (min (fr.rel k) (cap : Int) ≤ fr.eff (fr.fn k))
  | i => (i.succs k).all fun t => fr.live t && decide (fr.fn t = fr.fn k) &&
      decide (min (fr.rel k) (cap : Int) - i.pops + i.pushes ≤ fr.rel t)

/-- The checker for frame certificates. -/
def frameOk (p : Prog n) (cap : Nat) (fr : Frames) : Bool :=
  fr.live 0 && decide (0 ≤ fr.rel 0) && decide (0 ≤ fr.base (fr.fn 0)) &&
  p.zipIdx.all fun (i, k) => !fr.live k || frameStep cap fr k i

theorem frameOk_at {p : Prog n} {cap : Nat} {fr : Frames} (h : frameOk p cap fr = true) {k : Nat}
    {i : Instr n} (hk : p[k]? = some i) (hl : fr.live k = true) : frameStep cap fr k i = true := by
  simp only [frameOk, Bool.and_eq_true, List.all_eq_true] at h
  have hmem : (i, k) ∈ p.zipIdx := by
    rw [List.mem_zipIdx_iff_getElem?]; simpa using hk
  have := h.2 _ hmem
  simpa [hl] using this

theorem frameStep_flow {cap : Nat} {fr : Frames} {k : Nat} {i : Instr n}
    (hst : frameStep cap fr k i = true) (hc : ∀ t, i ≠ .call t) (hr : i ≠ .ret) :
    ∀ t ∈ i.succs k, fr.live t = true ∧ fr.fn t = fr.fn k ∧
      min (fr.rel k) (cap : Int) - i.pops + i.pushes ≤ fr.rel t := by
  cases i <;> first
    | exact absurd rfl (hc _)
    | exact absurd rfl hr
    | (simp only [frameStep, List.all_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hst
       exact fun t ht => (fun h => ⟨h.1.1, h.1.2, h.2⟩) (hst t ht))

/-- The entry depths of the suspended words: `b` is the entry depth of the word `f` being left by
the next `ret`, which returns to `a` in a word entered at depth `b'`. -/
def Frames.chain (fr : Frames) : Nat → Nat → List Nat → List Nat → Prop
  | _, _, [], [] => True
  | b, f, a :: as, b' :: bs =>
      (b : Int) + fr.eff f ≤ (b' : Int) + fr.rel a ∧ (b' : Int) ≤ fr.base (fr.fn a) ∧
        fr.live a = true ∧ fr.chain b' (fr.fn a) as bs
  | _, _, _, _ => False

/-- The frame invariant: the current instruction is live, and there are entry depths for the
current word (`b0`) and every suspended one under which the bounds hold. -/
structure FrameInv (fr : Frames) (s : State n) : Prop where
  live : fr.live s.pc = true
  frame : ∃ (b0 : Nat) (bs : List Nat), (s.dstack.length : Int) ≤ b0 + fr.rel s.pc ∧
    (b0 : Int) ≤ fr.base (fr.fn s.pc) ∧ fr.chain b0 (fr.fn s.pc) s.rstack bs

theorem FrameInv.init {p : Prog n} {cap : Nat} {fr : Frames} (h : frameOk p cap fr = true)
    (mem : Memory n) : FrameInv fr (State.init mem) := by
  simp only [frameOk, Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨⟨hl, hr⟩, hb⟩, _⟩ := h
  refine ⟨by simpa [State.init] using hl, 0, [], ?_, ?_, ?_⟩
  · simpa [State.init] using hr
  · simpa [State.init] using hb
  · simp [State.init, Frames.chain]

/-- **Soundness of the frame checker:** one step from a state within the capacity keeps the
invariant. -/
theorem FrameInv.step {p : Prog n} {cap : Nat} {fr : Frames} (hok : frameOk p cap fr = true)
    {s s' : State n} (hi : FrameInv fr s) (hcap : s.dstack.length ≤ cap)
    (h : WordDialect.step p s = .next s') : FrameInv fr s' := by
  unfold WordDialect.step at h
  split at h
  · cases h
  · rename_i i hk
    have hst := frameOk_at hok hk hi.live
    have hdep := exec_depth i s s' h
    obtain ⟨b0, bs, hd, hb, hch⟩ := hi.frame
    have hmin : (s.dstack.length : Int) ≤ b0 + min (fr.rel s.pc) (cap : Int) := by
      rw [Int.min_def]; split <;> omega
    rcases exec_flow i s s' h with ⟨hpc, hrs⟩ | ⟨t, rfl, hpc, hrs⟩ | ⟨rfl, hrs⟩
    · have hc : ∀ t, i ≠ .call t := by
        rintro t rfl
        simp only [exec] at h
        cases h
        simp at hrs
      have hr : i ≠ .ret := by rintro rfl; simp [Instr.succs] at hpc
      obtain ⟨hl, hf, hrel⟩ := frameStep_flow hst hc hr _ hpc
      refine ⟨hl, b0, bs, ?_, ?_, ?_⟩
      · omega
      · rw [hf]; exact hb
      · rw [hf, hrs]; exact hch
    · simp only [frameStep, Bool.and_eq_true, decide_eq_true_eq] at hst
      obtain ⟨⟨⟨⟨⟨⟨hlt, hft⟩, hrt⟩, hl1⟩, hf1⟩, hr1⟩, hbt⟩ := hst
      simp only [Instr.pops, Instr.pushes] at hdep
      refine ⟨by rw [hpc]; exact hlt, s.dstack.length, b0 :: bs, ?_, ?_, ?_⟩
      · rw [hpc]; omega
      · rw [hpc, hft]
        have : (s.dstack.length : Int) ≤ fr.base (fr.fn s.pc) + fr.rel s.pc := by omega
        rw [Int.min_def] at hbt; split at hbt <;> omega
      · rw [hpc, hrs, hft]
        refine ⟨?_, ?_, hl1, ?_⟩
        · omega
        · rw [hf1]; exact hb
        · rw [hf1]; exact hch
    · simp only [frameStep, decide_eq_true_eq] at hst
      simp only [Instr.pops, Instr.pushes] at hdep
      rw [hrs] at hch
      cases bs with
      | nil => simp [Frames.chain] at hch
      | cons b1 bs =>
        obtain ⟨he, hb1, hla, hch'⟩ := hch
        refine ⟨hla, b1, bs, ?_, hb1, hch'⟩
        omega

theorem FrameInv.bound {fr : Frames} {s : State n} (hi : FrameInv fr s) :
    s.dstack.length ≤ fr.ub s.pc := by
  obtain ⟨b0, bs, hd, hb, _⟩ := hi.frame
  unfold Frames.ub
  omega

theorem frameOk_sound {p : Prog n} {cap : Nat} {fr : Frames} (h : frameOk p cap fr = true) :
    UbSound p cap fr.ub :=
  ⟨FrameInv fr, FrameInv.init h, fun _ _ hi hc hs => FrameInv.step h hi hc hs,
    fun _ hi => hi.bound⟩

/-- Raise entry `t` of a table of optional bounds to at least `v`. After 16 raises the entry
jumps to `top`, so the iteration ends. -/
def raiseOpt (a : Array (Option Int)) (cnt : Array Nat) (t : Nat) (v top : Int) :
    Array (Option Int) × Array Nat × Bool :=
  if t < a.size then
    match a[t]! with
    | some old =>
      if v ≤ old then (a, cnt, false)
      else
        let c := cnt[t]! + 1
        (a.set! t (some (if 16 < c then top else v)), cnt.set! t c, true)
    | none => (a.set! t (some v), cnt, true)
  else (a, cnt, false)

/-- The same for a table of bounds. -/
def raise (a : Array Int) (cnt : Array Nat) (t : Nat) (v top : Int) :
    Array Int × Array Nat × Bool :=
  if t < a.size && a[t]! < v then
    let c := cnt[t]! + 1
    (a.set! t (if 16 < c then top else v), cnt.set! t c, true)
  else (a, cnt, false)

/-- An untrusted analysis proposing a frame certificate: the live instructions and their words by
a walk from the entry (a `call t` starts word `t`), then the least relative bounds, effects and
entry bounds by iteration, with widening. Its result is used only when `frameOk` accepts it. -/
def analyseFrames (p : Prog n) (cap : Nat) : Frames := Id.run do
  let len := p.length
  let size := len + 2
  let mut live : Array Bool := Array.replicate size false
  let mut fn : Array Nat := Array.replicate size 0
  let mut work : List (Nat × Nat) := [(0, 0)]
  for _ in List.range (4 * size + 8) do
    match work with
    | [] => break
    | (k, f) :: rest =>
      work := rest
      if k < size && !live[k]! then
        live := live.set! k true
        fn := fn.set! k f
        match p[k]? with
        | some (.call t) => work := (t, t) :: (k + 1, f) :: work
        | some i => work := (i.succs k).map (fun t => (t, f)) ++ work
        | none => pure ()
  let capI : Int := cap
  let topRel : Int := 2 * capI + 16
  let effMin : Int := -(2 * capI + 16)
  let mut rel : Array (Option Int) := Array.replicate size none
  let mut relN : Array Nat := Array.replicate size 0
  let mut eff : Array Int := Array.replicate size effMin
  let mut effN : Array Nat := Array.replicate size 0
  let mut base : Array Int := Array.replicate size 0
  let mut baseN : Array Nat := Array.replicate size 0
  rel := rel.set! 0 (some 0)
  for (i, k) in p.zipIdx do
    if let .call t := i then
      if t < size && live[k]! then rel := rel.set! t (some 0)
  for _ in List.range (64 * size + 64) do
    let mut changed := false
    for (i, k) in p.zipIdx do
      if live[k]! then
        if let some r := rel[k]! then
          let m := min r capI
          match i with
          | .call t =>
            if t < size then
              let (a, c, ch) := raiseOpt rel relN (k + 1) (m + eff[t]!) topRel
              rel := a; relN := c; changed := changed || ch
              let (a, c, ch) := raise base baseN t (min capI (base[fn[k]!]! + r)) capI
              base := a; baseN := c; changed := changed || ch
          | .ret =>
            let (a, c, ch) := raise eff effN fn[k]! m capI
            eff := a; effN := c; changed := changed || ch
          | _ =>
            for t in i.succs k do
              let (a, c, ch) := raiseOpt rel relN t (m - i.pops + i.pushes) topRel
              rel := a; relN := c; changed := changed || ch
    if !changed then break
  return { live := fun k => live.getD k false, fn := fun k => fn.getD k 0,
           rel := fun k => (rel.getD k none).getD 0, eff := fun f => eff.getD f effMin,
           base := fun f => base.getD f 0 }

/-- The upper bounds the backends use, as a table: the least of the context-insensitive bound,
the frame certificate's bound (when `frameOk` accepts it) and `cap + 3`. -/
def upperTable (p : Prog n) (cap : Nat) : Array Nat :=
  let b := boundTable p cap
  let fr := analyseFrames p cap
  let ok := frameOk p cap fr
  (Array.range (p.length + 1)).map fun k =>
    Nat.min (Nat.min (b.bound k) (if ok then fr.ub k else cap + 3)) (cap + 3)

/-- Reading the table: `cap + 3` (no room) outside it. -/
def upperAt (a : Array Nat) (cap k : Nat) : Nat := a.getD k (cap + 3)

theorem upperTable_sound (p : Prog n) (cap : Nat) :
    UbSound p cap (fun k => upperAt (upperTable p cap) cap k) := by
  have hb := boundOk_sound (boundTable_ok p cap)
  have hf : UbSound p cap (fun k => if frameOk p cap (analyseFrames p cap) = true then
      (analyseFrames p cap).ub k else cap + 3) := by
    cases h : frameOk p cap (analyseFrames p cap)
    · simpa using ubSound_top p cap
    · simpa using frameOk_sound h
  refine UbSound.mono ((hb.min hf).min (ubSound_top p cap)) ?_
  intro k
  simp only [upperAt, upperTable, Array.getD_eq_getD_getElem?, Array.getElem?_map,
    Array.getElem?_range]
  split <;> split <;> simp <;> omega

end WordDialect
