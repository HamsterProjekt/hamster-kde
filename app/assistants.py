# SPDX-License-Identifier: GPL-3.0-or-later
"""AI assistants: connecting them to Hamster's MCP server.

Hamster's MCP server (hamster-mcp, from HamsterProjekt/hamster) lets an AI
assistant read and change the tracked time, the activities and the
categories. An assistant starts it itself, from the command written in its
configuration file. This module finds that command for the installation at
hand, and adds it to (or removes it from) the configuration of the
assistants it knows, so that nobody needs a terminal for it.

No Qt here, so that it can be tested on its own; the tracking settings use
it through app/hamster-kde.
"""

import json
import os
import shlex
import shutil
import tempfile

SERVER_NAME = "hamster"
SERVICE = "io.github.HamsterProjekt.Hamster"

# what status() says
MISSING = "missing"            # the assistant does not seem to be installed
CONNECTED = "connected"        # it has Hamster, with the right command
OUTDATED = "outdated"          # it has Hamster, with another command
DISCONNECTED = "disconnected"  # installed, without Hamster
UNREADABLE = "unreadable"      # its configuration file is not valid JSON


class AssistantError(Exception):
    """A configuration that cannot be changed; the message says why."""


def _home(environ):
    return environ.get("HOME") or os.path.expanduser("~")


def host_config_home(environ):
    """~/.config of the user, also from inside a Flatpak.

    There XDG_CONFIG_HOME is the sandbox's own (~/.var/app/ID/config), and
    the real one, if moved, is in HOST_XDG_CONFIG_HOME.
    """
    if environ.get("FLATPAK_ID"):
        return environ.get("HOST_XDG_CONFIG_HOME") or os.path.join(_home(environ), ".config")
    return environ.get("XDG_CONFIG_HOME") or os.path.join(_home(environ), ".config")


def host_data_home(environ):
    if environ.get("FLATPAK_ID"):
        return environ.get("HOST_XDG_DATA_HOME") or os.path.join(_home(environ), ".local", "share")
    return environ.get("XDG_DATA_HOME") or os.path.join(_home(environ), ".local", "share")


def server_command(environ=None, which=shutil.which):
    """The command that starts hamster-mcp, as a list; None if there is none.

    - in the Flatpak: through flatpak run, from outside the sandbox, where
      the assistants run;
    - an installed Hamster (./waf install): hamster-mcp on the PATH;
    - a checkout set up by scripts/install-backend.sh: hamster-mcp.py next
      to the hamster-service.py that D-Bus starts, with the same Python.
    """
    environ = os.environ if environ is None else environ
    flatpak_id = environ.get("FLATPAK_ID")
    if flatpak_id:
        return ["flatpak", "run", "--command=hamster-mcp", flatpak_id]
    installed = which("hamster-mcp")
    if installed:
        return [installed]
    service_file = os.path.join(host_data_home(environ), "dbus-1", "services", SERVICE + ".service")
    return _command_next_to_service(service_file)


def _command_next_to_service(service_file):
    try:
        with open(service_file, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    for line in lines:
        if not line.startswith("Exec="):
            continue
        try:
            words = shlex.split(line[len("Exec="):])
        except ValueError:
            return None
        for index, word in enumerate(words):
            if os.path.basename(word) == "hamster-service.py":
                script = os.path.join(os.path.dirname(word), "hamster-mcp.py")
                if not os.path.isfile(script):
                    return None   # a Hamster from before the MCP server
                python = words[index - 1] if index > 0 and "=" not in words[index - 1] \
                    and os.path.basename(words[index - 1]) != "env" else "python3"
                return [python, script]
    return None


class Assistant(object):
    """An assistant that keeps its MCP servers under "mcpServers" in a JSON file."""

    def __init__(self, id, name, config_path, present_paths, extra=None):
        self.id = id
        self.name = name
        self.config_path = config_path
        self.present_paths = present_paths
        # more keys of the server entry, written by the assistant's own tools
        self.extra = extra or {}

    def installed(self):
        return any(os.path.exists(path) for path in self.present_paths)

    def _read(self):
        """The configuration; {} if there is no file yet."""
        try:
            with open(self.config_path, encoding="utf-8") as f:
                text = f.read()
        except FileNotFoundError:
            return {}
        except OSError as error:
            raise AssistantError("Could not read {}: {}".format(self.config_path, error.strerror or error))
        try:
            data = json.loads(text) if text.strip() else {}
        except ValueError:
            raise AssistantError("{} is not valid JSON; it was left as it is.".format(self.config_path))
        if not isinstance(data, dict) or not isinstance(data.get("mcpServers", {}), dict):
            raise AssistantError("{} is not laid out as expected; it was left as it is."
                                 .format(self.config_path))
        return data

    def status(self, command):
        try:
            entry = self._read().get("mcpServers", {}).get(SERVER_NAME)
        except AssistantError:
            return UNREADABLE
        if entry is not None:
            if command and _same_command(entry, command):
                return CONNECTED
            return OUTDATED
        return DISCONNECTED if self.installed() else MISSING

    def connect(self, command):
        if not command:
            raise AssistantError("Hamster's MCP server is not installed.")
        data = self._read()
        servers = data.setdefault("mcpServers", {})
        entry = dict(self.extra)
        entry.update(server_entry(command))
        servers[SERVER_NAME] = entry
        self._write(data)

    def disconnect(self):
        data = self._read()
        servers = data.get("mcpServers", {})
        if SERVER_NAME in servers:
            del servers[SERVER_NAME]
            self._write(data)

    def _write(self, data):
        # through a link (configuration kept in a dotfiles repository), to its target
        path = os.path.realpath(self.config_path)
        directory = os.path.dirname(path)
        try:
            os.makedirs(directory, exist_ok=True)
            try:
                mode = os.stat(path).st_mode & 0o777
            except FileNotFoundError:
                mode = 0o600   # it may hold secrets of other servers
            # written next to it, then renamed: never half a file
            fd, temporary = tempfile.mkstemp(dir=directory, prefix=".hamster-", suffix=".json")
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2, ensure_ascii=False)
                    f.write("\n")
                os.chmod(temporary, mode)
                os.replace(temporary, path)
            except BaseException:
                os.unlink(temporary)
                raise
        except OSError as error:
            raise AssistantError("Could not write {}: {}".format(path, error.strerror or error))


def server_entry(command):
    return {"command": command[0], "args": list(command[1:])}


def _same_command(entry, command):
    return (isinstance(entry, dict) and entry.get("command") == command[0]
            and list(entry.get("args") or []) == list(command[1:]))


def configuration_snippet(command):
    """The JSON to paste into the configuration of another assistant."""
    return json.dumps({"mcpServers": {SERVER_NAME: server_entry(command)}}, indent=2)


def known_assistants(environ=None):
    environ = os.environ if environ is None else environ
    home = _home(environ)
    claude_desktop = os.path.join(host_config_home(environ), "Claude")
    # Claude Code keeps its user-wide servers in ~/.claude.json
    # (in $CLAUDE_CONFIG_DIR when that is set)
    claude_code_dir = environ.get("CLAUDE_CONFIG_DIR") or home
    return [
        Assistant("claude-desktop", "Claude Desktop",
                  os.path.join(claude_desktop, "claude_desktop_config.json"),
                  [claude_desktop]),
        Assistant("claude-code", "Claude Code",
                  os.path.join(claude_code_dir, ".claude.json"),
                  [os.path.join(claude_code_dir, ".claude.json"), os.path.join(home, ".claude")],
                  extra={"type": "stdio"}),
    ]
