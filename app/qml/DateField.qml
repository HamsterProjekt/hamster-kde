// SPDX-License-Identifier: GPL-3.0-or-later
// A date as text (YYYY-MM-DD), with a calendar to pick from.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "lib.js" as Lib

RowLayout {
    id: field

    // null when empty; unchanged while the text is not a date
    property var date: null
    property bool allowEmpty: false
    readonly property bool valid: (allowEmpty && input.text.trim() === "") || Lib.parseDate(input.text) !== null
    // the user changed the date
    signal edited()

    spacing: 0

    function show(value) {
        date = value;
        input.text = value ? Lib.formatDate(value) : "";
    }

    QQC2.TextField {
        id: input
        Layout.fillWidth: true
        placeholderText: field.allowEmpty ? "" : "YYYY-MM-DD"
        Accessible.name: qsTr("Date")
        onTextEdited: {
            const parsed = Lib.parseDate(text);
            if (parsed || (field.allowEmpty && text.trim() === "")) {
                field.date = parsed;
                field.edited();
            }
        }
    }

    QQC2.ToolButton {
        icon.name: "view-calendar"
        text: qsTr("Pick a date")
        display: QQC2.AbstractButton.IconOnly
        onClicked: {
            const shown = field.date || new Date();
            grid.year = shown.getFullYear();
            grid.month = shown.getMonth();
            popup.open();
        }

        QQC2.Popup {
            id: popup
            y: parent.height
            x: parent.width - width
            padding: Kirigami.Units.smallSpacing

            ColumnLayout {
                RowLayout {
                    QQC2.ToolButton {
                        icon.name: "go-previous"
                        onClicked: {
                            const previous = new Date(grid.year, grid.month - 1, 1);
                            grid.year = previous.getFullYear();
                            grid.month = previous.getMonth();
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: new Date(grid.year, grid.month, 1).toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    }
                    QQC2.ToolButton {
                        icon.name: "go-next"
                        onClicked: {
                            const next = new Date(grid.year, grid.month + 1, 1);
                            grid.year = next.getFullYear();
                            grid.month = next.getMonth();
                        }
                    }
                }
                QQC2.DayOfWeekRow {
                    Layout.fillWidth: true
                    locale: grid.locale
                }
                QQC2.MonthGrid {
                    id: grid
                    Layout.fillWidth: true
                    locale: Qt.locale()
                    delegate: QQC2.ItemDelegate {
                        required property var model
                        readonly property bool chosen: Lib.sameDay(model.date, field.date)
                        implicitWidth: Kirigami.Units.gridUnit * 2
                        implicitHeight: Kirigami.Units.gridUnit * 2
                        enabled: model.month === grid.month
                        highlighted: chosen
                        contentItem: QQC2.Label {
                            text: model.day
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: model.today
                            opacity: enabled ? 1 : 0.3
                            color: chosen ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                        }
                        onClicked: {
                            // MonthGrid dates are UTC midnights
                            field.show(new Date(model.year, model.month, model.day));
                            field.edited();
                            popup.close();
                        }
                    }
                }
            }
        }
    }
}
