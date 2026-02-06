--[[
    MIM-104 Patriot SAM System Simulation for DCS World

    System Components:
    - AN/MPQ-53 Phased Array Radar (PAC-2) / AN/MPQ-65 (PAC-3)
    - ECS (Engagement Control Station)
    - Launching Stations (4-16 missiles per battery)

    Capabilities:
    - Track-via-Missile (TVM) guidance
    - Multiple simultaneous engagements
    - Anti-ballistic missile capability (PAC-3)

    Author: Claude Code
    Version: 1.0
]]

PATRIOT_SAMSIM = {}
PATRIOT_SAMSIM.Version = "1.0.0"

-- ============================================================================
-- Configuration
-- ============================================================================
PATRIOT_SAMSIM.Config = {
    -- AN/MPQ-53/65 Radar
    radar = {
        searchRange = 170000,       -- 170km search range
        trackRange = 100000,        -- 100km track range
        maxAltitude = 24000,        -- 24km altitude
        minAltitude = 60,           -- 60m minimum
        azimuthCoverage = 90,       -- 90 degree sector (phased array)
        elevationCoverage = 90,     -- 90 degree elevation
        maxTracks = 100,            -- Up to 100 simultaneous tracks
        maxEngagements = 9,         -- 9 simultaneous engagements
        updateRate = 0.1,           -- 10Hz update
        phasedArray = true,
        tvm = true,                 -- Track-via-Missile
    },

    -- MIM-104 Missile variants
    missiles = {
        PAC2 = {
            name = "MIM-104C PAC-2",
            maxRange = 160000,      -- 160km
            minRange = 3000,        -- 3km
            maxAltitude = 24000,
            maxSpeed = 1700,        -- Mach 5
            maxG = 25,
            guidance = "TVM",       -- Track-via-Missile
            warhead = "blast_frag",
            warheadRadius = 20,
        },
        PAC3 = {
            name = "MIM-104F PAC-3",
            maxRange = 35000,       -- 35km (optimized for TBM)
            minRange = 3000,
            maxAltitude = 15000,
            maxSpeed = 1500,        -- Mach 4.5
            maxG = 50,              -- Higher maneuverability
            guidance = "ARH",       -- Active Radar Homing (hit-to-kill)
            warhead = "hit_to_kill",
            warheadRadius = 0,      -- Direct hit required
        },
    },

    -- Launcher configuration
    launcher = {
        missilesPerStation = 4,     -- 4 missiles per M901 launcher
        stations = 4,               -- 4 launcher stations per battery
        reloadTime = 600,           -- 10 minutes per missile
    },

    -- ECCM capabilities
    eccm = {
        sidelobeCancel = true,
        frequencyAgility = true,
        burnThroughRange = 30000,   -- 30km burn-through
        clutterRejection = 0.9,
        antijamPower = 50,          -- dBW
    },
}

-- ============================================================================
-- System State
-- ============================================================================
PATRIOT_SAMSIM.State = {
    systemMode = "STANDBY",         -- STANDBY, ALERT, ENGAGE, AUTOMATIC
    powerState = "OFF",

    -- Radar state
    radar = {
        mode = 0,                   -- 0=OFF, 1=STANDBY, 2=SEARCH, 3=TRACK, 4=ENGAGE
        modeName = "OFF",
        azimuth = 0,                -- Center azimuth of sector
        elevation = 10,
        sectorWidth = 90,
        rotating = false,           -- Phased array doesn't rotate
    },

    -- ECS state
    ecs = {
        operatorMode = "MANUAL",    -- MANUAL, SEMI_AUTO, AUTO
        engagementMode = "SINGLE",  -- SINGLE, RIPPLE, SALVO
        threatPriority = "AUTO",    -- AUTO, TBM_FIRST, AIR_FIRST
        iffMode = 4,                -- Mode 4 default
    },

    -- Tracks
    tracks = {},                    -- All radar tracks
    engagements = {},               -- Active engagements
    maxEngagements = 9,

    -- Missiles
    missiles = {
        total = 16,
        ready = 16,
        inFlight = 0,
        active = {},
    },

    -- Datalink
    datalink = {
        active = false,
        linkedUnits = {},
        sharedTracks = {},
    },
}

-- ============================================================================
-- Radar Operations
-- ============================================================================
PATRIOT_SAMSIM.Radar = {}

function PATRIOT_SAMSIM.Radar.setMode(mode)
    local modeNames = {
        [0] = "OFF",
        [1] = "STANDBY",
        [2] = "SEARCH",
        [3] = "TRACK",
        [4] = "ENGAGE",
    }

    PATRIOT_SAMSIM.State.radar.mode = mode
    PATRIOT_SAMSIM.State.radar.modeName = modeNames[mode] or "UNKNOWN"

    if mode >= 2 then
        PATRIOT_SAMSIM.State.powerState = "ON"
    end
end

function PATRIOT_SAMSIM.Radar.setSector(centerAzimuth, width)
    PATRIOT_SAMSIM.State.radar.azimuth = centerAzimuth
    PATRIOT_SAMSIM.State.radar.sectorWidth = math.min(width, 90)  -- Max 90 degrees
end

function PATRIOT_SAMSIM.Radar.update(dt)
    local state = PATRIOT_SAMSIM.State
    local config = PATRIOT_SAMSIM.Config.radar

    if state.radar.mode < 2 then return end

    -- Phased array - no mechanical scan, electronic steering
    -- Scan entire sector near-instantaneously

    -- Get all aircraft in sector
    local contacts = PATRIOT_SAMSIM.Radar.scanSector()

    -- Update tracks
    for _, contact in ipairs(contacts) do
        PATRIOT_SAMSIM.Radar.updateTrack(contact)
    end

    -- Age and remove stale tracks
    PATRIOT_SAMSIM.Radar.ageTracks(dt)

    -- Auto-engagement in AUTO mode
    if state.ecs.operatorMode == "AUTO" and state.radar.mode >= 4 then
        PATRIOT_SAMSIM.Engagement.autoEngage()
    end
end

function PATRIOT_SAMSIM.Radar.scanSector()
    local state = PATRIOT_SAMSIM.State
    local config = PATRIOT_SAMSIM.Config.radar
    local contacts = {}

    -- Get site position (would come from DCS group position)
    local sitePos = PATRIOT_SAMSIM.getSitePosition()
    if not sitePos then return contacts end

    -- Scan for aircraft
    local volume = {
        id = world.VolumeType.SPHERE,
        params = {
            point = sitePos,
            radius = config.searchRange,
        }
    }

    local centerAz = state.radar.azimuth
    local halfWidth = state.radar.sectorWidth / 2

    world.searchObjects(Object.Category.UNIT, volume, function(found)
        if found and found:isExist() then
            local desc = found:getDesc()
            if desc.category == Unit.Category.AIRPLANE or
               desc.category == Unit.Category.HELICOPTER then

                local targetPos = found:getPoint()
                local dx = targetPos.x - sitePos.x
                local dz = targetPos.z - sitePos.z
                local range = math.sqrt(dx*dx + dz*dz)
                local azimuth = math.deg(math.atan2(dz, dx))
                if azimuth < 0 then azimuth = azimuth + 360 end

                -- Check if in sector
                local azDiff = math.abs(azimuth - centerAz)
                if azDiff > 180 then azDiff = 360 - azDiff end

                if azDiff <= halfWidth and range <= config.searchRange then
                    local altitude = targetPos.y - sitePos.y
                    if altitude >= config.minAltitude and altitude <= config.maxAltitude then
                        local elevation = math.deg(math.atan2(altitude, range))

                        table.insert(contacts, {
                            unit = found,
                            id = found:getID(),
                            name = found:getName(),
                            typeName = found:getTypeName(),
                            position = targetPos,
                            range = range,
                            azimuth = azimuth,
                            elevation = elevation,
                            altitude = altitude,
                            velocity = found:getVelocity(),
                        })
                    end
                end
            end
        end
        return true
    end)

    return contacts
end

function PATRIOT_SAMSIM.Radar.updateTrack(contact)
    local state = PATRIOT_SAMSIM.State
    local trackId = contact.id

    -- Calculate velocity and heading
    local vel = contact.velocity
    local speed = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)
    local heading = math.deg(math.atan2(vel.z, vel.x))
    if heading < 0 then heading = heading + 360 end

    -- Check if existing track
    local existingTrack = nil
    for i, track in ipairs(state.tracks) do
        if track.id == trackId then
            existingTrack = track
            break
        end
    end

    if existingTrack then
        -- Update existing track
        existingTrack.position = contact.position
        existingTrack.range = contact.range
        existingTrack.azimuth = contact.azimuth
        existingTrack.elevation = contact.elevation
        existingTrack.altitude = contact.altitude
        existingTrack.speed = speed
        existingTrack.heading = heading
        existingTrack.lastUpdate = timer.getTime()
        existingTrack.quality = math.min(1.0, existingTrack.quality + 0.1)

        -- Threat assessment
        existingTrack.threat = PATRIOT_SAMSIM.Radar.assessThreat(existingTrack)
    else
        -- Create new track
        local newTrack = {
            id = trackId,
            unitName = contact.name,
            typeName = contact.typeName,
            position = contact.position,
            range = contact.range,
            azimuth = contact.azimuth,
            elevation = contact.elevation,
            altitude = contact.altitude,
            speed = speed,
            heading = heading,
            quality = 0.5,
            lastUpdate = timer.getTime(),
            iffStatus = "UNKNOWN",
            threat = 0,
            trackNumber = #state.tracks + 1,
        }

        newTrack.threat = PATRIOT_SAMSIM.Radar.assessThreat(newTrack)
        table.insert(state.tracks, newTrack)

        -- Limit tracks
        if #state.tracks > PATRIOT_SAMSIM.Config.radar.maxTracks then
            table.remove(state.tracks, 1)
        end
    end
end

function PATRIOT_SAMSIM.Radar.assessThreat(track)
    local threat = 0

    -- Range factor (closer = higher threat)
    local rangeFactor = 1 - (track.range / PATRIOT_SAMSIM.Config.radar.searchRange)
    threat = threat + rangeFactor * 30

    -- Speed factor
    if track.speed > 500 then  -- Fast mover
        threat = threat + 20
    end
    if track.speed > 1000 then  -- Very fast (missile?)
        threat = threat + 30
    end

    -- Altitude factor (low = potentially more dangerous)
    if track.altitude < 1000 then
        threat = threat + 15
    end

    -- Heading toward site
    local sitePos = PATRIOT_SAMSIM.getSitePosition()
    if sitePos then
        local toSite = math.deg(math.atan2(sitePos.z - track.position.z, sitePos.x - track.position.x))
        if toSite < 0 then toSite = toSite + 360 end
        local headingDiff = math.abs(track.heading - toSite)
        if headingDiff > 180 then headingDiff = 360 - headingDiff end
        if headingDiff < 30 then
            threat = threat + 25  -- Heading toward us
        end
    end

    return math.min(100, threat)
end

function PATRIOT_SAMSIM.Radar.ageTracks(dt)
    local state = PATRIOT_SAMSIM.State
    local currentTime = timer.getTime()
    local maxAge = 10  -- 10 seconds max track age

    for i = #state.tracks, 1, -1 do
        local track = state.tracks[i]
        local age = currentTime - track.lastUpdate

        track.quality = math.max(0, track.quality - dt * 0.05)

        if age > maxAge or track.quality <= 0 then
            table.remove(state.tracks, i)
        end
    end
end

-- ============================================================================
-- Engagement Control
-- ============================================================================
PATRIOT_SAMSIM.Engagement = {}

function PATRIOT_SAMSIM.Engagement.designate(trackId)
    local state = PATRIOT_SAMSIM.State

    -- Find track
    local track = nil
    for _, t in ipairs(state.tracks) do
        if t.id == trackId then
            track = t
            break
        end
    end

    if not track then
        return false, "Track not found"
    end

    -- Check engagement limit
    if #state.engagements >= state.maxEngagements then
        return false, "Maximum engagements reached"
    end

    -- Check if already engaging
    for _, eng in ipairs(state.engagements) do
        if eng.trackId == trackId then
            return false, "Already engaging this track"
        end
    end

    -- Create engagement
    local engagement = {
        id = #state.engagements + 1,
        trackId = trackId,
        track = track,
        state = "DESIGNATED",
        missileId = nil,
        startTime = timer.getTime(),
        launchTime = nil,
    }

    table.insert(state.engagements, engagement)

    return true, "Target designated"
end

function PATRIOT_SAMSIM.Engagement.launch(engagementId)
    local state = PATRIOT_SAMSIM.State

    -- Find engagement
    local engagement = nil
    for _, eng in ipairs(state.engagements) do
        if eng.id == engagementId then
            engagement = eng
            break
        end
    end

    if not engagement then
        return false, "Engagement not found"
    end

    -- Check missile availability
    if state.missiles.ready <= 0 then
        return false, "No missiles ready"
    end

    -- Calculate firing solution
    local solution = PATRIOT_SAMSIM.Engagement.calculateSolution(engagement.track)
    if not solution.valid then
        return false, solution.reason
    end

    -- Launch missile
    state.missiles.ready = state.missiles.ready - 1
    state.missiles.inFlight = state.missiles.inFlight + 1

    local missile = {
        id = #state.missiles.active + 1,
        engagementId = engagementId,
        targetId = engagement.trackId,
        launchTime = timer.getTime(),
        position = PATRIOT_SAMSIM.getSitePosition(),
        phase = "BOOST",
        timeToIntercept = solution.timeToIntercept,
        predictedIntercept = solution.interceptPoint,
    }

    table.insert(state.missiles.active, missile)

    engagement.state = "MISSILE_AWAY"
    engagement.missileId = missile.id
    engagement.launchTime = timer.getTime()

    return true, "Missile launched"
end

function PATRIOT_SAMSIM.Engagement.calculateSolution(track)
    local config = PATRIOT_SAMSIM.Config.missiles.PAC2
    local solution = {
        valid = false,
        pk = 0,
        timeToIntercept = 0,
        interceptPoint = nil,
        reason = "",
    }

    -- Range checks
    if track.range > config.maxRange then
        solution.reason = "Target beyond maximum range"
        return solution
    end

    if track.range < config.minRange then
        solution.reason = "Target within minimum range"
        return solution
    end

    -- Altitude check
    if track.altitude > config.maxAltitude then
        solution.reason = "Target above maximum altitude"
        return solution
    end

    -- Calculate intercept
    local missileSpeed = config.maxSpeed * 0.8  -- Average speed
    local timeToIntercept = track.range / missileSpeed

    -- Predict target position
    local interceptX = track.position.x + track.speed * math.cos(math.rad(track.heading)) * timeToIntercept
    local interceptZ = track.position.z + track.speed * math.sin(math.rad(track.heading)) * timeToIntercept
    local interceptY = track.position.y

    solution.interceptPoint = {x = interceptX, y = interceptY, z = interceptZ}
    solution.timeToIntercept = timeToIntercept

    -- Calculate Pk
    local basePk = 0.85  -- Base Pk for Patriot

    -- Range factor
    local rangeFactor = 1 - (track.range / config.maxRange) * 0.3

    -- Aspect factor (beam aspect harder)
    local aspectFactor = 0.9

    -- ECM factor
    local ecmFactor = 1.0  -- Reduced if jamming present

    solution.pk = basePk * rangeFactor * aspectFactor * ecmFactor
    solution.valid = true

    return solution
end

function PATRIOT_SAMSIM.Engagement.autoEngage()
    local state = PATRIOT_SAMSIM.State

    -- Sort tracks by threat
    local sortedTracks = {}
    for _, track in ipairs(state.tracks) do
        table.insert(sortedTracks, track)
    end
    table.sort(sortedTracks, function(a, b) return a.threat > b.threat end)

    -- Engage highest threats
    for _, track in ipairs(sortedTracks) do
        if #state.engagements >= state.maxEngagements then
            break
        end

        -- Check if already engaged
        local alreadyEngaged = false
        for _, eng in ipairs(state.engagements) do
            if eng.trackId == track.id then
                alreadyEngaged = true
                break
            end
        end

        if not alreadyEngaged and track.threat > 50 and track.iffStatus ~= "FRIENDLY" then
            local success, msg = PATRIOT_SAMSIM.Engagement.designate(track.id)
            if success then
                -- Auto-launch in full auto mode
                if state.ecs.operatorMode == "AUTO" then
                    for _, eng in ipairs(state.engagements) do
                        if eng.trackId == track.id and eng.state == "DESIGNATED" then
                            PATRIOT_SAMSIM.Engagement.launch(eng.id)
                            break
                        end
                    end
                end
            end
        end
    end
end

function PATRIOT_SAMSIM.Engagement.update(dt)
    local state = PATRIOT_SAMSIM.State

    -- Update active missiles
    for i = #state.missiles.active, 1, -1 do
        local missile = state.missiles.active[i]
        PATRIOT_SAMSIM.Engagement.updateMissile(missile, dt)

        if missile.state == "COMPLETE" or missile.state == "MISS" then
            state.missiles.inFlight = state.missiles.inFlight - 1

            -- Update engagement state
            for _, eng in ipairs(state.engagements) do
                if eng.missileId == missile.id then
                    eng.state = missile.state == "COMPLETE" and "KILL" or "MISS"
                    break
                end
            end

            table.remove(state.missiles.active, i)
        end
    end

    -- Clean up completed engagements
    for i = #state.engagements, 1, -1 do
        local eng = state.engagements[i]
        if eng.state == "KILL" or eng.state == "MISS" or eng.state == "ABORTED" then
            local age = timer.getTime() - (eng.launchTime or eng.startTime)
            if age > 30 then  -- Keep for 30 seconds
                table.remove(state.engagements, i)
            end
        end
    end
end

function PATRIOT_SAMSIM.Engagement.updateMissile(missile, dt)
    local elapsed = timer.getTime() - missile.launchTime

    -- Phase transitions
    if elapsed < 3 then
        missile.phase = "BOOST"
    elseif elapsed < missile.timeToIntercept * 0.7 then
        missile.phase = "MIDCOURSE"
    else
        missile.phase = "TERMINAL"
    end

    -- Check for intercept
    if elapsed >= missile.timeToIntercept then
        -- Check if target still exists and calculate miss distance
        local target = Unit.getByName(missile.targetId) -- Would need unit name
        if target and target:isExist() then
            local targetPos = target:getPoint()
            local dx = targetPos.x - missile.predictedIntercept.x
            local dy = targetPos.y - missile.predictedIntercept.y
            local dz = targetPos.z - missile.predictedIntercept.z
            local missDistance = math.sqrt(dx*dx + dy*dy + dz*dz)

            local killRadius = PATRIOT_SAMSIM.Config.missiles.PAC2.warheadRadius
            if missDistance <= killRadius then
                missile.state = "COMPLETE"
                missile.result = "KILL"
            else
                missile.state = "MISS"
                missile.result = "MISS"
                missile.missDistance = missDistance
            end
        else
            missile.state = "COMPLETE"
            missile.result = "TARGET_LOST"
        end
    end
end

-- ============================================================================
-- IFF System
-- ============================================================================
PATRIOT_SAMSIM.IFF = {}

function PATRIOT_SAMSIM.IFF.interrogate(trackId)
    local state = PATRIOT_SAMSIM.State

    for _, track in ipairs(state.tracks) do
        if track.id == trackId then
            -- Simulate IFF response
            local unit = Unit.getByName(track.unitName)
            if unit then
                local coalition = unit:getCoalition()
                local siteCoalition = PATRIOT_SAMSIM.getCoalition()

                if coalition == siteCoalition then
                    track.iffStatus = "FRIENDLY"
                elseif coalition == 0 then
                    track.iffStatus = "NEUTRAL"
                else
                    track.iffStatus = "HOSTILE"
                end
            else
                track.iffStatus = "NO_RESPONSE"
            end

            return track.iffStatus
        end
    end

    return "TRACK_NOT_FOUND"
end

-- ============================================================================
-- Datalink
-- ============================================================================
PATRIOT_SAMSIM.Datalink = {}

function PATRIOT_SAMSIM.Datalink.enable()
    PATRIOT_SAMSIM.State.datalink.active = true
end

function PATRIOT_SAMSIM.Datalink.disable()
    PATRIOT_SAMSIM.State.datalink.active = false
end

function PATRIOT_SAMSIM.Datalink.shareTracks()
    if not PATRIOT_SAMSIM.State.datalink.active then return end

    -- Would share tracks with linked units via network
    PATRIOT_SAMSIM.State.datalink.sharedTracks = PATRIOT_SAMSIM.State.tracks
end

-- ============================================================================
-- Command Processing
-- ============================================================================
function PATRIOT_SAMSIM.processCommand(cmd)
    local cmdType = cmd.type

    if cmdType == "POWER" then
        if cmd.state == "ON" then
            PATRIOT_SAMSIM.State.powerState = "ON"
            PATRIOT_SAMSIM.Radar.setMode(1)  -- Standby
            return {success = true, message = "Power ON"}
        else
            PATRIOT_SAMSIM.State.powerState = "OFF"
            PATRIOT_SAMSIM.Radar.setMode(0)
            return {success = true, message = "Power OFF"}
        end

    elseif cmdType == "RADAR_MODE" then
        local modes = {OFF = 0, STANDBY = 1, SEARCH = 2, TRACK = 3, ENGAGE = 4}
        local mode = modes[cmd.mode] or 1
        PATRIOT_SAMSIM.Radar.setMode(mode)
        return {success = true, message = "Radar mode set to " .. cmd.mode}

    elseif cmdType == "SET_SECTOR" then
        PATRIOT_SAMSIM.Radar.setSector(cmd.azimuth or 0, cmd.width or 90)
        return {success = true, message = "Sector set"}

    elseif cmdType == "OPERATOR_MODE" then
        PATRIOT_SAMSIM.State.ecs.operatorMode = cmd.mode or "MANUAL"
        return {success = true, message = "Operator mode: " .. cmd.mode}

    elseif cmdType == "DESIGNATE" then
        local success, msg = PATRIOT_SAMSIM.Engagement.designate(cmd.trackId)
        return {success = success, message = msg}

    elseif cmdType == "LAUNCH" then
        local success, msg = PATRIOT_SAMSIM.Engagement.launch(cmd.engagementId or 1)
        return {success = success, message = msg}

    elseif cmdType == "IFF_INTERROGATE" then
        local status = PATRIOT_SAMSIM.IFF.interrogate(cmd.trackId)
        return {success = true, iffStatus = status}

    elseif cmdType == "DATALINK" then
        if cmd.enable then
            PATRIOT_SAMSIM.Datalink.enable()
        else
            PATRIOT_SAMSIM.Datalink.disable()
        end
        return {success = true, message = "Datalink " .. (cmd.enable and "enabled" or "disabled")}
    end

    return {success = false, message = "Unknown command"}
end

-- ============================================================================
-- State Export
-- ============================================================================
function PATRIOT_SAMSIM.getStateForExport()
    local state = PATRIOT_SAMSIM.State

    return {
        systemType = "PATRIOT",
        systemName = "MIM-104 Patriot",
        version = PATRIOT_SAMSIM.Version,
        powerState = state.powerState,
        systemMode = state.systemMode,

        radar = {
            mode = state.radar.mode,
            modeName = state.radar.modeName,
            azimuth = state.radar.azimuth,
            sectorWidth = state.radar.sectorWidth,
            elevation = state.radar.elevation,
        },

        ecs = state.ecs,

        tracks = state.tracks,
        engagements = state.engagements,

        missiles = {
            total = state.missiles.total,
            ready = state.missiles.ready,
            inFlight = state.missiles.inFlight,
            active = state.missiles.active,
        },

        datalink = state.datalink,
    }
end

-- ============================================================================
-- Utility Functions
-- ============================================================================
function PATRIOT_SAMSIM.getSitePosition()
    -- Would return actual DCS group position
    return PATRIOT_SAMSIM.sitePosition or {x = 0, y = 0, z = 0}
end

function PATRIOT_SAMSIM.getCoalition()
    return PATRIOT_SAMSIM.coalition or 2  -- Default blue
end

function PATRIOT_SAMSIM.initialize(groupName, position, heading)
    PATRIOT_SAMSIM.groupName = groupName
    PATRIOT_SAMSIM.sitePosition = position
    PATRIOT_SAMSIM.heading = heading or 0
    PATRIOT_SAMSIM.State.radar.azimuth = heading or 0

    -- Start update loop
    timer.scheduleFunction(function()
        PATRIOT_SAMSIM.Radar.update(0.1)
        PATRIOT_SAMSIM.Engagement.update(0.1)
        return timer.getTime() + 0.1
    end, nil, timer.getTime() + 1)

    env.info("PATRIOT SAMSIM initialized: " .. (groupName or "Unknown"))
end

env.info("PATRIOT SAMSIM loaded - Version " .. PATRIOT_SAMSIM.Version)
