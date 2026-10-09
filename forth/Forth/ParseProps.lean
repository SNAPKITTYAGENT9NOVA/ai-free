import Forth.Print

/-!
# Forth.ParseProps

Properties of the text parser `Forth.parse`, the converse direction of `parse_print`:

* `parse_wf`: every successful parse yields a well-formed program (`Program.WF`, including that
  every `LEAVE` is inside a loop), and hence
  (`parse_print_of_parse`) `print P` is a canonical text for every parseable source: it parses
  back to the same program.
* Case: `tokenize_upper` (the tokens of the upper-cased text are the upper-cased tokens) and
  `parse_toUpper` / `parse_toUpper_ok` / `parse_case_insensitive` (upper-casing the source does
  not change the parsed program, or whether parsing fails; only the spelling quoted in an error
  message can change).
* Comments: `tokenize_paren_comment`, `tokenize_line_comment`, `tokenize_line_comment_end`
  (comments tokenize like whitespace), with the token-level `stripParens_close` /
  `stripParens_append`.
* Dictionary words: `classify_dict`, `parseTop_constant`, `parseTop_constant_lit` and
  `classify_constant` (`n CONSTANT X` drops the literal and makes `X`, in any case, the literal
  `n`), `parseTop_colon` and `parseTop_defs_prefix` (the body of the `k`-th definition is parsed
  as word `k`), `classify_recurse` and `parseSeq_recurse_name` (`RECURSE` is a call of the word
  being defined: replacing it by the word's own name changes nothing).
-/

namespace WordDialect
namespace Forth

open Parse

namespace ParseProps

theorem bind_ok {α β : Type} {x : Except String α} {f : α → Except String β} {y : β}
    (h : (x >>= f) = .ok y) : ∃ a, x = .ok a ∧ f a = .ok y := by
  cases x with
  | error e => cases h
  | ok a => exact ⟨a, rfl, h⟩

theorem iteT {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : c) : ite c a b = a := by
  simp [h]

theorem iteF {c : Prop} [Decidable c] {α : Sort _} {a b : α} (h : ¬c) : ite c a b = b := by
  simp [h]

/-- Two token lists related elementwise by `R`. -/
inductive Rel2 (R : Tok → Tok → Prop) : List Tok → List Tok → Prop
  | nil : Rel2 R [] []
  | cons {t t' : Tok} {ts ts' : List Tok} :
      R t t' → Rel2 R ts ts' → Rel2 R (t :: ts) (t' :: ts')

theorem Rel2.length_eq {R : Tok → Tok → Prop} {ts ts' : List Tok} (h : Rel2 R ts ts') :
    ts.length = ts'.length := by
  induction h with
  | nil => rfl
  | cons _ _ ih => simp [ih]

/-! ## Well-formedness -/

theorem Block.WF_mono {k k' : Nat} {d : Bool} (hk : k ≤ k') :
    ∀ b : Block, b.WF k d → b.WF k' d
  | .nil, _ => trivial
  | .op _ r, h => Block.WF_mono hk r h
  | .ite t e r, h =>
    ⟨Block.WF_mono hk t h.1, Block.WF_mono hk e h.2.1, Block.WF_mono hk r h.2.2⟩
  | .untilL x r, h => ⟨Block.WF_mono hk x h.1, Block.WF_mono hk r h.2⟩
  | .call _ r, h => ⟨by have := h.1; omega, Block.WF_mono hk r h.2⟩
  | .exit r, h => ⟨h.1, Block.WF_mono hk r h.2⟩
  | .doLoop x r, h => ⟨Block.WF_mono hk x h.1, Block.WF_mono hk r h.2⟩
  | .plusLoop x r, h => ⟨Block.WF_mono hk x h.1, Block.WF_mono hk r h.2⟩
  | .leave r, h => Block.WF_mono hk r h

theorem Block.WF_append {k : Nat} {d : Bool} :
    ∀ a b : Block, a.WF k d → b.WF k d → (a.append b).WF k d
  | .nil, _, _, hb => hb
  | .op _ r, b, ha, hb => Block.WF_append r b ha hb
  | .ite _ _ r, b, ha, hb => ⟨ha.1, ha.2.1, Block.WF_append r b ha.2.2 hb⟩
  | .untilL _ r, b, ha, hb => ⟨ha.1, Block.WF_append r b ha.2 hb⟩
  | .call _ r, b, ha, hb => ⟨ha.1, Block.WF_append r b ha.2 hb⟩
  | .exit r, b, ha, hb => ⟨ha.1, Block.WF_append r b ha.2 hb⟩
  | .doLoop _ r, b, ha, hb => ⟨ha.1, Block.WF_append r b ha.2 hb⟩
  | .plusLoop _ r, b, ha, hb => ⟨ha.1, Block.WF_append r b ha.2 hb⟩
  | .leave r, b, ha, hb => Block.WF_append r b ha hb

theorem Block.WF_dropLastLit {k : Nat} {d : Bool} :
    ∀ (b b' : Block) (z : Int), b.dropLastLit = some (b', z) → b.WF k d → b'.WF k d := by
  intro b
  induction b with
  | nil => intro b' z h; cases h
  | op o r ih =>
    intro b' z h hw
    rw [Block.dropLastLit.eq_def] at h
    split at h
    · cases h
    · cases h; trivial
    · rename_i heq
      injection heq with h1 h2
      subst h1 h2
      simp only [Option.map_eq_some_iff] at h
      obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
      cases he
      exact ih p1 p2 hp hw
    all_goals (rename_i heq; cases heq)
  | ite t e r _ _ ih =>
    intro b' z h hw
    simp only [Block.dropLastLit, Option.map_eq_some_iff] at h
    obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
    cases he
    exact ⟨hw.1, hw.2.1, ih _ _ hp hw.2.2⟩
  | untilL x r _ ih =>
    intro b' z h hw
    simp only [Block.dropLastLit, Option.map_eq_some_iff] at h
    obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
    cases he
    exact ⟨hw.1, ih _ _ hp hw.2⟩
  | call i r ih =>
    intro b' z h hw
    simp only [Block.dropLastLit, Option.map_eq_some_iff] at h
    obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
    cases he
    exact ⟨hw.1, ih _ _ hp hw.2⟩
  | exit r ih =>
    intro b' z h hw
    simp only [Block.dropLastLit, Option.map_eq_some_iff] at h
    obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
    cases he
    exact ⟨hw.1, ih _ _ hp hw.2⟩
  | doLoop x r _ ih =>
    intro b' z h hw
    simp only [Block.dropLastLit, Option.map_eq_some_iff] at h
    obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
    cases he
    exact ⟨hw.1, ih _ _ hp hw.2⟩
  | plusLoop x r _ ih =>
    intro b' z h hw
    simp only [Block.dropLastLit, Option.map_eq_some_iff] at h
    obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
    cases he
    exact ⟨hw.1, ih _ _ hp hw.2⟩
  | leave r ih =>
    intro b' z h hw
    simp only [Block.dropLastLit, Option.map_eq_some_iff] at h
    obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
    cases he
    exact ih p1 p2 hp hw

theorem Block.WF_loopOf {k : Nat} {d : Bool} (q : Bool) {mk : Block → Block → Block}
    (hmk : ∀ b r : Block, b.WF k d → r.WF k d → (mk b r).WF k d) {body rest : Block}
    (hb : body.WF k d) (hr : rest.WF k d) : (Block.loopOf q mk body rest).WF k d := by
  cases q
  · exact hmk _ _ hb hr
  · exact ⟨trivial, hmk _ _ hb trivial, hr⟩

/-- Every dictionary entry compiles to a call of a word `< k` or to a literal. -/
def DictInv (k : Nat) (dict : Dict) : Prop :=
  ∀ p ∈ dict, (∃ i, i < k ∧ p.2 = Block.call i) ∨ ∃ z, p.2 = Block.op (.lit z)

theorem DictInv.mono {k k' : Nat} {dict : Dict} (h : DictInv k dict) (hk : k ≤ k') :
    DictInv k' dict := by
  intro p hp
  rcases h p hp with ⟨i, hi, he⟩ | hz
  · exact .inl ⟨i, by omega, he⟩
  · exact .inr hz

theorem DictInv.cons {k : Nat} {dict : Dict} (h : DictInv k dict) (u : Tok) (w : Block → Block)
    (hw : (∃ i, i < k ∧ w = Block.call i) ∨ ∃ z, w = Block.op (.lit z)) :
    DictInv k ((u, w) :: dict) := by
  intro p hp
  simp only [List.mem_cons] at hp
  rcases hp with rfl | hp
  · exact hw
  · exact h p hp

theorem classify_prim_wf {k : Nat} {inDef : Bool} {dict : Dict} {self : Option Nat} {t : Tok}
    {w : Block → Block} (hd : DictInv k dict)
    (hs : ∀ j, self = some j → j < k ∧ inDef = true)
    (h : classify dict self t = .prim w) : ∀ r : Block, r.WF k inDef → (w r).WF k inDef := by
  intro r hr
  simp only [classify, lookupWord] at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · split at h
    · rename_i j; cases h; exact ⟨(hs j rfl).1, hr⟩
    · cases h
  split at h
  · split at h
    · rename_i j; cases h; exact ⟨(hs j rfl).2, hr⟩
    · cases h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h; exact hr
  split at h
  · rename_i w' hl
    cases h
    obtain ⟨u, hm, -⟩ := Print.lookup_some_mem hl
    rcases hd _ hm with ⟨i, hi, he⟩ | ⟨z, he⟩
    · simp only at he; subst he; exact ⟨hi, hr⟩
    · simp only at he; subst he; exact hr
  split at h
  · cases h; exact hr
  split at h
  · cases h; exact hr
  · cases h

theorem parseSeq_wf {k : Nat} {inDef : Bool} :
    ∀ (fuel : Nat) (dict : Dict) (self : Option Nat) (ts : List Tok) (b : Block)
      (st : Option Tok) (r : List Tok), DictInv k dict →
      (∀ j, self = some j → j < k ∧ inDef = true) →
      parseSeq fuel dict self ts = .ok (b, st, r) → b.WF k inDef
  | 0, _, _, _, _, _, _, _, _, h => by simp [parseSeq] at h
  | _ + 1, _, _, [], _, _, _, _, _, h => by
    simp only [parseSeq, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, -⟩ := h; trivial
  | fuel + 1, dict, self, t :: ts, b, st, r, hd, hs, h => by
    simp only [parseSeq] at h
    split at h
    · cases h; trivial
    · cases h
    · rename_i w hc
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      cases h2
      exact classify_prim_wf hd hs hc _ (parseSeq_wf fuel dict self ts b1 s1 r1 hd hs h1)
    · obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have w1 := parseSeq_wf fuel dict self ts b1 s1 r1 hd hs h1
      simp only at h2
      split at h2
      · obtain ⟨⟨b2, s2, r2⟩, h3, h4⟩ := bind_ok h2
        have w2 := parseSeq_wf fuel dict self _ b2 s2 r2 hd hs h3
        simp only at h4
        split at h4
        · obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h4
          have w3 := parseSeq_wf fuel dict self _ b3 s3 r3 hd hs h5
          cases h6
          exact ⟨w1, w2, w3⟩
        · cases h4
      · split at h2
        · obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
          have w3 := parseSeq_wf fuel dict self _ b3 s3 r3 hd hs h5
          cases h6
          exact ⟨w1, trivial, w3⟩
        · cases h2
    · obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have w1 := parseSeq_wf fuel dict self ts b1 s1 r1 hd hs h1
      simp only at h2
      split at h2
      · obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
        have w3 := parseSeq_wf fuel dict self _ b3 s3 r3 hd hs h5
        cases h6
        exact ⟨w1, w3⟩
      · cases h2
    · rename_i q _
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have w1 := parseSeq_wf fuel dict self ts b1 s1 r1 hd hs h1
      simp only at h2
      split at h2
      · obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
        have w3 := parseSeq_wf fuel dict self _ b3 s3 r3 hd hs h5
        cases h6
        exact Block.WF_loopOf (mk := Block.doLoop) q (fun _ _ h1 h2 => ⟨h1, h2⟩) w1 w3
      · split at h2
        · obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
          have w3 := parseSeq_wf fuel dict self _ b3 s3 r3 hd hs h5
          cases h6
          exact Block.WF_loopOf (mk := Block.plusLoop) q (fun _ _ h1 h2 => ⟨h1, h2⟩) w1 w3
        · cases h2

/-- The block conditions of `Program.WF` (all but the `LEAVE` check, which `parseTokens` makes
on the finished program). -/
def BlocksWF (P : Program) : Prop :=
  (∀ i (body : Block), P.defs[i]? = some body → body.WF (i + 1) true) ∧ P.main.WF P.defs.length false

/-- The invariant of `parseTop`: the dictionary and definitions so far are well formed. -/
theorem parseTop_wf :
    ∀ (fuel : Nat) (dict : Dict) (defs : List Block) (vars : Nat) (main : Block) (toks : List Tok)
      (P : Program), DictInv defs.length dict →
      (∀ i (body : Block), defs[i]? = some body → body.WF (i + 1) true) →
      main.WF defs.length false →
      parseTop fuel dict defs vars main toks = .ok P → BlocksWF P
  | 0, _, _, _, _, _, _, _, _, _, h => by simp [parseTop] at h
  | fuel + 1, dict, defs, vars, main, toks, P, hd, hdefs, hmain, h => by
    simp only [parseTop] at h
    obtain ⟨⟨b, stop, rest⟩, h1, h2⟩ := bind_ok h
    have wb : b.WF defs.length false :=
      parseSeq_wf _ dict none toks b stop rest hd (fun j hj => by cases hj) h1
    simp only at h2
    split at h2
    · cases h2
      exact ⟨hdefs, Block.WF_append _ _ hmain wb⟩
    · split at h2
      · split at h2
        · cases h2
        · rename_i name body
          obtain ⟨⟨bb, s2, r2⟩, h3, h4⟩ := bind_ok h2
          have hd' : DictInv (defs.length + 1) ((upper name, Block.call defs.length) :: dict) :=
            (hd.mono (by omega)).cons _ _ (.inl ⟨defs.length, by omega, rfl⟩)
          have wbb : bb.WF (defs.length + 1) true :=
            parseSeq_wf _ _ _ body bb s2 r2 hd'
              (fun j hj => by cases hj; exact ⟨by omega, rfl⟩) h3
          simp only at h4
          split at h4
          · refine parseTop_wf fuel _ _ vars _ r2 P (by simpa using hd') ?_ ?_ h4
            · intro i body' hi
              rw [List.getElem?_append] at hi
              split at hi
              · exact hdefs i body' hi
              · rename_i hlt
                cases hk : i - defs.length with
                | succ n => rw [hk] at hi; simp at hi
                | zero =>
                rw [hk] at hi
                simp only [List.getElem?_cons_zero, Option.some.injEq] at hi
                subst hi
                have : i = defs.length := by omega
                subst this; exact wbb
            · simpa using Block.WF_append _ _ (Block.WF_mono (by omega) _ hmain)
                (Block.WF_mono (by omega) _ wb)
          · split at h4
            · cases h4
            · split at h4 <;> cases h4
      · split at h2
        · split at h2
          · cases h2
          · exact parseTop_wf fuel _ defs (vars + 1) _ _ P
              (hd.cons _ _ (.inr ⟨_, rfl⟩)) hdefs (Block.WF_append _ _ hmain wb) h2
        · split at h2
          · split at h2
            · cases h2
            · cases h2
            · rename_i b' z name rest' hdl
              exact parseTop_wf fuel _ defs vars _ _ P (hd.cons _ _ (.inr ⟨_, rfl⟩)) hdefs
                (Block.WF_append _ _ hmain (Block.WF_dropLastLit _ _ _ hdl wb)) h2
          · cases h2

end ParseProps

/-- **Every successful parse yields a well-formed program.** -/
theorem parse_wf {src : String} {P : Program} (h : parse src = .ok P) : P.WF := by
  unfold parse at h
  obtain ⟨toks, -, h2⟩ := ParseProps.bind_ok h
  unfold parseTokens at h2
  obtain ⟨P', h3, h4⟩ := ParseProps.bind_ok h2
  split at h4
  · cases h4
    obtain ⟨hd, hm⟩ := ParseProps.parseTop_wf _ [] [] 0 .nil toks _ (fun p hp => by cases hp)
      (fun i b hi => by simp at hi) trivial h3
    exact ⟨hd, hm, ‹_›⟩
  · cases h4

/-- **`print` is a canonical form**: whatever text parses to `P`, so does `print P`. -/
theorem parse_print_of_parse {src : String} {P : Program} (h : parse src = .ok P) :
    parse (print P) = .ok P :=
  parse_print P (parse_wf h)

namespace ParseProps

/-! ## Case-insensitivity -/

theorem toUpper_cases (c : Char) :
    c.toUpper = c ∨ (65 ≤ c.toUpper.toNat ∧ c.toUpper.toNat ≤ 90) := by
  unfold Char.toUpper
  split
  · right
    rename_i h
    obtain ⟨h1, h2⟩ := h
    simp only [Char.toNat] at *
    simp [UInt32.le_iff_toNat_le] at h1 h2
    simp [UInt32.toNat_add]
    omega
  · left; rfl

theorem toUpper_self {x : Char} (h : ¬(97 ≤ x.toNat ∧ x.toNat ≤ 122)) : x.toUpper = x := by
  unfold Char.toUpper
  split
  · rename_i h'
    exfalso; apply h
    obtain ⟨h1, h2⟩ := h'
    simp only [Char.toNat]
    simp [UInt32.le_iff_toNat_le] at h1 h2
    omega
  · rfl

theorem toUpper_toUpper (c : Char) : c.toUpper.toUpper = c.toUpper := by
  rcases toUpper_cases c with h | h
  · rw [h]; exact h
  · exact toUpper_self (by omega)

theorem upper_upper (t : Tok) : upper (upper t) = upper t := by
  simp only [upper, List.map_map]
  congr 1
  funext c
  exact toUpper_toUpper c

/-- A character that upper-casing fixes and no other character upper-cases to. -/
def Fixed (x : Char) : Prop := x.toUpper = x ∧ ¬(65 ≤ x.toNat ∧ x.toNat ≤ 90)

theorem toUpper_eq_fixed {c x : Char} (hx : Fixed x) : c.toUpper = x ↔ c = x := by
  constructor
  · intro h
    rcases toUpper_cases c with h' | h'
    · rw [h'] at h; exact h
    · rw [h] at h'; exact absurd h' hx.2
  · rintro rfl; exact hx.1

theorem fixed_space : Fixed ' ' := ⟨by decide, by decide⟩
theorem fixed_tab : Fixed '\t' := ⟨by decide, by decide⟩
theorem fixed_nl : Fixed '\n' := ⟨by decide, by decide⟩
theorem fixed_cr : Fixed '\r' := ⟨by decide, by decide⟩
theorem fixed_bs : Fixed '\\' := ⟨by decide, by decide⟩
theorem fixed_lp : Fixed '(' := ⟨by decide, by decide⟩
theorem fixed_rp : Fixed ')' := ⟨by decide, by decide⟩

theorem beq_toUpper {c x : Char} (hx : Fixed x) : (c.toUpper == x) = (c == x) := by
  apply Bool.eq_iff_iff.mpr
  simp only [beq_iff_eq]
  exact toUpper_eq_fixed hx

theorem isWs_toUpper (c : Char) : isWs c.toUpper = isWs c := by
  simp only [isWs, beq_toUpper fixed_space, beq_toUpper fixed_tab, beq_toUpper fixed_nl,
    beq_toUpper fixed_cr]

theorem map_toUpper_single {cs : List Char} {x : Char} (hx : Fixed x) :
    cs.map Char.toUpper = [x] ↔ cs = [x] := by
  match cs with
  | [] => simp
  | [c] => simp [toUpper_eq_fixed hx]
  | _ :: _ :: _ => simp

theorem flush_upper (cur : List Char) (rest : List Tok) :
    flush (cur.map Char.toUpper) (rest.map upper) = (flush cur rest).map upper := by
  unfold flush
  by_cases h : cur = []
  · subst h; simp
  · rw [iteF (by simpa using h), iteF h]
    simp [upper, List.map_reverse]

/-- The lexer commutes with upper-casing. -/
theorem lex_upper : ∀ (cs cur : List Char) (skip : Bool),
    lex (cs.map Char.toUpper) (cur.map Char.toUpper) skip = (lex cs cur skip).map upper := by
  intro cs
  induction cs with
  | nil =>
    intro cur skip
    simp only [List.map_nil, lex, map_toUpper_single fixed_bs]
    split
    · rfl
    · have := flush_upper cur []
      simpa using this
  | cons c cs ih =>
    have ih0 := fun b => ih [] b
    simp only [List.map_nil] at ih0
    intro cur skip
    cases skip with
    | true =>
      simp only [List.map_cons, lex, beq_toUpper fixed_nl]
      split <;> exact ih0 _
    | false =>
      simp only [List.map_cons, lex, isWs_toUpper, map_toUpper_single fixed_bs,
        beq_toUpper fixed_nl]
      split
      · split
        · split <;> exact ih0 _
        · rw [ih0, flush_upper]
      · have := ih (c :: cur) false
        simpa using this

theorem getLast_upper {t : Tok} : (upper t).getLast? = some ')' ↔ t.getLast? = some ')' := by
  simp only [upper, List.getLast?_map, Option.map_eq_some_iff]
  constructor
  · rintro ⟨a, ha, he⟩
    rw [(toUpper_eq_fixed fixed_rp).mp he] at ha; exact ha
  · intro h; exact ⟨_, h, fixed_rp.1⟩

theorem stripParens_upper : ∀ (inside : Bool) (ts : List Tok),
    stripParens inside (ts.map upper) = (stripParens inside ts).map (·.map upper)
  | false, [] => rfl
  | true, [] => rfl
  | false, t :: ts => by
    simp only [List.map_cons, stripParens]
    by_cases h : t = ['(']
    · rw [iteT h, iteT (by rw [h]; rfl)]
      exact stripParens_upper true ts
    · rw [iteF h, iteF (show ¬upper t = ['('] from
        fun e => h ((map_toUpper_single fixed_lp).mp e))]
      rw [stripParens_upper false ts]
      cases stripParens false ts <;> rfl
  | true, t :: ts => by
    simp only [List.map_cons, stripParens, getLast_upper]
    split
    · exact stripParens_upper false ts
    · exact stripParens_upper true ts

/-- **The tokenizer commutes with upper-casing**: the tokens of the upper-cased text are the
upper-cased tokens (and the errors are the same). -/
theorem tokenize_upper (src : String) :
    tokenize (src.map Char.toUpper) = (tokenize src).map (·.map upper) := by
  unfold tokenize
  have := lex_upper src.toList [] false
  simp only [List.map_nil] at this
  rw [String.toList_map, this, stripParens_upper]

/-- Two classifications agree, except possibly in an error message. -/
def ISim (i j : Item) : Prop := i = j ∨ ∃ m m', i = .bad m ∧ j = .bad m'

theorem classify_sim {dict : Dict} {self : Option Nat} {t t' : Tok} (h : upper t = upper t') :
    ISim (classify dict self t) (classify dict self t') := by
  simp only [classify, lookupWord, h]
  by_cases h1 : upper t' ∈ stops
  · rw [iteT h1, iteT h1]; exact .inl rfl
  rw [iteF h1, iteF h1]
  by_cases h2 : upper t' = kIF
  · rw [iteT h2, iteT h2]; exact .inl rfl
  rw [iteF h2, iteF h2]
  by_cases h3 : upper t' = kBEGIN
  · rw [iteT h3, iteT h3]; exact .inl rfl
  rw [iteF h3, iteF h3]
  by_cases h4 : upper t' = kRECURSE
  · rw [iteT h4, iteT h4]; exact .inl rfl
  rw [iteF h4, iteF h4]
  by_cases h5 : upper t' = kEXIT
  · rw [iteT h5, iteT h5]; exact .inl rfl
  rw [iteF h5, iteF h5]
  by_cases h6 : upper t' = kDO
  · rw [iteT h6, iteT h6]; exact .inl rfl
  rw [iteF h6, iteF h6]
  by_cases h7 : upper t' = kQDO
  · rw [iteT h7, iteT h7]; exact .inl rfl
  rw [iteF h7, iteF h7]
  by_cases h8 : upper t' = kLEAVE
  · rw [iteT h8, iteT h8]; exact .inl rfl
  rw [iteF h8, iteF h8]
  cases dict.lookup (upper t') with
  | some w => exact .inl rfl
  | none =>
    cases opTable.lookup (upper t') with
    | some o => exact .inl rfl
    | none =>
      cases number (upper t') with
      | some z => exact .inl rfl
      | none => exact .inr ⟨_, _, rfl, rfl⟩

/-- Two `parseSeq` results agree up to error messages, with related remaining tokens. -/
def RSim (R : Tok → Tok → Prop) :
    Except String (Block × Option Tok × List Tok) →
      Except String (Block × Option Tok × List Tok) → Prop
  | .ok (b, s, r), .ok (b', s', r') => b = b' ∧ s = s' ∧ Rel2 R r r'
  | .error _, .error _ => True
  | _, _ => False

/-- Two results agree up to error messages. -/
def PSim {α : Type} : Except String α → Except String α → Prop
  | .ok a, .ok a' => a = a'
  | .error _, .error _ => True
  | _, _ => False

theorem psim_iff {α : Type} {x y : Except String α} : PSim x y ↔ x.toOption = y.toOption := by
  cases x <;> cases y <;> simp [PSim, Except.toOption]

theorem rsim_bind {R : Tok → Tok → Prop} {α : Type}
    {S : Except String α → Except String α → Prop}
    (hS : ∀ e e', S (.error e) (.error e'))
    {x x' : Except String (Block × Option Tok × List Tok)} (h : RSim R x x')
    {k k' : Block × Option Tok × List Tok → Except String α}
    (hk : ∀ b s r r', Rel2 R r r' → S (k (b, s, r)) (k' (b, s, r'))) :
    S (x >>= k) (x' >>= k') := by
  match x, x', h with
  | .ok (b, s, r), .ok (b', s', r'), h =>
    obtain ⟨rfl, rfl, hr⟩ := h
    exact hk b s r r' hr
  | .error e, .error e', _ => exact hS e e'
  | .ok _, .error _, h => exact h.elim
  | .error _, .ok _, h => exact h.elim

theorem parseSeq_congr {R : Tok → Tok → Prop} {dict : Dict} {self : Option Nat}
    (hR : ∀ t t', R t t' → ISim (classify dict self t) (classify dict self t')) :
    ∀ (fuel : Nat) (ts ts' : List Tok), Rel2 R ts ts' →
      RSim R (parseSeq fuel dict self ts) (parseSeq fuel dict self ts')
  | 0, _, _, _ => by simp [parseSeq, RSim]
  | _ + 1, [], [], _ => ⟨rfl, rfl, .nil⟩
  | f + 1, t :: ts, t' :: ts', .cons ht hts => by
    have ih := parseSeq_congr hR f
    have hS : ∀ e e', RSim R (.error e) (.error e') := fun _ _ => trivial
    simp only [parseSeq]
    rcases hR t t' ht with he | ⟨m, m', h1, h2⟩
    · rw [he]
      cases classify dict self t' with
      | stop u => exact ⟨rfl, rfl, hts⟩
      | bad msg => trivial
      | prim w =>
        refine rsim_bind hS (ih ts ts' hts) ?_
        intro b s r r' hr; exact ⟨rfl, rfl, hr⟩
      | ifK =>
        refine rsim_bind hS (ih ts ts' hts) ?_
        intro b s r r' hr
        simp only
        by_cases hs1 : s = some kELSE
        · rw [iteT hs1, iteT hs1]
          refine rsim_bind hS (ih r r' hr) ?_
          intro b2 s2 r2 r2' hr2
          simp only
          by_cases hs2 : s2 = some kTHEN
          · rw [iteT hs2, iteT hs2]
            refine rsim_bind hS (ih r2 r2' hr2) ?_
            intro b3 s3 r3 r3' hr3; exact ⟨rfl, rfl, hr3⟩
          · rw [iteF hs2, iteF hs2]; trivial
        · rw [iteF hs1, iteF hs1]
          by_cases hs2 : s = some kTHEN
          · rw [iteT hs2, iteT hs2]
            refine rsim_bind hS (ih r r' hr) ?_
            intro b3 s3 r3 r3' hr3; exact ⟨rfl, rfl, hr3⟩
          · rw [iteF hs2, iteF hs2]; trivial
      | beginK =>
        refine rsim_bind hS (ih ts ts' hts) ?_
        intro b s r r' hr
        simp only
        by_cases hs1 : s = some kUNTIL
        · rw [iteT hs1, iteT hs1]
          refine rsim_bind hS (ih r r' hr) ?_
          intro b3 s3 r3 r3' hr3; exact ⟨rfl, rfl, hr3⟩
        · rw [iteF hs1, iteF hs1]; trivial
      | doK q =>
        refine rsim_bind hS (ih ts ts' hts) ?_
        intro b s r r' hr
        simp only
        by_cases hs1 : s = some kLOOP
        · rw [iteT hs1, iteT hs1]
          refine rsim_bind hS (ih r r' hr) ?_
          intro b3 s3 r3 r3' hr3; exact ⟨rfl, rfl, hr3⟩
        · rw [iteF hs1, iteF hs1]
          by_cases hs2 : s = some kPLOOP
          · rw [iteT hs2, iteT hs2]
            refine rsim_bind hS (ih r r' hr) ?_
            intro b3 s3 r3 r3' hr3; exact ⟨rfl, rfl, hr3⟩
          · rw [iteF hs2, iteF hs2]; trivial
    · rw [h1, h2]; trivial

/-- Tokens equal up to case. -/
def UEq (t t' : Tok) : Prop := upper t = upper t'

theorem parseTop_congr :
    ∀ (fuel : Nat) (dict : Dict) (defs : List Block) (vars : Nat) (main : Block)
      (toks toks' : List Tok), Rel2 UEq toks toks' →
      PSim (parseTop fuel dict defs vars main toks) (parseTop fuel dict defs vars main toks')
  | 0, _, _, _, _, _, _, _ => by simp [parseTop, PSim]
  | f + 1, dict, defs, vars, main, toks, toks', h => by
    have hS : ∀ e e', PSim (α := Program) (.error e) (.error e') := fun _ _ => trivial
    simp only [parseTop]
    rw [h.length_eq]
    refine rsim_bind hS (parseSeq_congr (fun t t' ht => classify_sim ht) _ _ _ h) ?_
    intro b s r r' hr
    simp only
    cases s with
    | none => rfl
    | some u =>
      simp only
      by_cases hc : u = kCOLON
      · rw [iteT hc, iteT hc]
        cases hr with
        | nil => trivial
        | @cons name name' body body' hn hb =>
          simp only
          rw [show upper name = upper name' from hn, hb.length_eq]
          refine rsim_bind hS (parseSeq_congr (fun t t' ht => classify_sim ht) _ _ _ hb) ?_
          intro bb s2 r2 r2' hr2
          simp only
          by_cases e1 : s2 = some kSEMI
          · rw [iteT e1, iteT e1]
            exact parseTop_congr f _ _ _ _ _ _ hr2
          · rw [iteF e1, iteF e1]
            by_cases e2 : s2 = some kCOLON
            · rw [iteT e2, iteT e2]; trivial
            · rw [iteF e2, iteF e2]
              by_cases e3 : s2 = some kVARIABLE ∨ s2 = some kCONSTANT
              · rw [iteT e3, iteT e3]; trivial
              · rw [iteF e3, iteF e3]; trivial
      · rw [iteF hc, iteF hc]
        by_cases hv : u = kVARIABLE
        · rw [iteT hv, iteT hv]
          cases hr with
          | nil => trivial
          | @cons name name' rest rest' hn hb =>
            simp only
            rw [show upper name = upper name' from hn]
            exact parseTop_congr f _ _ _ _ _ _ hb
        · rw [iteF hv, iteF hv]
          by_cases hk : u = kCONSTANT
          · rw [iteT hk, iteT hk]
            cases b.dropLastLit with
            | none => trivial
            | some p =>
              obtain ⟨b', z⟩ := p
              cases hr with
              | nil => trivial
              | @cons name name' rest rest' hn hb =>
                simp only
                rw [show upper name = upper name' from hn]
                exact parseTop_congr f _ _ _ _ _ _ hb
          · rw [iteF hk, iteF hk]; trivial

theorem forall₂_upper : ∀ toks : List Tok, Rel2 UEq toks (toks.map upper)
  | [] => .nil
  | t :: ts => .cons (upper_upper t).symm (forall₂_upper ts)

end ParseProps

open ParseProps in
/-- **Parsing is case-insensitive**: upper-casing the source gives the same result, except that
an error message may quote a token in its other spelling. (Upper-casing never changes a digit,
a sign, whitespace, `\`, `(` or `)`, and every word is looked up upper-cased.) -/
theorem parse_toUpper (src : String) :
    (parse (src.map Char.toUpper)).toOption = (parse src).toOption := by
  unfold parse
  rw [tokenize_upper]
  cases tokenize src with
  | error e => rfl
  | ok toks =>
    show (parseTokens (toks.map upper)).toOption = (parseTokens toks).toOption
    unfold parseTokens
    rw [List.length_map]
    have h := parseTop_congr (toks.length + 1) [] [] 0 .nil _ _ (forall₂_upper toks)
    revert h
    cases parseTop (toks.length + 1) [] [] 0 .nil toks <;>
      cases parseTop (toks.length + 1) [] [] 0 .nil (toks.map upper) <;>
      intro h <;> simp only [PSim] at h <;> (try subst h) <;> (try contradiction) <;> rfl

theorem parse_toUpper_ok {src : String} {P : Program} :
    parse (src.map Char.toUpper) = .ok P ↔ parse src = .ok P := by
  have := parse_toUpper src
  constructor
  · intro h; rw [h] at this
    cases h' : parse src <;> rw [h'] at this <;> simp_all [Except.toOption]
  · intro h; rw [h] at this
    cases h' : parse (src.map Char.toUpper) <;> rw [h'] at this <;> simp_all [Except.toOption]

/-- Sources that agree up to the case of their letters parse to the same program (or both
fail). -/
theorem parse_case_insensitive {src src' : String}
    (h : src.map Char.toUpper = src'.map Char.toUpper) :
    (parse src).toOption = (parse src').toOption := by
  rw [← parse_toUpper src, ← parse_toUpper src', h]

namespace ParseProps

/-! ## Comments -/

theorem flush_eq (cur : List Char) (l : List Tok) : flush cur l = flush cur [] ++ l := by
  unfold flush; split <;> simp

/-- The lexer is a left-to-right machine: after any prefix `a` it has emitted some tokens and
is in some state (`cur`, `skip`), and it continues from that state. -/
theorem lex_append : ∀ (a cur : List Char) (skip : Bool), (skip = true → cur = []) →
    ∃ (toks : List Tok) (cur' : List Char) (skip' : Bool), (skip' = true → cur' = []) ∧
      ∀ x, lex (a ++ x) cur skip = toks ++ lex x cur' skip' := by
  intro a
  induction a with
  | nil => intro cur skip h; exact ⟨[], cur, skip, h, fun _ => rfl⟩
  | cons c a ih =>
    intro cur skip hinv
    cases skip with
    | true =>
      by_cases hc : (c == '\n') = true
      · obtain ⟨t, c', s', hi, h⟩ := ih [] false (by simp)
        exact ⟨t, c', s', hi, fun x => by
          simp only [List.cons_append, lex, hc, ite_true]; exact h x⟩
      · obtain ⟨t, c', s', hi, h⟩ := ih [] true (fun _ => rfl)
        exact ⟨t, c', s', hi, fun x => by
          simp only [List.cons_append, lex, hc]; exact h x⟩
    | false =>
      by_cases hw : isWs c = true
      · by_cases hb : cur = ['\\']
        · by_cases hc : (c == '\n') = true
          · obtain ⟨t, c', s', hi, h⟩ := ih [] false (by simp)
            exact ⟨t, c', s', hi, fun x => by
              simp only [List.cons_append, lex, hw, hb, hc, ite_true]; exact h x⟩
          · obtain ⟨t, c', s', hi, h⟩ := ih [] true (fun _ => rfl)
            exact ⟨t, c', s', hi, fun x => by
              simp only [List.cons_append, lex, hw, hb, hc, ite_true]; exact h x⟩
        · obtain ⟨t, c', s', hi, h⟩ := ih [] false (by simp)
          exact ⟨flush cur [] ++ t, c', s', hi, fun x => by
            simp only [List.cons_append, lex, hw, hb, ite_true, ite_false]
            rw [h x, flush_eq, List.append_assoc]⟩
      · obtain ⟨t, c', s', hi, h⟩ := ih (c :: cur) false (by simp)
        exact ⟨t, c', s', hi, fun x => by
          simp only [List.cons_append, lex, hw]; exact h x⟩

/-- Inside a `\` comment, everything up to the next newline is dropped. -/
theorem lex_skip {x : List Char} : ∀ (s cur : List Char), (∀ ch ∈ s, ch ≠ '\n') →
    (s ≠ [] ∨ cur = []) → lex (s ++ x) cur true = lex x [] true
  | [], cur, _, h => by
    rcases h with h | rfl
    · exact absurd rfl h
    · rfl
  | ch :: s, cur, hs, _ => by
    have hc : (ch == '\n') = false := by simpa using hs ch (by simp)
    simp only [List.cons_append, lex, hc]
    exact lex_skip s [] (fun c hc => hs c (by simp [hc])) (.inr rfl)

/-- The text of a `( … )` comment body lexes to tokens none of which closes the comment. -/
theorem lex_paren_body {b : List Char} : ∀ (c cur : List Char), '\\' ∉ cur → ')' ∉ cur →
    (∀ ch ∈ c, ch ≠ ')' ∧ ch ≠ '\\') →
    ∃ ctoks : List Tok, (∀ t ∈ ctoks, t.getLast? ≠ some ')') ∧
      lex (c ++ ' ' :: ')' :: ' ' :: b) cur false = ctoks ++ [')'] :: lex b [] false
  | [], cur, h1, h2, _ => by
    have hb : cur ≠ ['\\'] := fun e => h1 (by simp [e])
    refine ⟨flush cur [], ?_, ?_⟩
    · intro t ht
      unfold flush at ht
      split at ht
      · simp at ht
      · simp only [List.mem_singleton] at ht
        subst ht
        intro e
        have := List.mem_of_getLast? e
        exact h2 (by simpa using this)
    · simp only [List.nil_append, lex, show isWs ' ' = true from rfl, hb, ite_true, ite_false,
        show isWs ')' = false from rfl, Bool.false_eq_true]
      rw [flush_eq]
      simp [flush]
  | ch :: c, cur, h1, h2, hc => by
    have hch := hc ch (by simp)
    have hc' := fun c' (h : c' ∈ c) => hc c' (by simp [h])
    by_cases hw : isWs ch = true
    · have hb : cur ≠ ['\\'] := fun e => h1 (by simp [e])
      obtain ⟨ct, hct, he⟩ := lex_paren_body c [] (by simp) (by simp) hc'
      refine ⟨flush cur [] ++ ct, ?_, ?_⟩
      · intro t ht
        simp only [List.mem_append] at ht
        rcases ht with ht | ht
        · unfold flush at ht
          split at ht
          · simp at ht
          · simp only [List.mem_singleton] at ht
            subst ht
            intro e
            have := List.mem_of_getLast? e
            exact h2 (by simpa using this)
        · exact hct t ht
      · simp only [List.cons_append, lex, hw, hb, ite_true, ite_false]
        rw [he, flush_eq]; simp
    · obtain ⟨ct, hct, he⟩ := lex_paren_body c (ch :: cur)
        (by simp [h1, Ne.symm hch.2]) (by simp [h2, Ne.symm hch.1]) hc'
      refine ⟨ct, hct, ?_⟩
      simp only [List.cons_append, lex, hw, Bool.false_eq_true, ite_false]
      exact he

theorem stripParens_close {rest : List Tok} : ∀ cs : List Tok,
    (∀ t ∈ cs, t.getLast? ≠ some ')') →
    stripParens true (cs ++ [')'] :: rest) = stripParens false rest
  | [], _ => by simp [stripParens]
  | t :: cs, h => by
    simp only [List.cons_append, stripParens, iteF (h t (by simp))]
    exact stripParens_close cs (fun t' ht => h t' (by simp [ht]))

theorem stripParens_append {rest : List Tok} : ∀ (ts us : List Tok) (inside : Bool),
    stripParens inside ts = .ok us →
    stripParens inside (ts ++ rest) = (us ++ ·) <$> stripParens false rest
  | [], us, false, h => by
    cases h
    simp only [List.nil_append]
    cases stripParens false rest <;> rfl
  | [], us, true, h => by cases h
  | t :: ts, us, false, h => by
    simp only [List.cons_append, stripParens] at h ⊢
    split
    · rename_i ht; rw [iteT ht] at h; exact stripParens_append ts us true h
    · rename_i ht
      rw [iteF ht] at h
      cases hs : stripParens false ts with
      | error e => rw [hs] at h; cases h
      | ok us' =>
        rw [hs] at h
        cases h
        rw [stripParens_append ts us' false hs]
        cases stripParens false rest <;> rfl
  | t :: ts, us, true, h => by
    simp only [List.cons_append, stripParens] at h ⊢
    split
    · rename_i ht; rw [iteT ht] at h; exact stripParens_append ts us false h
    · rename_i ht; rw [iteF ht] at h; exact stripParens_append ts us true h

theorem lex_skip_step {c : Char} {cs cur : List Char} (hc : c ≠ '\n') :
    lex (c :: cs) cur true = lex cs [] true := by
  have : (c == '\n') = false := by simpa using hc
  simp only [lex, this, Bool.false_eq_true, ite_false]

theorem lex_nl_skip {cs cur : List Char} : lex ('\n' :: cs) cur true = lex cs [] false := by
  simp only [lex]; rfl

theorem lex_ws_bs {c : Char} {cs : List Char} (hw : isWs c = true) (hc : c ≠ '\n') :
    lex (c :: cs) ['\\'] false = lex cs [] true := by
  have : (c == '\n') = false := by simpa using hc
  simp only [lex, hw, this, ite_true, Bool.false_eq_true, ite_false]

theorem lex_nl_bs {cs : List Char} : lex ('\n' :: cs) ['\\'] false = lex cs [] false := by
  simp only [lex]; rfl

theorem lex_ws {c : Char} {cs cur : List Char} (hw : isWs c = true) (hb : cur ≠ ['\\']) :
    lex (c :: cs) cur false = flush cur (lex cs [] false) := by
  simp only [lex, hw, hb, ite_true, ite_false]

theorem lex_char {c : Char} {cs cur : List Char} (hw : isWs c = false) :
    lex (c :: cs) cur false = lex cs (c :: cur) false := by
  simp only [lex, hw, Bool.false_eq_true, ite_false]

end ParseProps

open ParseProps in
/-- **`( … )` comments are erased.** A comment ` ( c ) ` between `a` and `b` tokenizes like a
single space, provided `a` does not end inside an open `(` comment (`tokenize a` succeeds) and
the body `c` contains no `)` (which would close it early), no `\` (which could start a line
comment hiding the `)`) and no newline (which would end a `\` comment open at the end of `a`). -/
theorem tokenize_paren_comment {a b c : String} (ha : ∃ ts, tokenize a = .ok ts)
    (hc : ∀ ch ∈ c.toList, ch ≠ ')' ∧ ch ≠ '\\' ∧ ch ≠ '\n') :
    tokenize (a ++ " ( " ++ c ++ " ) " ++ b) = tokenize (a ++ " " ++ b) := by
  obtain ⟨ts, ha⟩ := ha
  unfold tokenize at ha ⊢
  have e1 : (a ++ " ( " ++ c ++ " ) " ++ b).toList =
      a.toList ++ (' ' :: '(' :: ' ' :: (c.toList ++ ' ' :: ')' :: ' ' :: b.toList)) := by simp
  have e2 : (a ++ " " ++ b).toList = a.toList ++ (' ' :: b.toList) := by simp
  rw [e1, e2]
  obtain ⟨toks, cur, skip, -, hsplit⟩ := lex_append a.toList [] false (by simp)
  rw [hsplit, hsplit]
  have hnl : ∀ ch ∈ ('(' :: ' ' :: (c.toList ++ [' ', ')', ' '])), ch ≠ '\n' := by
    intro ch hch
    simp only [List.mem_cons, List.mem_append, List.not_mem_nil, or_false] at hch
    rcases hch with rfl | rfl | h | rfl | rfl | rfl
    all_goals first | decide | exact (hc ch h).2.2
  have hskip : lex ('(' :: ' ' :: (c.toList ++ ' ' :: ')' :: ' ' :: b.toList)) [] true =
      lex b.toList [] true := by
    have := lex_skip ('(' :: ' ' :: (c.toList ++ [' ', ')', ' '])) [] hnl (.inl (by simp))
      (x := b.toList)
    simpa using this
  have hsp : isWs ' ' = true := rfl
  have hsn : ' ' ≠ '\n' := by decide
  cases skip with
  | true => rw [lex_skip_step hsn, lex_skip_step hsn, hskip]
  | false =>
    by_cases hb : cur = ['\\']
    · subst hb
      rw [lex_ws_bs hsp hsn, lex_ws_bs hsp hsn, hskip]
    · obtain ⟨ct, hct, hbody⟩ := lex_paren_body (b := b.toList) c.toList [] (by simp) (by simp)
        (fun ch h => ⟨(hc ch h).1, (hc ch h).2.1⟩)
      have hpre : stripParens false (toks ++ flush cur []) = .ok ts := by
        have := hsplit []
        simp only [List.append_nil, lex, hb, ite_false] at this
        rw [← this]; exact ha
      rw [lex_ws hsp hb, lex_ws hsp hb, lex_char (by decide), lex_ws hsp (by decide), hbody]
      have : flush ['('] (ct ++ [')'] :: lex b.toList [] false) =
          ['('] :: (ct ++ [')'] :: lex b.toList [] false) := rfl
      rw [this, flush_eq cur (['('] :: _), flush_eq cur (lex b.toList [] false)]
      rw [← List.append_assoc, ← List.append_assoc, stripParens_append _ _ _ hpre,
        stripParens_append _ _ _ hpre]
      simp only [stripParens, iteT, stripParens_close ct hct]

open ParseProps in
/-- **`\` comments are erased**: ` \ c` up to the end of the line is dropped (for any `a`; the
newline stays a separator). -/
theorem tokenize_line_comment {a b c : String} (hc : ∀ ch ∈ c.toList, ch ≠ '\n') :
    tokenize (a ++ " \\ " ++ c ++ "\n" ++ b) = tokenize (a ++ "\n" ++ b) := by
  unfold tokenize
  have e1 : (a ++ " \\ " ++ c ++ "\n" ++ b).toList =
      a.toList ++ (' ' :: '\\' :: ' ' :: (c.toList ++ '\n' :: b.toList)) := by simp
  have e2 : (a ++ "\n" ++ b).toList = a.toList ++ ('\n' :: b.toList) := by simp
  rw [e1, e2]
  obtain ⟨toks, cur, skip, -, hsplit⟩ := lex_append a.toList [] false (by simp)
  rw [hsplit, hsplit]
  have hsk : lex (c.toList ++ '\n' :: b.toList) [] true = lex b.toList [] false := by
    rw [lex_skip c.toList [] hc (.inr rfl), lex_nl_skip]
  have hsp : isWs ' ' = true := rfl
  have hsn : ' ' ≠ '\n' := by decide
  have hbn : '\\' ≠ '\n' := by decide
  cases skip with
  | true => rw [lex_skip_step hsn, lex_skip_step hbn, lex_skip_step hsn, hsk, lex_nl_skip]
  | false =>
    by_cases hb : cur = ['\\']
    · subst hb
      rw [lex_ws_bs hsp hsn, lex_skip_step hbn, lex_skip_step hsn, hsk, lex_nl_bs]
    · rw [lex_ws hsp hb, lex_char (by decide), lex_ws_bs hsp hsn, hsk, lex_ws rfl hb]

/-- At the end of the text, ` \ c` (no newline in `c`) is dropped. -/
theorem tokenize_line_comment_end {a c : String} (hc : ∀ ch ∈ c.toList, ch ≠ '\n') :
    tokenize (a ++ " \\ " ++ c) = tokenize a := by
  unfold tokenize
  have e1 : (a ++ " \\ " ++ c).toList = a.toList ++ (' ' :: '\\' :: ' ' :: c.toList) := by simp
  rw [e1, ← List.append_nil a.toList]
  obtain ⟨toks, cur, skip, hinv, hsplit⟩ := ParseProps.lex_append a.toList [] false (by simp)
  rw [hsplit, List.append_nil, hsplit]
  have hsk : lex c.toList [] true = [] := by
    have := ParseProps.lex_skip c.toList [] hc (.inr rfl) (x := [])
    simp only [List.append_nil] at this
    rw [this]; rfl
  have hsp : isWs ' ' = true := rfl
  have hsn : ' ' ≠ '\n' := by decide
  have hbn : '\\' ≠ '\n' := by decide
  cases skip with
  | true =>
    rw [hinv rfl, ParseProps.lex_skip_step hsn, ParseProps.lex_skip_step hbn,
      ParseProps.lex_skip_step hsn, hsk]
    rfl
  | false =>
    by_cases hb : cur = ['\\']
    · subst hb
      rw [ParseProps.lex_ws_bs hsp hsn, ParseProps.lex_skip_step hbn,
        ParseProps.lex_skip_step hsn, hsk]
      rfl
    · rw [ParseProps.lex_ws hsp hb, ParseProps.lex_char (by decide), ParseProps.lex_ws_bs hsp hsn,
        hsk]
      simp only [lex, hb, ite_false]

/-! ## `CONSTANT`, `RECURSE` and dictionary words -/

namespace ParseProps

theorem Block.append_nil : ∀ b : Block, b.append .nil = b
  | .nil => rfl
  | .op _ r => by simp [Block.append, Block.append_nil r]
  | .ite _ _ r => by simp [Block.append, Block.append_nil r]
  | .untilL _ r => by simp [Block.append, Block.append_nil r]
  | .call _ r => by simp [Block.append, Block.append_nil r]
  | .exit r => by simp [Block.append, Block.append_nil r]
  | .doLoop _ r => by simp [Block.append, Block.append_nil r]
  | .plusLoop _ r => by simp [Block.append, Block.append_nil r]
  | .leave r => by simp [Block.append, Block.append_nil r]

end ParseProps

open ParseProps

/-- A token whose upper-cased spelling is in the dictionary and is not a keyword means what the
dictionary says (dictionary entries shadow built-in words and numbers). -/
theorem classify_dict {dict : Dict} {self : Option Nat} {t : Tok} {w : Block → Block}
    (hk : upper t ∉ Print.keywords) (hl : dict.lookup (upper t) = some w) :
    classify dict self t = .prim w := by
  obtain ⟨h1, h2, h3, h4, h5, h6, h7, h8⟩ :=
    Print.not_keyword (t := upper t) (fun kw hkw e => hk (e ▸ hkw))
  simp only [classify]
  rw [iteF h1, iteF h2, iteF h3, iteF h4, iteF h5, iteF h6, iteF h7, iteF h8]
  simp only [lookupWord, hl]

/-- `RECURSE` (any case) inside the definition of word `i` is a call of word `i`. -/
theorem classify_recurse {dict : Dict} {i : Nat} {t : Tok} (h : upper t = kRECURSE) :
    classify dict (some i) t = .prim (.call i) := by
  simp only [classify, h]
  rfl

/-- One step of `parseSeq` over a word that compiles to `w`. -/
theorem parseSeq_prim {fuel : Nat} {dict : Dict} {self : Option Nat} {t : Tok} {ts : List Tok}
    {w : Block → Block} (h : classify dict self t = .prim w) :
    parseSeq (fuel + 1) dict self (t :: ts) =
      (parseSeq fuel dict self ts).map fun p => (w p.1, p.2.1, p.2.2) := by
  simp only [parseSeq, h]
  cases parseSeq fuel dict self ts <;> rfl

/-- **`CONSTANT`**: when the top-level code before `CONSTANT` ends in a literal `z`, the literal is
removed from the main block and `name` is entered in the dictionary as the literal `z`. -/
theorem parseTop_constant {fuel : Nat} {dict : Dict} {defs : List Block} {vars : Nat}
    {main b b' : Block} {toks rest : List Tok} {name : Tok} {z : Int}
    (h : parseSeq (toks.length + 1) dict none toks = .ok (b, some kCONSTANT, name :: rest))
    (hz : b.dropLastLit = some (b', z)) :
    parseTop (fuel + 1) dict defs vars main toks =
      parseTop fuel ((upper name, Block.op (.lit z)) :: dict) defs vars (main.append b') rest := by
  simp only [parseTop, h, bind, Except.bind, hz, ite_true]
  rw [iteF (by decide), iteF (by decide)]

/-- `n CONSTANT name` at the start of top-level code, with `n` a number literal not shadowed
by the dictionary: `name` is entered as the literal `n`, and the main block is unchanged. -/
theorem parseTop_constant_lit {fuel : Nat} {dict : Dict} {defs : List Block} {vars : Nat}
    {main : Block} {zt c name : Tok} {rest : List Tok} {z : Int}
    (hz : number (upper zt) = some z) (hzd : dict.lookup (upper zt) = none)
    (hc : upper c = kCONSTANT) :
    parseTop (fuel + 1) dict defs vars main (zt :: c :: name :: rest) =
      parseTop fuel ((upper name, Block.op (.lit z)) :: dict) defs vars main rest := by
  have hk : upper zt ∉ Print.keywords := fun hm => by
    have := Print.keyword_no_number _ hm; rw [hz] at this; cases this
  obtain ⟨h1, h2, h3, h4, h5, h6, h7, h8⟩ :=
    Print.not_keyword (t := upper zt) (fun kw hkw e => hk (e ▸ hkw))
  have hop : opTable.lookup (upper zt) = none := by
    cases h : opTable.lookup (upper zt) with
    | none => rfl
    | some o =>
      obtain ⟨k, hm, rfl⟩ := Print.lookup_some_mem h
      have := Print.opTable_no_number _ hm; simp only at this; rw [hz] at this; cases this
  have hcz : classify dict none zt = .prim (.op (.lit z)) := by
    simp only [classify]
    rw [iteF h1, iteF h2, iteF h3, iteF h4, iteF h5, iteF h6, iteF h7, iteF h8]
    simp only [lookupWord, hzd, hop, hz]
  have hcc : classify dict none c = .stop kCONSTANT := by
    rw [← hc]; simp only [classify, hc]; rfl
  have hseq : parseSeq ((zt :: c :: name :: rest).length + 1) dict none (zt :: c :: name :: rest) =
      .ok (.op (.lit z) .nil, some kCONSTANT, name :: rest) := by
    simp only [List.length_cons]
    rw [parseSeq_prim hcz]
    simp only [parseSeq, hcc]
    rfl
  rw [parseTop_constant hseq rfl, ParseProps.Block.append_nil]

/-- After `… CONSTANT name`, a token spelled like `name` (any case) is the literal. -/
theorem classify_constant {dict : Dict} {self : Option Nat} {name t : Tok} {z : Int}
    (hn : upper name ∉ Print.keywords) (ht : upper t = upper name) :
    classify ((upper name, Block.op (.lit z)) :: dict) self t = .prim (.op (.lit z)) :=
  classify_dict (ht ▸ hn) (by rw [ht]; exact Print.lookup_cons_self)

/-- **Colon definitions**: the body of a definition is parsed with the new word in the dictionary
(as a call of index `defs.length`, its index in the final program, see `parseTop_defs_prefix`)
and with `RECURSE` meaning that same call. -/
theorem parseTop_colon {fuel : Nat} {dict : Dict} {defs : List Block} {vars : Nat}
    {main bb : Block} {c name : Tok} {body rest : List Tok} (hc : upper c = kCOLON)
    (h : parseSeq (body.length + 1) ((upper name, Block.call defs.length) :: dict)
      (some defs.length) body = .ok (bb, some kSEMI, rest)) :
    parseTop (fuel + 1) dict defs vars main (c :: name :: body) =
      parseTop fuel ((upper name, Block.call defs.length) :: dict) (defs ++ [bb]) vars main
        rest := by
  have hcc : classify dict none c = .stop kCOLON := by
    rw [← hc]; simp only [classify, hc]; rfl
  simp only [parseTop, parseSeq, hcc, bind, Except.bind, iteT, h]
  rw [show main.append .nil = main from ParseProps.Block.append_nil main]

/-- Definitions only grow: the definitions present when `parseTop` reaches a point are the first
definitions of the final program. -/
theorem parseTop_defs_prefix :
    ∀ (fuel : Nat) (dict : Dict) (defs : List Block) (vars : Nat) (main : Block)
      (toks : List Tok) (P : Program),
      parseTop fuel dict defs vars main toks = .ok P → ∃ more, P.defs = defs ++ more
  | 0, _, _, _, _, _, _, h => by simp [parseTop] at h
  | fuel + 1, dict, defs, vars, main, toks, P, h => by
    simp only [parseTop] at h
    obtain ⟨⟨b, stop, rest⟩, -, h2⟩ := bind_ok h
    simp only at h2
    split at h2
    · cases h2; exact ⟨[], by simp⟩
    · split at h2
      · split at h2
        · cases h2
        · obtain ⟨⟨bb, s2, r2⟩, -, h4⟩ := bind_ok h2
          simp only at h4
          split at h4
          · obtain ⟨more, hm⟩ := parseTop_defs_prefix fuel _ _ _ _ _ P h4
            exact ⟨bb :: more, by simp [hm]⟩
          · split at h4
            · cases h4
            · split at h4 <;> cases h4
      · split at h2
        · split at h2
          · cases h2
          · exact parseTop_defs_prefix fuel _ _ _ _ _ P h2
        · split at h2
          · split at h2
            · cases h2
            · cases h2
            · exact parseTop_defs_prefix fuel _ _ _ _ _ P h2
          · cases h2

/-- Inside the definition of word `k` named `name`, `RECURSE` and `name` mean the same. -/
theorem classify_recurse_eq_name {dict : Dict} {k : Nat} {name t : Tok}
    (hn : upper name ∉ Print.keywords) (ht : upper t = kRECURSE) :
    classify ((upper name, Block.call k) :: dict) (some k) t =
      classify ((upper name, Block.call k) :: dict) (some k) name := by
  rw [classify_recurse ht, classify_dict hn Print.lookup_cons_self]

/-- **`RECURSE` is the word's own name**: inside the definition of word `k` named `name`,
replacing any `RECURSE` tokens by `name` does not change the parsed block or where it stops
(nor whether it fails). -/
theorem parseSeq_recurse_name {dict : Dict} {k : Nat} {name : Tok}
    (hn : upper name ∉ Print.keywords) (fuel : Nat) {ts ts' : List Tok}
    (h : Rel2 (fun t t' => t = t' ∨ (upper t = kRECURSE ∧ t' = name)) ts ts') :
    RSim (fun t t' => t = t' ∨ (upper t = kRECURSE ∧ t' = name))
      (parseSeq fuel ((upper name, Block.call k) :: dict) (some k) ts)
      (parseSeq fuel ((upper name, Block.call k) :: dict) (some k) ts') := by
  refine parseSeq_congr (fun t t' ht => ?_) fuel ts ts' h
  rcases ht with rfl | ⟨ht, rfl⟩
  · exact .inl rfl
  · exact .inl (classify_recurse_eq_name hn ht)

end Forth
end WordDialect
