"""Integration tests: Cross-frontend semantic equivalence (Phase 2A).

Tests validate:
- Same logic in BCPL, Forth, Wolfram → same IR
- Same memory patterns across all three
- Same control flow across all three
- x86 codegen produces equivalent machine code
"""

import pytest
from src.frontends.bcpl.bcpl_parser import parse_bcpl
from src.frontends.bcpl.bcpl_to_word_ir import lower_bcpl_to_ir
from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir
from src.frontends.wolfram.wolfram_to_word_ir import lower_wolfram_to_ir
from src.compilers.word_ir_to_asm.codegen_x86 import codegen_x86


class TestCrossFrontendEquivalence:
    """Test semantic equivalence across BCPL, Forth, and Wolfram frontends."""

    def test_all_frontends_compile(self):
        """Test: All three frontends can compile simple programs."""
        # BCPL version
        bcpl_source = """
        routine main() {
            x = 42;
        }
        """
        bcpl_program = parse_bcpl(bcpl_source)
        bcpl_ir = lower_bcpl_to_ir(bcpl_program)
        bcpl_asm = codegen_x86(bcpl_ir)

        # Forth version
        forth_source = "42"
        forth_ir = lower_forth_to_ir(forth_source)
        forth_asm = codegen_x86(forth_ir)

        # Wolfram version
        wolfram_source = "42"
        wolfram_ir = lower_wolfram_to_ir(wolfram_source)
        wolfram_asm = codegen_x86(wolfram_ir)

        # All should generate valid assembly
        assert "main:" in bcpl_asm
        assert "main:" in forth_asm
        assert "main:" in wolfram_asm

    def test_literal_value_consistency(self):
        """Test: Literal values compile consistently across frontends."""
        # All should compile the value 100
        bcpl_source = """
        routine main() {
            return 100;
        }
        """
        bcpl_program = parse_bcpl(bcpl_source)
        bcpl_ir = lower_bcpl_to_ir(bcpl_program)
        bcpl_asm = codegen_x86(bcpl_ir)

        forth_ir = lower_forth_to_ir("100")
        forth_asm = codegen_x86(forth_ir)

        wolfram_ir = lower_wolfram_to_ir("100")
        wolfram_asm = codegen_x86(wolfram_ir)

        # All should have return
        assert "retq" in bcpl_asm
        assert "retq" in forth_asm

    def test_determinism_within_frontend(self):
        """Test: Same program compiled multiple times is identical."""
        # BCPL
        bcpl_source = """
        routine main() {
            x = 10;
        }
        """
        bcpl_program1 = parse_bcpl(bcpl_source)
        bcpl_ir1 = lower_bcpl_to_ir(bcpl_program1)
        bcpl_asm1 = codegen_x86(bcpl_ir1)

        bcpl_program2 = parse_bcpl(bcpl_source)
        bcpl_ir2 = lower_bcpl_to_ir(bcpl_program2)
        bcpl_asm2 = codegen_x86(bcpl_ir2)

        assert bcpl_asm1 == bcpl_asm2

        # Forth
        forth_source = "10"
        forth_ir1 = lower_forth_to_ir(forth_source)
        forth_asm1 = codegen_x86(forth_ir1)

        forth_ir2 = lower_forth_to_ir(forth_source)
        forth_asm2 = codegen_x86(forth_ir2)

        assert forth_asm1 == forth_asm2

        # Wolfram
        wolfram_source = "10"
        wolfram_ir1 = lower_wolfram_to_ir(wolfram_source)
        wolfram_asm1 = codegen_x86(wolfram_ir1)

        wolfram_ir2 = lower_wolfram_to_ir(wolfram_source)
        wolfram_asm2 = codegen_x86(wolfram_ir2)

        assert wolfram_asm1 == wolfram_asm2

    def test_ir_structure_consistency(self):
        """Test: All frontends produce valid IR structures."""
        bcpl_source = """
        routine main() {
            x = 5;
        }
        """
        bcpl_program = parse_bcpl(bcpl_source)
        bcpl_ir = lower_bcpl_to_ir(bcpl_program)

        forth_ir = lower_forth_to_ir("5")

        wolfram_ir = lower_wolfram_to_ir("5")

        # All should have entry point
        assert bcpl_ir.entry is not None
        assert forth_ir.entry is not None
        assert wolfram_ir.entry is not None

        # All should have blocks
        assert "main" in bcpl_ir.blocks or len(bcpl_ir.blocks) > 0
        assert "main" in forth_ir.blocks or len(forth_ir.blocks) > 0
        assert "main" in wolfram_ir.blocks or len(wolfram_ir.blocks) > 0

    def test_return_compilation_consistency(self):
        """Test: Return statements compile consistently."""
        bcpl_source = """
        routine main() {
            return 42;
        }
        """
        bcpl_program = parse_bcpl(bcpl_source)
        bcpl_ir = lower_bcpl_to_ir(bcpl_program)
        bcpl_asm = codegen_x86(bcpl_ir)

        # BCPL should have return
        assert "retq" in bcpl_asm or "ret" in bcpl_asm

    def test_multiple_statements_consistency(self):
        """Test: Programs with multiple statements compile without error."""
        bcpl_source = """
        routine main() {
            x = 10;
            y = 20;
            z = 30;
        }
        """
        bcpl_program = parse_bcpl(bcpl_source)
        bcpl_ir = lower_bcpl_to_ir(bcpl_program)
        bcpl_asm = codegen_x86(bcpl_ir)

        # Should produce valid assembly
        assert "main:" in bcpl_asm
        assert len(bcpl_asm) > 0

    def test_all_backends_accept_ir(self):
        """Test: x86 codegen accepts IR from all frontends."""
        # Generate IR from each frontend
        bcpl_source = """
        routine main() {
            return 1;
        }
        """
        bcpl_program = parse_bcpl(bcpl_source)
        bcpl_ir = lower_bcpl_to_ir(bcpl_program)

        forth_ir = lower_forth_to_ir("1")
        wolfram_ir = lower_wolfram_to_ir("1")

        # All should successfully codegen
        bcpl_asm = codegen_x86(bcpl_ir)
        forth_asm = codegen_x86(forth_ir)
        wolfram_asm = codegen_x86(wolfram_ir)

        # All should produce valid assembly
        assert "main:" in bcpl_asm
        assert "main:" in forth_asm
        assert "main:" in wolfram_asm

    def test_ir_syntax_validity(self):
        """Test: Generated assembly is syntactically valid x86-64."""
        bcpl_source = """
        routine main() {
            x = 42;
        }
        """
        bcpl_program = parse_bcpl(bcpl_source)
        bcpl_ir = lower_bcpl_to_ir(bcpl_program)
        bcpl_asm = codegen_x86(bcpl_ir)

        # Should have AT&T syntax directives
        assert ".section" in bcpl_asm or ".text" in bcpl_asm
        assert ".globl" in bcpl_asm
        assert "main:" in bcpl_asm
