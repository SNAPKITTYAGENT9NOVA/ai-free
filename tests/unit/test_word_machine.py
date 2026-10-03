"""Unit tests: Word Machine (VM, registers, memory, stack)"""

import pytest
from src.word_machine.vm import RegisterFile, Memory, Stack, ExecutionState, WordMachine
from src.word_core.types import WORD64, PTR


class TestRegisterFile:
    def test_init_default_values(self):
        rf = RegisterFile()
        for i in range(16):
            assert rf.get_data(i) == WORD64(0)
            assert rf.get_ptr(i) == PTR(0)

    def test_set_get_data_register(self):
        rf = RegisterFile()
        val = WORD64(12345)
        rf.set_data(0, val)
        assert rf.get_data(0) == val

    def test_set_get_ptr_register(self):
        rf = RegisterFile()
        ptr = PTR(5000)
        rf.set_ptr(5, ptr)
        assert rf.get_ptr(5) == ptr

    def test_invalid_data_register_get(self):
        rf = RegisterFile()
        with pytest.raises(ValueError):
            rf.get_data(16)

    def test_invalid_data_register_set(self):
        rf = RegisterFile()
        with pytest.raises(ValueError):
            rf.set_data(-1, WORD64(0))

    def test_invalid_ptr_register_get(self):
        rf = RegisterFile()
        with pytest.raises(ValueError):
            rf.get_ptr(20)

    def test_register_independence(self):
        rf = RegisterFile()
        rf.set_data(0, WORD64(100))
        rf.set_data(1, WORD64(200))
        assert rf.get_data(0) == WORD64(100)
        assert rf.get_data(1) == WORD64(200)


class TestMemory:
    def test_load_zero_by_default(self):
        mem = Memory()
        result = mem.load(PTR(100))
        assert result == WORD64(0)

    def test_store_and_load(self):
        mem = Memory()
        addr = PTR(200)
        val = WORD64(0x1234567890ABCDEF)
        mem.store(addr, val)
        loaded = mem.load(addr)
        assert loaded == val

    def test_store_multiple_locations(self):
        mem = Memory()
        mem.store(PTR(0), WORD64(111))
        mem.store(PTR(8), WORD64(222))
        assert mem.load(PTR(0)) == WORD64(111)
        assert mem.load(PTR(8)) == WORD64(222)

    def test_load_out_of_bounds(self):
        mem = Memory()
        with pytest.raises(MemoryError):
            mem.load(PTR(1 << 32))

    def test_store_out_of_bounds(self):
        mem = Memory()
        with pytest.raises(MemoryError):
            mem.store(PTR(1 << 32), WORD64(0))

    def test_alloc_returns_pointer(self):
        mem = Memory()
        ptr = mem.alloc(1024)
        assert ptr.address == 0

    def test_alloc_sequential(self):
        mem = Memory()
        p1 = mem.alloc(100)
        p2 = mem.alloc(200)
        assert p1.address == 0
        assert p2.address == 100

    def test_alloc_too_large(self):
        mem = Memory()
        with pytest.raises(MemoryError):
            mem.alloc(1 << 32)


class TestStack:
    def test_push_pop_frame(self):
        stack = Stack()
        ret_addr = PTR(1000)
        stack.push_frame(ret_addr)
        assert stack.depth == 1
        popped = stack.pop_frame()
        assert popped == ret_addr
        assert stack.depth == 0

    def test_stack_fifo(self):
        stack = Stack()
        stack.push_frame(PTR(100))
        stack.push_frame(PTR(200))
        stack.push_frame(PTR(300))
        assert stack.pop_frame() == PTR(300)
        assert stack.pop_frame() == PTR(200)
        assert stack.pop_frame() == PTR(100)

    def test_stack_underflow(self):
        stack = Stack()
        with pytest.raises(RuntimeError):
            stack.pop_frame()

    def test_stack_overflow(self):
        stack = Stack()
        stack.MAX_DEPTH = 10
        for i in range(10):
            stack.push_frame(PTR(i))
        with pytest.raises(RuntimeError):
            stack.push_frame(PTR(11))

    def test_is_empty(self):
        stack = Stack()
        assert stack.is_empty()
        stack.push_frame(PTR(0))
        assert not stack.is_empty()


class TestExecutionState:
    def test_init_default(self):
        state = ExecutionState()
        assert state.pc == 0
        assert state.cycle_count == 0
        assert state.halted == False

    def test_step_increments_cycle(self):
        state = ExecutionState()
        state.step()
        assert state.cycle_count == 1

    def test_step_halt_on_max_cycles(self):
        state = ExecutionState()
        for _ in range(10_000_001):
            state.step()
        assert state.halted


class TestWordMachine:
    def test_init(self):
        vm = WordMachine()
        assert vm.state.pc == 0
        assert vm.state.cycle_count == 0

    def test_reset(self):
        vm = WordMachine()
        vm.state.cycle_count = 100
        vm.reset()
        assert vm.state.cycle_count == 0

    def test_execute_halts_on_limit(self):
        vm = WordMachine()
        final_state = vm.execute(max_cycles=1000)
        assert final_state.cycle_count <= 1000

    def test_register_operations(self):
        vm = WordMachine()
        val = WORD64(42)
        vm.state.registers.set_data(0, val)
        assert vm.state.registers.get_data(0) == val

    def test_memory_operations(self):
        vm = WordMachine()
        addr = PTR(100)
        val = WORD64(999)
        vm.state.memory.store(addr, val)
        loaded = vm.state.memory.load(addr)
        assert loaded == val
