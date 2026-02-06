--[[
    SA-10 Grumble (S-300PS) SAMSim Controller for DCS World

    System Components:
    - 64N6 "Big Bird" Surveillance Radar
    - 76N6 "Clam Shell" Low Altitude Detection Radar
    - 30N6 "Flap Lid" Fire Control/Engagement Radar
    - 5P85 TEL with 5V55R missiles

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_SA10 = {}
SAMSIM_SA10.Version = "1.0.0"
SAMSIM_SA10.SystemName = "S-300PS (SA-10 Grumble)"

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_SA10.Config = {
    -- 64N6 "Big Bird" Surveillance Radar
    BigBird = {
        MAX_RANGE = 300000,           -- 300km
        MIN_RANGE = 2000,
        MAX_ALTITUDE = 40000,         -- 40km (can detect ballistic targets)
        MIN_ALTITUDE = 25,            -- 25m with clam shell assist
        ROTATION_PERIOD = 12,         -- 12 seconds
        BEAM_WIDTH_AZ = 1.5,
        BEAM_WIDTH_EL = 20,           -- Stacked beams
        DETECTION_PROB_MAX = 0.95,
        POWER_KW = 1400,
        FREQUENCY_MHZ = 2000,         -- S-band
        MAX_TRACKS = 100,             -- Can track 100 targets
    },

    -- 76N6 "Clam Shell" Low Altitude Radar
    ClamShell = {
        MAX_RANGE = 90000,
        MIN_RANGE = 500,
        MAX_ALTITUDE = 6000,
        MIN_ALTITUDE = 10,            -- Excellent low altitude
        ROTATION_PERIOD = 6,
        DETECTION_PROB_MAX = 0.92,
    },

    -- 30N6 "Flap Lid" Engagement Radar
    FlapLid = {
        MAX_RANGE = 200000,           -- 200km track range
        MIN_RANGE = 5000,
        MAX_ALTITUDE = 30000,
        TRACK_BEAM_WIDTH = 0.5,       -- Very narrow beam
        ACQUISITION_BEAM_WIDTH = 2.0,
        ACQUISITION_TIME = 1.5,       -- Very fast acquisition
        TRACK_PRECISION = 0.1,        -- mrad - very precise
        MAX_SIMULTANEOUS_TARGETS = 6, -- Can engage 6 targets
        ANTENNA_SLEW_RATE = 30,       -- deg/sec
        POWER_KW = 600,
        FREQUENCY_GHZ = 10,           -- X-band
        TVM_UPLINK = true,            -- Track Via Missile capability
    },

    -- 5V55R Missile
    Missile = {
        MAX_RANGE = 90000,            -- 90km
        MIN_RANGE = 5000,             -- 5km
        MAX_ALTITUDE = 30000,         -- 30km
        MIN_ALTITUDE = 25,            -- 25m
        MAX_SPEED = 2000,             -- Mach 6
        ACCELERATION = 40,            -- 40g
        GUIDANCE = "TVM",             -- Track Via Missile
        WARHEAD_KG = 133,
        PROXIMITY_FUZE_M = 20,
        SALVO_SIZE = 2,
        RELOAD_TIME = 60,             -- 1 minute reload
    },

    -- System
    System = {
        REACTION_TIME = 8,            -- 8 seconds (very fast)
        MAX_SIMULTANEOUS_ENGAGEMENTS = 6,
    },

    UPDATE_INTERVAL = 0.05,
}

-- ============================================================================
-- System States
-- ============================================================================
SAMSIM_SA10.SurveillanceMode = {
    OFF = 0,
    STANDBY = 1,
    SEARCH = 2,
    SECTOR = 3,
}

SAMSIM_SA10.EngagementMode = {
    OFF = 0,
    STANDBY = 1,
    ACQUISITION = 2,
    TRACK = 3,
    GUIDANCE = 4,
    MULTI_TARGET = 5,  -- Multiple target tracking
}

SAMSIM_SA10.SystemMode = {
    AUTONOMOUS = 0,     -- Independent operation
    COORDINATED = 1,    -- Coordinated with higher echelon
    MANUAL = 2,         -- Manual control
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_SA10.State = {
    -- System
    systemMode = 0,
    combatReady = false,

    -- Big Bird surveillance
    bigBird = {
        mode = 0,
        azimuth = 0,
        sectorCenter = 0,
        sectorWidth = 90,
        contacts = {},
        trackFiles = {},      -- Maintained track files
    },

    -- Clam Shell low altitude
    clamShell = {
        mode = 0,
        azimuth = 0,
        contacts = {},
    },

    -- Flap Lid engagement radar
    flapLid = {
        mode = 0,
        channels = {},        -- Up to 6 engagement channels
        activeChannel = 1,
    },

    -- Engagement channels (up to 6)
    engagements = {},

    -- Selected targets for engagement
    targetQueue = {},

    -- Missiles
    missiles = {
        ready = 4,            -- 4 missiles per TEL
        tels = 4,             -- 4 TELs in battery
        totalReady = 16,
        inFlight = 0,
    },

    -- Site
    site = {
        position = {x=0, y=0, z=0},
        heading = 0,
        name = "SA10_Battalion",
    },
}

-- ============================================================================
-- Engagement Channel
-- ============================================================================
local function createEngagementChannel()
    return {
        active = false,
        targetId = nil,
        mode = SAMSIM_SA10.EngagementMode.OFF,
        antenna = {
            azimuth = 0,
            elevation = 15,
            targetAz = 0,
            targetEl = 0,
        },
        track = {
            valid = false,
            position = {x=0, y=0, z=0},
            velocity = {x=0, y=0, z=0},
            smoothedPosition = {x=0, y=0, z=0},
            smoothedVelocity = {x=0, y=0, z=0},
            range = 0,
            azimuth = 0,
            elevation = 0,
            altitude = 0,
            speed = 0,
            rangeRate = 0,
        },
        firingSolution = {
            valid = false,
            interceptPoint = {x=0, y=0, z=0},
            timeToIntercept = 0,
            inEnvelope = false,
            pk = 0,
        },
        acquisitionTimer = 0,
        trackQuality = 0,
        missilesAssigned = 0,
    }
end

-- Initialize engagement channels
for i = 1, 6 do
    SAMSIM_SA10.State.engagements[i] = createEngagementChannel()
end

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

local function vectorDot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function normalizeAngle(angle)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

-- ============================================================================
-- RCS Database
-- ============================================================================
SAMSIM_SA10.RCSDatabase = {
    ["F-15C"] = 5.0, ["F-15E"] = 6.0, ["F-16C"] = 1.2,
    ["FA-18C"] = 1.5, ["F-14A"] = 10.0, ["F-4E"] = 8.0,
    ["MiG-21"] = 3.0, ["MiG-29A"] = 3.0,
    ["Su-27"] = 10.0, ["Su-25"] = 8.0, ["A-10A"] = 15.0,
    ["M-2000C"] = 1.5, ["Tornado"] = 5.0,
    ["F-22A"] = 0.0001, ["F-35A"] = 0.001, ["B-2A"] = 0.01,
    ["B-52H"] = 100.0, ["B-1B"] = 10.0,
    ["Tu-22M3"] = 40.0, ["Tu-160"] = 25.0,
    ["UH-1H"] = 5.0, ["AH-64D"] = 3.5, ["Mi-24P"] = 10.0,
    ["BGM-109"] = 0.1, ["AGM-86"] = 0.1, -- Cruise missiles
    DEFAULT = 5.0,
}

function SAMSIM_SA10.estimateRCS(typeName)
    for pattern, rcs in pairs(SAMSIM_SA10.RCSDatabase) do
        if pattern ~= "DEFAULT" and string.find(typeName, pattern) then
            return rcs
        end
    end
    return SAMSIM_SA10.RCSDatabase.DEFAULT
end

-- ============================================================================
-- Big Bird Surveillance Radar
-- ============================================================================
function SAMSIM_SA10.updateBigBird(dt)
    local state = SAMSIM_SA10.State.bigBird
    local config = SAMSIM_SA10.Config.BigBird

    if state.mode == SAMSIM_SA10.SurveillanceMode.OFF then
        return
    end

    if state.mode == SAMSIM_SA10.SurveillanceMode.STANDBY then
        return
    end

    -- Antenna rotation
    if state.mode == SAMSIM_SA10.SurveillanceMode.SEARCH then
        state.azimuth = state.azimuth + (360 / config.ROTATION_PERIOD) * dt
        if state.azimuth >= 360 then
            state.azimuth = state.azimuth - 360
        end
    elseif state.mode == SAMSIM_SA10.SurveillanceMode.SECTOR then
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

    SAMSIM_SA10.scanBigBird()
end

function SAMSIM_SA10.scanBigBird()
    local state = SAMSIM_SA10.State.bigBird
    local config = SAMSIM_SA10.Config.BigBird
    local sitePos = SAMSIM_SA10.State.site.position

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

    local currentTime = timer.getTime()

    for _, obj in ipairs(foundObjects) do
        local pos = obj:getPoint()
        local vel = obj:getVelocity()
        local relPos = vectorSubtract(pos, sitePos)
        local range = vectorMagnitude(relPos)
        local azimuth = math.deg(math.atan2(relPos.x, relPos.z))
        if azimuth < 0 then azimuth = azimuth + 360 end
        local altitude = pos.y

        if altitude >= config.MIN_ALTITUDE and altitude <= config.MAX_ALTITUDE and
           range >= config.MIN_RANGE and range <= config.MAX_RANGE then

            local azDiff = math.abs(normalizeAngle(azimuth - state.azimuth))
            if azDiff <= config.BEAM_WIDTH_AZ / 2 then
                local rcs = SAMSIM_SA10.estimateRCS(obj:getTypeName())

                -- Detection probability
                local rangeNorm = range / config.MAX_RANGE
                local rangeFactor = math.max(0, 1 - rangeNorm^2)
                local rcsFactor = math.min(1, math.sqrt(rcs / 0.1))
                local detectionProb = config.DETECTION_PROB_MAX * rangeFactor * rcsFactor

                if math.random() < detectionProb then
                    local id = obj:getID()

                    -- Range rate
                    local rangeUnit = vectorScale(relPos, 1/range)
                    local rangeRate = -vectorDot(vel, rangeUnit)

                    state.contacts[id] = {
                        id = id,
                        name = obj:getName(),
                        typeName = obj:getTypeName(),
                        position = pos,
                        velocity = vel,
                        range = range,
                        azimuth = azimuth,
                        altitude = altitude,
                        rcs = rcs,
                        rangeRate = rangeRate,
                        lastSeen = currentTime,
                        speed = vectorMagnitude(vel),
                        heading = math.deg(math.atan2(vel.x, vel.z)),
                        threatLevel = SAMSIM_SA10.assessThreat(range, rangeRate, rcs),
                    }

                    -- Maintain track file
                    SAMSIM_SA10.updateTrackFile(id, state.contacts[id])
                end
            end
        end
    end

    -- Age out contacts
    for id, contact in pairs(state.contacts) do
        if currentTime - contact.lastSeen > 15 then
            state.contacts[id] = nil
        end
    end
end

function SAMSIM_SA10.assessThreat(range, rangeRate, rcs)
    -- Threat assessment algorithm
    local threat = 0

    -- Closing target is higher threat
    if rangeRate > 50 then
        threat = threat + 30
    elseif rangeRate > 0 then
        threat = threat + 20
    end

    -- Closer is higher threat
    if range < 50000 then
        threat = threat + 40
    elseif range < 100000 then
        threat = threat + 25
    elseif range < 150000 then
        threat = threat + 10
    end

    -- Small RCS might be cruise missile/stealth - high threat
    if rcs < 0.5 then
        threat = threat + 30
    end

    return math.min(100, threat)
end

function SAMSIM_SA10.updateTrackFile(id, contact)
    local trackFiles = SAMSIM_SA10.State.bigBird.trackFiles

    if not trackFiles[id] then
        trackFiles[id] = {
            id = id,
            firstSeen = timer.getTime(),
            positions = {},
            classification = "UNKNOWN",
            hostile = false,
            priority = 0,
        }
    end

    local file = trackFiles[id]
    table.insert(file.positions, {
        time = timer.getTime(),
        position = deepCopy(contact.position),
        velocity = deepCopy(contact.velocity),
    })

    -- Keep last 30 seconds
    while #file.positions > 0 and timer.getTime() - file.positions[1].time > 30 do
        table.remove(file.positions, 1)
    end

    file.priority = contact.threatLevel
end

-- ============================================================================
-- Clam Shell Low Altitude Radar
-- ============================================================================
function SAMSIM_SA10.updateClamShell(dt)
    local state = SAMSIM_SA10.State.clamShell
    local config = SAMSIM_SA10.Config.ClamShell

    if state.mode == SAMSIM_SA10.SurveillanceMode.OFF then
        return
    end

    if state.mode >= SAMSIM_SA10.SurveillanceMode.SEARCH then
        state.azimuth = state.azimuth + (360 / config.ROTATION_PERIOD) * dt
        if state.azimuth >= 360 then
            state.azimuth = state.azimuth - 360
        end

        SAMSIM_SA10.scanClamShell()
    end
end

function SAMSIM_SA10.scanClamShell()
    local state = SAMSIM_SA10.State.clamShell
    local config = SAMSIM_SA10.Config.ClamShell
    local sitePos = SAMSIM_SA10.State.site.position
    local bigBird = SAMSIM_SA10.State.bigBird

    -- Clam Shell focuses on low altitude
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

    local currentTime = timer.getTime()

    for _, obj in ipairs(foundObjects) do
        local pos = obj:getPoint()
        local altitude = pos.y

        -- Only process low altitude targets
        if altitude <= config.MAX_ALTITUDE then
            local vel = obj:getVelocity()
            local relPos = vectorSubtract(pos, sitePos)
            local range = vectorMagnitude(relPos)
            local azimuth = math.deg(math.atan2(relPos.x, relPos.z))
            if azimuth < 0 then azimuth = azimuth + 360 end

            if range >= config.MIN_RANGE and range <= config.MAX_RANGE then
                local azDiff = math.abs(normalizeAngle(azimuth - state.azimuth))
                if azDiff <= 3 then  -- Wider beam
                    local rcs = SAMSIM_SA10.estimateRCS(obj:getTypeName())
                    local detectionProb = config.DETECTION_PROB_MAX

                    if math.random() < detectionProb then
                        local id = obj:getID()

                        local rangeUnit = vectorScale(relPos, 1/range)
                        local rangeRate = -vectorDot(vel, rangeUnit)

                        state.contacts[id] = {
                            id = id,
                            name = obj:getName(),
                            typeName = obj:getTypeName(),
                            position = pos,
                            velocity = vel,
                            range = range,
                            azimuth = azimuth,
                            altitude = altitude,
                            rcs = rcs,
                            rangeRate = rangeRate,
                            lastSeen = currentTime,
                            speed = vectorMagnitude(vel),
                            lowAltitude = true,
                        }

                        -- Cross-cue to Big Bird
                        bigBird.contacts[id] = state.contacts[id]
                        SAMSIM_SA10.updateTrackFile(id, state.contacts[id])
                    end
                end
            end
        end
    end

    -- Age out
    for id, contact in pairs(state.contacts) do
        if currentTime - contact.lastSeen > 8 then
            state.contacts[id] = nil
        end
    end
end

-- ============================================================================
-- Flap Lid Engagement Radar
-- ============================================================================
function SAMSIM_SA10.updateFlapLid(dt)
    local state = SAMSIM_SA10.State.flapLid
    local engagements = SAMSIM_SA10.State.engagements

    if state.mode == SAMSIM_SA10.EngagementMode.OFF then
        return
    end

    -- Update all active engagement channels
    for i, channel in ipairs(engagements) do
        if channel.active then
            SAMSIM_SA10.updateEngagementChannel(channel, dt, i)
        end
    end
end

function SAMSIM_SA10.updateEngagementChannel(channel, dt, channelNum)
    local config = SAMSIM_SA10.Config.FlapLid

    -- Antenna slew
    local azDiff = normalizeAngle(channel.antenna.targetAz - channel.antenna.azimuth)
    local elDiff = channel.antenna.targetEl - channel.antenna.elevation
    local slewRate = config.ANTENNA_SLEW_RATE * dt

    if math.abs(azDiff) > slewRate then
        channel.antenna.azimuth = channel.antenna.azimuth + slewRate * (azDiff > 0 and 1 or -1)
    else
        channel.antenna.azimuth = channel.antenna.targetAz
    end

    if math.abs(elDiff) > slewRate then
        channel.antenna.elevation = channel.antenna.elevation + slewRate * (elDiff > 0 and 1 or -1)
    else
        channel.antenna.elevation = channel.antenna.targetEl
    end

    channel.antenna.azimuth = normalizeAngle(channel.antenna.azimuth)
    channel.antenna.elevation = math.max(0, math.min(85, channel.antenna.elevation))

    if channel.mode == SAMSIM_SA10.EngagementMode.ACQUISITION then
        SAMSIM_SA10.processChannelAcquisition(channel, dt)
    elseif channel.mode == SAMSIM_SA10.EngagementMode.TRACK or
           channel.mode == SAMSIM_SA10.EngagementMode.GUIDANCE then
        SAMSIM_SA10.processChannelTrack(channel, dt)
    end
end

function SAMSIM_SA10.processChannelAcquisition(channel, dt)
    local config = SAMSIM_SA10.Config.FlapLid
    local bigBird = SAMSIM_SA10.State.bigBird

    if not channel.targetId then
        return
    end

    local contact = bigBird.contacts[channel.targetId]
    if not contact then
        return
    end

    local sitePos = SAMSIM_SA10.State.site.position
    local relPos = vectorSubtract(contact.position, sitePos)

    channel.antenna.targetAz = contact.azimuth
    channel.antenna.targetEl = math.deg(math.atan2(contact.altitude,
        math.sqrt(relPos.x^2 + relPos.z^2)))

    local azError = math.abs(normalizeAngle(channel.antenna.azimuth - contact.azimuth))
    local elError = math.abs(channel.antenna.elevation - channel.antenna.targetEl)

    if azError < config.ACQUISITION_BEAM_WIDTH / 2 and elError < config.ACQUISITION_BEAM_WIDTH / 2 then
        channel.acquisitionTimer = channel.acquisitionTimer + dt

        if channel.acquisitionTimer >= config.ACQUISITION_TIME then
            channel.mode = SAMSIM_SA10.EngagementMode.TRACK
            channel.trackQuality = 0.7
            SAMSIM_SA10.initializeChannelTrack(channel, contact)
        end
    else
        channel.acquisitionTimer = math.max(0, channel.acquisitionTimer - dt * 0.3)
    end
end

function SAMSIM_SA10.initializeChannelTrack(channel, contact)
    channel.track.valid = true
    channel.track.position = deepCopy(contact.position)
    channel.track.velocity = deepCopy(contact.velocity)
    channel.track.smoothedPosition = deepCopy(contact.position)
    channel.track.smoothedVelocity = deepCopy(contact.velocity)
    channel.track.range = contact.range
    channel.track.azimuth = contact.azimuth
    channel.track.altitude = contact.altitude
    channel.track.rangeRate = contact.rangeRate or 0
end

function SAMSIM_SA10.processChannelTrack(channel, dt)
    local config = SAMSIM_SA10.Config.FlapLid
    local bigBird = SAMSIM_SA10.State.bigBird

    if not channel.track.valid then
        channel.mode = SAMSIM_SA10.EngagementMode.ACQUISITION
        return
    end

    local contact = bigBird.contacts[channel.targetId]
    local targetUnit = nil

    if contact then
        targetUnit = Unit.getByName(contact.name)
    end

    if targetUnit and targetUnit:isExist() then
        local pos = targetUnit:getPoint()
        local vel = targetUnit:getVelocity()
        local sitePos = SAMSIM_SA10.State.site.position
        local relPos = vectorSubtract(pos, sitePos)

        -- High precision tracking with strong smoothing
        local alpha = 0.4
        channel.track.smoothedPosition.x = channel.track.smoothedPosition.x + alpha * (pos.x - channel.track.smoothedPosition.x)
        channel.track.smoothedPosition.y = channel.track.smoothedPosition.y + alpha * (pos.y - channel.track.smoothedPosition.y)
        channel.track.smoothedPosition.z = channel.track.smoothedPosition.z + alpha * (pos.z - channel.track.smoothedPosition.z)

        channel.track.smoothedVelocity.x = channel.track.smoothedVelocity.x + alpha * (vel.x - channel.track.smoothedVelocity.x)
        channel.track.smoothedVelocity.y = channel.track.smoothedVelocity.y + alpha * (vel.y - channel.track.smoothedVelocity.y)
        channel.track.smoothedVelocity.z = channel.track.smoothedVelocity.z + alpha * (vel.z - channel.track.smoothedVelocity.z)

        channel.track.position = pos
        channel.track.velocity = vel
        channel.track.range = vectorMagnitude(relPos)
        channel.track.azimuth = math.deg(math.atan2(relPos.x, relPos.z))
        if channel.track.azimuth < 0 then channel.track.azimuth = channel.track.azimuth + 360 end
        channel.track.elevation = math.deg(math.atan2(pos.y - sitePos.y,
            math.sqrt(relPos.x^2 + relPos.z^2)))
        channel.track.altitude = pos.y
        channel.track.speed = vectorMagnitude(vel)

        local rangeUnit = vectorScale(relPos, 1/channel.track.range)
        channel.track.rangeRate = -vectorDot(vel, rangeUnit)

        channel.antenna.targetAz = channel.track.azimuth
        channel.antenna.targetEl = channel.track.elevation

        local azError = math.abs(normalizeAngle(channel.antenna.azimuth - channel.track.azimuth))
        local elError = math.abs(channel.antenna.elevation - channel.track.elevation)
        local totalError = math.sqrt(azError^2 + elError^2)

        channel.trackQuality = math.max(0, math.min(1, 1 - totalError / config.TRACK_BEAM_WIDTH))

        -- Very good tracking - can maintain track at high angles
        if totalError > config.TRACK_BEAM_WIDTH * 5 then
            channel.track.valid = false
            channel.mode = SAMSIM_SA10.EngagementMode.ACQUISITION
        end
    else
        channel.track.valid = false
        channel.mode = SAMSIM_SA10.EngagementMode.ACQUISITION
    end

    SAMSIM_SA10.calculateChannelFiringSolution(channel)
end

function SAMSIM_SA10.calculateChannelFiringSolution(channel)
    local solution = channel.firingSolution
    local track = channel.track
    local missileConfig = SAMSIM_SA10.Config.Missile
    local sitePos = SAMSIM_SA10.State.site.position

    if not track.valid then
        solution.valid = false
        return
    end

    local range = track.range
    local altitude = track.altitude

    -- TVM guidance allows longer range and better accuracy
    local missileAvgSpeed = missileConfig.MAX_SPEED * 0.7
    local closingSpeed = track.rangeRate
    local timeToIntercept = range / (missileAvgSpeed + closingSpeed)

    local interceptPoint = vectorAdd(track.smoothedPosition, vectorScale(track.smoothedVelocity, timeToIntercept))

    solution.interceptPoint = interceptPoint
    solution.timeToIntercept = timeToIntercept

    solution.inRangeMax = range <= missileConfig.MAX_RANGE
    solution.inRangeMin = range >= missileConfig.MIN_RANGE
    solution.inAltitude = altitude >= missileConfig.MIN_ALTITUDE and altitude <= missileConfig.MAX_ALTITUDE
    solution.inEnvelope = solution.inRangeMax and solution.inRangeMin and solution.inAltitude

    -- High Pk for S-300
    local rangeFactor = 1 - (range / missileConfig.MAX_RANGE)^1.5
    local altFactor = 1.0
    if altitude < 100 then
        altFactor = 0.8 + 0.2 * (altitude / 100)
    end
    local trackQualityFactor = channel.trackQuality

    solution.pk = math.max(0, math.min(0.90,
        0.80 * rangeFactor * altFactor * trackQualityFactor))

    solution.valid = solution.inEnvelope and channel.trackQuality > 0.5
end

-- ============================================================================
-- Target Assignment
-- ============================================================================
function SAMSIM_SA10.assignTarget(targetId, channelNum)
    local engagements = SAMSIM_SA10.State.engagements
    local bigBird = SAMSIM_SA10.State.bigBird

    if channelNum < 1 or channelNum > 6 then
        return false, "Invalid channel"
    end

    local channel = engagements[channelNum]
    local contact = bigBird.contacts[targetId]

    if not contact then
        return false, "Target not found"
    end

    channel.active = true
    channel.targetId = targetId
    channel.mode = SAMSIM_SA10.EngagementMode.ACQUISITION
    channel.acquisitionTimer = 0
    channel.track.valid = false

    return true, "Target assigned to channel " .. channelNum
end

-- ============================================================================
-- Missile Launch
-- ============================================================================
function SAMSIM_SA10.launchMissile(channelNum)
    local missiles = SAMSIM_SA10.State.missiles
    local channel = SAMSIM_SA10.State.engagements[channelNum]

    if not channel or not channel.active then
        return false, "Channel not active"
    end

    if not channel.firingSolution.valid then
        return false, "No valid firing solution"
    end

    if missiles.totalReady <= 0 then
        return false, "No missiles ready"
    end

    channel.mode = SAMSIM_SA10.EngagementMode.GUIDANCE
    channel.missilesAssigned = channel.missilesAssigned + 1

    missiles.totalReady = missiles.totalReady - 1
    missiles.inFlight = missiles.inFlight + 1

    return true, "Missile launched on channel " .. channelNum
end

-- ============================================================================
-- Command Interface
-- ============================================================================
function SAMSIM_SA10.processCommand(cmd)
    local response = {success = false, message = "Unknown command"}

    if cmd.type == "POWER" then
        if cmd.system == "BIGBIRD" then
            SAMSIM_SA10.State.bigBird.mode = cmd.state == "ON" and
                SAMSIM_SA10.SurveillanceMode.STANDBY or SAMSIM_SA10.SurveillanceMode.OFF
        elseif cmd.system == "CLAMSHELL" then
            SAMSIM_SA10.State.clamShell.mode = cmd.state == "ON" and
                SAMSIM_SA10.SurveillanceMode.STANDBY or SAMSIM_SA10.SurveillanceMode.OFF
        elseif cmd.system == "FLAPLID" then
            SAMSIM_SA10.State.flapLid.mode = cmd.state == "ON" and
                SAMSIM_SA10.EngagementMode.STANDBY or SAMSIM_SA10.EngagementMode.OFF
        end
        response = {success = true, message = cmd.system .. " power " .. cmd.state}

    elseif cmd.type == "SURVEILLANCE_MODE" then
        if cmd.mode == "SEARCH" then
            SAMSIM_SA10.State.bigBird.mode = SAMSIM_SA10.SurveillanceMode.SEARCH
            SAMSIM_SA10.State.clamShell.mode = SAMSIM_SA10.SurveillanceMode.SEARCH
        elseif cmd.mode == "SECTOR" then
            SAMSIM_SA10.State.bigBird.mode = SAMSIM_SA10.SurveillanceMode.SECTOR
            if cmd.center then SAMSIM_SA10.State.bigBird.sectorCenter = cmd.center end
            if cmd.width then SAMSIM_SA10.State.bigBird.sectorWidth = cmd.width end
        elseif cmd.mode == "STANDBY" then
            SAMSIM_SA10.State.bigBird.mode = SAMSIM_SA10.SurveillanceMode.STANDBY
            SAMSIM_SA10.State.clamShell.mode = SAMSIM_SA10.SurveillanceMode.STANDBY
        end
        response = {success = true, message = "Surveillance mode set to " .. cmd.mode}

    elseif cmd.type == "DESIGNATE" then
        local success, msg = SAMSIM_SA10.assignTarget(cmd.targetId, cmd.channel or 1)
        response = {success = success, message = msg}

    elseif cmd.type == "LAUNCH" then
        local success, msg = SAMSIM_SA10.launchMissile(cmd.channel or 1)
        response = {success = success, message = msg}

    elseif cmd.type == "CHANNEL_COMMAND" then
        local channel = SAMSIM_SA10.State.engagements[cmd.channel]
        if channel then
            if cmd.action == "DROP" then
                channel.active = false
                channel.mode = SAMSIM_SA10.EngagementMode.OFF
                channel.track.valid = false
            end
            response = {success = true, message = "Channel command executed"}
        end
    end

    return response
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM_SA10.getStateForExport()
    local state = SAMSIM_SA10.State

    local contactsList = {}
    for id, contact in pairs(state.bigBird.contacts) do
        table.insert(contactsList, {
            id = id,
            typeName = contact.typeName,
            range = math.floor(contact.range),
            azimuth = math.floor(contact.azimuth * 10) / 10,
            altitude = math.floor(contact.altitude),
            speed = math.floor(contact.speed),
            rangeRate = math.floor(contact.rangeRate or 0),
            threatLevel = contact.threatLevel or 0,
            lowAltitude = contact.lowAltitude or false,
        })
    end

    local channelsData = {}
    for i, channel in ipairs(state.engagements) do
        channelsData[i] = {
            active = channel.active,
            targetId = channel.targetId,
            mode = channel.mode,
            modeName = SAMSIM_SA10.getEngagementModeName(channel.mode),
            antennaAz = channel.antenna.azimuth,
            antennaEl = channel.antenna.elevation,
            trackValid = channel.track.valid,
            trackRange = channel.track.range,
            trackAzimuth = channel.track.azimuth,
            trackElevation = channel.track.elevation,
            trackAltitude = channel.track.altitude,
            trackQuality = channel.trackQuality,
            firingSolutionValid = channel.firingSolution.valid,
            inEnvelope = channel.firingSolution.inEnvelope,
            pk = channel.firingSolution.pk,
            missilesAssigned = channel.missilesAssigned,
        }
    end

    return {
        systemType = "SA10",
        systemName = SAMSIM_SA10.SystemName,
        timestamp = timer.getTime(),

        bigBird = {
            mode = state.bigBird.mode,
            modeName = SAMSIM_SA10.getSurveillanceModeName(state.bigBird.mode),
            azimuth = state.bigBird.azimuth,
            sectorCenter = state.bigBird.sectorCenter,
            sectorWidth = state.bigBird.sectorWidth,
            contactCount = #contactsList,
        },

        clamShell = {
            mode = state.clamShell.mode,
            azimuth = state.clamShell.azimuth,
        },

        flapLid = {
            mode = state.flapLid.mode,
            activeChannel = state.flapLid.activeChannel,
        },

        contacts = contactsList,
        channels = channelsData,

        missiles = {
            totalReady = state.missiles.totalReady,
            inFlight = state.missiles.inFlight,
            tels = state.missiles.tels,
        },

        config = {
            bigBirdMaxRange = SAMSIM_SA10.Config.BigBird.MAX_RANGE,
            flapLidMaxRange = SAMSIM_SA10.Config.FlapLid.MAX_RANGE,
            missileMaxRange = SAMSIM_SA10.Config.Missile.MAX_RANGE,
            missileMinRange = SAMSIM_SA10.Config.Missile.MIN_RANGE,
            maxChannels = 6,
        },
    }
end

function SAMSIM_SA10.getSurveillanceModeName(mode)
    local names = {"OFF", "STANDBY", "SEARCH", "SECTOR"}
    return names[mode + 1] or "UNKNOWN"
end

function SAMSIM_SA10.getEngagementModeName(mode)
    local names = {"OFF", "STANDBY", "ACQUISITION", "TRACK", "GUIDANCE", "MULTI_TARGET"}
    return names[mode + 1] or "UNKNOWN"
end

-- ============================================================================
-- Main Update Loop
-- ============================================================================
function SAMSIM_SA10.update()
    local currentTime = timer.getTime()
    if not SAMSIM_SA10.lastUpdate then
        SAMSIM_SA10.lastUpdate = currentTime
    end

    local dt = currentTime - SAMSIM_SA10.lastUpdate
    SAMSIM_SA10.lastUpdate = currentTime

    SAMSIM_SA10.updateBigBird(dt)
    SAMSIM_SA10.updateClamShell(dt)
    SAMSIM_SA10.updateFlapLid(dt)

    return timer.getTime() + SAMSIM_SA10.Config.UPDATE_INTERVAL
end

-- ============================================================================
-- Initialization
-- ============================================================================
function SAMSIM_SA10.initialize(siteName, position, heading)
    SAMSIM_SA10.State.site.name = siteName or "SA10_Battalion"
    SAMSIM_SA10.State.site.position = position or {x=0, y=0, z=0}
    SAMSIM_SA10.State.site.heading = heading or 0

    SAMSIM_SA10.State.missiles.totalReady = 16
    SAMSIM_SA10.State.missiles.inFlight = 0

    timer.scheduleFunction(SAMSIM_SA10.update, nil, timer.getTime() + 0.1)

    env.info("SAMSIM SA-10: Initialized battalion " .. SAMSIM_SA10.State.site.name)
end

env.info("SAMSIM SA-10 (S-300PS) Controller loaded - Version " .. SAMSIM_SA10.Version)
