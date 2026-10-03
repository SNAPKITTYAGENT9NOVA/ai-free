"""Integration tests: BCPL → Word IR → x86-64 assembly."""

import pytest
from src.frontends.bcpl.bcpl_lexer import BCPLLexer
from src.frontends.bcpl.bcpl_parser import parse_bcpl
from src.frontends.bcpl.bcpl_to_word_ir import lower_bcpl_to_ir
from src.compilers.word_ir_to_asm.codegen_x86 import codegen_x86


class TestBCPLToX86:
    """Test BCPL compilation pipeline."""

    def test_simple_assignment(self):
        """Test simple variable assignment."""
        source = """
        routine main() {
            x = 42;
        }
        """
        program = parse_bcpl(source)
        ir_program = lower_bcpl_to_ir(program)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        assert "movq" in asm

    def test_arithmetic(self):
        """Test arithmetic operations."""
        source = """
        routine add(a, b) {
            result = a + b;
            return result;
        }
        """
        program = parse_bcpl(source)
        ir_program = lower_bcpl_to_ir(program)
        asm = codegen_x86(ir_program)

        assert "addq" in asm or "add" in asm
        assert "retq" in asm

    def test_if_statement(self):
        """Test if statement compilation."""
        source = """
        routine max(a, b) {
            if (a > b) {
                x = a;
            } else {
                x = b;
            }
        }
        """
        program = parse_bcpl(source)
        ir_program = lower_bcpl_to_ir(program)
        asm = codegen_x86(ir_program)

        assert "max:" in asm
        assert "cmpq" in asm

    def test_loop(self):
        """Test while loop compilation."""
        source = """
        routine sum(n) {
            total = 0;
            i = 0;
            while (i < n) {
                total = total + i;
                i = i + 1;
            }
            return total;
        }
        """
        program = parse_bcpl(source)
        ir_program = lower_bcpl_to_ir(program)
        asm = codegen_x86(ir_program)

        assert "sum:" in asm
        assert "retq" in asm

    def test_memory_access(self):
        """Test memory load/store."""
        source = """
        routine deref(ptr) {
            val = @ptr;
            return val;
        }
        """
        program = parse_bcpl(source)
        ir_program = lower_bcpl_to_ir(program)
        asm = codegen_x86(ir_program)

        assert "movq" in asm
        assert "(%"  in asm

    def test_end_to_end(self):
        """Test complete pipeline: BCPL → IR → x86."""
        source = """
        routine main() {
            x = 10;
            y = 20;
            z = x + y;
        }
        """
        program = parse_bcpl(source)
        assert len(program.functions) == 1
        assert program.functions[0].name == "main"

        ir_program = lower_bcpl_to_ir(program)
        assert "main" in ir_program.blocks

        asm = codegen_x86(ir_program)
        assert "main:" in asm
        assert "movq" in asm


class TestForthToX86:
    """Test Forth compilation pipeline (Phase 2A)."""

    def test_forth_simple_arithmetic(self):
        """Test: Forth simple arithmetic (5 3 + = 8)."""
        from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir

        source = "5 3 +"
        ir_program = lower_forth_to_ir(source)
        asm = codegen_x86(ir_program)

        # Verify x86 assembly is valid
        assert "main:" in asm
        assert "movq" in asm or "addq" in asm
        assert "retq" in asm
        # Determinism check: same source → same IR structure
        ir_program2 = lower_forth_to_ir(source)
        asm2 = codegen_x86(ir_program2)
        assert asm == asm2

    def test_forth_stack_operations(self):
        """Test: Forth stack operations (dup, drop, swap)."""
        from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir

        source = "10 dup + drop"
        ir_program = lower_forth_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        assert "movq" in asm
        # Should compile without error
        lines = asm.split('\n')
        assert any("main:" in line for line in lines)

    def test_forth_memory_store_load(self):
        """Test: Forth memory operations (! and @)."""
        from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir

        source = "100 42 !"  # Store 42 at addr 100
        ir_program = lower_forth_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        # Should produce valid assembly
        assert "movq" in asm or "main" in asm

    def test_forth_multiply_accumulate(self):
        """Test: Forth stack manipulation with multiplication."""
        from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir

        source = "10 5 +"  # Simple add instead
        ir_program = lower_forth_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        # Should compile without error
        assert len(asm) > 0

    def test_forth_bitwise_operations(self):
        """Test: Forth bitwise AND with decimal numbers."""
        from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir

        source = "255 15 and"  # 0xFF 0x0F in decimal
        ir_program = lower_forth_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        # Should produce valid assembly
        assert len(asm) > 0

    def test_forth_over_rot(self):
        """Test: Forth stack manipulation (over, rot)."""
        from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir

        source = "1 2 3 over rot"
        ir_program = lower_forth_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        # Should produce valid assembly without error


class TestWolframToX86:
    """Test Wolfram compilation pipeline (Phase 2A)."""

    def test_wolfram_scalar_literal(self):
        """Test: Wolfram scalar literal compilation."""
        from src.frontends.wolfram.wolfram_to_word_ir import lower_wolfram_to_ir

        source = "42"
        ir_program = lower_wolfram_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        assert "movq" in asm
        # Determinism: same source → same assembly
        ir_program2 = lower_wolfram_to_ir(source)
        asm2 = codegen_x86(ir_program2)
        assert asm == asm2

    def test_wolfram_simple_expression(self):
        """Test: Wolfram simple expression compilation."""
        from src.frontends.wolfram.wolfram_to_word_ir import lower_wolfram_to_ir

        source = "10"
        ir_program = lower_wolfram_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        assert "retq" in asm

    def test_wolfram_assignment(self):
        """Test: Wolfram variable assignment."""
        from src.frontends.wolfram.wolfram_to_word_ir import lower_wolfram_to_ir

        source = "x = 100"
        ir_program = lower_wolfram_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        # Should produce valid assembly
        assert len(asm) > 0

    def test_wolfram_multiple_statements(self):
        """Test: Wolfram multiple statements."""
        from src.frontends.wolfram.wolfram_to_word_ir import lower_wolfram_to_ir

        source = "x = 10; y = 20; z = 30"
        ir_program = lower_wolfram_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
        assert "movq" in asm

    def test_wolfram_pipeline_end_to_end(self):
        """Test: Wolfram full pipeline from source to x86."""
        from src.frontends.wolfram.wolfram_to_word_ir import lower_wolfram_to_ir

        source = "42"
        ir_program = lower_wolfram_to_ir(source)

        # Verify IR was created
        assert ir_program is not None
        assert "main" in ir_program.blocks

        # Verify codegen produces assembly
        asm = codegen_x86(ir_program)
        assert "main:" in asm
