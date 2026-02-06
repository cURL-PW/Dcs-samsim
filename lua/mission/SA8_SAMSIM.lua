--[[
    SA-8 Gecko (9K33 Osa) SAM System Simulation
    Short-range mobile SAM system

    Characteristics:
    - All-in-one vehicle (radar + missiles on same platform)
    - Land Roll surveillance radar
    - Engagement radar with optical backup
    - 9M33 missiles (6 ready)
    - Effective range: 2-10 km
    - Altitude: 25m - 5000m
]]

SA8_SAMSIM = {}

-- System configuration
SA8_SAMSIM.Config = {
    -- Land Roll Radar (surveillance/tracking)
    radar = {
        searchRange = 30000,      -- 30 km search range
        trackRange = 20000,       -- 20 km tracking range
        searchAzimuth = 360,      -- Full rotation
        rotationRate = 33,        -- 33 rpm
        beamWidth = 1.5,          -- degrees
        minElevation = -5,
        maxElevation = 80,
        frequency = 6000,         -- MHz (C-band)
        peakPower = 250,          -- kW
        prf = 3000,
    },

    -- Optical Tracking System (backup)
    optical = {
        fov = 2,                  -- degrees
        maxRange = 15000,
        tracking = true,
    },

    -- 9M33 Missile
    missile = {
        name = "9M33",
        maxRange = 10000,         -- 10 km
        minRange = 1500,          -- 1.5 km
        maxAltitude = 5000,
        minAltitude = 25,
        maxSpeed = 500,           -- m/s
        guidance = "CLOS_RADIO",  -- Command to Line of Sight
        warhead = 19,             -- kg
        fuze = "PROX_CONTACT",
    },

    -- Launcher
    launcher = {
        missiles = 6,             -- 6 missiles ready
        reloadTime = 300,         -- 5 minutes per missile (in field)
    },
}

-- Radar modes
SA8_SAMSIM.RadarMode = {
    OFF = 0,
    STANDBY = 1,
    SEARCH = 2,
    ACQUISITION = 3,
    TRACK = 4,
    ENGAGE = 5,
    OPTICAL = 6,      -- Optical tracking (EMCON)
}

-- System state
SA8_SAMSIM.State = {
    mode = 0,
    modeName = "OFF",

    -- Radar state
    radarAzimuth = 0,
    radarElevation = 5,
    searchAzimuth = 0,

    -- Track data
    trackValid = false,
    trackId = nil,
    trackRange = 0,
    trackAzimuth = 0,
    trackElevation = 0,
    trackQuality = 0,

    -- Optical tracking
    opticalActive = false,
    opticalTrackValid = false,

    -- Missiles
    missilesReady = 6,
    missilesInFlight = 0,
    activeMissiles = {},

    -- Detected contacts
    contacts = {},

    -- Fire control
    firingSolution = {
        valid = false,
        inEnvelope = false,
        pk = 0,
        timeToIntercept = 0,
    },
}

-- Mode names lookup
SA8_SAMSIM.ModeNames = {
    [0] = "OFF",
    [1] = "STANDBY",
    [2] = "SEARCH",
    [3] = "ACQUISITION",
    [4] = "TRACK",
    [5] = "ENGAGE",
    [6] = "OPTICAL",
}

function SA8_SAMSIM:initialize(groupName)
    self.groupName = groupName
    self.group = Group.getByName(groupName)
    self.position = self:getPosition()
    self.State.missilesReady = self.Config.launcher.missiles

    env.info(string.format("[SA-8] Initialized: %s", groupName))
    return self
end

function SA8_SAMSIM:getPosition()
    if self.group then
        local units = self.group:getUnits()
        if units and units[1] then
            return units[1]:getPoint()
        end
    end
    return {x = 0, y = 0, z = 0}
end

function SA8_SAMSIM:setMode(mode)
    if mode < 0 or mode > 6 then return end

    local oldMode = self.State.mode
    self.State.mode = mode
    self.State.modeName = self.ModeNames[mode]

    if mode == self.RadarMode.OFF then
        self.State.trackValid = false
        self.State.opticalActive = false
    elseif mode == self.RadarMode.OPTICAL then
        self.State.opticalActive = true
    else
        self.State.opticalActive = false
    end

    env.info(string.format("[SA-8] Mode changed: %s -> %s",
        self.ModeNames[oldMode], self.ModeNames[mode]))
end

function SA8_SAMSIM:update(dt)
    if self.State.mode == self.RadarMode.OFF then
        return
    end

    self.position = self:getPosition()

    -- Update search radar rotation
    if self.State.mode >= self.RadarMode.SEARCH then
        self.State.searchAzimuth = (self.State.searchAzimuth + self.Config.radar.rotationRate * 6 * dt) % 360
    end

    -- Scan for contacts
    if self.State.mode >= self.RadarMode.SEARCH then
        self:scanForTargets()
    end

    -- Update track
    if self.State.mode >= self.RadarMode.TRACK and self.State.trackId then
        self:updateTrack()
    end

    -- Update optical tracking
    if self.State.opticalActive and self.State.trackId then
        self:updateOpticalTrack()
    end

    -- Update missiles in flight
    self:updateMissiles(dt)

    -- Calculate firing solution
    if self.State.trackValid then
        self:calculateFiringSolution()
    end
end

function SA8_SAMSIM:scanForTargets()
    local detected = {}
    local searchRange = self.Config.radar.searchRange

    -- Get all air objects
    local sphere = trigger.misc.getZone("all") or {point = self.position, radius = searchRange}
    local volS = {
        id = world.VolumeType.SPHERE,
        params = {point = self.position, radius = searchRange}
    }

    local foundUnits = {}
    world.searchObjects(Object.Category.UNIT, volS, function(foundItem)
        if foundItem:getDesc().category == Unit.Category.AIRPLANE or
           foundItem:getDesc().category == Unit.Category.HELICOPTER then
            table.insert(foundUnits, foundItem)
        end
        return true
    end)

    for _, unit in ipairs(foundUnits) do
        if unit and unit:isExist() then
            local unitPos = unit:getPoint()
            local contact = self:processContact(unit, unitPos)

            if contact then
                table.insert(detected, contact)
            end
        end
    end

    self.State.contacts = detected
end

function SA8_SAMSIM:processContact(unit, unitPos)
    local dx = unitPos.x - self.position.x
    local dy = unitPos.y - self.position.y
    local dz = unitPos.z - self.position.z

    local horizontalRange = math.sqrt(dx*dx + dz*dz)
    local slantRange = math.sqrt(dx*dx + dy*dy + dz*dz)
    local azimuth = math.deg(math.atan2(dx, dz))
    if azimuth < 0 then azimuth = azimuth + 360 end
    local elevation = math.deg(math.atan2(dy, horizontalRange))

    -- Check if in radar coverage
    if slantRange > self.Config.radar.searchRange then
        return nil
    end

    -- Get velocity
    local velocity = unit:getVelocity()
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    local heading = math.deg(math.atan2(velocity.x, velocity.z))
    if heading < 0 then heading = heading + 360 end

    -- Check minimum altitude
    local altitude = unitPos.y - self.position.y
    if altitude < self.Config.missile.minAltitude then
        return nil
    end

    -- Calculate RCS and detection probability
    local rcs = self:estimateRCS(unit)
    local detectionProb = self:calculateDetectionProbability(slantRange, rcs, elevation)

    if math.random() > detectionProb then
        return nil
    end

    return {
        id = unit:getID(),
        unitId = unit:getID(),
        typeName = unit:getTypeName(),
        position = unitPos,
        range = slantRange,
        azimuth = azimuth,
        elevation = elevation,
        altitude = altitude,
        speed = speed,
        heading = heading,
        velocity = velocity,
        rcs = rcs,
    }
end

function SA8_SAMSIM:estimateRCS(unit)
    local typeName = unit:getTypeName():lower()

    -- Approximate RCS values
    if typeName:find("f%-16") or typeName:find("mig%-29") then
        return 3
    elseif typeName:find("f%-15") or typeName:find("su%-27") then
        return 10
    elseif typeName:find("a%-10") or typeName:find("su%-25") then
        return 15
    elseif typeName:find("heli") or typeName:find("mi%-") or typeName:find("ah%-") then
        return 5
    elseif typeName:find("uav") or typeName:find("drone") then
        return 0.5
    elseif typeName:find("cruise") or typeName:find("agm") then
        return 0.1
    else
        return 5
    end
end

function SA8_SAMSIM:calculateDetectionProbability(range, rcs, elevation)
    local maxRange = self.Config.radar.searchRange
    local normalizedRange = range / maxRange

    -- Base probability
    local prob = 0.95 * (1 - normalizedRange^2)

    -- RCS factor
    local rcsFactor = math.min(1, rcs / 5)
    prob = prob * (0.5 + 0.5 * rcsFactor)

    -- Low elevation penalty
    if elevation < 2 then
        prob = prob * (0.5 + 0.5 * elevation / 2)
    end

    return math.max(0, math.min(1, prob))
end

function SA8_SAMSIM:designateTarget(targetId)
    for _, contact in ipairs(self.State.contacts) do
        if contact.id == targetId then
            self.State.trackId = targetId
            self:setMode(self.RadarMode.ACQUISITION)
            env.info(string.format("[SA-8] Target designated: %d", targetId))
            return true
        end
    end
    return false
end

function SA8_SAMSIM:updateTrack()
    local targetUnit = Unit.getByName(tostring(self.State.trackId))
    if not targetUnit then
        targetUnit = nil
        for _, contact in ipairs(self.State.contacts) do
            if contact.id == self.State.trackId then
                targetUnit = Unit.getByName(contact.typeName) -- Fallback
                break
            end
        end
    end

    -- Try to find unit by ID
    local foundUnit = nil
    for _, contact in ipairs(self.State.contacts) do
        if contact.id == self.State.trackId then
            foundUnit = contact
            break
        end
    end

    if foundUnit then
        self.State.trackValid = true
        self.State.trackRange = foundUnit.range
        self.State.trackAzimuth = foundUnit.azimuth
        self.State.trackElevation = foundUnit.elevation

        -- Point antenna at target
        self.State.radarAzimuth = foundUnit.azimuth
        self.State.radarElevation = foundUnit.elevation

        -- Track quality based on range and signal
        local rangeNorm = foundUnit.range / self.Config.radar.trackRange
        self.State.trackQuality = math.max(0, 1 - rangeNorm * 0.5)

        if self.State.mode == self.RadarMode.ACQUISITION and self.State.trackQuality > 0.7 then
            self:setMode(self.RadarMode.TRACK)
        end
    else
        self.State.trackValid = false
        self.State.trackQuality = 0
    end
end

function SA8_SAMSIM:updateOpticalTrack()
    -- Optical tracking provides backup tracking without radar emissions
    for _, contact in ipairs(self.State.contacts) do
        if contact.id == self.State.trackId then
            if contact.range <= self.Config.optical.maxRange then
                self.State.opticalTrackValid = true
                self.State.trackValid = true
                self.State.trackRange = contact.range
                self.State.trackAzimuth = contact.azimuth
                self.State.trackElevation = contact.elevation
                self.State.trackQuality = 0.85  -- Optical gives good quality
                return
            end
        end
    end
    self.State.opticalTrackValid = false
end

function SA8_SAMSIM:calculateFiringSolution()
    if not self.State.trackValid then
        self.State.firingSolution.valid = false
        return
    end

    local range = self.State.trackRange
    local altitude = self.State.trackElevation

    -- Find contact data
    local contact = nil
    for _, c in ipairs(self.State.contacts) do
        if c.id == self.State.trackId then
            contact = c
            break
        end
    end

    if not contact then
        self.State.firingSolution.valid = false
        return
    end

    -- Check engagement envelope
    local inRangeMax = range <= self.Config.missile.maxRange
    local inRangeMin = range >= self.Config.missile.minRange
    local inAltMax = contact.altitude <= self.Config.missile.maxAltitude
    local inAltMin = contact.altitude >= self.Config.missile.minAltitude

    local inEnvelope = inRangeMax and inRangeMin and inAltMax and inAltMin

    -- Calculate Pk
    local pk = 0
    if inEnvelope then
        local rangeNorm = range / self.Config.missile.maxRange
        pk = 0.85 * (1 - rangeNorm * 0.3)

        -- Track quality factor
        pk = pk * self.State.trackQuality

        -- Target speed factor
        if contact.speed > 350 then
            pk = pk * 0.8
        end

        -- Altitude factor
        if contact.altitude < 100 then
            pk = pk * 0.7
        end
    end

    -- Time to intercept
    local missileSpeed = self.Config.missile.maxSpeed
    local timeToIntercept = range / missileSpeed

    self.State.firingSolution = {
        valid = inEnvelope and self.State.trackQuality > 0.6,
        inEnvelope = inEnvelope,
        inRangeMax = inRangeMax,
        inRangeMin = inRangeMin,
        inAltitude = inAltMax and inAltMin,
        pk = pk,
        timeToIntercept = timeToIntercept,
    }
end

function SA8_SAMSIM:launch()
    if not self.State.firingSolution.valid then
        return false, "No valid firing solution"
    end

    if self.State.missilesReady <= 0 then
        return false, "No missiles available"
    end

    if self.State.missilesInFlight >= 2 then
        return false, "Maximum missiles in flight"
    end

    -- Launch missile
    self.State.missilesReady = self.State.missilesReady - 1
    self.State.missilesInFlight = self.State.missilesInFlight + 1

    local missile = {
        id = #self.State.activeMissiles + 1,
        targetId = self.State.trackId,
        launchTime = timer.getTime(),
        phase = "BOOST",
        position = {x = self.position.x, y = self.position.y + 10, z = self.position.z},
        range = 0,
    }

    table.insert(self.State.activeMissiles, missile)
    self:setMode(self.RadarMode.ENGAGE)

    env.info(string.format("[SA-8] Missile launched at target %d", self.State.trackId))
    return true, "Missile launched"
end

function SA8_SAMSIM:updateMissiles(dt)
    local toRemove = {}

    for i, missile in ipairs(self.State.activeMissiles) do
        local flightTime = timer.getTime() - missile.launchTime

        -- Update phase
        if flightTime < 2 then
            missile.phase = "BOOST"
        elseif flightTime < 15 then
            missile.phase = "SUSTAIN"
        else
            missile.phase = "TERMINAL"
        end

        -- Find target contact
        local targetContact = nil
        for _, contact in ipairs(self.State.contacts) do
            if contact.id == missile.targetId then
                targetContact = contact
                break
            end
        end

        if targetContact then
            -- Simple missile flight simulation
            local speed = self.Config.missile.maxSpeed
            local dx = targetContact.position.x - missile.position.x
            local dy = targetContact.position.y - missile.position.y
            local dz = targetContact.position.z - missile.position.z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

            if dist > 0 then
                missile.position.x = missile.position.x + (dx/dist) * speed * dt
                missile.position.y = missile.position.y + (dy/dist) * speed * dt
                missile.position.z = missile.position.z + (dz/dist) * speed * dt
            end

            missile.range = dist

            -- Check intercept
            if dist < 15 then  -- 15m proximity
                -- Kill assessment
                local pk = self.State.firingSolution.pk
                if math.random() < pk then
                    env.info(string.format("[SA-8] Target %d DESTROYED", missile.targetId))
                    -- Could trigger actual destruction here
                else
                    env.info(string.format("[SA-8] Missile MISS on target %d", missile.targetId))
                end
                table.insert(toRemove, i)
                self.State.missilesInFlight = self.State.missilesInFlight - 1
            end
        else
            -- Target lost
            if flightTime > 20 then
                table.insert(toRemove, i)
                self.State.missilesInFlight = self.State.missilesInFlight - 1
                env.info("[SA-8] Missile self-destructed (target lost)")
            end
        end
    end

    -- Remove completed missiles
    for i = #toRemove, 1, -1 do
        table.remove(self.State.activeMissiles, toRemove[i])
    end
end

function SA8_SAMSIM:dropTrack()
    self.State.trackId = nil
    self.State.trackValid = false
    self.State.trackQuality = 0
    if self.State.mode > self.RadarMode.SEARCH then
        self:setMode(self.RadarMode.SEARCH)
    end
end

function SA8_SAMSIM:getState()
    return {
        systemType = "SA8",
        mode = self.State.mode,
        modeName = self.State.modeName,

        radar = {
            azimuth = self.State.radarAzimuth,
            elevation = self.State.radarElevation,
            searchAzimuth = self.State.searchAzimuth,
            mode = self.State.mode,
            modeName = self.State.modeName,
        },

        optical = {
            active = self.State.opticalActive,
            trackValid = self.State.opticalTrackValid,
        },

        track = {
            valid = self.State.trackValid,
            id = self.State.trackId,
            range = self.State.trackRange,
            azimuth = self.State.trackAzimuth,
            elevation = self.State.trackElevation,
            quality = self.State.trackQuality,
        },

        contacts = self.State.contacts,
        firingSolution = self.State.firingSolution,

        missiles = {
            ready = self.State.missilesReady,
            inFlight = self.State.missilesInFlight,
            active = self.State.activeMissiles,
        },
    }
end

function SA8_SAMSIM:handleCommand(cmd)
    if cmd.type == "POWER" then
        if cmd.state == "ON" then
            self:setMode(self.RadarMode.STANDBY)
        else
            self:setMode(self.RadarMode.OFF)
        end

    elseif cmd.type == "RADAR_MODE" then
        local modeMap = {
            OFF = 0, STANDBY = 1, SEARCH = 2,
            ACQUISITION = 3, TRACK = 4, ENGAGE = 5, OPTICAL = 6
        }
        local mode = modeMap[cmd.mode]
        if mode then self:setMode(mode) end

    elseif cmd.type == "DESIGNATE" then
        self:designateTarget(cmd.targetId)

    elseif cmd.type == "DROP_TRACK" then
        self:dropTrack()

    elseif cmd.type == "LAUNCH" then
        return self:launch()

    elseif cmd.type == "OPTICAL_MODE" then
        if cmd.enabled then
            self:setMode(self.RadarMode.OPTICAL)
        else
            self:setMode(self.RadarMode.TRACK)
        end
    end
end

env.info("[SAMSIM] SA-8 Gecko module loaded")
