import CM0.Lower

/-!
# CM0.Emit

Assembly text (ARMv6-M Thumb, unified syntax, as accepted by `clang --target=thumbv6m-none-eabi`)
for a lowered program, plus the small bare-metal runtime.

The program text is produced from exactly the instruction list `lowerProg` builds, one
`.L<index>:` label per model instruction, so the text and the verified model cannot diverge.
A model instruction is one Thumb instruction, except the fixed sequences documented in `CM0.Isa`
(`movImm` built from bytes, branches as `bl`, `sltiu`, `call`). An operand outside what an
ARMv6-M encoding accepts (a high register where only low ones are allowed, an offset beyond
124, an immediate beyond 255) is printed as an `.error` directive, so the assembler rejects the
program instead of emitting something else.

The image runs from flash, as on the Cortex-M3 profile. The reset handler copies `.data` to
RAM with `copyCode` (proved in `CM0/Boot.lean`), runs the prologue, then jumps over a literal
pool to the lowered code. The rest of the runtime (`epilogue`) is hand-written assembly. It
* implements `exitHalt` as: write `depth`, the data stack, IR memory and the virtual register
  file to the UART (the nRF51 UART at `uartBase`, waiting for `EVENTS_TXDRDY` after each byte),
  one word per line as eight hexadecimal digits, then end with status 0,
* implements `exitTrap t` as ending with status `code t`, and `exitOvf` (stack overflow) with
  status 6.

A run ends on the UART, the same way on the emulator and on a board, with no debugger: after the
dump (if any) the runtime prints a line `EXIT` and the status, stores the status at `exitblk`, and
sleeps. Before printing it starts the crystal and sets up the UART as a board needs (`uartInit`).
-/

namespace WordDialect
namespace CM0
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
  | .r6 => "r6" | .r7 => "r7" | .r8 => "r8" | .r9 => "r9" | .r10 => "r10" | .sp => "sp"

/-- `r0 … r7`: the registers most ARMv6-M instructions accept. -/
def isLow : Reg → Bool
  | .r0 | .r1 | .r2 | .r3 | .r4 | .r5 | .r6 | .r7 => true
  | _ => false

def hex (n : Nat) : String := "0x" ++ String.ofList (Nat.toDigits 16 n)

/-- The label of model instruction `t` of a code list printed with label prefix `p`. -/
def lblP (p : String) (t : Nat) : String := s!".L{p}{t}"

def lbl (t : Nat) : String := lblP "" t

def err (msg : String) : String := s!".error \"{msg}\""

/-- A 32-bit constant in a low register: its most significant non-zero byte with `movs`, then
for each lower byte `lsls #8` and, unless the byte is zero, `adds`. -/
def li (d : String) (v : Nat) : String :=
  let bytes := [v / 2 ^ 24 % 256, v / 2 ^ 16 % 256, v / 2 ^ 8 % 256, v % 256]
  let rest := bytes.dropWhile (· == 0)
  match rest with
  | [] => s!"movs {d}, #0"
  | b :: bs =>
    s!"movs {d}, #{b}" ++ String.join (bs.map fun x =>
      s!"\n\tlsls {d}, {d}, #8" ++ (if x == 0 then "" else s!"\n\tadds {d}, #{x}"))

/-- A symbol's address, from a literal word the linker fills in. -/
def la (d sym : String) : String := s!"ldr {d}, ={sym}"

/-- `ldr`/`str` with an immediate offset: low registers, offsets `0 … 124` in steps of 4. -/
def ldst (op : String) (r b : Reg) (disp : Int) : String :=
  if isLow r ∧ isLow b ∧ 0 ≤ disp ∧ disp ≤ 124 ∧ disp % 4 = 0 then
    s!"{op} {regName r}, [{regName b}, #{disp}]"
  else err s!"{op} operands out of range"

/-- A two-operand data-processing instruction on low registers. -/
def lowOp (op : String) (d s : Reg) : String :=
  if isLow d ∧ isLow s then s!"{op} {regName d}, {regName s}" else err s!"{op} needs low registers"

/-- The condition code under which `cmp a, b` makes `c.eval a b` hold. -/
def condName : Cond → String
  | .eq => "eq" | .ne => "ne" | .ult => "lo" | .uge => "hs" | .ugt => "hi" | .ule => "ls"
  | .slt => "lt" | .sge => "ge" | .sgt => "gt" | .sle => "le"

/-- The negation of `c`, so a branch can skip over a `bl`. -/
def condNot : Cond → Cond
  | .eq => .ne | .ne => .eq | .ult => .uge | .uge => .ult | .ugt => .ule | .ule => .ugt
  | .slt => .sge | .sge => .slt | .sgt => .sle | .sle => .sgt

/-- Branch to `t` when `c` holds after `cmp`: the opposite conditional branch over a `bl`. -/
def farBranch (p : String) (k : Nat) (cmp : String) (c : Cond) (t : Nat) : String :=
  s!"{cmp}\n\tb{condName (condNot c)} .Ls{p}{k}\n\tbl {lblP p t}\n.Ls{p}{k}:"

/-- The text of model instruction `k` of a code list printed with label prefix `p` (the lowered
program uses `""`, the start-up copy loop `"c"`). -/
def instrP (p : String) (k : Nat) : Instr Nat → String
  | .movImm d v => if isLow d then li (regName d) v.toNat else err "movImm needs a low register"
  | .movRR d s => s!"mov {regName d}, {regName s}"
  | .load d b disp => ldst "ldr" d b disp
  | .store b disp s => ldst "str" s b disp
  | .add d s =>
    if isLow d ∧ isLow s then s!"adds {regName d}, {regName d}, {regName s}"
    else if d ≠ .sp ∧ s ≠ .sp then s!"add {regName d}, {regName s}" else err "add with sp"
  | .sub d s =>
    if isLow d ∧ isLow s then s!"subs {regName d}, {regName d}, {regName s}"
    else err "sub needs low registers"
  | .mul d s =>
    if isLow d ∧ isLow s then s!"muls {regName d}, {regName s}, {regName d}"
    else err "mul needs low registers"
  | .and d s => lowOp "ands" d s
  | .or d s => lowOp "orrs" d s
  | .xor d s => lowOp "eors" d s
  | .addImm d v =>
    if ¬ isLow d then err "addImm needs a low register"
    else if 0 ≤ v ∧ v < 256 then s!"adds {regName d}, #{v}"
    else if -256 < v ∧ v < 0 then s!"subs {regName d}, #{-v}"
    else err s!"immediate {v} out of range"
  | .shlImm d k =>
    if isLow d ∧ k < 32 then s!"lsls {regName d}, {regName d}, #{k}" else err s!"shift {k}"
  | .not d => if isLow d then s!"mvns {regName d}, {regName d}" else err "mvn needs a low register"
  | .neg d => if isLow d then s!"rsbs {regName d}, {regName d}, #0" else err "neg needs a low register"
  | .sltiu d s k =>
    if isLow d ∧ isLow s ∧ d ≠ s ∧ k < 256 then
      s!"movs {regName d}, #0\n\tcmp {regName s}, #{k}\n\tbhs 1f\n\tmovs {regName d}, #1\n1:"
    else err "sltiu operands out of range"
  | .lsl d s => lowOp "lsls" d s
  | .lsr d s => lowOp "lsrs" d s
  | .ror d s => lowOp "rors" d s
  | .bcc c a b t => farBranch p k s!"cmp {regName a}, {regName b}" c t
  | .beqz a t =>
    if isLow a then farBranch p k s!"cmp {regName a}, #0" .eq t else err "beqz needs a low register"
  | .bnez a t =>
    if isLow a then farBranch p k s!"cmp {regName a}, #0" .ne t else err "bnez needs a low register"
  | .jmp t => s!"bl {lblP p t}"
  | .call t => s!"b 2f\n1:\tpush \{lr}\n\tbl {lblP p t}\n2:\tbl 1b"
  | .ret => "pop {pc}"
  | .exitHalt => "bl .Lhalt"
  | .exitTrap t => s!"bl .Ltrap{trapCode t}"
  | .exitOvf => "bl .Ltrap6"

def instr (k : Nat) (i : Instr Nat) : String := instrP "" k i

def body (code : List (Instr Nat)) : String :=
  String.intercalate "\n" (code.zipIdx.map fun (i, k) => s!"{lbl k}:\n\t{instr k i}") ++ "\n"

/-- The chip family the runtime's device code is written for. The lowered program and its proofs
do not depend on it; only the hand-written set-up, output and end-of-run code does. -/
inductive Soc where
  /-- Nordic nRF51/nRF52 (BBC micro:bit): the UART at `uartBase`. -/
  | nrf
  /-- Microchip SAM D21 (SAM D21 Curiosity Nano, `ATSAMD21G17D`): SERCOM5 as a USART on
  PA22 (TX, pad 0) and PB22 (RX, pad 2), the debugger's virtual COM port; the yellow LED on PB10;
  the switch SW0 on PB11. -/
  | samd21
  deriving DecidableEq, Repr

/-- Data-stack placement (`capacity` words ending at `dEnd`), return-stack placement (`rcap`
entries ending at `rEnd`, the stack `sp` points into), IR memory image, register-file size,
auxiliary-stack placement (`acap` words ending at `aEnd`), the UART address and its pins. The three
stacks are sections the linker places at fixed addresses (`cm0c` uses a linker script). -/
structure Runtime where
  dEnd : Nat
  capacity : Nat
  rEnd : Nat
  rcap : Nat
  memImage : List Nat
  nregs : Nat
  aEnd : Nat
  acap : Nat
  uartBase : Nat := 0x40002000
  /-- The UART pins as the nRF `PSEL` registers take them, and the TX pin's number in GPIO
  port 0. The defaults are the BBC micro:bit V1's (TX P0.24, RX P0.25). -/
  txPin : Nat := 24
  rxPsel : Nat := 25
  /-- The chip family of the board (see `Soc`). -/
  soc : Soc := .nrf
  /-- The stack-depth certificate the code is lowered with (`WordDialect.Depth`); the driver
  passes `safeCert` of the program. The default claims nothing and keeps every guard. -/
  cert : Nat → Nat := fun _ => 0
  /-- The upper bound on the data-stack depth the code is lowered with; the driver passes
  `upperTable` of the program against `dCap` (`WordDialect.Depth`). An overflow guard is left out
  where `ub k + 1 ≤ dCap`; the default (`2^32` everywhere) shows no room, so every guard stays. -/
  ub : Nat → Nat := fun _ => 2 ^ 32

def Runtime.dBase (r : Runtime) : Nat := r.dEnd - 4 * r.capacity

def Runtime.rBase (r : Runtime) : Nat := r.rEnd - 4 * r.rcap

def Runtime.aBase (r : Runtime) : Nat := r.aEnd - 4 * r.acap

/-- The data stack's capacity in words. -/
def Runtime.dCap (r : Runtime) : Nat := (r.dEnd - r.dBase) / 4

/-- The lowering's view of the runtime: the constants the guards and bounds checks use. -/
def Runtime.layout (r : Runtime) : Layout :=
  { dEnd := BitVec.ofNat 32 r.dEnd, memSize := r.memImage.length,
    dLim := BitVec.ofNat 32 (r.dBase + 4), rGap := BitVec.ofNat 32 (4 * r.rcap - 8),
    aEnd := BitVec.ofNat 32 r.aEnd, aLim := BitVec.ofNat 32 (r.aBase + 4), cert := r.cert,
    ub := r.ub, dCap := r.dCap }

/-- The `.data` image: IR memory, the register file (`nregs + 1` words) and the two-word
status block `exitblk`, in the order `epilogue` lays them out. The image is linked into
flash and copied to RAM at reset. -/
def dataImage (r : Runtime) : List Nat := r.memImage ++ List.replicate (r.nregs + 3) 0

def dataWords (r : Runtime) : Nat := (dataImage r).length

/-- The start-up copy loop: copy `n` words from `lma` (flash) to `vma` (RAM). Model indices
`0 … 9`; it falls through to index 10, where the prologue starts. -/
def copyCode (lma vma : W) (n : Nat) : List (Instr Nat) :=
  [.movImm .r1 lma, .movImm .r2 vma, .movImm .r3 (BitVec.ofNat 32 n), .beqz .r3 10,
   .load .r0 .r1 0, .store .r2 0 .r0, .addImm .r1 4, .addImm .r2 4, .addImm .r3 (-1),
   .bnez .r3 4]

/-- The text of the copy loop: `copyCode` printed with label prefix `c`, the two addresses
loaded from literal words the linker fills in (`__data_load`, the load address of `.data` in
flash, and `irmem`, its start in RAM). Its model is `copyCode` with those two addresses
(`CM0/Boot.lean`). -/
def copyText (r : Runtime) : String :=
  let code := copyCode 0 0 (dataWords r)
  s!".Lc0:\n\t{la "r1" "__data_load"}\n.Lc1:\n\t{la "r2" "irmem"}\n" ++
  String.join ((code.zipIdx.drop 2).map fun (i, k) => s!"{lblP "c" k}:\n\t{instrP "c" k i}\n") ++
  ".Lc10:\n"

/-- Assembler directives and the vector table: initial stack pointer (the empty return stack)
and reset vector. -/
def vectors (r : Runtime) : String :=
  "\t.syntax unified\n\t.thumb\n\t.section .vectors, \"a\"\n" ++
  s!"\t.word {hex r.rEnd}\n\t.word _start\n"

/-- The reset handler: the copy loop, the prologue, then a jump over the literal pool to the
lowered code. The prologue's model is `CM0.Emit.prologueCode` (`CM0/Init.lean`); keep the two
in step. -/
def prologue (r : Runtime) : String :=
  vectors r ++ "\t.text\n\t.globl _start\n\t.thumb_func\n_start:\n" ++ copyText r ++
  s!"\t{li "r0" r.rEnd}\n\tmov r9, r0\n\tmov sp, r0\n\t{la "r0" "irmem"}\n\tmov r8, r0\n" ++
  s!"\t{la "r5" "regfile"}\n\t{li "r4" r.dEnd}\n\t{li "r6" r.aEnd}\n" ++
  "\tb .L0\n\t.ltorg\n"

/-- Bring up the UART as a board needs it (the emulator needs none of it): start the 16 MHz
crystal (`TASKS_HFCLKSTART`, waiting a bounded time for `EVENTS_HFCLKSTARTED`, since the
internal RC oscillator is too loose for a serial line), make the TX pin an output that idles
high, select the pins, set 115200 baud (`BAUDRATE = 0x01D7E000`), enable the UART and start
its transmitter. Uses `r0 … r3`. -/
def uartInit (r : Runtime) : String :=
  "\t.thumb_func\nuart_init:\n" ++
  s!"\t{la "r2" "0x40000000"}\n\tmovs r3, #1\n\tstr r3, [r2]\n" ++
  s!"\t{la "r1" "0x100000"}\n\t{la "r0" "0x100"}\n" ++
  "9:\tldr r3, [r2, r0]\n\tcmp r3, #0\n\tbne 8f\n\tsubs r1, #1\n\tbne 9b\n8:\n" ++
  s!"\t{la "r2" "0x50000000"}\n\t{la "r0" "0x508"}\n\t{la "r3" (hex (2 ^ r.txPin))}\n\tstr r3, [r2, r0]\n" ++
  s!"\t{la "r0" (hex (0x700 + 4 * r.txPin))}\n\tmovs r3, #1\n\tstr r3, [r2, r0]\n" ++
  s!"\t{la "r2" (hex r.uartBase)}\n" ++
  s!"\t{la "r0" "0x50C"}\n\t{la "r3" (hex r.txPin)}\n\tstr r3, [r2, r0]\n" ++
  s!"\t{la "r0" "0x514"}\n\t{la "r3" (hex r.rxPsel)}\n\tstr r3, [r2, r0]\n" ++
  s!"\t{la "r0" "0x524"}\n\t{la "r3" "0x01D7E000"}\n\tstr r3, [r2, r0]\n" ++
  s!"\t{la "r0" "0x500"}\n\tmovs r3, #4\n\tstr r3, [r2, r0]\n" ++
  "\tmovs r3, #1\n\tstr r3, [r2, #8]\n\tbx lr\n"

/-- SAM D21 bring-up (register addresses and fields from the SAM D21/DA1 data sheet,
DS40001882G): run the CPU and GCLK generator 0 from the 8 MHz internal oscillator undivided
(`SYSCTRL.OSC8M.PRESC := 0`; at reset it is divided by 8, too slow for 115200 baud), clock
SERCOM5 (`PM.APBCMASK` bit 7, `GCLK.CLKCTRL := CLKEN | GEN0 | ID 0x19`), hand PA22 and PB22 to
peripheral function D (SERCOM5 pads 0 and 2), and make SERCOM5 a USART with the internal clock,
LSB first, TX on pad 0, RX on pad 2, 16x oversampling, 8 data bits, no parity, one stop bit,
`BAUD = 65536 · (1 - 16 · 115200 / 8000000) = 50436`. Waits are bounded. Uses `r0 … r3`. -/
def uartInitSamd21 : String :=
  "\t.thumb_func\nuart_init:\n" ++
  -- SYSCTRL.OSC8M (0x40000820): clear PRESC (bits 9:8)
  s!"\t{la "r2" "0x40000800"}\n\tldr r3, [r2, #0x20]\n\t{la "r1" "0x300"}\n\tbics r3, r1\n\tstr r3, [r2, #0x20]\n" ++
  -- PM.APBCMASK (0x40000420): SERCOM5 clock on
  s!"\t{la "r2" "0x40000400"}\n\tldr r3, [r2, #0x20]\n\tmovs r1, #0x80\n\torrs r3, r1\n\tstr r3, [r2, #0x20]\n" ++
  -- GCLK.CLKCTRL (0x40000C02, 16 bits): SERCOM5_CORE from generator 0; wait for STATUS.SYNCBUSY
  s!"\t{la "r2" "0x40000C00"}\n\t{la "r3" "0x4019"}\n\tstrh r3, [r2, #2]\n" ++
  s!"\t{la "r1" "0x100000"}\n9:\tldrb r3, [r2, #1]\n\tlsls r3, r3, #24\n\tbpl 8f\n\tsubs r1, #1\n\tbne 9b\n8:\n" ++
  -- PORT group A (0x41004400): PA22 -> function D (PMUX11 low nibble, PINCFG22.PMUXEN)
  s!"\t{la "r2" "0x41004400"}\n" ++
  "\tmovs r1, #0x3B\n\tldrb r3, [r2, r1]\n\tmovs r0, #0x0F\n\tbics r3, r0\n\tmovs r0, #3\n\torrs r3, r0\n\tstrb r3, [r2, r1]\n" ++
  "\tmovs r1, #0x56\n\tldrb r3, [r2, r1]\n\tmovs r0, #1\n\torrs r3, r0\n\tstrb r3, [r2, r1]\n" ++
  -- PORT group B (0x41004480): PB22 -> function D
  "\tadds r2, #0x80\n" ++
  "\tmovs r1, #0x3B\n\tldrb r3, [r2, r1]\n\tmovs r0, #0x0F\n\tbics r3, r0\n\tmovs r0, #3\n\torrs r3, r0\n\tstrb r3, [r2, r1]\n" ++
  "\tmovs r1, #0x56\n\tldrb r3, [r2, r1]\n\tmovs r0, #1\n\torrs r3, r0\n\tstrb r3, [r2, r1]\n" ++
  -- SERCOM5 (0x42001C00): CTRLA, CTRLB (wait SYNCBUSY), BAUD, then ENABLE (wait SYNCBUSY)
  s!"\t{la "r2" "0x42001C00"}\n\t{la "r3" "0x40200004"}\n\tstr r3, [r2]\n" ++
  s!"\t{la "r3" "0x00030000"}\n\tstr r3, [r2, #4]\n" ++
  s!"\t{la "r1" "0x100000"}\n7:\tldr r3, [r2, #0x1C]\n\tcmp r3, #0\n\tbeq 6f\n\tsubs r1, #1\n\tbne 7b\n6:\n" ++
  s!"\t{la "r3" "50436"}\n\tstrh r3, [r2, #0x0C]\n" ++
  s!"\t{la "r3" "0x40200006"}\n\tstr r3, [r2]\n" ++
  s!"\t{la "r1" "0x100000"}\n5:\tldr r3, [r2, #0x1C]\n\tcmp r3, #0\n\tbeq 4f\n\tsubs r1, #1\n\tbne 5b\n4:\n" ++
  "\tbx lr\n"

/-- SAM D21 `putc`: wait for `INTFLAG.DRE`, write `DATA`, then wait for `INTFLAG.TXC`, so the
last byte is on the wire before the run ends. -/
def putcSamd21 : String :=
  "\t.thumb_func\nputc:\n" ++
  s!"\t{la "r2" "0x42001C00"}\n" ++
  "1:\tldrb r3, [r2, #0x18]\n\tlsls r3, r3, #31\n\tbeq 1b\n\tstrh r0, [r2, #0x28]\n" ++
  "2:\tldrb r3, [r2, #0x18]\n\tlsls r3, r3, #30\n\tbpl 2b\n\tbx lr\n"

/-- SAM D21 end of run, after the transcript, with the status in `r6`: light the yellow LED
(PB10, active low) when the status is 0, then wait for the switch SW0 (PB11, input with the
internal pull-up) to be released and pressed, and reset the chip (`AIRCR.SYSRESETREQ`), so each
press runs the program again and prints a fresh transcript. -/
def finishSamd21 : String :=
  s!"\t{la "r2" "0x41004480"}\n\tcmp r6, #0\n\tbne 1f\n" ++
  s!"\t{la "r3" "0x400"}\n\tstr r3, [r2, #0x08]\n\tstr r3, [r2, #0x14]\n1:\n" ++
  "\tmovs r1, #0x4B\n\tmovs r3, #6\n\tstrb r3, [r2, r1]\n" ++
  s!"\t{la "r3" "0x800"}\n\tstr r3, [r2, #0x18]\n" ++
  "2:\tldr r0, [r2, #0x20]\n\ttst r0, r3\n\tbeq 2b\n" ++
  "3:\tldr r0, [r2, #0x20]\n\ttst r0, r3\n\tbne 3b\n" ++
  s!"\t{la "r1" "0xE000ED0C"}\n\t{la "r0" "0x05FA0004"}\n\tstr r0, [r1]\n4:\tb 4b\n"

/-- Output and end-of-run routines, entered only from `exitHalt`, `exitTrap` and `exitOvf`, so
they may use any register. `putc` writes `r0` to the UART; `putw` writes `r6` as eight
hexadecimal digits and a newline; `putws` writes the `r5` words at address `r4`.

The end of a run (`.Lexit` with the status in `r1`, entered with the UART not yet set up;
`.Lfinish` with the status in `r6` and the UART set up) needs no debugger: the status goes to
the two words at `exitblk` (the status and the marker `0xE0D0F1A1`, for a debugger that wants
to read it), then the UART gets the line `EXIT` and the status as a word line, and the core
sleeps (`wfi`) for good. -/
def devices (r : Runtime) : String :=
  (match r.soc with
   | .nrf =>
     uartInit r ++
     "\t.thumb_func\nputc:\n" ++
     s!"\t{la "r2" (hex r.uartBase)}\n\t{la "r1" "0x51C"}\n\tstr r0, [r2, r1]\n\t{la "r1" "0x11C"}\n" ++
     "1:\tldr r3, [r2, r1]\n\tcmp r3, #0\n\tbeq 1b\n\tmovs r3, #0\n\tstr r3, [r2, r1]\n\tbx lr\n"
   | .samd21 => uartInitSamd21 ++ putcSamd21) ++
  "\t.thumb_func\nputw:\n\tmov r10, lr\n\tmovs r7, #28\n" ++
  "2:\tmov r0, r6\n\tlsrs r0, r7\n\tmovs r1, #15\n\tands r0, r1\n\tcmp r0, #10\n\tbhs 3f\n" ++
  "\tadds r0, #48\n\tb 4f\n3:\tadds r0, #87\n4:\tbl putc\n" ++
  "\tsubs r7, #4\n\tbpl 2b\n\tmovs r0, #10\n\tbl putc\n\tbx r10\n" ++
  "\t.thumb_func\nputws:\n\tmov r9, lr\n" ++
  "5:\tcmp r5, #0\n\tbeq 6f\n\tldr r6, [r4]\n\tadds r4, #4\n\tbl putw\n\tsubs r5, #1\n\tb 5b\n" ++
  "6:\tbx r9\n" ++
  ".Lexit:\n\tmov r6, r1\n\tbl uart_init\n" ++
  s!".Lfinish:\n\t{la "r0" "exitblk"}\n\tstr r6, [r0]\n\t{la "r1" "0xE0D0F1A1"}\n\tstr r1, [r0, #4]\n" ++
  String.join ("EXIT\n".toList.map fun ch => s!"\tmovs r0, #{ch.toNat}\n\tbl putc\n") ++
  "\tbl putw\n" ++
  (match r.soc with
   | .nrf => "7:\twfi\n\tb 7b\n"
   | .samd21 => finishSamd21)

/-- Set up the UART for the halt dump. -/
def uartOn (_r : Runtime) : String := "\tbl uart_init\n"

def epilogue (r : Runtime) : String :=
  let m := r.memImage.length
  ".Lhalt:\n" ++ uartOn r ++
  "\tmov r11, r5\n" ++
  s!"\t{li "r0" r.dEnd}\n\tsubs r0, r0, r4\n\tlsrs r0, r0, #2\n\tmov r5, r0\n\tmov r6, r0\n" ++
  "\tbl putw\n\tbl putws\n" ++
  s!"\tmov r4, r8\n\t{li "r5" m}\n\tbl putws\n" ++
  s!"\tmov r4, r11\n\t{li "r5" r.nregs}\n\tbl putws\n" ++
  "\tmovs r6, #0\n\tb .Lfinish\n" ++
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
end CM0
end WordDialect
