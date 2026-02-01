--[[
    SAMSIM Electronic Warfare Module

    Simulates ECM/ECCM, IFF, and related electronic warfare effects

    Author: Claude Code
    Version: 1.0
]]

SAMSIM_EW = {}
SAMSIM_EW.Version = "1.0.0"

-- ============================================================================
-- ECM Types
-- ============================================================================
SAMSIM_EW.JammingType = {
    NONE = 0,
    NOISE_BARRAGE = 1,      -- Wideband noise jamming
    NOISE_SPOT = 2,         -- Narrowband noise jamming
    DECEPTIVE_RANGE = 3,    -- Range gate pull-off (RGPO)
    DECEPTIVE_VELOCITY = 4, -- Velocity gate pull-off (VGPO)
    CHAFF = 5,              -- Chaff corridor/cloud
    DRFM = 6,               -- Digital RF Memory (modern)
}

SAMSIM_EW.IFFMode = {
    OFF = 0,
    MODE_1 = 1,     -- Military only (2 digit)
    MODE_2 = 2,     -- Military only (4 digit)
    MODE_3A = 3,    -- Military/Civil (4 digit squawk)
    MODE_C = 4,     -- Altitude reporting
    MODE_4 = 5,     -- Encrypted military
    MODE_S = 6,     -- Selective interrogation
}

SAMSIM_EW.IFFResponse = {
    NONE = 0,
    FRIENDLY = 1,
    HOSTILE = 2,
    UNKNOWN = 3,
    PENDING = 4,
}

-- ============================================================================
-- ECM Emitter Database
-- ============================================================================
SAMSIM_EW.ECMDatabase = {
    -- Aircraft ECM pods/systems
    ["AN/ALQ-131"] = {
        type = "NOISE_SPOT",
        power_dbw = 30,
        bandwidth_mhz = 500,
        effective_vs = {"X", "S", "C"},
    },
    ["AN/ALQ-184"] = {
        type = "NOISE_BARRAGE",
        power_dbw = 32,
        bandwidth_mhz = 2000,
        effective_vs = {"X", "S", "C", "Ku"},
    },
    ["AN/ALQ-99"] = {
        type = "NOISE_BARRAGE",
        power_dbw = 40,
        bandwidth_mhz = 4000,
        effective_vs = {"X", "S", "C", "L"},
    },
    ["Sorbtsiya"] = {
        type = "DECEPTIVE_RANGE",
        power_dbw = 28,
        bandwidth_mhz = 1000,
        effective_vs = {"X", "S"},
    },
    ["Khibiny"] = {
        type = "DRFM",
        power_dbw = 35,
        bandwidth_mhz = 3000,
        effective_vs = {"X", "S", "C", "Ku"},
    },
    ["DEFAULT"] = {
        type = "NOISE_SPOT",
        power_dbw = 25,
        bandwidth_mhz = 500,
        effective_vs = {"X", "S"},
    },
}

-- ============================================================================
-- Configuration
-- ============================================================================
SAMSIM_EW.Config = {
    -- Burn-through calculation
    BURN_THROUGH_MARGIN_DB = 6,     -- Required S/J margin for detection

    -- ECCM effectiveness
    ECCM_FREQUENCY_AGILITY_GAIN = 8,    -- dB improvement
    ECCM_PULSE_COMPRESSION_GAIN = 10,   -- dB improvement
    ECCM_SIDELOBE_BLANKING_GAIN = 15,   -- dB improvement
    ECCM_MTI_GAIN = 6,                  -- dB improvement vs chaff

    -- Chaff
    CHAFF_BLOOM_TIME = 5,           -- Seconds for chaff to bloom
    CHAFF_DECAY_TIME = 60,          -- Seconds for chaff to decay
    CHAFF_FALL_RATE = 3,            -- m/s descent rate
    CHAFF_RCS_INITIAL = 100,        -- Initial RCS of chaff cloud

    -- IFF
    IFF_RANGE_MAX = 400000,         -- 400km IFF range
    IFF_RESPONSE_TIME = 0.5,        -- Seconds for response
    IFF_SIDELOBE_SUPPRESSION = true,

    -- Display
    STROBE_UPDATE_RATE = 0.1,       -- Seconds between strobe updates
}

-- ============================================================================
-- State
-- ============================================================================
SAMSIM_EW.State = {
    -- Active jammers in the environment
    jammers = {},

    -- Chaff clouds
    chaffClouds = {},

    -- IFF interrogations
    iffQueries = {},
    iffResponses = {},

    -- ECCM settings (per radar)
    eccmSettings = {},

    -- Jamming strobes for display
    jamStrobes = {},
}

-- ============================================================================
-- Utility Functions
-- ============================================================================
local function dbToLinear(db)
    return 10 ^ (db / 10)
end

local function linearToDb(linear)
    if linear <= 0 then return -100 end
    return 10 * math.log10(linear)
end

local function vectorMagnitude(v)
    return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z)
end

local function vectorSubtract(a, b)
    return {x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}
end

local function normalizeAngle(angle)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

-- ============================================================================
-- ECM Detection and Effects
-- ============================================================================

-- Check if a jammer is effective against a radar
function SAMSIM_EW.isJammerEffective(jammerType, radarBand)
    local ecmData = SAMSIM_EW.ECMDatabase[jammerType] or SAMSIM_EW.ECMDatabase["DEFAULT"]

    for _, band in ipairs(ecmData.effective_vs) do
        if band == radarBand then
            return true
        end
    end
    return false
end

-- Calculate jamming-to-signal ratio (J/S) at the radar
function SAMSIM_EW.calculateJS(radarPos, radarPower, radarGain, radarBand,
                                jammerPos, jammerType, targetRCS)
    local ecmData = SAMSIM_EW.ECMDatabase[jammerType] or SAMSIM_EW.ECMDatabase["DEFAULT"]

    -- Check band effectiveness
    if not SAMSIM_EW.isJammerEffective(jammerType, radarBand) then
        return -100  -- Jammer not effective
    end

    -- Range from radar to jammer
    local relPos = vectorSubtract(jammerPos, radarPos)
    local range = vectorMagnitude(relPos)

    -- Jammer power reaching radar (one-way propagation)
    -- Pj_received = Pj * Gj / (4 * pi * R^2)
    local jammerPower = dbToLinear(ecmData.power_dbw)
    local jammerGain = 10  -- Assume 10 dBi jammer antenna
    local pjReceived = jammerPower * dbToLinear(jammerGain) / (4 * math.pi * range^2)

    -- Signal power from target (two-way propagation)
    -- Ps = Pt * Gt * sigma / ((4*pi)^3 * R^4) * Gr
    local signalPower = radarPower * radarGain * targetRCS /
                        ((4 * math.pi)^3 * range^4) * radarGain

    -- J/S ratio in dB
    local jsRatio = linearToDb(pjReceived / signalPower)

    return jsRatio
end

-- Calculate burn-through range (range at which radar can see through jamming)
function SAMSIM_EW.calculateBurnThroughRange(radarPower, radarGain, radarBand,
                                              jammerType, targetRCS, eccmGain)
    local ecmData = SAMSIM_EW.ECMDatabase[jammerType] or SAMSIM_EW.ECMDatabase["DEFAULT"]

    if not SAMSIM_EW.isJammerEffective(jammerType, radarBand) then
        return math.huge  -- Can always see if jammer ineffective
    end

    local jammerPower = dbToLinear(ecmData.power_dbw)
    local jammerGain = 10
    local requiredSJ = dbToLinear(SAMSIM_EW.Config.BURN_THROUGH_MARGIN_DB - eccmGain)

    -- Burn-through range formula:
    -- R_bt = ((Pt * Gt^2 * sigma * lambda^2) / ((4*pi)^3 * Pj * Gj * S/J_req))^(1/4)
    -- Simplified:
    local numerator = radarPower * radarGain^2 * targetRCS
    local denominator = (4 * math.pi)^3 * jammerPower * dbToLinear(jammerGain) * requiredSJ

    local burnThroughRange = (numerator / denominator)^0.25

    return burnThroughRange
end

-- Update jammer detection for a radar system
function SAMSIM_EW.updateJammerDetection(radarId, radarPos, radarAzimuth, radarBeamWidth,
                                          radarBand, maxRange)
    local strobes = {}
    local currentTime = timer.getTime()

    -- Find all active jammers
    local airObjects = {}
    local sphere = {
        id = world.VolumeType.SPHERE,
        params = {point = radarPos, radius = maxRange}
    }

    world.searchObjects(Object.Category.UNIT, sphere, function(obj)
        if obj:getCategory() == Object.Category.UNIT then
            local desc = obj:getDesc()
            if desc.category == Unit.Category.AIRPLANE then
                table.insert(airObjects, obj)
            end
        end
        return true
    end)

    -- Check each aircraft for ECM capability
    for _, aircraft in ipairs(airObjects) do
        local pos = aircraft:getPoint()
        local relPos = vectorSubtract(pos, radarPos)
        local range = vectorMagnitude(relPos)
        local azimuth = math.deg(math.atan2(relPos.x, relPos.z))
        if azimuth < 0 then azimuth = azimuth + 360 end

        -- Check if aircraft has ECM (simplified - assume some aircraft types have ECM)
        local typeName = aircraft:getTypeName()
        local hasECM = SAMSIM_EW.aircraftHasECM(typeName)

        if hasECM then
            local jammerType = SAMSIM_EW.getAircraftECM(typeName)
            local ecmData = SAMSIM_EW.ECMDatabase[jammerType] or SAMSIM_EW.ECMDatabase["DEFAULT"]

            if SAMSIM_EW.isJammerEffective(jammerType, radarBand) then
                -- Calculate strobe width based on jammer power and range
                local jsRatio = ecmData.power_dbw - 20 * math.log10(range / 10000)
                local strobeWidth = math.min(30, math.max(5, jsRatio / 2))

                -- Add noise variation
                local noiseAz = (math.random() - 0.5) * 3

                table.insert(strobes, {
                    azimuth = azimuth + noiseAz,
                    width = strobeWidth,
                    intensity = math.min(1, jsRatio / 40),
                    range = range,
                    type = ecmData.type,
                    sourceId = aircraft:getID(),
                })
            end
        end
    end

    SAMSIM_EW.State.jamStrobes[radarId] = {
        strobes = strobes,
        timestamp = currentTime,
    }

    return strobes
end

-- Check if aircraft type has ECM
function SAMSIM_EW.aircraftHasECM(typeName)
    local ecmAircraft = {
        -- US/NATO
        ["F-16CM"] = true, ["F-16C_50"] = true,
        ["F-15E"] = true,
        ["FA-18C_hornet"] = true, ["F/A-18C"] = true,
        ["EA-18G"] = true,
        ["F-4E"] = true,
        ["Tornado"] = true,
        -- Russian
        ["Su-27"] = true, ["Su-33"] = true,
        ["Su-30"] = true, ["Su-35"] = true,
        ["Su-34"] = true,
        ["MiG-29A"] = true, ["MiG-29S"] = true,
        ["Su-25T"] = true, ["Su-25TM"] = true,
    }

    for pattern, _ in pairs(ecmAircraft) do
        if string.find(typeName, pattern) then
            return true
        end
    end
    return false
end

-- Get ECM type for aircraft
function SAMSIM_EW.getAircraftECM(typeName)
    local ecmMapping = {
        ["EA-18G"] = "AN/ALQ-99",
        ["F-16CM"] = "AN/ALQ-184",
        ["F-16C_50"] = "AN/ALQ-131",
        ["Su-34"] = "Khibiny",
        ["Su-35"] = "Khibiny",
        ["Su-30"] = "Sorbtsiya",
    }

    for pattern, ecm in pairs(ecmMapping) do
        if string.find(typeName, pattern) then
            return ecm
        end
    end
    return "DEFAULT"
end

-- ============================================================================
-- Chaff Simulation
-- ============================================================================

-- Create a chaff cloud
function SAMSIM_EW.createChaffCloud(position, velocity, rcs)
    local cloud = {
        id = #SAMSIM_EW.State.chaffClouds + 1,
        position = {x = position.x, y = position.y, z = position.z},
        velocity = {x = velocity.x * 0.3, y = -SAMSIM_EW.Config.CHAFF_FALL_RATE, z = velocity.z * 0.3},
        rcs = rcs or SAMSIM_EW.Config.CHAFF_RCS_INITIAL,
        createTime = timer.getTime(),
        age = 0,
    }

    table.insert(SAMSIM_EW.State.chaffClouds, cloud)
    return cloud.id
end

-- Update chaff clouds
function SAMSIM_EW.updateChaffClouds(dt)
    local currentTime = timer.getTime()
    local toRemove = {}

    for i, cloud in ipairs(SAMSIM_EW.State.chaffClouds) do
        cloud.age = currentTime - cloud.createTime

        -- Update position
        cloud.position.x = cloud.position.x + cloud.velocity.x * dt
        cloud.position.y = cloud.position.y + cloud.velocity.y * dt
        cloud.position.z = cloud.position.z + cloud.velocity.z * dt

        -- Decay RCS over time
        if cloud.age > SAMSIM_EW.Config.CHAFF_BLOOM_TIME then
            local decayFactor = 1 - (cloud.age - SAMSIM_EW.Config.CHAFF_BLOOM_TIME) /
                                    SAMSIM_EW.Config.CHAFF_DECAY_TIME
            cloud.rcs = SAMSIM_EW.Config.CHAFF_RCS_INITIAL * math.max(0, decayFactor)
        end

        -- Remove if too old or on ground
        if cloud.age > SAMSIM_EW.Config.CHAFF_DECAY_TIME or cloud.position.y < 0 then
            table.insert(toRemove, i)
        end
    end

    -- Remove expired clouds
    for i = #toRemove, 1, -1 do
        table.remove(SAMSIM_EW.State.chaffClouds, toRemove[i])
    end
end

-- Get chaff contacts for radar display
function SAMSIM_EW.getChaffContacts(radarPos, maxRange, mtiEnabled)
    local contacts = {}

    for _, cloud in ipairs(SAMSIM_EW.State.chaffClouds) do
        local relPos = vectorSubtract(cloud.position, radarPos)
        local range = vectorMagnitude(relPos)

        if range <= maxRange and cloud.rcs > 1 then
            local azimuth = math.deg(math.atan2(relPos.x, relPos.z))
            if azimuth < 0 then azimuth = azimuth + 360 end

            -- MTI reduces chaff visibility
            local effectiveRCS = cloud.rcs
            if mtiEnabled then
                effectiveRCS = effectiveRCS * 0.1  -- MTI reduces slow-moving chaff
            end

            if effectiveRCS > 1 then
                table.insert(contacts, {
                    id = "CHAFF_" .. cloud.id,
                    type = "CHAFF",
                    position = cloud.position,
                    range = range,
                    azimuth = azimuth,
                    altitude = cloud.position.y,
                    rcs = effectiveRCS,
                    velocity = cloud.velocity,
                })
            end
        end
    end

    return contacts
end

-- ============================================================================
-- IFF Simulation
-- ============================================================================

-- Initialize ECCM settings for a radar
function SAMSIM_EW.initECCM(radarId)
    SAMSIM_EW.State.eccmSettings[radarId] = {
        frequencyAgility = false,
        pulseCompression = false,
        sidelobeBlanking = true,
        stc = 0,        -- Sensitivity Time Control (0-100)
        ftc = 0,        -- Fast Time Constant (0-100)
        mti = false,    -- Moving Target Indication
        cfar = true,    -- Constant False Alarm Rate
    }
end

-- Get ECCM gain for a radar
function SAMSIM_EW.getECCMGain(radarId)
    local settings = SAMSIM_EW.State.eccmSettings[radarId]
    if not settings then return 0 end

    local gain = 0

    if settings.frequencyAgility then
        gain = gain + SAMSIM_EW.Config.ECCM_FREQUENCY_AGILITY_GAIN
    end
    if settings.pulseCompression then
        gain = gain + SAMSIM_EW.Config.ECCM_PULSE_COMPRESSION_GAIN
    end
    if settings.sidelobeBlanking then
        gain = gain + SAMSIM_EW.Config.ECCM_SIDELOBE_BLANKING_GAIN
    end

    return gain
end

-- Set ECCM parameter
function SAMSIM_EW.setECCM(radarId, parameter, value)
    if not SAMSIM_EW.State.eccmSettings[radarId] then
        SAMSIM_EW.initECCM(radarId)
    end

    SAMSIM_EW.State.eccmSettings[radarId][parameter] = value
end

-- Perform IFF interrogation
function SAMSIM_EW.interrogateIFF(radarId, targetId, targetPos, radarPos, mode)
    local currentTime = timer.getTime()

    -- Check range
    local relPos = vectorSubtract(targetPos, radarPos)
    local range = vectorMagnitude(relPos)

    if range > SAMSIM_EW.Config.IFF_RANGE_MAX then
        return SAMSIM_EW.IFFResponse.NONE
    end

    -- Create query
    local queryId = radarId .. "_" .. targetId .. "_" .. currentTime
    SAMSIM_EW.State.iffQueries[queryId] = {
        radarId = radarId,
        targetId = targetId,
        mode = mode or SAMSIM_EW.IFFMode.MODE_3A,
        queryTime = currentTime,
        status = "PENDING",
    }

    -- Simulate response (in real sim, would check aircraft's IFF transponder)
    -- For now, use coalition to determine response
    local target = nil

    -- Try to find the target unit
    local sphere = {
        id = world.VolumeType.SPHERE,
        params = {point = targetPos, radius = 100}
    }

    world.searchObjects(Object.Category.UNIT, sphere, function(obj)
        if obj:getID() == targetId then
            target = obj
        end
        return true
    end)

    local response = SAMSIM_EW.IFFResponse.UNKNOWN

    if target then
        local coalition = target:getCoalition()
        -- Assume radar belongs to red coalition for SAM sites
        -- In real implementation, would check actual SAM coalition
        if coalition == coalition.RED then
            response = SAMSIM_EW.IFFResponse.FRIENDLY
        elseif coalition == coalition.BLUE then
            response = SAMSIM_EW.IFFResponse.HOSTILE
        else
            response = SAMSIM_EW.IFFResponse.UNKNOWN
        end
    end

    -- Store response (with delay)
    SAMSIM_EW.State.iffResponses[targetId] = {
        response = response,
        mode = mode,
        responseTime = currentTime + SAMSIM_EW.Config.IFF_RESPONSE_TIME,
        valid = true,
        validUntil = currentTime + 30,  -- Response valid for 30 seconds
    }

    return response
end

-- Get IFF response for a target
function SAMSIM_EW.getIFFResponse(targetId)
    local response = SAMSIM_EW.State.iffResponses[targetId]
    local currentTime = timer.getTime()

    if not response then
        return SAMSIM_EW.IFFResponse.NONE
    end

    if currentTime < response.responseTime then
        return SAMSIM_EW.IFFResponse.PENDING
    end

    if currentTime > response.validUntil then
        return SAMSIM_EW.IFFResponse.NONE
    end

    return response.response
end

-- ============================================================================
-- State Export for UI
-- ============================================================================
function SAMSIM_EW.getStateForExport(radarId)
    local state = {
        jammingStrobes = {},
        chaffContacts = {},
        iffResponses = {},
        eccmSettings = SAMSIM_EW.State.eccmSettings[radarId] or {},
    }

    -- Jamming strobes
    local strobeData = SAMSIM_EW.State.jamStrobes[radarId]
    if strobeData then
        state.jammingStrobes = strobeData.strobes
    end

    -- Chaff contacts
    for _, cloud in ipairs(SAMSIM_EW.State.chaffClouds) do
        table.insert(state.chaffContacts, {
            id = cloud.id,
            position = cloud.position,
            rcs = cloud.rcs,
            age = cloud.age,
        })
    end

    -- IFF responses
    for targetId, response in pairs(SAMSIM_EW.State.iffResponses) do
        state.iffResponses[targetId] = {
            response = response.response,
            responseName = SAMSIM_EW.getIFFResponseName(response.response),
        }
    end

    return state
end

function SAMSIM_EW.getIFFResponseName(response)
    local names = {"NONE", "FRIENDLY", "HOSTILE", "UNKNOWN", "PENDING"}
    return names[response + 1] or "NONE"
end

-- ============================================================================
-- Command Processing
-- ============================================================================
function SAMSIM_EW.processCommand(cmd)
    local response = {success = false, message = "Unknown EW command"}

    if cmd.type == "SET_ECCM" then
        SAMSIM_EW.setECCM(cmd.radarId, cmd.parameter, cmd.value)
        response = {success = true, message = "ECCM " .. cmd.parameter .. " set"}

    elseif cmd.type == "IFF_INTERROGATE" then
        local result = SAMSIM_EW.interrogateIFF(cmd.radarId, cmd.targetId,
                                                 cmd.targetPos, cmd.radarPos, cmd.mode)
        response = {success = true, response = result,
                   message = "IFF: " .. SAMSIM_EW.getIFFResponseName(result)}

    elseif cmd.type == "DROP_CHAFF" then
        local id = SAMSIM_EW.createChaffCloud(cmd.position, cmd.velocity, cmd.rcs)
        response = {success = true, message = "Chaff deployed", chaffId = id}
    end

    return response
end

-- ============================================================================
-- Update Loop
-- ============================================================================
function SAMSIM_EW.update(dt)
    SAMSIM_EW.updateChaffClouds(dt)
end

env.info("SAMSIM Electronic Warfare Module loaded - Version " .. SAMSIM_EW.Version)
