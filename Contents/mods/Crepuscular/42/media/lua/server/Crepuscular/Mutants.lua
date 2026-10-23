if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Phase = require "Crepuscular/Phase"
local State = require "Crepuscular/State"
local Kinds = require "Crepuscular/Kinds"
local Clock = require "Crepuscular/Clock"

-- The Mutants adapter: a gate on new mutants while the definition in effect has off=mutants, and
-- an optional requeue of loaded zombies when they come back on. Far mutants are removed by
-- Despawn, as any kind that is off.
local Mutants = {}

local OWNER = "Crepuscular"
local REQUEUE_PER_MINUTE = 200

-- The latest requeue: { began, offered, finished }.
local lastRequeue = nil

-- The ForeignOwnership table our isClaimed is installed in, and the function it replaced.
local gated = nil
local original = nil

local function active()
    return Kinds.started() and Kinds.mutantsApi() ~= nil
end

-- Whether The Mutants may make new mutants now: the definition in effect, forced phases included.
local function mutantsOn()
    return not ModData.get(State.NAME).effects.off.mutants
end

local function claim(z)
    if not Kinds.started() then
        return "the game has not started"
    end
    if not mutantsOn() then
        return "mutants are off"
    end
    local kind = Kinds.of(z)
    if kind ~= nil and kind ~= "mutants" then
        return "kind " .. kind
    end
    return nil
end

-- The Mutants calls this before it turns a zombie into a mutant; a claimed zombie stays normal and
-- is asked again when it is next created or loaded.
local function isClaimed(z, outfitName)
    if z ~= nil then
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
            .. " far mutants are still removed while they are off")
    end
    if type(PZTheMutants.PendingZombies) ~= "table" then
        Log.warn("The Mutants has no PendingZombies, so MutantRequeue does nothing")
    end
end

Events.OnServerStarted.Add(check)
Events.OnGameStart.Add(check)

-- NPCs and members of every kind stay as they are: a mutant offered again would be healed.
local function ordinary(z, kindOf)
    return not z:isDead() and not z:isReanimatedForGrappleOnly() and not Kinds.isNpc(z) and kindOf(z) == nil
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
    local kindOf = Kinds.test()
    local offered = 0
    while cursor < zombies:size() and offered < REQUEUE_PER_MINUTE do
        local z = zombies:get(cursor)
        cursor = cursor + 1
        -- An entry already there is newer, from OnZombieCreate.
        if pending[z] == nil and ordinary(z, kindOf) then
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
    local now = Clock.now()
    return Phase.stamp(now, now.hours)
end

-- nil until the first minute after the start, so a game loaded while mutants are on doesn't requeue.
local wasOn = nil

local function minute()
    if not active() then
        wasOn, cursor = nil, nil
        return
    end
    local open = mutantsOn()
    if open then
        if wasOn == false and Settings.mutantRequeue() then
            cursor = 0
            lastRequeue = { began = stamp(), offered = 0, finished = false }
        end
        if cursor ~= nil then
            requeue()
        end
    else
        cursor = nil
    end
    wasOn = open
end

Events.EveryOneMinute.Add(minute)

function Mutants.status()
    local api, why = Kinds.mutantsApi()
    if api == nil then
        if PZTheMutants == nil then
            return { "The Mutants: not loaded" }
        end
        return { "The Mutants: off, " .. why }
    end
    local gate = "gated"
    if gated == nil then
        gate = "not gated, it has no ForeignOwnership.isClaimed"
    end
    local now = "off now"
    if mutantsOn() then
        now = "on now"
    end
    local last = "none this session"
    if lastRequeue ~= nil then
        last = "began " .. lastRequeue.began .. ", " .. lastRequeue.offered .. " zombies offered"
        if not lastRequeue.finished then
            last = last .. ", not finished"
        end
    end
    return {
        "The Mutants: " .. gate .. "; mutants " .. now,
        "The Mutants: last requeue " .. last,
    }
end

return Mutants
