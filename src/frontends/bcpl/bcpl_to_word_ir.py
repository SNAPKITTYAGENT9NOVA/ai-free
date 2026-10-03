"""BCPL → Word IR compiler: lowers BCPL AST to canonical Word IR.

Semantics:
  - Variables map to memory locations (allocated on stack)
  - Operations map to Word IR nodes (ir_add, ir_load, ir_store, etc.)
  - Control flow (if, while) maps to conditional jumps
  - Functions map to IR blocks with entry/exit
"""

from typing import Dict, List, Tuple
from src.word_ir.ir_ast import (
    IRNode, IRWord, IRPointer, IRLoad, IRStore, IRBinOp, IRUnaryOp,
    IRAlloc, IRCompare, IRJump, IRCall, IRReturn, IRBlock, IRProgram,
    IRNodeType, ir_add, ir_sub, ir_mul, ir_and, ir_or, ir_xor,
    ir_load, ir_store, ir_word, ir_ptr, ir_shl, ir_shr
)
from .bcpl_ast import (
    Expr, BinOp, UnaryOp, Number, Identifier, Call, Load, Alloc,
    Stmt, Assignment, Store, IfStmt, WhileStmt, ForStmt, ReturnStmt, ExprStmt, Block,
    FuncDef, Program
)


class BCPLLowering:
    """Lower BCPL AST to Word IR."""

    def __init__(self):
        self.var_offsets: Dict[str, int] = {}
        self.next_offset = 0
        self.blocks: Dict[str, List[IRNode]] = {}
        self.label_counter = 0

    def fresh_label(self) -> str:
        """Generate a fresh label."""
        label = f"L{self.label_counter}"
        self.label_counter += 1
        return label

    def allocate_var(self, name: str) -> int:
        """Allocate stack space for a variable."""
        if name not in self.var_offsets:
            offset = self.next_offset
            self.var_offsets[name] = offset
            self.next_offset += 8
        return self.var_offsets[name]

    def lower_expr(self, expr: Expr) -> IRNode:
        """Lower expression to IR node."""
        if isinstance(expr, Number):
            return ir_word(expr.value, width=64)
        elif isinstance(expr, Identifier):
            offset = self.allocate_var(expr.name)
            addr = ir_word(offset, width=64)
            return ir_load(addr)
        elif isinstance(expr, BinOp):
            left = self.lower_expr(expr.left)
            right = self.lower_expr(expr.right)
            if expr.op == "+":
                return ir_add(left, right)
            elif expr.op == "-":
                return ir_sub(left, right)
            elif expr.op == "*":
                return ir_mul(left, right)
            elif expr.op == "&":
                return ir_and(left, right)
            elif expr.op == "|":
                return ir_or(left, right)
            elif expr.op == "^":
                return ir_xor(left, right)
            elif expr.op in ("==", "!=", "<", "<=", ">", ">="):
                return IRCompare(left=left, right=right, condition=expr.op)
            else:
                raise ValueError(f"Unknown binary operator: {expr.op}")
        elif isinstance(expr, UnaryOp):
            operand = self.lower_expr(expr.operand)
            if expr.op == "-":
                zero = ir_word(0, width=64)
                return ir_sub(zero, operand)
            else:
                raise ValueError(f"Unknown unary operator: {expr.op}")
        elif isinstance(expr, Load):
            addr = self.lower_expr(expr.address)
            return ir_load(addr)
        elif isinstance(expr, Alloc):
            size = self.lower_expr(expr.size)
            return IRAlloc(size=size)
        elif isinstance(expr, Call):
            args = [self.lower_expr(arg) for arg in expr.args]
            target = 0
            return IRCall(target=target, args=tuple(args))
        else:
            raise ValueError(f"Unknown expression type: {type(expr)}")

    def lower_stmt(self, stmt: Stmt) -> List[IRNode]:
        """Lower statement to list of IR nodes."""
        if isinstance(stmt, ExprStmt):
            return [self.lower_expr(stmt.expr)]
        elif isinstance(stmt, Assignment):
            offset = self.allocate_var(stmt.lhs)
            addr = ir_word(offset, width=64)
            value = self.lower_expr(stmt.rhs)
            return [ir_store(addr, value)]
        elif isinstance(stmt, Store):
            addr = self.lower_expr(stmt.address)
            value = self.lower_expr(stmt.value)
            return [ir_store(addr, value)]
        elif isinstance(stmt, IfStmt):
            ir_nodes = []
            cond = self.lower_expr(stmt.condition)
            ir_nodes.append(cond)
            then_label = self.fresh_label()
            else_label = self.fresh_label() if stmt.else_block else None
            end_label = self.fresh_label()
            ir_nodes.append(IRJump(
                target=0,
                conditional=True,
                condition="ne"
            ))
            for s in stmt.then_block:
                ir_nodes.extend(self.lower_stmt(s))
            ir_nodes.append(IRJump(target=0))
            if stmt.else_block:
                for s in stmt.else_block:
                    ir_nodes.extend(self.lower_stmt(s))
            return ir_nodes
        elif isinstance(stmt, WhileStmt):
            ir_nodes = []
            loop_label = self.fresh_label()
            cond = self.lower_expr(stmt.condition)
            ir_nodes.append(cond)
            ir_nodes.append(IRJump(target=0, conditional=True, condition="ne"))
            for s in stmt.body:
                ir_nodes.extend(self.lower_stmt(s))
            ir_nodes.append(IRJump(target=0))
            return ir_nodes
        elif isinstance(stmt, ForStmt):
            ir_nodes = []
            if stmt.init:
                ir_nodes.extend(self.lower_stmt(stmt.init))
            loop_label = self.fresh_label()
            cond = self.lower_expr(stmt.condition)
            ir_nodes.append(cond)
            ir_nodes.append(IRJump(target=0, conditional=True, condition="ne"))
            for s in stmt.body:
                ir_nodes.extend(self.lower_stmt(s))
            if stmt.update:
                ir_nodes.extend(self.lower_stmt(stmt.update))
            ir_nodes.append(IRJump(target=0))
            return ir_nodes
        elif isinstance(stmt, ReturnStmt):
            if stmt.value:
                value = self.lower_expr(stmt.value)
                return [value, IRReturn()]
            else:
                return [IRReturn()]
        elif isinstance(stmt, Block):
            ir_nodes = []
            for s in stmt.stmts:
                ir_nodes.extend(self.lower_stmt(s))
            return ir_nodes
        else:
            raise ValueError(f"Unknown statement type: {type(stmt)}")

    def lower_function(self, func: FuncDef) -> Tuple[str, IRBlock]:
        """Lower function definition to IR block."""
        self.var_offsets.clear()
        self.next_offset = 0
        ir_nodes = []
        for param in func.params:
            self.allocate_var(param)
        for stmt in func.body:
            ir_nodes.extend(self.lower_stmt(stmt))
        return func.name, IRBlock(label=func.name, nodes=ir_nodes)

    def lower_program(self, program: Program) -> IRProgram:
        """Lower BCPL program to Word IR program."""
        self.blocks.clear()
        for func in program.functions:
            name, block = self.lower_function(func)
            self.blocks[name] = block
        return IRProgram(blocks=self.blocks, entry="main")


def lower_bcpl_to_ir(program: Program) -> IRProgram:
    """Convenience function: lower BCPL AST to Word IR program."""
    lowering = BCPLLowering()
    return lowering.lower_program(program)
