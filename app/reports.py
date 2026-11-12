# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes activities to a file: HTML report, TSV, XML or iCal.

Port of hamster/reports.py, without the rest of Hamster: the activities
come as the dictionaries of the overview,

    {"id", "activity", "category", "description", "tags": [..],
     "start": "YYYY-MM-DD HH:MM", "end": the same, or None while ongoing}

TSV, XML and the HTML report have the columns of the original. The iCal
file differs: the original wrote times that calendars do not accept.
"""
import csv
import datetime as dt
import html
import itertools
import json
import os
import re
from calendar import timegm
from string import Template
from xml.dom.minidom import Document

FORMATS = ("html", "tsv", "xml", "ical")
EXTENSIONS = {"html": "html", "tsv": "tsv", "xml": "xml", "ical": "ics"}
# what a file name says about its format
_BY_EXTENSION = {"html": "html", "htm": "html", "tsv": "tsv", "xml": "xml", "ics": "ical"}
UNSORTED = "Unsorted"
TEMPLATE_NAME = "report_template.html"
# date of each row in the HTML report
HTML_DATE = "%b %d, %Y"


class Fact:
    def __init__(self, data, day_start, now):
        self.id = data.get("id") or 0
        self.activity = (data.get("activity") or "").strip()
        self.category = data.get("category") or ""
        self.description = data.get("description") or ""
        self.tags = [tag.strip() for tag in data.get("tags") or []]
        self.start = _moment(data["start"])
        self.end = _moment(data["end"]) if data.get("end") else None
        # the hamster day: before the day start, it is still the day before
        early = self.start.hour * 60 + self.start.minute < day_start
        self.date = self.start.date() - dt.timedelta(days=1 if early else 0)
        self.delta = max((self.end or now) - self.start, dt.timedelta())

    @property
    def minutes(self):
        return self.delta.total_seconds() / 60

    def as_dict(self):
        """The fact as the script of the HTML report wants it."""
        return {
            "id": self.id or "",
            "activity": self.activity,
            "category": self.category or UNSORTED,
            "description": self.description,
            "tags": self.tags,
            "date": timegm(self.date.timetuple()),
            "start_time": timegm(self.start.timetuple()),
            "end_time": timegm(self.end.timetuple()) if self.end else "",
            "delta": self.delta.total_seconds(),
        }


def _moment(text):
    return dt.datetime.strptime(text[:16], "%Y-%m-%d %H:%M")


def _stamp(moment):
    return moment.strftime("%Y-%m-%d %H:%M") if moment else ""


def resolve(path, chosen_format):
    """Return (format, path) for what was picked in the file dialog.

    An extension that names a format decides; otherwise the format is the
    chosen one (HTML if none) and its extension is added.
    """
    if chosen_format not in FORMATS:
        chosen_format = "html"
    extension = os.path.splitext(path)[1][1:].lower()
    if extension in _BY_EXTENSION:
        return _BY_EXTENSION[extension], path
    if extension == "txt" and chosen_format == "tsv":
        return "tsv", path
    return chosen_format, "{}.{}".format(path.rstrip("."), EXTENSIONS[chosen_format])


def suggested_name(first, last):
    """File name for a report on these days (without extension)."""
    days = first.isoformat() if first == last else "{} - {}".format(first.isoformat(), last.isoformat())
    return "Time track, " + days


def write(report_format, path, facts, first, last, day_start=330, now=None, template_dirs=()):
    """Write the facts to path.

    facts: dictionaries as described above, in the order to write them.
    first, last: the days (datetime.date) the report is about.
    template_dirs: where to look for report_template.html, in this order.
    Returns the number of activities written. Raises OSError or ValueError.
    """
    if report_format not in FORMATS:
        raise ValueError("unknown format: {}".format(report_format))
    now = (now or dt.datetime.now()).replace(second=0, microsecond=0)
    facts = [Fact(data, day_start, now) for data in facts]
    writer = {"html": _html, "tsv": _tsv, "xml": _xml, "ical": _ical}[report_format]
    if report_format == "html":
        text, written = _html(facts, first, last, template_dirs)
    else:
        text, written = writer(facts)
    # the whole text first: a failure leaves no half-written file
    with open(path, "w", encoding="utf-8", newline="") as report:
        report.write(text)
    return written


# --- TSV ---

def _tsv(facts):
    import io
    out = io.StringIO()
    rows = csv.writer(out, dialect="excel-tab")
    rows.writerow(["activity", "start time", "end time", "duration minutes",
                   "category", "description", "tags"])
    for fact in facts:
        rows.writerow([fact.activity, _stamp(fact.start), _stamp(fact.end), str(fact.minutes),
                       fact.category or UNSORTED, fact.description, ", ".join(fact.tags)])
    return out.getvalue(), len(facts)


# --- XML ---

def _xml(facts):
    doc = Document()
    activities = doc.createElement("activities")
    for fact in facts:
        activity = doc.createElement("activity")
        activity.setAttribute("name", fact.activity)
        activity.setAttribute("start_time", _stamp(fact.start))
        activity.setAttribute("end_time", _stamp(fact.end))
        activity.setAttribute("duration_minutes", str(fact.minutes))
        activity.setAttribute("category", fact.category or UNSORTED)
        activity.setAttribute("description", fact.description)
        activity.setAttribute("tags", ", ".join(fact.tags))
        activities.appendChild(activity)
    doc.appendChild(activities)
    # Before Python 3.13, minidom writes line breaks and tabs in attributes
    # as they are, and a parser reads them back as spaces. The document has
    # only attributes, so every such character in it is in a value.
    xml = doc.toxml().replace("\t", "&#9;").replace("\n", "&#10;").replace("\r", "&#13;")
    return xml, len(facts)


# --- iCal ---

def _ical_text(text):
    return (text.replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,")
            .replace("\r\n", "\n").replace("\n", "\\n"))


def _ical_line(name, value):
    """One content line, folded at 75 bytes as the format asks."""
    line = "{}:{}".format(name, value)
    pieces = []
    limit = 75
    while len(line.encode("utf-8")) > limit:
        cut = limit
        while len(line[:cut].encode("utf-8")) > limit:
            cut -= 1
        pieces.append(line[:cut])
        line = line[cut:]
        limit = 74   # continuation lines start with a space
    pieces.append(line)
    return "\r\n ".join(pieces) + "\r\n"


def _ical(facts):
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    local = "%Y%m%dT%H%M%S"   # no time zone: the time of the wall clock
    out = ["BEGIN:VCALENDAR\r\n", "VERSION:2.0\r\n", "PRODID:-//HamsterProjekt//hamster-kde//EN\r\n"]
    written = 0
    for fact in facts:
        if not fact.end:   # an ongoing activity is not an event yet
            continue
        written += 1
        out.append("BEGIN:VEVENT\r\n")
        out.append(_ical_line("UID", "hamster-{}-{}@hamster-kde".format(
            fact.id or written, fact.start.strftime(local))))
        out.append(_ical_line("DTSTAMP", stamp))
        out.append(_ical_line("DTSTART", fact.start.strftime(local)))
        out.append(_ical_line("DTEND", fact.end.strftime(local)))
        out.append(_ical_line("SUMMARY", _ical_text(fact.activity)))
        if fact.category:
            out.append(_ical_line("CATEGORIES", _ical_text(fact.category)))
        description = fact.description
        if fact.tags:
            tags = " ".join("#" + tag for tag in fact.tags)
            description = description + "\n" + tags if description else tags
        if description:
            out.append(_ical_line("DESCRIPTION", _ical_text(description)))
        out.append("END:VEVENT\r\n")
    out.append("END:VCALENDAR\r\n")
    return "".join(out), written


# --- HTML ---

def _title(first, last):
    start = {"B": first.strftime("%B"), "d": first.strftime("%d"), "Y": first.strftime("%Y")}
    end = {"B": last.strftime("%B"), "d": last.strftime("%d"), "Y": last.strftime("%Y")}
    if first.year != last.year:
        days = "{} {}, {} – {} {}, {}".format(start["B"], start["d"], start["Y"], end["B"], end["d"], end["Y"])
    elif first.month != last.month:
        days = "{} {} – {} {}, {}".format(start["B"], start["d"], end["B"], end["d"], end["Y"])
    elif first == last:
        days = "{} {}, {}".format(start["B"], start["d"], start["Y"])
    else:
        days = "{} {} – {}, {}".format(start["B"], start["d"], end["d"], end["Y"])
    return "Activity report for " + days


def _duration(minutes):
    minutes = int(round(minutes))
    hours, minutes = divmod(minutes, 60)
    if hours and minutes:
        return "{}h {}min".format(hours, minutes)
    return "{}h".format(hours) if hours else "{}min".format(minutes)


def _script_json(value):
    """JSON that can stand inside a <script> element."""
    return json.dumps(value).replace("</", "<\\/")


def _html(facts, first, last, template_dirs):
    template_path = None
    for directory in template_dirs:
        candidate = os.path.join(directory, TEMPLATE_NAME)
        if os.path.exists(candidate):
            template_path = candidate
            break
    if template_path is None:
        raise FileNotFoundError(2, "the report template is missing", TEMPLATE_NAME)
    with open(template_path, encoding="utf-8") as template_file:
        main = template_file.read()

    def extract(name):
        nonlocal main
        match = re.search("<{0}>(.*)</{0}>".format(name), main, re.DOTALL)
        if not match:
            return ""
        main = main.replace(match.group(), "${}_rows".format(name))
        return match.group(1)

    row_template = Template(extract("all_activities"))
    extract("by_date_activity")
    extract("by_date")

    rows = []
    for fact in facts:
        rows.append(row_template.safe_substitute(
            date=fact.date.strftime(HTML_DATE),
            date_iso=fact.date.isoformat(),
            activity=html.escape(fact.activity),
            category=html.escape(fact.category),   # "Unsorted" is not shown in the list
            tags=html.escape(", ".join(fact.tags)),
            start=fact.start.strftime("%H:%M"),
            start_iso=fact.start.isoformat(),
            end=fact.end.strftime("%H:%M") if fact.end else "",
            end_iso=fact.end.isoformat() if fact.end else "",
            duration=_duration(fact.minutes),
            duration_minutes="%d" % fact.minutes,
            duration_decimal="%.2f" % (fact.minutes / 60.0),
            description=html.escape(fact.description).replace("\n", "<br />"),
        ))

    # every day of the report, also those without activities; the script
    # of the report puts the names into the page as text, so no escaping
    by_date = {}
    for date, date_facts in itertools.groupby(facts, lambda fact: fact.date):
        by_date.setdefault(date, []).extend(date_facts)
    date_facts = []
    date = min([first] + list(by_date))
    while date <= max([last] + list(by_date)):
        day_facts = [fact.as_dict() for fact in by_date.get(date, [])]
        date_facts.append([date.strftime(HTML_DATE), day_facts])
        date += dt.timedelta(days=1)

    override = os.path.join(template_dirs[0], TEMPLATE_NAME) if template_dirs else ""
    text = Template(main).safe_substitute(
        title=html.escape(_title(first, last)),
        totals_by_day_title="Totals by Day",
        activity_log_title="Activity Log",
        totals_title="Totals",
        activity_totals_heading="activities",
        category_totals_heading="categories",
        tag_totals_heading="tags",
        show_prompt="Distinguish:",
        header_date="Date",
        header_activity="Activity",
        header_category="Category",
        header_tags="Tags",
        header_start="Start",
        header_end="End",
        header_duration="Duration",
        header_description="Description",
        data_dir=html.escape(os.path.dirname(template_path).lstrip("/")),
        show_template="Show template",
        template_instructions="You can override it by storing your version in "
                              + html.escape(os.path.dirname(override) if override else ""),
        start_date=timegm(first.timetuple()),
        end_date=timegm(last.timetuple()),
        facts=_script_json([fact.as_dict() for fact in facts]),
        date_facts=_script_json(date_facts),
        all_activities_rows="\n".join(rows),
    )
    return text, len(facts)
