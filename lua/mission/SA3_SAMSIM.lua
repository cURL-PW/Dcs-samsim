--[[
    SA-3 Goa (S-125 Neva/Pechora) SAMSim Controller for DCS World

    System Components:
    - P-15 "Flat Face" or P-15M "Squat Eye" Early Warning Radar
    - SNR-125 "Low Blow" Fire Control Radar
    - 5P73 Launcher with V-601P (5V27) missiles

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_SA3 = {}
SAMSIM_SA3.Version = "1.0.0"
SAMSIM_SA3.SystemName = "S-125 Neva/Pechora (SA-3 Goa)"

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_SA3.Config = {
    -- P-15 Early Warning Radar (shared with SA-2 in many configurations)
    P15 = {
        MAX_RANGE = 150000,           -- 150km max detection range
        MIN_RANGE = 1000,             -- 1km minimum range
        MAX_ALTITUDE = 25000,         -- 25km max altitude
        MIN_ALTITUDE = 100,           -- 100m minimum altitude (better low alt than SA-2)
        ROTATION_PERIOD = 6,          -- 6 seconds per rotation
        BEAM_WIDTH_AZ = 2.0,          -- 2 degree azimuth beam width
        BEAM_WIDTH_EL = 6.0,          -- 6 degree elevation beam
        DETECTION_PROB_MAX = 0.92,
        MIN_RCS = 0.5,                -- Better sensitivity than P-19
        POWER_KW = 380,
        FREQUENCY_MHZ = 800,          -- UHF band
    },

    -- SNR-125 "Low Blow" Fire Control Radar
    SNR125 = {
        MAX_RANGE = 50000,            -- 50km max tracking range
        MIN_RANGE = 3500,             -- 3.5km minimum engagement range
        MAX_ALTITUDE = 18000,         -- 18km max engagement altitude
        MIN_ALTITUDE = 20,            -- 20m minimum (excellent low altitude)
        TRACK_BEAM_WIDTH = 1.2,       -- 1.2 degree beam width
        ACQUISITION_BEAM_WIDTH = 4.0, -- 4 degree acquisition beam
        ACQUISITION_TIME = 2.5,       -- Time to acquire target (seconds)
        TRACK_PRECISION = 0.5,        -- 0.5 mrad tracking precision
        MAX_TRACK_TARGETS = 1,        -- Single target tracker
        ANTENNA_SLEW_RATE = 18,       -- 18 deg/sec antenna slew
        POWER_KW = 250,
        FREQUENCY_GHZ = 6.0,          -- C-band (different from SA-2)
    },

    -- V-601P (5V27) Missile
    Missile = {
        MAX_RANGE = 25000,            -- 25km max range
        MIN_RANGE = 3500,             -- 3.5km minimum range
        MAX_ALTITUDE = 18000,         -- 18km ceiling
        MIN_ALTITUDE = 20,            -- 20m minimum
        MAX_SPEED = 1000,             -- ~Mach 3
        ACCELERATION = 35,            -- 35g max
        GUIDANCE = "CLOS",            -- Command Line Of Sight
        WARHEAD_KG = 60,              -- 60kg warhead
        PROXIMITY_FUZE_M = 12,        -- 12m proximity fuze
        SALVO_SIZE = 2,               -- Typical 2-missile salvo
        RELOAD_TIME = 15,             -- 15 seconds reload
    },

    -- System settings
    System = {
        READY_TIME = 4,               -- 4 minutes from cold start
        REACTION_TIME = 26,           -- 26 seconds reaction time
        MAX_SIMULTANEOUS_MISSILES = 2,
    },

    -- Update rates
    UPDATE_INTERVAL = 0.05,
    NETWORK_INTERVAL = 0.1,
}

-- ============================================================================
-- System States
-- ============================================================================
SAMSIM_SA3.P15Mode = {
    OFF = 0,
    STANDBY = 1,
    ROTATE = 2,
    SECTOR = 3,
}

SAMSIM_SA3.SNR125Mode = {
    OFF = 0,
    STANDBY = 1,
    ACQUISITION = 2,
    TRACK = 3,
    TRACK_MEMORY = 4,      -- Track memory when target fades
    GUIDANCE = 5,
}

SAMSIM_SA3.SystemStatus = {
    OFF = 0,
    STARTUP = 1,
    READY = 2,
    ENGAGED = 3,
    COOLDOWN = 4,
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_SA3.State = {
    -- System state
    status = 0,
    startupTimer = 0,

    -- P-15 radar state
    p15 = {
        mode = 0,
        azimuth = 0,
        sectorCenter = 0,
        sectorWidth = 60,
        contacts = {},
        selectedContact = nil,
    },

    -- SNR-125 radar state
    snr125 = {
        mode = 0,
        azimuth = 0,
        elevation = 15,
        targetAzimuth = 0,
        targetElevation = 0,
        targetRange = 0,
        acquisitionTimer = 0,
        trackQuality = 0,
        trackMemoryTimer = 0,
        antennaAz = 0,
        antennaEl = 0,
    },

    -- Track data
    track = {
        valid = false,
        id = nil,
        position = {x=0, y=0, z=0},
        velocity = {x=0, y=0, z=0},
        range = 0,
        azimuth = 0,
        elevation = 0,
        speed = 0,
        heading = 0,
        altitude = 0,
        rcs = 1.0,
        lastUpdate = 0,
        smoothedPosition = {x=0, y=0, z=0},
        smoothedVelocity = {x=0, y=0, z=0},
        predictionTime = 0,
    },

    -- Firing solution
    firingSolution = {
        valid = false,
        interceptPoint = {x=0, y=0, z=0},
        timeToIntercept = 0,
        inEnvelope = false,
        inRangeMax = false,
        inRangeMin = false,
        inAltitude = false,
        leadAngle = 0,
        pk = 0,
    },

    -- Missile state
    missiles = {
        ready = 4,           -- 4-rail launcher
        inFlight = 0,
        launched = {},
    },

    -- Site configuration
    site = {
        position = {x=0, y=0, z=0},
        heading = 0,
        name = "SA3_Site",
    },
}

-- ============================================================================
-- Utility Functions
-- ============================================================================
local function deepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = deepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

local function vectorMagnitude(v)
    return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
end

local function vectorSubtract(a, b)
    return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
end

local function vectorAdd(a, b)
    return {x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}
end

local function vectorScale(v, s)
    return {x = v.x * s, y = v.y * s, z = v.z * s}
end

local function normalizeAngle(angle)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

-- ============================================================================
-- RCS Estimation
-- ============================================================================
SAMSIM_SA3.RCSDatabase = {
    -- Fighters
    ["F-15C"] = 5.0,
    ["F-15E"] = 6.0,
    ["F-16C"] = 1.2,
    ["F-16CM"] = 1.0,
    ["FA-18C"] = 1.5,
    ["F-14A"] = 10.0,
    ["F-14B"] = 10.0,
    ["F-4E"] = 8.0,
    ["MiG-21"] = 3.0,
    ["MiG-23"] = 5.0,
    ["MiG-29A"] = 3.0,
    ["MiG-29S"] = 2.5,
    ["MiG-31"] = 15.0,
    ["Su-27"] = 10.0,
    ["Su-33"] = 12.0,
    ["Su-25"] = 8.0,
    ["Su-25T"] = 7.0,
    ["A-10A"] = 15.0,
    ["A-10C"] = 14.0,
    ["AV-8B"] = 5.0,
    ["M-2000C"] = 1.5,
    ["JF-17"] = 2.0,

    -- Modern low-observable
    ["F-22A"] = 0.0001,
    ["F-35A"] = 0.001,
    ["B-2A"] = 0.01,

    -- Bombers
    ["B-52H"] = 100.0,
    ["B-1B"] = 10.0,
    ["Tu-22M3"] = 40.0,
    ["Tu-95MS"] = 80.0,
    ["Tu-160"] = 25.0,

    -- Helicopters
    ["UH-1H"] = 5.0,
    ["AH-64A"] = 4.0,
    ["AH-64D"] = 3.5,
    ["Ka-50"] = 4.0,
    ["Mi-24P"] = 10.0,
    ["Mi-8"] = 15.0,

    -- Default
    DEFAULT = 5.0,
}

function SAMSIM_SA3.estimateRCS(typeName)
    for pattern, rcs in pairs(SAMSIM_SA3.RCSDatabase) do
        if pattern ~= "DEFAULT" and string.find(typeName, pattern) then
            return rcs
        end
    end
    return SAMSIM_SA3.RCSDatabase.DEFAULT
end

-- ============================================================================
-- P-15 Radar Simulation
-- ============================================================================
function SAMSIM_SA3.updateP15(dt)
    local state = SAMSIM_SA3.State.p15
    local config = SAMSIM_SA3.Config.P15

    if state.mode == SAMSIM_SA3.P15Mode.OFF then
        return
    end

    if state.mode == SAMSIM_SA3.P15Mode.STANDBY then
        return
    end

    -- Update antenna rotation
    if state.mode == SAMSIM_SA3.P15Mode.ROTATE then
        state.azimuth = state.azimuth + (360 / config.ROTATION_PERIOD) * dt
        if state.azimuth >= 360 then
            state.azimuth = state.azimuth - 360
        end
    elseif state.mode == SAMSIM_SA3.P15Mode.SECTOR then
        -- Sector scan implementation
        local halfWidth = state.sectorWidth / 2
        local minAz = state.sectorCenter - halfWidth
        local maxAz = state.sectorCenter + halfWidth

        if not state.sectorDirection then state.sectorDirection = 1 end

        state.azimuth = state.azimuth + state.sectorDirection * (360 / config.ROTATION_PERIOD) * 1.5 * dt

        if state.azimuth > maxAz then
            state.azimuth = maxAz
            state.sectorDirection = -1
        elseif state.azimuth < minAz then
            state.azimuth = minAz
            state.sectorDirection = 1
        end
    end

    -- Search for contacts
    SAMSIM_SA3.scanForContacts()
end

function SAMSIM_SA3.scanForContacts()
    local state = SAMSIM_SA3.State.p15
    local config = SAMSIM_SA3.Config.P15
    local sitePos = SAMSIM_SA3.State.site.position

    -- Get all air objects
    local sphere = {
        id = world.VolumeType.SPHERE,
        params = {
            point = sitePos,
            radius = config.MAX_RANGE
        }
    }

    local foundObjects = {}
    local handler = function(foundItem)
        if foundItem:getCategory() == Object.Category.UNIT then
            local desc = foundItem:getDesc()
            if desc.category == Unit.Category.AIRPLANE or desc.category == Unit.Category.HELICOPTER then
                table.insert(foundObjects, foundItem)
            end
        end
        return true
    end

    world.searchObjects(Object.Category.UNIT, sphere, handler)

    -- Process contacts
    local currentTime = timer.getTime()
    local currentContacts = {}

    for _, obj in ipairs(foundObjects) do
        local pos = obj:getPoint()
        local relPos = vectorSubtract(pos, sitePos)
        local range = vectorMagnitude(relPos)
        local azimuth = math.deg(math.atan2(relPos.x, relPos.z))
        if azimuth < 0 then azimuth = azimuth + 360 end
        local altitude = pos.y

        -- Check altitude limits (SA-3 has better low altitude capability)
        if altitude >= config.MIN_ALTITUDE and altitude <= config.MAX_ALTITUDE then
            -- Check if in beam
            local azDiff = math.abs(normalizeAngle(azimuth - state.azimuth))
            if azDiff <= config.BEAM_WIDTH_AZ / 2 then
                -- Calculate detection probability
                local rcs = SAMSIM_SA3.estimateRCS(obj:getTypeName())
                local detectionProb = SAMSIM_SA3.calculateDetectionProbability(range, rcs, altitude, config)

                if math.random() < detectionProb then
                    local id = obj:getID()
                    currentContacts[id] = {
                        id = id,
                        name = obj:getName(),
                        typeName = obj:getTypeName(),
                        position = pos,
                        range = range,
                        azimuth = azimuth,
                        altitude = altitude,
                        rcs = rcs,
                        lastSeen = currentTime,
                        velocity = obj:getVelocity(),
                        heading = math.deg(math.atan2(obj:getVelocity().x, obj:getVelocity().z)),
                        speed = vectorMagnitude(obj:getVelocity()),
                    }
                end
            end
        end
    end

    -- Merge with existing contacts
    for id, contact in pairs(currentContacts) do
        state.contacts[id] = contact
    end

    -- Age out old contacts
    for id, contact in pairs(state.contacts) do
        if currentTime - contact.lastSeen > 8 then  -- 8 second track memory
            state.contacts[id] = nil
        end
    end
end

function SAMSIM_SA3.calculateDetectionProbability(range, rcs, altitude, config)
    -- Enhanced detection at low altitude compared to SA-2
    local rangeNorm = range / config.MAX_RANGE
    local rangeFactor = math.max(0, 1 - rangeNorm^2)

    local rcsFactor = math.min(1, math.sqrt(rcs / config.MIN_RCS))

    -- Better low altitude performance
    local altFactor = 1.0
    if altitude < 500 then
        altFactor = 0.8 + 0.2 * (altitude / 500)
    end

    local prob = config.DETECTION_PROB_MAX * rangeFactor * rcsFactor * altFactor

    return math.max(0, math.min(1, prob))
end

-- ============================================================================
-- SNR-125 Fire Control Radar Simulation
-- ============================================================================
function SAMSIM_SA3.updateSNR125(dt)
    local state = SAMSIM_SA3.State.snr125
    local track = SAMSIM_SA3.State.track
    local config = SAMSIM_SA3.Config.SNR125

    if state.mode == SAMSIM_SA3.SNR125Mode.OFF then
        track.valid = false
        return
    end

    if state.mode == SAMSIM_SA3.SNR125Mode.STANDBY then
        track.valid = false
        return
    end

    -- Antenna slew simulation
    local azDiff = normalizeAngle(state.targetAzimuth - state.antennaAz)
    local elDiff = state.targetElevation - state.antennaEl
    local slewRate = config.ANTENNA_SLEW_RATE * dt

    if math.abs(azDiff) > slewRate then
        state.antennaAz = state.antennaAz + slewRate * (azDiff > 0 and 1 or -1)
    else
        state.antennaAz = state.targetAzimuth
    end

    if math.abs(elDiff) > slewRate then
        state.antennaEl = state.antennaEl + slewRate * (elDiff > 0 and 1 or -1)
    else
        state.antennaEl = state.targetElevation
    end

    state.antennaAz = normalizeAngle(state.antennaAz)
    state.antennaEl = math.max(0, math.min(85, state.antennaEl))

    if state.mode == SAMSIM_SA3.SNR125Mode.ACQUISITION then
        SAMSIM_SA3.processAcquisition(dt)
    elseif state.mode == SAMSIM_SA3.SNR125Mode.TRACK then
        SAMSIM_SA3.processTrack(dt)
    elseif state.mode == SAMSIM_SA3.SNR125Mode.TRACK_MEMORY then
        SAMSIM_SA3.processTrackMemory(dt)
    elseif state.mode == SAMSIM_SA3.SNR125Mode.GUIDANCE then
        SAMSIM_SA3.processGuidance(dt)
    end
end

function SAMSIM_SA3.processAcquisition(dt)
    local state = SAMSIM_SA3.State.snr125
    local p15 = SAMSIM_SA3.State.p15
    local config = SAMSIM_SA3.Config.SNR125

    if not p15.selectedContact then
        return
    end

    local contact = p15.contacts[p15.selectedContact]
    if not contact then
        return
    end

    -- Point antenna at designated target
    state.targetAzimuth = contact.azimuth
    state.targetElevation = math.deg(math.atan2(contact.altitude,
        math.sqrt((contact.position.x - SAMSIM_SA3.State.site.position.x)^2 +
                  (contact.position.z - SAMSIM_SA3.State.site.position.z)^2)))

    -- Check if antenna is pointing at target
    local azError = math.abs(normalizeAngle(state.antennaAz - contact.azimuth))
    local elError = math.abs(state.antennaEl - state.targetElevation)

    if azError < config.ACQUISITION_BEAM_WIDTH / 2 and elError < config.ACQUISITION_BEAM_WIDTH / 2 then
        state.acquisitionTimer = state.acquisitionTimer + dt

        if state.acquisitionTimer >= config.ACQUISITION_TIME then
            -- Target acquired, transition to track
            state.mode = SAMSIM_SA3.SNR125Mode.TRACK
            state.trackQuality = 0.5
            SAMSIM_SA3.initializeTrack(contact)
        end
    else
        state.acquisitionTimer = math.max(0, state.acquisitionTimer - dt * 0.5)
    end
end

function SAMSIM_SA3.initializeTrack(contact)
    local track = SAMSIM_SA3.State.track
    track.valid = true
    track.id = contact.id
    track.position = deepCopy(contact.position)
    track.velocity = deepCopy(contact.velocity)
    track.smoothedPosition = deepCopy(contact.position)
    track.smoothedVelocity = deepCopy(contact.velocity)
    track.range = contact.range
    track.azimuth = contact.azimuth
    track.altitude = contact.altitude
    track.rcs = contact.rcs
    track.lastUpdate = timer.getTime()
end

function SAMSIM_SA3.processTrack(dt)
    local state = SAMSIM_SA3.State.snr125
    local track = SAMSIM_SA3.State.track
    local config = SAMSIM_SA3.Config.SNR125

    if not track.valid or not track.id then
        state.mode = SAMSIM_SA3.SNR125Mode.ACQUISITION
        return
    end

    -- Try to get current target data
    local targetUnit = Unit.getByName(SAMSIM_SA3.State.p15.contacts[track.id] and
                                       SAMSIM_SA3.State.p15.contacts[track.id].name or "")

    if not targetUnit then
        -- Try by ID
        for _, contact in pairs(SAMSIM_SA3.State.p15.contacts) do
            if contact.id == track.id then
                targetUnit = Unit.getByName(contact.name)
                break
            end
        end
    end

    if targetUnit and targetUnit:isExist() then
        local pos = targetUnit:getPoint()
        local vel = targetUnit:getVelocity()
        local sitePos = SAMSIM_SA3.State.site.position
        local relPos = vectorSubtract(pos, sitePos)

        -- Update track with smoothing
        local alpha = 0.3
        track.smoothedPosition.x = track.smoothedPosition.x + alpha * (pos.x - track.smoothedPosition.x)
        track.smoothedPosition.y = track.smoothedPosition.y + alpha * (pos.y - track.smoothedPosition.y)
        track.smoothedPosition.z = track.smoothedPosition.z + alpha * (pos.z - track.smoothedPosition.z)

        track.smoothedVelocity.x = track.smoothedVelocity.x + alpha * (vel.x - track.smoothedVelocity.x)
        track.smoothedVelocity.y = track.smoothedVelocity.y + alpha * (vel.y - track.smoothedVelocity.y)
        track.smoothedVelocity.z = track.smoothedVelocity.z + alpha * (vel.z - track.smoothedVelocity.z)

        track.position = pos
        track.velocity = vel
        track.range = vectorMagnitude(relPos)
        track.azimuth = math.deg(math.atan2(relPos.x, relPos.z))
        if track.azimuth < 0 then track.azimuth = track.azimuth + 360 end
        track.elevation = math.deg(math.atan2(pos.y - sitePos.y,
            math.sqrt(relPos.x^2 + relPos.z^2)))
        track.altitude = pos.y
        track.speed = vectorMagnitude(vel)
        track.heading = math.deg(math.atan2(vel.x, vel.z))
        track.lastUpdate = timer.getTime()

        -- Point antenna at target
        state.targetAzimuth = track.azimuth
        state.targetElevation = track.elevation

        -- Calculate track quality
        local azError = math.abs(normalizeAngle(state.antennaAz - track.azimuth))
        local elError = math.abs(state.antennaEl - track.elevation)
        local totalError = math.sqrt(azError^2 + elError^2)

        state.trackQuality = math.max(0, math.min(1, 1 - totalError / config.TRACK_BEAM_WIDTH))

        -- Check if still tracking
        if totalError > config.TRACK_BEAM_WIDTH * 2 then
            state.mode = SAMSIM_SA3.SNR125Mode.TRACK_MEMORY
            state.trackMemoryTimer = 0
        end
    else
        state.mode = SAMSIM_SA3.SNR125Mode.TRACK_MEMORY
        state.trackMemoryTimer = 0
    end

    -- Update firing solution
    SAMSIM_SA3.calculateFiringSolution()
end

function SAMSIM_SA3.processTrackMemory(dt)
    local state = SAMSIM_SA3.State.snr125
    local track = SAMSIM_SA3.State.track

    state.trackMemoryTimer = state.trackMemoryTimer + dt
    state.trackQuality = math.max(0, state.trackQuality - dt * 0.2)

    -- Predict position based on last known velocity
    track.smoothedPosition = vectorAdd(track.smoothedPosition, vectorScale(track.smoothedVelocity, dt))

    -- Update antenna target
    local relPos = vectorSubtract(track.smoothedPosition, SAMSIM_SA3.State.site.position)
    state.targetAzimuth = math.deg(math.atan2(relPos.x, relPos.z))
    state.targetElevation = math.deg(math.atan2(track.smoothedPosition.y,
        math.sqrt(relPos.x^2 + relPos.z^2)))

    -- Try to reacquire
    if state.trackMemoryTimer > 5 then
        state.mode = SAMSIM_SA3.SNR125Mode.ACQUISITION
        track.valid = false
    end
end

function SAMSIM_SA3.processGuidance(dt)
    -- CLOS guidance - similar to track but with missile guidance updates
    SAMSIM_SA3.processTrack(dt)

    local missiles = SAMSIM_SA3.State.missiles
    local track = SAMSIM_SA3.State.track

    if missiles.inFlight == 0 then
        SAMSIM_SA3.State.snr125.mode = SAMSIM_SA3.SNR125Mode.TRACK
    end
end

-- ============================================================================
-- Firing Solution Calculator
-- ============================================================================
function SAMSIM_SA3.calculateFiringSolution()
    local track = SAMSIM_SA3.State.track
    local solution = SAMSIM_SA3.State.firingSolution
    local missileConfig = SAMSIM_SA3.Config.Missile
    local snrConfig = SAMSIM_SA3.Config.SNR125
    local sitePos = SAMSIM_SA3.State.site.position

    if not track.valid then
        solution.valid = false
        return
    end

    -- Calculate relative geometry
    local relPos = vectorSubtract(track.smoothedPosition, sitePos)
    local range = vectorMagnitude(relPos)
    local altitude = track.altitude

    -- Simple intercept calculation for CLOS
    local closingSpeed = 0
    local relVel = track.smoothedVelocity
    local rangeUnitVector = vectorScale(relPos, 1/range)
    closingSpeed = -(relVel.x * rangeUnitVector.x + relVel.y * rangeUnitVector.y + relVel.z * rangeUnitVector.z)

    -- Estimate time to intercept
    local missileAvgSpeed = missileConfig.MAX_SPEED * 0.7
    local timeToIntercept = range / (missileAvgSpeed + closingSpeed)

    -- Predict intercept point
    local interceptPoint = vectorAdd(track.smoothedPosition, vectorScale(track.smoothedVelocity, timeToIntercept))

    -- Calculate lead angle for CLOS
    local interceptRelPos = vectorSubtract(interceptPoint, sitePos)
    local leadAngle = math.deg(math.acos(
        (relPos.x * interceptRelPos.x + relPos.y * interceptRelPos.y + relPos.z * interceptRelPos.z) /
        (vectorMagnitude(relPos) * vectorMagnitude(interceptRelPos))
    ))

    solution.interceptPoint = interceptPoint
    solution.timeToIntercept = timeToIntercept
    solution.leadAngle = leadAngle

    -- Check engagement envelope
    solution.inRangeMax = range <= missileConfig.MAX_RANGE
    solution.inRangeMin = range >= missileConfig.MIN_RANGE
    solution.inAltitude = altitude >= missileConfig.MIN_ALTITUDE and altitude <= missileConfig.MAX_ALTITUDE
    solution.inEnvelope = solution.inRangeMax and solution.inRangeMin and solution.inAltitude

    -- Calculate Pk (simplified model)
    local rangeFactor = 1 - (range / missileConfig.MAX_RANGE)^2
    local altFactor = 1.0
    if altitude < 500 then
        altFactor = 0.9  -- SA-3 is better at low altitude
    end
    local trackQualityFactor = SAMSIM_SA3.State.snr125.trackQuality
    local aspectFactor = 0.9  -- Simplified

    solution.pk = math.max(0, math.min(0.85,
        0.75 * rangeFactor * altFactor * trackQualityFactor * aspectFactor))

    solution.valid = solution.inEnvelope and SAMSIM_SA3.State.snr125.trackQuality > 0.3
end

-- ============================================================================
-- Missile Launch
-- ============================================================================
function SAMSIM_SA3.launchMissile()
    local state = SAMSIM_SA3.State
    local solution = state.firingSolution
    local missiles = state.missiles

    if not solution.valid then
        return false, "No valid firing solution"
    end

    if missiles.ready <= 0 then
        return false, "No missiles ready"
    end

    if missiles.inFlight >= SAMSIM_SA3.Config.System.MAX_SIMULTANEOUS_MISSILES then
        return false, "Maximum missiles in flight"
    end

    missiles.ready = missiles.ready - 1
    missiles.inFlight = missiles.inFlight + 1

    table.insert(missiles.launched, {
        launchTime = timer.getTime(),
        targetId = state.track.id,
        interceptPoint = deepCopy(solution.interceptPoint),
        timeToIntercept = solution.timeToIntercept,
    })

    -- Switch to guidance mode
    state.snr125.mode = SAMSIM_SA3.SNR125Mode.GUIDANCE

    return true, "Missile launched"
end

-- ============================================================================
-- Command Interface
-- ============================================================================
function SAMSIM_SA3.processCommand(cmd)
    local response = {success = false, message = "Unknown command"}

    if cmd.type == "POWER" then
        if cmd.system == "P15" then
            if cmd.state == "ON" then
                SAMSIM_SA3.State.p15.mode = SAMSIM_SA3.P15Mode.STANDBY
            else
                SAMSIM_SA3.State.p15.mode = SAMSIM_SA3.P15Mode.OFF
            end
            response = {success = true, message = "P-15 power " .. cmd.state}
        elseif cmd.system == "SNR125" then
            if cmd.state == "ON" then
                SAMSIM_SA3.State.snr125.mode = SAMSIM_SA3.SNR125Mode.STANDBY
            else
                SAMSIM_SA3.State.snr125.mode = SAMSIM_SA3.SNR125Mode.OFF
            end
            response = {success = true, message = "SNR-125 power " .. cmd.state}
        end

    elseif cmd.type == "P15_MODE" then
        if cmd.mode == "ROTATE" then
            SAMSIM_SA3.State.p15.mode = SAMSIM_SA3.P15Mode.ROTATE
        elseif cmd.mode == "SECTOR" then
            SAMSIM_SA3.State.p15.mode = SAMSIM_SA3.P15Mode.SECTOR
            if cmd.center then SAMSIM_SA3.State.p15.sectorCenter = cmd.center end
            if cmd.width then SAMSIM_SA3.State.p15.sectorWidth = cmd.width end
        elseif cmd.mode == "STANDBY" then
            SAMSIM_SA3.State.p15.mode = SAMSIM_SA3.P15Mode.STANDBY
        end
        response = {success = true, message = "P-15 mode set to " .. cmd.mode}

    elseif cmd.type == "DESIGNATE" then
        SAMSIM_SA3.State.p15.selectedContact = cmd.targetId
        SAMSIM_SA3.State.snr125.mode = SAMSIM_SA3.SNR125Mode.ACQUISITION
        SAMSIM_SA3.State.snr125.acquisitionTimer = 0
        response = {success = true, message = "Target designated"}

    elseif cmd.type == "SNR125_MODE" then
        if cmd.mode == "TRACK" then
            SAMSIM_SA3.State.snr125.mode = SAMSIM_SA3.SNR125Mode.TRACK
        elseif cmd.mode == "STANDBY" then
            SAMSIM_SA3.State.snr125.mode = SAMSIM_SA3.SNR125Mode.STANDBY
        end
        response = {success = true, message = "SNR-125 mode set to " .. cmd.mode}

    elseif cmd.type == "LAUNCH" then
        local success, msg = SAMSIM_SA3.launchMissile()
        response = {success = success, message = msg}

    elseif cmd.type == "ANTENNA" then
        if cmd.azimuth then SAMSIM_SA3.State.snr125.targetAzimuth = cmd.azimuth end
        if cmd.elevation then SAMSIM_SA3.State.snr125.targetElevation = cmd.elevation end
        response = {success = true, message = "Antenna command accepted"}
    end

    return response
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM_SA3.getStateForExport()
    local state = SAMSIM_SA3.State

    -- Prepare contacts list
    local contactsList = {}
    for id, contact in pairs(state.p15.contacts) do
        table.insert(contactsList, {
            id = id,
            typeName = contact.typeName,
            range = math.floor(contact.range),
            azimuth = math.floor(contact.azimuth * 10) / 10,
            altitude = math.floor(contact.altitude),
            speed = math.floor(contact.speed),
            heading = math.floor(contact.heading),
        })
    end

    return {
        systemType = "SA3",
        systemName = SAMSIM_SA3.SystemName,
        timestamp = timer.getTime(),

        p15 = {
            mode = state.p15.mode,
            modeName = SAMSIM_SA3.getModeNameP15(state.p15.mode),
            azimuth = state.p15.azimuth,
            sectorCenter = state.p15.sectorCenter,
            sectorWidth = state.p15.sectorWidth,
            contactCount = #contactsList,
        },

        snr125 = {
            mode = state.snr125.mode,
            modeName = SAMSIM_SA3.getModeNameSNR125(state.snr125.mode),
            antennaAz = state.snr125.antennaAz,
            antennaEl = state.snr125.antennaEl,
            targetAzimuth = state.snr125.targetAzimuth,
            targetElevation = state.snr125.targetElevation,
            trackQuality = state.snr125.trackQuality,
            acquisitionProgress = state.snr125.acquisitionTimer / SAMSIM_SA3.Config.SNR125.ACQUISITION_TIME,
        },

        contacts = contactsList,
        selectedContact = state.p15.selectedContact,

        track = {
            valid = state.track.valid,
            range = state.track.range,
            azimuth = state.track.azimuth,
            elevation = state.track.elevation,
            altitude = state.track.altitude,
            speed = state.track.speed,
            heading = state.track.heading,
        },

        firingSolution = {
            valid = state.firingSolution.valid,
            inEnvelope = state.firingSolution.inEnvelope,
            inRangeMax = state.firingSolution.inRangeMax,
            inRangeMin = state.firingSolution.inRangeMin,
            inAltitude = state.firingSolution.inAltitude,
            timeToIntercept = state.firingSolution.timeToIntercept,
            pk = state.firingSolution.pk,
        },

        missiles = {
            ready = state.missiles.ready,
            inFlight = state.missiles.inFlight,
        },

        config = {
            p15MaxRange = SAMSIM_SA3.Config.P15.MAX_RANGE,
            snr125MaxRange = SAMSIM_SA3.Config.SNR125.MAX_RANGE,
            missileMaxRange = SAMSIM_SA3.Config.Missile.MAX_RANGE,
            missileMinRange = SAMSIM_SA3.Config.Missile.MIN_RANGE,
        },
    }
end

function SAMSIM_SA3.getModeNameP15(mode)
    local names = {"OFF", "STANDBY", "ROTATE", "SECTOR"}
    return names[mode + 1] or "UNKNOWN"
end

function SAMSIM_SA3.getModeNameSNR125(mode)
    local names = {"OFF", "STANDBY", "ACQUISITION", "TRACK", "TRACK_MEMORY", "GUIDANCE"}
    return names[mode + 1] or "UNKNOWN"
end

-- ============================================================================
-- Main Update Loop
-- ============================================================================
function SAMSIM_SA3.update()
    local currentTime = timer.getTime()
    if not SAMSIM_SA3.lastUpdate then
        SAMSIM_SA3.lastUpdate = currentTime
    end

    local dt = currentTime - SAMSIM_SA3.lastUpdate
    SAMSIM_SA3.lastUpdate = currentTime

    -- Update subsystems
    SAMSIM_SA3.updateP15(dt)
    SAMSIM_SA3.updateSNR125(dt)

    -- Schedule next update
    return timer.getTime() + SAMSIM_SA3.Config.UPDATE_INTERVAL
end

-- ============================================================================
-- Initialization
-- ============================================================================
function SAMSIM_SA3.initialize(siteName, position, heading)
    SAMSIM_SA3.State.site.name = siteName or "SA3_Site"
    SAMSIM_SA3.State.site.position = position or {x=0, y=0, z=0}
    SAMSIM_SA3.State.site.heading = heading or 0

    SAMSIM_SA3.State.missiles.ready = 4
    SAMSIM_SA3.State.missiles.inFlight = 0
    SAMSIM_SA3.State.missiles.launched = {}

    -- Start update timer
    timer.scheduleFunction(SAMSIM_SA3.update, nil, timer.getTime() + 0.1)

    env.info("SAMSIM SA-3: Initialized site " .. SAMSIM_SA3.State.site.name)
end

env.info("SAMSIM SA-3 (S-125 Neva/Pechora) Controller loaded - Version " .. SAMSIM_SA3.Version)
