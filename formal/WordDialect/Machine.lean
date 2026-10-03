import WordDialect.Memory

/-!
# WordDialect.Machine

Universal Word IR instruction set, machine state, and the single-step operational semantics.

This file is the authoritative semantics. Every frontend translation and every backend
lowering is correct only relative to `step` as defined here.

Stack convention: `dstack` is a list whose head is the top of stack. A binary operation
on `a b` (with `b` on top) computes `a op b`, as in Forth.

Code addresses are instruction indices (`Nat`), so control flow is ISA-neutral.
Registers are an unbounded file of virtual registers (`Nat → Word n`); mapping them onto
physical registers is a backend concern.
-/

namespace WordDialect

inductive Instr (n : Nat) where
  | word   (w : Word n)
  | ptr    (p : Ptr n)
  | load | store
  | add | sub | mul | div | sdiv
  | and | or | xor | not
  | shl | shr | rotl | rotr
  | cmp    (c : Cond)
  | select
  | jmp    (target : Nat)
  | branch (target : Nat)
  | call   (target : Nat)
  | ret
  | push   (r : Nat)
  | pop    (r : Nat)
  | dup | drop | swap | over | rot
  | halt

inductive Trap where
  | stackUnderflow
  | badAddress
  | divideByZero
  | badPc
  | returnUnderflow
  deriving DecidableEq, Repr

structure State (n : Nat) where
  pc     : Nat
  dstack : List (Word n)
  rstack : List Nat
  regs   : Nat → Word n
  mem    : Memory n

inductive Outcome (n : Nat) where
  | next    (s : State n)
  | halted  (s : State n)
  | trapped (t : Trap)

abbrev Prog (n : Nat) := List (Instr n)

namespace State

/-- Continue at `pc + 1` with a new data stack. -/
def fall {n : Nat} (s : State n) (d : List (Word n)) : Outcome n :=
  .next { s with pc := s.pc + 1, dstack := d }

def setReg {n : Nat} (regs : Nat → Word n) (r : Nat) (v : Word n) : Nat → Word n :=
  fun i => if i = r then v else regs i

end State

/-- Semantics of one instruction in state `s` (the instruction is located at `s.pc`). -/
def exec {n : Nat} (i : Instr n) (s : State n) : Outcome n :=
  match i, s.dstack with
  | .word w, d => s.fall (w :: d)
  | .ptr p, d => s.fall (p.toWord :: d)
  | .load, a :: d =>
      match s.mem.read? a with
      | some v => s.fall (v :: d)
      | none => .trapped .badAddress
  | .store, a :: v :: d =>
      match s.mem.write? a v with
      | some m => .next { s with pc := s.pc + 1, dstack := d, mem := m }
      | none => .trapped .badAddress
  | .add, b :: a :: d => s.fall ((a + b) :: d)
  | .sub, b :: a :: d => s.fall ((a - b) :: d)
  | .mul, b :: a :: d => s.fall ((a * b) :: d)
  | .sdiv, b :: a :: d =>
      if b = 0#n then .trapped .divideByZero else s.fall (a.sdiv b :: d)
  | .div, b :: a :: d =>
      if b = 0#n then .trapped .divideByZero else s.fall (a.udiv b :: d)
  | .and, b :: a :: d => s.fall ((a &&& b) :: d)
  | .or,  b :: a :: d => s.fall ((a ||| b) :: d)
  | .xor, b :: a :: d => s.fall ((a ^^^ b) :: d)
  | .not, a :: d => s.fall ((~~~a) :: d)
  | .shl,  b :: a :: d => s.fall (Word.shl a b :: d)
  | .shr,  b :: a :: d => s.fall (Word.shr a b :: d)
  | .rotl, b :: a :: d => s.fall (Word.rotl a b :: d)
  | .rotr, b :: a :: d => s.fall (Word.rotr a b :: d)
  | .cmp c, b :: a :: d => s.fall (Word.ofBool (c.eval a b) :: d)
  | .select, c :: y :: x :: d => s.fall ((if Word.isTrue c then x else y) :: d)
  | .jmp t, _ => .next { s with pc := t }
  | .branch t, c :: d =>
      if Word.isTrue c then .next { s with pc := t, dstack := d }
      else s.fall d
  | .call t, _ => .next { s with pc := t, rstack := (s.pc + 1) :: s.rstack }
  | .ret, _ =>
      match s.rstack with
      | a :: rs => .next { s with pc := a, rstack := rs }
      | [] => .trapped .returnUnderflow
  | .push r, d => s.fall (s.regs r :: d)
  | .pop r, v :: d =>
      .next { s with pc := s.pc + 1, dstack := d, regs := State.setReg s.regs r v }
  | .dup,  a :: d => s.fall (a :: a :: d)
  | .drop, _ :: d => s.fall d
  | .swap, b :: a :: d => s.fall (a :: b :: d)
  | .over, b :: a :: d => s.fall (a :: b :: a :: d)
  | .rot,  c :: b :: a :: d => s.fall (a :: c :: b :: d)
  | .halt, _ => .halted s
  | _, _ => .trapped .stackUnderflow

def step {n : Nat} (p : Prog n) (s : State n) : Outcome n :=
  match p[s.pc]? with
  | none => .trapped .badPc
  | some i => exec i s

end WordDialect
