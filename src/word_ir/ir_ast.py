"""Universal Word IR: Canonical intermediate representation

All frontends (BCPL, Forth, Wolfram) lower to this single IR.
No ISA-specific assumptions. Pure word and pointer semantics.
"""

from dataclasses import dataclass
from enum import Enum
from typing import List, Optional, Union, Any


class IRNodeType(Enum):
    """Canonical IR node types: language-agnostic, ISA-neutral"""
    WORD = "WORD"
    PTR = "PTR"
    LOAD = "LOAD"
    STORE = "STORE"
    ADD = "ADD"
    SUB = "SUB"
    MUL = "MUL"
    AND = "AND"
    OR = "OR"
    XOR = "XOR"
    SHL = "SHL"
    SHR = "SHR"
    ROT = "ROT"
    CMP = "CMP"
    JMP = "JMP"
    CALL = "CALL"
    RET = "RET"
    ALLOC = "ALLOC"


@dataclass(frozen=True)
class IRNode:
    """Base IR node: immutable, type-tagged"""
    node_type: IRNodeType = None
    operands: tuple = ()
    metadata: dict = None

    def __post_init__(self):
        if self.metadata is None:
            object.__setattr__(self, 'metadata', {})


@dataclass(frozen=True)
class IRWord(IRNode):
    """Literal word value (WORD32, WORD64, WORD128)"""
    value: int = 0
    width: int = 64

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.WORD)
        if self.metadata is None:
            object.__setattr__(self, 'metadata', {'width': self.width, 'value': self.value})


@dataclass(frozen=True)
class IRPointer(IRNode):
    """Pointer literal or symbolic address"""
    address: int = 0

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.PTR)
        if self.metadata is None:
            object.__setattr__(self, 'metadata', {'address': self.address})


@dataclass(frozen=True)
class IRLoad(IRNode):
    """Load from memory: LOAD(address_expr) → word"""
    address: IRNode = None

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.LOAD)
        object.__setattr__(self, 'operands', (self.address,))


@dataclass(frozen=True)
class IRStore(IRNode):
    """Store to memory: STORE(address_expr, value_expr)"""
    address: IRNode = None
    value: IRNode = None

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.STORE)
        object.__setattr__(self, 'operands', (self.address, self.value))


@dataclass(frozen=True)
class IRBinOp(IRNode):
    """Binary operation: op(left, right) → word"""
    op_type: IRNodeType = IRNodeType.ADD
    left: IRNode = None
    right: IRNode = None

    def __post_init__(self):
        object.__setattr__(self, 'node_type', self.op_type)
        object.__setattr__(self, 'operands', (self.left, self.right))


@dataclass(frozen=True)
class IRUnaryOp(IRNode):
    """Unary operation: op(operand) → word"""
    op_type: IRNodeType = IRNodeType.SHL
    operand: IRNode = None

    def __post_init__(self):
        object.__setattr__(self, 'node_type', self.op_type)
        object.__setattr__(self, 'operands', (self.operand,))


@dataclass(frozen=True)
class IRAlloc(IRNode):
    """Allocate memory: ALLOC(size_expr) → pointer"""
    size: IRNode = None

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.ALLOC)
        object.__setattr__(self, 'operands', (self.size,))


@dataclass(frozen=True)
class IRCompare(IRNode):
    """Compare: CMP(left, right) → condition code"""
    left: IRNode = None
    right: IRNode = None
    condition: str = "eq"

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.CMP)
        object.__setattr__(self, 'operands', (self.left, self.right))
        if self.metadata is None:
            object.__setattr__(self, 'metadata', {'condition': self.condition})


@dataclass(frozen=True)
class IRJump(IRNode):
    """Jump to address"""
    target: int = 0
    conditional: bool = False
    condition: str = None

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.JMP)
        if self.metadata is None:
            object.__setattr__(self, 'metadata', {
                'target': self.target,
                'conditional': self.conditional,
                'condition': self.condition
            })


@dataclass(frozen=True)
class IRCall(IRNode):
    """Call function at address"""
    target: int = 0
    args: tuple = ()

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.CALL)
        if self.metadata is None:
            object.__setattr__(self, 'metadata', {'target': self.target, 'args_count': len(self.args)})


@dataclass(frozen=True)
class IRReturn(IRNode):
    """Return from function"""

    def __post_init__(self):
        object.__setattr__(self, 'node_type', IRNodeType.RET)


@dataclass(frozen=True)
class IRBlock:
    """Basic block: sequence of IR nodes"""
    label: str
    nodes: List[IRNode] = None

    def __post_init__(self):
        if self.nodes is None:
            object.__setattr__(self, 'nodes', [])


@dataclass(frozen=True)
class IRProgram:
    """Complete IR program: blocks + entry point"""
    blocks: dict = None
    entry: str = "main"

    def __post_init__(self):
        if self.blocks is None:
            object.__setattr__(self, 'blocks', {})


def ir_add(left: IRNode, right: IRNode) -> IRNode:
    return IRBinOp(op_type=IRNodeType.ADD, left=left, right=right)


def ir_sub(left: IRNode, right: IRNode) -> IRNode:
    return IRBinOp(op_type=IRNodeType.SUB, left=left, right=right)


def ir_mul(left: IRNode, right: IRNode) -> IRNode:
    return IRBinOp(op_type=IRNodeType.MUL, left=left, right=right)


def ir_and(left: IRNode, right: IRNode) -> IRNode:
    return IRBinOp(op_type=IRNodeType.AND, left=left, right=right)


def ir_or(left: IRNode, right: IRNode) -> IRNode:
    return IRBinOp(op_type=IRNodeType.OR, left=left, right=right)


def ir_xor(left: IRNode, right: IRNode) -> IRNode:
    return IRBinOp(op_type=IRNodeType.XOR, left=left, right=right)


def ir_shl(operand: IRNode, amount: int) -> IRNode:
    return IRUnaryOp(op_type=IRNodeType.SHL, operand=operand)


def ir_shr(operand: IRNode, amount: int) -> IRNode:
    return IRUnaryOp(op_type=IRNodeType.SHR, operand=operand)


def ir_load(addr: IRNode) -> IRNode:
    return IRLoad(address=addr)


def ir_store(addr: IRNode, val: IRNode) -> IRNode:
    return IRStore(address=addr, value=val)


def ir_word(val: int, width: int = 64) -> IRNode:
    return IRWord(node_type=None, value=val, width=width)


def ir_ptr(addr: int) -> IRNode:
    return IRPointer(node_type=None, address=addr)
