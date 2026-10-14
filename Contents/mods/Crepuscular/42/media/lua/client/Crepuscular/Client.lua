local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local State = require "Crepuscular/State"
local Overrides = require "Crepuscular/Overrides"

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

if isClient() then
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
