import CM.Lower

/-!
# CM.Emit

Assembly text (Thumb-2, unified syntax, as accepted by `clang --target=thumbv7m-none-eabi`) for a
lowered program, plus the small bare-metal runtime.

The program text is produced from exactly the instruction list `lowerProg` builds, one
`.L<index>:` label per model instruction, so the text and the verified model cannot diverge.
A model instruction is one Thumb-2 instruction, except the fixed sequences documented in
`CM.Isa` (`movImm` as `movw`/`movt`, conditional branches as `cmp` and the opposite branch over
a `b.w`, `sltiu` as `cmp` and an `ite` block, `call`, `ret`). An immediate or displacement outside
what the encoding accepts is printed as an `.error` directive, so the assembler rejects the
program instead of emitting something else.

The image runs from flash. It starts with the Cortex-M vector table (initial stack pointer and
reset vector); code and the vector table stay in flash, and `.data` (IR memory, register file)
is linked to RAM with its load address in flash. There is no operating system. The reset handler
* copies `.data` from flash to RAM with the loop `copyCode`, which is printed from the model like
  the lowered program and proved in `CM/Boot.lean`,
* then runs the prologue, which sets `r4 … r9` to the conventions in `CM.Lower`, with the return
  stack in the `.rstack` section.

The rest of the runtime (`epilogue`) is hand-written assembly. It
* implements `exitHalt` as: write `depth`, the data stack, IR memory and the virtual register
  file to the UART (a PL011, UART0 of the Stellaris LM3S6965 at `uartBase`, polling its
  transmit-full flag), one word per line as eight hexadecimal digits, then stop with status 0,
* implements `exitTrap t` as stopping with status `code t`, and `exitOvf` (stack overflow) with
  status 6.

The machine is stopped through semihosting (`bkpt 0xab`, operation `SYS_EXIT_EXTENDED`), which
the emulator and debug probes implement; on a board running without a debugger, that one stub is
replaced by whatever signals the end of a run. The lowered code itself uses no device.
-/

namespace WordDialect
namespace CM
namespace Emit

open Reg

def trapCode : Trap → Nat
  | .stackUnderflow => 1
  | .badAddress => 2
  | .divideByZero => 3
  | .badPc => 4
  | .returnUnderflow => 5

def regName : Reg → String
  | .r0 => "r0" | .r1 => "r1" | .r2 => "r2" | .r3 => "r3" | .r4 => "r4" | .r5 => "r5"
  | .r6 => "r6" | .r7 => "r7" | .r8 => "r8" | .r9 => "r9" | .r10 => "r10" | .r11 => "r11"
  | .r12 => "r12" | .lr => "lr"

def aluName : Alu → String
  | .add => "add" | .sub => "sub" | .mul => "mul" | .and => "and" | .orr => "orr"
  | .eor => "eor" | .lsl => "lsl" | .lsr => "lsr" | .asr => "asr"

def shiftName : Shift → String
  | .lsl => "lsl" | .lsr => "lsr" | .asr => "asr"

def hex (n : Nat) : String := "0x" ++ String.ofList (Nat.toDigits 16 n)

/-- The label of model instruction `t` of a code list printed with label prefix `p`. -/
def lblP (p : String) (t : Nat) : String := s!".L{p}{t}"

def lbl (t : Nat) : String := lblP "" t

def err (msg : String) : String := s!".error \"{msg}\""

/-- `movw`/`movt` of a 32-bit constant (the model's `movImm`). -/
def li (d : String) (v : Nat) : String :=
  s!"movw {d}, #{hex (v % 65536)}\n\tmovt {d}, #{hex (v / 65536 % 65536)}"

/-- `movw`/`movt` of a symbol's address. -/
def la (d sym : String) : String :=
  s!"movw {d}, #:lower16:{sym}\n\tmovt {d}, #:upper16:{sym}"

/-- `ldr`/`str` with an immediate offset: `-255 … 4095`. -/
def ldst (op : String) (r b : Reg) (disp : Int) : String :=
  if -255 ≤ disp ∧ disp < 4096 then s!"{op} {regName r}, [{regName b}, #{disp}]"
  else err s!"displacement {disp} out of range"

def bin (op : String) (d s : Reg) : String := s!"{op} {regName d}, {regName d}, {regName s}"

/-- The condition code under which `cmp a, b` makes `c.eval a b` hold. -/
def condName : Cond → String
  | .eq => "eq" | .ne => "ne" | .ult => "lo" | .uge => "hs" | .ugt => "hi" | .ule => "ls"
  | .slt => "lt" | .sge => "ge" | .sgt => "gt" | .sle => "le"

/-- The negation of `c`, so a far branch can skip over a `b.w`. -/
def condNot : Cond → Cond
  | .eq => .ne | .ne => .eq | .ult => .uge | .uge => .ult | .ugt => .ule | .ule => .ugt
  | .slt => .sge | .sge => .slt | .sgt => .sle | .sle => .sgt

/-- Branch to `t` when `c` holds after `cmp`: the opposite branch over a `b.w`. -/
def farBranch (p : String) (k : Nat) (cmp : String) (c : Cond) (t : Nat) : String :=
  s!"{cmp}\n\tb{condName (condNot c)} .Ls{p}{k}\n\tb.w {lblP p t}\n.Ls{p}{k}:"

/-- The text of model instruction `k` of a code list printed with label prefix `p` (the lowered
program uses `""`, the start-up copy loop `"c"`). -/
def instrP (p : String) (k : Nat) : Instr Nat → String
  | .movImm d v => li (regName d) v.toNat
  | .movRR d s => s!"mov {regName d}, {regName s}"
  | .load d b disp => ldst "ldr" d b disp
  | .store b disp s => ldst "str" s b disp
  | .add d s => bin "add" d s
  | .sub d s => bin "sub" d s
  | .mul d s => bin "mul" d s
  | .and d s => bin "and" d s
  | .or d s => bin "orr" d s
  | .xor d s => bin "eor" d s
  | .addImm d v =>
    if 0 ≤ v ∧ v < 4096 then s!"addw {regName d}, {regName d}, #{v}"
    else if -4096 < v ∧ v < 0 then s!"subw {regName d}, {regName d}, #{-v}"
    else err s!"immediate {v} out of range"
  | .shlImm d k => if k < 32 then s!"lsl {regName d}, {regName d}, #{k}" else err s!"shift {k}"
  | .sltiu d s k =>
    if k < 256 then
      s!"cmp {regName s}, #{k}\n\tite lo\n\tmovlo {regName d}, #1\n\tmovhs {regName d}, #0"
    else err s!"immediate {k} out of range"
  | .not d => s!"mvn {regName d}, {regName d}"
  | .neg d => s!"rsb {regName d}, {regName d}, #0"
  | .lsl d s => bin "lsl" d s
  | .lsr d s => bin "lsr" d s
  | .ror d s => bin "ror" d s
  | .divu d a b => s!"udiv {regName d}, {regName a}, {regName b}"
  | .div d a b => s!"sdiv {regName d}, {regName a}, {regName b}"
  | .alu op d a b => s!"{aluName op} {regName d}, {regName a}, {regName b}"
  | .shiftImm sh d a n =>
    -- `lsr`/`asr` by `#0` do not exist (that encoding means 32); a shift by 0 is a move
    if n = 0 then s!"mov {regName d}, {regName a}"
    else if n < 32 then s!"{shiftName sh} {regName d}, {regName a}, #{n}" else err s!"shift {n}"
  | .bcc c a b t => farBranch p k s!"cmp {regName a}, {regName b}" c t
  | .beqz a t => farBranch p k s!"cmp {regName a}, #0" .eq t
  | .bnez a t => farBranch p k s!"cmp {regName a}, #0" .ne t
  | .jmp t => s!"b.w {lblP p t}"
  | .call t =>
    s!"{la "lr" s!"({lblP p (k + 1)} + 1)"}\n\tstr lr, [r8, #-4]!\n\tb.w {lblP p t}"
  | .ret => "ldr lr, [r8], #4\n\tbx lr"
  | .exitHalt => "b.w .Lhalt"
  | .exitTrap t => s!"b.w .Ltrap{trapCode t}"
  | .exitOvf => "b.w .Ltrap6"

def instr (k : Nat) (i : Instr Nat) : String := instrP "" k i

def body (code : List (Instr Nat)) : String :=
  String.intercalate "\n" (code.zipIdx.map fun (i, k) => s!"{lbl k}:\n\t{instr k i}") ++ "\n"

/-- Data-stack placement (`capacity` words ending at `dEnd`), return-stack placement (`rcap`
entries ending at `rEnd`), IR memory image, register-file size, auxiliary-stack placement
(`acap` words ending at `aEnd`), the initial stack pointer of the vector table (used only by
exception entry; the lowered code does not use `sp`), and the address of the PL011 UART. The three stacks
are sections the linker places at fixed addresses (`cmc` uses a linker script). -/
structure Runtime where
  dEnd : Nat
  capacity : Nat
  rEnd : Nat
  rcap : Nat
  memImage : List Nat
  nregs : Nat
  aEnd : Nat
  acap : Nat
  spInit : Nat := 0x20010000
  uartBase : Nat := 0x4000C000

def Runtime.dBase (r : Runtime) : Nat := r.dEnd - 4 * r.capacity

def Runtime.rBase (r : Runtime) : Nat := r.rEnd - 4 * r.rcap

def Runtime.aBase (r : Runtime) : Nat := r.aEnd - 4 * r.acap

/-- The lowering's view of the runtime: the constants the guards and bounds checks use. -/
def Runtime.layout (r : Runtime) : Layout :=
  { dEnd := BitVec.ofNat 32 r.dEnd, memSize := r.memImage.length,
    dLim := BitVec.ofNat 32 (r.dBase + 4), rGap := BitVec.ofNat 32 (4 * r.rcap - 8),
    aEnd := BitVec.ofNat 32 r.aEnd, aLim := BitVec.ofNat 32 (r.aBase + 4) }

/-- Assembler directives and the vector table: initial stack pointer and reset vector. -/
def vectors (r : Runtime) : String :=
  "\t.syntax unified\n\t.thumb\n\t.section .vectors, \"a\"\n" ++
  s!"\t.word {hex r.spInit}\n\t.word _start\n"

/-- The `.data` image: IR memory, the register file (`nregs + 1` words) and the two-word
semihosting parameter block, in the order `epilogue` lays them out. The image is linked into
flash and copied to RAM at reset. -/
def dataImage (r : Runtime) : List Nat := r.memImage ++ List.replicate (r.nregs + 3) 0

def dataWords (r : Runtime) : Nat := (dataImage r).length

/-- The start-up copy loop: copy `n` words from `lma` (flash) to `vma` (RAM). Model indices
`0 … 9`; it falls through to index 10, where the prologue starts. -/
def copyCode (lma vma : W) (n : Nat) : List (Instr Nat) :=
  [.movImm .r1 lma, .movImm .r2 vma, .movImm .r3 (BitVec.ofNat 32 n), .beqz .r3 10,
   .load .r0 .r1 0, .store .r2 0 .r0, .addImm .r1 4, .addImm .r2 4, .addImm .r3 (-1),
   .bnez .r3 4]

/-- The text of the copy loop: `copyCode` printed with label prefix `c`, the two addresses as the
symbols the linker resolves (`__data_load`, the load address of `.data` in flash, and `irmem`,
its start in RAM). Its model is `copyCode` with those two addresses (`CM/Boot.lean`). -/
def copyText (r : Runtime) : String :=
  let code := copyCode 0 0 (dataWords r)
  s!".Lc0:\n\t{la "r1" "__data_load"}\n.Lc1:\n\t{la "r2" "irmem"}\n" ++
  String.join ((code.zipIdx.drop 2).map fun (i, k) => s!"{lblP "c" k}:\n\t{instrP "c" k i}\n") ++
  ".Lc10:\n"

/-- The reset handler: the copy loop, then the prologue. The prologue's model is
`CM.Emit.prologueCode` (`CM/Init.lean`), where each address is the `movImm` of the address the
linker resolves the symbol to; keep the two in step. -/
def prologue (r : Runtime) : String :=
  vectors r ++ "\t.text\n\t.globl _start\n\t.thumb_func\n_start:\n" ++ copyText r ++
  s!"\t{li "r7" r.rEnd}\n\tmov r8, r7\n\t{la "r6" "irmem"}\n\t{la "r5" "regfile"}\n" ++
  s!"\t{li "r4" r.dEnd}\n\t{li "r9" r.aEnd}\n"

/-- Output and exit routines, entered only from `exitHalt`, `exitTrap` and `exitOvf`, so they
may use any register. `putc` writes `r3` to the UART; `putw` writes `r0` as eight hexadecimal
digits and a newline; `putws` writes the `r9` words at address `r7`. `.Lexit` stops the machine
through semihosting with status `r1`. -/
def devices (r : Runtime) : String :=
  "\t.thumb_func\nputc:\n" ++
  s!"\t{li "r12" r.uartBase}\n" ++
  "1:\tldr r11, [r12, #0x18]\n\ttst r11, #0x20\n\tbne 1b\n\tstr r3, [r12]\n\tbx lr\n" ++
  "\t.thumb_func\nputw:\n\tmov r10, lr\n\tmovs r1, #28\n" ++
  "2:\tlsr r2, r0, r1\n\tand r2, r2, #15\n\tcmp r2, #10\n\tite lo\n" ++
  "\taddlo r3, r2, #48\n\taddhs r3, r2, #87\n\tbl putc\n" ++
  "\tsubs r1, r1, #4\n\tbpl 2b\n\tmovs r3, #10\n\tbl putc\n\tbx r10\n" ++
  "\t.thumb_func\nputws:\n\tmov r8, lr\n" ++
  "5:\tcmp r9, #0\n\tbeq 6f\n\tldr r0, [r7], #4\n\tbl putw\n\tsubs r9, r9, #1\n\tb 5b\n" ++
  "6:\tbx r8\n" ++
  s!".Lexit:\n\t{la "r0" "exitblk"}\n\t{li "r2" 0x20026}\n" ++
  "\tstr r2, [r0]\n\tstr r1, [r0, #4]\n\tmov r1, r0\n\tmovs r0, #0x20\n\tbkpt 0xab\n7:\tb 7b\n"

/-- Turn on UART0: its clock (`RCGC1`, bit 0, in the Stellaris system control block) and the
UART with its transmitter (`UARTCTL = UARTEN | TXE | RXE`). The baud rate is left at its reset
divisor; the emulator ignores it. -/
def uartOn (r : Runtime) : String :=
  s!"\t{li "r12" 0x400FE104}\n\tldr r11, [r12]\n\torr r11, r11, #1\n\tstr r11, [r12]\n" ++
  s!"\t{li "r12" r.uartBase}\n\tmovw r11, #0x301\n\tstr r11, [r12, #0x30]\n"

def epilogue (r : Runtime) : String :=
  let m := r.memImage.length
  ".Lhalt:\n" ++ uartOn r ++
  s!"\t{li "r0" r.dEnd}\n\tsub r0, r0, r4\n\tlsr r0, r0, #2\n\tmov r9, r0\n\tbl putw\n" ++
  "\tmov r7, r4\n\tbl putws\n" ++
  s!"\t{la "r7" "irmem"}\n\t{li "r9" m}\n\tbl putws\n" ++
  s!"\t{la "r7" "regfile"}\n\t{li "r9" r.nregs}\n\tbl putws\n" ++
  "\tmovs r1, #0\n\tb .Lexit\n" ++
  String.join ((List.range 6).map fun k => s!".Ltrap{k + 1}:\n\tmovs r1, #{k + 1}\n\tb .Lexit\n") ++
  devices r ++ "\t.ltorg\n" ++
  "\t.data\n\t.balign 4\nirmem:\n" ++
  String.join (r.memImage.map fun v => s!"\t.word {v % 2 ^ 32}\n") ++
  "regfile:\n" ++ s!"\t.zero {4 * (r.nregs + 1)}\n" ++ "exitblk:\n\t.word 0, 0\n" ++
  "\t.section .dstack, \"aw\", %nobits\n\t.balign 4\n" ++
  s!"\t.skip {4 * r.capacity}\n" ++
  "\t.section .rstack, \"aw\", %nobits\n\t.balign 4\n" ++
  s!"\t.skip {4 * r.rcap}\n" ++
  "\t.section .astack, \"aw\", %nobits\n\t.balign 4\n" ++
  s!"\t.skip {4 * r.acap}\n"

/-- Full assembly text for a lowered program. -/
def program (r : Runtime) (code : List (Instr Nat)) : String :=
  prologue r ++ body code ++ epilogue r

end Emit
end CM
end WordDialect
