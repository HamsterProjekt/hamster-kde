#!/bin/sh
# Installs everything for the current user: the Plasma widget and the
# Hamster services with Markdown storage. No root needed.
#
#   ./install.sh [path-to-hamster-checkout]    (default: ../hamster)
#   ./install.sh --uninstall                   (keeps your Markdown files)
set -e
cd "$(dirname "$0")"

if [ "$1" = "--uninstall" ]; then
    scripts/install-backend.sh --uninstall
    kpackagetool6 --type Plasma/Applet --remove org.projecthamster.plasmoid || true
    exit 0
fi

scripts/install-backend.sh "$@"
kpackagetool6 --type Plasma/Applet --upgrade plasmoid 2>/dev/null \
    || kpackagetool6 --type Plasma/Applet --install plasmoid
echo
echo "Now right-click a panel, choose 'Add or Manage Widgets', and add 'Hamster Time Tracker'."
