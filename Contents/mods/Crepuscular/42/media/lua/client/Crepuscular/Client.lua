local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local State = require "Crepuscular/State"
local Overrides = require "Crepuscular/Overrides"
local Kinds = require "Crepuscular/Kinds"

-- The server may have given the online ID to another zombie by now, so a copy is only removed near
-- where the server's mutant was.
local OUT_RANGE = 30

-- id of the last blood moon this game has shown.
local announced = nil

local function announce(state)
    if state.phase ~= "bloodmoon" or state.bloodMoon.id == announced or not Settings.bloodMoonAnnounce() then
        return
    end
    local text = getText("IGUI_Crepuscular_BloodMoon")
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            player:setHaloNote(text, 255, 60, 60, 500)
            announced = state.bloodMoon.id
        end
    end
end

-- The server removed these mutants; the game doesn't remove this game's copies of zombies a script
-- removes, and the copy this game runs would go on attacking.
local function takeOut(list)
    local byId = {}
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        byId[z:getOnlineID()] = z
    end
    for _, entry in ipairs(list) do
        local z = byId[entry.id]
        if z ~= nil and Kinds.isMutant(z) then
            local dx, dy = z:getX() - entry.x, z:getY() - entry.y
            if dx * dx + dy * dy <= OUT_RANGE * OUT_RANGE then
                VirtualZombieManager.instance:removeZombieFromWorld(z)
            end
        end
    end
end

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == State.MODULE and command == "out" then
            takeOut(args.list)
        end
    end)

    Events.OnGameStart.Add(function()
        ModData.request(State.NAME)
    end)

    -- The packet only raises this event; nothing is stored unless we store it.
    Events.OnReceiveGlobalModData.Add(function(tag, state)
        if tag ~= State.NAME then
            return
        end
        if type(state) ~= "table" then
            Log.warn("the server has no Crepuscular state; is the mod running there?")
            return
        end
        ModData.add(State.NAME, state)
        Overrides.applyAll(state.sandbox)
        announce(state)
    end)
else
    State.listen(announce)
end
