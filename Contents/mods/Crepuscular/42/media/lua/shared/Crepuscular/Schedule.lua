-- Decides occasions and runs the current event on the server's ledger. Pure: the clock, climate
-- and random rolls are passed in.
--
-- Ledger: { occasion = { phase, key, date, open, start, endless, serial }, decided = { [track] = key },
--   pool = { [track] = { key, ids, covered } }, current = { id, track, serial, running, at,
--   startsAt, endsAt, phasesLeft }, count = { [id] = n }, lastStart = { [id] = hours },
--   lastDay = { [id] = world day }, roll = { [id] = interval roll since the last start },
--   follow = { [id] = { sun, moon } }, serial }
local Phase = require "Crepuscular/Phase"

local Schedule = {}

-- World-age hours are floats, so comparisons allow half a minute.
local TOLERANCE = 0.5 / 60

local function trackOf(phase)
    if phase == "day" then
        return "sun"
    end
    return "moon"
end

function Schedule.prepare(ledger)
    for _, name in ipairs({ "decided", "pool", "count", "lastStart", "lastDay", "roll", "follow" }) do
        if ledger[name] == nil then
            ledger[name] = {}
        end
    end
    if ledger.serial == nil then
        ledger.serial = 0
    end
end

local function label(occasion)
    return occasion.phase .. " of " .. occasion.key
end

-- World age turns a day at 07:00, so an occasion counts the world day at noon of its date: this is
-- that noon in world-age hours. An endless occasion keeps the date it opened on, so it counts the
-- date of `now` (world-age hours) instead.
local function noon(occasion, now)
    local midnight = occasion.start - occasion.open
    if occasion.endless then
        midnight = midnight + 24 * math.floor((now - midnight + TOLERANCE) / 24)
    end
    return midnight + 12
end

-- Noon is 5 hours from the turn of a world day, so it needs no tolerance.
local function worldDay(occasion, now)
    return math.floor(noon(occasion, now) / 24)
end

Schedule.noon = noon
Schedule.worldDay = worldDay

-- When ev would start in the occasion: at its at= time, or as the occasion starts, but not before
-- `earliest`: the occasion's nominal start for a decision, now for an admin's.
local function startTime(ev, occasion, earliest)
    if ev.at == nil then
        return earliest
    end
    return math.max(earliest, occasion.start + Phase.wrap(ev.at - occasion.open, 24))
end

-- When an event with interval= is next due: its unit ("d" counts world days, "h" world-age hours)
-- and the earliest and latest due, the same once its wait is rolled. The wait runs from its last
-- start; the first one from world day 0, or for hours from world age 0, 07:00 that day.
function Schedule.due(ledger, ev)
    local interval = ev.interval
    local base = ledger.lastStart[ev.id] or 0
    if interval.unit == "d" then
        base = ledger.lastDay[ev.id] or 0
    end
    local roll = ledger.roll[ev.id]
    if roll == nil then
        return interval.unit, base + interval.min, base + interval.max
    end
    local due = base + interval.min + math.floor(roll * (interval.max - interval.min + 1) / 100)
    return interval.unit, due, due
end

-- Why ev still waits for its interval if it starts at `when` in the occasion, or nil once it is
-- due. A wait is rolled when first needed and kept until the event starts again, so a lost chance
-- doesn't roll anew.
local function waiting(ledger, ev, occasion, when, roll)
    local interval = ev.interval
    if interval.max > interval.min and ledger.roll[ev.id] == nil then
        ledger.roll[ev.id] = roll()
    end
    local unit, due = Schedule.due(ledger, ev)
    if unit == "d" then
        if worldDay(occasion, when) < due then
            return "is not due before world day " .. due
        end
        return nil
    end
    local left = due - when
    if left > TOLERANCE then
        return "is not due for " .. math.floor(left * 60 + 0.5) .. " more minutes"
    end
    return nil
end

local function calendar(ev, occasion, day, climate)
    local date = occasion.date
    if ev.moon ~= nil then
        local phase = Phase.moon(date.year, date.month, date.day)
        local before = Phase.previousDay(date)
        if not ev.moon[phase] or Phase.moon(before.year, before.month, before.day) == phase then
            return false
        end
    end
    if ev.date ~= nil then
        local key = (date.month + 1) * 100 + date.day
        local inside = false
        for _, r in ipairs(ev.date) do
            if (r.from <= r.to and key >= r.from and key <= r.to)
                or (r.from > r.to and (key >= r.from or key <= r.to)) then
                inside = true
            end
        end
        if not inside then
            return false
        end
    end
    if ev.month ~= nil and not ev.month[date.month + 1] then
        return false
    end
    if ev.season ~= nil and not ev.season[climate.season] then
        return false
    end
    if ev.every ~= nil and Phase.wrap(day, ev.every.n) ~= ev.every.k then
        return false
    end
    if ev.mindays ~= nil and day < ev.mindays then
        return false
    end
    if ev.maxdays ~= nil and day > ev.maxdays then
        return false
    end
    return true
end

local function weather(ev, climate)
    if ev.weather ~= nil then
        local fog = climate.fog >= 0.5
        local any = (ev.weather.rain and climate.rain) or (ev.weather.snow and climate.snow)
            or (ev.weather.storm and climate.storm) or (ev.weather.fog and fog)
            or (ev.weather.clear and not climate.rain and not climate.snow and not climate.storm and not fog)
        if not any then
            return false
        end
    end
    if ev.tempmin ~= nil and climate.temp < ev.tempmin then
        return false
    end
    if ev.tempmax ~= nil and climate.temp > ev.tempmax then
        return false
    end
    return true
end

local function nthHits(nth, count)
    return Phase.wrap(count - nth.k, nth.n) == 0
end

-- Returns false, and records nothing, when an event measured in hours would already be over.
local function start(ledger, ev, startsAt, now, log)
    if ev["for"].hours ~= nil and startsAt + ev["for"].hours <= now + TOLERANCE then
        ledger.current = nil
        log(ev.id .. " missed: its time was over before it could start")
        return false
    end
    ledger.serial = ledger.serial + 1
    local current = { id = ev.id, track = ev.track, serial = ledger.serial, running = true, startsAt = startsAt }
    if ev["for"].hours ~= nil then
        current.endsAt = startsAt + ev["for"].hours
    else
        current.phasesLeft = ev["for"].phases
    end
    ledger.current = current
    ledger.lastStart[ev.id] = startsAt
    ledger.lastDay[ev.id] = worldDay(ledger.occasion, startsAt)
    ledger.roll[ev.id] = nil
    -- The event replaces the phase's own line, which isn't shown again when it ends.
    ledger.occasion.serial = nil
    return true
end

local function finish(ledger, log, why)
    local current = ledger.current
    ledger.follow[current.id] = { sun = true, moon = true }
    ledger.current = nil
    log(current.id .. " ended: " .. why)
end

-- Picks among the pool of the occasion's track (1.4 steps 5-7), each event as it would start, not
-- before `earliest`. Returns the chosen event or nil.
local function pick(ledger, defs, climate, roll, earliest, log)
    local occasion = ledger.occasion
    local track = trackOf(occasion.phase)
    local name = label(occasion)
    local candidates = {}
    for _, id in ipairs(ledger.pool[track].ids) do
        local ev = defs.byId[id]
        if ev ~= nil and ev.track == track then
            local last = ledger.lastStart[id]
            local when = startTime(ev, occasion, earliest)
            local wait = nil
            if ev.cooldown ~= nil and last ~= nil and when < last + ev.cooldown - TOLERANCE then
                wait = "is cooling down"
            elseif ev.interval ~= nil then
                wait = waiting(ledger, ev, occasion, when, roll)
            end
            if wait ~= nil then
                log(name .. ": " .. id .. " " .. wait)
            elseif not weather(ev, climate) then
                log(name .. ": " .. id .. " weather doesn't match")
            else
                candidates[#candidates + 1] = ev
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.prio ~= b.prio then
            return a.prio > b.prio
        end
        return a.order < b.order
    end)
    for _, ev in ipairs(candidates) do
        local head = name .. ": " .. ev.id .. " prio " .. ev.prio
        if ev.chance == nil or ev.chance >= 100 then
            log(head .. ": chosen")
            return ev
        elseif ev.chance <= 0 then
            log(head .. ": chance 0")
        else
            local rolled = roll()
            local text = string.format("%s rolled %.1f", head, rolled)
            if rolled < ev.chance then
                log(text .. " < " .. ev.chance .. ": chosen")
                return ev
            end
            log(text .. ", not < " .. ev.chance)
        end
    end
    log(name .. ": no event")
    return nil
end

-- Makes ev the current event of the ledger's occasion, starting at its start time.
local function schedule(ledger, ev, earliest, now, log)
    local occasion = ledger.occasion
    local at = startTime(ev, occasion, earliest)
    if at <= now + TOLERANCE then
        start(ledger, ev, at, now, log)
        return
    end
    ledger.current = { id = ev.id, track = ev.track, running = false, at = at }
    log(label(occasion) .. ": " .. ev.id .. " waits for its start time")
end

local function decide(ledger, defs, input, log)
    local occasion = ledger.occasion
    local track = trackOf(occasion.phase)
    local name = label(occasion)
    local covering = nil
    if ledger.current ~= nil and ledger.current.running then
        covering = ledger.current.id
    end

    local chained = {}
    for id, flags in pairs(ledger.follow) do
        if flags[track] then
            chained[id] = true
            flags[track] = nil
        end
        if not flags.sun and not flags.moon then
            ledger.follow[id] = nil
        end
    end

    local climate = input.climate()
    local day = worldDay(occasion, input.now)
    local ids = {}
    for _, ev in ipairs(defs.events) do
        if ev.track == track and calendar(ev, occasion, day, climate) then
            local ok = true
            if ev.nth ~= nil then
                local count = (ledger.count[ev.id] or 0) + 1
                ledger.count[ev.id] = count
                ok = nthHits(ev.nth, count)
                log(name .. ": " .. ev.id .. " count " .. count .. (ok and ", nth hits" or ""))
            end
            if ok and ev.after ~= nil then
                ok = false
                for _, id in ipairs(ev.after) do
                    if chained[id] then
                        ok = true
                    end
                end
            end
            if ok then
                ids[#ids + 1] = ev.id
            end
        end
    end
    ledger.decided[track] = occasion.key
    ledger.pool[track] = { key = occasion.key, ids = ids, covered = covering }

    if covering ~= nil then
        log(name .. ": covered by " .. covering)
        return
    end
    local ev = pick(ledger, defs, climate, input.roll, occasion.start, log)
    -- The phase's own announcement belongs to this start until an event takes over.
    ledger.serial = ledger.serial + 1
    ledger.occasion.serial = ledger.serial
    if ev ~= nil then
        schedule(ledger, ev, occasion.start, input.now, log)
    end
end

-- Counts a phase change and moves the ledger to the clock's occasion, which is endless while the
-- clock's is.
local function advance(ledger, input, log)
    local seen = ledger.occasion
    local occasion = input.occasion
    if seen ~= nil and seen.phase == occasion.phase and (occasion.endless or seen.key == input.key) then
        -- Until it is decided the occasion follows the clock: in a world created at 07:00 the
        -- world age jumps by a day on the first frame.
        if ledger.decided[trackOf(seen.phase)] ~= seen.key then
            seen.open, seen.start = occasion.open, occasion.start
        end
    else
        local current = ledger.current
        if seen ~= nil and current ~= nil then
            if not current.running then
                log(current.id .. " missed: the " .. label(seen) .. " ended before its start time")
                ledger.current = nil
            elseif current.phasesLeft ~= nil then
                current.phasesLeft = current.phasesLeft - 1
            end
        end
        ledger.occasion = {
            phase = occasion.phase, key = input.key, date = occasion.date, open = occasion.open, start = occasion.start,
        }
    end
    ledger.occasion.endless = occasion.endless
end

-- One tick (1.5): count a phase change, end the current event if due, decide a new occasion,
-- start a waiting event whose time has come.
-- input: { occasion (Phase.occasion), key, now = world-age hours, ready = the climate has updated,
-- climate() = { rain, snow, storm, fog, temp, season }, roll() = 0 <= n < 100 }.
function Schedule.tick(ledger, defs, input, log)
    -- Before the climate's first update the season may still hold yesterday's dawn and dusk.
    if ledger.occasion == nil or input.ready then
        advance(ledger, input, log)
    end

    local current = ledger.current
    if current ~= nil then
        local ev = defs.byId[current.id]
        if ev == nil then
            if current.running then
                finish(ledger, log, "its definition is gone")
            else
                log(current.id .. " dropped: its definition is gone")
                ledger.current = nil
            end
        elseif current.running and ((current.phasesLeft ~= nil and current.phasesLeft <= 0)
            or (current.endsAt ~= nil and input.now >= current.endsAt - TOLERANCE)) then
            finish(ledger, log, "its time is up")
        else
            -- A changed definition keeps the computed end; its effects follow from now on.
            current.track = ev.track
        end
    end

    local track = trackOf(ledger.occasion.phase)
    if ledger.decided[track] ~= ledger.occasion.key and input.ready then
        decide(ledger, defs, input, log)
    end

    current = ledger.current
    if current ~= nil and not current.running and input.now >= current.at - TOLERANCE
        and start(ledger, defs.byId[current.id], current.at, input.now, log) then
        log(current.id .. " started at its start time")
    end
end

-- Admin: ends the current event and starts id now, whatever its conditions and at=.
function Schedule.begin(ledger, defs, id, now, log)
    local current = ledger.current
    if current ~= nil then
        if current.running then
            finish(ledger, log, "an admin started " .. id)
        else
            ledger.current = nil
        end
    end
    start(ledger, defs.byId[id], now, now, log)
    log(id .. " started by an admin")
end

-- Admin: ends the running event, or drops a waiting one. Returns its id, or nil.
function Schedule.stop(ledger, log)
    local current = ledger.current
    if current == nil then
        return nil
    end
    if current.running then
        finish(ledger, log, "an admin ended it")
    else
        ledger.current = nil
        log(current.id .. " dropped by an admin")
    end
    return current.id
end

-- Admin: picks again for this occasion with fresh rolls, without counting again, and starts the
-- choice now (or at its at= time if that is still ahead). input: { now, climate(), roll() }.
-- Returns "running" while an event runs, else the chosen id or false.
function Schedule.redecide(ledger, defs, input, log)
    local current = ledger.current
    if current ~= nil and current.running then
        return "running"
    end
    ledger.current = nil
    if ledger.pool[trackOf(ledger.occasion.phase)] == nil then
        return false
    end
    local ev = pick(ledger, defs, input.climate(), input.roll, input.now, log)
    if ev == nil then
        return false
    end
    schedule(ledger, ev, input.now, input.now, log)
    return ev.id
end

return Schedule
