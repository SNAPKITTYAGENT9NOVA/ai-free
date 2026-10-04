import Forth.Semantics

/-!
# Forth.Parse

Text frontend: Forth source → `Program` (dictionary + main block + variable count).

Lexing (`tokenize`):
* tokens are separated by whitespace (space, tab, newline, carriage return);
* `\` as a token starts a comment that runs to the end of the line;
* `(` as a token starts a comment that ends with the first token ending in `)`
  (an unterminated `(` comment is an error).

Parsing (`parse`), case-insensitive:
* integer literals, optionally negative (`-12`), taken modulo `2^n` by `Op.lit`;
* `+ - * / MOD AND OR XOR INVERT LSHIFT RSHIFT = <> < > U< U> 0= DUP DROP SWAP OVER ROT @ !`;
* `IF … ELSE … THEN`, `IF … THEN`, `BEGIN … UNTIL`;
* `: name … ;` colon definitions at top level. A name is visible from the start of its own
  body (so a word may call itself recursively) and in everything after it; a later definition
  of the same name shadows the earlier one. Word `k` (in definition order) is `defs[k]`.
* `RECURSE` (inside a definition) calls the word being defined; `EXIT` (inside a definition)
  leaves it. Both are errors outside a definition.
* `VARIABLE name` (top level) allocates the next memory cell: the `k`-th variable (from 0) is
  cell `k`, and `name` pushes `k`. The program records how many cells it uses (`vars`).
* `<number> CONSTANT name` (top level): the number literal immediately before `CONSTANT` is
  removed from the top-level code and `name` pushes it. (Standard Forth takes the value from
  the stack at run time; here it must be a literal, resolved at parse time.)
* Top-level code outside definitions forms the main block, in source order.
* Anything else is an error (`unknown word`), as are unbalanced control words, nested
  definitions, `VARIABLE`/`CONSTANT` inside a definition and a missing `;`. In particular
  `>R R>` and `DO … LOOP` are not supported: the IR has no return stack for data words (see
  `NEXT_STEPS.md`).

Name lookup order: dictionary, then built-in words, then numbers.

Everything is structurally recursive on `List Char` / fuel, so concrete parses are checked by
`decide`/`rfl`. `Forth.Print` proves `parse (print P) = .ok P` for well-formed programs;
`Forth.ParseProps` proves the converse direction (`parse_wf`: every successful parse is
well formed) and the claims above about case, comments, `CONSTANT` and `RECURSE`.
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
  | .exit r, b => .exit (r.append b)

/-- Split off a trailing literal at the top level of a block (the token just before
`CONSTANT`). -/
def Block.dropLastLit : Block → Option (Block × Int)
  | .nil => none
  | .op (.lit z) .nil => some (.nil, z)
  | .op o r => r.dropLastLit.map fun p => (.op o p.1, p.2)
  | .ite t e r => r.dropLastLit.map fun p => (.ite t e p.1, p.2)
  | .untilL x r => r.dropLastLit.map fun p => (.untilL x p.1, p.2)
  | .call i r => r.dropLastLit.map fun p => (.call i p.1, p.2)
  | .exit r => r.dropLastLit.map fun p => (.exit p.1, p.2)

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
  [ (['+'], .add), (['-'], .sub), (['*'], .mul), (['/'], .div), (['M', 'O', 'D'], .mod),
    (['A', 'N', 'D'], .and), (['O', 'R'], .or), (['X', 'O', 'R'], .xor),
    (['I', 'N', 'V', 'E', 'R', 'T'], .invert),
    (['L', 'S', 'H', 'I', 'F', 'T'], .lshift), (['R', 'S', 'H', 'I', 'F', 'T'], .rshift),
    (['='], .eq), (['<', '>'], .ne), (['<'], .lt), (['>'], .gt),
    (['U', '<'], .ult), (['U', '>'], .ugt), (['0', '='], .zeq),
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
def kVARIABLE : Tok := ['V', 'A', 'R', 'I', 'A', 'B', 'L', 'E']
def kCONSTANT : Tok := ['C', 'O', 'N', 'S', 'T', 'A', 'N', 'T']
def kRECURSE : Tok := ['R', 'E', 'C', 'U', 'R', 'S', 'E']
def kEXIT : Tok := ['E', 'X', 'I', 'T']

/-- Words that end the block being parsed. -/
def stops : List Tok := [kELSE, kTHEN, kUNTIL, kCOLON, kSEMI, kVARIABLE, kCONSTANT]

/-- Dictionary: (upper-cased name, what the name compiles to), most recent first. A colon
definition `k` compiles to `Block.call k`; a variable or constant to a literal. -/
abbrev Dict := List (Tok × (Block → Block))

def showTok (t : Tok) : String := String.ofList t

/-- What a token means where a word is expected. -/
inductive Item where
  | stop (u : Tok)
  | ifK
  | beginK
  | prim (w : Block → Block)
  | bad (msg : String)

/-- Look up a (non-keyword) token `t`, upper-cased `u`: dictionary, built-ins, numbers. -/
def lookupWord (dict : Dict) (t u : Tok) : Item :=
  match dict.lookup u with
  | some w => .prim w
  | none =>
    match opTable.lookup u with
    | some o => .prim (.op o)
    | none =>
      match number u with
      | some z => .prim (.op (.lit z))
      | none => .bad s!"unknown word: {showTok t}"

/-- Classify a token; `self` is the index of the word being defined, if any. -/
def classify (dict : Dict) (self : Option Nat) (t : Tok) : Item :=
  let u := upper t
  if u ∈ stops then .stop u
  else if u = kIF then .ifK
  else if u = kBEGIN then .beginK
  else if u = kRECURSE then
    match self with
    | some i => .prim (.call i)
    | none => .bad "RECURSE outside a definition"
  else if u = kEXIT then
    match self with
    | some _ => .prim .exit
    | none => .bad "EXIT outside a definition"
  else lookupWord dict t u

/-- Parse a block up to the end of input or a stop word. Returns the block, the stop word
met (`none` at end of input) and the tokens after it. -/
def parseSeq : Nat → Dict → Option Nat → List Tok → Except String (Block × Option Tok × List Tok)
  | 0, _, _, _ => .error "input too deeply nested"
  | _ + 1, _, _, [] => .ok (.nil, none, [])
  | fuel + 1, dict, self, t :: ts =>
    match classify dict self t with
    | .stop u => .ok (.nil, some u, ts)
    | .bad msg => .error msg
    | .prim w => do
      let (rest, stop, ts') ← parseSeq fuel dict self ts
      .ok (w rest, stop, ts')
    | .ifK => do
      let (tb, stop1, ts1) ← parseSeq fuel dict self ts
      if stop1 = some kELSE then
        let (eb, stop2, ts2) ← parseSeq fuel dict self ts1
        if stop2 = some kTHEN then
          let (rest, stop3, ts3) ← parseSeq fuel dict self ts2
          .ok (.ite tb eb rest, stop3, ts3)
        else .error "IF … ELSE without THEN"
      else if stop1 = some kTHEN then
        let (rest, stop3, ts3) ← parseSeq fuel dict self ts1
        .ok (.ite tb .nil rest, stop3, ts3)
      else .error "IF without THEN"
    | .beginK => do
      let (body, stop1, ts1) ← parseSeq fuel dict self ts
      if stop1 = some kUNTIL then
        let (rest, stop2, ts2) ← parseSeq fuel dict self ts1
        .ok (.untilL body rest, stop2, ts2)
      else .error "BEGIN without UNTIL"

/-- Parse top-level code, definitions, variables and constants. `vars` counts the variables
so far; `main` accumulates the top-level code so far. -/
def parseTop : Nat → Dict → List Block → Nat → Block → List Tok → Except String Program
  | 0, _, _, _, _, _ => .error "input too long"
  | fuel + 1, dict, defs, vars, main, toks => do
    let (b, stop, rest) ← parseSeq (toks.length + 1) dict none toks
    match stop with
    | none => .ok ⟨defs, main.append b, vars⟩
    | some u =>
      if u = kCOLON then
        match rest with
        | [] => .error "missing name after :"
        | name :: body =>
          let dict' := (upper name, Block.call defs.length) :: dict
          let (bb, stop2, rest2) ← parseSeq (body.length + 1) dict' (some defs.length) body
          if stop2 = some kSEMI then parseTop fuel dict' (defs ++ [bb]) vars (main.append b) rest2
          else if stop2 = some kCOLON then .error s!"nested definition inside {showTok name}"
          else if stop2 = some kVARIABLE ∨ stop2 = some kCONSTANT then
            .error s!"VARIABLE or CONSTANT inside definition of {showTok name}"
          else .error s!"definition of {showTok name} has no ;"
      else if u = kVARIABLE then
        match rest with
        | [] => .error "missing name after VARIABLE"
        | name :: rest' =>
          parseTop fuel ((upper name, Block.op (.lit vars)) :: dict) defs (vars + 1)
            (main.append b) rest'
      else if u = kCONSTANT then
        match b.dropLastLit, rest with
        | none, _ => .error "CONSTANT needs a number literal immediately before it"
        | some _, [] => .error "missing name after CONSTANT"
        | some (b', z), name :: rest' =>
          parseTop fuel ((upper name, Block.op (.lit z)) :: dict) defs vars (main.append b') rest'
      else .error s!"unexpected {showTok u}"

def parseTokens (toks : List Tok) : Except String Program :=
  parseTop (toks.length + 1) [] [] 0 .nil toks

end Parse

/-- Parse Forth source text into a program. -/
def parse (src : String) : Except String Program := do
  Parse.parseTokens (← Parse.tokenize src)

end Forth
end WordDialect
