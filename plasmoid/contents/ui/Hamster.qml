// SPDX-License-Identifier: GPL-3.0-or-later
// Talks to the Hamster D-Bus services (io.github.HamsterProjekt.Hamster and
// io.github.HamsterProjekt.Hamster.WindowServer). Any backend that implements those
// interfaces works, whatever it stores its facts in.

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

import "../code/stuff.js" as Stuff

Item {
    id: hamster

    // True once the service has answered; false after a failed call.
    property bool available: false
    // Today's facts, oldest first (see Stuff.factFromJson for the shape).
    property var facts: []
    // The fact being tracked right now, or null.
    property var ongoing: null
    // [{name, category}] for autocompletion.
    property var activities: []
    // Updated on every refresh so durations of the ongoing fact recompute.
    property date now: new Date()
    // Last failure, as text for the user; cleared by the next success.
    property string lastError: ""

    readonly property string apiService: "io.github.HamsterProjekt.Hamster"
    readonly property string apiPath: "/io/github/HamsterProjekt/Hamster"
    readonly property string windowService: "io.github.HamsterProjekt.Hamster.WindowServer"
    readonly property string windowPath: "/io/github/HamsterProjekt/Hamster/WindowServer"

    function call(service, path, member, signature, args, onSuccess, what) {
        const message = {
            "service": service,
            "path": path,
            "iface": service,
            "member": member
        };
        if (signature) {
            message.signature = signature;
            message.arguments = args;
        }
        DBus.SessionBus.asyncCall(message, reply => {
            if (service === apiService)
                available = true;
            if (onSuccess)
                onSuccess(reply.value);
        }, reply => {
            if (service === apiService)
                available = false;
            const detail = reply && reply.error ? reply.error.message : "";
            lastError = detail ? what + ": " + detail : what;
            console.warn("Hamster:", lastError);
        });
    }

    function api(member, signature, args, onSuccess, what) {
        call(apiService, apiPath, member, signature, args, onSuccess, what);
    }

    function windows(member, signature, args, what) {
        call(windowService, windowPath, member, signature, args, null, what);
    }

    function refresh() {
        api("GetTodaysFactsJSON", "", [], value => {
            const list = [];
            for (const text of (value || [])) {
                try {
                    list.push(Stuff.factFromJson(text));
                } catch (e) {
                    console.warn("Hamster: cannot read fact:", e, text);
                }
            }
            const last = list.length ? list[list.length - 1] : null;
            now = new Date();
            facts = list;
            ongoing = last && !last.endTime ? last : null;
            lastError = "";
        }, i18n("Could not get today's activities"));
    }

    function refreshActivities() {
        api("GetActivities", "(s)", [""], value => {
            const list = [];
            for (const row of (value || []))
                list.push({ name: String(row[0]), category: String(row[1] || "") });
            activities = list;
        }, i18n("Could not get the activity list"));
    }

    // `text` uses hamster's own syntax:
    //   [start[-end]] activity[@category][,, description][, #tag #tag]
    function addFact(text) {
        api("AddFact", "(siib)",
            [text, new DBus.int32(0), new DBus.int32(0), new DBus.bool(false)],
            () => refresh(), i18n("Could not add the activity"));
    }

    function continueFact(fact) {
        addFact(Stuff.serialize(fact));
    }

    function stopTracking() {
        // 0 means "now" to the service
        api("StopTracking", "(i)", [new DBus.int32(0)], () => refresh(),
            i18n("Could not stop tracking"));
    }

    function showOverview() {
        windows("overview", "", [], i18n("Could not open the overview window"));
    }

    function showPreferences() {
        windows("preferences", "", [], i18n("Could not open the settings window"));
    }

    // id 0 opens the "add earlier activity" window
    function editFact(id) {
        windows("edit", "(i)", [new DBus.int32(id)], i18n("Could not open the edit window"));
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: hamster.apiService
        path: hamster.apiPath
        iface: hamster.apiService

        function dbusFactsChanged() {
            hamster.refresh();
        }
        function dbusTagsChanged() {
            hamster.refresh();
        }
        function dbusActivitiesChanged() {
            hamster.refreshActivities();
        }
    }

    // Catches the service being started or restarted behind our back.
    DBus.DBusServiceWatcher {
        busType: DBus.BusType.Session
        watchedService: hamster.apiService
        onRegisteredChanged: {
            if (registered) {
                hamster.refresh();
                hamster.refreshActivities();
            } else {
                hamster.available = false;
            }
        }
    }

    // Keeps the elapsed time current and picks up the day rollover.
    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: hamster.refresh()
    }

    Component.onCompleted: {
        // The service is D-Bus activated, so these calls also start it.
        refresh();
        refreshActivities();
    }
}
