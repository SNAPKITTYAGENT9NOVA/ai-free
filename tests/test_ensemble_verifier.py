# -*- coding: utf-8 -*-
import unittest

import numpy as np

import arc_dsl_primitives as dsl
from arc_dataset_loader import ARCPair
from ensemble_verifier import ARC2EnsembleVerifier


class TestEnsembleVerifier(unittest.TestCase):
    def test_rank_and_verify(self):
        in1 = np.array([[1, 0], [0, 2]], dtype=np.uint8)
        out1 = dsl.apply_gravity(dsl.rotate_cw(in1, 1), "DOWN")
        test_in = np.array([[3, 0], [0, 4]], dtype=np.uint8)
        expected_out = dsl.apply_gravity(dsl.rotate_cw(test_in, 1), "DOWN")

        verifier = ARC2EnsembleVerifier()
        candidates = verifier.rank_and_verify(
            candidate_programs=[["rot90", "gravity_down"], ["rot90"]],
            train_pairs=[ARCPair(in1, out1)],
            test_input=test_in,
            top_k=2,
        )
        self.assertGreater(len(candidates), 0)
        self.assertEqual(candidates[0].program_names, ["rot90", "gravity_down"])
        self.assertTrue(np.array_equal(candidates[0].predicted_grid, expected_out))
        self.assertEqual(candidates[0].train_score, 0.0)


if __name__ == "__main__":
    unittest.main()
