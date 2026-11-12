// SPDX-License-Identifier: GPL-3.0-or-later
// Shown when the Hamster service that answers is not the expected one:
// another installation's (the Hamster Flatpak with the GTK windows, say),
// or one that uses another folder than the settings. See hamsterbus.py.

import QtQuick
import org.kde.kirigami as Kirigami

Kirigami.InlineMessage {
    type: Kirigami.MessageType.Warning
    text: bus.storageProblem
    visible: bus.storageProblem !== ""
    actions: [
        Kirigami.Action {
            text: qsTr("Use This Application's Service")
            icon.name: "view-refresh"
            visible: bus.canUseOwnService
            onTriggered: bus.useOwnService()
        }
    ]
}
