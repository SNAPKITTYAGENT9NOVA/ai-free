"""BCPL lexical analyzer (tokenizer).

BCPL (Basic Combined Programming Language) is a procedural language from the 1960s.
Syntax: keywords (let, and, or, not, if, while, for, etc.), operators, identifiers, numbers.
"""

import re
from enum import Enum, auto
from dataclasses import dataclass
from typing import List, Optional


class TokenType(Enum):
    """BCPL token types."""
    # Literals
    NUMBER = auto()
    CHAR = auto()
    STRING = auto()
    IDENTIFIER = auto()

    # Keywords
    LET = auto()
    AND = auto()
    OR = auto()
    NOT = auto()
    IF = auto()
    THEN = auto()
    ELSE = auto()
    WHILE = auto()
    FOR = auto()
    DO = auto()
    BREAK = auto()
    CONTINUE = auto()
    RETURN = auto()
    MANIFEST = auto()
    GLOBAL = auto()
    STATIC = auto()
    EXTERNAL = auto()
    ROUTINE = auto()

    # Operators
    PLUS = auto()
    MINUS = auto()
    STAR = auto()
    SLASH = auto()
    MOD = auto()
    LSHIFT = auto()
    RSHIFT = auto()
    BITAND = auto()
    BITOR = auto()
    BITXOR = auto()
    BITNOT = auto()
    ASSIGN = auto()
    EQ = auto()
    NE = auto()
    LT = auto()
    LE = auto()
    GT = auto()
    GE = auto()

    # Delimiters
    LPAREN = auto()
    RPAREN = auto()
    LBRACKET = auto()
    RBRACKET = auto()
    LBRACE = auto()
    RBRACE = auto()
    SEMICOLON = auto()
    COMMA = auto()
    DOT = auto()
    COLON = auto()
    ARROW = auto()

    # Special
    EOF = auto()
    NEWLINE = auto()


@dataclass
class Token:
    """Lexical token with source location."""
    type: TokenType
    value: str
    line: int
    col: int

    def __repr__(self):
        return f"Token({self.type.name}, {self.value!r}, {self.line}:{self.col})"


class BCPLLexer:
    """BCPL lexical analyzer.

    Converts BCPL source text into a stream of tokens.
    Handles:
      - Keywords (let, if, while, etc.)
      - Operators (arithmetic, bitwise, comparison)
      - Identifiers and numbers
      - String and character literals
      - Comments (// and /* ... */)
    """

    KEYWORDS = {
        "let": TokenType.LET,
        "and": TokenType.AND,
        "or": TokenType.OR,
        "not": TokenType.NOT,
        "if": TokenType.IF,
        "then": TokenType.THEN,
        "else": TokenType.ELSE,
        "while": TokenType.WHILE,
        "for": TokenType.FOR,
        "do": TokenType.DO,
        "break": TokenType.BREAK,
        "continue": TokenType.CONTINUE,
        "return": TokenType.RETURN,
        "manifest": TokenType.MANIFEST,
        "global": TokenType.GLOBAL,
        "static": TokenType.STATIC,
        "external": TokenType.EXTERNAL,
        "routine": TokenType.ROUTINE,
    }

    def __init__(self, source: str):
        self.source = source
        self.pos = 0
        self.line = 1
        self.col = 1
        self.tokens: List[Token] = []

    def current_char(self) -> Optional[str]:
        if self.pos >= len(self.source):
            return None
        return self.source[self.pos]

    def peek_char(self, offset: int = 1) -> Optional[str]:
        pos = self.pos + offset
        if pos >= len(self.source):
            return None
        return self.source[pos]

    def advance(self):
        if self.pos < len(self.source):
            if self.source[self.pos] == "\n":
                self.line += 1
                self.col = 1
            else:
                self.col += 1
            self.pos += 1

    def skip_whitespace(self):
        while self.current_char() and self.current_char() in " \t\r\n":
            self.advance()

    def skip_comment(self):
        if self.current_char() == "/" and self.peek_char() == "/":
            while self.current_char() and self.current_char() != "\n":
                self.advance()
            if self.current_char() == "\n":
                self.advance()
        elif self.current_char() == "/" and self.peek_char() == "*":
            self.advance()
            self.advance()
            while self.pos < len(self.source):
                if self.current_char() == "*" and self.peek_char() == "/":
                    self.advance()
                    self.advance()
                    break
                self.advance()

    def read_number(self) -> Token:
        start_line, start_col = self.line, self.col
        num_str = ""
        while self.current_char() and self.current_char().isdigit():
            num_str += self.current_char()
            self.advance()
        if self.current_char() == "." and self.peek_char() and self.peek_char().isdigit():
            num_str += self.current_char()
            self.advance()
            while self.current_char() and self.current_char().isdigit():
                num_str += self.current_char()
                self.advance()
        return Token(TokenType.NUMBER, num_str, start_line, start_col)

    def read_identifier(self) -> Token:
        start_line, start_col = self.line, self.col
        ident = ""
        while self.current_char() and (self.current_char().isalnum() or self.current_char() == "_"):
            ident += self.current_char()
            self.advance()
        token_type = self.KEYWORDS.get(ident, TokenType.IDENTIFIER)
        return Token(token_type, ident, start_line, start_col)

    def read_string(self, quote: str) -> Token:
        start_line, start_col = self.line, self.col
        self.advance()
        value = ""
        while self.current_char() and self.current_char() != quote:
            if self.current_char() == "\\":
                self.advance()
                if self.current_char():
                    value += self.current_char()
                    self.advance()
            else:
                value += self.current_char()
                self.advance()
        if self.current_char() == quote:
            self.advance()
        token_type = TokenType.CHAR if quote == "'" else TokenType.STRING
        return Token(token_type, value, start_line, start_col)

    def tokenize(self) -> List[Token]:
        """Tokenize BCPL source code."""
        self.tokens = []
        while self.pos < len(self.source):
            self.skip_whitespace()
            if self.pos >= len(self.source):
                break

            ch = self.current_char()
            if ch in ("/" ) and self.peek_char() in ("/", "*"):
                self.skip_comment()
                continue

            start_line, start_col = self.line, self.col

            if ch.isdigit():
                self.tokens.append(self.read_number())
            elif ch.isalpha() or ch == "_":
                self.tokens.append(self.read_identifier())
            elif ch in ('"', "'"):
                self.tokens.append(self.read_string(ch))
            elif ch == "+" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.ASSIGN, "+=", start_line, start_col))
            elif ch == "-" and self.peek_char() == ">":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.ARROW, "->", start_line, start_col))
            elif ch == "<" and self.peek_char() == "<":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.LSHIFT, "<<", start_line, start_col))
            elif ch == ">" and self.peek_char() == ">":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.RSHIFT, ">>", start_line, start_col))
            elif ch == "=" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.EQ, "==", start_line, start_col))
            elif ch == "!" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.NE, "!=", start_line, start_col))
            elif ch == "<" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.LE, "<=", start_line, start_col))
            elif ch == ">" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.GE, ">=", start_line, start_col))
            elif ch == "+":
                self.advance()
                self.tokens.append(Token(TokenType.PLUS, "+", start_line, start_col))
            elif ch == "-":
                self.advance()
                self.tokens.append(Token(TokenType.MINUS, "-", start_line, start_col))
            elif ch == "*":
                self.advance()
                self.tokens.append(Token(TokenType.STAR, "*", start_line, start_col))
            elif ch == "/":
                self.advance()
                self.tokens.append(Token(TokenType.SLASH, "/", start_line, start_col))
            elif ch == "%":
                self.advance()
                self.tokens.append(Token(TokenType.MOD, "%", start_line, start_col))
            elif ch == "&":
                self.advance()
                self.tokens.append(Token(TokenType.BITAND, "&", start_line, start_col))
            elif ch == "|":
                self.advance()
                self.tokens.append(Token(TokenType.BITOR, "|", start_line, start_col))
            elif ch == "^":
                self.advance()
                self.tokens.append(Token(TokenType.BITXOR, "^", start_line, start_col))
            elif ch == "~":
                self.advance()
                self.tokens.append(Token(TokenType.BITNOT, "~", start_line, start_col))
            elif ch == "=":
                self.advance()
                self.tokens.append(Token(TokenType.ASSIGN, "=", start_line, start_col))
            elif ch == "<":
                self.advance()
                self.tokens.append(Token(TokenType.LT, "<", start_line, start_col))
            elif ch == ">":
                self.advance()
                self.tokens.append(Token(TokenType.GT, ">", start_line, start_col))
            elif ch == "(":
                self.advance()
                self.tokens.append(Token(TokenType.LPAREN, "(", start_line, start_col))
            elif ch == ")":
                self.advance()
                self.tokens.append(Token(TokenType.RPAREN, ")", start_line, start_col))
            elif ch == "[":
                self.advance()
                self.tokens.append(Token(TokenType.LBRACKET, "[", start_line, start_col))
            elif ch == "]":
                self.advance()
                self.tokens.append(Token(TokenType.RBRACKET, "]", start_line, start_col))
            elif ch == "{":
                self.advance()
                self.tokens.append(Token(TokenType.LBRACE, "{", start_line, start_col))
            elif ch == "}":
                self.advance()
                self.tokens.append(Token(TokenType.RBRACE, "}", start_line, start_col))
            elif ch == ";":
                self.advance()
                self.tokens.append(Token(TokenType.SEMICOLON, ";", start_line, start_col))
            elif ch == ",":
                self.advance()
                self.tokens.append(Token(TokenType.COMMA, ",", start_line, start_col))
            elif ch == ".":
                self.advance()
                self.tokens.append(Token(TokenType.DOT, ".", start_line, start_col))
            elif ch == ":":
                self.advance()
                self.tokens.append(Token(TokenType.COLON, ":", start_line, start_col))
            else:
                self.advance()

        self.tokens.append(Token(TokenType.EOF, "", self.line, self.col))
        return self.tokens
