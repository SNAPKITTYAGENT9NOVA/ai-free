"""Forth → Word IR compiler: maps stack operations to IR.

Semantics:
  - Stack is implicit (conceptual)
  - Numbers push to stack → IR literals
  - Operations consume stack → IR nodes
  - Stack depth tracked for safety
"""

from typing import List, Dict, Tuple
from src.word_ir.ir_ast import (
    IRNode, IRWord, IRLoad, IRStore, IRBinOp, IRNodeType,
    IRBlock, IRProgram, ir_add, ir_sub, ir_mul, ir_and, ir_or,
    ir_xor, ir_load, ir_store, ir_word
)
from .forth_lexer import ForthLexer, TokenType
from .forth_ast import (
    Word, NumberWord, BuiltinWord, CustomWord, StringWord, ControlFlow,
    WordDef, ForthProgram
)


class ForthLowering:
    """Lower Forth words to Word IR."""

    def __init__(self):
        self.stack: List[IRNode] = []
        self.ir_nodes: List[IRNode] = []

    def lower_number(self, value: int):
        """Push number to stack."""
        self.stack.append(ir_word(value, width=64))

    def lower_builtin(self, word: str):
        """Execute built-in Forth word."""
        if word == "dup" and len(self.stack) >= 1:
            top = self.stack[-1]
            self.stack.append(top)
        elif word == "drop" and len(self.stack) >= 1:
            self.stack.pop()
        elif word == "swap" and len(self.stack) >= 2:
            self.stack[-1], self.stack[-2] = self.stack[-2], self.stack[-1]
        elif word == "over" and len(self.stack) >= 2:
            second = self.stack[-2]
            self.stack.append(second)
        elif word == "rot" and len(self.stack) >= 3:
            a, b, c = self.stack.pop(), self.stack.pop(), self.stack.pop()
            self.stack.extend([b, a, c])
        elif word == "+" and len(self.stack) >= 2:
            right = self.stack.pop()
            left = self.stack.pop()
            self.stack.append(ir_add(left, right))
        elif word == "-" and len(self.stack) >= 2:
            right = self.stack.pop()
            left = self.stack.pop()
            self.stack.append(ir_sub(left, right))
        elif word == "*" and len(self.stack) >= 2:
            right = self.stack.pop()
            left = self.stack.pop()
            self.stack.append(ir_mul(left, right))
        elif word == "/" and len(self.stack) >= 2:
            right = self.stack.pop()
            left = self.stack.pop()
            result = IRBinOp(op_type=IRNodeType.MUL, left=left, right=right)
            self.stack.append(result)
        elif word == "and" and len(self.stack) >= 2:
            right = self.stack.pop()
            left = self.stack.pop()
            self.stack.append(ir_and(left, right))
        elif word == "or" and len(self.stack) >= 2:
            right = self.stack.pop()
            left = self.stack.pop()
            self.stack.append(ir_or(left, right))
        elif word == "xor" and len(self.stack) >= 2:
            right = self.stack.pop()
            left = self.stack.pop()
            self.stack.append(ir_xor(left, right))
        elif word == "@" and len(self.stack) >= 1:
            addr = self.stack.pop()
            self.stack.append(ir_load(addr))
        elif word == "!" and len(self.stack) >= 2:
            value = self.stack.pop()
            addr = self.stack.pop()
            self.ir_nodes.append(ir_store(addr, value))
        elif word == "alloc" and len(self.stack) >= 1:
            size = self.stack.pop()
            from src.word_ir.ir_ast import IRAlloc
            self.stack.append(IRAlloc(size=size))

    def lower_program(self, source: str) -> IRProgram:
        """Lower Forth source to Word IR."""
        lexer = ForthLexer(source)
        tokens = lexer.tokenize()

        blocks = {}
        current_def = None
        current_words = []

        for token in tokens:
            if token.type == TokenType.EOF:
                break
            elif token.type == TokenType.NUMBER:
                value = int(token.value)
                current_words.append(NumberWord(name=str(value), value=value))
            elif token.type == TokenType.COLON:
                current_def = None
            elif token.type == TokenType.SEMICOLON:
                if current_def:
                    blocks[current_def] = IRBlock(label=current_def, nodes=self.ir_nodes)
                    current_def = None
                    self.ir_nodes = []
            elif token.type in (TokenType.DUP, TokenType.DROP, TokenType.SWAP, TokenType.OVER,
                                TokenType.ADD, TokenType.SUB, TokenType.MUL, TokenType.DIV,
                                TokenType.AND, TokenType.OR, TokenType.XOR, TokenType.LOAD,
                                TokenType.STORE):
                current_words.append(BuiltinWord(name=token.value))
            elif token.type == TokenType.WORD:
                current_words.append(CustomWord(name=token.value))
            elif token.type == TokenType.STRING:
                current_words.append(StringWord(name=f"str_{token.value}", value=token.value))

        main_block = IRBlock(label="main", nodes=self.ir_nodes)
        blocks["main"] = main_block
        return IRProgram(blocks=blocks, entry="main")


def lower_forth_to_ir(source: str) -> IRProgram:
    """Convenience function: lower Forth source to Word IR."""
    lowering = ForthLowering()
    return lowering.lower_program(source)
