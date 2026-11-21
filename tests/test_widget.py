#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests of app/widget.py: installing the Plasma widget from the settings.
Run: python3 tests/test_widget.py (nothing else needed)."""
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest

here = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(here, "..", "app"))
import widget  # noqa: E402
from widget import (CURRENT, MISSING, NEWER, OUTDATED, SYSTEM, UNAVAILABLE,  # noqa: E402
                    WIDGET_ID, Widget)

FLATPAK = "io.github.HamsterProjekt.HamsterKDE"


class WidgetTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="hamster-widget-")
        self.addCleanup(shutil.rmtree, self.home)
        self.environ = {"HOME": self.home, "XDG_DATA_DIRS": self.path("system")}
        self.source = self.path("app", "plasmoid")
        self.make_widget(self.source, "1.2.0")

    def path(self, *parts):
        return os.path.join(self.home, *parts)

    def make_widget(self, folder, version, main="Item {}"):
        os.makedirs(os.path.join(folder, "contents", "ui"), exist_ok=True)
        with open(os.path.join(folder, "metadata.json"), "w") as f:
            json.dump({"KPlugin": {"Id": WIDGET_ID, "Version": version}}, f)
        with open(os.path.join(folder, "contents", "ui", "main.qml"), "w") as f:
            f.write(main)

    def installed(self, *parts):
        return self.path(".local", "share", "plasma", "plasmoids", WIDGET_ID, *parts)

    def service(self, name):
        return self.path(".local", "share", "dbus-1", "services", name + ".service")

    def widget(self):
        return Widget(self.environ, source=self.source)

    def test_install_update_remove(self):
        w = self.widget()
        self.assertEqual(w.status(), MISSING)
        self.assertFalse(w.install())   # no service files outside the Flatpak
        self.assertEqual(w.status(), CURRENT)
        with open(self.installed("contents", "ui", "main.qml")) as f:
            self.assertEqual(f.read(), "Item {}")
        self.assertFalse(os.path.exists(self.service("io.github.HamsterProjekt.Hamster")))
        # nothing left over from the swap
        self.assertEqual(os.listdir(os.path.dirname(self.installed())), [WIDGET_ID])

        self.make_widget(self.source, "1.2.0", main="Item { id: changed }")
        self.assertEqual(w.status(), OUTDATED)   # same version, other files
        w.install()
        self.assertEqual(w.status(), CURRENT)
        with open(self.installed("contents", "ui", "main.qml")) as f:
            self.assertEqual(f.read(), "Item { id: changed }")

        w.remove()
        self.assertEqual(w.status(), MISSING)
        self.assertFalse(os.path.exists(self.installed()))
        w.remove()   # twice is fine

    def test_caches_are_not_copied_or_compared(self):
        os.makedirs(os.path.join(self.source, "contents", "__pycache__"))
        open(os.path.join(self.source, "contents", "__pycache__", "x.pyc"), "w").close()
        w = self.widget()
        w.install()
        self.assertFalse(os.path.exists(self.installed("contents", "__pycache__")))
        self.assertEqual(w.status(), CURRENT)

    def test_newer_installed_widget(self):
        self.make_widget(self.installed(), "2.0.0")
        self.assertEqual(self.widget().status(), NEWER)
        self.make_widget(self.installed(), "1.10.0")
        self.assertEqual(self.widget().status(), NEWER)   # not compared as text
        self.make_widget(self.installed(), "1.1.9")
        self.assertEqual(self.widget().status(), OUTDATED)

    def test_installed_for_all_users(self):
        self.make_widget(self.path("system", "plasma", "plasmoids", WIDGET_ID), "1.0.0")
        self.assertEqual(self.widget().status(), SYSTEM)

    def test_no_copy_of_the_widget(self):
        w = Widget(self.environ, source=None, app_dir=self.path("nothing"))
        self.assertEqual(w.status(), UNAVAILABLE)
        with self.assertRaises(widget.WidgetError):
            w.install()

    def test_bundled_widget(self):
        self.assertEqual(widget.bundled_widget(self.path("app")), os.path.realpath(self.source))
        os.makedirs(self.path("checkout", "app"))
        self.make_widget(self.path("checkout", "plasmoid"), "1.0.0")
        self.assertEqual(widget.bundled_widget(self.path("checkout", "app")),
                         os.path.realpath(self.path("checkout", "plasmoid")))
        self.assertIsNone(widget.bundled_widget(self.path("nothing")))

    def test_flatpak_adds_the_service_files(self):
        self.environ.update(FLATPAK_ID=FLATPAK, XDG_DATA_HOME=self.path(".var", "app", FLATPAK, "data"))
        # what scripts/install-backend.sh left: a service from a checkout
        os.makedirs(os.path.dirname(self.service("x")))
        with open(self.service("io.github.HamsterProjekt.Hamster"), "w") as f:
            f.write("[D-BUS Service]\nName=io.github.HamsterProjekt.Hamster\nExec=/usr/bin/python3 /src/hamster-service.py\n")
        w = self.widget()
        self.assertEqual(w.path, self.installed())   # the host's folder, not the sandbox's
        self.assertTrue(w.install())
        self.assertEqual(w.status(), CURRENT)
        with open(self.service("io.github.HamsterProjekt.Hamster")) as f:
            self.assertEqual(f.read(), "[D-BUS Service]\nName=io.github.HamsterProjekt.Hamster\n"
                             "Exec=/usr/bin/flatpak run --command=hamster-service {}\n".format(FLATPAK))
        with open(self.service("io.github.HamsterProjekt.Hamster.WindowServer")) as f:
            self.assertIn("Exec=/usr/bin/flatpak run {} --service\n".format(FLATPAK), f.read())
        mode = stat.S_IMODE(os.stat(self.service("io.github.HamsterProjekt.Hamster")).st_mode)
        self.assertEqual(mode, 0o644)
        self.assertFalse(w.install())   # nothing changed this time

        # the widget is there, but D-Bus cannot start Hamster for it
        os.unlink(self.service("io.github.HamsterProjekt.Hamster.WindowServer"))
        self.assertEqual(w.status(), OUTDATED)
        self.assertTrue(w.install())
        self.assertEqual(w.status(), CURRENT)

        w.remove()
        self.assertFalse(os.path.exists(self.service("io.github.HamsterProjekt.Hamster")))
        self.assertFalse(os.path.exists(self.service("io.github.HamsterProjekt.Hamster.WindowServer")))

    def test_remove_keeps_service_files_of_other_installations(self):
        self.environ["FLATPAK_ID"] = FLATPAK
        os.makedirs(os.path.dirname(self.service("x")))
        other = "[D-BUS Service]\nName=io.github.HamsterProjekt.Hamster\nExec=/usr/bin/python3 /src/hamster-service.py\n"
        with open(self.service("io.github.HamsterProjekt.Hamster"), "w") as f:
            f.write(other)
        self.widget().remove()
        with open(self.service("io.github.HamsterProjekt.Hamster")) as f:
            self.assertEqual(f.read(), other)

    def test_old_names_are_removed(self):
        self.environ["FLATPAK_ID"] = FLATPAK
        legacy = self.path(".local", "share", "plasma", "plasmoids", "org.projecthamster.plasmoid")
        self.make_widget(legacy, "0.1.0")
        os.makedirs(os.path.dirname(self.service("x")))
        with open(self.service("org.gnome.Hamster"), "w") as f:
            f.write("Exec=/usr/bin/flatpak run --command=hamster-service org.projecthamster.HamsterKDE\n")
        with open(self.service("org.gnome.Hamster.WindowServer"), "w") as f:
            f.write("Exec=/usr/bin/hamster-windows-service\n")   # of another Hamster: kept
        self.widget().install()
        self.assertFalse(os.path.exists(legacy))
        self.assertFalse(os.path.exists(self.service("org.gnome.Hamster")))
        self.assertTrue(os.path.exists(self.service("org.gnome.Hamster.WindowServer")))

    def test_the_real_widget(self):
        source = widget.bundled_widget(os.path.join(here, "..", "app"))
        self.assertTrue(source and os.path.isfile(os.path.join(source, "contents", "ui", "main.qml")))
        self.assertTrue(Widget.version_of(source))


if __name__ == "__main__":
    unittest.main()
