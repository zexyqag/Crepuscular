local Log = require "Crepuscular/Log"

local Settings = {}

local DEFAULTS = {
    NightMode = 1,
    NightStartHour = 20,
    NightEndHour = 4,
    BloodMoonChance = 50,
    BloodMoonAnnounce = true,
    BloodMoonMutants = true,
    MutantsAdapter = true,
    MutantsWhen = 1,
    MutantKeepDistance = 40,
    MutantRemovalsPerMinute = 50,
    MutantRequeue = false,
    CryOfFearAdapter = true,
    ExcludedOutfits = "",
    DayOverrides = "",
    NightOverrides = "",
    BloodMoonOverrides = "",
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

function Settings.bloodMoonChance()
    return integer("BloodMoonChance", 0, 100)
end

function Settings.bloodMoonAnnounce()
    return boolean("BloodMoonAnnounce")
end

function Settings.bloodMoonMutants()
    return boolean("BloodMoonMutants")
end

function Settings.mutantsAdapter()
    return boolean("MutantsAdapter")
end

-- 1 = by day, 2 = by night, 3 = always, 4 = blood moons only.
function Settings.mutantsWhen()
    return integer("MutantsWhen", 1, 4)
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

function Settings.cryOfFearAdapter()
    return boolean("CryOfFearAdapter")
end

-- Comma-separated outfit name prefixes.
function Settings.excludedOutfits()
    return text("ExcludedOutfits")
end

-- name is DayOverrides, NightOverrides or BloodMoonOverrides.
function Settings.overrides(name)
    return text(name)
end

return Settings
