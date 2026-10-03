"""Word IR → Assembly code generation.

Subpackages:
  - register_allocator: Graph coloring for Word → machine register mapping
  - codegen_x86: x86-64 assembly backend
  - codegen_arm: ARM Thumb-2 assembly backend
  - codegen_riscv: RISC-V assembly backend

All backends preserve Word IR semantics under their respective ISA contracts.

Awaiting Agent 1 publication of ir_ast.py.
"""
