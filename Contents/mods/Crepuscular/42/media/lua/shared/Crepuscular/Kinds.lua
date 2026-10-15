local Log = require "Crepuscular/Log"
local State = require "Crepuscular/State"

-- Monster kinds: named sets of zombies that other mods make. A zombie belongs to the first kind
-- whose test it passes: cof, mutants, the kinds of the Kinds option in order, then the kinds other
-- mods register (API.lua). Bandits belong to none.
local Kinds = {}

Kinds.BUILTIN = { cof = true, mutants = true }

local MUTANTS_API_VERSION = 1

-- The Mutants tries its outfit lookup only once, so a call before the game has started can switch
-- off its identity for the whole session.
local started = false
-- Changes with every registration and at the start, for whatever depends on the registry.
local revision = 0

local function start()
    started = true
    revision = revision + 1
end

Events.OnServerStarted.Add(start)
Events.OnGameStart.Add(start)

function Kinds.started()
    return started
end

function Kinds.revision()
    return revision
end

-- Kinds registered by code, each { name, isMember, despawn }: the built-ins, and other mods' ones
-- in the order they first registered.
local builtins = {}
local registered = {}
local byName = {}

-- spec: { isMember = function(z), despawn = false to never remove far members }. The same name
-- again replaces its spec.
function Kinds.register(name, spec)
    local entry = byName[name]
    if entry == nil then
        entry = { name = name }
        byName[name] = entry
        local list = registered
        if Kinds.BUILTIN[name] then
            list = builtins
        end
        list[#list + 1] = entry
    end
    entry.isMember = spec.isMember
    entry.despawn = spec.despawn ~= false
    revision = revision + 1
end

-- The names other mods registered, once the game has started; nil before, when some may still
-- be missing.
function Kinds.registered()
    if not started then
        return nil
    end
    local names = {}
    for _, entry in ipairs(registered) do
        names[entry.name] = true
    end
    return names
end

-- The Mutants' public API, or nil and why it can't be used.
function Kinds.mutantsApi()
    if PZTheMutants == nil then
        return nil, "not loaded"
    end
    local api = PZTheMutants.API
    if type(api) ~= "table" or type(api.isMutant) ~= "function" then
        return nil, "loaded without PZTheMutants.API"
    end
    if api.VERSION ~= MUTANTS_API_VERSION then
        return nil, "API version " .. tostring(api.VERSION) .. ", Crepuscular knows version " .. MUTANTS_API_VERSION
    end
    return api
end

function Kinds.isMutant(z)
    if not started then
        return false
    end
    local api = Kinds.mutantsApi()
    return api ~= nil and api.isMutant(z)
end

-- Cry of Fear's identity function lives in its server file on a server and in its client file
-- in single player and on players' games.
local function cryOfFearIdentity()
    local identity
    if isServer() then
        identity = COF_ServerMonsters
    else
        identity = COF_MonsterIdentity
    end
    if type(identity) == "table" and type(identity.name) == "function" then
        return identity
    end
    return nil
end

function Kinds.cryOfFearLoaded()
    return cryOfFearIdentity() ~= nil
end

-- The Cry of Fear monster's name, or nil.
function Kinds.cryOfFear(z)
    local identity = cryOfFearIdentity()
    if identity == nil then
        return nil
    end
    return identity.name(z)
end

function Kinds.isBandit(z)
    return z:getVariableBoolean("Bandit")
end

Kinds.register("cof", { isMember = function(z)
    return Kinds.cryOfFear(z) ~= nil
end })
Kinds.register("mutants", { isMember = Kinds.isMutant })

-- Outfit index -> name, numbered as the game numbers persistent outfits: the female names sorted,
-- then the male ones, each name once whatever its case.
local outfitNames = nil

local function listOutfits()
    local names, seen, count = {}, {}, 0
    for _, female in ipairs({ true, false }) do
        local list = getAllOutfits(female)
        for i = 0, list:size() - 1 do
            local name = list:get(i)
            local key = string.lower(name)
            if not seen[key] then
                seen[key] = true
                names[count] = key
                count = count + 1
            end
        end
    end
    if count == 0 then
        Log.error("the game lists no outfits, so the kinds of the Kinds option match nothing")
    end
    return names
end

-- The lowercased name behind the zombie's persistent outfit ID. A living zombie on a server is not
-- dressed, and a reused one keeps the outfit name of its previous life, so getOutfitName() can't
-- be used.
local function outfitName(z)
    local id = z:getPersistentOutfitID()
    if id == 0 then
        return nil
    end
    if outfitNames == nil then
        outfitNames = listOutfits()
    end
    -- Bit 31 is the female flag and bits 30-16 the outfit index.
    if id < 0 then
        id = id + 2147483648
    end
    return outfitNames[math.floor(id / 65536)]
end

-- The Kinds option as the server parsed it: { { name, prefixes } }, prefixes lowercased.
local function optionKinds()
    local state = State.get()
    if state == nil then
        return {}
    end
    return state.kinds
end

local function startsWithAny(name, prefixes)
    for _, prefix in ipairs(prefixes) do
        if string.sub(name, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- The kind z belongs to and whether its far members are removed while it is off; nil if none.
function Kinds.of(z)
    if Kinds.isBandit(z) then
        return nil
    end
    for _, entry in ipairs(builtins) do
        if entry.isMember(z) then
            return entry.name, entry.despawn
        end
    end
    local options = optionKinds()
    local taken = {}
    if #options > 0 then
        local name = outfitName(z)
        for _, kind in ipairs(options) do
            taken[kind.name] = true
            if name ~= nil and startsWithAny(name, kind.prefixes) then
                return kind.name, true
            end
        end
    end
    for _, entry in ipairs(registered) do
        if not taken[entry.name] and entry.isMember(z) then
            return entry.name, entry.despawn
        end
    end
    return nil
end

-- Every kind in membership order: { name, source = "built in", "Kinds option" or "registered",
-- hidden = a registered kind the Kinds option has taken the name of }.
function Kinds.list()
    local list, taken = {}, {}
    for _, entry in ipairs(builtins) do
        list[#list + 1] = { name = entry.name, source = "built in" }
    end
    for _, kind in ipairs(optionKinds()) do
        taken[kind.name] = true
        list[#list + 1] = { name = kind.name, source = "Kinds option" }
    end
    for _, entry in ipairs(registered) do
        list[#list + 1] = { name = entry.name, source = "registered", hidden = taken[entry.name] }
    end
    return list
end

-- Cry of Fear stops these looping sounds before it takes a monster out (its COF_NetSync.Loops):
-- removing a zombie doesn't stop what its emitter plays.
local COF_LOOPS = { "COF_Sawcrazy_Engine", "COF_Sawrunner_Engine", "COF_Stranger_Voice" }

-- Removes z from this game as VirtualZombieManager does, a Cry of Fear monster the way Cry of Fear
-- removes one.
function Kinds.remove(z, kind)
    if kind == "cof" then
        local emitter = z:getEmitter()
        for _, sound in ipairs(COF_LOOPS) do
            emitter:stopOrTriggerSoundByName(sound)
        end
        z:setTarget(nil)
    end
    VirtualZombieManager.instance:removeZombieFromWorld(z)
end

return Kinds
