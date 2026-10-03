"""Wolfram language → Word IR compiler.

Transforms Wolfram symbolic expressions into executable Word IR:
  - Matrix multiplication C = A . B → loop of LOAD + MUL + ADD + STORE
  - Tensor indexing → pointer arithmetic + LOAD
  - Type inference and memory allocation

Semantic preservation proved in proofs/WolframLowering.lean.

Awaiting Agent 1 publication of ir_ast.py.
"""
