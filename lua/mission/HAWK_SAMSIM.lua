--[[
    MIM-23 HAWK SAM System Simulation for DCS World

    System Components:
    - AN/MPQ-50 Pulse Acquisition Radar (PAR)
    - AN/MPQ-46 High Power Illuminator Radar (HPI)
    - AN/MPQ-48 Continuous Wave Acquisition Radar (CWAR)
    - AN/MPQ-51 Range Only Radar (ROR)
    - M192 Launcher (3 missiles each)

    Author: Claude Code
    Version: 1.0
]]

HAWK_SAMSIM = {}
HAWK_SAMSIM.Version = "1.0.0"

-- ============================================================================
-- Configuration
-- ============================================================================
HAWK_SAMSIM.Config = {
    -- AN/MPQ-50 Pulse Acquisition Radar
    par = {
        range = 100000,             -- 100km search range
        azimuthCoverage = 360,      -- Full rotation
        rotationSpeed = 20,         -- 20 RPM
        minAltitude = 60,
        maxAltitude = 18000,
    },

    -- AN/MPQ-46 High Power Illuminator
    hpi = {
        trackRange = 60000,         -- 60km track range
        beamWidth = 2.5,            -- degrees
        maxTargets = 1,             -- Single target illumination
        cwPower = 5000,             -- Watts
    },

    -- AN/MPQ-48 CWAR
    cwar = {
        range = 50000,              -- 50km
        dopplerProcessing = true,
        lowAltitudeCapable = true,
    },

    -- MIM-23B Missile
    missile = {
        maxRange = 40000,           -- 40km
        minRange = 2000,            -- 2km
        maxAltitude = 18000,
        minAltitude = 30,
        maxSpeed = 900,             -- Mach 2.7
        maxG = 20,
        guidance = "SARH",          -- Semi-Active Radar Homing
        warheadWeight = 75,         -- kg
        warheadRadius = 15,
    },

    -- Launcher configuration
    launcher = {
        missilesPerLauncher = 3,
        launchers = 3,              -- 9 missiles total
        reloadTime = 300,           -- 5 minutes
    },
}

-- ============================================================================
-- System State
-- ============================================================================
HAWK_SAMSIM.State = {
    powerState = "OFF",
    batteryStatus = "COLD",         -- COLD, WARM, HOT

    -- PAR state
    par = {
        mode = 0,
        modeName = "OFF",
        azimuth = 0,
        rotation = true,
        contacts = {},
    },

    -- HPI (Illuminator) state
    hpi = {
        mode = 0,
        modeName = "OFF",
        targetAzimuth = 0,
        targetElevation = 0,
        illuminating = false,
        targetId = nil,
    },

    -- CWAR state
    cwar = {
        mode = 0,
        enabled = false,
    },

    -- Current track
    track = {
        valid = false,
        id = nil,
        range = 0,
        azimuth = 0,
        elevation = 0,
        altitude = 0,
        speed = 0,
        heading = 0,
        quality = 0,
    },

    -- Contacts list
    contacts = {},

    -- Missiles
    missiles = {
        total = 9,
        ready = 9,
        inFlight = 0,
        active = {},
    },

    -- Firing solution
    firingSolution = {
        valid = false,
        pk = 0,
        timeToIntercept = 0,
        inEnvelope = false,
    },

    -- IFF
    iff = {
        mode = 3,
        lastResponse = "NONE",
    },
}

-- ============================================================================
-- PAR (Pulse Acquisition Radar) Operations
-- ============================================================================
HAWK_SAMSIM.PAR = {}

function HAWK_SAMSIM.PAR.setMode(mode)
    local modeNames = {
        [0] = "OFF",
        [1] = "STANDBY",
        [2] = "SEARCH",
        [3] = "TRACK_HANDOFF",
    }

    HAWK_SAMSIM.State.par.mode = mode
    HAWK_SAMSIM.State.par.modeName = modeNames[mode] or "UNKNOWN"
end

function HAWK_SAMSIM.PAR.update(dt)
    local state = HAWK_SAMSIM.State
    local config = HAWK_SAMSIM.Config.par

    if state.par.mode < 2 then return end

    -- Rotate antenna
    if state.par.rotation then
        state.par.azimuth = state.par.azimuth + (config.rotationSpeed * 6 * dt)  -- 6 deg/sec at 1RPM
        if state.par.azimuth >= 360 then
            state.par.azimuth = state.par.azimuth - 360
        end
    end

    -- Scan for targets
    local contacts = HAWK_SAMSIM.PAR.scan()
    state.contacts = contacts
end

function HAWK_SAMSIM.PAR.scan()
    local state = HAWK_SAMSIM.State
    local config = HAWK_SAMSIM.Config.par
    local contacts = {}

    local sitePos = HAWK_SAMSIM.getSitePosition()
    if not sitePos then return contacts end

    local volume = {
        id = world.VolumeType.SPHERE,
        params = {
            point = sitePos,
            radius = config.range,
        }
    }

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

                local altitude = targetPos.y - sitePos.y

                if altitude >= config.minAltitude and altitude <= config.maxAltitude then
                    local elevation = math.deg(math.atan2(altitude, range))
                    local vel = found:getVelocity()
                    local speed = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)
                    local heading = math.deg(math.atan2(vel.z, vel.x))
                    if heading < 0 then heading = heading + 360 end

                    table.insert(contacts, {
                        id = found:getID(),
                        unitName = found:getName(),
                        typeName = found:getTypeName(),
                        range = range,
                        azimuth = azimuth,
                        elevation = elevation,
                        altitude = altitude,
                        speed = speed,
                        heading = heading,
                        position = targetPos,
                    })
                end
            end
        end
        return true
    end)

    return contacts
end

-- ============================================================================
-- HPI (High Power Illuminator) Operations
-- ============================================================================
HAWK_SAMSIM.HPI = {}

function HAWK_SAMSIM.HPI.setMode(mode)
    local modeNames = {
        [0] = "OFF",
        [1] = "STANDBY",
        [2] = "ACQUISITION",
        [3] = "TRACK",
        [4] = "ILLUMINATION",
    }

    HAWK_SAMSIM.State.hpi.mode = mode
    HAWK_SAMSIM.State.hpi.modeName = modeNames[mode] or "UNKNOWN"

    if mode < 4 then
        HAWK_SAMSIM.State.hpi.illuminating = false
    end
end

function HAWK_SAMSIM.HPI.slew(azimuth, elevation)
    HAWK_SAMSIM.State.hpi.targetAzimuth = azimuth
    HAWK_SAMSIM.State.hpi.targetElevation = elevation
end

function HAWK_SAMSIM.HPI.designate(contactId)
    local state = HAWK_SAMSIM.State

    -- Find contact
    for _, contact in ipairs(state.contacts) do
        if contact.id == contactId then
            state.hpi.targetId = contactId

            -- Slew to target
            HAWK_SAMSIM.HPI.slew(contact.azimuth, contact.elevation)

            -- Begin tracking
            HAWK_SAMSIM.HPI.setMode(3)

            return true
        end
    end

    return false
end

function HAWK_SAMSIM.HPI.illuminate()
    local state = HAWK_SAMSIM.State

    if state.hpi.mode < 3 or not state.hpi.targetId then
        return false
    end

    state.hpi.mode = 4
    state.hpi.modeName = "ILLUMINATION"
    state.hpi.illuminating = true

    return true
end

function HAWK_SAMSIM.HPI.update(dt)
    local state = HAWK_SAMSIM.State

    if state.hpi.mode < 3 or not state.hpi.targetId then
        state.track.valid = false
        return
    end

    -- Find target in contacts
    local target = nil
    for _, contact in ipairs(state.contacts) do
        if contact.id == state.hpi.targetId then
            target = contact
            break
        end
    end

    if target then
        -- Update track
        state.track.valid = true
        state.track.id = target.id
        state.track.range = target.range
        state.track.azimuth = target.azimuth
        state.track.elevation = target.elevation
        state.track.altitude = target.altitude
        state.track.speed = target.speed
        state.track.heading = target.heading
        state.track.quality = math.min(1.0, state.track.quality + dt * 0.2)

        -- Update slew position
        state.hpi.targetAzimuth = target.azimuth
        state.hpi.targetElevation = target.elevation

        -- Calculate firing solution
        HAWK_SAMSIM.calculateFiringSolution()
    else
        -- Lost track
        state.track.quality = state.track.quality - dt * 0.3
        if state.track.quality <= 0 then
            state.track.valid = false
            state.hpi.illuminating = false
        end
    end
end

-- ============================================================================
-- Firing Solution
-- ============================================================================
function HAWK_SAMSIM.calculateFiringSolution()
    local state = HAWK_SAMSIM.State
    local config = HAWK_SAMSIM.Config.missile
    local solution = state.firingSolution

    if not state.track.valid then
        solution.valid = false
        return
    end

    -- Range checks
    local inRangeMax = state.track.range <= config.maxRange
    local inRangeMin = state.track.range >= config.minRange

    -- Altitude checks
    local inAltitude = state.track.altitude >= config.minAltitude and
                       state.track.altitude <= config.maxAltitude

    solution.inEnvelope = inRangeMax and inRangeMin and inAltitude

    if not solution.inEnvelope then
        solution.valid = false
        solution.pk = 0
        return
    end

    -- Calculate Pk
    local basePk = 0.75

    -- Range factor
    local rangeFactor = 1 - (state.track.range / config.maxRange) * 0.4

    -- Aspect factor
    local aspectFactor = 0.85

    -- Quality factor
    local qualityFactor = state.track.quality

    solution.pk = basePk * rangeFactor * aspectFactor * qualityFactor

    -- Time to intercept
    local missileSpeed = config.maxSpeed * 0.75
    solution.timeToIntercept = state.track.range / missileSpeed

    solution.valid = true
end

-- ============================================================================
-- Missile Operations
-- ============================================================================
HAWK_SAMSIM.Missile = {}

function HAWK_SAMSIM.Missile.launch()
    local state = HAWK_SAMSIM.State

    if state.missiles.ready <= 0 then
        return false, "No missiles ready"
    end

    if not state.track.valid then
        return false, "No valid track"
    end

    if not state.hpi.illuminating then
        return false, "Illuminator not active"
    end

    if not state.firingSolution.valid then
        return false, "No valid firing solution"
    end

    -- Launch
    state.missiles.ready = state.missiles.ready - 1
    state.missiles.inFlight = state.missiles.inFlight + 1

    local missile = {
        id = #state.missiles.active + 1,
        targetId = state.track.id,
        launchTime = timer.getTime(),
        position = HAWK_SAMSIM.getSitePosition(),
        phase = "BOOST",
        timeToIntercept = state.firingSolution.timeToIntercept,
    }

    table.insert(state.missiles.active, missile)

    return true, "Missile launched"
end

function HAWK_SAMSIM.Missile.update(dt)
    local state = HAWK_SAMSIM.State

    for i = #state.missiles.active, 1, -1 do
        local missile = state.missiles.active[i]
        local elapsed = timer.getTime() - missile.launchTime

        -- Update phase
        if elapsed < 2 then
            missile.phase = "BOOST"
        elseif elapsed < missile.timeToIntercept * 0.6 then
            missile.phase = "CRUISE"
        else
            missile.phase = "TERMINAL"
        end

        -- Check intercept
        if elapsed >= missile.timeToIntercept then
            -- Simulate kill assessment
            local killProbability = state.firingSolution.pk
            local roll = math.random()

            if roll < killProbability then
                missile.result = "KILL"
            else
                missile.result = "MISS"
            end

            state.missiles.inFlight = state.missiles.inFlight - 1
            table.remove(state.missiles.active, i)
        end
    end
end

-- ============================================================================
-- IFF Operations
-- ============================================================================
HAWK_SAMSIM.IFF = {}

function HAWK_SAMSIM.IFF.interrogate(contactId)
    local state = HAWK_SAMSIM.State

    for _, contact in ipairs(state.contacts) do
        if contact.id == contactId then
            local unit = Unit.getByName(contact.unitName)
            if unit then
                local coalition = unit:getCoalition()
                local siteCoalition = HAWK_SAMSIM.getCoalition()

                if coalition == siteCoalition then
                    state.iff.lastResponse = "FRIENDLY"
                elseif coalition == 0 then
                    state.iff.lastResponse = "NEUTRAL"
                else
                    state.iff.lastResponse = "HOSTILE"
                end
            else
                state.iff.lastResponse = "NO_RESPONSE"
            end

            return state.iff.lastResponse
        end
    end

    return "CONTACT_NOT_FOUND"
end

-- ============================================================================
-- Command Processing
-- ============================================================================
function HAWK_SAMSIM.processCommand(cmd)
    local cmdType = cmd.type

    if cmdType == "POWER" then
        if cmd.state == "ON" then
            HAWK_SAMSIM.State.powerState = "ON"
            HAWK_SAMSIM.State.batteryStatus = "WARM"
            return {success = true, message = "Power ON"}
        else
            HAWK_SAMSIM.State.powerState = "OFF"
            HAWK_SAMSIM.State.batteryStatus = "COLD"
            HAWK_SAMSIM.PAR.setMode(0)
            HAWK_SAMSIM.HPI.setMode(0)
            return {success = true, message = "Power OFF"}
        end

    elseif cmdType == "PAR_MODE" then
        local modes = {OFF = 0, STANDBY = 1, SEARCH = 2, TRACK_HANDOFF = 3}
        HAWK_SAMSIM.PAR.setMode(modes[cmd.mode] or 0)
        return {success = true, message = "PAR mode: " .. (cmd.mode or "OFF")}

    elseif cmdType == "HPI_MODE" then
        local modes = {OFF = 0, STANDBY = 1, ACQUISITION = 2, TRACK = 3, ILLUMINATION = 4}
        HAWK_SAMSIM.HPI.setMode(modes[cmd.mode] or 0)
        return {success = true, message = "HPI mode: " .. (cmd.mode or "OFF")}

    elseif cmdType == "DESIGNATE" then
        local success = HAWK_SAMSIM.HPI.designate(cmd.targetId)
        return {success = success, message = success and "Designated" or "Target not found"}

    elseif cmdType == "ILLUMINATE" then
        local success = HAWK_SAMSIM.HPI.illuminate()
        return {success = success, message = success and "Illuminating" or "Cannot illuminate"}

    elseif cmdType == "LAUNCH" then
        local success, msg = HAWK_SAMSIM.Missile.launch()
        return {success = success, message = msg}

    elseif cmdType == "DROP_TRACK" then
        HAWK_SAMSIM.State.track.valid = false
        HAWK_SAMSIM.State.hpi.illuminating = false
        HAWK_SAMSIM.State.hpi.targetId = nil
        HAWK_SAMSIM.HPI.setMode(2)
        return {success = true, message = "Track dropped"}

    elseif cmdType == "IFF_INTERROGATE" then
        local response = HAWK_SAMSIM.IFF.interrogate(cmd.targetId)
        return {success = true, iffStatus = response}
    end

    return {success = false, message = "Unknown command"}
end

-- ============================================================================
-- State Export
-- ============================================================================
function HAWK_SAMSIM.getStateForExport()
    local state = HAWK_SAMSIM.State

    return {
        systemType = "HAWK",
        systemName = "MIM-23 HAWK",
        version = HAWK_SAMSIM.Version,
        powerState = state.powerState,
        batteryStatus = state.batteryStatus,

        par = {
            mode = state.par.mode,
            modeName = state.par.modeName,
            azimuth = state.par.azimuth,
        },

        hpi = {
            mode = state.hpi.mode,
            modeName = state.hpi.modeName,
            targetAzimuth = state.hpi.targetAzimuth,
            targetElevation = state.hpi.targetElevation,
            illuminating = state.hpi.illuminating,
        },

        track = state.track,
        contacts = state.contacts,

        missiles = {
            total = state.missiles.total,
            ready = state.missiles.ready,
            inFlight = state.missiles.inFlight,
            active = state.missiles.active,
        },

        firingSolution = state.firingSolution,
        iff = state.iff,
    }
end

-- ============================================================================
-- Utility Functions
-- ============================================================================
function HAWK_SAMSIM.getSitePosition()
    return HAWK_SAMSIM.sitePosition or {x = 0, y = 0, z = 0}
end

function HAWK_SAMSIM.getCoalition()
    return HAWK_SAMSIM.coalition or 2
end

function HAWK_SAMSIM.initialize(groupName, position, heading)
    HAWK_SAMSIM.groupName = groupName
    HAWK_SAMSIM.sitePosition = position
    HAWK_SAMSIM.heading = heading or 0

    timer.scheduleFunction(function()
        HAWK_SAMSIM.PAR.update(0.1)
        HAWK_SAMSIM.HPI.update(0.1)
        HAWK_SAMSIM.Missile.update(0.1)
        return timer.getTime() + 0.1
    end, nil, timer.getTime() + 1)

    env.info("HAWK SAMSIM initialized: " .. (groupName or "Unknown"))
end

env.info("HAWK SAMSIM loaded - Version " .. HAWK_SAMSIM.Version)
