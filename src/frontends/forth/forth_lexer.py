r"""Forth lexical analyzer (tokenizer).

Forth is a stack-based language where words are separated by whitespace.
Syntax: words (identifiers), numbers, string literals, comments (\ and ( ... )).
"""

from enum import Enum, auto
from typing import List

from src.lexers import BaseLexer, Token


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


class ForthLexer(BaseLexer):
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

    def skip_comment(self):
        """Skip Forth comments: \ line-comments and ( block-comments )."""
        if self.current_char() == "\\":
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

    def read_hex_number(self) -> str:
        """Read a hexadecimal number starting with 0x or 0X."""
        num_str = ""
        num_str += self.current_char()  # '0'
        self.advance()
        num_str += self.current_char()  # 'x' or 'X'
        self.advance()
        while self.current_char() and self.current_char() in "0123456789abcdefABCDEF":
            num_str += self.current_char()
            self.advance()
        return num_str

    def read_number(self) -> Token:
        """Read a number (decimal or hexadecimal)."""
        start_line, start_col = self.line, self.col
        if self.current_char() == "0" and self.peek_char() and self.peek_char() in "xX":
            num_str = self.read_hex_number()
        else:
            num_str = super().read_number()
        return Token(TokenType.NUMBER, num_str, start_line, start_col)

    def read_word(self) -> Token:
        """Read a word (built-in or custom)."""
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

    def read_string_literal(self) -> Token:
        """Read a string literal."""
        start_line, start_col = self.line, self.col
        value = super().read_string('"')
        return Token(TokenType.STRING, value, start_line, start_col)

    def tokenize(self) -> List[Token]:
        """Tokenize Forth source code."""
        self.tokens = []
        while self.pos < len(self.source):
            self.skip_whitespace()
            if self.pos >= len(self.source):
                break

            ch = self.current_char()
            if ch == "\\" or (ch == "(" and self.peek_char() == " "):
                self.skip_comment()
                continue

            start_line, start_col = self.line, self.col

            if ch == '"':
                self.tokens.append(self.read_string_literal())
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
