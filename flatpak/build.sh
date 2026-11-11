#!/bin/sh
# Builds the Flatpak and installs it for the current user.
#
#   flatpak/build.sh [path-to-hamster-checkout]   (default: ../hamster, as in the manifest)
#   flatpak/build.sh --bundle                     also writes hamster-kde.flatpak, to
#                                                 install elsewhere with `flatpak install`
#
# Needs flatpak-builder (`sudo apt install flatpak-builder`, or
# `flatpak install flathub org.flatpak.Builder`) and the Flathub remote.
# The first build downloads the KDE SDK and the PyQt base application
# (about 2 GB). Nothing is written into this repository: the build goes to
# ~/.cache/hamster-kde-flatpak.
set -e
id=org.projecthamster.HamsterKDE
here="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$here/flatpak/$id.yml"
work="${XDG_CACHE_HOME:-$HOME/.cache}/hamster-kde-flatpak"

bundle=no
hamster=
for argument in "$@"; do
    case "$argument" in
        --bundle) bundle=yes ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) hamster="$argument" ;;
    esac
done

if command -v flatpak-builder > /dev/null; then
    builder=flatpak-builder
elif flatpak info org.flatpak.Builder > /dev/null 2>&1; then
    builder="flatpak run org.flatpak.Builder"
else
    echo "flatpak-builder is not installed. Either of:" >&2
    echo "    sudo apt install flatpak-builder" >&2
    echo "    flatpak install flathub org.flatpak.Builder" >&2
    exit 1
fi

if [ -n "$hamster" ]; then
    # the manifest names the checkout next to this repository
    hamster="$(cd "$hamster" && pwd)"
    mkdir -p "$work"
    sed "s|path: \.\./\.\./hamster\$|path: $hamster|; s|path: \.\.\$|path: $here|" \
        "$manifest" > "$work/$id.yml"
    manifest="$work/$id.yml"
else
    hamster="$here/../hamster"
fi
if [ ! -f "$hamster/src/hamster/storage/markdown.py" ]; then
    echo "No Markdown storage in $hamster (expected src/hamster/storage/markdown.py)" >&2
    exit 1
fi

if ! flatpak remotes --columns=name | grep -qx flathub; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

$builder --user --install --install-deps-from=flathub --force-clean \
    --state-dir="$work/state" --repo="$work/repo" "$work/build" "$manifest"

if [ "$bundle" = yes ]; then
    flatpak build-bundle "$work/repo" "$here/hamster-kde.flatpak" "$id"
    echo "Bundle written to $here/hamster-kde.flatpak"
fi
echo
echo "Installed. Start it with:   flatpak run $id"
echo "For the Plasma widget:      scripts/install-flatpak-widget.sh"
