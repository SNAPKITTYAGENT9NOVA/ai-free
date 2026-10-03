import WordDialect
import WordIR
import Forth
import BCPL
import Wolfram
import X86

/-!
# wordc

Native execution harness. For each program it
1. lowers the IR to x86-64 and emits GNU assembly (`X86.Emit`),
2. assembles and links it with `as` / `ld`,
3. runs the binary on this machine,
4. runs the same IR program under the Lean semantics (`WordDialect.run`), and
5. compares exit status and the dumped data stack, IR memory and virtual registers.

Usage: `wordc check [fuzzCount]`, `wordc emit <sample>`.
-/

open WordDialect

structure Sample where
  name : String
  prog : Prog 64
  mem : List Nat
  nregs : Nat := 4

def dBase : Nat := 0x10000000
def capacity : Nat := 65536
def dEnd : Nat := dBase + 8 * capacity

def layoutFor (s : Sample) : X86.Layout :=
  { dEnd := BitVec.ofNat 64 dEnd, memSize := s.mem.length }

def runtimeFor (s : Sample) : X86.Emit.Runtime :=
  { dEnd := dEnd, capacity := capacity, memImage := s.mem, nregs := s.nregs }

def asmFor (s : Sample) : String :=
  X86.Emit.program (runtimeFor s) (X86.lowerProg (layoutFor s) s.prog)

def mkMem (img : List Nat) : Memory 64 :=
  { cell := fun a => BitVec.ofNat 64 (img.getD a.toNat 0),
    valid := fun a => decide (a.toNat < img.length) }

inductive Result where
  | halted (stack mem regs : List Nat)
  | trap (code : Nat)
  | timeout
  deriving BEq, Repr

/-- Expected result under the Lean semantics. -/
def expected (s : Sample) : Result :=
  match run s.prog 200000 (State.init (mkMem s.mem)) with
  | none => .timeout
  | some (.trapped t) => .trap (X86.Emit.trapCode t)
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

def workDir : String := "/tmp/wordc"

def runNative (s : Sample) : IO (Except String Result) := do
  IO.FS.createDirAll workDir
  let base := s!"{workDir}/{s.name}"
  IO.FS.writeFile (base ++ ".s") (asmFor s)
  let a ← IO.Process.output { cmd := "as", args := #["-o", base ++ ".o", base ++ ".s"] }
  if a.exitCode != 0 then return .error s!"as failed: {a.stderr}"
  let l ← IO.Process.output { cmd := "ld", args := #[s!"--section-start=.dstack={X86.Emit.hex dBase}", "-o", base, base ++ ".o"] }
  if l.exitCode != 0 then return .error s!"ld failed: {l.stderr}"
  let child ← IO.Process.spawn { cmd := base, stdout := .piped, stderr := .null, stdin := .null }
  let bytes ← readAll child.stdout ByteArray.empty
  let code ← child.wait
  if code == 0 then
    match parseDump s bytes with
    | some r => return .ok r
    | none => return .error s!"malformed dump ({bytes.size} bytes)"
  else
    return .ok (.trap code.toNat)

def check (s : Sample) : IO Bool := do
  let exp := expected s
  match exp with
  | .timeout => IO.println s!"SKIP  {s.name} (IR did not terminate within fuel)"; return true
  | _ =>
    match ← runNative s with
    | .error e => IO.println s!"ERROR {s.name}: {e}"; return false
    | .ok got =>
      if got == exp then
        IO.println s!"PASS  {s.name}  {repr exp}"; return true
      else
        IO.println s!"FAIL  {s.name}\n  lean:   {repr exp}\n  native: {repr got}"; return false

/-! ## Programs from the frontends -/

def forthSample (name : String) (b : Forth.Block) (mem : List Nat := List.replicate 16 0) : Sample :=
  { name, prog := Forth.compileProgram b, mem }

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

def fuzz (count : Nat) : IO Bool := do
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
    match ← runNative s with
    | .error e => IO.println s!"ERROR fuzz_{i}: {e}"; ok := false
    | .ok got =>
      if got != exp then
        IO.println s!"FAIL  fuzz_{i}\n  lean:   {repr exp}\n  native: {repr got}"
        IO.FS.writeFile s!"{workDir}/fuzz_fail_{i}.txt" s!"{repr prog.length}"
        ok := false
  IO.println s!"fuzz: {count} programs, {skipped} skipped; halted {halts}; traps by code (1 underflow, 2 badaddr, 3 div0, 4 badpc, 5 ret) {traps.toList.drop 1}; max final depth {longest}; {if ok then "all agree" else "MISMATCH"}"
  return ok

def main (args : List String) : IO UInt32 := do
  match args with
  | ["emit", name] =>
    match (samplesFrontends ++ samplesRaw).find? (·.name == name) with
    | some s => IO.println (asmFor s); return 0
    | none => IO.eprintln "unknown sample"; return 1
  | "check" :: rest =>
    let count := match rest with | [n] => n.toNat! | _ => 200
    IO.setRandSeed 20260610
    let mut ok := true
    for s in samplesFrontends ++ samplesRaw do
      if !(← check s) then ok := false
    if !(← fuzz count) then ok := false
    return (if ok then 0 else 1)
  | _ => IO.eprintln "usage: wordc check [fuzzCount] | wordc emit <sample>"; return 2
