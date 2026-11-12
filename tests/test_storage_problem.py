#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests of storage_problem() in app/hamsterbus.py: when the windows warn that
the Hamster service answering is not the expected one.
Run: python3 tests/test_storage_problem.py (needs PyQt6 and PyGObject)."""
import os
import sys
import tempfile
import unittest

here = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(here, "..", "app"))
try:
    from hamsterbus import storage_problem
except ImportError as error:  # PyQt6 or PyGObject missing
    storage_problem = None
    missing = str(error)


@unittest.skipIf(storage_problem is None, "hamsterbus cannot be imported")
class StorageProblemTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp()

    def test_the_expected_folder(self):
        self.assertEqual(storage_problem(("markdown", self.folder), self.folder, own=True), "")
        self.assertEqual(storage_problem(("markdown", self.folder), self.folder, own=False), "")

    def test_the_same_folder_through_a_link(self):
        link = self.folder + "-link"
        os.symlink(self.folder, link)
        self.addCleanup(os.remove, link)
        self.assertEqual(storage_problem(("markdown", self.folder), link, own=True), "")

    def test_another_folder(self):
        problem = storage_problem(("markdown", "/elsewhere"), self.folder, own=True)
        self.assertIn("/elsewhere", problem)
        self.assertIn(self.folder, problem)
        self.assertNotIn("pkill", problem)   # the windows offer a button instead
        self.assertIn("pkill", storage_problem(("markdown", "/elsewhere"), self.folder, own=False))

    def test_sqlite_in_the_flatpak(self):
        problem = storage_problem(("sqlite", "/data/hamster.db"), self.folder, own=True)
        self.assertIn("/data/hamster.db", problem)
        self.assertIn("GTK", problem)

    def test_sqlite_chosen_outside_the_flatpak(self):
        self.assertEqual(storage_problem(("sqlite", "/data/hamster.db"), self.folder, own=False), "")

    def test_a_service_that_cannot_tell(self):
        self.assertIn("Another Hamster service", storage_problem(None, self.folder, own=True))
        self.assertEqual(storage_problem(None, self.folder, own=False), "")


if __name__ == "__main__":
    unittest.main()
