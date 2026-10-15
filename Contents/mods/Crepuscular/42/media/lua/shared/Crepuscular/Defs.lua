-- Parses the Day, Night, Events1-8 and Kinds options. Pure: the clock rule and the kinds code
-- registers are passed in.
local Phase = require "Crepuscular/Phase"

local Defs = {}

Defs.BASES = { "Day", "Night" }
Defs.SLOTS = { "Events1", "Events2", "Events3", "Events4", "Events5", "Events6", "Events7", "Events8" }
Defs.KINDS = "Kinds"
Defs.OPTIONS = {}
for _, list in ipairs({ Defs.BASES, Defs.SLOTS, { Defs.KINDS } }) do
    for _, name in ipairs(list) do
        Defs.OPTIONS[#Defs.OPTIONS + 1] = name
    end
end

-- The game stores each string option behind a signed 16-bit byte count.
Defs.LIMIT = 32000

local MOONS = {
    new = 0, waxingcrescent = 1, firstquarter = 2, waxinggibbous = 3,
    full = 4, waninggibbous = 5, thirdquarter = 6, waningcrescent = 7,
}
-- The game's season numbers: 3 is the second half of summer.
local SEASONS = { spring = { 1 }, summer = { 2, 3 }, autumn = { 4 }, winter = { 5 } }
local WEATHER = { rain = true, snow = true, storm = true, fog = true, clear = true }
local MONTH_DAYS = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local MAX_PHASES = 60
local MAX_HOURS = 30 * 24
local MAX_COOLDOWN_HOURS = 3650 * 24

local CONDITIONS = {
    "moon", "date", "month", "season", "every", "nth", "mindays", "maxdays",
    "after", "cooldown", "weather", "tempmin", "tempmax", "chance",
}

-- UTF-8 bytes, as the game writes the option. Kahlua strings are Java strings: string.byte gives
-- UTF-16 units, and a surrogate pair is 4 bytes.
function Defs.bytes(text)
    local n = 0
    for i = 1, #text do
        local c = string.byte(text, i)
        if c < 128 then
            n = n + 1
        elseif c < 2048 or (c >= 55296 and c <= 57343) then
            n = n + 2
        else
            n = n + 3
        end
    end
    return n
end

local function trim(text)
    return string.match(text, "^ *(.-) *$")
end

-- Line endings around an option or an event come from pasted text and env files.
local function strip(text)
    return string.match(text, "^%s*(.-)%s*$")
end

local function split(text, separator)
    local parts, from = {}, 1
    while true do
        local i, j = string.find(text, separator, from, true)
        if i == nil then
            parts[#parts + 1] = string.sub(text, from)
            return parts
        end
        parts[#parts + 1] = string.sub(text, from, i - 1)
        from = j + 1
    end
end

-- Non-empty parts, each cleaned by clean.
local function items(text, separator, clean)
    local list = {}
    for _, part in ipairs(split(text, separator)) do
        part = clean(part)
        if part ~= "" then
            list[#list + 1] = part
        end
    end
    return list
end

local function number(text, whole)
    local sign, body = string.match(text, "^([+-]?)(.*)$")
    local ok = string.find(body, "^[0-9]+$") ~= nil
    if not whole and not ok then
        ok = string.find(body, "^[0-9]+%.[0-9]*$") ~= nil or string.find(body, "^%.[0-9]+$") ~= nil
    end
    if not ok then
        return nil
    end
    local n = tonumber(body)
    if sign == "-" then
        n = -n
    end
    return n
end

local function quote(text)
    return "'" .. text .. "'"
end

local function ranged(text, whole, min, max, what)
    local n = number(text, whole)
    if n == nil or n < min or n > max then
        return nil, quote(text) .. " is not " .. what
    end
    return n
end

-- A list where each item is parsed by `one`; returns a set, or nil and the reason.
local function list(text, one, what)
    local parts = items(text, ",", trim)
    if #parts == 0 then
        return nil, quote(text) .. " is not " .. what
    end
    local set = {}
    for _, item in ipairs(parts) do
        local ok = one(item, set)
        if not ok then
            return nil, quote(item) .. " is not " .. what
        end
    end
    return set
end

-- "a..b" -> a, b; anything else -> the text, nil.
local function range(text)
    local i, j = string.find(text, "..", 1, true)
    if i == nil then
        return text, nil
    end
    return trim(string.sub(text, 1, i - 1)), trim(string.sub(text, j + 1))
end

local function monthDay(text)
    local m, d = string.match(text, "^([0-9][0-9]?)-([0-9][0-9]?)$")
    m, d = tonumber(m), tonumber(d)
    if m == nil or m < 1 or m > 12 or d < 1 or d > MONTH_DAYS[m] then
        return nil
    end
    return m * 100 + d
end

local function month(text)
    local m = number(text, true)
    if m == nil or m < 1 or m > 12 then
        return nil
    end
    return m
end

-- N or N+K.
local function cycle(text)
    local n, k = string.match(text, "^([0-9]+) *%+ *([0-9]+)$")
    if n == nil then
        n = string.match(text, "^([0-9]+)$")
    end
    return tonumber(n), tonumber(k)
end

local function idText(text)
    return string.find(text, "^[a-z0-9_]+$") ~= nil
end

local function hourText(hours)
    local minutes = math.floor(hours * 60 + 0.5)
    return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

local PARSE = {}

function PARSE.id(v)
    if not idText(v) then
        return nil, quote(v) .. " is not made of a-z, 0-9 and _"
    end
    return v
end

function PARSE.track(v)
    if v ~= "sun" and v ~= "moon" then
        return nil, quote(v) .. " is not sun or moon"
    end
    return v
end

function PARSE.at(v)
    local h, m = string.match(v, "^([0-9][0-9]?):([0-9][0-9])$")
    if h == nil then
        h, m = string.match(v, "^([0-9][0-9]?)$"), "0"
    end
    h, m = tonumber(h), tonumber(m)
    if h == nil or h > 23 or m > 59 then
        return nil, quote(v) .. " is not HH or HH:MM"
    end
    return h + m / 60
end

PARSE["for"] = function(v)
    if v == "phase" then
        return { phases = 1 }
    end
    local n = string.match(v, "^([0-9]+)p$")
    if n ~= nil then
        n = tonumber(n)
        if n < 1 or n > MAX_PHASES then
            return nil, quote(v) .. " is not 1 to " .. MAX_PHASES .. " phases"
        end
        return { phases = n }
    end
    local amount, unit = string.match(v, "^(.-) *([hd])$")
    local x = amount and number(amount, false)
    if x == nil then
        return nil, quote(v) .. " is not phase, Np, Xh or Xd"
    end
    if unit == "d" then
        x = x * 24
    end
    if x <= 0 then
        return nil, quote(v) .. " is not longer than 0"
    end
    if x > MAX_HOURS then
        return nil, quote(v) .. " is over 30 days"
    end
    return { hours = x }
end

function PARSE.prio(v)
    return ranged(v, true, -999, 999, "a whole number from -999 to 999")
end

function PARSE.chance(v)
    return ranged(v, false, 0, 100, "a number from 0 to 100")
end

function PARSE.moon(v)
    return list(v, function(item, set)
        local p = MOONS[item]
        if p == nil then
            p = number(item, true)
            if p == nil or p < 0 or p > 7 then
                return false
            end
        end
        set[p] = true
        return true
    end, "a moon phase")
end

function PARSE.date(v)
    local ranges = {}
    local ok, why = list(v, function(item)
        local a, b = range(item)
        local from = monthDay(a)
        local to = from
        if b ~= nil then
            to = monthDay(b)
        end
        if from == nil or to == nil then
            return false
        end
        ranges[#ranges + 1] = { from = from, to = to }
        return true
    end, "MM-DD or MM-DD..MM-DD")
    if not ok then
        return nil, why
    end
    return ranges
end

function PARSE.month(v)
    return list(v, function(item, set)
        local a, b = range(item)
        local from = month(a)
        local to = from
        if b ~= nil then
            to = month(b)
        end
        if from == nil or to == nil then
            return false
        end
        local m = from
        while true do
            set[m] = true
            if m == to then
                return true
            end
            m = m % 12 + 1
        end
    end, "a month from 1 to 12 or a range of them")
end

function PARSE.season(v)
    return list(v, function(item, set)
        local numbers = SEASONS[item]
        if numbers == nil then
            return false
        end
        for _, n in ipairs(numbers) do
            set[n] = true
        end
        return true
    end, "spring, summer, autumn or winter")
end

function PARSE.every(v)
    local n, k = cycle(v)
    if n == nil or n < 2 or n > 3650 or (k ~= nil and k >= n) then
        return nil, quote(v) .. " is not N or N+K days, N from 2 to 3650 and K below N"
    end
    return { n = n, k = k or 0 }
end

function PARSE.nth(v)
    local n, k = cycle(v)
    if n == nil or n < 1 or n > 1000 or (k ~= nil and (k < 1 or k > n)) then
        return nil, quote(v) .. " is not N or N+K, N from 1 to 1000 and K from 1 to N"
    end
    return { n = n, k = k or n }
end

function PARSE.mindays(v)
    return ranged(v, true, 0, 36500, "a whole number from 0 to 36500")
end

PARSE.maxdays = PARSE.mindays

function PARSE.after(v)
    local order = {}
    local set, why = list(v, function(item, s)
        if not idText(item) then
            return false
        end
        if not s[item] then
            order[#order + 1] = item
        end
        s[item] = true
        return true
    end, "an event id")
    if set == nil then
        return nil, why
    end
    return order
end

function PARSE.cooldown(v)
    local amount, unit = string.match(v, "^(.-) *([hd])$")
    local x = amount and number(amount, false)
    if x ~= nil and unit == "d" then
        x = x * 24
    end
    if x == nil or x <= 0 or x > MAX_COOLDOWN_HOURS then
        return nil, quote(v) .. " is not Xd or Xh, longer than 0 and up to 3650 days"
    end
    return x
end

function PARSE.weather(v)
    return list(v, function(item, set)
        if not WEATHER[item] then
            return false
        end
        set[item] = true
        return true
    end, "rain, snow, storm, fog or clear")
end

function PARSE.tempmin(v)
    return ranged(v, false, -80, 80, "a number from -80 to 80")
end

PARSE.tempmax = PARSE.tempmin

function PARSE.off(v)
    if v == "none" then
        return {}
    end
    local set, why = list(v, function(item, s)
        if not idText(item) then
            return false
        end
        s[item] = true
        return true
    end, "none or a list of kind names")
    if set ~= nil and set.none then
        return nil, "none can't be combined with kind names"
    end
    return set, why
end

function PARSE.say(v)
    if v == "" then
        return nil, "is empty"
    end
    return v
end

function PARSE.color(v)
    if string.find(v, "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") == nil then
        return nil, quote(v) .. " is not a colour as rrggbb"
    end
    return v
end

-- Keys a base definition may have; the rest belong to events.
local EFFECTS = { off = true, say = true, color = true }

-- Splits a definition into fields: { key, option (for set.), value } or { bad = reason }.
local function fields(text)
    local out = {}
    for _, field in ipairs(items(strip(text), ";", trim)) do
        local eq = string.find(field, "=", 1, true)
        local name = ""
        if eq ~= nil then
            name = trim(string.sub(field, 1, eq - 1))
        end
        if string.find(field, "%c") then
            if name == "" or string.find(name, "%c") then
                name = quote((string.gsub(field, "%c", " ")))
            end
            out[#out + 1] = { name = string.lower(name), bad = "contains a control character such as a newline or tab" }
        elseif name == "" then
            out[#out + 1] = { name = quote(field), bad = "is not key=value" }
        else
            local value = trim(string.sub(field, eq + 1))
            local key = string.lower(name)
            local f = { name = key, key = key, value = value }
            if string.sub(key, 1, 4) == "set." then
                f.key = "set."
                f.option = string.sub(name, 5)
                f.name = "set." .. f.option
            elseif key ~= "say" then
                f.value = string.lower(value)
            end
            out[#out + 1] = f
        end
    end
    return out
end

-- Parses one definition's fields into def. report(key or nil, reason) records an error.
-- Returns the set of keys present.
local function parseFields(def, list, isEvent, report)
    local seen = {}
    for _, f in ipairs(list) do
        if f.bad ~= nil then
            report(f.name, f.bad)
        elseif seen[f.name] then
            report(f.name, "is repeated")
        else
            seen[f.name] = true
            if f.key == "set." then
                if f.option == "" then
                    report(f.name, "has no option name")
                else
                    def.set[f.option] = f.value
                end
            elseif PARSE[f.key] == nil then
                report(f.name, "unknown key")
            elseif not isEvent and not EFFECTS[f.key] then
                report(f.name, "only events can have this key")
            else
                local value, why = PARSE[f.key](f.value)
                if value == nil then
                    report(f.name, why)
                else
                    def[f.key] = value
                end
            end
        end
    end
    return seen
end

local function windowText(from, to)
    return hourText(from) .. "-" .. hourText(to)
end

-- The at= of an event with fixed hours must fall inside its track's window, [from, to).
local function checkAt(ev, rule, report)
    if ev.at == nil or ev.track == nil or rule.mode ~= 1 then
        return
    end
    if rule.start == rule.finish then
        if ev.track == "moon" then
            report("at", "there is no night window: NightStartHour equals NightEndHour")
        end
        return
    end
    local from, to, name = rule.finish, rule.start, "day"
    if ev.track == "moon" then
        from, to, name = rule.start, rule.finish, "night"
    end
    if Phase.wrap(ev.at - from, 24) >= Phase.wrap(to - from, 24) then
        report("at", quote(hourText(ev.at)) .. " is outside the " .. name .. " window " .. windowText(from, to))
    end
end

local function newDef(label)
    return { label = label, set = {}, errors = 0 }
end

local function message(label, key, reason)
    if key == nil then
        return label .. ": " .. reason
    end
    return label .. ": " .. key .. ": " .. reason
end

-- The Kinds option: name=prefix,prefix;name=prefix. A bad entry is skipped and the rest kept.
-- Returns { { name, prefixes } } in order, prefixes lowercased.
local function parseKinds(text, builtin, fail)
    local kinds, seen = {}, {}
    for _, f in ipairs(fields(text)) do
        if f.bad ~= nil then
            fail(f.name, f.bad)
        elseif not idText(f.name) then
            fail(quote(f.name), "is not made of a-z, 0-9 and _")
        elseif f.name == "none" or builtin[f.name] then
            fail(f.name, "is a kind name Crepuscular has")
        elseif seen[f.name] then
            fail(f.name, "is repeated")
        else
            seen[f.name] = true
            local prefixes = {}
            local ok, why = list(f.value, function(item, set)
                item = string.lower(item)
                if not set[item] then
                    prefixes[#prefixes + 1] = item
                end
                set[item] = true
                return true
            end, "a list of outfit name prefixes")
            if ok == nil then
                fail(f.name, why)
            else
                kinds[#kinds + 1] = { name = f.name, prefixes = prefixes }
            end
        end
    end
    return kinds
end

-- texts: option name -> text; rule: the clock rule (Phase.occasion); builtin: set of the built-in
-- kind names; registered: set of the names other mods registered, or nil while they may still be
-- missing, which leaves off= unchecked.
-- Returns { day, night, events (valid, in order), byId, ids, kinds, errors, warnings, failed }.
function Defs.parse(texts, rule, builtin, registered)
    local result = { events = {}, byId = {}, ids = {}, errors = {}, warnings = {}, failed = 0 }

    local function warn(def, key, reason)
        result.warnings[#result.warnings + 1] = message(def.label, key, reason)
    end

    local function fail(def, key, reason)
        result.errors[#result.errors + 1] = message(def.label, key, reason)
        def.errors = def.errors + 1
    end

    local option = { label = Defs.KINDS, errors = 0 }
    result.kinds = parseKinds(texts[Defs.KINDS], builtin, function(key, reason)
        fail(option, key, reason)
    end)
    if option.errors > 0 then
        result.failed = result.failed + 1
    end

    local known = nil
    if registered ~= nil then
        known = {}
        for name in pairs(builtin) do
            known[name] = true
        end
        for name in pairs(registered) do
            known[name] = true
        end
        for _, kind in ipairs(result.kinds) do
            if registered[kind.name] then
                warn(option, kind.name, "replaces the kind another mod registered under this name")
            end
            known[kind.name] = true
        end
    end

    local function checkKinds(def)
        if def.off == nil or known == nil then
            return
        end
        local names = {}
        for kind in pairs(def.off) do
            if not known[kind] then
                names[#names + 1] = kind
            end
        end
        table.sort(names)
        for _, kind in ipairs(names) do
            warn(def, "off", quote(kind) .. " is not a known kind")
        end
    end

    for _, name in ipairs(Defs.BASES) do
        local def = newDef(name)
        parseFields(def, fields(texts[name]), false, function(key, reason)
            fail(def, key, reason)
        end)
        checkKinds(def)
        if def.errors > 0 then
            result.failed = result.failed + 1
        end
        result[string.lower(name)] = def
    end

    -- Every event that parsed, in definition order, valid or not.
    local parsed = {}
    for _, slot in ipairs(Defs.SLOTS) do
        local position = 0
        for _, text in ipairs(items(texts[slot], "|", strip)) do
            position = position + 1
            local list = fields(text)
            local label = slot .. " #" .. position
            for _, f in ipairs(list) do
                if f.key == "id" and idText(f.value) then
                    label = label .. " (" .. f.value .. ")"
                    break
                end
            end
            local ev = newDef(label)
            ev.order = #parsed + 1
            local present = parseFields(ev, list, true, function(key, reason)
                fail(ev, key, reason)
            end)
            if not present.id then
                fail(ev, "id", "is missing")
            end
            if not present.track then
                fail(ev, "track", "is missing")
            end
            checkAt(ev, rule, function(key, reason)
                fail(ev, key, reason)
            end)
            if ev.tempmin ~= nil and ev.tempmax ~= nil and ev.tempmax < ev.tempmin then
                fail(ev, "tempmax", ev.tempmax .. " is below tempmin " .. ev.tempmin)
            end
            if ev.mindays ~= nil and ev.maxdays ~= nil and ev.maxdays < ev.mindays then
                fail(ev, "maxdays", ev.maxdays .. " is below mindays " .. ev.mindays)
            end
            ev["for"] = ev["for"] or { phases = 1 }
            ev.prio = ev.prio or 0
            parsed[#parsed + 1] = ev
        end
    end

    -- The first otherwise valid event with an id holds it. An event chained after an id nobody
    -- holds is skipped, which can skip others or hand its own id to a later definition.
    local holder
    local changed = true
    while changed do
        changed = false
        holder = {}
        for _, ev in ipairs(parsed) do
            if ev.errors == 0 and holder[ev.id] == nil then
                holder[ev.id] = ev
            end
        end
        for _, ev in ipairs(parsed) do
            if holder[ev.id] == ev and ev.after ~= nil then
                for _, id in ipairs(ev.after) do
                    if holder[id] == nil then
                        fail(ev, "after", "no loaded event has the id " .. quote(id))
                        changed = true
                    end
                end
            end
        end
    end
    for _, ev in ipairs(parsed) do
        if ev.errors == 0 and holder[ev.id] ~= ev then
            fail(ev, "id", quote(ev.id) .. " is already used by " .. holder[ev.id].label)
        end
    end

    for _, ev in ipairs(parsed) do
        if ev.errors > 0 then
            result.failed = result.failed + 1
        else
            local events = result.events
            events[#events + 1] = ev
            result.byId[ev.id] = ev
            result.ids[#result.ids + 1] = ev.id
        end
    end

    for _, ev in ipairs(result.events) do
        checkKinds(ev)
        if ev.chance == 0 then
            warn(ev, "chance", "is 0, so it never happens")
        end
        local conditions = false
        for _, key in ipairs(CONDITIONS) do
            if ev[key] ~= nil then
                conditions = true
            end
        end
        if not conditions then
            local occasion = "night"
            if ev.track == "sun" then
                occasion = "day"
            end
            warn(ev, nil, "has no conditions, so it can happen every " .. occasion)
        end
        if ev.after ~= nil then
            local rivals = {}
            for _, other in ipairs(result.events) do
                if other ~= ev and other.track == ev.track
                    and (other.prio > ev.prio or (other.prio == ev.prio and other.order < ev.order)) then
                    rivals[#rivals + 1] = other.id .. " (prio " .. other.prio .. ")"
                end
            end
            if #rivals > 0 then
                warn(ev, "after", "can lose to " .. table.concat(rivals, ", "))
            end
        end
    end
    return result
end

return Defs
