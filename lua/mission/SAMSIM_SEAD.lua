--[[
    SEAD/DEAD Tactical Simulation Module for DCS World

    Features:
    - Anti-Radiation Missile (ARM) simulation
    - Jammer aircraft effects
    - Wild Weasel tactics
    - SAM site threat assessment
    - Emission control (EMCON) recommendations
    - Decoy and countermeasures

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_SEAD = {}
SAMSIM_SEAD.Version = "1.0.0"

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_SEAD.Config = {
    -- Anti-Radiation Missiles
    arms = {
        AGM88 = {  -- AGM-88 HARM
            name = "AGM-88 HARM",
            maxRange = 150000,      -- 150km max launch range
            minRange = 25000,       -- 25km
            speed = 680,            -- Mach 2
            seeker = {
                type = "PASSIVE_RADAR",
                sensitivity = -60,   -- dBm
                bandwidth = {2000, 18000},  -- MHz frequency range
                fov = 45,           -- degrees
                memoryTime = 30,    -- seconds of memory after emitter shutdown
            },
            guidance = "HOME_ON_JAM",
            loft = true,            -- Lofts for extended range
            warhead = 66,           -- kg
            warheadRadius = 25,     -- meters
        },
        Kh31P = {  -- Kh-31P
            name = "Kh-31P",
            maxRange = 110000,
            minRange = 15000,
            speed = 1000,           -- Mach 3
            seeker = {
                type = "PASSIVE_RADAR",
                sensitivity = -55,
                bandwidth = {5000, 15000},
                fov = 30,
                memoryTime = 20,
            },
            guidance = "HOME_ON_JAM",
            loft = false,
            warhead = 87,
            warheadRadius = 20,
        },
        AGM45 = {  -- AGM-45 Shrike
            name = "AGM-45 Shrike",
            maxRange = 40000,
            minRange = 5000,
            speed = 680,
            seeker = {
                type = "PASSIVE_RADAR",
                sensitivity = -50,
                bandwidth = {1000, 10000},
                fov = 25,
                memoryTime = 5,     -- Very short memory
            },
            guidance = "HOME_ON_JAM",
            loft = false,
            warhead = 66,
            warheadRadius = 15,
        },
    },

    -- Jammer Aircraft
    jammers = {
        EF111 = {
            name = "EF-111A Raven",
            type = "STANDOFF",
            jamPower = 1000,        -- Watts ERP
            bandwidth = {2000, 18000},
            techniques = {"NOISE", "DECEPTION", "RANGE_GATE_PULL_OFF"},
            standoffRange = 80000,  -- 80km standoff
        },
        EA6B = {
            name = "EA-6B Prowler",
            type = "ESCORT",
            jamPower = 2000,
            bandwidth = {500, 20000},
            techniques = {"NOISE", "DECEPTION", "DRFM", "CROSSEYE"},
            standoffRange = 50000,
        },
        EA18G = {
            name = "EA-18G Growler",
            type = "ESCORT",
            jamPower = 3000,
            bandwidth = {500, 40000},
            techniques = {"NOISE", "DECEPTION", "DRFM", "CROSSEYE", "REACTIVE"},
            standoffRange = 60000,
            armCapable = true,      -- Can carry HARMs
        },
    },

    -- SAM Vulnerability
    vulnerability = {
        radarKillRadius = 30,       -- meters - radar destroyed
        launcherKillRadius = 15,    -- meters - launcher destroyed
        commandKillRadius = 20,     -- meters - command post destroyed
    },

    -- EMCON Recommendations
    emcon = {
        armDetectionRange = 80000,  -- Range at which to recommend EMCON
        armFlightTime = 120,        -- Typical ARM flight time to close
        shutdownDelay = 5,          -- Seconds to shutdown after launch detect
        restartDelay = 60,          -- Minimum time before restart
    },
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_SEAD.State = {
    -- Active ARMs in flight
    armsInFlight = {},

    -- Detected jammer aircraft
    detectedJammers = {},

    -- Threat level for each SAM site
    siteThreatLevels = {},

    -- EMCON recommendations
    emconRecommendations = {},

    -- ARM launch detections
    armLaunches = {},

    -- Destroyed/damaged components
    damage = {},
}

-- ============================================================================
-- ARM Simulation
-- ============================================================================
SAMSIM_SEAD.ARM = {}

function SAMSIM_SEAD.ARM.detectLaunch(missileUnit, targetSite)
    if not missileUnit or not targetSite then return end

    local armType = SAMSIM_SEAD.ARM.identifyMissile(missileUnit)
    if not armType then return end

    local config = SAMSIM_SEAD.Config.arms[armType]
    if not config then return end

    local launchPos = missileUnit:getPoint()
    local sitePos = targetSite.position

    local dx = sitePos.x - launchPos.x
    local dz = sitePos.z - launchPos.z
    local range = math.sqrt(dx*dx + dz*dz)

    -- Check if launch is within ARM parameters
    if range > config.maxRange or range < config.minRange then
        return
    end

    -- Calculate time to impact
    local tti = range / config.speed

    local arm = {
        id = missileUnit:getID(),
        type = armType,
        name = config.name,
        launchTime = timer.getTime(),
        launchPos = launchPos,
        targetSite = targetSite.id,
        targetPos = sitePos,
        range = range,
        timeToImpact = tti,
        speed = config.speed,
        phase = "LAUNCH",
        memoryLock = false,
        lastKnownEmitter = sitePos,
    }

    table.insert(SAMSIM_SEAD.State.armsInFlight, arm)

    -- Notify SAM site of ARM launch
    SAMSIM_SEAD.notifyARMLaunch(targetSite.id, arm)

    env.info(string.format("SEAD: ARM launch detected - %s at %s, TTI: %.0fs",
        config.name, targetSite.id, tti))

    return arm
end

function SAMSIM_SEAD.ARM.identifyMissile(unit)
    if not unit then return nil end

    local typeName = unit:getTypeName()

    -- Map DCS weapon types to our ARM types
    if typeName:find("AGM%-88") or typeName:find("HARM") then
        return "AGM88"
    elseif typeName:find("Kh%-31P") then
        return "Kh31P"
    elseif typeName:find("AGM%-45") or typeName:find("Shrike") then
        return "AGM45"
    end

    return nil
end

function SAMSIM_SEAD.ARM.update(dt)
    local currentTime = timer.getTime()

    for i = #SAMSIM_SEAD.State.armsInFlight, 1, -1 do
        local arm = SAMSIM_SEAD.State.armsInFlight[i]
        local elapsed = currentTime - arm.launchTime
        local config = SAMSIM_SEAD.Config.arms[arm.type]

        -- Update phase
        if elapsed < arm.timeToImpact * 0.2 then
            arm.phase = "BOOST"
        elseif elapsed < arm.timeToImpact * 0.8 then
            arm.phase = "CRUISE"
        else
            arm.phase = "TERMINAL"
        end

        -- Check if target emitter is still active
        local siteState = SAMSIM_SEAD.getSiteState(arm.targetSite)
        if siteState then
            if siteState.emitting then
                arm.lastKnownEmitter = siteState.position
                arm.memoryLock = false
            else
                arm.memoryLock = true
                -- ARM may lose lock if memory time exceeded
                if arm.memoryLock and elapsed > config.seeker.memoryTime then
                    arm.phase = "LOST_LOCK"
                end
            end
        end

        -- Check for impact
        if elapsed >= arm.timeToImpact then
            SAMSIM_SEAD.ARM.impact(arm)
            table.remove(SAMSIM_SEAD.State.armsInFlight, i)
        end
    end
end

function SAMSIM_SEAD.ARM.impact(arm)
    local config = SAMSIM_SEAD.Config.arms[arm.type]

    -- Calculate miss distance based on tracking
    local missDistance = 0

    if arm.phase == "LOST_LOCK" then
        -- Lost lock - random miss
        missDistance = math.random(50, 200)
    elseif arm.memoryLock then
        -- Memory lock - some accuracy degradation
        missDistance = math.random(10, 50)
    else
        -- Active track - good accuracy
        missDistance = math.random(0, 15)
    end

    -- Determine damage
    local result = "MISS"
    local vulnConfig = SAMSIM_SEAD.Config.vulnerability

    if missDistance <= vulnConfig.radarKillRadius then
        result = "RADAR_DESTROYED"
        SAMSIM_SEAD.applyDamage(arm.targetSite, "RADAR", 1.0)
    elseif missDistance <= vulnConfig.launcherKillRadius then
        result = "LAUNCHER_DAMAGED"
        SAMSIM_SEAD.applyDamage(arm.targetSite, "LAUNCHER", 0.5)
    elseif missDistance <= config.warheadRadius then
        result = "MINOR_DAMAGE"
        SAMSIM_SEAD.applyDamage(arm.targetSite, "GENERAL", 0.2)
    end

    env.info(string.format("SEAD: ARM impact - %s at %s, Miss: %.0fm, Result: %s",
        arm.name, arm.targetSite, missDistance, result))

    return {
        result = result,
        missDistance = missDistance,
        targetSite = arm.targetSite,
    }
end

-- ============================================================================
-- Jammer Simulation
-- ============================================================================
SAMSIM_SEAD.Jammer = {}

function SAMSIM_SEAD.Jammer.detectJammers(sitePosition, siteRadar)
    local jammers = {}

    -- Search for jammer aircraft
    local volume = {
        id = world.VolumeType.SPHERE,
        params = {
            point = sitePosition,
            radius = 200000,  -- 200km search radius
        }
    }

    world.searchObjects(Object.Category.UNIT, volume, function(found)
        if found and found:isExist() then
            local typeName = found:getTypeName()
            local jammerType = SAMSIM_SEAD.Jammer.identifyJammer(typeName)

            if jammerType then
                local jammerPos = found:getPoint()
                local dx = jammerPos.x - sitePosition.x
                local dz = jammerPos.z - sitePosition.z
                local range = math.sqrt(dx*dx + dz*dz)
                local azimuth = math.deg(math.atan2(dz, dx))
                if azimuth < 0 then azimuth = azimuth + 360 end

                local config = SAMSIM_SEAD.Config.jammers[jammerType]

                -- Calculate jamming effect
                local jammingEffect = SAMSIM_SEAD.Jammer.calculateEffect(
                    config, range, siteRadar
                )

                table.insert(jammers, {
                    id = found:getID(),
                    type = jammerType,
                    name = config.name,
                    position = jammerPos,
                    range = range,
                    azimuth = azimuth,
                    power = config.jamPower,
                    effect = jammingEffect,
                })
            end
        end
        return true
    end)

    SAMSIM_SEAD.State.detectedJammers = jammers
    return jammers
end

function SAMSIM_SEAD.Jammer.identifyJammer(typeName)
    if typeName:find("EF%-111") or typeName:find("Raven") then
        return "EF111"
    elseif typeName:find("EA%-6") or typeName:find("Prowler") then
        return "EA6B"
    elseif typeName:find("EA%-18") or typeName:find("Growler") then
        return "EA18G"
    end
    return nil
end

function SAMSIM_SEAD.Jammer.calculateEffect(jammerConfig, range, radarConfig)
    -- Calculate J/S (Jamming to Signal) ratio

    -- Simplified calculation
    local jammerERP = jammerConfig.jamPower
    local radarPower = radarConfig and radarConfig.power or 1000

    -- Range factors (inverse square law)
    local rangeFactor = (1000 / range)^2  -- Normalized to 1km

    -- Frequency overlap
    local freqOverlap = 1.0  -- Assume full overlap for simplicity

    -- Calculate J/S in dB
    local js_ratio = 10 * math.log10(jammerERP / radarPower) + 20 * math.log10(rangeFactor)

    local effect = {
        js_ratio = js_ratio,
        effectLevel = "NONE",
        burnThrough = 0,
    }

    -- Determine effect level
    if js_ratio > 20 then
        effect.effectLevel = "SEVERE"
        effect.burnThrough = range * 0.1  -- 10% of range
    elseif js_ratio > 10 then
        effect.effectLevel = "MODERATE"
        effect.burnThrough = range * 0.3
    elseif js_ratio > 0 then
        effect.effectLevel = "LIGHT"
        effect.burnThrough = range * 0.6
    end

    return effect
end

-- ============================================================================
-- Threat Assessment
-- ============================================================================
SAMSIM_SEAD.Threat = {}

function SAMSIM_SEAD.Threat.assess(siteId)
    local threat = {
        level = "LOW",
        score = 0,
        factors = {},
        recommendations = {},
    }

    -- Check for ARMs in flight
    local armsTargetingUs = 0
    for _, arm in ipairs(SAMSIM_SEAD.State.armsInFlight) do
        if arm.targetSite == siteId then
            armsTargetingUs = armsTargetingUs + 1
            table.insert(threat.factors, {
                type = "ARM_INBOUND",
                detail = arm.name,
                tti = arm.timeToImpact - (timer.getTime() - arm.launchTime),
            })
        end
    end

    if armsTargetingUs > 0 then
        threat.score = threat.score + 50 * armsTargetingUs
        table.insert(threat.recommendations, "IMMEDIATE_SHUTDOWN")
        table.insert(threat.recommendations, "RELOCATE_IF_POSSIBLE")
    end

    -- Check for jammer activity
    for _, jammer in ipairs(SAMSIM_SEAD.State.detectedJammers) do
        if jammer.range < 100000 then  -- Within 100km
            threat.score = threat.score + 20
            table.insert(threat.factors, {
                type = "JAMMER_ACTIVE",
                detail = jammer.name,
                range = jammer.range,
            })
        end
    end

    -- Check for Wild Weasel aircraft (fighters with ARMs)
    -- Would scan for F-16CJ, F-4G, Tornado ECR, etc.

    -- Determine threat level
    if threat.score >= 80 then
        threat.level = "CRITICAL"
        table.insert(threat.recommendations, "EMCON_IMMEDIATE")
    elseif threat.score >= 50 then
        threat.level = "HIGH"
        table.insert(threat.recommendations, "EMCON_RECOMMENDED")
    elseif threat.score >= 20 then
        threat.level = "MODERATE"
        table.insert(threat.recommendations, "REDUCED_EMISSIONS")
    end

    SAMSIM_SEAD.State.siteThreatLevels[siteId] = threat
    return threat
end

-- ============================================================================
-- EMCON (Emission Control) Management
-- ============================================================================
SAMSIM_SEAD.EMCON = {}

function SAMSIM_SEAD.EMCON.recommend(siteId)
    local threat = SAMSIM_SEAD.State.siteThreatLevels[siteId]
    if not threat then
        threat = SAMSIM_SEAD.Threat.assess(siteId)
    end

    local recommendation = {
        siteId = siteId,
        action = "NORMAL",
        urgency = "LOW",
        reason = "",
        duration = 0,
    }

    -- Check for immediate ARM threat
    for _, factor in ipairs(threat.factors or {}) do
        if factor.type == "ARM_INBOUND" then
            if factor.tti and factor.tti < 30 then
                recommendation.action = "IMMEDIATE_SHUTDOWN"
                recommendation.urgency = "CRITICAL"
                recommendation.reason = "ARM impact in " .. math.floor(factor.tti) .. "s"
                recommendation.duration = factor.tti + 60
                break
            elseif factor.tti and factor.tti < 60 then
                recommendation.action = "SHUTDOWN"
                recommendation.urgency = "HIGH"
                recommendation.reason = "ARM approaching"
                recommendation.duration = 90
            end
        end
    end

    -- If no ARM, check jammer activity
    if recommendation.action == "NORMAL" then
        for _, factor in ipairs(threat.factors or {}) do
            if factor.type == "JAMMER_ACTIVE" and factor.range < 60000 then
                recommendation.action = "REDUCED_POWER"
                recommendation.urgency = "MODERATE"
                recommendation.reason = "Heavy jamming - consider EMCON"
            end
        end
    end

    SAMSIM_SEAD.State.emconRecommendations[siteId] = recommendation
    return recommendation
end

function SAMSIM_SEAD.EMCON.autoExecute(siteId, siteController)
    local recommendation = SAMSIM_SEAD.State.emconRecommendations[siteId]
    if not recommendation then return end

    if recommendation.action == "IMMEDIATE_SHUTDOWN" then
        if siteController and siteController.setRadarMode then
            siteController.setRadarMode(0)  -- OFF
            env.info("SEAD EMCON: Auto-shutdown " .. siteId .. " due to ARM threat")
        end
    end
end

-- ============================================================================
-- Damage System
-- ============================================================================
function SAMSIM_SEAD.applyDamage(siteId, component, severity)
    if not SAMSIM_SEAD.State.damage[siteId] then
        SAMSIM_SEAD.State.damage[siteId] = {
            radar = 1.0,
            launchers = 1.0,
            command = 1.0,
            overall = 1.0,
        }
    end

    local damage = SAMSIM_SEAD.State.damage[siteId]

    if component == "RADAR" then
        damage.radar = math.max(0, damage.radar - severity)
    elseif component == "LAUNCHER" then
        damage.launchers = math.max(0, damage.launchers - severity)
    elseif component == "COMMAND" then
        damage.command = math.max(0, damage.command - severity)
    elseif component == "GENERAL" then
        damage.overall = math.max(0, damage.overall - severity)
    end

    -- Check if site is destroyed
    if damage.radar <= 0 or damage.command <= 0 then
        damage.status = "DESTROYED"
        env.info("SEAD: Site " .. siteId .. " destroyed!")
    elseif damage.radar < 0.5 or damage.overall < 0.5 then
        damage.status = "HEAVILY_DAMAGED"
    elseif damage.overall < 0.8 then
        damage.status = "DAMAGED"
    else
        damage.status = "OPERATIONAL"
    end

    return damage
end

function SAMSIM_SEAD.getDamage(siteId)
    return SAMSIM_SEAD.State.damage[siteId]
end

-- ============================================================================
-- Notifications
-- ============================================================================
function SAMSIM_SEAD.notifyARMLaunch(siteId, arm)
    -- Store launch notification
    if not SAMSIM_SEAD.State.armLaunches[siteId] then
        SAMSIM_SEAD.State.armLaunches[siteId] = {}
    end

    table.insert(SAMSIM_SEAD.State.armLaunches[siteId], {
        time = timer.getTime(),
        armType = arm.type,
        armName = arm.name,
        tti = arm.timeToImpact,
        range = arm.range,
    })

    -- Trigger EMCON recommendation
    SAMSIM_SEAD.EMCON.recommend(siteId)
end

-- ============================================================================
-- Site State Interface
-- ============================================================================
function SAMSIM_SEAD.getSiteState(siteId)
    -- Would interface with SAMSIM.Unified to get site state
    -- Returns: position, emitting status, radar parameters
    if SAMSIM and SAMSIM.Unified and SAMSIM.Unified.Sites then
        local site = SAMSIM.Unified.Sites[siteId]
        if site then
            return {
                position = site.position,
                emitting = site.controller and site.controller.State and
                          site.controller.State.radar and
                          site.controller.State.radar.mode >= 2,
            }
        end
    end
    return nil
end

-- ============================================================================
-- Update Loop
-- ============================================================================
function SAMSIM_SEAD.update()
    -- Update ARM tracking
    SAMSIM_SEAD.ARM.update(0.1)

    -- Update threat assessments for all sites
    if SAMSIM and SAMSIM.Unified and SAMSIM.Unified.Sites then
        for siteId, _ in pairs(SAMSIM.Unified.Sites) do
            SAMSIM_SEAD.Threat.assess(siteId)
            SAMSIM_SEAD.EMCON.recommend(siteId)
        end
    end

    return timer.getTime() + 0.5
end

-- ============================================================================
-- Command Processing
-- ============================================================================
function SAMSIM_SEAD.processCommand(cmd)
    local cmdType = cmd.type

    if cmdType == "GET_THREAT_ASSESSMENT" then
        local threat = SAMSIM_SEAD.Threat.assess(cmd.siteId)
        return {success = true, threat = threat}

    elseif cmdType == "GET_EMCON_RECOMMENDATION" then
        local rec = SAMSIM_SEAD.EMCON.recommend(cmd.siteId)
        return {success = true, recommendation = rec}

    elseif cmdType == "GET_ARMS_INBOUND" then
        local arms = {}
        for _, arm in ipairs(SAMSIM_SEAD.State.armsInFlight) do
            if not cmd.siteId or arm.targetSite == cmd.siteId then
                table.insert(arms, arm)
            end
        end
        return {success = true, arms = arms}

    elseif cmdType == "GET_JAMMERS" then
        return {success = true, jammers = SAMSIM_SEAD.State.detectedJammers}

    elseif cmdType == "GET_DAMAGE" then
        return {success = true, damage = SAMSIM_SEAD.getDamage(cmd.siteId)}

    elseif cmdType == "AUTO_EMCON" then
        if cmd.enable then
            -- Enable auto EMCON for site
        else
            -- Disable auto EMCON
        end
        return {success = true}
    end

    return {success = false, message = "Unknown SEAD command"}
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM_SEAD.getStateForExport()
    return {
        module = "SEAD",
        version = SAMSIM_SEAD.Version,
        armsInFlight = SAMSIM_SEAD.State.armsInFlight,
        detectedJammers = SAMSIM_SEAD.State.detectedJammers,
        siteThreatLevels = SAMSIM_SEAD.State.siteThreatLevels,
        emconRecommendations = SAMSIM_SEAD.State.emconRecommendations,
        damage = SAMSIM_SEAD.State.damage,
    }
end

-- ============================================================================
-- Initialization
-- ============================================================================
function SAMSIM_SEAD.initialize()
    -- Start update loop
    timer.scheduleFunction(SAMSIM_SEAD.update, nil, timer.getTime() + 1)

    env.info("SAMSIM SEAD Module initialized - Version " .. SAMSIM_SEAD.Version)
end

env.info("SAMSIM SEAD Module loaded - Version " .. SAMSIM_SEAD.Version)
