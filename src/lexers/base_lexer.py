"""Base lexer module with universal tokenization infrastructure.

This module provides:
  - Token: Universal token dataclass used by all lexers
  - BaseLexer: Abstract base class with common tokenization algorithms

Each language lexer (BCPL, Forth, Wolfram) keeps its language-specific TokenType
enum but inherits from BaseLexer to reuse common parsing logic.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class Token:
    """Universal lexical token with source location.

    Works with any language's TokenType enum. The type field can be any Enum
    that represents tokens for the specific language being lexed.
    """
    type: object  # Language-specific TokenType enum value
    value: str
    line: int
    col: int

    def __repr__(self):
        return f"Token({self.type.name}, {self.value!r}, {self.line}:{self.col})"


class BaseLexer(ABC):
    """Abstract base lexer with common tokenization algorithms.

    Provides:
      - Position tracking (current_char, peek_char, advance)
      - Common parsing methods (skip_whitespace, read_number, read_string)
      - Language-specific hooks (skip_comment, tokenize)

    Subclasses implement:
      - skip_comment(): Handle language-specific comment syntax
      - tokenize(): Main tokenization loop
    """

    def __init__(self, source: str):
        """Initialize lexer with source code."""
        self.source = source
        self.pos = 0
        self.line = 1
        self.col = 1
        self.tokens: List[Token] = []

    # ===== Position tracking =====

    def current_char(self) -> Optional[str]:
        """Get current character without advancing."""
        if self.pos >= len(self.source):
            return None
        return self.source[self.pos]

    def peek_char(self, offset: int = 1) -> Optional[str]:
        """Look ahead at character at given offset from current position."""
        pos = self.pos + offset
        if pos >= len(self.source):
            return None
        return self.source[pos]

    def advance(self) -> None:
        """Move to next character and track line/column position."""
        if self.pos < len(self.source):
            if self.source[self.pos] == "\n":
                self.line += 1
                self.col = 1
            else:
                self.col += 1
            self.pos += 1

    # ===== Common parsing methods =====

    def skip_whitespace(self) -> None:
        """Skip whitespace characters (space, tab, CR, LF)."""
        while self.current_char() and self.current_char() in " \t\r\n":
            self.advance()

    def read_number(self) -> str:
        """Read a numeric literal (integer or float).

        Returns:
            String containing the number (e.g., "42", "3.14")
        """
        num_str = ""

        # Read integer part
        while self.current_char() and self.current_char().isdigit():
            num_str += self.current_char()
            self.advance()

        # Read decimal part if present
        if self.current_char() == "." and self.peek_char() and self.peek_char().isdigit():
            num_str += self.current_char()
            self.advance()
            while self.current_char() and self.current_char().isdigit():
                num_str += self.current_char()
                self.advance()

        return num_str

    def read_string(self, quote: str) -> str:
        """Read a string literal with escape sequence handling.

        Args:
            quote: The quote character that started the string (" or ')

        Returns:
            String content without quotes
        """
        self.advance()  # Skip opening quote
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
            self.advance()  # Skip closing quote
        return value

    # ===== Language-specific hooks (abstract) =====

    @abstractmethod
    def skip_comment(self) -> None:
        r"""Skip over a comment in the source code.

        This is called when a comment sequence is detected. The implementation
        should advance past the comment and any trailing whitespace/newlines.

        Subclasses must implement language-specific comment syntax:
          - BCPL: // and /* ... */
          - Forth: \ and ( ... )
          - Wolfram: (* ... *)
        """
        pass

    @abstractmethod
    def tokenize(self) -> List[Token]:
        """Tokenize the entire source code into a list of tokens.

        Must:
          1. Process all characters in source
          2. Skip whitespace
          3. Call skip_comment() when appropriate
          4. Create Token objects for each token
          5. Append EOF token at end

        Returns:
            List of Token objects
        """
        pass
