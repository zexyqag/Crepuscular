if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Phase = require "Crepuscular/Phase"
local State = require "Crepuscular/State"
local Kinds = require "Crepuscular/Kinds"

-- The Mutants adapter: a gate on new mutants, removal of far mutants outside the window, and an
-- optional requeue of loaded zombies when the window opens.
local Mutants = {}

local OWNER = "Crepuscular"
local REQUEUE_PER_MINUTE = 200

-- Mutants removed since this game started.
local removed = 0
-- The latest requeue: { began, offered, finished }.
local lastRequeue = nil

-- The ForeignOwnership table our isClaimed is installed in, and the function it replaced.
local gated = nil
local original = nil

local function active()
    return Kinds.started() and Kinds.mutantsApi() ~= nil and Settings.mutantsAdapter()
end

-- Whether The Mutants may make new mutants now. Follows the day/night phase, forced phases included.
local function windowOpen()
    local phase = ModData.get(State.NAME).phase
    if phase == "bloodmoon" and Settings.bloodMoonMutants() then
        return true
    end
    local when = Settings.mutantsWhen()
    if when == 1 then
        return phase == "day"
    elseif when == 2 then
        return phase ~= "day"
    elseif when == 3 then
        return true
    end
    return phase == "bloodmoon"
end

local function claim(z)
    if not Kinds.started() then
        return "the game has not started"
    end
    if not windowOpen() then
        return "outside the Mutants window"
    end
    local monster = Kinds.cryOfFear(z)
    if monster ~= nil then
        return "Cry of Fear " .. monster
    end
    local prefix = Kinds.excluded(z)
    if prefix ~= nil then
        return "ExcludedOutfits " .. prefix
    end
    return nil
end

-- The Mutants calls this before it turns a zombie into a mutant; a claimed zombie stays normal and
-- is asked again when it is next created or loaded.
local function isClaimed(z, outfitName)
    if z ~= nil and Settings.mutantsAdapter() then
        local reason = claim(z)
        if reason ~= nil then
            return true, OWNER, reason
        end
    end
    return original(z, outfitName)
end

-- Once only: another mod may wrap isClaimed after us, and wrapping that again would loop.
local function install()
    if gated ~= nil or Kinds.mutantsApi() == nil then
        return
    end
    local owner = PZTheMutants.ForeignOwnership
    if type(owner) ~= "table" or type(owner.isClaimed) ~= "function" then
        return
    end
    original = owner.isClaimed
    owner.isClaimed = isClaimed
    gated = owner
    Log.info("The Mutants: gate installed")
end

-- In single player OnGameBoot comes before the server files load, so the gate goes in when this
-- file loads after The Mutants, or else once every mod's Lua has loaded.
install()
Events.OnInitGlobalModData.Add(install)

local function check()
    install()
    local api, why = Kinds.mutantsApi()
    if api == nil then
        if PZTheMutants ~= nil then
            Log.error("The Mutants adapter is off: " .. why)
        end
        return
    end
    if gated == nil then
        Log.error("The Mutants has no ForeignOwnership.isClaimed, so it can't be kept from making new mutants;"
            .. " far mutants are still removed")
    end
    if type(PZTheMutants.PendingZombies) ~= "table" then
        Log.warn("The Mutants has no PendingZombies, so MutantRequeue does nothing")
    end
end

Events.OnServerStarted.Add(check)
Events.OnGameStart.Add(check)

-- Single player: the local players. getOnlinePlayers() is empty outside multiplayer.
local function players()
    local list = {}
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, online:size() - 1 do
            list[#list + 1] = online:get(i)
        end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(i)
            if player ~= nil then
                list[#list + 1] = player
            end
        end
    end
    return list
end

local function near(z, list, distance)
    local x, y = z:getX(), z:getY()
    for _, player in ipairs(list) do
        local dx, dy = player:getX() - x, player:getY() - y
        if dx * dx + dy * dy <= distance * distance then
            return true
        end
    end
    return false
end

-- A Cry of Fear monster never passes isMutant: both identities come from the same outfit index.
local function removable(z, list, distance)
    return not z:isDead() and Kinds.isMutant(z) and not z:isReanimatedForGrappleOnly()
        and z:getTarget() == nil and not near(z, list, distance) and Kinds.excluded(z) == nil
end

local function cleanup()
    local cap = Settings.mutantRemovalsPerMinute()
    local distance = Settings.mutantKeepDistance()
    local list = players()
    local zombies = getCell():getZombieList()
    local doomed = {}
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if removable(z, list, distance) then
            doomed[#doomed + 1] = z
            if #doomed == cap then
                break
            end
        end
    end
    if #doomed == 0 then
        return
    end
    -- Removing a zombie clears its online ID, so the batch is written first.
    local out = {}
    for i, z in ipairs(doomed) do
        out[i] = { id = z:getOnlineID(), x = z:getX(), y = z:getY() }
        VirtualZombieManager.instance:removeZombieFromWorld(z)
    end
    removed = removed + #doomed
    -- Sent at once, as the server may give a removed zombie's online ID to a new one. Does nothing
    -- in single player.
    sendServerCommand(State.MODULE, "out", { list = out })
    Log.info("removed " .. #doomed .. " mutants outside the Mutants window")
end

local function ordinary(z)
    return not z:isDead() and not z:isReanimatedForGrappleOnly() and not Kinds.isMutant(z)
        and Kinds.cryOfFear(z) == nil and Kinds.excluded(z) == nil and not Kinds.isBandit(z)
end

-- Requeue in progress: the next index in the zombie list.
local cursor = nil

-- The Mutants replaces its PendingZombies table on every tick that empties it, so it is read anew.
local function requeue()
    local pending = PZTheMutants.PendingZombies
    if type(pending) ~= "table" then
        cursor = nil
        return
    end
    local zombies = getCell():getZombieList()
    local offered = 0
    while cursor < zombies:size() and offered < REQUEUE_PER_MINUTE do
        local z = zombies:get(cursor)
        cursor = cursor + 1
        -- An entry already there is newer, from OnZombieCreate.
        if pending[z] == nil and ordinary(z) then
            pending[z] = { attempts = 0, retryTicks = 0 }
            offered = offered + 1
        end
    end
    lastRequeue.offered = lastRequeue.offered + offered
    if cursor >= zombies:size() then
        cursor = nil
        lastRequeue.finished = true
        Log.info("requeue done: " .. lastRequeue.offered .. " zombies offered to The Mutants")
    end
end

local function stamp()
    local now = Phase.now()
    return string.format("%s %02d:%02d", Phase.key(now), now.hour, getGameTime():getMinutes())
end

-- nil until the first minute after the start, so a game loaded inside the window doesn't requeue.
local wasOpen = nil

local function minute()
    if not active() then
        wasOpen, cursor = nil, nil
        return
    end
    local open = windowOpen()
    if open then
        if wasOpen == false and Settings.mutantRequeue() then
            cursor = 0
            lastRequeue = { began = stamp(), offered = 0, finished = false }
        end
        if cursor ~= nil then
            requeue()
        end
    else
        cursor = nil
        cleanup()
    end
    wasOpen = open
end

Events.EveryOneMinute.Add(minute)

local WHEN = { "by day", "by night", "always", "blood moons only" }

function Mutants.status()
    local api, why = Kinds.mutantsApi()
    if api == nil then
        if PZTheMutants == nil then
            return { "The Mutants: not loaded" }
        end
        return { "The Mutants: off, " .. why }
    end
    if not Settings.mutantsAdapter() then
        return { "The Mutants: off, MutantsAdapter is false" }
    end
    local gate = "gated"
    if gated == nil then
        gate = "not gated, it has no ForeignOwnership.isClaimed"
    end
    local window = "closed"
    if windowOpen() then
        window = "open"
    end
    local last = "none this session"
    if lastRequeue ~= nil then
        last = "began " .. lastRequeue.began .. ", " .. lastRequeue.offered .. " zombies offered"
        if not lastRequeue.finished then
            last = last .. ", not finished"
        end
    end
    return {
        "The Mutants: on, " .. gate .. "; window " .. window .. " (" .. WHEN[Settings.mutantsWhen()]
            .. (Settings.bloodMoonMutants() and ", open on blood moons" or "") .. ")",
        "The Mutants: " .. removed .. " mutants removed this session; last requeue " .. last,
    }
end

return Mutants
