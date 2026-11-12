# SPDX-License-Identifier: GPL-3.0-or-later
"""The Hamster service (io.github.HamsterProjekt.Hamster) for the QML windows.

Available to QML as `bus`; qml/Backend.qml is what the windows use.
Calls do not block: the answer comes with the finished or failed signal.

This goes through GLib's D-Bus, not Qt's: its values turn into plain
Python ones without further ado, and Qt runs GLib's main loop anyway.
"""
import json
import os
import shutil
import subprocess
import time

from gi.repository import Gio, GLib
from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

NAME = "io.github.HamsterProjekt.Hamster"
PATH = "/io/github/HamsterProjekt/Hamster"
# program that runs the service where D-Bus cannot start it (see flatpak/)
SERVICE_PROGRAM = "hamster-service"
_TYPES = {"s": str, "i": int, "u": int, "b": bool}


def in_flatpak():
    return bool(os.environ.get("FLATPAK_ID"))


def ensure_service(connection, own=None):
    """Start the Hamster service if nothing else will.

    Normally D-Bus starts it on the first call. Where that is not set up,
    and the service comes with this program, it is started here; it then
    lives as long as this program. Return the process, or None.

    own: start the service that comes with this program even if D-Bus could
         start one. The default in the Flatpak: D-Bus can never start its
         service there (a Flatpak only offers names beginning with its id),
         so a name D-Bus can start belongs to another installation, such as
         the Hamster Flatpak with the GTK windows and its SQLite database.
    """
    if own is None:
        own = in_flatpak()
    def ask(method, signature=None, *arguments):
        parameters = GLib.Variant(signature, arguments) if signature else None
        return connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                    "org.freedesktop.DBus", method, parameters, None,
                                    Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]
    try:
        if ask("NameHasOwner", "(s)", NAME):
            return None
        if not own and NAME in ask("ListActivatableNames"):
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


def storage_problem(storage, expected_directory, own):
    """What is wrong with the storage of the service that answers; "" if nothing.

    storage: (kind, location) from the service's GetStorage, or None if it
             cannot tell (a service from before GetStorage).
    expected_directory: the folder of the Markdown files in the settings.
    own: whether the service has to be the one of this program (the Flatpak).
    """
    if storage is None:
        if not own:
            return ""
        return ("Another Hamster service is answering, not the one of this application, "
                "so the activities shown are not those in {}. "
                "It is most likely the Hamster Flatpak with the GTK windows.").format(expected_directory)
    kind, location = storage
    if kind != "markdown":
        if not own:
            # installed with --sqlite, or the system-wide Hamster: chosen
            return ""
        return ("Another Hamster service is answering: it keeps the activities in the "
                "database {}, not in the folder {}. "
                "It is most likely the Hamster Flatpak with the GTK windows.").format(location, expected_directory)
    if not expected_directory or os.path.realpath(location) == os.path.realpath(expected_directory):
        return ""
    message = ("The Hamster service uses the files in {}, not those in {}, "
               "the folder chosen in the settings.").format(location, expected_directory)
    if not own:
        message += " Stop it (pkill -f hamster-service) to have it start again with that folder."
    return message


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
    storageProblemChanged = pyqtSignal()

    def __init__(self, parent=None, expected_directory=None):
        """expected_directory: function returning the folder of the Markdown
        files in the settings; the service that answers is checked against it.
        """
        super().__init__(parent)
        self._calls = 0
        self._registered = False
        self._storage_problem = ""
        self._expected_directory = expected_directory or (lambda: "")
        # the Flatpak runs its own service, never one D-Bus starts
        self._own = in_flatpak() and shutil.which(SERVICE_PROGRAM) is not None
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
            lambda *arguments: self._appeared(),
            lambda *arguments: self._vanished())

    def _appeared(self):
        self._check_storage()
        self._set_registered(True)

    def _vanished(self):
        self._set_storage_problem("")
        self._set_registered(False)
        if self._own:
            # stopped, for instance to change the folder: back with ours
            self._start_own()

    def _start_own(self):
        """Start the service of this program, if no service is running."""
        try:
            if self._connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                          "org.freedesktop.DBus", "NameHasOwner", GLib.Variant("(s)", (NAME,)),
                                          None, Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]:
                return
        except GLib.Error:
            return
        # the previous one may still be on its way out
        if self._service is not None and self._service.poll() is None:
            try:
                self._service.wait(5)
            except subprocess.TimeoutExpired:
                return
        self._service = ensure_service(self._connection, own=True) or self._service

    def _set_registered(self, registered):
        if registered != self._registered:
            self._registered = registered
            self.registeredChanged.emit()

    # --- which service answers ---

    def _check_storage(self):
        def answered(connection, result, data):
            try:
                storage = tuple(connection.call_finish(result).unpack()[0])
            except GLib.Error as error:
                if not error.matches(Gio.DBusError.quark(), Gio.DBusError.UNKNOWN_METHOD):
                    return   # gone already; checked again when it is back
                storage = None
            self._set_storage_problem(storage_problem(storage, self._expected_directory(), self._own))
        self._connection.call(NAME, PATH, NAME, "GetStorage", None, GLib.VariantType("((ss))"),
                              Gio.DBusCallFlags.NO_AUTO_START, 5000, None, answered, None)

    def _set_storage_problem(self, problem):
        if problem != self._storage_problem:
            self._storage_problem = problem
            self.storageProblemChanged.emit()

    @pyqtProperty(str, notify=storageProblemChanged)
    def storageProblem(self):
        """Why the service that answers is not the expected one; "" if it is."""
        return self._storage_problem

    @pyqtProperty(bool, constant=True)
    def canUseOwnService(self):
        """Whether useOwnService() can put this program's service in place."""
        return self._own

    @pyqtSlot()
    def useOwnService(self):
        """Stop the service that answers; this program's starts in its place."""
        self._connection.call(NAME, PATH, NAME, "Quit", None, None,
                              Gio.DBusCallFlags.NO_AUTO_START, 5000, None, None, None)

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
        self._send(call_id, member, parameters, retry=self._own)
        return call_id

    def _send(self, call_id, member, parameters, retry):
        # In the Flatpak, D-Bus never starts the service: it would start
        # another installation's. A call that finds none starts ours, once.
        flags = Gio.DBusCallFlags.NO_AUTO_START if self._own else Gio.DBusCallFlags.NONE
        self._connection.call(NAME, PATH, NAME, member, parameters, None, flags, -1, None,
                              self._answered, (call_id, member, parameters, retry))

    def _answered(self, connection, result, data):
        call_id, member, parameters, retry = data
        try:
            values = connection.call_finish(result).unpack()
        except GLib.Error as error:
            if retry and (error.matches(Gio.DBusError.quark(), Gio.DBusError.SERVICE_UNKNOWN)
                          or error.matches(Gio.DBusError.quark(), Gio.DBusError.NAME_HAS_NO_OWNER)):
                self._start_own()
                self._send(call_id, member, parameters, retry=False)
                return
            Gio.DBusError.strip_remote_error(error)
            self.failed.emit(call_id, error.message or "")
            return
        self.finished.emit(call_id, json.dumps(values))
