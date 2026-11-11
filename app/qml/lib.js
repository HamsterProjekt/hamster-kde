// SPDX-License-Identifier: GPL-3.0-or-later
// Dates, durations and Hamster's fact syntax, ported from hamster/lib
// (datetime.py, parsing.py, fact.py).
//
// A "hamster day" starts at the configured day start (05:30 by default),
// so 01:00 still belongs to the previous calendar day. Hamster days are
// represented by a Date at local midnight; dayStart is in minutes.
.pragma library

function pad(n) {
    return (n < 10 ? "0" : "") + n;
}

// --- dates ---

function midnight(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days,
                    date.getHours(), date.getMinutes());
}

function addMinutes(date, minutes) {
    return new Date(date.getTime() + minutes * 60000);
}

function sameDay(a, b) {
    return !!a && !!b && a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// hamster day a moment belongs to
function hday(date, dayStart) {
    const day = midnight(date);
    return date.getHours() * 60 + date.getMinutes() < dayStart ? addDays(day, -1) : day;
}

function today(dayStart) {
    return hday(new Date(), dayStart);
}

// moment of a hamster day at the given time of day
function fromDayTime(day, hours, minutes, dayStart) {
    const civil = hours * 60 + minutes < dayStart ? addDays(day, 1) : day;
    return new Date(civil.getFullYear(), civil.getMonth(), civil.getDate(), hours, minutes);
}

function dayBegin(day, dayStart) {
    return fromDayTime(day, Math.floor(dayStart / 60), dayStart % 60, dayStart);
}

function formatDate(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
}

function formatTime(date) {
    return pad(date.getHours()) + ":" + pad(date.getMinutes());
}

function formatDateTime(date) {
    return formatDate(date) + " " + formatTime(date);
}

// "2026-11-11" -> Date at midnight, or null
function parseDate(text) {
    const m = /^\s*(\d{4})-(\d{1,2})-(\d{1,2})\s*$/.exec(text || "");
    if (!m)
        return null;
    const date = new Date(+m[1], +m[2] - 1, +m[3]);
    return date.getMonth() === +m[2] - 1 ? date : null;
}

// "9:30", "09.30", "0930" -> {hours, minutes}, or null
function parseTime(text) {
    const m = /^\s*(\d{1,2})[:.,]?(\d{2})\s*$/.exec(text || "");
    if (!m || +m[1] > 23 || +m[2] > 59)
        return null;
    return { hours: +m[1], minutes: +m[2] };
}

// "2026-11-11 09:00" (as sent by the service) -> Date, or null
function parseDateTime(text) {
    const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{1,2}):(\d{2})/.exec(text || "");
    return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) : null;
}

// --- durations ---

// minutes spent on a fact; an ongoing fact is measured up to now
function minutes(fact, now) {
    if (!fact.start)
        return 0;
    const end = fact.end || now;
    return Math.max(0, Math.round((end.getTime() - fact.start.getTime()) / 60000));
}

// "2h 25min"
function formatDuration(totalMinutes) {
    return Math.floor(totalMinutes / 60) + "h " + (totalMinutes % 60) + "min";
}

// "02:25"
function formatDurationClock(totalMinutes) {
    return pad(Math.floor(totalMinutes / 60)) + ":" + pad(totalMinutes % 60);
}

// --- facts ---

function factFromJson(text) {
    const d = JSON.parse(text);
    return {
        id: d.id || 0,
        activity: d.activity || "",
        category: d.category || "",
        description: d.description || "",
        tags: d.tags || [],
        start: parseDateTime(d.range && d.range.start),
        end: parseDateTime(d.range && d.range.end)
    };
}

function factToJson(fact) {
    return JSON.stringify({
        activity: fact.activity,
        category: fact.category,
        description: fact.description,
        tags: fact.tags,
        range: {
            start: fact.start ? formatDateTime(fact.start) : null,
            end: fact.end ? formatDateTime(fact.end) : null
        }
    });
}

const RE_DATE = /^(\d{4})-(\d{2})-(\d{2})/;
// "--", a relative time (-15, +30), or a time possibly preceded by a date
const RE_MOMENT = /^(?:(--)|([-+]\d{1,3})|(?:(\d{4}-\d{2}-\d{2})\s?)?(\d(?=[,.:])|[01]\d|2[0-3])[,.:]?([0-5]\d)(?!\d?-\d{2}-\d{2}))/;

function momentFromMatch(m, defaultDay, now, dayStart) {
    if (m[1])
        return null;
    if (m[2])
        return addMinutes(now, parseInt(m[2]));
    if (m[3]) {
        const date = parseDate(m[3]);
        return new Date(date.getFullYear(), date.getMonth(), date.getDate(), +m[4], +m[5]);
    }
    return fromDayTime(defaultDay, +m[4], +m[5], dayStart);
}

function atBoundary(text) {
    return text === "" || /^\s/.test(text);
}

// Reads a time range at the beginning of text. Returns {start, end, rest}.
function parseRange(text, defaultDay, now, dayStart) {
    const none = { start: null, end: null, rest: text };
    let start = null;
    let end = null;
    let firstDay = null;
    let rest;

    let m = RE_MOMENT.exec(text);
    if (m) {
        start = momentFromMatch(m, defaultDay, now, dayStart);
        rest = text.slice(m[0].length);
    } else {
        m = RE_DATE.exec(text);
        if (!m || !parseDate(m[0]))
            return none;
        firstDay = parseDate(m[0]);
        start = dayBegin(firstDay, dayStart);
        end = dayBegin(addDays(firstDay, 1), dayStart);
        rest = text.slice(m[0].length);
    }

    // the end is optional
    const separator = /^(\s?-\s?|\s)/.exec(rest);
    if (separator) {
        const after = rest.slice(separator[0].length);
        const endDay = start ? hday(start, dayStart) : defaultDay;
        let consumed = -1;
        let candidate = end;
        if ((m = RE_MOMENT.exec(after))) {
            candidate = momentFromMatch(m, endDay, now, dayStart);
            consumed = m[0].length;
        } else if ((m = RE_DATE.exec(after)) && parseDate(m[0])) {
            candidate = dayBegin(addDays(parseDate(m[0]), 1), dayStart);
            consumed = 10;
        } else if (start && (m = /^\d{1,3}(?!\d)/.exec(after))) {
            candidate = addMinutes(start, parseInt(m[0]));
            consumed = m[0].length;
        }
        if (consumed >= 0 && atBoundary(after.slice(consumed))) {
            end = candidate;
            rest = after.slice(consumed);
        }
    }

    // "10.00@cat" is not a time
    if (!atBoundary(rest))
        return none;
    return { start: start, end: end, rest: rest.replace(/^\s+/, "") };
}

function findAll(regexp, text) {
    const found = [];
    let m;
    while ((m = regexp.exec(text)) !== null)
        found.push(m[1].trim());
    return found;
}

// [start [- end]] activity[@category][, description][, #tag #tag]
function parseFact(text, defaultDay, now, dayStart) {
    const range = parseRange(text.trim(), defaultDay, now, dayStart);
    let rest = range.rest;

    let tags = [];
    let m = /,{1,2}\s*(?=#)/.exec(rest);
    if (m) {
        tags = findAll(/#([^#,]+)/g, rest.slice(m.index + m[0].length));
        rest = rest.slice(0, m.index);
    }

    let description = "";
    m = /,+\s*/.exec(rest);
    if (m) {
        description = rest.slice(m.index + m[0].length).trim();
        rest = rest.slice(0, m.index);
    }
    tags = findAll(/#([a-zA-Z][^\s]+)/g, description).concat(tags);

    rest = rest.trim();
    const at = rest.lastIndexOf("@");
    return {
        start: range.start,
        end: range.end,
        activity: (at >= 0 ? rest.slice(0, at) : rest).trim(),
        category: at >= 0 ? rest.slice(at + 1).trim() : "",
        description: description,
        tags: tags
    };
}

function serializeRange(fact, defaultDay, dayStart) {
    if (!fact.start)
        return "";
    const startDay = hday(fact.start, dayStart);
    let text = sameDay(startDay, defaultDay) ? formatTime(fact.start) : formatDateTime(fact.start);
    if (fact.end) {
        text += " - " + (sameDay(hday(fact.end, dayStart), startDay)
                         ? formatTime(fact.end) : formatDateTime(fact.end));
    }
    return text;
}

// activity@category, description, #tag #tag
function serializeName(fact, withDescription) {
    let text = fact.activity;
    if (fact.category)
        text += "@" + fact.category;
    const description = withDescription ? fact.description : "";
    if (description)
        text += ", " + description;
    const tags = fact.tags.filter(tag => description.indexOf("#" + tag) < 0);
    if (tags.length)
        text += ", " + tags.map(tag => "#" + tag).join(" ");
    return text;
}

function serializeFact(fact, defaultDay, dayStart, withDescription) {
    const range = serializeRange(fact, defaultDay, dayStart);
    const name = serializeName(fact, withDescription);
    return range && name ? range + " " + name : range + name;
}

// "tag one, #two #three" -> ["tag one", "two", "three"]
function parseTags(text) {
    const tags = [];
    for (const part of text.split(/[,#]/)) {
        const tag = part.trim();
        if (tag && tags.indexOf(tag) < 0)
            tags.push(tag);
    }
    return tags;
}

// --- statistics ---

function ranked(map) {
    const rows = [];
    for (const name in map)
        rows.push({ name: name, minutes: map[name] });
    rows.sort((a, b) => b.minutes - a.minutes || a.name.localeCompare(b.name));
    return rows;
}

// {total, categories, activities, tags}; the lists are [{name, minutes}], largest first
function totals(facts, now) {
    const categories = {};
    const activities = {};
    const tags = {};
    let total = 0;
    for (const fact of facts) {
        const spent = minutes(fact, now);
        total += spent;
        categories[fact.category] = (categories[fact.category] || 0) + spent;
        activities[fact.activity] = (activities[fact.activity] || 0) + spent;
        for (const tag of fact.tags)
            tags[tag] = (tags[tag] || 0) + spent;
    }
    return { total: total, categories: ranked(categories), activities: ranked(activities), tags: ranked(tags) };
}

// Inline completion of the activity being typed, after an optional time range.
// activities: [{name, category}]. Returns the completed text, or "".
function complete(text, activities, defaultDay, now, dayStart) {
    const range = parseRange(text, defaultDay, now, dayStart);
    const typed = range.rest.toLowerCase();
    if (!typed || typed.indexOf(",") >= 0)
        return "";
    const prefix = text.slice(0, text.length - range.rest.length);
    for (const activity of activities) {
        const candidate = activity.category ? activity.name + "@" + activity.category : activity.name;
        if (candidate.length > typed.length && candidate.toLowerCase().startsWith(typed))
            return prefix + candidate;
    }
    return "";
}
