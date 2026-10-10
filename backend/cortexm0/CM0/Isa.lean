import WordDialect

/-!
# CM0.Isa

A Lean model of the ARMv6-M instruction subset the Cortex-M0 profile emits, on 32-bit registers
and 32-bit words. ARMv6-M is the Cortex-M0, M0+ and M1 architecture: almost every instruction is
16 bits wide, data processing works on the low registers `r0 … r7` only, constants come from
`movs` with an 8-bit immediate, conditional branches reach 256 bytes, and there is **no divide
instruction**. The lowering therefore divides with a loop of the instructions below, proved in
`CM0/Divide.lean`.

Scope and trust boundary:
* The registers `r0 … r10` and the stack pointer `sp`, which holds the return stack. The link
  register is not modelled: the emitted code writes it (every branch is a `bl`, see below) but
  no model instruction reads it, as for the condition flags.
* Memory is the shared `Memory 32` model, indexed by byte address. The lowering only performs
  4-byte-aligned accesses (`ldr`/`str`); no unaligned or sub-word access is modelled.
* Condition flags are not part of the model state. Most ARMv6-M data-processing instructions set
  them (`adds`, `subs`, `ands`, …), and the conditional sequences read them right after their
  own `cmp`; no model instruction reads flags set by another, so they are dead between model
  instructions.
* Shifts by a register (`lsls`, `lsrs`) use the bottom byte of the amount, as the architecture
  does: amounts of 32 to 255 give zero, and 256 shifts by 0 again. `rors` rotates by the amount
  modulo 32.
* Faults (invalid memory access, jumping outside the code) are a distinct outcome, never a silent
  state.
* Some model instructions are fixed instruction sequences in the emitted text (`CM0.Emit`); the
  model gives each the combined effect of its sequence:
  - `movImm d v` builds `v` in a low register from bytes (`movs`, then `lsls #8` and `adds`
    pairs), which writes only `d` (and the flags);
  - every branch is a `bl` (range 16 MiB), which also writes the link register: `jmp t` is
    `bl t`, and `bcc c a b t` is `cmp a, b` and the opposite conditional branch over a `bl`;
    `beqz`/`bnez` are the same with `cmp a, #0`;
  - `sltiu d s k` is `movs d, #0; cmp s, #k; bhs 1f; movs d, #1; 1:` (`Emit` requires `d ≠ s`);
  - `call t` is `b 2f; 1: push {lr}; bl t; 2: bl 1b`: the second `bl` puts the return address
    (the next instruction, with the Thumb bit) in `lr`, and `push {lr}` stores it on the return
    stack `sp`; `ret` is `pop {pc}`.
  Code addresses are instruction indices, as for jumps (the code-address abstraction of every
  backend model here).
* `exitHalt` / `exitTrap t` stand for the runtime stubs that dump state and stop the machine;
  they are terminal here. `exitOvf` is the stub for a stack-overflow guard (status 6); it has no
  IR counterpart, since IR stacks are unbounded. There is no operating system: the stubs talk to
  a UART and stop the machine through semihosting (`CM0.Emit`).

That the model matches the hardware is the stated assumption of this backend; `cm0c` tests it by
running the emitted code on an emulated Cortex-M0 board (`qemu-system-arm -M microbit`).
-/

namespace WordDialect
namespace CM0

abbrev W := BitVec 32

/-- Registers. Roles (see `CM0.Lower`): `r0 r1 r2 r3 r7 r10` scratch (`r7` and `r10` only inside
the division loops), `r4` data-stack pointer, `r5` register file, `r6` auxiliary-stack pointer,
`r8` IR memory, `r9` the empty return stack, `sp` the return-stack pointer. The three pointers
used as load/store bases are low registers, as ARMv6-M requires; `r8` and `r9` are only added
and compared. -/
inductive Reg where
  | r0 | r1 | r2 | r3 | sp | r6 | r9 | r8 | r5 | r4 | r7 | r10
  deriving DecidableEq, Repr

/-- Instructions, generic in the type of jump targets (`Nat` code indices for the model,
`String` labels for assembly text). Two-operand forms `op d s` mean `d := d op s`. -/
inductive Instr (L : Type) where
  | movImm (d : Reg) (v : W)
  | movRR (d s : Reg)
  /-- `ldr d, [b, #disp]`. -/
  | load (d b : Reg) (disp : Int)
  /-- `str s, [b, #disp]`. -/
  | store (b : Reg) (disp : Int) (s : Reg)
  /-- `adds d, d, s`, or `add d, s` when `s` is a high register. -/
  | add (d s : Reg)
  /-- `subs d, d, s`. -/
  | sub (d s : Reg)
  /-- `muls d, s, d`. -/
  | mul (d s : Reg)
  /-- `ands d, s`. -/
  | and (d s : Reg)
  /-- `orrs d, s`. -/
  | or (d s : Reg)
  /-- `eors d, s`. -/
  | xor (d s : Reg)
  /-- `adds d, #v` or `subs d, #-v`. -/
  | addImm (d : Reg) (v : Int)
  /-- `lsls d, d, #k`. -/
  | shlImm (d : Reg) (k : Nat)
  /-- `mvns d, d`. -/
  | not (d : Reg)
  /-- `rsbs d, d, #0`. -/
  | neg (d : Reg)
  /-- `1` if `s <u k`, else `0` (a fixed sequence, see above). -/
  | sltiu (d s : Reg) (k : Nat)
  /-- `lsls d, s` (bottom byte of `s`). -/
  | lsl (d s : Reg)
  /-- `lsrs d, s` (bottom byte of `s`). -/
  | lsr (d s : Reg)
  /-- `rors d, s` (amount modulo 32). -/
  | ror (d s : Reg)
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
  | .bcc c a b t => .next (if c.eval (m.regs a) (m.regs b) then { m with pc := t } else m.adv)
  | .beqz a t => .next (if m.regs a = 0#32 then { m with pc := t } else m.adv)
  | .bnez a t => .next (if m.regs a = 0#32 then m.adv else { m with pc := t })
  | .jmp t => .next { m with pc := t }
  | .call t =>
      let sp := m.regs .sp - 4#32
      match m.mem.write? sp (BitVec.ofNat 32 (m.pc + 1)) with
      | some mem' => .next { (m.setReg .sp sp) with mem := mem', pc := t }
      | none => .fault
  | .ret =>
      match m.mem.read? (m.regs .sp) with
      | some v => .next { (m.setReg .sp (m.regs .sp + 4#32)) with pc := v.toNat }
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

end CM0
end WordDialect
