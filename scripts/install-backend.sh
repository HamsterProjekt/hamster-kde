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
#     org.gnome.Hamster is started on demand with the chosen storage, and the
#     windows (overview, edit, settings) are the Qt ones of app/
#   - adds a "Hamster Time Tracker" entry to the application menu

set -e

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
schemas="$data_home/glib-2.0/schemas"
services="$data_home/dbus-1/services"
applications="$data_home/applications"
desktop_file="$applications/org.projecthamster.hamster-kde.desktop"
# (the .GUI one was installed by earlier versions of this script)
names="org.gnome.Hamster org.gnome.Hamster.WindowServer org.gnome.Hamster.GUI"

reload_bus() {
    dbus-send --session --type=method_call --dest=org.freedesktop.DBus \
        / org.freedesktop.DBus.ReloadConfig 2>/dev/null || true
}

stop_service() {
    dbus-send --session --type=method_call --dest=org.gnome.Hamster \
        /org/gnome/Hamster org.gnome.Hamster.Quit 2>/dev/null || true
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
    if busctl --user list 2>/dev/null | grep -q '^org.gnome.Hamster '; then
        stop_service
    fi
    for name in $names; do
        rm -f "$services/$name.service"
    done
    rm -f "$desktop_file"
    rm -f "$schemas/org.gnome.hamster.gschema.xml"
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
hamster_service="$services/org.gnome.Hamster.service"
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
cp "$hamster/data/org.gnome.hamster.gschema.xml" "$schemas/"
glib-compile-schemas "$schemas"

python3="$(command -v python3)"
service_file() {
    printf '[D-BUS Service]\nName=%s\nExec=%s\n' "$1" "$2" > "$services/$1.service"
}
if [ "$storage" = markdown ]; then
    service_file org.gnome.Hamster \
        "/usr/bin/env HAMSTER_STORAGE=markdown $python3 $hamster/src/hamster-service.py"
else
    service_file org.gnome.Hamster "$python3 $hamster/src/hamster-service.py"
fi
service_file org.gnome.Hamster.WindowServer \
    "$python3 $here/app/hamster-kde --service"
rm -f "$services/org.gnome.Hamster.GUI.service"

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

# A service that is already running (an earlier installation, or the
# distribution's Hamster with its SQLite database) keeps answering, and a
# new one refuses to start next to it: the facts would go on to the old
# storage. Stop it; D-Bus starts the new one on the next call.
if busctl --user list 2>/dev/null | grep -q '^org.gnome.Hamster '; then
    echo "Stopping the Hamster service that is running"
    stop_service
fi
pkill -u "$(id -u)" -f '^[^ ]*python[0-9.]* [^ ]*hamster-service([.]py)?( |$)' 2>/dev/null || true

if [ -n "$(command -v dpkg-query)" ] \
        && dpkg-query -W -f '${Status}' hamster-time-tracker 2>/dev/null | grep -q 'ok installed'; then
    echo "Warning: the distribution's Hamster (hamster-time-tracker) is installed." >&2
    echo "It also provides org.gnome.Hamster, with the SQLite storage; remove it:" >&2
    echo "    sudo apt remove hamster-time-tracker" >&2
fi

echo "Installed. Hamster runs from $hamster"
if [ "$storage" = markdown ]; then
    echo "Storage: Markdown. Facts are stored in $data_home/hamster/markdown,"
    echo "unless another folder is chosen in the tracking settings."
    echo "(For Hamster's SQLite database instead, run again with --sqlite.)"
else
    echo "Storage: SQLite. Facts are stored in $data_home/hamster/hamster.db."
    echo "(For Markdown files instead, run again with --markdown.)"
fi
