#!/bin/sh
# Checks the Flatpak manifest as far as that goes without building it: runs
# the install commands of its two own modules into a directory, as
# flatpak-builder would into /app, and starts Hamster from there on a
# private bus. The runtime and the bundled libraries are not tested by this.
#
#   tests/run_flatpak_layout_test.sh HAMSTER_CHECKOUT WORK_DIR
cd "$(dirname "$0")/.." || exit 1
HAMSTER="$(cd "${1:?path to the hamster checkout}" && pwd)"
OUT="${2:?work directory}"
rm -rf "$OUT"
mkdir -p "$OUT/app" "$OUT/home/data" "$OUT/home/config"
OUT="$(cd "$OUT" && pwd)"
ID=io.github.HamsterProjekt.HamsterKDE

# the build commands of a module, one per line
commands() {
    python3 - "flatpak/$ID.yml" "$1" <<'PY'
import sys, yaml
manifest = yaml.safe_load(open(sys.argv[1]))
module = next(m for m in manifest["modules"] if m["name"] == sys.argv[2])
print("\n".join(module["build-commands"]))
PY
}
export FLATPAK_DEST="$OUT/app" FLATPAK_ID="$ID"
commands hamster > "$OUT/hamster.sh"
(cd "$HAMSTER" && sh -e "$OUT/hamster.sh") 2> "$OUT/hamster-install.log" \
    || { echo "FAIL  the hamster module does not install, see $OUT/hamster-install.log"; exit 1; }
commands hamster-kde > "$OUT/hamster-kde.sh"
sh -e "$OUT/hamster-kde.sh" || { echo "FAIL  the hamster-kde module does not install"; exit 1; }
# the wrappers name /app
sed -i "s|/app/|$OUT/app/|g" "$OUT/app/bin/hamster-kde" "$OUT/app/bin/hamster-service"

# another installation that D-Bus can start, as the Hamster Flatpak with the
# GTK windows is: a service with the SQLite database
mkdir -p "$OUT/home/data/dbus-1/services"
printf '[D-BUS Service]\nName=io.github.HamsterProjekt.Hamster\nExec=/usr/bin/env HAMSTER_STORAGE=sqlite %s %s\n' \
    "$(command -v python3)" "$HAMSTER/src/hamster-service.py" \
    > "$OUT/home/data/dbus-1/services/io.github.HamsterProjekt.Hamster.service"

export OUT ID HAMSTER
export XDG_DATA_HOME="$OUT/home/data" XDG_CONFIG_HOME="$OUT/home/config"
export XDG_DATA_DIRS="$OUT/app/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GSETTINGS_BACKEND=keyfile NO_AT_BRIDGE=1
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HAMSTER_STORAGE HAMSTER_MARKDOWN_DIR GSETTINGS_SCHEMA_DIR
exec dbus-run-session -- sh -c '
failures=0
check() {  # check DESCRIPTION COMMAND...
    what="$1"; shift
    if "$@" > /dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}
owner() {
    dbus-send --session --print-reply --dest=org.freedesktop.DBus / \
        org.freedesktop.DBus.NameHasOwner string:"$1" | grep -q "boolean true"
}
hamster() {  # hamster METHOD [ARGUMENTS...]
    method="$1"; shift
    dbus-send --session --print-reply --dest=io.github.HamsterProjekt.Hamster /io/github/HamsterProjekt/Hamster \
        io.github.HamsterProjekt.Hamster."$method" "$@" 2>&1
}
wait_for() {  # wait_for markdown|sqlite: until the service that answers has that storage
    n=0
    while [ $n -lt 100 ]; do
        hamster GetStorage | grep -q "\"$1\"" && return 0
        sleep 0.1; n=$((n + 1))
    done
    return 1
}
app="$OUT/app"

check "what the manifest installs is there" test -x "$app/bin/hamster-kde" -a -x "$app/bin/hamster-service" \
    -a -f "$app/lib/hamster/hamster/storage/markdown.py" -a -f "$app/lib/hamster-kde/qml/Overview.qml" \
    -a -f "$app/lib/hamster-kde/report_template.html" -a -f "$app/share/glib-2.0/schemas/gschemas.compiled" \
    -a -f "$app/share/applications/$ID.desktop" -a -f "$app/share/metainfo/$ID.metainfo.xml" \
    -a -f "$app/share/icons/hicolor/scalable/apps/$ID.svg"
check "desktop file" desktop-file-validate "$app/share/applications/$ID.desktop"
check "its program and icon are the installed ones" sh -c "grep -q \"^Exec=hamster-kde \" \"$app/share/applications/$ID.desktop\" && grep -qx \"Icon=$ID\" \"$app/share/applications/$ID.desktop\""
check "the storage folder setting is in the schema" grep -q markdown-directory "$app/share/glib-2.0/schemas/io.github.HamsterProjekt.Hamster.gschema.xml"
check "nothing of the tests or of git is installed" sh -c "! find \"$app\" -name tests -o -name .git | grep -q ."

# D-Bus could start the service of the other installation; the windows start their own
check "no service yet" sh -c "! dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.NameHasOwner string:io.github.HamsterProjekt.Hamster | grep -q \"boolean true\""
PATH="$app/bin:$PATH" FLATPAK_ID="$ID" hamster-kde overview > "$OUT/windows.log" 2>&1 &
windows=$!
n=0
while [ $n -lt 80 ] && ! owner io.github.HamsterProjekt.Hamster.WindowServer; do sleep 0.1; n=$((n + 1)); done
check "the windows start" owner io.github.HamsterProjekt.Hamster.WindowServer
n=0
while [ $n -lt 100 ] && ! owner io.github.HamsterProjekt.Hamster; do sleep 0.1; n=$((n + 1)); done
check "they started the service" owner io.github.HamsterProjekt.Hamster
dbus-send --session --print-reply --dest=io.github.HamsterProjekt.Hamster /io/github/HamsterProjekt/Hamster \
    io.github.HamsterProjekt.Hamster.AddFact string:"packaging@Work" int32:0 int32:0 boolean:false > /dev/null 2>&1
check "the service is the Markdown one, writing to the data directory" \
    grep -q "packaging@Work" "$XDG_DATA_HOME/hamster/markdown/$(date +%Y-%m).md"
check "not the one D-Bus would have started" sh -c "! test -e \"$XDG_DATA_HOME/hamster/hamster.db\""

# stopped (as when the folder is changed): the windows start theirs again,
# before a call has D-Bus start the other one
hamster Quit > /dev/null
n=0
while [ $n -lt 50 ] && owner io.github.HamsterProjekt.Hamster; do sleep 0.1; n=$((n + 1)); done
n=0
while [ $n -lt 100 ] && ! owner io.github.HamsterProjekt.Hamster; do sleep 0.1; n=$((n + 1)); done
check "after a stop, the windows bring back their service" wait_for markdown
check "it says it is installed (no git needed for its version)" sh -c "cd / && PYTHONPATH=\"$app/lib/hamster\" python3 -c \"import hamster; assert hamster.installed, hamster.__version__\""
sleep 2
check "the windows are still running" kill -0 $windows
check "no QML errors" sh -c "! grep -iE \"qml.*(error|is not a type|not installed|unavailable)|Traceback\" \"$OUT/windows.log\""
# a second start hands over to the first and returns
check "a second start hands over" sh -c "PATH=\"$app/bin:\$PATH\" timeout 10 hamster-kde prefs"
kill $windows 2>/dev/null
wait $windows 2>/dev/null

# the other installation answers when the windows start: they say so,
# and put theirs in its place when asked
hamster Quit > /dev/null
n=0
while [ $n -lt 50 ] && owner io.github.HamsterProjekt.Hamster; do sleep 0.1; n=$((n + 1)); done
check "the other service runs" wait_for sqlite
PATH="$app/bin:$PATH" FLATPAK_ID="$ID" python3 tests/app_shot.py Overview "$OUT/other-service.png" \
    "console.log(\"problem: \" + bus.storageProblem + \" own: \" + bus.canUseOwnService); bus.useOwnService()" \
    "console.log(\"afterwards: [\" + bus.storageProblem + \"]\")" > "$OUT/other-service.log" 2>&1
check "the windows warn about it" grep -q "problem: Another Hamster service is answering: it keeps the activities in the database" "$OUT/other-service.log"
check "and offer their own service" grep -q "own: true" "$OUT/other-service.log"
check "which then answers" wait_for markdown
check "and the warning is gone" grep -qF "afterwards: []" "$OUT/other-service.log"

for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$$" ] && continue
    [ -O "$p" ] || continue
    if tr "\\0" "\\n" < "$p/environ" 2>/dev/null | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"; then
        kill "$pid" 2>/dev/null
    fi
done 2>/dev/null
echo "$failures failure(s); the installed tree is in $OUT/app, logs in $OUT"
[ "$failures" = 0 ]
'
