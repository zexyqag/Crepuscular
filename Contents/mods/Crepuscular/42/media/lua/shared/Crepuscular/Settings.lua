local Log = require "Crepuscular/Log"

local Settings = {}

local DEFAULTS = {
    NightMode = 1,
    NightStartHour = 20,
    NightEndHour = 4,
    Day = "",
    Night = "off=mutants",
    Events1 = "id=bloodmoon;track=moon;moon=full;chance=50;prio=10;off=none;say=@IGUI_Crepuscular_BloodMoon;color=ff3c3c",
    Events2 = "",
    Events3 = "",
    Events4 = "",
    Events5 = "",
    Events6 = "",
    Events7 = "",
    Events8 = "",
    MutantKeepDistance = 40,
    MutantRemovalsPerMinute = 50,
    MutantRequeue = false,
    ExcludedOutfits = "",
}

local function invalid(name, value)
    Log.warnOnce("setting " .. name, "Crepuscular." .. name .. " is " .. tostring(value)
        .. ", which is not a valid value; using " .. tostring(DEFAULTS[name]))
    return DEFAULTS[name]
end

local function read(name)
    local vars = SandboxVars.Crepuscular
    if vars == nil then
        return nil
    end
    return vars[name]
end

local function integer(name, min, max)
    local value = read(name)
    if type(value) ~= "number" or value ~= math.floor(value) or value < min or value > max then
        return invalid(name, value)
    end
    return value
end

local function boolean(name)
    local value = read(name)
    if type(value) ~= "boolean" then
        return invalid(name, value)
    end
    return value
end

local function text(name)
    local value = read(name)
    if type(value) ~= "string" then
        return invalid(name, value)
    end
    return value
end

-- 1 = fixed hours, 2 = the game's seasonal night.
function Settings.nightMode()
    return integer("NightMode", 1, 2)
end

function Settings.nightStartHour()
    return integer("NightStartHour", 0, 23)
end

function Settings.nightEndHour()
    return integer("NightEndHour", 0, 23)
end

-- name is Day, Night or Events1 to Events8.
function Settings.definition(name)
    return text(name)
end

function Settings.mutantKeepDistance()
    return integer("MutantKeepDistance", 0, 300)
end

function Settings.mutantRemovalsPerMinute()
    return integer("MutantRemovalsPerMinute", 1, 500)
end

function Settings.mutantRequeue()
    return boolean("MutantRequeue")
end

-- Comma-separated outfit name prefixes.
function Settings.excludedOutfits()
    return text("ExcludedOutfits")
end

return Settings
