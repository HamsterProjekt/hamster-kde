#!/bin/sh
# Packs plasmoid/ into a .plasmoid file (a zip with metadata.json at the top),
# which installs with
#   kpackagetool6 --type Plasma/Applet --install hamster-kde.plasmoid
# or from "Add Widgets… → Get New Widgets → Install Widget From Local File".
#
#   scripts/package-plasmoid.sh [OUTPUT [VERSION]]
#
# OUTPUT defaults to hamster-kde.plasmoid; VERSION, if given, replaces the
# version in metadata.json, so that Plasma sees each release as newer.
set -e
here="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-hamster-kde.plasmoid}" in
    /*) out="${1:-hamster-kde.plasmoid}" ;;
    *) out="$PWD/${1:-hamster-kde.plasmoid}" ;;
esac
version="$2"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$here/plasmoid/." "$work/"
find "$work" -name '__pycache__' -prune -exec rm -rf {} +
if [ -n "$version" ]; then
    python3 - "$work/metadata.json" "$version" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data["KPlugin"]["Version"] = version
with open(path, "w") as f:
    json.dump(data, f, indent=4, ensure_ascii=False)
    f.write("\n")
PY
fi
rm -f "$out"
(cd "$work" && zip -qrX "$out" .)
echo "Wrote $out"
