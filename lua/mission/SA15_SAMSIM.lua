--[[
    SA-15 Gauntlet (9K330 Tor / Tor-M1) SAM System Simulation
    Modern short-range mobile SAM system

    Characteristics:
    - Fully autonomous operation
    - 3D pulse-doppler surveillance radar
    - Phased array tracking radar
    - 9M330/9M331 missiles (8 ready)
    - Effective range: 1-12 km
    - Altitude: 10m - 6000m
    - Can engage multiple targets simultaneously
]]

SA15_SAMSIM = {}

-- System configuration
SA15_SAMSIM.Config = {
    -- Surveillance Radar (top mounted)
    searchRadar = {
        range = 25000,            -- 25 km
        azimuth = 360,            -- Full rotation
        rotationRate = 60,        -- rpm (fast)
        beamWidth = 1.5,
        elevation = {-5, 64},     -- degrees
        frequency = 5500,         -- MHz (C-band)
        peakPower = 50,           -- kW
        prf = 10000,
        doppler = true,           -- Pulse-doppler for MTI
    },

    -- Tracking Radar (phased array)
    trackRadar = {
        range = 20000,            -- 20 km
        channels = 4,             -- Can track 4 targets
        scanRate = 0.1,           -- seconds between scans
        beamWidth = 1.0,
        electronicallyScanned = true,
    },

    -- 9M331 Missile
    missile = {
        name = "9M331",
        maxRange = 12000,         -- 12 km
        minRange = 1000,          -- 1 km
        maxAltitude = 6000,
        minAltitude = 10,
        maxSpeed = 850,           -- m/s (Mach 2.5)
        guidance = "CLOS_RADIO",
        warhead = 15,             -- kg
        fuze = "PROX_LASER",
        maxG = 30,                -- High maneuverability
    },

    -- Launcher
    launcher = {
        missiles = 8,             -- 8 missiles (2x4 in turret)
        reloadTime = 15,          -- 15 seconds between launches (same target)
        simultaneousTargets = 2,  -- Can engage 2 targets simultaneously
    },

    -- Reaction time
    reactionTime = 5,             -- 5-8 seconds (very fast)
}

-- Radar modes
SA15_SAMSIM.RadarMode = {
    OFF = 0,
    STANDBY = 1,
    SEARCH = 2,
    TRACK = 3,
    ENGAGE = 4,
    AUTO = 5,         -- Fully automatic engagement
}

-- Engagement channel
SA15_SAMSIM.Channel = {}
SA15_SAMSIM.Channel.__index = SA15_SAMSIM.Channel

function SA15_SAMSIM.Channel:new(id)
    local ch = setmetatable({}, self)
    ch.id = id
    ch.targetId = nil
    ch.trackValid = false
    ch.trackRange = 0
    ch.trackAzimuth = 0
    ch.trackElevation = 0
    ch.trackQuality = 0
    ch.missileAssigned = nil
    ch.mode = 0  -- 0=idle, 1=track, 2=engage
    return ch
end

-- System state
SA15_SAMSIM.State = {
    mode = 0,
    modeName = "OFF",
    autoMode = false,

    -- Search radar state
    searchAzimuth = 0,

    -- Tracking channels
    channels = {},

    -- Missiles
    missilesReady = 8,
    missilesInFlight = 0,
    activeMissiles = {},

    -- Detected contacts
    contacts = {},

    -- Threat queue (auto mode)
    threatQueue = {},
}

-- Mode names
SA15_SAMSIM.ModeNames = {
    [0] = "OFF",
    [1] = "STANDBY",
    [2] = "SEARCH",
    [3] = "TRACK",
    [4] = "ENGAGE",
    [5] = "AUTO",
}

function SA15_SAMSIM:initialize(groupName)
    self.groupName = groupName
    self.group = Group.getByName(groupName)
    self.position = self:getPosition()
    self.State.missilesReady = self.Config.launcher.missiles

    -- Initialize tracking channels
    self.State.channels = {}
    for i = 1, self.Config.trackRadar.channels do
        self.State.channels[i] = SA15_SAMSIM.Channel:new(i)
    end

    env.info(string.format("[SA-15] Initialized: %s", groupName))
    return self
end

function SA15_SAMSIM:getPosition()
    if self.group then
        local units = self.group:getUnits()
        if units and units[1] then
            return units[1]:getPoint()
        end
    end
    return {x = 0, y = 0, z = 0}
end

function SA15_SAMSIM:setMode(mode)
    if mode < 0 or mode > 5 then return end

    local oldMode = self.State.mode
    self.State.mode = mode
    self.State.modeName = self.ModeNames[mode]

    if mode == self.RadarMode.OFF then
        for _, ch in ipairs(self.State.channels) do
            ch.targetId = nil
            ch.trackValid = false
            ch.mode = 0
        end
    end

    self.State.autoMode = (mode == self.RadarMode.AUTO)

    env.info(string.format("[SA-15] Mode changed: %s -> %s",
        self.ModeNames[oldMode], self.ModeNames[mode]))
end

function SA15_SAMSIM:update(dt)
    if self.State.mode == self.RadarMode.OFF then
        return
    end

    self.position = self:getPosition()

    -- Update search radar rotation
    if self.State.mode >= self.RadarMode.SEARCH then
        self.State.searchAzimuth = (self.State.searchAzimuth + self.Config.searchRadar.rotationRate * 6 * dt) % 360
    end

    -- Scan for contacts
    if self.State.mode >= self.RadarMode.SEARCH then
        self:scanForTargets()
    end

    -- Update tracking channels
    for _, channel in ipairs(self.State.channels) do
        if channel.targetId then
            self:updateChannelTrack(channel)
        end
    end

    -- Auto mode processing
    if self.State.autoMode then
        self:processAutoMode()
    end

    -- Update missiles
    self:updateMissiles(dt)
end

function SA15_SAMSIM:scanForTargets()
    local detected = {}
    local searchRange = self.Config.searchRadar.range

    local volS = {
        id = world.VolumeType.SPHERE,
        params = {point = self.position, radius = searchRange}
    }

    local foundUnits = {}
    world.searchObjects(Object.Category.UNIT, volS, function(foundItem)
        local desc = foundItem:getDesc()
        if desc.category == Unit.Category.AIRPLANE or
           desc.category == Unit.Category.HELICOPTER then
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

    -- Sort by threat level (range and heading)
    table.sort(detected, function(a, b)
        return a.range < b.range
    end)

    self.State.contacts = detected

    -- Update threat queue for auto mode
    if self.State.autoMode then
        self:updateThreatQueue()
    end
end

function SA15_SAMSIM:processContact(unit, unitPos)
    local dx = unitPos.x - self.position.x
    local dy = unitPos.y - self.position.y
    local dz = unitPos.z - self.position.z

    local horizontalRange = math.sqrt(dx*dx + dz*dz)
    local slantRange = math.sqrt(dx*dx + dy*dy + dz*dz)
    local azimuth = math.deg(math.atan2(dx, dz))
    if azimuth < 0 then azimuth = azimuth + 360 end
    local elevation = math.deg(math.atan2(dy, horizontalRange))

    -- Range check
    if slantRange > self.Config.searchRadar.range then
        return nil
    end

    -- Velocity for doppler filtering
    local velocity = unit:getVelocity()
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    local heading = math.deg(math.atan2(velocity.x, velocity.z))
    if heading < 0 then heading = heading + 360 end

    -- Altitude check
    local altitude = unitPos.y - self.position.y
    if altitude < self.Config.missile.minAltitude then
        return nil
    end

    -- Radial velocity for MTI
    local radialVelocity = (velocity.x * dx + velocity.y * dy + velocity.z * dz) / slantRange

    -- MTI filtering - reject slow moving targets (clutter)
    if self.Config.searchRadar.doppler then
        if math.abs(radialVelocity) < 20 then  -- 20 m/s minimum
            -- Target may be filtered by MTI
            if math.random() < 0.3 then
                return nil
            end
        end
    end

    -- RCS and detection
    local rcs = self:estimateRCS(unit)
    local detectionProb = 0.95 * (1 - (slantRange / self.Config.searchRadar.range)^2)
    detectionProb = detectionProb * math.min(1, rcs / 3)

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
        radialVelocity = radialVelocity,
        rcs = rcs,
        threatLevel = self:assessThreat(slantRange, altitude, speed, heading),
    }
end

function SA15_SAMSIM:estimateRCS(unit)
    local typeName = unit:getTypeName():lower()

    if typeName:find("cruise") or typeName:find("agm") then
        return 0.1
    elseif typeName:find("uav") or typeName:find("drone") then
        return 0.3
    elseif typeName:find("f%-22") or typeName:find("f%-35") then
        return 0.5
    elseif typeName:find("f%-16") or typeName:find("mig%-29") then
        return 3
    elseif typeName:find("heli") then
        return 5
    else
        return 5
    end
end

function SA15_SAMSIM:assessThreat(range, altitude, speed, heading)
    local threat = 50

    -- Range factor (closer = higher threat)
    threat = threat + (1 - range / self.Config.searchRadar.range) * 30

    -- Speed factor
    if speed > 300 then
        threat = threat + 10
    end

    -- Low altitude = higher threat
    if altitude < 500 then
        threat = threat + 15
    end

    return math.min(100, threat)
end

function SA15_SAMSIM:updateThreatQueue()
    self.State.threatQueue = {}

    for _, contact in ipairs(self.State.contacts) do
        -- Check if already being engaged
        local beingEngaged = false
        for _, ch in ipairs(self.State.channels) do
            if ch.targetId == contact.id then
                beingEngaged = true
                break
            end
        end

        if not beingEngaged then
            table.insert(self.State.threatQueue, contact)
        end
    end

    -- Sort by threat level
    table.sort(self.State.threatQueue, function(a, b)
        return a.threatLevel > b.threatLevel
    end)
end

function SA15_SAMSIM:processAutoMode()
    -- Assign targets to free channels
    for _, channel in ipairs(self.State.channels) do
        if channel.mode == 0 and #self.State.threatQueue > 0 then
            local target = table.remove(self.State.threatQueue, 1)
            self:assignTargetToChannel(channel, target.id)
        end

        -- Auto-launch if tracking
        if channel.mode >= 1 and channel.trackValid and channel.trackQuality > 0.7 then
            local solution = self:calculateChannelSolution(channel)
            if solution.valid and solution.pk > 0.5 then
                if not channel.missileAssigned then
                    self:launchAtChannel(channel.id)
                end
            end
        end
    end
end

function SA15_SAMSIM:assignTargetToChannel(channel, targetId)
    channel.targetId = targetId
    channel.mode = 1  -- Track mode
    env.info(string.format("[SA-15] Channel %d assigned to target %d", channel.id, targetId))
end

function SA15_SAMSIM:updateChannelTrack(channel)
    local contact = nil
    for _, c in ipairs(self.State.contacts) do
        if c.id == channel.targetId then
            contact = c
            break
        end
    end

    if contact then
        channel.trackValid = true
        channel.trackRange = contact.range
        channel.trackAzimuth = contact.azimuth
        channel.trackElevation = contact.elevation
        channel.trackQuality = 0.9 * (1 - contact.range / self.Config.trackRadar.range * 0.3)
    else
        channel.trackValid = false
        channel.trackQuality = 0

        -- Release channel if target lost
        if channel.mode < 2 then
            channel.targetId = nil
            channel.mode = 0
        end
    end
end

function SA15_SAMSIM:calculateChannelSolution(channel)
    if not channel.trackValid then
        return {valid = false}
    end

    local range = channel.trackRange
    local contact = nil
    for _, c in ipairs(self.State.contacts) do
        if c.id == channel.targetId then
            contact = c
            break
        end
    end

    if not contact then
        return {valid = false}
    end

    local inRangeMax = range <= self.Config.missile.maxRange
    local inRangeMin = range >= self.Config.missile.minRange
    local inAltMax = contact.altitude <= self.Config.missile.maxAltitude
    local inAltMin = contact.altitude >= self.Config.missile.minAltitude
    local inEnvelope = inRangeMax and inRangeMin and inAltMax and inAltMin

    local pk = 0
    if inEnvelope then
        pk = 0.92 * (1 - range / self.Config.missile.maxRange * 0.2)
        pk = pk * channel.trackQuality

        -- High-G capability helps against maneuvering targets
        if contact.speed > 400 then
            pk = pk * 0.85
        end
    end

    return {
        valid = inEnvelope and channel.trackQuality > 0.6,
        inEnvelope = inEnvelope,
        pk = pk,
        timeToIntercept = range / self.Config.missile.maxSpeed,
    }
end

function SA15_SAMSIM:designateTarget(targetId, channelId)
    local channel = self.State.channels[channelId or 1]
    if not channel then return false end

    for _, contact in ipairs(self.State.contacts) do
        if contact.id == targetId then
            self:assignTargetToChannel(channel, targetId)
            return true
        end
    end
    return false
end

function SA15_SAMSIM:launchAtChannel(channelId)
    local channel = self.State.channels[channelId]
    if not channel or not channel.trackValid then
        return false, "Invalid channel or no track"
    end

    if self.State.missilesReady <= 0 then
        return false, "No missiles available"
    end

    local solution = self:calculateChannelSolution(channel)
    if not solution.valid then
        return false, "No valid solution"
    end

    -- Launch missile
    self.State.missilesReady = self.State.missilesReady - 1
    self.State.missilesInFlight = self.State.missilesInFlight + 1

    local missile = {
        id = #self.State.activeMissiles + 1,
        channelId = channelId,
        targetId = channel.targetId,
        launchTime = timer.getTime(),
        phase = "BOOST",
        position = {x = self.position.x, y = self.position.y + 5, z = self.position.z},
        range = 0,
    }

    table.insert(self.State.activeMissiles, missile)
    channel.missileAssigned = missile.id
    channel.mode = 2  -- Engage mode

    env.info(string.format("[SA-15] Missile launched from channel %d at target %d",
        channelId, channel.targetId))
    return true
end

function SA15_SAMSIM:updateMissiles(dt)
    local toRemove = {}

    for i, missile in ipairs(self.State.activeMissiles) do
        local flightTime = timer.getTime() - missile.launchTime

        -- Phase update
        if flightTime < 1.5 then
            missile.phase = "BOOST"
        elseif flightTime < 12 then
            missile.phase = "SUSTAIN"
        else
            missile.phase = "TERMINAL"
        end

        -- Find target
        local targetContact = nil
        for _, contact in ipairs(self.State.contacts) do
            if contact.id == missile.targetId then
                targetContact = contact
                break
            end
        end

        if targetContact then
            local speed = self.Config.missile.maxSpeed
            local dx = targetContact.position.x - missile.position.x
            local dy = targetContact.position.y - missile.position.y
            local dz = targetContact.position.z - missile.position.z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

            if dist > 0 then
                -- Proportional navigation
                missile.position.x = missile.position.x + (dx/dist) * speed * dt
                missile.position.y = missile.position.y + (dy/dist) * speed * dt
                missile.position.z = missile.position.z + (dz/dist) * speed * dt
            end

            missile.range = dist

            -- Intercept check
            if dist < 10 then
                local channel = self.State.channels[missile.channelId]
                local solution = self:calculateChannelSolution(channel)

                if math.random() < (solution.pk or 0.8) then
                    env.info(string.format("[SA-15] Target %d DESTROYED", missile.targetId))
                else
                    env.info(string.format("[SA-15] Missile MISS on target %d", missile.targetId))
                end

                table.insert(toRemove, i)
                self.State.missilesInFlight = self.State.missilesInFlight - 1

                -- Release channel
                if channel then
                    channel.missileAssigned = nil
                    channel.targetId = nil
                    channel.mode = 0
                end
            end
        else
            if flightTime > 15 then
                table.insert(toRemove, i)
                self.State.missilesInFlight = self.State.missilesInFlight - 1
                env.info("[SA-15] Missile self-destructed")

                local channel = self.State.channels[missile.channelId]
                if channel then
                    channel.missileAssigned = nil
                    channel.targetId = nil
                    channel.mode = 0
                end
            end
        end
    end

    for i = #toRemove, 1, -1 do
        table.remove(self.State.activeMissiles, toRemove[i])
    end
end

function SA15_SAMSIM:dropTrack(channelId)
    local channel = self.State.channels[channelId or 1]
    if channel then
        channel.targetId = nil
        channel.trackValid = false
        channel.mode = 0
    end
end

function SA15_SAMSIM:getState()
    local channelStates = {}
    for _, ch in ipairs(self.State.channels) do
        table.insert(channelStates, {
            id = ch.id,
            targetId = ch.targetId,
            trackValid = ch.trackValid,
            trackRange = ch.trackRange,
            trackAzimuth = ch.trackAzimuth,
            trackQuality = ch.trackQuality,
            mode = ch.mode,
            missileAssigned = ch.missileAssigned,
        })
    end

    return {
        systemType = "SA15",
        mode = self.State.mode,
        modeName = self.State.modeName,
        autoMode = self.State.autoMode,

        searchRadar = {
            azimuth = self.State.searchAzimuth,
            mode = self.State.mode >= self.RadarMode.SEARCH and "ACTIVE" or "OFF",
        },

        channels = channelStates,
        contacts = self.State.contacts,

        missiles = {
            ready = self.State.missilesReady,
            inFlight = self.State.missilesInFlight,
            active = self.State.activeMissiles,
        },
    }
end

function SA15_SAMSIM:handleCommand(cmd)
    if cmd.type == "POWER" then
        if cmd.state == "ON" then
            self:setMode(self.RadarMode.STANDBY)
        else
            self:setMode(self.RadarMode.OFF)
        end

    elseif cmd.type == "RADAR_MODE" then
        local modeMap = {
            OFF = 0, STANDBY = 1, SEARCH = 2, TRACK = 3, ENGAGE = 4, AUTO = 5
        }
        local mode = modeMap[cmd.mode]
        if mode then self:setMode(mode) end

    elseif cmd.type == "AUTO_MODE" then
        self:setMode(cmd.enabled and self.RadarMode.AUTO or self.RadarMode.SEARCH)

    elseif cmd.type == "DESIGNATE" then
        self:designateTarget(cmd.targetId, cmd.channel)

    elseif cmd.type == "DROP_TRACK" then
        self:dropTrack(cmd.channel)

    elseif cmd.type == "LAUNCH" then
        return self:launchAtChannel(cmd.channel or 1)
    end
end

env.info("[SAMSIM] SA-15 Gauntlet module loaded")
