if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Phase = require "Crepuscular/Phase"
local State = require "Crepuscular/State"
local Sandbox = require "Crepuscular/Sandbox"
local Clock = require "Crepuscular/Clock"

local Commands = {}

local FORCE = { auto = true, day = true, night = true, bloodmoon = true }

local function status()
    local state = ModData.get(State.NAME)
    local bloodMoon = state.bloodMoon
    local now = Phase.now()
    local open, start = Phase.window(now)
    local lines = {}

    local window = "closed"
    if open then
        window = "open since the night of " .. Phase.key(start)
    end
    lines[#lines + 1] = "phase " .. state.phase .. (Clock.forced and " (forced)" or "")
        .. "; night mode " .. Settings.nightMode() .. ", night window " .. window
    lines[#lines + 1] = "moon phase today " .. Phase.moon(now.year, now.month, now.day)
        .. " (the game shows " .. getClimateMoon():getCurrentMoonPhase() .. "), 4 is full"

    local up = "not up"
    if bloodMoon.active then
        up = "up for the night of " .. bloodMoon.night
    end
    local last = "never"
    if bloodMoon.lastRollAt ~= nil then
        last = string.format("%.1f days ago", (now.hours - bloodMoon.lastRollAt) / 24)
    end
    lines[#lines + 1] = "blood moon " .. up .. "; chance " .. Settings.bloodMoonChance() .. "%, last roll " .. last
        .. ", last night decided " .. tostring(bloodMoon.decided)

    local overridden = 0
    for name, entry in pairs(ModData.getOrCreate(Sandbox.STORE)) do
        if entry.applied ~= nil then
            overridden = overridden + 1
            lines[#lines + 1] = "override " .. name .. " = " .. tostring(entry.applied) .. " (base " .. tostring(entry.base) .. ")"
        end
    end
    local skipped = 0
    for name, reason in pairs(Sandbox.problems) do
        skipped = skipped + 1
        lines[#lines + 1] = "skipped " .. name .. ": " .. reason
    end
    return {
        text = "IGUI_Crepuscular_Status",
        args = { "IGUI_Crepuscular_Phase_" .. state.phase, overridden, skipped },
        lines = lines,
    }
end

-- Returns the reply for the player's screen: a translation key, its arguments (strings in it are
-- translation keys too) and, for the status, lines for the log. nil for an unknown command.
function Commands.run(args)
    if args.command == "status" then
        return status()
    elseif args.command == "force" and FORCE[args.phase] then
        if args.phase == "auto" then
            Clock.force(nil)
        else
            Clock.force(args.phase)
        end
        return { text = "IGUI_Crepuscular_Forced", args = { "IGUI_Crepuscular_Phase_" .. args.phase } }
    elseif args.command == "roll" then
        return { text = "IGUI_Crepuscular_Roll_" .. Clock.rollNow() }
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
