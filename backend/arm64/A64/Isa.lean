import WordDialect

/-!
# A64.Isa

A Lean model of the AArch64 (ARM64) instruction subset the backend emits.

Scope and trust boundary:
* 64-bit `x` registers only; the registers the lowering uses.
* Memory is the shared `Memory 64` model, indexed by byte address. The lowering only performs
  8-byte-aligned accesses; no unaligned or sub-word access is modelled.
* The condition flags are modelled by `Flags`, an encoding of `NZCV`: `zf` is `Z`, `sf` is `N`,
  `ovf` is `V`, and `cf` is the *borrow*, `NOT C` (AArch64 sets `C` when a subtraction does not
  borrow). The condition codes `Cc` are named after their meaning, and `Emit` prints each as its
  AArch64 mnemonic (`b` as `lo`, `ae` as `hs`, `a` as `hi`, `be` as `ls`, `l` as `lt`, ...).
* Only `cmp`, `cmn` and `tst` set the flags on AArch64; every other instruction leaves them
  unchanged. The model is more conservative: arithmetic, shifts and divides make the flags
  unknown (`none`), and reading unknown flags faults. A proof that the code never faults shows it
  never reads flags across such an instruction, which then holds on the hardware a fortiori.
* AArch64 `udiv` and `sdiv` never fault: division by zero gives `0`, and `sdiv` of the most negative
  number by `-1` wraps. Both are exactly `BitVec.udiv` and `BitVec.sdiv`.
* Faults (invalid memory access, unknown flags, jumping outside the code) are a distinct outcome,
  never a silent state.
* Some model instructions are fixed instruction sequences in the emitted text (`A64.Emit`); the
  model gives each the combined effect of its sequence:
  - `movImm d v` is `movz` and three `movk` (writes `d`);
  - `call t` is `adr x30, <next>; str x30, [x23, #-8]!; b t`: it pushes the return address on the
    return stack (`x23`, growing downward) and writes `x30`;
  - `ret` is `ldr x30, [x23], #8; br x30`: it pops the return address into `x30` and jumps there.
  Code addresses are instruction indices, as for jumps (the code-address abstraction of every
  backend model here).
* `exitHalt` / `exitTrap t` stand for the runtime stubs that dump state and `exit`; they are
  terminal here. `exitOvf` is the stub for a stack-overflow guard (`exit(6)`); it has no IR
  counterpart, since IR stacks are unbounded.

That the model matches the hardware is the stated assumption of this backend; `a64c` tests it by
running the emitted code under `qemu-aarch64`.
-/

namespace WordDialect
namespace A64

abbrev W := BitVec 64

/-- Registers. Roles (see `A64.Lower`): `x9 x10 x11 x12` scratch, `x19` data-stack pointer,
`x20` register file, `x21` IR memory, `x22` empty return stack, `x23` return-stack pointer,
`x24` auxiliary-stack pointer, `x30` link register (written by `call` and `ret`). -/
inductive Reg where
  | x9 | x10 | x11 | x12 | x23 | x24 | x22 | x21 | x20 | x19 | x30
  deriving DecidableEq, Repr

/-- Condition codes (the subset used), named after their meaning on `subFlags`. -/
inductive Cc where
  | e | ne | b | be | a | ae | l | le | g | ge
  deriving DecidableEq, Repr

/-- `NZCV`, with `cf` the borrow (`NOT C`). -/
structure Flags where
  zf : Bool
  sf : Bool
  cf : Bool
  ovf : Bool

def Cc.holds : Cc → Flags → Bool
  | .e,  f => f.zf
  | .ne, f => !f.zf
  | .b,  f => f.cf
  | .be, f => f.cf || f.zf
  | .a,  f => !f.cf && !f.zf
  | .ae, f => !f.cf
  | .l,  f => f.sf != f.ovf
  | .le, f => f.zf || (f.sf != f.ovf)
  | .g,  f => !f.zf && (f.sf == f.ovf)
  | .ge, f => f.sf == f.ovf

/-- Flags of `a - b`, as set by `cmp a, b` (and by `cmn a, #k` when `b = -k`). -/
def subFlags (a b : W) : Flags :=
  let d := a - b
  { zf := d == 0#64, sf := d.msb, cf := a.ult b,
    ovf := (a.msb != b.msb) && (a.msb != d.msb) }

/-- Flags of `tst a, b` (`ands`): `N` and `Z` of the result, `C = V = 0` (so the borrow is set). -/
def logicFlags (r : W) : Flags := { zf := r == 0#64, sf := r.msb, cf := true, ovf := false }

/-- Instructions, generic in the type of jump targets (`Nat` code indices for the model,
`String` labels for assembly text). Two-operand forms `op d s` mean `d := d op s`. -/
inductive Instr (L : Type) where
  | movImm (d : Reg) (v : W)
  | movRR (d s : Reg)
  | load (d b : Reg) (disp : Int)
  | store (b : Reg) (disp : Int) (s : Reg)
  | loadIdx (d b i : Reg)
  | storeIdx (b i s : Reg)
  | add (d s : Reg)
  | sub (d s : Reg)
  | mul (d s : Reg)
  | and (d s : Reg)
  | or (d s : Reg)
  | xor (d s : Reg)
  | addImm (d : Reg) (v : Int)
  | not (d : Reg)
  | neg (d : Reg)
  | cmp (a b : Reg)
  | cmpImm (a : Reg) (v : Int)
  | test (a b : Reg)
  /-- `lsl d, d, x10` (shift amount modulo 64). -/
  | shlCl (d : Reg)
  /-- `lsr d, d, x10`. -/
  | shrCl (d : Reg)
  /-- `ror d, d, x10`. -/
  | rorCl (d : Reg)
  /-- `csel d, s, d, c`. -/
  | cmov (c : Cc) (d s : Reg)
  | udiv (d a b : Reg)
  | sdiv (d a b : Reg)
  | jmp (t : L)
  | jcc (c : Cc) (t : L)
  | call (t : L)
  | ret
  | exitHalt
  | exitTrap (t : Trap)
  | exitOvf

structure M where
  regs  : Reg → W
  flags : Option Flags
  mem   : Memory 64
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

/-- Write a register and advance; the flags become unknown (conservatively). -/
def M.arith (m : M) (r : Reg) (v : W) : M :=
  { (m.setReg r v) with flags := none, pc := m.pc + 1 }

/-- Write a register and advance; flags untouched (as `mov`). -/
def M.mov (m : M) (r : Reg) (v : W) : M := (m.setReg r v).adv

def M.ea (m : M) (b : Reg) (disp : Int) : W := m.regs b + BitVec.ofInt 64 disp

def M.eaIdx (m : M) (b i : Reg) : W := m.regs b + m.regs i * 8#64

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
  | .loadIdx d b i =>
      match m.mem.read? (m.eaIdx b i) with
      | some v => .next (m.mov d v)
      | none => .fault
  | .storeIdx b i s =>
      match m.mem.write? (m.eaIdx b i) (m.regs s) with
      | some mem' => .next { m.adv with mem := mem' }
      | none => .fault
  | .add d s => .next (m.arith d (m.regs d + m.regs s))
  | .sub d s => .next (m.arith d (m.regs d - m.regs s))
  | .mul d s => .next (m.arith d (m.regs d * m.regs s))
  | .and d s => .next (m.arith d (m.regs d &&& m.regs s))
  | .or d s => .next (m.arith d (m.regs d ||| m.regs s))
  | .xor d s => .next (m.arith d (m.regs d ^^^ m.regs s))
  | .addImm d v => .next (m.arith d (m.regs d + BitVec.ofInt 64 v))
  | .not d => .next (m.mov d (~~~m.regs d))
  | .neg d => .next (m.arith d (0#64 - m.regs d))
  | .cmp a b => .next { m.adv with flags := some (subFlags (m.regs a) (m.regs b)) }
  | .cmpImm a v => .next { m.adv with flags := some (subFlags (m.regs a) (BitVec.ofInt 64 v)) }
  | .test a b => .next { m.adv with flags := some (logicFlags (m.regs a &&& m.regs b)) }
  | .shlCl d => .next (m.arith d (m.regs d <<< ((m.regs .x10).toNat % 64)))
  | .shrCl d => .next (m.arith d (m.regs d >>> ((m.regs .x10).toNat % 64)))
  | .rorCl d => .next (m.arith d ((m.regs d).rotateRight ((m.regs .x10).toNat % 64)))
  | .cmov c d s =>
      match m.flags with
      | none => .fault
      | some f => .next (if c.holds f then m.mov d (m.regs s) else m.adv)
  | .udiv d a b => .next (m.arith d ((m.regs a).udiv (m.regs b)))
  | .sdiv d a b => .next (m.arith d ((m.regs a).sdiv (m.regs b)))
  | .jmp t => .next { m with pc := t }
  | .jcc c t =>
      match m.flags with
      | none => .fault
      | some f => .next (if c.holds f then { m with pc := t } else m.adv)
  | .call t =>
      let sp := m.regs .x23 - 8#64
      let ra := BitVec.ofNat 64 (m.pc + 1)
      match m.mem.write? sp ra with
      | some mem' => .next { ((m.setReg .x30 ra).setReg .x23 sp) with mem := mem', pc := t }
      | none => .fault
  | .ret =>
      match m.mem.read? (m.regs .x23) with
      | some v => .next { ((m.setReg .x30 v).setReg .x23 (m.regs .x23 + 8#64)) with pc := v.toNat }
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

end A64
end WordDialect
