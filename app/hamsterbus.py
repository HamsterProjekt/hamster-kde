# SPDX-License-Identifier: GPL-3.0-or-later
"""The Hamster service (org.gnome.Hamster) for the QML windows.

Available to QML as `bus`; qml/Backend.qml is what the windows use.
Calls do not block: the answer comes with the finished or failed signal.

This goes through GLib's D-Bus, not Qt's: its values turn into plain
Python ones without further ado, and Qt runs GLib's main loop anyway.
"""
import json
import shutil
import subprocess
import time

from gi.repository import Gio, GLib
from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

NAME = "org.gnome.Hamster"
PATH = "/org/gnome/Hamster"
# program that runs the service where D-Bus cannot start it (see flatpak/)
SERVICE_PROGRAM = "hamster-service"
_TYPES = {"s": str, "i": int, "u": int, "b": bool}


def ensure_service(connection):
    """Start the Hamster service if nothing else will.

    Normally D-Bus starts it on the first call. Where that is not set up,
    and the service comes with this program, it is started here; it then
    lives as long as this program. Return the process, or None.
    """
    def ask(method, signature=None, *arguments):
        parameters = GLib.Variant(signature, arguments) if signature else None
        return connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                    "org.freedesktop.DBus", method, parameters, None,
                                    Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
    try:
        if ask("NameHasOwner", "(s)", NAME) or NAME in ask("ListActivatableNames"):
            return None
    except GLib.Error:
        return None
    program = shutil.which(SERVICE_PROGRAM)
    if not program:
        return None
    process = subprocess.Popen([program])
    # the windows ask for their data right away
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and process.poll() is None:
        try:
            if ask("NameHasOwner", "(s)", NAME):
                break
        except GLib.Error:
            break
        time.sleep(0.1)
    return process


class HamsterBus(QObject):
    # call id, JSON list of the values returned
    finished = pyqtSignal(int, str)
    # call id, message for the user
    failed = pyqtSignal(int, str)
    factsChanged = pyqtSignal()
    activitiesChanged = pyqtSignal()
    tagsChanged = pyqtSignal()
    # the service came or went
    registeredChanged = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._calls = 0
        self._registered = False
        self._connection = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self._service = ensure_service(self._connection)
        for member, signal in (("FactsChanged", self.factsChanged),
                               ("ActivitiesChanged", self.activitiesChanged),
                               ("TagsChanged", self.tagsChanged)):
            self._connection.signal_subscribe(
                NAME, NAME, member, PATH, None, Gio.DBusSignalFlags.NONE,
                lambda *arguments, signal=signal: signal.emit())
        Gio.bus_watch_name_on_connection(
            self._connection, NAME, Gio.BusNameWatcherFlags.NONE,
            lambda *arguments: self._set_registered(True),
            lambda *arguments: self._set_registered(False))

    def _set_registered(self, registered):
        if registered != self._registered:
            self._registered = registered
            self.registeredChanged.emit()

    @pyqtProperty(bool, notify=registeredChanged)
    def registered(self):
        return self._registered

    @pyqtSlot(str, str, "QVariantList", result=int)
    def call(self, member, signature, arguments):
        """Call a method of the service; return the id of the call.

        signature: D-Bus signature of the arguments, e.g. "(si)"; empty for none.
                   Strings, integers and booleans are what Hamster takes.
        """
        self._calls += 1
        call_id = self._calls
        try:
            types = [_TYPES[code] for code in signature.strip("()")]
            if len(types) != len(arguments):
                raise ValueError("{} takes {} argument(s)".format(member, len(types)))
            values = tuple(convert(value) for convert, value in zip(types, arguments))
            parameters = GLib.Variant(signature, values) if types else None
        except (KeyError, TypeError, ValueError) as error:
            # after this returns, like every other answer
            GLib.idle_add(lambda: self.failed.emit(call_id, str(error)) and False)
            return call_id
        self._connection.call(NAME, PATH, NAME, member, parameters, None,
                              Gio.DBusCallFlags.NONE, -1, None, self._answered, call_id)
        return call_id

    def _answered(self, connection, result, call_id):
        try:
            values = connection.call_finish(result).unpack()
        except GLib.Error as error:
            Gio.DBusError.strip_remote_error(error)
            self.failed.emit(call_id, error.message or "")
            return
        self.finished.emit(call_id, json.dumps(values))
