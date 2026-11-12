#!/bin/sh
# Sets up, for the current user only, the Hamster services running from a
# source checkout. Nothing needs root.
#
#   scripts/install-backend.sh [--markdown|--sqlite] [path-to-hamster-checkout]
#                                                 (default checkout: ../hamster)
#   scripts/install-backend.sh --uninstall
#
# Storage:
#   --markdown  facts in Markdown files, ~/.local/share/hamster/markdown/
#               (see storage/markdown.py), or the folder chosen in the
#               tracking settings
#   --sqlite    facts in Hamster's SQLite database,
#               ~/.local/share/hamster/hamster.db
#   neither     keep the storage of the current installation; Markdown on a
#               first installation
#
# What it does:
#   - compiles Hamster's settings schema into ~/.local/share/glib-2.0/schemas
#   - adds D-Bus service files to ~/.local/share/dbus-1/services, so that
#     io.github.HamsterProjekt.Hamster is started on demand with the chosen storage, and the
#     windows (overview, edit, settings) are the Qt ones of app/
#   - adds a "Hamster Time Tracker" entry to the application menu
#   - removes what installations from before the rename to
#     io.github.HamsterProjekt left (org.gnome.Hamster service files and
#     schema, the org.projecthamster desktop file), and copies the settings
#     of the old schema over once

set -e

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
schemas="$data_home/glib-2.0/schemas"
services="$data_home/dbus-1/services"
applications="$data_home/applications"
desktop_file="$applications/io.github.HamsterProjekt.hamster-kde.desktop"
# (the .GUI one was installed by earlier versions of this script)
names="io.github.HamsterProjekt.Hamster io.github.HamsterProjekt.Hamster.WindowServer io.github.HamsterProjekt.Hamster.GUI"
# the names installations used before the fork had its own
legacy_names="org.gnome.Hamster org.gnome.Hamster.WindowServer org.gnome.Hamster.GUI"
legacy_schema="$schemas/org.gnome.hamster.gschema.xml"
legacy_desktop_file="$applications/org.projecthamster.hamster-kde.desktop"

reload_bus() {
    dbus-send --session --type=method_call --dest=org.freedesktop.DBus \
        / org.freedesktop.DBus.ReloadConfig 2>/dev/null || true
}

remove_legacy() {
    for name in $legacy_names; do
        rm -f "$services/$name.service"
    done
    rm -f "$legacy_schema" "$legacy_desktop_file"
}

stop_service() {
    dbus-send --session --type=method_call --dest=io.github.HamsterProjekt.Hamster \
        /io/github/HamsterProjekt/Hamster io.github.HamsterProjekt.Hamster.Quit 2>/dev/null || true
}

storage=""
checkout=""
for arg in "$@"; do
    case "$arg" in
        --markdown) storage=markdown ;;
        --sqlite) storage=sqlite ;;
        --uninstall) ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) checkout="$arg" ;;
    esac
done

if [ "$1" = "--uninstall" ]; then
    if busctl --user list 2>/dev/null | grep -q '^io.github.HamsterProjekt.Hamster '; then
        stop_service
    fi
    for name in $names; do
        rm -f "$services/$name.service"
    done
    rm -f "$desktop_file"
    rm -f "$schemas/io.github.HamsterProjekt.Hamster.gschema.xml"
    remove_legacy
    if [ -d "$schemas" ]; then
        glib-compile-schemas "$schemas"
    fi
    reload_bus
    echo "Removed. Your data in $data_home/hamster (Markdown files and hamster.db)"
    echo "and in any folder chosen in the tracking settings is untouched."
    exit 0
fi

here="$(cd "$(dirname "$0")/.." && pwd)"
hamster="$(cd "${checkout:-$here/../hamster}" && pwd)"

# Without --markdown or --sqlite, keep what the installed service file says,
# so that running the installer again to update does not switch storage.
hamster_service="$services/io.github.HamsterProjekt.Hamster.service"
if [ ! -f "$hamster_service" ] && [ -f "$services/org.gnome.Hamster.service" ]; then
    hamster_service="$services/org.gnome.Hamster.service"   # from before the rename
fi
if [ -z "$storage" ]; then
    if [ -f "$hamster_service" ] && ! grep -q 'HAMSTER_STORAGE=markdown' "$hamster_service"; then
        storage=sqlite
    else
        storage=markdown
    fi
fi
if [ ! -f "$hamster/src/hamster/storage/markdown.py" ]; then
    echo "No Markdown storage in $hamster (expected src/hamster/storage/markdown.py)" >&2
    exit 1
fi

mkdir -p "$schemas" "$services" "$applications"
remove_legacy
cp "$hamster/data/io.github.HamsterProjekt.Hamster.gschema.xml" "$schemas/"
glib-compile-schemas "$schemas"

# Settings of the old schema (among them the folder of the Markdown files)
# are copied once, when the new schema has none yet.
if command -v dconf > /dev/null \
        && [ -z "$(dconf dump /io/github/HamsterProjekt/Hamster/ 2>/dev/null)" ]; then
    old_settings="$(dconf dump /org/gnome/hamster/ 2>/dev/null || true)"
    if [ -n "$old_settings" ]; then
        printf '%s\n' "$old_settings" | dconf load /io/github/HamsterProjekt/Hamster/
        echo "Copied the settings of org.gnome.hamster to io.github.HamsterProjekt.Hamster"
    fi
fi

python3="$(command -v python3)"
service_file() {
    printf '[D-BUS Service]\nName=%s\nExec=%s\n' "$1" "$2" > "$services/$1.service"
}
if [ "$storage" = markdown ]; then
    service_file io.github.HamsterProjekt.Hamster \
        "/usr/bin/env HAMSTER_STORAGE=markdown $python3 $hamster/src/hamster-service.py"
else
    service_file io.github.HamsterProjekt.Hamster "$python3 $hamster/src/hamster-service.py"
fi
service_file io.github.HamsterProjekt.Hamster.WindowServer \
    "$python3 $here/app/hamster-kde --service"
rm -f "$services/io.github.HamsterProjekt.Hamster.GUI.service"

cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Hamster Time Tracker
Comment=Overview of your tracked time
Exec=$python3 $here/app/hamster-kde overview
Icon=chronometer
Categories=Office;Utility;Qt;KDE;
StartupWMClass=hamster-kde
DESKTOP

# a windows service of a previous installation would keep answering
dbus-send --session --type=method_call --dest=org.freedesktop.DBus / \
    org.freedesktop.DBus.ReloadConfig 2>/dev/null || true
pkill -u "$(id -u)" -f '^[^ ]*python[0-9.]* [^ ]*hamster-windows-service[.]py' 2>/dev/null || true

reload_bus

# A service of an earlier installation that is already running keeps
# answering, and a new one refuses to start next to it: the facts would go
# on to the old storage. Stop it; D-Bus starts the new one on the next call.
# (The distribution's Hamster uses upstream's org.gnome.Hamster, and can
# stay installed next to this.)
if busctl --user list 2>/dev/null | grep -q '^io.github.HamsterProjekt.Hamster '; then
    echo "Stopping the Hamster service that is running"
    stop_service
fi
pkill -u "$(id -u)" -f "^[^ ]*python[0-9.]* $hamster/src/hamster-service[.]py( |\$)" 2>/dev/null || true

echo "Installed. Hamster runs from $hamster"
if [ "$storage" = markdown ]; then
    echo "Storage: Markdown. Facts are stored in $data_home/hamster/markdown,"
    echo "unless another folder is chosen in the tracking settings."
    echo "(For Hamster's SQLite database instead, run again with --sqlite.)"
else
    echo "Storage: SQLite. Facts are stored in $data_home/hamster/hamster.db."
    echo "(For Markdown files instead, run again with --markdown.)"
fi
