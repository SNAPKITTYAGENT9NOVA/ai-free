# -*- coding: utf-8 -*-
"""
Unit tests for ARC2ProgramSynthesizer and ARC DSL primitives.
"""

import unittest

import numpy as np

import arc_dsl_primitives as dsl
from arc2_program_synthesizer import ARC2ProgramSynthesizer
from arc_dataset_loader import ARCPair


class TestARC2Synthesizer(unittest.TestCase):
    def test_dsl_primitives(self):
        arr = np.array([[1, 2], [3, 4]])
        rot = dsl.rotate_cw(arr, 1)
        self.assertTrue(np.array_equal(rot, np.array([[3, 1], [4, 2]])))

        grav = dsl.apply_gravity(np.array([[1, 0], [0, 2], [0, 0]]), "DOWN")
        expected = np.array([[0, 0], [0, 0], [1, 2]])
        self.assertTrue(np.array_equal(grav, expected))

    def test_synthesizer_rot_gravity(self):
        demo_in = np.array([[1, 0, 0], [0, 2, 0], [0, 0, 0]], dtype=np.uint8)
        demo_out = dsl.apply_gravity(dsl.rotate_cw(demo_in, 1), "DOWN")
        pair = ARCPair(input_grid=demo_in, output_grid=demo_out)

        synth = ARC2ProgramSynthesizer(max_depth=3, timeout_sec=5.0)
        sol = synth.synthesize([pair])
        self.assertIsNotNone(sol)
        assert sol is not None

        curr = demo_in.copy()
        for op_name in sol:
            for op in synth.operators:
                if op.name == op_name:
                    curr = op.fn(curr)
                    break
        self.assertTrue(np.array_equal(curr, demo_out))


if __name__ == "__main__":
    unittest.main()
