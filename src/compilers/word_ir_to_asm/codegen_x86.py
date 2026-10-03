"""Word IR → x86-64 assembly code generator.

Semantics:
  - Word registers → x86 general-purpose registers (RAX, RBX, RCX, RDX, RSI, RDI, R8-R15)
  - LOAD → MOV from memory
  - STORE → MOV to memory
  - ADD/SUB/MUL/etc. → corresponding x86 instructions
  - ALLOC → stack allocation
  - CALL/RET → function calling convention (System V AMD64 ABI)
"""

from typing import Dict, List, Tuple
from src.word_ir.ir_ast import (
    IRNode, IRWord, IRPointer, IRLoad, IRStore, IRBinOp, IRUnaryOp,
    IRAlloc, IRCompare, IRJump, IRCall, IRReturn, IRBlock, IRProgram,
    IRNodeType
)


class X86RegisterAllocator:
    """Simple register allocator for x86-64."""

    REGISTERS = ["rax", "rbx", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15"]
    CALLER_SAVED = ["rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11"]
    CALLEE_SAVED = ["rbx", "rbp", "rsp", "r12", "r13", "r14", "r15"]

    def __init__(self):
        self.reg_map: Dict[int, str] = {}
        self.next_reg = 0

    def allocate(self) -> str:
        """Allocate the next available register."""
        reg = self.REGISTERS[self.next_reg % len(self.REGISTERS)]
        self.next_reg += 1
        return reg

    def reset(self):
        """Reset allocator."""
        self.reg_map.clear()
        self.next_reg = 0


class X86CodeGen:
    """Generate x86-64 assembly from Word IR."""

    def __init__(self):
        self.allocator = X86RegisterAllocator()
        self.code: List[str] = []
        self.label_counter = 0

    def fresh_label(self) -> str:
        """Generate fresh label."""
        label = f".L{self.label_counter}"
        self.label_counter += 1
        return label

    def emit(self, instruction: str):
        """Emit an x86 instruction."""
        self.code.append(f"  {instruction}")

    def emit_label(self, label: str):
        """Emit a label."""
        self.code.append(f"{label}:")

    def lower_ir_node(self, node: IRNode) -> str:
        """Lower IR node to x86 instruction sequence, return result register."""
        if isinstance(node, IRWord):
            reg = self.allocator.allocate()
            self.emit(f"movq ${node.value}, %{reg}")
            return reg
        elif isinstance(node, IRPointer):
            reg = self.allocator.allocate()
            self.emit(f"movq ${node.address}, %{reg}")
            return reg
        elif isinstance(node, IRLoad):
            addr_reg = self.lower_ir_node(node.address)
            result_reg = self.allocator.allocate()
            self.emit(f"movq (%{addr_reg}), %{result_reg}")
            return result_reg
        elif isinstance(node, IRStore):
            addr_reg = self.lower_ir_node(node.address)
            val_reg = self.lower_ir_node(node.value)
            self.emit(f"movq %{val_reg}, (%{addr_reg})")
            return addr_reg
        elif isinstance(node, IRBinOp):
            left_reg = self.lower_ir_node(node.left)
            right_reg = self.lower_ir_node(node.right)
            result_reg = self.allocator.allocate()

            if node.op_type == IRNodeType.ADD:
                self.emit(f"movq %{left_reg}, %{result_reg}")
                self.emit(f"addq %{right_reg}, %{result_reg}")
            elif node.op_type == IRNodeType.SUB:
                self.emit(f"movq %{left_reg}, %{result_reg}")
                self.emit(f"subq %{right_reg}, %{result_reg}")
            elif node.op_type == IRNodeType.MUL:
                self.emit(f"movq %{left_reg}, %rax")
                self.emit(f"imulq %{right_reg}, %rax")
                self.emit(f"movq %rax, %{result_reg}")
            elif node.op_type == IRNodeType.AND:
                self.emit(f"movq %{left_reg}, %{result_reg}")
                self.emit(f"andq %{right_reg}, %{result_reg}")
            elif node.op_type == IRNodeType.OR:
                self.emit(f"movq %{left_reg}, %{result_reg}")
                self.emit(f"orq %{right_reg}, %{result_reg}")
            elif node.op_type == IRNodeType.XOR:
                self.emit(f"movq %{left_reg}, %{result_reg}")
                self.emit(f"xorq %{right_reg}, %{result_reg}")

            return result_reg
        elif isinstance(node, IRUnaryOp):
            operand_reg = self.lower_ir_node(node.operand)
            result_reg = self.allocator.allocate()

            if node.op_type == IRNodeType.SHL:
                self.emit(f"movq %{operand_reg}, %{result_reg}")
                self.emit(f"shlq $1, %{result_reg}")
            elif node.op_type == IRNodeType.SHR:
                self.emit(f"movq %{operand_reg}, %{result_reg}")
                self.emit(f"shrq $1, %{result_reg}")

            return result_reg
        elif isinstance(node, IRCompare):
            left_reg = self.lower_ir_node(node.left)
            right_reg = self.lower_ir_node(node.right)
            self.emit(f"cmpq %{right_reg}, %{left_reg}")
            return left_reg
        elif isinstance(node, IRAlloc):
            size_reg = self.lower_ir_node(node.size)
            self.emit(f"subq %{size_reg}, %rsp")
            return "rsp"
        elif isinstance(node, IRReturn):
            self.emit("retq")
            return "rax"
        else:
            return "rax"

    def lower_block(self, block: IRBlock):
        """Lower IR block to x86 assembly."""
        self.emit_label(block.label)
        self.allocator.reset()

        for node in block.nodes:
            self.lower_ir_node(node)

    def lower_program(self, program: IRProgram) -> str:
        """Lower entire IR program to x86-64 assembly."""
        self.code = []
        self.code.append(".section .text")
        self.code.append(".globl main")

        entry_block = program.blocks.get(program.entry)
        if entry_block:
            self.lower_block(entry_block)

        for label, block in program.blocks.items():
            if label != program.entry:
                self.lower_block(block)

        self.code.append("movq $0, %rax")
        self.code.append("retq")

        return "\n".join(self.code)


def codegen_x86(program: IRProgram) -> str:
    """Generate x86-64 assembly from Word IR program."""
    codegen = X86CodeGen()
    return codegen.lower_program(program)
