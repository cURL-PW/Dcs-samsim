--[[
    SAMSIM Missile Simulation Module

    Simulates missile flight, guidance, and kill assessment

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_Missile = {}
SAMSIM_Missile.Version = "1.0.0"

-- ============================================================================
-- Missile Types
-- ============================================================================
SAMSIM_Missile.Types = {
    -- SA-2
    V750 = {
        name = "V-750 (SA-2)",
        maxRange = 45000,
        minRange = 7000,
        maxAltitude = 25000,
        minAltitude = 500,
        maxSpeed = 1100,        -- m/s
        acceleration = 30,      -- g
        guidance = "CLOS",
        warheadKg = 195,
        proximityFuze = 65,     -- meters
        burnTime = 6,           -- seconds
        coastTime = 20,         -- seconds after burnout
    },
    -- SA-3
    V601P = {
        name = "5V27 (SA-3)",
        maxRange = 25000,
        minRange = 3500,
        maxAltitude = 18000,
        minAltitude = 20,
        maxSpeed = 1000,
        acceleration = 35,
        guidance = "CLOS",
        warheadKg = 60,
        proximityFuze = 12,
        burnTime = 4,
        coastTime = 15,
    },
    -- SA-6
    M3M9 = {
        name = "3M9 (SA-6)",
        maxRange = 24000,
        minRange = 4000,
        maxAltitude = 14000,
        minAltitude = 50,
        maxSpeed = 800,
        acceleration = 20,
        guidance = "SARH",
        warheadKg = 56,
        proximityFuze = 15,
        burnTime = 5,
        coastTime = 12,
    },
    -- SA-10
    V5V55R = {
        name = "5V55R (SA-10)",
        maxRange = 90000,
        minRange = 5000,
        maxAltitude = 30000,
        minAltitude = 25,
        maxSpeed = 2000,
        acceleration = 40,
        guidance = "TVM",
        warheadKg = 133,
        proximityFuze = 20,
        burnTime = 10,
        coastTime = 30,
    },
    -- SA-11
    M9M38 = {
        name = "9M38 (SA-11)",
        maxRange = 35000,
        minRange = 3000,
        maxAltitude = 22000,
        minAltitude = 15,
        maxSpeed = 1230,
        acceleration = 25,
        guidance = "SARH",
        warheadKg = 70,
        proximityFuze = 17,
        burnTime = 6,
        coastTime = 18,
    },
}

-- ============================================================================
-- Guidance Types
-- ============================================================================
SAMSIM_Missile.GuidanceType = {
    CLOS = 1,       -- Command Line Of Sight
    SARH = 2,       -- Semi-Active Radar Homing
    TVM = 3,        -- Track Via Missile
    ARH = 4,        -- Active Radar Homing
}

-- ============================================================================
-- Missile Status
-- ============================================================================
SAMSIM_Missile.Status = {
    READY = 0,
    LAUNCHED = 1,
    BOOST = 2,
    SUSTAIN = 3,
    COAST = 4,
    TERMINAL = 5,
    INTERCEPT = 6,
    MISS = 7,
    DESTROYED = 8,
}

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_Missile.Config = {
    UPDATE_INTERVAL = 0.05,
    GUIDANCE_UPDATE_RATE = 20,      -- Hz
    MAX_TRACKING_ERROR = 5,         -- degrees
    KILL_RADIUS_MULTIPLIER = 1.5,   -- Multiply proximity fuze by this for Pk calc
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_Missile.State = {
    missiles = {},      -- Active missiles
    engagements = {},   -- Engagement results
    nextMissileId = 1,
}

-- ============================================================================
-- Utility Functions
-- ============================================================================
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

local function vectorNormalize(v)
    local mag = vectorMagnitude(v)
    if mag > 0 then
        return {x = v.x / mag, y = v.y / mag, z = v.z / mag}
    end
    return {x = 0, y = 0, z = 0}
end

local function vectorDot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function vectorCross(a, b)
    return {
        x = a.y * b.z - a.z * b.y,
        y = a.z * b.x - a.x * b.z,
        z = a.x * b.y - a.y * b.x
    }
end

-- ============================================================================
-- Missile Creation
-- ============================================================================
function SAMSIM_Missile.launch(missileType, launchPos, launchVel, targetId, targetPos, targetVel, radarId)
    local typeData = SAMSIM_Missile.Types[missileType]
    if not typeData then
        env.error("SAMSIM_Missile: Unknown missile type " .. tostring(missileType))
        return nil
    end

    local missile = {
        id = SAMSIM_Missile.State.nextMissileId,
        type = missileType,
        typeData = typeData,
        status = SAMSIM_Missile.Status.LAUNCHED,

        -- Position and velocity
        position = {x = launchPos.x, y = launchPos.y, z = launchPos.z},
        velocity = {x = launchVel.x or 0, y = launchVel.y + 50, z = launchVel.z or 0},
        heading = 0,
        pitch = 85,     -- Launch nearly vertical

        -- Target info
        targetId = targetId,
        targetPos = targetPos,
        targetVel = targetVel,
        predictedIntercept = nil,

        -- Timing
        launchTime = timer.getTime(),
        flightTime = 0,
        burnEndTime = timer.getTime() + typeData.burnTime,
        maxFlightTime = typeData.burnTime + typeData.coastTime,

        -- Guidance
        radarId = radarId,
        guidanceActive = true,
        lastGuidanceUpdate = 0,
        commandedHeading = 0,
        commandedPitch = 0,

        -- Track data
        trackLost = false,
        missDistance = nil,

        -- For display
        trail = {},
    }

    SAMSIM_Missile.State.nextMissileId = SAMSIM_Missile.State.nextMissileId + 1
    table.insert(SAMSIM_Missile.State.missiles, missile)

    env.info("SAMSIM_Missile: Launched " .. typeData.name .. " ID " .. missile.id)

    return missile.id
end

-- ============================================================================
-- Guidance Algorithms
-- ============================================================================

-- Command Line Of Sight (CLOS) guidance
function SAMSIM_Missile.guidanceCLOS(missile, radarPos, targetPos)
    -- Calculate line of sight from radar to target
    local losToTarget = vectorSubtract(targetPos, radarPos)
    local losDistance = vectorMagnitude(losToTarget)
    local losNorm = vectorNormalize(losToTarget)

    -- Calculate where missile should be on LOS
    local missileToRadar = vectorSubtract(missile.position, radarPos)
    local missileRange = vectorMagnitude(missileToRadar)

    -- Desired position on LOS at missile's range
    local desiredPos = vectorAdd(radarPos, vectorScale(losNorm, missileRange))

    -- Steering command is toward desired position
    local steerVector = vectorSubtract(desiredPos, missile.position)

    return vectorNormalize(steerVector)
end

-- Semi-Active Radar Homing (SARH) guidance - Proportional Navigation
function SAMSIM_Missile.guidanceSARH(missile, targetPos, targetVel)
    -- Relative position and velocity
    local relPos = vectorSubtract(targetPos, missile.position)
    local relVel = vectorSubtract(targetVel, missile.velocity)

    local range = vectorMagnitude(relPos)
    local closingVel = -vectorDot(relVel, vectorNormalize(relPos))

    -- Line of sight rate (simplified)
    local losRate = vectorCross(relPos, relVel)
    local losRateMag = vectorMagnitude(losRate) / (range * range)

    -- Proportional navigation constant (typically 3-5)
    local N = 4

    -- Acceleration command perpendicular to LOS
    local accelMag = N * closingVel * losRateMag

    -- Direction of acceleration
    local accelDir = vectorNormalize(vectorCross(vectorCross(relPos, relVel), relPos))

    return vectorScale(accelDir, accelMag)
end

-- Track Via Missile (TVM) guidance - combination of CLOS and PN
function SAMSIM_Missile.guidanceTVM(missile, radarPos, targetPos, targetVel)
    -- TVM uses missile seeker data sent back to ground for processing
    -- Then ground sends optimal steering commands

    -- Calculate pure pursuit vector
    local pursuitVec = vectorSubtract(targetPos, missile.position)

    -- Calculate lead angle based on target velocity
    local timeToIntercept = vectorMagnitude(pursuitVec) / vectorMagnitude(missile.velocity)
    local predictedPos = vectorAdd(targetPos, vectorScale(targetVel, timeToIntercept * 0.8))

    local leadVec = vectorSubtract(predictedPos, missile.position)

    return vectorNormalize(leadVec)
end

-- ============================================================================
-- Missile Update
-- ============================================================================
function SAMSIM_Missile.updateMissile(missile, dt, radarPos, targetPos, targetVel)
    local currentTime = timer.getTime()
    missile.flightTime = currentTime - missile.launchTime

    -- Check max flight time
    if missile.flightTime > missile.maxFlightTime then
        missile.status = SAMSIM_Missile.Status.MISS
        return
    end

    -- Update status based on flight phase
    if currentTime < missile.burnEndTime then
        missile.status = SAMSIM_Missile.Status.BOOST
    else
        missile.status = SAMSIM_Missile.Status.COAST
    end

    -- Calculate thrust
    local thrust = 0
    if missile.status == SAMSIM_Missile.Status.BOOST then
        thrust = missile.typeData.maxSpeed * 3  -- Simplified thrust
    end

    -- Guidance update
    if missile.guidanceActive and targetPos then
        local steerCmd = nil

        if missile.typeData.guidance == "CLOS" then
            steerCmd = SAMSIM_Missile.guidanceCLOS(missile, radarPos, targetPos)
        elseif missile.typeData.guidance == "SARH" then
            steerCmd = SAMSIM_Missile.guidanceSARH(missile, targetPos, targetVel)
        elseif missile.typeData.guidance == "TVM" then
            steerCmd = SAMSIM_Missile.guidanceTVM(missile, radarPos, targetPos, targetVel)
        end

        if steerCmd then
            -- Smooth steering (missile has limited maneuverability)
            local maxTurn = missile.typeData.acceleration * 9.81 * dt / vectorMagnitude(missile.velocity)

            local currentDir = vectorNormalize(missile.velocity)
            local desiredDir = steerCmd

            -- Blend current and desired direction
            local newDir = {
                x = currentDir.x + (desiredDir.x - currentDir.x) * math.min(1, maxTurn * 10),
                y = currentDir.y + (desiredDir.y - currentDir.y) * math.min(1, maxTurn * 10),
                z = currentDir.z + (desiredDir.z - currentDir.z) * math.min(1, maxTurn * 10),
            }
            newDir = vectorNormalize(newDir)

            -- Apply thrust in new direction
            local speed = vectorMagnitude(missile.velocity)
            if thrust > 0 then
                speed = math.min(missile.typeData.maxSpeed, speed + thrust * dt / 100)
            else
                -- Drag in coast phase
                speed = speed * (1 - 0.01 * dt)
            end

            missile.velocity = vectorScale(newDir, speed)
        end
    end

    -- Apply gravity
    missile.velocity.y = missile.velocity.y - 9.81 * dt

    -- Update position
    missile.position.x = missile.position.x + missile.velocity.x * dt
    missile.position.y = missile.position.y + missile.velocity.y * dt
    missile.position.z = missile.position.z + missile.velocity.z * dt

    -- Store trail point
    if #missile.trail < 100 then
        table.insert(missile.trail, {
            x = missile.position.x,
            y = missile.position.y,
            z = missile.position.z,
            time = currentTime,
        })
    end

    -- Check intercept
    if targetPos then
        local distToTarget = vectorMagnitude(vectorSubtract(targetPos, missile.position))
        missile.missDistance = distToTarget

        if distToTarget < missile.typeData.proximityFuze then
            missile.status = SAMSIM_Missile.Status.INTERCEPT
            SAMSIM_Missile.assessKill(missile, distToTarget)
        end
    end

    -- Check ground impact
    if missile.position.y < 0 then
        missile.status = SAMSIM_Missile.Status.MISS
    end
end

-- ============================================================================
-- Kill Assessment
-- ============================================================================
function SAMSIM_Missile.assessKill(missile, missDistance)
    local typeData = missile.typeData

    -- Simplified kill probability based on miss distance
    local killRadius = typeData.proximityFuze * SAMSIM_Missile.Config.KILL_RADIUS_MULTIPLIER
    local pk = 0

    if missDistance <= typeData.proximityFuze * 0.5 then
        pk = 0.95  -- Direct hit
    elseif missDistance <= typeData.proximityFuze then
        pk = 0.80  -- Within fuze radius
    elseif missDistance <= killRadius then
        pk = 0.50 * (1 - (missDistance - typeData.proximityFuze) / (killRadius - typeData.proximityFuze))
    end

    -- Random kill determination
    local killed = math.random() < pk

    -- Record engagement result
    local engagement = {
        missileId = missile.id,
        missileType = missile.type,
        targetId = missile.targetId,
        launchTime = missile.launchTime,
        interceptTime = timer.getTime(),
        flightTime = missile.flightTime,
        missDistance = missDistance,
        pk = pk,
        killed = killed,
    }

    table.insert(SAMSIM_Missile.State.engagements, engagement)

    if killed then
        missile.status = SAMSIM_Missile.Status.DESTROYED
        env.info("SAMSIM_Missile: Target DESTROYED by missile " .. missile.id)
    else
        env.info("SAMSIM_Missile: Target SURVIVED missile " .. missile.id .. " (miss dist: " ..
                 string.format("%.1f", missDistance) .. "m)")
    end

    return engagement
end

-- ============================================================================
-- Main Update Loop
-- ============================================================================
function SAMSIM_Missile.update(radarPos, getTargetData)
    local currentTime = timer.getTime()
    local dt = SAMSIM_Missile.Config.UPDATE_INTERVAL

    local toRemove = {}

    for i, missile in ipairs(SAMSIM_Missile.State.missiles) do
        if missile.status == SAMSIM_Missile.Status.LAUNCHED or
           missile.status == SAMSIM_Missile.Status.BOOST or
           missile.status == SAMSIM_Missile.Status.SUSTAIN or
           missile.status == SAMSIM_Missile.Status.COAST or
           missile.status == SAMSIM_Missile.Status.TERMINAL then

            -- Get current target data
            local targetPos, targetVel = nil, nil
            if getTargetData and missile.targetId then
                targetPos, targetVel = getTargetData(missile.targetId)
            end

            SAMSIM_Missile.updateMissile(missile, dt, radarPos, targetPos, targetVel)
        else
            -- Missile is no longer active
            if missile.flightTime > 5 then  -- Keep for 5 seconds after terminal
                table.insert(toRemove, i)
            end
        end
    end

    -- Remove finished missiles
    for i = #toRemove, 1, -1 do
        table.remove(SAMSIM_Missile.State.missiles, toRemove[i])
    end

    return timer.getTime() + SAMSIM_Missile.Config.UPDATE_INTERVAL
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM_Missile.getStateForExport()
    local missiles = {}

    for _, missile in ipairs(SAMSIM_Missile.State.missiles) do
        table.insert(missiles, {
            id = missile.id,
            type = missile.type,
            typeName = missile.typeData.name,
            status = missile.status,
            statusName = SAMSIM_Missile.getStatusName(missile.status),
            position = missile.position,
            velocity = missile.velocity,
            speed = vectorMagnitude(missile.velocity),
            flightTime = missile.flightTime,
            targetId = missile.targetId,
            missDistance = missile.missDistance,
            trail = missile.trail,
        })
    end

    local engagements = {}
    for i = math.max(1, #SAMSIM_Missile.State.engagements - 10), #SAMSIM_Missile.State.engagements do
        local eng = SAMSIM_Missile.State.engagements[i]
        if eng then
            table.insert(engagements, {
                missileId = eng.missileId,
                targetId = eng.targetId,
                flightTime = eng.flightTime,
                missDistance = eng.missDistance,
                pk = eng.pk,
                killed = eng.killed,
            })
        end
    end

    return {
        missiles = missiles,
        engagements = engagements,
        activeMissiles = #SAMSIM_Missile.State.missiles,
    }
end

function SAMSIM_Missile.getStatusName(status)
    local names = {"READY", "LAUNCHED", "BOOST", "SUSTAIN", "COAST", "TERMINAL", "INTERCEPT", "MISS", "DESTROYED"}
    return names[status + 1] or "UNKNOWN"
end

-- ============================================================================
-- Command Processing
-- ============================================================================
function SAMSIM_Missile.processCommand(cmd)
    local response = {success = false, message = "Unknown missile command"}

    if cmd.type == "LAUNCH_MISSILE" then
        local missileId = SAMSIM_Missile.launch(
            cmd.missileType,
            cmd.launchPos,
            cmd.launchVel or {x=0, y=0, z=0},
            cmd.targetId,
            cmd.targetPos,
            cmd.targetVel,
            cmd.radarId
        )

        if missileId then
            response = {success = true, message = "Missile launched", missileId = missileId}
        else
            response = {success = false, message = "Launch failed"}
        end

    elseif cmd.type == "GET_MISSILE_STATUS" then
        for _, missile in ipairs(SAMSIM_Missile.State.missiles) do
            if missile.id == cmd.missileId then
                response = {
                    success = true,
                    status = missile.status,
                    position = missile.position,
                    flightTime = missile.flightTime,
                }
                break
            end
        end
    end

    return response
end

env.info("SAMSIM Missile Simulation Module loaded - Version " .. SAMSIM_Missile.Version)
