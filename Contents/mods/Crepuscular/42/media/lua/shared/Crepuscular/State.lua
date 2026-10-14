-- The global ModData table Crepuscular: the server owns it and sends it to every client.
-- { version, phase = "day" | "night", forced,
--   event = { id, track, serial, running, startsAt, endsAt } or nil,
--   effects = { off = { [kind] = true } },
--   announce = { serial, text, color } or nil,
--   sandbox = { [option name] = current value },
--   ids = { event ids }, errors = number of definitions with errors }
local State = {}

State.NAME = "Crepuscular"
State.VERSION = 2
State.MODULE = "Crepuscular"
-- Server only, never sent: see Schedule.
State.LEDGER = "CrepuscularLedger"

local listeners = {}

-- Single player has no network, so the server code hands the state to the client code directly;
-- an MP client hands on what it receives.
function State.listen(listener)
    listeners[#listeners + 1] = listener
end

function State.notify(state)
    for i = 1, #listeners do
        listeners[i](state)
    end
end

return State
