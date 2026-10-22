if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Overrides = require "Crepuscular/Overrides"
local Sandbox = require "Crepuscular/Sandbox"
local Kinds = require "Crepuscular/Kinds"

-- Monster mods that create their monsters themselves, by settings they read live. Each entry: kind;
-- name, as messages call the mod; mod, its Workshop title; loaded(); OFF, the settings that stop its new
-- monsters, which Clock writes while the definition in effect has the kind off; refill(), when the kind
-- is on again; follow(night, hour), the settings that put its own clock on Crepuscular's, which Clock
-- writes whatever the kind; check(defs), its warnings, each minute; status(managed, off).
local Spawners = {}

local EMPTY = {}

-- Cry of Fear Monster NPCs and Silent Hill Monster NPCs, one framework in two copies: monsters at homes
-- across the map. While the kind is off their spawns are None and Despawn removes far monsters.
-- spec: kind, name, mod, loaded, off; host(), the table whose engine keeps its record of spent homes on
-- this side; spawns, its SandboxVars table of those settings; gates, its own switches that limit when
-- its monsters appear, each with how that meets off=.
local function adapter(spec)
    local self = { kind = spec.kind, name = spec.name, mod = spec.mod, loaded = spec.loaded, OFF = spec.off }

    local function on(option)
        local vars = SandboxVars[spec.spawns]
        return vars ~= nil and vars[option] == true
    end

    -- The mod marks a home spent when it fills it, and with its NightOnly off frees it again only
    -- RespawnHours after that or after a kill, so monsters removed while the kind was off wouldn't
    -- come back. When it is on again every home may be filled again, as NightOnly does at dusk. Its
    -- levels coming back change its settings revision, which makes it look for the homes around
    -- players anew.
    function self.refill()
        local host = spec.host()
        local saved = nil
        if type(host) == "table" and type(host.engine) == "table" and type(host.engine.saved) == "function" then
            saved = host.engine.saved()
        end
        if type(saved) ~= "table" or type(saved.done) ~= "table" then
            Log.warnOnce(spec.kind .. " refill", spec.name .. " has no spent-home record Crepuscular knows, so its monsters"
                .. " removed while " .. spec.kind .. " was off come back only after its RespawnHours")
            return
        end
        saved.done = {}
        Log.info(spec.name .. ": " .. spec.kind .. " is on again, so every home may be filled again")
    end

    -- Its night-only option is a clock of its own, which the gates warn about instead.
    function self.follow()
        return EMPTY
    end

    -- Only while some definition turns the kind off and the mod is loaded.
    function self.check(defs)
        if defs.spawners[spec.kind] == nil then
            return
        end
        for _, gate in ipairs(spec.gates) do
            if on(gate.option) then
                Log.warnOnce(spec.kind .. " " .. gate.option, spec.name .. "'s " .. spec.spawns .. "." .. gate.option .. " is on: "
                    .. gate.against .. ". Turn it off and let off=" .. spec.kind .. " decide when its monsters roam")
            end
        end
    end

    -- managed: some definition turns the kind off and the mod is loaded; off: the kind is off in the
    -- definition in effect.
    function self.status(managed, off)
        if not spec.loaded() then
            return spec.name .. ": not loaded"
        end
        local line = spec.name .. ": loaded; "
        if not managed then
            line = line .. "no definition turns " .. spec.kind .. " off, so its spawns are its own"
        elseif off then
            line = line .. spec.kind .. " is off now, its spawns set to None"
        else
            line = line .. spec.kind .. " is on now"
        end
        local gates = {}
        for _, gate in ipairs(spec.gates) do
            local state = "off"
            if on(gate.option) then
                state = "on"
            end
            gates[#gates + 1] = "its " .. gate.option .. " is " .. state
        end
        return line .. "; " .. table.concat(gates, ", ")
    end

    return self
end

local START = "BlackoutPredators.NightStartHour"
local FINISH = "BlackoutPredators.DayStartHour"

-- Whether Blackout Predators' night takes in the hour (its BP.IsNight): equal hours are never its night.
local function covers(start, finish, hour)
    if start > finish then
        return hour >= start or hour < finish
    end
    return hour >= start and hour < finish
end

local function exists(name)
    return getSandboxOptions():getOptionByName(name) ~= nil
end

-- Blackout Predators: Volatiles that sleep in fixed nests by day, hunt at its night, and at night take
-- the place of ordinary zombies far from players (its night swap). It reads its night hours live; while
-- VolatilesFollowNight is on they follow the definitions. While volatiles is off only the swap stops: no
-- Volatile is ever removed.
local function blackout()
    local self = {
        kind = "volatiles", name = "Blackout Predators", mod = "Blackout Predators", loaded = Kinds.blackoutLoaded,
        OFF = { ["BlackoutPredators.AmbientSpawnChancePercent"] = "0" },
    }

    local function following()
        return Kinds.blackoutLoaded() and Settings.volatilesFollowNight()
    end

    -- Its swap starts again by itself, and a killed nest Volatile never comes back, by its own rule.
    function self.refill()
    end

    -- night: whether the definition in effect is the Night or a moon event; hour: the hour of the day.
    -- Its night is the hours from NightStartHour to DayStartHour, and as each night starts it screams in
    -- the hour equal to NightStartHour.
    function self.follow(night, hour)
        if not following() then
            return EMPTY
        end
        if not exists(START) or not exists(FINISH) then
            Log.warnOnce("volatiles hours", "Blackout Predators has no " .. START .. " and " .. FINISH
                .. " options, so its Volatiles keep their own night")
            return EMPTY
        end
        local start, finish = Sandbox.applied(START), Sandbox.applied(FINISH)
        local after = (hour + 1) % 24
        if night then
            -- Its start stays put all night, so the scream comes once, at dusk; a night that would run
            -- past its 23 hours moves it to an hour already past.
            if not covers(start, finish, hour) then
                start = hour
            elseif not covers(start, finish, after) then
                start = (hour + 23) % 24
            end
            return { [START] = start, [FINISH] = (start + 23) % 24 }
        end
        -- Equal hours are never its night, but it screams in that hour all the same, so it is one not
        -- coming up.
        if start ~= finish or start == hour or start == after then
            start = (hour + 23) % 24
        end
        return { [START] = start, [FINISH] = start }
    end

    function self.check(defs)
        if not following() or not exists(START) or not exists(FINISH) then
            return
        end
        local start, finish = Sandbox.base(START), Sandbox.base(FINISH)
        local options = getSandboxOptions()
        local ownStart = options:getOptionByName(START):getDefaultValue()
        local ownFinish = options:getOptionByName(FINISH):getDefaultValue()
        if start ~= ownStart or finish ~= ownFinish then
            Log.warnOnce("volatiles pinned " .. start .. " " .. finish, "Blackout Predators' night hours are " .. start .. " and "
                .. finish .. " in the sandbox options (its own are " .. ownStart .. " and " .. ownFinish .. "), but"
                .. " VolatilesFollowNight is on, so Crepuscular sets them by its own night. Turn VolatilesFollowNight off to keep them")
        end
        local all = { defs.day, defs.night }
        for _, ev in ipairs(defs.events) do
            all[#all + 1] = ev
        end
        for _, def in ipairs(all) do
            for _, name in ipairs({ START, FINISH }) do
                if def.values[name] ~= nil then
                    Log.warnOnce("volatiles set " .. def.label .. " " .. name, def.label .. ": set." .. name .. " does nothing while"
                        .. " VolatilesFollowNight is on: Crepuscular sets Blackout Predators' night hours by its own night")
                end
            end
        end
    end

    function self.status(managed, off)
        if not Kinds.blackoutLoaded() then
            return self.name .. ": not loaded"
        end
        local line = self.name .. ": loaded; "
        if Kinds.volatileOutfit() == nil then
            line = self.name .. ": loaded without BlackoutPredators.Outfit, so volatiles has no members; "
        end
        if not managed then
            line = line .. "no definition turns volatiles off, so its night swap is its own"
        elseif off then
            line = line .. "volatiles is off now, its night swap set to 0"
        else
            line = line .. "volatiles is on now"
        end
        if not exists(START) or not exists(FINISH) then
            return line .. "; it has no " .. START .. " and " .. FINISH .. " options"
        end
        local hours = "its own hours decide, VolatilesFollowNight is off"
        if Settings.volatilesFollowNight() then
            hours = "its hours follow Crepuscular's night"
        end
        local start, finish = Overrides.current(START), Overrides.current(FINISH)
        local now = "day"
        if covers(start, finish, getGameTime():getHour()) then
            now = "night"
        end
        return line .. "; " .. hours .. ": NightStartHour " .. start .. ", DayStartHour " .. finish .. ", its " .. now .. " now"
    end

    return self
end

local NIGHT_ONLY = "its own 20:00-04:00 night fights the definitions that turn "

Spawners.LIST = {
    adapter({
        kind = "cof",
        name = "Cry of Fear",
        mod = "Cry of Fear Monster NPCs",
        loaded = Kinds.cryOfFearLoaded,
        -- The levels of the regular and special monsters' homes (1 is None), the Human Flowers and the
        -- Sawrunner's night encounters.
        off = {
            ["COF_Spawns.Regular"] = "1",
            ["COF_Spawns.Sawcrazy"] = "1",
            ["COF_Spawns.Sawrunner"] = "1",
            ["COF_Spawns.Stranger"] = "1",
            ["COF_Spawns.Drowned"] = "1",
            ["COF_Spawns.HumanFlowers"] = "false",
            ["COF_Sawrunner.NightEvent"] = "false",
        },
        host = function()
            if isServer() then
                return COF_ServerMonsters
            end
            return COF_MonsterSpawns
        end,
        spawns = "COF_Spawns",
        gates = { { option = "NightOnly", against = NIGHT_ONLY .. "cof off" } },
    }),
    adapter({
        kind = "silenthill",
        name = "Silent Hill",
        mod = "Silent Hill Monster NPCs",
        loaded = Kinds.silentHillLoaded,
        -- Its two population levels, the regular monsters' and Pyramid Head's (1 is None).
        off = {
            ["SHM_Spawns.Regular"] = "1",
            ["SHM_Spawns.PyramidHead"] = "1",
        },
        host = function()
            if isServer() then
                return SHM_ServerMonsters
            end
            return SHM_MonsterSpawns
        end,
        spawns = "SHM_Spawns",
        gates = {
            { option = "NightOnly", against = NIGHT_ONLY .. "silenthill off" },
            { option = "FogOnly", against = "its monsters then appear only in fog, also while silenthill is on" },
        },
    }),
    blackout(),
}

return Spawners
