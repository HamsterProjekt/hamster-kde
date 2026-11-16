// SPDX-License-Identifier: GPL-3.0-or-later
// Checks the completion helpers of app/qml/lib.js:  node tests/lib_test.js
const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");

// lib.js is a QML library: without its pragma, and with its functions
// exported, a copy of it is a module that node can load
const source = fs.readFileSync(path.join(__dirname, "..", "app", "qml", "lib.js"), "utf8")
    .replace(/^\.pragma library$/m, "");
const folder = fs.mkdtempSync(path.join(os.tmpdir(), "hamster-kde-lib-"));
const copy = path.join(folder, "lib.js");
fs.writeFileSync(copy, source + "\nmodule.exports = { suggest, categoryNames };\n");
let Lib;
try {
    Lib = require(copy);
} finally {
    fs.rmSync(folder, { recursive: true });
}

const activities = [
    { label: "Lunch", detail: "Day-to-day" },
    { label: "World domination", detail: "Work" },
    { label: "Watering flowers", detail: "Day-to-day" },
    { label: "Slow lunch", detail: "" },
];
const labels = found => found.map(candidate => candidate.label);

// nothing typed: everything, in the order given
assert.deepStrictEqual(labels(Lib.suggest("", activities, 50)),
                       ["Lunch", "World domination", "Watering flowers", "Slow lunch"]);
// any case; those starting with it before those containing it
assert.deepStrictEqual(labels(Lib.suggest("LUN", activities, 50)), ["Lunch", "Slow lunch"]);
assert.deepStrictEqual(labels(Lib.suggest("w", activities, 50)),
                       ["World domination", "Watering flowers", "Slow lunch"]);
assert.deepStrictEqual(labels(Lib.suggest(" wat ", activities, 50)), ["Watering flowers"]);
assert.deepStrictEqual(labels(Lib.suggest("w", activities, 2)), ["World domination", "Watering flowers"]);
assert.deepStrictEqual(labels(Lib.suggest("zzz", activities, 50)), []);
// the detail is not searched
assert.deepStrictEqual(labels(Lib.suggest("Work", activities, 50)), []);
// typed in full: still offered when it brings a detail along, otherwise not
assert.deepStrictEqual(labels(Lib.suggest("Lunch", activities.slice(0, 1), 50)), ["Lunch"]);
assert.deepStrictEqual(labels(Lib.suggest("Work", [{ label: "Work", detail: "" }], 50)), []);
assert.deepStrictEqual(labels(Lib.suggest("work", [{ label: "Work", detail: "" }], 50)), ["Work"]);

assert.deepStrictEqual(
    Lib.categoryNames(
        [{ name: "a", category: "Work" }, { name: "b", category: "" }, { name: "c", category: "Work" }],
        [{ id: 1, name: "Day-to-day" }, { id: 2, name: "Work" }]),
    ["Work", "Day-to-day"]);

console.log("lib_test: ok");
