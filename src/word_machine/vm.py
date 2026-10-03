"""Word Machine: Virtual machine for Word Dialect

RegisterFile(W0..W15 data registers, P0..P15 pointer registers)
Linear memory with deterministic LOAD/STORE semantics
Stack with frame tracking
Deterministic instruction execution
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple
from enum import Enum
from src.word_core.types import WORD64, PTR, WordValue


class Instruction(Enum):
    """Word Dialect instruction set"""
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
    HALT = "HALT"


@dataclass
class RegisterFile:
    """16 data registers (W0..W15) + 16 pointer registers (P0..P15)"""
    data: Dict[int, WORD64] = field(default_factory=lambda: {i: WORD64(0) for i in range(16)})
    ptrs: Dict[int, PTR] = field(default_factory=lambda: {i: PTR(0) for i in range(16)})

    def set_data(self, reg: int, val: WORD64) -> None:
        if not (0 <= reg < 16):
            raise ValueError(f"Invalid data register: {reg}")
        self.data[reg] = val

    def get_data(self, reg: int) -> WORD64:
        if not (0 <= reg < 16):
            raise ValueError(f"Invalid data register: {reg}")
        return self.data[reg]

    def set_ptr(self, reg: int, addr: PTR) -> None:
        if not (0 <= reg < 16):
            raise ValueError(f"Invalid pointer register: {reg}")
        self.ptrs[reg] = addr

    def get_ptr(self, reg: int) -> PTR:
        if not (0 <= reg < 16):
            raise ValueError(f"Invalid pointer register: {reg}")
        return self.ptrs[reg]


@dataclass
class Memory:
    """Linear address space: 2^32 bytes max. LOAD/STORE operations are deterministic."""
    MAX_SIZE: int = (1 << 32)
    cells: Dict[int, int] = field(default_factory=dict)
    allocations: List[Tuple[int, int]] = field(default_factory=list)
    next_alloc: int = 0

    def load(self, addr: PTR) -> WORD64:
        """Load 8 bytes from address (little-endian)"""
        if addr.address >= self.MAX_SIZE:
            raise MemoryError(f"Load address out of bounds: {addr.address}")
        val = 0
        for i in range(8):
            byte_addr = addr.address + i
            byte_val = self.cells.get(byte_addr, 0)
            val |= (byte_val & 0xFF) << (8 * i)
        return WORD64(val & ((1 << 64) - 1))

    def store(self, addr: PTR, val: WORD64) -> None:
        """Store 8 bytes to address (little-endian)"""
        if addr.address >= self.MAX_SIZE:
            raise MemoryError(f"Store address out of bounds: {addr.address}")
        for i in range(8):
            byte_addr = addr.address + i
            byte_val = (val.value >> (8 * i)) & 0xFF
            self.cells[byte_addr] = byte_val

    def alloc(self, size: int) -> PTR:
        """Allocate contiguous memory, return pointer"""
        if self.next_alloc + size >= self.MAX_SIZE:
            raise MemoryError(f"Allocation would exceed memory")
        addr = self.next_alloc
        self.allocations.append((addr, size))
        self.next_alloc += size
        return PTR(addr)


@dataclass
class Stack:
    """Call stack with frame tracking"""
    MAX_DEPTH: int = 65536
    frames: List[PTR] = field(default_factory=list)
    depth: int = 0

    def push_frame(self, ret_addr: PTR) -> None:
        """Push return address as frame"""
        if self.depth >= self.MAX_DEPTH:
            raise RuntimeError("Stack overflow")
        self.frames.append(ret_addr)
        self.depth += 1

    def pop_frame(self) -> PTR:
        """Pop return address"""
        if self.depth == 0:
            raise RuntimeError("Stack underflow")
        self.depth -= 1
        return self.frames.pop()

    def is_empty(self) -> bool:
        return self.depth == 0


@dataclass
class ExecutionState:
    """Complete VM state for deterministic execution"""
    pc: int = 0
    registers: RegisterFile = field(default_factory=RegisterFile)
    memory: Memory = field(default_factory=Memory)
    stack: Stack = field(default_factory=Stack)
    cycle_count: int = 0
    halted: bool = False

    def step(self) -> None:
        """Execute one instruction (deterministic). Placeholder: no code loaded yet."""
        self.cycle_count += 1
        if self.cycle_count > 10_000_000:
            self.halted = True

    def is_terminal(self) -> bool:
        """Execution has terminated"""
        return self.halted or (self.stack.is_empty() and self.pc == 0)


class WordMachine:
    """Word Dialect Virtual Machine: deterministic execution engine"""

    def __init__(self):
        self.state = ExecutionState()

    def load_code(self, instructions: List[Tuple[int, Instruction]]) -> None:
        """Load program: list of (address, instruction)"""
        pass

    def execute(self, max_cycles: int = 1_000_000) -> ExecutionState:
        """Run until halt or cycle limit. Always deterministic."""
        while not self.state.is_terminal() and self.state.cycle_count < max_cycles:
            self.state.step()
        return self.state

    def reset(self) -> None:
        """Reset VM to initial state"""
        self.state = ExecutionState()
