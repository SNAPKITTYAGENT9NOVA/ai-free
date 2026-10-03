"""Word Machine Virtual Machine.

Executes Word IR with deterministic semantics:
  - Register file (W0..WN general-purpose WORD registers)
  - Linear address space with allocation tracking
  - Stack-based calling convention
  - Halt detection and cycle counting for termination analysis
"""
