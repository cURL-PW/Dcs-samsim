--[[
    SAMSIM Events Module
    Unified event handling for DCS World

    Author: Claude Code
    Version: 1.0.0
]]

SAMSIM_Events = {}
SAMSIM_Events.Version = "1.0.0"

-- ============================================================================
-- Event Types
-- ============================================================================
SAMSIM_Events.Type = {
    -- DCS Native Events (mapped)
    SHOT = "SHOT",
    HIT = "HIT",
    DEAD = "DEAD",
    CRASH = "CRASH",
    PILOT_DEAD = "PILOT_DEAD",
    BIRTH = "BIRTH",
    TAKEOFF = "TAKEOFF",
    LAND = "LAND",
    ENGINE_STARTUP = "ENGINE_STARTUP",
    ENGINE_SHUTDOWN = "ENGINE_SHUTDOWN",
    WEAPON_ADD = "WEAPON_ADD",

    -- SAMSIM Custom Events
    SAM_ACTIVATED = "SAM_ACTIVATED",
    SAM_DEACTIVATED = "SAM_DEACTIVATED",
    SAM_TRACKING = "SAM_TRACKING",
    SAM_TRACK_LOST = "SAM_TRACK_LOST",
    SAM_ENGAGED = "SAM_ENGAGED",
    SAM_SUPPRESSED = "SAM_SUPPRESSED",
    SAM_RECOVERED = "SAM_RECOVERED",
    SAM_DAMAGED = "SAM_DAMAGED",
    SAM_DESTROYED = "SAM_DESTROYED",

    -- Missile Events
    MISSILE_LAUNCHED = "MISSILE_LAUNCHED",
    MISSILE_GUIDANCE_ACTIVE = "MISSILE_GUIDANCE_ACTIVE",
    MISSILE_IMPACT = "MISSILE_IMPACT",
    MISSILE_MISS = "MISSILE_MISS",
    MISSILE_DESTROYED = "MISSILE_DESTROYED",

    -- ARM Events
    ARM_DETECTED = "ARM_DETECTED",
    ARM_LAUNCHED = "ARM_LAUNCHED",
    ARM_IMPACT = "ARM_IMPACT",
    ARM_MISS = "ARM_MISS",

    -- Threat Events
    THREAT_DETECTED = "THREAT_DETECTED",
    THREAT_UPDATED = "THREAT_UPDATED",
    THREAT_LOST = "THREAT_LOST",
    THREAT_DESTROYED = "THREAT_DESTROYED",

    -- IADS Events
    NETWORK_CREATED = "NETWORK_CREATED",
    NETWORK_EMCON = "NETWORK_EMCON",
    NODE_ADDED = "NODE_ADDED",
    NODE_REMOVED = "NODE_REMOVED",
    NODE_LINKED = "NODE_LINKED",
    NODE_UNLINKED = "NODE_UNLINKED",

    -- Sector Events
    SECTOR_CREATED = "SECTOR_CREATED",
    SECTOR_THREAT_LEVEL_CHANGED = "SECTOR_THREAT_LEVEL_CHANGED",
    SECTOR_COVERAGE_CHANGED = "SECTOR_COVERAGE_CHANGED",
}

-- Map DCS events to SAMSIM events
SAMSIM_Events.DCSEventMap = {
    [world.event.S_EVENT_SHOT] = SAMSIM_Events.Type.SHOT,
    [world.event.S_EVENT_HIT] = SAMSIM_Events.Type.HIT,
    [world.event.S_EVENT_DEAD] = SAMSIM_Events.Type.DEAD,
    [world.event.S_EVENT_CRASH] = SAMSIM_Events.Type.CRASH,
    [world.event.S_EVENT_PILOT_DEAD] = SAMSIM_Events.Type.PILOT_DEAD,
    [world.event.S_EVENT_BIRTH] = SAMSIM_Events.Type.BIRTH,
    [world.event.S_EVENT_TAKEOFF] = SAMSIM_Events.Type.TAKEOFF,
    [world.event.S_EVENT_LAND] = SAMSIM_Events.Type.LAND,
    [world.event.S_EVENT_ENGINE_STARTUP] = SAMSIM_Events.Type.ENGINE_STARTUP,
    [world.event.S_EVENT_ENGINE_SHUTDOWN] = SAMSIM_Events.Type.ENGINE_SHUTDOWN,
}

-- ============================================================================
-- Handler Registry
-- ============================================================================
SAMSIM_Events.handlers = {}
SAMSIM_Events.nextHandlerId = 1
SAMSIM_Events.initialized = false

-- ============================================================================
-- Handler Management
-- ============================================================================

--- Register an event handler
---@param eventType string Event type from SAMSIM_Events.Type
---@param handler function Handler function(eventData)
---@param priority number|nil Priority (lower = earlier, default 100)
---@return number Handler ID for removal
function SAMSIM_Events.addHandler(eventType, handler, priority)
    priority = priority or 100

    if not SAMSIM_Events.handlers[eventType] then
        SAMSIM_Events.handlers[eventType] = {}
    end

    local handlerId = SAMSIM_Events.nextHandlerId
    SAMSIM_Events.nextHandlerId = SAMSIM_Events.nextHandlerId + 1

    table.insert(SAMSIM_Events.handlers[eventType], {
        id = handlerId,
        handler = handler,
        priority = priority,
    })

    -- Sort by priority
    table.sort(SAMSIM_Events.handlers[eventType], function(a, b)
        return a.priority < b.priority
    end)

    return handlerId
end

--- Remove an event handler by ID
---@param eventType string
---@param handlerId number
---@return boolean Success
function SAMSIM_Events.removeHandler(eventType, handlerId)
    local handlers = SAMSIM_Events.handlers[eventType]
    if not handlers then return false end

    for i, entry in ipairs(handlers) do
        if entry.id == handlerId then
            table.remove(handlers, i)
            return true
        end
    end

    return false
end

--- Remove all handlers for an event type
---@param eventType string
function SAMSIM_Events.removeAllHandlers(eventType)
    SAMSIM_Events.handlers[eventType] = nil
end

--- Check if event type has handlers
---@param eventType string
---@return boolean
function SAMSIM_Events.hasHandlers(eventType)
    return SAMSIM_Events.handlers[eventType] ~= nil and
           #SAMSIM_Events.handlers[eventType] > 0
end

-- ============================================================================
-- Event Firing
-- ============================================================================

--- Fire a SAMSIM event
---@param eventType string Event type
---@param data table Event data
function SAMSIM_Events.fire(eventType, data)
    local handlers = SAMSIM_Events.handlers[eventType]
    if not handlers then return end

    -- Add metadata to event data
    local eventData = data or {}
    eventData.eventType = eventType
    eventData.time = SAMSIM_Utils and SAMSIM_Utils.getTime() or timer.getTime()

    -- Call all handlers
    for _, entry in ipairs(handlers) do
        local success, err = pcall(entry.handler, eventData)
        if not success then
            if SAMSIM_Utils then
                SAMSIM_Utils.error("Event handler error for %s: %s", eventType, tostring(err))
            end
        end
    end
end

-- ============================================================================
-- DCS Event Processing
-- ============================================================================

--- Process DCS native event
---@param event table DCS event object
function SAMSIM_Events.processDCSEvent(event)
    if not event then return end

    -- Map DCS event to SAMSIM event
    local eventType = SAMSIM_Events.DCSEventMap[event.id]
    if not eventType then return end

    -- Build event data
    local eventData = {
        id = event.id,
        time = event.time,
    }

    -- Extract initiator info
    if event.initiator then
        eventData.initiator = {
            name = event.initiator:getName(),
            typeName = event.initiator:getTypeName(),
            coalition = event.initiator:getCoalition(),
            position = event.initiator:getPoint(),
        }

        -- Get group info if available
        local group = event.initiator:getGroup()
        if group then
            eventData.initiator.groupName = group:getName()
        end
    end

    -- Extract target info
    if event.target then
        eventData.target = {
            name = event.target:getName(),
            typeName = event.target:getTypeName(),
            coalition = event.target:getCoalition(),
            position = event.target:getPoint(),
        }

        local group = event.target:getGroup()
        if group then
            eventData.target.groupName = group:getName()
        end
    end

    -- Extract weapon info for SHOT events
    if event.weapon then
        eventData.weapon = {
            typeName = event.weapon:getTypeName(),
            position = event.weapon:getPoint(),
        }

        -- Check if it's an ARM
        if SAMSIM_Config then
            local armConfig = SAMSIM_Config.getARMType(event.weapon:getTypeName())
            if armConfig then
                eventData.weapon.isARM = true
                eventData.weapon.armConfig = armConfig
            end
        end
    end

    -- Fire the mapped SAMSIM event
    SAMSIM_Events.fire(eventType, eventData)

    -- Special handling for specific events
    SAMSIM_Events.handleSpecialEvents(eventType, eventData)
end

--- Handle special event logic
---@param eventType string
---@param eventData table
function SAMSIM_Events.handleSpecialEvents(eventType, eventData)
    -- Handle ARM launch detection
    if eventType == SAMSIM_Events.Type.SHOT then
        if eventData.weapon and eventData.weapon.isARM then
            SAMSIM_Events.fire(SAMSIM_Events.Type.ARM_LAUNCHED, {
                weapon = eventData.weapon,
                initiator = eventData.initiator,
                target = eventData.target,
                launchPosition = eventData.initiator and eventData.initiator.position,
            })
        end
    end

    -- Handle unit death - check if it's a SAM component
    if eventType == SAMSIM_Events.Type.DEAD then
        if eventData.initiator then
            local typeName = eventData.initiator.typeName
            if SAMSIM_Config then
                local samConfig = SAMSIM_Config.getSAMTypeByUnit(typeName)
                if samConfig then
                    SAMSIM_Events.fire(SAMSIM_Events.Type.SAM_DAMAGED, {
                        unitName = eventData.initiator.name,
                        groupName = eventData.initiator.groupName,
                        typeName = typeName,
                        samType = samConfig,
                    })
                end
            end
        end
    end
end

-- ============================================================================
-- Weapon Tracking
-- ============================================================================

SAMSIM_Events.trackedWeapons = {}

--- Start tracking a weapon
---@param weapon table DCS weapon object
---@param data table Additional tracking data
function SAMSIM_Events.trackWeapon(weapon, data)
    if not weapon then return end

    local weaponId = tostring(weapon)
    SAMSIM_Events.trackedWeapons[weaponId] = {
        weapon = weapon,
        data = data or {},
        startTime = timer.getTime(),
        lastPosition = weapon:getPoint(),
    }
end

--- Update tracked weapons
function SAMSIM_Events.updateTrackedWeapons()
    local toRemove = {}

    for weaponId, trackData in pairs(SAMSIM_Events.trackedWeapons) do
        local weapon = trackData.weapon

        -- Check if weapon still exists
        if not weapon:isExist() then
            -- Weapon no longer exists - either hit or miss
            local eventType = SAMSIM_Events.Type.MISSILE_IMPACT
            if trackData.data.isARM then
                eventType = SAMSIM_Events.Type.ARM_IMPACT
            end

            SAMSIM_Events.fire(eventType, {
                weaponId = weaponId,
                lastPosition = trackData.lastPosition,
                flightTime = timer.getTime() - trackData.startTime,
                data = trackData.data,
            })

            toRemove[#toRemove + 1] = weaponId
        else
            -- Update position
            trackData.lastPosition = weapon:getPoint()

            -- Check for proximity to target (if tracking specific target)
            if trackData.data.targetPosition then
                local dist = SAMSIM_Utils.getDistance3D(
                    trackData.lastPosition,
                    trackData.data.targetPosition
                )

                if dist < 100 then  -- Within 100m
                    -- Consider it a hit
                    SAMSIM_Events.fire(SAMSIM_Events.Type.MISSILE_IMPACT, {
                        weaponId = weaponId,
                        position = trackData.lastPosition,
                        data = trackData.data,
                        hit = true,
                    })
                    toRemove[#toRemove + 1] = weaponId
                end
            end
        end
    end

    -- Remove finished weapons
    for _, weaponId in ipairs(toRemove) do
        SAMSIM_Events.trackedWeapons[weaponId] = nil
    end
end

-- ============================================================================
-- Convenience Event Shortcuts
-- ============================================================================

--- Fire SAM activated event
---@param groupName string
---@param samType string
function SAMSIM_Events.samActivated(groupName, samType)
    SAMSIM_Events.fire(SAMSIM_Events.Type.SAM_ACTIVATED, {
        groupName = groupName,
        samType = samType,
    })
end

--- Fire SAM deactivated event
---@param groupName string
---@param reason string|nil
function SAMSIM_Events.samDeactivated(groupName, reason)
    SAMSIM_Events.fire(SAMSIM_Events.Type.SAM_DEACTIVATED, {
        groupName = groupName,
        reason = reason,
    })
end

--- Fire SAM tracking event
---@param groupName string
---@param targetName string
function SAMSIM_Events.samTracking(groupName, targetName)
    SAMSIM_Events.fire(SAMSIM_Events.Type.SAM_TRACKING, {
        groupName = groupName,
        targetName = targetName,
    })
end

--- Fire SAM suppressed event
---@param groupName string
---@param duration number Expected suppression duration
function SAMSIM_Events.samSuppressed(groupName, duration)
    SAMSIM_Events.fire(SAMSIM_Events.Type.SAM_SUPPRESSED, {
        groupName = groupName,
        duration = duration,
    })
end

--- Fire SAM recovered event
---@param groupName string
function SAMSIM_Events.samRecovered(groupName)
    SAMSIM_Events.fire(SAMSIM_Events.Type.SAM_RECOVERED, {
        groupName = groupName,
    })
end

--- Fire threat detected event
---@param trackId string
---@param unitName string
---@param category string
---@param priority number
function SAMSIM_Events.threatDetected(trackId, unitName, category, priority)
    SAMSIM_Events.fire(SAMSIM_Events.Type.THREAT_DETECTED, {
        trackId = trackId,
        unitName = unitName,
        category = category,
        priority = priority,
    })
end

--- Fire threat lost event
---@param trackId string
function SAMSIM_Events.threatLost(trackId)
    SAMSIM_Events.fire(SAMSIM_Events.Type.THREAT_LOST, {
        trackId = trackId,
    })
end

--- Fire EMCON change event
---@param networkName string
---@param level string
---@param reason string|nil
function SAMSIM_Events.networkEMCON(networkName, level, reason)
    SAMSIM_Events.fire(SAMSIM_Events.Type.NETWORK_EMCON, {
        networkName = networkName,
        level = level,
        reason = reason,
    })
end

-- ============================================================================
-- DCS Event Handler Object
-- ============================================================================

SAMSIM_Events.dcsEventHandler = {
    onEvent = function(self, event)
        SAMSIM_Events.processDCSEvent(event)
    end
}

-- ============================================================================
-- Initialization
-- ============================================================================

--- Initialize the event system
function SAMSIM_Events.init()
    if SAMSIM_Events.initialized then
        return true
    end

    -- Register with DCS world events
    if world and world.addEventHandler then
        world.addEventHandler(SAMSIM_Events.dcsEventHandler)
    end

    -- Start weapon tracking update loop
    if SAMSIM_Utils then
        SAMSIM_Utils.scheduleRepeat(SAMSIM_Events.updateTrackedWeapons, 0.5)
    elseif timer then
        local function updateLoop(_, time)
            SAMSIM_Events.updateTrackedWeapons()
            return time + 0.5
        end
        timer.scheduleFunction(updateLoop, nil, timer.getTime() + 0.5)
    end

    SAMSIM_Events.initialized = true

    if SAMSIM_Utils then
        SAMSIM_Utils.info("SAMSIM_Events v%s initialized", SAMSIM_Events.Version)
    end

    return true
end

--- Shutdown the event system
function SAMSIM_Events.shutdown()
    if world and world.removeEventHandler then
        world.removeEventHandler(SAMSIM_Events.dcsEventHandler)
    end

    SAMSIM_Events.handlers = {}
    SAMSIM_Events.trackedWeapons = {}
    SAMSIM_Events.initialized = false
end

return SAMSIM_Events
