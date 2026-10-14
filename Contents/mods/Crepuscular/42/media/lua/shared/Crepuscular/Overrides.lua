local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"

local Overrides = {}

local LISTS = { "DayOverrides", "NightOverrides", "BloodMoonOverrides" }

-- Later lists win.
local PHASE_LISTS = {
    day = { "DayOverrides" },
    night = { "NightOverrides" },
    bloodmoon = { "NightOverrides", "BloodMoonOverrides" },
}

local function trim(text)
    return string.match(text, "^%s*(.-)%s*$")
end

local function finite(n)
    return n ~= nil and n == n and n ~= math.huge and n ~= -math.huge
end

local function numeric(kind)
    return kind == "integer" or kind == "enum" or kind == "double"
end

-- The value as the option's own type, or nil if the option can't hold it. Checked here so that a
-- bad value shows up at once, not only when its phase comes.
local function convert(option, text)
    local kind = option:getType()
    if kind == "boolean" then
        local lower = string.lower(text)
        if lower == "true" then
            return true
        elseif lower == "false" then
            return false
        end
        return nil
    elseif numeric(kind) then
        local n = tonumber(text)
        if not finite(n) or n < option:getMin() or n > option:getMax() then
            return nil
        end
        if kind ~= "double" and n ~= math.floor(n) then
            return nil
        end
        return n
    end
    return text
end

local function describe(option)
    local kind = option:getType()
    if numeric(kind) then
        return kind .. " from " .. tostring(option:getMin()) .. " to " .. tostring(option:getMax())
    end
    return kind
end

local function skip(problems, list, name, reason)
    problems[name] = reason
    Log.warnOnce(list .. " " .. name .. " " .. reason, list .. ": skipped " .. name .. ", " .. reason)
end

local function parse(list, problems)
    local entries = {}
    for entry in string.gmatch(Settings.overrides(list), "[^;]+") do
        entry = trim(entry)
        if entry ~= "" then
            local name, text = string.match(entry, "^([^=]-)%s*=%s*(.-)$")
            if name == nil or name == "" then
                skip(problems, list, entry, "not Table.Option=value")
            else
                entries[name] = text
            end
        end
    end
    return entries
end

-- Reads the three lists. Returns the set of option names they validly mention, and for each
-- list the typed value per name. Invalid entries are left out and recorded in problems.
function Overrides.read(problems)
    local names, lists = {}, {}
    for _, list in ipairs(LISTS) do
        local values = {}
        for name, text in pairs(parse(list, problems)) do
            local option = getSandboxOptions():getOptionByName(name)
            if option == nil then
                skip(problems, list, name, "no such sandbox option")
            elseif string.sub(name, 1, 12) == "Crepuscular." then
                skip(problems, list, name, "Crepuscular's own options can't change by phase")
            else
                local value = convert(option, text)
                if value == nil then
                    skip(problems, list, name, "'" .. text .. "' is not a valid " .. describe(option))
                else
                    names[name] = true
                    values[name] = value
                end
            end
        end
        lists[list] = values
    end
    return names, lists
end

function Overrides.forPhase(phase, lists)
    local wanted = {}
    for _, list in ipairs(PHASE_LISTS[phase]) do
        for name, value in pairs(lists[list]) do
            wanted[name] = value
        end
    end
    return wanted
end

function Overrides.current(name)
    return getSandboxOptions():getOptionByName(name):getValueAsObject()
end

-- Sets an existing option in Java, which the game reads, and mirrors it into SandboxVars, which
-- Lua reads. Returns false when the option refused the value and kept its old one.
function Overrides.apply(name, value)
    local option = getSandboxOptions():getOptionByName(name)
    if option:getValueAsObject() == value then
        return true
    end
    getSandboxOptions():set(name, value)
    option:toTable(SandboxVars)
    return option:getValueAsObject() == value
end

-- Client side: takes the server's values.
function Overrides.applyAll(values)
    for name, value in pairs(values) do
        if getSandboxOptions():getOptionByName(name) == nil then
            Log.warnOnce("unknown " .. name, "the server changes sandbox option " .. name .. ", which this game doesn't have")
        elseif Overrides.current(name) ~= value then
            if Overrides.apply(name, value) then
                Log.info(name .. " = " .. tostring(value))
            else
                Log.warnOnce("refused " .. name .. "=" .. tostring(value), "this game refused " .. name .. " = " .. tostring(value))
            end
        end
    end
end

return Overrides
