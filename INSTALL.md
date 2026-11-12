# Installing Hamster for KDE Plasma

There are three ways to install it. Pick one:

| Way | What you get | Root needed |
|---|---|---|
| [From the source checkouts](#from-the-source-checkouts) (recommended) | Widget, windows and the Markdown backend, running from two git checkouts | Only for the packages |
| [As a Flatpak](#as-a-flatpak) | Windows and Markdown backend in a sandbox, the widget next to it | Only for `flatpak-builder` |
| [The widget only](#the-widget-only) | The panel widget, on top of the HamsterProjekt Hamster installed system-wide (SQLite, GTK windows) | Yes |

Everything is installed for your user only, under `~/.local/share`.

Installed before the fork had its own names (`org.gnome.Hamster`,
`org.projecthamster.*`)? See [Upgrading from the old names](#upgrading-from-the-old-names).

**Which storage?** The first two ways store your data in Markdown files, the
third in Hamster's usual SQLite database. To have the Qt windows *and*
SQLite, install from the source checkouts with `./install.sh --sqlite`; see
[Using SQLite instead of Markdown](#using-sqlite-instead-of-markdown).

## From the source checkouts

### 1. Install the packages

On Kubuntu, KDE neon and Debian with Plasma 6:

```bash
sudo apt install git python3-gi python3-dbus python3-pyqt6 python3-pyqt6.qtqml python3-pyqt6.qtquick libglib2.0-bin dbus-bin kpackagetool6 plasma-workspace qml6-module-org-kde-kirigami qml6-module-org-kde-desktop qml6-module-org-kde-kcmutils qml6-module-qtquick-controls qml6-module-qtquick-dialogs qml6-module-qtquick-layouts
```

Most of them are already there on a Plasma desktop. The package names were
checked on Ubuntu 26.04 (Plasma 6.6). On another distribution, install the
same things under its own names:

| Needed | For |
|---|---|
| Plasma 6, with `kpackagetool6` and the `org.kde.plasma.workspace.dbus` QML module (part of plasma-workspace) | the widget |
| Python 3 with PyQt6 (QtQml, QtDBus, QtWidgets) and PyGObject | the windows |
| The QML modules Kirigami, `org.kde.desktop`, `org.kde.kcmutils`, Qt Quick Controls, Dialogs and Layouts | the windows and the widget's settings |
| Python 3 with PyGObject and dbus-python, `glib-compile-schemas`, `dbus-send` | the Hamster service |

GTK is not needed.

### 2. Get the two repositories next to each other

```bash
mkdir -p ~/projects && cd ~/projects
```

```bash
git clone https://github.com/HamsterProjekt/hamster.git
```

```bash
git clone https://github.com/HamsterProjekt/hamster-kde.git
```

They can be anywhere. If `hamster` is not next to `hamster-kde`, give its
path to the installer in step 4.

### 3. Stop a Hamster that is already running

A running Hamster service keeps answering until it is stopped, so the new
one would not be used:

```bash
pkill -f hamster-service
```

```bash
pkill -f hamster-windows-service
```

The distribution's Hamster (`hamster-time-tracker`) can stay installed: it
uses upstream's `org.gnome.Hamster`, not `io.github.HamsterProjekt.Hamster`.
Its SQLite database is not migrated to the Markdown files.

### 4. Run the installer

```bash
cd ~/projects/hamster-kde && ./install.sh
```

With the Hamster checkout somewhere else: `./install.sh /path/to/hamster`.

This stores your data in Markdown files. For Hamster's SQLite database
instead, add `--sqlite`:

```bash
cd ~/projects/hamster-kde && ./install.sh --sqlite
```

See [Using SQLite instead of Markdown](#using-sqlite-instead-of-markdown).

It writes these, and nothing else:

| File | What it is |
|---|---|
| `~/.local/share/dbus-1/services/io.github.HamsterProjekt.Hamster.service` | starts the Hamster service on demand, with the chosen storage |
| `~/.local/share/dbus-1/services/io.github.HamsterProjekt.Hamster.WindowServer.service` | starts the windows on demand |
| `~/.local/share/glib-2.0/schemas/io.github.HamsterProjekt.Hamster.gschema.xml` | Hamster's settings schema |
| `~/.local/share/applications/io.github.HamsterProjekt.hamster-kde.desktop` | "Hamster Time Tracker" in the application menu |
| `~/.local/share/plasma/plasmoids/io.github.HamsterProjekt.plasmoid` | the widget |

The service files point at the two checkouts, so keep them. After moving
one, run `./install.sh` again.

### 5. Add the widget to a panel

Right-click a panel, choose "Add or Manage Widgets", and add
"Hamster Time Tracker".

### 6. Check that it works

This starts the service and prints its version:

```bash
dbus-send --session --print-reply --dest=io.github.HamsterProjekt.Hamster /io/github/HamsterProjekt/Hamster io.github.HamsterProjekt.Hamster.Version
```

Type an activity in the widget, for example `coding@work`. It is then in
the file of this month:

```bash
cat ~/.local/share/hamster/markdown/$(date +%Y-%m).md
```

The overview is in the application menu as "Hamster Time Tracker", or:

```bash
~/projects/hamster-kde/app/hamster-kde
```

### Updating

```bash
cd ~/projects/hamster && git pull
```

```bash
cd ~/projects/hamster-kde && git pull && ./install.sh
```

`./install.sh` keeps the storage you chose when you installed, SQLite or
Markdown.

The running programs keep the old code until they are restarted:

```bash
pkill -f hamster-service
```

```bash
pkill -f 'hamster-kde --service'
```

```bash
systemctl --user restart plasma-plasmashell.service
```

### Uninstalling

```bash
cd ~/projects/hamster-kde && ./install.sh --uninstall
```

This removes the files listed in step 4. Your data stays: the Markdown
files in `~/.local/share/hamster/markdown` (or the folder you chose), and
the SQLite database `~/.local/share/hamster/hamster.db`. The two
checkouts can then be deleted.

### Using SQLite instead of Markdown

The Hamster service can keep your data in Markdown files (the default of
the installer) or in Hamster's usual SQLite database,
`~/.local/share/hamster/hamster.db`. The widget and the windows work the
same with both. Choose with an option of the installer:

```bash
cd ~/projects/hamster-kde && ./install.sh --sqlite
```

```bash
cd ~/projects/hamster-kde && ./install.sh --markdown
```

Use it on a first installation, or at any time to switch. The installer
stops the running service, and D-Bus starts it again with the new storage
on the next call. When you later run `./install.sh` without an option, for
instance to update, it keeps the storage you chose.

The two storages keep separate data. Nothing is converted from one to the
other, and nothing is deleted when you switch, so switching back brings
your earlier data back.

To check which storage is used, look at what the service printed when it
started; the last line is the current one:

```bash
journalctl --user -b | grep 'storage:'
```

Under the hood the option only changes the `Exec` line of
`~/.local/share/dbus-1/services/io.github.HamsterProjekt.Hamster.service`: with
`HAMSTER_STORAGE=markdown` the service uses Markdown, without it SQLite.

The folder setting under "Storage" in the tracking settings only applies to
the Markdown files; with SQLite it has no effect.

## As a Flatpak

The windows and the Hamster service with the Markdown storage as one
Flatpak, `io.github.HamsterProjekt.HamsterKDE`. It is not on Flathub: every
merge to `main` builds it on GitHub and publishes it as a release, or you
build it yourself.

1. Install `flatpak`:

   ```bash
   sudo apt install flatpak
   ```

2. Clone this repository, for the widget and its installer:

   ```bash
   git clone https://github.com/HamsterProjekt/hamster-kde.git ~/projects/hamster-kde
   ```

3. Get the Flatpak, in one of two ways.

   **The latest release.** The runtime comes from Flathub with it:

   ```bash
   wget https://github.com/HamsterProjekt/hamster-kde/releases/latest/download/hamster-kde.flatpak
   ```

   ```bash
   flatpak install --user hamster-kde.flatpak
   ```

   **Built on your computer.** This needs `flatpak-builder`
   (`sudo apt install flatpak-builder`); the first build downloads the KDE
   SDK and the PyQt base application, about 2 GB. The Hamster service comes
   from the `main` branch of
   [HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster):

   ```bash
   cd ~/projects/hamster-kde && flatpak/build.sh
   ```

   `flatpak/build.sh ~/projects/hamster` takes the Hamster service from a
   local checkout instead. `flatpak/build.sh --bundle` also writes
   `hamster-kde.flatpak`, which installs on another computer with
   `flatpak install --user hamster-kde.flatpak`.

4. Start it:

   ```bash
   flatpak run io.github.HamsterProjekt.HamsterKDE
   ```

5. For the panel widget, which cannot be inside a Flatpak:

   ```bash
   scripts/install-flatpak-widget.sh
   ```

   Then add "Hamster Time Tracker" to a panel. This takes the place of
   `./install.sh`; use one or the other.

The Flatpak keeps its files in
`~/.var/app/io.github.HamsterProjekt.HamsterKDE/data/hamster/markdown`, not in
`~/.local/share/hamster/markdown`. To go on with existing files, choose
their folder in the tracking settings.

To update, install the latest release again, or pull and run
`flatpak/build.sh` again. To uninstall:

```bash
scripts/install-flatpak-widget.sh --uninstall
```

```bash
flatpak uninstall io.github.HamsterProjekt.HamsterKDE
```

More about the Flatpak is in the [README](README.md#flatpak).

## The widget only

The widget works with the Hamster service of
[HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster) however it
is installed, also system-wide with its SQLite database and GTK windows (see
"System-wide with waf" in its
[INSTALL.md](https://github.com/HamsterProjekt/hamster/blob/main/INSTALL.md)).
The stock `hamster-time-tracker` package does not work with it: that is
upstream Hamster, with upstream's `org.gnome.Hamster` names.

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
```

After changes, `--upgrade` in place of `--install`. To remove it:

```bash
kpackagetool6 --type Plasma/Applet --remove io.github.HamsterProjekt.plasmoid
```

## The parts separately

`./install.sh` runs these two; they can be used on their own:

```bash
scripts/install-backend.sh ~/projects/hamster
```

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
```

The first sets up the service, the windows and the menu entry
(`scripts/install-backend.sh --uninstall` removes them). The second is the
widget.

## Upgrading from the old names

Until November 2026 Hamster for KDE used upstream's D-Bus names
(`org.gnome.Hamster`), the settings schema `org.gnome.hamster`, and the ids
`org.projecthamster.plasmoid`, `org.projecthamster.hamster-kde` and
`org.projecthamster.HamsterKDE`. They are now HamsterProjekt's own:
`io.github.HamsterProjekt.Hamster`, `io.github.HamsterProjekt.plasmoid`,
`io.github.HamsterProjekt.hamster-kde` and
`io.github.HamsterProjekt.HamsterKDE`.

**From the source checkouts:** pull both repositories and run `./install.sh`
as in [Updating](#updating). The installer removes the old service files,
schema, menu entry and widget, and copies your settings (among them the
folder of the Markdown files) to the new schema. Stop the old service and
windows, as in Updating, and add "Hamster Time Tracker" to the panel again:
the old widget is gone from it.

**As a Flatpak:** build and install the new one and run
`scripts/install-flatpak-widget.sh`, which removes the old widget and service
files. The new Flatpak has its own folder, so before you start it, copy the
files of the old one:

```bash
mkdir -p ~/.var/app/io.github.HamsterProjekt.HamsterKDE/data
```

```bash
cp -a ~/.var/app/org.projecthamster.HamsterKDE/data/hamster ~/.var/app/io.github.HamsterProjekt.HamsterKDE/data/
```

If you had chosen another folder in the tracking settings, choose it again.
When everything is there, remove the old Flatpak:

```bash
flatpak uninstall org.projecthamster.HamsterKDE
```

## When something does not work

**The widget is not in the list of widgets.** Check that it is installed,
then restart the Plasma shell:

```bash
kpackagetool6 --type Plasma/Applet --list | grep -i hamster
```

```bash
systemctl --user restart plasma-plasmashell.service
```

**The widget stays empty, or nothing is saved.** Run the service by hand
and read what it prints:

```bash
pkill -f hamster-service
```

```bash
HAMSTER_STORAGE=markdown python3 ~/projects/hamster/src/hamster-service.py
```

A missing Python module there means a package of step 1 is not installed.
The service also refuses to start when the folder chosen for the Markdown
files cannot be created, for instance on a drive that is not mounted.

**Activities of the old database show up, or the GTK windows open.** Another
Hamster is answering. See which program has the name, and go through
[step 3](#3-stop-a-hamster-that-is-already-running) again:

```bash
busctl --user status io.github.HamsterProjekt.Hamster | grep -E 'PID|CommandLine'
```

**A window does not open.** Start it from a terminal to see the error:

```bash
~/projects/hamster-kde/app/hamster-kde
```

**`./install.sh` says "No Markdown storage in ...".** The path is not a
checkout of [HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster); the
upstream Hamster does not have the Markdown storage.
