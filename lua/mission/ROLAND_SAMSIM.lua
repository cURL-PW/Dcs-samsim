--[[
    Roland SAM System Simulation for DCS World

    System Variants:
    - Roland 1 (optical only)
    - Roland 2 (radar + optical)
    - Roland 3 (improved radar)

    All-in-one vehicle with:
    - Search radar
    - Tracking radar/optics
    - 2 ready missiles + 8 stowed

    Author: Claude Code
    Version: 1.0
]]

ROLAND_SAMSIM = {}
ROLAND_SAMSIM.Version = "1.0.0"

-- ============================================================================
-- Configuration
-- ============================================================================
ROLAND_SAMSIM.Config = {
    -- Search Radar (Roland 2/3)
    searchRadar = {
        range = 18000,              -- 18km
        azimuthCoverage = 360,
        rotationSpeed = 60,         -- RPM
        minAltitude = 20,
        maxAltitude = 5500,
    },

    -- Tracking Radar (Roland 2/3)
    trackRadar = {
        range = 16000,              -- 16km
        beamWidth = 1.3,            -- degrees
        monopulse = true,
    },

    -- Optical Tracker (all variants)
    optical = {
        range = 10000,              -- 10km effective
        fov = 3,                    -- degrees
        irCapable = true,           -- Thermal imaging
        dayOnly = false,            -- Can work at night with IR
    },

    -- Roland Missile
    missile = {
        maxRange = 8000,            -- 8km (Roland 3: up to 9.5km)
        minRange = 500,             -- 500m
        maxAltitude = 6000,
        minAltitude = 15,
        maxSpeed = 570,             -- Mach 1.7
        maxG = 16,
        guidance = "SACLOS",        -- Semi-Automatic Command to Line of Sight
        warheadWeight = 6.5,        -- kg
        warheadRadius = 8,
        flightTime = 13,            -- seconds max
    },

    -- Launcher
    launcher = {
        ready = 2,                  -- 2 on rails
        stowed = 8,                 -- 8 in magazine
        reloadTime = 10,            -- 10 seconds per missile
        autoReload = true,
    },
}

-- ============================================================================
-- System State
-- ============================================================================
ROLAND_SAMSIM.State = {
    variant = "ROLAND2",            -- ROLAND1, ROLAND2, ROLAND3
    powerState = "OFF",
    systemStatus = "COLD",          -- COLD, READY, TRACKING, ENGAGING

    -- Search Radar
    searchRadar = {
        mode = 0,
        modeName = "OFF",
        azimuth = 0,
        contacts = {},
    },

    -- Track system (radar or optical)
    tracker = {
        mode = 0,
        modeName = "OFF",
        type = "RADAR",             -- RADAR or OPTICAL
        azimuth = 0,
        elevation = 0,
        targetId = nil,
        lockOn = false,
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

    -- Contacts
    contacts = {},

    -- Missiles
    missiles = {
        onRail = 2,
        inMagazine = 8,
        inFlight = 0,
        active = {},
        reloading = false,
        reloadProgress = 0,
    },

    -- Firing solution
    firingSolution = {
        valid = false,
        pk = 0,
        timeToIntercept = 0,
        inEnvelope = false,
    },

    -- EMCON (Emission Control)
    emcon = false,                  -- When true, radar off, optical only
}

-- ============================================================================
-- Search Radar Operations
-- ============================================================================
ROLAND_SAMSIM.SearchRadar = {}

function ROLAND_SAMSIM.SearchRadar.setMode(mode)
    if ROLAND_SAMSIM.State.emcon and mode > 1 then
        -- Cannot activate radar in EMCON
        return false
    end

    local modeNames = {
        [0] = "OFF",
        [1] = "STANDBY",
        [2] = "SEARCH",
    }

    ROLAND_SAMSIM.State.searchRadar.mode = mode
    ROLAND_SAMSIM.State.searchRadar.modeName = modeNames[mode] or "UNKNOWN"
    return true
end

function ROLAND_SAMSIM.SearchRadar.update(dt)
    local state = ROLAND_SAMSIM.State
    local config = ROLAND_SAMSIM.Config.searchRadar

    if state.searchRadar.mode < 2 then return end
    if state.emcon then return end  -- No radar in EMCON

    -- Rotate antenna
    state.searchRadar.azimuth = state.searchRadar.azimuth + (config.rotationSpeed * 6 * dt)
    if state.searchRadar.azimuth >= 360 then
        state.searchRadar.azimuth = state.searchRadar.azimuth - 360
    end

    -- Scan
    state.contacts = ROLAND_SAMSIM.SearchRadar.scan()
end

function ROLAND_SAMSIM.SearchRadar.scan()
    local config = ROLAND_SAMSIM.Config.searchRadar
    local contacts = {}

    local sitePos = ROLAND_SAMSIM.getSitePosition()
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
-- Tracker Operations (Radar or Optical)
-- ============================================================================
ROLAND_SAMSIM.Tracker = {}

function ROLAND_SAMSIM.Tracker.setMode(mode)
    local modeNames = {
        [0] = "OFF",
        [1] = "STANDBY",
        [2] = "ACQUISITION",
        [3] = "TRACK",
        [4] = "GUIDANCE",
    }

    ROLAND_SAMSIM.State.tracker.mode = mode
    ROLAND_SAMSIM.State.tracker.modeName = modeNames[mode] or "UNKNOWN"

    if mode < 3 then
        ROLAND_SAMSIM.State.tracker.lockOn = false
    end
end

function ROLAND_SAMSIM.Tracker.setType(trackerType)
    -- RADAR or OPTICAL
    ROLAND_SAMSIM.State.tracker.type = trackerType

    if trackerType == "OPTICAL" then
        -- Optical can work in EMCON
    elseif trackerType == "RADAR" and ROLAND_SAMSIM.State.emcon then
        -- Cannot use radar in EMCON, switch to optical
        ROLAND_SAMSIM.State.tracker.type = "OPTICAL"
    end
end

function ROLAND_SAMSIM.Tracker.slew(azimuth, elevation)
    ROLAND_SAMSIM.State.tracker.azimuth = azimuth
    ROLAND_SAMSIM.State.tracker.elevation = elevation
end

function ROLAND_SAMSIM.Tracker.designate(contactId)
    local state = ROLAND_SAMSIM.State

    for _, contact in ipairs(state.contacts) do
        if contact.id == contactId then
            state.tracker.targetId = contactId
            ROLAND_SAMSIM.Tracker.slew(contact.azimuth, contact.elevation)
            ROLAND_SAMSIM.Tracker.setMode(3)  -- Track mode
            return true
        end
    end

    return false
end

function ROLAND_SAMSIM.Tracker.update(dt)
    local state = ROLAND_SAMSIM.State

    if state.tracker.mode < 3 or not state.tracker.targetId then
        state.track.valid = false
        return
    end

    -- Find target
    local target = nil
    for _, contact in ipairs(state.contacts) do
        if contact.id == state.tracker.targetId then
            target = contact
            break
        end
    end

    -- If using optical and radar is off, need to search optically
    if not target and state.tracker.type == "OPTICAL" then
        target = ROLAND_SAMSIM.Tracker.opticalSearch()
    end

    if target then
        local config = state.tracker.type == "RADAR" and
                       ROLAND_SAMSIM.Config.trackRadar or
                       ROLAND_SAMSIM.Config.optical

        -- Check range
        if target.range <= config.range then
            state.track.valid = true
            state.track.id = target.id
            state.track.range = target.range
            state.track.azimuth = target.azimuth
            state.track.elevation = target.elevation
            state.track.altitude = target.altitude
            state.track.speed = target.speed
            state.track.heading = target.heading
            state.track.quality = math.min(1.0, state.track.quality + dt * 0.3)

            state.tracker.lockOn = true
            state.tracker.azimuth = target.azimuth
            state.tracker.elevation = target.elevation

            -- Calculate firing solution
            ROLAND_SAMSIM.calculateFiringSolution()
        else
            state.track.quality = state.track.quality - dt * 0.2
            if state.track.quality <= 0 then
                state.track.valid = false
                state.tracker.lockOn = false
            end
        end
    else
        state.track.quality = state.track.quality - dt * 0.4
        if state.track.quality <= 0 then
            state.track.valid = false
            state.tracker.lockOn = false
        end
    end
end

function ROLAND_SAMSIM.Tracker.opticalSearch()
    -- Optical-only search (limited FOV)
    local state = ROLAND_SAMSIM.State
    local config = ROLAND_SAMSIM.Config.optical

    local sitePos = ROLAND_SAMSIM.getSitePosition()
    if not sitePos then return nil end

    local volume = {
        id = world.VolumeType.SPHERE,
        params = {
            point = sitePos,
            radius = config.range,
        }
    }

    local found = nil

    world.searchObjects(Object.Category.UNIT, volume, function(unit)
        if unit and unit:isExist() and unit:getID() == state.tracker.targetId then
            local desc = unit:getDesc()
            if desc.category == Unit.Category.AIRPLANE or
               desc.category == Unit.Category.HELICOPTER then

                local targetPos = unit:getPoint()
                local dx = targetPos.x - sitePos.x
                local dz = targetPos.z - sitePos.z
                local range = math.sqrt(dx*dx + dz*dz)
                local azimuth = math.deg(math.atan2(dz, dx))
                if azimuth < 0 then azimuth = azimuth + 360 end
                local altitude = targetPos.y - sitePos.y
                local elevation = math.deg(math.atan2(altitude, range))
                local vel = unit:getVelocity()
                local speed = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)
                local heading = math.deg(math.atan2(vel.z, vel.x))
                if heading < 0 then heading = heading + 360 end

                -- Check if in optical FOV
                local azDiff = math.abs(azimuth - state.tracker.azimuth)
                if azDiff > 180 then azDiff = 360 - azDiff end
                local elDiff = math.abs(elevation - state.tracker.elevation)

                if azDiff <= config.fov/2 and elDiff <= config.fov/2 then
                    found = {
                        id = unit:getID(),
                        unitName = unit:getName(),
                        typeName = unit:getTypeName(),
                        range = range,
                        azimuth = azimuth,
                        elevation = elevation,
                        altitude = altitude,
                        speed = speed,
                        heading = heading,
                        position = targetPos,
                    }
                end
            end
        end
        return found == nil
    end)

    return found
end

-- ============================================================================
-- Firing Solution
-- ============================================================================
function ROLAND_SAMSIM.calculateFiringSolution()
    local state = ROLAND_SAMSIM.State
    local config = ROLAND_SAMSIM.Config.missile
    local solution = state.firingSolution

    if not state.track.valid then
        solution.valid = false
        return
    end

    -- Range checks
    local inRangeMax = state.track.range <= config.maxRange
    local inRangeMin = state.track.range >= config.minRange
    local inAltitude = state.track.altitude >= config.minAltitude and
                       state.track.altitude <= config.maxAltitude

    solution.inEnvelope = inRangeMax and inRangeMin and inAltitude

    if not solution.inEnvelope then
        solution.valid = false
        solution.pk = 0
        return
    end

    -- Calculate Pk (SACLOS guidance)
    local basePk = 0.70

    -- Range factor (SACLOS degrades with range)
    local rangeFactor = 1 - (state.track.range / config.maxRange) * 0.5

    -- Quality factor
    local qualityFactor = state.track.quality

    -- Crossing target penalty (harder for SACLOS)
    local crossingPenalty = 1.0
    local sitePos = ROLAND_SAMSIM.getSitePosition()
    if sitePos then
        local targetBearing = math.deg(math.atan2(
            state.track.position.z - sitePos.z,
            state.track.position.x - sitePos.x
        ))
        if targetBearing < 0 then targetBearing = targetBearing + 360 end
        local aspectAngle = math.abs(state.track.heading - targetBearing)
        if aspectAngle > 180 then aspectAngle = 360 - aspectAngle end
        if aspectAngle > 60 and aspectAngle < 120 then
            crossingPenalty = 0.7  -- Beam aspect harder
        end
    end

    solution.pk = basePk * rangeFactor * qualityFactor * crossingPenalty
    solution.timeToIntercept = state.track.range / (config.maxSpeed * 0.7)
    solution.valid = true
end

-- ============================================================================
-- Missile Operations
-- ============================================================================
ROLAND_SAMSIM.Missile = {}

function ROLAND_SAMSIM.Missile.launch()
    local state = ROLAND_SAMSIM.State

    if state.missiles.onRail <= 0 then
        return false, "No missiles on rail"
    end

    if not state.track.valid then
        return false, "No valid track"
    end

    if not state.firingSolution.valid then
        return false, "No valid solution"
    end

    -- Launch
    state.missiles.onRail = state.missiles.onRail - 1
    state.missiles.inFlight = state.missiles.inFlight + 1

    local missile = {
        id = #state.missiles.active + 1,
        targetId = state.track.id,
        launchTime = timer.getTime(),
        position = ROLAND_SAMSIM.getSitePosition(),
        phase = "BOOST",
        timeToIntercept = state.firingSolution.timeToIntercept,
        pk = state.firingSolution.pk,
    }

    table.insert(state.missiles.active, missile)

    -- Set tracker to guidance mode
    ROLAND_SAMSIM.Tracker.setMode(4)

    -- Start auto-reload
    if state.missiles.inMagazine > 0 and ROLAND_SAMSIM.Config.launcher.autoReload then
        state.missiles.reloading = true
        state.missiles.reloadProgress = 0
    end

    return true, "Missile launched"
end

function ROLAND_SAMSIM.Missile.update(dt)
    local state = ROLAND_SAMSIM.State
    local config = ROLAND_SAMSIM.Config.missile

    -- Update active missiles
    for i = #state.missiles.active, 1, -1 do
        local missile = state.missiles.active[i]
        local elapsed = timer.getTime() - missile.launchTime

        -- Update phase
        if elapsed < 0.5 then
            missile.phase = "BOOST"
        elseif elapsed < missile.timeToIntercept * 0.7 then
            missile.phase = "CRUISE"
        else
            missile.phase = "TERMINAL"
        end

        -- Check max flight time
        if elapsed > config.flightTime then
            missile.result = "TIMEOUT"
            state.missiles.inFlight = state.missiles.inFlight - 1
            table.remove(state.missiles.active, i)
        elseif elapsed >= missile.timeToIntercept then
            -- Intercept
            local roll = math.random()
            if roll < missile.pk then
                missile.result = "KILL"
            else
                missile.result = "MISS"
            end
            state.missiles.inFlight = state.missiles.inFlight - 1
            table.remove(state.missiles.active, i)
        end
    end

    -- Handle reload
    if state.missiles.reloading then
        state.missiles.reloadProgress = state.missiles.reloadProgress + dt
        if state.missiles.reloadProgress >= ROLAND_SAMSIM.Config.launcher.reloadTime then
            if state.missiles.inMagazine > 0 and state.missiles.onRail < 2 then
                state.missiles.inMagazine = state.missiles.inMagazine - 1
                state.missiles.onRail = state.missiles.onRail + 1
                state.missiles.reloadProgress = 0

                -- Continue reloading if needed
                if state.missiles.onRail < 2 and state.missiles.inMagazine > 0 then
                    -- Keep reloading
                else
                    state.missiles.reloading = false
                end
            else
                state.missiles.reloading = false
            end
        end
    end
end

-- ============================================================================
-- EMCON Mode
-- ============================================================================
function ROLAND_SAMSIM.setEMCON(enabled)
    ROLAND_SAMSIM.State.emcon = enabled

    if enabled then
        -- Turn off all radars
        ROLAND_SAMSIM.SearchRadar.setMode(0)
        ROLAND_SAMSIM.State.tracker.type = "OPTICAL"
    end
end

-- ============================================================================
-- Command Processing
-- ============================================================================
function ROLAND_SAMSIM.processCommand(cmd)
    local cmdType = cmd.type

    if cmdType == "POWER" then
        if cmd.state == "ON" then
            ROLAND_SAMSIM.State.powerState = "ON"
            ROLAND_SAMSIM.State.systemStatus = "READY"
            return {success = true, message = "Power ON"}
        else
            ROLAND_SAMSIM.State.powerState = "OFF"
            ROLAND_SAMSIM.State.systemStatus = "COLD"
            ROLAND_SAMSIM.SearchRadar.setMode(0)
            ROLAND_SAMSIM.Tracker.setMode(0)
            return {success = true, message = "Power OFF"}
        end

    elseif cmdType == "SEARCH_MODE" then
        local modes = {OFF = 0, STANDBY = 1, SEARCH = 2}
        ROLAND_SAMSIM.SearchRadar.setMode(modes[cmd.mode] or 0)
        return {success = true, message = "Search radar: " .. (cmd.mode or "OFF")}

    elseif cmdType == "TRACKER_MODE" then
        local modes = {OFF = 0, STANDBY = 1, ACQUISITION = 2, TRACK = 3, GUIDANCE = 4}
        ROLAND_SAMSIM.Tracker.setMode(modes[cmd.mode] or 0)
        return {success = true, message = "Tracker: " .. (cmd.mode or "OFF")}

    elseif cmdType == "TRACKER_TYPE" then
        ROLAND_SAMSIM.Tracker.setType(cmd.trackerType or "RADAR")
        return {success = true, message = "Tracker type: " .. (cmd.trackerType or "RADAR")}

    elseif cmdType == "DESIGNATE" then
        local success = ROLAND_SAMSIM.Tracker.designate(cmd.targetId)
        return {success = success, message = success and "Designated" or "Target not found"}

    elseif cmdType == "LAUNCH" then
        local success, msg = ROLAND_SAMSIM.Missile.launch()
        return {success = success, message = msg}

    elseif cmdType == "DROP_TRACK" then
        ROLAND_SAMSIM.State.track.valid = false
        ROLAND_SAMSIM.State.tracker.lockOn = false
        ROLAND_SAMSIM.State.tracker.targetId = nil
        ROLAND_SAMSIM.Tracker.setMode(2)
        return {success = true, message = "Track dropped"}

    elseif cmdType == "EMCON" then
        ROLAND_SAMSIM.setEMCON(cmd.enable)
        return {success = true, message = "EMCON " .. (cmd.enable and "ON" or "OFF")}

    elseif cmdType == "SET_VARIANT" then
        ROLAND_SAMSIM.State.variant = cmd.variant or "ROLAND2"
        return {success = true, message = "Variant: " .. cmd.variant}
    end

    return {success = false, message = "Unknown command"}
end

-- ============================================================================
-- State Export
-- ============================================================================
function ROLAND_SAMSIM.getStateForExport()
    local state = ROLAND_SAMSIM.State

    return {
        systemType = "ROLAND",
        systemName = "Roland",
        variant = state.variant,
        version = ROLAND_SAMSIM.Version,
        powerState = state.powerState,
        systemStatus = state.systemStatus,
        emcon = state.emcon,

        searchRadar = {
            mode = state.searchRadar.mode,
            modeName = state.searchRadar.modeName,
            azimuth = state.searchRadar.azimuth,
        },

        tracker = {
            mode = state.tracker.mode,
            modeName = state.tracker.modeName,
            type = state.tracker.type,
            azimuth = state.tracker.azimuth,
            elevation = state.tracker.elevation,
            lockOn = state.tracker.lockOn,
        },

        track = state.track,
        contacts = state.contacts,

        missiles = {
            onRail = state.missiles.onRail,
            inMagazine = state.missiles.inMagazine,
            inFlight = state.missiles.inFlight,
            active = state.missiles.active,
            reloading = state.missiles.reloading,
            reloadProgress = state.missiles.reloadProgress,
        },

        firingSolution = state.firingSolution,
    }
end

-- ============================================================================
-- Utility Functions
-- ============================================================================
function ROLAND_SAMSIM.getSitePosition()
    return ROLAND_SAMSIM.sitePosition or {x = 0, y = 0, z = 0}
end

function ROLAND_SAMSIM.getCoalition()
    return ROLAND_SAMSIM.coalition or 2
end

function ROLAND_SAMSIM.initialize(groupName, position, heading)
    ROLAND_SAMSIM.groupName = groupName
    ROLAND_SAMSIM.sitePosition = position
    ROLAND_SAMSIM.heading = heading or 0

    timer.scheduleFunction(function()
        ROLAND_SAMSIM.SearchRadar.update(0.1)
        ROLAND_SAMSIM.Tracker.update(0.1)
        ROLAND_SAMSIM.Missile.update(0.1)
        return timer.getTime() + 0.1
    end, nil, timer.getTime() + 1)

    env.info("ROLAND SAMSIM initialized: " .. (groupName or "Unknown"))
end

env.info("ROLAND SAMSIM loaded - Version " .. ROLAND_SAMSIM.Version)
