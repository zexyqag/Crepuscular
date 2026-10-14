if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Phase = require "Crepuscular/Phase"
local State = require "Crepuscular/State"
local Sandbox = require "Crepuscular/Sandbox"

local Clock = {}

-- Full-moon dates come in runs of 2-4 days, 29.5 days apart.
local ROLL_GAP_HOURS = 20 * 24

-- "day", "night" or "bloodmoon" while an admin forces the phase. Never saved.
Clock.forced = nil

-- A dedicated server can transmit only once it has started listening.
local started = false

local function publish(state)
    if isServer() then
        if started then
            ModData.transmit(State.NAME)
        end
    else
        State.notify(state)
    end
end

-- Called once per night window, with the date the window opened on.
local function decide(bloodMoon, start, key, now)
    local moon = Phase.moon(start.year, start.month, start.day)
    if moon ~= Phase.FULL_MOON then
        Log.info("night of " .. key .. ": moon phase " .. moon .. ", not full")
        return
    end
    local chance = Settings.bloodMoonChance()
    if chance == 0 then
        Log.info("night of " .. key .. ": full moon, blood moon chance is 0")
        return
    end
    if bloodMoon.lastRollAt ~= nil and now.hours - bloodMoon.lastRollAt < ROLL_GAP_HOURS then
        Log.info("night of " .. key .. ": full moon, already rolled for this one")
        return
    end
    bloodMoon.lastRollAt = now.hours
    local roll = ZombRand(100)
    if roll < chance then
        bloodMoon.active = true
        bloodMoon.night = key
        Log.info("night of " .. key .. ": rolled " .. roll .. " under " .. chance .. ", blood moon")
    else
        Log.info("night of " .. key .. ": rolled " .. roll .. ", not under " .. chance .. ", no blood moon")
    end
end

function Clock.tick()
    local state = ModData.get(State.NAME)
    local bloodMoon = state.bloodMoon
    local now = Phase.now()
    local open, start = Phase.window(now)
    local key = open and Phase.key(start) or nil
    local dirty = false

    if bloodMoon.active and bloodMoon.night ~= key then
        bloodMoon.active = false
        Log.info("blood moon of " .. bloodMoon.night .. " is over")
        dirty = true
    end
    if open and bloodMoon.decided ~= key then
        bloodMoon.decided = key
        decide(bloodMoon, start, key, now)
        dirty = true
    end

    local phase = Clock.forced
    if phase == nil then
        if not open then
            phase = "day"
        elseif bloodMoon.active then
            phase = "bloodmoon"
        else
            phase = "night"
        end
    end
    if phase ~= state.phase then
        if phase == "bloodmoon" then
            bloodMoon.id = bloodMoon.id + 1
        end
        Log.info("phase " .. state.phase .. " -> " .. phase)
        state.phase = phase
        dirty = true
    end

    local values, changed = Sandbox.sync(phase)
    state.sandbox = values
    if dirty or changed then
        publish(state)
    end
end

-- phase is nil for automatic.
function Clock.force(phase)
    Clock.forced = phase
    Log.info("phase forced to " .. (phase or "automatic"))
    Clock.tick()
end

-- Rolls the chance for the current night window, ignoring the moon and the last roll.
-- Returns "yes", "no", "day" (no window open) or "active".
function Clock.rollNow()
    local bloodMoon = ModData.get(State.NAME).bloodMoon
    local open, start = Phase.window(Phase.now())
    if not open then
        return "day"
    end
    if bloodMoon.active then
        return "active"
    end
    local key = Phase.key(start)
    bloodMoon.decided = key
    if ZombRand(100) >= Settings.bloodMoonChance() then
        Log.info("admin roll for the night of " .. key .. ": no blood moon")
        return "no"
    end
    bloodMoon.active = true
    bloodMoon.night = key
    Log.info("admin roll for the night of " .. key .. ": blood moon")
    Clock.tick()
    return "yes"
end

-- After the world has loaded: OnInitGlobalModData comes before the seasons that isNight() needs.
local function init()
    local state = ModData.getOrCreate(State.NAME)
    if state.version == nil then
        state.version = State.VERSION
        state.phase = "day"
        state.bloodMoon = { active = false, id = 0 }
        state.sandbox = {}
    end
    Clock.tick()
end

Events.OnGameTimeLoaded.Add(init)
Events.EveryOneMinute.Add(Clock.tick)
Events.OnServerStarted.Add(function()
    started = true
end)
-- Single player: the local players exist from here on.
Events.OnGameStart.Add(function()
    State.notify(ModData.get(State.NAME))
end)

return Clock
