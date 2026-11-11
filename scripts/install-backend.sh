#!/bin/sh
# Sets up, for the current user only, the Hamster services running from a
# source checkout with the Markdown storage. Nothing needs root.
#
#   scripts/install-backend.sh [path-to-hamster-checkout]   (default: ../hamster)
#   scripts/install-backend.sh --uninstall
#
# What it does:
#   - compiles Hamster's settings schema into ~/.local/share/glib-2.0/schemas
#   - adds D-Bus service files to ~/.local/share/dbus-1/services, so that
#     org.gnome.Hamster is started on demand with HAMSTER_STORAGE=markdown,
#     and the windows (overview, edit, settings) are the Qt ones of app/
#   - adds a "Hamster Time Tracker" entry to the application menu
# The facts go to ~/.local/share/hamster/markdown/ (see storage/markdown.py),
# or to the folder chosen in the tracking settings.

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
    echo "Removed. Your Markdown files in $data_home/hamster/markdown are untouched."
    exit 0
fi

here="$(cd "$(dirname "$0")/.." && pwd)"
hamster="$(cd "${1:-$here/../hamster}" && pwd)"
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
service_file org.gnome.Hamster \
    "/usr/bin/env HAMSTER_STORAGE=markdown $python3 $hamster/src/hamster-service.py"
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
echo "Installed. Hamster runs from $hamster"
echo "Facts are stored in $data_home/hamster/markdown, unless another folder"
echo "is chosen in the tracking settings."
