local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"

-- Zombies that belong to other mods: The Mutants, Cry of Fear, Bandits and ExcludedOutfits.
local Kinds = {}

local MUTANTS_API_VERSION = 1

-- The Mutants tries its outfit lookup only once, so a call before the game has started can switch
-- off its identity for the whole session.
local started = false

local function start()
    started = true
end

Events.OnServerStarted.Add(start)
Events.OnGameStart.Add(start)

function Kinds.started()
    return started
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
                names[count] = name
                count = count + 1
            end
        end
    end
    if count == 0 then
        Log.error("the game lists no outfits, so ExcludedOutfits matches nothing")
    end
    return names
end

-- The name behind the zombie's persistent outfit ID, once the game has started. A living zombie on
-- a server is not dressed, and a reused one keeps the outfit name of its previous life, so
-- getOutfitName() can't be used.
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

local excludedText = nil
local excludedPrefixes = {}

local function prefixes()
    local text = Settings.excludedOutfits()
    if text ~= excludedText then
        excludedText = text
        excludedPrefixes = {}
        for entry in string.gmatch(text, "[^,]+") do
            local prefix = string.lower(string.match(entry, "^%s*(.-)%s*$"))
            if prefix ~= "" then
                excludedPrefixes[#excludedPrefixes + 1] = prefix
            end
        end
    end
    return excludedPrefixes
end

-- The ExcludedOutfits prefix the zombie's outfit starts with, or nil.
function Kinds.excluded(z)
    local list = prefixes()
    if #list == 0 then
        return nil
    end
    local name = outfitName(z)
    if name == nil then
        return nil
    end
    name = string.lower(name)
    for _, prefix in ipairs(list) do
        if string.sub(name, 1, #prefix) == prefix then
            return prefix
        end
    end
    return nil
end

return Kinds
