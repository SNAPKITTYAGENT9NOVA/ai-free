# -*- coding: utf-8 -*-
"""
Unit tests for ARCInteractiveEnv and Closed-Loop integration with ARC3PolicyValueNet.
"""

import unittest

from src.arc3_policy_value_net import ARC3PolicyValueNet
from src.arc_interactive_env import ARCInteractiveEnv


class TestARCInteractiveEnv(unittest.TestCase):
    def setUp(self):
        self.env = ARCInteractiveEnv(max_steps=50, seed=42)

    def test_reset(self):
        obs, info = self.env.reset()
        self.assertEqual(obs.shape, (32,))
        self.assertIsInstance(info, dict)
        self.assertIn("step", info)
        self.assertEqual(info["step"], 0)

    def test_step_valid_transitions(self):
        self.env.reset()
        for action in range(11):
            obs, reward, terminated, truncated, info = self.env.step(action)
            self.assertEqual(obs.shape, (32,))
            self.assertIsInstance(reward, float)
            self.assertIsInstance(terminated, bool)
            self.assertIsInstance(truncated, bool)
            self.assertIn("action_name", info)

    def test_closed_loop_agent_rollout(self):
        """Test full closed-loop interaction between PolicyValueNet and InteractiveEnv."""
        net = ARC3PolicyValueNet(input_dim=32, hidden_dim=64, action_dim=11, seed=99)
        obs, info = self.env.reset()

        total_reward = 0.0
        steps = 0
        done = False

        while not done and steps < 30:
            action_idx, action_name, prob, val = net.predict_action(obs, deterministic=False)
            self.assertGreaterEqual(action_idx, 0)
            self.assertLess(action_idx, 11)

            obs, reward, terminated, truncated, info = self.env.step(action_idx)
            total_reward += reward
            steps += 1
            done = terminated or truncated

        self.assertGreater(steps, 0)
        print(f"Closed-loop episode finished after {steps} steps, total reward: {total_reward:.3f}")


if __name__ == "__main__":
    unittest.main()
