#!/bin/sh
# Changes the storage folder in the settings window and checks that the
# Hamster service follows: files copied, new facts written to the new folder,
# and back again with "Use Default". Runs on a private bus with its own data,
# settings and service files. Nothing of yours is touched.
#
#   tests/run_storage_test.sh HAMSTER_CHECKOUT WORK_DIR
cd "$(dirname "$0")/.." || exit 1
HAMSTER="$(cd "${1:?path to the hamster checkout}" && pwd)"
OUT="${2:?work directory}"
rm -rf "$OUT"
mkdir -p "$OUT/data/glib-2.0/schemas" "$OUT/data/dbus-1/services" "$OUT/config" "$OUT/cloud folder"
OUT="$(cd "$OUT" && pwd)"
cp "$HAMSTER/data/org.gnome.hamster.gschema.xml" "$OUT/data/glib-2.0/schemas/" \
    && glib-compile-schemas "$OUT/data/glib-2.0/schemas"
printf '[D-BUS Service]\nName=org.gnome.Hamster\nExec=%s %s\n' \
    "$(command -v python3)" "$HAMSTER/src/hamster-service.py" \
    > "$OUT/data/dbus-1/services/org.gnome.Hamster.service"

export HAMSTER OUT
export XDG_DATA_HOME="$OUT/data" XDG_CONFIG_HOME="$OUT/config"
export GSETTINGS_SCHEMA_DIR="$OUT/data/glib-2.0/schemas" GSETTINGS_BACKEND=keyfile NO_AT_BRIDGE=1
export HAMSTER_STORAGE=markdown
unset HAMSTER_MARKDOWN_DIR
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
exec dbus-run-session -- sh -c '
default="$OUT/data/hamster/markdown"
cloud="$OUT/cloud folder"
month="$(date +%Y-%m).md"
failures=0
check() {  # check DESCRIPTION COMMAND...
    what="$1"; shift
    if "$@" > /dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}
add_fact() {
    dbus-send --session --print-reply --dest=org.gnome.Hamster /org/gnome/Hamster \
        org.gnome.Hamster.AddFact string:"$1" int32:0 int32:0 boolean:false > /dev/null
}

add_fact "08:00 - 09:00 first@Work"
check "a fact goes to the default folder" grep -q "first@Work" "$default/$month"

# an unrelated file, and one that is already in the new folder
echo "mine" > "$default/notes.md"
printf "# Activities\n\n## Elsewhere\n\n- Already here\n" > "$cloud/activities.md"

python3 tests/app_shot.py Preferences "$OUT/moved.png" \
    "w.changeStorage(\"file://$cloud\")" > "$OUT/app.log" 2>&1
check "the month was copied" grep -q "first@Work" "$cloud/$month"
check "the original is still there" grep -q "first@Work" "$default/$month"
check "a file already there is kept" grep -qx -- "- Already here" "$cloud/activities.md"
check "and is not replaced by the copy" sh -c "! grep -q handstands \"$cloud/activities.md\""
check "other files are not copied" test ! -e "$cloud/notes.md"

add_fact "09:00 - 10:00 second@Work"
check "a new fact goes to the new folder" grep -q "second@Work" "$cloud/$month"
check "and not to the old one" sh -c "! grep -q second@Work \"$default/$month\""

python3 tests/app_shot.py Preferences "$OUT/back.png" "w.changeStorage(\"\")" >> "$OUT/app.log" 2>&1
add_fact "10:00 - 11:00 third@Work"
check "Use Default goes back" grep -q "third@Work" "$default/$month"
check "nothing overwritten on the way back" sh -c "! grep -q second@Work \"$default/$month\""

python3 tests/app_shot.py Preferences "$OUT/refused.png" \
    "w.changeStorage(\"/proc/hamster-nowhere\")" >> "$OUT/app.log" 2>&1
add_fact "11:00 - 12:00 fourth@Work"
check "an unusable folder is refused" grep -q "fourth@Work" "$default/$month"

dbus-send --session --dest=org.gnome.Hamster /org/gnome/Hamster org.gnome.Hamster.Quit 2>/dev/null
# what was started on this bus (portals, for the folder dialog) would stay
for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$$" ] && continue
    [ -O "$p" ] || continue
    if tr "\\0" "\\n" < "$p/environ" 2>/dev/null | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"; then
        kill "$pid" 2>/dev/null
    fi
done 2>/dev/null
echo "$failures failure(s); pictures and app.log in $OUT"
[ "$failures" = 0 ]
'
