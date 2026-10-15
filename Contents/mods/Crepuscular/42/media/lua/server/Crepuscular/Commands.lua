if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Phase = require "Crepuscular/Phase"
local State = require "Crepuscular/State"
local Defs = require "Crepuscular/Defs"
local Sandbox = require "Crepuscular/Sandbox"
local Kinds = require "Crepuscular/Kinds"
local Clock = require "Crepuscular/Clock"
local Despawn = require "Crepuscular/Despawn"
local Mutants = require "Crepuscular/Mutants"
local CryOfFear = require "Crepuscular/CryOfFear"
local Zombies = require "Crepuscular/Zombies"

local Commands = {}

local FORCE = { auto = true, day = true, night = true }

local function sorted(set)
    local list = {}
    for k in pairs(set) do
        list[#list + 1] = k
    end
    table.sort(list)
    return list
end

local function translated(key)
    return { key = key }
end

local function status()
    local state = ModData.get(State.NAME)
    local ledger = ModData.get(State.LEDGER)
    local rule = Clock.rule()
    local defs = Clock.definitions(rule)
    local now = Clock.now()
    local lines = {}
    local function add(line)
        lines[#lines + 1] = line
    end
    local function stamp(hours)
        return Phase.stamp(now, hours)
    end

    local clock = "seasonal night"
    if rule.mode == 1 then
        clock = string.format("fixed hours, night %02d:00-%02d:00", rule.start, rule.finish)
    end
    add("Crepuscular " .. getModInfoByID("Crepuscular"):getModVersion() .. "; " .. clock)

    local occasion = ledger.occasion
    add("phase " .. state.phase .. (state.forced and " (forced)" or "") .. "; the clock is in the "
        .. occasion.phase .. " of " .. occasion.key .. ", opened " .. stamp(occasion.start))
    add("moon phase today " .. Phase.moon(now.year, now.month, now.day) .. " (the game shows "
        .. getClimateMoon():getCurrentMoonPhase() .. "), 4 is full")
    for _, track in ipairs({ "sun", "moon" }) do
        local pool = ledger.pool[track]
        local line = track .. ": "
        if pool == nil then
            line = line .. "nothing decided yet"
        else
            line = line .. "last decided " .. pool.key
            if pool.covered ~= nil then
                line = line .. ", covered by " .. pool.covered
            elseif #pool.ids > 0 then
                line = line .. ", candidates " .. table.concat(pool.ids, ", ")
            end
        end
        add(line)
    end

    local current = ledger.current
    if current == nil then
        add("event: none")
    elseif not current.running then
        add("event " .. current.id .. " (" .. current.track .. ") waits for " .. stamp(current.at))
    else
        local line = "event " .. current.id .. " (" .. current.track .. ") since " .. stamp(current.startsAt)
        if current.endsAt ~= nil then
            line = line .. ", until " .. stamp(current.endsAt)
        else
            line = line .. ", for " .. current.phasesLeft .. " more phase changes"
        end
        add(line)
    end

    add("definitions: " .. #defs.events .. " events loaded (" .. table.concat(defs.ids, ", ") .. "), "
        .. defs.failed .. " definitions with errors")
    for _, text in ipairs(defs.errors) do
        add("error: " .. text)
    end
    for _, text in ipairs(defs.warnings) do
        add("warning: " .. text)
    end
    for _, id in ipairs(sorted(ledger.count)) do
        add("count " .. id .. ": " .. ledger.count[id])
    end
    for _, id in ipairs(sorted(ledger.lastStart)) do
        local line = "last start " .. id .. ": " .. stamp(ledger.lastStart[id])
        local ev = defs.byId[id]
        if ev ~= nil and ev.cooldown ~= nil then
            line = line .. ", cooldown until " .. stamp(ledger.lastStart[id] + ev.cooldown)
        end
        add(line)
    end
    for _, id in ipairs(sorted(ledger.follow)) do
        add("chain flag " .. id .. ": " .. table.concat(sorted(ledger.follow[id]), ", "))
    end
    local kinds = {}
    for _, kind in ipairs(Kinds.list()) do
        local source = kind.source
        if kind.hidden then
            source = source .. ", replaced by the Kinds option"
        end
        kinds[#kinds + 1] = kind.name .. " (" .. source .. ")"
    end
    add("kinds: " .. table.concat(kinds, ", "))
    local off = sorted(state.effects.off)
    if #off == 0 then
        off = { "none" }
    end
    add("kinds off: " .. table.concat(off, ", ") .. "; far members " .. Despawn.status())
    for _, line in ipairs(Zombies.status()) do
        add(line)
    end

    local overridden = 0
    for name, entry in pairs(ModData.getOrCreate(Sandbox.STORE)) do
        if entry.applied ~= nil then
            overridden = overridden + 1
            add("override " .. name .. " = " .. tostring(entry.applied) .. " (base " .. tostring(entry.base) .. ")")
        end
    end
    for name, reason in pairs(Sandbox.problems) do
        add("refused " .. name .. ": " .. reason)
    end
    local sizes = {}
    for _, name in ipairs(Defs.OPTIONS) do
        sizes[#sizes + 1] = name .. " " .. Defs.bytes(Settings.definition(name))
    end
    add("bytes: " .. table.concat(sizes, ", ") .. "; keep each under " .. Defs.LIMIT)
    for _, line in ipairs(Mutants.status()) do
        add(line)
    end
    add(CryOfFear.status(defs.cof ~= nil, state.effects.off.cof == true))

    local event = translated("IGUI_Crepuscular_None")
    if current ~= nil then
        event = current.id
    end
    return {
        text = "IGUI_Crepuscular_Status",
        args = { translated("IGUI_Crepuscular_Phase_" .. state.phase), event, #defs.events, defs.failed, overridden },
        lines = lines,
    }
end

-- Returns the reply for the player's screen: a translation key, its arguments ({ key } entries are
-- translation keys) and, for the status, lines for the log. nil for an unknown command.
function Commands.run(args)
    local command = args.command
    if command == "status" then
        return status()
    elseif command == "force" and FORCE[args.phase] then
        if args.phase == "auto" then
            Clock.force(nil)
        else
            Clock.force(args.phase)
        end
        return { text = "IGUI_Crepuscular_Forced", args = { translated("IGUI_Crepuscular_Phase_" .. args.phase) } }
    elseif command == "start" and type(args.id) == "string" then
        if Clock.start(args.id) then
            return { text = "IGUI_Crepuscular_Started", args = { args.id } }
        end
        return { text = "IGUI_Crepuscular_Unknown", args = { args.id } }
    elseif command == "end" then
        local id = Clock.stop()
        if id == nil then
            return { text = "IGUI_Crepuscular_NoEvent" }
        end
        return { text = "IGUI_Crepuscular_Ended", args = { id } }
    elseif command == "redecide" then
        local result = Clock.redecide()
        if result == "running" then
            return { text = "IGUI_Crepuscular_Running" }
        end
        return { text = "IGUI_Crepuscular_Redecided", args = { result or translated("IGUI_Crepuscular_None") } }
    end
    return nil
end

local function allowed(player)
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability.SandboxOptions)
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= State.MODULE or command ~= "admin" or type(args) ~= "table" then
        return
    end
    local reply
    if allowed(player) then
        reply = Commands.run(args)
        if reply == nil then
            Log.warn(player:getUsername() .. " sent an unknown admin command")
            return
        end
        for _, line in ipairs(reply.lines or {}) do
            print("[Crepuscular] " .. line)
        end
    else
        Log.warn(player:getUsername() .. " sent an admin command without the sandbox options capability")
        reply = { text = "IGUI_Crepuscular_Denied" }
    end
    reply.player = args.player
    sendServerCommand(player, State.MODULE, "reply", reply)
end)

-- Single player has no server to send to: the admin menu calls run() directly.
State.commands = Commands

return Commands
