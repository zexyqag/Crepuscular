local Log = require "Crepuscular/Log"

local Overrides = {}

local function finite(n)
    return n ~= nil and n == n and n ~= math.huge and n ~= -math.huge
end

local function numeric(kind)
    return kind == "integer" or kind == "enum" or kind == "double"
end

-- The value as the option's own type, or nil if the option can't hold it. Checked here so that a
-- bad value shows up at once, not only when its definition applies.
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

-- The set. entries of a definition as typed values. Entries the game can't take are left out
-- with a warning: the option may belong to a mod that isn't loaded.
function Overrides.check(label, entries, warnings)
    local values = {}
    local names = {}
    for name in pairs(entries) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local text = entries[name]
        local option = getSandboxOptions():getOptionByName(name)
        local why = nil
        if option == nil then
            why = "no such sandbox option"
        elseif string.sub(name, 1, 12) == "Crepuscular." then
            why = "Crepuscular's own options can't be set"
        else
            local value = convert(option, text)
            if value == nil then
                why = "'" .. text .. "' is not a valid " .. describe(option)
            else
                values[name] = value
            end
        end
        if why ~= nil then
            warnings[#warnings + 1] = label .. ": set." .. name .. ": " .. why
        end
    end
    return values
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
