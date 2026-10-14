local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"

local Phase = {}

Phase.FULL_MOON = 4

-- Dates are { year, month (0-11), day (1-31) }, as the game's calendar keeps them.
function Phase.now()
    local time = getGameTime()
    return {
        year = time:getYear(),
        month = time:getMonth(),
        day = time:getDay() + 1,
        hour = time:getHour(),
        hours = time:getWorldAgeHours(),
    }
end

local function previousDay(date)
    if date.day > 1 then
        return { year = date.year, month = date.month, day = date.day - 1 }
    end
    if date.month > 0 then
        return { year = date.year, month = date.month - 1, day = getGameTime():daysInMonth(date.year, date.month - 1) }
    end
    return { year = date.year - 1, month = 11, day = 31 }
end

function Phase.key(date)
    return string.format("%d-%02d-%02d", date.year, date.month + 1, date.day)
end

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

-- Indexed by month + 1; the game indexes its table with the 0-based month.
local DAY_YEAR = { -1, -1, 30, 58, 89, 119, 150, 180, 211, 241, 272, 303 }

local function leap(year)
    return rem(year, 4) == 0 and (rem(year, 400) == 0 or rem(year, 100) ~= 0)
end

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

-- Whether a night window is open at `now`, and if so the date it opened on.
function Phase.window(now)
    local today = { year = now.year, month = now.month, day = now.day }
    if Settings.nightMode() == 2 then
        if not getGameTime():isNight() then
            return false
        end
        if now.hour >= 12 then
            return true, today
        end
        return true, previousDay(today)
    end
    local start, finish = Settings.nightStartHour(), Settings.nightEndHour()
    if start == finish then
        Log.warnOnce("no night", "NightStartHour equals NightEndHour (" .. start .. "), so there is no night")
        return false
    end
    if start < finish then
        if now.hour >= start and now.hour < finish then
            return true, today
        end
        return false
    end
    if now.hour >= start then
        return true, today
    end
    if now.hour < finish then
        return true, previousDay(today)
    end
    return false
end

return Phase
