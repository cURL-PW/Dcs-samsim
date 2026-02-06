--[[
    Multiplayer Support Module for DCS SAMSim

    Features:
    - Multi-user session management
    - Role-based access control
    - Site assignment and coordination
    - Synchronized state updates
    - Command authorization levels
    - Player communication

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_Multiplayer = {}
SAMSIM_Multiplayer.Version = "1.0.0"

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_Multiplayer.Config = {
    maxPlayers = 16,
    maxSitesPerPlayer = 4,
    sessionTimeout = 300,           -- 5 minutes inactive timeout
    heartbeatInterval = 10,         -- 10 second heartbeat
    syncInterval = 0.5,             -- State sync every 500ms

    -- Role definitions
    roles = {
        COMMANDER = {
            level = 100,
            canAssignSites = true,
            canChangePolicy = true,
            canKickPlayers = true,
            canManageAllSites = true,
        },
        BATTERY_COMMANDER = {
            level = 80,
            canAssignSites = false,
            canChangePolicy = true,
            canKickPlayers = false,
            canManageAllSites = false,
        },
        OPERATOR = {
            level = 50,
            canAssignSites = false,
            canChangePolicy = false,
            canKickPlayers = false,
            canManageAllSites = false,
        },
        OBSERVER = {
            level = 10,
            canAssignSites = false,
            canChangePolicy = false,
            canKickPlayers = false,
            canManageAllSites = false,
            readOnly = true,
        },
    },
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_Multiplayer.State = {
    -- Session info
    session = {
        id = nil,
        name = "Default Session",
        createdAt = 0,
        hostId = nil,
        password = nil,
    },

    -- Connected players
    players = {},
    -- Format: { [playerId] = { id, name, role, assignedSites, lastHeartbeat, ... } }

    -- Site assignments
    siteAssignments = {},
    -- Format: { [siteId] = playerId }

    -- Chat messages
    chat = {},

    -- Command queue (for authorization)
    pendingCommands = {},

    -- Sync state
    lastSync = 0,
}

-- ============================================================================
-- Session Management
-- ============================================================================
SAMSIM_Multiplayer.Session = {}

function SAMSIM_Multiplayer.Session.create(sessionName, password)
    local sessionId = SAMSIM_Multiplayer.generateId()

    SAMSIM_Multiplayer.State.session = {
        id = sessionId,
        name = sessionName or "SAM Operations",
        createdAt = timer.getTime(),
        hostId = nil,
        password = password,
    }

    env.info("MP: Session created - " .. sessionId)
    return sessionId
end

function SAMSIM_Multiplayer.Session.join(playerId, playerName, password, requestedRole)
    local state = SAMSIM_Multiplayer.State
    local session = state.session

    -- Check password if set
    if session.password and session.password ~= password then
        return false, "Invalid password"
    end

    -- Check max players
    local playerCount = 0
    for _ in pairs(state.players) do
        playerCount = playerCount + 1
    end

    if playerCount >= SAMSIM_Multiplayer.Config.maxPlayers then
        return false, "Session full"
    end

    -- Determine role
    local role = "OPERATOR"
    if not session.hostId then
        -- First player becomes commander
        role = "COMMANDER"
        session.hostId = playerId
    elseif requestedRole and SAMSIM_Multiplayer.Config.roles[requestedRole] then
        -- Check if role request is valid (observer can always join as observer)
        if requestedRole == "OBSERVER" then
            role = "OBSERVER"
        else
            role = "OPERATOR"  -- Default to operator, can be promoted
        end
    end

    -- Create player entry
    state.players[playerId] = {
        id = playerId,
        name = playerName or ("Player " .. playerId),
        role = role,
        roleConfig = SAMSIM_Multiplayer.Config.roles[role],
        assignedSites = {},
        joinedAt = timer.getTime(),
        lastHeartbeat = timer.getTime(),
        connected = true,
    }

    env.info(string.format("MP: Player joined - %s (%s) as %s", playerName, playerId, role))

    return true, {
        sessionId = session.id,
        playerId = playerId,
        role = role,
    }
end

function SAMSIM_Multiplayer.Session.leave(playerId)
    local state = SAMSIM_Multiplayer.State
    local player = state.players[playerId]

    if not player then
        return false, "Player not found"
    end

    -- Unassign all sites
    for _, siteId in ipairs(player.assignedSites) do
        state.siteAssignments[siteId] = nil
    end

    -- If commander leaves, promote someone
    if player.role == "COMMANDER" then
        SAMSIM_Multiplayer.promoteNewCommander()
    end

    state.players[playerId] = nil

    env.info(string.format("MP: Player left - %s", player.name))
    return true
end

function SAMSIM_Multiplayer.promoteNewCommander()
    local state = SAMSIM_Multiplayer.State
    local newCommander = nil
    local highestLevel = 0

    for playerId, player in pairs(state.players) do
        if player.roleConfig.level > highestLevel then
            highestLevel = player.roleConfig.level
            newCommander = playerId
        end
    end

    if newCommander then
        state.players[newCommander].role = "COMMANDER"
        state.players[newCommander].roleConfig = SAMSIM_Multiplayer.Config.roles.COMMANDER
        state.session.hostId = newCommander

        env.info("MP: New commander - " .. state.players[newCommander].name)
    end
end

-- ============================================================================
-- Site Assignment
-- ============================================================================
SAMSIM_Multiplayer.Sites = {}

function SAMSIM_Multiplayer.Sites.assign(siteId, playerId, assignerId)
    local state = SAMSIM_Multiplayer.State

    -- Check assigner permission
    local assigner = state.players[assignerId]
    if not assigner or not assigner.roleConfig.canAssignSites then
        return false, "Not authorized to assign sites"
    end

    local player = state.players[playerId]
    if not player then
        return false, "Player not found"
    end

    -- Check max sites per player
    if #player.assignedSites >= SAMSIM_Multiplayer.Config.maxSitesPerPlayer then
        return false, "Player has maximum sites assigned"
    end

    -- Check if site is already assigned
    if state.siteAssignments[siteId] then
        local currentOwner = state.players[state.siteAssignments[siteId]]
        if currentOwner then
            -- Remove from current owner
            for i, sid in ipairs(currentOwner.assignedSites) do
                if sid == siteId then
                    table.remove(currentOwner.assignedSites, i)
                    break
                end
            end
        end
    end

    -- Assign site
    state.siteAssignments[siteId] = playerId
    table.insert(player.assignedSites, siteId)

    env.info(string.format("MP: Site %s assigned to %s", siteId, player.name))
    return true
end

function SAMSIM_Multiplayer.Sites.unassign(siteId, requesterId)
    local state = SAMSIM_Multiplayer.State

    local requester = state.players[requesterId]
    if not requester then
        return false, "Requester not found"
    end

    local currentOwner = state.siteAssignments[siteId]
    if not currentOwner then
        return false, "Site not assigned"
    end

    -- Check permission (owner or commander)
    if currentOwner ~= requesterId and not requester.roleConfig.canManageAllSites then
        return false, "Not authorized"
    end

    -- Remove assignment
    local player = state.players[currentOwner]
    if player then
        for i, sid in ipairs(player.assignedSites) do
            if sid == siteId then
                table.remove(player.assignedSites, i)
                break
            end
        end
    end

    state.siteAssignments[siteId] = nil

    env.info(string.format("MP: Site %s unassigned", siteId))
    return true
end

function SAMSIM_Multiplayer.Sites.canControl(siteId, playerId)
    local state = SAMSIM_Multiplayer.State
    local player = state.players[playerId]

    if not player then
        return false
    end

    -- Observers can't control
    if player.roleConfig.readOnly then
        return false
    end

    -- Commanders can control all
    if player.roleConfig.canManageAllSites then
        return true
    end

    -- Check if assigned
    return state.siteAssignments[siteId] == playerId
end

-- ============================================================================
-- Command Authorization
-- ============================================================================
SAMSIM_Multiplayer.Commands = {}

function SAMSIM_Multiplayer.Commands.authorize(cmd, playerId)
    local state = SAMSIM_Multiplayer.State
    local player = state.players[playerId]

    if not player then
        return false, "Player not found"
    end

    -- Observers can't execute commands
    if player.roleConfig.readOnly then
        return false, "Observer cannot execute commands"
    end

    -- Check site control for site-specific commands
    if cmd.siteId then
        if not SAMSIM_Multiplayer.Sites.canControl(cmd.siteId, playerId) then
            return false, "Not authorized for this site"
        end
    end

    -- Check role-specific permissions
    if cmd.type == "CHANGE_POLICY" and not player.roleConfig.canChangePolicy then
        return false, "Not authorized to change policy"
    end

    if cmd.type == "KICK_PLAYER" and not player.roleConfig.canKickPlayers then
        return false, "Not authorized to kick players"
    end

    if cmd.type == "ASSIGN_SITE" and not player.roleConfig.canAssignSites then
        return false, "Not authorized to assign sites"
    end

    return true
end

function SAMSIM_Multiplayer.Commands.execute(cmd, playerId)
    -- Authorize
    local authorized, reason = SAMSIM_Multiplayer.Commands.authorize(cmd, playerId)
    if not authorized then
        return {success = false, message = reason}
    end

    -- Route to unified controller
    if SAMSIM and SAMSIM.Unified then
        return SAMSIM.Unified.processCommand(cmd)
    end

    return {success = false, message = "Controller not available"}
end

-- ============================================================================
-- Player Management
-- ============================================================================
SAMSIM_Multiplayer.Players = {}

function SAMSIM_Multiplayer.Players.setRole(playerId, newRole, requesterId)
    local state = SAMSIM_Multiplayer.State

    local requester = state.players[requesterId]
    if not requester or requester.role ~= "COMMANDER" then
        return false, "Only commander can change roles"
    end

    local player = state.players[playerId]
    if not player then
        return false, "Player not found"
    end

    if not SAMSIM_Multiplayer.Config.roles[newRole] then
        return false, "Invalid role"
    end

    -- Can't demote yourself as commander
    if playerId == requesterId and newRole ~= "COMMANDER" then
        return false, "Cannot demote yourself"
    end

    player.role = newRole
    player.roleConfig = SAMSIM_Multiplayer.Config.roles[newRole]

    -- If promoting to commander, demote current commander
    if newRole == "COMMANDER" and requesterId ~= playerId then
        requester.role = "BATTERY_COMMANDER"
        requester.roleConfig = SAMSIM_Multiplayer.Config.roles.BATTERY_COMMANDER
        state.session.hostId = playerId
    end

    env.info(string.format("MP: %s role changed to %s", player.name, newRole))
    return true
end

function SAMSIM_Multiplayer.Players.kick(playerId, requesterId)
    local state = SAMSIM_Multiplayer.State

    local requester = state.players[requesterId]
    if not requester or not requester.roleConfig.canKickPlayers then
        return false, "Not authorized to kick players"
    end

    -- Can't kick yourself
    if playerId == requesterId then
        return false, "Cannot kick yourself"
    end

    return SAMSIM_Multiplayer.Session.leave(playerId)
end

function SAMSIM_Multiplayer.Players.heartbeat(playerId)
    local state = SAMSIM_Multiplayer.State
    local player = state.players[playerId]

    if player then
        player.lastHeartbeat = timer.getTime()
        player.connected = true
    end
end

function SAMSIM_Multiplayer.Players.checkTimeouts()
    local state = SAMSIM_Multiplayer.State
    local currentTime = timer.getTime()
    local timeout = SAMSIM_Multiplayer.Config.sessionTimeout

    for playerId, player in pairs(state.players) do
        if currentTime - player.lastHeartbeat > timeout then
            player.connected = false
            env.info("MP: Player timed out - " .. player.name)

            -- Auto-remove after extended timeout
            if currentTime - player.lastHeartbeat > timeout * 2 then
                SAMSIM_Multiplayer.Session.leave(playerId)
            end
        end
    end
end

-- ============================================================================
-- Chat System
-- ============================================================================
SAMSIM_Multiplayer.Chat = {}

function SAMSIM_Multiplayer.Chat.send(playerId, message, channel)
    local state = SAMSIM_Multiplayer.State
    local player = state.players[playerId]

    if not player then
        return false, "Player not found"
    end

    local chatMsg = {
        id = SAMSIM_Multiplayer.generateId(),
        playerId = playerId,
        playerName = player.name,
        message = message,
        channel = channel or "ALL",  -- ALL, TEAM, SITE
        timestamp = timer.getTime(),
    }

    table.insert(state.chat, chatMsg)

    -- Keep only last 100 messages
    while #state.chat > 100 do
        table.remove(state.chat, 1)
    end

    return true, chatMsg
end

function SAMSIM_Multiplayer.Chat.getRecent(count)
    local state = SAMSIM_Multiplayer.State
    count = count or 20

    local recent = {}
    local start = math.max(1, #state.chat - count + 1)

    for i = start, #state.chat do
        table.insert(recent, state.chat[i])
    end

    return recent
end

-- ============================================================================
-- State Synchronization
-- ============================================================================
SAMSIM_Multiplayer.Sync = {}

function SAMSIM_Multiplayer.Sync.getFullState()
    local state = SAMSIM_Multiplayer.State

    -- Get unified controller state
    local gameState = {}
    if SAMSIM and SAMSIM.Unified then
        gameState = SAMSIM.Unified.getStateForExport()
    end

    return {
        module = "MULTIPLAYER",
        version = SAMSIM_Multiplayer.Version,
        session = state.session,
        players = state.players,
        siteAssignments = state.siteAssignments,
        chat = SAMSIM_Multiplayer.Chat.getRecent(10),
        gameState = gameState,
    }
end

function SAMSIM_Multiplayer.Sync.getPlayerState(playerId)
    local state = SAMSIM_Multiplayer.State
    local player = state.players[playerId]

    if not player then
        return nil
    end

    -- Get states only for assigned sites (unless commander)
    local siteStates = {}
    if SAMSIM and SAMSIM.Unified then
        if player.roleConfig.canManageAllSites then
            siteStates = SAMSIM.Unified.getStateForExport()
        else
            for _, siteId in ipairs(player.assignedSites) do
                local site = SAMSIM.Unified.Sites[siteId]
                if site and site.controller then
                    siteStates[siteId] = site.controller.getStateForExport()
                end
            end
        end
    end

    return {
        player = player,
        assignedSites = player.assignedSites,
        siteStates = siteStates,
        canControl = not player.roleConfig.readOnly,
    }
end

-- ============================================================================
-- Command Processing
-- ============================================================================
function SAMSIM_Multiplayer.processCommand(cmd, playerId)
    local cmdType = cmd.type

    -- Session commands
    if cmdType == "JOIN_SESSION" then
        local success, result = SAMSIM_Multiplayer.Session.join(
            playerId, cmd.playerName, cmd.password, cmd.role
        )
        return {success = success, data = result}

    elseif cmdType == "LEAVE_SESSION" then
        local success = SAMSIM_Multiplayer.Session.leave(playerId)
        return {success = success}

    elseif cmdType == "HEARTBEAT" then
        SAMSIM_Multiplayer.Players.heartbeat(playerId)
        return {success = true}

    -- Site management
    elseif cmdType == "ASSIGN_SITE" then
        local success, msg = SAMSIM_Multiplayer.Sites.assign(
            cmd.siteId, cmd.targetPlayerId, playerId
        )
        return {success = success, message = msg}

    elseif cmdType == "UNASSIGN_SITE" then
        local success, msg = SAMSIM_Multiplayer.Sites.unassign(cmd.siteId, playerId)
        return {success = success, message = msg}

    -- Player management
    elseif cmdType == "SET_ROLE" then
        local success, msg = SAMSIM_Multiplayer.Players.setRole(
            cmd.targetPlayerId, cmd.role, playerId
        )
        return {success = success, message = msg}

    elseif cmdType == "KICK_PLAYER" then
        local success, msg = SAMSIM_Multiplayer.Players.kick(cmd.targetPlayerId, playerId)
        return {success = success, message = msg}

    -- Chat
    elseif cmdType == "CHAT" then
        local success, msg = SAMSIM_Multiplayer.Chat.send(playerId, cmd.message, cmd.channel)
        return {success = success, message = msg}

    -- State sync
    elseif cmdType == "GET_STATE" then
        local state = SAMSIM_Multiplayer.Sync.getFullState()
        return {success = true, state = state}

    elseif cmdType == "GET_PLAYER_STATE" then
        local state = SAMSIM_Multiplayer.Sync.getPlayerState(playerId)
        return {success = state ~= nil, state = state}

    -- Game commands (route through authorization)
    else
        return SAMSIM_Multiplayer.Commands.execute(cmd, playerId)
    end
end

-- ============================================================================
-- Utility
-- ============================================================================
function SAMSIM_Multiplayer.generateId()
    local chars = "0123456789ABCDEF"
    local id = ""
    for i = 1, 8 do
        local idx = math.random(1, 16)
        id = id .. chars:sub(idx, idx)
    end
    return id
end

-- ============================================================================
-- Update Loop
-- ============================================================================
function SAMSIM_Multiplayer.update()
    -- Check for timeouts
    SAMSIM_Multiplayer.Players.checkTimeouts()

    return timer.getTime() + SAMSIM_Multiplayer.Config.heartbeatInterval
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM_Multiplayer.getStateForExport()
    return SAMSIM_Multiplayer.Sync.getFullState()
end

-- ============================================================================
-- Initialization
-- ============================================================================
function SAMSIM_Multiplayer.initialize()
    -- Create default session
    SAMSIM_Multiplayer.Session.create("SAM Operations")

    -- Start update loop
    timer.scheduleFunction(SAMSIM_Multiplayer.update, nil, timer.getTime() + 1)

    env.info("SAMSIM Multiplayer Module initialized - Version " .. SAMSIM_Multiplayer.Version)
end

env.info("SAMSIM Multiplayer Module loaded - Version " .. SAMSIM_Multiplayer.Version)
