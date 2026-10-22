local Log = require "Crepuscular/Log"
local State = require "Crepuscular/State"
local Overrides = require "Crepuscular/Overrides"
local Kinds = require "Crepuscular/Kinds"

-- The server may have given the online ID to another zombie by now, so a copy is only removed near
-- where the server's zombie was.
local OUT_RANGE = 30

-- Serial of the last announcement this game has shown.
local announced = nil

-- NotificationPlace: 1 over the head, 2 in chat, 3 both.
local HEAD, CHAT = 1, 2

-- A chat line kept until the chat has a tab: a joining player's game gets the state before the
-- server sets up its chat.
local waiting = nil

local HEX = "0123456789abcdef"

-- One colour channel of rrggbb, from 1-based position i.
local function channel(color, i)
    local high = string.find(HEX, string.sub(color, i, i), 1, true) - 1
    local low = string.find(HEX, string.sub(color, i + 1, i + 1), 1, true) - 1
    return high * 16 + low
end

local function players()
    local list = {}
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            list[#list + 1] = player
        end
    end
    return list
end

local function overHead(list, text, r, g, b)
    for _, player in ipairs(list) do
        player:setHaloNote(text, r, g, b, 500)
    end
end

-- What ISChat reads of a message, laid out as the game's chat lines: colour and font size tags,
-- the speaker in brackets and the text with < and > escaped. ISChat reads it again when the player
-- changes the font size.
local function chatMessage(text, r, g, b)
    local color = "<RGB:" .. r / 255 .. "," .. g / 255 .. "," .. b / 255 .. "> <SIZE:"
    local body = "> [" .. getText("IGUI_Crepuscular_ChatTitle") .. "]: "
        .. (string.gsub((string.gsub(text, "<", "&lt;")), ">", "&gt;"))
    return {
        getTextWithPrefix = function()
            return color .. getCore():getOptionChatFontSize() .. body
        end,
        getAuthor = function()
            return nil
        end,
    }
end

-- Adds the waiting line to the tab the player has open, where the game puts its server messages.
local function toChat()
    if waiting == nil or ISChat.instance == nil or ISChat.instance.chatText == nil then
        return
    end
    local line = waiting
    waiting = nil
    local ok, err = pcall(ISChat.addLineInChat, line.message, ISChat.instance.chatText.tabID)
    if not ok then
        Log.warnOnce("chat failed", "the chat took no line (" .. tostring(err) .. "), so it shows over the head")
        overHead(players(), line.text, line.r, line.g, line.b)
    end
end

local function announce(state)
    local line = state.announce
    if line == nil or line.serial == announced then
        return
    end
    local list = players()
    if #list == 0 then
        return
    end
    announced = line.serial
    local text = line.text
    if text ~= nil and string.sub(text, 1, 1) == "@" then
        text = getText(string.sub(text, 2))
    end
    local r, g, b = channel(line.color, 1), channel(line.color, 3), channel(line.color, 5)
    local head, chat = line.place ~= CHAT, line.place ~= HEAD
    if text ~= nil and chat then
        local missing = nil
        if not isClient() then
            missing = "single player has no chat"
        elseif type(ISChat) ~= "table" or type(ISChat.addLineInChat) ~= "function" then
            missing = "the game's chat (ISChat.addLineInChat) is missing"
        end
        if missing ~= nil then
            Log.warnOnce("no chat", "NotificationPlace puts lines in chat, but " .. missing .. ", so they show over the head")
            head, chat = true, false
        end
    end
    if text ~= nil and head then
        overHead(list, text, r, g, b)
    end
    if text ~= nil and chat then
        waiting = { message = chatMessage(text, r, g, b), text = text, r = r, g = g, b = b }
        toChat()
    end
    -- One sound per game, however many players share its screen. A name the game lacks plays
    -- nothing, and the server warns about it.
    if line.sound ~= nil then
        getSoundManager():playUISound(line.sound)
    end
end

State.listen(announce)

-- Cry of Fear's own answer to its server's out command (its COF_NetClient.lua): it finds the copy
-- by online ID, checks it is a monster within 30 tiles of the server's one, stops its looping
-- sounds and removes it.
local function cryOfFearOut()
    local answers = COF_NetClient
    if type(answers) == "table" and type(answers.out) == "function" then
        return answers.out
    end
    return nil
end

-- The server removed these zombies, { id, x, y, kind } each; the game doesn't remove this game's
-- copies of zombies a script removes, and the copy this game runs would go on attacking.
local function takeOut(list)
    local byId = {}
    local zombies = getCell():getZombieList()
    for i = 0, zombies:size() - 1 do
        local z = zombies:get(i)
        byId[z:getOnlineID()] = z
    end
    local kindOf = Kinds.test()
    local cofOut = cryOfFearOut()
    for _, entry in ipairs(list) do
        if entry.kind == "cof" and cofOut ~= nil then
            -- Only for a copy this game has: Cry of Fear looks it up again by itself.
            if byId[entry.id] ~= nil then
                local ok, err = pcall(cofOut, entry)
                if not ok then
                    Log.warnOnce("cof out", "Cry of Fear's out failed for a monster the server removed: " .. tostring(err))
                end
            end
        else
            local z = byId[entry.id]
            if z ~= nil and kindOf(z) == entry.kind then
                local dx, dy = z:getX() - entry.x, z:getY() - entry.y
                if dx * dx + dy * dy <= OUT_RANGE * OUT_RANGE then
                    Kinds.remove(z, entry.kind)
                end
            end
        end
    end
end

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == State.MODULE and command == "out" then
            takeOut(args.list)
        end
    end)

    Events.OnGameStart.Add(function()
        ModData.request(State.NAME)
    end)

    -- Fired once the chat has its first tab.
    Events.OnSetDefaultTab.Add(toChat)

    -- The packet only raises this event; nothing is stored unless we store it.
    Events.OnReceiveGlobalModData.Add(function(tag, state)
        if tag ~= State.NAME then
            return
        end
        if type(state) ~= "table" then
            Log.warn("the server has no Crepuscular state; is the mod running there?")
            return
        end
        ModData.add(State.NAME, state)
        Overrides.applyAll(state.sandbox)
        State.notify(state)
    end)
end
