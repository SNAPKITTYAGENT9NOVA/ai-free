import Harness

/-!
# Harness32

The differential-testing harness at word width 32, shared by the two microcontroller profiles
(`rv32c`, `cmc`). A target supplies a `Runner32`: it runs a `Sample32` (an IR program at width 32
plus an initial memory image and register-file size) and reports the dumped final state or the
exit status of a trap. The harness runs the same program under the Lean semantics at width 32 and
compares.

* `narrow` turns the shared 64-bit samples and generated programs of `Harness` into 32-bit ones,
  so the same programs run on every target. The generator's edge values near `2^63` and `2^64`
  become the same edges near `2^31` and `2^32`; other values keep their low 32 bits.
* `samples32` adds cases specific to 32-bit words; `auxSamples32` and `overflowSamples32` are
  the auxiliary-stack and overflow programs; Forth source files are compiled directly at width 32
  (`forthFileSample32`).
* Both microcontroller runtimes print their halt dump as text, one word per line in eight
  hexadecimal digits (`parseHexDump`).
-/

open WordDialect

/-! ## Samples at width 32 -/

structure Sample32 where
  name : String
  prog : Prog 32
  mem : List Nat
  nregs : Nat := 4
  buildError : Option String := none

/-- A 64-bit word as a 32-bit one: the edge values of the generator (`Harness.edge`) near
`2^63` and `2^64` become the same edges near `2^31` and `2^32`; other values keep their low
32 bits. -/
def narrowWord (w : Word 64) : Word 32 :=
  let v := w.toNat
  if v = 2 ^ 63 - 1 then BitVec.ofNat 32 (2 ^ 31 - 1)
  else if v = 2 ^ 63 then BitVec.ofNat 32 (2 ^ 31)
  else if v = 2 ^ 63 + 1 then BitVec.ofNat 32 (2 ^ 31 + 1)
  else BitVec.ofNat 32 v

def narrowInstr : Instr 64 → Instr 32
  | .word w => .word (narrowWord w)
  | .ptr q => .ptr ⟨narrowWord q.addr⟩
  | .load => .load | .store => .store
  | .add => .add | .sub => .sub | .mul => .mul | .div => .div | .sdiv => .sdiv
  | .and => .and | .or => .or | .xor => .xor | .not => .not
  | .shl => .shl | .shr => .shr | .rotl => .rotl | .rotr => .rotr
  | .cmp c => .cmp c
  | .select => .select
  | .jmp t => .jmp t | .branch t => .branch t | .call t => .call t | .ret => .ret
  | .push r => .push r | .pop r => .pop r
  | .dup => .dup | .drop => .drop | .swap => .swap | .over => .over | .rot => .rot
  | .tor => .tor | .fromr => .fromr | .rfetch => .rfetch
  | .halt => .halt

def narrowMem (v : Nat) : Nat := (narrowWord (BitVec.ofNat 64 v)).toNat

def narrow (s : Sample) : Sample32 :=
  { name := s.name, prog := s.prog.map narrowInstr, mem := s.mem.map narrowMem, nregs := s.nregs,
    buildError := s.buildError }

def expected32 (s : Sample32) : Result :=
  match run s.prog 200000 (State.init (Memory.ofImage s.mem : Memory 32)) with
  | none => .timeout
  | some (.trapped t) => .trap (trapCode t)
  | some (.next _) => .timeout
  | some (.halted st) =>
    .halted (st.dstack.map (·.toNat))
      ((List.range s.mem.length).map fun a => (st.mem.cell (BitVec.ofNat 32 a)).toNat)
      ((List.range s.nregs).map fun r => (st.regs r).toNat)

/-- A target at width 32. -/
abbrev Runner32 := Sample32 → IO (Except String Result)

/-- The UART dump: one word per line, eight hexadecimal digits. -/
def hexWords (t : String) : Option (List Nat) :=
  ((t.splitOn "\n").filter (· ≠ "")).mapM fun l =>
    if l.length = 8 then
      l.foldl (fun acc ch => acc.bind fun v =>
        if '0' ≤ ch ∧ ch ≤ '9' then some (16 * v + (ch.toNat - '0'.toNat))
        else if 'a' ≤ ch ∧ ch ≤ 'f' then some (16 * v + (ch.toNat - 'a'.toNat + 10))
        else none) (some 0)
    else none

/-- A halt dump: depth, the data stack (top first), IR memory, the virtual registers. -/
def parseHexDump (s : Sample32) (out : String) : Except String Result :=
  match hexWords out with
  | some (depth :: rest) =>
    let m := s.mem.length
    if rest.length != depth + m + s.nregs then .error s!"malformed dump: {out}"
    else .ok (.halted (rest.take depth) ((rest.drop depth).take m) (rest.drop (depth + m)))
  | _ => .error s!"malformed dump: {out}"

def check32 (run : Runner32) (s : Sample32) : IO Bool := do
  if let some e := s.buildError then
    IO.println s!"ERROR {s.name}: {e}"; return false
  let exp := expected32 s
  if exp == .timeout then
    IO.println s!"SKIP  {s.name} (IR did not terminate within fuel)"; return true
  match ← run s with
  | .error e => IO.println s!"ERROR {s.name}: {e}"; return false
  | .ok got =>
    if got == exp then IO.println s!"PASS  {s.name}  {repr exp}"; return true
    else IO.println s!"FAIL  {s.name}\n  lean:   {repr exp}\n  target: {repr got}"; return false

/-! ## Samples specific to 32-bit words -/

def samples32 : List Sample32 :=
  [ { name := "w32_wrap", mem := [], nregs := 1,
      prog := [.word 0xffffffff, .word 1, .add, .word 0x7fffffff, .word 1, .add, .word 0x10000,
               .word 0x10000, .mul, .halt] }
  , { name := "w32_sdiv_intmin", mem := [], nregs := 1,
      prog := [.word 0x80000000, .word 0xffffffff, .sdiv, .word 0xfffffff9, .word 2, .sdiv, .halt] }
  , { name := "w32_shifts", mem := [], nregs := 1,
      prog := [.word 1, .word 31, .shl, .word 1, .word 32, .shl, .word 0x80000000, .word 31, .shr,
               .word 0x80000001, .word 1, .rotl, .word 0x80000001, .word 33, .rotr, .halt] }
  , { name := "w32_compare_signed", mem := [], nregs := 1,
      prog := [.word 0x80000000, .word 0x7fffffff, .cmp .slt, .word 0x80000000, .word 0x7fffffff,
               .cmp .ult, .halt] }
  , { name := "w32_memory", mem := [7, 0xffffffff, 3], nregs := 2,
      prog := [.word 1, .load, .word 2, .load, .add, .word 0, .store, .word 3, .load, .halt] }
    -- unsigned and signed division across signs and extremes (Cortex-M0 divides in software)
  , { name := "w32_div_extremes", mem := [], nregs := 1,
      prog := [.word 0xffffffff, .word 1, .div, .word 0xffffffff, .word 0xffffffff, .div,
               .word 0xfffffffe, .word 0xffffffff, .div, .word 0x80000000, .word 3, .div,
               .word 7, .word 0xfffffffe, .sdiv, .word 0xfffffff9, .word 2, .sdiv,
               .word 0xfffffff9, .word 0xfffffffe, .sdiv, .word 0x80000000, .word 1, .sdiv,
               .word 0x7fffffff, .word 0x80000000, .sdiv, .word 0x80000000, .word 0x80000000, .sdiv,
               .word 123456789, .word 1000, .div, .halt] }
    -- halts with values read from a non-zero memory image: the image must have reached RAM
  , { name := "w32_memory_image", mem := [7, 0xffffffff, 3, 0x12345678], nregs := 2,
      prog := [.word 1, .load, .word 2, .load, .add, .word 0, .store, .word 0, .load, .word 3,
               .load, .halt] } ]

/-- Programs that grow a stack without bound: the emitted code must stop with exit 6. -/
def overflowSamples32 : List Sample32 :=
  [ { name := "ovf_word_loop", prog := [.word 1, .jmp 0], mem := [] },
    { name := "ovf_dup_loop", prog := [.word 1, .dup, .jmp 1], mem := [] },
    { name := "ovf_call_loop", prog := [.call 0], mem := [] },
    { name := "ovf_tor_loop", prog := [.word 1, .tor, .jmp 0], mem := [] } ]

def auxSamples32 : List Sample32 :=
  [ { name := "aux_basic", mem := [], nregs := 1,
      prog := [.word 7, .tor, .word 3, .rfetch, .add, .fromr, .mul, .halt] }
  , { name := "aux_across_call", mem := [], nregs := 1,
      prog := [.word 100, .tor, .word 5, .call 7, .fromr, .add, .halt,
               .tor, .rfetch, .fromr, .mul, .ret] }
  , { name := "aux_fact_rec", mem := [], nregs := 1,
      prog := [.word 5, .call 3, .halt,
               .dup, .branch 8, .drop, .word 1, .ret,
               .dup, .tor, .word 1, .sub, .call 3, .fromr, .mul, .ret] }
  , { name := "aux_fromr_empty", mem := [], nregs := 1, prog := [.word 1, .fromr, .halt] }
  , { name := "aux_rfetch_empty", mem := [], nregs := 1, prog := [.rfetch, .halt] }
  , { name := "aux_ret_not_aux", mem := [], nregs := 1, prog := [.word 1, .tor, .ret] }
  , { name := "aux_tor_underflow", mem := [], nregs := 1, prog := [.tor, .halt] } ]

def checkOverflow32 (run : Runner32) : IO Bool := do
  let mut ok := true
  for s in overflowSamples32 do
    match ← run s with
    | .ok (.trap 6) => IO.println s!"PASS  {s.name}  overflow exit 6"
    | .ok got => IO.println s!"FAIL  {s.name}  expected overflow exit 6, got {repr got}"; ok := false
    | .error e => IO.println s!"ERROR {s.name}: {e}"; ok := false
  return ok

/-- The shared generated programs, narrowed to 32 bits. -/
def fuzz32 (run : Runner32) (count : Nat) : IO Bool := do
  let mut ok := true
  let mut skipped := 0
  let mut halts := 0
  let mut traps : Array Nat := #[0, 0, 0, 0, 0, 0]
  for i in List.range count do
    let len ← IO.rand 4 40
    let prog ← genProg len
    let mem ← (List.range 16).mapM fun _ => randWord
    let s := narrow { name := s!"fuzz_{i}", prog, mem, nregs := 4 }
    let exp := expected32 s
    match exp with
    | .halted .. => halts := halts + 1
    | .trap c => traps := traps.set! c (traps[c]! + 1)
    | .timeout => skipped := skipped + 1
    if exp == .timeout then continue
    match ← run s with
    | .error e => IO.println s!"ERROR fuzz_{i}: {e}"; ok := false
    | .ok got =>
      if got != exp then
        IO.println s!"FAIL  fuzz_{i}\n  lean:   {repr exp}\n  target: {repr got}"; ok := false
  IO.println s!"fuzz: {count} programs, {skipped} skipped; halted {halts}; traps by code (1 underflow, 2 badaddr, 3 div0, 4 badpc, 5 ret) {traps.toList.drop 1}; {if ok then "all agree" else "MISMATCH"}"
  return ok

/-- A Forth source file compiled at width 32, with `memWords` zero words of IR memory. -/
def forthFileSample32 (path : String) (memWords : Nat) : IO Sample32 := do
  let src ← IO.FS.readFile path
  let name := (System.FilePath.mk path).fileStem.getD "forth"
  let mem := List.replicate memWords 0
  match Forth.parse src with
  | .ok P => return { name, prog := P.compile, mem := mem ++ List.replicate (P.vars - mem.length) 0,
                      nregs := forthRegs }
  | .error e => return { name, prog := [], mem, buildError := some s!"Forth parse error: {e}" }

def allSamples32 : List Sample32 := allSamples.map narrow ++ samples32 ++ auxSamples32

/-- Every fixed sample, `count` generated programs, and the overflow programs. -/
def checkAll32 (run : Runner32) (count : Nat) : IO Bool := do
  IO.setRandSeed 20260610
  let mut ok := true
  for s in allSamples32 do
    if !(← check32 run s) then ok := false
  let fz ← fuzz32 run count
  let ovf ← checkOverflow32 run
  return ok && fz && ovf
