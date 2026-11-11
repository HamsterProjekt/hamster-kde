// SPDX-License-Identifier: GPL-3.0-or-later
// What sits in the panel: icon and/or "activity 01:23".

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

MouseArea {
    id: compact

    // 0 = label, 1 = icon, 2 = icon and label (same values as the GNOME extension)
    readonly property int appearance: root.panelAppearance
    readonly property bool vertical: root.vertical
    // A vertical panel has no room for text.
    readonly property bool showLabel: !vertical && appearance !== 1
    readonly property bool showIcon: vertical || appearance !== 0

    Layout.minimumWidth: vertical ? 0 : row.implicitWidth
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: vertical ? Infinity : Layout.minimumWidth
    Layout.minimumHeight: vertical ? width : 0

    hoverEnabled: true
    onClicked: root.expanded = !root.expanded

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            visible: compact.showIcon
            source: root.stateIcon
            isMask: true
            Layout.fillHeight: true
            Layout.fillWidth: compact.vertical
            Layout.preferredWidth: compact.vertical ? -1 : height
        }

        PlasmaComponents.Label {
            visible: compact.showLabel
            text: root.panelText
            textFormat: Text.PlainText
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            Layout.fillHeight: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 16
            Layout.rightMargin: Kirigami.Units.smallSpacing
        }
    }
}
