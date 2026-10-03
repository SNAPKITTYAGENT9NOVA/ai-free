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
    """Test Forth compilation pipeline."""

    def test_forth_simple(self):
        """Test simple Forth arithmetic."""
        from src.frontends.forth.forth_to_word_ir import lower_forth_to_ir

        source = "5 10 + ."
        ir_program = lower_forth_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm


class TestWolframToX86:
    """Test Wolfram compilation pipeline."""

    def test_wolfram_simple(self):
        """Test simple Wolfram expression."""
        from src.frontends.wolfram.wolfram_to_word_ir import lower_wolfram_to_ir

        source = "2 + 3"
        ir_program = lower_wolfram_to_ir(source)
        asm = codegen_x86(ir_program)

        assert "main:" in asm
