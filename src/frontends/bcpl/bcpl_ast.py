"""BCPL Abstract Syntax Tree (AST) definitions."""

from dataclasses import dataclass
from typing import List, Optional, Union


@dataclass
class Expr:
    """Base expression class."""
    pass


@dataclass
class BinOp(Expr):
    """Binary operation: op(left, right)"""
    op: str
    left: Expr
    right: Expr


@dataclass
class UnaryOp(Expr):
    """Unary operation: op(operand)"""
    op: str
    operand: Expr


@dataclass
class Number(Expr):
    """Numeric literal."""
    value: int


@dataclass
class Identifier(Expr):
    """Variable reference."""
    name: str


@dataclass
class Call(Expr):
    """Function call: name(args)"""
    name: str
    args: List[Expr]


@dataclass
class Load(Expr):
    """Memory load: @address"""
    address: Expr


@dataclass
class Alloc(Expr):
    """Memory allocation: alloc(size)"""
    size: Expr


@dataclass
class Stmt:
    """Base statement class."""
    pass


@dataclass
class Assignment(Stmt):
    """Assignment: lhs = rhs"""
    lhs: str
    rhs: Expr


@dataclass
class Store(Stmt):
    """Memory store: address! = value"""
    address: Expr
    value: Expr


@dataclass
class IfStmt(Stmt):
    """If statement: if(cond) then block else block"""
    condition: Expr
    then_block: List[Stmt]
    else_block: Optional[List[Stmt]] = None


@dataclass
class WhileStmt(Stmt):
    """While loop: while(cond) do block"""
    condition: Expr
    body: List[Stmt]


@dataclass
class ForStmt(Stmt):
    """For loop: for(init; cond; update) do block"""
    init: Optional[Stmt]
    condition: Expr
    update: Optional[Stmt]
    body: List[Stmt]


@dataclass
class ReturnStmt(Stmt):
    """Return statement: return expr"""
    value: Optional[Expr] = None


@dataclass
class ExprStmt(Stmt):
    """Expression statement."""
    expr: Expr


@dataclass
class Block(Stmt):
    """Block of statements."""
    stmts: List[Stmt]


@dataclass
class FuncDef:
    """Function definition."""
    name: str
    params: List[str]
    body: List[Stmt]


@dataclass
class Program:
    """BCPL program: list of function definitions."""
    functions: List[FuncDef]
