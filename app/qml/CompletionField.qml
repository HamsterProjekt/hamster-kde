// SPDX-License-Identifier: GPL-3.0-or-later
// A text field that lists the candidates matching what is typed.
//
// Typing opens the list, Down opens it without typing. Up and Down choose,
// Enter or Tab takes the chosen one, Escape closes the list only.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "lib.js" as Lib

QQC2.TextField {
    id: field

    // [{label, detail}], the most wanted first; the detail is shown next to
    // the label and is not searched
    property var candidates: []
    // the candidates listed now
    property var matches: []
    readonly property bool suggesting: popup.visible

    // a candidate was taken from the list; the text is its label already
    signal picked(var candidate)

    function suggest() {
        matches = Lib.suggest(text, candidates, 50);
        list.currentIndex = -1;
        if (matches.length === 0) {
            popup.close();
            return;
        }
        // above the field when there is too little room below it
        const top = field.mapToItem(null, 0, 0).y;
        const below = (field.Window.window ? field.Window.window.height : 0) - top - field.height;
        popup.above = below < Kirigami.Units.gridUnit * 5 && top > below;
        popup.room = popup.above ? top : below;
        popup.open();
    }

    function pick(index) {
        const candidate = matches[index];
        popup.close();
        text = candidate.label;
        picked(candidate);
    }

    onTextEdited: suggest()
    onActiveFocusChanged: {
        if (!activeFocus)
            popup.close();
    }

    // Escape closes the list, not the window
    Keys.onShortcutOverride: event => {
        event.accepted = popup.visible && event.key === Qt.Key_Escape;
    }
    Keys.onPressed: event => {
        const chosen = popup.visible && list.currentIndex >= 0;
        if (event.key === Qt.Key_Down) {
            if (popup.visible)
                list.currentIndex = Math.min(list.currentIndex + 1, list.count - 1);
            else
                suggest();
            event.accepted = true;
        } else if (event.key === Qt.Key_Up && popup.visible) {
            list.currentIndex = Math.max(list.currentIndex - 1, -1);
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && chosen) {
            pick(list.currentIndex);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && popup.visible) {
            popup.close();
            event.accepted = true;
        } else if (event.key === Qt.Key_Tab && chosen) {
            pick(list.currentIndex);   // and on to the next field
        }
    }

    QQC2.Popup {
        id: popup

        property bool above: false
        // height available on that side of the field
        property real room: 0

        y: above ? -height : field.height
        width: field.width
        height: Math.min(list.contentHeight + topPadding + bottomPadding,
                         Kirigami.Units.gridUnit * 10, Math.max(room, Kirigami.Units.gridUnit * 2))
        padding: 1
        focus: false
        closePolicy: QQC2.Popup.CloseOnPressOutsideParent

        contentItem: ListView {
            id: list
            clip: true
            model: field.matches
            currentIndex: -1
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            delegate: QQC2.ItemDelegate {
                id: row

                required property var modelData
                required property int index
                readonly property color textColor: highlighted || down
                    ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor

                width: ListView.view.width
                highlighted: ListView.isCurrentItem
                Accessible.name: modelData.detail ? modelData.label + ", " + modelData.detail : modelData.label
                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: row.textColor
                    }
                    QQC2.Label {
                        Layout.maximumWidth: row.width / 2
                        visible: text !== ""
                        text: row.modelData.detail || ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: row.textColor
                        opacity: 0.6
                    }
                }
                onClicked: field.pick(index)
            }
        }
    }
}
