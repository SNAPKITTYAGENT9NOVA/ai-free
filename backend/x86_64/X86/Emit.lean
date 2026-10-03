import X86.Lower

/-!
# X86.Emit

GNU `as` (Intel syntax) text for a lowered program, plus the small runtime.

The program text is produced from exactly the instruction list `lowerProg` builds, one
`.L<index>:` label per x86 instruction, so the text and the verified model cannot diverge.

The runtime (`prologue`, `epilogue`) is the only hand-written assembly. It
* sets `r12 r13 r14 r15` to the conventions in `X86.Lower`,
* implements `exitHalt` as: write `depth`, the data stack, IR memory and the virtual register
  file to stdout (raw little-endian 64-bit words), then `exit(0)`,
* implements `exitTrap t` as `exit(code t)`.
-/

namespace WordDialect
namespace X86
namespace Emit

open Reg

def trapCode : Trap → Nat
  | .stackUnderflow => 1
  | .badAddress => 2
  | .divideByZero => 3
  | .badPc => 4
  | .returnUnderflow => 5

def regName : Reg → String
  | .rax => "rax" | .rcx => "rcx" | .rdx => "rdx" | .rbx => "rbx" | .rsp => "rsp"
  | .r12 => "r12" | .r13 => "r13" | .r14 => "r14" | .r15 => "r15"

def ccName : Cc → String
  | .e => "e" | .ne => "ne" | .b => "b" | .be => "be" | .a => "a" | .ae => "ae"
  | .l => "l" | .le => "le" | .g => "g" | .ge => "ge"

def hex (n : Nat) : String := "0x" ++ String.ofList (Nat.toDigits 16 n)

def lbl (t : Nat) : String := s!".L{t}"

def mem (b : Reg) (disp : Int) : String :=
  if disp = 0 then s!"qword ptr [{regName b}]"
  else if disp > 0 then s!"qword ptr [{regName b} + {disp}]"
  else s!"qword ptr [{regName b} - {-disp}]"

def instr : Instr Nat → String
  | .movImm d v => s!"movabs {regName d}, {hex v.toNat}"
  | .movRR d s => s!"mov {regName d}, {regName s}"
  | .load d b disp => s!"mov {regName d}, {mem b disp}"
  | .store b disp s => s!"mov {mem b disp}, {regName s}"
  | .loadIdx d b i => s!"mov {regName d}, qword ptr [{regName b} + {regName i}*8]"
  | .storeIdx b i s => s!"mov qword ptr [{regName b} + {regName i}*8], {regName s}"
  | .add d s => s!"add {regName d}, {regName s}"
  | .sub d s => s!"sub {regName d}, {regName s}"
  | .imul d s => s!"imul {regName d}, {regName s}"
  | .and d s => s!"and {regName d}, {regName s}"
  | .or d s => s!"or {regName d}, {regName s}"
  | .xor d s => s!"xor {regName d}, {regName s}"
  | .addImm d v => s!"add {regName d}, {v}"
  | .not d => s!"not {regName d}"
  | .neg d => s!"neg {regName d}"
  | .cmp a b => s!"cmp {regName a}, {regName b}"
  | .cmpImm a v => s!"cmp {regName a}, {v}"
  | .test a b => s!"test {regName a}, {regName b}"
  | .shlCl d => s!"shl {regName d}, cl"
  | .shrCl d => s!"shr {regName d}, cl"
  | .rolCl d => s!"rol {regName d}, cl"
  | .rorCl d => s!"ror {regName d}, cl"
  | .cmov c d s => s!"cmov{ccName c} {regName d}, {regName s}"
  | .div s => s!"div {regName s}"
  | .idiv s => s!"idiv {regName s}"
  | .cqo => "cqo"
  | .jmp t => s!"jmp {lbl t}"
  | .jcc c t => s!"j{ccName c} {lbl t}"
  | .call t => s!"call {lbl t}"
  | .ret => "ret"
  | .exitHalt => "jmp .Lhalt"
  | .exitTrap t => s!"jmp .Ltrap{trapCode t}"

def body (code : List (Instr Nat)) : String :=
  String.intercalate "\n" (code.zipIdx.map fun (i, k) => s!"{lbl k}:\n\t{instr i}") ++ "\n"

/-- Data-stack placement: `capacity` words ending at `dEnd`. -/
structure Runtime where
  dEnd : Nat
  capacity : Nat
  memImage : List Nat
  nregs : Nat

def Runtime.dBase (r : Runtime) : Nat := r.dEnd - 8 * r.capacity

def prologue (r : Runtime) : String :=
  "\t.intel_syntax noprefix\n\t.text\n\t.globl _start\n_start:\n" ++
  "\tmov r12, rsp\n\tlea r13, [rip + irmem]\n\tlea r14, [rip + regfile]\n" ++
  s!"\tmovabs r15, {hex r.dEnd}\n"

def sysWrite (bufSetup : String) (len : String) : String :=
  s!"\t{bufSetup}\n\tmov rdx, {len}\n\tmov rax, 1\n\tmov rdi, 1\n\tsyscall\n"

def epilogue (r : Runtime) : String :=
  let m := r.memImage.length
  ".Lhalt:\n" ++
  s!"\tmovabs rax, {hex r.dEnd}\n\tsub rax, r15\n\tshr rax, 3\n\tlea rbx, [rip + hdr]\n\tmov qword ptr [rbx], rax\n" ++
  sysWrite "mov rsi, rbx" "8" ++
  "\tlea rbx, [rip + hdr]\n\tmov rdx, qword ptr [rbx]\n\tshl rdx, 3\n\tmov rsi, r15\n\tmov rax, 1\n\tmov rdi, 1\n\tsyscall\n" ++
  sysWrite "lea rsi, [rip + irmem]" (toString (8 * m)) ++
  sysWrite "lea rsi, [rip + regfile]" (toString (8 * r.nregs)) ++
  "\txor rdi, rdi\n\tjmp .Lexit\n" ++
  String.join ((List.range 5).map fun k => s!".Ltrap{k + 1}:\n\tmov rdi, {k + 1}\n\tjmp .Lexit\n") ++
  ".Lexit:\n\tmov rax, 60\n\tsyscall\n" ++
  "\t.data\n\t.balign 8\nirmem:\n" ++
  String.join (r.memImage.map fun v => s!"\t.quad {v}\n") ++
  "\t.section .dstack, \"aw\", @nobits\n\t.balign 8\n" ++
  s!"\t.skip {8 * r.capacity}\n" ++
  "\t.bss\n\t.balign 8\nhdr:\n\t.skip 8\nregfile:\n" ++ s!"\t.skip {8 * (r.nregs + 1)}\n"

/-- Full assembly text for a lowered program. -/
def program (r : Runtime) (code : List (Instr Nat)) : String :=
  prologue r ++ body code ++ epilogue r

end Emit
end X86
end WordDialect
