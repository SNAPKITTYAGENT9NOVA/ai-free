"""Wolfram language lexical analyzer (stub).

Wolfram is a symbolic math language. This lexer provides basic tokenization
for Wolfram expressions: numbers, symbols, operators, and function calls.

Full Wolfram parsing is deferred—this stub focuses on lexical structure.
"""

from enum import Enum, auto
from dataclasses import dataclass
from typing import List, Optional


class TokenType(Enum):
    """Wolfram token types."""
    # Literals
    NUMBER = auto()
    SYMBOL = auto()
    STRING = auto()

    # Operators
    PLUS = auto()
    MINUS = auto()
    STAR = auto()
    SLASH = auto()
    POWER = auto()
    DOT = auto()
    CROSS = auto()

    # Comparison
    EQ = auto()
    NEQU = auto()
    LT = auto()
    LE = auto()
    GT = auto()
    GE = auto()

    # Logical
    AND = auto()
    OR = auto()
    NOT = auto()

    # Delimiters
    LPAREN = auto()
    RPAREN = auto()
    LBRACKET = auto()
    RBRACKET = auto()
    LBRACE = auto()
    RBRACE = auto()
    COMMA = auto()
    SEMICOLON = auto()
    COLON = auto()
    ARROW = auto()

    # Functions (stub)
    FUNCTION = auto()

    # Special
    EOF = auto()


@dataclass
class Token:
    """Lexical token with source location."""
    type: TokenType
    value: str
    line: int
    col: int

    def __repr__(self):
        return f"Token({self.type.name}, {self.value!r}, {self.line}:{self.col})"


class WolframLexer:
    """Wolfram lexical analyzer (stub).

    Provides basic tokenization for Wolfram mathematical expressions.
    Handles:
      - Numbers (integer, float, scientific notation)
      - Symbols (identifiers, built-in functions)
      - Operators (arithmetic, comparison, logical)
      - Delimiters (parentheses, brackets, braces)
      - Comments (* ... *)

    Note: Full parsing of Wolfram syntax (patterns, rules, etc.) is deferred.
    """

    BUILTIN_FUNCTIONS = {
        "Plus", "Times", "Power", "Divide", "Mod",
        "Sin", "Cos", "Tan", "Log", "Exp",
        "List", "Array", "Matrix",
        "Sum", "Product", "Integrate",
        "Dot", "Cross", "Norm",
        "If", "And", "Or", "Not",
        "Equal", "NotEqual", "Less", "Greater",
        "GreaterEqual", "LessEqual",
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
        if self.current_char() == "(" and self.peek_char() == "*":
            self.advance()
            self.advance()
            while self.pos < len(self.source):
                if self.current_char() == "*" and self.peek_char() == ")":
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
        if self.current_char() and self.current_char() in "eE":
            num_str += self.current_char()
            self.advance()
            if self.current_char() and self.current_char() in "+-":
                num_str += self.current_char()
                self.advance()
            while self.current_char() and self.current_char().isdigit():
                num_str += self.current_char()
                self.advance()
        return Token(TokenType.NUMBER, num_str, start_line, start_col)

    def read_symbol(self) -> Token:
        start_line, start_col = self.line, self.col
        sym = ""
        while self.current_char() and (self.current_char().isalnum() or self.current_char() == "_"):
            sym += self.current_char()
            self.advance()
        token_type = TokenType.FUNCTION if sym in self.BUILTIN_FUNCTIONS else TokenType.SYMBOL
        return Token(token_type, sym, start_line, start_col)

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
        return Token(TokenType.STRING, value, start_line, start_col)

    def tokenize(self) -> List[Token]:
        """Tokenize Wolfram source code."""
        self.tokens = []
        while self.pos < len(self.source):
            self.skip_whitespace()
            if self.pos >= len(self.source):
                break

            ch = self.current_char()
            if ch == "(" and self.peek_char() == "*":
                self.skip_comment()
                continue

            start_line, start_col = self.line, self.col

            if ch == '"':
                self.tokens.append(self.read_string('"'))
            elif ch.isdigit():
                self.tokens.append(self.read_number())
            elif ch.isalpha() or ch == "_":
                self.tokens.append(self.read_symbol())
            elif ch == "+":
                self.advance()
                self.tokens.append(Token(TokenType.PLUS, "+", start_line, start_col))
            elif ch == "-" and not (self.peek_char() and self.peek_char().isdigit()):
                self.advance()
                self.tokens.append(Token(TokenType.MINUS, "-", start_line, start_col))
            elif ch == "*":
                self.advance()
                self.tokens.append(Token(TokenType.STAR, "*", start_line, start_col))
            elif ch == "/":
                self.advance()
                self.tokens.append(Token(TokenType.SLASH, "/", start_line, start_col))
            elif ch == "^":
                self.advance()
                self.tokens.append(Token(TokenType.POWER, "^", start_line, start_col))
            elif ch == "." and (not self.peek_char() or not self.peek_char().isdigit()):
                self.advance()
                self.tokens.append(Token(TokenType.DOT, ".", start_line, start_col))
            elif ch == "=" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.EQ, "==", start_line, start_col))
            elif ch == "!" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.NEQU, "!=", start_line, start_col))
            elif ch == "<" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.LE, "<=", start_line, start_col))
            elif ch == ">" and self.peek_char() == "=":
                self.advance()
                self.advance()
                self.tokens.append(Token(TokenType.GE, ">=", start_line, start_col))
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
            elif ch == ",":
                self.advance()
                self.tokens.append(Token(TokenType.COMMA, ",", start_line, start_col))
            elif ch == ";":
                self.advance()
                self.tokens.append(Token(TokenType.SEMICOLON, ";", start_line, start_col))
            elif ch == ":":
                self.advance()
                if self.current_char() == "=":
                    self.advance()
                    self.tokens.append(Token(TokenType.ARROW, ":=", start_line, start_col))
                else:
                    self.tokens.append(Token(TokenType.COLON, ":", start_line, start_col))
            else:
                self.advance()

        self.tokens.append(Token(TokenType.EOF, "", self.line, self.col))
        return self.tokens
