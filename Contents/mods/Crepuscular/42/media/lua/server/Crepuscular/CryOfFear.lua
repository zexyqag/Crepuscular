if isClient() then return end

local Log = require "Crepuscular/Log"
local Kinds = require "Crepuscular/Kinds"

-- Cry of Fear support. Its monsters are the kind cof. While the definition in effect has cof off,
-- Clock sets its spawns to None and Despawn removes far monsters.
local CryOfFear = {}

-- The settings that stop each of Cry of Fear's spawns, which it reads live: the levels of the
-- regular and special monsters' homes (1 is None), the Human Flowers and the Sawrunner's night
-- encounters.
CryOfFear.OFF = {
    ["COF_Spawns.Regular"] = "1",
    ["COF_Spawns.Sawcrazy"] = "1",
    ["COF_Spawns.Sawrunner"] = "1",
    ["COF_Spawns.Stranger"] = "1",
    ["COF_Spawns.Drowned"] = "1",
    ["COF_Spawns.HumanFlowers"] = "false",
    ["COF_Sawrunner.NightEvent"] = "false",
}

local function nightOnly()
    local vars = SandboxVars.COF_Spawns
    return vars ~= nil and vars.NightOnly == true
end

-- managed: some definition turns cof off and Cry of Fear is loaded.
function CryOfFear.check(managed)
    if managed and nightOnly() then
        Log.warnOnce("cof night only", "Cry of Fear's COF_Spawns.NightOnly is on: its own 20:00-04:00 night"
            .. " fights the definitions that turn cof off. Turn it off and let off=cof decide when its monsters roam")
    end
end

-- off: cof is off in the definition in effect.
function CryOfFear.status(managed, off)
    if not Kinds.cryOfFearLoaded() then
        return "Cry of Fear: not loaded"
    end
    local line = "Cry of Fear: loaded; "
    if not managed then
        line = line .. "no definition turns cof off, so its spawns are its own"
    elseif off then
        line = line .. "cof is off now, its spawns set to None"
    else
        line = line .. "cof is on now"
    end
    local night = "off"
    if nightOnly() then
        night = "on"
    end
    return line .. "; its NightOnly is " .. night
end

return CryOfFear
