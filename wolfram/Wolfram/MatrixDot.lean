import Wolfram.MatrixLayout

/-!
# Wolfram.MatrixDot

Lowering of Wolfram `Dot[A, B]` (matrix product, `A : m×k`, `B : k×p`, result `C : m×p`) into
Universal Word IR. The IR never sees a matrix: the lowering emits three nested counted loops
over word memory,

    for i < m: for j < p: acc := 0; for l < k: acc := acc + A[i*k+l] * B[l*p+j];
                          C[i*p+j] := acc

with virtual registers `rI rJ rL rAcc` and row-major addressing.

This module defines the lowering and proves the innermost (accumulate) loop correct.
-/

namespace WordDialect
namespace Wolfram

open IR

abbrev rI : Nat := 0
abbrev rJ : Nat := 1
abbrev rL : Nat := 2
abbrev rAcc : Nat := 3

/-- Address of element `(row, col)` of a matrix with row length `stride` at `base`. -/
def idx2 {n : Nat} (rowR colR stride base : Nat) : RExpr n :=
  .add (.add (.mul (.reg rowR) (.const (BitVec.ofNat n stride))) (.reg colR))
    (.const (BitVec.ofNat n base))

def accExpr {n : Nat} (k p bA bB : Nat) : RExpr n :=
  .add (.reg rAcc) (.mul (.load (idx2 rI rL k bA)) (.load (idx2 rL rJ p bB)))

/-- `acc := acc + A[i,l] * B[l,j]`. -/
def accCode {n : Nat} (k p bA bB : Nat) : List (Instr n) :=
  (accExpr k p bA bB).code ++ [.pop rAcc]

/-- `C[i,j] := acc`. -/
def storeCode {n : Nat} (p bC : Nat) : List (Instr n) :=
  (RExpr.reg rAcc).code ++ (idx2 rI rJ p bC).code ++ [.store]

def innerLoop {n : Nat} (k p bA bB : Nat) : Frag n :=
  countedLoop rL k (Frag.ofCode (accCode k p bA bB))

/-- One output element: zero the accumulator, run the reduction, store. -/
def cellBody {n : Nat} (k p bA bB bC : Nat) : Frag n :=
  (Frag.ofCode (initCode rAcc)).seq
    ((innerLoop k p bA bB).seq (Frag.ofCode (storeCode p bC)))

def rowLoop {n : Nat} (k p bA bB bC : Nat) : Frag n :=
  countedLoop rJ p (cellBody k p bA bB bC)

/-- The lowering of `C = A . B`. -/
def dotFrag {n : Nat} (m k p bA bB bC : Nat) : Frag n :=
  countedLoop rI m (rowLoop k p bA bB bC)

/-- Numeric side conditions: sizes fit in a word, regions fit in the address space, and the
destination is disjoint from both sources. -/
structure DotGeom (n m k p bA bB bC : Nat) : Prop where
  hn : 0 < n
  hm : m < 2 ^ n
  hk : k < 2 ^ n
  hp : p < 2 ^ n
  hA : bA + m * k ≤ 2 ^ n
  hB : bB + k * p ≤ 2 ^ n
  hC : bC + m * p ≤ 2 ^ n
  dA : bC + m * p ≤ bA ∨ bA + m * k ≤ bC
  dB : bC + m * p ≤ bB ∨ bB + k * p ≤ bC

theorem idx_lt {i m t k : Nat} (hi : i < m) (ht : t < k) : i * k + t < m * k := by
  have h1 : (i + 1) * k ≤ m * k := Nat.mul_le_mul_right k hi
  have h2 : (i + 1) * k = i * k + k := Nat.succ_mul i k
  omega

theorem idx2_eval {n : Nat} (regs : Nat → Word n) (mem : Memory n)
    (rowR colR stride base i j : Nat)
    (hi : regs rowR = BitVec.ofNat n i) (hj : regs colR = BitVec.ofNat n j) :
    (idx2 rowR colR stride base : RExpr n).eval regs mem =
      .ok (BitVec.ofNat n (base + i * stride + j)) := by
  simp only [idx2, RExpr.eval, hi, hj]
  rw [← BitVec.ofNat_mul, ← BitVec.ofNat_add, ← BitVec.ofNat_add]
  congr 2
  omega

theorem accCode_straight {n : Nat} (k p bA bB : Nat) :
    ∀ i ∈ (accCode k p bA bB : List (Instr n)), i.isStraight = true := by
  intro i hi
  simp only [accCode, List.mem_append, List.mem_singleton] at hi
  rcases hi with hi | rfl
  · exact RExpr.code_straight _ i hi
  · rfl

theorem storeCode_straight {n : Nat} (p bC : Nat) :
    ∀ i ∈ (storeCode p bC : List (Instr n)), i.isStraight = true := by
  intro i hi
  simp only [storeCode, List.mem_append, List.mem_singleton] at hi
  rcases hi with (hi | hi) | rfl
  · exact RExpr.code_straight _ i hi
  · exact RExpr.code_straight _ i hi
  · rfl

/-- One step of the reduction: with counter `t < k` the body adds `A i t * B t j`. -/
theorem acc_step {n m k p bA bB bC : Nat} (G : DotGeom n m k p bA bB bC)
    {A B : Nat → Nat → Int} {mem0 : Memory n} {val : Nat → Word n} {cnt : Nat}
    (hA : MatAt mem0 bA m k A) (hB : MatAt mem0 bB k p B) (hcnt : cnt ≤ m * p)
    (s : State n) (i j t : Nat) (hi : i < m) (hj : j < p) (ht : t < k)
    (hcw : CWritten mem0 s.mem bC val cnt)
    (hri : s.regs rI = BitVec.ofNat n i) (hrj : s.regs rJ = BitVec.ofNat n j)
    (hrl : s.regs rL = BitVec.ofNat n t) :
    execSeq (accCode k p bA bB : List (Instr n)) s =
      .next { s with pc := s.pc + (accCode k p bA bB : List (Instr n)).length,
                     regs := State.setReg s.regs rAcc
                       (s.regs rAcc + BitVec.ofInt n (A i t) * BitVec.ofInt n (B t j)) } := by
  have hGA := G.hA
  have hGB := G.hB
  have hGC := G.hC
  have hAi : i * k + t < m * k := idx_lt hi ht
  have hBi : t * p + j < k * p := idx_lt ht hj
  have hreadA : s.mem.read? (BitVec.ofNat n (bA + i * k + t)) = some (BitVec.ofInt n (A i t)) := by
    rw [cwritten_read_other hcw (by omega) (by omega) (by rcases G.dA with h | h <;> omega)]
    exact hA i t hi ht
  have hreadB : s.mem.read? (BitVec.ofNat n (bB + t * p + j)) = some (BitVec.ofInt n (B t j)) := by
    rw [cwritten_read_other hcw (by omega) (by omega) (by rcases G.dB with h | h <;> omega)]
    exact hB t j ht hj
  have hev : (accExpr k p bA bB : RExpr n).eval s.regs s.mem =
      .ok (s.regs rAcc + BitVec.ofInt n (A i t) * BitVec.ofInt n (B t j)) := by
    simp only [accExpr, RExpr.eval]
    rw [idx2_eval s.regs s.mem rI rL k bA i t hri hrl,
        idx2_eval s.regs s.mem rL rJ p bB t j hrl hrj]
    simp [hreadA, hreadB]
  rw [accCode, execSeq_append, RExpr.code_ok _ s _ hev]
  simp [Outcome.andThen, execSeq, exec, State.fall, Nat.add_assoc]

/-- The accumulate loop computes `acc = Σ_{l<k} A i l * B l j` (mod `2^n`) and changes nothing
but its counter and the accumulator. -/
theorem inner_run {n m k p bA bB bC : Nat} (G : DotGeom n m k p bA bB bC)
    {A B : Nat → Nat → Int} {mem0 : Memory n} {val : Nat → Word n} {cnt : Nat}
    (hA : MatAt mem0 bA m k A) (hB : MatAt mem0 bB k p B) (hcnt : cnt ≤ m * p)
    {prog : Prog n} {b : Nat} (hat : At prog b ((innerLoop k p bA bB : Frag n).emit b))
    (s0 : State n) (hpc : s0.pc = b) (i j : Nat) (hi : i < m) (hj : j < p)
    (hcw : CWritten mem0 s0.mem bC val cnt)
    (hri : s0.regs rI = BitVec.ofNat n i) (hrj : s0.regs rJ = BitVec.ofNat n j)
    (hacc : s0.regs rAcc = 0#n) :
    ∃ s', Steps prog s0 s' ∧ s'.pc = b + (accCode k p bA bB : List (Instr n)).length + 12 ∧
      s'.dstack = s0.dstack ∧ s'.mem = s0.mem ∧ s'.regs rI = BitVec.ofNat n i ∧
      s'.regs rJ = BitVec.ofNat n j ∧
      s'.regs rAcc = BitVec.ofInt n (dotSum A B i j k) := by
  let Inv : Nat → State n → Prop := fun t s =>
    s.mem = s0.mem ∧ s.regs rI = BitVec.ofNat n i ∧ s.regs rJ = BitVec.ofNat n j ∧
      s.regs rAcc = BitVec.ofInt n (dotSum A B i j t)
  have hrun := countedLoop_run (r := rL) (N := k) (body := Frag.ofCode (accCode k p bA bB))
    G.hn G.hk (by simpa [innerLoop] using hat) Inv
    (by
      intro t s s' ⟨h1, h2, h3, h4⟩ hm _ _ hr
      exact ⟨hm.trans h1, (hr rI (by decide)).trans h2, (hr rJ (by decide)).trans h3,
        (hr rAcc (by decide)).trans h4⟩)
    (by
      intro t s ht ⟨h1, h2, h3, h4⟩ hpcs hrl
      have hatb := countedLoop_body_at (hat := by simpa [innerLoop] using hat)
      have hcw' : CWritten mem0 s.mem bC val cnt := by rw [h1]; exact hcw
      have hx := acc_step G hA hB hcnt s i j t hi hj ht hcw' h2 h3 hrl
      have hatb' : At prog s.pc (accCode k p bA bB) := by
        rw [hpcs]; simpa [Frag.ofCode] using hatb
      obtain ⟨hst, hpc'⟩ := execSeq_steps (accCode_straight k p bA bB) hatb' hx
      refine ⟨_, hst, ?_, ?_, ?_, ?_⟩
      · simp [hpcs, Frag.ofCode]
      · simp [State.setReg, hrl, rL, rAcc]
      · rfl
      · refine ⟨h1, ?_, ?_, ?_⟩
        · simp [State.setReg, h2, rI, rAcc]
        · simp [State.setReg, h3, rJ, rAcc]
        · simp [State.setReg, h4, dotSum, BitVec.ofInt_add, BitVec.ofInt_mul, rAcc])
    s0 hpc ⟨rfl, hri, hrj, by simpa [dotSum] using hacc⟩
  obtain ⟨s', hs', hpc', hr', hd', hm', hi', hj', hacc'⟩ := hrun
  refine ⟨s', hs', ?_, hd', hm', hi', hj', hacc'⟩
  simp [Frag.ofCode] at hpc'
  omega

/-! ## One output element, one row, the whole product -/

/-- The word the destination cell `q` (row-major) must hold: the `(q / p, q % p)` entry of
`A . B`, as an integer reduced modulo `2^n`. -/
def dotVal {n : Nat} (A B : Nat → Nat → Int) (k p : Nat) (q : Nat) : Word n :=
  BitVec.ofInt n (dotSum A B (q / p) (q % p) k)

theorem dotVal_at {n : Nat} (A B : Nat → Nat → Int) (k p i j : Nat) (hj : j < p) :
    (dotVal A B k p (i * p + j) : Word n) = BitVec.ofInt n (dotSum A B i j k) := by
  have hp : 0 < p := by omega
  have h1 : (i * p + j) / p = i := by
    rw [Nat.mul_comm, Nat.mul_add_div hp, Nat.div_eq_of_lt hj]; rfl
  have h2 : (i * p + j) % p = j := by
    rw [Nat.mul_comm, Nat.mul_add_mod, Nat.mod_eq_of_lt hj]
  simp [dotVal, h1, h2]

theorem initCode_acc {n : Nat} (s : State n) :
    execSeq (initCode rAcc : List (Instr n)) s =
      .next { s with pc := s.pc + 2, regs := State.setReg s.regs rAcc 0#n } :=
  initCode_run rAcc s

/-- Computing and storing one element `C[i,j]`. -/
theorem cell_run {n m k p bA bB bC : Nat} (G : DotGeom n m k p bA bB bC)
    {A B : Nat → Nat → Int} {mem0 : Memory n}
    (hA : MatAt mem0 bA m k A) (hB : MatAt mem0 bB k p B)
    (hvC : ∀ q, q < m * p → mem0.valid (BitVec.ofNat n (bC + q)) = true)
    {prog : Prog n} {b : Nat} (hat : At prog b ((cellBody k p bA bB bC : Frag n).emit b))
    (s0 : State n) (hpc : s0.pc = b) (i j : Nat) (hi : i < m) (hj : j < p)
    (hcw : CWritten mem0 s0.mem bC (dotVal A B k p) (i * p + j))
    (hri : s0.regs rI = BitVec.ofNat n i) (hrj : s0.regs rJ = BitVec.ofNat n j) :
    ∃ s', Steps prog s0 s' ∧ s'.pc = b + (cellBody k p bA bB bC : Frag n).size ∧
      s'.dstack = s0.dstack ∧ s'.regs rI = BitVec.ofNat n i ∧ s'.regs rJ = BitVec.ofNat n j ∧
      CWritten mem0 s'.mem bC (dotVal A B k p) (i * p + j + 1) := by
  have hGC := G.hC
  have hat' := Frag.seq_at (by simpa [cellBody] using hat)
  have hinit : At prog b (initCode rAcc) := by simpa [Frag.ofCode] using hat'.1
  have hrest := Frag.seq_at hat'.2
  have hinner : At prog (b + 2) ((innerLoop k p bA bB : Frag n).emit (b + 2)) := by
    simpa [Frag.ofCode, initCode] using hrest.1
  have hstore : At prog (b + 2 + ((accCode k p bA bB : List (Instr n)).length + 12))
      (storeCode p bC : List (Instr n)) := by
    simpa [Frag.ofCode, initCode, innerLoop, countedLoop_size] using hrest.2
  -- 1. acc := 0
  have hx0 := initCode_acc s0
  obtain ⟨hst0, hpc0⟩ := execSeq_steps (initCode_straight rAcc) (by rw [hpc]; exact hinit) hx0
  -- 2. reduction
  obtain ⟨s1, hs1, hpc1, hd1, hm1, hri1, hrj1, hacc1⟩ := inner_run G hA hB
    (cnt := i * p + j) (val := dotVal A B k p) (by have := idx_lt hi hj; omega) hinner
    { s0 with pc := s0.pc + 2, regs := State.setReg s0.regs rAcc 0#n } (by simp [hpc])
    i j hi hj hcw (by simp [State.setReg, hri, rI, rAcc]) (by simp [State.setReg, hrj, rJ, rAcc])
    (by simp [State.setReg])
  -- 3. store
  have hq : i * p + j < m * p := idx_lt hi hj
  have hcw1 : CWritten mem0 s1.mem bC (dotVal A B k p) (i * p + j) := by
    rw [hm1]; exact hcw
  have hvalid : s1.mem.valid (BitVec.ofNat n (bC + (i * p + j))) = true := by
    rw [hcw1.1]; exact hvC _ hq
  obtain ⟨mem', hw⟩ : ∃ m', s1.mem.write? (BitVec.ofNat n (bC + (i * p + j)))
      (dotVal A B k p (i * p + j)) = some m' := by simp [Memory.write?, hvalid]
  have hCaddr : (idx2 rI rJ p bC : RExpr n).eval s1.regs s1.mem =
      .ok (BitVec.ofNat n (bC + (i * p + j))) := by
    rw [idx2_eval s1.regs s1.mem rI rJ p bC i j hri1 hrj1]
    congr 2
    omega
  have hw' : s1.mem.write? (BitVec.ofNat n (bC + (i * p + j)))
      (BitVec.ofInt n (dotSum A B i j k)) = some mem' := by
    rwa [dotVal_at A B k p i j hj] at hw
  have hxs : execSeq (storeCode p bC : List (Instr n)) s1 =
      .next { s1 with pc := s1.pc + (storeCode p bC : List (Instr n)).length, mem := mem' } := by
    rw [storeCode, execSeq_append, execSeq_append,
      RExpr.code_ok (RExpr.reg rAcc) s1 (s1.regs rAcc) (by simp [RExpr.eval])]
    simp only [Outcome.andThen]
    rw [RExpr.code_ok (idx2 rI rJ p bC)
      { s1 with pc := s1.pc + (RExpr.reg rAcc : RExpr n).code.length, dstack := s1.regs rAcc :: s1.dstack }
      _ hCaddr]
    simp [execSeq, exec, State.fall, hacc1, hw', RExpr.code, storeCode, Nat.add_assoc] <;> omega
  obtain ⟨hst2, hpc2⟩ := execSeq_steps (storeCode_straight p bC)
    (by rw [hpc1]; have e : b + 2 + (accCode k p bA bB : List (Instr n)).length + 12 =
          b + 2 + ((accCode k p bA bB : List (Instr n)).length + 12) := by omega
        simpa [hpc, e] using hstore) hxs
  refine ⟨_, ((hst0.trans hs1).trans hst2), ?_, ?_, ?_, ?_, ?_⟩
  · simp [hpc1, hpc, cellBody, Frag.seq_size, Frag.ofCode_size, innerLoop, countedLoop_size, Frag.ofCode, initCode] <;> omega
  · simpa using hd1
  · simpa using hri1
  · simpa using hrj1
  · exact cwritten_step (by omega) hcw1 hw

/-- One full row of the product. -/
theorem row_run {n m k p bA bB bC : Nat} (G : DotGeom n m k p bA bB bC)
    {A B : Nat → Nat → Int} {mem0 : Memory n}
    (hA : MatAt mem0 bA m k A) (hB : MatAt mem0 bB k p B)
    (hvC : ∀ q, q < m * p → mem0.valid (BitVec.ofNat n (bC + q)) = true)
    {prog : Prog n} {b : Nat} (hat : At prog b ((rowLoop k p bA bB bC : Frag n).emit b))
    (s0 : State n) (hpc : s0.pc = b) (i : Nat) (hi : i < m)
    (hcw : CWritten mem0 s0.mem bC (dotVal A B k p) (i * p))
    (hri : s0.regs rI = BitVec.ofNat n i) :
    ∃ s', Steps prog s0 s' ∧ s'.pc = b + (cellBody k p bA bB bC : Frag n).size + 12 ∧
      s'.dstack = s0.dstack ∧ s'.regs rI = BitVec.ofNat n i ∧
      CWritten mem0 s'.mem bC (dotVal A B k p) (i * p + p) := by
  let Inv : Nat → State n → Prop := fun u s =>
    s.regs rI = BitVec.ofNat n i ∧ CWritten mem0 s.mem bC (dotVal A B k p) (i * p + u)
  have hrun := countedLoop_run (r := rJ) (N := p) (body := cellBody k p bA bB bC)
    G.hn G.hp (by simpa [rowLoop] using hat) Inv
    (by
      intro u s s' ⟨h1, h2⟩ hm _ _ hr
      refine ⟨(hr rI (by decide)).trans h1, ?_⟩
      have : s'.mem = s.mem := hm
      rw [this]; exact h2)
    (by
      intro u s hu ⟨h1, h2⟩ hpcs hrj
      have hatb := countedLoop_body_at (hat := by simpa [rowLoop] using hat)
      obtain ⟨s', hs', hpc', hd', hri', hrj', hcw'⟩ :=
        cell_run (prog := prog) G hA hB hvC hatb s hpcs i u hi hu h2 h1 hrj
      have e : i * p + u + 1 = i * p + (u + 1) := by omega
      rw [e] at hcw'
      exact ⟨s', hs', hpc', hrj', hd', ⟨hri', hcw'⟩⟩)
    s0 hpc ⟨hri, by simpa using hcw⟩
  obtain ⟨s', hs', hpc', _, hd', hI'⟩ := hrun
  exact ⟨s', hs', hpc', hd', hI'.1, hI'.2⟩

theorem rowLoop_size {n : Nat} (k p bA bB bC : Nat) :
    (rowLoop k p bA bB bC : Frag n).size = (cellBody k p bA bB bC : Frag n).size + 12 :=
  countedLoop_size _ _ _

theorem dotFrag_size {n : Nat} (m k p bA bB bC : Nat) :
    (dotFrag m k p bA bB bC : Frag n).size = (cellBody k p bA bB bC : Frag n).size + 24 := by
  simp only [dotFrag, countedLoop_size, rowLoop_size]

/-- The whole product: every destination word holds the right entry. -/
theorem dot_run {n m k p bA bB bC : Nat} (G : DotGeom n m k p bA bB bC)
    {A B : Nat → Nat → Int} {mem0 : Memory n}
    (hA : MatAt mem0 bA m k A) (hB : MatAt mem0 bB k p B)
    (hvC : ∀ q, q < m * p → mem0.valid (BitVec.ofNat n (bC + q)) = true)
    {prog : Prog n} {b : Nat} (hat : At prog b ((dotFrag m k p bA bB bC : Frag n).emit b))
    (s0 : State n) (hpc : s0.pc = b) (hmem : s0.mem = mem0) :
    ∃ s', Steps prog s0 s' ∧ s'.pc = b + (dotFrag m k p bA bB bC : Frag n).size ∧
      s'.dstack = s0.dstack ∧ CWritten mem0 s'.mem bC (dotVal A B k p) (m * p) := by
  let Inv : Nat → State n → Prop := fun i s =>
    CWritten mem0 s.mem bC (dotVal A B k p) (i * p)
  have hrun := countedLoop_run (r := rI) (N := m) (body := rowLoop k p bA bB bC)
    G.hn G.hm (by simpa [dotFrag] using hat) Inv
    (by
      intro i s s' h hm _ _ _
      have : s'.mem = s.mem := hm
      show CWritten mem0 s'.mem bC (dotVal A B k p) (i * p)
      rw [this]; exact h)
    (by
      intro i s hi h hpcs hri
      have hatb := countedLoop_body_at (hat := by simpa [dotFrag] using hat)
      obtain ⟨s', hs', hpc', hd', hri', hcw'⟩ :=
        row_run (prog := prog) G hA hB hvC hatb s hpcs i hi h hri
      have e : i * p + p = (i + 1) * p := by rw [Nat.succ_mul]
      rw [e] at hcw'
      refine ⟨s', hs', ?_, hri', hd', hcw'⟩
      rw [hpc', rowLoop_size]; omega)
    s0 hpc (by show CWritten mem0 s0.mem bC (dotVal A B k p) (0 * p)
               rw [hmem]; simpa using cwritten_zero mem0 bC (dotVal A B k p))
  obtain ⟨s', hs', hpc', _, hd', hI'⟩ := hrun
  refine ⟨s', hs', ?_, hd', hI'⟩
  rw [dotFrag_size]
  rw [hpc']
  simp [rowLoop_size, dotFrag, countedLoop_size] <;> omega

/-- `C = A . B`, in the vocabulary of the mathematics: afterwards the destination matrix at `bC`
holds the integer product of `A` and `B` (reduced modulo `2^n`), the set of addressable words is
unchanged, every word outside the destination is unchanged, and the data stack is untouched. -/
theorem dot_correct {n m k p bA bB bC : Nat} (G : DotGeom n m k p bA bB bC)
    {A B : Nat → Nat → Int} {mem0 : Memory n}
    (hA : MatAt mem0 bA m k A) (hB : MatAt mem0 bB k p B)
    (hvC : ∀ q, q < m * p → mem0.valid (BitVec.ofNat n (bC + q)) = true)
    {prog : Prog n} {b : Nat} (hat : At prog b ((dotFrag m k p bA bB bC : Frag n).emit b))
    (s0 : State n) (hpc : s0.pc = b) (hmem : s0.mem = mem0) :
    ∃ s', Steps prog s0 s' ∧ s'.pc = b + (dotFrag m k p bA bB bC : Frag n).size ∧
      s'.dstack = s0.dstack ∧
      MatAt s'.mem bC m p (fun i j => dotSum A B i j k) ∧
      s'.mem.valid = mem0.valid ∧
      (∀ a, (∀ q, q < m * p → a ≠ BitVec.ofNat n (bC + q)) →
        s'.mem.read? a = mem0.read? a) := by
  obtain ⟨s', hs', hpc', hd', hv, hr, ho⟩ := dot_run G hA hB hvC hat s0 hpc hmem
  refine ⟨s', hs', hpc', hd', ?_, hv, ho⟩
  intro i j hi hj
  have hq : i * p + j < m * p := idx_lt hi hj
  have := hr (i * p + j) hq
  rw [dotVal_at A B k p i j hj] at this
  have e : bC + i * p + j = bC + (i * p + j) := by omega
  rw [e]; exact this

/-- The whole program `C = A . B`: the lowering placed at address 0 followed by `HALT`, run from
the initial machine state, halts with the product in memory. -/
theorem dotProgram_correct {n m k p bA bB bC : Nat} (G : DotGeom n m k p bA bB bC)
    {A B : Nat → Nat → Int} {mem0 : Memory n}
    (hA : MatAt mem0 bA m k A) (hB : MatAt mem0 bB k p B)
    (hvC : ∀ q, q < m * p → mem0.valid (BitVec.ofNat n (bC + q)) = true) :
    ∃ s', WordDialect.Exec ((dotFrag m k p bA bB bC : Frag n).emit 0 ++ [.halt])
        (State.init mem0) (.halted s') ∧
      s'.dstack = [] ∧ MatAt s'.mem bC m p (fun i j => dotSum A B i j k) ∧
      s'.mem.valid = mem0.valid ∧
      (∀ a, (∀ q, q < m * p → a ≠ BitVec.ofNat n (bC + q)) →
        s'.mem.read? a = mem0.read? a) := by
  have hat : At ((dotFrag m k p bA bB bC : Frag n).emit 0 ++ [.halt]) 0
      ((dotFrag m k p bA bB bC : Frag n).emit 0) := by
    have := at_embed ([] : Prog n) ((dotFrag m k p bA bB bC : Frag n).emit 0) [.halt]
    simpa using this
  obtain ⟨s', hs', hpc', hd', hmat, hv, ho⟩ :=
    dot_correct G hA hB hvC hat (State.init mem0) rfl rfl
  have hfetch : ((dotFrag m k p bA bB bC : Frag n).emit 0 ++ [.halt])[s'.pc]? = some .halt := by
    rw [hpc']; simp [(dotFrag m k p bA bB bC : Frag n).len]
  refine ⟨s', Exec.of_steps hs' (.halt ?_), hd', hmat, hv, ho⟩
  rw [step_of_fetch hfetch]; rfl

end Wolfram
end WordDialect
