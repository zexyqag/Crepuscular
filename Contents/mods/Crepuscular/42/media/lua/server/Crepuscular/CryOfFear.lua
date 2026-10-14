if isClient() then return end

local Log = require "Crepuscular/Log"
local Kinds = require "Crepuscular/Kinds"

-- Cry of Fear support. Its monsters are recognised in Kinds; Crepuscular never changes Cry of
-- Fear's settings by itself.
local CryOfFear = {}

local function nightOnly()
    local vars = SandboxVars.COF_Spawns
    return vars ~= nil and vars.NightOnly == true
end

function CryOfFear.status()
    if not Kinds.cryOfFearLoaded() then
        return "Cry of Fear: not loaded"
    end
    local night = "on"
    if not nightOnly() then
        night = "off, so its monsters stay by day"
    end
    return "Cry of Fear: loaded; its NightOnly is " .. night
end

local function check()
    if Kinds.cryOfFearLoaded() and not nightOnly() then
        Log.warn("Cry of Fear's COF_Spawns.NightOnly is off, so its monsters roam by day too;"
            .. " Crepuscular leaves it as it is")
    end
end

Events.OnServerStarted.Add(check)
Events.OnGameStart.Add(check)

return CryOfFear
