-- The global ModData table Crepuscular: the server owns it and sends it to every client.
-- { version, phase = "day" | "night", forced,
--   event = { id, track, serial, running, startsAt, endsAt } or nil,
--   effects = { off = { [kind] = true } },
--   announce = { serial, text, color } or nil,
--   sandbox = { [option name] = current value },
--   kinds = { { name, prefixes } } from the Kinds option,
--   ids = { event ids }, errors = number of definitions with errors }
local State = {}

State.NAME = "Crepuscular"
State.VERSION = 2
State.MODULE = "Crepuscular"
-- Server only, never sent: see Schedule.
State.LEDGER = "CrepuscularLedger"

-- The state, or nil while there is none of this version yet.
function State.get()
    local state = ModData.get(State.NAME)
    if state == nil or state.version ~= State.VERSION then
        return nil
    end
    return state
end

local listeners = {}

-- Listeners get each new state: from the server code in single player and on a server, and from
-- what an MP client receives.
function State.listen(listener)
    listeners[#listeners + 1] = listener
end

function State.notify(state)
    for i = 1, #listeners do
        listeners[i](state)
    end
end

return State
