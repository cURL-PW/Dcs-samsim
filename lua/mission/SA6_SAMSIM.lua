--[[
    SA-6 Gainful (2K12 Kub) SAMSim Controller for DCS World

    System Components:
    - 1S91 "Straight Flush" SPAR (Self-Propelled Acquisition Radar)
      - Combined search and fire control radar
    - 2P25 TEL (Transporter Erector Launcher) with 3M9 missiles

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_SA6 = {}
SAMSIM_SA6.Version = "1.0.0"
SAMSIM_SA6.SystemName = "2K12 Kub (SA-6 Gainful)"

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_SA6.Config = {
    -- 1S91 "Straight Flush" Combined Radar
    -- Unique feature: Combined search and track radar on single vehicle
    Radar1S91 = {
        -- Search radar (top antenna)
        SEARCH_MAX_RANGE = 75000,     -- 75km search range
        SEARCH_MIN_RANGE = 1000,
        SEARCH_MAX_ALT = 14000,
        SEARCH_MIN_ALT = 20,          -- Very good low altitude
        SEARCH_ROTATION_PERIOD = 5,    -- 5 seconds
        SEARCH_BEAM_WIDTH_AZ = 1.5,
        SEARCH_DETECTION_PROB = 0.90,

        -- Track radar (parabolic antenna)
        TRACK_MAX_RANGE = 28000,      -- 28km track range
        TRACK_MIN_RANGE = 4000,       -- 4km minimum
        TRACK_BEAM_WIDTH = 1.0,
        TRACK_PRECISION = 0.3,        -- mrad
        ACQUISITION_TIME = 2,

        -- CW Illuminator
        CW_ILLUMINATION_RANGE = 24000, -- 24km illumination range

        ANTENNA_SLEW_RATE = 25,       -- Fast slew rate
        POWER_KW = 200,
        FREQUENCY_GHZ = 8.0,          -- X-band
    },

    -- 3M9 (3M9M3) Missile
    Missile = {
        MAX_RANGE = 24000,            -- 24km
        MIN_RANGE = 4000,             -- 4km
        MAX_ALTITUDE = 14000,         -- 14km
        MIN_ALTITUDE = 50,            -- 50m
        MAX_SPEED = 800,              -- Mach 2.8
        ACCELERATION = 20,            -- 20g
        GUIDANCE = "SARH",            -- Semi-Active Radar Homing
        WARHEAD_KG = 56,
        PROXIMITY_FUZE_M = 15,
    },

    -- System settings
    System = {
        REACTION_TIME = 22,           -- 22 seconds (faster than static systems)
        RELOAD_TIME = 10,             -- 10 minutes (vehicle must return to reload)
        MISSILES_PER_TEL = 3,         -- 3 missiles per TEL
    },

    UPDATE_INTERVAL = 0.05,
}

-- ============================================================================
-- System States
-- ============================================================================
SAMSIM_SA6.RadarMode = {
    OFF = 0,
    STANDBY = 1,
    SEARCH = 2,
    IFF = 3,              -- IFF interrogation
    ACQUISITION = 4,
    TRACK = 5,
    ILLUMINATION = 6,     -- CW illumination for SARH guidance
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_SA6.State = {
    radar = {
        mode = 0,
        -- Search antenna
        searchAzimuth = 0,
        searchElevation = 5,
        -- Track antenna
        trackAzimuth = 0,
        trackElevation = 10,
        targetAzimuth = 0,
        targetElevation = 0,
        -- Acquisition
        acquisitionTimer = 0,
        -- Track state
        trackQuality = 0,
        cwPower = 0,        -- CW illuminator power (0-100)
    },

    contacts = {},
    selectedContact = nil,

    track = {
        valid = false,
        id = nil,
        position = {x=0, y=0, z=0},
        velocity = {x=0, y=0, z=0},
        range = 0,
        azimuth = 0,
        elevation = 0,
        altitude = 0,
        speed = 0,
        heading = 0,
        rangeRate = 0,      -- Doppler
        smoothedPosition = {x=0, y=0, z=0},
        smoothedVelocity = {x=0, y=0, z=0},
    },

    firingSolution = {
        valid = false,
        interceptPoint = {x=0, y=0, z=0},
        timeToIntercept = 0,
        inEnvelope = false,
        pk = 0,
    },

    missiles = {
        ready = 3,
        inFlight = 0,
    },

    site = {
        position = {x=0, y=0, z=0},
        heading = 0,
        name = "SA6_Battery",
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
SAMSIM_SA6.RCSDatabase = {
    ["F-15C"] = 5.0, ["F-15E"] = 6.0, ["F-16C"] = 1.2,
    ["FA-18C"] = 1.5, ["F-14A"] = 10.0, ["F-4E"] = 8.0,
    ["MiG-21"] = 3.0, ["MiG-23"] = 5.0, ["MiG-29A"] = 3.0,
    ["Su-27"] = 10.0, ["Su-25"] = 8.0, ["A-10A"] = 15.0,
    ["M-2000C"] = 1.5, ["JF-17"] = 2.0,
    ["F-22A"] = 0.0001, ["F-35A"] = 0.001,
    ["B-52H"] = 100.0, ["Tu-22M3"] = 40.0,
    ["UH-1H"] = 5.0, ["AH-64D"] = 3.5, ["Mi-24P"] = 10.0,
    DEFAULT = 5.0,
}

function SAMSIM_SA6.estimateRCS(typeName)
    for pattern, rcs in pairs(SAMSIM_SA6.RCSDatabase) do
        if pattern ~= "DEFAULT" and string.find(typeName, pattern) then
            return rcs
        end
    end
    return SAMSIM_SA6.RCSDatabase.DEFAULT
end

-- ============================================================================
-- 1S91 Radar Simulation
-- ============================================================================
function SAMSIM_SA6.updateRadar(dt)
    local state = SAMSIM_SA6.State.radar
    local config = SAMSIM_SA6.Config.Radar1S91

    if state.mode == SAMSIM_SA6.RadarMode.OFF then
        state.cwPower = 0
        return
    end

    if state.mode == SAMSIM_SA6.RadarMode.STANDBY then
        state.cwPower = 0
        return
    end

    -- Search mode - rotate search antenna
    if state.mode >= SAMSIM_SA6.RadarMode.SEARCH then
        state.searchAzimuth = state.searchAzimuth + (360 / config.SEARCH_ROTATION_PERIOD) * dt
        if state.searchAzimuth >= 360 then
            state.searchAzimuth = state.searchAzimuth - 360
        end

        SAMSIM_SA6.scanForContacts()
    end

    -- Track antenna slew
    if state.mode >= SAMSIM_SA6.RadarMode.ACQUISITION then
        local azDiff = normalizeAngle(state.targetAzimuth - state.trackAzimuth)
        local elDiff = state.targetElevation - state.trackElevation
        local slewRate = config.ANTENNA_SLEW_RATE * dt

        if math.abs(azDiff) > slewRate then
            state.trackAzimuth = state.trackAzimuth + slewRate * (azDiff > 0 and 1 or -1)
        else
            state.trackAzimuth = state.targetAzimuth
        end

        if math.abs(elDiff) > slewRate then
            state.trackElevation = state.trackElevation + slewRate * (elDiff > 0 and 1 or -1)
        else
            state.trackElevation = state.targetElevation
        end

        state.trackAzimuth = normalizeAngle(state.trackAzimuth)
        state.trackElevation = math.max(-5, math.min(80, state.trackElevation))
    end

    if state.mode == SAMSIM_SA6.RadarMode.ACQUISITION then
        SAMSIM_SA6.processAcquisition(dt)
    elseif state.mode == SAMSIM_SA6.RadarMode.TRACK then
        SAMSIM_SA6.processTrack(dt)
        state.cwPower = 0
    elseif state.mode == SAMSIM_SA6.RadarMode.ILLUMINATION then
        SAMSIM_SA6.processIllumination(dt)
        state.cwPower = 100
    end
end

function SAMSIM_SA6.scanForContacts()
    local state = SAMSIM_SA6.State.radar
    local config = SAMSIM_SA6.Config.Radar1S91
    local sitePos = SAMSIM_SA6.State.site.position

    local sphere = {
        id = world.VolumeType.SPHERE,
        params = {
            point = sitePos,
            radius = config.SEARCH_MAX_RANGE
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
    local currentContacts = {}

    for _, obj in ipairs(foundObjects) do
        local pos = obj:getPoint()
        local vel = obj:getVelocity()
        local relPos = vectorSubtract(pos, sitePos)
        local range = vectorMagnitude(relPos)
        local azimuth = math.deg(math.atan2(relPos.x, relPos.z))
        if azimuth < 0 then azimuth = azimuth + 360 end
        local altitude = pos.y

        if altitude >= config.SEARCH_MIN_ALT and altitude <= config.SEARCH_MAX_ALT and
           range >= config.SEARCH_MIN_RANGE and range <= config.SEARCH_MAX_RANGE then

            local azDiff = math.abs(normalizeAngle(azimuth - state.searchAzimuth))
            if azDiff <= config.SEARCH_BEAM_WIDTH_AZ / 2 then
                local rcs = SAMSIM_SA6.estimateRCS(obj:getTypeName())

                -- Calculate range rate (Doppler)
                local rangeUnit = vectorScale(relPos, 1/range)
                local rangeRate = -vectorDot(vel, rangeUnit)

                -- SA-6 uses Doppler, so needs target with radial velocity
                local dopplerFactor = math.min(1, math.abs(rangeRate) / 50)
                local detectionProb = config.SEARCH_DETECTION_PROB * dopplerFactor

                if math.random() < detectionProb then
                    local id = obj:getID()
                    currentContacts[id] = {
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

    for id, contact in pairs(currentContacts) do
        SAMSIM_SA6.State.contacts[id] = contact
    end

    for id, contact in pairs(SAMSIM_SA6.State.contacts) do
        if currentTime - contact.lastSeen > 6 then
            SAMSIM_SA6.State.contacts[id] = nil
        end
    end
end

function SAMSIM_SA6.processAcquisition(dt)
    local state = SAMSIM_SA6.State.radar
    local config = SAMSIM_SA6.Config.Radar1S91

    if not SAMSIM_SA6.State.selectedContact then
        return
    end

    local contact = SAMSIM_SA6.State.contacts[SAMSIM_SA6.State.selectedContact]
    if not contact then
        return
    end

    state.targetAzimuth = contact.azimuth
    state.targetElevation = math.deg(math.atan2(contact.altitude,
        math.sqrt((contact.position.x - SAMSIM_SA6.State.site.position.x)^2 +
                  (contact.position.z - SAMSIM_SA6.State.site.position.z)^2)))

    local azError = math.abs(normalizeAngle(state.trackAzimuth - contact.azimuth))
    local elError = math.abs(state.trackElevation - state.targetElevation)

    if azError < config.TRACK_BEAM_WIDTH and elError < config.TRACK_BEAM_WIDTH then
        state.acquisitionTimer = state.acquisitionTimer + dt

        if state.acquisitionTimer >= config.ACQUISITION_TIME then
            state.mode = SAMSIM_SA6.RadarMode.TRACK
            state.trackQuality = 0.6
            SAMSIM_SA6.initializeTrack(contact)
        end
    else
        state.acquisitionTimer = math.max(0, state.acquisitionTimer - dt * 0.5)
    end
end

function SAMSIM_SA6.initializeTrack(contact)
    local track = SAMSIM_SA6.State.track
    track.valid = true
    track.id = contact.id
    track.position = deepCopy(contact.position)
    track.velocity = deepCopy(contact.velocity)
    track.smoothedPosition = deepCopy(contact.position)
    track.smoothedVelocity = deepCopy(contact.velocity)
    track.range = contact.range
    track.azimuth = contact.azimuth
    track.altitude = contact.altitude
    track.rangeRate = contact.rangeRate
    track.lastUpdate = timer.getTime()
end

function SAMSIM_SA6.processTrack(dt)
    local state = SAMSIM_SA6.State.radar
    local track = SAMSIM_SA6.State.track
    local config = SAMSIM_SA6.Config.Radar1S91

    if not track.valid then
        state.mode = SAMSIM_SA6.RadarMode.ACQUISITION
        return
    end

    local targetUnit = nil
    for _, contact in pairs(SAMSIM_SA6.State.contacts) do
        if contact.id == track.id then
            targetUnit = Unit.getByName(contact.name)
            break
        end
    end

    if targetUnit and targetUnit:isExist() then
        local pos = targetUnit:getPoint()
        local vel = targetUnit:getVelocity()
        local sitePos = SAMSIM_SA6.State.site.position
        local relPos = vectorSubtract(pos, sitePos)

        -- Smoothing
        local alpha = 0.35
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

        -- Range rate (Doppler)
        local rangeUnit = vectorScale(relPos, 1/track.range)
        track.rangeRate = -vectorDot(vel, rangeUnit)

        track.lastUpdate = timer.getTime()

        state.targetAzimuth = track.azimuth
        state.targetElevation = track.elevation

        local azError = math.abs(normalizeAngle(state.trackAzimuth - track.azimuth))
        local elError = math.abs(state.trackElevation - track.elevation)
        local totalError = math.sqrt(azError^2 + elError^2)

        state.trackQuality = math.max(0, math.min(1, 1 - totalError / config.TRACK_BEAM_WIDTH))

        if totalError > config.TRACK_BEAM_WIDTH * 3 then
            track.valid = false
            state.mode = SAMSIM_SA6.RadarMode.ACQUISITION
        end
    else
        track.valid = false
        state.mode = SAMSIM_SA6.RadarMode.ACQUISITION
    end

    SAMSIM_SA6.calculateFiringSolution()
end

function SAMSIM_SA6.processIllumination(dt)
    SAMSIM_SA6.processTrack(dt)
end

-- ============================================================================
-- Firing Solution
-- ============================================================================
function SAMSIM_SA6.calculateFiringSolution()
    local track = SAMSIM_SA6.State.track
    local solution = SAMSIM_SA6.State.firingSolution
    local missileConfig = SAMSIM_SA6.Config.Missile
    local sitePos = SAMSIM_SA6.State.site.position

    if not track.valid then
        solution.valid = false
        return
    end

    local range = track.range
    local altitude = track.altitude

    -- Intercept calculation
    local missileAvgSpeed = missileConfig.MAX_SPEED * 0.65
    local closingSpeed = track.rangeRate
    local timeToIntercept = range / (missileAvgSpeed + closingSpeed)

    local interceptPoint = vectorAdd(track.smoothedPosition, vectorScale(track.smoothedVelocity, timeToIntercept))

    solution.interceptPoint = interceptPoint
    solution.timeToIntercept = timeToIntercept

    -- Envelope check
    solution.inRangeMax = range <= missileConfig.MAX_RANGE
    solution.inRangeMin = range >= missileConfig.MIN_RANGE
    solution.inAltitude = altitude >= missileConfig.MIN_ALTITUDE and altitude <= missileConfig.MAX_ALTITUDE
    solution.inEnvelope = solution.inRangeMax and solution.inRangeMin and solution.inAltitude

    -- Pk calculation
    local rangeFactor = 1 - (range / missileConfig.MAX_RANGE)^2
    local altFactor = 1.0
    if altitude < 200 then
        altFactor = 0.7 + 0.3 * (altitude / 200)
    end
    local trackQualityFactor = SAMSIM_SA6.State.radar.trackQuality

    solution.pk = math.max(0, math.min(0.75,
        0.65 * rangeFactor * altFactor * trackQualityFactor))

    solution.valid = solution.inEnvelope and SAMSIM_SA6.State.radar.trackQuality > 0.4
end

-- ============================================================================
-- Missile Launch
-- ============================================================================
function SAMSIM_SA6.launchMissile()
    local state = SAMSIM_SA6.State
    local solution = state.firingSolution
    local missiles = state.missiles

    if not solution.valid then
        return false, "No valid firing solution"
    end

    if missiles.ready <= 0 then
        return false, "No missiles ready"
    end

    -- Switch to illumination mode for SARH guidance
    state.radar.mode = SAMSIM_SA6.RadarMode.ILLUMINATION

    missiles.ready = missiles.ready - 1
    missiles.inFlight = missiles.inFlight + 1

    return true, "Missile launched - CW illumination active"
end

-- ============================================================================
-- Command Interface
-- ============================================================================
function SAMSIM_SA6.processCommand(cmd)
    local response = {success = false, message = "Unknown command"}

    if cmd.type == "POWER" then
        if cmd.state == "ON" then
            SAMSIM_SA6.State.radar.mode = SAMSIM_SA6.RadarMode.STANDBY
        else
            SAMSIM_SA6.State.radar.mode = SAMSIM_SA6.RadarMode.OFF
        end
        response = {success = true, message = "Radar power " .. cmd.state}

    elseif cmd.type == "RADAR_MODE" then
        if cmd.mode == "SEARCH" then
            SAMSIM_SA6.State.radar.mode = SAMSIM_SA6.RadarMode.SEARCH
        elseif cmd.mode == "STANDBY" then
            SAMSIM_SA6.State.radar.mode = SAMSIM_SA6.RadarMode.STANDBY
        elseif cmd.mode == "TRACK" then
            SAMSIM_SA6.State.radar.mode = SAMSIM_SA6.RadarMode.TRACK
        end
        response = {success = true, message = "Radar mode set to " .. cmd.mode}

    elseif cmd.type == "DESIGNATE" then
        SAMSIM_SA6.State.selectedContact = cmd.targetId
        SAMSIM_SA6.State.radar.mode = SAMSIM_SA6.RadarMode.ACQUISITION
        SAMSIM_SA6.State.radar.acquisitionTimer = 0
        response = {success = true, message = "Target designated"}

    elseif cmd.type == "LAUNCH" then
        local success, msg = SAMSIM_SA6.launchMissile()
        response = {success = success, message = msg}

    elseif cmd.type == "ANTENNA" then
        if cmd.azimuth then SAMSIM_SA6.State.radar.targetAzimuth = cmd.azimuth end
        if cmd.elevation then SAMSIM_SA6.State.radar.targetElevation = cmd.elevation end
        response = {success = true, message = "Antenna command accepted"}
    end

    return response
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM_SA6.getStateForExport()
    local state = SAMSIM_SA6.State

    local contactsList = {}
    for id, contact in pairs(state.contacts) do
        table.insert(contactsList, {
            id = id,
            typeName = contact.typeName,
            range = math.floor(contact.range),
            azimuth = math.floor(contact.azimuth * 10) / 10,
            altitude = math.floor(contact.altitude),
            speed = math.floor(contact.speed),
            heading = math.floor(contact.heading),
            rangeRate = math.floor(contact.rangeRate),
        })
    end

    return {
        systemType = "SA6",
        systemName = SAMSIM_SA6.SystemName,
        timestamp = timer.getTime(),

        radar = {
            mode = state.radar.mode,
            modeName = SAMSIM_SA6.getModeNameRadar(state.radar.mode),
            searchAzimuth = state.radar.searchAzimuth,
            trackAzimuth = state.radar.trackAzimuth,
            trackElevation = state.radar.trackElevation,
            trackQuality = state.radar.trackQuality,
            cwPower = state.radar.cwPower,
            acquisitionProgress = state.radar.acquisitionTimer / SAMSIM_SA6.Config.Radar1S91.ACQUISITION_TIME,
        },

        contacts = contactsList,
        selectedContact = state.selectedContact,

        track = {
            valid = state.track.valid,
            range = state.track.range,
            azimuth = state.track.azimuth,
            elevation = state.track.elevation,
            altitude = state.track.altitude,
            speed = state.track.speed,
            heading = state.track.heading,
            rangeRate = state.track.rangeRate,
        },

        firingSolution = {
            valid = state.firingSolution.valid,
            inEnvelope = state.firingSolution.inEnvelope,
            timeToIntercept = state.firingSolution.timeToIntercept,
            pk = state.firingSolution.pk,
        },

        missiles = {
            ready = state.missiles.ready,
            inFlight = state.missiles.inFlight,
        },

        config = {
            searchMaxRange = SAMSIM_SA6.Config.Radar1S91.SEARCH_MAX_RANGE,
            trackMaxRange = SAMSIM_SA6.Config.Radar1S91.TRACK_MAX_RANGE,
            missileMaxRange = SAMSIM_SA6.Config.Missile.MAX_RANGE,
            missileMinRange = SAMSIM_SA6.Config.Missile.MIN_RANGE,
        },
    }
end

function SAMSIM_SA6.getModeNameRadar(mode)
    local names = {"OFF", "STANDBY", "SEARCH", "IFF", "ACQUISITION", "TRACK", "ILLUMINATION"}
    return names[mode + 1] or "UNKNOWN"
end

-- ============================================================================
-- Main Update Loop
-- ============================================================================
function SAMSIM_SA6.update()
    local currentTime = timer.getTime()
    if not SAMSIM_SA6.lastUpdate then
        SAMSIM_SA6.lastUpdate = currentTime
    end

    local dt = currentTime - SAMSIM_SA6.lastUpdate
    SAMSIM_SA6.lastUpdate = currentTime

    SAMSIM_SA6.updateRadar(dt)

    return timer.getTime() + SAMSIM_SA6.Config.UPDATE_INTERVAL
end

-- ============================================================================
-- Initialization
-- ============================================================================
function SAMSIM_SA6.initialize(siteName, position, heading)
    SAMSIM_SA6.State.site.name = siteName or "SA6_Battery"
    SAMSIM_SA6.State.site.position = position or {x=0, y=0, z=0}
    SAMSIM_SA6.State.site.heading = heading or 0

    SAMSIM_SA6.State.missiles.ready = 3
    SAMSIM_SA6.State.missiles.inFlight = 0

    timer.scheduleFunction(SAMSIM_SA6.update, nil, timer.getTime() + 0.1)

    env.info("SAMSIM SA-6: Initialized battery " .. SAMSIM_SA6.State.site.name)
end

env.info("SAMSIM SA-6 (2K12 Kub) Controller loaded - Version " .. SAMSIM_SA6.Version)
