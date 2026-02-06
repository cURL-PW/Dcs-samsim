--[[
    Unified SAMSim Controller for DCS World

    Manages multiple SAM system simulations:
    Long Range:
    - SA-2 Guideline (S-75 Dvina)
    - SA-3 Goa (S-125 Neva/Pechora)
    - SA-10 Grumble (S-300PS)
    Medium Range:
    - SA-6 Gainful (2K12 Kub)
    - SA-11 Gadfly (9K37 Buk)
    Short Range:
    - SA-8 Gecko (9K33 Osa)
    - SA-15 Gauntlet (9K330 Tor)
    - SA-19 Grison (2K22 Tunguska)

    Author: Claude Code
    Version: 1.1
]]

SAMSIM = SAMSIM or {}
SAMSIM.Unified = {}
SAMSIM.Unified.Version = "1.1.0"

-- ============================================================================
-- System Registry
-- ============================================================================
SAMSIM.Unified.Systems = {
    SA2 = {
        name = "SA-2 Guideline",
        natoName = "SA-2 Guideline",
        sovietName = "S-75 Dvina",
        controller = nil,  -- Will be set when loaded
        loaded = false,
    },
    SA3 = {
        name = "SA-3 Goa",
        natoName = "SA-3 Goa",
        sovietName = "S-125 Neva/Pechora",
        controller = nil,
        loaded = false,
    },
    SA6 = {
        name = "SA-6 Gainful",
        natoName = "SA-6 Gainful",
        sovietName = "2K12 Kub",
        controller = nil,
        loaded = false,
    },
    SA10 = {
        name = "SA-10 Grumble",
        natoName = "SA-10 Grumble",
        sovietName = "S-300PS",
        controller = nil,
        loaded = false,
    },
    SA11 = {
        name = "SA-11 Gadfly",
        natoName = "SA-11 Gadfly",
        sovietName = "9K37 Buk",
        controller = nil,
        loaded = false,
    },
    SA8 = {
        name = "SA-8 Gecko",
        natoName = "SA-8 Gecko",
        sovietName = "9K33 Osa",
        category = "short_range",
        controller = nil,
        loaded = false,
    },
    SA15 = {
        name = "SA-15 Gauntlet",
        natoName = "SA-15 Gauntlet",
        sovietName = "9K330 Tor",
        category = "short_range",
        controller = nil,
        loaded = false,
    },
    SA19 = {
        name = "SA-19 Grison",
        natoName = "SA-19 Grison",
        sovietName = "2K22 Tunguska",
        category = "short_range",
        controller = nil,
        loaded = false,
    },
}

-- ============================================================================
-- Active Sites
-- ============================================================================
SAMSIM.Unified.Sites = {}
SAMSIM.Unified.ActiveSiteId = nil

-- ============================================================================
-- Site Management
-- ============================================================================
function SAMSIM.Unified.createSite(siteId, systemType, name, position, heading)
    if not SAMSIM.Unified.Systems[systemType] then
        env.error("SAMSIM Unified: Unknown system type " .. tostring(systemType))
        return false
    end

    local system = SAMSIM.Unified.Systems[systemType]

    -- Get the appropriate controller
    local controller = nil
    if systemType == "SA2" and SAMSIM and SAMSIM.State then
        controller = SAMSIM
    elseif systemType == "SA3" and SAMSIM_SA3 then
        controller = SAMSIM_SA3
    elseif systemType == "SA6" and SAMSIM_SA6 then
        controller = SAMSIM_SA6
    elseif systemType == "SA10" and SAMSIM_SA10 then
        controller = SAMSIM_SA10
    elseif systemType == "SA11" and SAMSIM_SA11 then
        controller = SAMSIM_SA11
    elseif systemType == "SA8" and SA8_SAMSIM then
        controller = SA8_SAMSIM
    elseif systemType == "SA15" and SA15_SAMSIM then
        controller = SA15_SAMSIM
    elseif systemType == "SA19" and SA19_SAMSIM then
        controller = SA19_SAMSIM
    end

    if not controller then
        env.error("SAMSIM Unified: Controller not loaded for " .. systemType)
        return false
    end

    -- Create site entry
    SAMSIM.Unified.Sites[siteId] = {
        id = siteId,
        systemType = systemType,
        systemName = system.name,
        natoName = system.natoName,
        sovietName = system.sovietName,
        name = name or (systemType .. "_Site_" .. siteId),
        position = position or {x=0, y=0, z=0},
        heading = heading or 0,
        controller = controller,
        active = true,
    }

    -- Initialize the controller
    controller.initialize(name, position, heading)

    -- Set as active if first site
    if not SAMSIM.Unified.ActiveSiteId then
        SAMSIM.Unified.ActiveSiteId = siteId
    end

    env.info("SAMSIM Unified: Created site " .. siteId .. " (" .. system.name .. ")")
    return true
end

function SAMSIM.Unified.removeSite(siteId)
    if SAMSIM.Unified.Sites[siteId] then
        SAMSIM.Unified.Sites[siteId].active = false
        SAMSIM.Unified.Sites[siteId] = nil

        if SAMSIM.Unified.ActiveSiteId == siteId then
            -- Find another active site
            for id, site in pairs(SAMSIM.Unified.Sites) do
                SAMSIM.Unified.ActiveSiteId = id
                break
            end
        end

        env.info("SAMSIM Unified: Removed site " .. siteId)
        return true
    end
    return false
end

function SAMSIM.Unified.setActiveSite(siteId)
    if SAMSIM.Unified.Sites[siteId] then
        SAMSIM.Unified.ActiveSiteId = siteId
        return true
    end
    return false
end

function SAMSIM.Unified.getActiveSite()
    return SAMSIM.Unified.Sites[SAMSIM.Unified.ActiveSiteId]
end

-- ============================================================================
-- Command Routing
-- ============================================================================
function SAMSIM.Unified.processCommand(cmd)
    -- Handle site-level commands
    if cmd.type == "LIST_SITES" then
        local sitesList = {}
        for id, site in pairs(SAMSIM.Unified.Sites) do
            table.insert(sitesList, {
                id = id,
                systemType = site.systemType,
                name = site.name,
                natoName = site.natoName,
                active = (id == SAMSIM.Unified.ActiveSiteId),
            })
        end
        return {success = true, sites = sitesList}

    elseif cmd.type == "SELECT_SITE" then
        if SAMSIM.Unified.setActiveSite(cmd.siteId) then
            return {success = true, message = "Selected site " .. cmd.siteId}
        else
            return {success = false, message = "Site not found"}
        end

    elseif cmd.type == "CREATE_SITE" then
        local success = SAMSIM.Unified.createSite(
            cmd.siteId,
            cmd.systemType,
            cmd.name,
            cmd.position,
            cmd.heading
        )
        return {success = success, message = success and "Site created" or "Failed to create site"}

    elseif cmd.type == "REMOVE_SITE" then
        local success = SAMSIM.Unified.removeSite(cmd.siteId)
        return {success = success, message = success and "Site removed" or "Site not found"}

    elseif cmd.type == "GET_AVAILABLE_SYSTEMS" then
        local systems = {}
        for sysType, sysInfo in pairs(SAMSIM.Unified.Systems) do
            table.insert(systems, {
                type = sysType,
                name = sysInfo.name,
                natoName = sysInfo.natoName,
                sovietName = sysInfo.sovietName,
            })
        end
        return {success = true, systems = systems}
    end

    -- Route to active site's controller
    local activeSite = SAMSIM.Unified.getActiveSite()
    if not activeSite then
        return {success = false, message = "No active site"}
    end

    -- Add site context to command if needed
    cmd.siteId = activeSite.id

    return activeSite.controller.processCommand(cmd)
end

-- ============================================================================
-- State Export
-- ============================================================================
function SAMSIM.Unified.getStateForExport()
    local activeSite = SAMSIM.Unified.getActiveSite()

    -- Get base state from active site's controller
    local state = {}
    if activeSite and activeSite.controller and activeSite.controller.getStateForExport then
        state = activeSite.controller.getStateForExport()
    end

    -- Add unified controller info
    state.unified = {
        version = SAMSIM.Unified.Version,
        activeSiteId = SAMSIM.Unified.ActiveSiteId,
        siteCount = 0,
        sites = {},
    }

    for id, site in pairs(SAMSIM.Unified.Sites) do
        state.unified.siteCount = state.unified.siteCount + 1
        table.insert(state.unified.sites, {
            id = id,
            systemType = site.systemType,
            name = site.name,
            natoName = site.natoName,
            sovietName = site.sovietName,
            active = (id == SAMSIM.Unified.ActiveSiteId),
        })
    end

    return state
end

-- ============================================================================
-- Network Communication
-- ============================================================================
SAMSIM.Unified.Network = {
    socket = nil,
    host = "127.0.0.1",
    sendPort = 7778,
    recvPort = 7777,
    lastSend = 0,
    sendInterval = 0.1,
    buffer = "",
}

function SAMSIM.Unified.Network.initialize()
    local socket = require("socket")
    SAMSIM.Unified.Network.socket = socket.udp()
    SAMSIM.Unified.Network.socket:setsockname("*", SAMSIM.Unified.Network.recvPort)
    SAMSIM.Unified.Network.socket:settimeout(0)
    env.info("SAMSIM Unified: Network initialized")
end

function SAMSIM.Unified.Network.update()
    local net = SAMSIM.Unified.Network
    if not net.socket then return end

    -- Receive commands
    local data, err = net.socket:receive()
    if data then
        local success, cmd = pcall(function()
            return SAMSIM.Unified.JSON.decode(data)
        end)

        if success and cmd then
            local response = SAMSIM.Unified.processCommand(cmd)
            if response then
                local respData = SAMSIM.Unified.JSON.encode(response)
                net.socket:sendto(respData, net.host, net.sendPort)
            end
        end
    end

    -- Send state update
    local currentTime = timer.getTime()
    if currentTime - net.lastSend >= net.sendInterval then
        net.lastSend = currentTime

        local state = SAMSIM.Unified.getStateForExport()
        local stateData = SAMSIM.Unified.JSON.encode(state)
        net.socket:sendto(stateData, net.host, net.sendPort)
    end

    return timer.getTime() + 0.05
end

-- ============================================================================
-- Simple JSON Encoder/Decoder
-- ============================================================================
SAMSIM.Unified.JSON = {}

function SAMSIM.Unified.JSON.encode(obj)
    local t = type(obj)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return obj and "true" or "false"
    elseif t == "number" then
        if obj ~= obj then return "null" end
        if obj == math.huge or obj == -math.huge then return "null" end
        return string.format("%.6g", obj)
    elseif t == "string" then
        return '"' .. obj:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"'
    elseif t == "table" then
        local isArray = #obj > 0 or next(obj) == nil
        if isArray then
            local parts = {}
            for i, v in ipairs(obj) do
                parts[i] = SAMSIM.Unified.JSON.encode(v)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(obj) do
                if type(k) == "string" then
                    table.insert(parts, '"' .. k .. '":' .. SAMSIM.Unified.JSON.encode(v))
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function SAMSIM.Unified.JSON.decode(str)
    local pos = 1
    local function skipWhitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end

    local function parseValue()
        skipWhitespace()
        local c = str:sub(pos, pos)

        if c == '"' then
            pos = pos + 1
            local startPos = pos
            while pos <= #str do
                local ch = str:sub(pos, pos)
                if ch == '"' then
                    local result = str:sub(startPos, pos - 1)
                    pos = pos + 1
                    return result:gsub('\\n', '\n'):gsub('\\r', '\r'):gsub('\\t', '\t'):gsub('\\"', '"'):gsub('\\\\', '\\')
                elseif ch == '\\' then
                    pos = pos + 2
                else
                    pos = pos + 1
                end
            end
        elseif c == '{' then
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            while true do
                skipWhitespace()
                local key = parseValue()
                skipWhitespace()
                pos = pos + 1  -- skip ':'
                local value = parseValue()
                obj[key] = value
                skipWhitespace()
                if str:sub(pos, pos) == '}' then
                    pos = pos + 1
                    return obj
                end
                pos = pos + 1  -- skip ','
            end
        elseif c == '[' then
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            while true do
                table.insert(arr, parseValue())
                skipWhitespace()
                if str:sub(pos, pos) == ']' then
                    pos = pos + 1
                    return arr
                end
                pos = pos + 1  -- skip ','
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            local numStr = str:match("^%-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            if numStr then
                pos = pos + #numStr
                return tonumber(numStr)
            end
        end
        return nil
    end

    return parseValue()
end

-- ============================================================================
-- Initialization
-- ============================================================================
function SAMSIM.Unified.initialize()
    -- Check which controllers are loaded
    -- Long Range Systems
    if SAMSIM and SAMSIM.State then
        SAMSIM.Unified.Systems.SA2.loaded = true
        SAMSIM.Unified.Systems.SA2.controller = SAMSIM
    end
    if SAMSIM_SA3 then
        SAMSIM.Unified.Systems.SA3.loaded = true
        SAMSIM.Unified.Systems.SA3.controller = SAMSIM_SA3
    end
    if SAMSIM_SA10 then
        SAMSIM.Unified.Systems.SA10.loaded = true
        SAMSIM.Unified.Systems.SA10.controller = SAMSIM_SA10
    end

    -- Medium Range Systems
    if SAMSIM_SA6 then
        SAMSIM.Unified.Systems.SA6.loaded = true
        SAMSIM.Unified.Systems.SA6.controller = SAMSIM_SA6
    end
    if SAMSIM_SA11 then
        SAMSIM.Unified.Systems.SA11.loaded = true
        SAMSIM.Unified.Systems.SA11.controller = SAMSIM_SA11
    end

    -- Short Range Systems
    if SA8_SAMSIM then
        SAMSIM.Unified.Systems.SA8.loaded = true
        SAMSIM.Unified.Systems.SA8.controller = SA8_SAMSIM
    end
    if SA15_SAMSIM then
        SAMSIM.Unified.Systems.SA15.loaded = true
        SAMSIM.Unified.Systems.SA15.controller = SA15_SAMSIM
    end
    if SA19_SAMSIM then
        SAMSIM.Unified.Systems.SA19.loaded = true
        SAMSIM.Unified.Systems.SA19.controller = SA19_SAMSIM
    end

    -- Initialize network
    SAMSIM.Unified.Network.initialize()

    -- Start network update loop
    timer.scheduleFunction(SAMSIM.Unified.Network.update, nil, timer.getTime() + 0.1)

    env.info("SAMSIM Unified Controller initialized - Version " .. SAMSIM.Unified.Version)
end

-- ============================================================================
-- Quick Setup Functions
-- ============================================================================

-- Create a complete SA-2 site
function SAMSIM.Unified.createSA2Site(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA2_1", "SA2", name, position, heading)
end

-- Create a complete SA-3 site
function SAMSIM.Unified.createSA3Site(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA3_1", "SA3", name, position, heading)
end

-- Create a complete SA-6 battery
function SAMSIM.Unified.createSA6Battery(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA6_1", "SA6", name, position, heading)
end

-- Create a complete SA-10 battalion
function SAMSIM.Unified.createSA10Battalion(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA10_1", "SA10", name, position, heading)
end

-- Create a complete SA-11 battery
function SAMSIM.Unified.createSA11Battery(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA11_1", "SA11", name, position, heading)
end

-- Create a complete SA-8 Gecko vehicle
function SAMSIM.Unified.createSA8Vehicle(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA8_1", "SA8", name, position, heading)
end

-- Create a complete SA-15 Tor vehicle
function SAMSIM.Unified.createSA15Vehicle(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA15_1", "SA15", name, position, heading)
end

-- Create a complete SA-19 Tunguska vehicle
function SAMSIM.Unified.createSA19Vehicle(name, position, heading)
    return SAMSIM.Unified.createSite(name or "SA19_1", "SA19", name, position, heading)
end

env.info("SAMSIM Unified Controller loaded - Version " .. SAMSIM.Unified.Version)
