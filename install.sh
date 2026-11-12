#!/bin/sh
# Installs everything for the current user: the Plasma widget and the
# Hamster services. No root needed.
#
#   ./install.sh [--markdown|--sqlite] [path-to-hamster-checkout]
#                                              (default checkout: ../hamster)
#   ./install.sh --uninstall                   (keeps your data)
#
# --markdown stores the facts in Markdown files, --sqlite in Hamster's SQLite
# database. With neither, the storage of the current installation is kept;
# a first installation uses Markdown.
set -e
cd "$(dirname "$0")"

# The widget was org.projecthamster.plasmoid before the fork had its own
# names; a panel that has it must get the new one added again.
remove_legacy_widget() {
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx 'org.projecthamster.plasmoid'; then
        kpackagetool6 --type Plasma/Applet --remove org.projecthamster.plasmoid || true
        echo "Removed the old widget (org.projecthamster.plasmoid); add the new one to your panel."
    fi
}

if [ "$1" = "--uninstall" ]; then
    scripts/install-backend.sh --uninstall
    kpackagetool6 --type Plasma/Applet --remove io.github.HamsterProjekt.plasmoid || true
    remove_legacy_widget
    exit 0
fi

scripts/install-backend.sh "$@"
remove_legacy_widget
kpackagetool6 --type Plasma/Applet --upgrade plasmoid 2>/dev/null \
    || kpackagetool6 --type Plasma/Applet --install plasmoid
echo
echo "Now right-click a panel, choose 'Add or Manage Widgets', and add 'Hamster Time Tracker'."
