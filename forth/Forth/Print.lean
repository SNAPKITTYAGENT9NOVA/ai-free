import Forth.Parse

/-!
# Forth.Print

A printer from `Program` back to Forth source, and the round trip

    parse_print : P.WF → parse (print P) = .ok P

for every well-formed program (`Program.WF`: every call targets a word defined at that point,
counting the word being defined, `EXIT` occurs only inside definitions, and `LEAVE` only inside
loops). Any `Int` literal
is printable, so literals need no condition.

Printed form: `VARIABLE V` once per variable cell (all named `V`: a variable is referenced by
its address, a literal, so the names are never used), then each definition `k` as
`: Wk … ;`, then the main block. Word names are `W` followed by the decimal index. Control
structures print as `IF … ELSE … THEN` (with a possibly empty `ELSE` part), `BEGIN … UNTIL`,
`BEGIN … WHILE … REPEAT`,
`DO … LOOP`, `DO … +LOOP`, `LEAVE` and `EXIT`; `CONSTANT`, `RECURSE` and `?DO` are never printed
(a `?DO` loop prints as the `IF` it parses to) (a constant is a literal, `RECURSE` a
call by name). Tokens are separated by one space.

The proof has two halves: `tokenize_join` (the lexer splits the printed text back into the
printed tokens) and `parseTokens_print` (the token-level parser inverts `printTokens`).
-/

namespace WordDialect
namespace Forth

/-- Well-formed blocks: calls target words `< k`; `EXIT` only when `inDef`. -/
def Block.WF (k : Nat) (inDef : Bool) : Block → Prop
  | .nil => True
  | .op _ r => r.WF k inDef
  | .ite t e r => t.WF k inDef ∧ e.WF k inDef ∧ r.WF k inDef
  | .untilL b r => b.WF k inDef ∧ r.WF k inDef
  | .call i r => i < k ∧ r.WF k inDef
  | .exit r => inDef = true ∧ r.WF k inDef
  | .doLoop b r => b.WF k inDef ∧ r.WF k inDef
  | .plusLoop b r => b.WF k inDef ∧ r.WF k inDef
  | .leave r => r.WF k inDef
  | .whileL c b r => c.WF k inDef ∧ b.WF k inDef ∧ r.WF k inDef

/-- Well-formed programs: word `i` may call words `0 … i` (itself included); the main block
may call every word; only definitions contain `EXIT`; every `LEAVE` is inside a loop. This is the
shape `parse` produces. -/
def Program.WF (P : Program) : Prop :=
  (∀ i (body : Block), P.defs[i]? = some body → body.WF (i + 1) true) ∧
    P.main.WF P.defs.length false ∧ P.leaveOK = true

namespace Print

open Parse

def digitList : List Char := ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']

def digitChar (k : Nat) : Char := digitList.getD k '0'

/-- Decimal digits of `k` in front of `acc` (fuel `f > k` suffices). -/
def natToksAux : Nat → Nat → Tok → Tok
  | 0, _, acc => acc
  | f + 1, k, acc =>
    if k < 10 then digitChar k :: acc else natToksAux f (k / 10) (digitChar (k % 10) :: acc)

def natToks (k : Nat) : Tok := natToksAux (k + 1) k []

def intToks : Int → Tok
  | .ofNat k => natToks k
  | .negSucc k => '-' :: natToks (k + 1)

def wordName (i : Nat) : Tok := 'W' :: natToks i

def varName : Tok := ['V']

def opTok : Op → Tok
  | .lit z => intToks z
  | .dup => ['D', 'U', 'P'] | .drop => ['D', 'R', 'O', 'P'] | .swap => ['S', 'W', 'A', 'P']
  | .over => ['O', 'V', 'E', 'R'] | .rot => ['R', 'O', 'T']
  | .add => ['+'] | .sub => ['-'] | .mul => ['*'] | .div => ['/'] | .mod => ['M', 'O', 'D']
  | .and => ['A', 'N', 'D'] | .or => ['O', 'R'] | .xor => ['X', 'O', 'R']
  | .invert => ['I', 'N', 'V', 'E', 'R', 'T']
  | .lshift => ['L', 'S', 'H', 'I', 'F', 'T'] | .rshift => ['R', 'S', 'H', 'I', 'F', 'T']
  | .eq => ['='] | .ne => ['<', '>'] | .lt => ['<'] | .gt => ['>']
  | .ult => ['U', '<'] | .ugt => ['U', '>'] | .zeq => ['0', '=']
  | .fetch => ['@'] | .store => ['!']
  | .tor => ['>', 'R'] | .fromr => ['R', '>'] | .rfetch => ['R', '@']
  | .loopI => ['I'] | .loopJ => ['J'] | .unloop => ['U', 'N', 'L', 'O', 'O', 'P']

def printBlock : Block → List Tok
  | .nil => []
  | .op o r => opTok o :: printBlock r
  | .ite t e r => kIF :: (printBlock t ++ kELSE :: (printBlock e ++ kTHEN :: printBlock r))
  | .untilL b r => kBEGIN :: (printBlock b ++ kUNTIL :: printBlock r)
  | .call i r => wordName i :: printBlock r
  | .exit r => kEXIT :: printBlock r
  | .doLoop b r => kDO :: (printBlock b ++ kLOOP :: printBlock r)
  | .plusLoop b r => kDO :: (printBlock b ++ kPLOOP :: printBlock r)
  | .leave r => kLEAVE :: printBlock r
  | .whileL c b r => kBEGIN :: (printBlock c ++ kWHILE :: (printBlock b ++ kREPEAT :: printBlock r))

def varToks : Nat → List Tok
  | 0 => []
  | v + 1 => kVARIABLE :: varName :: varToks v

/-- Definitions numbered from `k`. -/
def defsToks : Nat → List Block → List Tok
  | _, [] => []
  | k, b :: bs => kCOLON :: wordName k :: (printBlock b ++ kSEMI :: defsToks (k + 1) bs)

def printTokens (P : Program) : List Tok :=
  varToks P.vars ++ (defsToks 0 P.defs ++ printBlock P.main)

/-- Each token followed by one space. -/
def joinToks : List Tok → List Char
  | [] => []
  | t :: ts => t ++ ' ' :: joinToks ts

end Print

/-- Print a program as Forth source. -/
def print (P : Program) : String := String.ofList (Print.joinToks (Print.printTokens P))

namespace Print

open Parse

/-! ## Decimal numerals -/

theorem digitChar_spec : ∀ k, k < 10 →
    (digitChar k).isDigit = true ∧ (digitChar k).toNat - 48 = k ∧
      digitChar k ∈ digitList := by
  decide

theorem natToksAux_read : ∀ f k acc a, k < f →
    ∃ a', digitsAux a (natToksAux f k acc) = digitsAux a' acc ∧ (a = 0 → a' = k) := by
  intro f
  induction f with
  | zero => intro k acc a h; omega
  | succ f ih =>
    intro k acc a hk
    by_cases h10 : k < 10
    · obtain ⟨h1, h2, _⟩ := digitChar_spec k h10
      refine ⟨10 * a + k, ?_, fun ha => by omega⟩
      simp [natToksAux, h10, digitsAux, h1, h2]
    · obtain ⟨h1, h2, _⟩ := digitChar_spec (k % 10) (Nat.mod_lt _ (by omega))
      obtain ⟨a'', he, ha''⟩ := ih (k / 10) (digitChar (k % 10) :: acc) a (by omega)
      refine ⟨10 * a'' + k % 10, ?_, fun ha => ?_⟩
      · simp only [natToksAux, h10, ite_false]
        rw [he]; simp [digitsAux, h1, h2]
      · have := ha'' ha; omega

theorem natToksAux_mem : ∀ f k acc c, c ∈ natToksAux f k acc → c ∈ digitList ∨ c ∈ acc := by
  intro f
  induction f with
  | zero => intro k acc c h; exact .inr h
  | succ f ih =>
    intro k acc c h
    by_cases h10 : k < 10
    · simp only [natToksAux, h10, ite_true, List.mem_cons] at h
      rcases h with h | h
      · exact .inl (h ▸ (digitChar_spec k h10).2.2)
      · exact .inr h
    · simp only [natToksAux, h10, ite_false] at h
      rcases ih _ _ _ h with h | h
      · exact .inl h
      · simp only [List.mem_cons] at h
        rcases h with h | h
        · exact .inl (h ▸ (digitChar_spec (k % 10) (Nat.mod_lt _ (by omega))).2.2)
        · exact .inr h

theorem natToksAux_ne_nil : ∀ f k acc, natToksAux (f + 1) k acc ≠ [] := by
  intro f
  induction f with
  | zero => intro k acc; simp only [natToksAux]; split <;> simp
  | succ f ih =>
    intro k acc; simp only [natToksAux]; split
    · simp
    · exact ih _ _

theorem natToks_mem {k : Nat} {c : Char} (h : c ∈ natToks k) : c ∈ digitList := by
  rcases natToksAux_mem _ _ _ _ h with h | h
  · exact h
  · simp at h

theorem natToks_cons (k : Nat) : ∃ c cs, natToks k = c :: cs ∧ c ∈ digitList := by
  cases h : natToks k with
  | nil => exact absurd h (natToksAux_ne_nil k k [])
  | cons c cs => exact ⟨c, cs, rfl, natToks_mem (by rw [h]; simp)⟩

theorem digits_natToks (k : Nat) : digits (natToks k) = some k := by
  obtain ⟨c, cs, hc, _⟩ := natToks_cons k
  obtain ⟨a', he, ha⟩ := natToksAux_read (k + 1) k [] 0 (by omega)
  have : digits (natToks k) = digitsAux 0 (natToks k) := by rw [hc]; rfl
  rw [this]; unfold natToks; rw [he, ha rfl]; rfl

theorem number_cons_ne {c : Char} {cs : List Char} (hc : c ≠ '-') :
    number (c :: cs) = (digits (c :: cs)).map Int.ofNat := by
  unfold number; split
  · rename_i ds h; simp at h; exact absurd h.1 hc
  · rfl

theorem minus_not_digit : '-' ∉ digitList := by decide

theorem number_natToks (k : Nat) : number (natToks k) = some (k : Int) := by
  obtain ⟨c, cs, hc, hd⟩ := natToks_cons k
  have hne : c ≠ '-' := fun h => minus_not_digit (h ▸ hd)
  rw [hc, number_cons_ne hne, ← hc, digits_natToks]; rfl

theorem number_intToks (z : Int) : number (intToks z) = some z := by
  cases z with
  | ofNat k => exact number_natToks k
  | negSucc k =>
    show (digits (natToks (k + 1))).map (fun k => -(k : Int)) = some (Int.negSucc k)
    rw [digits_natToks]; show some _ = some _; congr 1

/-! ## Token facts -/

def keywords : List Tok := [kIF, kBEGIN, kRECURSE, kEXIT, kDO, kQDO, kLEAVE] ++ stops

theorem not_keyword {t : Tok} (h : ∀ kw ∈ keywords, kw ≠ t) :
    t ∉ stops ∧ t ≠ kIF ∧ t ≠ kBEGIN ∧ t ≠ kRECURSE ∧ t ≠ kEXIT ∧ t ≠ kDO ∧ t ≠ kQDO ∧
      t ≠ kLEAVE := by
  refine ⟨fun hm => h t (by simp [keywords, hm]) rfl, fun e => h kIF (by simp [keywords]) e.symm,
    fun e => h kBEGIN (by simp [keywords]) e.symm, fun e => h kRECURSE (by simp [keywords]) e.symm,
    fun e => h kEXIT (by simp [keywords]) e.symm, fun e => h kDO (by simp [keywords]) e.symm,
    fun e => h kQDO (by simp [keywords]) e.symm, fun e => h kLEAVE (by simp [keywords]) e.symm⟩

theorem upper_of {t : Tok} (h : ∀ c ∈ t, c.toUpper = c) : upper t = t := by
  unfold upper
  induction t with
  | nil => rfl
  | cons c cs ih =>
    simp only [List.map_cons, h c (by simp)]
    rw [ih (fun c' hc' => h c' (by simp [hc']))]

def numChars : List Char := '-' :: digitList

theorem numChars_facts : ∀ c ∈ numChars,
    c.toUpper = c ∧ c ≠ 'W' ∧ c ≠ 'V' ∧ isWs c = false ∧ c ≠ '\\' ∧ c ≠ '(' := by
  decide

theorem intToks_mem {z : Int} {c : Char} (h : c ∈ intToks z) : c ∈ numChars := by
  cases z with
  | ofNat k => exact List.mem_cons_of_mem _ (natToks_mem h)
  | negSucc k =>
    simp only [intToks, List.mem_cons] at h
    rcases h with h | h
    · subst h; simp [numChars]
    · exact List.mem_cons_of_mem _ (natToks_mem h)

theorem intToks_ne_nil (z : Int) : intToks z ≠ [] := by
  cases z with
  | ofNat k => obtain ⟨c, cs, h, _⟩ := natToks_cons k; simp [intToks, h]
  | negSucc k => simp [intToks]

theorem wordName_inj {i j : Nat} (h : wordName i = wordName j) : i = j := by
  simp only [wordName, List.cons.injEq, true_and] at h
  have := digits_natToks i
  rw [h, digits_natToks] at this
  exact (Option.some.inj this).symm

/-! ## Dictionary lookups -/

/-- Every dictionary key is a printed name. -/
def DictOK (dict : Dict) : Prop := ∀ p ∈ dict, p.1 = varName ∨ ∃ j, p.1 = wordName j

theorem lookup_cons_ne {β : Type} {a k : Tok} {v : β} {l : List (Tok × β)} (h : a ≠ k) :
    ((k, v) :: l).lookup a = l.lookup a := by
  simp only [List.lookup]; rw [beq_false_of_ne h]

theorem lookup_cons_self {β : Type} {a : Tok} {v : β} {l : List (Tok × β)} :
    ((a, v) :: l).lookup a = some v := by
  simp [List.lookup]

theorem lookup_some_mem {β : Type} {a : Tok} {v : β} :
    ∀ {l : List (Tok × β)}, l.lookup a = some v → ∃ k, (k, v) ∈ l ∧ k = a
  | [], h => by simp [List.lookup] at h
  | (k, w) :: l, h => by
    by_cases hk : a = k
    · subst hk; rw [lookup_cons_self] at h; cases h; exact ⟨a, by simp, rfl⟩
    · rw [lookup_cons_ne hk] at h
      obtain ⟨k', hm, he⟩ := lookup_some_mem h
      exact ⟨k', List.mem_cons_of_mem _ hm, he⟩

theorem lookup_none {dict : Dict} {t : Tok} (hd : DictOK dict) (hv : t ≠ varName)
    (hw : ∀ j, t ≠ wordName j) : dict.lookup t = none := by
  cases h : dict.lookup t with
  | none => rfl
  | some w =>
    obtain ⟨k, hm, rfl⟩ := lookup_some_mem h
    rcases hd _ hm with e | ⟨j, e⟩
    · exact absurd e hv
    · exact absurd e (hw j)

theorem head_ne_names {t : Tok} {c : Char} {cs : List Char} (ht : t = c :: cs) (hW : c ≠ 'W')
    (hV : c ≠ 'V') : t ≠ varName ∧ ∀ j, t ≠ wordName j := by
  subst ht
  exact ⟨fun e => hV (by simp [varName] at e; exact e.1),
    fun j e => hW (by simp [wordName] at e; exact e.1)⟩

theorem opTable_no_number : ∀ p ∈ opTable, number p.1 = none := by decide

theorem keyword_no_number : ∀ kw ∈ keywords, number kw = none := by decide

/-- No keyword is spelled like a word name, `W` followed by a digit (`WHILE` starts with `W`). -/
theorem keyword_not_word : ∀ kw ∈ keywords, ∀ c ∈ digitList, kw.take 2 ≠ ['W', c] := by decide

/-! ## Classification of printed tokens -/

theorem classify_lookup {dict : Dict} {self : Option Nat} {t : Tok} (hu : upper t = t)
    (hk : ∀ kw ∈ keywords, kw ≠ t) : classify dict self t = lookupWord dict t t := by
  obtain ⟨h1, h2, h3, h4, h5, h6, h7, h8⟩ := not_keyword hk
  simp only [classify, hu, h1, h2, h3, h4, h5, h6, h7, h8, ↓reduceIte]

theorem lookupWord_names {dict dict' : Dict} {t : Tok} (hd : DictOK dict) (hd' : DictOK dict')
    (hv : t ≠ varName) (hw : ∀ j, t ≠ wordName j) : lookupWord dict t t = lookupWord dict' t t := by
  simp only [lookupWord, lookup_none hd hv hw, lookup_none hd' hv hw]

theorem dictOK_nil : DictOK [] := by intro p h; simp at h

theorem classify_op {dict : Dict} {self : Option Nat} (hd : DictOK dict) (o : Op) :
    classify dict self (opTok o) = .prim (.op o) := by
  cases o
  case lit z =>
    have hmem := fun c (h : c ∈ intToks z) => numChars_facts c (intToks_mem h)
    have hnum := number_intToks z
    have hk : ∀ kw ∈ keywords, kw ≠ intToks z := by
      intro kw hkw e; have := keyword_no_number kw hkw; rw [e, hnum] at this; cases this
    show classify dict self (intToks z) = _
    rw [classify_lookup (upper_of fun c h => (hmem c h).1) hk]
    obtain ⟨c, cs, hc⟩ : ∃ c cs, intToks z = c :: cs := by
      cases h : intToks z with
      | nil => exact absurd h (intToks_ne_nil z)
      | cons c cs => exact ⟨c, cs, rfl⟩
    have hcm := hmem c (by rw [hc]; simp)
    obtain ⟨hv, hw⟩ := head_ne_names hc hcm.2.1 hcm.2.2.1
    have hop : opTable.lookup (intToks z) = none := by
      cases h : opTable.lookup (intToks z) with
      | none => rfl
      | some o =>
        obtain ⟨k, hm, rfl⟩ := lookup_some_mem h
        have := opTable_no_number _ hm; simp only at this; rw [hnum] at this; cases this
    simp only [lookupWord, lookup_none hd hv hw, hop, hnum]
  all_goals
    rw [classify_lookup (by decide) (by decide),
      lookupWord_names hd dictOK_nil (by decide) (fun j e => by simp [wordName, opTok] at e)]
    rfl

theorem upper_wordName (i : Nat) : upper (wordName i) = wordName i := by
  apply upper_of
  intro c h
  simp only [wordName, List.mem_cons] at h
  rcases h with h | h
  · subst h; decide
  · exact (numChars_facts c (List.mem_cons_of_mem _ (natToks_mem h))).1

theorem classify_word {dict : Dict} {self : Option Nat} {i : Nat}
    (hl : dict.lookup (wordName i) = some (Block.call i)) :
    classify dict self (wordName i) = .prim (.call i) := by
  have hk : ∀ kw ∈ keywords, kw ≠ wordName i := by
    intro kw hkw e
    obtain ⟨c, cs, hcs, hc⟩ := natToks_cons i
    have := keyword_not_word kw hkw c hc
    rw [e] at this; simp [wordName, hcs] at this
  rw [classify_lookup (upper_wordName i) hk]
  simp only [lookupWord, hl]

theorem classify_stop {dict : Dict} {self : Option Nat} {u : Tok} (hu : u ∈ stops) :
    classify dict self u = .stop u := by
  simp only [stops, List.mem_cons, List.mem_nil_iff, or_false] at hu
  rcases hu with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> rfl

theorem classify_if {dict : Dict} {self : Option Nat} : classify dict self kIF = .ifK := rfl

theorem classify_begin {dict : Dict} {self : Option Nat} : classify dict self kBEGIN = .beginK :=
  rfl

theorem classify_do {dict : Dict} {self : Option Nat} : classify dict self kDO = .doK false := rfl

theorem classify_leave {dict : Dict} {self : Option Nat} :
    classify dict self kLEAVE = .prim .leave := rfl

theorem classify_exit {dict : Dict} {j : Nat} : classify dict (some j) kEXIT = .prim .exit := rfl

/-! ## Blocks: `parseSeq` inverts `printBlock` -/

theorem parseSeq_stop {dict : Dict} {self : Option Nat} {u : Tok} (hu : u ∈ stops)
    (rest : List Tok) (f : Nat) :
    parseSeq (f + 1) dict self (u :: rest) = .ok (.nil, some u, rest) := by
  simp only [parseSeq, classify_stop hu]

theorem parseSeq_print {dict : Dict} {self : Option Nat} {k : Nat} {inDef : Bool}
    (hd : DictOK dict) (hcalls : ∀ i, i < k → dict.lookup (wordName i) = some (Block.call i))
    (hself : inDef = true → ∃ j, self = some j) :
    ∀ (b : Block), b.WF k inDef → ∀ (tail : List Tok) (stop : Option Tok) (rest : List Tok),
      (∀ f, parseSeq (f + 1) dict self tail = .ok (.nil, stop, rest)) →
      ∀ fuel, (printBlock b).length < fuel →
        parseSeq fuel dict self (printBlock b ++ tail) = .ok (b, stop, rest) := by
  intro b
  induction b with
  | nil =>
    intro _ tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    exact ht f
  | op o r ih =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hf' : (printBlock r).length < f := by simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, parseSeq, classify_op hd]
    rw [ih hwf tail stop rest ht f hf']
    rfl
  | call i r ih =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hf' : (printBlock r).length < f := by simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, parseSeq, classify_word (hcalls i hwf.1)]
    rw [ih hwf.2 tail stop rest ht f hf']
    rfl
  | exit r ih =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hf' : (printBlock r).length < f := by simp [printBlock] at hf; omega
    obtain ⟨j, rfl⟩ := hself hwf.1
    simp only [printBlock, List.cons_append, parseSeq, classify_exit]
    rw [ih hwf.2 tail stop rest ht f hf']
    rfl
  | ite t e r iht ihe ihr =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hlen : (printBlock t).length < f ∧ (printBlock e).length < f ∧
        (printBlock r).length < f := by simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, List.append_assoc, parseSeq, classify_if]
    rw [iht hwf.1 (kELSE :: (printBlock e ++ kTHEN :: (printBlock r ++ tail))) (some kELSE)
        (printBlock e ++ kTHEN :: (printBlock r ++ tail)) (parseSeq_stop (by decide) _) f hlen.1]
    simp only [bind, Except.bind, ite_true]
    rw [ihe hwf.2.1 (kTHEN :: (printBlock r ++ tail)) (some kTHEN) (printBlock r ++ tail)
        (parseSeq_stop (by decide) _) f hlen.2.1]
    simp only [ite_true]
    rw [ihr hwf.2.2 tail stop rest ht f hlen.2.2]
  | untilL x r ihx ihr =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hlen : (printBlock x).length < f ∧ (printBlock r).length < f := by
      simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, List.append_assoc, parseSeq, classify_begin]
    rw [ihx hwf.1 (kUNTIL :: (printBlock r ++ tail)) (some kUNTIL) (printBlock r ++ tail)
        (parseSeq_stop (by decide) _) f hlen.1]
    simp only [bind, Except.bind, ite_true]
    rw [ihr hwf.2 tail stop rest ht f hlen.2]
  | whileL c x r ihc ihx ihr =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hlen : (printBlock c).length < f ∧ (printBlock x).length < f ∧
        (printBlock r).length < f := by simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, List.append_assoc, parseSeq, classify_begin]
    rw [ihc hwf.1 (kWHILE :: (printBlock x ++ kREPEAT :: (printBlock r ++ tail))) (some kWHILE)
        (printBlock x ++ kREPEAT :: (printBlock r ++ tail)) (parseSeq_stop (by decide) _) f hlen.1]
    simp only [bind, Except.bind, ite_true, show (some kWHILE = some kUNTIL) = False by decide,
      ite_false]
    rw [ihx hwf.2.1 (kREPEAT :: (printBlock r ++ tail)) (some kREPEAT) (printBlock r ++ tail)
        (parseSeq_stop (by decide) _) f hlen.2.1]
    simp only [ite_true]
    rw [ihr hwf.2.2 tail stop rest ht f hlen.2.2]
  | doLoop x r ihx ihr =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hlen : (printBlock x).length < f ∧ (printBlock r).length < f := by
      simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, List.append_assoc, parseSeq, classify_do]
    rw [ihx hwf.1 (kLOOP :: (printBlock r ++ tail)) (some kLOOP) (printBlock r ++ tail)
        (parseSeq_stop (by decide) _) f hlen.1]
    simp only [bind, Except.bind, ite_true]
    rw [ihr hwf.2 tail stop rest ht f hlen.2]
    rfl
  | plusLoop x r ihx ihr =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hlen : (printBlock x).length < f ∧ (printBlock r).length < f := by
      simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, List.append_assoc, parseSeq, classify_do]
    rw [ihx hwf.1 (kPLOOP :: (printBlock r ++ tail)) (some kPLOOP) (printBlock r ++ tail)
        (parseSeq_stop (by decide) _) f hlen.1]
    simp only [bind, Except.bind, ite_true, show (some kPLOOP = some kLOOP) = False by decide,
      ite_false]
    rw [ihr hwf.2 tail stop rest ht f hlen.2]
    rfl
  | leave r ih =>
    intro hwf tail stop rest ht fuel hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp [printBlock] at hf; omega⟩
    have hf' : (printBlock r).length < f := by simp [printBlock] at hf; omega
    simp only [printBlock, List.cons_append, parseSeq, classify_leave]
    rw [ih hwf tail stop rest ht f hf']
    rfl

/-! ## Programs: `parseTop` inverts `printTokens` -/

theorem parseSeq_nil {dict : Dict} {self : Option Nat} (f : Nat) :
    parseSeq (f + 1) dict self [] = .ok (.nil, none, []) := rfl

theorem parseTop_main {dict : Dict} {defs : List Block} {vars : Nat} {main : Block}
    (hd : DictOK dict)
    (hcalls : ∀ i, i < defs.length → dict.lookup (wordName i) = some (Block.call i))
    (hwf : main.WF defs.length false) (f : Nat) :
    parseTop (f + 1) dict defs vars .nil (printBlock main) = .ok ⟨defs, main, vars⟩ := by
  have h := parseSeq_print hd hcalls (self := none) (fun h => by cases h) main hwf [] none []
    parseSeq_nil ((printBlock main).length + 1) (by omega)
  rw [List.append_nil] at h
  simp only [parseTop, h]
  rfl

theorem dictOK_cons_word {dict : Dict} (hd : DictOK dict) (k : Nat) (w : Block → Block) :
    DictOK ((wordName k, w) :: dict) := by
  intro p hp
  simp only [List.mem_cons] at hp
  rcases hp with rfl | hp
  · exact .inr ⟨k, rfl⟩
  · exact hd p hp

theorem dictOK_cons_var {dict : Dict} (hd : DictOK dict) (w : Block → Block) :
    DictOK ((varName, w) :: dict) := by
  intro p hp
  simp only [List.mem_cons] at hp
  rcases hp with rfl | hp
  · exact .inl rfl
  · exact hd p hp

theorem parseTop_defs {vars : Nat} {main : Block} :
    ∀ (bs : List Block) (dict : Dict) (defs : List Block) (fuel : Nat), DictOK dict →
      (∀ i, i < defs.length → dict.lookup (wordName i) = some (Block.call i)) →
      (∀ j (b : Block), bs[j]? = some b → b.WF (defs.length + j + 1) true) →
      main.WF (defs.length + bs.length) false → bs.length < fuel →
      parseTop fuel dict defs vars .nil (defsToks defs.length bs ++ printBlock main) =
        .ok ⟨defs ++ bs, main, vars⟩ := by
  intro bs
  induction bs with
  | nil =>
    intro dict defs fuel hd hcalls _ hmain hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    simp only [defsToks, List.nil_append, List.append_nil]
    exact parseTop_main hd hcalls (by simpa using hmain) f
  | cons b bs ih =>
    intro dict defs fuel hd hcalls hbs hmain hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by simp at hf; omega⟩
    have hb : b.WF (defs.length + 1) true := by simpa using hbs 0 b rfl
    let dict' : Dict := (wordName defs.length, Block.call defs.length) :: dict
    have hd' : DictOK dict' := dictOK_cons_word hd _ _
    have hcalls' : ∀ i, i < defs.length + 1 →
        dict'.lookup (wordName i) = some (Block.call i) := by
      intro i hi
      by_cases he : i = defs.length
      · subst he; exact lookup_cons_self
      · rw [lookup_cons_ne (fun e => he (wordName_inj e))]
        exact hcalls i (by omega)
    have hbody := parseSeq_print hd' hcalls' (self := some defs.length) (fun _ => ⟨_, rfl⟩) b hb
      (kSEMI :: (defsToks (defs.length + 1) bs ++ printBlock main)) (some kSEMI)
      (defsToks (defs.length + 1) bs ++ printBlock main) (parseSeq_stop (by decide) _)
    have hrest := ih dict' (defs ++ [b]) f hd'
      (by simpa using hcalls')
      (fun j b' h => by
        have := hbs (j + 1) b' (by simpa using h)
        simpa [Nat.add_assoc, Nat.add_comm 1 j] using this)
      (by simpa [Nat.add_assoc, Nat.add_comm 1 bs.length] using hmain)
      (by simp at hf; omega)
    simp only [List.length_append, List.length_singleton] at hrest
    simp only [defsToks, List.cons_append, List.append_assoc, parseTop, List.length_cons]
    rw [parseSeq_stop (by decide)]
    simp only [bind, Except.bind]
    simp only [↓reduceIte, upper_wordName]
    rw [hbody _ (by simp; omega)]
    simp only [↓reduceIte]
    rw [show Block.nil.append Block.nil = Block.nil from rfl, hrest]
    simp

theorem parseTop_vars {rest : List Tok} :
    ∀ (j v : Nat) (dict : Dict) (fuel : Nat), DictOK dict → j ≤ fuel →
      ∃ dict', DictOK dict' ∧
        parseTop fuel dict [] v .nil (varToks j ++ rest) =
          parseTop (fuel - j) dict' [] (v + j) .nil rest := by
  intro j
  induction j with
  | zero => intro v dict fuel hd _; exact ⟨dict, hd, by simp [varToks]⟩
  | succ j ih =>
    intro v dict fuel hd hf
    obtain ⟨f, rfl⟩ : ∃ f, fuel = f + 1 := ⟨fuel - 1, by omega⟩
    obtain ⟨dict', hd', he⟩ := ih (v + 1) ((varName, Block.op (.lit v)) :: dict) f
      (dictOK_cons_var hd _) (by omega)
    refine ⟨dict', hd', ?_⟩
    simp only [varToks, List.cons_append, parseTop, List.length_cons]
    rw [parseSeq_stop (by decide)]
    simp only [bind, Except.bind]
    simp (config := { decide := true }) only [↓reduceIte]
    rw [show upper varName = varName from rfl, show Block.nil.append Block.nil = Block.nil from rfl,
      he]
    congr 1 <;> omega

theorem varToks_length (v : Nat) : (varToks v).length = 2 * v := by
  induction v with
  | zero => rfl
  | succ v ih => simp [varToks, ih]; omega

theorem defsToks_length : ∀ (bs : List Block) (k : Nat), 2 * bs.length ≤ (defsToks k bs).length
  | [], _ => by simp [defsToks]
  | b :: bs, k => by
    have := defsToks_length bs (k + 1)
    simp [defsToks]; omega

/-- The token-level round trip. -/
theorem parseTokens_print (P : Program) (h : P.WF) : parseTokens (printTokens P) = .ok P := by
  obtain ⟨hdefs, hmain, hleave⟩ := h
  have hlen := varToks_length P.vars
  have hlen2 := defsToks_length P.defs 0
  unfold parseTokens printTokens
  obtain ⟨dict', hd', he⟩ := parseTop_vars (rest := defsToks 0 P.defs ++ printBlock P.main)
    P.vars 0 [] ((varToks P.vars ++ (defsToks 0 P.defs ++ printBlock P.main)).length + 1)
    dictOK_nil (by simp only [List.length_append]; omega)
  rw [he]
  have := parseTop_defs (vars := 0 + P.vars) (main := P.main) P.defs dict' []
    ((varToks P.vars ++ (defsToks 0 P.defs ++ printBlock P.main)).length + 1 - P.vars) hd'
    (fun i hi => by simp at hi) (fun j b hj => by simpa using hdefs j b hj) (by simpa using hmain)
    (by simp only [List.length_append]; omega)
  simp only [List.length_nil] at this
  rw [this]
  cases P
  simp only [Nat.zero_add, List.nil_append, bind, Except.bind] at hleave ⊢
  simp only [hleave, ↓reduceIte]

/-! ## Characters: `tokenize` inverts `joinToks` -/

/-- A token the lexer reads back unchanged: nonempty, no whitespace, not a comment opener. -/
def Plain (t : Tok) : Prop :=
  t ≠ [] ∧ (∀ c ∈ t, isWs c = false) ∧ t ≠ ['\\'] ∧ t ≠ ['(']

theorem lex_word {rest : List Char} :
    ∀ (t cur : List Char), (∀ c ∈ t, isWs c = false) →
      lex (t ++ rest) cur false = lex rest (t.reverse ++ cur) false := by
  intro t
  induction t with
  | nil => intro cur _; rfl
  | cons c cs ih =>
    intro cur h
    simp only [List.cons_append, lex, h c (by simp), Bool.false_eq_true, ite_false]
    rw [ih (c :: cur) (fun c' hc' => h c' (by simp [hc']))]
    simp

theorem lex_join : ∀ (toks : List Tok), (∀ t ∈ toks, Plain t) →
    lex (joinToks toks) [] false = toks
  | [], _ => rfl
  | t :: ts, h => by
    obtain ⟨hne, hws, hbs, _⟩ := h t (by simp)
    simp only [joinToks]
    rw [lex_word t [] hws]
    have hrev : t.reverse ≠ ['\\'] := fun e => hbs (by simpa using congrArg List.reverse e)
    have hrev' : t.reverse ≠ [] := by simpa using hne
    simp only [lex, List.append_nil, show isWs ' ' = true from rfl, ite_true, hrev, ite_false,
      flush, hrev', List.reverse_reverse]
    rw [lex_join ts (fun t' ht' => h t' (by simp [ht']))]

theorem stripParens_plain : ∀ (toks : List Tok), (∀ t ∈ toks, Plain t) →
    stripParens false toks = .ok toks
  | [], _ => rfl
  | t :: ts, h => by
    have hp := (h t (by simp)).2.2.2
    simp only [stripParens, hp, ite_false]
    rw [stripParens_plain ts (fun t' ht' => h t' (by simp [ht']))]
    rfl

theorem tokenize_join (toks : List Tok) (h : ∀ t ∈ toks, Plain t) :
    tokenize (String.ofList (joinToks toks)) = .ok toks := by
  unfold tokenize
  rw [String.toList_ofList, lex_join toks h, stripParens_plain toks h]

theorem plain_of {t : Tok} (hne : t ≠ [])
    (h : ∀ c ∈ t, isWs c = false ∧ c ≠ '\\' ∧ c ≠ '(') : Plain t := by
  refine ⟨hne, fun c hc => (h c hc).1, fun e => ?_, fun e => ?_⟩
  · exact (h '\\' (by simp [e])).2.1 rfl
  · exact (h '(' (by simp [e])).2.2 rfl

/-- `Plain` spelled out, so that `decide` proves it for a concrete token. -/
theorem plain_concrete {t : Tok}
    (h : t ≠ [] ∧ (∀ c ∈ t, isWs c = false) ∧ t ≠ ['\\'] ∧ t ≠ ['(']) : Plain t := h

theorem plain_opTok (o : Op) : Plain (opTok o) := by
  cases o
  case lit z =>
    refine plain_of (intToks_ne_nil z) (fun c hc => ?_)
    have := numChars_facts c (intToks_mem hc)
    exact ⟨this.2.2.2.1, this.2.2.2.2⟩
  all_goals exact plain_concrete (by decide)

theorem plain_wordName (i : Nat) : Plain (wordName i) := by
  refine plain_of (by simp [wordName]) (fun c hc => ?_)
  simp only [wordName, List.mem_cons] at hc
  rcases hc with rfl | hc
  · decide
  · have := numChars_facts c (List.mem_cons_of_mem _ (natToks_mem hc))
    exact ⟨this.2.2.2.1, this.2.2.2.2⟩

theorem plain_printBlock : ∀ (b : Block), ∀ t ∈ printBlock b, Plain t := by
  intro b
  induction b with
  | nil => intro t h; simp [printBlock] at h
  | op o r ih =>
    intro t h; simp only [printBlock, List.mem_cons] at h
    rcases h with rfl | h
    · exact plain_opTok o
    · exact ih t h
  | call i r ih =>
    intro t h; simp only [printBlock, List.mem_cons] at h
    rcases h with rfl | h
    · exact plain_wordName i
    · exact ih t h
  | exit r ih =>
    intro t h; simp only [printBlock, List.mem_cons] at h
    rcases h with rfl | h
    · exact plain_concrete (by decide)
    · exact ih t h
  | ite x e r ihx ihe ihr =>
    intro t h; simp only [printBlock, List.mem_cons, List.mem_append] at h
    rcases h with rfl | h | rfl | h | rfl | h
    · exact plain_concrete (by decide)
    · exact ihx t h
    · exact plain_concrete (by decide)
    · exact ihe t h
    · exact plain_concrete (by decide)
    · exact ihr t h
  | untilL x r ihx ihr =>
    intro t h; simp only [printBlock, List.mem_cons, List.mem_append] at h
    rcases h with rfl | h | rfl | h
    · exact plain_concrete (by decide)
    · exact ihx t h
    · exact plain_concrete (by decide)
    · exact ihr t h
  | doLoop x r ihx ihr =>
    intro t h; simp only [printBlock, List.mem_cons, List.mem_append] at h
    rcases h with rfl | h | rfl | h
    · exact plain_concrete (by decide)
    · exact ihx t h
    · exact plain_concrete (by decide)
    · exact ihr t h
  | plusLoop x r ihx ihr =>
    intro t h; simp only [printBlock, List.mem_cons, List.mem_append] at h
    rcases h with rfl | h | rfl | h
    · exact plain_concrete (by decide)
    · exact ihx t h
    · exact plain_concrete (by decide)
    · exact ihr t h
  | leave r ih =>
    intro t h; simp only [printBlock, List.mem_cons] at h
    rcases h with rfl | h
    · exact plain_concrete (by decide)
    · exact ih t h
  | whileL c x r ihc ihx ihr =>
    intro t h; simp only [printBlock, List.mem_cons, List.mem_append] at h
    rcases h with rfl | h | rfl | h | rfl | h
    · exact plain_concrete (by decide)
    · exact ihc t h
    · exact plain_concrete (by decide)
    · exact ihx t h
    · exact plain_concrete (by decide)
    · exact ihr t h

theorem plain_printTokens (P : Program) : ∀ t ∈ printTokens P, Plain t := by
  have hv : ∀ v, ∀ t ∈ varToks v, Plain t := by
    intro v
    induction v with
    | zero => intro t h; simp [varToks] at h
    | succ v ih =>
      intro t h; simp only [varToks, List.mem_cons] at h
      rcases h with rfl | rfl | h
      · exact plain_concrete (by decide)
      · exact plain_concrete (by decide)
      · exact ih t h
  have hd : ∀ (bs : List Block) k, ∀ t ∈ defsToks k bs, Plain t := by
    intro bs
    induction bs with
    | nil => intro k t h; simp [defsToks] at h
    | cons b bs ih =>
      intro k t h; simp only [defsToks, List.mem_cons, List.mem_append] at h
      rcases h with rfl | rfl | h | rfl | h
      · exact plain_concrete (by decide)
      · exact plain_wordName k
      · exact plain_printBlock b t h
      · exact plain_concrete (by decide)
      · exact ih (k + 1) t h
  intro t h
  simp only [printTokens, List.mem_append] at h
  rcases h with h | h | h
  · exact hv _ t h
  · exact hd _ _ t h
  · exact plain_printBlock _ t h

end Print

/-- **Round trip.** Printing a well-formed program and parsing the text gives the program
back. -/
theorem parse_print (P : Program) (h : P.WF) : parse (print P) = .ok P := by
  unfold parse print
  rw [Print.tokenize_join _ (Print.plain_printTokens P)]
  exact Print.parseTokens_print P h

end Forth
end WordDialect
