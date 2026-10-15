if isClient() then return end

local Log = require "Crepuscular/Log"
local Settings = require "Crepuscular/Settings"
local Phase = require "Crepuscular/Phase"
local State = require "Crepuscular/State"
local Kinds = require "Crepuscular/Kinds"
local Zombies = require "Crepuscular/Zombies"
local Clock = require "Crepuscular/Clock"

-- Killed zombies that get back up. At its death a zombie is marked to rise by the rise= in effect;
-- while a definition with wake=true applies, its corpse rises once due, as a corpse playing dead
-- does, so the zombie stays one of the population.
--
-- Registry: { next = the next id, low = no registered id is below it, count, entries = { [id] = {
--   x, y, z, due, died, misses, found } } }, ids given in registration order. x, y, z: the square the
--   zombie died on, or once found = true the one its corpse lies on; due and died: world-age hours;
--   misses: scans that found the square loaded but neither the corpse nor someone dragging it.
-- Marker, the modData field Crepuscular, which a corpse copies from its zombie and a zombie from the
--   corpse it rose from: { id, rises, due, died } on a registered corpse, { rises } on a risen zombie.
--   A corpse without an id never rises.
local Risers = {}

-- Scans that miss a corpse before its entry is dropped: a corpse being dragged is a zombie, not a
-- corpse, until it is put down.
local MISSES = 3
-- Tiles around, and the level below, where a zombie died that are searched for its corpse until it is
-- found: a corpse can slide or fall while the zombie dies.
local SEARCH = 3
-- Tiles a player may be from a corpse to finish it off, or from a zombie to report a head hit.
local REACH = 3
-- Milliseconds between a head-hit report and the death it belongs to, in either order.
local WINDOW = 5000

-- Since this game started, for the status.
local counts = { marked = 0, down = 0, rose = 0, gone = 0, expired = 0, dropped = 0, finished = 0 }
local last = nil

local function hours()
    return getGameTime():getWorldAgeHours()
end

local function registry()
    local reg = ModData.getOrCreate(State.RISERS)
    if reg.entries == nil then
        reg.next, reg.low, reg.count, reg.entries = 1, 1, 0, {}
    end
    return reg
end

local function remove(reg, id)
    if reg.entries[id] ~= nil then
        reg.entries[id] = nil
        reg.count = reg.count - 1
    end
end

-- Drops the oldest entries above RiserLimit.
local function trim(reg)
    local limit = Settings.riserLimit()
    while reg.count > limit and reg.low < reg.next do
        if reg.entries[reg.low] ~= nil then
            remove(reg, reg.low)
            counts.dropped = counts.dropped + 1
        end
        reg.low = reg.low + 1
    end
end

local function add(reg, id, entry)
    if reg.entries[id] == nil then
        reg.count = reg.count + 1
    end
    reg.entries[id] = entry
    reg.low = math.min(reg.low, id)
    trim(reg)
end

local function marker(o)
    if not o:hasModData() then
        return nil
    end
    local m = o:getModData().Crepuscular
    if type(m) ~= "table" then
        return nil
    end
    return m
end

local function marked(o, id)
    local m = marker(o)
    return m ~= nil and m.id == id
end

local function near(player, x, y, z)
    local dx, dy = player:getX() - x, player:getY() - y
    return dx * dx + dy * dy <= REACH * REACH and math.floor(player:getZ()) == math.floor(z)
end

local function place(x, y, z)
    return math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z)
end

-- ------------------------------------------------------------------ head hits

-- Zombie -> when a player's game reported a floor head hit on it, in milliseconds.
local reports = setmetatable({}, { __mode = "k" })
-- Online ID -> { at, x, y, z, id } of a registered zombie that just died, for a report that comes
-- after the death: the hit and the report travel in different packets.
local deaths = {}

local function headHit(z)
    local at = reports[z]
    reports[z] = nil
    return at ~= nil and getTimestampMs() - at <= WINDOW
end

local function rememberDeath(z, id, x, y, level)
    local now = getTimestampMs()
    local old = {}
    for key, death in pairs(deaths) do
        if now - death.at > WINDOW then
            old[#old + 1] = key
        end
    end
    for _, key in ipairs(old) do
        deaths[key] = nil
    end
    deaths[z:getOnlineID()] = { at = now, x = x, y = y, z = level, id = id }
end

-- ------------------------------------------------------------------ marking at death

-- Zombies whose death this life has handled: a zombie that burns to death fires the event twice.
-- The game reuses dead zombies and fires OnZombieCreate for each new life.
local handled = setmetatable({}, { __mode = "k" })

-- Why z stays down, or nil.
local function staysDown(z, m, defs)
    if Kinds.isBandit(z) then
        return "a Bandit"
    end
    local kind = Zombies.kindOf(z, Kinds.test())
    if kind ~= nil and not defs.riseKinds[kind] then
        return "of the kind " .. kind
    end
    if z:isReanimatedPlayer() and not Settings.risePlayers() then
        return "a player's zombie"
    end
    if z:isOnFire() and Settings.fireStaysDown() then
        return "it burned"
    end
    if Settings.headHitsStayDown() and headHit(z) then
        return "hit on the head on the floor"
    end
    local max = Settings.maxRises()
    if max > 0 and m ~= nil and m.rises >= max then
        return "it rose " .. m.rises .. " times"
    end
    local rise = Clock.risers.rise
    if rise <= 0 then
        return "rise 0"
    end
    if rise < 100 then
        local rolled = ZombRandFloat(0, 100)
        if rolled >= rise then
            return string.format("rolled %.1f, not below rise %d", rolled, rise)
        end
    end
    return nil
end

local function delay()
    local a, b = Settings.riseDelayMin(), Settings.riseDelayMax()
    local low, high = math.min(a, b), math.max(a, b)
    if high > low then
        return ZombRandFloat(low, high)
    end
    return low
end

-- A dragged corpse is a zombie until it is put down, and dies again then: its new corpse takes the
-- marker, and the entry moves to where it lies, made again from the marker if a scan dropped it.
local function dropped(z, m)
    if m == nil or m.id == nil then
        return
    end
    local reg = registry()
    local entry = reg.entries[m.id]
    if entry == nil then
        entry = { due = m.due, died = m.died }
        add(reg, m.id, entry)
    end
    entry.x, entry.y, entry.z = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    entry.found, entry.misses = false, 0
    Log.info("corpse " .. m.id .. " put down at " .. place(entry.x, entry.y, entry.z))
end

local function died(z)
    if handled[z] then
        return
    end
    handled[z] = true
    local m = marker(z)
    if z:isReanimatedForGrappleOnly() then
        dropped(z, m)
        return
    end
    local x, y, level = math.floor(z:getX()), math.floor(z:getY()), math.floor(z:getZ())
    local why = staysDown(z, m, Clock.definitions(Clock.rule()))
    if why ~= nil then
        if m ~= nil then
            z:getModData().Crepuscular = nil
        end
        counts.down = counts.down + 1
        Log.info("zombie killed at " .. place(x, y, level) .. " stays down: " .. why)
        return
    end
    local reg = registry()
    local id = reg.next
    reg.next = id + 1
    local now = hours()
    local due = now + delay()
    local rises = 0
    if m ~= nil then
        rises = m.rises
    end
    z:getModData().Crepuscular = { id = id, rises = rises, due = due, died = now }
    add(reg, id, { x = x, y = y, z = level, due = due, died = now, misses = 0, found = false })
    counts.marked = counts.marked + 1
    if isServer() and Settings.headHitsStayDown() then
        rememberDeath(z, id, x, y, level)
    end
    Log.info("zombie killed at " .. place(x, y, level) .. " marked to rise as corpse " .. id .. " from "
        .. Phase.stamp(Clock.now(), due))
end

-- ------------------------------------------------------------------ rising

-- The corpse marked id on the square, or nil.
local function holder(square, id)
    if square == nil then
        return nil
    end
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if marked(body, id) then
            return body
        end
    end
    return nil
end

-- Calls fn(square) for every loaded square of the search area of an entry, until fn returns a value.
local function around(cell, e, fn)
    for level = e.z, e.z - 1, -1 do
        for dx = -SEARCH, SEARCH do
            for dy = -SEARCH, SEARCH do
                local square = cell:getGridSquare(e.x + dx, e.y + dy, level)
                if square ~= nil then
                    local found = fn(square)
                    if found ~= nil then
                        return found
                    end
                end
            end
        end
    end
    return nil
end

local function find(cell, e, id)
    if e.found then
        return holder(cell:getGridSquare(e.x, e.y, e.z), id)
    end
    return around(cell, e, function(square)
        return holder(square, id)
    end)
end

local function dragged(cell, e, id)
    return around(cell, e, function(square)
        local movers = square:getMovingObjects()
        for i = 0, movers:size() - 1 do
            local o = movers:get(i)
            if instanceof(o, "IsoZombie") and o:isReanimatedForGrappleOnly() and marked(o, id) then
                return true
            end
        end
        return nil
    end) ~= nil
end

local function keepDown(reg, id, body, why)
    if body ~= nil then
        body:getModData().Crepuscular = nil
    end
    remove(reg, id)
    counts.down = counts.down + 1
    Log.info("corpse " .. id .. " stays down: " .. why)
end

local function strip(data)
    local keys = {}
    for key in pairs(data) do
        if type(key) == "string" and string.sub(key, 1, 4) == "COF_" then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do
        data[key] = nil
    end
end

-- Returns true if the corpse rose.
local function raise(reg, id, body)
    local square = body:getSquare()
    if not Settings.riseInSafehouses() and SafeHouse.getSafeHouse(square) ~= nil then
        keepDown(reg, id, body, "it lies in a safehouse")
        return false
    end
    local was = body:isFakeDead()
    body:setFakeDead(true)
    if not body:isFakeDead() then
        keepDown(reg, id, body, "it can't play dead")
        Log.warnOnce("risers can't play dead", "a corpse on stairs, and every corpse while ZombieLore.DisableFakeDead"
            .. " is 3 (never), can't play dead, so it stays down instead of rising")
        return false
    end
    local data = body:getModData()
    local m = data.Crepuscular
    data.Crepuscular = { rises = m.rises + 1 }
    -- Cry of Fear's marks of the monster that died: in single player a monster that rose with them
    -- would skip its health and die again at once.
    strip(data)
    local z = body:reanimate()
    if z == nil then
        -- The server has no free zombie ID; the corpse tries again next scan.
        data.Crepuscular = m
        body:setFakeDead(was)
        return false
    end
    Zombies.risen(z)
    remove(reg, id)
    counts.rose = counts.rose + 1
    Log.info("corpse " .. id .. " rose at " .. place(square:getX(), square:getY(), square:getZ())
        .. ", rise " .. (m.rises + 1) .. " of this body")
    return true
end

local function scan()
    local reg = registry()
    if reg.count == 0 then
        return
    end
    -- EveryTenMinutes comes before the minute's EveryOneMinute: the definition in effect is brought
    -- up to this minute first.
    Clock.tick()
    trim(reg)
    local wake = Clock.risers.wake
    local maxAge = Settings.riseMaxAgeHours()
    if not wake and maxAge == 0 then
        return
    end
    local now = hours()
    local old, due = {}, {}
    for id, e in pairs(reg.entries) do
        if maxAge > 0 and now - e.died > maxAge then
            old[#old + 1] = id
        elseif wake and e.due <= now then
            due[#due + 1] = id
        end
    end
    for _, id in ipairs(old) do
        remove(reg, id)
        counts.expired = counts.expired + 1
    end
    table.sort(due)
    local cell = getCell()
    local budget = Settings.risesPerScan()
    local result = { at = now, due = #due, rose = 0, unloaded = 0, missed = 0 }
    for _, id in ipairs(due) do
        if result.rose >= budget then
            break
        end
        local e = reg.entries[id]
        if cell:getGridSquare(e.x, e.y, e.z) == nil then
            -- Not loaded, which doesn't use up the scan.
            result.unloaded = result.unloaded + 1
        else
            local body = find(cell, e, id)
            if body ~= nil then
                local square = body:getSquare()
                e.x, e.y, e.z, e.found, e.misses = square:getX(), square:getY(), square:getZ(), true, 0
                if raise(reg, id, body) then
                    result.rose = result.rose + 1
                end
            elseif not dragged(cell, e, id) then
                result.missed = result.missed + 1
                e.misses = e.misses + 1
                if e.misses >= MISSES then
                    remove(reg, id)
                    counts.gone = counts.gone + 1
                    Log.info("corpse " .. id .. " is gone: burned, removed or carried off")
                end
            end
        end
    end
    last = result
end

Events.OnZombieCreate.Add(function(z)
    handled[z] = nil
end)
Events.OnZombieDead.Add(died)
Events.EveryTenMinutes.Add(scan)

-- ------------------------------------------------------------------ finish off and head hits

-- args: { x, y, z, ids = { object IDs of corpses on that square } }: the game's own corpse ID, which
-- every game shares, since a player's game can't read the markers. Returns how many it kept down.
function Risers.finishOff(player, args)
    if not Settings.finishOff() or type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number"
        or type(args.ids) ~= "table" then
        return 0
    end
    local square = getCell():getGridSquare(args.x, args.y, args.z)
    if square == nil or not near(player, args.x + 0.5, args.y + 0.5, args.z) then
        Log.info(player:getUsername() .. " is too far from " .. place(args.x, args.y, args.z) .. " to finish off corpses there")
        return 0
    end
    local wanted = {}
    for _, id in ipairs(args.ids) do
        wanted[id] = true
    end
    local reg = registry()
    local n = 0
    local bodies = square:getDeadBodys()
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if wanted[body:getObjectIDAsLong()] then
            local m = marker(body)
            if m ~= nil and m.id ~= nil then
                remove(reg, m.id)
            end
            if m ~= nil then
                body:getModData().Crepuscular = nil
            end
            n = n + 1
        end
    end
    counts.finished = counts.finished + n
    Log.info(player:getUsername() .. " finished off " .. n .. " corpses at " .. place(args.x, args.y, args.z))
    return n
end

-- A player's game saw its own player hit z on the head while z lay on the floor.
function Risers.headHit(player, z)
    if Settings.headHitsStayDown() and near(player, z:getX(), z:getY(), z:getZ()) then
        reports[z] = getTimestampMs()
    end
end

-- The same, from a player's game in multiplayer, by the zombie's online ID: it may have died here first.
local function headHitById(player, id)
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        if z:getOnlineID() == id and not z:isDead() then
            Risers.headHit(player, z)
            return
        end
    end
    local death = deaths[id]
    if death == nil or getTimestampMs() - death.at > WINDOW or not near(player, death.x + 0.5, death.y + 0.5, death.z)
        or not Settings.headHitsStayDown() then
        return
    end
    deaths[id] = nil
    local reg = registry()
    local e = reg.entries[death.id]
    if e ~= nil then
        keepDown(reg, death.id, find(getCell(), e, death.id), "hit on the head on the floor")
    end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= State.MODULE or type(args) ~= "table" then
        return
    end
    if command == "finishOff" then
        Risers.finishOff(player, args)
    elseif command == "headHit" then
        headHitById(player, args.id)
    end
end)

-- ------------------------------------------------------------------ status

function Risers.count()
    return registry().count
end

function Risers.status()
    local reg = registry()
    local now = hours()
    local due, found = 0, 0
    for _, e in pairs(reg.entries) do
        if e.due <= now then
            due = due + 1
        end
        if e.found then
            found = found + 1
        end
    end
    local r = Clock.risers
    local wake = "off"
    if r.wake then
        wake = "on"
    end
    local scanned = "no scan yet"
    if last ~= nil then
        scanned = "last scan " .. Phase.stamp(Clock.now(), last.at) .. ": " .. last.due .. " due, " .. last.rose .. " rose, "
            .. last.unloaded .. " not loaded, " .. last.missed .. " not found"
    end
    return {
        "risers: rise " .. r.rise .. ", wake " .. wake .. "; " .. reg.count .. " corpses registered (at most "
            .. Settings.riserLimit() .. "), " .. due .. " due, " .. found .. " found; " .. scanned,
        "this session: " .. counts.marked .. " marked to rise, " .. counts.down .. " kept down, " .. counts.rose .. " rose, "
            .. counts.finished .. " finished off, " .. counts.gone .. " gone, " .. counts.expired .. " too old, "
            .. counts.dropped .. " over the limit",
    }
end

-- Single player has no server to send to: the corpse actions call these directly.
State.risers = Risers

return Risers
