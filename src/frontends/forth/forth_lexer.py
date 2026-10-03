r"""Forth lexical analyzer (tokenizer).

Forth is a stack-based language where words are separated by whitespace.
Syntax: words (identifiers), numbers, string literals, comments (\ and ( ... )).
"""

import re
from enum import Enum, auto
from dataclasses import dataclass
from typing import List, Optional


class TokenType(Enum):
    """Forth token types."""
    # Literals
    NUMBER = auto()
    STRING = auto()
    WORD = auto()

    # Forth built-in words
    PUSH = auto()          # Literal push
    DUP = auto()
    DROP = auto()
    SWAP = auto()
    OVER = auto()
    ROT = auto()
    DEPTH = auto()
    CLEAR = auto()
    ADD = auto()           # +
    SUB = auto()           # -
    MUL = auto()           # *
    DIV = auto()           # /
    MOD = auto()
    NEG = auto()
    ABS = auto()
    MIN = auto()
    MAX = auto()
    AND = auto()
    OR = auto()
    XOR = auto()
    NOT = auto()
    LSHIFT = auto()
    RSHIFT = auto()
    EQ = auto()            # =
    LT = auto()            # <
    GT = auto()            # >
    LE = auto()
    GE = auto()
    NE = auto()
    LOAD = auto()          # @
    STORE = auto()         # !
    PLUS_STORE = auto()    # +!
    ALLOC = auto()
    MEMORY = auto()
    IF = auto()
    THEN = auto()
    ELSE = auto()
    DO = auto()
    LOOP = auto()
    BEGIN = auto()
    UNTIL = auto()
    WHILE = auto()
    REPEAT = auto()
    COLON = auto()         # :
    SEMICOLON = auto()    # ;
    QUOTE = auto()
    DOT = auto()           # .
    EMIT = auto()
    KEY = auto()
    CR = auto()
    SPACE = auto()
    SPACES = auto()

    # Delimiters
    LPAREN = auto()
    RPAREN = auto()
    LBRACKET = auto()
    RBRACKET = auto()

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


class ForthLexer(object):
    """Forth lexical analyzer.

    Converts Forth source text into a stream of tokens.
    Handles:
      - Words (identifiers, built-in operators)
      - Numbers (decimal, hex)
      - String literals
      - Comments (backslash and ( ... ))
      - Colon definitions (: name ... ;)
    """

    BUILTIN_WORDS = {
        "dup": TokenType.DUP,
        "drop": TokenType.DROP,
        "swap": TokenType.SWAP,
        "over": TokenType.OVER,
        "rot": TokenType.ROT,
        "depth": TokenType.DEPTH,
        "clear": TokenType.CLEAR,
        "+": TokenType.ADD,
        "-": TokenType.SUB,
        "*": TokenType.MUL,
        "/": TokenType.DIV,
        "mod": TokenType.MOD,
        "negate": TokenType.NEG,
        "abs": TokenType.ABS,
        "min": TokenType.MIN,
        "max": TokenType.MAX,
        "and": TokenType.AND,
        "or": TokenType.OR,
        "xor": TokenType.XOR,
        "not": TokenType.NOT,
        "lshift": TokenType.LSHIFT,
        "rshift": TokenType.RSHIFT,
        "=": TokenType.EQ,
        "<": TokenType.LT,
        ">": TokenType.GT,
        "<=": TokenType.LE,
        ">=": TokenType.GE,
        "<>": TokenType.NE,
        "@": TokenType.LOAD,
        "!": TokenType.STORE,
        "+!": TokenType.PLUS_STORE,
        "alloc": TokenType.ALLOC,
        "memory": TokenType.MEMORY,
        "if": TokenType.IF,
        "then": TokenType.THEN,
        "else": TokenType.ELSE,
        "do": TokenType.DO,
        "loop": TokenType.LOOP,
        "begin": TokenType.BEGIN,
        "until": TokenType.UNTIL,
        "while": TokenType.WHILE,
        "repeat": TokenType.REPEAT,
        ":": TokenType.COLON,
        ";": TokenType.SEMICOLON,
        '"': TokenType.QUOTE,
        ".": TokenType.DOT,
        "emit": TokenType.EMIT,
        "key": TokenType.KEY,
        "cr": TokenType.CR,
        "space": TokenType.SPACE,
        "spaces": TokenType.SPACES,
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
        if self.current_char() == "\\" :
            while self.current_char() and self.current_char() != "\n":
                self.advance()
            if self.current_char() == "\n":
                self.advance()
        elif self.current_char() == "(" and self.peek_char() == " ":
            self.advance()
            self.advance()
            while self.pos < len(self.source):
                if self.current_char() == ")":
                    self.advance()
                    break
                self.advance()

    def read_number(self) -> Token:
        start_line, start_col = self.line, self.col
        num_str = ""
        if self.current_char() == "0" and self.peek_char() and self.peek_char() in "xX":
            num_str += self.current_char()
            self.advance()
            num_str += self.current_char()
            self.advance()
            while self.current_char() and self.current_char() in "0123456789abcdefABCDEF":
                num_str += self.current_char()
                self.advance()
        else:
            while self.current_char() and self.current_char().isdigit():
                num_str += self.current_char()
                self.advance()
        return Token(TokenType.NUMBER, num_str, start_line, start_col)

    def read_word(self) -> Token:
        start_line, start_col = self.line, self.col
        word = ""
        while self.current_char() and not self.current_char().isspace() and self.current_char() not in "()[]":
            word += self.current_char()
            self.advance()

        # Check if it's a negative number
        if word.startswith('-') and len(word) > 1 and word[1:].isdigit():
            return Token(TokenType.NUMBER, word, start_line, start_col)

        token_type = self.BUILTIN_WORDS.get(word, TokenType.WORD)
        return Token(token_type, word, start_line, start_col)

    def read_string(self) -> Token:
        start_line, start_col = self.line, self.col
        self.advance()
        value = ""
        while self.current_char() and self.current_char() != '"':
            if self.current_char() == "\\":
                self.advance()
                if self.current_char():
                    value += self.current_char()
                    self.advance()
            else:
                value += self.current_char()
                self.advance()
        if self.current_char() == '"':
            self.advance()
        return Token(TokenType.STRING, value, start_line, start_col)

    def tokenize(self) -> List[Token]:
        """Tokenize Forth source code."""
        self.tokens = []
        while self.pos < len(self.source):
            self.skip_whitespace()
            if self.pos >= len(self.source):
                break

            ch = self.current_char()
            if ch in ("\\" ) or (ch == "(" and self.peek_char() == " "):
                self.skip_comment()
                continue

            start_line, start_col = self.line, self.col

            if ch == '"':
                self.tokens.append(self.read_string())
            elif ch.isdigit():
                self.tokens.append(self.read_number())
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
            else:
                self.tokens.append(self.read_word())

        self.tokens.append(Token(TokenType.EOF, "", self.line, self.col))
        return self.tokens
