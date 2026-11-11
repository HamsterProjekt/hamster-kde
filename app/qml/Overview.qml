// SPDX-License-Identifier: GPL-3.0-or-later
// Activities of a day, week, month or any range, with totals.
// Port of hamster/overview.py.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "lib.js" as Lib

QQC2.ApplicationWindow {
    id: window

    readonly property int dayStart: settings ? settings.dayStartMinutes : 330

    // "day", "week", "month" or "custom"; first and last are hamster days
    property string span: "day"
    property var first: Lib.today(dayStart)
    property var last: Lib.today(dayStart)

    property var facts: []
    // one entry per fact: {fact, firstOfDay}
    property var rows: []
    property var now: new Date()
    property bool tracking: false
    property bool showDetails: false
    property string problem: ""
    // where the last report went
    property string exported: ""

    readonly property var stats: Lib.totals(facts, now)
    readonly property var palette: ["#93cfb1", "#8fc7d4", "#e6c27a", "#d99a9a", "#b5a6d9",
                                    "#a9cf83", "#d9a6cf", "#9db4e0"]
    readonly property real dayColumnWidth: Kirigami.Units.gridUnit * 6.5

    title: qsTr("Hamster Time Tracker")
    width: Kirigami.Units.gridUnit * 44
    height: Kirigami.Units.gridUnit * 34
    minimumWidth: Kirigami.Units.gridUnit * 30
    minimumHeight: Kirigami.Units.gridUnit * 18
    visible: true

    Backend {
        id: backend
        onFactsChanged: window.reload()
        onFailed: message => window.problem = message
    }

    Component.onCompleted: reload()
    onDayStartChanged: reload()

    Timer {
        // elapsed time of the ongoing activity, and midnight
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: window.reload()
    }

    function reload() {
        backend.getFacts(first, last, searchField.visible ? searchField.text.trim() : "", list => {
            const selected = factList.currentIndex >= 0 && factList.currentIndex < rows.length
                ? rows[factList.currentIndex].fact.id : 0;
            const built = [];
            let previousDay = null;
            let select = -1;
            for (const fact of list) {
                const day = Lib.hday(fact.start, dayStart);
                built.push({ fact: fact, firstOfDay: !Lib.sameDay(day, previousDay) });
                previousDay = day;
                if (fact.id === selected)
                    select = built.length - 1;
            }
            now = new Date();
            facts = list;
            rows = built;
            factList.currentIndex = select;
            problem = "";
        });
        const day = Lib.today(dayStart);
        backend.getFacts(day, day, "", list => {
            tracking = list.length > 0 && !list[list.length - 1].end;
        });
    }

    // --- the range shown ---

    function showSpan(newSpan, day) {
        span = newSpan;
        if (span === "week") {
            const offset = (day.getDay() - Qt.locale().firstDayOfWeek + 7) % 7;
            first = Lib.addDays(day, -offset);
            last = Lib.addDays(first, 6);
        } else if (span === "month") {
            first = new Date(day.getFullYear(), day.getMonth(), 1);
            last = new Date(day.getFullYear(), day.getMonth() + 1, 0);
        } else {
            first = day;
            last = day;
        }
        reload();
    }

    function showRange(from, to) {
        span = "custom";
        first = from <= to ? from : to;
        last = from <= to ? to : from;
        reload();
    }

    function step(direction) {
        if (span === "month") {
            showSpan("month", new Date(first.getFullYear(), first.getMonth() + direction, 1));
        } else if (span === "custom") {
            const days = Math.round((last.getTime() - first.getTime()) / 86400000) + 1;
            showRange(Lib.addDays(first, direction * days), Lib.addDays(last, direction * days));
        } else {
            showSpan(span, Lib.addDays(first, direction * (span === "week" ? 7 : 1)));
        }
    }

    function rangeTitle() {
        const locale = Qt.locale();
        if (span === "day")
            return first.toLocaleDateString(locale, "MMMM d, yyyy");
        if (span === "month")
            return first.toLocaleDateString(locale, "MMMM yyyy");
        const sameYear = first.getFullYear() === last.getFullYear();
        return first.toLocaleDateString(locale, sameYear ? "MMM d" : "MMM d, yyyy")
            + " – " + last.toLocaleDateString(locale, "MMM d, yyyy");
    }

    // --- actions on the selected fact ---

    function selectedFact() {
        return factList.currentIndex >= 0 && factList.currentIndex < rows.length
            ? rows[factList.currentIndex].fact : null;
    }

    function editSelected() {
        const fact = selectedFact();
        if (fact)
            app.edit(fact.id);
    }

    function removeSelected() {
        const fact = selectedFact();
        if (fact)
            backend.removeFact(fact.id);
    }

    function continueSelected() {
        const fact = selectedFact();
        if (!fact)
            return;
        const current = new Date();
        backend.addFact({
            activity: fact.activity, category: fact.category,
            description: fact.description, tags: fact.tags,
            start: new Date(current.getFullYear(), current.getMonth(), current.getDate(),
                            current.getHours(), current.getMinutes()),
            end: null
        });
    }

    // --- reports ---

    readonly property var reportFormats: ["html", "tsv", "xml", "ical"]

    // write what is shown (the range, narrowed by the search) to a file
    function exportReport(format, file) {
        const list = facts.map(fact => ({
            id: fact.id, activity: fact.activity, category: fact.category,
            description: fact.description, tags: fact.tags,
            start: Lib.formatDateTime(fact.start),
            end: fact.end ? Lib.formatDateTime(fact.end) : null
        }));
        const result = settings.exportReport(format, file, JSON.stringify(list),
                                             Lib.formatDate(first), Lib.formatDate(last));
        exported = result.ok ? result.path : "";
        exportedMessage.visible = result.ok;
        problem = result.ok ? "" : result.message;
        return result;
    }

    FileDialog {
        id: reportDialog
        title: qsTr("Save Report")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("HTML Report (*.html *.htm)"), qsTr("Tab-Separated Values (*.tsv *.txt)"),
                      qsTr("XML (*.xml)"), qsTr("iCal (*.ics)")]
        onAccepted: {
            const index = selectedNameFilter.index;
            const result = window.exportReport(window.reportFormats[index >= 0 ? index : 0],
                                               selectedFile.toString());
            // as Hamster does: show the report
            if (result.ok)
                Qt.openUrlExternally("file://" + result.path);
        }
    }

    QQC2.Action {
        id: exportAction
        text: qsTr("Export…")
        icon.name: "document-export"
        shortcut: "Ctrl+E"
        enabled: window.facts.length > 0
        onTriggered: {
            reportDialog.currentFolder = "file://" + settings.reportFolder;
            reportDialog.selectedFile = "file://" + settings.reportFolder + "/"
                + settings.reportName(Lib.formatDate(window.first), Lib.formatDate(window.last));
            reportDialog.open();
        }
    }

    function plain(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
    }

    QQC2.Action {
        id: addAction
        text: qsTr("Add Activity")
        icon.name: "list-add"
        shortcut: "Ctrl+N"
        onTriggered: app.edit(0)
    }
    QQC2.Action {
        id: stopAction
        text: qsTr("Stop Tracking")
        icon.name: "media-playback-stop"
        enabled: window.tracking
        onTriggered: backend.stopTracking()
    }
    QQC2.Action {
        id: searchAction
        text: qsTr("Search")
        icon.name: "edit-find"
        shortcut: "Ctrl+F"
        checkable: true
        onToggled: {
            if (checked)
                searchField.forceActiveFocus();
            else
                window.reload();
        }
    }
    QQC2.Action {
        shortcut: "Alt+Left"
        onTriggered: window.step(-1)
    }
    QQC2.Action {
        shortcut: "Alt+Right"
        onTriggered: window.step(1)
    }

    header: QQC2.ToolBar {
        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true

                QQC2.ToolButton {
                    icon.name: "go-previous"
                    text: qsTr("Previous")
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: window.step(-1)
                }
                QQC2.ToolButton {
                    icon.name: "go-next"
                    text: qsTr("Next")
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                    onClicked: window.step(1)
                }
                QQC2.ToolButton {
                    text: window.rangeTitle() + "  ▾"
                    font.bold: true
                    onClicked: rangeMenu.popup(this, 0, height)

                    QQC2.Menu {
                        id: rangeMenu
                        QQC2.MenuItem {
                            text: qsTr("Today")
                            onTriggered: window.showSpan("day", Lib.today(window.dayStart))
                        }
                        QQC2.MenuSeparator {}
                        QQC2.MenuItem {
                            text: qsTr("Day")
                            onTriggered: window.showSpan("day", window.first)
                        }
                        QQC2.MenuItem {
                            text: qsTr("Week")
                            onTriggered: window.showSpan("week", window.first)
                        }
                        QQC2.MenuItem {
                            text: qsTr("Month")
                            onTriggered: window.showSpan("month", window.first)
                        }
                        QQC2.MenuSeparator {}
                        QQC2.MenuItem {
                            text: qsTr("Other Range…")
                            onTriggered: {
                                rangeFrom.show(window.first);
                                rangeTo.show(window.last);
                                rangeDialog.open();
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                QQC2.ToolButton {
                    action: addAction
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                }
                QQC2.ToolButton {
                    action: stopAction
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                }
                QQC2.ToolButton {
                    action: searchAction
                    display: QQC2.AbstractButton.IconOnly
                    QQC2.ToolTip.text: text
                    QQC2.ToolTip.visible: hovered
                }
                QQC2.ToolButton {
                    icon.name: "application-menu"
                    text: qsTr("Menu")
                    display: QQC2.AbstractButton.IconOnly
                    onClicked: mainMenu.popup(this, 0, height)

                    QQC2.Menu {
                        id: mainMenu
                        QQC2.MenuItem {
                            action: exportAction
                        }
                        QQC2.MenuItem {
                            text: qsTr("Tracking Settings…")
                            icon.name: "configure"
                            onTriggered: app.preferences()
                        }
                    }
                }
            }

            QQC2.TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                visible: searchAction.checked
                placeholderText: qsTr("Search activities, categories, descriptions and tags")
                onTextEdited: searchTimer.restart()
                Keys.onEscapePressed: {
                    text = "";
                    searchAction.checked = false;
                    window.reload();
                }

                Timer {
                    id: searchTimer
                    interval: 300
                    onTriggered: window.reload()
                }
            }
        }
    }

    QQC2.Dialog {
        id: rangeDialog
        title: qsTr("Show activities")
        anchors.centerIn: parent
        modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onAccepted: {
            if (rangeFrom.date && rangeTo.date)
                window.showRange(rangeFrom.date, rangeTo.date);
        }

        GridLayout {
            columns: 2
            QQC2.Label {
                text: qsTr("From:")
            }
            DateField {
                id: rangeFrom
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            }
            QQC2.Label {
                text: qsTr("To:")
            }
            DateField {
                id: rangeTo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            }
        }
    }

    QQC2.Menu {
        id: factMenu
        QQC2.MenuItem {
            text: qsTr("Edit…")
            icon.name: "document-edit"
            onTriggered: window.editSelected()
        }
        QQC2.MenuItem {
            text: qsTr("Continue Now")
            icon.name: "media-playback-start"
            onTriggered: window.continueSelected()
        }
        QQC2.MenuItem {
            text: qsTr("Delete")
            icon.name: "edit-delete"
            onTriggered: window.removeSelected()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            text: window.problem
            visible: window.problem !== ""
        }
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Positive
            id: exportedMessage
            text: qsTr("Report saved to %1").arg(window.exported)
            visible: false
            showCloseButton: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Kirigami.Theme.backgroundColor

            // the day column runs down the whole list
            Rectangle {
                width: window.dayColumnWidth
                height: parent.height
                color: Kirigami.Theme.alternateBackgroundColor
            }

            QQC2.ScrollView {
                anchors.fill: parent

                ListView {
                    id: factList
                    clip: true
                    focus: true
                    model: window.rows
                    currentIndex: -1
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds

                    Keys.onReturnPressed: window.editSelected()
                    Keys.onEnterPressed: window.editSelected()
                    Keys.onDeletePressed: window.removeSelected()

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property var fact: modelData.fact
                        readonly property bool selected: ListView.isCurrentItem

                        width: ListView.view.width
                        height: content.implicitHeight + Kirigami.Units.smallSpacing * 2

                        Rectangle {
                            x: window.dayColumnWidth
                            width: parent.width - x
                            height: parent.height
                            color: Kirigami.Theme.highlightColor
                            opacity: row.selected ? 0.25 : hover.hovered ? 0.08 : 0
                        }

                        QQC2.Label {
                            visible: row.modelData.firstOfDay
                            x: Kirigami.Units.smallSpacing
                            y: Kirigami.Units.smallSpacing
                            width: window.dayColumnWidth - Kirigami.Units.smallSpacing * 3
                            horizontalAlignment: Text.AlignRight
                            font.bold: true
                            textFormat: Text.PlainText
                            text: Lib.hday(row.fact.start, window.dayStart)
                                .toLocaleDateString(Qt.locale(), "dddd\nMMM d")
                        }

                        RowLayout {
                            id: content
                            x: window.dayColumnWidth + Kirigami.Units.smallSpacing
                            y: Kirigami.Units.smallSpacing
                            width: parent.width - x - Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing

                            QQC2.Label {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: timeMetrics.width
                                textFormat: Text.PlainText
                                font.features: { "tnum": 1 }
                                text: Lib.formatTime(row.fact.start) + " - "
                                    + (row.fact.end ? Lib.formatTime(row.fact.end) : "")
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    QQC2.Label {
                                        textFormat: Text.PlainText
                                        text: row.fact.activity
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: content.width * 0.55
                                    }
                                    QQC2.Label {
                                        // also when empty: it takes the rest of the line
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: row.fact.category ? "- " + row.fact.category : ""
                                        opacity: 0.6
                                        elide: Text.ElideRight
                                    }
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    visible: row.fact.tags.length > 0
                                    spacing: Kirigami.Units.smallSpacing
                                    Repeater {
                                        model: row.fact.tags
                                        Rectangle {
                                            required property string modelData
                                            radius: 3
                                            color: Kirigami.Theme.disabledTextColor
                                            implicitWidth: tagLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                                            implicitHeight: tagLabel.implicitHeight + 2
                                            QQC2.Label {
                                                id: tagLabel
                                                anchors.centerIn: parent
                                                textFormat: Text.PlainText
                                                text: parent.modelData
                                                font: Kirigami.Theme.smallFont
                                                color: Kirigami.Theme.backgroundColor
                                            }
                                        }
                                    }
                                }

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    visible: row.fact.description !== ""
                                    textFormat: Text.PlainText
                                    text: row.fact.description
                                    wrapMode: Text.Wrap
                                    font.italic: true
                                    opacity: 0.7
                                }
                            }

                            QQC2.Label {
                                Layout.alignment: Qt.AlignTop
                                textFormat: Text.PlainText
                                text: Lib.formatDuration(Lib.minutes(row.fact, window.now))
                            }
                        }

                        HoverHandler {
                            id: hover
                        }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (point, button) => {
                                factList.currentIndex = row.index;
                                factList.forceActiveFocus();
                                if (button === Qt.RightButton)
                                    factMenu.popup();
                            }
                            onDoubleTapped: (point, button) => {
                                if (button === Qt.LeftButton)
                                    app.edit(row.fact.id);
                            }
                        }
                    }

                    TextMetrics {
                        id: timeMetrics
                        font.features: { "tnum": 1 }
                        text: "00:00 - 00:00"
                    }
                }
            }

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - window.dayColumnWidth * 2
                visible: window.rows.length === 0
                icon.name: "chronometer"
                text: searchField.visible && searchField.text.trim() !== ""
                    ? qsTr("Nothing found") : qsTr("No activities")
                helpfulAction: addAction
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // totals; click to show or hide the breakdown
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: totalsColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
            visible: window.facts.length > 0

            TapHandler {
                onTapped: window.showDetails = !window.showDetails
            }

            ColumnLayout {
                id: totalsColumn
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    text: "<b>" + qsTr("Total:") + "</b> " + Lib.formatDuration(window.stats.total) + "; "
                        + window.stats.categories.map(row => "<b>"
                            + window.plain(row.name || qsTr("Unsorted")) + ":</b> "
                            + Lib.formatDuration(row.minutes)).join(", ")
                }

                // share of each category
                Row {
                    id: stackedBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                    spacing: 1
                    Repeater {
                        model: window.stats.categories
                        Rectangle {
                            required property var modelData
                            required property int index
                            height: stackedBar.height
                            width: window.stats.total > 0
                                ? (stackedBar.width - (window.stats.categories.length - 1))
                                  * modelData.minutes / window.stats.total
                                : 0
                            color: window.palette[index % window.palette.length]
                            QQC2.ToolTip.text: (modelData.name || qsTr("Unsorted")) + ": "
                                + Lib.formatDuration(modelData.minutes)
                            QQC2.ToolTip.visible: barHover.hovered
                            HoverHandler {
                                id: barHover
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: window.showDetails
                    spacing: Kirigami.Units.gridUnit * 2

                    Repeater {
                        model: [window.stats.activities, window.stats.categories, window.stats.tags]

                        // one bar per activity, category or tag
                        ColumnLayout {
                            id: chart
                            required property var modelData
                            readonly property int largest: modelData.length ? modelData[0].minutes : 0
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: 2

                            Repeater {
                                model: chart.modelData.slice(0, 12)
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing
                                    QQC2.Label {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 3
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideMiddle
                                        textFormat: Text.StyledText
                                        text: window.plain(parent.modelData.name || qsTr("Unsorted"))
                                            + ", <i>" + Lib.formatDurationClock(parent.modelData.minutes) + "</i>"
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.9
                                        Rectangle {
                                            height: parent.height
                                            width: chart.largest > 0
                                                ? Math.max(2, parent.width * parent.parent.modelData.minutes / chart.largest)
                                                : 0
                                            color: Kirigami.Theme.disabledTextColor
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
