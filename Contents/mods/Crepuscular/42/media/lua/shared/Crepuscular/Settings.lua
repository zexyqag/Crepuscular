local Log = require "Crepuscular/Log"

local Settings = {}

local DEFAULTS = {
    NightMode = 1,
    NightStartHour = 20,
    NightEndHour = 4,
    Day = "speed=+25;health=0.7",
    Night = "speed=-50;rise=50;wake=true;off=mutants",
    Events1 = "id=bloodmoon;track=moon;moon=full;chance=50;prio=10;speed=+50;rise=100;wake=true;off=none;say=@IGUI_Crepuscular_BloodMoon;color=ff3c3c",
    Events2 = "",
    Events3 = "",
    Events4 = "",
    Events5 = "",
    Events6 = "",
    Events7 = "",
    Events8 = "",
    Kinds = "",
    KeepDistance = 40,
    RemovalsPerMinute = 50,
    MutantRequeue = false,
    VolatilesFollowNight = true,
    ZombiesPerSweep = 400,
    RiseDelayMin = 1.0,
    RiseDelayMax = 2.0,
    MaxRises = 1,
    RiseMaxAgeHours = 168,
    FireStaysDown = true,
    FinishOff = true,
    FinishOffSeconds = 3,
    HeadHitsStayDown = false,
    RiseInSafehouses = false,
    RisePlayers = false,
    RiseKinds = "",
    RisesPerScan = 10,
    RiserLimit = 5000,
    Notifications = true,
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

local function number(name, min, max)
    local value = read(name)
    if type(value) ~= "number" or value < min or value > max then
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

-- name is Day, Night, Events1 to Events8 or Kinds.
function Settings.definition(name)
    return text(name)
end

function Settings.keepDistance()
    return integer("KeepDistance", 0, 300)
end

function Settings.removalsPerMinute()
    return integer("RemovalsPerMinute", 1, 500)
end

function Settings.mutantRequeue()
    return boolean("MutantRequeue")
end

-- Whether Blackout Predators' own night hours are set to follow the definitions'.
function Settings.volatilesFollowNight()
    return boolean("VolatilesFollowNight")
end

function Settings.zombiesPerSweep()
    return integer("ZombiesPerSweep", 50, 5000)
end

-- In-game hours after death before a marked corpse may get up.
function Settings.riseDelayMin()
    return number("RiseDelayMin", 0, 48)
end

function Settings.riseDelayMax()
    return number("RiseDelayMax", 0, 48)
end

-- The two, the lower first.
function Settings.riseDelay()
    local low, high = Settings.riseDelayMin(), Settings.riseDelayMax()
    if low > high then
        Log.warnOnce("setting RiseDelay", "Crepuscular.RiseDelayMin is " .. tostring(low) .. ", above Crepuscular.RiseDelayMax "
            .. tostring(high) .. "; using " .. tostring(high) .. " to " .. tostring(low))
        return high, low
    end
    return low, high
end

-- 0 for no limit.
function Settings.maxRises()
    return integer("MaxRises", 0, 20)
end

-- 0 for no limit.
function Settings.riseMaxAgeHours()
    return integer("RiseMaxAgeHours", 0, 8760)
end

function Settings.fireStaysDown()
    return boolean("FireStaysDown")
end

function Settings.finishOff()
    return boolean("FinishOff")
end

function Settings.finishOffSeconds()
    return integer("FinishOffSeconds", 1, 30)
end

function Settings.headHitsStayDown()
    return boolean("HeadHitsStayDown")
end

function Settings.riseInSafehouses()
    return boolean("RiseInSafehouses")
end

function Settings.risePlayers()
    return boolean("RisePlayers")
end

-- Kind names, as in off=.
function Settings.riseKinds()
    return text("RiseKinds")
end

function Settings.risesPerScan()
    return integer("RisesPerScan", 1, 100)
end

function Settings.riserLimit()
    return integer("RiserLimit", 100, 50000)
end

-- Whether players' games show the definitions' lines and play their sounds.
function Settings.notifications()
    return boolean("Notifications")
end

return Settings
