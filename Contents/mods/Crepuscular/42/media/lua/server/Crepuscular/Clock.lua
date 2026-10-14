if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Phase = require "Crepuscular/Phase"
local State = require "Crepuscular/State"
local Defs = require "Crepuscular/Defs"
local Schedule = require "Crepuscular/Schedule"
local Overrides = require "Crepuscular/Overrides"
local Sandbox = require "Crepuscular/Sandbox"

local Clock = {}

-- "day" or "night" while an admin forces the phase. Never saved.
Clock.forced = nil

-- The kinds off= knows.
local KINDS = { mutants = true }

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

function Clock.now()
    local time = getGameTime()
    return {
        year = time:getYear(),
        month = time:getMonth(),
        day = time:getDay() + 1,
        time = time:getTimeOfDay(),
        hours = time:getWorldAgeHours(),
    }
end

function Clock.rule()
    if Settings.nightMode() == 2 then
        local time = getGameTime()
        local endless = nil
        if time:isEndlessNight() then
            endless = "night"
        elseif time:isEndlessDay() then
            endless = "day"
        end
        local season = getClimateManager():getSeason()
        return { mode = 2, endless = endless, dawn = season:getDawn(), dusk = season:getDusk() }
    end
    local start, finish = Settings.nightStartHour(), Settings.nightEndHour()
    if start == finish then
        Log.warnOnce("no night", "NightStartHour equals NightEndHour (" .. start .. "), so there is no night")
    end
    return { mode = 1, start = start, finish = finish }
end

-- The texts and hours the definitions were last parsed from, and the result.
local source = {}
local parsed = nil

-- The definitions, parsed again whenever a text or the fixed hours change.
function Clock.definitions(rule)
    local texts = {}
    local same = parsed ~= nil and source.mode == rule.mode and source.start == rule.start
        and source.finish == rule.finish
    for _, name in ipairs(Defs.OPTIONS) do
        texts[name] = Settings.definition(name)
        same = same and source[name] == texts[name]
    end
    if same then
        return parsed
    end
    local defs = Defs.parse(texts, rule, KINDS)
    local all = { defs.day, defs.night }
    for _, ev in ipairs(defs.events) do
        all[#all + 1] = ev
    end
    defs.names = {}
    for _, def in ipairs(all) do
        def.values = Overrides.check(def.label, def.set, defs.warnings)
        for name in pairs(def.values) do
            defs.names[name] = true
        end
    end
    for _, text in ipairs(defs.errors) do
        Log.warnOnce(text, text)
    end
    for _, text in ipairs(defs.warnings) do
        Log.warnOnce(text, text)
    end
    for _, name in ipairs(Defs.OPTIONS) do
        local bytes = Defs.bytes(texts[name])
        if bytes > Defs.LIMIT then
            Log.errorOnce(name .. " " .. bytes, name .. " is " .. bytes .. " bytes; above 32767 the game silently"
                .. " corrupts the save and the connect packet, so keep each option under " .. Defs.LIMIT)
        end
    end
    Log.info(#defs.events .. " events loaded, " .. defs.failed .. " definitions with errors")
    texts.mode, texts.start, texts.finish = rule.mode, rule.start, rule.finish
    source = texts
    parsed = defs
    return defs
end

-- Read only when a decision needs it.
local function climate()
    local manager = getClimateManager()
    return {
        rain = manager:isRaining(),
        snow = manager:isSnowing(),
        storm = manager:getIsThunderStorming(),
        fog = manager:getFogIntensity(),
        temp = manager:getTemperature(),
        season = manager:getSeason():getSeason(),
    }
end

local function roll()
    return ZombRandFloat(0, 100)
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = copy(v)
    end
    return out
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not same(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

-- Resolves the definition in effect (3.1), applies its sandbox values and publishes on change.
local function update(state, ledger, defs)
    local clock = ledger.occasion.phase
    local phase = Clock.forced or clock
    local current = ledger.current
    local ev = nil
    if current ~= nil and current.running then
        ev = defs.byId[current.id]
    end
    local base, label = defs.day, phase
    if ev ~= nil then
        label = ev.id
        if ev.track == "moon" then
            base = defs.night
        end
    elseif phase == "night" then
        base = defs.night
    end

    local off = base.off or {}
    local wanted = copy(base.values)
    local announce = nil
    if ev ~= nil then
        if ev.off ~= nil then
            off = ev.off
        end
        for name, value in pairs(ev.values) do
            wanted[name] = value
        end
        if ev.say ~= nil then
            announce = { serial = current.serial, text = ev.say, color = ev.color or "ffffff" }
        end
    elseif ledger.occasion.serial ~= nil and phase == clock and base.say ~= nil then
        announce = { serial = ledger.occasion.serial, text = base.say, color = base.color or "ffffff" }
    end
    local event = nil
    if current ~= nil then
        event = {
            id = current.id, track = current.track, serial = current.serial, running = current.running,
            startsAt = current.startsAt or current.at, endsAt = current.endsAt,
        }
    end

    local sandbox, changed = Sandbox.sync(defs.names, wanted, label)
    local fresh = {
        version = State.VERSION,
        phase = phase,
        forced = Clock.forced ~= nil,
        event = event,
        effects = { off = copy(off) },
        announce = announce,
        sandbox = sandbox,
        ids = copy(defs.ids),
        errors = defs.failed,
    }
    if changed or not same(state, fresh) then
        for k in pairs(state) do
            if fresh[k] == nil then
                state[k] = nil
            end
        end
        for k, v in pairs(fresh) do
            state[k] = v
        end
        publish(state)
    end
end

function Clock.tick()
    local state = ModData.get(State.NAME)
    local ledger = ModData.get(State.LEDGER)
    local rule = Clock.rule()
    local defs = Clock.definitions(rule)
    local now = Clock.now()
    local occasion = Phase.occasion(now, rule)
    Schedule.tick(ledger, defs, {
        occasion = occasion,
        key = Phase.key(occasion.date),
        now = now.hours,
        -- Before the climate's first update, weather getters return initial values.
        ready = getClimateManager():isUpdated(),
        climate = climate,
        roll = roll,
    }, Log.info)
    update(state, ledger, defs)
end

-- phase is nil for automatic.
function Clock.force(phase)
    Clock.forced = phase
    Log.info("phase forced to " .. (phase or "automatic"))
    Clock.tick()
end

-- Admin: starts the event now. Returns false for an id that isn't loaded.
function Clock.start(id)
    local defs = Clock.definitions(Clock.rule())
    if defs.byId[id] == nil then
        return false
    end
    Schedule.begin(ModData.get(State.LEDGER), defs, id, Clock.now().hours, Log.info)
    Clock.tick()
    return true
end

-- Admin: ends the current event. Returns its id, or nil if there was none.
function Clock.stop()
    local id = Schedule.stop(ModData.get(State.LEDGER), Log.info)
    Clock.tick()
    return id
end

-- Admin: decides this occasion again. Returns "running", the chosen id or false.
function Clock.redecide()
    local result = Schedule.redecide(ModData.get(State.LEDGER), Clock.definitions(Clock.rule()), {
        now = Clock.now().hours,
        climate = climate,
        roll = roll,
    }, Log.info)
    Clock.tick()
    return result
end

-- After the world has loaded: OnInitGlobalModData comes before the seasons the clock needs.
local function init()
    local state = ModData.getOrCreate(State.NAME)
    if state.version ~= State.VERSION then
        if state.version ~= nil then
            Log.warn("state reset to version " .. State.VERSION .. "; the saved one was version " .. tostring(state.version))
        end
        ModData.remove(State.NAME)
        ModData.remove(State.LEDGER)
        ModData.create(State.NAME).version = State.VERSION
    end
    Schedule.prepare(ModData.getOrCreate(State.LEDGER))
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
