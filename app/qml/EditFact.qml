// SPDX-License-Identifier: GPL-3.0-or-later
// Add or edit one activity. Port of hamster/edit_activity.py.
//
// The command line and the separate fields show the same fact: typing in
// one updates the other.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "lib.js" as Lib

QQC2.ApplicationWindow {
    id: window

    // 0 to add a new fact
    property int factId: 0

    // the fact as it stands (see Lib.parseFact for the shape)
    property var fact: ({ start: null, end: null, activity: "", category: "", description: "", tags: [] })
    property var activities: []
    // facts of the day being edited, for the timeline
    property var dayFacts: []
    // why the fact cannot be saved; empty when it can
    property string problem: ""
    property bool checked: false
    property bool loading: false
    property alias commandText: commandLine.text

    readonly property int dayStart: settings ? settings.dayStartMinutes : 330
    // hamster day that times typed without a date belong to
    readonly property var day: fact.start ? Lib.hday(fact.start, dayStart) : Lib.today(dayStart)

    title: factId ? qsTr("Edit activity") : qsTr("Add activity")
    width: Kirigami.Units.gridUnit * 34
    height: column.implicitHeight + Kirigami.Units.largeSpacing * 4
    minimumWidth: Kirigami.Units.gridUnit * 26
    minimumHeight: column.implicitHeight + Kirigami.Units.largeSpacing * 4
    visible: true

    Backend {
        id: backend
        onFailed: message => window.problem = message
    }

    Component.onCompleted: {
        backend.getActivities(list => activities = list);
        if (factId) {
            backend.getFact(factId, loaded => {
                fact = loaded;
                showFields();
                showCommandLine();
                check();
                activityField.forceActiveFocus();
            }, message => problem = message);
        } else {
            const now = new Date();
            fact = { start: new Date(now.getFullYear(), now.getMonth(), now.getDate(),
                                     now.getHours(), now.getMinutes()),
                     end: null, activity: "", category: "", description: "", tags: [] };
            showFields();
            showCommandLine();
            // ready for the activity to be typed after the time
            commandLine.text += " ";
            commandLine.typedLength = commandLine.text.length;
            commandLine.forceActiveFocus();
        }
    }

    onDayChanged: loadDay()

    function loadDay() {
        backend.getFacts(day, day, "", list => dayFacts = list.filter(other => other.id !== factId));
    }

    // fact -> separate fields
    function showFields() {
        loading = true;
        startTime.text = fact.start ? Lib.formatTime(fact.start) : "";
        startDate.show(fact.start ? Lib.midnight(fact.start) : null);
        endTime.text = fact.end ? Lib.formatTime(fact.end) : "";
        const endOtherDay = fact.end && fact.start
            && !Lib.sameDay(Lib.hday(fact.end, dayStart), Lib.hday(fact.start, dayStart));
        endDate.show(endOtherDay ? Lib.midnight(fact.end) : null);
        activityField.text = fact.activity;
        categoryField.text = fact.category;
        tagsField.text = fact.tags.join(", ");
        if (descriptionField.text !== fact.description)
            descriptionField.text = fact.description;
        loading = false;
    }

    // fact -> command line (the description has its own field)
    function showCommandLine() {
        commandLine.text = Lib.serializeFact(fact, Lib.today(dayStart), dayStart, false);
        commandLine.typedLength = commandLine.text.length;
    }

    // command line -> fact
    function readCommandLine() {
        const parsed = Lib.parseFact(commandLine.text, day, new Date(), dayStart);
        fact = {
            start: parsed.start || fact.start,
            end: parsed.start ? parsed.end : fact.end,
            activity: parsed.activity,
            category: parsed.category,
            description: parsed.description || fact.description,
            tags: parsed.tags
        };
        showFields();
        check();
    }

    // separate fields -> fact
    function readFields() {
        if (loading)
            return;
        let start = null;
        const from = Lib.parseTime(startTime.text);
        if (from && startDate.date) {
            start = new Date(startDate.date.getFullYear(), startDate.date.getMonth(),
                             startDate.date.getDate(), from.hours, from.minutes);
        }
        let end = null;
        const to = Lib.parseTime(endTime.text);
        if (to && endDate.date) {
            end = new Date(endDate.date.getFullYear(), endDate.date.getMonth(),
                           endDate.date.getDate(), to.hours, to.minutes);
        } else if (to && start) {
            // same hamster day as the start
            end = Lib.fromDayTime(Lib.hday(start, dayStart), to.hours, to.minutes, dayStart);
        }
        fact = {
            start: start,
            end: end,
            activity: activityField.text.trim(),
            category: categoryField.text.trim(),
            description: descriptionField.text.trim(),
            tags: Lib.parseTags(tagsField.text)
        };
        showCommandLine();
        check();
    }

    function check() {
        checked = false;
        if (!Lib.parseTime(startTime.text) || !startDate.valid || !fact.start) {
            problem = qsTr("The start is missing or is not a time.");
        } else if (endTime.text.trim() !== "" && !Lib.parseTime(endTime.text)) {
            problem = qsTr("The end is not a time.");
        } else if (!endDate.valid) {
            problem = qsTr("The end date is not a date.");
        } else if (!fact.activity) {
            problem = qsTr("The activity is missing.");
        } else {
            problem = "";
            checkTimer.restart();
        }
    }

    // the service has the last word (overnight facts, forbidden characters…)
    Timer {
        id: checkTimer
        interval: 250
        onTriggered: {
            const asked = Lib.factToJson(window.fact);
            backend.checkFact(window.fact, (ok, message) => {
                if (asked !== Lib.factToJson(window.fact))
                    return;   // edited meanwhile
                window.problem = ok ? "" : message;
                window.checked = ok;
            });
        }
    }

    function save() {
        const done = () => window.close();
        const failed = message => problem = message;
        if (factId)
            backend.updateFact(factId, fact, done, failed);
        else
            backend.addFact(fact, done, failed);
    }

    QQC2.Action {
        shortcut: "Escape"
        onTriggered: window.close()
    }
    QQC2.Action {
        shortcut: "Ctrl+Return"
        enabled: saveButton.enabled
        onTriggered: window.save()
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        // the day at a glance: other activities in grey, this one highlighted
        Item {
            id: timeline
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5

            readonly property var begin: Lib.dayBegin(window.day, window.dayStart)

            function position(moment) {
                const fraction = (moment.getTime() - begin.getTime()) / (24 * 3600 * 1000);
                return Math.max(0, Math.min(1, fraction)) * width;
            }

            QQC2.Label {
                anchors.left: parent.left
                anchors.bottom: bar.top
                text: window.day.toLocaleDateString(Qt.locale(), "dddd, MMMM d")
                font: Kirigami.Theme.smallFont
            }

            Rectangle {
                id: bar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Kirigami.Units.gridUnit * 0.8
                height: Kirigami.Units.gridUnit * 0.6
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Kirigami.Theme.disabledTextColor
                border.width: 1
            }

            Repeater {
                model: window.dayFacts
                Rectangle {
                    required property var modelData
                    x: timeline.position(modelData.start)
                    y: bar.y
                    height: bar.height
                    width: Math.max(1, timeline.position(modelData.end || new Date()) - x)
                    color: Kirigami.Theme.disabledTextColor
                }
            }

            Rectangle {
                visible: window.fact.start !== null
                x: visible ? timeline.position(window.fact.start) : 0
                y: bar.y - 2
                height: bar.height + 4
                width: visible ? Math.max(2, timeline.position(window.fact.end || new Date()) - x) : 0
                color: Kirigami.Theme.highlightColor
                opacity: 0.8
            }

            Repeater {
                model: 7   // every four hours
                QQC2.Label {
                    required property int index
                    readonly property var moment: Lib.addMinutes(timeline.begin, index * 240)
                    x: Math.min(timeline.width - width, timeline.position(moment))
                    anchors.top: bar.bottom
                    text: Lib.formatTime(moment)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    visible: index < 6
                }
            }
        }

        QQC2.Label {
            text: qsTr("Command line")
            font.bold: true
        }
        QQC2.TextField {
            id: commandLine

            // length of what was typed, without the suggested completion
            property int typedLength: 0

            Layout.fillWidth: true
            placeholderText: qsTr("start - end activity@category, description, #tag")
            onTextEdited: {
                const typed = text;
                const grew = typed.length > typedLength;
                typedLength = typed.length;
                if (grew && cursorPosition === typed.length) {
                    const completed = Lib.complete(typed, window.activities, window.day,
                                                   new Date(), window.dayStart);
                    if (completed) {
                        text = completed;
                        select(typed.length, completed.length);
                    }
                }
                window.readCommandLine();
            }
            onAccepted: {
                if (saveButton.enabled)
                    window.save();
            }
        }

        QQC2.Label {
            text: qsTr("Description")
            font.bold: true
        }
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            QQC2.TextArea {
                id: descriptionField
                wrapMode: TextEdit.Wrap
                KeyNavigation.priority: KeyNavigation.BeforeItem
                KeyNavigation.tab: startTime
                onTextChanged: {
                    if (activeFocus)
                        window.readFields();
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: qsTr("Start")
                font.bold: true
            }
            QQC2.Label {
                text: qsTr("End")
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                QQC2.TextField {
                    id: startTime
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                    placeholderText: "HH:MM"
                    Accessible.name: qsTr("Start time")
                    onTextEdited: window.readFields()
                }
                DateField {
                    id: startDate
                    Layout.fillWidth: true
                    onEdited: window.readFields()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                QQC2.TextField {
                    id: endTime
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                    placeholderText: qsTr("ongoing")
                    Accessible.name: qsTr("End time")
                    onTextEdited: window.readFields()
                }
                DateField {
                    id: endDate
                    Layout.fillWidth: true
                    allowEmpty: true
                    onEdited: window.readFields()
                }
            }

            QQC2.Label {
                text: qsTr("Activity")
                font.bold: true
            }
            QQC2.Label {
                text: qsTr("Category")
                font.bold: true
            }

            QQC2.TextField {
                id: activityField
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onTextEdited: window.readFields()
            }
            QQC2.TextField {
                id: categoryField
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onTextEdited: window.readFields()
            }
        }

        QQC2.Label {
            text: qsTr("Tags")
            font.bold: true
        }
        QQC2.TextField {
            id: tagsField
            Layout.fillWidth: true
            placeholderText: qsTr("separated by commas")
            onTextEdited: window.readFields()
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 2.5
            text: window.problem
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            maximumLineCount: 4
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true

            QQC2.Button {
                text: qsTr("Delete")
                icon.name: "edit-delete"
                visible: window.factId !== 0
                onClicked: backend.removeFact(window.factId, () => window.close())
            }
            Item {
                Layout.fillWidth: true
            }
            QQC2.Button {
                text: qsTr("Cancel")
                icon.name: "dialog-cancel"
                onClicked: window.close()
            }
            QQC2.Button {
                id: saveButton
                text: qsTr("Save")
                icon.name: "document-save"
                enabled: window.problem === "" && window.checked
                highlighted: true
                onClicked: window.save()
            }
        }
    }
}
