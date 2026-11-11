// SPDX-License-Identifier: GPL-3.0-or-later
// Helpers ported from hamster-shell-extension (extension/stuff.js).
.pragma library

function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

// "01:23"
function formatDuration(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    return pad(hours) + ":" + pad(minutes);
}

// "1h 23min"; empty string when under a minute (caller supplies the wording)
function formatDurationHuman(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const parts = [];
    if (hours > 0)
        parts.push(hours + "h");
    if (minutes > 0)
        parts.push(minutes + "min");
    return parts.join(" ");
}

// "1.5h"
function formatDurationHours(totalSeconds) {
    return (Math.round(totalSeconds / 360) / 10).toFixed(1) + "h";
}

// Hamster datetime string ("2026-11-11 09:00", seconds optional) -> Date in local time
function parseDateTime(s) {
    if (!s)
        return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?/.exec(s);
    if (!m)
        return null;
    return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], m[6] ? +m[6] : 0);
}

// One element of GetTodaysFactsJSON -> plain object
function factFromJson(text) {
    const d = JSON.parse(text);
    return {
        id: d.id,
        name: d.activity || "",
        category: d.category || "",
        description: d.description || "",
        tags: d.tags || [],
        startTime: parseDateTime(d.range && d.range.start),
        endTime: parseDateTime(d.range && d.range.end)
    };
}

// Seconds spent on a fact; ongoing facts are measured up to `now`
function delta(fact, now) {
    if (!fact || !fact.startTime)
        return 0;
    const end = fact.endTime || now;
    return Math.max(0, Math.floor((end.getTime() - fact.startTime.getTime()) / 1000));
}

function timeOfDay(date) {
    return pad(date.getHours()) + ":" + pad(date.getMinutes());
}

// "09:00 – 10:30", or "09:00 –" while ongoing
function timeRange(fact) {
    if (!fact.startTime)
        return "";
    return timeOfDay(fact.startTime) + " – " + (fact.endTime ? timeOfDay(fact.endTime) : "");
}

function sameActivity(a, b) {
    return !!a && !!b && a.name === b.name && a.category === b.category
        && a.tags.join(",") === b.tags.join(",");
}

// Text that hamster's fact parser reads back as the same activity,
// category, description and tags (used by "continue").
function serialize(fact) {
    let s = fact.name;
    if (fact.category)
        s += "@" + fact.category;
    if (fact.description)
        s += ",, " + fact.description;
    const tags = fact.tags.filter(t => fact.description.indexOf("#" + t) < 0);
    if (tags.length)
        s += ", " + tags.map(t => "#" + t).join(" ");
    return s;
}

// [{category, seconds}], in order of first appearance
function categoryTotals(facts, now) {
    const totals = [];
    const index = {};
    for (const fact of facts) {
        if (!(fact.category in index)) {
            index[fact.category] = totals.length;
            totals.push({ category: fact.category, seconds: 0 });
        }
        totals[index[fact.category]].seconds += delta(fact, now);
    }
    return totals;
}

function totalSeconds(facts, now) {
    let total = 0;
    for (const fact of facts)
        total += delta(fact, now);
    return total;
}

// Inline completion for the entry field. `text` is what the user typed,
// optionally starting with a time ("10:30 ", "10:30-11:00 ", "-15 ").
// Returns the completed text, or "" when there is nothing to complete.
function complete(text, activities) {
    const m = /^(\s*(?:\d{1,2}[:.]\d{2}(?:\s*-\s*\d{1,2}[:.]\d{2})?|-\d+)\s+)?(.*)$/.exec(text);
    const prefix = m[1] || "";
    const typed = m[2].toLowerCase();
    if (!typed || typed.indexOf(",") >= 0)
        return "";
    for (const activity of activities) {
        const candidate = activity.category ? activity.name + "@" + activity.category : activity.name;
        if (candidate.length > typed.length && candidate.toLowerCase().startsWith(typed))
            return prefix + candidate;
    }
    return "";
}
