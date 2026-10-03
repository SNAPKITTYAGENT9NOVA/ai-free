/-!
# Wasm.Isa

A model of the WebAssembly subset the backend emits, following the WebAssembly core
specification:

* typed operand stack (`i32` / `i64`), mutable globals, linear memory, a function table;
* `i64.load`/`i64.store` on **bytes** (little-endian), taking an `i32` address plus a static offset
  computed in unbounded arithmetic; an access with any byte outside the memory traps. There is no
  aliasing assumption: overlapping accesses are modelled exactly;
* `i64.div_s` traps on division by zero and on `INT64_MIN / -1`; `i64.div_u` traps on division by
  zero; shifts and rotates take the count modulo 64 (the spec's definition);
* `if` (without `else`) and `loop`/`br` with the spec's label discipline, including unwinding the
  operand stack to the label height on a branch; `call_indirect` through the function table (a
  callee runs on a fresh operand stack and returns the single value it leaves).

Two host calls are terminal pseudo-instructions: `exitTrap c` (`i32.const c; call $proc_exit`) and
`exitHalt` (`global.get sp; call $halt`, which dumps the machine state and exits 0).

Semantics is a big-step relation, so loops need no fuel. That the model matches a real
WebAssembly engine is an assumption, tested by differential execution (`wasmw`).
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
  globals : Nat → Val
  mem : WMem

inductive WI where
  | i32const (v : W32)
  | i64const (v : W)
  | globalGet (i : Nat)
  | globalSet (i : Nat)
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
  | loop (body : List WI)
  | ite (thn : List WI)
  | br (l : Nat)
  | callIndirect
  | exitTrap (code : Nat)
  | exitHalt

/-- Control constructs, calls and terminal pseudo-instructions (handled by `RunI`, not `stepI`). -/
def WI.isCtl : WI → Bool
  | .loop _ | .ite _ | .br _ | .callIndirect | .exitTrap _ | .exitHalt => true
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
  | .globalGet i, s => some { s with stack := s.globals i :: s.stack }
  | .globalSet i, s =>
    match s.stack with
    | v :: r => some { s with stack := r, globals := fun j => if j = i then v else s.globals j }
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

/-- Leaving a labelled construct entered with operand stack `entry`: a branch to label 0 is
consumed (for `if`; `loop` re-enters) and the operand stack is unwound to its height at entry;
other branches propagate outward. -/
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

/-- A function table: entry `i` is the body of function `i`. -/
abbrev Funcs := List (List WI)

mutual
inductive RunI (fs : Funcs) : WI → WState → Res → Prop where
  | simple {i s s'} : i.isCtl = false → stepI i s = some s' → RunI fs i s (.normal s')
  | simpleFault {i s} : i.isCtl = false → stepI i s = none → RunI fs i s .fault
  | loopNormal {body s s'} : Run fs body s (.normal s') → RunI fs (.loop body) s (.normal s')
  | loopBr0 {body s s' r} :
      Run fs body s (.br 0 s') → RunI fs (.loop body) { s' with stack := s.stack } r →
      RunI fs (.loop body) s r
  | loopBrS {body s n s'} : Run fs body s (.br (n + 1) s') → RunI fs (.loop body) s (.br n s')
  | loopExit {body s c} : Run fs body s (.exit c) → RunI fs (.loop body) s (.exit c)
  | loopHalted {body s s'} : Run fs body s (.halted s') → RunI fs (.loop body) s (.halted s')
  | loopFault {body s} : Run fs body s .fault → RunI fs (.loop body) s .fault
  | iteThen {thn s r c res res'} :
      s.stack = .i32 c :: r → c ≠ 0#32 → Run fs thn { s with stack := r } res →
      BlockOut r res res' → RunI fs (.ite thn) s res'
  | iteElse {thn s r c} :
      s.stack = .i32 c :: r → c = 0#32 → RunI fs (.ite thn) s (.normal { s with stack := r })
  | iteFault {thn s} : (∀ c r, s.stack ≠ .i32 c :: r) → RunI fs (.ite thn) s .fault
  | br {l s} : RunI fs (.br l) s (.br l s)
  | callNormal {s r i body s' v} :
      s.stack = .i32 i :: r → fs[i.toNat]? = some body →
      Run fs body { s with stack := [] } (.normal s') → s'.stack = [.i32 v] →
      RunI fs .callIndirect s (.normal { s' with stack := .i32 v :: r })
  | callBad {s r i body s'} :
      s.stack = .i32 i :: r → fs[i.toNat]? = some body →
      Run fs body { s with stack := [] } (.normal s') → (∀ v, s'.stack ≠ [.i32 v]) →
      RunI fs .callIndirect s .fault
  | callAbrupt {s r i body res} :
      s.stack = .i32 i :: r → fs[i.toNat]? = some body →
      Run fs body { s with stack := [] } res → res.abrupt →
      RunI fs .callIndirect s (match res with | .br _ _ => .fault | other => other)
  | callMissing {s r i} :
      s.stack = .i32 i :: r → fs[i.toNat]? = none → RunI fs .callIndirect s .fault
  | callBadStack {s} : (∀ i r, s.stack ≠ .i32 i :: r) → RunI fs .callIndirect s .fault
  | exitTrap {c s} : RunI fs (.exitTrap c) s (.exit c)
  | exitHalt {s} : RunI fs .exitHalt s (.halted s)

inductive Run (fs : Funcs) : List WI → WState → Res → Prop where
  | nil {s} : Run fs [] s (.normal s)
  | consNormal {i is s s' r} : RunI fs i s (.normal s') → Run fs is s' r → Run fs (i :: is) s r
  | consAbrupt {i is s r} : RunI fs i s r → r.abrupt → Run fs (i :: is) s r
end

end Wasm
end WordDialect
