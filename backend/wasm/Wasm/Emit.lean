import Wasm.Lower

/-!
# Wasm.Emit

WebAssembly text (WAT) for a lowered program, plus the small runtime. The instruction text is
printed from exactly the `WI` list `lowerProg` builds, so the text and the verified model cannot
diverge. Hand-written: the imports, the memory declaration with the IR memory image, and the `$halt`
helper that dumps the final state (data-stack depth, data stack, IR memory, virtual registers as raw
little-endian 64-bit words) through WASI `fd_write` and exits 0. Traps are `proc_exit(code)`.
-/

namespace WordDialect
namespace Wasm
namespace Emit

/-- Placement of the runtime regions in linear memory. -/
structure Runtime where
  memImage : List Nat
  nregs : Nat

def Runtime.rf (_ : Runtime) : Nat := 0x1000
def Runtime.mb (r : Runtime) : Nat := r.rf + 8 * r.nregs
def Runtime.dBase (_ : Runtime) : Nat := 0x10000
def Runtime.dEnd (r : Runtime) : Nat := r.dBase + 8 * 65536
def Runtime.rEnd (r : Runtime) : Nat := r.dEnd + 8 * 4096
def Runtime.pages (r : Runtime) : Nat := (r.rEnd + 65535) / 65536

def Runtime.layout (r : Runtime) : Layout :=
  { dEnd := r.dEnd, rEnd := r.rEnd, rf := r.rf, mb := r.mb, M := r.memImage.length }

def ind (d : Nat) : String := String.ofList (List.replicate (2 * d) ' ')

def line (d : Nat) (s : String) : String := ind d ++ s ++ "\n"

partial def instr (d : Nat) : WI → String
  | .i32const v => line d s!"i32.const {v.toNat}"
  | .i64const v => line d s!"i64.const {v.toNat}"
  | .localGet i => line d s!"local.get {i}"
  | .localSet i => line d s!"local.set {i}"
  | .i64load off => line d s!"i64.load offset={off}"
  | .i64store off => line d s!"i64.store offset={off}"
  | .i64add => line d "i64.add" | .i64sub => line d "i64.sub" | .i64mul => line d "i64.mul"
  | .i64and => line d "i64.and" | .i64or => line d "i64.or" | .i64xor => line d "i64.xor"
  | .i64shl => line d "i64.shl" | .i64shru => line d "i64.shr_u"
  | .i64rotl => line d "i64.rotl" | .i64rotr => line d "i64.rotr"
  | .i64divu => line d "i64.div_u" | .i64divs => line d "i64.div_s"
  | .i64eq => line d "i64.eq" | .i64ne => line d "i64.ne"
  | .i64ltu => line d "i64.lt_u" | .i64leu => line d "i64.le_u"
  | .i64gtu => line d "i64.gt_u" | .i64geu => line d "i64.ge_u"
  | .i64lts => line d "i64.lt_s" | .i64les => line d "i64.le_s"
  | .i64gts => line d "i64.gt_s" | .i64ges => line d "i64.ge_s"
  | .i64eqz => line d "i64.eqz"
  | .i32add => line d "i32.add" | .i32sub => line d "i32.sub" | .i32shl => line d "i32.shl"
  | .i32gtu => line d "i32.gt_u" | .i32eq => line d "i32.eq"
  | .i32wrap => line d "i32.wrap_i64"
  | .i64extu => line d "i64.extend_i32_u"
  | .select => line d "select"
  | .block b => line d "block" ++ String.join (b.map (instr (d + 1))) ++ line d "end"
  | .loop b => line d "loop" ++ String.join (b.map (instr (d + 1))) ++ line d "end"
  | .ite t => line d "if" ++ String.join (t.map (instr (d + 1))) ++ line d "end"
  | .br l => line d s!"br {l}"
  | .brIf l => line d s!"br_if {l}"
  | .brTable ls dflt => line d s!"br_table {String.intercalate " " (ls.map toString)} {dflt}"
  | .exitTrap c => line d s!"i32.const {c}" ++ line d "call $proc_exit"
  | .exitHalt => line d "local.get 1" ++ line d "call $halt"

def hexByte (n : Nat) : String :=
  let s := String.ofList (Nat.toDigits 16 n)
  "\\" ++ (if s.length < 2 then "0" ++ s else s)

def wordBytes (w : Nat) : String :=
  String.join ((List.range 8).map fun i => hexByte ((w / 256 ^ i) % 256))

def program (r : Runtime) (code : List WI) : String :=
  let m := r.memImage.length
  "(module\n" ++
  "  (import \"wasi_snapshot_preview1\" \"fd_write\" (func $fd_write (param i32 i32 i32 i32) (result i32)))\n" ++
  "  (import \"wasi_snapshot_preview1\" \"proc_exit\" (func $proc_exit (param i32)))\n" ++
  s!"  (memory (export \"memory\") {r.pages})\n" ++
  (if m = 0 then "" else
    s!"  (data (i32.const {r.mb}) \"{String.join (r.memImage.map wordBytes)}\")\n") ++
  "  (func $write (param $p i32) (param $n i32)\n" ++
  "    (i32.store (i32.const 16) (local.get $p))\n" ++
  "    (i32.store (i32.const 20) (local.get $n))\n" ++
  "    (drop (call $fd_write (i32.const 1) (i32.const 16) (i32.const 1) (i32.const 24))))\n" ++
  "  (func $halt (param $sp i32)\n" ++
  s!"    (i64.store (i32.const 0) (i64.extend_i32_u (i32.shr_u (i32.sub (i32.const {r.dEnd}) (local.get $sp)) (i32.const 3))))\n" ++
  "    (call $write (i32.const 0) (i32.const 8))\n" ++
  s!"    (call $write (local.get $sp) (i32.sub (i32.const {r.dEnd}) (local.get $sp)))\n" ++
  s!"    (call $write (i32.const {r.mb}) (i32.const {8 * m}))\n" ++
  s!"    (call $write (i32.const {r.rf}) (i32.const {8 * r.nregs}))\n" ++
  "    (call $proc_exit (i32.const 0)))\n" ++
  "  (func $main (export \"_start\") (local $pc i32) (local $sp i32) (local $rp i32)\n" ++
  s!"    (local.set $sp (i32.const {r.dEnd}))\n" ++
  s!"    (local.set $rp (i32.const {r.rEnd}))\n" ++
  String.join (code.map (instr 2)) ++
  "  )\n)\n"

end Emit
end Wasm
end WordDialect
