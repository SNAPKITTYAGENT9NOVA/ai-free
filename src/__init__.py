"""Universal Word Dialect Stack compiler.

A formally-verifiable compiler that transforms multiple language frontends
(BCPL, Forth, Wolfram) into a canonical Word Intermediate Representation (Word IR),
then lowers to machine-specific assembly (x86-64, ARM, RISC-V).

Core components:
  - word_core: Type system (WORD[N], PTR, Address)
  - word_machine: Virtual machine for Word IR execution
  - word_ir: Intermediate representation and AST
  - frontends: Language-specific parsers and lowering passes
  - compilers: IR-to-assembly code generators
"""

__version__ = "0.1.0"
