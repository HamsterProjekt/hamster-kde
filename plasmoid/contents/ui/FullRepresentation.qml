// SPDX-License-Identifier: GPL-3.0-or-later
// The popup: entry field, today's activities, totals and actions.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "../code/stuff.js" as Stuff

ColumnLayout {
    id: full

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14
    Layout.preferredWidth: Kirigami.Units.gridUnit * 26
    Layout.preferredHeight: Kirigami.Units.gridUnit * 24

    spacing: Kirigami.Units.smallSpacing

    function durationText(fact) {
        return Stuff.formatDurationHuman(Stuff.delta(fact, hamster.now)) || i18n("Just started");
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded) {
                entry.forceActiveFocus();
                factList.positionViewAtEnd();
            }
        }
    }

    PlasmaComponents.Label {
        text: i18n("What are you doing?")
        font.bold: true
    }

    PlasmaComponents.TextField {
        id: entry

        // Length of what the user typed themselves, without the completion.
        property int typedLength: 0

        Layout.fillWidth: true
        focus: true
        placeholderText: i18n("activity@category,, description, #tag")

        // Inline completion: the suggested rest of the activity is selected,
        // so typing on replaces it and Enter accepts it.
        onTextEdited: {
            const typed = text;
            const grew = typed.length > typedLength;
            typedLength = typed.length;
            if (!grew || cursorPosition !== typed.length)
                return;
            const completed = Stuff.complete(typed, hamster.activities);
            if (completed) {
                text = completed;
                select(typed.length, completed.length);
            }
        }

        onAccepted: {
            const fact = text.trim();
            if (!fact)
                return;
            hamster.addFact(fact);
            text = "";
            typedLength = 0;
            root.expanded = false;
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        type: Kirigami.MessageType.Error
        text: hamster.lastError
        visible: hamster.lastError.length > 0
    }

    PlasmaComponents.Label {
        text: i18n("Today's activities")
        font.bold: true
        Layout.topMargin: Kirigami.Units.smallSpacing
    }

    PlasmaComponents.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
            id: factList

            clip: true
            model: hamster.facts
            onCountChanged: positionViewAtEnd()

            delegate: RowLayout {
                id: row

                required property var modelData
                readonly property bool isOngoing: !modelData.endTime
                readonly property bool canContinue: !Stuff.sameActivity(modelData, hamster.ongoing)

                width: ListView.view.width
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: Stuff.timeRange(row.modelData)
                    textFormat: Text.PlainText
                    font.features: { "tnum": 1 }
                    opacity: 0.7
                    Layout.preferredWidth: timeMetrics.width
                }

                PlasmaComponents.Label {
                    text: row.modelData.name
                        + (row.modelData.tags.length ? " #" + row.modelData.tags.join(" #") : "")
                    textFormat: Text.PlainText
                    font.bold: row.isOngoing
                    elide: Text.ElideRight
                    Layout.fillWidth: true

                    PlasmaComponents.ToolTip.visible: truncated && hover.hovered
                    PlasmaComponents.ToolTip.text: text
                    HoverHandler {
                        id: hover
                    }
                }

                PlasmaComponents.Label {
                    text: full.durationText(row.modelData)
                    textFormat: Text.PlainText
                    opacity: 0.7
                }

                PlasmaComponents.ToolButton {
                    icon.name: "document-edit"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Edit")
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.text: text
                    onClicked: {
                        hamster.editFact(row.modelData.id);
                        root.expanded = false;
                    }
                }

                // Kept in the layout when hidden so the columns stay aligned.
                PlasmaComponents.ToolButton {
                    icon.name: "media-playback-start"
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: i18n("Continue")
                    opacity: row.canContinue ? 1 : 0
                    enabled: row.canContinue
                    PlasmaComponents.ToolTip.visible: hovered
                    PlasmaComponents.ToolTip.text: text
                    onClicked: {
                        hamster.continueFact(row.modelData);
                        root.expanded = false;
                    }
                }
            }

            TextMetrics {
                id: timeMetrics
                font.features: { "tnum": 1 }
                text: "00:00 – 00:00"
            }

            PlasmaExtras.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 2
                visible: factList.count === 0
                iconName: hamster.available ? "chronometer" : "dialog-warning"
                text: hamster.available
                    ? i18n("No activities today")
                    : i18n("The Hamster service is not running")
                explanation: hamster.available
                    ? ""
                    : i18n("Install the Hamster time tracker, or start its service.")
            }
        }
    }

    PlasmaComponents.Label {
        visible: root.showSummary && hamster.facts.length > 0
        text: Stuff.categoryTotals(hamster.facts, hamster.now).map(total =>
            (total.category || i18n("Unsorted")) + ": " + Stuff.formatDurationHours(total.seconds)
        ).join(", ")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        opacity: 0.7
        Layout.fillWidth: true
    }

    PlasmaComponents.Label {
        visible: hamster.facts.length > 0
        text: i18n("Total: %1", Stuff.formatDurationHuman(Stuff.totalSeconds(hamster.facts, hamster.now)) || "0min")
        textFormat: Text.PlainText
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Button {
            text: i18n("Stop Tracking")
            icon.name: "media-playback-stop"
            enabled: hamster.ongoing !== null
            onClicked: {
                hamster.stopTracking();
                root.expanded = false;
            }
        }

        PlasmaComponents.Button {
            text: i18n("Add Earlier Activity")
            icon.name: "list-add"
            onClicked: {
                hamster.editFact(0);
                root.expanded = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        PlasmaComponents.ToolButton {
            icon.name: "view-calendar-timeline"
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Show Overview")
            PlasmaComponents.ToolTip.visible: hovered
            PlasmaComponents.ToolTip.text: text
            onClicked: {
                hamster.showOverview();
                root.expanded = false;
            }
        }

        PlasmaComponents.ToolButton {
            icon.name: "configure"
            display: PlasmaComponents.AbstractButton.IconOnly
            text: i18n("Tracking Settings")
            PlasmaComponents.ToolTip.visible: hovered
            PlasmaComponents.ToolTip.text: text
            onClicked: {
                hamster.showPreferences();
                root.expanded = false;
            }
        }
    }
}
