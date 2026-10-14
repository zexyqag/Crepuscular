-- The global ModData table Crepuscular: the server owns it and sends it to every client.
-- { version, phase = "day" | "night" | "bloodmoon",
--   bloodMoon = { active, night, id, decided, lastRollAt },
--   sandbox = { [option name] = current value } }
local State = {}

State.NAME = "Crepuscular"
State.VERSION = 1
State.MODULE = "Crepuscular"

local listeners = {}

-- Single player has no network, so the server code hands the state to the client code directly.
function State.listen(listener)
    listeners[#listeners + 1] = listener
end

function State.notify(state)
    for i = 1, #listeners do
        listeners[i](state)
    end
end

return State
