# -*- coding: utf-8 -*-
import unittest

from arc_grid_optimizer import ArcGridOptimizer


class TestArcGridOptimizer(unittest.TestCase):
    def setUp(self):
        self.opt = ArcGridOptimizer(background_color=0)

    def test_bounding_box_and_crop(self):
        grid = [[0, 0, 0, 0], [0, 5, 5, 0], [0, 5, 0, 0], [0, 0, 0, 0]]
        bbox = self.opt.find_bounding_box(grid)
        self.assertEqual(bbox, (1, 1, 2, 2))
        cropped = self.opt.crop_to_content(grid)
        self.assertEqual(cropped, [[5, 5], [5, 0]])

    def test_rotate_and_mirror(self):
        grid = [[1, 2], [3, 4]]
        rot = self.opt.rotate_90(grid)
        self.assertEqual(rot, [[3, 1], [4, 2]])
        mirror = self.opt.mirror_horizontal(grid)
        self.assertEqual(mirror, [[2, 1], [4, 3]])

    def test_color_counts(self):
        grid = [[1, 2, 0], [0, 1, 1]]
        counts = self.opt.count_colors(grid)
        self.assertEqual(counts[1], 3)
        self.assertEqual(counts[2], 1)
        self.assertEqual(counts[0], 2)


if __name__ == "__main__":
    unittest.main()
