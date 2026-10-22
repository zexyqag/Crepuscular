if isClient() then return end

local Log = require "Crepuscular/Log"
local Overrides = require "Crepuscular/Overrides"

-- Base values live in the server-only global ModData table CrepuscularBase:
-- { [option name] = { base = value, applied = value while an override is in force } }.
-- The game saves the sandbox options with the world, so a save made while a definition applies
-- would otherwise keep its values for good.
local Sandbox = {}

Sandbox.STORE = "CrepuscularBase"

-- Values the game refused at the last sync, name -> reason, for the status report.
Sandbox.problems = {}

-- name -> value the option refused; not tried again until another value is wanted.
local refused = {}

local function exists(name)
    return getSandboxOptions():getOptionByName(name) ~= nil
end

-- Returns true if the value changed.
local function restoreBase(name, entry)
    if Overrides.current(name) == entry.base then
        return false
    end
    Overrides.apply(name, entry.base)
    Log.info(name .. " back to its base value " .. tostring(entry.base))
    return true
end

-- names: every option any definition sets; wanted: name -> value for the definition in effect,
-- described by label. Returns the current value of each option it tracks or just released, and
-- whether any value changed.
-- After a load, an option still at its stored applied value was saved while a definition applied
-- and gets its base back when that ends; any other value was changed while the game was stopped,
-- for example in the server's sandbox file, and becomes the base.
function Sandbox.sync(names, wanted, label)
    local problems = {}
    local store = ModData.getOrCreate(Sandbox.STORE)
    local values, changed = {}, false

    local dropped = {}
    for name in pairs(store) do
        if not names[name] then
            dropped[#dropped + 1] = name
        end
    end
    for _, name in ipairs(dropped) do
        local entry = store[name]
        store[name] = nil
        if entry.applied ~= nil and exists(name) then
            changed = restoreBase(name, entry) or changed
            values[name] = entry.base
        end
    end

    for name in pairs(names) do
        local live = Overrides.current(name)
        local entry = store[name]
        if entry == nil then
            entry = { base = live }
            store[name] = entry
        elseif entry.applied == nil or live ~= entry.applied then
            -- Not a value we set: the base itself, or a change made by someone else.
            entry.base = live
            entry.applied = nil
        end

        local value = wanted[name]
        if value ~= nil and refused[name] == value then
            problems[name] = "the option refuses " .. tostring(value)
            value = nil
        end
        if value ~= nil and live ~= value then
            if Overrides.apply(name, value) then
                changed = true
                Log.info(name .. " = " .. tostring(value) .. " for " .. label)
            else
                refused[name] = value
                problems[name] = "the option refuses " .. tostring(value)
                Log.warn(name .. " refuses " .. tostring(value) .. "; skipped")
                value = nil
            end
        end

        if value ~= nil then
            entry.applied = value
        elseif entry.applied ~= nil then
            changed = restoreBase(name, entry) or changed
            entry.applied = nil
        end
        values[name] = Overrides.current(name)
    end

    Sandbox.problems = problems
    return values, changed
end

-- The option's value outside the definitions: the base Crepuscular keeps while it tracks the option, or
-- its value while it doesn't.
function Sandbox.base(name)
    local entry = ModData.getOrCreate(Sandbox.STORE)[name]
    if entry ~= nil then
        return entry.base
    end
    return Overrides.current(name)
end

-- The value Crepuscular last gave the option, which a server's own sandbox file may have replaced at a
-- restart, or its value while Crepuscular gives it none.
function Sandbox.applied(name)
    local entry = ModData.getOrCreate(Sandbox.STORE)[name]
    if entry ~= nil and entry.applied ~= nil then
        return entry.applied
    end
    return Overrides.current(name)
end

return Sandbox
