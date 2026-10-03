"""Compiler pipeline: lowering and code generation.

Subpackages:
  - wolfram_to_word_ir: Symbolic math → Word IR lowering
  - word_ir_to_asm: Word IR → ISA-specific assembly

All lowering transforms are formally verified in proofs/.
"""
