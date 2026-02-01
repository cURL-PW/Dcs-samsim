--[[
    SA-2 (S-75 Dvina) SAMSIM Controller
    DCS World Mission Script

    This script provides SAMSim-like control for SA-2 systems in DCS World.
    It manages radar states, target tracking, and missile engagement.
]]

-- Initialize SAMSIM namespace
SAMSIM = SAMSIM or {}

-- Configuration
SAMSIM.Config = {
    -- Communication settings
    UDP_SEND_PORT = 7777,      -- Port to send data to external server
    UDP_RECV_PORT = 7778,      -- Port to receive commands from external server
    UPDATE_INTERVAL = 0.1,     -- Update interval in seconds (10 Hz)

    -- SA-2 System Parameters (based on real S-75 specifications)
    RADAR_MAX_RANGE = 160000,  -- 160 km max detection range
    RADAR_MIN_RANGE = 7000,    -- 7 km minimum engagement range
    RADAR_MAX_ALT = 30000,     -- 30 km max altitude
    RADAR_MIN_ALT = 500,       -- 500 m min altitude
    MISSILE_MAX_RANGE = 45000, -- 45 km max engagement range
    MISSILE_MIN_RANGE = 7000,  -- 7 km min engagement range
    ANTENNA_ROTATION_SPEED = 6, -- degrees per second
    TRACK_SCAN_WIDTH = 10,     -- degrees scan width in track mode

    -- Missile specifications (V-750VK)
    MISSILE_MAX_SPEED = 1200,  -- m/s
    MISSILE_FLIGHT_TIME = 60,  -- max flight time seconds
    MISSILE_GUIDANCE_DELAY = 2, -- seconds before guidance active
}

-- SA-2 Site State
SAMSIM.Sites = {}

-- Radar modes
SAMSIM.RadarMode = {
    STANDBY = 0,
    SEARCH = 1,
    TRACK = 2,
    GUIDE = 3,
}

-- System state
SAMSIM.SystemState = {
    OFFLINE = 0,
    STARTUP = 1,
    READY = 2,
    ENGAGED = 3,
    COOLDOWN = 4,
}

--[[
    Initialize an SA-2 site
    @param groupName: Name of the SA-2 group in mission editor
    @param siteId: Unique identifier for this site
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

        -- Radar state
        radarMode = SAMSIM.RadarMode.STANDBY,
        systemState = SAMSIM.SystemState.OFFLINE,

        -- Antenna position
        antennaAzimuth = 0,      -- Current azimuth (degrees)
        antennaElevation = 5,    -- Current elevation (degrees)
        targetAzimuth = 0,       -- Target azimuth for antenna
        targetElevation = 5,     -- Target elevation for antenna

        -- Tracking
        trackedTarget = nil,     -- Currently tracked target
        trackedTargetId = nil,
        trackQuality = 0,        -- 0-100 track quality

        -- Detection
        detectedTargets = {},    -- List of detected targets

        -- Missiles
        missilesReady = 6,       -- Available missiles (typical 6 per battery)
        missilesInFlight = {},   -- Missiles currently in flight
        lastLaunchTime = 0,

        -- Position
        position = nil,

        -- Engagement
        engagementAuthorized = false,
        autoEngage = false,
    }

    -- Get site position from tracking radar unit
    local units = group:getUnits()
    for _, unit in pairs(units) do
        local unitType = unit:getTypeName()
        -- Find the Fan Song tracking radar (SNR-75)
        if string.find(unitType, "SNR") or string.find(unitType, "p-19") or string.find(unitType, "RPC") then
            site.position = unit:getPoint()
            site.trackingRadar = unit
            break
        end
    end

    if not site.position then
        -- Fallback to first unit
        site.position = units[1]:getPoint()
        site.trackingRadar = units[1]
    end

    SAMSIM.Sites[siteId] = site
    env.info("SAMSIM: Initialized SA-2 site: " .. siteId)

    return site
end

--[[
    Set radar mode for a site
]]
function SAMSIM.SetRadarMode(siteId, mode)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    local oldMode = site.radarMode
    site.radarMode = mode

    if mode == SAMSIM.RadarMode.STANDBY then
        site.trackedTarget = nil
        site.trackedTargetId = nil
        site.trackQuality = 0
        -- Order group to hold fire
        site.group:getController():setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
    elseif mode == SAMSIM.RadarMode.SEARCH then
        site.group:getController():setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
    elseif mode == SAMSIM.RadarMode.TRACK then
        -- Tracking mode - narrow beam
    elseif mode == SAMSIM.RadarMode.GUIDE then
        -- Missile guidance mode
    end

    env.info("SAMSIM: Site " .. siteId .. " radar mode: " .. oldMode .. " -> " .. mode)
    return true
end

--[[
    Set system power state
]]
function SAMSIM.SetSystemState(siteId, state)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    site.systemState = state

    if state == SAMSIM.SystemState.OFFLINE then
        SAMSIM.SetRadarMode(siteId, SAMSIM.RadarMode.STANDBY)
    elseif state == SAMSIM.SystemState.READY then
        env.info("SAMSIM: Site " .. siteId .. " systems ready")
    end

    return true
end

--[[
    Command antenna to move to specific azimuth/elevation
]]
function SAMSIM.CommandAntenna(siteId, azimuth, elevation)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    -- Clamp values
    site.targetAzimuth = azimuth % 360
    site.targetElevation = math.max(0, math.min(85, elevation))

    return true
end

--[[
    Designate and track a target
]]
function SAMSIM.DesignateTarget(siteId, targetId)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    -- Find target in detected targets
    for _, target in pairs(site.detectedTargets) do
        if target.id == targetId then
            site.trackedTargetId = targetId
            site.trackedTarget = target.object
            site.radarMode = SAMSIM.RadarMode.TRACK
            env.info("SAMSIM: Site " .. siteId .. " tracking target: " .. targetId)
            return true
        end
    end

    return false
end

--[[
    Drop track and return to search
]]
function SAMSIM.DropTrack(siteId)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    site.trackedTarget = nil
    site.trackedTargetId = nil
    site.trackQuality = 0
    site.radarMode = SAMSIM.RadarMode.SEARCH

    return true
end

--[[
    Launch missile at tracked target
]]
function SAMSIM.LaunchMissile(siteId)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    if not site.trackedTarget then
        env.warning("SAMSIM: No target tracked for launch")
        return false
    end

    if site.missilesReady <= 0 then
        env.warning("SAMSIM: No missiles available")
        return false
    end

    if site.radarMode ~= SAMSIM.RadarMode.TRACK and site.radarMode ~= SAMSIM.RadarMode.GUIDE then
        env.warning("SAMSIM: Must be in TRACK or GUIDE mode to launch")
        return false
    end

    -- Check range
    local targetPos = site.trackedTarget:getPoint()
    local range = SAMSIM.GetDistance3D(site.position, targetPos)

    if range < SAMSIM.Config.MISSILE_MIN_RANGE then
        env.warning("SAMSIM: Target too close")
        return false
    end

    if range > SAMSIM.Config.MISSILE_MAX_RANGE then
        env.warning("SAMSIM: Target out of range")
        return false
    end

    -- Switch to guidance mode
    site.radarMode = SAMSIM.RadarMode.GUIDE

    -- Actually engage target using DCS AI
    site.group:getController():setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)

    -- Force engagement of specific target
    local attackTask = {
        id = 'AttackUnit',
        params = {
            unitId = site.trackedTarget:getID(),
            weaponType = 2147485694, -- SAM
            expend = "One",
            attackQtyLimit = true,
            attackQty = 1,
        }
    }
    site.group:getController():pushTask(attackTask)

    -- Record launch
    site.missilesReady = site.missilesReady - 1
    site.lastLaunchTime = timer.getTime()

    table.insert(site.missilesInFlight, {
        launchTime = timer.getTime(),
        targetId = site.trackedTargetId,
        flightTime = 0,
    })

    env.info("SAMSIM: Site " .. siteId .. " launched missile. Remaining: " .. site.missilesReady)

    return true
end

--[[
    Set engagement authorization
]]
function SAMSIM.SetEngagementAuth(siteId, authorized)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    site.engagementAuthorized = authorized

    if authorized then
        site.group:getController():setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_FREE)
    else
        site.group:getController():setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
    end

    return true
end

--[[
    Set auto-engage mode
]]
function SAMSIM.SetAutoEngage(siteId, autoEngage)
    local site = SAMSIM.Sites[siteId]
    if not site then return false end

    site.autoEngage = autoEngage
    return true
end

--[[
    Calculate 3D distance between two points
]]
function SAMSIM.GetDistance3D(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dy = (pos1.y or 0) - (pos2.y or 0)
    local dz = pos1.z - pos2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

--[[
    Calculate azimuth from site to target
]]
function SAMSIM.GetAzimuth(sitePos, targetPos)
    local dx = targetPos.x - sitePos.x
    local dz = targetPos.z - sitePos.z
    local azimuth = math.deg(math.atan2(dz, dx))
    return (90 - azimuth) % 360  -- Convert to compass bearing
end

--[[
    Calculate elevation angle from site to target
]]
function SAMSIM.GetElevation(sitePos, targetPos)
    local dx = targetPos.x - sitePos.x
    local dy = (targetPos.y or 0) - (sitePos.y or 0)
    local dz = targetPos.z - sitePos.z
    local groundDist = math.sqrt(dx*dx + dz*dz)
    return math.deg(math.atan2(dy, groundDist))
end

--[[
    Scan for targets in radar coverage
]]
function SAMSIM.ScanForTargets(site)
    site.detectedTargets = {}

    if site.radarMode == SAMSIM.RadarMode.STANDBY then
        return
    end

    -- Get all enemy aircraft and helicopters
    local redCoal = coalition.getAirGroups(coalition.side.RED)
    local blueCoal = coalition.getAirGroups(coalition.side.BLUE)

    -- Determine enemy coalition based on site's coalition
    local siteCoal = site.group:getCoalition()
    local enemyGroups = (siteCoal == coalition.side.RED) and blueCoal or redCoal

    local targetIndex = 1

    for _, group in pairs(enemyGroups) do
        local units = group:getUnits()
        for _, unit in pairs(units) do
            if unit and unit:isExist() and unit:inAir() then
                local targetPos = unit:getPoint()
                local range = SAMSIM.GetDistance3D(site.position, targetPos)
                local azimuth = SAMSIM.GetAzimuth(site.position, targetPos)
                local elevation = SAMSIM.GetElevation(site.position, targetPos)
                local altitude = targetPos.y - site.position.y

                -- Check if target is within radar coverage
                if range <= SAMSIM.Config.RADAR_MAX_RANGE and
                   range >= SAMSIM.Config.RADAR_MIN_RANGE * 0.5 and
                   altitude >= SAMSIM.Config.RADAR_MIN_ALT and
                   altitude <= SAMSIM.Config.RADAR_MAX_ALT then

                    -- In search mode, check if antenna is pointing at target
                    local detected = false

                    if site.radarMode == SAMSIM.RadarMode.SEARCH then
                        -- Full 360 search
                        detected = true
                    elseif site.radarMode == SAMSIM.RadarMode.TRACK or site.radarMode == SAMSIM.RadarMode.GUIDE then
                        -- Narrow beam - check if within antenna pointing direction
                        local azDiff = math.abs(azimuth - site.antennaAzimuth)
                        if azDiff > 180 then azDiff = 360 - azDiff end
                        local elDiff = math.abs(elevation - site.antennaElevation)

                        if azDiff <= SAMSIM.Config.TRACK_SCAN_WIDTH and elDiff <= 10 then
                            detected = true
                        end
                    end

                    if detected then
                        -- Calculate closure rate
                        local velocity = unit:getVelocity()
                        local speed = math.sqrt(velocity.x^2 + (velocity.y or 0)^2 + velocity.z^2)

                        -- Simple closure rate calculation
                        local dx = site.position.x - targetPos.x
                        local dz = site.position.z - targetPos.z
                        local groundDist = math.sqrt(dx*dx + dz*dz)
                        local closureRate = 0
                        if groundDist > 0 then
                            closureRate = (velocity.x * dx + velocity.z * dz) / groundDist
                        end

                        table.insert(site.detectedTargets, {
                            id = "TGT-" .. targetIndex,
                            object = unit,
                            unitName = unit:getName(),
                            typeName = unit:getTypeName(),
                            range = range,
                            azimuth = azimuth,
                            elevation = elevation,
                            altitude = altitude,
                            speed = speed,
                            closureRate = closureRate,
                            position = targetPos,
                        })

                        targetIndex = targetIndex + 1
                    end
                end
            end
        end
    end
end

--[[
    Update antenna position
]]
function SAMSIM.UpdateAntenna(site, dt)
    if site.radarMode == SAMSIM.RadarMode.STANDBY then
        return
    end

    -- If tracking, point at target
    if site.trackedTarget and site.trackedTarget:isExist() then
        local targetPos = site.trackedTarget:getPoint()
        site.targetAzimuth = SAMSIM.GetAzimuth(site.position, targetPos)
        site.targetElevation = SAMSIM.GetElevation(site.position, targetPos)
    end

    -- Move antenna towards target position
    local azDiff = site.targetAzimuth - site.antennaAzimuth
    if azDiff > 180 then azDiff = azDiff - 360 end
    if azDiff < -180 then azDiff = azDiff + 360 end

    local maxMove = SAMSIM.Config.ANTENNA_ROTATION_SPEED * dt

    if math.abs(azDiff) <= maxMove then
        site.antennaAzimuth = site.targetAzimuth
    else
        site.antennaAzimuth = site.antennaAzimuth + maxMove * (azDiff > 0 and 1 or -1)
    end
    site.antennaAzimuth = site.antennaAzimuth % 360

    -- Elevation
    local elDiff = site.targetElevation - site.antennaElevation
    if math.abs(elDiff) <= maxMove then
        site.antennaElevation = site.targetElevation
    else
        site.antennaElevation = site.antennaElevation + maxMove * (elDiff > 0 and 1 or -1)
    end
end

--[[
    Update track quality
]]
function SAMSIM.UpdateTrackQuality(site)
    if not site.trackedTarget or not site.trackedTarget:isExist() then
        site.trackQuality = 0
        if site.radarMode == SAMSIM.RadarMode.TRACK or site.radarMode == SAMSIM.RadarMode.GUIDE then
            -- Target lost
            SAMSIM.DropTrack(site.id)
        end
        return
    end

    local targetPos = site.trackedTarget:getPoint()
    local range = SAMSIM.GetDistance3D(site.position, targetPos)

    -- Track quality based on range and aspect
    local rangeQuality = 100 - (range / SAMSIM.Config.RADAR_MAX_RANGE * 50)

    -- Reduce quality based on antenna pointing error
    local azimuth = SAMSIM.GetAzimuth(site.position, targetPos)
    local azDiff = math.abs(azimuth - site.antennaAzimuth)
    if azDiff > 180 then azDiff = 360 - azDiff end
    local pointingQuality = math.max(0, 100 - azDiff * 10)

    site.trackQuality = math.floor((rangeQuality + pointingQuality) / 2)
end

--[[
    Update missiles in flight
]]
function SAMSIM.UpdateMissiles(site)
    local currentTime = timer.getTime()
    local activeMissiles = {}

    for _, missile in pairs(site.missilesInFlight) do
        missile.flightTime = currentTime - missile.launchTime

        if missile.flightTime < SAMSIM.Config.MISSILE_FLIGHT_TIME then
            table.insert(activeMissiles, missile)
        end
    end

    site.missilesInFlight = activeMissiles

    -- Return to track mode if no missiles in flight
    if #site.missilesInFlight == 0 and site.radarMode == SAMSIM.RadarMode.GUIDE then
        if site.trackedTarget then
            site.radarMode = SAMSIM.RadarMode.TRACK
        else
            site.radarMode = SAMSIM.RadarMode.SEARCH
        end
    end
end

--[[
    Get site status for export
]]
function SAMSIM.GetSiteStatus(siteId)
    local site = SAMSIM.Sites[siteId]
    if not site then return nil end

    local targets = {}
    for _, target in pairs(site.detectedTargets) do
        table.insert(targets, {
            id = target.id,
            type = target.typeName,
            range = math.floor(target.range),
            azimuth = math.floor(target.azimuth * 10) / 10,
            elevation = math.floor(target.elevation * 10) / 10,
            altitude = math.floor(target.altitude),
            speed = math.floor(target.speed),
            closure = math.floor(target.closureRate),
        })
    end

    local trackedInfo = nil
    if site.trackedTarget and site.trackedTarget:isExist() then
        local tgtPos = site.trackedTarget:getPoint()
        trackedInfo = {
            id = site.trackedTargetId,
            range = math.floor(SAMSIM.GetDistance3D(site.position, tgtPos)),
            azimuth = math.floor(SAMSIM.GetAzimuth(site.position, tgtPos) * 10) / 10,
            elevation = math.floor(SAMSIM.GetElevation(site.position, tgtPos) * 10) / 10,
            altitude = math.floor(tgtPos.y),
        }
    end

    return {
        siteId = siteId,
        systemState = site.systemState,
        radarMode = site.radarMode,
        antennaAz = math.floor(site.antennaAzimuth * 10) / 10,
        antennaEl = math.floor(site.antennaElevation * 10) / 10,
        targets = targets,
        tracked = trackedInfo,
        trackQuality = site.trackQuality,
        missilesReady = site.missilesReady,
        missilesInFlight = #site.missilesInFlight,
        engAuth = site.engagementAuthorized,
        autoEng = site.autoEngage,
        time = timer.getTime(),
    }
end

--[[
    Main update function - called periodically
]]
function SAMSIM.Update()
    local dt = SAMSIM.Config.UPDATE_INTERVAL

    for siteId, site in pairs(SAMSIM.Sites) do
        if site.systemState ~= SAMSIM.SystemState.OFFLINE then
            -- Scan for targets
            SAMSIM.ScanForTargets(site)

            -- Update antenna
            SAMSIM.UpdateAntenna(site, dt)

            -- Update tracking
            SAMSIM.UpdateTrackQuality(site)

            -- Update missiles
            SAMSIM.UpdateMissiles(site)

            -- Auto-engage logic
            if site.autoEngage and site.engagementAuthorized then
                if not site.trackedTarget and #site.detectedTargets > 0 then
                    -- Auto-designate closest target
                    local closest = nil
                    local closestRange = math.huge
                    for _, target in pairs(site.detectedTargets) do
                        if target.range < closestRange then
                            closest = target
                            closestRange = target.range
                        end
                    end
                    if closest then
                        SAMSIM.DesignateTarget(siteId, closest.id)
                    end
                end

                -- Auto-launch if tracking and in range
                if site.trackedTarget and site.trackQuality > 50 then
                    local targetPos = site.trackedTarget:getPoint()
                    local range = SAMSIM.GetDistance3D(site.position, targetPos)
                    if range >= SAMSIM.Config.MISSILE_MIN_RANGE and
                       range <= SAMSIM.Config.MISSILE_MAX_RANGE * 0.8 and
                       #site.missilesInFlight == 0 then
                        SAMSIM.LaunchMissile(siteId)
                    end
                end
            end
        end
    end

    -- Schedule next update
    return timer.getTime() + SAMSIM.Config.UPDATE_INTERVAL
end

--[[
    Process command from external controller
    Command format: {cmd = "command_name", siteId = "site_id", params = {...}}
]]
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

    elseif cmd == "set_radar_mode" then
        return {success = SAMSIM.SetRadarMode(siteId, params.mode)}

    elseif cmd == "set_system_state" then
        return {success = SAMSIM.SetSystemState(siteId, params.state)}

    elseif cmd == "command_antenna" then
        return {success = SAMSIM.CommandAntenna(siteId, params.azimuth, params.elevation)}

    elseif cmd == "designate_target" then
        return {success = SAMSIM.DesignateTarget(siteId, params.targetId)}

    elseif cmd == "drop_track" then
        return {success = SAMSIM.DropTrack(siteId)}

    elseif cmd == "launch_missile" then
        return {success = SAMSIM.LaunchMissile(siteId)}

    elseif cmd == "set_eng_auth" then
        return {success = SAMSIM.SetEngagementAuth(siteId, params.authorized)}

    elseif cmd == "set_auto_engage" then
        return {success = SAMSIM.SetAutoEngage(siteId, params.autoEngage)}

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

--[[
    Initialize SAMSIM system
]]
function SAMSIM.Init()
    env.info("SAMSIM: Initializing SA-2 SAMSim Controller...")

    -- Start update loop
    timer.scheduleFunction(SAMSIM.Update, nil, timer.getTime() + 1)

    env.info("SAMSIM: System initialized successfully")
end

-- Auto-initialize when script is loaded
SAMSIM.Init()

env.info("SAMSIM: SA-2 SAMSim Controller loaded")
