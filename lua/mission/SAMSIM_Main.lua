--[[
    SAMSIM Main Entry Point
    Unified initialization for DCS SAM Simulation System

    This is the main entry point for SAMSIM. Load this file in your
    mission to initialize all SAMSIM modules.

    Usage:
        dofile("SAMSIM_Main.lua")
        SAMSIM.init({
            debug = true,
            autoDetect = true,
            samPattern = "^SAM_",
            ewrPattern = "^EWR_",
        })

    Author: Claude Code
    Version: 1.0.0

    NO MIST REQUIRED - This system is fully standalone.
]]

-- ============================================================================
-- Version Information
-- ============================================================================
SAMSIM = {}
SAMSIM.Version = "1.0.0"
SAMSIM.BuildDate = "2026-02-06"
SAMSIM.RequiresMIST = false

-- ============================================================================
-- Module Registry
-- ============================================================================
SAMSIM.Modules = {
    Utils = nil,
    Config = nil,
    Events = nil,
    IADS = nil,
    Threat = nil,
    Sector = nil,
    SEAD = nil,
}

-- ============================================================================
-- Default Configuration
-- ============================================================================
SAMSIM.DefaultConfig = {
    -- Debug settings
    debug = false,
    logLevel = 2,  -- 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR

    -- Auto-detection
    autoDetect = true,
    samPattern = "^SAM_",
    ewrPattern = "^EWR_",

    -- Network settings
    networkName = "SAMSIM_IADS",
    coalition = nil,  -- Auto-detect if nil
    maxLinkDistance = 150000,

    -- SEAD settings
    seadEnabled = true,
    autoEMCON = true,
    backupActivation = true,

    -- Sector settings
    sectorsEnabled = true,
    adaptiveCoverage = true,

    -- Threat tracking
    threatTrackingEnabled = true,
    threatUpdateInterval = 2.0,

    -- Update intervals
    networkUpdateInterval = 2.0,
    sectorUpdateInterval = 3.0,

    -- WebSocket (for external interface)
    webSocketEnabled = false,
    webSocketPort = 12080,
}

-- ============================================================================
-- Module Loading
-- ============================================================================

--- Get the base path for SAMSIM scripts
local function getBasePath()
    -- Try to determine base path from current file location
    -- Default to common DCS script locations
    local paths = {
        lfs and (lfs.writedir() .. "Scripts/"),
        "./",
        "Scripts/",
    }

    for _, path in ipairs(paths) do
        if path then
            return path
        end
    end

    return ""
end

--- Load a SAMSIM module
---@param modulePath string Relative path to module
---@param moduleName string Module name for logging
---@return boolean Success
local function loadModule(modulePath, moduleName)
    local basePath = getBasePath()

    local success, result = pcall(function()
        dofile(basePath .. modulePath)
    end)

    if success then
        env.info(string.format("SAMSIM: Loaded module '%s'", moduleName))
        return true
    else
        env.warning(string.format("SAMSIM: Failed to load module '%s': %s", moduleName, tostring(result)))
        return false
    end
end

--- Load all SAMSIM modules
---@return boolean Success
function SAMSIM.loadModules()
    local allLoaded = true

    -- Core modules (load order matters)
    local modules = {
        {"lua/mission/core/SAMSIM_Utils.lua", "Utils"},
        {"lua/mission/core/SAMSIM_Config.lua", "Config"},
        {"lua/mission/core/SAMSIM_Events.lua", "Events"},
        {"lua/mission/iads/SAMSIM_IADS.lua", "IADS"},
        {"lua/mission/iads/SAMSIM_Threat.lua", "Threat"},
        {"lua/mission/iads/SAMSIM_Sector.lua", "Sector"},
        {"lua/mission/SAMSIM_SEAD.lua", "SEAD"},
    }

    for _, mod in ipairs(modules) do
        if not loadModule(mod[1], mod[2]) then
            allLoaded = false
        end
    end

    -- Store references
    SAMSIM.Modules.Utils = SAMSIM_Utils
    SAMSIM.Modules.Config = SAMSIM_Config
    SAMSIM.Modules.Events = SAMSIM_Events
    SAMSIM.Modules.IADS = SAMSIM_IADS
    SAMSIM.Modules.Threat = SAMSIM_Threat
    SAMSIM.Modules.Sector = SAMSIM_Sector
    SAMSIM.Modules.SEAD = SAMSIM_SEAD

    return allLoaded
end

-- ============================================================================
-- Initialization
-- ============================================================================

--- Initialize SAMSIM with configuration
---@param userConfig table|nil User configuration (merged with defaults)
---@return table Network object
function SAMSIM.init(userConfig)
    userConfig = userConfig or {}

    -- Merge with defaults
    local config = {}
    for k, v in pairs(SAMSIM.DefaultConfig) do
        config[k] = v
    end
    for k, v in pairs(userConfig) do
        config[k] = v
    end

    SAMSIM.config = config

    env.info("==============================================")
    env.info("  SAMSIM v" .. SAMSIM.Version .. " Initializing")
    env.info("  MIST-free DCS SAM Simulation System")
    env.info("==============================================")

    -- Initialize Utils first
    if SAMSIM_Utils then
        SAMSIM_Utils.init()
        if config.debug then
            SAMSIM_Utils.setLogLevel(SAMSIM_Utils.LogLevel.DEBUG)
        else
            SAMSIM_Utils.setLogLevel(config.logLevel or SAMSIM_Utils.LogLevel.INFO)
        end
    end

    -- Initialize Config
    if SAMSIM_Config then
        SAMSIM_Config.init()
    end

    -- Initialize Events
    if SAMSIM_Events then
        SAMSIM_Events.init()
    end

    -- Initialize Threat tracking
    if SAMSIM_Threat and config.threatTrackingEnabled then
        SAMSIM_Threat.init()
        SAMSIM_Threat.startUpdateLoop()
    end

    -- Initialize Sector management
    if SAMSIM_Sector and config.sectorsEnabled then
        SAMSIM_Sector.init()
    end

    -- Create IADS network
    local network = nil
    if SAMSIM_IADS then
        SAMSIM_IADS.init()

        -- Determine coalition
        local networkCoalition = config.coalition
        if not networkCoalition then
            -- Default to RED
            networkCoalition = coalition.side.RED
        end

        -- Create network
        network = SAMSIM_IADS.createNetwork(config.networkName, {
            coalition = networkCoalition,
            settings = {
                maxLinkDistance = config.maxLinkDistance,
            },
        })

        -- Auto-detect and add SAMs/EWRs
        if config.autoDetect then
            SAMSIM_IADS.autoAddByPattern(network, config.samPattern, config.ewrPattern)
            SAMSIM_IADS.autoLinkByDistance(network, config.maxLinkDistance)
        end

        -- Start update loop
        SAMSIM_IADS.startUpdateLoop(network, config.networkUpdateInterval)
    end

    -- Initialize SEAD with network integration
    if SAMSIM_SEAD and config.seadEnabled then
        SAMSIM_SEAD.initialize({
            network = network,
            autoEMCON = config.autoEMCON,
            backupActivation = config.backupActivation,
        })
    end

    -- Start sector update loop if enabled
    if SAMSIM_Sector and config.sectorsEnabled then
        SAMSIM_Sector.startUpdateLoop(config.sectorUpdateInterval)
    end

    -- Store network reference
    SAMSIM.network = network

    env.info("==============================================")
    env.info("  SAMSIM Initialization Complete")
    if network then
        local status = SAMSIM_IADS.getNetworkStatus(network)
        env.info(string.format("  Network: %s", config.networkName))
        env.info(string.format("  SAMs: %d, EWRs: %d", status.nodes.sams, status.nodes.ewrs))
        env.info(string.format("  Links: %d", status.links))
    end
    env.info("==============================================")

    return network
end

-- ============================================================================
-- Quick Setup Functions
-- ============================================================================

--- Quick setup for RED coalition
---@param options table|nil Additional options
---@return table Network
function SAMSIM.initRed(options)
    options = options or {}
    options.coalition = coalition.side.RED
    options.networkName = options.networkName or "RED_IADS"
    return SAMSIM.init(options)
end

--- Quick setup for BLUE coalition
---@param options table|nil Additional options
---@return table Network
function SAMSIM.initBlue(options)
    options = options or {}
    options.coalition = coalition.side.BLUE
    options.networkName = options.networkName or "BLUE_IADS"
    return SAMSIM.init(options)
end

--- Initialize both coalitions
---@param options table|nil Shared options
---@return table, table Red network, Blue network
function SAMSIM.initBoth(options)
    options = options or {}

    local redNetwork = SAMSIM.initRed({
        samPattern = options.redSamPattern or "^RED_SAM_",
        ewrPattern = options.redEwrPattern or "^RED_EWR_",
        networkName = "RED_IADS",
    })

    local blueNetwork = SAMSIM.initBlue({
        samPattern = options.blueSamPattern or "^BLUE_SAM_",
        ewrPattern = options.blueEwrPattern or "^BLUE_EWR_",
        networkName = "BLUE_IADS",
    })

    return redNetwork, blueNetwork
end

-- ============================================================================
-- Manual Setup Functions
-- ============================================================================

--- Add a SAM site manually
---@param groupName string DCS group name
---@param samType string|nil SAM type (auto-detect if nil)
---@param options table|nil Additional options
---@return table|nil Node
function SAMSIM.addSAM(groupName, samType, options)
    if not SAMSIM.network then
        env.warning("SAMSIM: No network initialized. Call SAMSIM.init() first.")
        return nil
    end

    return SAMSIM_IADS.addSAM(SAMSIM.network, groupName, samType, options)
end

--- Add an EWR manually
---@param groupName string DCS group name
---@param options table|nil Additional options
---@return table|nil Node
function SAMSIM.addEWR(groupName, options)
    if not SAMSIM.network then
        env.warning("SAMSIM: No network initialized. Call SAMSIM.init() first.")
        return nil
    end

    return SAMSIM_IADS.addEWR(SAMSIM.network, groupName, options)
end

--- Create a defense sector
---@param name string Sector name
---@param center table Center position {x, y, z}
---@param radius number Radius in meters
---@return table|nil Sector
function SAMSIM.createSector(name, center, radius)
    if not SAMSIM_Sector then
        env.warning("SAMSIM: Sector module not loaded.")
        return nil
    end

    local sector = SAMSIM_Sector.createCircular(name, center, radius)

    -- Auto-assign SAMs if network exists
    if SAMSIM.network and sector then
        SAMSIM_Sector.autoAssignSAMs(sector, SAMSIM.network)
    end

    return sector
end

--- Create a sector from DCS trigger zone
---@param zoneName string DCS trigger zone name
---@return table|nil Sector
function SAMSIM.createSectorFromZone(zoneName)
    if not SAMSIM_Sector then
        env.warning("SAMSIM: Sector module not loaded.")
        return nil
    end

    local sector = SAMSIM_Sector.createFromZone(zoneName)

    if SAMSIM.network and sector then
        SAMSIM_Sector.autoAssignSAMs(sector, SAMSIM.network)
    end

    return sector
end

-- ============================================================================
-- Control Functions
-- ============================================================================

--- Set network EMCON level
---@param level string "ACTIVE", "LIMITED", "DARK", or "ADAPTIVE"
function SAMSIM.setEMCON(level)
    if not SAMSIM.network then return end
    SAMSIM_IADS.setNetworkEMCON(SAMSIM.network, level)
end

--- Go dark (all radars off)
function SAMSIM.goDark()
    if not SAMSIM.network then return end
    SAMSIM_IADS.goToDark(SAMSIM.network)
end

--- Go active (all radars on)
function SAMSIM.goActive()
    if not SAMSIM.network then return end
    SAMSIM_IADS.goToActive(SAMSIM.network)
end

-- ============================================================================
-- Status Functions
-- ============================================================================

--- Get network status
---@return table|nil Status
function SAMSIM.getStatus()
    if not SAMSIM.network then return nil end
    return SAMSIM_IADS.getNetworkStatus(SAMSIM.network)
end

--- Get SEAD status
---@return table|nil Status
function SAMSIM.getSEADStatus()
    if not SAMSIM_SEAD then return nil end
    return SAMSIM_SEAD.getNetworkSEADStatus(SAMSIM.network)
end

--- Get all sectors status
---@return table|nil Status
function SAMSIM.getSectorsStatus()
    if not SAMSIM_Sector then return nil end
    return SAMSIM_Sector.getAllSectorsStatus()
end

--- Get threat statistics
---@return table|nil Statistics
function SAMSIM.getThreatStats()
    if not SAMSIM_Threat then return nil end
    return SAMSIM_Threat.getStatistics()
end

-- ============================================================================
-- Shutdown
-- ============================================================================

--- Shutdown SAMSIM
function SAMSIM.shutdown()
    env.info("SAMSIM: Shutting down...")

    if SAMSIM_Sector then
        SAMSIM_Sector.stopUpdateLoop()
    end

    if SAMSIM_Threat then
        SAMSIM_Threat.stopUpdateLoop()
    end

    if SAMSIM_IADS and SAMSIM.network then
        SAMSIM_IADS.stopUpdateLoop(SAMSIM.network)
    end

    if SAMSIM_Events then
        SAMSIM_Events.shutdown()
    end

    env.info("SAMSIM: Shutdown complete")
end

-- ============================================================================
-- Module Info
-- ============================================================================

env.info("==============================================")
env.info("  SAMSIM Main Module Loaded")
env.info("  Version: " .. SAMSIM.Version)
env.info("  MIST Required: NO")
env.info("  ")
env.info("  Call SAMSIM.init() to initialize")
env.info("==============================================")

return SAMSIM
