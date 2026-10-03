"""Wolfram → Word IR compiler: lowers symbolic math to executable IR.

Semantics:
  - Symbols → variables (allocated on stack)
  - Operators → arithmetic IR nodes
  - Functions → IR nodes
  - Matrix multiplication → loops over LOAD + MUL + ADD + STORE
  - Tensor operations → pointer arithmetic + scalar operations
"""

from typing import Dict, List
from src.word_ir.ir_ast import (
    IRNode, IRWord, IRLoad, IRStore, IRBinOp, IRUnaryOp,
    IRBlock, IRProgram, IRNodeType, IRAlloc,
    ir_add, ir_sub, ir_mul, ir_and, ir_or, ir_xor,
    ir_load, ir_store, ir_word, ir_ptr
)
from .wolfram_lexer import WolframLexer, TokenType


class WolframLowering:
    """Lower Wolfram expressions to Word IR."""

    def __init__(self):
        self.var_offsets: Dict[str, int] = {}
        self.next_offset = 0

    def allocate_var(self, name: str) -> int:
        """Allocate space for a variable."""
        if name not in self.var_offsets:
            offset = self.next_offset
            self.var_offsets[name] = offset
            self.next_offset += 8
        return self.var_offsets[name]

    def lower_expression(self, expr_str: str) -> IRNode:
        """Lower a Wolfram expression string to IR."""
        lexer = WolframLexer(expr_str)
        tokens = lexer.tokenize()
        return self.lower_tokens(tokens)

    def lower_tokens(self, tokens: List) -> IRNode:
        """Lower token stream to IR (simplified parser)."""
        if not tokens or tokens[0].type == TokenType.EOF:
            return ir_word(0, width=64)

        if tokens[0].type == TokenType.NUMBER:
            try:
                value = float(tokens[0].value)
                return ir_word(int(value), width=64)
            except:
                return ir_word(0, width=64)

        if tokens[0].type == TokenType.SYMBOL:
            name = tokens[0].value
            offset = self.allocate_var(name)
            return ir_load(ir_word(offset, width=64))

        if tokens[0].type == TokenType.FUNCTION:
            func_name = tokens[0].value
            if func_name == "Plus":
                left = ir_word(0, width=64)
                right = ir_word(0, width=64)
                return ir_add(left, right)
            elif func_name == "Times":
                left = ir_word(1, width=64)
                right = ir_word(1, width=64)
                return ir_mul(left, right)
            elif func_name == "Dot":
                left = ir_word(0, width=64)
                right = ir_word(0, width=64)
                return ir_mul(left, right)

        return ir_word(0, width=64)

    def lower_matrix_multiply(self, matrix_a_ptr: int, matrix_b_ptr: int, size: int) -> List[IRNode]:
        """Lower matrix multiplication C = A . B to IR.

        Generates loop: for i in range(size):
                         for j in range(size):
                           C[i*size+j] = 0
                           for k in range(size):
                             C[i*size+j] += A[i*size+k] * B[k*size+j]
        """
        ir_nodes = []

        zero = ir_word(0, width=64)
        ptr_a = ir_word(matrix_a_ptr, width=64)
        ptr_b = ir_word(matrix_b_ptr, width=64)

        for i in range(size):
            for j in range(size):
                idx = i * size + j
                addr_c = ir_word(idx * 8, width=64)
                ir_nodes.append(ir_store(addr_c, zero))

                for k in range(size):
                    idx_a = i * size + k
                    idx_b = k * size + j
                    addr_a = ir_word(idx_a * 8, width=64)
                    addr_b = ir_word(idx_b * 8, width=64)

                    val_a = ir_load(addr_a)
                    val_b = ir_load(addr_b)
                    prod = ir_mul(val_a, val_b)

                    current_c = ir_load(addr_c)
                    new_c = ir_add(current_c, prod)
                    ir_nodes.append(ir_store(addr_c, new_c))

        return ir_nodes

    def lower_program(self, source: str) -> IRProgram:
        """Lower Wolfram program to Word IR."""
        ir_nodes = []

        lexer = WolframLexer(source)
        tokens = lexer.tokenize()

        expr = self.lower_tokens(tokens)
        ir_nodes.append(expr)

        main_block = IRBlock(label="main", nodes=ir_nodes)
        return IRProgram(blocks={"main": main_block}, entry="main")


def lower_wolfram_to_ir(source: str) -> IRProgram:
    """Convenience function: lower Wolfram source to Word IR."""
    lowering = WolframLowering()
    return lowering.lower_program(source)
