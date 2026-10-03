/-!
# Wasm.Isa

A model of the WebAssembly subset the backend emits, following the WebAssembly core
specification:

* typed operand stack (`i32` / `i64`), numbered locals, structured control
  (`block`, `loop`, `if`, `br`, `br_if`, `br_table`) with the spec's label discipline, including
  unwinding the operand stack to the label's height when a branch is taken;
* linear memory as **bytes**; `i64.load`/`i64.store` are little-endian, take an `i32` address plus a
  static offset computed in unbounded arithmetic, and fault (trap) if any accessed byte is outside
  the memory. There is no aliasing assumption: overlapping accesses are modelled exactly;
* `i64.div_s` faults on division by zero and on `INT64_MIN / -1` (the spec's two traps);
  `i64.div_u` faults on division by zero; shifts and rotates take the count modulo 64.

Two host calls are modelled as terminal pseudo-instructions: `exitTrap c` (`i32.const c; call
$proc_exit`) and `exitHalt` (`local.get sp; call $halt`, which dumps the machine state and exits 0).

Semantics is a big-step relation (`Run`), so loops need no fuel. That the model matches a real
WebAssembly engine is an assumption, tested by differential execution (see `wasmw`).
-/

namespace WordDialect
namespace Wasm

abbrev W := BitVec 64
abbrev W32 := BitVec 32

inductive Val where
  | i32 (v : W32)
  | i64 (v : W)
  deriving DecidableEq

/-- Little-endian read of `n` bytes starting at `a` (each byte taken modulo 256). -/
def rdBytes (b : Nat → Nat) (a : Nat) : Nat → Nat
  | 0 => 0
  | n + 1 => rdBytes b a n + (b (a + n) % 256) * 256 ^ n

structure WMem where
  bytes : Nat → Nat
  size : Nat

def WMem.read64 (m : WMem) (a : Nat) : Option W :=
  if a + 8 ≤ m.size then some (BitVec.ofNat 64 (rdBytes m.bytes a 8)) else none

def WMem.write64 (m : WMem) (a : Nat) (v : W) : Option WMem :=
  if a + 8 ≤ m.size then
    some { m with bytes := fun p => if a ≤ p ∧ p < a + 8 then (v.toNat / 256 ^ (p - a)) % 256 else m.bytes p }
  else none

structure WState where
  stack : List Val
  locals : Nat → Val
  mem : WMem

inductive WI where
  | i32const (v : W32)
  | i64const (v : W)
  | localGet (i : Nat)
  | localSet (i : Nat)
  | i64load (off : Nat)
  | i64store (off : Nat)
  | i64add | i64sub | i64mul | i64and | i64or | i64xor
  | i64shl | i64shru | i64rotl | i64rotr | i64divu | i64divs
  | i64eq | i64ne | i64ltu | i64leu | i64gtu | i64geu | i64lts | i64les | i64gts | i64ges
  | i64eqz
  | i32add | i32sub | i32shl | i32gtu | i32eq
  | i32wrap
  | i64extu
  | select
  | block (body : List WI)
  | loop (body : List WI)
  | ite (thn : List WI)
  | br (l : Nat)
  | brIf (l : Nat)
  | brTable (ls : List Nat) (dflt : Nat)
  | exitTrap (code : Nat)
  | exitHalt

/-- Control constructs and terminal pseudo-instructions (handled by `RunI`, not `stepI`). -/
def WI.isCtl : WI → Bool
  | .block _ | .loop _ | .ite _ | .br _ | .brIf _ | .brTable _ _ | .exitTrap _ | .exitHalt => true
  | _ => false

def bool32 (b : Bool) : W32 := if b then 1#32 else 0#32

def bin64 (f : W → W → W) (s : WState) : Option WState :=
  match s.stack with
  | .i64 b :: .i64 a :: r => some { s with stack := .i64 (f a b) :: r }
  | _ => none

def cmp64 (f : W → W → Bool) (s : WState) : Option WState :=
  match s.stack with
  | .i64 b :: .i64 a :: r => some { s with stack := .i32 (bool32 (f a b)) :: r }
  | _ => none

def bin32 (f : W32 → W32 → W32) (s : WState) : Option WState :=
  match s.stack with
  | .i32 b :: .i32 a :: r => some { s with stack := .i32 (f a b) :: r }
  | _ => none

/-- One non-control instruction; `none` is a trap. -/
def stepI : WI → WState → Option WState
  | .i32const v, s => some { s with stack := .i32 v :: s.stack }
  | .i64const v, s => some { s with stack := .i64 v :: s.stack }
  | .localGet i, s => some { s with stack := s.locals i :: s.stack }
  | .localSet i, s =>
    match s.stack with
    | v :: r => some { s with stack := r, locals := fun j => if j = i then v else s.locals j }
    | _ => none
  | .i64load off, s =>
    match s.stack with
    | .i32 a :: r =>
      match s.mem.read64 (a.toNat + off) with
      | some v => some { s with stack := .i64 v :: r }
      | none => none
    | _ => none
  | .i64store off, s =>
    match s.stack with
    | .i64 v :: .i32 a :: r =>
      match s.mem.write64 (a.toNat + off) v with
      | some m => some { s with stack := r, mem := m }
      | none => none
    | _ => none
  | .i64add, s => bin64 (· + ·) s
  | .i64sub, s => bin64 (· - ·) s
  | .i64mul, s => bin64 (· * ·) s
  | .i64and, s => bin64 (· &&& ·) s
  | .i64or, s => bin64 (· ||| ·) s
  | .i64xor, s => bin64 (· ^^^ ·) s
  | .i64shl, s => bin64 (fun a b => a <<< (b.toNat % 64)) s
  | .i64shru, s => bin64 (fun a b => a >>> (b.toNat % 64)) s
  | .i64rotl, s => bin64 (fun a b => a.rotateLeft (b.toNat % 64)) s
  | .i64rotr, s => bin64 (fun a b => a.rotateRight (b.toNat % 64)) s
  | .i64divu, s =>
    match s.stack with
    | .i64 b :: .i64 a :: r =>
      if b = 0#64 then none
      else some { s with stack := .i64 (BitVec.ofNat 64 (a.toNat / b.toNat)) :: r }
    | _ => none
  | .i64divs, s =>
    match s.stack with
    | .i64 b :: .i64 a :: r =>
      if b = 0#64 ∨ (a = BitVec.intMin 64 ∧ b = BitVec.allOnes 64) then none
      else some { s with stack := .i64 (BitVec.ofInt 64 (Int.tdiv a.toInt b.toInt)) :: r }
    | _ => none
  | .i64eq, s => cmp64 (fun a b => a == b) s
  | .i64ne, s => cmp64 (fun a b => a != b) s
  | .i64ltu, s => cmp64 (fun a b => a.ult b) s
  | .i64leu, s => cmp64 (fun a b => a.ule b) s
  | .i64gtu, s => cmp64 (fun a b => b.ult a) s
  | .i64geu, s => cmp64 (fun a b => b.ule a) s
  | .i64lts, s => cmp64 (fun a b => a.slt b) s
  | .i64les, s => cmp64 (fun a b => a.sle b) s
  | .i64gts, s => cmp64 (fun a b => b.slt a) s
  | .i64ges, s => cmp64 (fun a b => b.sle a) s
  | .i64eqz, s =>
    match s.stack with
    | .i64 a :: r => some { s with stack := .i32 (bool32 (a == 0#64)) :: r }
    | _ => none
  | .i32add, s => bin32 (· + ·) s
  | .i32sub, s => bin32 (· - ·) s
  | .i32shl, s => bin32 (fun a b => a <<< (b.toNat % 32)) s
  | .i32gtu, s =>
    match s.stack with
    | .i32 b :: .i32 a :: r => some { s with stack := .i32 (bool32 (b.ult a)) :: r }
    | _ => none
  | .i32eq, s =>
    match s.stack with
    | .i32 b :: .i32 a :: r => some { s with stack := .i32 (bool32 (a == b)) :: r }
    | _ => none
  | .i32wrap, s =>
    match s.stack with
    | .i64 a :: r => some { s with stack := .i32 (BitVec.ofNat 32 a.toNat) :: r }
    | _ => none
  | .i64extu, s =>
    match s.stack with
    | .i32 a :: r => some { s with stack := .i64 (BitVec.ofNat 64 a.toNat) :: r }
    | _ => none
  | .select, s =>
    match s.stack with
    | .i32 c :: v2 :: v1 :: r => some { s with stack := (if c ≠ 0#32 then v1 else v2) :: r }
    | _ => none
  | _, _ => none

/-- Outcomes of running a list of instructions. -/
inductive Res where
  | normal (s : WState)
  | br (n : Nat) (s : WState)
  | exit (code : Nat)
  | halted (s : WState)
  | fault

/-- Leaving a labelled block (or `if`) entered with operand stack `entry`: a branch to label 0 is
consumed and the operand stack is unwound to its height at entry; other branches propagate. -/
inductive BlockOut (entry : List Val) : Res → Res → Prop where
  | norm {s} : BlockOut entry (.normal s) (.normal s)
  | br0 {s} : BlockOut entry (.br 0 s) (.normal { s with stack := entry })
  | brS {n s} : BlockOut entry (.br (n + 1) s) (.br n s)
  | exit {c} : BlockOut entry (.exit c) (.exit c)
  | halted {s} : BlockOut entry (.halted s) (.halted s)
  | fault : BlockOut entry .fault .fault

/-- Results that abandon the rest of an instruction sequence. -/
def Res.abrupt : Res → Prop
  | .normal _ => False
  | _ => True

mutual
inductive RunI : WI → WState → Res → Prop where
  | simple {i s s'} : i.isCtl = false → stepI i s = some s' → RunI i s (.normal s')
  | simpleFault {i s} : i.isCtl = false → stepI i s = none → RunI i s .fault
  | block {body s r r'} : Run body s r → BlockOut s.stack r r' → RunI (.block body) s r'
  | loopNormal {body s s'} : Run body s (.normal s') → RunI (.loop body) s (.normal s')
  | loopBr0 {body s s' r} :
      Run body s (.br 0 s') → RunI (.loop body) { s' with stack := s.stack } r →
      RunI (.loop body) s r
  | loopBrS {body s n s'} : Run body s (.br (n + 1) s') → RunI (.loop body) s (.br n s')
  | loopExit {body s c} : Run body s (.exit c) → RunI (.loop body) s (.exit c)
  | loopHalted {body s s'} : Run body s (.halted s') → RunI (.loop body) s (.halted s')
  | loopFault {body s} : Run body s .fault → RunI (.loop body) s .fault
  | iteThen {thn s r c res res'} :
      s.stack = .i32 c :: r → c ≠ 0#32 → Run thn { s with stack := r } res →
      BlockOut r res res' → RunI (.ite thn) s res'
  | iteElse {thn s r c} :
      s.stack = .i32 c :: r → c = 0#32 → RunI (.ite thn) s (.normal { s with stack := r })
  | iteFault {thn s} : (∀ c r, s.stack ≠ .i32 c :: r) → RunI (.ite thn) s .fault
  | br {l s} : RunI (.br l) s (.br l s)
  | brIfTaken {l s r c} :
      s.stack = .i32 c :: r → c ≠ 0#32 → RunI (.brIf l) s (.br l { s with stack := r })
  | brIfNot {l s r c} :
      s.stack = .i32 c :: r → c = 0#32 → RunI (.brIf l) s (.normal { s with stack := r })
  | brIfFault {l s} : (∀ c r, s.stack ≠ .i32 c :: r) → RunI (.brIf l) s .fault
  | brTable {ls d s r i} :
      s.stack = .i32 i :: r →
      RunI (.brTable ls d) s (.br (ls.getD i.toNat d) { s with stack := r })
  | brTableFault {ls d s} : (∀ i r, s.stack ≠ .i32 i :: r) → RunI (.brTable ls d) s .fault
  | exitTrap {c s} : RunI (.exitTrap c) s (.exit c)
  | exitHalt {s} : RunI .exitHalt s (.halted s)

inductive Run : List WI → WState → Res → Prop where
  | nil {s} : Run [] s (.normal s)
  | consNormal {i is s s' r} : RunI i s (.normal s') → Run is s' r → Run (i :: is) s r
  | consAbrupt {i is s r} : RunI i s r → r.abrupt → Run (i :: is) s r
end

end Wasm
end WordDialect
