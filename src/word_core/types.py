"""Word Dialect Type System: WORD[N], PTR, Invariants

Universal word types as first-class citizens. All numeric computation flows through WORD.
PTR is representation-compatible with WORD — pointer arithmetic is word arithmetic.
"""

from dataclasses import dataclass
from typing import Union, ClassVar


@dataclass(frozen=True)
class WORD32:
    """32-bit word with bounds invariant: 0 ≤ value < 2^32"""
    value: int

    MAX: ClassVar[int] = (1 << 32) - 1

    def __post_init__(self):
        if not (0 <= self.value <= self.MAX):
            raise ValueError(f"WORD32 out of bounds: {self.value} not in [0, 2^32)")

    def __add__(self, other: 'WORD32') -> 'WORD32':
        return WORD32((self.value + other.value) & self.MAX)

    def __sub__(self, other: 'WORD32') -> 'WORD32':
        return WORD32((self.value - other.value) & self.MAX)

    def __mul__(self, other: 'WORD32') -> 'WORD32':
        return WORD32((self.value * other.value) & self.MAX)

    def __and__(self, other: 'WORD32') -> 'WORD32':
        return WORD32(self.value & other.value)

    def __or__(self, other: 'WORD32') -> 'WORD32':
        return WORD32(self.value | other.value)

    def __xor__(self, other: 'WORD32') -> 'WORD32':
        return WORD32(self.value ^ other.value)

    def __lshift__(self, n: int) -> 'WORD32':
        if not (0 <= n < 32):
            raise ValueError(f"Shift amount out of bounds: {n}")
        return WORD32((self.value << n) & self.MAX)

    def __rshift__(self, n: int) -> 'WORD32':
        if not (0 <= n < 32):
            raise ValueError(f"Shift amount out of bounds: {n}")
        return WORD32(self.value >> n)

    def __eq__(self, other: 'WORD32') -> bool:
        return self.value == other.value

    def __lt__(self, other: 'WORD32') -> bool:
        return self.value < other.value

    def __le__(self, other: 'WORD32') -> bool:
        return self.value <= other.value


@dataclass(frozen=True)
class WORD64:
    """64-bit word with bounds invariant: 0 ≤ value < 2^64"""
    value: int

    MAX: ClassVar[int] = (1 << 64) - 1

    def __post_init__(self):
        if not (0 <= self.value <= self.MAX):
            raise ValueError(f"WORD64 out of bounds: {self.value} not in [0, 2^64)")

    def __add__(self, other: 'WORD64') -> 'WORD64':
        return WORD64((self.value + other.value) & self.MAX)

    def __sub__(self, other: 'WORD64') -> 'WORD64':
        return WORD64((self.value - other.value) & self.MAX)

    def __mul__(self, other: 'WORD64') -> 'WORD64':
        return WORD64((self.value * other.value) & self.MAX)

    def __and__(self, other: 'WORD64') -> 'WORD64':
        return WORD64(self.value & other.value)

    def __or__(self, other: 'WORD64') -> 'WORD64':
        return WORD64(self.value | other.value)

    def __xor__(self, other: 'WORD64') -> 'WORD64':
        return WORD64(self.value ^ other.value)

    def __lshift__(self, n: int) -> 'WORD64':
        if not (0 <= n < 64):
            raise ValueError(f"Shift amount out of bounds: {n}")
        return WORD64((self.value << n) & self.MAX)

    def __rshift__(self, n: int) -> 'WORD64':
        if not (0 <= n < 64):
            raise ValueError(f"Shift amount out of bounds: {n}")
        return WORD64(self.value >> n)

    def __eq__(self, other: 'WORD64') -> bool:
        return self.value == other.value

    def __lt__(self, other: 'WORD64') -> bool:
        return self.value < other.value

    def __le__(self, other: 'WORD64') -> bool:
        return self.value <= other.value


@dataclass(frozen=True)
class WORD128:
    """128-bit word with bounds invariant: 0 ≤ value < 2^128"""
    value: int

    MAX: ClassVar[int] = (1 << 128) - 1

    def __post_init__(self):
        if not (0 <= self.value <= self.MAX):
            raise ValueError(f"WORD128 out of bounds: {self.value} not in [0, 2^128)")

    def __add__(self, other: 'WORD128') -> 'WORD128':
        return WORD128((self.value + other.value) & self.MAX)

    def __sub__(self, other: 'WORD128') -> 'WORD128':
        return WORD128((self.value - other.value) & self.MAX)

    def __mul__(self, other: 'WORD128') -> 'WORD128':
        return WORD128((self.value * other.value) & self.MAX)


@dataclass(frozen=True)
class PTR:
    """Pointer: representation-compatible with WORD64. Address in linear memory [0, 2^64)"""
    address: int

    MAX_ADDRESS: ClassVar[int] = (1 << 64) - 1

    def __post_init__(self):
        if not (0 <= self.address <= self.MAX_ADDRESS):
            raise ValueError(f"PTR address out of bounds: {self.address}")

    @staticmethod
    def from_word64(w: WORD64) -> 'PTR':
        """PTR and WORD64 have identical representations."""
        return PTR(w.value)

    def to_word64(self) -> WORD64:
        """PTR and WORD64 have identical representations."""
        return WORD64(self.address)

    def __add__(self, offset: int) -> 'PTR':
        """Pointer arithmetic: PTR + bytes."""
        return PTR((self.address + offset) & self.MAX_ADDRESS)

    def __sub__(self, offset: int) -> 'PTR':
        """Pointer arithmetic: PTR - bytes."""
        return PTR((self.address - offset) & self.MAX_ADDRESS)

    def __eq__(self, other: 'PTR') -> bool:
        return self.address == other.address

    def __lt__(self, other: 'PTR') -> bool:
        return self.address < other.address

    def __le__(self, other: 'PTR') -> bool:
        return self.address <= other.address


WordValue = Union[WORD32, WORD64, WORD128, PTR]
