import WordDialect
import WordIR
import Forth
import BCPL
import Wolfram

/-!
# Harness

Shared differential-testing harness for every backend. A backend supplies a `Runner`: it takes a
`Sample` (an IR program plus initial memory and register-file size), runs it on the real target,
and reports either the dumped final state or the exit code of a trap. The harness runs the same IR
program under the Lean semantics (`WordDialect.run`) and compares.

Trap exit codes are common to all backends: 1 stackUnderflow, 2 badAddress, 3 divideByZero,
4 badPc, 5 returnUnderflow; 6 is a target stack overflow, which has no IR counterpart. On halt a backend writes, as raw little-endian 64-bit words, the data
stack depth, the data stack (top first), the IR memory and the virtual registers.
-/

open WordDialect

structure Sample where
  name : String
  prog : Prog 64
  mem : List Nat
  nregs : Nat := 4
  /-- Set when the sample could not be built (e.g. Forth source failed to parse); `check`
  then reports an error instead of running anything. -/
  buildError : Option String := none

def mkMem (img : List Nat) : Memory 64 := Memory.ofImage img

inductive Result where
  | halted (stack mem regs : List Nat)
  | trap (code : Nat)
  | timeout
  deriving BEq, Repr

/-- Expected result under the Lean semantics. -/
def trapCode : Trap → Nat
  | .stackUnderflow => 1
  | .badAddress => 2
  | .divideByZero => 3
  | .badPc => 4
  | .returnUnderflow => 5

def expected (s : Sample) : Result :=
  match run s.prog 200000 (State.init (mkMem s.mem)) with
  | none => .timeout
  | some (.trapped t) => .trap (trapCode t)
  | some (.next _) => .timeout
  | some (.halted st) =>
    .halted (st.dstack.map (·.toNat))
      ((List.range s.mem.length).map fun a => (st.mem.cell (BitVec.ofNat 64 a)).toNat)
      ((List.range s.nregs).map fun r => (st.regs r).toNat)

def u64 (b : ByteArray) (off : Nat) : Nat :=
  (List.range 8).foldl (fun acc i => acc + (b.get! (off + i)).toNat * 2 ^ (8 * i)) 0

partial def readAll (h : IO.FS.Handle) (acc : ByteArray) : IO ByteArray := do
  let chunk ← h.read 65536
  if chunk.isEmpty then pure acc else readAll h (acc ++ chunk)

def parseDump (s : Sample) (b : ByteArray) : Option Result :=
  if b.size < 8 then none else
  let depth := u64 b 0
  let m := s.mem.length
  if b.size != 8 + 8 * depth + 8 * m + 8 * s.nregs then none else
  some (.halted ((List.range depth).map fun i => u64 b (8 + 8 * i))
    ((List.range m).map fun i => u64 b (8 + 8 * depth + 8 * i))
    ((List.range s.nregs).map fun i => u64 b (8 + 8 * depth + 8 * m + 8 * i)))

/-- A backend: run a sample on the real target. -/
abbrev Runner := Sample → IO (Except String Result)

def check (run : Runner) (s : Sample) : IO Bool := do
  if let some e := s.buildError then
    IO.println s!"ERROR {s.name}: {e}"; return false
  let exp := expected s
  match exp with
  | .timeout => IO.println s!"SKIP  {s.name} (IR did not terminate within fuel)"; return true
  | _ =>
    match ← run s with
    | .error e => IO.println s!"ERROR {s.name}: {e}"; return false
    | .ok got =>
      if got == exp then
        IO.println s!"PASS  {s.name}  {repr exp}"; return true
      else
        IO.println s!"FAIL  {s.name}\n  lean:   {repr exp}\n  target: {repr got}"; return false

/-! ## Programs from the frontends -/

def forthSample (name : String) (b : Forth.Block) (mem : List Nat := List.replicate 16 0) : Sample :=
  { name, prog := Forth.compileProgram b, mem }

/-- A sample written as Forth source text. A parse failure becomes a reported error. The memory
image is extended with zero cells if the program's `VARIABLE`s (cells `0 … vars - 1`) need more. -/
def forthTextSample (name : String) (src : String) (mem : List Nat := List.replicate 16 0) :
    Sample :=
  match Forth.parse src with
  | .ok P => { name, prog := P.compile, mem := mem ++ List.replicate (P.vars - mem.length) 0 }
  | .error e => { name, prog := [], mem, buildError := some s!"Forth parse error: {e}" }

open Forth in
def forthOps (ops : List Op) : Block := ops.foldr (fun o b => .op o b) .nil

def bcplAddr : BCPL.Var → Word 64 := fun x => BitVec.ofNat 64 x

def samplesFrontends : List Sample :=
  open Forth in
  [ forthSample "forth_five_dup_plus" Forth.fiveDupPlus
  , forthSample "forth_countdown"
      (.op (.lit 10) (.untilL (forthOps [.lit 1, .sub, .dup, .lit 0, .eq]) .nil))
  , forthSample "forth_if_else" (.op (.lit 3) (.op (.lit 5) (.op .lt (.ite (.op (.lit 111) .nil) (.op (.lit 222) .nil) .nil))))
  , forthSample "forth_store_fetch" (forthOps [.lit 42, .lit 7, .store, .lit 7, .fetch])
  , forthSample "forth_sdiv_trunc" (forthOps [.lit (-7), .lit 2, .div])
  , forthSample "forth_sdiv_intmin" (forthOps [.lit (-9223372036854775808), .lit (-1), .div])
  , forthSample "forth_shifts" (forthOps [.lit 1, .lit 64, .lshift, .lit (-1), .lit 70, .rshift,
      .lit 255, .lit 3, .rshift, .lit 1, .lit 63, .lshift])
  , forthSample "forth_compare_signed" (forthOps [.lit (-1), .lit 1, .lt, .lit (-1), .lit 1, .ult,
      .lit 5, .lit 5, .eq, .lit 5, .lit 6, .ne])
  , forthSample "forth_stack_words" (forthOps [.lit 1, .lit 2, .lit 3, .rot, .over, .swap, .dup,
      .drop])
  , forthSample "forth_trap_div0" (forthOps [.lit 1, .lit 0, .div])
  , forthSample "forth_trap_underflow" (forthOps [.add])
  , forthSample "forth_trap_badaddr" (forthOps [.lit 1000, .fetch])
  , forthTextSample "forth_text_sum_recursive" Forth.sumSrc
  , forthTextSample "forth_text_fib_recursive"
      ": FIB ( n -- fib[n] ) DUP 2 < IF ELSE DUP 1 - FIB SWAP 2 - FIB + THEN ;\n15 FIB"
  , forthTextSample "forth_text_gcd_words"
      ": MOD ( a b -- a mod b ) OVER OVER / * - ;\n\
       : GCD ( a b -- g ) BEGIN SWAP OVER MOD DUP 0 = UNTIL DROP ;\n\
       1071 462 GCD 3 !  3 @  \\ store the result at address 3, read it back"
  , forthTextSample "forth_text_trap_in_word" ": INNER 1 0 / ; : OUTER 7 INNER 8 ; 5 OUTER"
  , forthTextSample "forth_text_mod_zeq"
      "-7 2 MOD  7 -2 MOD  -7 -2 MOD  9223372036854775807 10 MOD\n\
       -9223372036854775808 -1 MOD  0 0=  5 0=  -1 0="
  , forthTextSample "forth_text_trap_mod0" "5 1 0 MOD"
  , forthTextSample "forth_text_variables"
      "VARIABLE N  VARIABLE ACC  100 CONSTANT LIMIT\n\
       : STEP ( -- ) ACC @ N @ + ACC !  N @ 1 + N ! ;\n\
       0 N !  0 ACC !  BEGIN STEP N @ LIMIT > UNTIL  ACC @ N @"
  , forthTextSample "forth_text_many_variables"
      "VARIABLE A0 VARIABLE A1 VARIABLE A2 VARIABLE A3 VARIABLE A4 VARIABLE A5 VARIABLE A6\n\
       VARIABLE A7 VARIABLE A8 VARIABLE A9 VARIABLE A10 VARIABLE A11 VARIABLE A12 VARIABLE A13\n\
       VARIABLE A14 VARIABLE A15 VARIABLE A16 VARIABLE A17 VARIABLE A18 VARIABLE A19\n\
       77 A19 !  -5 A0 !  A19 @ A0 @ +  A19"
  , forthTextSample "forth_text_exit_recursive"
      ": GCD ( a b -- g ) DUP 0= IF DROP EXIT THEN SWAP OVER MOD RECURSE ;\n\
       : SUM ( n -- 0+...+n ) DUP 0= IF EXIT THEN DUP 1 - RECURSE + ;\n\
       1071 462 GCD  20 SUM"
  , forthTextSample "forth_text_exit_dead_code" ": F 1 EXIT 2 3 ; : G F F + EXIT F ; G"
  , { name := "bcpl_sum_1_to_10", mem := List.replicate 4 0,
      prog := BCPL.compileProgram bcplAddr
        (.seq (.assign (.var 1) (.num 10)) (.seq (.assign (.var 0) (.num 0))
          (.while (.bin .ne (.var 1) (.num 0))
            (.seq (.assign (.var 0) (.bin .add (.var 0) (.var 1)))
                  (.assign (.var 1) (.bin .sub (.var 1) (.num 1))))))) }
  , { name := "bcpl_indirect", mem := List.replicate 8 0,
      prog := BCPL.compileProgram bcplAddr
        (.seq (.assign (.var 0) (.addrOf 5))
          (.seq (.assign (.rv (.var 0)) (.num 77))
            (.assign (.var 1) (.bin .add (.rv (.var 0)) (.num 1))))) }
  , { name := "wolfram_dot_2x2", nregs := 4,
      mem := [1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0],
      prog := (Wolfram.dotFrag 2 2 2 0 4 8 : IR.Frag 64).emit 0 ++ [.halt] }
  , { name := "wolfram_dot_3x2_2x4", nregs := 4,
      mem := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prog := (Wolfram.dotFrag 3 2 4 0 6 14 : IR.Frag 64).emit 0 ++ [.halt] }
  ]

/-! ## Hand-written IR covering control flow and calls -/

def samplesRaw : List Sample :=
  [ { name := "raw_call_ret", mem := [], nregs := 1,
      prog := [.word 5, .call 4, .call 4, .halt, .dup, .add, .ret] }
  , { name := "raw_trap_ret_empty", mem := [], nregs := 1, prog := [.ret] }
  , { name := "raw_trap_badpc", mem := [], nregs := 1, prog := [.word 1, .jmp 100] }
  , { name := "raw_rotates", mem := [], nregs := 1,
      prog := [.word 0x8000000000000001, .word 1, .rotl, .word 0x8000000000000001, .word 1, .rotr,
               .word 3, .word 130, .rotl, .halt] }
  , { name := "raw_select_regs", mem := [], nregs := 3,
      prog := [.word 9, .pop 2, .word 11, .word 22, .word 0, .select, .push 2, .word 11,
               .word 22, .word 1, .select, .halt] }
  ]

/-! ## Randomised differential testing -/

def edge : Array Nat :=
  #[0, 1, 2, 3, 7, 63, 64, 65, 127, 128, 255, 2 ^ 63 - 1, 2 ^ 63, 2 ^ 63 + 1, 2 ^ 64 - 1,
    2 ^ 64 - 2, 0xdeadbeef, 0x123456789abcdef0]

def randWord : IO Nat := do
  let k ← IO.rand 0 3
  if k = 0 then
    let hi ← IO.rand 0 (2 ^ 32 - 1)
    let lo ← IO.rand 0 (2 ^ 32 - 1)
    pure (hi * 2 ^ 32 + lo)
  else
    let i ← IO.rand 0 (edge.size - 1)
    pure edge[i]!

def conds : Array Cond := #[.eq, .ne, .ult, .ule, .ugt, .uge, .slt, .sle, .sgt, .sge]

def genInstr (depth : Nat) : IO (List (Instr 64) × Int) := do
  let r ← IO.rand 0 99
  if depth < 2 && r >= 6 then
    let k ← IO.rand 0 2
    if k = 0 then do let w ← randWord; return ([.word (BitVec.ofNat 64 w)], 1)
    else if k = 1 then do let q ← IO.rand 0 3; return ([.push q], 1)
    else do let w ← randWord; return ([.word (BitVec.ofNat 64 w)], 1)
  else
    let k ← IO.rand 0 27
    match k with
    | 0 => do let w ← randWord; return ([.word (BitVec.ofNat 64 w)], 1)
    | 1 => return ([.add], -1) | 2 => return ([.sub], -1) | 3 => return ([.mul], -1)
    | 4 => return ([.and], -1) | 5 => return ([.or], -1) | 6 => return ([.xor], -1)
    | 7 => return ([.not], 0)
    | 8 => return ([.shl], -1) | 9 => return ([.shr], -1)
    | 10 => return ([.rotl], -1) | 11 => return ([.rotr], -1)
    | 12 => return ([.div], -1) | 13 => return ([.sdiv], -1)
    | 14 => do let c ← IO.rand 0 9; return ([.cmp (conds[c]?.getD .eq)], -1)
    | 15 => return ([.select], -2)
    | 16 => return ([.dup], 1) | 17 => return ([.drop], -1) | 18 => return ([.swap], 0)
    | 19 => return ([.over], 1) | 20 => return ([.rot], 0)
    | 21 => do let q ← IO.rand 0 3; return ([.push q], 1)
    | 22 => do let q ← IO.rand 0 3; return ([.pop q], -1)
    | 23 => do let v ← randWord; let a ← IO.rand 0 17
               return ([.word (BitVec.ofNat 64 v), .word (BitVec.ofNat 64 a), .store], 0)
    | 24 => do let a ← IO.rand 0 17; return ([.word (BitVec.ofNat 64 a), .load], 1)
    | 25 => do let v ← randWord; return ([.word (BitVec.ofNat 64 v), .word 0, .select], 0)
    | _ => do let w ← randWord; return ([.word (BitVec.ofNat 64 w)], 1)

def genProg (len : Nat) : IO (List (Instr 64)) := do
  let mut code : List (Instr 64) := []
  let mut depth : Int := 0
  for _ in List.range len do
    let (is, d) ← genInstr depth.toNat
    code := code ++ is
    depth := max 0 (depth + d)
  -- a few forward jumps / conditional branches
  let n := code.length
  for _ in List.range 2 do
    let k ← IO.rand 0 (n - 1)
    let skip ← IO.rand 1 4
    let kind ← IO.rand 0 1
    if kind = 0 then
      code := code.set k (.jmp (min n (k + 1 + skip)))
    else
      code := code.set k (.branch (min n (k + 1 + skip)))
  return code ++ [.halt]

def fuzz (run : Runner) (count : Nat) : IO Bool := do
  let mut ok := true
  let mut skipped := 0
  let mut halts := 0
  let mut traps : Array Nat := #[0, 0, 0, 0, 0, 0]
  let mut longest := 0
  for i in List.range count do
    let len ← IO.rand 4 40
    let prog ← genProg len
    let mem ← (List.range 16).mapM fun _ => randWord
    let s : Sample := { name := s!"fuzz_{i}", prog, mem, nregs := 4 }
    let exp := expected s
    match exp with
    | .halted st _ _ => halts := halts + 1; longest := max longest st.length
    | .trap c => traps := traps.set! c (traps[c]! + 1)
    | .timeout => pure ()
    if exp == .timeout then skipped := skipped + 1 else
    match ← run s with
    | .error e => IO.println s!"ERROR fuzz_{i}: {e}"; ok := false
    | .ok got =>
      if got != exp then
        IO.println s!"FAIL  fuzz_{i}\n  lean:   {repr exp}\n  target: {repr got}"
        ok := false
  IO.println s!"fuzz: {count} programs, {skipped} skipped; halted {halts}; traps by code (1 underflow, 2 badaddr, 3 div0, 4 badpc, 5 ret) {traps.toList.drop 1}; max final depth {longest}; {if ok then "all agree" else "MISMATCH"}"
  return ok

def allSamples : List Sample := samplesFrontends ++ samplesRaw

/-- Run every sample and `count` random programs against a backend. -/
def checkAll (run : Runner) (count : Nat) : IO Bool := do
  IO.setRandSeed 20260610
  let mut ok := true
  for s in allSamples do
    if !(← check run s) then ok := false
  if !(← fuzz run count) then ok := false
  return ok
