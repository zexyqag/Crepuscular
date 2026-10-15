require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTimedActionQueue"

local Settings = require "Crepuscular/Settings"
local State = require "Crepuscular/State"

-- What a player does to keep a corpse down: Finish off, and a floor head hit. Finish off is on every
-- zombie corpse, so the menu doesn't show which ones would rise. The server, or single player, keeps
-- the corpses down.

-- A timed action's time advances by the game's multiplier, 48 a second at normal speed.
local PER_SECOND = 48

local function zombieCorpses(square, ids)
    local wanted = nil
    if ids ~= nil then
        wanted = {}
        for _, id in ipairs(ids) do
            wanted[id] = true
        end
    end
    local list = {}
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if body:isZombie() then
            local id = body:getObjectIDAsLong()
            if wanted == nil or wanted[id] then
                list[#list + 1] = id
            end
        end
    end
    return list
end

-- The zombie corpse nearest the player on the squares of the objects clicked, the first of equals, as
-- the game picks the one corpse its own corpse options act on.
local function nearest(player, worldObjects)
    local best, seen = nil, {}
    for _, o in ipairs(worldObjects) do
        local square = o:getSquare()
        if square ~= nil and not seen[square] then
            seen[square] = true
            local bodies = square:getDeadBodys()
            for i = 0, bodies:size() - 1 do
                local body = bodies:get(i)
                if body:isZombie() and (best == nil or best:DistToSquared(player) > body:DistToSquared(player)) then
                    best = body
                end
            end
        end
    end
    return best
end

local FinishOff = ISBaseTimedAction:derive("CrepuscularFinishOff")

function FinishOff:isValid()
    return #zombieCorpses(self.square, self.ids) > 0
end

function FinishOff:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

-- Without a complete(), the game runs the whole action on the player's game alone, so the server
-- needs no copy of it and gets the corpses' IDs instead.
function FinishOff:perform()
    local square = self.square
    local args = { x = square:getX(), y = square:getY(), z = square:getZ(), ids = self.ids }
    if isClient() then
        sendClientCommand(self.character, State.MODULE, "finishOff", args)
    else
        State.risers.finishOff(self.character, args)
    end
    ISBaseTimedAction.perform(self)
end

function FinishOff:new(character, square, ids)
    local o = ISBaseTimedAction.new(self, character)
    o.square = square
    o.ids = ids
    o.maxTime = Settings.finishOffSeconds() * PER_SECOND
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end

local function finish(player, square, ids)
    if luautils.walkAdj(player, square) then
        ISTimedActionQueue.add(FinishOff:new(player, square, ids))
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldObjects, test)
    if test or not Settings.finishOff() then
        return
    end
    local player = getSpecificPlayer(playerIndex)
    if player == nil then
        return
    end
    local body = nearest(player, worldObjects)
    if body == nil then
        return
    end
    local square = body:getSquare()
    local ids = zombieCorpses(square, nil)
    if #ids == 1 then
        context:addOption(getText("ContextMenu_Crepuscular_FinishOff"), player, finish, square, ids)
    else
        context:addOption(getText("ContextMenu_Crepuscular_FinishOffAll", #ids), player, finish, square, ids)
    end
end)

-- Every game that learns of a hit fires this, but only the attacker's own game knows where it landed.
Events.OnWeaponHitCharacter.Add(function(wielder, target, weapon, damage)
    if not Settings.headHitsStayDown() or not instanceof(target, "IsoZombie") or not instanceof(wielder, "IsoPlayer")
        or not wielder:isLocalPlayer() or weapon:isRanged() or target:getHitHeadWhileOnFloor() <= 0 then
        return
    end
    if isClient() then
        sendClientCommand(wielder, State.MODULE, "headHit", { id = target:getOnlineID() })
    else
        State.risers.headHit(wielder, target)
    end
end)
