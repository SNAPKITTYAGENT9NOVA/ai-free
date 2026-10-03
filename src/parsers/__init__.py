"""Parser module: unified parsing infrastructure for Universal Word Dialect Stack.

Provides:
  - base_parser: Abstract Parser class and common AST node classes
  - bcpl_parser: BCPL language parser
  - forth_parser: Forth language parser
  - wolfram_parser: Wolfram language parser

All parsers accept tokens from the corresponding lexers and output AST nodes
with full source location tracking for error reporting and debugging.
"""

from .base_parser import (
    Parser,
    ParseError,
    SourceLocation,
    ASTNode,
    Program,
    FunctionDef,
    Stmt,
    Expr,
    Literal,
    Identifier,
    BinaryOp,
    UnaryOp,
    Call,
    Load,
    Index,
    ExprStmt,
    Assignment,
    Store,
    Block,
    IfStmt,
    WhileStmt,
    ForStmt,
    ReturnStmt,
)

from .bcpl_parser import BCPLParser, parse_bcpl
from .forth_parser import (
    ForthParser,
    parse_forth,
    ForthProgram,
    ForthWord,
    ForthLiteral,
    ForthBuiltin,
    ForthCustomWord,
    ForthWordDef,
)
from .wolfram_parser import (
    WolframParser,
    parse_wolfram,
    WolframProgram,
    WolframExpr,
    WolframLiteral,
    WolframSymbol,
    WolframFunctionCall,
    WolframList,
    WolframMatrix,
)

__all__ = [
    # Base parser
    "Parser",
    "ParseError",
    "SourceLocation",
    "ASTNode",
    "Program",
    "FunctionDef",
    "Stmt",
    "Expr",
    "Literal",
    "Identifier",
    "BinaryOp",
    "UnaryOp",
    "Call",
    "Load",
    "Index",
    "ExprStmt",
    "Assignment",
    "Store",
    "Block",
    "IfStmt",
    "WhileStmt",
    "ForStmt",
    "ReturnStmt",
    # BCPL parser
    "BCPLParser",
    "parse_bcpl",
    # Forth parser
    "ForthParser",
    "parse_forth",
    "ForthProgram",
    "ForthWord",
    "ForthLiteral",
    "ForthBuiltin",
    "ForthCustomWord",
    "ForthWordDef",
    # Wolfram parser
    "WolframParser",
    "parse_wolfram",
    "WolframProgram",
    "WolframExpr",
    "WolframLiteral",
    "WolframSymbol",
    "WolframFunctionCall",
    "WolframList",
    "WolframMatrix",
]
