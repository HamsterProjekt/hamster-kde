// SPDX-License-Identifier: GPL-3.0-or-later
// Tracking settings: day start, categories and activities, tags.
// Port of hamster/preferences.py.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "lib.js" as Lib

QQC2.ApplicationWindow {
    id: window

    readonly property int unsorted: -1

    // [{id, name}], "Unsorted" first
    property var categories: []
    property var activities: []
    property int categoryId: unsorted
    property string problem: ""
    // what happened when the storage folder was changed
    property string storageNote: ""

    function changeStorage(folder) {
        const result = settings.changeStorageDirectory(folder, copyFiles.checked);
        if (result.ok) {
            storageNote = result.message;
            problem = "";
            // the service restarts with the new folder on this request
            restartTimer.restart();
        } else {
            problem = result.message;
        }
    }

    Timer {
        id: restartTimer
        interval: 700
        onTriggered: {
            window.loadCategories();
            window.loadTags();
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Folder for Hamster's files")
        currentFolder: "file://" + settings.storageDirectory
        onAccepted: window.changeStorage(selectedFolder.toString())
    }

    title: qsTr("Tracking Settings")
    width: Kirigami.Units.gridUnit * 50
    height: Kirigami.Units.gridUnit * 40
    minimumWidth: Kirigami.Units.gridUnit * 48
    minimumHeight: Kirigami.Units.gridUnit * 30
    visible: true

    Backend {
        id: backend
        onActivitiesChanged: window.loadCategories()
        onTagsChanged: window.loadTags()
        onFailed: message => window.problem = message
    }

    Component.onCompleted: {
        dayStartField.text = Lib.formatDurationClock(settings.dayStartMinutes);
        loadCategories();
        loadTags();
    }

    function loadCategories() {
        backend.getCategories(list => {
            categories = [{ id: unsorted, name: qsTr("Unsorted") }].concat(list);
            if (!categories.some(category => category.id === categoryId))
                categoryId = unsorted;
            loadActivities();
        });
    }

    function loadActivities() {
        const asked = categoryId;
        backend.getCategoryActivities(asked, list => {
            if (asked === categoryId)
                activities = list;
        });
    }

    function loadTags() {
        backend.getTags(list => {
            if (!tagsField.activeFocus) {
                tagsField.text = list.filter(tag => tag.autocomplete)
                    .map(tag => tag.name).join(", ");
            }
        });
    }

    function selectedActivity() {
        return activityList.currentIndex >= 0 && activityList.currentIndex < activities.length
            ? activities[activityList.currentIndex] : null;
    }

    function categoryName(id) {
        const found = categories.find(category => category.id === id);
        return found ? found.name : "";
    }

    // asks for a name, then calls accept(name)
    function askName(title, current, accept) {
        nameDialog.title = title;
        nameField.text = current;
        nameDialog.accept_ = accept;
        nameDialog.open();
        nameField.selectAll();
        nameField.forceActiveFocus();
    }

    QQC2.Dialog {
        id: nameDialog
        property var accept_: null
        anchors.centerIn: parent
        modal: true
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel
        onAccepted: {
            const name = nameField.text.trim();
            if (name && accept_)
                accept_(name);
        }
        QQC2.TextField {
            id: nameField
            implicitWidth: Kirigami.Units.gridUnit * 18
            onAccepted: nameDialog.accept()
        }
    }

    QQC2.Action {
        shortcut: "Escape"
        onTriggered: window.close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            type: Kirigami.MessageType.Error
            text: window.problem
            visible: window.problem !== ""
            showCloseButton: true
            onVisibleChanged: {
                if (!visible)
                    window.problem = "";
            }
        }

        Kirigami.Heading {
            level: 4
            text: qsTr("Tracking")
        }
        RowLayout {
            QQC2.Label {
                text: qsTr("New day starts at:")
            }
            QQC2.TextField {
                id: dayStartField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                placeholderText: "HH:MM"
                onEditingFinished: {
                    const time = Lib.parseTime(text);
                    if (time)
                        settings.dayStartMinutes = time.hours * 60 + time.minutes;
                    text = Lib.formatDurationClock(settings.dayStartMinutes);
                }
            }
            QQC2.Label {
                Layout.fillWidth: true
                text: !settings || settings.writable
                    ? qsTr("Earlier activities count as the day before.")
                    : qsTr("Hamster's settings are not installed; this cannot be changed.")
                opacity: 0.7
                wrapMode: Text.Wrap
            }
        }

        Kirigami.Heading {
            level: 4
            text: qsTr("Storage")
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                text: qsTr("Folder:")
            }
            QQC2.TextField {
                Layout.fillWidth: true
                readOnly: true
                text: settings.storageDirectory
            }
            QQC2.Button {
                text: qsTr("Choose…")
                icon.name: "folder-open"
                enabled: settings.storageConfigurable
                onClicked: folderDialog.open()
            }
            QQC2.Button {
                text: qsTr("Use Default")
                icon.name: "edit-undo"
                enabled: settings.storageConfigurable && !settings.storageIsDefault
                onClicked: window.changeStorage("")
            }
        }
        QQC2.CheckBox {
            id: copyFiles
            checked: true
            enabled: settings.storageConfigurable
            text: qsTr("Copy my activities to the new folder (nothing there is overwritten)")
        }
        QQC2.Label {
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.Wrap
            opacity: 0.7
            text: !settings.storageConfigurable
                ? qsTr("Run the installer again to be able to change the folder.")
                : window.storageNote
        }

        Kirigami.Heading {
            level: 4
            text: qsTr("Categories and activities")
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.largeSpacing

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    background: Rectangle {
                        color: Kirigami.Theme.backgroundColor
                        border.color: Kirigami.Theme.disabledTextColor
                    }
                    ListView {
                        id: categoryList
                        clip: true
                        model: window.categories
                        delegate: QQC2.ItemDelegate {
                            required property var modelData
                            width: ListView.view.width
                            text: modelData.name
                            font.italic: modelData.id === window.unsorted
                            highlighted: modelData.id === window.categoryId
                            onClicked: {
                                window.categoryId = modelData.id;
                                activityList.currentIndex = -1;
                                window.loadActivities();
                            }
                        }
                    }
                }
                RowLayout {
                    QQC2.Button {
                        text: qsTr("Add")
                        icon.name: "list-add"
                        onClicked: window.askName(qsTr("New category"), "",
                                                  name => backend.addCategory(name))
                    }
                    QQC2.Button {
                        text: qsTr("Rename")
                        icon.name: "edit-rename"
                        enabled: window.categoryId !== window.unsorted
                        onClicked: window.askName(qsTr("Rename category"),
                                                  window.categoryName(window.categoryId),
                                                  name => backend.renameCategory(window.categoryId, name))
                    }
                    QQC2.Button {
                        text: qsTr("Remove")
                        icon.name: "list-remove"
                        enabled: window.categoryId !== window.unsorted
                        QQC2.ToolTip.text: qsTr("Its activities become unsorted.")
                        QQC2.ToolTip.visible: hovered
                        onClicked: backend.removeCategory(window.categoryId)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    background: Rectangle {
                        color: Kirigami.Theme.backgroundColor
                        border.color: Kirigami.Theme.disabledTextColor
                    }
                    ListView {
                        id: activityList
                        clip: true
                        model: window.activities
                        currentIndex: -1
                        delegate: QQC2.ItemDelegate {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            text: modelData.name
                            highlighted: ListView.isCurrentItem
                            onClicked: activityList.currentIndex = index
                        }
                    }
                }
                RowLayout {
                    QQC2.Button {
                        text: qsTr("Add")
                        icon.name: "list-add"
                        onClicked: window.askName(qsTr("New activity"), "",
                                                  name => backend.addActivity(name, window.categoryId))
                    }
                    QQC2.Button {
                        text: qsTr("Rename")
                        icon.name: "edit-rename"
                        enabled: window.selectedActivity() !== null
                        onClicked: {
                            const activity = window.selectedActivity();
                            window.askName(qsTr("Rename activity"), activity.name,
                                           name => backend.updateActivity(activity.id, name, window.categoryId));
                        }
                    }
                    QQC2.Button {
                        text: qsTr("Remove")
                        icon.name: "list-remove"
                        enabled: window.selectedActivity() !== null
                        QQC2.ToolTip.text: qsTr("Activities already tracked are kept, but no longer suggested.")
                        QQC2.ToolTip.visible: hovered
                        onClicked: backend.removeActivity(window.selectedActivity().id)
                    }
                    QQC2.Button {
                        text: qsTr("Move to")
                        icon.name: "go-jump"
                        enabled: window.selectedActivity() !== null && window.categories.length > 1
                        onClicked: moveMenu.popup(this, 0, height)

                        QQC2.Menu {
                            id: moveMenu
                            Repeater {
                                model: window.categories.filter(category => category.id !== window.categoryId)
                                QQC2.MenuItem {
                                    required property var modelData
                                    text: modelData.name
                                    onTriggered: {
                                        const activity = window.selectedActivity();
                                        backend.updateActivity(activity.id, activity.name, modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Kirigami.Heading {
            level: 4
            text: qsTr("Tags")
        }
        QQC2.Label {
            Layout.fillWidth: true
            text: qsTr("Tags suggested while typing, separated by commas:")
            wrapMode: Text.Wrap
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.TextField {
                id: tagsField
                Layout.fillWidth: true
                onAccepted: backend.setAutocompleteTags(text)
            }
            QQC2.Button {
                text: qsTr("Apply")
                icon.name: "dialog-ok-apply"
                onClicked: backend.setAutocompleteTags(tagsField.text)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item {
                Layout.fillWidth: true
            }
            QQC2.Button {
                text: qsTr("Close")
                icon.name: "window-close"
                onClicked: window.close()
            }
        }
    }
}
