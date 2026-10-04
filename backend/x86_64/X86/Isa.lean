import WordDialect

/-!
# X86.Isa

A Lean model of the x86-64 instruction subset the backend emits.

Scope and trust boundary:
* 64-bit registers only; the registers the lowering uses.
* Memory is the shared `Memory 64` model, indexed by byte address. The lowering only performs
  8-byte-aligned accesses; no unaligned or sub-word access is modelled.
* Flags `ZF SF CF OF` are modelled concretely. Instructions that architecturally leave the
  flags undefined (arithmetic, shifts, `imul`, divide) set them to `none`; reading `none`
  faults. So a proof that the machine never faults shows the lowering never relies on
  undefined flags.
* Faults (invalid memory access, divide error, undefined flags, jumping outside the code)
  are a distinct outcome, never a silent state.
* `exitHalt` / `exitTrap t` stand for the runtime stubs that dump state and `exit`; they are
  terminal here. `exitOvf` is the stub for a stack-overflow guard (`exit(6)`); it has no IR
  counterpart, since IR stacks are unbounded.

That the model matches the hardware is the stated assumption of this backend.
-/

namespace WordDialect
namespace X86

abbrev W := BitVec 64

inductive Reg where
  | rax | rcx | rdx | rbx | rsp | rbp | r12 | r13 | r14 | r15
  deriving DecidableEq, Repr

/-- Condition codes (the subset used). -/
inductive Cc where
  | e | ne | b | be | a | ae | l | le | g | ge
  deriving DecidableEq, Repr

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

/-- Flags of `a - b`, as set by `cmp a, b`. -/
def subFlags (a b : W) : Flags :=
  let d := a - b
  { zf := d == 0#64, sf := d.msb, cf := a.ult b,
    ovf := (a.msb != b.msb) && (a.msb != d.msb) }

/-- Flags of a logical result (`test`, `and`, `or`, `xor`): `CF = OF = 0`. -/
def logicFlags (r : W) : Flags := { zf := r == 0#64, sf := r.msb, cf := false, ovf := false }

/-- Instructions, generic in the type of jump targets (`Nat` code indices for the model,
`String` labels for assembly text). -/
inductive Instr (L : Type) where
  | movImm (d : Reg) (v : W)
  | movRR (d s : Reg)
  | load (d b : Reg) (disp : Int)
  | store (b : Reg) (disp : Int) (s : Reg)
  | loadIdx (d b i : Reg)
  | storeIdx (b i s : Reg)
  | add (d s : Reg)
  | sub (d s : Reg)
  | imul (d s : Reg)
  | and (d s : Reg)
  | or (d s : Reg)
  | xor (d s : Reg)
  | addImm (d : Reg) (v : Int)
  | not (d : Reg)
  | neg (d : Reg)
  | cmp (a b : Reg)
  | cmpImm (a : Reg) (v : Int)
  | test (a b : Reg)
  | shlCl (d : Reg)
  | shrCl (d : Reg)
  | rolCl (d : Reg)
  | rorCl (d : Reg)
  | cmov (c : Cc) (d s : Reg)
  | div (s : Reg)
  | idiv (s : Reg)
  | cqo
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

/-- Write a register and advance; flags become undefined. -/
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
  | .imul d s => .next (m.arith d (m.regs d * m.regs s))
  | .and d s => .next (m.arith d (m.regs d &&& m.regs s))
  | .or d s => .next (m.arith d (m.regs d ||| m.regs s))
  | .xor d s => .next (m.arith d (m.regs d ^^^ m.regs s))
  | .addImm d v => .next (m.arith d (m.regs d + BitVec.ofInt 64 v))
  | .not d => .next (m.mov d (~~~m.regs d))
  | .neg d => .next (m.arith d (0#64 - m.regs d))
  | .cmp a b => .next { m.adv with flags := some (subFlags (m.regs a) (m.regs b)) }
  | .cmpImm a v => .next { m.adv with flags := some (subFlags (m.regs a) (BitVec.ofInt 64 v)) }
  | .test a b => .next { m.adv with flags := some (logicFlags (m.regs a &&& m.regs b)) }
  | .shlCl d => .next (m.arith d (m.regs d <<< ((m.regs .rcx).toNat % 64)))
  | .shrCl d => .next (m.arith d (m.regs d >>> ((m.regs .rcx).toNat % 64)))
  | .rolCl d => .next (m.arith d ((m.regs d).rotateLeft ((m.regs .rcx).toNat % 64)))
  | .rorCl d => .next (m.arith d ((m.regs d).rotateRight ((m.regs .rcx).toNat % 64)))
  | .cmov c d s =>
      match m.flags with
      | none => .fault
      | some f => .next (if c.holds f then m.mov d (m.regs s) else m.adv)
  | .div s =>
      let dv := m.regs s
      if dv = 0#64 then .fault
      else
        let dividend : Nat := (m.regs .rdx).toNat * 2 ^ 64 + (m.regs .rax).toNat
        let q := dividend / dv.toNat
        if q < 2 ^ 64 then
          .next { ((m.setReg .rax (BitVec.ofNat 64 q)).setReg .rdx
            (BitVec.ofNat 64 (dividend % dv.toNat))) with flags := none, pc := m.pc + 1 }
        else .fault
  | .idiv s =>
      let dv := m.regs s
      if dv = 0#64 then .fault
      else
        let dividend : Int := (m.regs .rdx).toInt * 2 ^ 64 + ((m.regs .rax).toNat : Int)
        let q := Int.tdiv dividend dv.toInt
        if -(2 ^ 63 : Int) ≤ q ∧ q < 2 ^ 63 then
          .next { ((m.setReg .rax (BitVec.ofInt 64 q)).setReg .rdx
            (BitVec.ofInt 64 (Int.tmod dividend dv.toInt))) with flags := none, pc := m.pc + 1 }
        else .fault
  | .cqo => .next (m.mov .rdx (if (m.regs .rax).msb then BitVec.allOnes 64 else 0#64))
  | .jmp t => .next { m with pc := t }
  | .jcc c t =>
      match m.flags with
      | none => .fault
      | some f => .next (if c.holds f then { m with pc := t } else m.adv)
  | .call t =>
      let sp := m.regs .rsp - 8#64
      match m.mem.write? sp (BitVec.ofNat 64 (m.pc + 1)) with
      | some mem' => .next { (m.setReg .rsp sp) with mem := mem', pc := t }
      | none => .fault
  | .ret =>
      match m.mem.read? (m.regs .rsp) with
      | some v => .next { (m.setReg .rsp (m.regs .rsp + 8#64)) with pc := v.toNat }
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

end X86
end WordDialect
