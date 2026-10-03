import WordDialect.Word

/-!
# WordDialect.Memory

Word-addressed memory: one address names one `Word n`. (Byte addressing is a backend
concern; the backend must map word address `a` to byte address `a * (n / 8)`.)

`valid` is the set of addressable words. Access outside it is a trap, never undefined
behaviour: `read?` and `write?` return `none`.
-/

namespace WordDialect

structure Memory (n : Nat) where
  cell  : Word n → Word n
  valid : Word n → Bool

namespace Memory

def read? {n : Nat} (m : Memory n) (a : Word n) : Option (Word n) :=
  if m.valid a then some (m.cell a) else none

def write? {n : Nat} (m : Memory n) (a v : Word n) : Option (Memory n) :=
  if m.valid a then
    some { m with cell := fun b => if b = a then v else m.cell b }
  else none

theorem read?_some {n : Nat} {m : Memory n} {a v : Word n}
    (h : m.read? a = some v) : m.valid a = true ∧ m.cell a = v := by
  unfold read? at h
  split at h
  · simp at h; exact ⟨by assumption, h⟩
  · simp at h

theorem read?_none_iff {n : Nat} (m : Memory n) (a : Word n) :
    m.read? a = none ↔ m.valid a = false := by
  unfold read?
  cases hv : m.valid a <;> simp

theorem write?_none_iff {n : Nat} (m : Memory n) (a v : Word n) :
    m.write? a v = none ↔ m.valid a = false := by
  unfold write?
  cases hv : m.valid a <;> simp

/-- A write to a valid address does not change which addresses are valid. -/
theorem write?_valid {n : Nat} {m m' : Memory n} {a v : Word n}
    (h : m.write? a v = some m') : m'.valid = m.valid := by
  unfold write? at h
  split at h
  · simp at h; subst h; rfl
  · simp at h

/-- Read-after-write at the same address returns the written word. -/
theorem read_write_same {n : Nat} {m m' : Memory n} {a v : Word n}
    (h : m.write? a v = some m') : m'.read? a = some v := by
  unfold write? at h
  split at h
  · rename_i hv
    simp at h; subst h
    simp [read?, hv]
  · simp at h

/-- Memory isolation: a write changes no other cell, and does not change validity. -/
theorem read_write_other {n : Nat} {m m' : Memory n} {a b v : Word n}
    (h : m.write? a v = some m') (hne : b ≠ a) : m'.read? b = m.read? b := by
  unfold write? at h
  split at h
  · simp at h; subst h
    simp [read?, hne]
  · simp at h

theorem cell_write_other {n : Nat} {m m' : Memory n} {a b v : Word n}
    (h : m.write? a v = some m') (hne : b ≠ a) : m'.cell b = m.cell b := by
  unfold write? at h
  split at h
  · simp at h; subst h; simp [hne]
  · simp at h

/-- Writing back the word just read leaves every readable cell unchanged. -/
theorem write_read_self {n : Nat} {m : Memory n} {a v : Word n}
    (h : m.read? a = some v) : ∃ m', m.write? a v = some m' ∧ ∀ b, m'.read? b = m.read? b := by
  obtain ⟨hv, hc⟩ := read?_some h
  refine ⟨{ m with cell := fun b => if b = a then v else m.cell b }, by simp [write?, hv], ?_⟩
  intro b
  by_cases hb : b = a
  · subst hb; simp [read?, hv, hc]
  · simp [read?, hb]

/-- Two writes to distinct addresses commute. -/
theorem write_comm {n : Nat} {m m1 m2 : Memory n} {a b u v : Word n} (hne : a ≠ b)
    (h1 : m.write? a u = some m1) (h2 : m1.write? b v = some m2) :
    ∃ m1' m2', m.write? b v = some m1' ∧ m1'.write? a u = some m2' ∧
      m2'.valid = m2.valid ∧ m2'.cell = m2.cell := by
  have hva : m.valid a = true := by
    by_cases hh : m.valid a = true
    · exact hh
    · have := (write?_none_iff m a u).mpr (by simpa using hh); rw [h1] at this; simp at this
  have hvb1 : m1.valid b = true := by
    by_cases hh : m1.valid b = true
    · exact hh
    · have := (write?_none_iff m1 b v).mpr (by simpa using hh); rw [h2] at this; simp at this
  have hm1 : m1.valid = m.valid := write?_valid h1
  have hvb : m.valid b = true := by rw [← hm1]; exact hvb1
  unfold write? at h1 h2
  simp only [hva, hvb1, ite_true, Option.some.injEq] at h1 h2
  subst h1; subst h2
  refine ⟨{ m with cell := fun c => if c = b then v else m.cell c },
          { m with cell := fun c => if c = a then u else if c = b then v else m.cell c },
          by simp [write?, hvb], by simp [write?, hva], rfl, ?_⟩
  funext c
  by_cases hca : c = a
  · have : c ≠ b := by rw [hca]; exact hne
    simp [hca]
    intro h; exact absurd h hne
  · by_cases hcb : c = b
    · simp [hca, hcb]
      intro h; exact absurd h.symm hne
    · simp [hca, hcb]

end Memory

end WordDialect
