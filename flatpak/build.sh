#!/bin/sh
# Builds the Flatpak of Hamster for KDE (io.github.HamsterProjekt.HamsterKDE)
# and installs it for the current user. The Hamster service in it comes from
# the main branch of https://github.com/HamsterProjekt/hamster, unless a local
# checkout is given.
#
#   flatpak/build.sh                    build and install
#   flatpak/build.sh PATH               take the Hamster service from the
#                                       checkout at PATH (e.g. ../hamster)
#   flatpak/build.sh --bundle           also write hamster-kde.flatpak, a single
#                                       file that installs elsewhere with
#                                       `flatpak install --user hamster-kde.flatpak`
#   flatpak/build.sh --no-install       build only (with --bundle: what CI does)
#
# Needs flatpak-builder (`sudo apt install flatpak-builder`, or
# `flatpak install flathub org.flatpak.Builder`) and the Flathub remote, which
# is added for your user if it is missing. The first build downloads the KDE
# SDK and the PyQt base application (about 2 GB). Nothing is written into this
# repository except the bundle: the build goes to ~/.cache/hamster-kde-flatpak,
# or to $FLATPAK_WORK if set.
set -e
id=io.github.HamsterProjekt.HamsterKDE
here="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$here/flatpak/$id.yml"
work="${FLATPAK_WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/hamster-kde-flatpak}"
bundle_file="$here/hamster-kde.flatpak"

bundle=no
install=yes
hamster=
for argument in "$@"; do
    case "$argument" in
        --bundle) bundle=yes ;;
        --no-install) install=no ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "Unknown option: $argument (see --help)" >&2; exit 2 ;;
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

mkdir -p "$work"
if [ -n "$hamster" ]; then
    hamster="$(cd "$hamster" && pwd)"
    if [ ! -f "$hamster/src/hamster/storage/markdown.py" ]; then
        echo "No Markdown storage in $hamster (expected src/hamster/storage/markdown.py)" >&2
        exit 1
    fi
    # the git source of Hamster becomes the checkout, and the path of this
    # repository absolute, as the manifest is used from another folder
    sed -e "s|^\( *\)- type: git\$|\1- type: dir|" \
        -e "s|url: https://github.com/HamsterProjekt/hamster.git\$|path: $hamster|" \
        -e "/^ *branch: main\$/d" \
        -e "s|path: \.\.\$|path: $here|" \
        "$manifest" > "$work/$id.yml"
    manifest="$work/$id.yml"
    echo "Hamster service from $hamster"
fi

if ! flatpak remotes --user --columns=name | grep -qx flathub; then
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
fi

set -- --user --install-deps-from=flathub --force-clean \
    --state-dir="$work/state" --repo="$work/repo"
if [ "$install" = yes ]; then
    set -- "$@" --install
fi
$builder "$@" "$work/build" "$manifest"

if [ "$bundle" = yes ]; then
    flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
        "$work/repo" "$bundle_file" "$id"
    echo "Bundle written to $bundle_file"
fi
if [ "$install" = yes ]; then
    echo
    echo "Installed. Start it with:   flatpak run $id"
    echo "For the Plasma widget:      scripts/install-flatpak-widget.sh"
fi
