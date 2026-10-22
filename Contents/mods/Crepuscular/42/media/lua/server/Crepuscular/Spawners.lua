if isClient() then return end

local Log = require "Crepuscular/Log"
local Kinds = require "Crepuscular/Kinds"

-- Monster mods that create their monsters themselves, at homes across the map: Cry of Fear Monster
-- NPCs and Silent Hill Monster NPCs, one framework in two copies. While the definition in effect has
-- such a kind off, Clock sets the mod's spawns to None and Despawn removes far monsters.
local Spawners = {}

-- spec: kind; name, as messages call the mod; mod, its Workshop title; loaded(); off, the settings
-- that stop each of its spawns, which it reads live; host(), the table whose engine keeps its record
-- of spent homes on this side; spawns, its SandboxVars table of those settings; gates, its own
-- switches that limit when its monsters appear, each with how that meets off=.
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

    -- managed: some definition turns the kind off and the mod is loaded.
    function self.check(managed)
        if not managed then
            return
        end
        for _, gate in ipairs(spec.gates) do
            if on(gate.option) then
                Log.warnOnce(spec.kind .. " " .. gate.option, spec.name .. "'s " .. spec.spawns .. "." .. gate.option .. " is on: "
                    .. gate.against .. ". Turn it off and let off=" .. spec.kind .. " decide when its monsters roam")
            end
        end
    end

    -- off: the kind is off in the definition in effect.
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
}

return Spawners
