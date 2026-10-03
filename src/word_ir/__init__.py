"""Word Intermediate Representation (Word IR).

Canonical AST for the universal Word Dialect.
All language frontends (BCPL, Forth, Wolfram) lower to this representation.
All backends (x86-64, ARM, RISC-V) accept this representation.

IR nodes: WORD, PTR, LOAD, STORE, ADD, SUB, MUL, AND, OR, XOR, SHL, SHR,
          ROT, CMP, JMP, CALL, RET, ALLOC.

Awaiting Agent 1 publication of ir_ast.py.
"""
