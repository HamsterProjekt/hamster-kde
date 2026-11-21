# SPDX-License-Identifier: GPL-3.0-or-later
"""The Plasma widget: installing it from the tracking settings.

A Plasma widget cannot be a Flatpak, so the Flatpak carries a copy of the
widget (plasmoid/) and puts it where Plasma looks for the user's widgets,
~/.local/share/plasma/plasmoids. That is a plain copy of the folder; it is
what `kpackagetool6 --install` does too, which is not in the sandbox.

From the Flatpak it also adds the D-Bus service files that let the widget
start Hamster on demand: a Flatpak can only offer names that begin with its
own id. This is what scripts/install-flatpak-widget.sh does from a terminal.

No Qt here, so that it can be tested on its own; the tracking settings use
it through app/hamster-kde.
"""

import json
import os
import shutil
import tempfile

from assistants import host_data_home

WIDGET_ID = "io.github.HamsterProjekt.plasmoid"
FLATPAK_ID = "io.github.HamsterProjekt.HamsterKDE"
SERVICES = {
    "io.github.HamsterProjekt.Hamster": "--command=hamster-service {id}",
    "io.github.HamsterProjekt.Hamster.WindowServer": "{id} --service",
}
# the ids before the fork had its own names
LEGACY_WIDGET_ID = "org.projecthamster.plasmoid"
LEGACY_FLATPAK_ID = "org.projecthamster.HamsterKDE"
LEGACY_SERVICES = ("org.gnome.Hamster", "org.gnome.Hamster.WindowServer")
# where flatpak is on the host; the sandbox has none to look up
HOST_FLATPAK = "/usr/bin/flatpak"

# what status() says
UNAVAILABLE = "unavailable"   # no copy of the widget comes with this installation
MISSING = "missing"           # not installed
CURRENT = "current"           # installed, the same as the copy here
OUTDATED = "outdated"         # installed, older (or Hamster cannot be started for it)
NEWER = "newer"               # installed, newer than the copy here
SYSTEM = "system"             # installed for all users, by the distribution


class WidgetError(Exception):
    """The widget could not be installed or removed; the message says why."""


def _version(text):
    parts = []
    for part in str(text or "").split("."):
        digits = "".join(c for c in part if c.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def _files(folder):
    """{relative path: bytes} of a widget folder, without Python caches."""
    found = {}
    for directory, subdirectories, names in os.walk(folder):
        subdirectories[:] = sorted(d for d in subdirectories if d != "__pycache__")
        for name in names:
            path = os.path.join(directory, name)
            with open(path, "rb") as f:
                found[os.path.relpath(path, folder)] = f.read()
    return found


def bundled_widget(app_dir=None):
    """The widget that comes with this installation; None if there is none.

    In the Flatpak it is next to the program (/app/lib/hamster-kde/plasmoid);
    in a checkout, plasmoid/ next to app/.
    """
    app_dir = app_dir or os.path.dirname(os.path.realpath(__file__))
    for folder in (os.path.join(app_dir, "plasmoid"), os.path.join(app_dir, "..", "plasmoid")):
        if os.path.isfile(os.path.join(folder, "metadata.json")):
            return os.path.realpath(folder)
    return None


class Widget(object):
    def __init__(self, environ=None, source=None, app_dir=None):
        self.environ = os.environ if environ is None else environ
        self.source = source if source is not None else bundled_widget(app_dir)
        self.flatpak_id = self.environ.get("FLATPAK_ID")
        data_home = host_data_home(self.environ)
        self.plasmoids = os.path.join(data_home, "plasma", "plasmoids")
        self.path = os.path.join(self.plasmoids, WIDGET_ID)
        self.services = os.path.join(data_home, "dbus-1", "services")
        self.applications = os.path.join(data_home, "applications")

    # --- what is there ---

    @staticmethod
    def version_of(folder):
        try:
            with open(os.path.join(folder, "metadata.json"), encoding="utf-8") as f:
                return str(json.load(f).get("KPlugin", {}).get("Version", ""))
        except (OSError, ValueError, AttributeError):
            return ""

    def system_path(self):
        """The widget installed for all users, if it is (not seen from the Flatpak)."""
        if self.flatpak_id:
            return None
        dirs = self.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
        for directory in dirs.split(":"):
            path = os.path.join(directory, "plasma", "plasmoids", WIDGET_ID)
            if directory and os.path.isfile(os.path.join(path, "metadata.json")):
                return path
        return None

    def _service_text(self, name):
        arguments = SERVICES[name].format(id=self.flatpak_id)
        return "[D-BUS Service]\nName={}\nExec={} run {}\n".format(name, HOST_FLATPAK, arguments)

    def _service_path(self, name):
        return os.path.join(self.services, name + ".service")

    def services_in_place(self):
        """Whether D-Bus starts this Flatpak's Hamster for the widget (True outside a Flatpak)."""
        if not self.flatpak_id:
            return True
        for name in SERVICES:
            try:
                with open(self._service_path(name), encoding="utf-8") as f:
                    if f.read() != self._service_text(name):
                        return False
            except OSError:
                return False
        return True

    def status(self):
        if not self.source:
            return UNAVAILABLE
        if not os.path.isfile(os.path.join(self.path, "metadata.json")):
            return SYSTEM if self.system_path() else MISSING
        try:
            same = _files(self.path) == _files(self.source)
        except OSError:
            same = False
        if same:
            return CURRENT if self.services_in_place() else OUTDATED
        if _version(self.version_of(self.path)) > _version(self.version_of(self.source)):
            return NEWER
        return OUTDATED

    # --- changing it ---

    def install(self):
        """Install the widget, or replace the installed one.

        Returns whether the service files changed, so that the caller can
        stop the Hamster service that D-Bus started from the old ones.
        """
        if not self.source:
            raise WidgetError("This installation of Hamster has no copy of the widget.")
        try:
            os.makedirs(self.plasmoids, exist_ok=True)
            # copied next to it, then renamed: never half a widget
            temporary = tempfile.mkdtemp(dir=self.plasmoids, prefix=".hamster-")
            try:
                shutil.copytree(self.source, os.path.join(temporary, WIDGET_ID),
                                ignore=shutil.ignore_patterns("__pycache__"))
                old = os.path.join(temporary, "old")
                if os.path.lexists(self.path):
                    os.rename(self.path, old)
                try:
                    os.rename(os.path.join(temporary, WIDGET_ID), self.path)
                except OSError:
                    if os.path.lexists(old):
                        os.rename(old, self.path)
                    raise
            finally:
                shutil.rmtree(temporary, ignore_errors=True)
            self._remove_legacy()
            return self._write_services()
        except OSError as error:
            raise WidgetError("Could not install the widget in {}: {}".format(
                self.plasmoids, error.strerror or error))

    def remove(self):
        """Remove the widget (and, from the Flatpak, its service files)."""
        try:
            if os.path.islink(self.path):
                os.unlink(self.path)
            elif os.path.isdir(self.path):
                shutil.rmtree(self.path)
            self._remove_legacy()
            if self.flatpak_id:
                for name in SERVICES:
                    self._remove_service_of(self._service_path(name), self.flatpak_id)
        except OSError as error:
            raise WidgetError("Could not remove the widget from {}: {}".format(
                self.plasmoids, error.strerror or error))

    def _write_services(self):
        if not self.flatpak_id or self.services_in_place():
            return False
        os.makedirs(self.services, exist_ok=True)
        for name in SERVICES:
            fd, temporary = tempfile.mkstemp(dir=self.services, prefix=".hamster-")
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(self._service_text(name))
                os.chmod(temporary, 0o644)
                os.replace(temporary, self._service_path(name))
            except BaseException:
                os.unlink(temporary)
                raise
        return True

    @staticmethod
    def _remove_service_of(path, flatpak_id):
        """Remove a service file only if it starts this Flatpak."""
        try:
            with open(path, encoding="utf-8") as f:
                ours = flatpak_id in f.read()
        except OSError:
            return
        if ours:
            os.unlink(path)

    def _remove_legacy(self):
        legacy = os.path.join(self.plasmoids, LEGACY_WIDGET_ID)
        if os.path.isdir(legacy) and not os.path.islink(legacy):
            shutil.rmtree(legacy)
        for name in LEGACY_SERVICES:
            self._remove_service_of(self._service_path(name), LEGACY_FLATPAK_ID)
        desktop = os.path.join(self.applications, "org.projecthamster.hamster-kde.desktop")
        if os.path.isfile(desktop):
            os.unlink(desktop)
