--[[
    SA-2 (S-75 Dvina) SAMSIM Controller - Enhanced Version
    DCS World Mission Script

    This script provides detailed SAMSim-like control for SA-2 systems.
    Includes realistic simulation of:
    - P-19 "Flat Face" Early Warning Radar
    - SNR-75 "Fan Song" Fire Control Radar
    - PRV-11 "Side Net" Height Finder (optional)
    - Firing solution computation
    - Radar noise and clutter effects
]]

-- Initialize SAMSIM namespace
SAMSIM = SAMSIM or {}

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------
SAMSIM.Config = {
    -- Communication
    UDP_SEND_PORT = 7777,
    UDP_RECV_PORT = 7778,
    UPDATE_INTERVAL = 0.1,  -- 10 Hz

    -- P-19 "Flat Face" Early Warning Radar
    P19 = {
        MAX_RANGE = 160000,     -- 160 km
        MIN_RANGE = 500,        -- 500 m
        MAX_ALTITUDE = 40000,   -- 40 km
        MIN_ALTITUDE = 100,     -- 100 m
        ROTATION_PERIOD = 6,    -- 6 seconds per revolution (10 RPM)
        BEAM_WIDTH_AZ = 2.5,    -- 2.5 degrees azimuth
        BEAM_WIDTH_EL = 4,      -- 4 degrees elevation (fan beam)
        DETECTION_PROB_MAX = 0.95,
        RANGE_RESOLUTION = 500, -- 500 m
        MIN_RCS = 1.0,          -- Minimum detectable RCS (m^2)
    },

    -- PRV-11 "Side Net" Height Finder
    PRV11 = {
        MAX_RANGE = 180000,
        MIN_RANGE = 5000,
        MAX_ALTITUDE = 32000,
        SCAN_RATE = 10,         -- degrees per second
        BEAM_WIDTH = 1.5,
        HEIGHT_ACCURACY = 300,  -- 300 m accuracy
    },

    -- SNR-75 "Fan Song" Fire Control Radar
    SNR75 = {
        MAX_RANGE = 65000,      -- 65 km tracking range
        MIN_RANGE = 7000,       -- 7 km
        MAX_ALTITUDE = 27000,   -- 27 km
        MIN_ALTITUDE = 500,     -- 500 m
        TRACK_BEAM_WIDTH = 1.0, -- 1 degree
        SCAN_SECTOR = 10,       -- +/- 10 degrees sector scan
        SCAN_RATE = 15,         -- degrees per second in sector scan
        ACQUISITION_TIME = 3,   -- seconds to acquire target
        RANGE_ACCURACY = 75,    -- 75 m
        ANGLE_ACCURACY = 0.3,   -- 0.3 degrees
        TRACK_MEMORY = 5,       -- 5 seconds track memory
    },

    -- V-750 (SA-2) Missile
    MISSILE = {
        MAX_RANGE = 45000,
        MIN_RANGE = 7000,
        MAX_ALTITUDE = 25000,
        MIN_ALTITUDE = 500,
        MAX_SPEED = 1200,       -- m/s (Mach 3.5)
        ACCELERATION = 25,      -- G
        FLIGHT_TIME_MAX = 60,   -- seconds
        GUIDANCE_DELAY = 2.5,   -- seconds after launch
        KILL_RADIUS = 65,       -- meters
        WARHEAD_WEIGHT = 195,   -- kg
        SALVO_INTERVAL = 6,     -- seconds between launches
    },

    -- Engagement Envelope
    ENVELOPE = {
        -- Kinematic zone (simplified)
        MAX_TARGET_SPEED = 700, -- m/s (~Mach 2)
        MAX_CROSSING_ANGLE = 70, -- degrees
        MIN_ENGAGEMENT_TIME = 20, -- seconds (time in kill zone)
    },

    -- Noise and Clutter
    NOISE = {
        THERMAL_NOISE_FLOOR = -110, -- dBm
        CLUTTER_STRENGTH = 0.3,
        JAMMING_SUSCEPTIBILITY = 0.8,
    },
}

--------------------------------------------------------------------------------
-- RADAR MODES AND STATES
--------------------------------------------------------------------------------

-- P-19 Early Warning Radar Modes
SAMSIM.P19Mode = {
    OFF = 0,
    STANDBY = 1,
    ROTATE = 2,      -- Normal rotation search
    SECTOR = 3,      -- Sector scan
}

-- SNR-75 Fire Control Radar Modes
SAMSIM.SNR75Mode = {
    OFF = 0,
    STANDBY = 1,
    ACQUISITION = 2, -- Wide beam acquisition
    TRACK_COARSE = 3, -- Coarse tracking
    TRACK_FINE = 4,   -- Fine tracking (engagement ready)
    GUIDANCE = 5,     -- Missile guidance active
}

-- PRV-11 Height Finder Modes
SAMSIM.PRV11Mode = {
    OFF = 0,
    STANDBY = 1,
    SCAN = 2,
    DESIGNATE = 3,  -- Height finding on designated bearing
}

-- Overall System State
SAMSIM.SystemState = {
    OFFLINE = 0,
    STARTUP = 1,      -- Systems warming up
    READY = 2,        -- All systems ready
    ALERT = 3,        -- Targets detected
    TRACKING = 4,     -- Target locked
    ENGAGED = 5,      -- Missiles in flight
    COOLDOWN = 6,     -- Post-engagement cooldown
}

-- IFF Modes
SAMSIM.IFFMode = {
    OFF = 0,
    INTERROGATE = 1,
    AUTO = 2,
}

--------------------------------------------------------------------------------
-- SA-2 SITE STATE
--------------------------------------------------------------------------------
SAMSIM.Sites = {}

--[[
    Create a new SA-2 site with full subsystem simulation
]]
function SAMSIM.InitSite(groupName, siteId)
    local group = Group.getByName(groupName)
    if not group then
        env.warning("SAMSIM: Group not found: " .. groupName)
        return nil
    end

    local site = {
        id = siteId,
        groupName = groupName,
        group = group,
        coalition = group:getCoalition(),

        -- Overall system state
        systemState = SAMSIM.SystemState.OFFLINE,
        startupTime = 0,
        startupDuration = 90, -- 90 seconds warmup

        -- Position
        position = nil,

        ------------------------
        -- P-19 Early Warning Radar
        ------------------------
        p19 = {
            mode = SAMSIM.P19Mode.OFF,
            unit = nil,
            position = nil,
            antennaAzimuth = 0,
            rotationDirection = 1,
            sectorCenter = 0,
            sectorWidth = 60,
            contacts = {},        -- Raw radar contacts
            tracks = {},          -- Processed tracks
            lastSweepTime = 0,
            sweepHistory = {},    -- For afterglow effect
            noiseLevel = 0,
            clutterMap = {},
        },

        ------------------------
        -- PRV-11 Height Finder
        ------------------------
        prv11 = {
            mode = SAMSIM.PRV11Mode.OFF,
            unit = nil,
            position = nil,
            antennaAzimuth = 0,
            antennaElevation = 0,
            targetAzimuth = 0,
            scanElevation = 0,
            heightData = {},      -- Height measurements
        },

        ------------------------
        -- SNR-75 Fire Control Radar
        ------------------------
        snr75 = {
            mode = SAMSIM.SNR75Mode.OFF,
            unit = nil,
            position = nil,
            antennaAzimuth = 0,
            antennaElevation = 5,
            targetAzimuth = 0,
            targetElevation = 5,
            scanPhase = 0,        -- For sector scan
            scanDirection = 1,

            -- Tracking data
            trackedTarget = nil,
            trackedTargetId = nil,
            acquisitionStartTime = 0,
            trackEstablishedTime = 0,
            trackQuality = 0,
            trackLostTime = 0,

            -- Smoothed target data (filtered)
            smoothedRange = 0,
            smoothedAzimuth = 0,
            smoothedElevation = 0,
            smoothedVelocity = {x=0, y=0, z=0},

            -- Predicted position
            predictedPosition = nil,
            predictedTime = 0,

            -- A-scope data (range display)
            aScopeData = {},

            -- B-scope data (range-azimuth)
            bScopeData = {},
        },

        ------------------------
        -- Firing Solution Computer
        ------------------------
        firingSolution = {
            valid = false,
            targetRange = 0,
            targetAzimuth = 0,
            targetElevation = 0,
            targetAltitude = 0,
            targetSpeed = 0,
            targetHeading = 0,
            closureRate = 0,
            crossingAngle = 0,
            interceptPoint = nil,
            timeToIntercept = 0,
            missileFlightTime = 0,
            launchZone = "NONE", -- "OPTIMAL", "MARGINAL", "NONE"
            killProbability = 0,
            leadAngle = 0,
            guidanceCorrection = {az = 0, el = 0},
        },

        ------------------------
        -- Missiles
        ------------------------
        missiles = {
            ready = 6,
            total = 6,
            inFlight = {},
            lastLaunchTime = 0,
            salvoCount = 0,
            reloadTime = 0,
        },

        ------------------------
        -- Engagement Control
        ------------------------
        engagement = {
            authorized = false,
            autoTrack = false,
            autoEngage = false,
            iffMode = SAMSIM.IFFMode.OFF,
            priorityMode = "CLOSEST", -- "CLOSEST", "FASTEST", "HIGHEST"
            burstMode = false,  -- Fire 2 missiles
        },

        ------------------------
        -- Detected Targets (consolidated)
        ------------------------
        detectedTargets = {},

        ------------------------
        -- Event Log
        ------------------------
        eventLog = {},
    }

    -- Find radar units in the group
    local units = group:getUnits()
    for _, unit in pairs(units) do
        if unit and unit:isExist() then
            local typeName = unit:getTypeName()

            if string.find(typeName:lower(), "p-19") or string.find(typeName:lower(), "flat face") then
                site.p19.unit = unit
                site.p19.position = unit:getPoint()
                env.info("SAMSIM: Found P-19 radar")
            elseif string.find(typeName:lower(), "snr") or string.find(typeName:lower(), "fan song") then
                site.snr75.unit = unit
                site.snr75.position = unit:getPoint()
                site.position = unit:getPoint() -- Site position = FC radar
                env.info("SAMSIM: Found SNR-75 radar")
            elseif string.find(typeName:lower(), "prv") or string.find(typeName:lower(), "side net") then
                site.prv11.unit = unit
                site.prv11.position = unit:getPoint()
                env.info("SAMSIM: Found PRV-11 height finder")
            end
        end
    end

    -- Fallback position
    if not site.position then
        site.position = units[1]:getPoint()
        site.snr75.position = site.position
    end

    if not site.p19.position then
        site.p19.position = site.position
    end

    SAMSIM.Sites[siteId] = site
    SAMSIM.LogEvent(site, "SYSTEM", "Site initialized: " .. siteId)

    return site
end

--------------------------------------------------------------------------------
-- EVENT LOGGING
--------------------------------------------------------------------------------
function SAMSIM.LogEvent(site, category, message)
    table.insert(site.eventLog, {
        time = timer.getTime(),
        category = category,
        message = message,
    })

    -- Keep only last 100 events
    while #site.eventLog > 100 do
        table.remove(site.eventLog, 1)
    end

    env.info("SAMSIM [" .. site.id .. "] " .. category .. ": " .. message)
end

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------
function SAMSIM.GetDistance3D(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dy = (pos1.y or 0) - (pos2.y or 0)
    local dz = pos1.z - pos2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function SAMSIM.GetGroundDistance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dz = pos1.z - pos2.z
    return math.sqrt(dx*dx + dz*dz)
end

function SAMSIM.GetAzimuth(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dz = toPos.z - fromPos.z
    local az = math.deg(math.atan2(dz, dx))
    return (90 - az) % 360
end

function SAMSIM.GetElevation(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dy = (toPos.y or 0) - (fromPos.y or 0)
    local dz = toPos.z - fromPos.z
    local groundDist = math.sqrt(dx*dx + dz*dz)
    return math.deg(math.atan2(dy, groundDist))
end

function SAMSIM.NormalizeAngle(angle)
    return (angle % 360 + 360) % 360
end

function SAMSIM.AngleDiff(a1, a2)
    local diff = a1 - a2
    if diff > 180 then diff = diff - 360 end
    if diff < -180 then diff = diff + 360 end
    return diff
end

-- Calculate RCS based on aspect (simplified)
function SAMSIM.EstimateRCS(unit, viewAzimuth)
    local typeName = unit:getTypeName()
    local baseRCS = 5.0 -- Default 5 m^2

    -- Aircraft type RCS estimates
    if string.find(typeName, "F-16") then baseRCS = 1.2
    elseif string.find(typeName, "F-15") then baseRCS = 10
    elseif string.find(typeName, "F-18") then baseRCS = 1.5
    elseif string.find(typeName, "F-14") then baseRCS = 12
    elseif string.find(typeName, "A-10") then baseRCS = 15
    elseif string.find(typeName, "F-4") then baseRCS = 8
    elseif string.find(typeName, "MiG-29") then baseRCS = 3
    elseif string.find(typeName, "Su-27") then baseRCS = 10
    elseif string.find(typeName, "B-52") then baseRCS = 100
    elseif string.find(typeName, "F-117") then baseRCS = 0.003
    elseif string.find(typeName, "B-2") then baseRCS = 0.0001
    end

    -- Aspect angle effect (nose-on vs beam)
    local heading = math.deg(unit:getHeading() or 0)
    local aspectAngle = math.abs(SAMSIM.AngleDiff(viewAzimuth, heading))

    -- RCS varies with aspect (simplified model)
    local aspectFactor = 1.0
    if aspectAngle < 30 or aspectAngle > 150 then
        aspectFactor = 0.5  -- Nose/tail - lower RCS
    elseif aspectAngle > 60 and aspectAngle < 120 then
        aspectFactor = 2.0  -- Beam - higher RCS
    end

    return baseRCS * aspectFactor
end

-- Detection probability based on range and RCS
function SAMSIM.CalculateDetectionProbability(range, rcs, radarConfig)
    local maxRange = radarConfig.MAX_RANGE
    local minRCS = radarConfig.MIN_RCS or 1.0
    local maxProb = radarConfig.DETECTION_PROB_MAX or 0.95

    -- Radar range equation (simplified)
    -- Detection range proportional to RCS^(1/4)
    local effectiveRange = maxRange * math.pow(rcs / minRCS, 0.25)

    if range > effectiveRange then
        return 0
    end

    -- Probability decreases with range
    local rangeRatio = range / effectiveRange
    local prob = maxProb * (1 - rangeRatio^2)

    -- Add noise
    prob = prob + (math.random() - 0.5) * 0.1

    return math.max(0, math.min(1, prob))
end

--------------------------------------------------------------------------------
-- P-19 EARLY WARNING RADAR SIMULATION
--------------------------------------------------------------------------------
function SAMSIM.UpdateP19(site, dt)
    local p19 = site.p19
    local config = SAMSIM.Config.P19

    if p19.mode == SAMSIM.P19Mode.OFF then
        return
    end

    -- Update antenna rotation
    if p19.mode == SAMSIM.P19Mode.ROTATE then
        -- Full 360 rotation
        local rotationSpeed = 360 / config.ROTATION_PERIOD
        p19.antennaAzimuth = (p19.antennaAzimuth + rotationSpeed * dt) % 360

    elseif p19.mode == SAMSIM.P19Mode.SECTOR then
        -- Sector scan
        local rotationSpeed = 360 / config.ROTATION_PERIOD
        p19.antennaAzimuth = p19.antennaAzimuth + rotationSpeed * dt * p19.rotationDirection

        local minAz = SAMSIM.NormalizeAngle(p19.sectorCenter - p19.sectorWidth/2)
        local maxAz = SAMSIM.NormalizeAngle(p19.sectorCenter + p19.sectorWidth/2)

        -- Check sector bounds (simplified)
        local diff = SAMSIM.AngleDiff(p19.antennaAzimuth, p19.sectorCenter)
        if math.abs(diff) > p19.sectorWidth/2 then
            p19.rotationDirection = -p19.rotationDirection
        end
    end

    -- Perform radar sweep detection
    local currentTime = timer.getTime()
    local sweepInterval = config.ROTATION_PERIOD / 360 * config.BEAM_WIDTH_AZ

    -- Clear old contacts on new sweep
    if currentTime - p19.lastSweepTime > config.ROTATION_PERIOD then
        p19.contacts = {}
        p19.lastSweepTime = currentTime
    end

    -- Scan for targets
    SAMSIM.P19ScanForTargets(site)

    -- Process contacts into tracks
    SAMSIM.P19ProcessTracks(site)

    -- Generate noise
    p19.noiseLevel = 0.1 + math.random() * 0.1
end

function SAMSIM.P19ScanForTargets(site)
    local p19 = site.p19
    local config = SAMSIM.Config.P19

    if p19.mode == SAMSIM.P19Mode.OFF or p19.mode == SAMSIM.P19Mode.STANDBY then
        return
    end

    -- Get enemy aircraft
    local enemyCoal = (site.coalition == coalition.side.RED) and coalition.side.BLUE or coalition.side.RED
    local enemyGroups = coalition.getAirGroups(enemyCoal)

    for _, group in pairs(enemyGroups) do
        local units = group:getUnits()
        for _, unit in pairs(units) do
            if unit and unit:isExist() and unit:inAir() then
                local targetPos = unit:getPoint()
                local range = SAMSIM.GetDistance3D(p19.position, targetPos)
                local azimuth = SAMSIM.GetAzimuth(p19.position, targetPos)
                local altitude = targetPos.y - p19.position.y

                -- Check range and altitude limits
                if range <= config.MAX_RANGE and range >= config.MIN_RANGE and
                   altitude >= config.MIN_ALTITUDE and altitude <= config.MAX_ALTITUDE then

                    -- Check if target is within current beam
                    local azDiff = math.abs(SAMSIM.AngleDiff(azimuth, p19.antennaAzimuth))

                    if azDiff <= config.BEAM_WIDTH_AZ / 2 then
                        -- Calculate detection probability
                        local rcs = SAMSIM.EstimateRCS(unit, azimuth)
                        local detProb = SAMSIM.CalculateDetectionProbability(range, rcs, config)

                        if math.random() < detProb then
                            -- Add range error
                            local rangeError = (math.random() - 0.5) * config.RANGE_RESOLUTION
                            local azError = (math.random() - 0.5) * 0.5

                            local contact = {
                                id = unit:getID(),
                                time = timer.getTime(),
                                range = range + rangeError,
                                azimuth = azimuth + azError,
                                altitude = altitude,
                                rcs = rcs,
                                unit = unit,
                            }

                            table.insert(p19.contacts, contact)
                        end
                    end
                end
            end
        end
    end
end

function SAMSIM.P19ProcessTracks(site)
    local p19 = site.p19
    local currentTime = timer.getTime()

    -- Correlate contacts with existing tracks
    for _, contact in pairs(p19.contacts) do
        local matched = false

        for trackId, track in pairs(p19.tracks) do
            -- Check if contact matches existing track
            local rangeDiff = math.abs(contact.range - track.range)
            local azDiff = math.abs(SAMSIM.AngleDiff(contact.azimuth, track.azimuth))

            if rangeDiff < 5000 and azDiff < 5 then
                -- Update track
                track.range = contact.range
                track.azimuth = contact.azimuth
                track.altitude = contact.altitude
                track.lastUpdate = currentTime
                track.hits = track.hits + 1
                track.unit = contact.unit
                matched = true
                break
            end
        end

        if not matched then
            -- Create new track
            local trackId = "EW-" .. tostring(#p19.tracks + 1)
            p19.tracks[trackId] = {
                id = trackId,
                range = contact.range,
                azimuth = contact.azimuth,
                altitude = contact.altitude,
                firstSeen = currentTime,
                lastUpdate = currentTime,
                hits = 1,
                unit = contact.unit,
                iff = "UNKNOWN",
            }
        end
    end

    -- Remove stale tracks
    for trackId, track in pairs(p19.tracks) do
        if currentTime - track.lastUpdate > 15 then -- 15 seconds timeout
            p19.tracks[trackId] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- SNR-75 FIRE CONTROL RADAR SIMULATION
--------------------------------------------------------------------------------
function SAMSIM.UpdateSNR75(site, dt)
    local snr75 = site.snr75
    local config = SAMSIM.Config.SNR75

    if snr75.mode == SAMSIM.SNR75Mode.OFF then
        return
    end

    local currentTime = timer.getTime()

    -- Update antenna position based on mode
    if snr75.mode == SAMSIM.SNR75Mode.STANDBY then
        -- Antenna stationary
    elseif snr75.mode == SAMSIM.SNR75Mode.ACQUISITION then
        -- Sector scan for target acquisition
        snr75.scanPhase = snr75.scanPhase + config.SCAN_RATE * dt * snr75.scanDirection
        if math.abs(snr75.scanPhase) > config.SCAN_SECTOR then
            snr75.scanDirection = -snr75.scanDirection
        end
        snr75.antennaAzimuth = SAMSIM.NormalizeAngle(snr75.targetAzimuth + snr75.scanPhase)

        -- Try to acquire target
        SAMSIM.SNR75TryAcquire(site)

    elseif snr75.mode == SAMSIM.SNR75Mode.TRACK_COARSE or
           snr75.mode == SAMSIM.SNR75Mode.TRACK_FINE or
           snr75.mode == SAMSIM.SNR75Mode.GUIDANCE then

        -- Track the target
        if snr75.trackedTarget and snr75.trackedTarget:isExist() then
            SAMSIM.SNR75UpdateTrack(site, dt)
        else
            -- Target lost
            SAMSIM.SNR75TargetLost(site)
        end
    end

    -- Update A-scope and B-scope data
    SAMSIM.SNR75UpdateScopes(site)

    -- Generate firing solution
    if snr75.mode >= SAMSIM.SNR75Mode.TRACK_COARSE then
        SAMSIM.UpdateFiringSolution(site)
    end
end

function SAMSIM.SNR75TryAcquire(site)
    local snr75 = site.snr75
    local config = SAMSIM.Config.SNR75
    local currentTime = timer.getTime()

    -- Check P-19 tracks for targets
    for trackId, track in pairs(site.p19.tracks) do
        if track.unit and track.unit:isExist() then
            local targetPos = track.unit:getPoint()
            local range = SAMSIM.GetDistance3D(snr75.position, targetPos)
            local azimuth = SAMSIM.GetAzimuth(snr75.position, targetPos)
            local elevation = SAMSIM.GetElevation(snr75.position, targetPos)

            -- Check if within FC radar coverage
            if range <= config.MAX_RANGE and range >= config.MIN_RANGE then
                local azDiff = math.abs(SAMSIM.AngleDiff(azimuth, snr75.antennaAzimuth))

                if azDiff <= config.TRACK_BEAM_WIDTH then
                    -- Target acquired!
                    snr75.trackedTarget = track.unit
                    snr75.trackedTargetId = trackId
                    snr75.acquisitionStartTime = currentTime
                    snr75.mode = SAMSIM.SNR75Mode.TRACK_COARSE
                    snr75.targetAzimuth = azimuth
                    snr75.targetElevation = elevation
                    snr75.smoothedRange = range
                    snr75.smoothedAzimuth = azimuth
                    snr75.smoothedElevation = elevation

                    SAMSIM.LogEvent(site, "TRACK", "Target acquired: " .. trackId)
                    return
                end
            end
        end
    end
end

function SAMSIM.SNR75UpdateTrack(site, dt)
    local snr75 = site.snr75
    local config = SAMSIM.Config.SNR75
    local currentTime = timer.getTime()

    local target = snr75.trackedTarget
    local targetPos = target:getPoint()
    local velocity = target:getVelocity()

    -- Calculate actual target parameters
    local range = SAMSIM.GetDistance3D(snr75.position, targetPos)
    local azimuth = SAMSIM.GetAzimuth(snr75.position, targetPos)
    local elevation = SAMSIM.GetElevation(snr75.position, targetPos)

    -- Add tracking errors based on track quality
    local trackAge = currentTime - snr75.acquisitionStartTime
    local qualityFactor = math.min(1, trackAge / config.ACQUISITION_TIME)

    local rangeError = config.RANGE_ACCURACY * (1 - qualityFactor * 0.8) * (math.random() - 0.5)
    local azError = config.ANGLE_ACCURACY * (1 - qualityFactor * 0.8) * (math.random() - 0.5)
    local elError = config.ANGLE_ACCURACY * (1 - qualityFactor * 0.8) * (math.random() - 0.5)

    -- Apply Kalman-like smoothing
    local alpha = 0.3 * qualityFactor
    snr75.smoothedRange = snr75.smoothedRange + alpha * (range + rangeError - snr75.smoothedRange)
    snr75.smoothedAzimuth = snr75.smoothedAzimuth + alpha * SAMSIM.AngleDiff(azimuth + azError, snr75.smoothedAzimuth)
    snr75.smoothedElevation = snr75.smoothedElevation + alpha * (elevation + elError - snr75.smoothedElevation)

    -- Smooth velocity
    snr75.smoothedVelocity.x = snr75.smoothedVelocity.x + alpha * (velocity.x - snr75.smoothedVelocity.x)
    snr75.smoothedVelocity.y = snr75.smoothedVelocity.y + alpha * (velocity.y - snr75.smoothedVelocity.y)
    snr75.smoothedVelocity.z = snr75.smoothedVelocity.z + alpha * (velocity.z - snr75.smoothedVelocity.z)

    -- Point antenna at target
    local azDiff = SAMSIM.AngleDiff(azimuth, snr75.antennaAzimuth)
    local elDiff = elevation - snr75.antennaElevation
    local maxMove = 15 * dt -- 15 deg/sec slew rate

    if math.abs(azDiff) <= maxMove then
        snr75.antennaAzimuth = azimuth
    else
        snr75.antennaAzimuth = SAMSIM.NormalizeAngle(snr75.antennaAzimuth + maxMove * (azDiff > 0 and 1 or -1))
    end

    if math.abs(elDiff) <= maxMove then
        snr75.antennaElevation = elevation
    else
        snr75.antennaElevation = snr75.antennaElevation + maxMove * (elDiff > 0 and 1 or -1)
    end

    -- Update track quality
    local pointingError = math.sqrt(azDiff^2 + elDiff^2)
    local rangeQuality = math.max(0, 100 - range / config.MAX_RANGE * 30)
    local pointingQuality = math.max(0, 100 - pointingError * 20)
    snr75.trackQuality = math.floor((rangeQuality + pointingQuality) / 2 * qualityFactor)

    -- Transition to fine track
    if snr75.mode == SAMSIM.SNR75Mode.TRACK_COARSE and trackAge > config.ACQUISITION_TIME then
        snr75.mode = SAMSIM.SNR75Mode.TRACK_FINE
        snr75.trackEstablishedTime = currentTime
        SAMSIM.LogEvent(site, "TRACK", "Fine track established")
    end

    -- Check for track loss
    local altitude = targetPos.y - snr75.position.y
    if range > config.MAX_RANGE or range < config.MIN_RANGE or
       altitude > config.MAX_ALTITUDE or altitude < config.MIN_ALTITUDE or
       pointingError > 15 then
        snr75.trackLostTime = currentTime
        if currentTime - snr75.trackLostTime > config.TRACK_MEMORY then
            SAMSIM.SNR75TargetLost(site)
        end
    end
end

function SAMSIM.SNR75TargetLost(site)
    local snr75 = site.snr75
    snr75.trackedTarget = nil
    snr75.trackedTargetId = nil
    snr75.trackQuality = 0
    snr75.mode = SAMSIM.SNR75Mode.ACQUISITION

    SAMSIM.LogEvent(site, "TRACK", "Target lost - returning to acquisition")

    -- Clear firing solution
    site.firingSolution.valid = false
end

function SAMSIM.SNR75UpdateScopes(site)
    local snr75 = site.snr75

    -- A-scope: Range display
    snr75.aScopeData = {}
    local numBins = 128
    for i = 1, numBins do
        local noise = math.random() * 0.2
        snr75.aScopeData[i] = noise
    end

    -- Add target return
    if snr75.trackedTarget and snr75.trackedTarget:isExist() then
        local range = snr75.smoothedRange
        local maxRange = SAMSIM.Config.SNR75.MAX_RANGE
        local bin = math.floor(range / maxRange * numBins) + 1
        if bin >= 1 and bin <= numBins then
            local signalStrength = 0.8 * (snr75.trackQuality / 100)
            snr75.aScopeData[bin] = math.min(1, snr75.aScopeData[bin] + signalStrength)
            if bin > 1 then snr75.aScopeData[bin-1] = snr75.aScopeData[bin-1] + signalStrength * 0.3 end
            if bin < numBins then snr75.aScopeData[bin+1] = snr75.aScopeData[bin+1] + signalStrength * 0.3 end
        end
    end

    -- B-scope: Range-Azimuth display
    snr75.bScopeData = {}
end

--------------------------------------------------------------------------------
-- FIRING SOLUTION COMPUTER
--------------------------------------------------------------------------------
function SAMSIM.UpdateFiringSolution(site)
    local snr75 = site.snr75
    local fs = site.firingSolution
    local missileConfig = SAMSIM.Config.MISSILE

    if not snr75.trackedTarget or not snr75.trackedTarget:isExist() then
        fs.valid = false
        return
    end

    local target = snr75.trackedTarget
    local targetPos = target:getPoint()
    local velocity = target:getVelocity()

    -- Basic target data
    fs.targetRange = snr75.smoothedRange
    fs.targetAzimuth = snr75.smoothedAzimuth
    fs.targetElevation = snr75.smoothedElevation
    fs.targetAltitude = targetPos.y

    -- Target velocity
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    fs.targetSpeed = speed

    -- Target heading
    fs.targetHeading = math.deg(math.atan2(velocity.z, velocity.x))
    fs.targetHeading = (90 - fs.targetHeading) % 360

    -- Closure rate
    local dx = snr75.position.x - targetPos.x
    local dz = snr75.position.z - targetPos.z
    local groundDist = math.sqrt(dx*dx + dz*dz)
    if groundDist > 0 then
        fs.closureRate = (velocity.x * dx + velocity.z * dz) / groundDist
    else
        fs.closureRate = 0
    end

    -- Crossing angle (angle between target heading and LOS)
    local losAngle = fs.targetAzimuth
    fs.crossingAngle = math.abs(SAMSIM.AngleDiff(fs.targetHeading, losAngle))
    if fs.crossingAngle > 90 then
        fs.crossingAngle = 180 - fs.crossingAngle
    end

    -- Calculate intercept point (simplified)
    local missileSpeed = missileConfig.MAX_SPEED * 0.8 -- Average speed
    local tof = fs.targetRange / missileSpeed -- Time of flight
    fs.missileFlightTime = tof

    -- Predict target position at intercept
    local predictedX = targetPos.x + velocity.x * tof
    local predictedY = targetPos.y + velocity.y * tof
    local predictedZ = targetPos.z + velocity.z * tof
    fs.interceptPoint = {x = predictedX, y = predictedY, z = predictedZ}
    fs.timeToIntercept = tof

    -- Calculate lead angle
    if groundDist > 0 then
        local leadX = (predictedX - snr75.position.x)
        local leadZ = (predictedZ - snr75.position.z)
        local leadAz = math.deg(math.atan2(leadZ, leadX))
        leadAz = (90 - leadAz) % 360
        fs.leadAngle = SAMSIM.AngleDiff(leadAz, fs.targetAzimuth)
    end

    -- Guidance corrections
    fs.guidanceCorrection.az = fs.leadAngle
    fs.guidanceCorrection.el = 0 -- Simplified

    -- Determine launch zone
    local inRangeMin = fs.targetRange >= missileConfig.MIN_RANGE
    local inRangeMax = fs.targetRange <= missileConfig.MAX_RANGE
    local inAltMin = fs.targetAltitude >= missileConfig.MIN_ALTITUDE
    local inAltMax = fs.targetAltitude <= missileConfig.MAX_ALTITUDE
    local speedOk = speed <= SAMSIM.Config.ENVELOPE.MAX_TARGET_SPEED
    local crossingOk = fs.crossingAngle <= SAMSIM.Config.ENVELOPE.MAX_CROSSING_ANGLE

    if inRangeMin and inRangeMax and inAltMin and inAltMax and speedOk and crossingOk then
        -- Check optimal vs marginal
        local rangeRatio = fs.targetRange / missileConfig.MAX_RANGE
        if rangeRatio > 0.3 and rangeRatio < 0.7 and fs.closureRate > 0 then
            fs.launchZone = "OPTIMAL"
        else
            fs.launchZone = "MARGINAL"
        end
    else
        fs.launchZone = "NONE"
    end

    -- Calculate kill probability (simplified)
    if fs.launchZone ~= "NONE" then
        local basePk = 0.65

        -- Range factor
        local rangeFactor = 1 - (fs.targetRange / missileConfig.MAX_RANGE) * 0.3

        -- Track quality factor
        local qualityFactor = snr75.trackQuality / 100

        -- Crossing angle factor
        local crossingFactor = 1 - (fs.crossingAngle / 90) * 0.4

        -- Speed factor
        local speedFactor = 1 - (speed / SAMSIM.Config.ENVELOPE.MAX_TARGET_SPEED) * 0.2

        fs.killProbability = basePk * rangeFactor * qualityFactor * crossingFactor * speedFactor
        fs.killProbability = math.max(0, math.min(1, fs.killProbability))

        if site.engagement.burstMode then
            -- Two missile salvo
            fs.killProbability = 1 - (1 - fs.killProbability)^2
        end
    else
        fs.killProbability = 0
    end

    fs.valid = true
end

--------------------------------------------------------------------------------
-- MISSILE LAUNCH
--------------------------------------------------------------------------------
function SAMSIM.LaunchMissile(siteId)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    local snr75 = site.snr75
    local fs = site.firingSolution
    local missiles = site.missiles
    local missileConfig = SAMSIM.Config.MISSILE
    local currentTime = timer.getTime()

    -- Pre-launch checks
    if not snr75.trackedTarget then
        SAMSIM.LogEvent(site, "LAUNCH", "ABORT - No target tracked")
        return false
    end

    if missiles.ready <= 0 then
        SAMSIM.LogEvent(site, "LAUNCH", "ABORT - No missiles available")
        return false
    end

    if snr75.mode < SAMSIM.SNR75Mode.TRACK_FINE then
        SAMSIM.LogEvent(site, "LAUNCH", "ABORT - Track not established")
        return false
    end

    if fs.launchZone == "NONE" then
        SAMSIM.LogEvent(site, "LAUNCH", "ABORT - Target outside launch zone")
        return false
    end

    -- Check salvo interval
    if currentTime - missiles.lastLaunchTime < missileConfig.SALVO_INTERVAL then
        SAMSIM.LogEvent(site, "LAUNCH", "ABORT - Salvo interval not elapsed")
        return false
    end

    -- Execute launch
    snr75.mode = SAMSIM.SNR75Mode.GUIDANCE

    -- Command DCS AI to engage
    site.group:getController():setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
    local attackTask = {
        id = 'AttackUnit',
        params = {
            unitId = snr75.trackedTarget:getID(),
            weaponType = 2147485694,
            expend = "One",
            attackQtyLimit = true,
            attackQty = 1,
        }
    }
    site.group:getController():pushTask(attackTask)

    -- Update missile state
    missiles.ready = missiles.ready - 1
    missiles.lastLaunchTime = currentTime
    missiles.salvoCount = missiles.salvoCount + 1

    local missile = {
        launchTime = currentTime,
        targetId = snr75.trackedTargetId,
        flightTime = 0,
        estimatedTOF = fs.missileFlightTime,
        guidanceActive = false,
        status = "BOOST",
    }
    table.insert(missiles.inFlight, missile)

    SAMSIM.LogEvent(site, "LAUNCH", string.format(
        "Missile away! Target: %s, Range: %.1f km, Pk: %.0f%%",
        snr75.trackedTargetId,
        fs.targetRange / 1000,
        fs.killProbability * 100
    ))

    -- Burst mode - launch second missile
    if site.engagement.burstMode and missiles.ready > 0 then
        timer.scheduleFunction(function()
            if site.snr75.trackedTarget and missiles.ready > 0 then
                SAMSIM.LaunchMissile(siteId)
            end
            return nil
        end, nil, currentTime + 3) -- 3 second delay for second missile
    end

    return true
end

function SAMSIM.UpdateMissiles(site)
    local missiles = site.missiles
    local missileConfig = SAMSIM.Config.MISSILE
    local currentTime = timer.getTime()

    local activeMissiles = {}
    for _, missile in pairs(missiles.inFlight) do
        missile.flightTime = currentTime - missile.launchTime

        -- Update guidance status
        if missile.flightTime > missileConfig.GUIDANCE_DELAY then
            missile.guidanceActive = true
            missile.status = "GUIDANCE"
        end

        -- Check if still active
        if missile.flightTime < missileConfig.FLIGHT_TIME_MAX then
            table.insert(activeMissiles, missile)
        else
            missile.status = "TIMEOUT"
            SAMSIM.LogEvent(site, "MISSILE", "Missile timed out")
        end
    end
    missiles.inFlight = activeMissiles

    -- Return to track mode if no missiles in flight
    if #missiles.inFlight == 0 and site.snr75.mode == SAMSIM.SNR75Mode.GUIDANCE then
        if site.snr75.trackedTarget then
            site.snr75.mode = SAMSIM.SNR75Mode.TRACK_FINE
        else
            site.snr75.mode = SAMSIM.SNR75Mode.ACQUISITION
        end
    end
end

--------------------------------------------------------------------------------
-- SYSTEM STATE MANAGEMENT
--------------------------------------------------------------------------------
function SAMSIM.SetSystemState(siteId, state)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    local oldState = site.systemState
    site.systemState = state

    if state == SAMSIM.SystemState.OFFLINE then
        site.p19.mode = SAMSIM.P19Mode.OFF
        site.snr75.mode = SAMSIM.SNR75Mode.OFF
        site.prv11.mode = SAMSIM.PRV11Mode.OFF

    elseif state == SAMSIM.SystemState.STARTUP then
        site.startupTime = timer.getTime()
        SAMSIM.LogEvent(site, "SYSTEM", "System startup initiated")

    elseif state == SAMSIM.SystemState.READY then
        site.p19.mode = SAMSIM.P19Mode.ROTATE
        site.snr75.mode = SAMSIM.SNR75Mode.STANDBY
        SAMSIM.LogEvent(site, "SYSTEM", "System ready")
    end

    return true
end

function SAMSIM.SetP19Mode(siteId, mode)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    site.p19.mode = mode
    SAMSIM.LogEvent(site, "P19", "Mode changed to " .. tostring(mode))
    return true
end

function SAMSIM.SetSNR75Mode(siteId, mode)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    site.snr75.mode = mode
    SAMSIM.LogEvent(site, "SNR75", "Mode changed to " .. tostring(mode))
    return true
end

function SAMSIM.CommandSNR75Antenna(siteId, azimuth, elevation)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    site.snr75.targetAzimuth = SAMSIM.NormalizeAngle(azimuth)
    site.snr75.targetElevation = math.max(0, math.min(85, elevation))
    return true
end

function SAMSIM.DesignateTarget(siteId, trackId)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    -- Look for target in P-19 tracks
    local track = site.p19.tracks[trackId]
    if track and track.unit and track.unit:isExist() then
        site.snr75.targetAzimuth = track.azimuth
        site.snr75.mode = SAMSIM.SNR75Mode.ACQUISITION
        SAMSIM.LogEvent(site, "DESIGNATE", "Target designated: " .. trackId)
        return true
    end

    return false
end

function SAMSIM.DropTrack(siteId)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    SAMSIM.SNR75TargetLost(site)
    return true
end

--------------------------------------------------------------------------------
-- STATUS EXPORT
--------------------------------------------------------------------------------
function SAMSIM.GetSiteStatus(siteId)
    local site = SAMSIM.Sites[siteId]
    if not site then return nil end

    -- P-19 tracks for target list
    local ewTracks = {}
    for trackId, track in pairs(site.p19.tracks) do
        table.insert(ewTracks, {
            id = trackId,
            range = math.floor(track.range),
            azimuth = math.floor(track.azimuth * 10) / 10,
            altitude = math.floor(track.altitude),
            hits = track.hits,
            iff = track.iff,
        })
    end

    -- Tracked target info
    local trackedInfo = nil
    if site.snr75.trackedTarget and site.snr75.trackedTarget:isExist() then
        trackedInfo = {
            id = site.snr75.trackedTargetId,
            range = math.floor(site.snr75.smoothedRange),
            azimuth = math.floor(site.snr75.smoothedAzimuth * 10) / 10,
            elevation = math.floor(site.snr75.smoothedElevation * 10) / 10,
            altitude = math.floor(site.firingSolution.targetAltitude),
            speed = math.floor(site.firingSolution.targetSpeed),
            heading = math.floor(site.firingSolution.targetHeading),
            closure = math.floor(site.firingSolution.closureRate),
            crossing = math.floor(site.firingSolution.crossingAngle),
        }
    end

    return {
        siteId = siteId,
        time = timer.getTime(),

        -- System state
        systemState = site.systemState,

        -- P-19 Early Warning
        p19 = {
            mode = site.p19.mode,
            antennaAz = math.floor(site.p19.antennaAzimuth * 10) / 10,
            tracks = ewTracks,
            noiseLevel = site.p19.noiseLevel,
        },

        -- SNR-75 Fire Control
        snr75 = {
            mode = site.snr75.mode,
            antennaAz = math.floor(site.snr75.antennaAzimuth * 10) / 10,
            antennaEl = math.floor(site.snr75.antennaElevation * 10) / 10,
            tracked = trackedInfo,
            trackQuality = site.snr75.trackQuality,
            aScopeData = site.snr75.aScopeData,
        },

        -- Firing Solution
        firingSolution = {
            valid = site.firingSolution.valid,
            launchZone = site.firingSolution.launchZone,
            killProbability = math.floor(site.firingSolution.killProbability * 100),
            timeToIntercept = math.floor(site.firingSolution.timeToIntercept * 10) / 10,
            leadAngle = math.floor(site.firingSolution.leadAngle * 10) / 10,
        },

        -- Missiles
        missiles = {
            ready = site.missiles.ready,
            total = site.missiles.total,
            inFlight = #site.missiles.inFlight,
        },

        -- Engagement
        engagement = {
            authorized = site.engagement.authorized,
            autoTrack = site.engagement.autoTrack,
            autoEngage = site.engagement.autoEngage,
            burstMode = site.engagement.burstMode,
        },

        -- Recent events
        recentEvents = {},
    }

    -- Add last 5 events
    local eventCount = math.min(5, #site.eventLog)
    for i = #site.eventLog - eventCount + 1, #site.eventLog do
        if site.eventLog[i] then
            table.insert(status.recentEvents, site.eventLog[i])
        end
    end

    return status
end

--------------------------------------------------------------------------------
-- MAIN UPDATE LOOP
--------------------------------------------------------------------------------
function SAMSIM.Update()
    local dt = SAMSIM.Config.UPDATE_INTERVAL
    local currentTime = timer.getTime()

    for siteId, site in pairs(SAMSIM.Sites) do
        -- Check startup completion
        if site.systemState == SAMSIM.SystemState.STARTUP then
            if currentTime - site.startupTime > site.startupDuration then
                SAMSIM.SetSystemState(siteId, SAMSIM.SystemState.READY)
            end
        end

        if site.systemState >= SAMSIM.SystemState.READY then
            -- Update P-19 early warning radar
            SAMSIM.UpdateP19(site, dt)

            -- Update SNR-75 fire control radar
            SAMSIM.UpdateSNR75(site, dt)

            -- Update missiles
            SAMSIM.UpdateMissiles(site)

            -- Update system state based on activity
            if site.snr75.mode >= SAMSIM.SNR75Mode.TRACK_COARSE then
                site.systemState = SAMSIM.SystemState.TRACKING
            elseif #site.missiles.inFlight > 0 then
                site.systemState = SAMSIM.SystemState.ENGAGED
            elseif #site.p19.tracks > 0 then
                site.systemState = SAMSIM.SystemState.ALERT
            else
                site.systemState = SAMSIM.SystemState.READY
            end

            -- Auto-track (designate from EW radar)
            if site.engagement.autoTrack and site.snr75.mode == SAMSIM.SNR75Mode.STANDBY then
                for trackId, track in pairs(site.p19.tracks) do
                    if track.hits >= 3 then -- Confirmed track
                        SAMSIM.DesignateTarget(siteId, trackId)
                        break
                    end
                end
            end

            -- Auto-engage
            if site.engagement.autoEngage and site.engagement.authorized then
                if site.firingSolution.valid and
                   site.firingSolution.launchZone ~= "NONE" and
                   site.snr75.trackQuality > 60 and
                   #site.missiles.inFlight == 0 then
                    SAMSIM.LaunchMissile(siteId)
                end
            end
        end
    end

    return timer.getTime() + SAMSIM.Config.UPDATE_INTERVAL
end

--------------------------------------------------------------------------------
-- COMMAND PROCESSING
--------------------------------------------------------------------------------
function SAMSIM.ProcessCommand(command)
    if not command or not command.cmd then
        return {success = false, error = "Invalid command"}
    end

    local siteId = command.siteId
    local cmd = command.cmd
    local params = command.params or {}

    if cmd == "init_site" then
        local site = SAMSIM.InitSite(params.groupName, siteId)
        return {success = site ~= nil}

    elseif cmd == "set_system_state" then
        return {success = SAMSIM.SetSystemState(siteId, params.state)}

    elseif cmd == "set_p19_mode" then
        return {success = SAMSIM.SetP19Mode(siteId, params.mode)}

    elseif cmd == "set_snr75_mode" then
        return {success = SAMSIM.SetSNR75Mode(siteId, params.mode)}

    elseif cmd == "command_antenna" then
        return {success = SAMSIM.CommandSNR75Antenna(siteId, params.azimuth, params.elevation)}

    elseif cmd == "designate_target" then
        return {success = SAMSIM.DesignateTarget(siteId, params.targetId)}

    elseif cmd == "drop_track" then
        return {success = SAMSIM.DropTrack(siteId)}

    elseif cmd == "launch_missile" then
        return {success = SAMSIM.LaunchMissile(siteId)}

    elseif cmd == "set_engagement" then
        local site = SAMSIM.Sites[siteId]
        if site then
            if params.authorized ~= nil then site.engagement.authorized = params.authorized end
            if params.autoTrack ~= nil then site.engagement.autoTrack = params.autoTrack end
            if params.autoEngage ~= nil then site.engagement.autoEngage = params.autoEngage end
            if params.burstMode ~= nil then site.engagement.burstMode = params.burstMode end
            return {success = true}
        end
        return {success = false}

    elseif cmd == "get_status" then
        return {success = true, data = SAMSIM.GetSiteStatus(siteId)}

    elseif cmd == "get_all_status" then
        local allStatus = {}
        for id, _ in pairs(SAMSIM.Sites) do
            allStatus[id] = SAMSIM.GetSiteStatus(id)
        end
        return {success = true, data = allStatus}

    else
        return {success = false, error = "Unknown command: " .. cmd}
    end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------
function SAMSIM.Init()
    env.info("SAMSIM: Initializing SA-2 SAMSim Controller (Enhanced)...")
    timer.scheduleFunction(SAMSIM.Update, nil, timer.getTime() + 1)
    env.info("SAMSIM: System initialized successfully")
end

SAMSIM.Init()
env.info("SAMSIM: SA-2 SAMSim Controller (Enhanced) loaded")
