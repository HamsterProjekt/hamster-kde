// SPDX-License-Identifier: GPL-3.0-or-later
// Plasma port of hamster-shell-extension.

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

import "../code/stuff.js" as Stuff

PlasmoidItem {
    id: root

    readonly property string panelText: hamster.ongoing
        ? hamster.ongoing.name + " " + Stuff.formatDuration(Stuff.delta(hamster.ongoing, hamster.now))
        : i18n("No activity")
    readonly property url stateIcon: Qt.resolvedUrl(hamster.ongoing
        ? "../icons/hamster-tracking-symbolic.svg"
        : "../icons/hamster-idle-symbolic.svg")

    // The views read these instead of the Plasmoid object, so they can be
    // loaded outside Plasma (see tests/).
    readonly property int panelAppearance: Plasmoid.configuration.panelAppearance
    readonly property bool showSummary: Plasmoid.configuration.showSummary
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    Plasmoid.status: hamster.ongoing ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    toolTipMainText: i18n("Hamster Time Tracker")
    toolTipSubText: hamster.available
        ? panelText
        : i18n("The Hamster service is not running")

    Hamster {
        id: hamster
    }

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    onExpandedChanged: expanded => {
        if (expanded)
            hamster.refresh();
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Stop Tracking")
            icon.name: "media-playback-stop"
            enabled: hamster.ongoing !== null
            onTriggered: hamster.stopTracking()
        },
        PlasmaCore.Action {
            text: i18n("Add Earlier Activity…")
            icon.name: "list-add"
            onTriggered: hamster.editFact(0)
        },
        PlasmaCore.Action {
            text: i18n("Show Overview")
            icon.name: "view-calendar-timeline"
            onTriggered: hamster.showOverview()
        },
        PlasmaCore.Action {
            text: i18n("Tracking Settings…")
            icon.name: "configure"
            onTriggered: hamster.showPreferences()
        }
    ]
}
