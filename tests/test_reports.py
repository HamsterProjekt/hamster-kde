#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests of app/reports.py. Run: python3 tests/test_reports.py"""
import csv
import datetime as dt
import json
import os
import re
import sys
import tempfile
import unittest
from xml.dom.minidom import parse

here = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(here, "..", "app"))
import reports  # noqa: E402

APP = os.path.join(here, "..", "app")
NOW = dt.datetime(2026, 11, 11, 15, 30)
FIRST, LAST = dt.date(2026, 11, 10), dt.date(2026, 11, 12)
FACTS = [
    {"id": 1, "activity": "World domination", "category": "Work", "description": "",
     "tags": ["global", "plan"], "start": "2026-11-10 09:00", "end": "2026-11-10 12:00"},
    {"id": 2, "activity": "Night shift", "category": "Work", "description": "past midnight",
     "tags": [], "start": "2026-11-11 01:00", "end": "2026-11-11 02:30"},
    {"id": 3, "activity": "Tea & <cake>", "category": "", "description": "two\nlines; with, signs",
     "tags": ["a\tb"], "start": "2026-11-11 10:00", "end": "2026-11-11 10:45"},
    {"id": 4, "activity": "gardening", "category": "Day-to-day", "description": "</script><b>",
     "tags": [], "start": "2026-11-11 15:00", "end": None},
]


class ReportsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def write(self, report_format, **more):
        path = os.path.join(self.dir.name, "report." + reports.EXTENSIONS[report_format])
        count = reports.write(report_format, path, FACTS, FIRST, LAST, now=NOW,
                              template_dirs=more.pop("template_dirs", (APP,)), **more)
        with open(path, encoding="utf-8", newline="") as report:
            return path, count, report.read()

    def test_tsv(self):
        path, count, text = self.write("tsv")
        self.assertEqual(count, 4)
        rows = list(csv.reader(text.splitlines(True), dialect="excel-tab"))
        self.assertEqual(rows[0], ["activity", "start time", "end time", "duration minutes",
                                   "category", "description", "tags"])
        self.assertEqual(rows[1], ["World domination", "2026-11-10 09:00", "2026-11-10 12:00",
                                   "180.0", "Work", "", "global, plan"])
        # tabs and line breaks in the text survive, quoted
        self.assertEqual(rows[3][0], "Tea & <cake>")
        self.assertEqual(rows[3][4], "Unsorted")
        self.assertEqual(rows[3][5], "two\nlines; with, signs")
        self.assertEqual(rows[3][6], "a\tb")
        # ongoing: no end, counted until now
        self.assertEqual(rows[4][2:4], ["", "30.0"])
        self.assertEqual(len(rows), 5)

    def test_xml(self):
        path, count, text = self.write("xml")
        activities = parse(path).getElementsByTagName("activity")
        self.assertEqual(len(activities), 4)
        third = activities[2]
        self.assertEqual(third.getAttribute("name"), "Tea & <cake>")
        self.assertEqual(third.getAttribute("category"), "Unsorted")
        self.assertEqual(third.getAttribute("duration_minutes"), "45.0")
        self.assertEqual(third.getAttribute("description"), "two\nlines; with, signs")
        self.assertEqual(activities[3].getAttribute("end_time"), "")

    def test_ical(self):
        path, count, text = self.write("ical")
        self.assertEqual(count, 3)   # not the ongoing one
        self.assertTrue(text.startswith("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"))
        self.assertTrue(text.endswith("END:VCALENDAR\r\n"))
        self.assertEqual(text.count("BEGIN:VEVENT"), 3)
        self.assertEqual(text.count("\r\n"), text.count("\n"))
        self.assertIn("DTSTART:20261110T090000\r\nDTEND:20261110T120000\r\n", text)
        self.assertIn("SUMMARY:Tea & <cake>\r\n", text)
        self.assertIn("DESCRIPTION:two\\nlines\\; with\\, signs\\n#a\tb\r\n", text)
        self.assertNotIn("CATEGORIES:\r\n", text)
        self.assertNotIn("gardening", text)
        uids = re.findall(r"^UID:(.*)\r$", text, re.M)
        self.assertEqual(len(set(uids)), 3)
        for line in text.split("\r\n"):
            self.assertLessEqual(len(line.encode("utf-8")), 75)

    def test_ical_folds_long_lines(self):
        long_fact = dict(FACTS[0], description="é" * 200)
        path = os.path.join(self.dir.name, "long.ics")
        reports.write("ical", path, [long_fact], FIRST, LAST, now=NOW)
        with open(path, encoding="utf-8", newline="") as report:
            text = report.read()
        for line in text.split("\r\n"):
            self.assertLessEqual(len(line.encode("utf-8")), 75)
        self.assertIn("é" * 200, text.replace("\r\n ", ""))

    def test_html(self):
        path, count, text = self.write("html")
        self.assertEqual(count, 4)
        self.assertIn("<title>Activity report for November 10 – 12, 2026</title>", text)
        self.assertIn("Tea &amp; &lt;cake&gt;", text)
        self.assertIn("two<br />lines; with, signs", text)
        self.assertNotIn("<all_activities>", text)
        # nothing of the template is left to fill in
        self.assertEqual(re.findall(r"\$[a-z_]+", re.sub(r'\$\(|\$"', "", text)), [])
        # the data of the script: valid, and it cannot end the script early
        facts = json.loads(re.search(r"var facts = (.*);", text).group(1))
        self.assertEqual([fact["delta"] for fact in facts], [10800, 5400, 2700, 1800])
        self.assertEqual(text.count("</script>"), 3)
        date_facts = json.loads(re.search(r"var dateFacts = (.*);", text).group(1))
        # a day start of 5:30: the night shift belongs to the 10th; the 12th is there, empty
        self.assertEqual([(day, len(day_facts)) for day, day_facts in date_facts],
                         [("Nov 10, 2026", 2), ("Nov 11, 2026", 2), ("Nov 12, 2026", 0)])
        self.assertEqual(date_facts[1][1][0]["activity"], "Tea &amp; &lt;cake&gt;")

    def test_html_template_override(self):
        override = os.path.join(self.dir.name, "mine")
        os.mkdir(override)
        with open(os.path.join(override, reports.TEMPLATE_NAME), "w") as template:
            template.write("<h1>$title</h1><all_activities>[$activity $duration]</all_activities>")
        path, count, text = self.write("html", template_dirs=(override, APP))
        self.assertEqual(text, "<h1>Activity report for November 10 – 12, 2026</h1>"
                               "[World domination 3h]\n[Night shift 1h 30min]\n"
                               "[Tea &amp; &lt;cake&gt; 45min]\n[gardening 30min]")

    def test_titles(self):
        day = dt.date
        self.assertEqual(reports._title(day(2026, 11, 11), day(2026, 11, 11)),
                         "Activity report for November 11, 2026")
        self.assertEqual(reports._title(day(2026, 10, 30), day(2026, 11, 2)),
                         "Activity report for October 30 – November 02, 2026")
        self.assertEqual(reports._title(day(2025, 12, 30), day(2026, 1, 2)),
                         "Activity report for December 30, 2025 – January 02, 2026")

    def test_resolve(self):
        self.assertEqual(reports.resolve("/x/report", "tsv"), ("tsv", "/x/report.tsv"))
        self.assertEqual(reports.resolve("/x/report.", "ical"), ("ical", "/x/report.ics"))
        self.assertEqual(reports.resolve("/x/report.ics", "html"), ("ical", "/x/report.ics"))
        self.assertEqual(reports.resolve("/x/report.HTM", "xml"), ("html", "/x/report.HTM"))
        self.assertEqual(reports.resolve("/x/report.txt", "tsv"), ("tsv", "/x/report.txt"))
        self.assertEqual(reports.resolve("/x/report.txt", "xml"), ("xml", "/x/report.txt.xml"))
        self.assertEqual(reports.resolve("/x/Time track, 2026-11-11", ""),
                         ("html", "/x/Time track, 2026-11-11.html"))

    def test_failure_leaves_no_file(self):
        path = os.path.join(self.dir.name, "broken.html")
        with self.assertRaises(OSError):
            reports.write("html", path, FACTS, FIRST, LAST, now=NOW, template_dirs=(self.dir.name,))
        self.assertFalse(os.path.exists(path))


if __name__ == "__main__":
    unittest.main()
