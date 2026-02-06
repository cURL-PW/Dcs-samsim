--[[
    SAMSIM Configuration Module
    Unified configuration for all SAM systems and IADS

    Author: Claude Code
    Version: 1.0.0
]]

SAMSIM_Config = {}
SAMSIM_Config.Version = "1.0.0"

-- ============================================================================
-- Global Settings
-- ============================================================================
SAMSIM_Config.Global = {
    debug = false,
    updateInterval = 1.0,          -- Base update interval (seconds)
    threatTrackTimeout = 30,       -- Seconds before track is considered lost
    networkSyncInterval = 2.0,     -- IADS network sync interval (seconds)
    weaponCheckInterval = 0.5,     -- Weapon tracking interval (seconds)
    enableWebSocket = true,        -- Enable WebSocket communication
    webSocketPort = 12080,         -- WebSocket server port
}

-- ============================================================================
-- SAM System Definitions
-- ============================================================================
SAMSIM_Config.SAMTypes = {
    -- ========================================================================
    -- Eastern/Soviet Systems
    -- ========================================================================
    SA2 = {
        name = "SA-2 Guideline",
        natoName = "Guideline",
        origin = "USSR",
        category = "LONG_RANGE",

        -- Unit type names in DCS
        units = {
            searchRadar = {"p-19 s-125 sr", "RLS_19J6"},
            trackRadar = {"SNR_75V", "snr s-125 tr"},
            launcher = {"S_75M_Volhov"},
            command = {"SNR_75V"},
        },

        -- SEAD suppression parameters
        suppression = {
            rate = 0.7,             -- 70% chance of suppression on ARM launch
            minOffDelay = 30,       -- Min radar off time (seconds)
            maxOffDelay = 90,       -- Max radar off time
            minOnDelay = 60,        -- Min time before restart
            maxOnDelay = 180,       -- Max time before restart
        },

        -- Radar parameters
        radar = {
            searchRange = 160000,   -- 160km
            trackRange = 75000,     -- 75km
            engageRange = 40000,    -- 40km max engagement
            minAltitude = 500,      -- 500m minimum
            maxAltitude = 30000,    -- 30km ceiling
            frequency = {2965, 2975}, -- MHz (Fan Song)
        },

        -- Missile parameters
        missile = {
            type = "V-750",
            maxRange = 45000,
            minRange = 7000,
            maxSpeed = 1100,        -- m/s
            guidance = "COMMAND",
            salvoSize = 1,
        },
    },

    SA3 = {
        name = "SA-3 Goa",
        natoName = "Goa",
        origin = "USSR",
        category = "MEDIUM_RANGE",

        units = {
            searchRadar = {"p-19 s-125 sr"},
            trackRadar = {"snr s-125 tr"},
            launcher = {"5p73 s-125 ln"},
            command = {"snr s-125 tr"},
        },

        suppression = {
            rate = 0.65,
            minOffDelay = 25,
            maxOffDelay = 70,
            minOnDelay = 45,
            maxOnDelay = 150,
        },

        radar = {
            searchRange = 110000,
            trackRange = 65000,
            engageRange = 25000,
            minAltitude = 200,
            maxAltitude = 18000,
            frequency = {6000, 6200},
        },

        missile = {
            type = "V-601P",
            maxRange = 25000,
            minRange = 3500,
            maxSpeed = 900,
            guidance = "SARH",
            salvoSize = 2,
        },
    },

    SA6 = {
        name = "SA-6 Gainful",
        natoName = "Gainful",
        origin = "USSR",
        category = "MEDIUM_RANGE",

        units = {
            searchRadar = {"Kub 1S91 str"},
            trackRadar = {"Kub 1S91 str"},  -- Combined search/track
            launcher = {"Kub 2P25 ln"},
            command = {"Kub 1S91 str"},
        },

        suppression = {
            rate = 0.6,
            minOffDelay = 20,
            maxOffDelay = 60,
            minOnDelay = 40,
            maxOnDelay = 120,
        },

        radar = {
            searchRange = 75000,
            trackRange = 28000,
            engageRange = 24000,
            minAltitude = 50,
            maxAltitude = 14000,
            frequency = {6400, 6700},
        },

        missile = {
            type = "3M9",
            maxRange = 24000,
            minRange = 4000,
            maxSpeed = 850,
            guidance = "SARH",
            salvoSize = 3,
        },
    },

    SA10 = {
        name = "SA-10 Grumble",
        natoName = "Grumble",
        origin = "USSR",
        category = "LONG_RANGE",

        units = {
            searchRadar = {"S-300PS 40B6MD sr", "S-300PS 64H6E sr"},
            trackRadar = {"S-300PS 40B6M tr"},
            launcher = {"S-300PS 5P85C ln", "S-300PS 5P85D ln"},
            command = {"S-300PS 54K6 cp"},
        },

        suppression = {
            rate = 0.4,             -- More resistant to SEAD
            minOffDelay = 15,
            maxOffDelay = 45,
            minOnDelay = 30,
            maxOnDelay = 90,
        },

        radar = {
            searchRange = 300000,
            trackRange = 200000,
            engageRange = 150000,
            minAltitude = 25,
            maxAltitude = 30000,
            frequency = {5000, 5500},
            phasedArray = true,
        },

        missile = {
            type = "5V55R",
            maxRange = 150000,
            minRange = 5000,
            maxSpeed = 2000,
            guidance = "TVM",
            salvoSize = 2,
            maxSimultaneous = 6,
        },
    },

    SA11 = {
        name = "SA-11 Gadfly",
        natoName = "Gadfly",
        origin = "USSR",
        category = "MEDIUM_RANGE",

        units = {
            searchRadar = {"SA-11 Buk SR 9S18M1"},
            trackRadar = {"SA-11 Buk LN 9A310M1"},  -- TELAR has own radar
            launcher = {"SA-11 Buk LN 9A310M1"},
            command = {"SA-11 Buk CC 9S470M1"},
        },

        suppression = {
            rate = 0.5,
            minOffDelay = 15,
            maxOffDelay = 50,
            minOnDelay = 35,
            maxOnDelay = 100,
        },

        radar = {
            searchRange = 140000,
            trackRange = 70000,
            engageRange = 35000,
            minAltitude = 15,
            maxAltitude = 22000,
            frequency = {8000, 8500},
        },

        missile = {
            type = "9M38",
            maxRange = 35000,
            minRange = 3000,
            maxSpeed = 1230,
            guidance = "SARH",
            salvoSize = 2,
        },
    },

    SA8 = {
        name = "SA-8 Gecko",
        natoName = "Gecko",
        origin = "USSR",
        category = "SHORT_RANGE",

        units = {
            searchRadar = {"Osa 9A33 ln"},
            trackRadar = {"Osa 9A33 ln"},
            launcher = {"Osa 9A33 ln"},
            command = {"Osa 9A33 ln"},
        },

        suppression = {
            rate = 0.55,
            minOffDelay = 10,
            maxOffDelay = 40,
            minOnDelay = 25,
            maxOnDelay = 80,
        },

        radar = {
            searchRange = 30000,
            trackRange = 20000,
            engageRange = 10000,
            minAltitude = 25,
            maxAltitude = 5000,
            frequency = {6000, 8000},
        },

        missile = {
            type = "9M33",
            maxRange = 10000,
            minRange = 1500,
            maxSpeed = 500,
            guidance = "RADIO_COMMAND",
            salvoSize = 2,
        },
    },

    SA15 = {
        name = "SA-15 Gauntlet",
        natoName = "Gauntlet",
        origin = "USSR",
        category = "SHORT_RANGE",

        units = {
            searchRadar = {"Tor 9A331"},
            trackRadar = {"Tor 9A331"},
            launcher = {"Tor 9A331"},
            command = {"Tor 9A331"},
        },

        suppression = {
            rate = 0.35,            -- Very resistant
            minOffDelay = 8,
            maxOffDelay = 30,
            minOnDelay = 20,
            maxOnDelay = 60,
        },

        radar = {
            searchRange = 25000,
            trackRange = 20000,
            engageRange = 12000,
            minAltitude = 10,
            maxAltitude = 6000,
            frequency = {14000, 15000},
            phasedArray = true,
        },

        missile = {
            type = "9M331",
            maxRange = 12000,
            minRange = 1000,
            maxSpeed = 850,
            guidance = "RADIO_COMMAND",
            salvoSize = 2,
            maxSimultaneous = 2,
        },
    },

    SA19 = {
        name = "SA-19 Grison",
        natoName = "Grison",
        origin = "USSR",
        category = "SHORT_RANGE",

        units = {
            searchRadar = {"2S6 Tunguska"},
            trackRadar = {"2S6 Tunguska"},
            launcher = {"2S6 Tunguska"},
            command = {"2S6 Tunguska"},
        },

        suppression = {
            rate = 0.45,
            minOffDelay = 5,
            maxOffDelay = 25,
            minOnDelay = 15,
            maxOnDelay = 50,
        },

        radar = {
            searchRange = 18000,
            trackRange = 16000,
            engageRange = 8000,
            minAltitude = 0,
            maxAltitude = 3500,
            frequency = {14000, 16000},
        },

        missile = {
            type = "9M311",
            maxRange = 8000,
            minRange = 1500,
            maxSpeed = 900,
            guidance = "RADIO_COMMAND",
            salvoSize = 2,
        },

        gun = {
            type = "2A38M",
            caliber = 30,
            rateOfFire = 5000,
            range = 4000,
        },
    },

    -- ========================================================================
    -- Western Systems
    -- ========================================================================
    PATRIOT = {
        name = "MIM-104 Patriot",
        natoName = "Patriot",
        origin = "USA",
        category = "LONG_RANGE",

        units = {
            searchRadar = {"Patriot str"},
            trackRadar = {"Patriot str"},
            launcher = {"Patriot ln"},
            command = {"Patriot cp", "Patriot ECS"},
        },

        suppression = {
            rate = 0.3,             -- Very resistant (phased array)
            minOffDelay = 10,
            maxOffDelay = 35,
            minOnDelay = 25,
            maxOnDelay = 70,
        },

        radar = {
            searchRange = 170000,
            trackRange = 100000,
            engageRange = 70000,
            minAltitude = 60,
            maxAltitude = 24000,
            frequency = {5400, 5900},
            phasedArray = true,
        },

        missile = {
            PAC2 = {
                type = "MIM-104C",
                maxRange = 160000,
                minRange = 3000,
                maxSpeed = 1700,
                guidance = "TVM",
            },
            PAC3 = {
                type = "MIM-104F",
                maxRange = 35000,
                minRange = 1000,
                maxSpeed = 2000,
                guidance = "ARH",
            },
        },

        maxSimultaneous = 9,
    },

    HAWK = {
        name = "MIM-23 HAWK",
        natoName = "HAWK",
        origin = "USA",
        category = "MEDIUM_RANGE",

        units = {
            searchRadar = {"Hawk pcp", "Hawk sr"},
            trackRadar = {"Hawk tr"},
            launcher = {"Hawk ln"},
            command = {"Hawk pcp"},
        },

        suppression = {
            rate = 0.55,
            minOffDelay = 15,
            maxOffDelay = 50,
            minOnDelay = 35,
            maxOnDelay = 100,
        },

        radar = {
            searchRange = 100000,
            trackRange = 60000,
            engageRange = 40000,
            minAltitude = 60,
            maxAltitude = 18000,
            frequency = {8000, 9000},
        },

        missile = {
            type = "MIM-23B",
            maxRange = 40000,
            minRange = 2000,
            maxSpeed = 900,
            guidance = "SARH",
            salvoSize = 2,
        },
    },

    ROLAND = {
        name = "Roland 2/3",
        natoName = "Roland",
        origin = "France/Germany",
        category = "SHORT_RANGE",

        units = {
            searchRadar = {"Roland ADS", "Roland Radar"},
            trackRadar = {"Roland ADS", "Roland Radar"},
            launcher = {"Roland ADS"},
            command = {"Roland ADS"},
        },

        suppression = {
            rate = 0.5,
            minOffDelay = 10,
            maxOffDelay = 40,
            minOnDelay = 20,
            maxOnDelay = 70,
        },

        radar = {
            searchRange = 18000,
            trackRange = 16000,
            engageRange = 8000,
            minAltitude = 20,
            maxAltitude = 6000,
            frequency = {9000, 10000},
        },

        missile = {
            type = "Roland 2",
            maxRange = 8000,
            minRange = 500,
            maxSpeed = 570,
            guidance = "SACLOS",
            salvoSize = 2,
        },

        opticalTracking = true,
    },
}

-- ============================================================================
-- EWR Definitions
-- ============================================================================
SAMSIM_Config.EWRTypes = {
    ["1L13 EWR"] = {
        name = "1L13 Box Spring",
        range = 300000,
        altitude = 30000,
        frequency = {150, 180},
    },
    ["55G6 EWR"] = {
        name = "55G6 Nebo",
        range = 400000,
        altitude = 40000,
        frequency = {160, 200},
    },
    ["EWR P-37 BAR LOCK"] = {
        name = "P-37 Bar Lock",
        range = 350000,
        altitude = 35000,
        frequency = {2800, 3100},
    },
    ["FPS-117"] = {
        name = "AN/FPS-117",
        range = 450000,
        altitude = 30000,
        frequency = {1215, 1400},
    },
}

-- ============================================================================
-- ARM (Anti-Radiation Missile) Definitions
-- ============================================================================
SAMSIM_Config.ARMTypes = {
    -- Western
    AGM_88 = {
        name = "AGM-88 HARM",
        weapons = {"AGM_88", "weapons.missiles.AGM_88"},
        maxRange = 150000,
        speed = 680,
        seeker = {
            sensitivity = -60,
            bandwidth = {2000, 18000},
            fov = 45,
            memoryTime = 30,
        },
    },
    AGM_45 = {
        name = "AGM-45 Shrike",
        weapons = {"AGM_45", "AGM_45A", "AGM_45B"},
        maxRange = 40000,
        speed = 680,
        seeker = {
            sensitivity = -50,
            bandwidth = {1000, 10000},
            fov = 25,
            memoryTime = 5,
        },
    },
    ALARM = {
        name = "ALARM",
        weapons = {"ALARM"},
        maxRange = 93000,
        speed = 760,
        seeker = {
            sensitivity = -55,
            bandwidth = {2000, 40000},
            fov = 360,
            memoryTime = 60,
            loiter = true,
        },
    },
    LD_10 = {
        name = "LD-10",
        weapons = {"LD-10"},
        maxRange = 80000,
        speed = 1200,
        seeker = {
            sensitivity = -58,
            bandwidth = {2000, 18000},
            fov = 40,
            memoryTime = 25,
        },
    },

    -- Eastern
    Kh_58 = {
        name = "Kh-58U",
        weapons = {"X_58", "Kh58U"},
        maxRange = 120000,
        speed = 1200,
        seeker = {
            sensitivity = -52,
            bandwidth = {1200, 11000},
            fov = 30,
            memoryTime = 15,
        },
    },
    Kh_31P = {
        name = "Kh-31P",
        weapons = {"X_31P", "Kh31P"},
        maxRange = 110000,
        speed = 1000,
        seeker = {
            sensitivity = -55,
            bandwidth = {5000, 15000},
            fov = 30,
            memoryTime = 20,
        },
    },
    Kh_25MPU = {
        name = "Kh-25MPU",
        weapons = {"X_25MPU", "Kh25MPU"},
        maxRange = 40000,
        speed = 870,
        seeker = {
            sensitivity = -48,
            bandwidth = {5000, 10000},
            fov = 20,
            memoryTime = 10,
        },
    },
}

-- ============================================================================
-- SEAD-Capable Aircraft
-- ============================================================================
SAMSIM_Config.SEADTypes = {
    -- Western SEAD
    "F-16CM_50",
    "F-16C_50",
    "FA-18C_hornet",
    "FA-18E",
    "FA-18F",
    "EA-18G",
    "F-4G",
    "Tornado IDS",
    "Tornado ECR",

    -- Eastern SEAD
    "Su-24M",
    "Su-24MR",
    "MiG-27K",
    "Su-25T",
    "Su-25TM",
    "JF-17",
}

-- ============================================================================
-- Jammer Aircraft
-- ============================================================================
SAMSIM_Config.JammerTypes = {
    EF_111A = {
        name = "EF-111A Raven",
        types = {"EF-111A"},
        jamPower = 1000,
        bandwidth = {2000, 18000},
        standoffRange = 80000,
    },
    EA_6B = {
        name = "EA-6B Prowler",
        types = {"EA-6B"},
        jamPower = 2000,
        bandwidth = {500, 20000},
        standoffRange = 50000,
    },
    EA_18G = {
        name = "EA-18G Growler",
        types = {"EA-18G"},
        jamPower = 3000,
        bandwidth = {500, 40000},
        standoffRange = 60000,
        armCapable = true,
    },
}

-- ============================================================================
-- Threat Categories
-- ============================================================================
SAMSIM_Config.ThreatCategories = {
    UNKNOWN = {priority = 5, name = "Unknown"},
    FIGHTER = {priority = 3, name = "Fighter"},
    ATTACK = {priority = 2, name = "Attack"},
    BOMBER = {priority = 2, name = "Bomber"},
    SEAD = {priority = 1, name = "SEAD"},
    HELICOPTER = {priority = 4, name = "Helicopter"},
    UAV = {priority = 4, name = "UAV"},
    CRUISE_MISSILE = {priority = 1, name = "Cruise Missile"},
    ARM = {priority = 1, name = "ARM"},
}

-- ============================================================================
-- Aircraft Type Classification
-- ============================================================================
SAMSIM_Config.AircraftCategories = {
    FIGHTER = {
        "F-14", "F-15", "F-16", "F-18", "F-22", "F-35",
        "MiG-21", "MiG-23", "MiG-25", "MiG-29", "MiG-31",
        "Su-27", "Su-30", "Su-33", "Su-35", "Su-57",
        "Mirage", "Rafale", "Eurofighter", "JAS-39", "JF-17",
    },
    ATTACK = {
        "A-10", "Su-25", "AV-8", "AMX",
        "Tornado IDS", "Su-24", "MiG-27",
        "F-111", "Su-34",
    },
    BOMBER = {
        "B-1", "B-2", "B-52",
        "Tu-22", "Tu-95", "Tu-160",
    },
    HELICOPTER = {
        "AH-64", "AH-1", "Ka-50", "Ka-52", "Mi-24", "Mi-28",
        "UH-60", "UH-1", "Mi-8", "Mi-17", "CH-47", "SA342",
    },
    UAV = {
        "MQ-1", "MQ-9", "RQ-4", "RQ-7",
        "Bayraktar", "Wing Loong", "CH-4", "CH-5",
    },
}

-- ============================================================================
-- IADS Default Settings
-- ============================================================================
SAMSIM_Config.IADSDefaults = {
    -- Network settings
    maxLinkDistance = 150000,       -- 150km max link distance
    ewrRefreshRate = 2.0,           -- EWR update interval
    threatShareDelay = 1.0,         -- Delay before sharing threat info

    -- Engagement rules
    minEngagePriority = 4,          -- Engage all threats priority 4 or higher
    maxSimultaneousTargets = 3,     -- Per SAM site
    overkillPrevention = true,      -- Prevent multiple sites engaging same target

    -- EMCON defaults
    defaultEMCON = "ACTIVE",        -- Default to radars active
    armDetectionAutoEMCON = true,   -- Auto EMCON on ARM detection
    armEMCONDuration = 60,          -- Seconds to stay dark after ARM

    -- Backup activation
    backupActivationDelay = 5,      -- Seconds before backup site activates
    backupDeactivationDelay = 30,   -- Seconds after primary recovers
}

-- ============================================================================
-- Sector Default Settings
-- ============================================================================
SAMSIM_Config.SectorDefaults = {
    minCoverageRadius = 50000,      -- 50km minimum sector radius
    overlapRequired = 0.2,          -- 20% overlap between sectors
    priorityLevels = 3,             -- Number of priority levels for SAMs
    adaptiveCoverageEnabled = true, -- Enable threat-based activation
}

-- ============================================================================
-- Helper Functions
-- ============================================================================

--- Get SAM type by unit type name
---@param unitTypeName string DCS unit type name
---@return table|nil SAM configuration
function SAMSIM_Config.getSAMTypeByUnit(unitTypeName)
    for samType, config in pairs(SAMSIM_Config.SAMTypes) do
        for category, units in pairs(config.units or {}) do
            for _, unitType in ipairs(units) do
                if string.find(unitTypeName, unitType, 1, true) then
                    return config, samType
                end
            end
        end
    end
    return nil
end

--- Get ARM type by weapon name
---@param weaponName string
---@return table|nil ARM configuration
function SAMSIM_Config.getARMType(weaponName)
    for armType, config in pairs(SAMSIM_Config.ARMTypes) do
        for _, weapon in ipairs(config.weapons) do
            if string.find(weaponName, weapon, 1, true) then
                return config, armType
            end
        end
    end
    return nil
end

--- Check if unit type is a SEAD aircraft
---@param typeName string
---@return boolean
function SAMSIM_Config.isSEADCapable(typeName)
    for _, seadType in ipairs(SAMSIM_Config.SEADTypes) do
        if string.find(typeName, seadType, 1, true) then
            return true
        end
    end
    return false
end

--- Check if unit type is an EWR
---@param typeName string
---@return boolean
function SAMSIM_Config.isEWR(typeName)
    for ewrType in pairs(SAMSIM_Config.EWRTypes) do
        if string.find(typeName, ewrType, 1, true) then
            return true
        end
    end
    return false
end

--- Get EWR configuration by type
---@param typeName string
---@return table|nil
function SAMSIM_Config.getEWRConfig(typeName)
    for ewrType, config in pairs(SAMSIM_Config.EWRTypes) do
        if string.find(typeName, ewrType, 1, true) then
            return config
        end
    end
    return nil
end

--- Classify aircraft by type name
---@param typeName string
---@return string Category name
function SAMSIM_Config.classifyAircraft(typeName)
    for category, types in pairs(SAMSIM_Config.AircraftCategories) do
        for _, pattern in ipairs(types) do
            if string.find(typeName, pattern, 1, true) then
                return category
            end
        end
    end
    return "UNKNOWN"
end

--- Get threat priority for category
---@param category string
---@return number Priority (1=highest, 5=lowest)
function SAMSIM_Config.getThreatPriority(category)
    local catInfo = SAMSIM_Config.ThreatCategories[category]
    if catInfo then
        return catInfo.priority
    end
    return 5  -- Default to lowest
end

-- ============================================================================
-- Initialization
-- ============================================================================

function SAMSIM_Config.init()
    if SAMSIM_Utils and SAMSIM_Utils.info then
        SAMSIM_Utils.info("SAMSIM_Config v%s initialized", SAMSIM_Config.Version)
    end
    return true
end

return SAMSIM_Config
