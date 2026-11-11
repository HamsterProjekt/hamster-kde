# Installing Hamster for KDE Plasma

There are three ways to install it. Pick one:

| Way | What you get | Root needed |
|---|---|---|
| [From the source checkouts](#from-the-source-checkouts) (recommended) | Widget, windows and the Markdown backend, running from two git checkouts | Only for the packages |
| [As a Flatpak](#as-a-flatpak) | Windows and Markdown backend in a sandbox, the widget next to it | Only for `flatpak-builder` |
| [The widget only](#the-widget-only) | The panel widget, on top of the stock Hamster package (SQLite) | Only for the package |

Everything is installed for your user only, under `~/.local/share`.

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
git clone https://github.com/atterdag/hamster.git
```

```bash
git clone https://github.com/atterdag/hamster-kde.git
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

If the distribution's Hamster is installed (`hamster-time-tracker`), remove
it. Both provide `org.gnome.Hamster`, and its SQLite database is not
migrated to the Markdown files.

```bash
sudo apt remove hamster-time-tracker
```

### 4. Run the installer

```bash
cd ~/projects/hamster-kde && ./install.sh
```

With the Hamster checkout somewhere else: `./install.sh /path/to/hamster`.

It writes these, and nothing else:

| File | What it is |
|---|---|
| `~/.local/share/dbus-1/services/org.gnome.Hamster.service` | starts the Hamster service on demand, with the Markdown storage |
| `~/.local/share/dbus-1/services/org.gnome.Hamster.WindowServer.service` | starts the windows on demand |
| `~/.local/share/glib-2.0/schemas/org.gnome.hamster.gschema.xml` | Hamster's settings schema |
| `~/.local/share/applications/org.projecthamster.hamster-kde.desktop` | "Hamster Time Tracker" in the application menu |
| `~/.local/share/plasma/plasmoids/org.projecthamster.plasmoid` | the widget |

The service files point at the two checkouts, so keep them. After moving
one, run `./install.sh` again.

### 5. Add the widget to a panel

Right-click a panel, choose "Add or Manage Widgets", and add
"Hamster Time Tracker".

### 6. Check that it works

This starts the service and prints its version:

```bash
dbus-send --session --print-reply --dest=org.gnome.Hamster /org/gnome/Hamster org.gnome.Hamster.Version
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

This removes the files listed in step 4. Your Markdown files in
`~/.local/share/hamster/markdown` (or the folder you chose) stay. The two
checkouts can then be deleted.

## As a Flatpak

The windows and the Hamster service with the Markdown storage as one
Flatpak, `org.projecthamster.HamsterKDE`. It is built on your computer;
it is not on Flathub.

1. Install `flatpak` and `flatpak-builder`:

   ```bash
   sudo apt install flatpak flatpak-builder
   ```

2. Clone both repositories next to each other, as in
   [step 2](#2-get-the-two-repositories-next-to-each-other) above.

3. Build and install. The first build downloads the KDE SDK and the PyQt
   base application, about 2 GB.

   ```bash
   cd ~/projects/hamster-kde && flatpak/build.sh
   ```

   `flatpak/build.sh /path/to/hamster` takes the Hamster checkout from
   another place. `flatpak/build.sh --bundle` also writes
   `hamster-kde.flatpak`, which installs on another computer with
   `flatpak install --user hamster-kde.flatpak`.

4. Start it:

   ```bash
   flatpak run org.projecthamster.HamsterKDE
   ```

5. For the panel widget, which cannot be inside a Flatpak:

   ```bash
   scripts/install-flatpak-widget.sh
   ```

   Then add "Hamster Time Tracker" to a panel. This takes the place of
   `./install.sh`; use one or the other.

The Flatpak keeps its files in
`~/.var/app/org.projecthamster.HamsterKDE/data/hamster/markdown`, not in
`~/.local/share/hamster/markdown`. To go on with existing files, choose
their folder in the tracking settings.

To update, pull both repositories and run `flatpak/build.sh` again. To
uninstall:

```bash
scripts/install-flatpak-widget.sh --uninstall
```

```bash
flatpak uninstall org.projecthamster.HamsterKDE
```

More about the Flatpak is in the [README](README.md#flatpak).

## The widget only

The widget works with any Hamster service, also the stock one with its
SQLite database and GTK windows:

```bash
sudo apt install hamster-time-tracker
```

```bash
kpackagetool6 --type Plasma/Applet --install plasmoid
```

After changes, `--upgrade` in place of `--install`. To remove it:

```bash
kpackagetool6 --type Plasma/Applet --remove org.projecthamster.plasmoid
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
busctl --user status org.gnome.Hamster | grep -E 'PID|CommandLine'
```

**A window does not open.** Start it from a terminal to see the error:

```bash
~/projects/hamster-kde/app/hamster-kde
```

**`./install.sh` says "No Markdown storage in ...".** The path is not a
checkout of [atterdag/hamster](https://github.com/atterdag/hamster); the
upstream Hamster does not have the Markdown storage.
