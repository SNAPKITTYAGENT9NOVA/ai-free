import WordDialect

/-!
# CM.Isa

A Lean model of the Thumb-2 (ARMv7-M) instruction subset the Cortex-M profile emits, on 32-bit
registers and 32-bit words. Cortex-M3 and later cores (M3, M4, M7, M33) implement all of it,
including the hardware divide.

Scope and trust boundary:
* The integer registers `r0 … r12` and `lr`. The stack pointer `sp` and the program counter are
  not used as data registers.
* Memory is the shared `Memory 32` model, indexed by byte address. The lowering only performs
  4-byte-aligned accesses (`ldr`/`str`); no unaligned or sub-word access is modelled.
* Condition flags are not part of the model state. Every instruction that sets or reads them is
  inside one fixed sequence whose combined effect the model gives (`bcc`, `beqz`, `bnez`,
  `sltiu`), and no sequence reads flags set by another, so they are dead between model
  instructions.
* Shifts by a register (`lsl`, `lsr`) use the bottom byte of the amount, as the architecture
  does: amounts of 32 to 255 give zero, and 256 shifts by 0 again. `ror` by a register rotates by
  the amount modulo 32.
* `udiv` and `sdiv` never fault: division by zero gives zero (the Cortex-M behaviour with the
  divide-by-zero trap `CCR.DIV_0_TRP` disabled, its reset value), and `sdiv` of the most negative
  number by `-1` wraps. The lowering guards the zero divisor itself.
* Faults (invalid memory access, jumping outside the code) are a distinct outcome, never a silent
  state.
* Some model instructions are fixed instruction sequences in the emitted text (`CM.Emit`); the
  model gives each the combined effect of its sequence:
  - `movImm d v` is `movw d, #lo16; movt d, #hi16`, which writes only `d`;
  - `bcc c a b t` is `cmp a, b` and the opposite conditional branch over a `b.w`, so its range
    is that of `b.w`; `beqz`/`bnez` are the same with `cmp a, #0`;
  - `sltiu d s k` is `cmp s, #k; ite lo; movlo d, #1; movhs d, #0`;
  - `call t` is `movw/movt lr, <next> + 1; str lr, [r8, #-4]!; b.w t`: it pushes the return
    address (with the Thumb bit) on the return stack (`r8`, growing downward) and writes `lr`;
  - `ret` is `ldr lr, [r8], #4; bx lr`: it pops the return address into `lr` and jumps.
  Code addresses are instruction indices, as for jumps (the code-address abstraction of every
  backend model here).
* `exitHalt` / `exitTrap t` stand for the runtime stubs that dump state and stop the machine;
  they are terminal here. `exitOvf` is the stub for a stack-overflow guard (status 6); it has no
  IR counterpart, since IR stacks are unbounded. There is no operating system: the stubs talk to
  a UART and stop the machine through semihosting (`CM.Emit`).

That the model matches the hardware is the stated assumption of this backend; `cmc` tests it by
running the emitted code on an emulated Cortex-M3 board (`qemu-system-arm -M mps2-an385`).
-/

namespace WordDialect
namespace CM

abbrev W := BitVec 32

/-- Registers. Roles (see `CM.Lower`): `r0 r1 r2 r3` scratch, `r4` data-stack pointer, `r5`
register file, `r6` IR memory, `r7` empty return stack, `r8` return-stack pointer, `r9`
auxiliary-stack pointer, `lr` return address (written by `call` and `ret`). The lowering uses no
others; `r10 … r12` are for hand-written programs (`CM.DataOps`). -/
inductive Reg where
  | r0 | r1 | r2 | r3 | r8 | r9 | r7 | r6 | r5 | r4 | lr
  | r10 | r11 | r12
  deriving DecidableEq, Repr

/-- The register operations of the three-register form `op d, a, b`. The shifts use the bottom
byte of `b`, as the hardware does. -/
inductive Alu where
  | add | sub | mul | and | orr | eor | lsl | lsr | asr
  deriving DecidableEq, Repr

def Alu.eval : Alu → W → W → W
  | .add, a, b => a + b
  | .sub, a, b => a - b
  | .mul, a, b => a * b
  | .and, a, b => a &&& b
  | .orr, a, b => a ||| b
  | .eor, a, b => a ^^^ b
  | .lsl, a, b => a <<< (b.toNat % 256)
  | .lsr, a, b => a >>> (b.toNat % 256)
  | .asr, a, b => a.sshiftRight (b.toNat % 256)

/-- Shifts by a constant: `lsl`, `lsr`, `asr` with `#n`. -/
inductive Shift where
  | lsl | lsr | asr
  deriving DecidableEq, Repr

def Shift.eval : Shift → W → Nat → W
  | .lsl, a, n => a <<< n
  | .lsr, a, n => a >>> n
  | .asr, a, n => a.sshiftRight n

/-- Instructions, generic in the type of jump targets (`Nat` code indices for the model,
`String` labels for assembly text). Two-operand forms `op d s` mean `d := d op s`. -/
inductive Instr (L : Type) where
  | movImm (d : Reg) (v : W)
  | movRR (d s : Reg)
  /-- `ldr d, [b, #disp]`. -/
  | load (d b : Reg) (disp : Int)
  /-- `str s, [b, #disp]`. -/
  | store (b : Reg) (disp : Int) (s : Reg)
  | add (d s : Reg)
  | sub (d s : Reg)
  | mul (d s : Reg)
  | and (d s : Reg)
  /-- `orr d, d, s`. -/
  | or (d s : Reg)
  /-- `eor d, d, s`. -/
  | xor (d s : Reg)
  | addImm (d : Reg) (v : Int)
  /-- `lsl d, d, #k`. -/
  | shlImm (d : Reg) (k : Nat)
  /-- `mvn d, d`. -/
  | not (d : Reg)
  /-- `rsb d, d, #0`. -/
  | neg (d : Reg)
  /-- The sequence `cmp s, #k; ite lo; movlo d, #1; movhs d, #0`: `1` if `s <u k`, else `0`. -/
  | sltiu (d s : Reg) (k : Nat)
  /-- `lsl d, d, s` (bottom byte of `s`). -/
  | lsl (d s : Reg)
  /-- `lsr d, d, s` (bottom byte of `s`). -/
  | lsr (d s : Reg)
  /-- `ror d, d, s` (amount modulo 32). -/
  | ror (d s : Reg)
  /-- `udiv d, a, b`. -/
  | divu (d a b : Reg)
  /-- `sdiv d, a, b`. -/
  | div (d a b : Reg)
  /-- Three-register form `op d, a, b` (`d := a op b`), for hand-written programs. -/
  | alu (op : Alu) (d a b : Reg)
  /-- `lsl`/`lsr`/`asr d, a, #n` (`d := a shifted by n`); `Emit` requires `n < 32`. -/
  | shiftImm (k : Shift) (d a : Reg) (n : Nat)
  | bcc (c : Cond) (a b : Reg) (t : L)
  | beqz (a : Reg) (t : L)
  | bnez (a : Reg) (t : L)
  | jmp (t : L)
  | call (t : L)
  | ret
  | exitHalt
  | exitTrap (t : Trap)
  | exitOvf

structure M where
  regs  : Reg → W
  mem   : Memory 32
  pc    : Nat

inductive Out where
  | next    (m : M)
  | halted  (m : M)
  | trapped (t : Trap)
  | overflow
  | fault

def M.setReg (m : M) (r : Reg) (v : W) : M :=
  { m with regs := fun x => if x = r then v else m.regs x }

def M.adv (m : M) : M := { m with pc := m.pc + 1 }

/-- Write a register and advance. -/
def M.mov (m : M) (r : Reg) (v : W) : M := (m.setReg r v).adv

/-- Write a register and advance (the result of an arithmetic instruction). -/
def M.arith (m : M) (r : Reg) (v : W) : M := { (m.setReg r v) with pc := m.pc + 1 }

def M.ea (m : M) (b : Reg) (disp : Int) : W := m.regs b + BitVec.ofInt 32 disp

/-- `udiv`: zero on a zero divisor. -/
def divu (a b : W) : W := if b = 0#32 then 0#32 else a.udiv b

/-- `sdiv`: zero on a zero divisor; otherwise `BitVec.sdiv` (which wraps on overflow). -/
def divs (a b : W) : W := if b = 0#32 then 0#32 else a.sdiv b

/-- Semantics of one instruction. -/
def exec (i : Instr Nat) (m : M) : Out :=
  match i with
  | .movImm d v => .next (m.mov d v)
  | .movRR d s => .next (m.mov d (m.regs s))
  | .load d b disp =>
      match m.mem.read? (m.ea b disp) with
      | some v => .next (m.mov d v)
      | none => .fault
  | .store b disp s =>
      match m.mem.write? (m.ea b disp) (m.regs s) with
      | some mem' => .next { m.adv with mem := mem' }
      | none => .fault
  | .add d s => .next (m.arith d (m.regs d + m.regs s))
  | .sub d s => .next (m.arith d (m.regs d - m.regs s))
  | .mul d s => .next (m.arith d (m.regs d * m.regs s))
  | .and d s => .next (m.arith d (m.regs d &&& m.regs s))
  | .or d s => .next (m.arith d (m.regs d ||| m.regs s))
  | .xor d s => .next (m.arith d (m.regs d ^^^ m.regs s))
  | .addImm d v => .next (m.arith d (m.regs d + BitVec.ofInt 32 v))
  | .shlImm d k => .next (m.arith d (m.regs d <<< (k % 32)))
  | .not d => .next (m.arith d (~~~m.regs d))
  | .neg d => .next (m.arith d (0#32 - m.regs d))
  | .sltiu d s k => .next (m.arith d (Word.ofBool ((m.regs s).ult (BitVec.ofNat 32 k))))
  | .lsl d s => .next (m.arith d (m.regs d <<< ((m.regs s).toNat % 256)))
  | .lsr d s => .next (m.arith d (m.regs d >>> ((m.regs s).toNat % 256)))
  | .ror d s => .next (m.arith d ((m.regs d).rotateRight ((m.regs s).toNat % 256)))
  | .divu d a b => .next (m.arith d (divu (m.regs a) (m.regs b)))
  | .div d a b => .next (m.arith d (divs (m.regs a) (m.regs b)))
  | .alu op d a b => .next (m.arith d (op.eval (m.regs a) (m.regs b)))
  | .shiftImm k d a n => .next (m.arith d (k.eval (m.regs a) n))
  | .bcc c a b t => .next (if c.eval (m.regs a) (m.regs b) then { m with pc := t } else m.adv)
  | .beqz a t => .next (if m.regs a = 0#32 then { m with pc := t } else m.adv)
  | .bnez a t => .next (if m.regs a = 0#32 then m.adv else { m with pc := t })
  | .jmp t => .next { m with pc := t }
  | .call t =>
      let sp := m.regs .r8 - 4#32
      let ra := BitVec.ofNat 32 (m.pc + 1)
      match m.mem.write? sp ra with
      | some mem' => .next { ((m.setReg .lr ra).setReg .r8 sp) with mem := mem', pc := t }
      | none => .fault
  | .ret =>
      match m.mem.read? (m.regs .r8) with
      | some v => .next { ((m.setReg .lr v).setReg .r8 (m.regs .r8 + 4#32)) with pc := v.toNat }
      | none => .fault
  | .exitHalt => .halted m
  | .exitTrap t => .trapped t
  | .exitOvf => .overflow

/-- One machine step over a code array; leaving the code is a fault. -/
def step (code : List (Instr Nat)) (m : M) : Out :=
  match code[m.pc]? with
  | none => .fault
  | some i => exec i m

/-- Fuel-bounded run. `none`: out of fuel. -/
def run (code : List (Instr Nat)) : Nat → M → Option Out
  | 0, _ => none
  | fuel + 1, m =>
    match step code m with
    | .next m' => run code fuel m'
    | o => some o

end CM
end WordDialect
