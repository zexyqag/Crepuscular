local Log = require "Crepuscular/Log"
local State = require "Crepuscular/State"
local Overrides = require "Crepuscular/Overrides"
local Kinds = require "Crepuscular/Kinds"

-- The server may have given the online ID to another zombie by now, so a copy is only removed near
-- where the server's zombie was.
local OUT_RANGE = 30

-- Serial of the last announcement this game has shown.
local announced = nil

local HEX = "0123456789abcdef"

-- One colour channel of rrggbb, from 1-based position i.
local function channel(color, i)
    local high = string.find(HEX, string.sub(color, i, i), 1, true) - 1
    local low = string.find(HEX, string.sub(color, i + 1, i + 1), 1, true) - 1
    return high * 16 + low
end

local function announce(state)
    local line = state.announce
    if line == nil or line.serial == announced then
        return
    end
    local text = line.text
    if string.sub(text, 1, 1) == "@" then
        text = getText(string.sub(text, 2))
    end
    local r, g, b = channel(line.color, 1), channel(line.color, 3), channel(line.color, 5)
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            player:setHaloNote(text, r, g, b, 500)
            announced = line.serial
        end
    end
end

State.listen(announce)

-- Cry of Fear's own answer to its server's out command (its COF_NetClient.lua): it finds the copy
-- by online ID, checks it is a monster within 30 tiles of the server's one, stops its looping
-- sounds and removes it.
local function cryOfFearOut()
    local answers = COF_NetClient
    if type(answers) == "table" and type(answers.out) == "function" then
        return answers.out
    end
    return nil
end

-- The server removed these zombies, { id, x, y, kind } each; the game doesn't remove this game's
-- copies of zombies a script removes, and the copy this game runs would go on attacking.
local function takeOut(list)
    local byId = {}
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        byId[z:getOnlineID()] = z
    end
    local cofOut = cryOfFearOut()
    for _, entry in ipairs(list) do
        if entry.kind == "cof" and cofOut ~= nil then
            cofOut(entry)
        else
            local z = byId[entry.id]
            if z ~= nil and Kinds.of(z) == entry.kind then
                local dx, dy = z:getX() - entry.x, z:getY() - entry.y
                if dx * dx + dy * dy <= OUT_RANGE * OUT_RANGE then
                    Kinds.remove(z, entry.kind)
                end
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
        State.notify(state)
    end)
end
