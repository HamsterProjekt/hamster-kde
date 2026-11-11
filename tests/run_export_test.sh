#!/bin/sh
# Exports the week shown in the overview in every format, through the
# window, against a real Hamster service with Markdown storage on a private
# bus with sample data. Nothing of yours is touched.
#
#   tests/run_export_test.sh HAMSTER_CHECKOUT WORK_DIR
cd "$(dirname "$0")/.." || exit 1
HAMSTER="$(cd "${1:?path to the hamster checkout}" && pwd)"
OUT="${2:?work directory}"
rm -rf "$OUT"
mkdir -p "$OUT/schemas" "$OUT/md" "$OUT/data" "$OUT/config" "$OUT/reports"
OUT="$(cd "$OUT" && pwd)"
cp "$HAMSTER/data/org.gnome.hamster.gschema.xml" "$OUT/schemas/" && glib-compile-schemas "$OUT/schemas"

today=$(date +%Y-%m-%d)
cat > "$OUT/md/$(date +%Y-%m).md" <<MD
# $(date +%Y-%m)

## $today

- 08:30 - 09:00 reading news@Day-to-day, #breakfast
- 09:12 - 11:37 Super secret project X@Work, #domination #local
  Several lines of description,
  to see how they are shown.
- 11:38 - 12:20 Lunch@Day-to-day, #food #good
- 12:21 - 12:50 gardening
MD

export HAMSTER OUT
export XDG_DATA_HOME="$OUT/data" XDG_CONFIG_HOME="$OUT/config"
export GSETTINGS_SCHEMA_DIR="$OUT/schemas" GSETTINGS_BACKEND=keyfile NO_AT_BRIDGE=1
export HAMSTER_STORAGE=markdown HAMSTER_MARKDOWN_DIR="$OUT/md"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
exec dbus-run-session -- sh -c '
python3 "$HAMSTER/src/hamster-service.py" > "$OUT/service.log" 2>&1 &
sleep 2
r="$OUT/reports"
failures=0
check() {  # check DESCRIPTION COMMAND...
    what="$1"; shift
    if "$@" > /dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}

# the format comes from the filter, or from the extension typed
python3 tests/app_shot.py Overview "$OUT/exported.png" "w.showSpan(\"week\", w.first)" "
    w.exportReport(\"html\", \"file://$r/week\");
    w.exportReport(\"tsv\", \"$r/week\");
    w.exportReport(\"xml\", \"$r/week\");
    w.exportReport(\"html\", \"$r/week.ics\");
    console.log(w.exportReport(\"ical\", \"$r/week\").message)" > "$OUT/app.log" 2>&1

check "four files, named after their format" sh -c "[ \"\$(ls \"$r\" | tr \"\\n\" \" \")\" = \"week.html week.ics week.tsv week.xml \" ]"
check "html: the activities" grep -q "<td>Super secret project X</td>" "$r/week.html"
check "html: several lines of description" grep -q "Several lines of description,<br />to see" "$r/week.html"
check "html: nothing left to fill in" sh -c "! grep -qE \"[$][a-z_]{3,}\" \"$r/week.html\""
check "tsv: header and four activities, one over two lines" sh -c "[ \"\$(wc -l < \"$r/week.tsv\")\" = 6 ]"
check "tsv: a row" grep -q "^Lunch	$(date +%Y-%m-%d) 11:38	$(date +%Y-%m-%d) 12:20	42.0	Day-to-day		food, good" "$r/week.tsv"
check "tsv: no category is Unsorted" grep -q "^gardening	.*	29.0	Unsorted		.\?$" "$r/week.tsv"
check "xml: well formed, four activities" python3 -c "
import sys, xml.dom.minidom
assert len(xml.dom.minidom.parse(sys.argv[1]).getElementsByTagName(\"activity\")) == 4" "$r/week.xml"
check "ical: four events" sh -c "[ \"\$(grep -c BEGIN:VEVENT \"$r/week.ics\")\" = 4 ]"
check "ical: times" grep -q "^DTSTART:$(date +%Y%m%d)T091200" "$r/week.ics"
check "the existing .ics was not replaced unasked" grep -q "already exists" "$OUT/app.log"
check "the folder is remembered" grep -q "last-report-folder=.$r.$" "$OUT/config/glib-2.0/settings/keyfile"

# what was started on this bus would stay
for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$$" ] && continue
    [ -O "$p" ] || continue
    if tr "\\0" "\\n" < "$p/environ" 2>/dev/null | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"; then
        kill "$pid" 2>/dev/null
    fi
done 2>/dev/null
echo "$failures failure(s); reports in $r, picture and app.log in $OUT"
[ "$failures" = 0 ]
'
