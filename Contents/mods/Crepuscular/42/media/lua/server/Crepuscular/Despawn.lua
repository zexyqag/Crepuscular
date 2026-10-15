if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local State = require "Crepuscular/State"
local Kinds = require "Crepuscular/Kinds"

-- Removes far members of the kinds the definition in effect turns off: every in-game minute up to
-- RemovalsPerMinute that are alive, not dragged, have no target and no player within KeepDistance.
local Despawn = {}

-- kind -> members removed since this game started.
local removed = {}

-- Where every player is, read once a minute. Single player: the local players;
-- getOnlinePlayers() is empty outside multiplayer.
local function positions()
    local list = {}
    local function add(player)
        list[#list + 1] = { x = player:getX(), y = player:getY() }
    end
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do
            add(online:get(i))
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player ~= nil then
                add(player)
            end
        end
    end
    return list
end

local function near(z, spots, limit)
    local x, y = z:getX(), z:getY()
    for _, spot in ipairs(spots) do
        local dx, dy = spot.x - x, spot.y - y
        if dx * dx + dy * dy <= limit then
            return true
        end
    end
    return false
end

local function minute()
    local state = State.get()
    if not Kinds.started() or state == nil then
        return
    end
    -- Without kinds that can have members here, such as mutants without The Mutants, there is
    -- nothing to look for.
    local targets, any = Kinds.removable(state.effects.off)
    if not any then
        return
    end
    local cap = Settings.removalsPerMinute()
    local distance = Settings.keepDistance()
    local limit = distance * distance
    local spots = positions()
    local kindOf = Kinds.test()
    local zombies = getCell():getZombieList()
    local doomed, kinds = {}, {}
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if not z:isDead() and not z:isReanimatedForGrappleOnly() and z:getTarget() == nil then
            local kind = kindOf(z)
            if kind ~= nil and targets[kind] and not near(z, spots, limit) then
                doomed[#doomed + 1] = z
                kinds[#doomed] = kind
                if #doomed == cap then
                    break
                end
            end
        end
    end
    if #doomed == 0 then
        return
    end
    -- Removing a zombie clears its online ID, so the batch is written first.
    local out = {}
    for i, z in ipairs(doomed) do
        local kind = kinds[i]
        out[i] = { id = z:getOnlineID(), x = z:getX(), y = z:getY(), kind = kind }
        Kinds.remove(z, kind)
        removed[kind] = (removed[kind] or 0) + 1
    end
    -- Sent at once, as the server may give a removed zombie's online ID to a new one. Does nothing
    -- in single player.
    sendServerCommand(State.MODULE, "out", { list = out })
    Log.info("removed " .. #doomed .. " far zombies of kinds that are off")
end

Events.EveryOneMinute.Add(minute)

function Despawn.status()
    local kinds = {}
    for kind in pairs(removed) do
        kinds[#kinds + 1] = kind
    end
    table.sort(kinds)
    local parts = {}
    for _, kind in ipairs(kinds) do
        parts[#parts + 1] = kind .. " " .. removed[kind]
    end
    if #parts == 0 then
        parts[1] = "none"
    end
    return "removed this session: " .. table.concat(parts, ", ")
end

return Despawn
