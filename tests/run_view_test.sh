#!/bin/sh
# Renders the plasmoid's views offscreen against the mock service and saves
# a screenshot. Usage: tests/run_view_test.sh [output.png]
cd "$(dirname "$0")/.." || exit 1
OUT="${1:-/tmp/hamster-kde-view.png}"
export OUT
exec dbus-run-session -- sh -c '
python3 tests/mock_hamster_service.py >/dev/null 2>&1 &
mock=$!
sleep 1
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software python3 - <<PY
import os, sys
from PyQt6.QtCore import QUrl, QTimer
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickView
app = QGuiApplication(sys.argv)
view = QQuickView()
view.setResizeMode(QQuickView.ResizeMode.SizeViewToRootObject)
view.setSource(QUrl.fromLocalFile("tests/qml/view_test.qml"))
if view.status() != QQuickView.Status.Ready:
    for e in view.errors():
        print(e.toString(), file=sys.stderr)
    sys.exit(1)
view.show()
def grab():
    ok = view.grabWindow().save(os.environ["OUT"])
    print("saved" if ok else "save failed", os.environ["OUT"])
    app.exit(0 if ok else 1)
QTimer.singleShot(2000, grab)
sys.exit(app.exec())
PY
status=$?
kill $mock
# Stop helper services that D-Bus activated on this private bus; left
# running they outlive the test and keep our output pipe open.
for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$$" ] && continue
    if tr "\\0" "\\n" < "$p/environ" 2>/dev/null | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"; then
        kill "$pid" 2>/dev/null
    fi
done 2>/dev/null
exit $status
'
