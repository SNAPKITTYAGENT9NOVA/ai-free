"""Forth Parser: tokens → AST.

Forth is a stack-based language. This parser handles:
  - Numbers (decimal and hex)
  - Built-in words (DUP, DROP, SWAP, arithmetic, memory ops, etc.)
  - Custom word definitions
  - Control flow (IF, THEN, ELSE, DO, LOOP)
  - Stack comments

The parser builds an AST representing Forth words and definitions,
separating parsing from lowering.
"""

from typing import List, Optional
from src.frontends.forth.forth_lexer import ForthLexer, TokenType
from .base_parser import (
    Parser, ParseError, Program, FunctionDef, Stmt, Expr,
    ASTNode, Literal, Identifier, Call, Block, ExprStmt, SourceLocation
)


# ============================================================================
# Forth-specific AST Nodes
# ============================================================================

class ForthWord(ASTNode):
    """Base class for Forth word AST nodes."""
    pass


class ForthLiteral(ForthWord, Literal):
    """Forth numeric or string literal."""
    pass


class ForthBuiltin(ForthWord):
    """Built-in Forth word (DUP, DROP, +, -, etc.)."""
    def __init__(self, name: str):
        super().__init__()
        self.name = name


class ForthCustomWord(ForthWord, Identifier):
    """Reference to a user-defined Forth word."""
    pass


class ForthWordDef(ASTNode):
    """Forth word definition: : name ... ;"""
    def __init__(self, name: str, body: List[ForthWord]):
        super().__init__()
        self.name = name
        self.body = body


class ForthProgram(Program):
    """Forth program: list of word definitions and top-level words."""
    def __init__(self, definitions: List[ForthWordDef], words: List[ForthWord]):
        super().__init__(items=definitions)
        self.definitions = definitions
        self.words = words


# ============================================================================
# Forth Parser
# ============================================================================

class ForthParser(Parser[ForthProgram]):
    """Forth parser: tokens → AST."""

    def parse(self) -> ForthProgram:
        """Parse Forth program: sequence of word definitions and words."""
        definitions = []
        words = []

        while self.current() and self.current().type != TokenType.EOF:
            if self.current().type == TokenType.COLON:
                # Word definition
                definitions.append(self.parse_word_def())
            else:
                # Top-level word
                word = self.parse_word()
                if word:
                    words.append(word)

        program = ForthProgram(definitions=definitions, words=words)
        program.set_location(1, 0, "forth_program")
        return program

    def parse_word_def(self) -> ForthWordDef:
        """Parse word definition: : name ... ;"""
        colon_token = self.expect(TokenType.COLON)
        name_token = self.expect(TokenType.WORD)
        name = name_token.value

        body = []
        while self.current() and self.current().type != TokenType.SEMICOLON:
            word = self.parse_word()
            if word:
                body.append(word)

        self.expect(TokenType.SEMICOLON)

        word_def = ForthWordDef(name=name, body=body)
        word_def.set_location(colon_token.line, colon_token.col, ":")
        return word_def

    def parse_word(self) -> Optional[ForthWord]:
        """Parse a single Forth word (literal, builtin, or custom)."""
        if not self.current() or self.current().type == TokenType.EOF:
            return None

        token = self.current()

        if token.type == TokenType.NUMBER:
            # Numeric literal
            self.advance()
            value = int(token.value) if token.value.startswith('0x') else int(token.value)
            word = ForthLiteral(value=value, type_hint="number")
            word.set_location(token.line, token.col, token.value)
            return word

        elif token.type == TokenType.STRING:
            # String literal
            self.advance()
            word = ForthLiteral(value=token.value, type_hint="string")
            word.set_location(token.line, token.col, f'"{token.value}"')
            return word

        elif self._is_builtin_word(token.type):
            # Built-in word
            self.advance()
            word = ForthBuiltin(name=token.value)
            word.set_location(token.line, token.col, token.value)
            return word

        elif token.type == TokenType.WORD:
            # Custom word
            self.advance()
            word = ForthCustomWord(name=token.value)
            word.set_location(token.line, token.col, token.value)
            return word

        elif token.type == TokenType.LPAREN:
            # Stack comment
            self.skip_stack_comment()
            return None

        elif token.type == TokenType.RPAREN:
            # Closing paren (end of stack comment)
            self.advance()
            return None

        else:
            # Unknown token, skip it
            self.advance()
            return None

    def skip_stack_comment(self) -> None:
        """Skip stack comment: ( ... ) or ( stack -- result )."""
        if self.current().type == TokenType.LPAREN:
            self.advance()
            while self.current() and self.current().type != TokenType.RPAREN:
                self.advance()
            if self.current() and self.current().type == TokenType.RPAREN:
                self.advance()

    def _is_builtin_word(self, token_type: TokenType) -> bool:
        """Check if token type is a built-in Forth word."""
        builtin_types = {
            TokenType.DUP, TokenType.DROP, TokenType.SWAP,
            TokenType.OVER, TokenType.ROT, TokenType.DEPTH,
            TokenType.CLEAR, TokenType.ADD, TokenType.SUB,
            TokenType.MUL, TokenType.DIV, TokenType.MOD,
            TokenType.NEG, TokenType.ABS, TokenType.MIN, TokenType.MAX,
            TokenType.AND, TokenType.OR, TokenType.XOR, TokenType.NOT,
            TokenType.LSHIFT, TokenType.RSHIFT, TokenType.EQ,
            TokenType.LT, TokenType.GT, TokenType.LE, TokenType.GE,
            TokenType.NE, TokenType.LOAD, TokenType.STORE,
            TokenType.PLUS_STORE, TokenType.ALLOC, TokenType.MEMORY,
            TokenType.IF, TokenType.THEN, TokenType.ELSE,
            TokenType.DO, TokenType.LOOP, TokenType.BEGIN,
            TokenType.UNTIL, TokenType.WHILE, TokenType.REPEAT,
            TokenType.DOT, TokenType.EMIT, TokenType.KEY,
            TokenType.CR, TokenType.SPACE, TokenType.SPACES,
        }
        return token_type in builtin_types


def parse_forth(source: str) -> ForthProgram:
    """Parse Forth source code → AST with source locations."""
    lexer = ForthLexer(source)
    tokens = lexer.tokenize()
    parser = ForthParser(tokens)
    return parser.parse()
