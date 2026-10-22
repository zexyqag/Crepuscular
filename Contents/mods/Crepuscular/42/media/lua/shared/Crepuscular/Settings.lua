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
    RiseKinds = "",
    Notifications = true,
    NotificationPlace = 1,
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

-- Kind names, as in off=, whose killed members Relentless Dead may raise.
function Settings.riseKinds()
    return text("RiseKinds")
end

-- Whether players' games show the definitions' lines and play their sounds.
function Settings.notifications()
    return boolean("Notifications")
end

-- Where players' games show the lines: 1 over the head, 2 in chat, 3 both.
function Settings.notificationPlace()
    return integer("NotificationPlace", 1, 3)
end

return Settings
