import WordDialect
import WordIR
import Forth
import BCPL
import Wolfram
import Lean
open Lean Elab Command

/-- Collect every declaration in namespace `WordDialect` and the axioms it depends on. -/
elab "#audit_wd" : command => do
  let env ← getEnv
  let mut thms : Nat := 0
  let mut used : Std.HashMap Name Nat := {}
  let mut bad : Array Name := #[]
  for (name, info) in env.constants.toList do
    if (`WordDialect).isPrefixOf name && !name.isInternal then
      match info with
      | .thmInfo _ =>
        thms := thms + 1
        let axs ← liftCoreM (collectAxioms name)
        for a in axs do
          used := used.insert a (used.getD a 0 + 1)
          if a != ``propext && a != ``Quot.sound && a != ``Classical.choice then
            bad := bad.push name
      | _ => pure ()
  logInfo m!"theorems audited: {thms}"
  logInfo m!"axioms used (name, #theorems): {used.toList}"
  logInfo m!"theorems using non-standard axioms: {bad}"

#audit_wd
