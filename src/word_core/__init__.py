"""Word type system and primitives.

Defines the fundamental types of the Word Dialect:
  - WORD[N]: N-bit word (32, 64, 128)
  - PTR: Pointer (first-class citizen, representation-compatible with WORD)
  - Address: Memory address

Proof obligations verified in word_type_safety.lean.
"""
