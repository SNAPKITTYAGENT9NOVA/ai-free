# -*- coding: utf-8 -*-
"""
Unit tests for ARC3PolicyValueNet.
"""

import os
import tempfile
import unittest

import numpy as np

from src.arc3_policy_value_net import ARC3PolicyValueNet


class TestARC3PolicyValueNet(unittest.TestCase):
    def setUp(self):
        self.input_dim = 32
        self.hidden_dim = 64
        self.action_dim = 11
        self.net = ARC3PolicyValueNet(
            input_dim=self.input_dim,
            hidden_dim=self.hidden_dim,
            action_dim=self.action_dim,
            seed=123,
        )

    def test_forward_single_observation(self):
        obs = np.random.randn(self.input_dim).astype(np.float32)
        probs, val = self.net.forward(obs)

        self.assertEqual(probs.shape, (self.action_dim,))
        self.assertAlmostEqual(float(np.sum(probs)), 1.0, places=5)
        self.assertTrue(np.all(probs >= 0.0))

        val_scalar = float(val.item())
        self.assertGreaterEqual(val_scalar, -1.0)
        self.assertLessEqual(val_scalar, 1.0)

    def test_forward_batch_observation(self):
        batch_size = 8
        obs_batch = np.random.randn(batch_size, self.input_dim).astype(np.float32)
        probs_batch, val_batch = self.net.forward(obs_batch)

        self.assertEqual(probs_batch.shape, (batch_size, self.action_dim))
        self.assertEqual(val_batch.shape, (batch_size, 1))

        for p in probs_batch:
            self.assertAlmostEqual(float(np.sum(p)), 1.0, places=5)

    def test_predict_action(self):
        obs = np.random.randn(self.input_dim).astype(np.float32)
        act_idx, act_name, prob, val = self.net.predict_action(obs, deterministic=True)

        self.assertIsInstance(act_idx, int)
        self.assertGreaterEqual(act_idx, 0)
        self.assertLess(act_idx, self.action_dim)
        self.assertIsInstance(act_name, str)
        self.assertGreaterEqual(prob, 0.0)
        self.assertLessEqual(prob, 1.0)
        self.assertGreaterEqual(val, -1.0)
        self.assertLessEqual(val, 1.0)

    def test_save_and_load_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            model_path = os.path.join(tmpdir, "arc3_test_model.json")
            self.net.save_model(model_path)
            self.assertTrue(os.path.exists(model_path))

            new_net = ARC3PolicyValueNet(
                input_dim=self.input_dim,
                hidden_dim=self.hidden_dim,
                action_dim=self.action_dim,
            )
            new_net.load_model(model_path)

            obs = np.random.randn(self.input_dim).astype(np.float32)
            p1, v1 = self.net.forward(obs)
            p2, v2 = new_net.forward(obs)

            np.testing.assert_allclose(p1, p2, rtol=1e-5)
            np.testing.assert_allclose(v1, v2, rtol=1e-5)


if __name__ == "__main__":
    unittest.main()
