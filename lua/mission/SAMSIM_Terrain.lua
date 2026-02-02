--[[
    SAMSIM Terrain Effects Module
    Phase 2: Terrain masking and ground clutter simulation

    Features:
    - Line-of-sight (LOS) terrain masking calculation
    - Ground clutter simulation based on terrain type
    - Multipath effects
    - Weather effects on radar propagation
    - Horizon calculation
]]

SAMSIM_Terrain = {}

-- Terrain types and their radar reflectivity (dB)
SAMSIM_Terrain.TerrainType = {
    WATER = { name = "Water", clutter = -20, smooth = true },
    FLAT = { name = "Flat/Desert", clutter = -15, smooth = true },
    FARMLAND = { name = "Farmland", clutter = -10, smooth = false },
    FOREST = { name = "Forest", clutter = 0, smooth = false },
    URBAN = { name = "Urban", clutter = 10, smooth = false },
    MOUNTAIN = { name = "Mountain", clutter = 5, smooth = false },
}

-- Weather conditions
SAMSIM_Terrain.Weather = {
    CLEAR = { name = "Clear", attenuation = 0, clutterMod = 0 },
    RAIN_LIGHT = { name = "Light Rain", attenuation = 0.01, clutterMod = 5 },
    RAIN_HEAVY = { name = "Heavy Rain", attenuation = 0.05, clutterMod = 15 },
    SNOW = { name = "Snow", attenuation = 0.02, clutterMod = 10 },
    FOG = { name = "Fog", attenuation = 0.03, clutterMod = 3 },
}

-- Constants
SAMSIM_Terrain.EARTH_RADIUS = 6371000  -- meters
SAMSIM_Terrain.RADAR_HORIZON_FACTOR = 1.33  -- 4/3 Earth model for radar


--[[
    Line of Sight (LOS) calculation
]]
SAMSIM_Terrain.LOS = {}

-- Check if there is line of sight between radar and target
function SAMSIM_Terrain.LOS:check(radarPos, targetPos, options)
    options = options or {}
    local samples = options.samples or 20
    local margin = options.margin or 50  -- meters margin for terrain clearance

    -- Get altitudes
    local radarAlt = radarPos.y
    local targetAlt = targetPos.y

    -- Calculate horizontal distance
    local dx = targetPos.x - radarPos.x
    local dz = targetPos.z - radarPos.z
    local horizontalDist = math.sqrt(dx*dx + dz*dz)

    -- Check radar horizon first
    local horizonRange = self:calculateHorizonRange(radarAlt, targetAlt)
    if horizontalDist > horizonRange then
        return false, "Beyond radar horizon", horizontalDist - horizonRange
    end

    -- Sample terrain along the path
    local blocked = false
    local blockingHeight = 0
    local blockingDistance = 0

    for i = 1, samples do
        local t = i / (samples + 1)
        local sampleX = radarPos.x + dx * t
        local sampleZ = radarPos.z + dz * t
        local sampleDist = horizontalDist * t

        -- Get terrain height at sample point
        local terrainHeight = self:getTerrainHeight(sampleX, sampleZ)

        -- Calculate LOS height at this distance
        local losHeight = radarAlt + (targetAlt - radarAlt) * t

        -- Account for Earth curvature
        local curvatureDrop = self:calculateCurvatureDrop(sampleDist)
        losHeight = losHeight - curvatureDrop

        -- Check if terrain blocks LOS
        if terrainHeight + margin > losHeight then
            blocked = true
            local blockHeight = terrainHeight + margin - losHeight
            if blockHeight > blockingHeight then
                blockingHeight = blockHeight
                blockingDistance = sampleDist
            end
        end
    end

    if blocked then
        return false, "Terrain masked", blockingHeight, blockingDistance
    end

    return true, "Clear LOS"
end

-- Calculate radar horizon range
function SAMSIM_Terrain.LOS:calculateHorizonRange(radarAlt, targetAlt)
    local factor = SAMSIM_Terrain.RADAR_HORIZON_FACTOR
    local R = SAMSIM_Terrain.EARTH_RADIUS

    -- Distance to radar horizon from both positions
    local d1 = math.sqrt(2 * R * factor * radarAlt + radarAlt * radarAlt)
    local d2 = math.sqrt(2 * R * factor * targetAlt + targetAlt * targetAlt)

    return d1 + d2
end

-- Calculate Earth curvature drop at distance
function SAMSIM_Terrain.LOS:calculateCurvatureDrop(distance)
    local R = SAMSIM_Terrain.EARTH_RADIUS * SAMSIM_Terrain.RADAR_HORIZON_FACTOR
    return distance * distance / (2 * R)
end

-- Get terrain height at position (uses DCS terrain API)
function SAMSIM_Terrain.LOS:getTerrainHeight(x, z)
    -- Use DCS land.getHeight function
    if land and land.getHeight then
        return land.getHeight({x = x, y = z})
    end
    return 0  -- Fallback if terrain API not available
end

-- Get minimum safe altitude for a flight path
function SAMSIM_Terrain.LOS:getMinSafeAltitude(startPos, endPos, margin)
    margin = margin or 100
    local samples = 50

    local dx = endPos.x - startPos.x
    local dz = endPos.z - startPos.z
    local maxHeight = 0

    for i = 0, samples do
        local t = i / samples
        local x = startPos.x + dx * t
        local z = startPos.z + dz * t
        local height = self:getTerrainHeight(x, z)
        if height > maxHeight then
            maxHeight = height
        end
    end

    return maxHeight + margin
end


--[[
    Ground Clutter Simulation
]]
SAMSIM_Terrain.Clutter = {}

-- Calculate ground clutter level at a position
function SAMSIM_Terrain.Clutter:getClutterLevel(radarPos, targetPos, radarParams)
    radarParams = radarParams or {}

    local beamWidth = radarParams.beamWidth or 2  -- degrees
    local frequency = radarParams.frequency or 3000  -- MHz
    local pulseWidth = radarParams.pulseWidth or 1  -- microseconds
    local mtiEnabled = radarParams.mtiEnabled or false
    local stcLevel = radarParams.stcLevel or 0

    -- Calculate geometry
    local dx = targetPos.x - radarPos.x
    local dz = targetPos.z - radarPos.z
    local horizontalDist = math.sqrt(dx*dx + dz*dz)
    local elevationAngle = math.deg(math.atan2(targetPos.y - radarPos.y, horizontalDist))

    -- Get terrain type in the beam footprint
    local terrainType = self:getTerrainType(targetPos.x, targetPos.z)

    -- Base clutter level from terrain type
    local clutterLevel = terrainType.clutter

    -- Adjust for grazing angle (low angles = more clutter)
    if elevationAngle < 5 then
        clutterLevel = clutterLevel + (5 - elevationAngle) * 3
    end

    -- Adjust for range (clutter cell size increases with range)
    local rangeKm = horizontalDist / 1000
    clutterLevel = clutterLevel + math.log10(rangeKm + 1) * 5

    -- Frequency adjustment (higher freq = more clutter detail)
    if frequency > 6000 then
        clutterLevel = clutterLevel + 3
    elseif frequency < 1000 then
        clutterLevel = clutterLevel - 5
    end

    -- MTI reduction
    if mtiEnabled then
        -- MTI reduces stationary clutter but not moving targets
        clutterLevel = clutterLevel - 25
    end

    -- STC (Sensitivity Time Control) reduction
    if stcLevel > 0 then
        -- STC reduces near-range clutter
        local stcReduction = stcLevel * (1 - rangeKm / 50)
        if stcReduction > 0 then
            clutterLevel = clutterLevel - stcReduction * 0.3
        end
    end

    -- Weather effects
    local weather = self:getCurrentWeather()
    clutterLevel = clutterLevel + weather.clutterMod

    return math.max(-30, clutterLevel)  -- Minimum -30 dB
end

-- Get terrain type at position
function SAMSIM_Terrain.Clutter:getTerrainType(x, z)
    -- Use DCS terrain type API if available
    if land and land.getSurfaceType then
        local surfaceType = land.getSurfaceType({x = x, y = z})

        -- Map DCS surface types to our terrain types
        if surfaceType == land.SurfaceType.WATER then
            return SAMSIM_Terrain.TerrainType.WATER
        elseif surfaceType == land.SurfaceType.ROAD or
               surfaceType == land.SurfaceType.RUNWAY then
            return SAMSIM_Terrain.TerrainType.URBAN
        elseif surfaceType == land.SurfaceType.SHALLOW_WATER then
            return SAMSIM_Terrain.TerrainType.WATER
        end
    end

    -- Check terrain height variation as proxy for terrain roughness
    local height = SAMSIM_Terrain.LOS:getTerrainHeight(x, z)
    local heightNearby = SAMSIM_Terrain.LOS:getTerrainHeight(x + 100, z + 100)
    local variation = math.abs(height - heightNearby)

    if variation > 50 then
        return SAMSIM_Terrain.TerrainType.MOUNTAIN
    elseif variation > 20 then
        return SAMSIM_Terrain.TerrainType.FOREST
    elseif height < 10 then
        return SAMSIM_Terrain.TerrainType.FLAT
    else
        return SAMSIM_Terrain.TerrainType.FARMLAND
    end
end

-- Get current weather conditions
function SAMSIM_Terrain.Clutter:getCurrentWeather()
    -- Try to get weather from DCS mission environment
    if env and env.mission and env.mission.weather then
        local clouds = env.mission.weather.clouds
        local fog = env.mission.weather.fog

        if fog and fog.visibility < 1000 then
            return SAMSIM_Terrain.Weather.FOG
        end

        if clouds and clouds.iprecptns then
            if clouds.iprecptns == 1 then
                return SAMSIM_Terrain.Weather.RAIN_LIGHT
            elseif clouds.iprecptns == 2 then
                return SAMSIM_Terrain.Weather.RAIN_HEAVY
            end
        end
    end

    return SAMSIM_Terrain.Weather.CLEAR
end

-- Calculate signal attenuation due to weather
function SAMSIM_Terrain.Clutter:getWeatherAttenuation(distance)
    local weather = self:getCurrentWeather()
    return weather.attenuation * (distance / 1000)  -- dB per km
end


--[[
    Multipath Effects
]]
SAMSIM_Terrain.Multipath = {}

-- Calculate multipath fading factor
function SAMSIM_Terrain.Multipath:calculateFading(radarPos, targetPos, frequency)
    frequency = frequency or 3000  -- MHz

    local dx = targetPos.x - radarPos.x
    local dz = targetPos.z - radarPos.z
    local horizontalDist = math.sqrt(dx*dx + dz*dz)

    local radarHeight = radarPos.y - SAMSIM_Terrain.LOS:getTerrainHeight(radarPos.x, radarPos.z)
    local targetHeight = targetPos.y - SAMSIM_Terrain.LOS:getTerrainHeight(targetPos.x, targetPos.z)

    -- Calculate wavelength
    local wavelength = 300 / frequency  -- meters (c / f)

    -- Calculate path difference for surface reflection
    local directPath = math.sqrt(horizontalDist^2 + (targetHeight - radarHeight)^2)
    local reflectedPath = math.sqrt(horizontalDist^2 + (targetHeight + radarHeight)^2)
    local pathDiff = reflectedPath - directPath

    -- Phase difference
    local phaseDiff = (2 * math.pi * pathDiff) / wavelength

    -- Fading factor (0 to 2, where 1 is no effect)
    -- Simplified model assuming smooth surface reflection
    local reflectionCoeff = 0.5  -- Typical ground reflection

    local terrainType = SAMSIM_Terrain.Clutter:getTerrainType(targetPos.x, targetPos.z)
    if terrainType.smooth then
        reflectionCoeff = 0.8
    else
        reflectionCoeff = 0.3
    end

    local fadingFactor = math.abs(1 + reflectionCoeff * math.cos(phaseDiff))

    -- Very low altitudes experience strong multipath nulls
    if targetHeight < 100 and math.abs(math.sin(phaseDiff)) < 0.3 then
        fadingFactor = fadingFactor * 0.3  -- Deep null
    end

    return fadingFactor
end

-- Check if target is in a multipath null
function SAMSIM_Terrain.Multipath:isInNull(radarPos, targetPos, frequency)
    local fadingFactor = self:calculateFading(radarPos, targetPos, frequency)
    return fadingFactor < 0.3
end


--[[
    Terrain Masking Map Generator
]]
SAMSIM_Terrain.MaskingMap = {}

-- Generate a terrain masking map for a radar position
function SAMSIM_Terrain.MaskingMap:generate(radarPos, config)
    config = config or {}
    local maxRange = config.maxRange or 100000  -- meters
    local resolution = config.resolution or 1000  -- meters per cell
    local altitudes = config.altitudes or {100, 500, 1000, 3000, 5000, 10000}

    local map = {
        radarPos = radarPos,
        maxRange = maxRange,
        resolution = resolution,
        cells = {},
    }

    local numCells = math.floor(maxRange / resolution)

    for az = 0, 359, 2 do  -- 2-degree resolution
        map.cells[az] = {}

        for r = 1, numCells do
            local range = r * resolution
            local azRad = math.rad(az)

            local targetX = radarPos.x + math.sin(azRad) * range
            local targetZ = radarPos.z + math.cos(azRad) * range

            map.cells[az][r] = {}

            for _, alt in ipairs(altitudes) do
                local targetPos = {
                    x = targetX,
                    y = SAMSIM_Terrain.LOS:getTerrainHeight(targetX, targetZ) + alt,
                    z = targetZ,
                }

                local visible, reason = SAMSIM_Terrain.LOS:check(radarPos, targetPos)
                map.cells[az][r][alt] = visible
            end
        end
    end

    return map
end

-- Check visibility using pre-generated map
function SAMSIM_Terrain.MaskingMap:checkVisibility(map, azimuth, range, altitude)
    local azKey = math.floor(azimuth / 2) * 2
    local rangeKey = math.floor(range / map.resolution)

    if azKey < 0 then azKey = azKey + 360 end
    if azKey >= 360 then azKey = azKey - 360 end

    if not map.cells[azKey] or not map.cells[azKey][rangeKey] then
        return true  -- Assume visible if no data
    end

    -- Find closest altitude
    local altKey = 100
    for alt, _ in pairs(map.cells[azKey][rangeKey]) do
        if math.abs(alt - altitude) < math.abs(altKey - altitude) then
            altKey = alt
        end
    end

    return map.cells[azKey][rangeKey][altKey]
end


--[[
    Integration with SAM systems
]]
SAMSIM_Terrain.Integration = {}

-- Apply terrain effects to a contact
function SAMSIM_Terrain.Integration:processContact(contact, radarPos, radarParams)
    local result = {
        visible = true,
        clutterLevel = -30,
        multipathFading = 1,
        weatherAttenuation = 0,
        terrainMasked = false,
        inMultipathNull = false,
    }

    local targetPos = {
        x = contact.x or contact.position.x,
        y = contact.y or contact.altitude or contact.position.y,
        z = contact.z or contact.position.z,
    }

    -- Check LOS
    local visible, reason, blockHeight = SAMSIM_Terrain.LOS:check(radarPos, targetPos)
    result.visible = visible
    result.terrainMasked = not visible
    result.maskingReason = reason

    if not visible then
        return result
    end

    -- Calculate clutter level
    result.clutterLevel = SAMSIM_Terrain.Clutter:getClutterLevel(radarPos, targetPos, radarParams)

    -- Calculate multipath effects
    local frequency = radarParams.frequency or 3000
    result.multipathFading = SAMSIM_Terrain.Multipath:calculateFading(radarPos, targetPos, frequency)
    result.inMultipathNull = result.multipathFading < 0.3

    -- Calculate weather attenuation
    local distance = math.sqrt(
        (targetPos.x - radarPos.x)^2 +
        (targetPos.y - radarPos.y)^2 +
        (targetPos.z - radarPos.z)^2
    )
    result.weatherAttenuation = SAMSIM_Terrain.Clutter:getWeatherAttenuation(distance)

    return result
end

-- Calculate detection probability considering terrain effects
function SAMSIM_Terrain.Integration:calculateDetectionProb(contact, radarPos, radarParams, baseProb)
    local effects = self:processContact(contact, radarPos, radarParams)

    if not effects.visible then
        return 0  -- Terrain masked
    end

    local prob = baseProb or 0.9

    -- Clutter reduction (if target RCS is not much higher than clutter)
    local targetRCS = contact.rcs or 5  -- m^2
    local targetRCS_dB = 10 * math.log10(targetRCS)
    local signalToClutter = targetRCS_dB - effects.clutterLevel

    if signalToClutter < 10 then
        prob = prob * (signalToClutter / 10)
    end

    -- Multipath effects
    prob = prob * effects.multipathFading

    -- Weather attenuation
    prob = prob * (10 ^ (-effects.weatherAttenuation / 10))

    return math.max(0, math.min(1, prob))
end


env.info("[SAMSIM] Terrain effects module loaded")
