--[[
    SA-11 Gadfly (9K37 Buk) SAMSim Controller for DCS World

    System Components:
    - 9S18 "Snow Drift" Target Acquisition Radar (TAR)
    - 9A310 TELAR with 9S35 "Fire Dome" Fire Control Radar
    - 9M38 missiles

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_SA11 = {}
SAMSIM_SA11.Version = "1.0.0"
SAMSIM_SA11.SystemName = "9K37 Buk (SA-11 Gadfly)"

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_SA11.Config = {
    -- 9S18 "Snow Drift" Target Acquisition Radar
    SnowDrift = {
        MAX_RANGE = 100000,           -- 100km
        MIN_RANGE = 1500,
        MAX_ALTITUDE = 20000,         -- 20km
        MIN_ALTITUDE = 15,            -- 15m (excellent low altitude)
        ROTATION_PERIOD = 4,          -- 4 seconds (fast rotation)
        BEAM_WIDTH_AZ = 1.8,
        DETECTION_PROB_MAX = 0.93,
        MAX_TRACKS = 60,              -- Can track 60 targets
        POWER_KW = 300,
        FREQUENCY_GHZ = 3.0,          -- S-band
    },

    -- 9S35 "Fire Dome" Fire Control Radar (on TELAR)
    FireDome = {
        MAX_RANGE = 42000,            -- 42km
        MIN_RANGE = 3000,
        MAX_ALTITUDE = 22000,
        TRACK_BEAM_WIDTH = 1.0,
        ACQUISITION_BEAM_WIDTH = 3.0,
        ACQUISITION_TIME = 2,
        TRACK_PRECISION = 0.2,        -- mrad
        ANTENNA_SLEW_RATE = 30,       -- deg/sec
        POWER_KW = 150,
        FREQUENCY_GHZ = 10,           -- X-band
        CW_ILLUMINATION = true,       -- Has CW illuminator for SARH
    },

    -- 9M38 Missile
    Missile = {
        MAX_RANGE = 35000,            -- 35km
        MIN_RANGE = 3000,             -- 3km
        MAX_ALTITUDE = 22000,         -- 22km
        MIN_ALTITUDE = 15,            -- 15m
        MAX_SPEED = 1230,             -- Mach 3.7
        ACCELERATION = 25,            -- 25g
        GUIDANCE = "SARH",            -- Semi-Active Radar Homing
        WARHEAD_KG = 70,
        PROXIMITY_FUZE_M = 17,
    },

    -- System
    System = {
        REACTION_TIME = 22,           -- 22 seconds
        MISSILES_PER_TELAR = 4,       -- 4 missiles per TELAR
        TELAR_COUNT = 4,              -- Typical battery has 4 TELARs
    },

    UPDATE_INTERVAL = 0.05,
}

-- ============================================================================
-- System States
-- ============================================================================
SAMSIM_SA11.SnowDriftMode = {
    OFF = 0,
    STANDBY = 1,
    SEARCH = 2,
    SECTOR = 3,
    MTI = 4,              -- Moving Target Indication
}

SAMSIM_SA11.FireDomeMode = {
    OFF = 0,
    STANDBY = 1,
    ACQUISITION = 2,
    TRACK = 3,
    ILLUMINATION = 4,     -- CW illumination for terminal guidance
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_SA11.State = {
    -- 9S18 Snow Drift
    snowDrift = {
        mode = 0,
        azimuth = 0,
        sectorCenter = 0,
        sectorWidth = 60,
        mtiEnabled = false,
        contacts = {},
    },

    -- TELARs (multiple Fire Dome radars)
    telars = {},

    -- Selected TELAR for engagement
    activeTelar = 1,

    -- Missiles
    missiles = {
        totalReady = 16,          -- 4 TELARs x 4 missiles
        inFlight = 0,
    },

    -- Site
    site = {
        position = {x=0, y=0, z=0},
        heading = 0,
        name = "SA11_Battery",
    },
}

-- ============================================================================
-- TELAR State
-- ============================================================================
local function createTelarState()
    return {
        id = 0,
        active = false,
        mode = SAMSIM_SA11.FireDomeMode.OFF,
        missilesReady = 4,

        -- Antenna
        antenna = {
            azimuth = 0,
            elevation = 15,
            targetAz = 0,
            targetEl = 0,
        },

        -- Target
        targetId = nil,
        acquisitionTimer = 0,
        trackQuality = 0,
        cwPower = 0,

        -- Track
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

        -- Firing solution
        firingSolution = {
            valid = false,
            interceptPoint = {x=0, y=0, z=0},
            timeToIntercept = 0,
            inEnvelope = false,
            pk = 0,
        },
    }
end

-- Initialize TELARs
for i = 1, 4 do
    SAMSIM_SA11.State.telars[i] = createTelarState()
    SAMSIM_SA11.State.telars[i].id = i
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
SAMSIM_SA11.RCSDatabase = {
    ["F-15C"] = 5.0, ["F-15E"] = 6.0, ["F-16C"] = 1.2,
    ["FA-18C"] = 1.5, ["F-14A"] = 10.0, ["F-4E"] = 8.0,
    ["MiG-21"] = 3.0, ["MiG-29A"] = 3.0,
    ["Su-27"] = 10.0, ["Su-25"] = 8.0, ["A-10A"] = 15.0,
    ["M-2000C"] = 1.5, ["Tornado"] = 5.0,
    ["F-22A"] = 0.0001, ["F-35A"] = 0.001,
    ["B-52H"] = 100.0, ["Tu-22M3"] = 40.0,
    ["UH-1H"] = 5.0, ["AH-64D"] = 3.5, ["Mi-24P"] = 10.0,
    DEFAULT = 5.0,
}

function SAMSIM_SA11.estimateRCS(typeName)
    for pattern, rcs in pairs(SAMSIM_SA11.RCSDatabase) do
        if pattern ~= "DEFAULT" and string.find(typeName, pattern) then
            return rcs
        end
    end
    return SAMSIM_SA11.RCSDatabase.DEFAULT
end

-- ============================================================================
-- Snow Drift TAR Simulation
-- ============================================================================
function SAMSIM_SA11.updateSnowDrift(dt)
    local state = SAMSIM_SA11.State.snowDrift
    local config = SAMSIM_SA11.Config.SnowDrift

    if state.mode == SAMSIM_SA11.SnowDriftMode.OFF or
       state.mode == SAMSIM_SA11.SnowDriftMode.STANDBY then
        return
    end

    -- Antenna rotation
    if state.mode == SAMSIM_SA11.SnowDriftMode.SEARCH or
       state.mode == SAMSIM_SA11.SnowDriftMode.MTI then
        state.azimuth = state.azimuth + (360 / config.ROTATION_PERIOD) * dt
        if state.azimuth >= 360 then
            state.azimuth = state.azimuth - 360
        end
    elseif state.mode == SAMSIM_SA11.SnowDriftMode.SECTOR then
        local halfWidth = state.sectorWidth / 2
        local minAz = state.sectorCenter - halfWidth
        local maxAz = state.sectorCenter + halfWidth

        if not state.sectorDirection then state.sectorDirection = 1 end

        state.azimuth = state.azimuth + state.sectorDirection * (360 / config.ROTATION_PERIOD) * 2 * dt

        if state.azimuth > maxAz then
            state.azimuth = maxAz
            state.sectorDirection = -1
        elseif state.azimuth < minAz then
            state.azimuth = minAz
            state.sectorDirection = 1
        end
    end

    SAMSIM_SA11.scanSnowDrift()
end

function SAMSIM_SA11.scanSnowDrift()
    local state = SAMSIM_SA11.State.snowDrift
    local config = SAMSIM_SA11.Config.SnowDrift
    local sitePos = SAMSIM_SA11.State.site.position

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
                local rcs = SAMSIM_SA11.estimateRCS(obj:getTypeName())

                -- MTI mode enhances detection of moving targets
                local rangeUnit = vectorScale(relPos, 1/range)
                local rangeRate = -vectorDot(vel, rangeUnit)

                local detectionProb = config.DETECTION_PROB_MAX
                if state.mtiEnabled or state.mode == SAMSIM_SA11.SnowDriftMode.MTI then
                    -- MTI requires target motion
                    local velocityFactor = math.min(1, math.abs(rangeRate) / 30)
                    detectionProb = detectionProb * (0.5 + 0.5 * velocityFactor)
                end

                if math.random() < detectionProb then
                    local id = obj:getID()
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
                    }
                end
            end
        end
    end

    -- Age out contacts
    for id, contact in pairs(state.contacts) do
        if currentTime - contact.lastSeen > 6 then
            state.contacts[id] = nil
        end
    end
end

-- ============================================================================
-- Fire Dome (TELAR) Simulation
-- ============================================================================
function SAMSIM_SA11.updateTelar(telar, dt)
    local config = SAMSIM_SA11.Config.FireDome

    if telar.mode == SAMSIM_SA11.FireDomeMode.OFF or
       telar.mode == SAMSIM_SA11.FireDomeMode.STANDBY then
        telar.cwPower = 0
        return
    end

    -- Antenna slew
    local azDiff = normalizeAngle(telar.antenna.targetAz - telar.antenna.azimuth)
    local elDiff = telar.antenna.targetEl - telar.antenna.elevation
    local slewRate = config.ANTENNA_SLEW_RATE * dt

    if math.abs(azDiff) > slewRate then
        telar.antenna.azimuth = telar.antenna.azimuth + slewRate * (azDiff > 0 and 1 or -1)
    else
        telar.antenna.azimuth = telar.antenna.targetAz
    end

    if math.abs(elDiff) > slewRate then
        telar.antenna.elevation = telar.antenna.elevation + slewRate * (elDiff > 0 and 1 or -1)
    else
        telar.antenna.elevation = telar.antenna.targetEl
    end

    telar.antenna.azimuth = normalizeAngle(telar.antenna.azimuth)
    telar.antenna.elevation = math.max(-3, math.min(85, telar.antenna.elevation))

    if telar.mode == SAMSIM_SA11.FireDomeMode.ACQUISITION then
        SAMSIM_SA11.processTelarAcquisition(telar, dt)
        telar.cwPower = 0
    elseif telar.mode == SAMSIM_SA11.FireDomeMode.TRACK then
        SAMSIM_SA11.processTelarTrack(telar, dt)
        telar.cwPower = 0
    elseif telar.mode == SAMSIM_SA11.FireDomeMode.ILLUMINATION then
        SAMSIM_SA11.processTelarTrack(telar, dt)
        telar.cwPower = 100
    end
end

function SAMSIM_SA11.processTelarAcquisition(telar, dt)
    local config = SAMSIM_SA11.Config.FireDome
    local snowDrift = SAMSIM_SA11.State.snowDrift

    if not telar.targetId then
        return
    end

    local contact = snowDrift.contacts[telar.targetId]
    if not contact then
        return
    end

    local sitePos = SAMSIM_SA11.State.site.position
    local relPos = vectorSubtract(contact.position, sitePos)

    telar.antenna.targetAz = contact.azimuth
    telar.antenna.targetEl = math.deg(math.atan2(contact.altitude,
        math.sqrt(relPos.x^2 + relPos.z^2)))

    local azError = math.abs(normalizeAngle(telar.antenna.azimuth - contact.azimuth))
    local elError = math.abs(telar.antenna.elevation - telar.antenna.targetEl)

    if azError < config.ACQUISITION_BEAM_WIDTH / 2 and elError < config.ACQUISITION_BEAM_WIDTH / 2 then
        telar.acquisitionTimer = telar.acquisitionTimer + dt

        if telar.acquisitionTimer >= config.ACQUISITION_TIME then
            telar.mode = SAMSIM_SA11.FireDomeMode.TRACK
            telar.trackQuality = 0.65
            SAMSIM_SA11.initializeTelarTrack(telar, contact)
        end
    else
        telar.acquisitionTimer = math.max(0, telar.acquisitionTimer - dt * 0.5)
    end
end

function SAMSIM_SA11.initializeTelarTrack(telar, contact)
    telar.track.valid = true
    telar.track.position = deepCopy(contact.position)
    telar.track.velocity = deepCopy(contact.velocity)
    telar.track.smoothedPosition = deepCopy(contact.position)
    telar.track.smoothedVelocity = deepCopy(contact.velocity)
    telar.track.range = contact.range
    telar.track.azimuth = contact.azimuth
    telar.track.altitude = contact.altitude
    telar.track.rangeRate = contact.rangeRate or 0
end

function SAMSIM_SA11.processTelarTrack(telar, dt)
    local config = SAMSIM_SA11.Config.FireDome
    local snowDrift = SAMSIM_SA11.State.snowDrift

    if not telar.track.valid then
        telar.mode = SAMSIM_SA11.FireDomeMode.ACQUISITION
        return
    end

    local contact = snowDrift.contacts[telar.targetId]
    local targetUnit = nil

    if contact then
        targetUnit = Unit.getByName(contact.name)
    end

    if targetUnit and targetUnit:isExist() then
        local pos = targetUnit:getPoint()
        local vel = targetUnit:getVelocity()
        local sitePos = SAMSIM_SA11.State.site.position
        local relPos = vectorSubtract(pos, sitePos)

        -- Smoothing
        local alpha = 0.35
        telar.track.smoothedPosition.x = telar.track.smoothedPosition.x + alpha * (pos.x - telar.track.smoothedPosition.x)
        telar.track.smoothedPosition.y = telar.track.smoothedPosition.y + alpha * (pos.y - telar.track.smoothedPosition.y)
        telar.track.smoothedPosition.z = telar.track.smoothedPosition.z + alpha * (pos.z - telar.track.smoothedPosition.z)

        telar.track.smoothedVelocity.x = telar.track.smoothedVelocity.x + alpha * (vel.x - telar.track.smoothedVelocity.x)
        telar.track.smoothedVelocity.y = telar.track.smoothedVelocity.y + alpha * (vel.y - telar.track.smoothedVelocity.y)
        telar.track.smoothedVelocity.z = telar.track.smoothedVelocity.z + alpha * (vel.z - telar.track.smoothedVelocity.z)

        telar.track.position = pos
        telar.track.velocity = vel
        telar.track.range = vectorMagnitude(relPos)
        telar.track.azimuth = math.deg(math.atan2(relPos.x, relPos.z))
        if telar.track.azimuth < 0 then telar.track.azimuth = telar.track.azimuth + 360 end
        telar.track.elevation = math.deg(math.atan2(pos.y - sitePos.y,
            math.sqrt(relPos.x^2 + relPos.z^2)))
        telar.track.altitude = pos.y
        telar.track.speed = vectorMagnitude(vel)

        local rangeUnit = vectorScale(relPos, 1/telar.track.range)
        telar.track.rangeRate = -vectorDot(vel, rangeUnit)

        telar.antenna.targetAz = telar.track.azimuth
        telar.antenna.targetEl = telar.track.elevation

        local azError = math.abs(normalizeAngle(telar.antenna.azimuth - telar.track.azimuth))
        local elError = math.abs(telar.antenna.elevation - telar.track.elevation)
        local totalError = math.sqrt(azError^2 + elError^2)

        telar.trackQuality = math.max(0, math.min(1, 1 - totalError / config.TRACK_BEAM_WIDTH))

        if totalError > config.TRACK_BEAM_WIDTH * 4 then
            telar.track.valid = false
            telar.mode = SAMSIM_SA11.FireDomeMode.ACQUISITION
        end
    else
        telar.track.valid = false
        telar.mode = SAMSIM_SA11.FireDomeMode.ACQUISITION
    end

    SAMSIM_SA11.calculateTelarFiringSolution(telar)
end

function SAMSIM_SA11.calculateTelarFiringSolution(telar)
    local solution = telar.firingSolution
    local track = telar.track
    local missileConfig = SAMSIM_SA11.Config.Missile
    local sitePos = SAMSIM_SA11.State.site.position

    if not track.valid then
        solution.valid = false
        return
    end

    local range = track.range
    local altitude = track.altitude

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

    -- Pk calculation
    local rangeFactor = 1 - (range / missileConfig.MAX_RANGE)^1.8
    local altFactor = 1.0
    if altitude < 100 then
        altFactor = 0.85 + 0.15 * (altitude / 100)
    end
    local trackQualityFactor = telar.trackQuality

    solution.pk = math.max(0, math.min(0.82,
        0.70 * rangeFactor * altFactor * trackQualityFactor))

    solution.valid = solution.inEnvelope and telar.trackQuality > 0.4
end

-- ============================================================================
-- Target Assignment
-- ============================================================================
function SAMSIM_SA11.assignTarget(targetId, telarNum)
    local telars = SAMSIM_SA11.State.telars
    local snowDrift = SAMSIM_SA11.State.snowDrift

    if telarNum < 1 or telarNum > 4 then
        return false, "Invalid TELAR number"
    end

    local telar = telars[telarNum]
    local contact = snowDrift.contacts[targetId]

    if not contact then
        return false, "Target not found"
    end

    if telar.missilesReady <= 0 then
        return false, "TELAR has no missiles"
    end

    telar.active = true
    telar.targetId = targetId
    telar.mode = SAMSIM_SA11.FireDomeMode.ACQUISITION
    telar.acquisitionTimer = 0
    telar.track.valid = false

    return true, "Target assigned to TELAR " .. telarNum
end

-- ============================================================================
-- Missile Launch
-- ============================================================================
function SAMSIM_SA11.launchMissile(telarNum)
    local telar = SAMSIM_SA11.State.telars[telarNum]
    local missiles = SAMSIM_SA11.State.missiles

    if not telar or not telar.active then
        return false, "TELAR not active"
    end

    if not telar.firingSolution.valid then
        return false, "No valid firing solution"
    end

    if telar.missilesReady <= 0 then
        return false, "No missiles ready on TELAR"
    end

    telar.mode = SAMSIM_SA11.FireDomeMode.ILLUMINATION
    telar.missilesReady = telar.missilesReady - 1

    missiles.totalReady = missiles.totalReady - 1
    missiles.inFlight = missiles.inFlight + 1

    return true, "Missile launched from TELAR " .. telarNum
end

-- ============================================================================
-- Command Interface
-- ============================================================================
function SAMSIM_SA11.processCommand(cmd)
    local response = {success = false, message = "Unknown command"}

    if cmd.type == "POWER" then
        if cmd.system == "SNOWDRIFT" then
            SAMSIM_SA11.State.snowDrift.mode = cmd.state == "ON" and
                SAMSIM_SA11.SnowDriftMode.STANDBY or SAMSIM_SA11.SnowDriftMode.OFF
        elseif cmd.system == "TELAR" then
            local telarNum = cmd.telar or SAMSIM_SA11.State.activeTelar
            SAMSIM_SA11.State.telars[telarNum].mode = cmd.state == "ON" and
                SAMSIM_SA11.FireDomeMode.STANDBY or SAMSIM_SA11.FireDomeMode.OFF
        end
        response = {success = true, message = cmd.system .. " power " .. cmd.state}

    elseif cmd.type == "SNOWDRIFT_MODE" then
        if cmd.mode == "SEARCH" then
            SAMSIM_SA11.State.snowDrift.mode = SAMSIM_SA11.SnowDriftMode.SEARCH
        elseif cmd.mode == "SECTOR" then
            SAMSIM_SA11.State.snowDrift.mode = SAMSIM_SA11.SnowDriftMode.SECTOR
            if cmd.center then SAMSIM_SA11.State.snowDrift.sectorCenter = cmd.center end
            if cmd.width then SAMSIM_SA11.State.snowDrift.sectorWidth = cmd.width end
        elseif cmd.mode == "MTI" then
            SAMSIM_SA11.State.snowDrift.mode = SAMSIM_SA11.SnowDriftMode.MTI
        elseif cmd.mode == "STANDBY" then
            SAMSIM_SA11.State.snowDrift.mode = SAMSIM_SA11.SnowDriftMode.STANDBY
        end
        response = {success = true, message = "Snow Drift mode set to " .. cmd.mode}

    elseif cmd.type == "SELECT_TELAR" then
        if cmd.telar >= 1 and cmd.telar <= 4 then
            SAMSIM_SA11.State.activeTelar = cmd.telar
            response = {success = true, message = "Selected TELAR " .. cmd.telar}
        end

    elseif cmd.type == "DESIGNATE" then
        local telarNum = cmd.telar or SAMSIM_SA11.State.activeTelar
        local success, msg = SAMSIM_SA11.assignTarget(cmd.targetId, telarNum)
        response = {success = success, message = msg}

    elseif cmd.type == "LAUNCH" then
        local telarNum = cmd.telar or SAMSIM_SA11.State.activeTelar
        local success, msg = SAMSIM_SA11.launchMissile(telarNum)
        response = {success = success, message = msg}

    elseif cmd.type == "TELAR_COMMAND" then
        local telar = SAMSIM_SA11.State.telars[cmd.telar]
        if telar then
            if cmd.action == "DROP" then
                telar.active = false
                telar.mode = SAMSIM_SA11.FireDomeMode.STANDBY
                telar.track.valid = false
            elseif cmd.action == "TRACK" then
                if telar.track.valid then
                    telar.mode = SAMSIM_SA11.FireDomeMode.TRACK
                end
            end
            response = {success = true, message = "TELAR command executed"}
        end
    end

    return response
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM_SA11.getStateForExport()
    local state = SAMSIM_SA11.State

    local contactsList = {}
    for id, contact in pairs(state.snowDrift.contacts) do
        table.insert(contactsList, {
            id = id,
            typeName = contact.typeName,
            range = math.floor(contact.range),
            azimuth = math.floor(contact.azimuth * 10) / 10,
            altitude = math.floor(contact.altitude),
            speed = math.floor(contact.speed),
            rangeRate = math.floor(contact.rangeRate or 0),
        })
    end

    local telarsData = {}
    for i, telar in ipairs(state.telars) do
        telarsData[i] = {
            id = telar.id,
            active = telar.active,
            mode = telar.mode,
            modeName = SAMSIM_SA11.getFireDomeModeName(telar.mode),
            missilesReady = telar.missilesReady,
            antennaAz = telar.antenna.azimuth,
            antennaEl = telar.antenna.elevation,
            targetId = telar.targetId,
            trackValid = telar.track.valid,
            trackRange = telar.track.range,
            trackAzimuth = telar.track.azimuth,
            trackElevation = telar.track.elevation,
            trackAltitude = telar.track.altitude,
            trackQuality = telar.trackQuality,
            cwPower = telar.cwPower,
            firingSolutionValid = telar.firingSolution.valid,
            inEnvelope = telar.firingSolution.inEnvelope,
            pk = telar.firingSolution.pk,
        }
    end

    return {
        systemType = "SA11",
        systemName = SAMSIM_SA11.SystemName,
        timestamp = timer.getTime(),

        snowDrift = {
            mode = state.snowDrift.mode,
            modeName = SAMSIM_SA11.getSnowDriftModeName(state.snowDrift.mode),
            azimuth = state.snowDrift.azimuth,
            sectorCenter = state.snowDrift.sectorCenter,
            sectorWidth = state.snowDrift.sectorWidth,
            contactCount = #contactsList,
        },

        contacts = contactsList,
        telars = telarsData,
        activeTelar = state.activeTelar,

        missiles = {
            totalReady = state.missiles.totalReady,
            inFlight = state.missiles.inFlight,
        },

        config = {
            snowDriftMaxRange = SAMSIM_SA11.Config.SnowDrift.MAX_RANGE,
            fireDomeMaxRange = SAMSIM_SA11.Config.FireDome.MAX_RANGE,
            missileMaxRange = SAMSIM_SA11.Config.Missile.MAX_RANGE,
            missileMinRange = SAMSIM_SA11.Config.Missile.MIN_RANGE,
            telarCount = 4,
        },
    }
end

function SAMSIM_SA11.getSnowDriftModeName(mode)
    local names = {"OFF", "STANDBY", "SEARCH", "SECTOR", "MTI"}
    return names[mode + 1] or "UNKNOWN"
end

function SAMSIM_SA11.getFireDomeModeName(mode)
    local names = {"OFF", "STANDBY", "ACQUISITION", "TRACK", "ILLUMINATION"}
    return names[mode + 1] or "UNKNOWN"
end

-- ============================================================================
-- Main Update Loop
-- ============================================================================
function SAMSIM_SA11.update()
    local currentTime = timer.getTime()
    if not SAMSIM_SA11.lastUpdate then
        SAMSIM_SA11.lastUpdate = currentTime
    end

    local dt = currentTime - SAMSIM_SA11.lastUpdate
    SAMSIM_SA11.lastUpdate = currentTime

    SAMSIM_SA11.updateSnowDrift(dt)

    for _, telar in ipairs(SAMSIM_SA11.State.telars) do
        SAMSIM_SA11.updateTelar(telar, dt)
    end

    return timer.getTime() + SAMSIM_SA11.Config.UPDATE_INTERVAL
end

-- ============================================================================
-- Initialization
-- ============================================================================
function SAMSIM_SA11.initialize(siteName, position, heading)
    SAMSIM_SA11.State.site.name = siteName or "SA11_Battery"
    SAMSIM_SA11.State.site.position = position or {x=0, y=0, z=0}
    SAMSIM_SA11.State.site.heading = heading or 0

    SAMSIM_SA11.State.missiles.totalReady = 16
    SAMSIM_SA11.State.missiles.inFlight = 0

    for _, telar in ipairs(SAMSIM_SA11.State.telars) do
        telar.missilesReady = 4
    end

    timer.scheduleFunction(SAMSIM_SA11.update, nil, timer.getTime() + 0.1)

    env.info("SAMSIM SA-11: Initialized battery " .. SAMSIM_SA11.State.site.name)
end

env.info("SAMSIM SA-11 (9K37 Buk) Controller loaded - Version " .. SAMSIM_SA11.Version)
