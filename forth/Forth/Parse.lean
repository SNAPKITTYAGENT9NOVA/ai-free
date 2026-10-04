import Forth.Semantics

/-!
# Forth.Parse

Text frontend: Forth source → `Program` (dictionary + main block).

Lexing (`tokenize`):
* tokens are separated by whitespace (space, tab, newline, carriage return);
* `\` as a token starts a comment that runs to the end of the line;
* `(` as a token starts a comment that ends with the first token ending in `)`
  (an unterminated `(` comment is an error).

Parsing (`parse`), case-insensitive:
* integer literals, optionally negative (`-12`), taken modulo `2^n` by `Op.lit`;
* `+ - * / AND OR XOR INVERT LSHIFT RSHIFT = <> < > U< U> DUP DROP SWAP OVER ROT @ !`;
* `IF … ELSE … THEN`, `IF … THEN`, `BEGIN … UNTIL`;
* `: name … ;` colon definitions at top level. A name is visible from the start of its own
  body (so a word may call itself recursively) and in everything after it; a later definition
  of the same name shadows the earlier one. Word `k` (in definition order) is `defs[k]`.
* Top-level code outside definitions forms the main block, in source order.
* Anything else is an error (`unknown word`), as are unbalanced control words, nested
  definitions and a missing `;`.

Name lookup order: dictionary, then built-in words, then numbers.

Everything is structurally recursive on `List Char` / fuel, so concrete parses are checked by
`decide`.
-/

namespace WordDialect
namespace Forth

/-- Concatenate two blocks: run `a`, then `b`. -/
def Block.append : Block → Block → Block
  | .nil, b => b
  | .op o r, b => .op o (r.append b)
  | .ite t e r, b => .ite t e (r.append b)
  | .untilL x r, b => .untilL x (r.append b)
  | .call i r, b => .call i (r.append b)

namespace Parse

abbrev Tok := List Char

def isWs (c : Char) : Bool := c == ' ' || c == '\t' || c == '\n' || c == '\r'

/-- Emit the pending token `cur` (kept reversed) in front of `rest`. -/
def flush (cur : List Char) (rest : List Tok) : List Tok :=
  if cur = [] then rest else cur.reverse :: rest

/-- Split into tokens. `cur` is the current token reversed; `skip` means "inside a `\`
comment". -/
def lex : List Char → List Char → Bool → List Tok
  | [], cur, _ => if cur = ['\\'] then [] else flush cur []
  | c :: cs, _, true => if c == '\n' then lex cs [] false else lex cs [] true
  | c :: cs, cur, false =>
    if isWs c then
      if cur = ['\\'] then (if c == '\n' then lex cs [] false else lex cs [] true)
      else flush cur (lex cs [] false)
    else lex cs (c :: cur) false

/-- Remove `( … )` comments. `inside` means "inside a `(` comment". -/
def stripParens : Bool → List Tok → Except String (List Tok)
  | false, [] => .ok []
  | true, [] => .error "unterminated ( comment"
  | false, t :: ts =>
    if t = ['('] then stripParens true ts else (t :: ·) <$> stripParens false ts
  | true, t :: ts => if t.getLast? = some ')' then stripParens false ts else stripParens true ts

def tokenize (src : String) : Except String (List Tok) :=
  stripParens false (lex src.toList [] false)

def upper (t : Tok) : Tok := t.map Char.toUpper

def opTable : List (Tok × Op) :=
  [ (['+'], .add), (['-'], .sub), (['*'], .mul), (['/'], .div),
    (['A', 'N', 'D'], .and), (['O', 'R'], .or), (['X', 'O', 'R'], .xor),
    (['I', 'N', 'V', 'E', 'R', 'T'], .invert),
    (['L', 'S', 'H', 'I', 'F', 'T'], .lshift), (['R', 'S', 'H', 'I', 'F', 'T'], .rshift),
    (['='], .eq), (['<', '>'], .ne), (['<'], .lt), (['>'], .gt),
    (['U', '<'], .ult), (['U', '>'], .ugt),
    (['D', 'U', 'P'], .dup), (['D', 'R', 'O', 'P'], .drop), (['S', 'W', 'A', 'P'], .swap),
    (['O', 'V', 'E', 'R'], .over), (['R', 'O', 'T'], .rot),
    (['@'], .fetch), (['!'], .store) ]

def digitsAux : Nat → List Char → Option Nat
  | acc, [] => some acc
  | acc, c :: cs => if c.isDigit then digitsAux (10 * acc + (c.toNat - '0'.toNat)) cs else none

/-- A nonempty string of decimal digits. -/
def digits : List Char → Option Nat
  | [] => none
  | cs => digitsAux 0 cs

def number : Tok → Option Int
  | '-' :: ds => (digits ds).map fun k => -(k : Int)
  | ds => (digits ds).map Int.ofNat

def kIF : Tok := ['I', 'F']
def kELSE : Tok := ['E', 'L', 'S', 'E']
def kTHEN : Tok := ['T', 'H', 'E', 'N']
def kBEGIN : Tok := ['B', 'E', 'G', 'I', 'N']
def kUNTIL : Tok := ['U', 'N', 'T', 'I', 'L']
def kCOLON : Tok := [':']
def kSEMI : Tok := [';']

/-- Words that end the block being parsed. -/
def stops : List Tok := [kELSE, kTHEN, kUNTIL, kCOLON, kSEMI]

/-- Dictionary: (upper-cased name, word index), most recent first. -/
abbrev Dict := List (Tok × Nat)

def showTok (t : Tok) : String := String.ofList t

/-- Parse a block up to the end of input or a stop word. Returns the block, the stop word
met (`none` at end of input) and the tokens after it. -/
def parseSeq : Nat → Dict → List Tok → Except String (Block × Option Tok × List Tok)
  | 0, _, _ => .error "input too deeply nested"
  | _ + 1, _, [] => .ok (.nil, none, [])
  | fuel + 1, dict, t :: ts =>
    let u := upper t
    if u ∈ stops then .ok (.nil, some u, ts)
    else if u = kIF then do
      let (tb, stop1, ts1) ← parseSeq fuel dict ts
      if stop1 = some kELSE then
        let (eb, stop2, ts2) ← parseSeq fuel dict ts1
        if stop2 = some kTHEN then
          let (rest, stop3, ts3) ← parseSeq fuel dict ts2
          .ok (.ite tb eb rest, stop3, ts3)
        else .error "IF … ELSE without THEN"
      else if stop1 = some kTHEN then
        let (rest, stop3, ts3) ← parseSeq fuel dict ts1
        .ok (.ite tb .nil rest, stop3, ts3)
      else .error "IF without THEN"
    else if u = kBEGIN then do
      let (body, stop1, ts1) ← parseSeq fuel dict ts
      if stop1 = some kUNTIL then
        let (rest, stop2, ts2) ← parseSeq fuel dict ts1
        .ok (.untilL body rest, stop2, ts2)
      else .error "BEGIN without UNTIL"
    else do
      let w : Block → Block ←
        match dict.lookup u with
        | some i => .ok (.call i)
        | none =>
          match opTable.lookup u with
          | some o => .ok (.op o)
          | none =>
            match number u with
            | some z => .ok (.op (.lit z))
            | none => .error s!"unknown word: {showTok t}"
      let (rest, stop, ts') ← parseSeq fuel dict ts
      .ok (w rest, stop, ts')

/-- Parse top-level code and definitions. `main` accumulates the top-level code so far. -/
def parseTop : Nat → Dict → List Block → Block → List Tok → Except String Program
  | 0, _, _, _, _ => .error "input too long"
  | fuel + 1, dict, defs, main, toks => do
    let (b, stop, rest) ← parseSeq (toks.length + 1) dict toks
    let main := main.append b
    match stop with
    | none => .ok ⟨defs, main⟩
    | some u =>
      if u = kCOLON then
        match rest with
        | [] => .error "missing name after :"
        | name :: body =>
          let dict' := (upper name, defs.length) :: dict
          let (bb, stop2, rest2) ← parseSeq (body.length + 1) dict' body
          if stop2 = some kSEMI then parseTop fuel dict' (defs ++ [bb]) main rest2
          else if stop2 = some kCOLON then .error s!"nested definition inside {showTok name}"
          else .error s!"definition of {showTok name} has no ;"
      else .error s!"unexpected {showTok u}"

def parseTokens (toks : List Tok) : Except String Program :=
  parseTop (toks.length + 1) [] [] .nil toks

end Parse

/-- Parse Forth source text into a program. -/
def parse (src : String) : Except String Program := do
  Parse.parseTokens (← Parse.tokenize src)

end Forth
end WordDialect
