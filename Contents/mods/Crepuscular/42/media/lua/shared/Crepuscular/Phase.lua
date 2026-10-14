-- Dates and occasions. Pure: the caller passes the clock in.
-- Dates are { year, month (0-11), day (1-31) }, as the game's calendar keeps them.
local Phase = {}

-- Java integer division and remainder, which truncate toward zero.
local function quot(a, b)
    local q = a / b
    if q < 0 then
        return math.ceil(q)
    end
    return math.floor(q)
end

local function rem(a, b)
    return a - quot(a, b) * b
end

-- x modulo n, floored. Spelled out because Kahlua's % isn't known to follow Lua for negative x.
function Phase.wrap(x, n)
    return x - math.floor(x / n) * n
end

local function leap(year)
    return rem(year, 4) == 0 and (rem(year, 400) == 0 or rem(year, 100) ~= 0)
end

local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function Phase.daysInMonth(year, month)
    if month == 1 and leap(year) then
        return 29
    end
    return DAYS[month + 1]
end

function Phase.previousDay(date)
    if date.day > 1 then
        return { year = date.year, month = date.month, day = date.day - 1 }
    end
    if date.month > 0 then
        return { year = date.year, month = date.month - 1, day = Phase.daysInMonth(date.year, date.month - 1) }
    end
    return { year = date.year - 1, month = 11, day = 31 }
end

function Phase.nextDay(date)
    if date.day < Phase.daysInMonth(date.year, date.month) then
        return { year = date.year, month = date.month, day = date.day + 1 }
    end
    if date.month < 11 then
        return { year = date.year, month = date.month + 1, day = 1 }
    end
    return { year = date.year + 1, month = 0, day = 1 }
end

function Phase.key(date)
    return string.format("%d-%02d-%02d", date.year, date.month + 1, date.day)
end

-- "YYYY-MM-DD HH:MM" of the moment `hours` world-age hours from `now`'s moment (now.hours).
function Phase.stamp(now, hours)
    local date = { year = now.year, month = now.month, day = now.day }
    local minutes = math.floor((now.time + hours - now.hours) * 60 + 0.5)
    while minutes < 0 do
        minutes = minutes + 24 * 60
        date = Phase.previousDay(date)
    end
    while minutes >= 24 * 60 do
        minutes = minutes - 24 * 60
        date = Phase.nextDay(date)
    end
    return string.format("%s %02d:%02d", Phase.key(date), math.floor(minutes / 60), minutes % 60)
end

-- Indexed by month + 1; the game indexes its table with the 0-based month.
local DAY_YEAR = { -1, -1, 30, 58, 89, 119, 150, 180, 211, 241, 272, 303 }

-- The game's moon phase for any date, 0 (new) to 7, 4 = full: the formula of ClimateMoon,
-- which only exposes today's phase and updates it after EveryOneMinute has run.
function Phase.moon(year, month, day)
    local dayOfYear = day + DAY_YEAR[month + 1]
    if month > 2 and leap(year) then
        dayOfYear = dayOfYear + 1
    end
    local century = quot(year, 100) + 1
    local golden = rem(year, 19) + 1
    local epact = rem(11 * golden + 20 + quot(8 * century + 5, 25) - 5 - (quot(3 * century, 4) - 12), 30)
    if epact <= 0 then
        epact = epact + 30
    end
    if (epact == 25 and golden > 11) or epact == 24 then
        epact = epact + 1
    end
    local phase = quot(rem((dayOfYear + epact) * 6 + 11, 177), 22)
    return rem(phase, 8)
end

-- The occasion the clock is in: { phase = "day" | "night", date it opened, open = hour of day it
-- opened, start = nominal start in world-age hours, endless }.
-- now: { year, month, day, time = hour of day with fraction, hours = world age }.
-- rule: { mode = 1, start, finish } (fixed hours) or { mode = 2, dawn, dusk, endless = nil | phase }.
-- An endless occasion has no boundary, so the caller keeps the one it is already in.
function Phase.occasion(now, rule)
    local today = { year = now.year, month = now.month, day = now.day }
    local time = now.time
    if rule.mode == 2 then
        if rule.endless ~= nil then
            return { phase = rule.endless, date = today, open = time, start = now.hours, endless = true }
        end
        if time >= rule.dawn and time <= rule.dusk then
            return { phase = "day", date = today, open = rule.dawn, start = now.hours - (time - rule.dawn) }
        end
        -- Split at noon: dusk and dawn move a little from one day to the next.
        local date = today
        if time < 12 then
            date = Phase.previousDay(today)
        end
        return { phase = "night", date = date, open = rule.dusk, start = now.hours - Phase.wrap(time - rule.dusk, 24) }
    end
    if rule.start == rule.finish then
        return { phase = "day", date = today, open = time, start = now.hours, endless = true }
    end
    local hour = math.floor(time)
    local night
    if rule.start < rule.finish then
        night = hour >= rule.start and hour < rule.finish
    else
        night = hour >= rule.start or hour < rule.finish
    end
    local phase, open = "day", rule.finish
    if night then
        phase, open = "night", rule.start
    end
    local date = today
    if hour < open then
        date = Phase.previousDay(today)
    end
    return { phase = phase, date = date, open = open, start = now.hours - Phase.wrap(time - open, 24) }
end

return Phase
