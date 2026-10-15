-- Speed tiers and health of ordinary zombies. Pure: the zombie's numbers and the game's settings
-- are passed in. Tiers are 1 sprinter, 2 fast shambler, 3 shambler, as the game numbers them.
local Phase = require "Crepuscular/Phase"

local Tuning = {}

-- Health travels to players' games as thousandths in a signed 16-bit number.
Tuning.HEALTH_LIMIT = 32.767

-- The most health a new zombie can roll, by ZombieLore.Toughness 1 to 4 (VirtualZombieManager).
local MAX_START = { 3.8, 1.8, 0.8, 3.8 }

-- The smallest prime above 2^32, so that every outfit ID has its own residue.
local PRIME = 4294967311

-- Every value below stays a whole number under 2^53, so doubles hold it exactly on every machine.
-- Kahlua's % truncates its quotient to a 32-bit integer; Phase.wrap doesn't.
local wrap = Phase.wrap

-- (a * b) mod PRIME for a below 2^33 and b below 2^32, in two halves of b.
local function mulmod(a, b)
    local high = math.floor(b / 65536)
    return wrap(wrap(a * high, PRIME) * 65536 + a * (b - high * 65536), PRIME)
end

local function mix(id, first, second)
    local x = id
    if x < 0 then
        x = x + 4294967296
    end
    -- Bit 15 is the game's fallen-hat flag, which machines set at different times in a zombie's life.
    if wrap(x, 65536) >= 32768 then
        x = x - 32768
    end
    x = mulmod(x + 1, first)
    -- Swapping the 16-bit halves only scrambles a little: neighbouring IDs still land one of a few
    -- fixed steps apart, which spreads them evenly enough over the shares.
    local high = math.floor(x / 65536)
    x = (x - high * 65536) * 65536 + high
    return mulmod(x, second)
end

-- 0 to 99 from the zombie's persistent outfit ID, which every zombie packet carries, so every
-- machine gets the same value and a reloaded zombie keeps it.
function Tuning.hash(id)
    return wrap(mix(id, 2654435761, 2246822519), 100)
end

-- 0 to 199 from the same ID by a second, unrelated hash, for Tuning.base.
function Tuning.roll(id)
    return wrap(mix(id, 3266489917, 668265263), 200)
end

-- The tier the game's ZombieLore.Speed gives: 1 to 3 as they are; 4 (random) as the game rolls it,
-- percent sprinters and the rest split evenly, but fixed per zombie by its roll.
function Tuning.base(roll, speed, percent)
    if speed ~= 4 then
        return speed
    end
    if math.floor(roll / 2) < percent then
        return 1
    end
    return 2 + wrap(roll, 2)
end

-- Whether some definition's speed reaches a zombie with hash h: fmax is the largest +N, smax the
-- largest -N. Zombies sped up are the last to be slowed down.
function Tuning.managed(h, fmax, smax)
    return h < fmax or h >= 100 - smax
end

-- The tier for speed=+N or -N (0 for none) and steps.
function Tuning.target(h, base, speed, steps)
    if speed > 0 and h < speed then
        return math.max(1, base - steps)
    end
    if speed < 0 and h >= 100 + speed then
        return math.min(3, base + steps)
    end
    return base
end

-- The tier of a walk type, as the game reads it: sprint1-5, slow1-3, anything else fast shambler.
function Tuning.tier(walkType)
    if walkType == nil then
        return 2
    end
    if string.sub(walkType, 1, 6) == "sprint" then
        return 1
    end
    if string.sub(walkType, 1, 4) == "slow" then
        return 3
    end
    return 2
end

-- The most health any zombie may have under health factor f at that Toughness, or nil when f
-- caps nothing. Always above 0: 0 health in an owner's packet kills the zombie.
function Tuning.cap(f, toughness)
    if f >= 1 then
        return nil
    end
    return f * MAX_START[toughness]
end

-- The game keeps health as a float, whose 24 bits can read back a capped value a little above the
-- cap; this margin is twice that.
local FLOAT = 1 + 1 / 4194304

-- Whether health is above the cap by more than the float could miss it.
function Tuning.above(health, cap)
    return health > cap * FLOAT
end

-- The health of a new zombie that rolled health, under factor f.
function Tuning.created(health, f)
    if f < 1 then
        return health * f
    end
    if f > 1 and health < Tuning.HEALTH_LIMIT then
        return math.min(health * f, Tuning.HEALTH_LIMIT)
    end
    return health
end

return Tuning
