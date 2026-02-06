--[[
    SAMSIM Threat Management Module
    Threat detection, tracking, and information sharing

    Author: Claude Code
    Version: 1.0.0
]]

SAMSIM_Threat = {}
SAMSIM_Threat.Version = "1.0.0"

-- ============================================================================
-- Threat Categories
-- ============================================================================
SAMSIM_Threat.Category = {
    UNKNOWN = "UNKNOWN",
    FIGHTER = "FIGHTER",
    ATTACK = "ATTACK",
    BOMBER = "BOMBER",
    SEAD = "SEAD",
    HELICOPTER = "HELICOPTER",
    UAV = "UAV",
    CRUISE_MISSILE = "CRUISE_MISSILE",
    ARM = "ARM",
    JAMMER = "JAMMER",
}

-- ============================================================================
-- Priority Levels (1 = highest threat)
-- ============================================================================
SAMSIM_Threat.Priority = {
    IMMEDIATE = 1,    -- ARM, active SEAD
    HIGH = 2,         -- Attack aircraft, bombers
    MEDIUM = 3,       -- Fighters
    LOW = 4,          -- Helicopters, UAVs
    MINIMAL = 5,      -- Unknown, non-threat
}

-- ============================================================================
-- Track State
-- ============================================================================
SAMSIM_Threat.TrackState = {
    NEW = "NEW",
    TRACKING = "TRACKING",
    LOST = "LOST",
    DESTROYED = "DESTROYED",
}

-- ============================================================================
-- Tracks Registry
-- ============================================================================
SAMSIM_Threat.tracks = {}
SAMSIM_Threat.nextTrackId = 1
SAMSIM_Threat.updateTaskId = nil

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_Threat.Config = {
    trackTimeout = 30,           -- Seconds before track considered lost
    updateInterval = 2.0,        -- Track update interval
    cleanupInterval = 5.0,       -- Cleanup interval for old tracks
    maxTracks = 200,             -- Maximum tracked targets
    priorityUpdateInterval = 5,  -- Reprioritize interval
}

-- ============================================================================
-- Track Structure
-- ============================================================================

--- Create a new track
---@param unit table DCS Unit object
---@param detectedBy string Sensor/node that detected
---@return table Track object
function SAMSIM_Threat.createTrack(unit, detectedBy)
    if not unit or not unit:isExist() then
        return nil
    end

    local trackId = string.format("TRK_%04d", SAMSIM_Threat.nextTrackId)
    SAMSIM_Threat.nextTrackId = SAMSIM_Threat.nextTrackId + 1

    local unitName = unit:getName()
    local typeName = SAMSIM_Utils.getUnitTypeName(unit)
    local position = unit:getPoint()
    local velocity = unit:getVelocity()

    -- Classify target
    local category = SAMSIM_Threat.categorizeTarget(unit)
    local priority = SAMSIM_Threat.calculatePriority(category, position, velocity)

    local track = {
        id = trackId,
        unitName = unitName,
        typeName = typeName,
        category = category,
        priority = priority,
        state = SAMSIM_Threat.TrackState.NEW,

        -- Position data
        position = position,
        velocity = velocity,
        heading = SAMSIM_Threat.calculateHeading(velocity),
        altitude = position.y,
        speed = SAMSIM_Utils.vec3Mag(velocity),
        agl = SAMSIM_Utils.getAGL(position),

        -- Detection info
        detectedBy = {[detectedBy] = true},
        detectionCount = 1,

        -- Engagement info
        engagedBy = {},
        engagementCount = 0,

        -- Timing
        firstDetected = SAMSIM_Utils.getTime(),
        lastUpdate = SAMSIM_Utils.getTime(),
        lastSeen = SAMSIM_Utils.getTime(),

        -- History
        positionHistory = {},
        maxHistoryLength = 10,

        -- Flags
        lost = false,
        hostile = (unit:getCoalition() ~= coalition.side.NEUTRAL),
    }

    -- Store track
    SAMSIM_Threat.tracks[trackId] = track

    -- Fire event
    SAMSIM_Events.threatDetected(trackId, unitName, category, priority)

    SAMSIM_Utils.debug("Created track %s: %s (%s) P%d",
        trackId, unitName, category, priority)

    return track
end

-- ============================================================================
-- Target Classification
-- ============================================================================

--- Categorize a target by unit type
---@param unit table DCS Unit object
---@return string Category
function SAMSIM_Threat.categorizeTarget(unit)
    if not unit then return SAMSIM_Threat.Category.UNKNOWN end

    local typeName = SAMSIM_Utils.getUnitTypeName(unit)

    -- Check for SEAD aircraft first (highest priority)
    if SAMSIM_Config.isSEADCapable(typeName) then
        return SAMSIM_Threat.Category.SEAD
    end

    -- Check for jammers
    for _, jammerConfig in pairs(SAMSIM_Config.JammerTypes or {}) do
        for _, jamType in ipairs(jammerConfig.types or {}) do
            if string.find(typeName, jamType, 1, true) then
                return SAMSIM_Threat.Category.JAMMER
            end
        end
    end

    -- Check weapon - might be an ARM
    local category = unit:getCategory()
    if category == Object.Category.WEAPON then
        local weaponDesc = unit:getDesc()
        if weaponDesc and weaponDesc.category == Weapon.Category.MISSILE then
            -- Check if ARM
            local armConfig = SAMSIM_Config.getARMType(typeName)
            if armConfig then
                return SAMSIM_Threat.Category.ARM
            end
            return SAMSIM_Threat.Category.CRUISE_MISSILE
        end
    end

    -- Use config classification
    local configCategory = SAMSIM_Config.classifyAircraft(typeName)
    if configCategory ~= "UNKNOWN" then
        return configCategory
    end

    return SAMSIM_Threat.Category.UNKNOWN
end

--- Check if unit is SEAD-capable
---@param typeName string
---@return boolean
function SAMSIM_Threat.isSEADCapable(typeName)
    return SAMSIM_Config.isSEADCapable(typeName)
end

--- Check if unit is an ARM carrier
---@param typeName string
---@return boolean
function SAMSIM_Threat.isARMCarrier(typeName)
    -- Most SEAD aircraft can carry ARMs
    return SAMSIM_Threat.isSEADCapable(typeName)
end

-- ============================================================================
-- Priority Calculation
-- ============================================================================

--- Calculate threat priority
---@param category string Threat category
---@param position table Position {x, y, z}
---@param velocity table Velocity {x, y, z}
---@return number Priority (1-5)
function SAMSIM_Threat.calculatePriority(category, position, velocity)
    -- Base priority from category
    local basePriority = SAMSIM_Config.getThreatPriority(category)

    -- Modifiers based on behavior
    local modifier = 0

    -- Low altitude is more threatening
    local altitude = position.y
    if altitude < 100 then
        modifier = modifier - 1
    elseif altitude < 500 then
        modifier = modifier - 0.5
    elseif altitude > 10000 then
        modifier = modifier + 0.5
    end

    -- High speed is more threatening
    local speed = SAMSIM_Utils.vec3Mag(velocity)
    if speed > 300 then  -- > Mach 1
        modifier = modifier - 0.5
    elseif speed > 500 then  -- > Mach 1.5
        modifier = modifier - 1
    end

    -- Apply modifier and clamp
    local priority = math.floor(basePriority + modifier + 0.5)
    return math.max(1, math.min(5, priority))
end

--- Calculate heading from velocity
---@param velocity table {x, y, z}
---@return number Heading in degrees
function SAMSIM_Threat.calculateHeading(velocity)
    if not velocity then return 0 end
    local heading = math.deg(math.atan2(velocity.x, velocity.z))
    if heading < 0 then heading = heading + 360 end
    return heading
end

-- ============================================================================
-- Track Management
-- ============================================================================

--- Update a track with new data
---@param trackId string
---@return boolean Success
function SAMSIM_Threat.updateTrack(trackId)
    local track = SAMSIM_Threat.tracks[trackId]
    if not track then return false end

    local unit = SAMSIM_Utils.getUnitByName(track.unitName)

    if not unit or not unit:isExist() then
        -- Unit no longer exists
        track.state = SAMSIM_Threat.TrackState.DESTROYED
        track.lost = true
        return false
    end

    -- Update position data
    local oldPosition = track.position
    track.position = unit:getPoint()
    track.velocity = unit:getVelocity()
    track.heading = SAMSIM_Threat.calculateHeading(track.velocity)
    track.altitude = track.position.y
    track.speed = SAMSIM_Utils.vec3Mag(track.velocity)
    track.agl = SAMSIM_Utils.getAGL(track.position)
    track.lastUpdate = SAMSIM_Utils.getTime()
    track.lastSeen = track.lastUpdate

    -- Update state
    if track.state == SAMSIM_Threat.TrackState.NEW then
        track.state = SAMSIM_Threat.TrackState.TRACKING
    elseif track.state == SAMSIM_Threat.TrackState.LOST then
        track.state = SAMSIM_Threat.TrackState.TRACKING
        track.lost = false
    end

    -- Store position history
    if oldPosition then
        table.insert(track.positionHistory, 1, {
            position = oldPosition,
            time = track.lastUpdate,
        })
        -- Trim history
        while #track.positionHistory > track.maxHistoryLength do
            table.remove(track.positionHistory)
        end
    end

    -- Recalculate priority periodically
    if track.lastUpdate % SAMSIM_Threat.Config.priorityUpdateInterval < SAMSIM_Threat.Config.updateInterval then
        track.priority = SAMSIM_Threat.calculatePriority(
            track.category,
            track.position,
            track.velocity
        )
    end

    -- Fire update event
    SAMSIM_Events.fire(SAMSIM_Events.Type.THREAT_UPDATED, {
        trackId = trackId,
        position = track.position,
        velocity = track.velocity,
        priority = track.priority,
    })

    return true
end

--- Remove a track
---@param trackId string
function SAMSIM_Threat.removeTrack(trackId)
    local track = SAMSIM_Threat.tracks[trackId]
    if track then
        SAMSIM_Events.threatLost(trackId)
        SAMSIM_Threat.tracks[trackId] = nil
        SAMSIM_Utils.debug("Removed track %s", trackId)
    end
end

--- Cleanup lost and old tracks
function SAMSIM_Threat.cleanupLostTracks()
    local now = SAMSIM_Utils.getTime()
    local timeout = SAMSIM_Threat.Config.trackTimeout
    local toRemove = {}

    for trackId, track in pairs(SAMSIM_Threat.tracks) do
        -- Check if track is stale
        if now - track.lastSeen > timeout then
            track.state = SAMSIM_Threat.TrackState.LOST
            track.lost = true
            toRemove[#toRemove + 1] = trackId
        end

        -- Check if unit still exists
        local unit = SAMSIM_Utils.getUnitByName(track.unitName)
        if not unit or not unit:isExist() then
            track.state = SAMSIM_Threat.TrackState.DESTROYED
            toRemove[#toRemove + 1] = trackId
        end
    end

    -- Remove old tracks
    for _, trackId in ipairs(toRemove) do
        SAMSIM_Threat.removeTrack(trackId)
    end
end

-- ============================================================================
-- Detection Reporting
-- ============================================================================

--- Report a detection from a sensor
---@param unit table DCS Unit object
---@param detectedBy string Sensor/node ID
---@param network table|nil IADS network for sharing
---@return table Track object (new or existing)
function SAMSIM_Threat.reportDetection(unit, detectedBy, network)
    if not unit or not unit:isExist() then return nil end

    local unitName = unit:getName()

    -- Check if track already exists
    local existingTrack = SAMSIM_Threat.findTrackByUnit(unitName)

    if existingTrack then
        -- Update existing track
        existingTrack.detectedBy[detectedBy] = true
        existingTrack.detectionCount = existingTrack.detectionCount + 1
        existingTrack.lastSeen = SAMSIM_Utils.getTime()

        if existingTrack.lost then
            existingTrack.lost = false
            existingTrack.state = SAMSIM_Threat.TrackState.TRACKING
        end

        -- Share with network
        if network then
            SAMSIM_IADS.shareThreat(network, existingTrack, detectedBy)
        end

        return existingTrack
    else
        -- Create new track
        local track = SAMSIM_Threat.createTrack(unit, detectedBy)

        -- Share with network
        if network and track then
            SAMSIM_IADS.shareThreat(network, track, detectedBy)
        end

        return track
    end
end

--- Report that a track was lost by a sensor
---@param trackId string
---@param sensor string Sensor that lost track
function SAMSIM_Threat.reportLost(trackId, sensor)
    local track = SAMSIM_Threat.tracks[trackId]
    if not track then return end

    -- Remove sensor from detection list
    track.detectedBy[sensor] = nil
    track.detectionCount = SAMSIM_Utils.tableLength(track.detectedBy)

    -- If no sensors tracking, mark as lost
    if track.detectionCount == 0 then
        track.state = SAMSIM_Threat.TrackState.LOST
        track.lost = true
        SAMSIM_Events.threatLost(trackId)
    end
end

--- Report engagement of a track
---@param trackId string
---@param engagedBy string SAM site engaging
function SAMSIM_Threat.reportEngagement(trackId, engagedBy)
    local track = SAMSIM_Threat.tracks[trackId]
    if not track then return end

    track.engagedBy[engagedBy] = true
    track.engagementCount = SAMSIM_Utils.tableLength(track.engagedBy)
end

-- ============================================================================
-- Track Queries
-- ============================================================================

--- Find track by unit name
---@param unitName string
---@return table|nil Track
function SAMSIM_Threat.findTrackByUnit(unitName)
    for _, track in pairs(SAMSIM_Threat.tracks) do
        if track.unitName == unitName then
            return track
        end
    end
    return nil
end

--- Find track by track ID
---@param trackId string
---@return table|nil Track
function SAMSIM_Threat.getTrack(trackId)
    return SAMSIM_Threat.tracks[trackId]
end

--- Get all tracks by category
---@param category string
---@return table Array of tracks
function SAMSIM_Threat.getTracksByCategory(category)
    local result = {}
    for _, track in pairs(SAMSIM_Threat.tracks) do
        if track.category == category and not track.lost then
            result[#result + 1] = track
        end
    end
    return result
end

--- Get tracks by minimum priority
---@param maxPriority number Maximum priority value (lower = more important)
---@return table Array of tracks
function SAMSIM_Threat.getTracksByPriority(maxPriority)
    local result = {}
    for _, track in pairs(SAMSIM_Threat.tracks) do
        if track.priority <= maxPriority and not track.lost then
            result[#result + 1] = track
        end
    end

    -- Sort by priority
    table.sort(result, function(a, b)
        return a.priority < b.priority
    end)

    return result
end

--- Get nearest threat to a position
---@param position table {x, y, z}
---@return table|nil Nearest track
function SAMSIM_Threat.getNearestThreat(position)
    local nearest = nil
    local minDist = math.huge

    for _, track in pairs(SAMSIM_Threat.tracks) do
        if not track.lost then
            local dist = SAMSIM_Utils.getDistance3D(position, track.position)
            if dist < minDist then
                minDist = dist
                nearest = track
            end
        end
    end

    return nearest, minDist
end

--- Get all threats within range
---@param position table {x, y, z}
---@param range number Range in meters
---@return table Array of tracks with distance
function SAMSIM_Threat.getThreatsInRange(position, range)
    local result = {}

    for _, track in pairs(SAMSIM_Threat.tracks) do
        if not track.lost then
            local dist = SAMSIM_Utils.getDistance3D(position, track.position)
            if dist <= range then
                result[#result + 1] = {
                    track = track,
                    distance = dist,
                }
            end
        end
    end

    -- Sort by distance
    table.sort(result, function(a, b)
        return a.distance < b.distance
    end)

    return result
end

--- Get highest priority threats
---@param count number Number of threats to return
---@return table Array of tracks
function SAMSIM_Threat.getHighestPriorityThreats(count)
    local tracks = SAMSIM_Threat.getTracksByPriority(5)

    local result = {}
    for i = 1, math.min(count, #tracks) do
        result[i] = tracks[i]
    end

    return result
end

--- Get all active tracks
---@return table Array of tracks
function SAMSIM_Threat.getAllActiveTracks()
    local result = {}
    for _, track in pairs(SAMSIM_Threat.tracks) do
        if not track.lost then
            result[#result + 1] = track
        end
    end
    return result
end

-- ============================================================================
-- Engagement Management
-- ============================================================================

--- Mark track as engaged by SAM
---@param trackId string
---@param engagedBy string SAM identifier
function SAMSIM_Threat.markEngaged(trackId, engagedBy)
    local track = SAMSIM_Threat.tracks[trackId]
    if track then
        track.engagedBy[engagedBy] = SAMSIM_Utils.getTime()
        track.engagementCount = SAMSIM_Utils.tableLength(track.engagedBy)
    end
end

--- Mark track as disengaged
---@param trackId string
---@param samSite string SAM identifier
function SAMSIM_Threat.markDisengaged(trackId, samSite)
    local track = SAMSIM_Threat.tracks[trackId]
    if track then
        track.engagedBy[samSite] = nil
        track.engagementCount = SAMSIM_Utils.tableLength(track.engagedBy)
    end
end

--- Get units engaging a track
---@param trackId string
---@return table Array of SAM identifiers
function SAMSIM_Threat.getEngagingUnits(trackId)
    local track = SAMSIM_Threat.tracks[trackId]
    if track then
        return SAMSIM_Utils.tableKeys(track.engagedBy)
    end
    return {}
end

--- Check if track is being engaged
---@param trackId string
---@return boolean
function SAMSIM_Threat.isBeingEngaged(trackId)
    local track = SAMSIM_Threat.tracks[trackId]
    return track and track.engagementCount > 0
end

-- ============================================================================
-- Prediction
-- ============================================================================

--- Predict future position of track
---@param trackId string
---@param timeAhead number Seconds ahead
---@return table|nil Predicted position
function SAMSIM_Threat.predictPosition(trackId, timeAhead)
    local track = SAMSIM_Threat.tracks[trackId]
    if not track then return nil end

    -- Simple linear prediction
    return {
        x = track.position.x + track.velocity.x * timeAhead,
        y = track.position.y + track.velocity.y * timeAhead,
        z = track.position.z + track.velocity.z * timeAhead,
    }
end

--- Calculate intercept point
---@param trackId string
---@param interceptorPos table Interceptor position
---@param interceptorSpeed number Interceptor speed
---@return table|nil Intercept point, time
function SAMSIM_Threat.calculateIntercept(trackId, interceptorPos, interceptorSpeed)
    local track = SAMSIM_Threat.tracks[trackId]
    if not track then return nil end

    -- Distance to target
    local dist = SAMSIM_Utils.getDistance3D(interceptorPos, track.position)

    -- Estimate time to intercept
    local relativeSpeed = interceptorSpeed - track.speed
    if relativeSpeed <= 0 then
        return nil  -- Can't catch target
    end

    local timeToIntercept = dist / relativeSpeed

    -- Predict target position at intercept time
    local interceptPoint = SAMSIM_Threat.predictPosition(trackId, timeToIntercept)

    return interceptPoint, timeToIntercept
end

-- ============================================================================
-- Update Loop
-- ============================================================================

--- Update all tracks
function SAMSIM_Threat.updateAllTracks()
    for trackId in pairs(SAMSIM_Threat.tracks) do
        SAMSIM_Threat.updateTrack(trackId)
    end
end

--- Start threat tracking update loop
function SAMSIM_Threat.startUpdateLoop()
    if SAMSIM_Threat.updateTaskId then
        return  -- Already running
    end

    -- Update loop
    SAMSIM_Threat.updateTaskId = SAMSIM_Utils.scheduleRepeat(function()
        SAMSIM_Threat.updateAllTracks()
    end, SAMSIM_Threat.Config.updateInterval)

    -- Cleanup loop
    SAMSIM_Threat.cleanupTaskId = SAMSIM_Utils.scheduleRepeat(function()
        SAMSIM_Threat.cleanupLostTracks()
    end, SAMSIM_Threat.Config.cleanupInterval)

    SAMSIM_Utils.info("Threat tracking started (%.1fs update interval)",
        SAMSIM_Threat.Config.updateInterval)
end

--- Stop threat tracking
function SAMSIM_Threat.stopUpdateLoop()
    if SAMSIM_Threat.updateTaskId then
        SAMSIM_Utils.cancel(SAMSIM_Threat.updateTaskId)
        SAMSIM_Threat.updateTaskId = nil
    end
    if SAMSIM_Threat.cleanupTaskId then
        SAMSIM_Utils.cancel(SAMSIM_Threat.cleanupTaskId)
        SAMSIM_Threat.cleanupTaskId = nil
    end
end

-- ============================================================================
-- Statistics
-- ============================================================================

--- Get threat statistics
---@return table Statistics
function SAMSIM_Threat.getStatistics()
    local stats = {
        totalTracks = SAMSIM_Utils.tableLength(SAMSIM_Threat.tracks),
        activeTracks = 0,
        lostTracks = 0,
        destroyedTracks = 0,
        byCategory = {},
        byPriority = {0, 0, 0, 0, 0},
    }

    for _, track in pairs(SAMSIM_Threat.tracks) do
        -- State counts
        if track.lost then
            stats.lostTracks = stats.lostTracks + 1
        elseif track.state == SAMSIM_Threat.TrackState.DESTROYED then
            stats.destroyedTracks = stats.destroyedTracks + 1
        else
            stats.activeTracks = stats.activeTracks + 1
        end

        -- Category counts
        stats.byCategory[track.category] = (stats.byCategory[track.category] or 0) + 1

        -- Priority counts
        if not track.lost then
            stats.byPriority[track.priority] = stats.byPriority[track.priority] + 1
        end
    end

    return stats
end

-- ============================================================================
-- Initialization
-- ============================================================================

function SAMSIM_Threat.init()
    -- Clear existing tracks
    SAMSIM_Threat.tracks = {}
    SAMSIM_Threat.nextTrackId = 1

    SAMSIM_Utils.info("SAMSIM_Threat v%s initialized", SAMSIM_Threat.Version)
    return true
end

return SAMSIM_Threat
