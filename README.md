# Hamster for KDE Plasma

A port of the [Project Hamster](https://github.com/projecthamster/hamster)
time tracker to KDE Plasma, with a backend that stores everything in
Markdown files. It is part of [HamsterProjekt](https://github.com/HamsterProjekt),
and is not an official Project Hamster release.

It has three parts:

- **A Plasma 6 panel widget**, a port of the GNOME
  [hamster-shell-extension](https://github.com/projecthamster/hamster-shell-extension).
  It shows the current activity and its elapsed time in the panel. Its popup
  has an entry field with autocompletion, today's activities with edit and
  continue buttons, time per category, and the day's total.
- **The windows** (overview, add/edit activity, tracking settings), written
  with Qt Quick and Kirigami in place of Hamster's GTK ones, so they follow
  the Plasma theme.
- **The Markdown backend**: the Hamster service from
  [a fork of Hamster](https://github.com/HamsterProjekt/hamster), which
  keeps the activities in plain Markdown files instead of a database. The
  files can be edited by hand and synchronised between computers.

Hamster's data model, D-Bus methods and way of entering activities are
unchanged. The D-Bus names are HamsterProjekt's own
(`io.github.HamsterProjekt.Hamster` instead of upstream's
`org.gnome.Hamster`), so upstream Hamster can stay installed next to it.

## How it fits together

The widget stores nothing itself. It talks over D-Bus to a Hamster backend:

| Service | Used for |
|---|---|
| `io.github.HamsterProjekt.Hamster` | `GetTodaysFactsJSON`, `GetActivities`, `AddFact`, `StopTracking`, and the `FactsChanged`, `TagsChanged` and `ActivitiesChanged` signals |
| `io.github.HamsterProjekt.Hamster.WindowServer` | `edit`, `overview`, `preferences` (the overview, edit and settings windows) |

They are provided by the Hamster service of
[HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster), with the
Markdown backend below or with SQLite. The stock Hamster package
(`hamster-time-tracker`) provides upstream's `org.gnome.Hamster` instead, so
the widget does not use it.

## Requirements

- Plasma 6 with the `org.kde.plasma.workspace.dbus` QML module (developed on Plasma 6.6),
  for the widget
- for the windows of `app/`: Python 3 with PyQt6 and PyGObject, Kirigami and
  Qt Quick Controls
- The Hamster service of [HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster),
  with Markdown or SQLite storage

## Markdown backend

The fork of Hamster at [HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster)
has `src/hamster/storage/markdown.py`, which stores
everything in Markdown files instead of SQLite. Get it next to this
repository:

    git clone https://github.com/HamsterProjekt/hamster.git ~/projects/hamster

The files it writes:

    ~/.local/share/hamster/markdown/2026-11.md      facts, one file per month
    ~/.local/share/hamster/markdown/activities.md   categories, activities, tags

    ## 2026-11-11

    - 09:00 - 10:30 coding@work, login bug, #backend #billable
    - 10:30 - 11:00 email@work
    - 11:00 meeting@work

The files can be edited by hand while the service runs; the format is
described at the top of `markdown.py`. The backend is selected with
`HAMSTER_STORAGE=markdown`; `./install.sh` sets that up unless you give it
`--sqlite`.

### Keeping SQLite instead

Markdown is not required. The widget and the windows work the same on
Hamster's SQLite database, in two ways:

- **With the fork's GTK windows:** install
  [HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster) system-wide
  (see its INSTALL.md, "System-wide with waf") and
  [install the widget only](#install-the-widget-only).
- **With the Qt windows:** `./install.sh --sqlite`. See
  [Using SQLite instead of Markdown](INSTALL.md#using-sqlite-instead-of-markdown).

The SQLite database is `~/.local/share/hamster/hamster.db`. It is not
converted to Markdown files or back: each storage keeps its own data.

### Storing the files elsewhere

To keep the files in a folder that is synchronised (OneDrive, Google Drive,
Dropbox, Nextcloud, ...), open the tracking settings (`app/hamster-kde prefs`,
or the settings button of the overview) and choose the folder under
"Storage". With "Copy my activities to the new folder" ticked, the current
files are copied there; files already in that folder are never overwritten,
and the originals stay where they were. "Use Default" goes back.

The folder has to be a local one, that is, the place where the sync client
keeps its copy. The setting is the `markdown-directory` key of the
`io.github.HamsterProjekt.Hamster` settings; the `HAMSTER_MARKDOWN_DIR` environment variable
overrides it. If the folder cannot be created when the service starts (a
drive that is not mounted), the service does not start, rather than writing
somewhere else.

### Several computers

With the folder synchronised between computers, each Hamster follows what the
others write: switch task on one, and the widget and the overview of the
others show it once the sync client has delivered the file. Hamster notices
the new file within a second, and looks every 30 seconds in case the system
did not tell it. How long the delivery itself takes is up to the sync client.
For the `onedrive` client, run it with `--monitor`; expect several seconds up
to a minute, and up to `monitor_interval` (5 minutes by default) where the
push notifications of OneDrive do not get through.

Change things on one computer at a time. If two of them write the same month
before the sync client has caught up, it keeps one version, or stores the
other as a conflict copy under another name, which Hamster does not read:
merge its lines into the month file by hand.

To run Hamster from that checkout for your user, without root and without
the distribution package:

    scripts/install-backend.sh ~/projects/hamster
    scripts/install-backend.sh --uninstall          # leaves your files alone

This adds on-demand D-Bus services under `~/.local/share/dbus-1/services`
and Hamster's settings schema under `~/.local/share/glib-2.0/schemas`. It
needs Python 3 with PyGObject and dbus-python (GTK is not needed). The
distribution package can stay installed: it provides upstream's
`org.gnome.Hamster`, not `io.github.HamsterProjekt.Hamster`.

## Quick install

[INSTALL.md](INSTALL.md) has the full instructions: the packages to install,
the steps, updating, uninstalling, the Flatpak, and what to check when
something does not work. In short, with both repositories cloned:

    ./install.sh ~/projects/hamster            # widget + Markdown backend, for your user
    ./install.sh --sqlite ~/projects/hamster   # the same, with Hamster's SQLite database
    ./install.sh --uninstall

The sections below describe the two parts separately.

## Install the widget only

    kpackagetool6 --type Plasma/Applet --install plasmoid     # first time
    kpackagetool6 --type Plasma/Applet --upgrade plasmoid     # after changes

Then add "Hamster Time Tracker" to a panel. Plasma lets you set a keyboard
shortcut that opens the popup in the widget's settings.

## The windows

`app/` holds the overview, the add/edit dialog and the tracking settings,
written in QML with Qt Quick Controls and Kirigami so they follow the
Plasma theme. They replace Hamster's GTK windows:

    app/hamster-kde              # overview
    app/hamster-kde add
    app/hamster-kde edit ID
    app/hamster-kde prefs

`hamster-kde` is a small PyQt6 launcher. It also provides
`io.github.HamsterProjekt.Hamster.WindowServer`, which is what the widget calls, and is
started on demand once `scripts/install-backend.sh` has run. The installer
also adds "Hamster Time Tracker" to the application menu.

Not ported from the GTK version yet: tag completion in the edit dialog.

### Exporting

"Export…" in the overview's menu (Ctrl+E) writes the activities shown, that
is the chosen range narrowed by the search, to a file and opens it:

| Format | Contents |
|---|---|
| HTML report | totals by day, category, activity and tag, and the activity log |
| TSV, XML | one row or element per activity, with the columns of Hamster's export |
| iCal | one event per finished activity, for a calendar such as KOrganizer |

The format is the one picked in the save dialog, unless the file name ends
in `.html`, `.tsv`, `.xml` or `.ics`. The charts of the HTML report are drawn
by a script loaded from the internet (jQuery, as in Hamster's report), so
they are missing when the report is opened offline. To change the report's
look, put your own `report_template.html` (start from
`app/report_template.html`) in `~/.local/share/hamster/`.

The iCal file is not what Hamster writes: its times were in a form calendars
reject. Times are written as local time without a time zone.

## Flatpak

`flatpak/` has what is needed to build the windows and the Hamster service
with the Markdown storage as one Flatpak, `io.github.HamsterProjekt.HamsterKDE`:

    flatpak/build.sh                      # builds, and installs for your user
    flatpak/build.sh ../hamster           # the same, with a local Hamster checkout
    flatpak/build.sh --bundle             # also writes hamster-kde.flatpak
    flatpak run io.github.HamsterProjekt.HamsterKDE

It needs `flatpak-builder` (`sudo apt install flatpak-builder`). The Hamster
service comes from the `main` branch of
[HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster), unless a
local checkout is given. The first build downloads the KDE SDK and the PyQt
base application, about 2 GB.

Every merge to `main` builds the Flatpak on GitHub
(`.github/workflows/flatpak.yml`) and publishes it as a release; the latest is
at <https://github.com/HamsterProjekt/hamster-kde/releases/latest/download/hamster-kde.flatpak>.
A change to Hamster itself is picked up by the next build of this repository.

The same bundle is also published under the repository's
[Packages](https://github.com/HamsterProjekt/hamster-kde/pkgs/container/hamster-kde-flatpak),
as `ghcr.io/hamsterprojekt/hamster-kde-flatpak`, tagged `latest` and with each
release's version. Fetch it with [oras](https://oras.land/):

    oras pull ghcr.io/hamsterprojekt/hamster-kde-flatpak:latest
    flatpak install --user hamster-kde.flatpak


The Plasma widget cannot be part of a Flatpak. To use it with the Flatpak:

    scripts/install-flatpak-widget.sh
    scripts/install-flatpak-widget.sh --uninstall

This installs the widget and tells D-Bus to start Hamster from the Flatpak
when the widget asks for it (a Flatpak can only offer names that begin with
its own id for that, and the widget calls `io.github.HamsterProjekt.Hamster`). It takes the
place of `scripts/install-backend.sh`; use one or the other. Without it, the
Flatpak works on its own: the overview starts the service itself.

Things to know:

- The Flatpak keeps its files in
  `~/.var/app/io.github.HamsterProjekt.HamsterKDE/data/hamster/markdown`, not in
  `~/.local/share/hamster/markdown`. To go on with existing files, choose
  their folder in the tracking settings; the setting is the Flatpak's own too.
- It may read and write your home directory (`--filesystem=home`), so that
  the files can be in any folder, and reports saved anywhere.
- The manifest takes this repository from the checkout (`type: dir`) and
  Hamster from GitHub (`type: git`, branch `main`). For Flathub, both have to
  be `type: git` sources with a `commit`.
- The id `io.github.HamsterProjekt.HamsterKDE` follows Flathub's rule for
  projects hosted on GitHub. For Flathub, `flatpak/*.metainfo.xml` still
  needs a developer, a home page and screenshots.
- Before the rename to HamsterProjekt's names the Flatpak was
  `org.projecthamster.HamsterKDE`; see "Upgrading from the old names" in
  [INSTALL.md](INSTALL.md#upgrading-from-the-old-names).

`tests/run_flatpak_layout_test.sh ~/projects/hamster /tmp/hamster-layout`
runs the install steps of the manifest into a directory and starts Hamster
from there. It does not build the Flatpak.

## Entering activities

The entry field takes Hamster's own syntax:

    [start[-end]] activity[@category][,, description][, #tag #tag]

For example `coding@work,, login bug, #backend` or `10:30 lunch@personal`.

## Development

    tests/run_backend_test.sh            # D-Bus layer against a mock service
    tests/run_view_test.sh out.png       # renders the views to a screenshot

Both run headless on a private session bus with `tests/mock_hamster_service.py`,
so they need neither Hamster nor a running Plasma. They need PyQt6 and
dbus-python.

    tests/run_app_test.sh ~/projects/hamster /tmp/hamster-shots   # renders the app's windows
    tests/run_storage_test.sh ~/projects/hamster /tmp/hamster-move # changes the storage folder
    tests/run_sync_test.sh ~/projects/hamster /tmp/hamster-sync   # a sync client delivers changed files
    tests/run_export_test.sh ~/projects/hamster /tmp/hamster-export # exports in every format
    python3 tests/test_reports.py                                  # the report writer alone

To try the real widget in a window: `plasmawindowed io.github.HamsterProjekt.plasmoid`.

## Bugs and questions

Report problems with the widget, the windows or the Flatpak in this
repository's [Issues](https://github.com/HamsterProjekt/hamster-kde/issues),
and ask questions or share ideas in its
[Discussions](https://github.com/HamsterProjekt/hamster-kde/discussions).
Problems with the Hamster service or the Markdown storage belong in
[HamsterProjekt/hamster](https://github.com/HamsterProjekt/hamster/issues).
This is not Project Hamster, so please don't report these upstream.

## Licence

GPL-3.0-or-later, as the code and icons it derives from. See `COPYING`.
