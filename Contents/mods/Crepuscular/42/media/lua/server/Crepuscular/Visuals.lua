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

-- key -> the value this game set, absent while the game's or another mod's applies. The game neither saves
-- modded values nor keeps them across a load, so starting empty sets everything wanted at the first tick.
local written = {}
-- The game's fog colour at the first sync of a load, nil if another mod had set one by then. The game sets it
-- once and never again, so turning a modded colour off leaves the last one shown in place.
local fogBase = nil
local started = false

local HEX = {}
for i = 0, 15 do
    HEX[string.sub("0123456789abcdef", i + 1, i + 1)] = i
end

-- The i-th two-digit channel of hex text, from 0 to 1.
local function channel(text, i)
    local at = i * 2 - 1
    return (HEX[string.sub(text, at, at)] * 16 + HEX[string.sub(text, at + 1, at + 1)]) / 255
end

-- rrggbbaa, outside and inside alike.
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

-- What setModdedValue takes for a key's value.
local function moddedOf(key, value)
    if key == "sky" then
        return colorInfo(value)
    elseif key == "fogcolor" then
        return colorInfo(value .. "ff")
    end
    return value
end

-- The game keeps and blends floats, so a value read back differs from the one written in its last digits.
local function near(a, b)
    return math.abs(a - b) < 1e-6
end

local function sameColor(a, b)
    return near(a:getR(), b:getR()) and near(a:getG(), b:getG()) and near(a:getB(), b:getB())
        and near(a:getAlphaFloat(), b:getAlphaFloat())
end

local function sameInfo(a, b)
    return sameColor(a:getExterior(), b:getExterior()) and sameColor(a:getInterior(), b:getInterior())
end

-- Whether got, a climate number or ClimateColorInfo, is the key's value as this game set it.
local function holds(key, got, value)
    if FLOATS[key] ~= nil then
        return near(got, value)
    end
    return sameInfo(got, moddedOf(key, value))
end

-- Sets the key's value, or turns it off for nil. Returns false, writing nothing, when another mod's value has
-- replaced the one to turn off.
local function write(manager, key, value)
    local target = climateValue(manager, key)
    if value == nil then
        -- The game can't be asked whether modded is on; turning off one another mod turned off changes nothing.
        if not holds(key, target:getModdedValue(), written[key]) then
            return false
        end
        target:setEnableModded(false)
        if key == "fogcolor" and fogBase ~= nil then
            target:getInternalValue():setTo(fogBase)
        end
        return true
    end
    target:setModdedValue(moddedOf(key, value))
    -- Absolute values: a partial blend compounds frame by frame in single player but reaches players'
    -- games as a single step.
    target:setModdedInterpolate(1)
    target:setEnableModded(true)
    return true
end

local function shown(value)
    if type(value) == "number" then
        return string.format("%.6g", value)
    end
    return value
end

-- wanted: key -> value of the definition in effect, described by label. Changes only what differs
-- from what this game set, and turns off only values still its own.
function Visuals.sync(wanted, label)
    -- Asked each time: loading a world replaces the climate manager after this file has run.
    local manager = getClimateManager()
    if not started then
        started = true
        local fog = manager:getClimateColor(COLORS.fogcolor)
        -- No mod has set a modded value while it is still the one the game starts with.
        if sameInfo(fog:getModdedValue(), ClimateColorInfo.new()) then
            fogBase = ClimateColorInfo.new()
            fogBase:setTo(fog:getInternalValue())
        end
    end
    local changed, wrote = {}, false
    for _, key in ipairs(Visuals.KEYS) do
        local value = wanted[key]
        if value ~= written[key] then
            local text = "the game's own"
            if value ~= nil then
                text = shown(value)
            end
            if write(manager, key, value) then
                wrote = true
            else
                text = "left to another mod"
            end
            written[key] = value
            changed[#changed + 1] = key .. " " .. text
        end
    end
    if wrote then
        -- Sent to players at the next climate tick instead of the next whole ten minutes.
        manager:updateEveryTenMins()
    end
    if #changed > 0 then
        Log.info("visuals for " .. label .. ": " .. table.concat(changed, ", "))
    end
end

local function note(line, keys, text)
    if #keys == 0 then
        return line
    end
    return line .. "; " .. text .. table.concat(keys, ", ")
end

function Visuals.status()
    local manager = getClimateManager()
    local set, admin, replaced, off = {}, {}, {}, {}
    for _, key in ipairs(Visuals.KEYS) do
        local value = written[key]
        if value ~= nil then
            set[#set + 1] = key .. " " .. shown(value)
            local target = climateValue(manager, key)
            if target:isEnableAdmin() then
                admin[#admin + 1] = key
            elseif not holds(key, target:getModdedValue(), value) then
                replaced[#replaced + 1] = key
            elseif not holds(key, target:getInternalValue(), value) then
                -- Each update blends a modded value that is on into the game's own.
                off[#off + 1] = key
            end
        end
    end
    if #set == 0 then
        return "visuals: the game's own"
    end
    local line = note("visuals: " .. table.concat(set, ", "), admin, "an admin climate override wins for ")
    return note(note(line, replaced, "another mod's value wins for "), off, "another mod turned off ")
end

return Visuals
