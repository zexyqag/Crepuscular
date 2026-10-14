local State = require "Crepuscular/State"

local PHASES = { "auto", "day", "night" }

local function allowed(player)
    if not isClient() or getDebug() then
        return true
    end
    local role = player:getRole()
    return role ~= nil and role:hasCapability(Capability.SandboxOptions)
end

local function show(reply)
    local player = getSpecificPlayer(reply.player)
    if player == nil then
        return
    end
    for _, line in ipairs(reply.lines or {}) do
        print("[Crepuscular] " .. line)
    end
    local args = {}
    for i, arg in ipairs(reply.args or {}) do
        if type(arg) == "table" then
            args[i] = getText(arg.key)
        else
            args[i] = arg
        end
    end
    player:setHaloNote(getText(reply.text, unpack(args)), 255, 255, 255, 300)
end

local function send(playerIndex, args)
    args.player = playerIndex
    if isClient() then
        sendClientCommand(getSpecificPlayer(playerIndex), State.MODULE, "admin", args)
    else
        local reply = State.commands.run(args)
        reply.player = playerIndex
        show(reply)
    end
end

local function fill(playerIndex, context, worldObjects, test)
    if test then
        return
    end
    local player = getSpecificPlayer(playerIndex)
    if player == nil or not allowed(player) then
        return
    end
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(context:addOption(getText("ContextMenu_Crepuscular")), menu)
    menu:addOption(getText("ContextMenu_Crepuscular_Status"), playerIndex, send, { command = "status" })
    local force = ISContextMenu:getNew(menu)
    menu:addSubMenu(menu:addOption(getText("ContextMenu_Crepuscular_Force")), force)
    for _, phase in ipairs(PHASES) do
        force:addOption(getText("IGUI_Crepuscular_Phase_" .. phase), playerIndex, send, { command = "force", phase = phase })
    end
    local state = ModData.get(State.NAME)
    if state ~= nil and #state.ids > 0 then
        local events = ISContextMenu:getNew(menu)
        menu:addSubMenu(menu:addOption(getText("ContextMenu_Crepuscular_Start")), events)
        for _, id in ipairs(state.ids) do
            events:addOption(id, playerIndex, send, { command = "start", id = id })
        end
    end
    menu:addOption(getText("ContextMenu_Crepuscular_End"), playerIndex, send, { command = "end" })
    menu:addOption(getText("ContextMenu_Crepuscular_Redecide"), playerIndex, send, { command = "redecide" })
end

Events.OnFillWorldObjectContextMenu.Add(fill)

-- The number of definitions with errors last shown to this game's admins.
local shownErrors = 0

local function errors(state)
    if state.errors == shownErrors then
        return
    end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player ~= nil then
            if state.errors > 0 and allowed(player) then
                player:setHaloNote(getText("IGUI_Crepuscular_Errors", state.errors), 255, 160, 60, 500)
            end
            shownErrors = state.errors
        end
    end
end

State.listen(errors)

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == State.MODULE and command == "reply" then
            show(args)
        end
    end)
end
