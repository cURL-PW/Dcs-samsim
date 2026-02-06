--[[
    SAMSIM IADS (Integrated Air Defense System) Module
    Network management for coordinated air defense

    Author: Claude Code
    Version: 1.0.0
]]

SAMSIM_IADS = {}
SAMSIM_IADS.Version = "1.0.0"

-- ============================================================================
-- Node Types
-- ============================================================================
SAMSIM_IADS.NodeType = {
    EWR = "EWR",               -- Early Warning Radar
    SAM = "SAM",               -- SAM Site
    COMMAND = "COMMAND",       -- Command Post
    COMMS = "COMMS",           -- Communications Relay
}

-- ============================================================================
-- SAM Operational States
-- ============================================================================
SAMSIM_IADS.SamState = {
    DARK = "DARK",             -- Radar off
    ACTIVE = "ACTIVE",         -- Searching
    TRACKING = "TRACKING",     -- Tracking target(s)
    ENGAGING = "ENGAGING",     -- Missiles in flight
    SUPPRESSED = "SUPPRESSED", -- SEAD suppressed
    DAMAGED = "DAMAGED",       -- Partially damaged
    DESTROYED = "DESTROYED",   -- Destroyed
}

-- ============================================================================
-- EMCON (Emission Control) Levels
-- ============================================================================
SAMSIM_IADS.EMCON = {
    ACTIVE = "ACTIVE",         -- All radars active
    LIMITED = "LIMITED",       -- Only EWR active
    DARK = "DARK",             -- All radars off
    ADAPTIVE = "ADAPTIVE",     -- Threat-based control
}

-- ============================================================================
-- Networks Registry
-- ============================================================================
SAMSIM_IADS.networks = {}

-- ============================================================================
-- Node Structure
-- ============================================================================

--- Create a new node
---@param nodeType string NodeType value
---@param groupName string DCS group name
---@param options table|nil Additional options
---@return table Node object
local function createNode(nodeType, groupName, options)
    options = options or {}

    local node = {
        id = string.format("%s_%s_%d", nodeType, groupName, os.time()),
        type = nodeType,
        groupName = groupName,
        name = options.name or groupName,

        -- Status
        state = SAMSIM_IADS.SamState.DARK,
        alive = true,
        operational = true,

        -- Position (updated on first check)
        position = nil,

        -- Links to other nodes
        links = {},

        -- SAM specific
        samType = options.samType,
        samConfig = options.samConfig,
        priority = options.priority or 2,

        -- EWR specific
        ewrConfig = options.ewrConfig,
        detectionRange = options.detectionRange,

        -- Tracking
        tracks = {},
        engagements = {},

        -- Timing
        lastUpdate = 0,
        suppressedUntil = 0,
    }

    return node
end

-- ============================================================================
-- Network Management
-- ============================================================================

--- Create a new IADS network
---@param name string Network name
---@param options table|nil Configuration options
---@return table Network object
function SAMSIM_IADS.createNetwork(name, options)
    options = options or {}

    local network = {
        name = name,
        coalition = options.coalition or coalition.side.RED,

        -- Nodes
        nodes = {},
        ewrs = {},
        sams = {},
        commandPosts = {},

        -- Links
        links = {},

        -- State
        emconLevel = options.emcon or SAMSIM_IADS.EMCON.ACTIVE,
        active = true,

        -- Settings
        settings = SAMSIM_Utils.mergeTables(
            SAMSIM_Config.IADSDefaults,
            options.settings or {}
        ),

        -- Threat data
        sharedThreats = {},

        -- Statistics
        stats = {
            created = SAMSIM_Utils.getTime(),
            engagements = 0,
            kills = 0,
            losses = 0,
        },
    }

    SAMSIM_IADS.networks[name] = network

    -- Fire event
    SAMSIM_Events.fire(SAMSIM_Events.Type.NETWORK_CREATED, {
        networkName = name,
        coalition = network.coalition,
    })

    SAMSIM_Utils.info("IADS Network '%s' created", name)

    return network
end

--- Get network by name
---@param name string
---@return table|nil
function SAMSIM_IADS.getNetwork(name)
    return SAMSIM_IADS.networks[name]
end

--- Delete a network
---@param name string
function SAMSIM_IADS.deleteNetwork(name)
    local network = SAMSIM_IADS.networks[name]
    if network then
        -- Cleanup nodes
        for _, node in pairs(network.nodes) do
            if node.updateTaskId then
                SAMSIM_Utils.cancel(node.updateTaskId)
            end
        end

        SAMSIM_IADS.networks[name] = nil
        SAMSIM_Utils.info("IADS Network '%s' deleted", name)
    end
end

-- ============================================================================
-- Node Registration
-- ============================================================================

--- Add EWR to network
---@param network table Network object
---@param groupName string DCS group name
---@param options table|nil Options
---@return table|nil Node object
function SAMSIM_IADS.addEWR(network, groupName, options)
    options = options or {}

    -- Check if group exists
    local group = SAMSIM_Utils.getGroupByName(groupName)
    if not group then
        SAMSIM_Utils.warn("EWR group '%s' not found", groupName)
        return nil
    end

    -- Get EWR config from unit types
    local units = group:getUnits()
    local ewrConfig = nil
    for _, unit in ipairs(units) do
        local typeName = SAMSIM_Utils.getUnitTypeName(unit)
        ewrConfig = SAMSIM_Config.getEWRConfig(typeName)
        if ewrConfig then break end
    end

    if not ewrConfig and not options.detectionRange then
        SAMSIM_Utils.warn("Unknown EWR type for group '%s'", groupName)
    end

    -- Create node
    local node = createNode(SAMSIM_IADS.NodeType.EWR, groupName, {
        name = options.name or groupName,
        ewrConfig = ewrConfig,
        detectionRange = options.detectionRange or (ewrConfig and ewrConfig.range) or 300000,
    })

    -- Get initial position
    node.position = SAMSIM_Utils.getGroupPosition(groupName)

    -- Register in network
    network.nodes[node.id] = node
    network.ewrs[node.id] = node

    -- Fire event
    SAMSIM_Events.fire(SAMSIM_Events.Type.NODE_ADDED, {
        networkName = network.name,
        nodeId = node.id,
        nodeType = node.type,
        groupName = groupName,
    })

    SAMSIM_Utils.info("Added EWR '%s' to network '%s'", groupName, network.name)

    return node
end

--- Add SAM site to network
---@param network table Network object
---@param groupName string DCS group name
---@param samType string|nil SAM type (e.g., "SA10", "PATRIOT")
---@param options table|nil Options
---@return table|nil Node object
function SAMSIM_IADS.addSAM(network, groupName, samType, options)
    options = options or {}

    -- Check if group exists
    local group = SAMSIM_Utils.getGroupByName(groupName)
    if not group then
        SAMSIM_Utils.warn("SAM group '%s' not found", groupName)
        return nil
    end

    -- Auto-detect SAM type if not specified
    local samConfig = nil
    if samType then
        samConfig = SAMSIM_Config.SAMTypes[samType]
    else
        -- Try to detect from unit types
        local units = group:getUnits()
        for _, unit in ipairs(units) do
            local typeName = SAMSIM_Utils.getUnitTypeName(unit)
            samConfig, samType = SAMSIM_Config.getSAMTypeByUnit(typeName)
            if samConfig then break end
        end
    end

    if not samConfig then
        SAMSIM_Utils.warn("Unknown SAM type for group '%s'", groupName)
        samConfig = {}
    end

    -- Create node
    local node = createNode(SAMSIM_IADS.NodeType.SAM, groupName, {
        name = options.name or groupName,
        samType = samType,
        samConfig = samConfig,
        priority = options.priority or 2,
    })

    -- Get initial position
    node.position = SAMSIM_Utils.getGroupPosition(groupName)

    -- Set initial state based on EMCON
    if network.emconLevel == SAMSIM_IADS.EMCON.DARK then
        node.state = SAMSIM_IADS.SamState.DARK
        SAMSIM_Utils.setGroupAlarmStateByName(groupName, SAMSIM_Utils.ALARM_STATE.GREEN)
    else
        node.state = SAMSIM_IADS.SamState.ACTIVE
        SAMSIM_Utils.setGroupAlarmStateByName(groupName, SAMSIM_Utils.ALARM_STATE.RED)
    end

    -- Register in network
    network.nodes[node.id] = node
    network.sams[node.id] = node

    -- Fire event
    SAMSIM_Events.fire(SAMSIM_Events.Type.NODE_ADDED, {
        networkName = network.name,
        nodeId = node.id,
        nodeType = node.type,
        groupName = groupName,
        samType = samType,
    })

    SAMSIM_Utils.info("Added SAM '%s' (%s) to network '%s'", groupName, samType or "unknown", network.name)

    return node
end

--- Add command post to network
---@param network table Network object
---@param groupName string DCS group name
---@param options table|nil Options
---@return table|nil Node object
function SAMSIM_IADS.addCommandPost(network, groupName, options)
    options = options or {}

    local group = SAMSIM_Utils.getGroupByName(groupName)
    if not group then
        SAMSIM_Utils.warn("Command post group '%s' not found", groupName)
        return nil
    end

    local node = createNode(SAMSIM_IADS.NodeType.COMMAND, groupName, {
        name = options.name or groupName,
    })

    node.position = SAMSIM_Utils.getGroupPosition(groupName)

    network.nodes[node.id] = node
    network.commandPosts[node.id] = node

    SAMSIM_Utils.info("Added Command Post '%s' to network '%s'", groupName, network.name)

    return node
end

--- Remove node from network
---@param network table Network object
---@param nodeId string Node ID
function SAMSIM_IADS.removeNode(network, nodeId)
    local node = network.nodes[nodeId]
    if not node then return end

    -- Remove from type-specific lists
    network.ewrs[nodeId] = nil
    network.sams[nodeId] = nil
    network.commandPosts[nodeId] = nil

    -- Remove all links
    for linkedId in pairs(node.links) do
        SAMSIM_IADS.unlinkNodes(network, nodeId, linkedId)
    end

    -- Remove from nodes
    network.nodes[nodeId] = nil

    SAMSIM_Events.fire(SAMSIM_Events.Type.NODE_REMOVED, {
        networkName = network.name,
        nodeId = nodeId,
    })
end

-- ============================================================================
-- Auto-Detection
-- ============================================================================

--- Auto-add SAM sites and EWRs by naming pattern
---@param network table Network object
---@param samPattern string Lua pattern for SAM groups (e.g., "^SAM_")
---@param ewrPattern string Lua pattern for EWR groups (e.g., "^EWR_")
---@return number, number Number of SAMs and EWRs added
function SAMSIM_IADS.autoAddByPattern(network, samPattern, ewrPattern)
    local samCount = 0
    local ewrCount = 0

    -- Find SAM groups
    if samPattern then
        local samGroups = SAMSIM_Utils.getGroupsByPattern(samPattern)
        for _, groupName in ipairs(samGroups) do
            local group = SAMSIM_Utils.getGroupByName(groupName)
            if group and group:getCoalition() == network.coalition then
                local node = SAMSIM_IADS.addSAM(network, groupName)
                if node then
                    samCount = samCount + 1
                end
            end
        end
    end

    -- Find EWR groups
    if ewrPattern then
        local ewrGroups = SAMSIM_Utils.getGroupsByPattern(ewrPattern)
        for _, groupName in ipairs(ewrGroups) do
            local group = SAMSIM_Utils.getGroupByName(groupName)
            if group and group:getCoalition() == network.coalition then
                local node = SAMSIM_IADS.addEWR(network, groupName)
                if node then
                    ewrCount = ewrCount + 1
                end
            end
        end
    end

    SAMSIM_Utils.info("Auto-added %d SAMs and %d EWRs to network '%s'",
        samCount, ewrCount, network.name)

    return samCount, ewrCount
end

-- ============================================================================
-- Link Management
-- ============================================================================

--- Link two nodes
---@param network table Network object
---@param node1Id string First node ID
---@param node2Id string Second node ID
---@return boolean Success
function SAMSIM_IADS.linkNodes(network, node1Id, node2Id)
    local node1 = network.nodes[node1Id]
    local node2 = network.nodes[node2Id]

    if not node1 or not node2 then
        return false
    end

    -- Create bidirectional link
    node1.links[node2Id] = true
    node2.links[node1Id] = true

    -- Store link in network
    local linkId = node1Id < node2Id and (node1Id .. "_" .. node2Id) or (node2Id .. "_" .. node1Id)
    network.links[linkId] = {
        node1 = node1Id,
        node2 = node2Id,
        distance = SAMSIM_Utils.getDistance2D(node1.position, node2.position),
    }

    SAMSIM_Events.fire(SAMSIM_Events.Type.NODE_LINKED, {
        networkName = network.name,
        node1 = node1Id,
        node2 = node2Id,
    })

    return true
end

--- Unlink two nodes
---@param network table Network object
---@param node1Id string First node ID
---@param node2Id string Second node ID
function SAMSIM_IADS.unlinkNodes(network, node1Id, node2Id)
    local node1 = network.nodes[node1Id]
    local node2 = network.nodes[node2Id]

    if node1 then node1.links[node2Id] = nil end
    if node2 then node2.links[node1Id] = nil end

    local linkId = node1Id < node2Id and (node1Id .. "_" .. node2Id) or (node2Id .. "_" .. node1Id)
    network.links[linkId] = nil

    SAMSIM_Events.fire(SAMSIM_Events.Type.NODE_UNLINKED, {
        networkName = network.name,
        node1 = node1Id,
        node2 = node2Id,
    })
end

--- Auto-link nodes within distance
---@param network table Network object
---@param maxDistance number Maximum link distance in meters
---@return number Number of links created
function SAMSIM_IADS.autoLinkByDistance(network, maxDistance)
    maxDistance = maxDistance or network.settings.maxLinkDistance
    local linkCount = 0

    local nodeIds = SAMSIM_Utils.tableKeys(network.nodes)

    for i = 1, #nodeIds do
        for j = i + 1, #nodeIds do
            local node1 = network.nodes[nodeIds[i]]
            local node2 = network.nodes[nodeIds[j]]

            if node1.position and node2.position then
                local distance = SAMSIM_Utils.getDistance2D(node1.position, node2.position)
                if distance <= maxDistance then
                    if SAMSIM_IADS.linkNodes(network, nodeIds[i], nodeIds[j]) then
                        linkCount = linkCount + 1
                    end
                end
            end
        end
    end

    SAMSIM_Utils.info("Auto-linked %d node pairs within %dm in network '%s'",
        linkCount, maxDistance, network.name)

    return linkCount
end

-- ============================================================================
-- EMCON Control
-- ============================================================================

--- Set network-wide EMCON level
---@param network table Network object
---@param level string EMCON level
---@param reason string|nil Reason for change
function SAMSIM_IADS.setNetworkEMCON(network, level, reason)
    local oldLevel = network.emconLevel
    network.emconLevel = level

    -- Apply to all SAM nodes
    for _, node in pairs(network.sams) do
        SAMSIM_IADS.setSiteEMCON(node, level)
    end

    SAMSIM_Events.networkEMCON(network.name, level, reason)
    SAMSIM_Utils.info("Network '%s' EMCON: %s -> %s (%s)",
        network.name, oldLevel, level, reason or "manual")
end

--- Set individual site EMCON
---@param node table SAM node
---@param level string EMCON level
function SAMSIM_IADS.setSiteEMCON(node, level)
    if node.type ~= SAMSIM_IADS.NodeType.SAM then return end

    if level == SAMSIM_IADS.EMCON.DARK then
        node.state = SAMSIM_IADS.SamState.DARK
        SAMSIM_Utils.setGroupAlarmStateByName(node.groupName, SAMSIM_Utils.ALARM_STATE.GREEN)
        SAMSIM_Events.samDeactivated(node.groupName, "EMCON")
    elseif level == SAMSIM_IADS.EMCON.ACTIVE then
        if node.state == SAMSIM_IADS.SamState.DARK or
           node.state == SAMSIM_IADS.SamState.SUPPRESSED then
            node.state = SAMSIM_IADS.SamState.ACTIVE
            SAMSIM_Utils.setGroupAlarmStateByName(node.groupName, SAMSIM_Utils.ALARM_STATE.RED)
            SAMSIM_Events.samActivated(node.groupName, node.samType)
        end
    end
end

--- Go to network-wide dark mode
---@param network table Network object
function SAMSIM_IADS.goToDark(network)
    SAMSIM_IADS.setNetworkEMCON(network, SAMSIM_IADS.EMCON.DARK, "command")
end

--- Go to network-wide active mode
---@param network table Network object
function SAMSIM_IADS.goToActive(network)
    SAMSIM_IADS.setNetworkEMCON(network, SAMSIM_IADS.EMCON.ACTIVE, "command")
end

-- ============================================================================
-- State Management
-- ============================================================================

--- Get site state
---@param node table SAM node
---@return string State
function SAMSIM_IADS.getSiteState(node)
    return node.state
end

--- Set site state
---@param node table SAM node
---@param state string New state
function SAMSIM_IADS.setSiteState(node, state)
    local oldState = node.state
    node.state = state

    -- Apply state-specific behaviors
    if state == SAMSIM_IADS.SamState.SUPPRESSED then
        SAMSIM_Utils.setGroupAlarmStateByName(node.groupName, SAMSIM_Utils.ALARM_STATE.GREEN)
        SAMSIM_Events.samSuppressed(node.groupName, 60)
    elseif state == SAMSIM_IADS.SamState.ACTIVE then
        SAMSIM_Utils.setGroupAlarmStateByName(node.groupName, SAMSIM_Utils.ALARM_STATE.RED)
        if oldState == SAMSIM_IADS.SamState.SUPPRESSED then
            SAMSIM_Events.samRecovered(node.groupName)
        end
    elseif state == SAMSIM_IADS.SamState.DARK then
        SAMSIM_Utils.setGroupAlarmStateByName(node.groupName, SAMSIM_Utils.ALARM_STATE.GREEN)
    end

    SAMSIM_Utils.debug("Site '%s' state: %s -> %s", node.groupName, oldState, state)
end

--- Get network status summary
---@param network table Network object
---@return table Status summary
function SAMSIM_IADS.getNetworkStatus(network)
    local status = {
        name = network.name,
        emcon = network.emconLevel,
        active = network.active,
        nodes = {
            total = SAMSIM_Utils.tableLength(network.nodes),
            ewrs = SAMSIM_Utils.tableLength(network.ewrs),
            sams = SAMSIM_Utils.tableLength(network.sams),
            commandPosts = SAMSIM_Utils.tableLength(network.commandPosts),
        },
        links = SAMSIM_Utils.tableLength(network.links),
        samStates = {
            dark = 0,
            active = 0,
            tracking = 0,
            engaging = 0,
            suppressed = 0,
            damaged = 0,
            destroyed = 0,
        },
        threats = SAMSIM_Utils.tableLength(network.sharedThreats),
        stats = network.stats,
    }

    -- Count SAM states
    for _, node in pairs(network.sams) do
        local stateKey = string.lower(node.state)
        if status.samStates[stateKey] then
            status.samStates[stateKey] = status.samStates[stateKey] + 1
        end
    end

    return status
end

-- ============================================================================
-- Backup Coverage
-- ============================================================================

--- Activate backup SAMs when a site is suppressed
---@param network table Network object
---@param suppressedNode table Suppressed SAM node
function SAMSIM_IADS.activateBackup(network, suppressedNode)
    if not network.settings.overkillPrevention then return end

    -- Find linked SAMs that can provide backup
    for linkedId in pairs(suppressedNode.links) do
        local linkedNode = network.nodes[linkedId]
        if linkedNode and
           linkedNode.type == SAMSIM_IADS.NodeType.SAM and
           linkedNode.state == SAMSIM_IADS.SamState.DARK then

            -- Check priority (lower priority = backup)
            if linkedNode.priority > suppressedNode.priority then
                SAMSIM_Utils.schedule(function()
                    if linkedNode.state == SAMSIM_IADS.SamState.DARK then
                        SAMSIM_IADS.setSiteState(linkedNode, SAMSIM_IADS.SamState.ACTIVE)
                        SAMSIM_Utils.info("Backup site '%s' activated for suppressed '%s'",
                            linkedNode.groupName, suppressedNode.groupName)
                    end
                end, network.settings.backupActivationDelay)
            end
        end
    end
end

--- Deactivate backup SAMs when primary recovers
---@param network table Network object
---@param recoveredNode table Recovered SAM node
function SAMSIM_IADS.deactivateBackup(network, recoveredNode)
    if not network.settings.overkillPrevention then return end

    -- Find backup SAMs
    for linkedId in pairs(recoveredNode.links) do
        local linkedNode = network.nodes[linkedId]
        if linkedNode and
           linkedNode.type == SAMSIM_IADS.NodeType.SAM and
           linkedNode.priority > recoveredNode.priority and
           linkedNode.state == SAMSIM_IADS.SamState.ACTIVE then

            -- Deactivate backup after delay
            SAMSIM_Utils.schedule(function()
                if recoveredNode.state == SAMSIM_IADS.SamState.ACTIVE then
                    SAMSIM_IADS.setSiteState(linkedNode, SAMSIM_IADS.SamState.DARK)
                    SAMSIM_Utils.info("Backup site '%s' deactivated, primary '%s' recovered",
                        linkedNode.groupName, recoveredNode.groupName)
                end
            end, network.settings.backupDeactivationDelay)
        end
    end
end

-- ============================================================================
-- Threat Information Sharing
-- ============================================================================

--- Share threat information across network
---@param network table Network object
---@param threat table Threat data
---@param detectedBy string Node ID that detected the threat
function SAMSIM_IADS.shareThreat(network, threat, detectedBy)
    local threatId = threat.trackId or threat.unitName or tostring(threat)

    -- Update or create shared threat
    network.sharedThreats[threatId] = {
        threat = threat,
        detectedBy = detectedBy,
        shareTime = SAMSIM_Utils.getTime(),
    }

    -- Propagate to linked nodes
    local sourceNode = network.nodes[detectedBy]
    if sourceNode then
        for linkedId in pairs(sourceNode.links) do
            local linkedNode = network.nodes[linkedId]
            if linkedNode and linkedNode.type == SAMSIM_IADS.NodeType.SAM then
                -- Add threat to node's track list
                linkedNode.tracks[threatId] = threat
            end
        end
    end
end

--- Get shared threats for a site
---@param node table SAM node
---@return table Array of threats
function SAMSIM_IADS.getSharedThreats(node)
    return node.tracks or {}
end

--- Clean up old shared threats
---@param network table Network object
function SAMSIM_IADS.cleanupSharedThreats(network)
    local now = SAMSIM_Utils.getTime()
    local timeout = network.settings.threatTrackTimeout or 30

    for threatId, data in pairs(network.sharedThreats) do
        if now - data.shareTime > timeout then
            network.sharedThreats[threatId] = nil

            -- Remove from all nodes
            for _, node in pairs(network.sams) do
                node.tracks[threatId] = nil
            end
        end
    end
end

-- ============================================================================
-- Node Health Check
-- ============================================================================

--- Check health of all nodes in network
---@param network table Network object
function SAMSIM_IADS.checkNodeHealth(network)
    for nodeId, node in pairs(network.nodes) do
        local alive = SAMSIM_Utils.isGroupAlive(node.groupName)

        if node.alive and not alive then
            -- Node just died
            node.alive = false
            node.state = SAMSIM_IADS.SamState.DESTROYED
            network.stats.losses = network.stats.losses + 1

            SAMSIM_Events.fire(SAMSIM_Events.Type.SAM_DESTROYED, {
                networkName = network.name,
                nodeId = nodeId,
                groupName = node.groupName,
            })

            -- Activate backup
            if node.type == SAMSIM_IADS.NodeType.SAM then
                SAMSIM_IADS.activateBackup(network, node)
            end

            SAMSIM_Utils.warn("Network '%s': Node '%s' destroyed", network.name, node.groupName)
        end

        -- Update position
        if alive then
            node.position = SAMSIM_Utils.getGroupPosition(node.groupName)
        end
    end
end

-- ============================================================================
-- Update Loop
-- ============================================================================

--- Main update function for a network
---@param network table Network object
function SAMSIM_IADS.update(network)
    if not network.active then return end

    -- Check node health
    SAMSIM_IADS.checkNodeHealth(network)

    -- Cleanup old threats
    SAMSIM_IADS.cleanupSharedThreats(network)

    -- Check suppression timeouts
    local now = SAMSIM_Utils.getTime()
    for _, node in pairs(network.sams) do
        if node.state == SAMSIM_IADS.SamState.SUPPRESSED and
           node.suppressedUntil > 0 and
           now >= node.suppressedUntil then
            -- Recover from suppression
            node.suppressedUntil = 0
            SAMSIM_IADS.setSiteState(node, SAMSIM_IADS.SamState.ACTIVE)
            SAMSIM_IADS.deactivateBackup(network, node)
        end
    end

    node.lastUpdate = now
end

--- Start network update loop
---@param network table Network object
---@param interval number|nil Update interval (default from settings)
function SAMSIM_IADS.startUpdateLoop(network, interval)
    interval = interval or network.settings.networkSyncInterval

    network.updateTaskId = SAMSIM_Utils.scheduleRepeat(function()
        SAMSIM_IADS.update(network)
    end, interval)

    SAMSIM_Utils.info("Network '%s' update loop started (%.1fs interval)", network.name, interval)
end

--- Stop network update loop
---@param network table Network object
function SAMSIM_IADS.stopUpdateLoop(network)
    if network.updateTaskId then
        SAMSIM_Utils.cancel(network.updateTaskId)
        network.updateTaskId = nil
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

function SAMSIM_IADS.init()
    SAMSIM_Utils.info("SAMSIM_IADS v%s initialized", SAMSIM_IADS.Version)
    return true
end

return SAMSIM_IADS
