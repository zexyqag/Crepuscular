local Log = require "Crepuscular/Log"
local State = require "Crepuscular/State"
local Defs = require "Crepuscular/Defs"

-- Monster kinds: named sets of zombies that other mods make. A zombie belongs to the first kind
-- whose test it passes: cof, silenthill, volatiles, mutants, the kinds of the Kinds option in order,
-- the kinds other mods register (API.lua), then the kinds of Zomboid Forge's types, last because
-- Zomboid Forge can give every zombie a type. Bandits belong to none.
local Kinds = {}

Kinds.BUILTIN = { cof = true, silenthill = true, volatiles = true, mutants = true }

local MUTANTS_API_VERSION = 1

-- B42 mod ids start with a backslash.
local FORGE_MOD = "\\ZomboidForge"
-- Zomboid Forge sets no global: its own files and its add-ons require this module.
local FORGE_MODULE = "ZomboidForge_module"
local SILENT_HILL_MOD = "\\SilentHillMonsters"
-- Its monsters' outfits, SHM_ and the monster's name, lowercased as outfitName gives them.
local SILENT_HILL_OUTFIT = "shm_"
local BLACKOUT_MOD = "\\blackoutpredators"

-- The Mutants tries its outfit lookup only once, so a call before the game has started can switch
-- off its identity for the whole session.
local started = false
-- Changes with every registration, at the start and when Zomboid Forge's types change, for whatever
-- depends on the kinds.
local revision = 0

-- Zomboid Forge's module, or nil and why it can't be used.
local function forgeApi()
    if not getActivatedMods():contains(FORGE_MOD) then
        return nil, "not loaded"
    end
    local api = require(FORGE_MODULE)
    if type(api) ~= "table" or type(api.GetZType) ~= "function" or type(api.ZTypes) ~= "table" then
        return nil, "loaded, but its " .. FORGE_MODULE .. " has no GetZType function and ZTypes table"
    end
    return api
end

-- Zomboid Forge once the game has started with its module as Crepuscular knows it, else nil:
-- { api, kinds = type id -> kind, types = kind -> its type ids, skipped = { { id, why } }, key }.
local forge = nil
local forgeWhy = "not loaded"

-- Whether the types changed. Zomboid Forge builds them as the world loads, and its add-ons may add
-- more as the game starts.
local function readForge()
    local ids = {}
    for id in pairs(forge.api.ZTypes) do
        if type(id) == "string" then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local kinds, types, skipped, key = {}, {}, {}, ""
    for _, id in ipairs(ids) do
        local name, why = Defs.forgeKind(id, Kinds.BUILTIN)
        if name == nil then
            skipped[#skipped + 1] = { id = id, why = why }
            key = key .. id .. ";"
        else
            kinds[id] = name
            types[name] = types[name] or {}
            table.insert(types[name], id)
            key = key .. id .. "=" .. name .. ";"
        end
    end
    if key == forge.key then
        return false
    end
    forge.kinds, forge.types, forge.skipped, forge.key = kinds, types, skipped, key
    for _, skip in ipairs(skipped) do
        if skip.id ~= Defs.FORGE_ORDINARY then
            Log.warnOnce("forge type " .. skip.id, "Zomboid Forge's type " .. skip.id .. " " .. skip.why
                .. ", so it has no kind and Crepuscular treats its zombies as ordinary")
        end
    end
    Log.info("Zomboid Forge: " .. Kinds.forgeStatus())
    return true
end

local function minute()
    if readForge() then
        revision = revision + 1
    end
end

local function start()
    started = true
    local api, why = forgeApi()
    forgeWhy = why
    if api ~= nil then
        if forge == nil then
            Events.EveryOneMinute.Add(minute)
        end
        forge = { api = api }
        readForge()
    elseif why ~= "not loaded" then
        Log.warnOnce("forge api", "Zomboid Forge is " .. why .. ", so its zombie types have no kinds and"
            .. " Crepuscular treats them as ordinary zombies")
    end
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
        Log.error("the game lists no outfits, so silenthill, volatiles and the kinds of the Kinds option match nothing")
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

local silentHill = getActivatedMods():contains(SILENT_HILL_MOD)

function Kinds.silentHillLoaded()
    return silentHill
end

-- Silent Hill Monster NPCs tells its monsters by the same outfit index, on the server and on every game.
local function isSilentHill(z)
    if not silentHill then
        return false
    end
    local name = outfitName(z)
    return name ~= nil and string.sub(name, 1, #SILENT_HILL_OUTFIT) == SILENT_HILL_OUTFIT
end

local blackout = getActivatedMods():contains(BLACKOUT_MOD)

function Kinds.blackoutLoaded()
    return blackout
end

-- The outfit Blackout Predators makes its Volatiles in, from its shared file, lowercased; nil while it
-- has none.
function Kinds.volatileOutfit()
    local mod = BlackoutPredators
    if type(mod) ~= "table" or type(mod.Outfit) ~= "string" then
        return nil
    end
    return string.lower(mod.Outfit)
end

-- Its Volatiles, by their persistent outfit on the server and on every game: its own modData flag
-- reaches players' games only with its state records.
local function isVolatile(z)
    if not blackout then
        return false
    end
    local outfit = Kinds.volatileOutfit()
    if outfit == nil then
        Log.warnOnce("volatile outfit", "Blackout Predators is loaded without BlackoutPredators.Outfit, so the kind"
            .. " volatiles has no members and Crepuscular treats its Volatiles as ordinary zombies")
        return false
    end
    return outfitName(z) == outfit
end

Kinds.register("cof", { isMember = function(z)
    return Kinds.cryOfFear(z) ~= nil
end })
Kinds.register("silenthill", { isMember = isSilentHill })
-- Never removed: Blackout Predators frees a nest's place only when its Volatile dies.
Kinds.register("volatiles", { isMember = isVolatile, despawn = false })
Kinds.register("mutants", { isMember = Kinds.isMutant })

-- Whether a built-in kind can have members in this game.
local AVAILABLE = {
    cof = Kinds.cryOfFearLoaded,
    silenthill = Kinds.silentHillLoaded,
    mutants = function()
        return started and Kinds.mutantsApi() ~= nil
    end,
}

local EMPTY = {}

-- The Kinds option as the server parsed it: { { name, prefixes } }, prefixes lowercased. A state
-- saved before there were kinds has none until the server's next minute.
local function optionKinds()
    local state = State.get()
    if state == nil or state.kinds == nil then
        return EMPTY
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

-- Another mod's member test; one that fails counts as no member.
local function member(entry, z)
    local ok, result = pcall(entry.isMember, z)
    if not ok then
        Log.warnOnce("isMember " .. entry.name, "the kind " .. entry.name .. " another mod registered fails its"
            .. " member test, so it has no members: " .. tostring(result))
        return false
    end
    return result
end

-- The kind of z's Zomboid Forge type, or nil. Asking the type of a zombie without an outfit ID
-- dresses it at random, and Zomboid Forge leaves players' zombies alone.
local function forgeKindOf(z)
    if forge == nil or z:getPersistentOutfitID() == 0 or z:isReanimatedPlayer() then
        return nil
    end
    local ok, ztype = pcall(forge.api.GetZType, z)
    if not ok then
        Log.warnOnce("forge GetZType", "Zomboid Forge's GetZType fails, so its zombies have no kind: " .. tostring(ztype))
        return nil
    end
    return forge.kinds[ztype]
end

-- The kinds of Zomboid Forge's types, sorted.
local function forgeNames()
    local names = {}
    if forge ~= nil then
        for name in pairs(forge.types) do
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

-- Kind name -> what took it from the kinds other mods register.
local function takenNames(options)
    local taken = {}
    for _, kind in ipairs(options) do
        taken[kind.name] = "the Kinds option"
    end
    for _, name in ipairs(forgeNames()) do
        taken[name] = taken[name] or "Zomboid Forge"
    end
    return taken
end

-- The membership test, built again when the Kinds option's kinds or the kinds change.
local test, testKinds, testRevision = nil, nil, nil

local function classifier()
    local options = optionKinds()
    if test ~= nil and testKinds == options and testRevision == revision then
        return test
    end
    local taken = takenNames(options)
    local others = {}
    for _, entry in ipairs(registered) do
        if taken[entry.name] == nil then
            others[#others + 1] = entry
        elseif taken[entry.name] == "Zomboid Forge" then
            Log.warnOnce("forge name " .. entry.name, "the kind " .. entry.name .. " another mod registered has the"
                .. " name of the kind of Zomboid Forge's type " .. table.concat(forge.types[entry.name], ", ")
                .. ", which takes it")
        end
    end
    test = function(z)
        if Kinds.isBandit(z) then
            return nil
        end
        for _, entry in ipairs(builtins) do
            if entry.isMember(z) then
                return entry.name
            end
        end
        if #options > 0 then
            local name = outfitName(z)
            if name ~= nil then
                for _, kind in ipairs(options) do
                    if startsWithAny(name, kind.prefixes) then
                        return kind.name
                    end
                end
            end
        end
        for _, entry in ipairs(others) do
            if member(entry, z) then
                return entry.name
            end
        end
        return forgeKindOf(z)
    end
    testKinds, testRevision = options, revision
    return test
end

-- The kind z belongs to, or nil.
function Kinds.of(z)
    return classifier()(z)
end

-- Kinds.of for many zombies in a row.
function Kinds.test()
    return classifier()
end

-- Crepuscular's kind names, which the Kinds option can't take and off= may always name: cof,
-- silenthill, volatiles, mutants and the kinds of Zomboid Forge's types.
function Kinds.builtin()
    local names = {}
    for name in pairs(Kinds.BUILTIN) do
        names[name] = true
    end
    for _, name in ipairs(forgeNames()) do
        names[name] = true
    end
    return names
end

-- Of the kinds in off, those that can have members in this game and whose far members are
-- removed; and whether there is any.
function Kinds.removable(off)
    local options = {}
    for _, kind in ipairs(optionKinds()) do
        options[kind.name] = true
    end
    local out, any = {}, false
    for name in pairs(off) do
        local can
        if Kinds.BUILTIN[name] then
            can = byName[name].despawn and AVAILABLE[name]()
        elseif options[name] or (forge ~= nil and forge.types[name] ~= nil) then
            can = true
        else
            can = byName[name] ~= nil and byName[name].despawn
        end
        if can then
            out[name] = true
            any = true
        end
    end
    return out, any
end

-- Every kind in membership order: { name, source = "built in", "Kinds option", "registered" or
-- "Zomboid Forge" and its types, hidden = what took the name of a registered kind }.
function Kinds.list()
    local list = {}
    for _, entry in ipairs(builtins) do
        list[#list + 1] = { name = entry.name, source = "built in" }
    end
    local options = optionKinds()
    for _, kind in ipairs(options) do
        list[#list + 1] = { name = kind.name, source = "Kinds option" }
    end
    local taken = takenNames(options)
    for _, entry in ipairs(registered) do
        list[#list + 1] = { name = entry.name, source = "registered", hidden = taken[entry.name] }
    end
    for _, name in ipairs(forgeNames()) do
        list[#list + 1] = { name = name, source = "Zomboid Forge " .. table.concat(forge.types[name], ", ") }
    end
    return list
end

-- What Crepuscular makes of Zomboid Forge, for the status.
function Kinds.forgeStatus()
    if forge == nil then
        return forgeWhy
    end
    local names = forgeNames()
    local line = "no kinds"
    if #names > 0 then
        line = "kinds " .. table.concat(names, ", ")
    end
    for _, skip in ipairs(forge.skipped) do
        line = line .. "; no kind for " .. skip.id .. ", which " .. skip.why
    end
    return line
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
