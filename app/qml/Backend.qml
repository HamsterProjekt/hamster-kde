// SPDX-License-Identifier: GPL-3.0-or-later
// The Hamster service (org.gnome.Hamster) over D-Bus, through `bus`
// (hamsterbus.py).

import QtQuick

import "lib.js" as Lib

Item {
    id: backend

    signal factsChanged()
    signal activitiesChanged()
    signal tagsChanged()
    // a call failed; message is meant for the user
    signal failed(string message)

    // the calls of this object that wait for their answer:
    // id -> {member, onSuccess, onError}
    property var pending: ({})

    // onSuccess(first value returned, all of them) and onError(message) are
    // optional; without onError the failure is reported through failed()
    function call(member, signature, args, onSuccess, onError) {
        const id = bus.call(member, signature || "", args || []);
        pending[id] = { member: member, onSuccess: onSuccess, onError: onError };
    }

    function int32(value) {
        return Math.round(value);
    }

    Connections {
        target: bus

        function onFinished(id, values) {
            const waiting = backend.pending[id];
            if (!waiting)
                return;   // a call of another window
            delete backend.pending[id];
            if (waiting.onSuccess) {
                const list = JSON.parse(values);
                waiting.onSuccess(list.length > 0 ? list[0] : undefined, list);
            }
        }

        function onFailed(id, message) {
            const waiting = backend.pending[id];
            if (!waiting)
                return;
            delete backend.pending[id];
            const text = message || waiting.member;
            console.warn("Hamster:", waiting.member, "failed:", text);
            if (waiting.onError)
                waiting.onError(text);
            else
                backend.failed(text);
        }

        function onFactsChanged() {
            backend.factsChanged();
        }
        function onActivitiesChanged() {
            backend.activitiesChanged();
        }
        function onTagsChanged() {
            backend.tagsChanged();
        }

        // the service came (back): whatever was shown may be out of date
        function onRegisteredChanged() {
            if (bus.registered) {
                backend.factsChanged();
                backend.activitiesChanged();
                backend.tagsChanged();
            }
        }
    }

    // --- facts ---

    // first and last are hamster days (Date at midnight)
    function getFacts(first, last, search, onSuccess) {
        const range = Lib.formatDate(first) + " - " + Lib.formatDate(last);
        call("GetFactsJSON", "(ss)", [range, search || ""],
             value => onSuccess((value || []).map(Lib.factFromJson)));
    }

    function getFact(id, onSuccess, onError) {
        call("GetFactJSON", "(i)", [int32(id)], value => onSuccess(Lib.factFromJson(value)), onError);
    }

    function getActivities(onSuccess) {
        call("GetActivities", "(s)", [""], value => onSuccess((value || []).map(
            row => ({ name: String(row[0]), category: String(row[1] || "") }))));
    }

    // onResult(ok, message)
    function checkFact(fact, onResult) {
        call("CheckFact", "(si)", [Lib.factToJson(fact), int32(0)],
             (value, values) => onResult(!!values[0], String(values[1] || "")),
             message => onResult(false, message));
    }

    function addFact(fact, onSuccess, onError) {
        call("AddFactJSON", "(s)", [Lib.factToJson(fact)], onSuccess, onError);
    }

    function updateFact(id, fact, onSuccess, onError) {
        call("UpdateFactJSON", "(is)", [int32(id), Lib.factToJson(fact)], onSuccess, onError);
    }

    function removeFact(id, onSuccess) {
        call("RemoveFact", "(i)", [int32(id)], onSuccess);
    }

    function stopTracking() {
        call("StopTracking", "(i)", [int32(0)]);   // 0: now
    }

    // --- categories, activities, tags ---

    function getCategories(onSuccess) {
        call("GetCategories", "", [], value => onSuccess((value || []).map(
            row => ({ id: Number(row[0]), name: String(row[1]) }))));
    }

    function getCategoryActivities(categoryId, onSuccess) {
        call("GetCategoryActivities", "(i)", [int32(categoryId)], value => onSuccess((value || []).map(
            row => ({ id: Number(row[0]), name: String(row[1]) }))));
    }

    function addCategory(name, onSuccess) {
        call("AddCategory", "(s)", [name], onSuccess);
    }

    function renameCategory(id, name, onSuccess) {
        call("UpdateCategory", "(is)", [int32(id), name], onSuccess);
    }

    function removeCategory(id, onSuccess) {
        call("RemoveCategory", "(i)", [int32(id)], onSuccess);
    }

    function addActivity(name, categoryId, onSuccess) {
        call("AddActivity", "(si)", [name, int32(categoryId)], onSuccess);
    }

    function updateActivity(id, name, categoryId, onSuccess) {
        call("UpdateActivity", "(isi)", [int32(id), name, int32(categoryId)], onSuccess);
    }

    function removeActivity(id, onSuccess) {
        call("RemoveActivity", "(i)", [int32(id)], onSuccess);
    }

    // [{name, autocomplete}]
    function getTags(onSuccess) {
        call("GetTags", "(b)", [false], value => onSuccess((value || []).map(
            row => ({ name: String(row[1]), autocomplete: !!row[2] }))));
    }

    // comma separated; the other tags are no longer suggested
    function setAutocompleteTags(text, onSuccess) {
        call("SetTagsAutocomplete", "(s)", [text], onSuccess);
    }
}
