#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests of ensure_service() and HamsterBus in app/hamsterbus.py, with a
stand-in for the D-Bus connection: no bus and no Hamster service needed.
Run: python3 tests/test_hamsterbus.py (needs PyQt6 and PyGObject)."""
import json
import os
import subprocess
import sys
import unittest
from unittest import mock

here = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(here, "..", "app"))
try:
    import hamsterbus
    from gi.repository import Gio, GLib
except ImportError as error:  # PyQt6 or PyGObject missing
    hamsterbus = None
    missing = str(error)


def dbus_error(code, message="it went wrong"):
    return GLib.Error.new_literal(Gio.DBusError.quark(), message, code)


class FakeConnection:
    """Answers the bus daemon's NameHasOwner and ListActivatableNames at
    once; keeps the asynchronous calls for the test to answer."""

    def __init__(self, owner=False, activatable=(), error=None):
        # owner: bool, or a list of the answers to give in turn
        self.owners = owner if isinstance(owner, list) else None
        self.owner = owner
        self.activatable = list(activatable)
        self.error = error
        self.sync_calls = []
        self.calls = []
        self.subscribed = []

    def call_sync(self, bus, path, interface, method, parameters, reply_type, flags, timeout, cancellable):
        self.sync_calls.append(method)
        if self.error is not None:
            raise self.error
        if method == "NameHasOwner":
            owner = self.owners.pop(0) if self.owners else self.owner
            if isinstance(owner, GLib.Error):
                raise owner
            return GLib.Variant("(b)", (bool(owner),))
        if method == "ListActivatableNames":
            return GLib.Variant("(as)", (self.activatable,))
        raise AssertionError(method)

    def call(self, name, path, interface, member, parameters, reply_type, flags, timeout,
             cancellable, callback, data):
        self.calls.append(dict(member=member, parameters=parameters, flags=flags,
                               callback=callback, data=data))

    def call_finish(self, result):
        if isinstance(result, GLib.Error):
            raise result
        return result

    def answer(self, index, result):
        """Answer the asynchronous call number index with a Variant or a GLib.Error."""
        call = self.calls[index]
        call["callback"](self, result, call["data"])

    def signal_subscribe(self, sender, interface, member, path, arg0, flags, callback):
        self.subscribed.append((member, callback))


class FakeProcess:
    def __init__(self, running=True, exits=True):
        self.running = running
        self.exits = exits

    def poll(self):
        return None if self.running else 0

    def wait(self, timeout=None):
        if not self.exits:
            raise subprocess.TimeoutExpired("hamster-service", timeout)
        self.running = False
        return 0


@unittest.skipIf(hamsterbus is None, "hamsterbus cannot be imported")
class EnsureServiceTest(unittest.TestCase):
    def setUp(self):
        self.popen = self.patch("subprocess.Popen", return_value=FakeProcess())
        self.which = self.patch("shutil.which", return_value="/app/bin/hamster-service")
        self.patch("time.sleep")

    def patch(self, target, **kwargs):
        patcher = mock.patch(target, **kwargs)
        started = patcher.start()
        self.addCleanup(patcher.stop)
        return started

    def test_in_flatpak(self):
        with mock.patch.dict(os.environ, {"FLATPAK_ID": "io.github.HamsterProjekt.HamsterKDE"}):
            self.assertTrue(hamsterbus.in_flatpak())
        with mock.patch.dict(os.environ, {"FLATPAK_ID": ""}):
            self.assertFalse(hamsterbus.in_flatpak())

    def test_already_running(self):
        self.assertIsNone(hamsterbus.ensure_service(FakeConnection(owner=True), own=True))
        self.popen.assert_not_called()

    def test_dbus_starts_it(self):
        connection = FakeConnection(activatable=[hamsterbus.NAME])
        self.assertIsNone(hamsterbus.ensure_service(connection, own=False))
        self.popen.assert_not_called()

    def test_own_ignores_what_dbus_could_start(self):
        connection = FakeConnection(owner=[False, False, True], activatable=[hamsterbus.NAME])
        self.assertIsInstance(hamsterbus.ensure_service(connection, own=True), FakeProcess)
        self.popen.assert_called_once_with(["/app/bin/hamster-service"])
        self.assertNotIn("ListActivatableNames", connection.sync_calls)
        # waited until the name was there
        self.assertEqual(connection.sync_calls.count("NameHasOwner"), 3)

    def test_own_defaults_to_the_flatpak(self):
        connection = FakeConnection(owner=[False, True], activatable=[hamsterbus.NAME])
        with mock.patch.dict(os.environ, {"FLATPAK_ID": "io.github.HamsterProjekt.HamsterKDE"}):
            self.assertIsNotNone(hamsterbus.ensure_service(connection))
        with mock.patch.dict(os.environ, {"FLATPAK_ID": ""}):
            self.assertIsNone(hamsterbus.ensure_service(FakeConnection(activatable=[hamsterbus.NAME])))

    def test_no_bus(self):
        connection = FakeConnection(error=dbus_error(Gio.DBusError.FAILED))
        self.assertIsNone(hamsterbus.ensure_service(connection, own=True))
        self.popen.assert_not_called()

    def test_no_program(self):
        self.which.return_value = None
        self.assertIsNone(hamsterbus.ensure_service(FakeConnection(), own=False))
        self.popen.assert_not_called()

    def test_bus_fails_while_waiting(self):
        connection = FakeConnection(owner=[False, dbus_error(Gio.DBusError.FAILED)])
        self.assertIsNotNone(hamsterbus.ensure_service(connection, own=True))
        self.assertEqual(connection.sync_calls.count("NameHasOwner"), 2)

    def test_service_dies_at_once(self):
        self.popen.return_value = FakeProcess(running=False)
        connection = FakeConnection()
        self.assertIsNotNone(hamsterbus.ensure_service(connection, own=True))
        self.assertEqual(connection.sync_calls.count("NameHasOwner"), 1)


@unittest.skipIf(hamsterbus is None, "hamsterbus cannot be imported")
class HamsterBusTest(unittest.TestCase):
    def make(self, connection=None, flatpak=False, folder="/data/hamster"):
        self.connection = connection or FakeConnection(owner=True)
        self.watchers = []
        environment = {"FLATPAK_ID": "io.github.HamsterProjekt.HamsterKDE" if flatpak else ""}
        with mock.patch.dict(os.environ, environment), \
             mock.patch.object(Gio, "bus_get_sync", return_value=self.connection), \
             mock.patch.object(Gio, "bus_watch_name_on_connection",
                               side_effect=lambda *arguments: self.watchers.append(arguments)), \
             mock.patch("shutil.which", return_value="/app/bin/hamster-service"):
            bus = hamsterbus.HamsterBus(expected_directory=lambda: folder)
        self.finished, self.failed, self.events = [], [], []
        bus.finished.connect(lambda *answer: self.finished.append(answer))
        bus.failed.connect(lambda *answer: self.failed.append(answer))
        for name in ("factsChanged", "registeredChanged", "storageProblemChanged"):
            getattr(bus, name).connect(lambda name=name: self.events.append(name))
        return bus

    def appear(self):
        self.watchers[0][3]()

    def vanish(self):
        self.watchers[0][4]()

    def test_change_signals(self):
        self.make()
        self.assertEqual([member for member, _ in self.connection.subscribed],
                         ["FactsChanged", "ActivitiesChanged", "TagsChanged"])
        self.connection.subscribed[0][1]("sender", "path", "interface", "FactsChanged", None)
        self.assertEqual(self.events, ["factsChanged"])

    def test_the_expected_service(self):
        bus = self.make()
        self.assertFalse(bus.registered)
        self.appear()
        self.assertTrue(bus.registered)
        self.assertEqual(self.connection.calls[0]["member"], "GetStorage")
        self.connection.answer(0, GLib.Variant("((ss))", (("markdown", "/data/hamster"),)))
        self.assertEqual(bus.storageProblem, "")
        self.assertEqual(self.events, ["registeredChanged"])
        self.appear()   # no news: no signal
        self.assertEqual(self.events, ["registeredChanged"])

    def test_another_folder(self):
        bus = self.make()
        self.appear()
        self.connection.answer(0, GLib.Variant("((ss))", (("markdown", "/elsewhere"),)))
        self.assertIn("/elsewhere", bus.storageProblem)
        self.vanish()
        self.assertEqual(bus.storageProblem, "")
        self.assertFalse(bus.registered)
        self.assertEqual(self.events, ["registeredChanged", "storageProblemChanged",
                                       "storageProblemChanged", "registeredChanged"])

    def test_a_service_without_get_storage(self):
        bus = self.make(flatpak=True)
        self.assertTrue(bus.canUseOwnService)
        self.appear()
        self.connection.answer(0, dbus_error(Gio.DBusError.UNKNOWN_METHOD))
        self.assertIn("Another Hamster service", bus.storageProblem)

    def test_gone_before_it_answers(self):
        bus = self.make(flatpak=True)
        self.appear()
        self.connection.answer(0, dbus_error(Gio.DBusError.NO_REPLY))
        self.assertEqual(bus.storageProblem, "")

    def test_use_own_service(self):
        bus = self.make()
        self.assertFalse(bus.canUseOwnService)
        bus.useOwnService()
        self.assertEqual(self.connection.calls[0]["member"], "Quit")
        self.assertEqual(self.connection.calls[0]["flags"], Gio.DBusCallFlags.NO_AUTO_START)

    def test_call(self):
        bus = self.make()
        call_id = bus.call("AddFact", "(siib)", ["coding@work", 0, 0, False])
        self.assertEqual(call_id, 1)
        call = self.connection.calls[0]
        self.assertEqual(call["member"], "AddFact")
        self.assertEqual(call["parameters"].unpack(), ("coding@work", 0, 0, False))
        self.assertEqual(call["flags"], Gio.DBusCallFlags.NONE)
        self.connection.answer(0, GLib.Variant("(i)", (7,)))
        self.assertEqual(self.finished, [(1, json.dumps([7]))])

    def test_call_without_arguments(self):
        bus = self.make()
        self.assertEqual(bus.call("GetTodaysFacts", "", []), 1)
        self.assertIsNone(self.connection.calls[0]["parameters"])

    def test_bad_arguments(self):
        bus = self.make()
        self.assertEqual(bus.call("AddFact", "(si)", ["one"]), 1)
        self.assertEqual(bus.call("AddFact", "(x)", [1]), 2)
        self.assertEqual(self.connection.calls, [])
        # the failure comes after call() returns, like every other answer
        self.assertEqual(self.failed, [])
        context = GLib.MainContext.default()
        while context.iteration(False):
            pass
        self.assertEqual([call_id for call_id, _ in self.failed], [1, 2])
        self.assertEqual(self.failed[0][1], "AddFact takes 2 argument(s)")

    def test_failure(self):
        bus = self.make()
        bus.call("StopTracking", "(i)", [0])
        error = dbus_error(Gio.DBusError.FAILED, "GDBus.Error:org.example.Oops: no such fact")
        self.connection.answer(0, error)
        self.assertEqual(len(self.failed), 1)
        self.assertEqual(self.failed[0][0], 1)
        self.assertIn("no such fact", self.failed[0][1])

    def test_flatpak_starts_its_own_on_a_failed_call(self):
        bus = self.make(connection=FakeConnection(owner=True), flatpak=True)
        bus.call("GetTodaysFacts", "", [])
        self.assertEqual(self.connection.calls[0]["flags"], Gio.DBusCallFlags.NO_AUTO_START)
        self.connection.owner = False
        with mock.patch.object(hamsterbus, "ensure_service", return_value=FakeProcess()) as ensure:
            self.connection.answer(0, dbus_error(Gio.DBusError.SERVICE_UNKNOWN))
        ensure.assert_called_once_with(self.connection, own=True)
        # sent again, once
        self.assertEqual(self.connection.calls[1]["member"], "GetTodaysFacts")
        self.connection.answer(1, dbus_error(Gio.DBusError.NAME_HAS_NO_OWNER))
        self.assertEqual(len(self.failed), 1)

    def test_vanished_in_the_flatpak(self):
        bus = self.make(connection=FakeConnection(owner=True), flatpak=True)
        old = FakeProcess()
        bus._service = old
        # another one took the name already
        with mock.patch.object(hamsterbus, "ensure_service") as ensure:
            self.vanish()
            ensure.assert_not_called()
            # the bus fails
            self.connection.owner = dbus_error(Gio.DBusError.FAILED)
            self.vanish()
            ensure.assert_not_called()
            # the old one does not stop
            self.connection.owner = False
            bus._service = FakeProcess(exits=False)
            self.vanish()
            ensure.assert_not_called()
            # the old one stops: ours again
            bus._service = old
            ensure.return_value = None
            self.vanish()
            ensure.assert_called_once_with(self.connection, own=True)
        self.assertIs(bus._service, old)

    def test_vanished_outside_the_flatpak(self):
        self.make()
        with mock.patch.object(hamsterbus, "ensure_service") as ensure:
            self.vanish()
        ensure.assert_not_called()


if __name__ == "__main__":
    unittest.main()
