--[[
    SA-19 Grison (2K22 Tunguska) SPAAGM System Simulation
    Combined gun/missile air defense system

    Characteristics:
    - Dual 30mm 2A38M autocannons (5000 rpm combined)
    - 9M311 missiles (8 ready)
    - Hot Shot radar (search + track)
    - Optical tracking system
    - Can engage with guns, missiles, or both
]]

SA19_SAMSIM = {}

-- System configuration
SA19_SAMSIM.Config = {
    -- Hot Shot Radar (1RL144)
    radar = {
        searchRange = 18000,      -- 18 km
        trackRange = 13000,       -- 13 km
        searchAzimuth = 360,
        rotationRate = 60,        -- rpm
        beamWidth = 2.0,
        frequency = 15000,        -- Ku-band
        peakPower = 20,           -- kW
    },

    -- Optical Tracking System
    optical = {
        fov = 2,
        maxRange = 8000,          -- 8 km
        tracking = true,
    },

    -- 2A38M 30mm Autocannon (x2)
    gun = {
        caliber = 30,             -- mm
        rateOfFire = 2500,        -- per gun
        muzzleVelocity = 960,     -- m/s
        maxRange = 4000,          -- 4 km effective
        maxAltitude = 3000,       -- 3 km
        magazineSize = 500,       -- per gun
        burstSize = 50,           -- rounds per burst
    },

    -- 9M311 Missile
    missile = {
        name = "9M311",
        maxRange = 8000,          -- 8 km
        minRange = 1500,          -- 1.5 km
        maxAltitude = 3500,
        minAltitude = 15,
        maxSpeed = 900,           -- m/s
        guidance = "CLOS_RADIO",
        warhead = 9,              -- kg
        fuze = "PROX_LASER",
    },

    -- Launcher
    launcher = {
        missiles = 8,             -- 4 per side
        reloadTime = 5,           -- quick reload for next launch
    },

    -- Reaction time
    reactionTime = 6,             -- seconds
}

-- Weapon modes
SA19_SAMSIM.WeaponMode = {
    SAFE = 0,
    MISSILE_ONLY = 1,
    GUN_ONLY = 2,
    COMBINED = 3,                 -- Missile first, gun for close-in
    AUTO = 4,                     -- Automatic weapon selection
}

-- Radar modes
SA19_SAMSIM.RadarMode = {
    OFF = 0,
    STANDBY = 1,
    SEARCH = 2,
    TRACK = 3,
    ENGAGE = 4,
    OPTICAL = 5,                  -- Passive optical tracking
}

-- System state
SA19_SAMSIM.State = {
    mode = 0,
    modeName = "OFF",
    weaponMode = 0,
    weaponModeName = "SAFE",

    -- Radar state
    radarAzimuth = 0,
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

    -- Gun state
    gunRoundsLeft = 1000,         -- 500 per gun
    gunBurstActive = false,
    gunElevation = 0,
    gunAzimuth = 0,

    -- Missiles
    missilesReady = 8,
    missilesInFlight = 0,
    activeMissiles = {},

    -- Detected contacts
    contacts = {},

    -- Fire control
    firingSolution = {
        valid = false,
        inMissileEnvelope = false,
        inGunEnvelope = false,
        pk = 0,
        timeToIntercept = 0,
        recommendedWeapon = "NONE",
    },
}

-- Mode names
SA19_SAMSIM.ModeNames = {
    [0] = "OFF",
    [1] = "STANDBY",
    [2] = "SEARCH",
    [3] = "TRACK",
    [4] = "ENGAGE",
    [5] = "OPTICAL",
}

SA19_SAMSIM.WeaponModeNames = {
    [0] = "SAFE",
    [1] = "MISSILE",
    [2] = "GUN",
    [3] = "COMBINED",
    [4] = "AUTO",
}

function SA19_SAMSIM:initialize(groupName)
    self.groupName = groupName
    self.group = Group.getByName(groupName)
    self.position = self:getPosition()
    self.State.missilesReady = self.Config.launcher.missiles
    self.State.gunRoundsLeft = self.Config.gun.magazineSize * 2

    env.info(string.format("[SA-19] Initialized: %s", groupName))
    return self
end

function SA19_SAMSIM:getPosition()
    if self.group then
        local units = self.group:getUnits()
        if units and units[1] then
            return units[1]:getPoint()
        end
    end
    return {x = 0, y = 0, z = 0}
end

function SA19_SAMSIM:setMode(mode)
    if mode < 0 or mode > 5 then return end

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

    env.info(string.format("[SA-19] Mode changed: %s -> %s",
        self.ModeNames[oldMode], self.ModeNames[mode]))
end

function SA19_SAMSIM:setWeaponMode(mode)
    if mode < 0 or mode > 4 then return end

    self.State.weaponMode = mode
    self.State.weaponModeName = self.WeaponModeNames[mode]
    env.info(string.format("[SA-19] Weapon mode: %s", self.WeaponModeNames[mode]))
end

function SA19_SAMSIM:update(dt)
    if self.State.mode == self.RadarMode.OFF then
        return
    end

    self.position = self:getPosition()

    -- Update search radar
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

    -- Calculate firing solution
    if self.State.trackValid then
        self:calculateFiringSolution()
    end

    -- Update gun burst
    if self.State.gunBurstActive then
        self:updateGunBurst(dt)
    end

    -- Update missiles
    self:updateMissiles(dt)
end

function SA19_SAMSIM:scanForTargets()
    local detected = {}
    local searchRange = self.Config.radar.searchRange

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

    self.State.contacts = detected
end

function SA19_SAMSIM:processContact(unit, unitPos)
    local dx = unitPos.x - self.position.x
    local dy = unitPos.y - self.position.y
    local dz = unitPos.z - self.position.z

    local horizontalRange = math.sqrt(dx*dx + dz*dz)
    local slantRange = math.sqrt(dx*dx + dy*dy + dz*dz)
    local azimuth = math.deg(math.atan2(dx, dz))
    if azimuth < 0 then azimuth = azimuth + 360 end
    local elevation = math.deg(math.atan2(dy, horizontalRange))

    if slantRange > self.Config.radar.searchRange then
        return nil
    end

    local velocity = unit:getVelocity()
    local speed = math.sqrt(velocity.x^2 + velocity.y^2 + velocity.z^2)
    local heading = math.deg(math.atan2(velocity.x, velocity.z))
    if heading < 0 then heading = heading + 360 end

    local altitude = unitPos.y - self.position.y

    -- RCS estimation
    local rcs = self:estimateRCS(unit)
    local detectionProb = 0.95 * (1 - (slantRange / self.Config.radar.searchRange)^2)

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

function SA19_SAMSIM:estimateRCS(unit)
    local typeName = unit:getTypeName():lower()

    if typeName:find("heli") then
        return 8
    elseif typeName:find("cruise") or typeName:find("agm") then
        return 0.1
    elseif typeName:find("uav") then
        return 0.5
    else
        return 5
    end
end

function SA19_SAMSIM:updateTrack()
    local contact = nil
    for _, c in ipairs(self.State.contacts) do
        if c.id == self.State.trackId then
            contact = c
            break
        end
    end

    if contact then
        self.State.trackValid = true
        self.State.trackRange = contact.range
        self.State.trackAzimuth = contact.azimuth
        self.State.trackElevation = contact.elevation

        self.State.radarAzimuth = contact.azimuth

        local rangeNorm = contact.range / self.Config.radar.trackRange
        self.State.trackQuality = math.max(0, 1 - rangeNorm * 0.4)

        -- Point guns at target
        self.State.gunAzimuth = contact.azimuth
        self.State.gunElevation = contact.elevation
    else
        self.State.trackValid = false
        self.State.trackQuality = 0
    end
end

function SA19_SAMSIM:updateOpticalTrack()
    for _, contact in ipairs(self.State.contacts) do
        if contact.id == self.State.trackId then
            if contact.range <= self.Config.optical.maxRange then
                self.State.opticalTrackValid = true
                self.State.trackValid = true
                self.State.trackRange = contact.range
                self.State.trackAzimuth = contact.azimuth
                self.State.trackElevation = contact.elevation
                self.State.trackQuality = 0.8
                return
            end
        end
    end
    self.State.opticalTrackValid = false
end

function SA19_SAMSIM:calculateFiringSolution()
    if not self.State.trackValid then
        self.State.firingSolution.valid = false
        return
    end

    local range = self.State.trackRange
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

    -- Missile envelope check
    local inMissileRangeMax = range <= self.Config.missile.maxRange
    local inMissileRangeMin = range >= self.Config.missile.minRange
    local inMissileAltMax = contact.altitude <= self.Config.missile.maxAltitude
    local inMissileAltMin = contact.altitude >= self.Config.missile.minAltitude
    local inMissileEnvelope = inMissileRangeMax and inMissileRangeMin and
                              inMissileAltMax and inMissileAltMin

    -- Gun envelope check
    local inGunRange = range <= self.Config.gun.maxRange
    local inGunAlt = contact.altitude <= self.Config.gun.maxAltitude
    local inGunEnvelope = inGunRange and inGunAlt

    -- Calculate Pk for each weapon
    local missilePk = 0
    if inMissileEnvelope then
        missilePk = 0.65 * (1 - range / self.Config.missile.maxRange * 0.3)
        missilePk = missilePk * self.State.trackQuality
    end

    local gunPk = 0
    if inGunEnvelope then
        gunPk = 0.4 * (1 - range / self.Config.gun.maxRange * 0.5)
        -- Gun is better against slow/hovering targets
        if contact.speed < 100 then
            gunPk = gunPk * 1.3
        end
        gunPk = gunPk * self.State.trackQuality
    end

    -- Recommended weapon
    local recommendedWeapon = "NONE"
    local bestPk = 0

    if self.State.weaponMode == self.WeaponMode.MISSILE_ONLY then
        if inMissileEnvelope then
            recommendedWeapon = "MISSILE"
            bestPk = missilePk
        end
    elseif self.State.weaponMode == self.WeaponMode.GUN_ONLY then
        if inGunEnvelope then
            recommendedWeapon = "GUN"
            bestPk = gunPk
        end
    elseif self.State.weaponMode == self.WeaponMode.COMBINED or
           self.State.weaponMode == self.WeaponMode.AUTO then
        -- Prefer missile at range, gun close-in
        if range > self.Config.gun.maxRange and inMissileEnvelope then
            recommendedWeapon = "MISSILE"
            bestPk = missilePk
        elseif inGunEnvelope then
            -- Use gun when close, unless missile has much better Pk
            if gunPk > missilePk * 0.7 or range < 2000 then
                recommendedWeapon = "GUN"
                bestPk = gunPk
            elseif inMissileEnvelope then
                recommendedWeapon = "MISSILE"
                bestPk = missilePk
            end
        elseif inMissileEnvelope then
            recommendedWeapon = "MISSILE"
            bestPk = missilePk
        end
    end

    self.State.firingSolution = {
        valid = (inMissileEnvelope or inGunEnvelope) and self.State.trackQuality > 0.5,
        inMissileEnvelope = inMissileEnvelope,
        inGunEnvelope = inGunEnvelope,
        missilePk = missilePk,
        gunPk = gunPk,
        pk = bestPk,
        timeToIntercept = range / self.Config.missile.maxSpeed,
        recommendedWeapon = recommendedWeapon,
    }
end

function SA19_SAMSIM:designateTarget(targetId)
    for _, contact in ipairs(self.State.contacts) do
        if contact.id == targetId then
            self.State.trackId = targetId
            self:setMode(self.RadarMode.TRACK)
            env.info(string.format("[SA-19] Target designated: %d", targetId))
            return true
        end
    end
    return false
end

function SA19_SAMSIM:launchMissile()
    if not self.State.firingSolution.valid then
        return false, "No valid firing solution"
    end

    if not self.State.firingSolution.inMissileEnvelope then
        return false, "Target not in missile envelope"
    end

    if self.State.missilesReady <= 0 then
        return false, "No missiles available"
    end

    if self.State.missilesInFlight >= 2 then
        return false, "Maximum missiles in flight"
    end

    self.State.missilesReady = self.State.missilesReady - 1
    self.State.missilesInFlight = self.State.missilesInFlight + 1

    local missile = {
        id = #self.State.activeMissiles + 1,
        targetId = self.State.trackId,
        launchTime = timer.getTime(),
        phase = "BOOST",
        position = {x = self.position.x, y = self.position.y + 3, z = self.position.z},
        range = 0,
    }

    table.insert(self.State.activeMissiles, missile)
    self:setMode(self.RadarMode.ENGAGE)

    env.info(string.format("[SA-19] Missile launched at target %d", self.State.trackId))
    return true
end

function SA19_SAMSIM:fireGunBurst()
    if not self.State.firingSolution.valid then
        return false, "No valid firing solution"
    end

    if not self.State.firingSolution.inGunEnvelope then
        return false, "Target not in gun envelope"
    end

    if self.State.gunRoundsLeft < self.Config.gun.burstSize then
        return false, "Insufficient ammunition"
    end

    if self.State.gunBurstActive then
        return false, "Burst already in progress"
    end

    self.State.gunBurstActive = true
    self.State.gunBurstRoundsRemaining = self.Config.gun.burstSize
    self:setMode(self.RadarMode.ENGAGE)

    env.info(string.format("[SA-19] Gun burst at target %d", self.State.trackId))
    return true
end

function SA19_SAMSIM:updateGunBurst(dt)
    if not self.State.gunBurstActive then return end

    local roundsPerSecond = (self.Config.gun.rateOfFire * 2) / 60
    local roundsThisFrame = roundsPerSecond * dt

    self.State.gunBurstRoundsRemaining = self.State.gunBurstRoundsRemaining - roundsThisFrame
    self.State.gunRoundsLeft = self.State.gunRoundsLeft - roundsThisFrame

    if self.State.gunBurstRoundsRemaining <= 0 or self.State.gunRoundsLeft <= 0 then
        self.State.gunBurstActive = false

        -- Assess hit probability
        if self.State.trackValid then
            local hitProb = self.State.firingSolution.gunPk
            if math.random() < hitProb then
                env.info(string.format("[SA-19] Gun burst HIT on target %d", self.State.trackId))
            else
                env.info(string.format("[SA-19] Gun burst MISS on target %d", self.State.trackId))
            end
        end
    end
end

function SA19_SAMSIM:updateMissiles(dt)
    local toRemove = {}

    for i, missile in ipairs(self.State.activeMissiles) do
        local flightTime = timer.getTime() - missile.launchTime

        if flightTime < 1 then
            missile.phase = "BOOST"
        elseif flightTime < 8 then
            missile.phase = "SUSTAIN"
        else
            missile.phase = "TERMINAL"
        end

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
                missile.position.x = missile.position.x + (dx/dist) * speed * dt
                missile.position.y = missile.position.y + (dy/dist) * speed * dt
                missile.position.z = missile.position.z + (dz/dist) * speed * dt
            end

            missile.range = dist

            if dist < 12 then
                local pk = self.State.firingSolution.missilePk or 0.65
                if math.random() < pk then
                    env.info(string.format("[SA-19] Missile HIT on target %d", missile.targetId))
                else
                    env.info(string.format("[SA-19] Missile MISS on target %d", missile.targetId))
                end
                table.insert(toRemove, i)
                self.State.missilesInFlight = self.State.missilesInFlight - 1
            end
        else
            if flightTime > 10 then
                table.insert(toRemove, i)
                self.State.missilesInFlight = self.State.missilesInFlight - 1
                env.info("[SA-19] Missile self-destructed")
            end
        end
    end

    for i = #toRemove, 1, -1 do
        table.remove(self.State.activeMissiles, toRemove[i])
    end
end

function SA19_SAMSIM:dropTrack()
    self.State.trackId = nil
    self.State.trackValid = false
    self.State.trackQuality = 0
    self.State.gunBurstActive = false
    if self.State.mode > self.RadarMode.SEARCH then
        self:setMode(self.RadarMode.SEARCH)
    end
end

function SA19_SAMSIM:getState()
    return {
        systemType = "SA19",
        mode = self.State.mode,
        modeName = self.State.modeName,
        weaponMode = self.State.weaponMode,
        weaponModeName = self.State.weaponModeName,

        radar = {
            azimuth = self.State.radarAzimuth,
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

        gun = {
            roundsLeft = math.floor(self.State.gunRoundsLeft),
            burstActive = self.State.gunBurstActive,
            azimuth = self.State.gunAzimuth,
            elevation = self.State.gunElevation,
        },

        missiles = {
            ready = self.State.missilesReady,
            inFlight = self.State.missilesInFlight,
            active = self.State.activeMissiles,
        },

        contacts = self.State.contacts,
        firingSolution = self.State.firingSolution,
    }
end

function SA19_SAMSIM:handleCommand(cmd)
    if cmd.type == "POWER" then
        if cmd.state == "ON" then
            self:setMode(self.RadarMode.STANDBY)
        else
            self:setMode(self.RadarMode.OFF)
        end

    elseif cmd.type == "RADAR_MODE" then
        local modeMap = {
            OFF = 0, STANDBY = 1, SEARCH = 2, TRACK = 3, ENGAGE = 4, OPTICAL = 5
        }
        local mode = modeMap[cmd.mode]
        if mode then self:setMode(mode) end

    elseif cmd.type == "WEAPON_MODE" then
        local modeMap = {
            SAFE = 0, MISSILE = 1, GUN = 2, COMBINED = 3, AUTO = 4
        }
        local mode = modeMap[cmd.mode]
        if mode then self:setWeaponMode(mode) end

    elseif cmd.type == "DESIGNATE" then
        self:designateTarget(cmd.targetId)

    elseif cmd.type == "DROP_TRACK" then
        self:dropTrack()

    elseif cmd.type == "LAUNCH" then
        return self:launchMissile()

    elseif cmd.type == "FIRE_GUN" then
        return self:fireGunBurst()

    elseif cmd.type == "OPTICAL_MODE" then
        if cmd.enabled then
            self:setMode(self.RadarMode.OPTICAL)
        else
            self:setMode(self.RadarMode.TRACK)
        end
    end
end

env.info("[SAMSIM] SA-19 Grison module loaded")
