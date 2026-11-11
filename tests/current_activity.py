#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prints the activity that the Hamster service says is being tracked, or -."""
import json

import dbus

hamster = dbus.Interface(dbus.SessionBus().get_object("org.gnome.Hamster", "/org/gnome/Hamster"),
                         "org.gnome.Hamster")
facts = [json.loads(fact) for fact in hamster.GetTodaysFactsJSON()]
ongoing = facts and not facts[-1]["range"]["end"]
print(facts[-1]["activity"] if ongoing else "-")
