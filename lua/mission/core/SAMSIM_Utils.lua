--[[
    SAMSIM Utilities Module
    MIST-free utility functions for DCS World

    This module provides all utility functions needed by SAMSIM
    without requiring MIST dependency.

    Author: Claude Code
    Version: 1.0.0
]]

SAMSIM_Utils = {}
SAMSIM_Utils.Version = "1.0.0"

-- ============================================================================
-- Logging Configuration
-- ============================================================================
SAMSIM_Utils.LogLevel = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    NONE = 5,
}

SAMSIM_Utils.currentLogLevel = SAMSIM_Utils.LogLevel.INFO

-- ============================================================================
-- Logging Functions
-- ============================================================================

function SAMSIM_Utils.setLogLevel(level)
    SAMSIM_Utils.currentLogLevel = level
end

function SAMSIM_Utils.log(level, prefix, msg, ...)
    if level < SAMSIM_Utils.currentLogLevel then
        return
    end

    local args = {...}
    local formatted = msg
    if #args > 0 then
        formatted = string.format(msg, unpack(args))
    end

    local timestamp = string.format("[%.2f]", timer.getTime())
    local output = string.format("%s [SAMSIM][%s] %s", timestamp, prefix, formatted)

    if trigger and trigger.action and trigger.action.outText then
        trigger.action.outText(output, 10)
    end

    if env and env.info then
        env.info(output)
    end
end

function SAMSIM_Utils.debug(msg, ...)
    SAMSIM_Utils.log(SAMSIM_Utils.LogLevel.DEBUG, "DEBUG", msg, ...)
end

function SAMSIM_Utils.info(msg, ...)
    SAMSIM_Utils.log(SAMSIM_Utils.LogLevel.INFO, "INFO", msg, ...)
end

function SAMSIM_Utils.warn(msg, ...)
    SAMSIM_Utils.log(SAMSIM_Utils.LogLevel.WARN, "WARN", msg, ...)
end

function SAMSIM_Utils.error(msg, ...)
    SAMSIM_Utils.log(SAMSIM_Utils.LogLevel.ERROR, "ERROR", msg, ...)
end

-- ============================================================================
-- Table Utilities (MIST.utils replacement)
-- ============================================================================

--- Check if table contains a specific value
---@param tbl table
---@param value any
---@return boolean
function SAMSIM_Utils.tableContainsValue(tbl, value)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

--- Check if table contains a specific key
---@param tbl table
---@param key any
---@return boolean
function SAMSIM_Utils.tableContainsKey(tbl, key)
    if not tbl then return false end
    return tbl[key] ~= nil
end

--- Shallow copy a table
---@param tbl table
---@return table
function SAMSIM_Utils.shallowCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

--- Deep copy a table
---@param tbl table
---@return table
function SAMSIM_Utils.deepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            copy[k] = SAMSIM_Utils.deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--- Merge two tables (override wins)
---@param base table
---@param override table
---@return table
function SAMSIM_Utils.mergeTables(base, override)
    local result = SAMSIM_Utils.deepCopy(base)
    if not override then return result end

    for k, v in pairs(override) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = SAMSIM_Utils.mergeTables(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

--- Get table length (works with non-sequential tables)
---@param tbl table
---@return number
function SAMSIM_Utils.tableLength(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

--- Get table keys as array
---@param tbl table
---@return table
function SAMSIM_Utils.tableKeys(tbl)
    local keys = {}
    if not tbl then return keys end
    for k in pairs(tbl) do
        keys[#keys + 1] = k
    end
    return keys
end

--- Get table values as array
---@param tbl table
---@return table
function SAMSIM_Utils.tableValues(tbl)
    local values = {}
    if not tbl then return values end
    for _, v in pairs(tbl) do
        values[#values + 1] = v
    end
    return values
end

-- ============================================================================
-- Vector Operations (MIST.vec replacement)
-- ============================================================================

--- Add two Vec3
---@param a table {x, y, z}
---@param b table {x, y, z}
---@return table
function SAMSIM_Utils.vec3Add(a, b)
    return {
        x = (a.x or 0) + (b.x or 0),
        y = (a.y or 0) + (b.y or 0),
        z = (a.z or 0) + (b.z or 0),
    }
end

--- Subtract two Vec3 (a - b)
---@param a table {x, y, z}
---@param b table {x, y, z}
---@return table
function SAMSIM_Utils.vec3Sub(a, b)
    return {
        x = (a.x or 0) - (b.x or 0),
        y = (a.y or 0) - (b.y or 0),
        z = (a.z or 0) - (b.z or 0),
    }
end

--- Multiply Vec3 by scalar
---@param v table {x, y, z}
---@param scalar number
---@return table
function SAMSIM_Utils.vec3Mult(v, scalar)
    return {
        x = (v.x or 0) * scalar,
        y = (v.y or 0) * scalar,
        z = (v.z or 0) * scalar,
    }
end

--- Get magnitude of Vec3
---@param v table {x, y, z}
---@return number
function SAMSIM_Utils.vec3Mag(v)
    local x, y, z = v.x or 0, v.y or 0, v.z or 0
    return math.sqrt(x*x + y*y + z*z)
end

--- Get 2D magnitude (x, z plane)
---@param v table {x, y, z}
---@return number
function SAMSIM_Utils.vec3Mag2D(v)
    local x, z = v.x or 0, v.z or 0
    return math.sqrt(x*x + z*z)
end

--- Normalize Vec3
---@param v table {x, y, z}
---@return table
function SAMSIM_Utils.vec3Normalize(v)
    local mag = SAMSIM_Utils.vec3Mag(v)
    if mag == 0 then
        return {x = 0, y = 0, z = 0}
    end
    return {
        x = (v.x or 0) / mag,
        y = (v.y or 0) / mag,
        z = (v.z or 0) / mag,
    }
end

--- Dot product of two Vec3
---@param a table {x, y, z}
---@param b table {x, y, z}
---@return number
function SAMSIM_Utils.vec3Dot(a, b)
    return (a.x or 0) * (b.x or 0) +
           (a.y or 0) * (b.y or 0) +
           (a.z or 0) * (b.z or 0)
end

--- Cross product of two Vec3
---@param a table {x, y, z}
---@param b table {x, y, z}
---@return table
function SAMSIM_Utils.vec3Cross(a, b)
    return {
        x = (a.y or 0) * (b.z or 0) - (a.z or 0) * (b.y or 0),
        y = (a.z or 0) * (b.x or 0) - (a.x or 0) * (b.z or 0),
        z = (a.x or 0) * (b.y or 0) - (a.y or 0) * (b.x or 0),
    }
end

-- ============================================================================
-- Distance & Geometry
-- ============================================================================

--- Get 3D distance between two points
---@param pos1 table {x, y, z}
---@param pos2 table {x, y, z}
---@return number Distance in meters
function SAMSIM_Utils.getDistance3D(pos1, pos2)
    local diff = SAMSIM_Utils.vec3Sub(pos2, pos1)
    return SAMSIM_Utils.vec3Mag(diff)
end

--- Get 2D distance between two points (ignoring altitude)
---@param pos1 table {x, y, z}
---@param pos2 table {x, y, z}
---@return number Distance in meters
function SAMSIM_Utils.getDistance2D(pos1, pos2)
    local dx = (pos2.x or 0) - (pos1.x or 0)
    local dz = (pos2.z or 0) - (pos1.z or 0)
    return math.sqrt(dx*dx + dz*dz)
end

--- Get heading from one point to another (radians)
---@param from table {x, y, z}
---@param to table {x, y, z}
---@return number Heading in radians (0 = North, clockwise)
function SAMSIM_Utils.getHeading(from, to)
    local dx = (to.x or 0) - (from.x or 0)
    local dz = (to.z or 0) - (from.z or 0)
    return math.atan2(dx, dz)
end

--- Get bearing from one point to another (degrees)
---@param from table {x, y, z}
---@param to table {x, y, z}
---@return number Bearing in degrees (0-360)
function SAMSIM_Utils.getBearing(from, to)
    local heading = SAMSIM_Utils.getHeading(from, to)
    local degrees = math.deg(heading)
    if degrees < 0 then
        degrees = degrees + 360
    end
    return degrees
end

--- Get altitude from position
---@param pos table {x, y, z}
---@return number Altitude in meters
function SAMSIM_Utils.getAltitude(pos)
    return pos.y or 0
end

--- Get ground altitude at position using DCS terrain
---@param pos table {x, y, z}
---@return number Ground altitude in meters
function SAMSIM_Utils.getGroundAltitude(pos)
    if land and land.getHeight then
        return land.getHeight({x = pos.x, y = pos.z})
    end
    return 0
end

--- Get altitude above ground level
---@param pos table {x, y, z}
---@return number AGL in meters
function SAMSIM_Utils.getAGL(pos)
    local groundAlt = SAMSIM_Utils.getGroundAltitude(pos)
    return (pos.y or 0) - groundAlt
end

--- Check if point is inside a polygon (2D)
---@param point table {x, z}
---@param polygon table Array of {x, z} vertices
---@return boolean
function SAMSIM_Utils.pointInPolygon(point, polygon)
    if not polygon or #polygon < 3 then
        return false
    end

    local inside = false
    local j = #polygon

    for i = 1, #polygon do
        local xi, zi = polygon[i].x, polygon[i].z
        local xj, zj = polygon[j].x, polygon[j].z

        if ((zi > point.z) ~= (zj > point.z)) and
           (point.x < (xj - xi) * (point.z - zi) / (zj - zi) + xi) then
            inside = not inside
        end
        j = i
    end

    return inside
end

--- Check if point is inside a circle (2D)
---@param point table {x, z}
---@param center table {x, z}
---@param radius number
---@return boolean
function SAMSIM_Utils.pointInCircle(point, center, radius)
    local dist = SAMSIM_Utils.getDistance2D(point, center)
    return dist <= radius
end

--- Calculate angle between two vectors
---@param v1 table {x, y, z}
---@param v2 table {x, y, z}
---@return number Angle in radians
function SAMSIM_Utils.angleBetween(v1, v2)
    local dot = SAMSIM_Utils.vec3Dot(v1, v2)
    local mag1 = SAMSIM_Utils.vec3Mag(v1)
    local mag2 = SAMSIM_Utils.vec3Mag(v2)

    if mag1 == 0 or mag2 == 0 then
        return 0
    end

    local cosAngle = dot / (mag1 * mag2)
    cosAngle = math.max(-1, math.min(1, cosAngle))
    return math.acos(cosAngle)
end

-- ============================================================================
-- Unit/Group Database (MIST.DBs replacement)
-- ============================================================================

--- Get group by name
---@param name string
---@return table|nil Group object
function SAMSIM_Utils.getGroupByName(name)
    if not name then return nil end
    return Group.getByName(name)
end

--- Get unit by name
---@param name string
---@return table|nil Unit object
function SAMSIM_Utils.getUnitByName(name)
    if not name then return nil end
    return Unit.getByName(name)
end

--- Get all units in a group
---@param groupName string
---@return table Array of Unit objects
function SAMSIM_Utils.getGroupUnits(groupName)
    local group = SAMSIM_Utils.getGroupByName(groupName)
    if not group then return {} end
    return group:getUnits() or {}
end

--- Get unit position
---@param unitName string
---@return table|nil Position {x, y, z}
function SAMSIM_Utils.getUnitPosition(unitName)
    local unit = SAMSIM_Utils.getUnitByName(unitName)
    if not unit then return nil end
    return unit:getPoint()
end

--- Get group center position (average of all units)
---@param groupName string
---@return table|nil Position {x, y, z}
function SAMSIM_Utils.getGroupPosition(groupName)
    local units = SAMSIM_Utils.getGroupUnits(groupName)
    if #units == 0 then return nil end

    local sumX, sumY, sumZ = 0, 0, 0
    local count = 0

    for _, unit in ipairs(units) do
        if unit:isExist() then
            local pos = unit:getPoint()
            sumX = sumX + pos.x
            sumY = sumY + pos.y
            sumZ = sumZ + pos.z
            count = count + 1
        end
    end

    if count == 0 then return nil end

    return {
        x = sumX / count,
        y = sumY / count,
        z = sumZ / count,
    }
end

--- Get groups matching a pattern
---@param pattern string Lua pattern (e.g., "^SAM_")
---@return table Array of group names
function SAMSIM_Utils.getGroupsByPattern(pattern)
    local result = {}

    -- Iterate through all coalitions
    for _, coalitionSide in ipairs({coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL}) do
        local groups = coalition.getGroups(coalitionSide)
        if groups then
            for _, group in ipairs(groups) do
                local name = group:getName()
                if name and string.match(name, pattern) then
                    result[#result + 1] = name
                end
            end
        end
    end

    return result
end

--- Get units matching a pattern
---@param pattern string Lua pattern
---@return table Array of unit names
function SAMSIM_Utils.getUnitsByPattern(pattern)
    local result = {}

    for _, coalitionSide in ipairs({coalition.side.RED, coalition.side.BLUE, coalition.side.NEUTRAL}) do
        local groups = coalition.getGroups(coalitionSide)
        if groups then
            for _, group in ipairs(groups) do
                local units = group:getUnits()
                if units then
                    for _, unit in ipairs(units) do
                        local name = unit:getName()
                        if name and string.match(name, pattern) then
                            result[#result + 1] = name
                        end
                    end
                end
            end
        end
    end

    return result
end

--- Get unit type name
---@param unit table Unit object
---@return string Type name
function SAMSIM_Utils.getUnitTypeName(unit)
    if not unit then return "Unknown" end
    local desc = unit:getDesc()
    if desc and desc.typeName then
        return desc.typeName
    end
    return "Unknown"
end

--- Check if unit is alive
---@param unitName string
---@return boolean
function SAMSIM_Utils.isUnitAlive(unitName)
    local unit = SAMSIM_Utils.getUnitByName(unitName)
    if not unit then return false end
    return unit:isExist() and unit:getLife() > 0
end

--- Check if group is alive (at least one unit alive)
---@param groupName string
---@return boolean
function SAMSIM_Utils.isGroupAlive(groupName)
    local units = SAMSIM_Utils.getGroupUnits(groupName)
    for _, unit in ipairs(units) do
        if unit:isExist() and unit:getLife() > 0 then
            return true
        end
    end
    return false
end

-- ============================================================================
-- Alarm State Control
-- ============================================================================

SAMSIM_Utils.ALARM_STATE = {
    AUTO = 0,
    GREEN = 1,
    RED = 2,
}

--- Set unit alarm state
---@param unit table Unit object
---@param state number ALARM_STATE value
function SAMSIM_Utils.setUnitAlarmState(unit, state)
    if not unit or not unit:isExist() then return end

    local controller = unit:getController()
    if controller then
        if state == SAMSIM_Utils.ALARM_STATE.GREEN then
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
        elseif state == SAMSIM_Utils.ALARM_STATE.RED then
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        else
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.AUTO)
        end
    end
end

--- Set group alarm state
---@param group table Group object
---@param state number ALARM_STATE value
function SAMSIM_Utils.setGroupAlarmState(group, state)
    if not group then return end

    local controller = group:getController()
    if controller then
        if state == SAMSIM_Utils.ALARM_STATE.GREEN then
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.GREEN)
        elseif state == SAMSIM_Utils.ALARM_STATE.RED then
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.RED)
        else
            controller:setOption(AI.Option.Ground.id.ALARM_STATE, AI.Option.Ground.val.ALARM_STATE.AUTO)
        end
    end
end

--- Set group alarm state by name
---@param groupName string
---@param state number ALARM_STATE value
function SAMSIM_Utils.setGroupAlarmStateByName(groupName, state)
    local group = SAMSIM_Utils.getGroupByName(groupName)
    SAMSIM_Utils.setGroupAlarmState(group, state)
end

-- ============================================================================
-- ROE Control
-- ============================================================================

SAMSIM_Utils.ROE = {
    WEAPON_FREE = AI.Option.Ground.val.ROE.OPEN_FIRE,
    WEAPON_HOLD = AI.Option.Ground.val.ROE.WEAPON_HOLD,
    RETURN_FIRE = AI.Option.Ground.val.ROE.RETURN_FIRE,
}

--- Set group ROE
---@param group table Group object
---@param roe number ROE value
function SAMSIM_Utils.setGroupROE(group, roe)
    if not group then return end

    local controller = group:getController()
    if controller then
        controller:setOption(AI.Option.Ground.id.ROE, roe)
    end
end

--- Set group ROE by name
---@param groupName string
---@param roe number ROE value
function SAMSIM_Utils.setGroupROEByName(groupName, roe)
    local group = SAMSIM_Utils.getGroupByName(groupName)
    SAMSIM_Utils.setGroupROE(group, roe)
end

-- ============================================================================
-- Scheduler (timer wrapper)
-- ============================================================================

SAMSIM_Utils.scheduledTasks = {}
SAMSIM_Utils.nextTaskId = 1

--- Schedule a function to run after delay
---@param func function Function to call
---@param delay number Delay in seconds
---@param ... any Arguments to pass to function
---@return number Task ID
function SAMSIM_Utils.schedule(func, delay, ...)
    local args = {...}
    local taskId = SAMSIM_Utils.nextTaskId
    SAMSIM_Utils.nextTaskId = SAMSIM_Utils.nextTaskId + 1

    local function wrapper()
        SAMSIM_Utils.scheduledTasks[taskId] = nil
        return func(unpack(args))
    end

    local dcsId = timer.scheduleFunction(wrapper, nil, timer.getTime() + delay)
    SAMSIM_Utils.scheduledTasks[taskId] = {
        dcsId = dcsId,
        func = func,
        repeating = false,
    }

    return taskId
end

--- Schedule a repeating function
---@param func function Function to call
---@param interval number Interval in seconds
---@param ... any Arguments to pass to function
---@return number Task ID
function SAMSIM_Utils.scheduleRepeat(func, interval, ...)
    local args = {...}
    local taskId = SAMSIM_Utils.nextTaskId
    SAMSIM_Utils.nextTaskId = SAMSIM_Utils.nextTaskId + 1

    local function wrapper(_, time)
        local taskInfo = SAMSIM_Utils.scheduledTasks[taskId]
        if not taskInfo then
            return nil  -- Stop repeating
        end

        local success, result = pcall(func, unpack(args))
        if not success then
            SAMSIM_Utils.error("Scheduled task error: %s", tostring(result))
        end

        return time + interval  -- Schedule next execution
    end

    local dcsId = timer.scheduleFunction(wrapper, nil, timer.getTime() + interval)
    SAMSIM_Utils.scheduledTasks[taskId] = {
        dcsId = dcsId,
        func = func,
        interval = interval,
        repeating = true,
    }

    return taskId
end

--- Cancel a scheduled task
---@param taskId number
function SAMSIM_Utils.cancel(taskId)
    local taskInfo = SAMSIM_Utils.scheduledTasks[taskId]
    if taskInfo then
        if taskInfo.dcsId then
            timer.removeFunction(taskInfo.dcsId)
        end
        SAMSIM_Utils.scheduledTasks[taskId] = nil
    end
end

--- Get current mission time
---@return number Time in seconds
function SAMSIM_Utils.getTime()
    return timer.getTime()
end

--- Get absolute time (with date)
---@return number Absolute time in seconds
function SAMSIM_Utils.getAbsTime()
    return timer.getAbsTime()
end

-- ============================================================================
-- Random Utilities
-- ============================================================================

--- Get random number in range
---@param min number
---@param max number
---@return number
function SAMSIM_Utils.random(min, max)
    return min + math.random() * (max - min)
end

--- Get random integer in range (inclusive)
---@param min number
---@param max number
---@return number
function SAMSIM_Utils.randomInt(min, max)
    return math.random(min, max)
end

--- Get random element from array
---@param array table
---@return any
function SAMSIM_Utils.randomElement(array)
    if not array or #array == 0 then return nil end
    return array[math.random(#array)]
end

--- Shuffle array in place
---@param array table
function SAMSIM_Utils.shuffle(array)
    for i = #array, 2, -1 do
        local j = math.random(i)
        array[i], array[j] = array[j], array[i]
    end
end

-- ============================================================================
-- String Utilities
-- ============================================================================

--- Split string by delimiter
---@param str string
---@param delimiter string
---@return table
function SAMSIM_Utils.split(str, delimiter)
    local result = {}
    local pattern = string.format("([^%s]+)", delimiter)
    for match in string.gmatch(str, pattern) do
        result[#result + 1] = match
    end
    return result
end

--- Trim whitespace from string
---@param str string
---@return string
function SAMSIM_Utils.trim(str)
    return str:match("^%s*(.-)%s*$")
end

--- Check if string starts with prefix
---@param str string
---@param prefix string
---@return boolean
function SAMSIM_Utils.startsWith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

--- Check if string ends with suffix
---@param str string
---@param suffix string
---@return boolean
function SAMSIM_Utils.endsWith(str, suffix)
    return str:sub(-#suffix) == suffix
end

-- ============================================================================
-- Coordinate Conversion
-- ============================================================================

--- Convert meters to nautical miles
---@param meters number
---@return number
function SAMSIM_Utils.metersToNM(meters)
    return meters / 1852
end

--- Convert nautical miles to meters
---@param nm number
---@return number
function SAMSIM_Utils.nmToMeters(nm)
    return nm * 1852
end

--- Convert meters to feet
---@param meters number
---@return number
function SAMSIM_Utils.metersToFeet(meters)
    return meters * 3.28084
end

--- Convert feet to meters
---@param feet number
---@return number
function SAMSIM_Utils.feetToMeters(feet)
    return feet / 3.28084
end

--- Convert m/s to knots
---@param mps number
---@return number
function SAMSIM_Utils.mpsToKnots(mps)
    return mps * 1.94384
end

--- Convert knots to m/s
---@param knots number
---@return number
function SAMSIM_Utils.knotsToMps(knots)
    return knots / 1.94384
end

-- ============================================================================
-- Initialization
-- ============================================================================

function SAMSIM_Utils.init()
    SAMSIM_Utils.info("SAMSIM_Utils v%s initialized (MIST-free)", SAMSIM_Utils.Version)
    return true
end

-- Auto-initialize if in DCS environment
if timer then
    SAMSIM_Utils.init()
end

return SAMSIM_Utils
