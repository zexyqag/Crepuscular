local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local State = require "Crepuscular/State"
local Kinds = require "Crepuscular/Kinds"
local Tuning = require "Crepuscular/Tuning"

-- Speed tiers and health of ordinary zombies, by the definition in effect. Every game sweeps its
-- zombies each in-game minute: the speed only of those it runs, whose packets carry it to the
-- others, and the health cap of all, since a new owner sends its own copy's health. The server
-- also sets both when it creates or loads a zombie.
local Zombies = {}

-- Since this game started, for the status.
local counts = { tiers = 0, capped = 0, created = 0 }

local function setTier(z, tier)
    if tier == 1 then
        z:doSprinter()
    elseif tier == 2 then
        z:doFastShambler()
    else
        z:doShambler()
    end
end

-- Whether this game runs z. On a server isRemoteZombie() is true exactly when no player's game
-- runs it, so the owner is asked there; in single player a zombie has no owner.
local runs
if isClient() then
    runs = function(z)
        return not z:isRemoteZombie()
    end
else
    runs = function(z)
        return z:getOwner() == nil
    end
end

-- In single player a zombie gets its outfit ID when the game dresses it, which it does when it first
-- draws it or is asked its outfit name; until then the ID is 0.
local solo = not isClient() and not isServer()

local function outfitID(z)
    local id = z:getPersistentOutfitID()
    if id == 0 and solo then
        z:getOutfitName()
        id = z:getPersistentOutfitID()
    end
    return id
end

-- zombie -> { id, h, roll }: its hashes, kept until its outfit ID changes.
local known = setmetatable({}, { __mode = "k" })

local function hashes(z, id)
    local entry = known[z]
    if entry == nil or entry.id ~= id then
        entry = { id = id, h = Tuning.hash(id), roll = Tuning.roll(id) }
        known[z] = entry
    end
    return entry
end

-- Left alone: dead, crawling, dragged corpses, zombies playing dead, Bandits and every kind's members.
-- A single player zombie is dressed before its kind is told, so the kinds see its outfit.
local function ordinary(z, kindOf)
    if z:isDead() or z:isCrawling() or z:isReanimatedForGrappleOnly() or z:isFakeDead() or Kinds.isBandit(z) then
        return false
    end
    outfitID(z)
    return kindOf(z) == nil
end

-- What the definition in effect asks, with the game settings it depends on, read live.
local function rules(effects)
    local lore = SandboxVars.ZombieLore
    return {
        speed = effects.speed, steps = effects.steps, fmax = effects.fmax, smax = effects.smax,
        reach = effects.fmax > 0 or effects.smax > 0,
        game = lore.Speed, percent = lore.SprinterPercentage,
        cap = Tuning.cap(effects.health, lore.Toughness),
    }
end

-- The tier the definition in effect gives a zombie some definition's speed reaches, or nil when it
-- has it already or none reaches it.
local function retier(z, r)
    local id = outfitID(z)
    -- In multiplayer each player's game dresses a zombie without an outfit ID at random, so its hash
    -- would differ from one game to the next.
    if id == 0 then
        return nil
    end
    local entry = hashes(z, id)
    if not Tuning.managed(entry.h, r.fmax, r.smax) then
        return nil
    end
    local tier = Tuning.target(entry.h, Tuning.base(entry.roll, r.game, r.percent), r.speed, r.steps)
    if Tuning.tier(z:getWalkType()) == tier then
        return nil
    end
    return tier
end

local function retiered(z, tier)
    setTier(z, tier)
    counts.tiers = counts.tiers + 1
end

-- The next index in the zombie list.
local cursor = 0

local function sweep()
    local state = State.get()
    if state == nil then
        return
    end
    local r = rules(state.effects)
    if not r.reach and r.cap == nil then
        return
    end
    local zombies = getCell():getZombieList()
    local size = zombies:size()
    local kindOf = Kinds.test()
    for _ = 1, math.min(Settings.zombiesPerSweep(), size) do
        if cursor >= size then
            cursor = 0
        end
        local z = zombies:get(cursor)
        cursor = cursor + 1
        -- Telling a zombie's kind costs more than everything else here, so it comes last.
        local tier = nil
        if r.reach and runs(z) then
            tier = retier(z, r)
        end
        local capped = r.cap ~= nil and Tuning.above(z:getHealth(), r.cap)
        if (tier ~= nil or capped) and ordinary(z, kindOf) then
            if tier ~= nil then
                retiered(z, tier)
            end
            if capped then
                z:setHealth(r.cap)
                counts.capped = counts.capped + 1
            end
        end
    end
end

Events.EveryOneMinute.Add(sweep)

-- No player's game runs a zombie being created, and its health was just rolled, so the factor
-- can't heal a wound. A zombie a mod spawns in an outfit is dressed after this event, which changes
-- its outfit ID: the sweep gives it its tier again, and health the mod sets wins.
local function created(z)
    local state = State.get()
    if not Kinds.started() or state == nil then
        return
    end
    local r = rules(state.effects)
    local f = state.effects.health
    if not r.reach and f == 1 then
        return
    end
    -- The game adds a new zombie to the list after this event; other mods fire it again for zombies
    -- already in the world.
    if getCell():getZombieList():contains(z) then
        return
    end
    if not ordinary(z, Kinds.test()) then
        return
    end
    if r.reach then
        local tier = retier(z, r)
        if tier ~= nil then
            retiered(z, tier)
        end
    end
    if f ~= 1 then
        z:setHealth(Tuning.created(z:getHealth(), f))
        counts.created = counts.created + 1
    end
end

if not isClient() then
    Events.OnZombieCreate.Add(created)
end

-- Warns once about game settings that work against the speed= of the definitions.
function Zombies.check(fmax, smax)
    local lore = SandboxVars.ZombieLore
    if smax > 0 and lore.Speed == 1 then
        Log.warnOnce("speed sprinters", "ZombieLore.Speed is Sprinters: the game makes every zombie run when it"
            .. " lunges, whatever its walk type, so speed=-N can't slow zombies down")
    end
    if (fmax > 0 or smax > 0) and lore.ActiveOnly ~= 1 then
        Log.warnOnce("speed active only", "ZombieLore.ActiveOnly is not Both: the game itself makes inactive"
            .. " zombies shamblers and gives them their speed back, which fights the speed= of the definitions")
    end
end

local function signed(n)
    if n > 0 then
        return "+" .. n
    end
    return tostring(n)
end

-- Status lines: what the definition in effect asks, and the zombies this game has loaded.
function Zombies.status()
    local effects = State.get().effects
    local lore = SandboxVars.ZombieLore
    local line = "zombies: speed " .. signed(effects.speed) .. ", steps " .. effects.steps .. ", health " .. effects.health
    local cap = Tuning.cap(effects.health, lore.Toughness)
    if cap ~= nil then
        line = line .. string.format(", at most %.2f", cap)
    end
    line = line .. "; the definitions' speed= reaches " .. math.min(100, effects.fmax + effects.smax)
        .. " in 100 ordinary zombies; " .. Settings.zombiesPerSweep() .. " checked per minute"
    local tiers, ordinaries = { 0, 0, 0 }, 0
    local low, high = nil, nil
    local zombies = getCell():getZombieList()
    local kindOf = Kinds.test()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if ordinary(z, kindOf) then
            ordinaries = ordinaries + 1
            local tier = Tuning.tier(z:getWalkType())
            tiers[tier] = tiers[tier] + 1
            local health = z:getHealth()
            low = math.min(low or health, health)
            high = math.max(high or health, health)
        end
    end
    local loaded = "zombies loaded: " .. zombies:size() .. ", ordinary " .. ordinaries .. ": " .. tiers[1]
        .. " sprinters, " .. tiers[2] .. " fast shamblers, " .. tiers[3] .. " shamblers"
    if low ~= nil then
        loaded = loaded .. string.format(", health %.2f to %.2f", low, high)
    end
    return {
        line,
        loaded .. "; this session " .. counts.tiers .. " speed changes, " .. counts.capped .. " capped, "
            .. counts.created .. " created with the health factor",
    }
end

return Zombies
