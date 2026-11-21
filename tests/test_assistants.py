#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Tests of app/assistants.py: connecting AI assistants to Hamster's MCP server.
Run: python3 tests/test_assistants.py (nothing else needed)."""
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest

here = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(here, "..", "app"))
import assistants  # noqa: E402
from assistants import (CONNECTED, DISCONNECTED, MISSING, OUTDATED, UNREADABLE,  # noqa: E402
                        AssistantError)


def nowhere(name):
    return None


class HomeTestCase(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="hamster-assistants-")
        self.addCleanup(shutil.rmtree, self.home)
        self.environ = {"HOME": self.home}

    def path(self, *parts):
        return os.path.join(self.home, *parts)

    def write(self, text, *parts):
        os.makedirs(os.path.dirname(self.path(*parts)), exist_ok=True)
        with open(self.path(*parts), "w", encoding="utf-8") as f:
            f.write(text)

    def read_json(self, *parts):
        with open(self.path(*parts), encoding="utf-8") as f:
            return json.load(f)


class ServerCommandTest(HomeTestCase):
    def service_file(self, exec_line):
        self.write("[D-BUS Service]\nName=io.github.HamsterProjekt.Hamster\nExec={}\n".format(exec_line),
                   ".local", "share", "dbus-1", "services", "io.github.HamsterProjekt.Hamster.service")

    def checkout(self, with_mcp=True):
        src = self.path("hamster", "src")
        os.makedirs(src)
        open(os.path.join(src, "hamster-service.py"), "w").close()
        if with_mcp:
            open(os.path.join(src, "hamster-mcp.py"), "w").close()
        return src

    def test_flatpak(self):
        self.environ["FLATPAK_ID"] = "io.github.HamsterProjekt.HamsterKDE"
        self.assertEqual(assistants.server_command(self.environ, nowhere),
                         ["flatpak", "run", "--command=hamster-mcp", "io.github.HamsterProjekt.HamsterKDE"])

    def test_installed(self):
        self.assertEqual(assistants.server_command(self.environ, lambda name: "/usr/bin/" + name),
                         ["/usr/bin/hamster-mcp"])

    def test_checkout_of_the_installer(self):
        src = self.checkout()
        self.service_file("/usr/bin/env HAMSTER_STORAGE=markdown /usr/bin/python3.12 {}/hamster-service.py".format(src))
        self.assertEqual(assistants.server_command(self.environ, nowhere),
                         ["/usr/bin/python3.12", os.path.join(src, "hamster-mcp.py")])
        self.service_file("/usr/bin/python3 {}/hamster-service.py".format(src))
        self.assertEqual(assistants.server_command(self.environ, nowhere),
                         ["/usr/bin/python3", os.path.join(src, "hamster-mcp.py")])

    def test_checkout_without_the_mcp_server(self):
        src = self.checkout(with_mcp=False)
        self.service_file("/usr/bin/python3 {}/hamster-service.py".format(src))
        self.assertIsNone(assistants.server_command(self.environ, nowhere))

    def test_nothing(self):
        self.assertIsNone(assistants.server_command(self.environ, nowhere))
        self.service_file("/usr/bin/flatpak run --command=hamster-service io.github.HamsterProjekt.HamsterKDE")
        self.assertIsNone(assistants.server_command(self.environ, nowhere))


class AssistantTest(HomeTestCase):
    COMMAND = ["flatpak", "run", "--command=hamster-mcp", "io.github.HamsterProjekt.HamsterKDE"]

    def assistant(self, id):
        return next(a for a in assistants.known_assistants(self.environ) if a.id == id)

    def test_claude_desktop(self):
        desktop = self.assistant("claude-desktop")
        self.assertEqual(desktop.config_path, self.path(".config", "Claude", "claude_desktop_config.json"))
        self.assertEqual(desktop.status(self.COMMAND), MISSING)
        os.makedirs(self.path(".config", "Claude"))
        self.assertEqual(desktop.status(self.COMMAND), DISCONNECTED)

        desktop.connect(self.COMMAND)
        self.assertEqual(desktop.status(self.COMMAND), CONNECTED)
        self.assertEqual(self.read_json(".config", "Claude", "claude_desktop_config.json"),
                         {"mcpServers": {"hamster": {"command": "flatpak",
                                                     "args": self.COMMAND[1:]}}})
        mode = stat.S_IMODE(os.stat(desktop.config_path).st_mode)
        self.assertEqual(mode, 0o600)
        self.assertEqual(desktop.status(["/usr/bin/hamster-mcp"]), OUTDATED)

        desktop.disconnect()
        self.assertEqual(desktop.status(self.COMMAND), DISCONNECTED)
        self.assertEqual(self.read_json(".config", "Claude", "claude_desktop_config.json"),
                         {"mcpServers": {}})

    def test_the_rest_of_the_configuration_is_kept(self):
        original = {"numStartups": 12, "theme": "dark",
                    "mcpServers": {"other": {"command": "other-mcp", "env": {"TOKEN": "x"}}},
                    "projects": {"/a": {"mcpServers": {}}}}
        self.write(json.dumps(original), ".claude.json")
        os.chmod(self.path(".claude.json"), 0o644)
        code = self.assistant("claude-code")
        self.assertEqual(code.status(self.COMMAND), DISCONNECTED)
        code.connect(self.COMMAND)

        data = self.read_json(".claude.json")
        self.assertEqual(data["mcpServers"]["hamster"],
                         {"type": "stdio", "command": "flatpak", "args": self.COMMAND[1:]})
        del data["mcpServers"]["hamster"]
        self.assertEqual(data, original)
        self.assertEqual(stat.S_IMODE(os.stat(self.path(".claude.json")).st_mode), 0o644)
        self.assertEqual(sorted(os.listdir(self.home)), [".claude.json"])   # no temporary file left

    def test_through_a_link(self):
        self.write("{}", "dotfiles", "claude.json")
        os.symlink(self.path("dotfiles", "claude.json"), self.path(".claude.json"))
        self.assistant("claude-code").connect(self.COMMAND)
        self.assertTrue(os.path.islink(self.path(".claude.json")))
        self.assertIn("hamster", self.read_json("dotfiles", "claude.json")["mcpServers"])

    def test_broken_configuration_is_left_alone(self):
        self.write("{not json", ".claude.json")
        code = self.assistant("claude-code")
        self.assertEqual(code.status(self.COMMAND), UNREADABLE)
        with self.assertRaisesRegex(AssistantError, "not valid JSON"):
            code.connect(self.COMMAND)
        with open(self.path(".claude.json")) as f:
            self.assertEqual(f.read(), "{not json")

    def test_without_a_server(self):
        with self.assertRaisesRegex(AssistantError, "not installed"):
            self.assistant("claude-code").connect(None)

    def test_flatpak_uses_the_host_configuration(self):
        self.environ.update(FLATPAK_ID="io.github.HamsterProjekt.HamsterKDE",
                            XDG_CONFIG_HOME=self.path(".var", "app", "x", "config"))
        self.assertEqual(self.assistant("claude-desktop").config_path,
                         self.path(".config", "Claude", "claude_desktop_config.json"))
        self.environ["HOST_XDG_CONFIG_HOME"] = self.path("elsewhere")
        self.assertEqual(self.assistant("claude-desktop").config_path,
                         self.path("elsewhere", "Claude", "claude_desktop_config.json"))

    def test_snippet(self):
        self.assertEqual(json.loads(assistants.configuration_snippet(["/usr/bin/hamster-mcp"])),
                         {"mcpServers": {"hamster": {"command": "/usr/bin/hamster-mcp", "args": []}}})


if __name__ == "__main__":
    unittest.main()
