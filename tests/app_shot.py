#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Renders one window of the app to a PNG, for checking it without a screen.

    app_shot.py Overview|EditFact|AddFact|Preferences out.png [script [later-script]]

EditFact edits the first activity of today; AddFact is the same window for
a new one. The scripts are JavaScript run in the window before the picture
(the window is `w`), the second one a second after the first.
"""
import importlib.machinery
import importlib.util
import json
import os
import sys

here = os.path.dirname(os.path.realpath(__file__))
loader = importlib.machinery.SourceFileLoader("hamster_kde", os.path.join(here, "..", "app", "hamster-kde"))
spec = importlib.util.spec_from_loader("hamster_kde", loader)
launcher = importlib.util.module_from_spec(spec)
loader.exec_module(launcher)

from PyQt6.QtCore import QTimer
from PyQt6.QtDBus import QDBusConnection, QDBusInterface
from PyQt6.QtQml import QQmlApplicationEngine, QQmlExpression
from PyQt6.QtQuick import QQuickWindow  # noqa: F401 (so windows come back as QQuickWindow)
from PyQt6.QtWidgets import QApplication

name, out = sys.argv[1], sys.argv[2]
extra = sys.argv[3] if len(sys.argv) > 3 else ""

app = QApplication(sys.argv[:1])
engine = QQmlApplicationEngine()
settings, bus, windows = launcher.expose(engine)

properties = {}
if name == "AddFact":
    name = "EditFact"
elif name == "EditFact":
    hamster = QDBusInterface("io.github.HamsterProjekt.Hamster", "/io/github/HamsterProjekt/Hamster", "io.github.HamsterProjekt.Hamster",
                             QDBusConnection.sessionBus())
    facts = hamster.call("GetTodaysFactsJSON").arguments()[0]
    properties["factId"] = json.loads(facts[0])["id"]
window = windows._create(name, properties)
if window is None:
    sys.exit(1)


later = sys.argv[4] if len(sys.argv) > 4 else ""


def run_script(script=None):
    script = script or extra
    if script:
        engine.rootContext().setContextProperty("w", window)
        expression = QQmlExpression(engine.rootContext(), window, script)
        expression.evaluate()
        if expression.hasError():
            print(expression.error().toString(), file=sys.stderr)


def grab():
    ok = window.grabWindow().save(out)
    print("saved" if ok else "save failed", out)
    app.exit(0 if ok else 1)


QTimer.singleShot(1500, run_script)
if later:
    QTimer.singleShot(2500, lambda: run_script(later))
QTimer.singleShot(3500, grab)
sys.exit(app.exec())
