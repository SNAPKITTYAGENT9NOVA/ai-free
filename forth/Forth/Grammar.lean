import Forth.ParseProps

/-!
# Forth.Grammar

A fuel-free specification of the parser, and the proofs that its fuel never runs out.

`parseSeq` and `parseTop` are defined with fuel so that they are structurally recursive (and
concrete parses are checked by `rfl`). This file shows that the fuel is irrelevant:

* **Grammar.** `Seq dict self ts b stop rest` is an inductive grammar for blocks: token list
  `ts` consists of block `b`, then the stop word `stop` (`none` at the end of input), then
  `rest`. Its rules are the productions `IF … ELSE … THEN`, `IF … THEN`, `BEGIN … UNTIL`,
  `BEGIN … WHILE … REPEAT`, `CASE … OF … ENDOF … ENDCASE`, `DO … LOOP`, `DO … +LOOP` (with
  `?DO` for `DO`) and single words, over the token
  classification `classify`. `Top` is the grammar of top-level code with `:` definitions,
  `VARIABLE` and `CONSTANT`, and `Prog` adds the `LEAVE` check. `parseSeq_iff`, `parseTop_iff`,
  `parseTokens_iff` and `parse_iff` prove that the parser accepts exactly these derivations, with
  their results, for every fuel larger than the input length (which is the fuel `parse` uses).
* **Fuel never runs out.** `parseSeq_ne_deep` and `parse_ne_fuel`: the errors
  `input too deeply nested` and `input too long` (`Parse.msgDeep`, `Parse.msgLong`) are never
  produced by `parse`. `parseSeq_fuel`: `parseSeq` gives the same result (including the error
  message) for every fuel larger than the input length.

The induction measure is the number of tokens: every recursive call of `parseSeq` gets a suffix
of its input, a stop word is consumed (`Seq.rest_le`, `Seq.rest_lt`), and every round of `parseTop`
consumes its stop word.
-/

namespace WordDialect
namespace Forth

open Parse

namespace Grammar

abbrev SeqRes := Except String (Block × Option Tok × List Tok)

/-- One step of `parseSeq` on input `t :: ts`, with `P` parsing the remaining blocks. -/
def seqStep (P : List Tok → SeqRes) (dict : Dict) (self : Option Nat) (t : Tok) (ts : List Tok) :
    SeqRes :=
  match classify dict self t with
  | .stop u => .ok (.nil, some u, ts)
  | .bad msg => .error msg
  | .prim w => do
    let (rest, stop, ts') ← P ts
    .ok (w rest, stop, ts')
  | .ifK => do
    let (tb, stop1, ts1) ← P ts
    if stop1 = some kELSE then
      let (eb, stop2, ts2) ← P ts1
      if stop2 = some kTHEN then
        let (rest, stop3, ts3) ← P ts2
        .ok (.ite tb eb rest, stop3, ts3)
      else .error "IF … ELSE without THEN"
    else if stop1 = some kTHEN then
      let (rest, stop3, ts3) ← P ts1
      .ok (.ite tb .nil rest, stop3, ts3)
    else .error "IF without THEN"
  | .beginK => do
    let (body, stop1, ts1) ← P ts
    if stop1 = some kUNTIL then
      let (rest, stop2, ts2) ← P ts1
      .ok (.untilL body rest, stop2, ts2)
    else if stop1 = some kWHILE then
      let (wb, stop2, ts2) ← P ts1
      if stop2 = some kREPEAT then
        let (rest, stop3, ts3) ← P ts2
        .ok (.whileL body wb rest, stop3, ts3)
      else .error "WHILE without REPEAT"
    else .error "BEGIN without UNTIL or WHILE"
  | .doK q => do
    let (body, stop1, ts1) ← P ts
    if stop1 = some kLOOP then
      let (rest, stop2, ts2) ← P ts1
      .ok (Block.loopOf q .doLoop body rest, stop2, ts2)
    else if stop1 = some kPLOOP then
      let (rest, stop2, ts2) ← P ts1
      .ok (Block.loopOf q .plusLoop body rest, stop2, ts2)
    else .error "DO without LOOP or +LOOP"
  | .caseK => do
    let (body, stop1, ts1) ← P ts
    if stop1 = some kENDCASE then
      let (rest, stop2, ts2) ← P ts1
      .ok (body.append (.op .drop rest), stop2, ts2)
    else .error "CASE without ENDCASE"
  | .ofK => do
    let (body, stop1, ts1) ← P ts
    if stop1 = some kENDOF then
      let (more, stop2, ts2) ← P ts1
      if stop2 = some kENDCASE then .ok (Block.ofClause body more, stop2, ts2)
      else .error "OF … ENDOF without ENDCASE"
    else .error "OF without ENDOF"

theorem parseSeq_succ (f : Nat) (dict : Dict) (self : Option Nat) (t : Tok) (ts : List Tok) :
    parseSeq (f + 1) dict self (t :: ts) = seqStep (parseSeq f dict self) dict self t ts := rfl

/-! ## The grammar of blocks -/

/-- `Seq dict self ts b stop rest`: the tokens `ts` are block `b`, then the stop word `stop`
(`none`: the end of the input), then the tokens `rest`. Words are classified by `classify`
(keywords, the dictionary `dict`, built-in words, numbers; `self` is the word being defined). -/
inductive Seq (dict : Dict) (self : Option Nat) : List Tok → Block → Option Tok → List Tok → Prop
  | eof : Seq dict self [] .nil none []
  | stop {t : Tok} {ts : List Tok} {u : Tok} :
      classify dict self t = .stop u → Seq dict self (t :: ts) .nil (some u) ts
  | prim {t : Tok} {ts : List Tok} {w : Block → Block} {b : Block} {st : Option Tok}
      {r : List Tok} :
      classify dict self t = .prim w → Seq dict self ts b st r → Seq dict self (t :: ts) (w b) st r
  | ifElse {t : Tok} {ts ts1 ts2 r : List Tok} {tb eb rb : Block} {st : Option Tok} :
      classify dict self t = .ifK → Seq dict self ts tb (some kELSE) ts1 →
      Seq dict self ts1 eb (some kTHEN) ts2 → Seq dict self ts2 rb st r →
      Seq dict self (t :: ts) (.ite tb eb rb) st r
  | ifThen {t : Tok} {ts ts1 r : List Tok} {tb rb : Block} {st : Option Tok} :
      classify dict self t = .ifK → Seq dict self ts tb (some kTHEN) ts1 →
      Seq dict self ts1 rb st r → Seq dict self (t :: ts) (.ite tb .nil rb) st r
  | begin {t : Tok} {ts ts1 r : List Tok} {body rb : Block} {st : Option Tok} :
      classify dict self t = .beginK → Seq dict self ts body (some kUNTIL) ts1 →
      Seq dict self ts1 rb st r → Seq dict self (t :: ts) (.untilL body rb) st r
  | whileL {t : Tok} {ts ts1 ts2 r : List Tok} {cond body rb : Block} {st : Option Tok} :
      classify dict self t = .beginK → Seq dict self ts cond (some kWHILE) ts1 →
      Seq dict self ts1 body (some kREPEAT) ts2 → Seq dict self ts2 rb st r →
      Seq dict self (t :: ts) (.whileL cond body rb) st r
  | caseB {t : Tok} {ts ts1 r : List Tok} {body rb : Block} {st : Option Tok} :
      classify dict self t = .caseK → Seq dict self ts body (some kENDCASE) ts1 →
      Seq dict self ts1 rb st r → Seq dict self (t :: ts) (body.append (.op .drop rb)) st r
  | ofB {t : Tok} {ts ts1 r : List Tok} {body more : Block} :
      classify dict self t = .ofK → Seq dict self ts body (some kENDOF) ts1 →
      Seq dict self ts1 more (some kENDCASE) r →
      Seq dict self (t :: ts) (Block.ofClause body more) (some kENDCASE) r
  | doLoop {q : Bool} {t : Tok} {ts ts1 r : List Tok} {body rb : Block} {st : Option Tok} :
      classify dict self t = .doK q → Seq dict self ts body (some kLOOP) ts1 →
      Seq dict self ts1 rb st r → Seq dict self (t :: ts) (Block.loopOf q .doLoop body rb) st r
  | plusLoop {q : Bool} {t : Tok} {ts ts1 r : List Tok} {body rb : Block} {st : Option Tok} :
      classify dict self t = .doK q → Seq dict self ts body (some kPLOOP) ts1 →
      Seq dict self ts1 rb st r → Seq dict self (t :: ts) (Block.loopOf q .plusLoop body rb) st r

/-- The remaining tokens are a suffix: no longer than the input, and shorter when a stop word
was met. -/
theorem Seq.rest {dict : Dict} {self : Option Nat} {ts : List Tok} {b : Block} {st : Option Tok}
    {r : List Tok} (h : Seq dict self ts b st r) :
    r.length ≤ ts.length ∧ (st ≠ none → r.length < ts.length) := by
  induction h with
  | eof => exact ⟨Nat.le_refl _, fun h => absurd rfl h⟩
  | stop => simp
  | prim _ _ ih => simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih.2 h; omega⟩
  | ifElse _ _ _ _ ih1 ih2 ih3 =>
    have := ih1.2 (by simp); have := ih2.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih3.2 h; omega⟩
  | ifThen _ _ _ ih1 ih2 =>
    have := ih1.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih2.2 h; omega⟩
  | begin _ _ _ ih1 ih2 =>
    have := ih1.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih2.2 h; omega⟩
  | whileL _ _ _ _ ih1 ih2 ih3 =>
    have := ih1.2 (by simp); have := ih2.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih3.2 h; omega⟩
  | caseB _ _ _ ih1 ih2 =>
    have := ih1.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih2.2 h; omega⟩
  | ofB _ _ _ ih1 ih2 =>
    have := ih1.2 (by simp); have := ih2.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun _ => by omega⟩
  | doLoop _ _ _ ih1 ih2 =>
    have := ih1.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih2.2 h; omega⟩
  | plusLoop _ _ _ ih1 ih2 =>
    have := ih1.2 (by simp)
    simp only [List.length_cons]; exact ⟨by omega, fun h => by have := ih2.2 h; omega⟩

theorem Seq.rest_le {dict : Dict} {self : Option Nat} {ts : List Tok} {b : Block}
    {st : Option Tok} {r : List Tok} (h : Seq dict self ts b st r) : r.length ≤ ts.length :=
  h.rest.1

theorem Seq.rest_lt {dict : Dict} {self : Option Nat} {ts : List Tok} {b : Block} {u : Tok}
    {r : List Tok} (h : Seq dict self ts b (some u) r) : r.length < ts.length :=
  h.rest.2 (by simp)

open ParseProps in
/-- **Soundness**: every successful run of `parseSeq`, for any fuel, is a derivation. -/
theorem parseSeq_sound {dict : Dict} {self : Option Nat} :
    ∀ (f : Nat) (ts : List Tok) (b : Block) (st : Option Tok) (r : List Tok),
      parseSeq f dict self ts = .ok (b, st, r) → Seq dict self ts b st r
  | 0, _, _, _, _, h => by simp [parseSeq] at h
  | _ + 1, [], _, _, _, h => by
    simp only [parseSeq, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h; exact .eof
  | f + 1, t :: ts, b, st, r, h => by
    rw [parseSeq_succ] at h
    unfold seqStep at h
    split at h
    · rename_i u hc; cases h; exact .stop hc
    · cases h
    · rename_i w hc
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      cases h2
      exact .prim hc (parseSeq_sound f ts _ _ _ h1)
    · rename_i hc
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have d1 := parseSeq_sound f ts b1 s1 r1 h1
      simp only at h2
      split at h2
      · rename_i e1; subst e1
        obtain ⟨⟨b2, s2, r2⟩, h3, h4⟩ := bind_ok h2
        have d2 := parseSeq_sound f _ b2 s2 r2 h3
        simp only at h4
        split at h4
        · rename_i e2; subst e2
          obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h4
          cases h6
          exact .ifElse hc d1 d2 (parseSeq_sound f _ _ _ _ h5)
        · cases h4
      · split at h2
        · rename_i _ e1; subst e1
          obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
          cases h6
          exact .ifThen hc d1 (parseSeq_sound f _ _ _ _ h5)
        · cases h2
    · rename_i hc
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have d1 := parseSeq_sound f ts b1 s1 r1 h1
      simp only at h2
      split at h2
      · rename_i e1; subst e1
        obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
        cases h6
        exact .begin hc d1 (parseSeq_sound f _ _ _ _ h5)
      · split at h2
        · rename_i _ e1; subst e1
          obtain ⟨⟨b2, s2, r2⟩, h3, h4⟩ := bind_ok h2
          have d2 := parseSeq_sound f _ b2 s2 r2 h3
          simp only at h4
          split at h4
          · rename_i e2; subst e2
            obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h4
            cases h6
            exact .whileL hc d1 d2 (parseSeq_sound f _ _ _ _ h5)
          · cases h4
        · cases h2
    · rename_i q hc
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have d1 := parseSeq_sound f ts b1 s1 r1 h1
      simp only at h2
      split at h2
      · rename_i e1; subst e1
        obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
        cases h6
        exact .doLoop hc d1 (parseSeq_sound f _ _ _ _ h5)
      · split at h2
        · rename_i _ e1; subst e1
          obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
          cases h6
          exact .plusLoop hc d1 (parseSeq_sound f _ _ _ _ h5)
        · cases h2
    · rename_i hc
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have d1 := parseSeq_sound f ts b1 s1 r1 h1
      simp only at h2
      split at h2
      · rename_i e1; subst e1
        obtain ⟨⟨b3, s3, r3⟩, h5, h6⟩ := bind_ok h2
        cases h6
        exact .caseB hc d1 (parseSeq_sound f _ _ _ _ h5)
      · cases h2
    · rename_i hc
      obtain ⟨⟨b1, s1, r1⟩, h1, h2⟩ := bind_ok h
      have d1 := parseSeq_sound f ts b1 s1 r1 h1
      simp only at h2
      split at h2
      · rename_i e1; subst e1
        obtain ⟨⟨b2, s2, r2⟩, h3, h4⟩ := bind_ok h2
        have d2 := parseSeq_sound f _ b2 s2 r2 h3
        simp only at h4
        split at h4
        · rename_i e2; subst e2
          cases h4
          exact .ofB hc d1 d2
        · cases h4
      · cases h2

/-- **Completeness**: every derivation is found by `parseSeq` with any fuel larger than the
number of tokens. -/
theorem parseSeq_complete {dict : Dict} {self : Option Nat} {ts : List Tok} {b : Block}
    {st : Option Tok} {r : List Tok} (h : Seq dict self ts b st r) :
    ∀ f, ts.length < f → parseSeq f dict self ts = .ok (b, st, r) := by
  induction h with
  | eof => intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩; rfl
  | stop hc =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    rw [parseSeq_succ]; simp only [seqStep, hc]
  | prim hc _ ih =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih f (by omega)]; rfl
  | ifElse hc d1 d2 _ ih1 ih2 ih3 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt; have l2 := d2.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, ite_true]
    rw [ih2 f (by omega)]
    simp only [ite_true]
    rw [ih3 f (by omega)]
  | ifThen hc d1 _ ih1 ih2 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, show (some kTHEN = some kELSE) = False by decide, ite_false,
      ite_true]
    rw [ih2 f (by omega)]
  | begin hc d1 _ ih1 ih2 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, ite_true]
    rw [ih2 f (by omega)]
  | whileL hc d1 d2 _ ih1 ih2 ih3 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt; have l2 := d2.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, show (some kWHILE = some kUNTIL) = False by decide, ite_false,
      ite_true]
    rw [ih2 f (by omega)]
    simp only [ite_true]
    rw [ih3 f (by omega)]
  | doLoop hc d1 _ ih1 ih2 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, ite_true]
    rw [ih2 f (by omega)]
  | plusLoop hc d1 _ ih1 ih2 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, show (some kPLOOP = some kLOOP) = False by decide, ite_false,
      ite_true]
    rw [ih2 f (by omega)]
  | caseB hc d1 _ ih1 ih2 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, ite_true]
    rw [ih2 f (by omega)]
  | ofB hc d1 _ ih1 ih2 =>
    intro f hf; obtain ⟨f, rfl⟩ : ∃ g, f = g + 1 := ⟨f - 1, by omega⟩
    simp only [List.length_cons] at hf
    have l1 := d1.rest_lt
    rw [parseSeq_succ]; simp only [seqStep, hc]
    rw [ih1 f (by omega)]
    simp only [bind, Except.bind, ite_true]
    rw [ih2 f (by omega)]
    simp only [ite_true]

/-- **`parseSeq` implements the grammar** for every fuel larger than the input. -/
theorem parseSeq_iff {dict : Dict} {self : Option Nat} {f : Nat} {ts : List Tok} {b : Block}
    {st : Option Tok} {r : List Tok} (hf : ts.length < f) :
    parseSeq f dict self ts = .ok (b, st, r) ↔ Seq dict self ts b st r :=
  ⟨parseSeq_sound f ts b st r, fun h => parseSeq_complete h f hf⟩

/-- The grammar is unambiguous: a token list has at most one parse. -/
theorem Seq.unique {dict : Dict} {self : Option Nat} {ts : List Tok} {b b' : Block}
    {st st' : Option Tok} {r r' : List Tok} (h : Seq dict self ts b st r)
    (h' : Seq dict self ts b' st' r') : b = b' ∧ st = st' ∧ r = r' := by
  have e := (parseSeq_complete h _ (Nat.lt_succ_self _)).symm.trans
    (parseSeq_complete h' _ (Nat.lt_succ_self _))
  simp only [Except.ok.injEq, Prod.mk.injEq] at e
  exact e

/-! ## The fuel of `parseSeq` -/

theorem bind_congr {α β : Type} {x y : Except String α} {k k' : α → Except String β}
    (hxy : x = y) (h : ∀ a, x = .ok a → k a = k' a) : x >>= k = y >>= k' := by
  subst hxy
  cases x with
  | error e => rfl
  | ok a => exact h a rfl

/-- `seqStep` only looks at its parser on suffixes of the input. -/
theorem seqStep_congr {P Q : List Tok → SeqRes} {dict : Dict} {self : Option Nat} {t : Tok}
    {ts : List Tok} (hPQ : ∀ X, X.length ≤ ts.length → P X = Q X)
    (hP : ∀ X b s r, P X = .ok (b, s, r) → r.length ≤ X.length) :
    seqStep P dict self t ts = seqStep Q dict self t ts := by
  unfold seqStep
  cases classify dict self t with
  | stop u => rfl
  | bad m => rfl
  | prim w => rw [hPQ ts (Nat.le_refl _)]
  | ifK =>
    refine bind_congr (hPQ ts (Nat.le_refl _)) ?_
    rintro ⟨tb, s1, ts1⟩ h1
    have l1 := hP _ _ _ _ h1
    simp only
    split
    · refine bind_congr (hPQ ts1 l1) ?_
      rintro ⟨eb, s2, ts2⟩ h2
      have l2 := hP _ _ _ _ h2
      simp only
      split
      · exact bind_congr (hPQ ts2 (by omega)) (fun _ _ => rfl)
      · rfl
    · split
      · exact bind_congr (hPQ ts1 l1) (fun _ _ => rfl)
      · rfl
  | beginK =>
    refine bind_congr (hPQ ts (Nat.le_refl _)) ?_
    rintro ⟨b1, s1, ts1⟩ h1
    have l1 := hP _ _ _ _ h1
    simp only
    split
    · exact bind_congr (hPQ ts1 l1) (fun _ _ => rfl)
    · split
      · refine bind_congr (hPQ ts1 l1) ?_
        rintro ⟨b2, s2, ts2⟩ h2
        have l2 := hP _ _ _ _ h2
        simp only
        split
        · exact bind_congr (hPQ ts2 (by omega)) (fun _ _ => rfl)
        · rfl
      · rfl
  | doK q =>
    refine bind_congr (hPQ ts (Nat.le_refl _)) ?_
    rintro ⟨b1, s1, ts1⟩ h1
    have l1 := hP _ _ _ _ h1
    simp only
    split
    · exact bind_congr (hPQ ts1 l1) (fun _ _ => rfl)
    · split
      · exact bind_congr (hPQ ts1 l1) (fun _ _ => rfl)
      · rfl
  | caseK =>
    refine bind_congr (hPQ ts (Nat.le_refl _)) ?_
    rintro ⟨b1, s1, ts1⟩ h1
    have l1 := hP _ _ _ _ h1
    simp only
    split
    · exact bind_congr (hPQ ts1 l1) (fun _ _ => rfl)
    · rfl
  | ofK =>
    refine bind_congr (hPQ ts (Nat.le_refl _)) ?_
    rintro ⟨b1, s1, ts1⟩ h1
    have l1 := hP _ _ _ _ h1
    simp only
    split
    · exact bind_congr (hPQ ts1 l1) (fun _ _ => rfl)
    · rfl

theorem parseSeq_rest_le {dict : Dict} {self : Option Nat} {f : Nat} {X : List Tok} {b : Block}
    {s : Option Tok} {r : List Tok} (h : parseSeq f dict self X = .ok (b, s, r)) :
    r.length ≤ X.length :=
  (parseSeq_sound f X b s r h).rest_le

theorem parseSeq_fuel_succ {dict : Dict} {self : Option Nat} :
    ∀ (f : Nat) (ts : List Tok), ts.length < f →
      parseSeq (f + 1) dict self ts = parseSeq f dict self ts
  | 0, _, h => by simp at h
  | f + 1, [], _ => rfl
  | f + 1, t :: ts, h => by
    simp only [List.length_cons] at h
    rw [parseSeq_succ, parseSeq_succ]
    exact seqStep_congr (fun X hX => parseSeq_fuel_succ f X (by omega))
      (fun _ _ _ _ h => parseSeq_rest_le h)

/-- **Fuel independence**: `parseSeq` gives the same result, errors included, for every fuel
larger than the number of tokens. -/
theorem parseSeq_fuel {dict : Dict} {self : Option Nat} {ts : List Tok} {f g : Nat}
    (hf : ts.length < f) (hg : ts.length < g) :
    parseSeq f dict self ts = parseSeq g dict self ts := by
  have key : ∀ k, parseSeq (ts.length + 1 + k) dict self ts = parseSeq (ts.length + 1) dict self ts := by
    intro k
    induction k with
    | zero => rfl
    | succ k ih => rw [← Nat.add_assoc, parseSeq_fuel_succ _ _ (by omega), ih]
  obtain ⟨k, rfl⟩ : ∃ k, f = ts.length + 1 + k := ⟨f - (ts.length + 1), by omega⟩
  obtain ⟨j, rfl⟩ : ∃ j, g = ts.length + 1 + j := ⟨g - (ts.length + 1), by omega⟩
  rw [key, key]

/-! ## Error messages -/

theorem head_append {a x : String} {c : Char} (h : a.toList.head? = some c) :
    (a ++ x).toList.head? = some c := by
  rw [String.toList_append]
  cases ha : a.toList with
  | nil => rw [ha] at h; cases h
  | cons d ds => rw [ha] at h; simpa using h

theorem ne_of_head {a b : String} {c d : Char} (ha : a.toList.head? = some c)
    (hb : b.toList.head? = some d) (h : c ≠ d) : a ≠ b := by
  intro e; subst e; rw [ha] at hb; exact h (Option.some.inj hb)

/-- The two fuel errors. -/
def FuelMsg (e : String) : Prop := e = msgDeep ∨ e = msgLong

/-- A message starting with a letter other than `i` is not a fuel error. -/
theorem not_fuelMsg_of_head {e : String} {c : Char} (h : e.toList.head? = some c)
    (hc : c ≠ 'i') : ¬FuelMsg e := by
  rintro (rfl | rfl)
  · exact ne_of_head (d := 'i') h (by decide) hc rfl
  · exact ne_of_head (d := 'i') h (by decide) hc rfl

theorem classify_bad_msg {dict : Dict} {self : Option Nat} {t : Tok} {m : String}
    (h : classify dict self t = .bad m) : ¬FuelMsg m := by
  simp only [classify, lookupWord] at h
  by_cases h1 : upper t ∈ stops
  · rw [ParseProps.iteT h1] at h; cases h
  rw [ParseProps.iteF h1] at h
  by_cases h2 : upper t = kIF
  · rw [ParseProps.iteT h2] at h; cases h
  rw [ParseProps.iteF h2] at h
  by_cases h3 : upper t = kBEGIN
  · rw [ParseProps.iteT h3] at h; cases h
  rw [ParseProps.iteF h3] at h
  by_cases h4 : upper t = kRECURSE
  · rw [ParseProps.iteT h4] at h
    cases self with
    | some j => cases h
    | none => cases h; exact not_fuelMsg_of_head (c := 'R') (by decide) (by decide)
  rw [ParseProps.iteF h4] at h
  by_cases h5 : upper t = kEXIT
  · rw [ParseProps.iteT h5] at h
    cases self with
    | some j => cases h
    | none => cases h; exact not_fuelMsg_of_head (c := 'E') (by decide) (by decide)
  rw [ParseProps.iteF h5] at h
  by_cases h6 : upper t = kDO
  · rw [ParseProps.iteT h6] at h; cases h
  rw [ParseProps.iteF h6] at h
  by_cases h7 : upper t = kQDO
  · rw [ParseProps.iteT h7] at h; cases h
  rw [ParseProps.iteF h7] at h
  by_cases h8 : upper t = kLEAVE
  · rw [ParseProps.iteT h8] at h; cases h
  rw [ParseProps.iteF h8] at h
  by_cases h9 : upper t = kQDUP
  · rw [ParseProps.iteT h9] at h; cases h
  rw [ParseProps.iteF h9] at h
  by_cases h10 : upper t = kCASE
  · rw [ParseProps.iteT h10] at h; cases h
  rw [ParseProps.iteF h10] at h
  by_cases h11 : upper t = kOF
  · rw [ParseProps.iteT h11] at h; cases h
  rw [ParseProps.iteF h11] at h
  split at h
  · cases h
  split at h
  · cases h
  split at h
  · cases h
  · cases h; exact not_fuelMsg_of_head (c := 'u') (head_append (by decide)) (by decide)

/-- Where an error of `seqStep` comes from: a bad word, a recursive call on a suffix, or one of
the messages about unbalanced control words. -/
theorem seqStep_error {P : List Tok → SeqRes} {dict : Dict} {self : Option Nat} {t : Tok}
    {ts : List Tok} {e : String}
    (hP : ∀ X b s r, P X = .ok (b, s, r) → r.length ≤ X.length)
    (h : seqStep P dict self t ts = .error e) :
    classify dict self t = .bad e ∨ (∃ X, X.length ≤ ts.length ∧ P X = .error e) ∨
      e ∈ ["IF … ELSE without THEN", "IF without THEN", "BEGIN without UNTIL or WHILE",
        "WHILE without REPEAT", "DO without LOOP or +LOOP", "CASE without ENDCASE",
        "OF … ENDOF without ENDCASE", "OF without ENDOF"] := by
  have bind_err : ∀ {α : Type} {x : Except String α} {k : α → SeqRes},
      x >>= k = .error e → x = .error e ∨ ∃ a, x = .ok a ∧ k a = .error e := by
    intro α x k hx
    cases x with
    | error e' => left; simpa [bind, Except.bind] using hx
    | ok a => exact .inr ⟨a, rfl, hx⟩
  unfold seqStep at h
  split at h
  · cases h
  · rename_i hc; cases h; exact .inl hc
  · rcases bind_err h with h1 | ⟨_, _, h2⟩
    · exact .inr (.inl ⟨ts, Nat.le_refl _, h1⟩)
    · cases h2
  · rcases bind_err h with h1 | ⟨⟨tb, s1, ts1⟩, h1, h2⟩
    · exact .inr (.inl ⟨ts, Nat.le_refl _, h1⟩)
    have l1 := hP _ _ _ _ h1
    simp only at h2
    split at h2
    · rcases bind_err h2 with h3 | ⟨⟨eb, s2, ts2⟩, h3, h4⟩
      · exact .inr (.inl ⟨ts1, l1, h3⟩)
      have l2 := hP _ _ _ _ h3
      simp only at h4
      split at h4
      · rcases bind_err h4 with h5 | ⟨_, _, h6⟩
        · exact .inr (.inl ⟨ts2, by omega, h5⟩)
        · cases h6
      · cases h4; simp
    · split at h2
      · rcases bind_err h2 with h5 | ⟨_, _, h6⟩
        · exact .inr (.inl ⟨ts1, l1, h5⟩)
        · cases h6
      · cases h2; simp
  · rcases bind_err h with h1 | ⟨⟨b1, s1, ts1⟩, h1, h2⟩
    · exact .inr (.inl ⟨ts, Nat.le_refl _, h1⟩)
    have l1 := hP _ _ _ _ h1
    simp only at h2
    split at h2
    · rcases bind_err h2 with h5 | ⟨_, _, h6⟩
      · exact .inr (.inl ⟨ts1, l1, h5⟩)
      · cases h6
    · split at h2
      · rcases bind_err h2 with h3 | ⟨⟨b2, s2, ts2⟩, h3, h4⟩
        · exact .inr (.inl ⟨ts1, l1, h3⟩)
        have l2 := hP _ _ _ _ h3
        simp only at h4
        split at h4
        · rcases bind_err h4 with h5 | ⟨_, _, h6⟩
          · exact .inr (.inl ⟨ts2, by omega, h5⟩)
          · cases h6
        · cases h4; simp
      · cases h2; simp
  · rcases bind_err h with h1 | ⟨⟨b1, s1, ts1⟩, h1, h2⟩
    · exact .inr (.inl ⟨ts, Nat.le_refl _, h1⟩)
    have l1 := hP _ _ _ _ h1
    simp only at h2
    split at h2
    · rcases bind_err h2 with h5 | ⟨_, _, h6⟩
      · exact .inr (.inl ⟨ts1, l1, h5⟩)
      · cases h6
    · split at h2
      · rcases bind_err h2 with h5 | ⟨_, _, h6⟩
        · exact .inr (.inl ⟨ts1, l1, h5⟩)
        · cases h6
      · cases h2; simp
  · rcases bind_err h with h1 | ⟨⟨b1, s1, ts1⟩, h1, h2⟩
    · exact .inr (.inl ⟨ts, Nat.le_refl _, h1⟩)
    have l1 := hP _ _ _ _ h1
    simp only at h2
    split at h2
    · rcases bind_err h2 with h5 | ⟨_, _, h6⟩
      · exact .inr (.inl ⟨ts1, l1, h5⟩)
      · cases h6
    · cases h2; simp
  · rcases bind_err h with h1 | ⟨⟨b1, s1, ts1⟩, h1, h2⟩
    · exact .inr (.inl ⟨ts, Nat.le_refl _, h1⟩)
    have l1 := hP _ _ _ _ h1
    simp only at h2
    split at h2
    · rcases bind_err h2 with h5 | ⟨⟨b2, s2, ts2⟩, h5, h6⟩
      · exact .inr (.inl ⟨ts1, l1, h5⟩)
      · simp only at h6
        split at h6
        · cases h6
        · cases h6; simp
    · cases h2; simp

theorem seqMsgs_not_fuel {e : String}
    (h : e ∈ ["IF … ELSE without THEN", "IF without THEN", "BEGIN without UNTIL or WHILE",
      "WHILE without REPEAT", "DO without LOOP or +LOOP", "CASE without ENDCASE",
      "OF … ENDOF without ENDCASE", "OF without ENDOF"]) : ¬FuelMsg e := by
  simp only [List.mem_cons, List.mem_nil_iff, or_false] at h
  rcases h with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    (rintro (h | h) <;> exact absurd h (by decide))

/-- With fuel larger than the input, `parseSeq` never fails for lack of fuel, and for any fuel
it never reports the `parseTop` fuel error. -/
theorem parseSeq_not_fuel {dict : Dict} {self : Option Nat} :
    ∀ (f : Nat) (ts : List Tok) (e : String), parseSeq f dict self ts = .error e →
      e ≠ msgLong ∧ (ts.length < f → e ≠ msgDeep)
  | 0, ts, e, h => by
    simp only [parseSeq, Except.error.injEq] at h; subst h
    exact ⟨by decide, fun h => by simp at h⟩
  | f + 1, [], e, h => by cases h
  | f + 1, t :: ts, e, h => by
    rw [parseSeq_succ] at h
    rcases seqStep_error (fun _ _ _ _ h => parseSeq_rest_le h) h with hc | ⟨X, hX, hX'⟩ | hm
    · have := classify_bad_msg hc
      exact ⟨fun h => this (.inr h), fun _ h => this (.inl h)⟩
    · have ih := parseSeq_not_fuel f X e hX'
      exact ⟨ih.1, fun hl => ih.2 (by simp at hl; omega)⟩
    · have := seqMsgs_not_fuel hm
      exact ⟨fun h => this (.inr h), fun _ h => this (.inl h)⟩

/-- **`input too deeply nested` is unreachable** with fuel larger than the input, which is the
fuel `parseTop` gives `parseSeq`. -/
theorem parseSeq_ne_deep {dict : Dict} {self : Option Nat} {f : Nat} {ts : List Tok}
    (hf : ts.length < f) : parseSeq f dict self ts ≠ .error msgDeep :=
  fun h => (parseSeq_not_fuel f ts _ h).2 hf rfl

/-! ## The grammar of programs -/

/-- `Top dict defs vars main toks P`: parsing the top-level tokens `toks`, with dictionary
`dict`, definitions `defs`, `vars` variables and top-level code `main` so far, gives program `P`.
Each round parses a block of top-level code, which ends at the end of the input, at `:` (a
definition `: name body ;`), at `VARIABLE name`, at `CONSTANT name` (taking the literal just
before it), at `CREATE name`, or at `ALLOT` or `,` (both taking the literal just before them). -/
inductive Top : Dict → List Block → Nat → Block → List Tok → Program → Prop
  | done {dict : Dict} {defs : List Block} {vars : Nat} {main b : Block} {toks r : List Tok} :
      Seq dict none toks b none r → Top dict defs vars main toks ⟨defs, main.append b, vars⟩
  | colon {dict : Dict} {defs : List Block} {vars : Nat} {main b bb : Block}
      {toks body rest2 : List Tok} {name : Tok} {P : Program} :
      Seq dict none toks b (some kCOLON) (name :: body) →
      Seq ((upper name, Block.call defs.length) :: dict) (some defs.length) body bb (some kSEMI)
        rest2 →
      Top ((upper name, Block.call defs.length) :: dict) (defs ++ [bb]) vars (main.append b) rest2 P →
      Top dict defs vars main toks P
  | var {dict : Dict} {defs : List Block} {vars : Nat} {main b : Block}
      {toks rest : List Tok} {name : Tok} {P : Program} :
      Seq dict none toks b (some kVARIABLE) (name :: rest) →
      Top ((upper name, Block.op (.lit vars)) :: dict) defs (vars + 1) (main.append b) rest P →
      Top dict defs vars main toks P
  | const {dict : Dict} {defs : List Block} {vars : Nat} {main b b' : Block} {z : Int}
      {toks rest : List Tok} {name : Tok} {P : Program} :
      Seq dict none toks b (some kCONSTANT) (name :: rest) → b.dropLastLit = some (b', z) →
      Top ((upper name, Block.op (.lit z)) :: dict) defs vars (main.append b') rest P →
      Top dict defs vars main toks P
  | create {dict : Dict} {defs : List Block} {vars : Nat} {main b : Block}
      {toks rest : List Tok} {name : Tok} {P : Program} :
      Seq dict none toks b (some kCREATE) (name :: rest) →
      Top ((upper name, Block.op (.lit vars)) :: dict) defs vars (main.append b) rest P →
      Top dict defs vars main toks P
  | allot {dict : Dict} {defs : List Block} {vars : Nat} {main b b' : Block} {z : Int}
      {toks rest : List Tok} {P : Program} :
      Seq dict none toks b (some kALLOT) rest → b.dropLastLit = some (b', z) →
      Top dict defs (vars + z.toNat) (main.append b') rest P → Top dict defs vars main toks P
  | comma {dict : Dict} {defs : List Block} {vars : Nat} {main b b' : Block} {z : Int}
      {toks rest : List Tok} {P : Program} :
      Seq dict none toks b (some kCOMMA) rest → b.dropLastLit = some (b', z) →
      Top dict defs (vars + 1)
        ((main.append b').append (.op (.lit z) (.op (.lit vars) (.op .store .nil)))) rest P →
      Top dict defs vars main toks P

/-- The grammar of whole programs: top-level code from the empty state, every `LEAVE` inside a
loop. -/
def Prog (toks : List Tok) (P : Program) : Prop := Top [] [] 0 .nil toks P ∧ P.leaveOK = true

open ParseProps in
theorem parseTop_sound :
    ∀ (fuel : Nat) (dict : Dict) (defs : List Block) (vars : Nat) (main : Block) (toks : List Tok)
      (P : Program), parseTop fuel dict defs vars main toks = .ok P → Top dict defs vars main toks P
  | 0, _, _, _, _, _, _, h => by simp [parseTop] at h
  | fuel + 1, dict, defs, vars, main, toks, P, h => by
    simp only [parseTop] at h
    obtain ⟨⟨b, stop, rest⟩, h1, h2⟩ := bind_ok h
    have d1 := parseSeq_sound _ _ _ _ _ h1
    simp only at h2
    split at h2
    · cases h2; exact .done d1
    · rename_i u
      split at h2
      · rename_i hu; subst hu
        split at h2
        · cases h2
        · rename_i name body
          obtain ⟨⟨bb, s2, r2⟩, h3, h4⟩ := bind_ok h2
          have d2 := parseSeq_sound _ _ _ _ _ h3
          simp only at h4
          split at h4
          · rename_i e2; subst e2
            exact .colon d1 d2 (parseTop_sound fuel _ _ _ _ _ _ h4)
          · split at h4
            · cases h4
            · split at h4 <;> cases h4
      · split at h2
        · rename_i hv; subst hv
          split at h2
          · cases h2
          · exact .var d1 (parseTop_sound fuel _ _ _ _ _ _ h2)
        · split at h2
          · rename_i hk; subst hk
            split at h2
            · cases h2
            · cases h2
            · rename_i hdl
              exact .const d1 hdl (parseTop_sound fuel _ _ _ _ _ _ h2)
          · split at h2
            · rename_i hc; subst hc
              split at h2
              · cases h2
              · exact .create d1 (parseTop_sound fuel _ _ _ _ _ _ h2)
            · split at h2
              · rename_i ha; subst ha
                split at h2
                · cases h2
                · rename_i hdl
                  exact .allot d1 hdl (parseTop_sound fuel _ _ _ _ _ _ h2)
              · split at h2
                · rename_i hm; subst hm
                  split at h2
                  · cases h2
                  · rename_i hdl
                    exact .comma d1 hdl (parseTop_sound fuel _ _ _ _ _ _ h2)
                · cases h2

theorem parseTop_complete {dict : Dict} {defs : List Block} {vars : Nat} {main : Block}
    {toks : List Tok} {P : Program} (h : Top dict defs vars main toks P) :
    ∀ fuel, toks.length < fuel → parseTop fuel dict defs vars main toks = .ok P := by
  induction h with
  | done d1 =>
    intro fuel hf; obtain ⟨f, rfl⟩ : ∃ g, fuel = g + 1 := ⟨fuel - 1, by omega⟩
    simp only [parseTop]
    rw [parseSeq_complete d1 _ (Nat.lt_succ_self _)]
    rfl
  | colon d1 d2 _ ih =>
    intro fuel hf; obtain ⟨f, rfl⟩ : ∃ g, fuel = g + 1 := ⟨fuel - 1, by omega⟩
    have l1 := d1.rest_lt; have l2 := d2.rest_lt
    simp only [List.length_cons] at l1
    simp only [parseTop]
    rw [parseSeq_complete d1 _ (Nat.lt_succ_self _)]
    simp only [bind, Except.bind, ite_true]
    rw [parseSeq_complete d2 _ (Nat.lt_succ_self _)]
    simp only [ite_true]
    exact ih f (by omega)
  | var d1 _ ih =>
    intro fuel hf; obtain ⟨f, rfl⟩ : ∃ g, fuel = g + 1 := ⟨fuel - 1, by omega⟩
    have l1 := d1.rest_lt
    simp only [List.length_cons] at l1
    simp only [parseTop]
    rw [parseSeq_complete d1 _ (Nat.lt_succ_self _)]
    simp only [bind, Except.bind, show (kVARIABLE = kCOLON) = False by decide, ite_false,
      ite_true]
    exact ih f (by omega)
  | const d1 hdl _ ih =>
    intro fuel hf; obtain ⟨f, rfl⟩ : ∃ g, fuel = g + 1 := ⟨fuel - 1, by omega⟩
    have l1 := d1.rest_lt
    simp only [List.length_cons] at l1
    simp only [parseTop]
    rw [parseSeq_complete d1 _ (Nat.lt_succ_self _)]
    simp only [bind, Except.bind, show (kCONSTANT = kCOLON) = False by decide,
      show (kCONSTANT = kVARIABLE) = False by decide, ite_false, ite_true, hdl]
    exact ih f (by omega)
  | create d1 _ ih =>
    intro fuel hf; obtain ⟨f, rfl⟩ : ∃ g, fuel = g + 1 := ⟨fuel - 1, by omega⟩
    have l1 := d1.rest_lt
    simp only [List.length_cons] at l1
    simp only [parseTop]
    rw [parseSeq_complete d1 _ (Nat.lt_succ_self _)]
    simp only [bind, Except.bind, show (kCREATE = kCOLON) = False by decide,
      show (kCREATE = kVARIABLE) = False by decide, show (kCREATE = kCONSTANT) = False by decide,
      ite_false, ite_true]
    exact ih f (by omega)
  | allot d1 hdl _ ih =>
    intro fuel hf; obtain ⟨f, rfl⟩ : ∃ g, fuel = g + 1 := ⟨fuel - 1, by omega⟩
    have l1 := d1.rest_lt
    simp only [parseTop]
    rw [parseSeq_complete d1 _ (Nat.lt_succ_self _)]
    simp only [bind, Except.bind, show (kALLOT = kCOLON) = False by decide,
      show (kALLOT = kVARIABLE) = False by decide, show (kALLOT = kCONSTANT) = False by decide,
      show (kALLOT = kCREATE) = False by decide, ite_false, ite_true, hdl]
    exact ih f (by omega)
  | comma d1 hdl _ ih =>
    intro fuel hf; obtain ⟨f, rfl⟩ : ∃ g, fuel = g + 1 := ⟨fuel - 1, by omega⟩
    have l1 := d1.rest_lt
    simp only [parseTop]
    rw [parseSeq_complete d1 _ (Nat.lt_succ_self _)]
    simp only [bind, Except.bind, show (kCOMMA = kCOLON) = False by decide,
      show (kCOMMA = kVARIABLE) = False by decide, show (kCOMMA = kCONSTANT) = False by decide,
      show (kCOMMA = kCREATE) = False by decide, show (kCOMMA = kALLOT) = False by decide,
      ite_false, ite_true, hdl]
    exact ih f (by omega)

/-- **`parseTop` implements the grammar** for every fuel larger than the input. -/
theorem parseTop_iff {fuel : Nat} {dict : Dict} {defs : List Block} {vars : Nat} {main : Block}
    {toks : List Tok} {P : Program} (hf : toks.length < fuel) :
    parseTop fuel dict defs vars main toks = .ok P ↔ Top dict defs vars main toks P :=
  ⟨parseTop_sound fuel dict defs vars main toks P, fun h => parseTop_complete h fuel hf⟩

open ParseProps in
/-- **The token-level parser implements the program grammar.** -/
theorem parseTokens_iff {toks : List Tok} {P : Program} : parseTokens toks = .ok P ↔ Prog toks P := by
  unfold parseTokens
  constructor
  · intro h
    obtain ⟨P', h1, h2⟩ := bind_ok h
    split at h2
    · cases h2; exact ⟨parseTop_sound _ _ _ _ _ _ _ h1, ‹_›⟩
    · cases h2
  · rintro ⟨ht, hl⟩
    rw [parseTop_complete ht _ (Nat.lt_succ_self _)]
    simp [bind, Except.bind, hl]

/-- **`parse` implements the grammar**: `parse src = .ok P` exactly when the tokens of `src`
derive `P`. -/
theorem parse_iff {src : String} {P : Program} :
    parse src = .ok P ↔ ∃ toks, tokenize src = .ok toks ∧ Prog toks P := by
  unfold parse
  cases tokenize src with
  | error e => simp [bind, Except.bind]
  | ok toks => simp only [bind, Except.bind]; rw [parseTokens_iff]; simp

/-- The program grammar is unambiguous. -/
theorem Prog.unique {toks : List Tok} {P P' : Program} (h : Prog toks P) (h' : Prog toks P') :
    P = P' := by
  have e := (parseTokens_iff.mpr h).symm.trans (parseTokens_iff.mpr h')
  simpa using e

/-! ## `parse` never runs out of fuel -/

theorem bind_error {α β : Type} {x : Except String α} {k : α → Except String β} {e : String}
    (h : x >>= k = .error e) : x = .error e ∨ ∃ a, x = .ok a ∧ k a = .error e := by
  cases x with
  | error e' => left; simpa [bind, Except.bind] using h
  | ok a => exact .inr ⟨a, rfl, h⟩

macro "not_fuel_msg" c:term : tactic => `(tactic| first
  | exact not_fuelMsg_of_head (c := $c) (by decide) (by decide)
  | exact not_fuelMsg_of_head (c := $c) (head_append (by decide)) (by decide)
  | exact not_fuelMsg_of_head (c := $c) (head_append (head_append (by decide))) (by decide))

theorem parseTop_not_fuel :
    ∀ (fuel : Nat) (dict : Dict) (defs : List Block) (vars : Nat) (main : Block) (toks : List Tok)
      (e : String), toks.length < fuel → parseTop fuel dict defs vars main toks = .error e →
        ¬FuelMsg e
  | 0, _, _, _, _, _, _, hf, _ => by simp at hf
  | fuel + 1, dict, defs, vars, main, toks, e, hf, h => by
    simp only [parseTop] at h
    rcases bind_error h with h1 | ⟨⟨b, stop, rest⟩, h1, h2⟩
    · have := parseSeq_not_fuel _ _ _ h1
      rintro (he | he)
      · exact this.2 (Nat.lt_succ_self _) he
      · exact this.1 he
    have d1 := parseSeq_sound _ _ _ _ _ h1
    simp only at h2
    split at h2
    · cases h2
    · rename_i u
      have l1 := d1.rest_lt
      split at h2
      · split at h2
        · cases h2; not_fuel_msg 'm'
        · rename_i name body
          rcases bind_error h2 with h3 | ⟨⟨bb, s2, r2⟩, h3, h4⟩
          · have := parseSeq_not_fuel _ _ _ h3
            rintro (he | he)
            · exact this.2 (Nat.lt_succ_self _) he
            · exact this.1 he
          have l2 := (parseSeq_sound _ _ _ _ _ h3).rest_le
          simp only at h4
          simp only [List.length_cons] at l1
          split at h4
          · exact parseTop_not_fuel fuel _ _ _ _ _ _ (by omega) h4
          · split at h4
            · cases h4; not_fuel_msg 'n'
            · split at h4
              · cases h4; not_fuel_msg 'V'
              · cases h4; not_fuel_msg 'd'
      · split at h2
        · split at h2
          · cases h2; not_fuel_msg 'm'
          · simp only [List.length_cons] at l1
            exact parseTop_not_fuel fuel _ _ _ _ _ _ (by omega) h2
        · split at h2
          · split at h2
            · cases h2; not_fuel_msg 'C'
            · cases h2; not_fuel_msg 'm'
            · simp only [List.length_cons] at l1
              exact parseTop_not_fuel fuel _ _ _ _ _ _ (by omega) h2
          · split at h2
            · split at h2
              · cases h2; not_fuel_msg 'm'
              · simp only [List.length_cons] at l1
                exact parseTop_not_fuel fuel _ _ _ _ _ _ (by omega) h2
            · split at h2
              · split at h2
                · cases h2; not_fuel_msg 'A'
                · exact parseTop_not_fuel fuel _ _ _ _ _ _ (by omega) h2
              · split at h2
                · split at h2
                  · cases h2; not_fuel_msg ','
                  · exact parseTop_not_fuel fuel _ _ _ _ _ _ (by omega) h2
                · cases h2; not_fuel_msg 'u'

theorem stripParens_error : ∀ (inside : Bool) (ts : List Tok) (e : String),
    stripParens inside ts = .error e → e = "unterminated ( comment"
  | false, [], _, h => by cases h
  | true, [], _, h => by simp only [stripParens, Except.error.injEq] at h; exact h.symm
  | false, t :: ts, e, h => by
    simp only [stripParens] at h
    split at h
    · exact stripParens_error true ts e h
    · cases hs : stripParens false ts with
      | error e' =>
        rw [hs] at h
        simp only [Functor.map, Except.map, Except.error.injEq] at h
        subst h; exact stripParens_error false ts _ hs
      | ok v => rw [hs] at h; cases h
  | true, t :: ts, e, h => by
    simp only [stripParens] at h
    split at h
    · exact stripParens_error false ts e h
    · exact stripParens_error true ts e h

/-- **`parse` never fails for lack of fuel**: neither `input too deeply nested` nor
`input too long` is ever its result. -/
theorem parse_ne_fuel (src : String) :
    parse src ≠ .error msgDeep ∧ parse src ≠ .error msgLong := by
  have key : ∀ e, parse src = .error e → ¬FuelMsg e := by
    intro e h
    unfold parse at h
    rcases bind_error h with h1 | ⟨toks, _, h2⟩
    · rw [stripParens_error _ _ _ h1]; not_fuel_msg 'u'
    unfold parseTokens at h2
    rcases bind_error h2 with h3 | ⟨P, _, h4⟩
    · exact parseTop_not_fuel _ _ _ _ _ _ _ (Nat.lt_succ_self _) h3
    split at h4
    · cases h4
    · cases h4; not_fuel_msg 'L'
  exact ⟨fun h => key _ h (.inl rfl), fun h => key _ h (.inr rfl)⟩

end Grammar
end Forth
end WordDialect
