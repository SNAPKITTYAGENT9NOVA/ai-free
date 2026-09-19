# -*- coding: utf-8 -*-
import os
import tempfile
import unittest

from src.code_inspection_search import CodeInspectionEngine, inspect_code


class TestCodeInspectionEngine(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = self.temp_dir.name

        self.sample_py = os.path.join(self.root, "sample_module.py")
        with open(self.sample_py, "w", encoding="utf-8") as f:
            f.write("""# sample
class MockInspector:
    def inspect_now(self):
        return True

def standalone_helper():
    pass
""")

        self.engine = CodeInspectionEngine(root_dirs=[self.root])

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_inspect_existing_class(self):
        res = self.engine.inspect("MockInspector")
        self.assertTrue(res.found)
        self.assertTrue(res.has_definition)
        self.assertEqual(res.target_type, "symbol")
        self.assertGreaterEqual(res.definition_count, 1)

    def test_inspect_existing_file(self):
        res = self.engine.inspect("sample_module.py")
        self.assertTrue(res.found)
        self.assertEqual(res.target_type, "file")

    def test_inspect_nonexistent_symbol(self):
        res = self.engine.inspect("NonExistentPhantomClass")
        self.assertFalse(res.found)
        self.assertFalse(res.has_definition)

    def test_inspect_convenience_function(self):
        res_dict = inspect_code("standalone_helper", root_dirs=[self.root])
        self.assertTrue(res_dict["found"])
        self.assertTrue(res_dict["has_definition"])


if __name__ == "__main__":
    unittest.main()
