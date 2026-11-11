#!/bin/sh
# Headless check of the plasmoid's D-Bus layer against the mock service,
# on a private session bus. Needs PyQt6 and dbus-python.
cd "$(dirname "$0")/.." || exit 1
exec dbus-run-session -- sh -c '
python3 tests/mock_hamster_service.py &
mock=$!
sleep 1
QT_QPA_PLATFORM=offscreen python3 - <<PY
import sys
from PyQt6.QtCore import QUrl
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine
app = QGuiApplication(sys.argv)
engine = QQmlApplicationEngine()
engine.quit.connect(app.quit)
engine.load(QUrl.fromLocalFile("tests/qml/backend_test.qml"))
if not engine.rootObjects():
    sys.exit(1)
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
