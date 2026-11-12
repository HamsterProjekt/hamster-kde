#!/bin/sh
# Plays a sync client (OneDrive, Dropbox, ...) delivering a month file that
# was changed on another computer, and checks that the running Hamster
# service tells its clients and reports the new current activity. Runs on a
# private bus with its own files. Nothing of yours is touched.
#
#   tests/run_sync_test.sh HAMSTER_CHECKOUT WORK_DIR
cd "$(dirname "$0")/.." || exit 1
HAMSTER="$(cd "${1:?path to the hamster checkout}" && pwd)"
OUT="${2:?work directory}"
rm -rf "$OUT"
mkdir -p "$OUT/schemas" "$OUT/md"
OUT="$(cd "$OUT" && pwd)"
cp "$HAMSTER/data/io.github.HamsterProjekt.Hamster.gschema.xml" "$OUT/schemas/" && glib-compile-schemas "$OUT/schemas"

export HAMSTER OUT
export GSETTINGS_SCHEMA_DIR="$OUT/schemas" GSETTINGS_BACKEND=memory
export HAMSTER_STORAGE=markdown HAMSTER_MARKDOWN_DIR="$OUT/md"
exec dbus-run-session -- sh -c '
month="$OUT/md/$(date +%Y-%m).md"
failures=0
check() {  # check DESCRIPTION COMMAND...
    what="$1"; shift
    if "$@" > /dev/null 2>&1; then echo "ok    $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}
current() {
    python3 tests/current_activity.py
}
# wait_signal SECONDS: a FactsChanged signal within that time, counted from the last call of mark
mark() { : > "$OUT/signals.log"; }
wait_signal() {
    n=0
    while [ $n -lt $(($1 * 10)) ]; do
        grep -q "member=FactsChanged" "$OUT/signals.log" && return 0
        sleep 0.1; n=$((n + 1))
    done
    return 1
}

python3 "$HAMSTER/src/hamster-service.py" > "$OUT/service.log" 2>&1 &
sleep 2
dbus-monitor --session "type=signal,interface=io.github.HamsterProjekt.Hamster" > "$OUT/signals.log" 2>/dev/null &
sleep 0.5

dbus-send --session --print-reply --dest=io.github.HamsterProjekt.Hamster /io/github/HamsterProjekt/Hamster \
    io.github.HamsterProjekt.Hamster.AddFact string:"writing@Work" int32:0 int32:0 boolean:false > /dev/null
check "tracking here" [ "$(current)" = writing ]
start=$(sed -n "s/^- \([0-9:]*\) writing@Work.*/\1/p" "$month")
now=$(date +%H:%M)

# 1. the other computer switched tasks; the sync client puts the new file
#    in place of the old one (written elsewhere, then renamed)
mark
sed "s/^- $start writing@Work/- $start - $now writing@Work\n- $now meeting@Work/" "$month" > "$OUT/md/.incoming"
mv "$OUT/md/.incoming" "$month"
check "replaced file: clients are told within 3 s" wait_signal 3
check "replaced file: the other computer s activity is the current one" [ "$(current)" = meeting ]

# 2. the same, with a client that writes into the existing file
mark
sleep 1
sed "s/^- $now meeting@Work/- $now - $now meeting@Work\n- $now review@Work/" "$month" > "$OUT/incoming"
cat "$OUT/incoming" > "$month"
check "file written in place: clients are told within 3 s" wait_signal 3
check "file written in place: the current activity follows" [ "$(current)" = review ]

# 3. tracking was stopped on the other computer
mark
sleep 1
sed "s/^- $now review@Work/- $now - $now review@Work/" "$month" > "$OUT/md/.incoming"
mv "$OUT/md/.incoming" "$month"
check "stopped elsewhere: clients are told" wait_signal 3
check "stopped elsewhere: nothing is tracked here" [ "$(current)" = - ]

# 4. a month that this service never read (first file of a new month arriving)
mark
printf "# 2020-03\n\n## 2020-03-02\n\n- 09:00 - 10:00 old@Work\n" > "$OUT/incoming"
cp "$OUT/incoming" "$OUT/md/2020-03.md"
check "a new month file: clients are told" wait_signal 3

# 5. what Hamster writes itself is not taken for a change from outside
mark
sleep 1
dbus-send --session --print-reply --dest=io.github.HamsterProjekt.Hamster /io/github/HamsterProjekt/Hamster \
    io.github.HamsterProjekt.Hamster.AddFact string:"local@Work" int32:0 int32:0 boolean:false > /dev/null
sleep 1.5
check "own write: one signal, not two" [ "$(grep -c member=FactsChanged "$OUT/signals.log")" = 1 ]
check "each change was reported once" [ "$(grep -c "modified externally" "$OUT/service.log")" = 4 ]

for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$$" ] && continue
    [ -O "$p" ] || continue
    if tr "\\0" "\\n" < "$p/environ" 2>/dev/null | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"; then
        kill "$pid" 2>/dev/null
    fi
done 2>/dev/null
echo "$failures failure(s); logs in $OUT"
[ "$failures" = 0 ]
'
