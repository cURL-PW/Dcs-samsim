--[[
    SAMSIM Export Script

    This script runs in the DCS Export environment and provides:
    - UDP communication with external SAMSIM server
    - Status updates from SA-2 sites
    - Command reception and forwarding

    Installation:
    1. Copy this file to: Saved Games/DCS/Scripts/
    2. Add to Export.lua: dofile(lfs.writedir() .. "Scripts/SAMSIM_Export.lua")

    Or merge contents into existing Export.lua
]]

-- SAMSIM Export Module
SAMSIM_Export = {}

-- Configuration
SAMSIM_Export.Config = {
    -- Server connection settings
    SERVER_HOST = "127.0.0.1",
    SEND_PORT = 7777,      -- Port to send status updates
    RECV_PORT = 7778,      -- Port to receive commands

    -- Update rates
    STATUS_INTERVAL = 0.1,  -- Send status every 100ms
    COMMAND_CHECK_INTERVAL = 0.05,  -- Check for commands every 50ms

    -- Debug
    DEBUG = false,
}

-- State
SAMSIM_Export.State = {
    socket = nil,
    sendSocket = nil,
    recvSocket = nil,
    lastStatusTime = 0,
    lastCommandTime = 0,
    initialized = false,
}

-- Simple JSON encoder (no external dependencies)
local function encodeJSON(obj)
    local t = type(obj)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return obj and "true" or "false"
    elseif t == "number" then
        if obj ~= obj then -- NaN
            return "null"
        elseif obj == math.huge then
            return "1e308"
        elseif obj == -math.huge then
            return "-1e308"
        else
            return tostring(obj)
        end
    elseif t == "string" then
        -- Escape special characters
        local escaped = obj:gsub('\\', '\\\\')
                           :gsub('"', '\\"')
                           :gsub('\n', '\\n')
                           :gsub('\r', '\\r')
                           :gsub('\t', '\\t')
        return '"' .. escaped .. '"'
    elseif t == "table" then
        -- Check if array or object
        local isArray = true
        local maxIndex = 0
        for k, v in pairs(obj) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArray = false
                break
            end
            if k > maxIndex then maxIndex = k end
        end

        if isArray and maxIndex > 0 then
            -- Array
            local parts = {}
            for i = 1, maxIndex do
                parts[i] = encodeJSON(obj[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            -- Object
            local parts = {}
            for k, v in pairs(obj) do
                local key = type(k) == "string" and k or tostring(k)
                table.insert(parts, '"' .. key .. '":' .. encodeJSON(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

-- Simple JSON decoder
local function decodeJSON(str)
    if not str or str == "" then return nil end

    -- Remove whitespace
    str = str:gsub("^%s+", ""):gsub("%s+$", "")

    local pos = 1
    local char = function() return str:sub(pos, pos) end
    local advance = function() pos = pos + 1 end
    local skip_ws = function()
        while char():match("%s") do advance() end
    end

    local parse_value, parse_string, parse_number, parse_array, parse_object

    parse_string = function()
        advance() -- skip opening quote
        local result = ""
        while pos <= #str do
            local c = char()
            if c == '"' then
                advance()
                return result
            elseif c == '\\' then
                advance()
                c = char()
                if c == 'n' then result = result .. '\n'
                elseif c == 'r' then result = result .. '\r'
                elseif c == 't' then result = result .. '\t'
                else result = result .. c
                end
            else
                result = result .. c
            end
            advance()
        end
        return result
    end

    parse_number = function()
        local start = pos
        if char() == '-' then advance() end
        while char():match("[0-9]") do advance() end
        if char() == '.' then
            advance()
            while char():match("[0-9]") do advance() end
        end
        if char():match("[eE]") then
            advance()
            if char():match("[+-]") then advance() end
            while char():match("[0-9]") do advance() end
        end
        return tonumber(str:sub(start, pos - 1))
    end

    parse_array = function()
        advance() -- skip [
        local result = {}
        skip_ws()
        if char() == ']' then
            advance()
            return result
        end
        while true do
            skip_ws()
            table.insert(result, parse_value())
            skip_ws()
            if char() == ']' then
                advance()
                return result
            elseif char() == ',' then
                advance()
            else
                break
            end
        end
        return result
    end

    parse_object = function()
        advance() -- skip {
        local result = {}
        skip_ws()
        if char() == '}' then
            advance()
            return result
        end
        while true do
            skip_ws()
            if char() ~= '"' then break end
            local key = parse_string()
            skip_ws()
            if char() ~= ':' then break end
            advance()
            skip_ws()
            result[key] = parse_value()
            skip_ws()
            if char() == '}' then
                advance()
                return result
            elseif char() == ',' then
                advance()
            else
                break
            end
        end
        return result
    end

    parse_value = function()
        skip_ws()
        local c = char()
        if c == '"' then return parse_string()
        elseif c == '{' then return parse_object()
        elseif c == '[' then return parse_array()
        elseif c == 't' then
            pos = pos + 4
            return true
        elseif c == 'f' then
            pos = pos + 5
            return false
        elseif c == 'n' then
            pos = pos + 4
            return nil
        elseif c:match("[%-0-9]") then
            return parse_number()
        end
        return nil
    end

    local ok, result = pcall(parse_value)
    if ok then return result end
    return nil
end

--[[
    Initialize UDP sockets
]]
function SAMSIM_Export.InitSockets()
    local socket = require("socket")

    -- Create send socket (UDP)
    SAMSIM_Export.State.sendSocket = socket.udp()
    SAMSIM_Export.State.sendSocket:settimeout(0)

    -- Create receive socket (UDP)
    SAMSIM_Export.State.recvSocket = socket.udp()
    SAMSIM_Export.State.recvSocket:settimeout(0)

    -- Bind receive socket
    local result, err = SAMSIM_Export.State.recvSocket:setsockname("*", SAMSIM_Export.Config.RECV_PORT)
    if not result then
        log.write("SAMSIM", log.WARNING, "Failed to bind receive socket: " .. tostring(err))
        return false
    end

    SAMSIM_Export.State.initialized = true
    log.write("SAMSIM", log.INFO, "Sockets initialized - Send:" .. SAMSIM_Export.Config.SEND_PORT .. " Recv:" .. SAMSIM_Export.Config.RECV_PORT)

    return true
end

--[[
    Send data to server
]]
function SAMSIM_Export.SendToServer(data)
    if not SAMSIM_Export.State.initialized then return end

    local json = encodeJSON(data)
    SAMSIM_Export.State.sendSocket:sendto(
        json,
        SAMSIM_Export.Config.SERVER_HOST,
        SAMSIM_Export.Config.SEND_PORT
    )

    if SAMSIM_Export.Config.DEBUG then
        log.write("SAMSIM", log.DEBUG, "Sent: " .. json)
    end
end

--[[
    Receive commands from server
]]
function SAMSIM_Export.ReceiveFromServer()
    if not SAMSIM_Export.State.initialized then return nil end

    local data, ip, port = SAMSIM_Export.State.recvSocket:receivefrom()
    if data then
        if SAMSIM_Export.Config.DEBUG then
            log.write("SAMSIM", log.DEBUG, "Received: " .. data)
        end
        return decodeJSON(data)
    end
    return nil
end

--[[
    Collect and send status update
]]
function SAMSIM_Export.SendStatusUpdate()
    -- Get SAMSIM status from mission environment
    -- This requires the mission script to have registered data

    local status = {
        type = "status",
        time = LoGetModelTime() or 0,
        missionTime = LoGetMissionStartTime() or 0,
        paused = LoGetPause() or false,
        sites = {},
    }

    -- Try to get data from shared table (set by mission script)
    if SAMSIM_SharedData then
        status.sites = SAMSIM_SharedData.sites or {}
    end

    -- Also collect basic world data
    status.selfData = LoGetSelfData()

    -- Get all aircraft positions for radar display
    local objects = LoGetWorldObjects()
    if objects then
        status.worldObjects = {}
        for id, obj in pairs(objects) do
            if obj.Type and obj.Type.level1 == 1 then -- Aircraft
                table.insert(status.worldObjects, {
                    id = id,
                    name = obj.Name,
                    type = obj.Type,
                    lat = obj.LatLongAlt and obj.LatLongAlt.Lat,
                    lon = obj.LatLongAlt and obj.LatLongAlt.Long,
                    alt = obj.LatLongAlt and obj.LatLongAlt.Alt,
                    heading = obj.Heading,
                    pitch = obj.Pitch,
                    bank = obj.Bank,
                    coalition = obj.Coalition,
                })
            end
        end
    end

    SAMSIM_Export.SendToServer(status)
end

--[[
    Process received command
]]
function SAMSIM_Export.ProcessCommand(command)
    if not command then return end

    -- Forward command to mission script via shared table
    if not SAMSIM_CommandQueue then
        SAMSIM_CommandQueue = {}
    end

    table.insert(SAMSIM_CommandQueue, command)

    -- Also try to call directly if available
    if SAMSIM and SAMSIM.ProcessCommand then
        local result = SAMSIM.ProcessCommand(command)
        SAMSIM_Export.SendToServer({
            type = "response",
            command = command.cmd,
            result = result,
        })
    end
end

--[[
    Export Start - Called when mission starts
]]
function LuaExportStart()
    log.write("SAMSIM", log.INFO, "SAMSIM Export starting...")

    -- Initialize sockets
    if not SAMSIM_Export.InitSockets() then
        log.write("SAMSIM", log.ERROR, "Failed to initialize SAMSIM Export")
        return
    end

    -- Send init message
    SAMSIM_Export.SendToServer({
        type = "init",
        message = "SAMSIM Export started",
        version = "1.0",
    })

    log.write("SAMSIM", log.INFO, "SAMSIM Export started successfully")
end

--[[
    Export Stop - Called when mission ends
]]
function LuaExportStop()
    if SAMSIM_Export.State.initialized then
        SAMSIM_Export.SendToServer({
            type = "shutdown",
            message = "SAMSIM Export stopped",
        })

        -- Close sockets
        if SAMSIM_Export.State.sendSocket then
            SAMSIM_Export.State.sendSocket:close()
        end
        if SAMSIM_Export.State.recvSocket then
            SAMSIM_Export.State.recvSocket:close()
        end

        SAMSIM_Export.State.initialized = false
    end

    log.write("SAMSIM", log.INFO, "SAMSIM Export stopped")
end

--[[
    Export Activity - Called periodically
]]
function LuaExportActivityNextEvent(t)
    if not SAMSIM_Export.State.initialized then
        return t + 1.0
    end

    local currentTime = LoGetModelTime() or 0

    -- Send status updates
    if currentTime - SAMSIM_Export.State.lastStatusTime >= SAMSIM_Export.Config.STATUS_INTERVAL then
        SAMSIM_Export.SendStatusUpdate()
        SAMSIM_Export.State.lastStatusTime = currentTime
    end

    -- Check for incoming commands
    local command = SAMSIM_Export.ReceiveFromServer()
    while command do
        SAMSIM_Export.ProcessCommand(command)
        command = SAMSIM_Export.ReceiveFromServer()
    end

    -- Next event in 50ms
    return t + SAMSIM_Export.Config.COMMAND_CHECK_INTERVAL
end

--[[
    Export After Frame - Called after each frame render
]]
function LuaExportAfterNextFrame()
    -- Optional: Can be used for high-frequency updates if needed
end

--[[
    Export Before Frame - Called before each frame render
]]
function LuaExportBeforeNextFrame()
    -- Optional: Can be used for pre-frame processing
end

log.write("SAMSIM", log.INFO, "SAMSIM Export module loaded")
