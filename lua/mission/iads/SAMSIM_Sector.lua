--[[
    SAMSIM Sector Management Module
    Geographic sector organization for coordinated air defense

    Author: Claude Code
    Version: 1.0.0
]]

SAMSIM_Sector = {}
SAMSIM_Sector.Version = "1.0.0"

-- ============================================================================
-- Sector Types
-- ============================================================================
SAMSIM_Sector.Type = {
    POINT = "POINT",           -- Circular (center + radius)
    POLYGON = "POLYGON",       -- Polygon vertices
    ZONE = "ZONE",             -- DCS trigger zone
}

-- ============================================================================
-- Threat Levels
-- ============================================================================
SAMSIM_Sector.ThreatLevel = {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    CRITICAL = 4,
}

-- ============================================================================
-- Coverage Modes
-- ============================================================================
SAMSIM_Sector.CoverageMode = {
    MINIMUM = "MINIMUM",       -- Only priority 1 SAMs active
    PARTIAL = "PARTIAL",       -- Priority 1-2 SAMs active
    FULL = "FULL",             -- All SAMs active
    ADAPTIVE = "ADAPTIVE",     -- Based on threat level
}

-- ============================================================================
-- Sectors Registry
-- ============================================================================
SAMSIM_Sector.sectors = {}

-- ============================================================================
-- Sector Creation
-- ============================================================================

--- Create a circular sector
---@param name string Sector name
---@param center table Center position {x, y, z}
---@param radius number Radius in meters
---@param options table|nil Additional options
---@return table Sector object
function SAMSIM_Sector.createCircular(name, center, radius, options)
    options = options or {}

    local sector = {
        id = string.format("SEC_%s_%d", name, os.time()),
        name = name,
        type = SAMSIM_Sector.Type.POINT,

        -- Bounds
        center = center,
        radius = radius,

        -- SAMs and EWRs
        sams = {},             -- {samId = {node, priority}}
        ewrs = {},

        -- Threat management
        threatLevel = SAMSIM_Sector.ThreatLevel.NONE,
        threats = {},          -- Threats currently in sector

        -- Coverage
        coverageMode = options.coverageMode or SAMSIM_Sector.CoverageMode.ADAPTIVE,
        activeCount = 0,

        -- Settings
        settings = SAMSIM_Utils.mergeTables(SAMSIM_Config.SectorDefaults, options.settings or {}),

        -- Statistics
        stats = {
            created = SAMSIM_Utils.getTime(),
            engagements = 0,
            activations = 0,
        },
    }

    SAMSIM_Sector.sectors[sector.id] = sector

    SAMSIM_Events.fire(SAMSIM_Events.Type.SECTOR_CREATED, {
        sectorId = sector.id,
        name = name,
        type = sector.type,
    })

    SAMSIM_Utils.info("Created circular sector '%s' (radius: %.0fm)", name, radius)

    return sector
end

--- Create a polygon sector
---@param name string Sector name
---@param vertices table Array of {x, z} positions
---@param options table|nil Additional options
---@return table Sector object
function SAMSIM_Sector.createPolygon(name, vertices, options)
    options = options or {}

    -- Calculate center from vertices
    local centerX, centerZ = 0, 0
    for _, v in ipairs(vertices) do
        centerX = centerX + v.x
        centerZ = centerZ + v.z
    end
    centerX = centerX / #vertices
    centerZ = centerZ / #vertices

    -- Calculate approximate radius (distance to farthest vertex)
    local maxRadius = 0
    for _, v in ipairs(vertices) do
        local dist = math.sqrt((v.x - centerX)^2 + (v.z - centerZ)^2)
        if dist > maxRadius then
            maxRadius = dist
        end
    end

    local sector = {
        id = string.format("SEC_%s_%d", name, os.time()),
        name = name,
        type = SAMSIM_Sector.Type.POLYGON,

        -- Bounds
        vertices = vertices,
        center = {x = centerX, y = 0, z = centerZ},
        radius = maxRadius,  -- Approximate for quick checks

        -- SAMs and EWRs
        sams = {},
        ewrs = {},

        -- Threat management
        threatLevel = SAMSIM_Sector.ThreatLevel.NONE,
        threats = {},

        -- Coverage
        coverageMode = options.coverageMode or SAMSIM_Sector.CoverageMode.ADAPTIVE,
        activeCount = 0,

        -- Settings
        settings = SAMSIM_Utils.mergeTables(SAMSIM_Config.SectorDefaults, options.settings or {}),

        -- Statistics
        stats = {
            created = SAMSIM_Utils.getTime(),
            engagements = 0,
            activations = 0,
        },
    }

    SAMSIM_Sector.sectors[sector.id] = sector

    SAMSIM_Events.fire(SAMSIM_Events.Type.SECTOR_CREATED, {
        sectorId = sector.id,
        name = name,
        type = sector.type,
    })

    SAMSIM_Utils.info("Created polygon sector '%s' (%d vertices)", name, #vertices)

    return sector
end

--- Create sector from DCS trigger zone
---@param zoneName string DCS trigger zone name
---@param options table|nil Additional options
---@return table|nil Sector object
function SAMSIM_Sector.createFromZone(zoneName, options)
    -- Get zone from DCS
    local zone = trigger.misc.getZone(zoneName)
    if not zone then
        SAMSIM_Utils.warn("Trigger zone '%s' not found", zoneName)
        return nil
    end

    options = options or {}

    local sector = {
        id = string.format("SEC_%s_%d", zoneName, os.time()),
        name = zoneName,
        type = SAMSIM_Sector.Type.ZONE,

        -- Bounds from zone
        zoneName = zoneName,
        center = zone.point,
        radius = zone.radius,

        -- SAMs and EWRs
        sams = {},
        ewrs = {},

        -- Threat management
        threatLevel = SAMSIM_Sector.ThreatLevel.NONE,
        threats = {},

        -- Coverage
        coverageMode = options.coverageMode or SAMSIM_Sector.CoverageMode.ADAPTIVE,
        activeCount = 0,

        -- Settings
        settings = SAMSIM_Utils.mergeTables(SAMSIM_Config.SectorDefaults, options.settings or {}),

        -- Statistics
        stats = {
            created = SAMSIM_Utils.getTime(),
            engagements = 0,
            activations = 0,
        },
    }

    SAMSIM_Sector.sectors[sector.id] = sector

    SAMSIM_Events.fire(SAMSIM_Events.Type.SECTOR_CREATED, {
        sectorId = sector.id,
        name = zoneName,
        type = sector.type,
    })

    SAMSIM_Utils.info("Created sector from zone '%s' (radius: %.0fm)", zoneName, zone.radius)

    return sector
end

-- ============================================================================
-- SAM Management
-- ============================================================================

--- Add SAM to sector
---@param sector table Sector object
---@param samNode table SAM node from IADS
---@param priority number|nil Priority (1=primary, 2=secondary, 3=backup)
function SAMSIM_Sector.addSAM(sector, samNode, priority)
    priority = priority or 2

    sector.sams[samNode.id] = {
        node = samNode,
        priority = priority,
        active = false,
        addedAt = SAMSIM_Utils.getTime(),
    }

    SAMSIM_Utils.debug("Added SAM '%s' to sector '%s' (priority %d)",
        samNode.groupName, sector.name, priority)

    -- Apply current coverage mode
    SAMSIM_Sector.applyCoverageMode(sector)
end

--- Remove SAM from sector
---@param sector table Sector object
---@param samNode table SAM node
function SAMSIM_Sector.removeSAM(sector, samNode)
    sector.sams[samNode.id] = nil
    SAMSIM_Utils.debug("Removed SAM '%s' from sector '%s'", samNode.groupName, sector.name)
end

--- Get SAMs by priority
---@param sector table Sector object
---@return table Array of SAM entries sorted by priority
function SAMSIM_Sector.getSAMsByPriority(sector)
    local result = {}
    for _, samEntry in pairs(sector.sams) do
        result[#result + 1] = samEntry
    end

    table.sort(result, function(a, b)
        return a.priority < b.priority
    end)

    return result
end

--- Add EWR to sector
---@param sector table Sector object
---@param ewrNode table EWR node from IADS
function SAMSIM_Sector.addEWR(sector, ewrNode)
    sector.ewrs[ewrNode.id] = {
        node = ewrNode,
        addedAt = SAMSIM_Utils.getTime(),
    }
end

-- ============================================================================
-- Threat Management
-- ============================================================================

--- Update sector threat level
---@param sector table Sector object
---@return number New threat level
function SAMSIM_Sector.updateThreatLevel(sector)
    local threats = SAMSIM_Sector.getThreatsInSector(sector)
    local highestPriority = 5

    -- Find highest priority threat
    for _, threat in ipairs(threats) do
        if threat.priority < highestPriority then
            highestPriority = threat.priority
        end
    end

    -- Map priority to threat level
    local oldLevel = sector.threatLevel
    local newLevel

    if #threats == 0 then
        newLevel = SAMSIM_Sector.ThreatLevel.NONE
    elseif highestPriority == 1 then
        newLevel = SAMSIM_Sector.ThreatLevel.CRITICAL
    elseif highestPriority == 2 then
        newLevel = SAMSIM_Sector.ThreatLevel.HIGH
    elseif highestPriority == 3 then
        newLevel = SAMSIM_Sector.ThreatLevel.MEDIUM
    else
        newLevel = SAMSIM_Sector.ThreatLevel.LOW
    end

    if newLevel ~= oldLevel then
        sector.threatLevel = newLevel
        sector.threats = threats

        SAMSIM_Events.fire(SAMSIM_Events.Type.SECTOR_THREAT_LEVEL_CHANGED, {
            sectorId = sector.id,
            sectorName = sector.name,
            oldLevel = oldLevel,
            newLevel = newLevel,
            threatCount = #threats,
        })

        SAMSIM_Utils.debug("Sector '%s' threat level: %d -> %d (%d threats)",
            sector.name, oldLevel, newLevel, #threats)

        -- Update coverage if adaptive
        if sector.coverageMode == SAMSIM_Sector.CoverageMode.ADAPTIVE then
            SAMSIM_Sector.adaptiveCoverage(sector)
        end
    end

    return newLevel
end

--- Get current threat level
---@param sector table Sector object
---@return number Threat level
function SAMSIM_Sector.getThreatLevel(sector)
    return sector.threatLevel
end

--- Get threats currently in sector
---@param sector table Sector object
---@return table Array of threats
function SAMSIM_Sector.getThreatsInSector(sector)
    local threats = {}

    for _, track in pairs(SAMSIM_Threat.tracks) do
        if not track.lost and SAMSIM_Sector.isPointInSector(sector, track.position) then
            threats[#threats + 1] = track
        end
    end

    return threats
end

-- ============================================================================
-- Position Checks
-- ============================================================================

--- Check if point is inside sector
---@param sector table Sector object
---@param point table Position {x, y, z}
---@return boolean
function SAMSIM_Sector.isPointInSector(sector, point)
    if not point then return false end

    if sector.type == SAMSIM_Sector.Type.POINT or sector.type == SAMSIM_Sector.Type.ZONE then
        -- Circular check
        return SAMSIM_Utils.pointInCircle(point, sector.center, sector.radius)

    elseif sector.type == SAMSIM_Sector.Type.POLYGON then
        -- Quick radius check first
        if not SAMSIM_Utils.pointInCircle(point, sector.center, sector.radius) then
            return false
        end
        -- Full polygon check
        return SAMSIM_Utils.pointInPolygon(point, sector.vertices)
    end

    return false
end

--- Find sector containing a point
---@param point table Position {x, y, z}
---@return table|nil Sector
function SAMSIM_Sector.getSectorForPoint(point)
    for _, sector in pairs(SAMSIM_Sector.sectors) do
        if SAMSIM_Sector.isPointInSector(sector, point) then
            return sector
        end
    end
    return nil
end

--- Get all sectors containing a point
---@param point table Position {x, y, z}
---@return table Array of sectors
function SAMSIM_Sector.getSectorsForPoint(point)
    local result = {}
    for _, sector in pairs(SAMSIM_Sector.sectors) do
        if SAMSIM_Sector.isPointInSector(sector, point) then
            result[#result + 1] = sector
        end
    end
    return result
end

-- ============================================================================
-- Coverage Control
-- ============================================================================

--- Set minimum coverage (priority 1 only)
---@param sector table Sector object
function SAMSIM_Sector.setMinimumCoverage(sector)
    sector.coverageMode = SAMSIM_Sector.CoverageMode.MINIMUM
    SAMSIM_Sector.applyCoverageMode(sector)
end

--- Set partial coverage (priority 1-2)
---@param sector table Sector object
function SAMSIM_Sector.setPartialCoverage(sector)
    sector.coverageMode = SAMSIM_Sector.CoverageMode.PARTIAL
    SAMSIM_Sector.applyCoverageMode(sector)
end

--- Set full coverage (all SAMs)
---@param sector table Sector object
function SAMSIM_Sector.setFullCoverage(sector)
    sector.coverageMode = SAMSIM_Sector.CoverageMode.FULL
    SAMSIM_Sector.applyCoverageMode(sector)
end

--- Set adaptive coverage (threat-based)
---@param sector table Sector object
function SAMSIM_Sector.setAdaptiveCoverage(sector)
    sector.coverageMode = SAMSIM_Sector.CoverageMode.ADAPTIVE
    SAMSIM_Sector.adaptiveCoverage(sector)
end

--- Apply current coverage mode
---@param sector table Sector object
function SAMSIM_Sector.applyCoverageMode(sector)
    local mode = sector.coverageMode
    local activeCount = 0

    for _, samEntry in pairs(sector.sams) do
        local shouldBeActive = false

        if mode == SAMSIM_Sector.CoverageMode.FULL then
            shouldBeActive = true
        elseif mode == SAMSIM_Sector.CoverageMode.PARTIAL then
            shouldBeActive = samEntry.priority <= 2
        elseif mode == SAMSIM_Sector.CoverageMode.MINIMUM then
            shouldBeActive = samEntry.priority == 1
        end

        -- Apply state
        if shouldBeActive and not samEntry.active then
            samEntry.active = true
            SAMSIM_IADS.setSiteState(samEntry.node, SAMSIM_IADS.SamState.ACTIVE)
            activeCount = activeCount + 1
        elseif not shouldBeActive and samEntry.active then
            samEntry.active = false
            SAMSIM_IADS.setSiteState(samEntry.node, SAMSIM_IADS.SamState.DARK)
        elseif samEntry.active then
            activeCount = activeCount + 1
        end
    end

    if sector.activeCount ~= activeCount then
        sector.activeCount = activeCount
        sector.stats.activations = sector.stats.activations + 1

        SAMSIM_Events.fire(SAMSIM_Events.Type.SECTOR_COVERAGE_CHANGED, {
            sectorId = sector.id,
            sectorName = sector.name,
            coverageMode = mode,
            activeCount = activeCount,
        })
    end
end

--- Apply adaptive coverage based on threat level
---@param sector table Sector object
function SAMSIM_Sector.adaptiveCoverage(sector)
    local threatLevel = sector.threatLevel

    -- Map threat level to coverage
    if threatLevel == SAMSIM_Sector.ThreatLevel.NONE then
        SAMSIM_Sector.setMinimumCoverage(sector)
    elseif threatLevel == SAMSIM_Sector.ThreatLevel.LOW then
        SAMSIM_Sector.setMinimumCoverage(sector)
    elseif threatLevel == SAMSIM_Sector.ThreatLevel.MEDIUM then
        SAMSIM_Sector.setPartialCoverage(sector)
    elseif threatLevel >= SAMSIM_Sector.ThreatLevel.HIGH then
        SAMSIM_Sector.setFullCoverage(sector)
    end

    -- Reset mode to adaptive after applying
    sector.coverageMode = SAMSIM_Sector.CoverageMode.ADAPTIVE
end

-- ============================================================================
-- Status
-- ============================================================================

--- Get sector status
---@param sector table Sector object
---@return table Status summary
function SAMSIM_Sector.getStatus(sector)
    return {
        id = sector.id,
        name = sector.name,
        type = sector.type,
        threatLevel = sector.threatLevel,
        coverageMode = sector.coverageMode,
        sams = {
            total = SAMSIM_Utils.tableLength(sector.sams),
            active = sector.activeCount,
        },
        ewrs = SAMSIM_Utils.tableLength(sector.ewrs),
        threats = #(sector.threats or {}),
        stats = sector.stats,
    }
end

--- Get all sectors status
---@return table Array of status summaries
function SAMSIM_Sector.getAllSectorsStatus()
    local result = {}
    for _, sector in pairs(SAMSIM_Sector.sectors) do
        result[#result + 1] = SAMSIM_Sector.getStatus(sector)
    end
    return result
end

-- ============================================================================
-- Sector Relationships
-- ============================================================================

--- Find adjacent sectors (overlapping or within distance)
---@param sector table Sector object
---@param maxDistance number|nil Maximum distance for adjacency
---@return table Array of adjacent sectors
function SAMSIM_Sector.getAdjacentSectors(sector, maxDistance)
    maxDistance = maxDistance or (sector.radius * 2)
    local result = {}

    for _, otherSector in pairs(SAMSIM_Sector.sectors) do
        if otherSector.id ~= sector.id then
            local dist = SAMSIM_Utils.getDistance2D(sector.center, otherSector.center)
            if dist <= maxDistance then
                result[#result + 1] = otherSector
            end
        end
    end

    return result
end

--- Check if sectors overlap
---@param sector1 table First sector
---@param sector2 table Second sector
---@return boolean
function SAMSIM_Sector.doSectorsOverlap(sector1, sector2)
    local dist = SAMSIM_Utils.getDistance2D(sector1.center, sector2.center)
    return dist < (sector1.radius + sector2.radius)
end

-- ============================================================================
-- Auto-Assignment
-- ============================================================================

--- Auto-assign SAMs to sector based on position
---@param sector table Sector object
---@param network table IADS network
---@return number Number of SAMs assigned
function SAMSIM_Sector.autoAssignSAMs(sector, network)
    local count = 0

    for _, samNode in pairs(network.sams) do
        if samNode.position and SAMSIM_Sector.isPointInSector(sector, samNode.position) then
            -- Calculate priority based on distance from center
            local dist = SAMSIM_Utils.getDistance2D(samNode.position, sector.center)
            local priority

            if dist < sector.radius * 0.3 then
                priority = 1  -- Core
            elseif dist < sector.radius * 0.6 then
                priority = 2  -- Middle
            else
                priority = 3  -- Outer
            end

            SAMSIM_Sector.addSAM(sector, samNode, priority)
            count = count + 1
        end
    end

    -- Auto-assign EWRs
    for _, ewrNode in pairs(network.ewrs) do
        if ewrNode.position and SAMSIM_Sector.isPointInSector(sector, ewrNode.position) then
            SAMSIM_Sector.addEWR(sector, ewrNode)
        end
    end

    SAMSIM_Utils.info("Auto-assigned %d SAMs to sector '%s'", count, sector.name)

    return count
end

-- ============================================================================
-- Update Loop
-- ============================================================================

--- Update all sectors
function SAMSIM_Sector.updateAll()
    for _, sector in pairs(SAMSIM_Sector.sectors) do
        SAMSIM_Sector.updateThreatLevel(sector)
    end
end

--- Start sector update loop
---@param interval number|nil Update interval
function SAMSIM_Sector.startUpdateLoop(interval)
    interval = interval or 3.0

    SAMSIM_Sector.updateTaskId = SAMSIM_Utils.scheduleRepeat(function()
        SAMSIM_Sector.updateAll()
    end, interval)

    SAMSIM_Utils.info("Sector management started (%.1fs interval)", interval)
end

--- Stop sector update loop
function SAMSIM_Sector.stopUpdateLoop()
    if SAMSIM_Sector.updateTaskId then
        SAMSIM_Utils.cancel(SAMSIM_Sector.updateTaskId)
        SAMSIM_Sector.updateTaskId = nil
    end
end

-- ============================================================================
-- Initialization
-- ============================================================================

function SAMSIM_Sector.init()
    SAMSIM_Sector.sectors = {}
    SAMSIM_Utils.info("SAMSIM_Sector v%s initialized", SAMSIM_Sector.Version)
    return true
end

return SAMSIM_Sector
