if isClient() then return end

local Log = require "Crepuscular/Log"

-- The sky colour, fog and darkness of the definition in effect, as the climate's modded values. Only the server
-- and single player set them: a player's game takes the server's values from its climate packets,
-- which overwrite anything set there.
local Visuals = {}

-- Definition keys and the ids of the climate values they set (ClimateManager.FLOAT_* and COLOR_*).
local FLOATS = { desat = 0, dark = 2, fog = 5, ambient = 9 }
local COLORS = { sky = 0, fogcolor = 1 }
Visuals.KEYS = { "sky", "fogcolor", "fog", "desat", "dark", "ambient" }

-- key -> the value this game set, absent while the game's own applies. The game neither saves modded
-- values nor keeps them across a load, so starting empty sets everything wanted at the first tick.
local written = {}
-- The fog colour from before it was set: the game sets it once and never again.
local fogBase = nil

local HEX = {}
for i = 0, 15 do
    HEX[string.sub("0123456789abcdef", i + 1, i + 1)] = i
end

-- The i-th two-digit channel of hex text, from 0 to 1.
local function channel(text, i)
    local at = i * 2 - 1
    return (HEX[string.sub(text, at, at)] * 16 + HEX[string.sub(text, at + 1, at + 1)]) / 255
end

-- rrggbbaa. The game draws only the exterior; the interior matches in case a later build draws it.
local function colorInfo(text)
    local r, g, b, a = channel(text, 1), channel(text, 2), channel(text, 3), channel(text, 4)
    local info = ClimateColorInfo.new()
    info:setExterior(r, g, b, a)
    info:setInterior(r, g, b, a)
    return info
end

local function climateValue(manager, key)
    if FLOATS[key] ~= nil then
        return manager:getClimateFloat(FLOATS[key])
    end
    return manager:getClimateColor(COLORS[key])
end

local function write(manager, key, value)
    local target = climateValue(manager, key)
    if value == nil then
        target:setEnableModded(false)
        if key == "fogcolor" then
            target:getInternalValue():setTo(fogBase)
            fogBase = nil
        end
        return
    end
    if key == "sky" then
        target:setModdedValue(colorInfo(value))
    elseif key == "fogcolor" then
        if fogBase == nil then
            fogBase = ClimateColorInfo.new()
            fogBase:setTo(target:getInternalValue())
        end
        target:setModdedValue(colorInfo(value .. "ff"))
    else
        target:setModdedValue(value)
    end
    -- Absolute values: a partial blend compounds frame by frame in single player but reaches players'
    -- games as a single step.
    target:setModdedInterpolate(1)
    target:setEnableModded(true)
end

local function shown(value)
    if type(value) == "number" then
        return string.format("%.3g", value)
    end
    return value
end

-- wanted: key -> value of the definition in effect, described by label. Changes only what differs
-- from what this game set, and turns off only values it turned on.
function Visuals.sync(wanted, label)
    -- Asked each time: loading a world replaces the climate manager after this file has run.
    local manager = getClimateManager()
    local changed = {}
    for _, key in ipairs(Visuals.KEYS) do
        local value = wanted[key]
        if value ~= written[key] then
            write(manager, key, value)
            written[key] = value
            local text = "the game's own"
            if value ~= nil then
                text = shown(value)
            end
            changed[#changed + 1] = key .. " " .. text
        end
    end
    if #changed > 0 then
        Log.info("visuals for " .. label .. ": " .. table.concat(changed, ", "))
    end
end

function Visuals.status()
    local manager = getClimateManager()
    local set, admin = {}, {}
    for _, key in ipairs(Visuals.KEYS) do
        if written[key] ~= nil then
            set[#set + 1] = key .. " " .. shown(written[key])
            if climateValue(manager, key):isEnableAdmin() then
                admin[#admin + 1] = key
            end
        end
    end
    if #set == 0 then
        return "visuals: the game's own"
    end
    local line = "visuals: " .. table.concat(set, ", ")
    if #admin > 0 then
        line = line .. "; an admin climate override wins for " .. table.concat(admin, ", ")
    end
    return line
end

return Visuals
