// Crepuscular's definition parser, moon and scheduler (ports of Defs.lua, Phase.lua and Schedule.lua,
// kept identical to them), the calendar driver, and the three output formats with their import.
(function (root, factory) {
    var api = factory();
    if (typeof module === "object" && module.exports) {
        module.exports = api;
    } else {
        root.Crepuscular = api;
    }
})(this, function () {
    "use strict";

    // User text becomes keys, so tables keyed by it have no prototype ("constructor", "__proto__").
    function dict(from) {
        var t = Object.create(null);
        if (from) {
            Object.keys(from).forEach(function (k) {
                t[k] = from[k];
            });
        }
        return t;
    }

    function Bad(why) {
        this.why = why;
    }

    // ------------------------------------------------------------------ numbers as the game's Lua writes them

    // Kahlua's tostring: whole numbers below 1e14 without a point (so -0 is "0"), else Java's Double.toString.
    function luaString(n) {
        if (n !== n) {
            return "nan";
        }
        if (n === Infinity || n === -Infinity) {
            return n > 0 ? "inf" : "-inf";
        }
        if (Math.floor(n) === n && Math.abs(n) < 1e14) {
            return String(n === 0 ? 0 : n);
        }
        var a = Math.abs(n);
        if (a >= 1e-3 && a < 1e7) {
            return String(n);
        }
        var parts = n.toExponential().split("e");
        var mantissa = parts[0].indexOf(".") < 0 ? parts[0] + ".0" : parts[0];
        return mantissa + "E" + parts[1].replace("+", "");
    }

    // Kahlua's own rounding: half to even after scaling.
    function kahluaRound(x) {
        if (x < 0) {
            return -kahluaRound(-x);
        }
        x += 0.5;
        var x2 = Math.floor(x);
        if (x2 === x) {
            return x2 - (x2 % 2);
        }
        return x2;
    }

    function kahluaDigits(value, printZero, minDigits) {
        var out = "";
        while (value > 0 || minDigits > 0) {
            var next = Math.floor(value / 10);
            out = String(Math.trunc(value - next * 10)) + out;
            value = next;
            minDigits--;
        }
        if (out === "" && printZero) {
            out = "0";
        }
        return out;
    }

    // string.format("%.1f", x) in Kahlua.
    function format1(x) {
        var sign = "";
        if (x < 0 || Object.is(x, -0)) {
            sign = "-";
            x = -x;
        }
        var n = kahluaRound(x * 10) / 10;
        var whole = Math.floor(n);
        var fraction = kahluaRound(whole + (n - whole) * 10) - whole;
        return sign + kahluaDigits(whole, true, 0) + "." + kahluaDigits(fraction, false, 1);
    }

    function pad2(n) {
        return n < 10 ? "0" + n : String(n);
    }

    // ------------------------------------------------------------------ Phase.lua

    var Phase = {};

    // Java integer division and remainder, which truncate toward zero.
    function quot(a, b) {
        var q = a / b;
        return q < 0 ? Math.ceil(q) : Math.floor(q);
    }

    function rem(a, b) {
        return a - quot(a, b) * b;
    }

    Phase.wrap = function (x, n) {
        return x - Math.floor(x / n) * n;
    };

    function leap(year) {
        return rem(year, 4) === 0 && (rem(year, 400) === 0 || rem(year, 100) !== 0);
    }

    var DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    Phase.daysInMonth = function (year, month) {
        if (month === 1 && leap(year)) {
            return 29;
        }
        return DAYS[month];
    };

    Phase.previousDay = function (date) {
        if (date.day > 1) {
            return { year: date.year, month: date.month, day: date.day - 1 };
        }
        if (date.month > 0) {
            return { year: date.year, month: date.month - 1, day: Phase.daysInMonth(date.year, date.month - 1) };
        }
        return { year: date.year - 1, month: 11, day: 31 };
    };

    Phase.key = function (date) {
        return date.year + "-" + pad2(date.month + 1) + "-" + pad2(date.day);
    };

    var DAY_YEAR = [-1, -1, 30, 58, 89, 119, 150, 180, 211, 241, 272, 303];

    Phase.moon = function (year, month, day) {
        var dayOfYear = day + DAY_YEAR[month];
        if (month > 2 && leap(year)) {
            dayOfYear = dayOfYear + 1;
        }
        var century = quot(year, 100) + 1;
        var golden = rem(year, 19) + 1;
        var epact = rem(11 * golden + 20 + quot(8 * century + 5, 25) - 5 - (quot(3 * century, 4) - 12), 30);
        if (epact <= 0) {
            epact = epact + 30;
        }
        if ((epact === 25 && golden > 11) || epact === 24) {
            epact = epact + 1;
        }
        var phase = quot(rem((dayOfYear + epact) * 6 + 11, 177), 22);
        return rem(phase, 8);
    };

    Phase.occasion = function (now, rule) {
        var today = { year: now.year, month: now.month, day: now.day };
        var time = now.time;
        if (rule.mode === 2) {
            if (rule.endless != null) {
                return { phase: rule.endless, date: today, open: time, start: now.hours, endless: true };
            }
            if (time >= rule.dawn && time <= rule.dusk) {
                return { phase: "day", date: today, open: rule.dawn, start: now.hours - (time - rule.dawn) };
            }
            var nightDate = today;
            if (time < 12) {
                nightDate = Phase.previousDay(today);
            }
            return { phase: "night", date: nightDate, open: rule.dusk, start: now.hours - Phase.wrap(time - rule.dusk, 24) };
        }
        if (rule.start === rule.finish) {
            return { phase: "day", date: today, open: time, start: now.hours, endless: true };
        }
        var hour = Math.floor(time);
        var night;
        if (rule.start < rule.finish) {
            night = hour >= rule.start && hour < rule.finish;
        } else {
            night = hour >= rule.start || hour < rule.finish;
        }
        var phase = "day", open = rule.finish;
        if (night) {
            phase = "night";
            open = rule.start;
        }
        var date = today;
        if (hour < open) {
            date = Phase.previousDay(today);
        }
        return { phase: phase, date: date, open: open, start: now.hours - Phase.wrap(time - open, 24) };
    };

    // ------------------------------------------------------------------ Defs.lua

    var Defs = {};

    Defs.BASES = ["Day", "Night"];
    Defs.SLOTS = ["Events1", "Events2", "Events3", "Events4", "Events5", "Events6", "Events7", "Events8"];
    Defs.KINDS = "Kinds";
    Defs.OPTIONS = Defs.BASES.concat(Defs.SLOTS, [Defs.KINDS]);

    // The game stores each string option behind a signed 16-bit byte count.
    Defs.LIMIT = 32000;

    var MOONS = dict({
        new: 0, waxingcrescent: 1, firstquarter: 2, waxinggibbous: 3,
        full: 4, waninggibbous: 5, thirdquarter: 6, waningcrescent: 7,
    });
    // The game's season numbers: 3 is the second half of summer.
    var SEASONS = dict({ spring: [1], summer: [2, 3], autumn: [4], winter: [5] });
    var WEATHER = dict({ rain: true, snow: true, storm: true, fog: true, clear: true });
    var MONTH_DAYS = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    var MAX_PHASES = 60;
    var MAX_HOURS = 30 * 24;
    var MAX_COOLDOWN_HOURS = 3650 * 24;
    var MAX_WAIT = { d: 3650, h: 3650 * 24 };
    var MAX_DAYS = 36500;

    var CONDITIONS = [
        "moon", "date", "month", "season", "every", "nth", "mindays", "maxdays",
        "after", "cooldown", "interval", "weather", "tempmin", "tempmax", "chance",
    ];

    // Number effects that may be a range a..b, which grow= of the same definition moves along.
    var GROWING = ["speed", "health", "rise", "fog", "desat", "dark", "ambient"];
    // Of those, the ones that are whole numbers.
    var WHOLE = dict({ speed: true, rise: true });

    // UTF-8 bytes, counted per UTF-16 unit as the game's Lua sees the text: a surrogate pair is 4.
    Defs.bytes = function (text) {
        var n = 0;
        for (var i = 0; i < text.length; i++) {
            var c = text.charCodeAt(i);
            if (c < 128) {
                n = n + 1;
            } else if (c < 2048 || (c >= 55296 && c <= 57343)) {
                n = n + 2;
            } else {
                n = n + 3;
            }
        }
        return n;
    };

    // Lua's %s and %c, which are ASCII only in the game too.
    var SPACE_START = /^[\t\n\v\f\r ]+/;
    var SPACE_END = /[\t\n\v\f\r ]+$/;
    var CONTROL = /[\x00-\x1f\x7f]/;
    var CONTROLS = /[\x00-\x1f\x7f]/g;

    function lower(text) {
        return text.toLowerCase();
    }

    function trim(text) {
        return text.replace(/^ +/, "").replace(/ +$/, "");
    }

    function strip(text) {
        return text.replace(SPACE_START, "").replace(SPACE_END, "");
    }

    function items(text, separator, clean) {
        var list = [];
        text.split(separator).forEach(function (part) {
            part = clean(part);
            if (part !== "") {
                list.push(part);
            }
        });
        return list;
    }

    function number(text, whole) {
        var m = /^([+-]?)([\s\S]*)$/.exec(text);
        var sign = m[1], body = m[2];
        var ok = /^[0-9]+$/.test(body);
        if (!whole && !ok) {
            ok = /^[0-9]+\.[0-9]*$/.test(body) || /^\.[0-9]+$/.test(body);
        }
        if (!ok) {
            return null;
        }
        var n = Number(body);
        if (sign === "-" && n !== 0) {
            n = -n;
        }
        return n;
    }

    function quote(text) {
        return "'" + text + "'";
    }

    function ranged(text, whole, min, max, what) {
        var n = number(text, whole);
        if (n === null || n < min || n > max) {
            return new Bad(quote(text) + " is not " + what);
        }
        return n;
    }

    function list(text, one, what) {
        var parts = items(text, ",", trim);
        if (parts.length === 0) {
            return new Bad(quote(text) + " is not " + what);
        }
        var set = dict();
        for (var i = 0; i < parts.length; i++) {
            if (!one(parts[i], set)) {
                return new Bad(quote(parts[i]) + " is not " + what);
            }
        }
        return set;
    }

    function range(text) {
        var i = text.indexOf("..");
        if (i < 0) {
            return [text, null];
        }
        return [trim(text.slice(0, i)), trim(text.slice(i + 2))];
    }

    function monthDay(text) {
        var m = /^([0-9][0-9]?)-([0-9][0-9]?)$/.exec(text);
        if (m === null) {
            return null;
        }
        var month = Number(m[1]), day = Number(m[2]);
        if (month < 1 || month > 12 || day < 1 || day > MONTH_DAYS[month - 1]) {
            return null;
        }
        return month * 100 + day;
    }

    function month(text) {
        var m = number(text, true);
        if (m === null || m < 1 || m > 12) {
            return null;
        }
        return m;
    }

    // N or N+K.
    function cycle(text) {
        var m = /^([0-9]+) *\+ *([0-9]+)$/.exec(text);
        if (m !== null) {
            return [Number(m[1]), Number(m[2])];
        }
        m = /^([0-9]+)$/.exec(text);
        return [m === null ? null : Number(m[1]), null];
    }

    function idText(text) {
        return /^[a-z0-9_]+$/.test(text);
    }

    function hourText(hours) {
        var minutes = Math.floor(hours * 60 + 0.5);
        return pad2(Math.floor(minutes / 60)) + ":" + pad2(minutes % 60);
    }

    // Each returns the parsed value or a Bad with the reason.
    var PARSE = dict();

    PARSE.id = function (v) {
        if (!idText(v)) {
            return new Bad(quote(v) + " is not made of a-z, 0-9 and _");
        }
        return v;
    };

    PARSE.track = function (v) {
        if (v !== "sun" && v !== "moon") {
            return new Bad(quote(v) + " is not sun or moon");
        }
        return v;
    };

    PARSE.at = function (v) {
        var m = /^([0-9][0-9]?):([0-9][0-9])$/.exec(v);
        var h = null, minutes = 0;
        if (m !== null) {
            h = Number(m[1]);
            minutes = Number(m[2]);
        } else {
            m = /^([0-9][0-9]?)$/.exec(v);
            if (m !== null) {
                h = Number(m[1]);
            }
        }
        if (h === null || h > 23 || minutes > 59) {
            return new Bad(quote(v) + " is not HH or HH:MM");
        }
        return h + minutes / 60;
    };

    PARSE["for"] = function (v) {
        if (v === "phase") {
            return { phases: 1 };
        }
        var m = /^([0-9]+)p$/.exec(v);
        if (m !== null) {
            var n = Number(m[1]);
            if (n < 1 || n > MAX_PHASES) {
                return new Bad(quote(v) + " is not 1 to " + MAX_PHASES + " phases");
            }
            return { phases: n };
        }
        m = /^([\s\S]*?) *([hd])$/.exec(v);
        var x = m === null ? null : number(m[1], false);
        if (x === null) {
            return new Bad(quote(v) + " is not phase, Np, Xh or Xd");
        }
        if (m[2] === "d") {
            x = x * 24;
        }
        if (x <= 0) {
            return new Bad(quote(v) + " is not longer than 0");
        }
        if (x > MAX_HOURS) {
            return new Bad(quote(v) + " is over 30 days");
        }
        return { hours: x };
    };

    PARSE.prio = function (v) {
        return ranged(v, true, -999, 999, "a whole number from -999 to 999");
    };

    PARSE.chance = function (v) {
        return ranged(v, false, 0, 100, "a number from 0 to 100");
    };

    PARSE.moon = function (v) {
        return list(v, function (item, set) {
            var p = MOONS[item];
            if (p === undefined) {
                p = number(item, true);
                if (p === null || p < 0 || p > 7) {
                    return false;
                }
            }
            set[p] = true;
            return true;
        }, "a moon phase");
    };

    PARSE.date = function (v) {
        var ranges = [];
        var ok = list(v, function (item) {
            var r = range(item);
            var from = monthDay(r[0]);
            var to = from;
            if (r[1] !== null) {
                to = monthDay(r[1]);
            }
            if (from === null || to === null) {
                return false;
            }
            ranges.push({ from: from, to: to });
            return true;
        }, "MM-DD or MM-DD..MM-DD");
        if (ok instanceof Bad) {
            return ok;
        }
        return ranges;
    };

    PARSE.month = function (v) {
        return list(v, function (item, set) {
            var r = range(item);
            var from = month(r[0]);
            var to = from;
            if (r[1] !== null) {
                to = month(r[1]);
            }
            if (from === null || to === null) {
                return false;
            }
            var m = from;
            while (true) {
                set[m] = true;
                if (m === to) {
                    return true;
                }
                m = m % 12 + 1;
            }
        }, "a month from 1 to 12 or a range of them");
    };

    PARSE.season = function (v) {
        return list(v, function (item, set) {
            var numbers = SEASONS[item];
            if (numbers === undefined) {
                return false;
            }
            numbers.forEach(function (n) {
                set[n] = true;
            });
            return true;
        }, "spring, summer, autumn or winter");
    };

    PARSE.every = function (v) {
        var c = cycle(v), n = c[0], k = c[1];
        if (n === null || n < 2 || n > 3650 || (k !== null && k >= n)) {
            return new Bad(quote(v) + " is not N or N+K days, N from 2 to 3650 and K below N");
        }
        return { n: n, k: k === null ? 0 : k };
    };

    PARSE.nth = function (v) {
        var c = cycle(v), n = c[0], k = c[1];
        if (n === null || n < 1 || n > 1000 || (k !== null && (k < 1 || k > n))) {
            return new Bad(quote(v) + " is not N or N+K, N from 1 to 1000 and K from 1 to N");
        }
        return { n: n, k: k === null ? n : k };
    };

    PARSE.mindays = function (v) {
        return ranged(v, true, 0, MAX_DAYS, "a whole number from 0 to 36500");
    };

    PARSE.maxdays = PARSE.mindays;

    PARSE.after = function (v) {
        var order = [];
        var set = list(v, function (item, s) {
            if (!idText(item)) {
                return false;
            }
            if (!s[item]) {
                order.push(item);
            }
            s[item] = true;
            return true;
        }, "an event id");
        if (set instanceof Bad) {
            return set;
        }
        return order;
    };

    PARSE.cooldown = function (v) {
        var m = /^([\s\S]*?) *([hd])$/.exec(v);
        var x = m === null ? null : number(m[1], false);
        if (x !== null && m[2] === "d") {
            x = x * 24;
        }
        if (x === null || x <= 0 || x > MAX_COOLDOWN_HOURS) {
            return new Bad(quote(v) + " is not Xd or Xh, longer than 0 and up to 3650 days");
        }
        return x;
    };

    // Whole days or hours: Nd or Nh -> [N, unit], or null.
    function duration(text) {
        var m = /^([\s\S]*?) *([hd])$/.exec(text);
        var n = m === null ? null : number(m[1], true);
        if (n === null) {
            return null;
        }
        return [n, m[2]];
    }

    PARSE.interval = function (v) {
        var r = range(v);
        var a = duration(r[0]);
        var b = a;
        if (r[1] !== null) {
            b = duration(r[1]);
        }
        if (a !== null && b !== null && a[1] !== b[1]) {
            return new Bad(quote(v) + " mixes days and hours");
        }
        if (a === null || b === null || a[0] < 1 || b[0] > MAX_WAIT[a[1]]) {
            return new Bad(quote(v) + " is not Nd, Nh or a range of them such as 3d..7d, in whole days or hours up to 3650 days");
        }
        if (b[0] < a[0]) {
            return new Bad(quote(v) + " is not from the shorter to the longer wait");
        }
        return { min: a[0], max: b[0], unit: a[1] };
    };

    PARSE.weather = function (v) {
        return list(v, function (item, set) {
            if (!WEATHER[item]) {
                return false;
            }
            set[item] = true;
            return true;
        }, "rain, snow, storm, fog or clear");
    };

    PARSE.tempmin = function (v) {
        return ranged(v, false, -80, 80, "a number from -80 to 80");
    };

    PARSE.tempmax = PARSE.tempmin;

    PARSE.off = function (v) {
        if (v === "none") {
            return dict();
        }
        var set = list(v, function (item, s) {
            if (!idText(item)) {
                return false;
            }
            s[item] = true;
            return true;
        }, "none or a list of kind names");
        if (!(set instanceof Bad) && set.none) {
            return new Bad("none can't be combined with kind names");
        }
        return set;
    };

    PARSE.say = function (v) {
        if (v === "") {
            return new Bad("is empty");
        }
        return v;
    };

    function hex(text, digits) {
        return text.length === digits && /^[0-9a-f]+$/.test(text);
    }

    PARSE.color = function (v) {
        if (!hex(v, 6)) {
            return new Bad(quote(v) + " is not a colour as rrggbb");
        }
        return v;
    };

    PARSE.sky = function (v) {
        if (!hex(v, 8)) {
            return new Bad(quote(v) + " is not a colour as rrggbbaa");
        }
        return v;
    };

    PARSE.fogcolor = PARSE.color;

    PARSE.sound = function (v) {
        if (!/^[A-Za-z0-9_]+$/.test(v)) {
            return new Bad(quote(v) + " is not a sound name made of letters, digits and _");
        }
        return v;
    };

    // A number, or a range a..b of them: { from: a, to: b }.
    function growing(v, whole, min, max, what, ranges) {
        var r = range(v);
        if (r[1] === null) {
            return ranged(v, whole, min, max, what);
        }
        var from = number(r[0], whole), to = number(r[1], whole);
        if (from === null || to === null || from < min || from > max || to < min || to > max) {
            return new Bad(quote(v) + " is not a range of " + ranges);
        }
        return { from: from, to: to };
    }

    PARSE.speed = function (v) {
        return growing(v, true, -100, 100, "a whole number from -100 to 100", "whole numbers from -100 to 100 such as +25..+75");
    };

    PARSE.steps = function (v) {
        return ranged(v, true, 1, 2, "1 or 2");
    };

    PARSE.health = function (v) {
        return growing(v, false, 0.1, 5, "a number from 0.1 to 5", "numbers from 0.1 to 5 such as 0.7..0.4");
    };

    PARSE.rise = function (v) {
        return growing(v, true, 0, 100, "a whole number from 0 to 100", "whole numbers from 0 to 100 such as 25..100");
    };

    // Climate values from 0 to 1.
    function climate(v) {
        return growing(v, false, 0, 1, "a number from 0 to 1", "numbers from 0 to 1 such as 0.2..0.6");
    }

    PARSE.fog = climate;
    PARSE.desat = climate;
    PARSE.dark = climate;
    PARSE.ambient = climate;

    PARSE.wake = function (v) {
        if (v !== "true" && v !== "false") {
            return new Bad(quote(v) + " is not true or false");
        }
        return v === "true";
    };

    // Whole world days: Nd -> N, or null.
    function wholeDays(text) {
        var m = /^([\s\S]*?) *d$/.exec(text);
        return m === null ? null : number(m[1], true);
    }

    PARSE.grow = function (v) {
        var r = range(v);
        var from = 0, to = wholeDays(r[0]);
        if (r[1] !== null) {
            from = to;
            to = wholeDays(r[1]);
        }
        if (from === null || to === null || from < 0 || to > MAX_DAYS) {
            return new Bad(quote(v) + " is not Nd or Ad..Bd, in whole world days from 0 to 36500");
        }
        if (to <= from) {
            return new Bad(quote(v) + " does not end after it starts");
        }
        return { from: from, to: to };
    };

    // Keys a base definition may have; the rest belong to events.
    var EFFECTS = dict({
        off: true, say: true, color: true, sound: true, speed: true, steps: true, health: true, rise: true,
        wake: true, grow: true, sky: true, fogcolor: true, fog: true, desat: true, dark: true,
        ambient: true,
    });

    // A range needs grow= in its own definition: an event's grow never moves what it inherits. Without
    // a valid grow= the range is dropped; a grow= field that failed has its error already.
    function ungrown(def, fieldList, fail) {
        var written = fieldList.some(function (f) { return f.name === "grow"; });
        GROWING.forEach(function (key) {
            if (typeof def[key] === "object" && def.grow === undefined) {
                if (!written) {
                    fail(key, "a range needs grow= in the same definition");
                }
                delete def[key];
            }
        });
    }

    // Whether a rise= value, or either end of its range, marks any corpse.
    function marks(v) {
        if (typeof v === "object") {
            return v.from > 0 || v.to > 0;
        }
        return v !== undefined && v > 0;
    }

    function idleGrow(def, warn) {
        if (def.grow === undefined) {
            return;
        }
        if (GROWING.some(function (key) { return typeof def[key] === "object"; })) {
            return;
        }
        warn("grow", "no value of this definition is a range, so it changes nothing");
    }

    // A number effect of def on world day `day`: a range goes linearly from its first value on the
    // first day of grow= to its second on the last, and keeps its ends outside them. Speed and rise
    // shares are whole numbers, rounded half away from 0.
    Defs.at = function (def, key, day) {
        var v = def[key];
        if (typeof v !== "object") {
            return v;
        }
        var grow = def.grow;
        var x = v.to;
        if (day <= grow.from) {
            x = v.from;
        } else if (day < grow.to) {
            x = v.from + (v.to - v.from) * (day - grow.from) / (grow.to - grow.from);
        }
        if (!WHOLE[key]) {
            return x;
        }
        var n = Math.floor(Math.abs(x) + 0.5);
        if (x < 0 && n > 0) {
            return -n;
        }
        return n;
    };

    // { key, option (for set.), value } or { bad = reason }, each with the name messages use.
    function fields(text) {
        var out = [];
        items(strip(text), ";", trim).forEach(function (field) {
            var eq = field.indexOf("=");
            var name = "";
            if (eq >= 0) {
                name = trim(field.slice(0, eq));
            }
            if (CONTROL.test(field)) {
                if (name === "" || CONTROL.test(name)) {
                    name = quote(field.replace(CONTROLS, " "));
                }
                out.push({ name: lower(name), bad: "contains a control character such as a newline or tab" });
            } else if (name === "") {
                out.push({ name: quote(field), bad: "is not key=value" });
            } else {
                var value = trim(field.slice(eq + 1));
                var key = lower(name);
                var f = { name: key, key: key, value: value };
                if (key.slice(0, 4) === "set.") {
                    f.key = "set.";
                    f.option = name.slice(4);
                    f.name = "set." + f.option;
                } else if (key !== "say" && key !== "sound") {
                    f.value = lower(value);
                }
                out.push(f);
            }
        });
        return out;
    }

    function parseFields(def, fieldList, isEvent, report) {
        var seen = dict();
        fieldList.forEach(function (f) {
            if (f.bad !== undefined) {
                report(f.name, f.bad);
            } else if (seen[f.name]) {
                report(f.name, "is repeated");
            } else {
                seen[f.name] = true;
                if (f.key === "set.") {
                    if (f.option === "") {
                        report(f.name, "has no option name");
                    } else {
                        def.set[f.option] = f.value;
                    }
                } else if (PARSE[f.key] === undefined) {
                    report(f.name, "unknown key");
                } else if (!isEvent && !EFFECTS[f.key]) {
                    report(f.name, "only events can have this key");
                } else {
                    var value = PARSE[f.key](f.value);
                    if (value instanceof Bad) {
                        report(f.name, value.why);
                    } else {
                        def[f.key] = value;
                    }
                }
            }
        });
        return seen;
    }

    function windowText(from, to) {
        return hourText(from) + "-" + hourText(to);
    }

    // The at= of an event with fixed hours must fall inside its track's window, [from, to).
    function checkAt(ev, rule, report) {
        if (ev.at === undefined || ev.track === undefined || rule.mode !== 1) {
            return;
        }
        if (rule.start === rule.finish) {
            if (ev.track === "moon") {
                report("at", "there is no night window: NightStartHour equals NightEndHour");
            }
            return;
        }
        var from = rule.finish, to = rule.start, name = "day";
        if (ev.track === "moon") {
            from = rule.start;
            to = rule.finish;
            name = "night";
        }
        if (Phase.wrap(ev.at - from, 24) >= Phase.wrap(to - from, 24)) {
            report("at", quote(hourText(ev.at)) + " is outside the " + name + " window " + windowText(from, to));
        }
    }

    function newDef(label) {
        return { label: label, set: dict(), errors: 0 };
    }

    function message(label, key, reason) {
        if (key === null) {
            return label + ": " + reason;
        }
        return label + ": " + key + ": " + reason;
    }

    // The Kinds option: name=prefix,prefix;name=prefix. A bad entry is skipped and the rest kept.
    function parseKinds(text, builtin, fail) {
        var kinds = [], seen = dict();
        fields(text).forEach(function (f) {
            if (f.bad !== undefined) {
                fail(f.name, f.bad);
            } else if (!idText(f.name)) {
                fail(quote(f.name), "is not made of a-z, 0-9 and _");
            } else if (f.name === "none" || builtin[f.name]) {
                fail(f.name, "is a kind name Crepuscular has");
            } else if (seen[f.name]) {
                fail(f.name, "is repeated");
            } else {
                seen[f.name] = true;
                var prefixes = [];
                var ok = list(f.value, function (item, set) {
                    item = lower(item);
                    if (!set[item]) {
                        prefixes.push(item);
                    }
                    set[item] = true;
                    return true;
                }, "a list of outfit name prefixes");
                if (ok instanceof Bad) {
                    fail(f.name, ok.why);
                } else {
                    kinds.push({ name: f.name, prefixes: prefixes });
                }
            }
        });
        return kinds;
    }

    // Zomboid Forge's own type for the game's ordinary zombies, which stay under the speed and health
    // of the definitions.
    Defs.FORGE_ORDINARY = "ZF_Zomboid";

    // The kind of a Zomboid Forge type: its id without what isn't A-Z, a-z, 0-9 or _, lowercased. A Bad
    // for a type that has none. own: Crepuscular's kind names, which a type can't take.
    Defs.forgeKind = function (id, own) {
        if (id === Defs.FORGE_ORDINARY) {
            return new Bad("is Zomboid Forge's type for ordinary zombies");
        }
        var name = lower(id.replace(/[^A-Za-z0-9_]/g, ""));
        if (name === "") {
            return new Bad("has no letter, digit or _ to name a kind by");
        }
        if (name === "none" || own[name]) {
            return new Bad("would be the kind " + name + ", which Crepuscular has");
        }
        return name;
    };

    // texts: option name -> text; rule: the clock rule; builtin: set of the built-in kind names;
    // registered: set of the kind names other mods registered, or null to leave off= unchecked.
    // Besides what Defs.lua returns, definitions lists every event in order, valid or not.
    Defs.parse = function (texts, rule, builtin, registered) {
        var result = { events: [], byId: dict(), ids: [], errors: [], warnings: [], failed: 0 };

        function warn(def, key, reason) {
            result.warnings.push(message(def.label, key, reason));
        }

        function fail(def, key, reason) {
            result.errors.push(message(def.label, key, reason));
            def.errors = def.errors + 1;
        }

        var option = { label: Defs.KINDS, errors: 0 };
        result.kinds = parseKinds(texts[Defs.KINDS], builtin, function (key, reason) {
            fail(option, key, reason);
        });
        if (option.errors > 0) {
            result.failed = result.failed + 1;
        }

        var known = null;
        if (registered != null) {
            known = dict();
            Object.keys(builtin).forEach(function (name) {
                known[name] = true;
            });
            Object.keys(registered).forEach(function (name) {
                known[name] = true;
            });
            result.kinds.forEach(function (kind) {
                if (registered[kind.name]) {
                    warn(option, kind.name, "replaces the kind another mod registered under this name");
                }
                known[kind.name] = true;
            });
        }

        function checkKinds(def) {
            if (def.off === undefined || known === null) {
                return;
            }
            Object.keys(def.off).filter(function (kind) {
                return !known[kind];
            }).sort().forEach(function (kind) {
                warn(def, "off", quote(kind) + " is not a known kind");
            });
        }

        Defs.BASES.forEach(function (name) {
            var def = newDef(name);
            function failed(key, reason) {
                fail(def, key, reason);
            }
            var fieldList = fields(texts[name]);
            parseFields(def, fieldList, false, failed);
            ungrown(def, fieldList, failed);
            idleGrow(def, function (key, reason) {
                warn(def, key, reason);
            });
            checkKinds(def);
            if (def.errors > 0) {
                result.failed = result.failed + 1;
            }
            result[lower(name)] = def;
        });

        var parsed = [];
        Defs.SLOTS.forEach(function (slot) {
            var position = 0;
            items(texts[slot], "|", strip).forEach(function (text) {
                position = position + 1;
                var fieldList = fields(text);
                var label = slot + " #" + position;
                for (var i = 0; i < fieldList.length; i++) {
                    if (fieldList[i].key === "id" && idText(fieldList[i].value)) {
                        label = label + " (" + fieldList[i].value + ")";
                        break;
                    }
                }
                var ev = newDef(label);
                ev.order = parsed.length + 1;
                var present = parseFields(ev, fieldList, true, function (key, reason) {
                    fail(ev, key, reason);
                });
                if (!present.id) {
                    fail(ev, "id", "is missing");
                }
                if (!present.track) {
                    fail(ev, "track", "is missing");
                }
                checkAt(ev, rule, function (key, reason) {
                    fail(ev, key, reason);
                });
                if (ev.tempmin !== undefined && ev.tempmax !== undefined && ev.tempmax < ev.tempmin) {
                    fail(ev, "tempmax", luaString(ev.tempmax) + " is below tempmin " + luaString(ev.tempmin));
                }
                if (ev.mindays !== undefined && ev.maxdays !== undefined && ev.maxdays < ev.mindays) {
                    fail(ev, "maxdays", luaString(ev.maxdays) + " is below mindays " + luaString(ev.mindays));
                }
                ungrown(ev, fieldList, function (key, reason) {
                    fail(ev, key, reason);
                });
                if (ev["for"] === undefined) {
                    ev["for"] = { phases: 1 };
                }
                if (ev.prio === undefined) {
                    ev.prio = 0;
                }
                parsed.push(ev);
            });
        });

        // The first otherwise valid event with an id holds it. An event chained after an id nobody
        // holds is skipped, which can skip others or hand its own id to a later definition.
        var holder;
        var changed = true;
        while (changed) {
            changed = false;
            holder = dict();
            parsed.forEach(function (ev) {
                if (ev.errors === 0 && holder[ev.id] === undefined) {
                    holder[ev.id] = ev;
                }
            });
            parsed.forEach(function (ev) {
                if (ev.id !== undefined && holder[ev.id] === ev && ev.after !== undefined) {
                    ev.after.forEach(function (id) {
                        if (holder[id] === undefined) {
                            fail(ev, "after", "no loaded event has the id " + quote(id));
                            changed = true;
                        }
                    });
                }
            });
        }
        parsed.forEach(function (ev) {
            if (ev.errors === 0 && holder[ev.id] !== ev) {
                fail(ev, "id", quote(ev.id) + " is already used by " + holder[ev.id].label);
            }
        });

        parsed.forEach(function (ev) {
            if (ev.errors > 0) {
                result.failed = result.failed + 1;
            } else {
                result.events.push(ev);
                result.byId[ev.id] = ev;
                result.ids.push(ev.id);
            }
        });

        result.events.forEach(function (ev) {
            checkKinds(ev);
            idleGrow(ev, function (key, reason) {
                warn(ev, key, reason);
            });
            if (ev.chance === 0) {
                warn(ev, "chance", "is 0, so it never happens");
            }
            var conditions = CONDITIONS.some(function (key) {
                return ev[key] !== undefined;
            });
            if (!conditions) {
                warn(ev, null, "has no conditions, so it can happen every " + (ev.track === "sun" ? "day" : "night"));
            }
            if (ev.after !== undefined) {
                var rivals = [];
                result.events.forEach(function (other) {
                    if (other !== ev && other.track === ev.track
                        && (other.prio > ev.prio || (other.prio === ev.prio && other.order < ev.order))) {
                        rivals.push(other.id + " (prio " + luaString(other.prio) + ")");
                    }
                });
                if (rivals.length > 0) {
                    warn(ev, "after", "can lose to " + rivals.join(", "));
                }
            }
        });

        var all = [result.day, result.night].concat(result.events);
        var wakes = all.some(function (def) {
            return def.wake === true;
        });
        if (!wakes) {
            all.forEach(function (def) {
                if (marks(def.rise)) {
                    warn(def, "rise", "no definition has wake=true, so marked corpses never get up");
                }
            });
        }
        result.definitions = parsed;
        return result;
    };

    // ------------------------------------------------------------------ Schedule.lua

    var Schedule = {};

    // World-age hours are floats, so comparisons allow half a minute.
    var TOLERANCE = 0.5 / 60;

    function trackOf(phase) {
        return phase === "day" ? "sun" : "moon";
    }

    Schedule.prepare = function (ledger) {
        ["decided", "pool", "count", "lastStart", "lastDay", "roll", "follow"].forEach(function (name) {
            if (ledger[name] === undefined) {
                ledger[name] = dict();
            }
        });
        if (ledger.serial === undefined) {
            ledger.serial = 0;
        }
    };

    function label(occasion) {
        return occasion.phase + " of " + occasion.key;
    }

    // World age turns a day at 07:00, so an occasion counts the world day at noon of its date: this is
    // that noon in world-age hours. An endless occasion keeps the date it opened on, so it counts the
    // date of `now` (world-age hours) instead.
    function noon(occasion, now) {
        var midnight = occasion.start - occasion.open;
        if (occasion.endless) {
            midnight = midnight + 24 * Math.floor((now - midnight + TOLERANCE) / 24);
        }
        return midnight + 12;
    }

    // Noon is 5 hours from the turn of a world day, so it needs no tolerance.
    function worldDay(occasion, now) {
        return Math.floor(noon(occasion, now) / 24);
    }

    Schedule.noon = noon;
    Schedule.worldDay = worldDay;

    // When ev would start in the occasion: at its at= time, or as the occasion starts, but not before
    // `earliest`: the occasion's nominal start for a decision, now for an admin's.
    function startTime(ev, occasion, earliest) {
        if (ev.at === undefined) {
            return earliest;
        }
        return Math.max(earliest, occasion.start + Phase.wrap(ev.at - occasion.open, 24));
    }

    // When an event with interval= is next due: [unit ("d" counts world days, "h" world-age hours),
    // the earliest and the latest due], the same once its wait is rolled. The wait runs from its last
    // start; the first one from world day 0, or for hours from world age 0, 07:00 that day.
    Schedule.due = function (ledger, ev) {
        var interval = ev.interval;
        var base = interval.unit === "d" ? ledger.lastDay[ev.id] : ledger.lastStart[ev.id];
        if (base === undefined) {
            base = 0;
        }
        var roll = ledger.roll[ev.id];
        if (roll === undefined) {
            return [interval.unit, base + interval.min, base + interval.max];
        }
        var due = base + interval.min + Math.floor(roll * (interval.max - interval.min + 1) / 100);
        return [interval.unit, due, due];
    };

    // Why ev still waits for its interval if it starts at `when` in the occasion, or null once it is
    // due. A wait is rolled when first needed and kept until the event starts again, so a lost chance
    // doesn't roll anew.
    function waiting(ledger, ev, occasion, when, roll) {
        var interval = ev.interval;
        if (interval.max > interval.min && ledger.roll[ev.id] === undefined) {
            ledger.roll[ev.id] = roll();
        }
        var d = Schedule.due(ledger, ev);
        if (d[0] === "d") {
            if (worldDay(occasion, when) < d[1]) {
                return "is not due before world day " + luaString(d[1]);
            }
            return null;
        }
        var left = d[1] - when;
        if (left > TOLERANCE) {
            return "is not due for " + luaString(Math.floor(left * 60 + 0.5)) + " more minutes";
        }
        return null;
    }

    function calendar(ev, occasion, day, climate) {
        var date = occasion.date;
        if (ev.moon !== undefined) {
            var phase = Phase.moon(date.year, date.month, date.day);
            var before = Phase.previousDay(date);
            if (!ev.moon[phase] || Phase.moon(before.year, before.month, before.day) === phase) {
                return false;
            }
        }
        if (ev.date !== undefined) {
            var key = (date.month + 1) * 100 + date.day;
            var inside = ev.date.some(function (r) {
                return (r.from <= r.to && key >= r.from && key <= r.to) || (r.from > r.to && (key >= r.from || key <= r.to));
            });
            if (!inside) {
                return false;
            }
        }
        if (ev.month !== undefined && !ev.month[date.month + 1]) {
            return false;
        }
        if (ev.season !== undefined && !ev.season[climate.season]) {
            return false;
        }
        if (ev.every !== undefined && Phase.wrap(day, ev.every.n) !== ev.every.k) {
            return false;
        }
        if (ev.mindays !== undefined && day < ev.mindays) {
            return false;
        }
        if (ev.maxdays !== undefined && day > ev.maxdays) {
            return false;
        }
        return true;
    }

    function weather(ev, climate) {
        if (ev.weather !== undefined) {
            var w = ev.weather;
            var fog = climate.fog >= 0.5;
            var any = (w.rain && climate.rain) || (w.snow && climate.snow) || (w.storm && climate.storm)
                || (w.fog && fog) || (w.clear && !climate.rain && !climate.snow && !climate.storm && !fog);
            if (!any) {
                return false;
            }
        }
        if (ev.tempmin !== undefined && climate.temp < ev.tempmin) {
            return false;
        }
        if (ev.tempmax !== undefined && climate.temp > ev.tempmax) {
            return false;
        }
        return true;
    }

    function nthHits(nth, count) {
        return Phase.wrap(count - nth.k, nth.n) === 0;
    }

    // Returns false, and records nothing, when an event measured in hours would already be over.
    function start(ledger, ev, startsAt, now, log) {
        if (ev["for"].hours !== undefined && startsAt + ev["for"].hours <= now + TOLERANCE) {
            ledger.current = undefined;
            log(ev.id + " missed: its time was over before it could start");
            return false;
        }
        ledger.serial = ledger.serial + 1;
        var current = { id: ev.id, track: ev.track, serial: ledger.serial, running: true, startsAt: startsAt };
        if (ev["for"].hours !== undefined) {
            current.endsAt = startsAt + ev["for"].hours;
        } else {
            current.phasesLeft = ev["for"].phases;
        }
        ledger.current = current;
        ledger.lastStart[ev.id] = startsAt;
        ledger.lastDay[ev.id] = worldDay(ledger.occasion, startsAt);
        delete ledger.roll[ev.id];
        // The event replaces the phase's own line, which isn't shown again when it ends.
        delete ledger.occasion.serial;
        return true;
    }

    function finish(ledger, log, why) {
        var current = ledger.current;
        ledger.follow[current.id] = { sun: true, moon: true };
        ledger.current = undefined;
        log(current.id + " ended: " + why);
    }

    // Picks among the pool of the occasion's track, each event as it would start, not before `earliest`.
    function pick(ledger, defs, climate, roll, earliest, log) {
        var occasion = ledger.occasion;
        var track = trackOf(occasion.phase);
        var name = label(occasion);
        var candidates = [];
        ledger.pool[track].ids.forEach(function (id) {
            var ev = defs.byId[id];
            if (ev !== undefined && ev.track === track) {
                var last = ledger.lastStart[id];
                var when = startTime(ev, occasion, earliest);
                var wait = null;
                if (ev.cooldown !== undefined && last !== undefined && when < last + ev.cooldown - TOLERANCE) {
                    wait = "is cooling down";
                } else if (ev.interval !== undefined) {
                    wait = waiting(ledger, ev, occasion, when, roll);
                }
                if (wait !== null) {
                    log(name + ": " + id + " " + wait);
                } else if (!weather(ev, climate)) {
                    log(name + ": " + id + " weather doesn't match");
                } else {
                    candidates.push(ev);
                }
            }
        });
        candidates.sort(function (a, b) {
            if (a.prio !== b.prio) {
                return b.prio - a.prio;
            }
            return a.order - b.order;
        });
        for (var i = 0; i < candidates.length; i++) {
            var ev = candidates[i];
            var head = name + ": " + ev.id + " prio " + luaString(ev.prio);
            if (ev.chance === undefined || ev.chance >= 100) {
                log(head + ": chosen");
                return ev;
            } else if (ev.chance <= 0) {
                log(head + ": chance 0");
            } else {
                var rolled = roll();
                var text = head + " rolled " + format1(rolled);
                if (rolled < ev.chance) {
                    log(text + " < " + luaString(ev.chance) + ": chosen");
                    return ev;
                }
                log(text + ", not < " + luaString(ev.chance));
            }
        }
        log(name + ": no event");
        return undefined;
    }

    function schedule(ledger, ev, earliest, now, log) {
        var occasion = ledger.occasion;
        var at = startTime(ev, occasion, earliest);
        if (at <= now + TOLERANCE) {
            start(ledger, ev, at, now, log);
            return;
        }
        ledger.current = { id: ev.id, track: ev.track, running: false, at: at };
        log(label(occasion) + ": " + ev.id + " waits for its start time");
    }

    function decide(ledger, defs, input, log) {
        var occasion = ledger.occasion;
        var track = trackOf(occasion.phase);
        var name = label(occasion);
        var covering;
        if (ledger.current !== undefined && ledger.current.running) {
            covering = ledger.current.id;
        }

        var chained = dict();
        Object.keys(ledger.follow).forEach(function (id) {
            var flags = ledger.follow[id];
            if (flags[track]) {
                chained[id] = true;
                delete flags[track];
            }
            if (!flags.sun && !flags.moon) {
                delete ledger.follow[id];
            }
        });

        var climate = input.climate();
        var day = worldDay(occasion, input.now);
        var ids = [];
        defs.events.forEach(function (ev) {
            if (ev.track === track && calendar(ev, occasion, day, climate)) {
                var ok = true;
                if (ev.nth !== undefined) {
                    var count = (ledger.count[ev.id] || 0) + 1;
                    ledger.count[ev.id] = count;
                    ok = nthHits(ev.nth, count);
                    log(name + ": " + ev.id + " count " + luaString(count) + (ok ? ", nth hits" : ""));
                }
                if (ok && ev.after !== undefined) {
                    ok = ev.after.some(function (id) {
                        return chained[id] === true;
                    });
                }
                if (ok) {
                    ids.push(ev.id);
                }
            }
        });
        ledger.decided[track] = occasion.key;
        ledger.pool[track] = { key: occasion.key, ids: ids, covered: covering };

        if (covering !== undefined) {
            log(name + ": covered by " + covering);
            return;
        }
        var ev = pick(ledger, defs, climate, input.roll, occasion.start, log);
        // The phase's own announcement belongs to this start until an event takes over.
        ledger.serial = ledger.serial + 1;
        ledger.occasion.serial = ledger.serial;
        if (ev !== undefined) {
            schedule(ledger, ev, occasion.start, input.now, log);
        }
    }

    // Counts a phase change and moves the ledger to the clock's occasion, which is endless while the
    // clock's is.
    function advance(ledger, input, log) {
        var seen = ledger.occasion;
        var occasion = input.occasion;
        if (seen !== undefined && seen.phase === occasion.phase && (occasion.endless || seen.key === input.key)) {
            // Until it is decided the occasion follows the clock: in a world created at 07:00 the
            // world age jumps by a day on the first frame.
            if (ledger.decided[trackOf(seen.phase)] !== seen.key) {
                seen.open = occasion.open;
                seen.start = occasion.start;
            }
        } else {
            var current = ledger.current;
            if (seen !== undefined && current !== undefined) {
                if (!current.running) {
                    log(current.id + " missed: the " + label(seen) + " ended before its start time");
                    ledger.current = undefined;
                } else if (current.phasesLeft !== undefined) {
                    current.phasesLeft = current.phasesLeft - 1;
                }
            }
            ledger.occasion = {
                phase: occasion.phase, key: input.key, date: occasion.date, open: occasion.open, start: occasion.start,
            };
        }
        ledger.occasion.endless = occasion.endless;
    }

    // input: { occasion (Phase.occasion), key, now = world-age hours, ready = the climate has updated,
    // climate() = { rain, snow, storm, fog, temp, season }, roll() = 0 <= n < 100 }.
    Schedule.tick = function (ledger, defs, input, log) {
        // Before the climate's first update the season may still hold yesterday's dawn and dusk.
        if (ledger.occasion === undefined || input.ready) {
            advance(ledger, input, log);
        }

        var current = ledger.current;
        if (current !== undefined) {
            var ev = defs.byId[current.id];
            if (ev === undefined) {
                if (current.running) {
                    finish(ledger, log, "its definition is gone");
                } else {
                    log(current.id + " dropped: its definition is gone");
                    ledger.current = undefined;
                }
            } else if (current.running && ((current.phasesLeft !== undefined && current.phasesLeft <= 0)
                || (current.endsAt !== undefined && input.now >= current.endsAt - TOLERANCE))) {
                finish(ledger, log, "its time is up");
            } else {
                // A changed definition keeps the computed end; its effects follow from now on.
                current.track = ev.track;
            }
        }

        var track = trackOf(ledger.occasion.phase);
        if (ledger.decided[track] !== ledger.occasion.key && input.ready) {
            decide(ledger, defs, input, log);
        }

        current = ledger.current;
        if (current !== undefined && !current.running && input.now >= current.at - TOLERANCE
            && start(ledger, defs.byId[current.id], current.at, input.now, log)) {
            log(current.id + " started at its start time");
        }
    };

    // ------------------------------------------------------------------ the calendar's game clock

    var Sim = {};

    // Days since 0000-03-01 of the proleptic Gregorian calendar, which the game's dates follow.
    function dayNumber(date) {
        var y = date.year - (date.month < 2 ? 1 : 0);
        var era = Math.floor(y / 400);
        var yoe = y - era * 400;
        var mp = (date.month + 10) % 12;
        var doy = Math.floor((153 * mp + 2) / 5) + date.day - 1;
        return era * 146097 + yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
    }

    function fromDayNumber(n) {
        var era = Math.floor(n / 146097);
        var doe = n - era * 146097;
        var yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
        var doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
        var mp = Math.floor((5 * doy + 2) / 153);
        var day = doy - Math.floor((153 * mp + 2) / 5) + 1;
        var m = (mp + 2) % 12;
        return { year: yoe + era * 400 + (m < 2 ? 1 : 0), month: m, day: day };
    }

    Sim.daysBetween = function (a, b) {
        return dayNumber(b) - dayNumber(a);
    };

    Sim.addDays = function (date, n) {
        return fromDayNumber(dayNumber(date) + n);
    };

    // begin: { year, month (0-11), day, minute of the day }. at(n) is the clock n in-game minutes
    // later. World age counts from 07:00 and turns a day each time the clock passes 07:00; a world
    // created at 07:00 sharp counts that on its first frame.
    Sim.clock = function (begin) {
        var first = begin.minute;
        var base = dayNumber(begin);
        // The 07:00 the world age counts from, once it has turned.
        var origin = first > 420 ? 0 : -1;
        return {
            at: function (n) {
                var total = first + n;
                var days = Math.floor(total / 1440);
                var minute = total - days * 1440;
                var date = fromDayNumber(base + days);
                var nights = Math.floor((total - 420) / 1440) - Math.floor((first - 420) / 1440) + (first === 420 && n >= 1 ? 1 : 0);
                var time = minute / 60;
                var hours = time >= 7 ? nights * 24 + time - 7 : nights * 24 + time + 17;
                return { year: date.year, month: date.month, day: date.day, time: time, hours: hours, minute: minute };
            },
            // The date and minute of the day at world-age hours h.
            moment: function (h) {
                var minutes = Math.round(h * 60) + 420;
                var days = Math.floor(minutes / 1440);
                var date = fromDayNumber(base + origin + days);
                date.minute = minutes - days * 1440;
                return date;
            },
        };
    };

    // The minutes of the day at which the occasion can change.
    function boundaries(rule) {
        if (rule.mode === 1) {
            return rule.start === rule.finish ? [] : [rule.start * 60, rule.finish * 60];
        }
        if (rule.endless != null) {
            return [];
        }
        var out = [720];
        var dawn = Math.floor(rule.dawn * 60), dusk = Math.floor(rule.dusk * 60);
        for (var d = -1; d <= 2; d++) {
            out.push(Phase.wrap(dawn + d, 1440), Phase.wrap(dusk + d, 1440));
        }
        return out;
    }

    // Runs Schedule.tick from the world's start for o.minutes in-game minutes, at every minute where
    // something can change; a minute in between would find nothing to do, as in the game.
    // o: { defs, rule, start, minutes, roll(), climate(now), record = false to keep only the runs }.
    // Returns { occasions, runs, clock }: occasions in order { phase, key, date, open, start, endless, end, pool,
    // waits (each interval= event of the track right after its decision: { id, unit, from, to }), logs,
    // each { hours, text } as the mod logs it }, runs { id, track, serial, startsAt, endedAt (null while
    // still running) }.
    Sim.run = function (o) {
        var keep = o.record !== false;
        var clock = Sim.clock(o.start);
        var ledger = {};
        Schedule.prepare(ledger);
        var marks = boundaries(o.rule);
        var occasions = [], runs = [];
        var record = null, active = null, now = null;
        var input = {
            climate: function () {
                return o.climate(now);
            },
            roll: o.roll,
        };

        function occasionRecord() {
            var occ = ledger.occasion;
            if (record === null || record.source !== occ) {
                if (record !== null) {
                    record.end = occ.start;
                }
                record = { source: occ, phase: occ.phase, key: occ.key, date: occ.date, end: null, pool: null, waits: [], logs: [] };
                occasions.push(record);
            }
            return record;
        }

        function log(text) {
            if (!keep) {
                return;
            }
            occasionRecord().logs.push({ hours: now.hours, text: text });
        }

        function tick(n) {
            now = clock.at(n);
            var occasion = Phase.occasion(now, o.rule);
            input.occasion = occasion;
            input.key = Phase.key(occasion.date);
            input.now = now.hours;
            input.ready = n > 0;
            Schedule.tick(ledger, o.defs, input, log);
            if (keep) {
                var r = occasionRecord();
                var track = trackOf(r.phase);
                var pool = ledger.pool[track];
                if (pool !== undefined && pool.key === r.key && r.pool !== pool) {
                    r.pool = pool;
                    r.waits = o.defs.events.filter(function (ev) {
                        return ev.track === track && ev.interval !== undefined;
                    }).map(function (ev) {
                        var d = Schedule.due(ledger, ev);
                        return { id: ev.id, unit: d[0], from: d[1], to: d[2] };
                    });
                }
            }
            var current = ledger.current;
            var running = current !== undefined && current.running ? current : null;
            if (active !== null && (running === null || running.serial !== active.serial)) {
                active.endedAt = now.hours;
                active = null;
            }
            if (running !== null && active === null) {
                active = { id: running.id, track: running.track, serial: running.serial, startsAt: running.startsAt, endedAt: null };
                runs.push(active);
            }
        }

        // The first minute after n whose world age is at least h, less the tolerance.
        function reach(n, h) {
            var target = h - TOLERANCE;
            var m = n + Math.max(1, Math.ceil((target - clock.at(n).hours) * 60));
            while (m > n + 1 && clock.at(m - 1).hours >= target) {
                m--;
            }
            while (clock.at(m).hours < target) {
                m++;
            }
            return m;
        }

        function next(n) {
            var best = o.minutes + 1;
            var minute = clock.at(n + 1).minute;
            marks.forEach(function (mark) {
                best = Math.min(best, n + 1 + Phase.wrap(mark - minute, 1440));
            });
            var current = ledger.current;
            if (current !== undefined) {
                if (!current.running) {
                    best = Math.min(best, reach(n, current.at));
                } else if (current.endsAt !== undefined) {
                    best = Math.min(best, reach(n, current.endsAt));
                }
            }
            return best;
        }

        tick(0);
        for (var n = 1; n <= o.minutes; n = next(n)) {
            tick(n);
        }
        occasions.forEach(function (r) {
            r.open = r.source.open;
            r.start = r.source.start;
            r.endless = r.source.endless;
            delete r.source;
        });
        return { occasions: occasions, runs: runs, clock: clock };
    };

    // mulberry32: a small seedable generator, 0 <= n < 1.
    Sim.random = function (seed) {
        var a = seed >>> 0;
        return function () {
            a = (a + 0x6D2B79F5) >>> 0;
            var t = a;
            t = Math.imul(t ^ (t >>> 15), t | 1);
            t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
        };
    };

    // ------------------------------------------------------------------ options, outputs and import

    // In sandbox-options.txt order.
    var OPTION_ORDER = ["NightMode", "NightStartHour", "NightEndHour"].concat(Defs.OPTIONS);

    var DEFAULTS = {
        NightMode: 1,
        NightStartHour: 20,
        NightEndHour: 4,
        Day: "speed=+25;health=0.7",
        Night: "speed=-50;rise=50;wake=true;off=mutants",
        Events1: "id=bloodmoon;track=moon;moon=full;chance=50;prio=10;speed=+50;rise=100;wake=true;off=none;say=@IGUI_Crepuscular_BloodMoon;color=ff3c3c",
        Events2: "",
        Events3: "",
        Events4: "",
        Events5: "",
        Events6: "",
        Events7: "",
        Events8: "",
        Kinds: "",
    };

    // Every Crepuscular option, for set. entries that name one.
    var OWN_OPTIONS = OPTION_ORDER.concat(["KeepDistance", "RemovalsPerMinute", "MutantRequeue", "ZombiesPerSweep",
        "RiseDelayMin", "RiseDelayMax", "MaxRises", "RiseMaxAgeHours", "FireStaysDown", "FinishOff", "FinishOffSeconds",
        "HeadHitsStayDown", "RiseInSafehouses", "RisePlayers", "RiseKinds", "RisesPerScan", "RiserLimit", "Notifications", "Verbose"]);

    // Cry of Fear Monster NPCs options a definition sets for its spawn levels (1 = None ... 5 = High).
    var COF_OPTIONS = {
        "COF_Spawns.Regular": { type: "enum", min: 1, max: 5 },
        "COF_Spawns.Sawcrazy": { type: "enum", min: 1, max: 5 },
        "COF_Spawns.Sawrunner": { type: "enum", min: 1, max: 5 },
        "COF_Spawns.Stranger": { type: "enum", min: 1, max: 5 },
        "COF_Spawns.Drowned": { type: "enum", min: 1, max: 5 },
        "COF_Spawns.HumanFlowers": { type: "boolean" },
        "COF_Sawrunner.NightEvent": { type: "boolean" },
        "COF_Spawns.NightOnly": { type: "boolean" },
    };

    // Double.valueOf, which Kahlua's tonumber uses, for finite decimals; null for anything else.
    function javaNumber(text) {
        var t = text.replace(/^[\x00-\x20]+|[\x00-\x20]+$/g, "");
        if (!/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?[fFdD]?$/.test(t)) {
            return null;
        }
        return Number(t.replace(/[fFdD]$/, ""));
    }

    // Overrides.check, for the options the builder knows: Crepuscular's own and Cry of Fear's levels.
    // The game checks the rest when it loads.
    function overrideWarnings(label, entries, warnings) {
        Object.keys(entries).sort().forEach(function (name) {
            var text = entries[name];
            var why = null;
            if (name.slice(0, 12) === "Crepuscular.") {
                why = OWN_OPTIONS.indexOf(name.slice(12)) < 0 ? "no such sandbox option" : "Crepuscular's own options can't be set";
            } else if (COF_OPTIONS[name] !== undefined) {
                var option = COF_OPTIONS[name];
                if (option.type === "boolean") {
                    if (lower(text) !== "true" && lower(text) !== "false") {
                        why = "'" + text + "' is not a valid boolean";
                    }
                } else {
                    var n = javaNumber(text);
                    if (n === null || !isFinite(n) || n < option.min || n > option.max || n !== Math.floor(n)) {
                        why = "'" + text + "' is not a valid enum from " + option.min + " to " + option.max;
                    }
                }
            }
            if (why !== null) {
                warnings.push(label + ": set." + name + ": " + why);
            }
        });
    }

    // Everything the mod checks and logs for these options, as it words it.
    // values: option name -> value (definition texts and the clock options); registered: kind names
    // other mods register; forge: the kinds of the Zomboid Forge types in the game.
    function check(values, registered, forge) {
        var rule = { mode: values.NightMode, start: values.NightStartHour, finish: values.NightEndHour };
        var texts = {};
        Defs.OPTIONS.forEach(function (name) {
            texts[name] = values[name];
        });
        var reg = dict();
        registered.forEach(function (name) {
            reg[name] = true;
        });
        var builtin = dict({ cof: true, mutants: true });
        (forge || []).forEach(function (name) {
            builtin[name] = true;
        });
        var defs = Defs.parse(texts, rule, builtin, reg);
        var errors = defs.errors.slice();
        var warnings = [];
        if (rule.mode === 1 && rule.start === rule.finish) {
            warnings.push("NightStartHour equals NightEndHour (" + rule.start + "), so there is no night");
        }
        warnings = warnings.concat(defs.warnings);
        [defs.day, defs.night].concat(defs.events).forEach(function (def) {
            overrideWarnings(def.label, def.set, warnings);
        });
        var sizes = {};
        Defs.OPTIONS.forEach(function (name) {
            var bytes = Defs.bytes(texts[name]);
            sizes[name] = bytes;
            if (bytes > Defs.LIMIT) {
                errors.push(name + " is " + bytes + " bytes; above 32767 the game silently"
                    + " corrupts the save and the connect packet, so keep each option under " + Defs.LIMIT);
            }
        });
        return {
            defs: defs, rule: rule, errors: errors, warnings: warnings, sizes: sizes,
            summary: defs.events.length + " events loaded, " + defs.failed + " definitions with errors",
        };
    }

    // Lines and fields with their own case, for the editor: the same splits Defs.parse makes.
    var Text = {};

    Text.events = function (slotText) {
        return items(slotText, "|", strip);
    };

    Text.fields = function (text) {
        return items(strip(text), ";", trim).map(function (field) {
            var eq = field.indexOf("=");
            if (eq < 0) {
                return { name: "", value: field, eq: false };
            }
            return { name: trim(field.slice(0, eq)), value: trim(field.slice(eq + 1)), eq: true };
        });
    };

    Text.join = function (fieldList) {
        return fieldList.map(function (f) {
            return f.eq ? f.name + "=" + f.value : f.value;
        }).join(";");
    };

    var Output = {};

    function isText(name) {
        return typeof DEFAULTS[name] === "string";
    }

    // The text without the line ends and spaces the mod ignores around an option and around each of
    // its events, so a pasted CR/LF can't end up inside a Lua or env string.
    Output.clean = function (name, value) {
        if (!isText(name)) {
            return value;
        }
        if (Defs.SLOTS.indexOf(name) >= 0) {
            return Text.events(value).join("|");
        }
        return strip(value);
    };

    // As StringConfigOption.getValueAsLuaString writes it.
    function luaValue(name, value) {
        if (!isText(name)) {
            return String(value);
        }
        return "\"" + value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    // The lines of the Crepuscular table in a SandboxVars.lua file, indented as the game writes them.
    Output.lua = function (values, names) {
        return names.map(function (name) {
            return "        " + name + " = " + luaValue(name, values[name]) + ",";
        }).join("\n");
    };

    // Compose's env_file: single quotes keep everything literal, except a backslash before the closing
    // quote; double quotes interpolate $ and take \ escapes.
    function envValue(name, value) {
        if (!isText(name)) {
            return String(value);
        }
        if (value.indexOf("'") < 0 && value.slice(-1) !== "\\") {
            return "'" + value + "'";
        }
        return "\"" + value.replace(/[\\"$]/g, "\\$&") + "\"";
    }

    Output.env = function (values, names) {
        return names.map(function (name) {
            return "SANDBOX_Crepuscular__" + name + "=" + envValue(name, values[name]);
        }).join("\n");
    };

    var Import = {};

    // "env", "lua" or "text".
    Import.detect = function (text) {
        if (/^\s*(export\s+)?SANDBOX_Crepuscular__/m.test(text)) {
            return "env";
        }
        var names = OPTION_ORDER.join("|");
        if (/\bCrepuscular\s*=\s*\{/.test(text) || new RegExp("^\\s*(" + names + ")\\s*=\\s*([\"'\\[]|-?[0-9]|true\\b|false\\b)", "m").test(text)) {
            return "lua";
        }
        return "text";
    };

    // Settings.lua's check of a value read from a file: the type and range the option takes.
    function accept(name, value, out) {
        if (OPTION_ORDER.indexOf(name) < 0) {
            out.ignored.push(name);
            return;
        }
        var ok;
        if (isText(name)) {
            ok = typeof value === "string";
        } else {
            var max = name === "NightMode" ? 2 : 23;
            var min = name === "NightMode" ? 1 : 0;
            ok = typeof value === "number" && value === Math.floor(value) && value >= min && value <= max;
        }
        if (ok) {
            out.values[name] = value;
        } else {
            out.problems.push("Crepuscular." + name + " is " + (typeof value === "string" ? value : luaString(value))
                + ", which is not a valid value; using " + DEFAULTS[name]);
        }
    }

    var LUA_ESCAPES = { a: "\x07", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t", v: "\v", "\\": "\\", "\"": "\"", "'": "'", "\n": "\n" };

    function luaTokens(src) {
        var tokens = [], i = 0, n = src.length;
        function longBracket(at) {
            var m = /^\[(=*)\[/.exec(src.slice(at, at + 64));
            if (m === null) {
                return null;
            }
            var close = "]" + m[1] + "]";
            var end = src.indexOf(close, at + m[0].length);
            if (end < 0) {
                throw new Error("an unfinished long string or comment");
            }
            var body = src.slice(at + m[0].length, end);
            return { body: body.charAt(0) === "\n" ? body.slice(1) : body, end: end + close.length };
        }
        while (i < n) {
            var c = src.charAt(i);
            if (/\s/.test(c)) {
                i++;
            } else if (src.slice(i, i + 2) === "--") {
                var block = longBracket(i + 2);
                if (block !== null) {
                    i = block.end;
                } else {
                    var eol = src.indexOf("\n", i);
                    i = eol < 0 ? n : eol + 1;
                }
            } else if (c === "\"" || c === "'") {
                var out = "";
                i++;
                while (true) {
                    if (i >= n || src.charAt(i) === "\n") {
                        throw new Error("an unfinished string");
                    }
                    var d = src.charAt(i);
                    if (d === c) {
                        i++;
                        break;
                    }
                    if (d === "\\") {
                        var e = src.charAt(i + 1);
                        var digits = /^[0-9]{1,3}/.exec(src.slice(i + 1, i + 4));
                        if (digits !== null) {
                            out += String.fromCharCode(Number(digits[0]));
                            i += 1 + digits[0].length;
                        } else {
                            out += LUA_ESCAPES[e] !== undefined ? LUA_ESCAPES[e] : e;
                            i += 2;
                        }
                    } else {
                        out += d;
                        i++;
                    }
                }
                tokens.push({ type: "string", value: out });
            } else if (c === "[" && longBracket(i) !== null) {
                var long = longBracket(i);
                tokens.push({ type: "string", value: long.body });
                i = long.end;
            } else {
                var m = /^(0[xX][0-9a-fA-F]+|[0-9]+\.?[0-9]*([eE][+-]?[0-9]+)?|\.[0-9]+([eE][+-]?[0-9]+)?)/.exec(src.slice(i));
                if (m !== null) {
                    tokens.push({ type: "number", value: Number(m[0]) });
                    i += m[0].length;
                    continue;
                }
                m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(src.slice(i));
                if (m !== null) {
                    var word = m[0];
                    tokens.push(word === "true" || word === "false" ? { type: "boolean", value: word === "true" } : { type: "name", value: word });
                    i += word.length;
                    continue;
                }
                tokens.push({ type: "symbol", value: c });
                i++;
            }
        }
        return tokens;
    }

    // A SandboxVars.lua file, its Crepuscular = { ... } table, or lines of that table.
    Import.lua = function (text) {
        var out = { values: {}, ignored: [], problems: [] };
        var tokens;
        try {
            tokens = luaTokens(text);
        } catch (e) {
            out.problems.push("The Lua text has " + e.message + ".");
            return out;
        }
        function symbol(t, value) {
            return t !== undefined && t.type === "symbol" && t.value === value;
        }
        var from = 0, to = tokens.length;
        for (var i = 0; i + 2 < tokens.length; i++) {
            if (tokens[i].type === "name" && tokens[i].value === "Crepuscular" && symbol(tokens[i + 1], "=")
                && symbol(tokens[i + 2], "{")) {
                from = i + 3;
                var depth = 1;
                for (to = from; to < tokens.length; to++) {
                    if (symbol(tokens[to], "{")) {
                        depth++;
                    } else if (symbol(tokens[to], "}") && --depth === 0) {
                        break;
                    }
                }
                break;
            }
        }
        for (var j = from; j < to; j++) {
            var t = tokens[j], v = tokens[j + 2];
            if (t.type !== "name" || !symbol(tokens[j + 1], "=") || v === undefined) {
                continue;
            }
            if (symbol(v, "-") && tokens[j + 3] !== undefined && tokens[j + 3].type === "number") {
                accept(t.value, -tokens[j + 3].value, out);
                j += 3;
            } else if (v.type === "string" || v.type === "number" || v.type === "boolean") {
                accept(t.value, v.value, out);
                j += 2;
            } else if (symbol(v, "{")) {
                out.ignored.push(t.value);
                var level = 0;
                for (j += 2; j < to; j++) {
                    if (symbol(tokens[j], "{")) {
                        level++;
                    } else if (symbol(tokens[j], "}") && --level === 0) {
                        break;
                    }
                }
            }
        }
        return out;
    };

    var GO_ESCAPES = { a: "\x07", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t", v: "\v", "\\": "\\" };

    // The value part of an env_file line, as Compose reads it.
    function readEnvValue(raw, problems, name) {
        var s = raw.replace(/^[ \t]+/, "");
        var q = s.charAt(0);
        var value = "";
        if (q !== "'" && q !== "\"") {
            value = s.split(" #")[0].replace(/\s+$/, "");
        } else {
            var escaped = false, closed = false;
            for (var i = 1; i < s.length; i++) {
                var c = s.charAt(i);
                if (c !== q) {
                    if (!escaped && c === "\\") {
                        escaped = true;
                        continue;
                    }
                    if (escaped) {
                        escaped = false;
                        value += "\\";
                    }
                    value += c;
                } else if (escaped) {
                    escaped = false;
                    value += c;
                } else {
                    closed = true;
                    break;
                }
            }
            if (!closed) {
                problems.push(name + ": the closing " + q + " is missing");
            }
            if (q === "'") {
                return value;
            }
            value = value.replace(/\\(.)/g, function (all, e) {
                if (e === "$") {
                    return "$$";
                }
                return GO_ESCAPES[e] !== undefined ? GO_ESCAPES[e] : all;
            });
        }
        if (/\$(\{?[A-Za-z0-9_]|\()/.test(value.replace(/\$\$/g, ""))) {
            problems.push(name + ": Compose replaces $NAME in this value with that variable; write \\$ in double quotes or use single quotes");
        }
        return value.replace(/\$\$/g, "$");
    }

    // SANDBOX_Crepuscular__Name=value lines of an env file.
    Import.env = function (text) {
        var out = { values: {}, ignored: [], problems: [] };
        text.split(/\r?\n/).forEach(function (line) {
            var m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$/.exec(line);
            if (m === null || /^\s*#/.test(line)) {
                return;
            }
            var key = /^SANDBOX_Crepuscular__(.+)$/.exec(m[1]);
            if (key === null) {
                out.ignored.push(m[1]);
                return;
            }
            var name = key[1];
            var value = readEnvValue(m[2], out.problems, m[1]);
            if (OPTION_ORDER.indexOf(name) >= 0 && !isText(name)) {
                accept(name, /^-?[0-9]+$/.test(value) ? Number(value) : value, out);
            } else {
                accept(name, value, out);
            }
        });
        return out;
    };

    return {
        Phase: Phase,
        Defs: Defs,
        Schedule: Schedule,
        Sim: Sim,
        Output: Output,
        Import: Import,
        Text: Text,
        DEFAULTS: DEFAULTS,
        OPTION_ORDER: OPTION_ORDER,
        COF_OPTIONS: COF_OPTIONS,
        check: check,
        luaString: luaString,
    };
});
