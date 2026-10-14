local State = require "Crepuscular/State"

local PHASES = { "auto", "day", "night", "bloodmoon" }

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
        if type(arg) == "string" then
            args[i] = getText(arg)
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
    menu:addOption(getText("ContextMenu_Crepuscular_Roll"), playerIndex, send, { command = "roll" })
end

Events.OnFillWorldObjectContextMenu.Add(fill)

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module == State.MODULE and command == "reply" then
            show(args)
        end
    end)
end
