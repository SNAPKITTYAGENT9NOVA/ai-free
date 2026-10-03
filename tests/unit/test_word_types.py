"""Unit tests: Word types (WORD32, WORD64, WORD128, PTR)"""

import pytest
from src.word_core.types import WORD32, WORD64, WORD128, PTR


class TestWORD32:
    def test_construct_valid(self):
        w = WORD32(42)
        assert w.value == 42

    def test_bounds_zero(self):
        w = WORD32(0)
        assert w.value == 0

    def test_bounds_max(self):
        w = WORD32((1 << 32) - 1)
        assert w.value == (1 << 32) - 1

    def test_bounds_overflow(self):
        with pytest.raises(ValueError):
            WORD32(1 << 32)

    def test_bounds_negative(self):
        with pytest.raises(ValueError):
            WORD32(-1)

    def test_addition_wraps(self):
        a = WORD32((1 << 32) - 1)
        b = WORD32(1)
        result = a + b
        assert result.value == 0

    def test_subtraction_wraps(self):
        a = WORD32(0)
        b = WORD32(1)
        result = a - b
        assert result.value == (1 << 32) - 1

    def test_multiplication_wraps(self):
        a = WORD32((1 << 16) + 1)
        b = WORD32((1 << 16) + 1)
        result = a * b
        assert result.value == ((1 << 16) + 1) * ((1 << 16) + 1) & ((1 << 32) - 1)

    def test_bitwise_and(self):
        a = WORD32(0xFFFF0000)
        b = WORD32(0x0000FFFF)
        result = a & b
        assert result.value == 0

    def test_bitwise_or(self):
        a = WORD32(0xFFFF0000)
        b = WORD32(0x0000FFFF)
        result = a | b
        assert result.value == 0xFFFFFFFF

    def test_bitwise_xor(self):
        a = WORD32(0xAAAAAAAA)
        b = WORD32(0x55555555)
        result = a ^ b
        assert result.value == 0xFFFFFFFF

    def test_left_shift(self):
        w = WORD32(1)
        result = w << 31
        assert result.value == (1 << 31)

    def test_right_shift(self):
        w = WORD32(1 << 31)
        result = w >> 31
        assert result.value == 1

    def test_equality(self):
        a = WORD32(42)
        b = WORD32(42)
        assert a == b

    def test_immutable(self):
        w = WORD32(42)
        with pytest.raises(AttributeError):
            w.value = 100


class TestWORD64:
    def test_construct_valid(self):
        w = WORD64(12345)
        assert w.value == 12345

    def test_bounds_max(self):
        w = WORD64((1 << 64) - 1)
        assert w.value == (1 << 64) - 1

    def test_bounds_overflow(self):
        with pytest.raises(ValueError):
            WORD64(1 << 64)

    def test_addition_wraps(self):
        a = WORD64((1 << 64) - 1)
        b = WORD64(1)
        result = a + b
        assert result.value == 0


class TestWORD128:
    def test_construct_valid(self):
        w = WORD128(999)
        assert w.value == 999

    def test_bounds_max(self):
        w = WORD128((1 << 128) - 1)
        assert w.value == (1 << 128) - 1


class TestPTR:
    def test_construct_valid(self):
        p = PTR(1000)
        assert p.address == 1000

    def test_bounds_zero(self):
        p = PTR(0)
        assert p.address == 0

    def test_bounds_max(self):
        p = PTR((1 << 64) - 1)
        assert p.address == (1 << 64) - 1

    def test_bounds_overflow(self):
        with pytest.raises(ValueError):
            PTR(1 << 64)

    def test_ptr_word64_conversion(self):
        w = WORD64(12345)
        p = PTR.from_word64(w)
        assert p.address == 12345
        w2 = p.to_word64()
        assert w2.value == 12345

    def test_pointer_arithmetic_add(self):
        p = PTR(1000)
        result = p + 256
        assert result.address == 1256

    def test_pointer_arithmetic_sub(self):
        p = PTR(1000)
        result = p - 256
        assert result.address == 744

    def test_pointer_equality(self):
        p1 = PTR(500)
        p2 = PTR(500)
        assert p1 == p2

    def test_pointer_comparison(self):
        p1 = PTR(100)
        p2 = PTR(200)
        assert p1 < p2
        assert p1 <= p2
        assert p2 > p1

    def test_pointer_immutable(self):
        p = PTR(42)
        with pytest.raises(AttributeError):
            p.address = 100
