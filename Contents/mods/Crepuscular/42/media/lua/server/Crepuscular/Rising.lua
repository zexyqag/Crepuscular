if isClient() then return end

local Kinds = require "Crepuscular/Kinds"
local Zombies = require "Crepuscular/Zombies"
local Clock = require "Crepuscular/Clock"

-- Corpses that get back up belong to Relentless Dead, when it is loaded. Crepuscular drives it with
-- the rise= and wake= of the definition in effect, keeps the kinds RiseKinds leaves out down, takes
-- Cry of Fear's and Silent Hill's health buffer marks off a corpse before it rises, and gives each
-- riser the speed and health of the definition in effect.
local Rising = {}

local NAME = "crepuscular"

local API = nil
if Clock.rising then
    API = require "RelentlessDead/API"
end

-- Status lines.
function Rising.status()
    if API == nil then
        return { "risers: Relentless Dead is not loaded, so rise= and wake= do nothing" }
    end
    return API.status()
end

if API == nil then
    return Rising
end

-- Asked at each death and each check of corpses. EveryTenMinutes, when corpses are checked, comes
-- before the minute's EveryOneMinute: the definition in effect is brought up to this minute first.
API.drive(NAME, function()
    if getGameTime():getMinutesStamp() ~= Clock.minute then
        Clock.tick()
    end
    return Clock.risers
end)

API.addVeto(NAME, function(z)
    local kind = Zombies.kindOf(z, Kinds.test())
    if kind ~= nil and not Clock.definitions(Clock.rule()).riseKinds[kind] then
        return "of the kind " .. kind
    end
    return nil
end)

-- Cry of Fear's and Silent Hill's marks that a monster's health buffer is on: in single player a
-- monster that rose with them would skip its health and die again at once.
local BUFFER_MARKS = { "^COF_%w+Initialized$", "^COF_%w+Padded$", "^SHM_%w+Initialized$", "^SHM_%w+Padded$" }

local function buffered(key)
    for _, pattern in ipairs(BUFFER_MARKS) do
        if string.find(key, pattern) then
            return true
        end
    end
    return false
end

API.addBeforeRise(NAME, function(body)
    local data = body:getModData()
    local keys = {}
    for key in pairs(data) do
        if type(key) == "string" and buffered(key) then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        data[key] = nil
    end
end)

Events.OnRisingRose.Add(function(z)
    Zombies.risen(z)
end)

return Rising
