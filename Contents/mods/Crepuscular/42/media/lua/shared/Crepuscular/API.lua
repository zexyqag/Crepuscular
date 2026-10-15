local Log = require "Crepuscular/Log"
local State = require "Crepuscular/State"
local Kinds = require "Crepuscular/Kinds"

-- The public API for other mods, the global Crepuscular.API, on the server, in single player and
-- on players' games.
local API = { VERSION = 1 }

local EVENT = "OnCrepuscularChange"

-- AddEvent returns the event if another mod has created it already, so whichever loads first,
-- handlers added to Events.OnCrepuscularChange stay.
LuaEventManager.AddEvent(EVENT)

local function refuse(name, why)
    Log.error("registerKind " .. tostring(name) .. ": " .. why)
    return false, why
end

-- name: a-z, 0-9 and _, not none, cof, mutants or a kind of the Kinds option.
-- spec.isMember(z) -> boolean, on the server and on players' games; spec.despawn = false keeps far
-- members while the kind is off. The same name again replaces its spec.
-- Returns true, or false and why.
function API.registerKind(name, spec)
    if type(name) ~= "string" or string.find(name, "^[a-z0-9_]+$") == nil then
        return refuse(name, "the name is not made of a-z, 0-9 and _")
    end
    if name == "none" or Kinds.BUILTIN[name] then
        return refuse(name, "the name belongs to Crepuscular")
    end
    local state = State.get()
    if state ~= nil then
        for _, kind in ipairs(state.kinds) do
            if kind.name == name then
                return refuse(name, "the Kinds option has a kind with that name")
            end
        end
    end
    if type(spec) ~= "table" or type(spec.isMember) ~= "function" then
        return refuse(name, "spec.isMember is not a function")
    end
    if spec.despawn ~= nil and type(spec.despawn) ~= "boolean" then
        return refuse(name, "spec.despawn is not true or false")
    end
    Kinds.register(name, spec)
    Log.info("kind " .. name .. " registered")
    return true
end

-- Whether the kind is active in the definition in effect. Kinds no definition turns off are.
function API.isActive(name)
    local state = State.get()
    return state == nil or not state.effects.off[name]
end

-- The kind of the zombie, or nil.
function API.kindOf(z)
    return Kinds.of(z)
end

-- { phase = "day" or "night", event, track and serial of the running event or nil }.
local function current(state)
    local out = { phase = state.phase }
    local ev = state.event
    if ev ~= nil and ev.running then
        out.event, out.track, out.serial = ev.id, ev.track, ev.serial
    end
    return out
end

-- A copy of what is current, or nil while this game has no state yet.
function API.current()
    local state = State.get()
    if state == nil then
        return nil
    end
    return current(state)
end

-- What OnCrepuscularChange last reported.
local last = nil

-- Fires OnCrepuscularChange(current, previous) once the game has started and whenever the phase
-- or the running event changes after that; previous is nil the first time.
State.listen(function(state)
    if not Kinds.started() then
        return
    end
    local now = current(state)
    -- Every start of an event has its own serial.
    if last ~= nil and now.phase == last.phase and now.serial == last.serial then
        return
    end
    local previous = last
    last = now
    -- The handlers get a copy: what they do to it can't change the next comparison.
    triggerEvent(EVENT, current(state), previous)
end)

Crepuscular = Crepuscular or {}
Crepuscular.API = API

return API
