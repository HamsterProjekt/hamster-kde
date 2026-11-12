#!/bin/sh
# Connects the Plasma widget to Hamster installed as a Flatpak
# (io.github.HamsterProjekt.HamsterKDE, see flatpak/). For the current user only.
#
#   scripts/install-flatpak-widget.sh
#   scripts/install-flatpak-widget.sh --uninstall
#
# A Flatpak cannot offer the D-Bus names io.github.HamsterProjekt.Hamster and
# io.github.HamsterProjekt.Hamster.WindowServer for starting on demand (only names that
# begin with its own id). This adds the two service files that do, to
# ~/.local/share/dbus-1/services, and installs the widget.
# It replaces what scripts/install-backend.sh set up, if that was used:
# Hamster then runs from the Flatpak, not from the source checkout.
set -e
id=io.github.HamsterProjekt.HamsterKDE
here="$(cd "$(dirname "$0")/.." && pwd)"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
services="$data_home/dbus-1/services"
names="io.github.HamsterProjekt.Hamster io.github.HamsterProjekt.Hamster.WindowServer"
# the ids before the fork had its own names
legacy_id=org.projecthamster.HamsterKDE
legacy_names="org.gnome.Hamster org.gnome.Hamster.WindowServer"

remove_legacy() {
    for name in $legacy_names; do
        if grep -qs "$legacy_id" "$services/$name.service"; then
            rm -f "$services/$name.service"
        fi
    done
    rm -f "$data_home/applications/org.projecthamster.hamster-kde.desktop"
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx 'org.projecthamster.plasmoid'; then
        kpackagetool6 --type Plasma/Applet --remove org.projecthamster.plasmoid || true
        echo "Removed the old widget (org.projecthamster.plasmoid); add the new one to your panel."
    fi
}

reload_bus() {
    dbus-send --session --type=method_call --dest=org.freedesktop.DBus \
        / org.freedesktop.DBus.ReloadConfig 2>/dev/null || true
}

stop_running() {
    # whatever provides the names now would keep doing so
    if busctl --user list 2>/dev/null | grep -q '^io.github.HamsterProjekt.Hamster '; then
        dbus-send --session --type=method_call --dest=io.github.HamsterProjekt.Hamster \
            /io/github/HamsterProjekt/Hamster io.github.HamsterProjekt.Hamster.Quit 2>/dev/null || true
    fi
}

if [ "$1" = "--uninstall" ]; then
    stop_running
    for name in $names; do
        if grep -qs "$id" "$services/$name.service"; then
            rm -f "$services/$name.service"
        fi
    done
    remove_legacy
    reload_bus
    kpackagetool6 --type Plasma/Applet --remove io.github.HamsterProjekt.plasmoid || true
    echo "Removed. The Flatpak and your Markdown files are untouched."
    exit 0
fi

if ! flatpak info "$id" > /dev/null 2>&1; then
    echo "$id is not installed. Build it first: flatpak/build.sh" >&2
    exit 1
fi
flatpak="$(command -v flatpak)"

stop_running
remove_legacy
mkdir -p "$services"
printf '[D-BUS Service]\nName=%s\nExec=%s\n' io.github.HamsterProjekt.Hamster \
    "$flatpak run --command=hamster-service $id" > "$services/io.github.HamsterProjekt.Hamster.service"
printf '[D-BUS Service]\nName=%s\nExec=%s\n' io.github.HamsterProjekt.Hamster.WindowServer \
    "$flatpak run $id --service" > "$services/io.github.HamsterProjekt.Hamster.WindowServer.service"
# of scripts/install-backend.sh: the same windows, from the source checkout
rm -f "$data_home/applications/io.github.HamsterProjekt.hamster-kde.desktop"
reload_bus

kpackagetool6 --type Plasma/Applet --upgrade "$here/plasmoid" 2>/dev/null \
    || kpackagetool6 --type Plasma/Applet --install "$here/plasmoid"
echo
echo "Done. Add 'Hamster Time Tracker' to a panel, if it is not there yet."
echo "The Flatpak keeps its files in ~/.var/app/$id/data/hamster/markdown,"
echo "unless another folder is chosen in the tracking settings."
if [ -d "$HOME/.var/app/$legacy_id/data/hamster" ]; then
    echo
    echo "The Flatpak from before the rename ($legacy_id) has files in"
    echo "~/.var/app/$legacy_id/data/hamster. To go on with them, see"
    echo "'Upgrading from the old names' in INSTALL.md."
fi
