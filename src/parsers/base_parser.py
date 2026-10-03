"""Base parser framework with common AST classes and abstract Parser template.

All parsers in the Universal Word Dialect Stack should:
1. Accept tokens from the corresponding lexer
2. Build an AST with source location tracking
3. Output AST nodes that can be lowered to Word IR
"""

from dataclasses import dataclass
from typing import List, Optional, TypeVar, Generic, Dict, Any
from abc import ABC, abstractmethod


# ============================================================================
# Source Location Tracking
# ============================================================================

@dataclass
class SourceLocation:
    """Source location for error reporting and debugging."""
    line: int
    col: int
    text: str = ""

    def __repr__(self):
        return f"<{self.line}:{self.col}>"


# ============================================================================
# Base AST Node Classes
# ============================================================================

@dataclass
class ASTNode:
    """Base class for all AST nodes with source location tracking."""
    location: SourceLocation = None

    def set_location(self, line: int, col: int, text: str = ""):
        """Set source location for error reporting."""
        self.location = SourceLocation(line=line, col=col, text=text)
        return self


# ============================================================================
# Expression Nodes (Common)
# ============================================================================

@dataclass
class Expr(ASTNode):
    """Base expression class."""
    pass


@dataclass
class Literal(Expr):
    """Numeric or string literal."""
    value: Any
    type_hint: str = "unknown"  # "int", "float", "string", etc.


@dataclass
class Identifier(Expr):
    """Variable or symbol reference."""
    name: str


@dataclass
class BinaryOp(Expr):
    """Binary operation: left op right."""
    op: str
    left: Expr
    right: Expr


@dataclass
class UnaryOp(Expr):
    """Unary operation: op operand."""
    op: str
    operand: Expr


@dataclass
class Call(Expr):
    """Function/word call: name(args) or name arg1 arg2 ..."""
    name: str
    args: List[Expr]


@dataclass
class Load(Expr):
    """Memory load: @address or deref(address)."""
    address: Expr


@dataclass
class Index(Expr):
    """Array/list indexing: expr[index]."""
    expr: Expr
    index: Expr


# ============================================================================
# Statement Nodes (Common)
# ============================================================================

@dataclass
class Stmt(ASTNode):
    """Base statement class."""
    pass


@dataclass
class ExprStmt(Stmt):
    """Expression statement."""
    expr: Expr


@dataclass
class Assignment(Stmt):
    """Assignment: lhs = rhs."""
    target: str  # variable name
    value: Expr


@dataclass
class Store(Stmt):
    """Memory store: @address = value or address! value."""
    address: Expr
    value: Expr


@dataclass
class Block(Stmt):
    """Block of statements: { stmts }."""
    stmts: List[Stmt]


@dataclass
class IfStmt(Stmt):
    """Conditional: if cond then consequent else alternate."""
    condition: Expr
    consequent: List[Stmt]
    alternate: Optional[List[Stmt]] = None


@dataclass
class WhileStmt(Stmt):
    """Loop: while condition do body."""
    condition: Expr
    body: List[Stmt]


@dataclass
class ForStmt(Stmt):
    """C-style for loop: for (init; cond; update) body."""
    init: Optional[Stmt]
    condition: Expr
    update: Optional[Stmt]
    body: List[Stmt]


@dataclass
class ReturnStmt(Stmt):
    """Return statement."""
    value: Optional[Expr] = None


@dataclass
class FunctionDef(ASTNode):
    """Function definition."""
    name: str
    params: List[str]
    body: List[Stmt]
    return_type: Optional[str] = None


@dataclass
class Program(ASTNode):
    """Top-level program: list of definitions and statements."""
    items: List[ASTNode]  # FunctionDef, Stmt, etc.


# ============================================================================
# Abstract Parser Template
# ============================================================================

T = TypeVar('T')


class Parser(ABC, Generic[T]):
    """Abstract base parser for lexical token streams.

    All language-specific parsers should extend this class.
    Provides common parsing utilities and error handling.
    """

    def __init__(self, tokens: List[Any]):
        """Initialize parser with token stream.

        Args:
            tokens: List of Token objects from lexer
        """
        self.tokens = tokens
        self.pos = 0

    # ========================================================================
    # Token Navigation
    # ========================================================================

    def current(self) -> Optional[Any]:
        """Get current token without advancing."""
        if self.pos >= len(self.tokens):
            return None
        return self.tokens[self.pos]

    def peek(self, offset: int = 1) -> Optional[Any]:
        """Look ahead at token at current + offset."""
        pos = self.pos + offset
        if pos >= len(self.tokens):
            return None
        return self.tokens[pos]

    def advance(self) -> Optional[Any]:
        """Consume and return current token."""
        token = self.current()
        self.pos += 1
        return token

    def match(self, *token_types: Any) -> bool:
        """Check if current token matches any of the given types."""
        token = self.current()
        return token and token.type in token_types

    def expect(self, token_type: Any) -> Any:
        """Consume current token if it matches; raise error otherwise."""
        token = self.current()
        if not token or token.type != token_type:
            self.error(f"Expected {token_type}, got {token}")
        return self.advance()

    def expect_value(self, *values: Any) -> Any:
        """Consume current token if its value matches; raise error otherwise."""
        token = self.current()
        if not token or token.value not in values:
            self.error(f"Expected one of {values}, got {token}")
        return self.advance()

    # ========================================================================
    # Error Handling
    # ========================================================================

    def error(self, message: str):
        """Raise parse error with location information."""
        token = self.current()
        if token:
            raise ParseError(f"{message} at {token.line}:{token.col}")
        else:
            raise ParseError(f"{message} at end of input")

    # ========================================================================
    # Abstract Methods (to be implemented by subclasses)
    # ========================================================================

    @abstractmethod
    def parse(self) -> T:
        """Parse token stream and return AST root node."""
        pass


class ParseError(Exception):
    """Parser error exception."""
    pass
