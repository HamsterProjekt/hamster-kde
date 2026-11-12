#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Stand-in for the Hamster D-Bus services, for developing the plasmoid
without Hamster installed.

Implements only what the plasmoid calls. Facts live in memory. Run it on a
private bus so it never collides with a real Hamster:

    dbus-run-session -- sh -c 'python3 tests/mock_hamster_service.py & plasmawindowed io.github.HamsterProjekt.plasmoid'
"""

import datetime as dt
import json
import re
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

FMT = "%Y-%m-%d %H:%M"


def log(*args):
    print("mock:", *args, file=sys.stderr, flush=True)


class Hamster(dbus.service.Object):
    def __init__(self, bus):
        # (dbus.service.Object uses self._name itself, so not that name)
        self.bus_name = dbus.service.BusName("io.github.HamsterProjekt.Hamster", bus=bus)
        super().__init__(bus, "/io/github/HamsterProjekt/Hamster")
        now = dt.datetime.now().replace(second=0, microsecond=0)
        day = now.replace(hour=0, minute=0)
        self.next_id = 1
        self.facts = []
        self._add("email", "work", "", [], day.replace(hour=8), day.replace(hour=8, minute=40))
        self._add("coding", "work", "login bug", ["backend", "billable"],
                  day.replace(hour=8, minute=40), day.replace(hour=11, minute=10))
        self._add("lunch", "personal", "", [], day.replace(hour=11, minute=10), day.replace(hour=11, minute=50))
        self._add("meeting", "work", "", [], now - dt.timedelta(minutes=25), None)

    def _add(self, activity, category, description, tags, start, end):
        fact = dict(id=self.next_id, activity=activity, category=category,
                    description=description, tags=tags, start=start, end=end)
        self.next_id += 1
        self.facts.append(fact)
        return fact["id"]

    @dbus.service.signal("io.github.HamsterProjekt.Hamster")
    def FactsChanged(self):
        pass

    @dbus.service.signal("io.github.HamsterProjekt.Hamster")
    def ActivitiesChanged(self):
        pass

    @dbus.service.signal("io.github.HamsterProjekt.Hamster")
    def TagsChanged(self):
        pass

    @dbus.service.method("io.github.HamsterProjekt.Hamster", out_signature="as")
    def GetTodaysFactsJSON(self):
        return [json.dumps(dict(
            id=f["id"], activity=f["activity"], category=f["category"],
            description=f["description"], tags=f["tags"], activity_id=0,
            range=dict(start=f["start"].strftime(FMT),
                       end=f["end"].strftime(FMT) if f["end"] else None),
        )) for f in self.facts]

    @dbus.service.method("io.github.HamsterProjekt.Hamster", in_signature="s", out_signature="a(ss)")
    def GetActivities(self, search):
        seen = []
        for f in self.facts:
            pair = (f["activity"], f["category"])
            if pair not in seen and search.lower() in f["activity"].lower():
                seen.append(pair)
        return seen

    @dbus.service.method("io.github.HamsterProjekt.Hamster", in_signature="siib", out_signature="i")
    def AddFact(self, text, start_time, end_time, temporary):
        log("AddFact", repr(str(text)), int(start_time), int(end_time), bool(temporary))
        # Crude version of hamster's parser; times at the start are not handled.
        head, _, tags_part = str(text).partition(", #")
        tags = [t.strip() for t in re.split(r"\s*#", tags_part) if t.strip()] if tags_part else []
        head, _, description = head.partition(",")
        activity, _, category = head.strip().rpartition("@") if "@" in head else (head.strip(), "", "")
        if not activity:
            raise dbus.DBusException("Missing activity")
        now = dt.datetime.now().replace(second=0, microsecond=0)
        if self.facts and self.facts[-1]["end"] is None:
            self.facts[-1]["end"] = now
        new_id = self._add(activity, category, description.strip(", "), tags, now, None)
        self.FactsChanged()
        self.ActivitiesChanged()
        return new_id

    @dbus.service.method("io.github.HamsterProjekt.Hamster", in_signature="i")
    def StopTracking(self, end_time):
        log("StopTracking", int(end_time))
        if self.facts and self.facts[-1]["end"] is None:
            self.facts[-1]["end"] = dt.datetime.now().replace(second=0, microsecond=0)
            self.FactsChanged()


class WindowServer(dbus.service.Object):
    def __init__(self, bus):
        self.bus_name = dbus.service.BusName("io.github.HamsterProjekt.Hamster.WindowServer", bus=bus)
        super().__init__(bus, "/io/github/HamsterProjekt/Hamster/WindowServer")

    @dbus.service.method("io.github.HamsterProjekt.Hamster.WindowServer")
    def edit(self, id=0):
        log("edit", int(id))

    @dbus.service.method("io.github.HamsterProjekt.Hamster.WindowServer")
    def overview(self):
        log("overview")

    @dbus.service.method("io.github.HamsterProjekt.Hamster.WindowServer")
    def preferences(self):
        log("preferences")


if __name__ == "__main__":
    DBusGMainLoop(set_as_default=True)
    session = dbus.SessionBus()
    hamster = Hamster(session)
    windows = WindowServer(session)
    log("ready")
    GLib.MainLoop().run()
