#!/bin/sh
# Renders the app's windows against a real Hamster service with Markdown
# storage, on a private bus, with sample data. Nothing of yours is touched.
#
#   tests/run_app_test.sh HAMSTER_CHECKOUT OUTPUT_DIR
cd "$(dirname "$0")/.." || exit 1
HAMSTER="$(cd "${1:?path to the hamster checkout}" && pwd)"
OUT="${2:?output directory}"
mkdir -p "$OUT/schemas" "$OUT/md"
cp "$HAMSTER/data/org.gnome.hamster.gschema.xml" "$OUT/schemas/" && glib-compile-schemas "$OUT/schemas"

today=$(date +%Y-%m-%d)
yesterday=$(date -d yesterday +%Y-%m-%d)
cat > "$OUT/md/$(date +%Y-%m).md" <<MD
# $(date +%Y-%m)

## $yesterday

- 09:00 - 12:00 World domination@Work, #domination #global
- 13:00 - 14:30 Watering flowers@Day-to-day

## $today

- 08:30 - 09:00 reading news@Day-to-day, #breakfast
- 09:12 - 11:37 Super secret project X@Work, #domination #local
  Several lines of description,
  to see how they are shown.
- 11:38 - 12:20 Lunch@Day-to-day, #food #good #joe
- 12:21 - 14:30 World domination@Work, #domination #global
- 14:30 - 14:50 Checking stocks@Work, quick look, #fun
- 14:50 - 15:10 gardening
MD

export HAMSTER OUT
export GSETTINGS_SCHEMA_DIR="$OUT/schemas" GSETTINGS_BACKEND=memory NO_AT_BRIDGE=1
export HAMSTER_STORAGE=markdown HAMSTER_MARKDOWN_DIR="$OUT/md"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
exec dbus-run-session -- sh -c '
python3 "$HAMSTER/src/hamster-service.py" > "$OUT/service.log" 2>&1 &
service=$!
sleep 2
{
python3 tests/app_shot.py Overview "$OUT/overview.png"
python3 tests/app_shot.py Overview "$OUT/overview-week.png" "w.showDetails = true; w.showSpan(\"week\", w.first)"
python3 tests/app_shot.py EditFact "$OUT/edit.png"
python3 tests/app_shot.py AddFact "$OUT/add.png"
python3 tests/app_shot.py Preferences "$OUT/preferences.png"
# type a new activity on the command line and save it
python3 tests/app_shot.py AddFact "$OUT/typed.png" \
    "w.commandText = \"16:00 - 16:45 testing@Work, a note, #qt\"; w.readCommandLine()" "w.save()"
# change an existing one through its fields
python3 tests/app_shot.py EditFact "$OUT/edited.png" \
    "var f = w.fact; f.description = \"two\\nlines\"; f.tags = [\"breakfast\", \"early\"]; w.fact = f; w.showFields(); w.check()" "w.save()"
python3 tests/app_shot.py Overview "$OUT/overview-after.png"
} > "$OUT/app.log" 2>&1
kill $service
for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$$" ] && continue
    [ -O "$p" ] || continue
    if tr "\\0" "\\n" < "$p/environ" 2>/dev/null | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"; then
        kill "$pid" 2>/dev/null
    fi
done 2>/dev/null
'
