--[[
    SAMSIM C2 (Command and Control) Module
    Phase 2: Multi-site coordination and command hierarchy

    Features:
    - Command Post (CP) with sector responsibility
    - Multi-site data fusion and track management
    - Target handoff between SAM sites
    - Engagement coordination
    - Threat assessment and prioritization
]]

SAMSIM_C2 = {}

-- Command Post types
SAMSIM_C2.CPType = {
    BATTALION = 1,      -- Controls 3-4 batteries
    REGIMENT = 2,       -- Controls 3-4 battalions
    BRIGADE = 3,        -- Controls multiple regiments
}

-- Engagement status
SAMSIM_C2.EngageStatus = {
    FREE = 0,           -- Target not engaged
    ASSIGNED = 1,       -- Target assigned to a site
    ENGAGING = 2,       -- Site actively engaging
    DESTROYED = 3,      -- Target confirmed destroyed
}

-- Target priority levels
SAMSIM_C2.Priority = {
    CRITICAL = 1,       -- High-value targets (AWACS, tankers, jamming)
    HIGH = 2,           -- Strike aircraft, cruise missiles
    MEDIUM = 3,         -- Fighter aircraft
    LOW = 4,            -- Helicopters, UAVs
    MINIMAL = 5,        -- Non-threat
}

-- Command Post class
SAMSIM_C2.CommandPost = {}
SAMSIM_C2.CommandPost.__index = SAMSIM_C2.CommandPost

function SAMSIM_C2.CommandPost:new(config)
    local cp = setmetatable({}, self)

    cp.id = config.id or "CP-1"
    cp.name = config.name or "Command Post"
    cp.type = config.type or SAMSIM_C2.CPType.BATTALION
    cp.position = config.position or {x = 0, y = 0, z = 0}

    -- Sector responsibility (in degrees from CP position)
    cp.sectorStart = config.sectorStart or 0
    cp.sectorEnd = config.sectorEnd or 360
    cp.maxRange = config.maxRange or 200000  -- 200km responsibility

    -- Subordinate SAM sites
    cp.sites = {}

    -- Fused track database
    cp.tracks = {}
    cp.trackIdCounter = 1

    -- Engagement coordination
    cp.engagements = {}

    -- Communications
    cp.dataLinkActive = true
    cp.updateRate = 2.0  -- seconds between track updates
    cp.lastUpdate = 0

    -- Settings
    cp.autoAssign = config.autoAssign or false
    cp.engagementPolicy = config.engagementPolicy or "WEAPONS_HOLD"
    -- WEAPONS_HOLD: Do not engage
    -- WEAPONS_TIGHT: Engage only if hostile (IFF confirmed)
    -- WEAPONS_FREE: Engage all non-friendly

    return cp
end

function SAMSIM_C2.CommandPost:registerSite(site)
    table.insert(self.sites, {
        id = site.siteId,
        site = site,
        status = "ACTIVE",
        lastHeard = timer.getTime(),
        assignedTargets = {},
    })

    env.info(string.format("[SAMSIM C2] Site %s registered with %s", site.siteId, self.id))
end

function SAMSIM_C2.CommandPost:unregisterSite(siteId)
    for i, s in ipairs(self.sites) do
        if s.id == siteId then
            table.remove(self.sites, i)
            env.info(string.format("[SAMSIM C2] Site %s unregistered from %s", siteId, self.id))
            return
        end
    end
end

-- Fuse tracks from all subordinate sites
function SAMSIM_C2.CommandPost:fuseTrackData()
    local fusedTracks = {}
    local trackAssociations = {}

    for _, siteData in ipairs(self.sites) do
        local site = siteData.site
        if not site then goto continue end

        -- Get contacts from this site
        local contacts = site.state and site.state.contacts or {}

        for _, contact in ipairs(contacts) do
            local associated = false

            -- Try to associate with existing fused track
            for trackId, track in pairs(fusedTracks) do
                local distance = self:calculateDistance(
                    contact.position or {x = contact.x, y = contact.y, z = contact.z},
                    track.position
                )

                -- Association threshold based on accuracy
                local threshold = 2000  -- 2km association gate

                if distance < threshold then
                    -- Update fused track with new data
                    self:updateFusedTrack(track, contact, siteData.id)
                    associated = true
                    break
                end
            end

            if not associated then
                -- Create new fused track
                local newTrack = self:createFusedTrack(contact, siteData.id)
                fusedTracks[newTrack.id] = newTrack
            end
        end

        ::continue::
    end

    -- Age out old tracks
    local currentTime = timer.getTime()
    for trackId, track in pairs(fusedTracks) do
        if currentTime - track.lastUpdate > 30 then
            -- Track is stale, mark as lost
            track.status = "LOST"
        end
    end

    self.tracks = fusedTracks
    return fusedTracks
end

function SAMSIM_C2.CommandPost:createFusedTrack(contact, sourceId)
    local track = {
        id = self.trackIdCounter,
        unitId = contact.id or contact.unitId,
        typeName = contact.typeName or "Unknown",
        category = contact.category or "AIR",

        position = contact.position or {
            x = contact.x or 0,
            y = contact.y or 0,
            z = contact.z or 0,
        },

        velocity = contact.velocity or {x = 0, y = 0, z = 0},
        heading = contact.heading or 0,
        speed = contact.speed or 0,
        altitude = contact.altitude or 0,

        -- Track quality
        sources = {sourceId},
        quality = 1,
        lastUpdate = timer.getTime(),
        firstSeen = timer.getTime(),

        -- IFF status
        iffStatus = contact.iffStatus or "UNKNOWN",

        -- Threat assessment
        priority = SAMSIM_C2.Priority.MEDIUM,
        threatLevel = 0,

        -- Engagement status
        engageStatus = SAMSIM_C2.EngageStatus.FREE,
        assignedSite = nil,

        status = "ACTIVE",
    }

    self.trackIdCounter = self.trackIdCounter + 1

    -- Assess threat
    self:assessThreat(track)

    return track
end

function SAMSIM_C2.CommandPost:updateFusedTrack(track, contact, sourceId)
    -- Update position with weighted average if multiple sources
    local weight = 0.7  -- Weight for new data

    if contact.position then
        track.position.x = track.position.x * (1 - weight) + contact.position.x * weight
        track.position.y = track.position.y * (1 - weight) + contact.position.y * weight
        track.position.z = track.position.z * (1 - weight) + contact.position.z * weight
    end

    if contact.velocity then
        track.velocity = contact.velocity
    end

    track.heading = contact.heading or track.heading
    track.speed = contact.speed or track.speed
    track.altitude = contact.altitude or track.altitude

    -- Add source if not already present
    local sourceFound = false
    for _, src in ipairs(track.sources) do
        if src == sourceId then
            sourceFound = true
            break
        end
    end
    if not sourceFound then
        table.insert(track.sources, sourceId)
    end

    -- Update quality based on number of sources
    track.quality = math.min(1.0, #track.sources * 0.3 + 0.4)
    track.lastUpdate = timer.getTime()
    track.status = "ACTIVE"

    -- Update IFF if better info available
    if contact.iffStatus and contact.iffStatus ~= "UNKNOWN" then
        track.iffStatus = contact.iffStatus
    end

    -- Re-assess threat
    self:assessThreat(track)
end

function SAMSIM_C2.CommandPost:assessThreat(track)
    local priority = SAMSIM_C2.Priority.MEDIUM
    local threatLevel = 50

    local typeName = track.typeName:lower()

    -- High-value air assets
    if typeName:find("awacs") or typeName:find("e%-3") or typeName:find("a%-50") then
        priority = SAMSIM_C2.Priority.CRITICAL
        threatLevel = 100
    elseif typeName:find("tanker") or typeName:find("kc%-") then
        priority = SAMSIM_C2.Priority.CRITICAL
        threatLevel = 95
    -- Jamming aircraft
    elseif typeName:find("prowler") or typeName:find("growler") or typeName:find("ea%-") then
        priority = SAMSIM_C2.Priority.CRITICAL
        threatLevel = 98
    -- Strike aircraft
    elseif typeName:find("f%-15e") or typeName:find("f%-16") or typeName:find("f%-18") or
           typeName:find("tornado") or typeName:find("su%-34") then
        priority = SAMSIM_C2.Priority.HIGH
        threatLevel = 80
    -- Cruise missiles
    elseif typeName:find("tomahawk") or typeName:find("agm%-86") or typeName:find("cruise") then
        priority = SAMSIM_C2.Priority.HIGH
        threatLevel = 90
    -- Fighter aircraft
    elseif typeName:find("f%-15") or typeName:find("f%-22") or typeName:find("su%-27") or
           typeName:find("mig%-29") or typeName:find("eurofighter") then
        priority = SAMSIM_C2.Priority.MEDIUM
        threatLevel = 60
    -- Helicopters
    elseif typeName:find("heli") or typeName:find("ah%-") or typeName:find("mi%-") then
        priority = SAMSIM_C2.Priority.LOW
        threatLevel = 40
    -- UAVs
    elseif typeName:find("uav") or typeName:find("drone") or typeName:find("mq%-") then
        priority = SAMSIM_C2.Priority.LOW
        threatLevel = 35
    end

    -- Modify based on behavior
    if track.speed > 300 then  -- Fast mover
        threatLevel = threatLevel + 10
    end

    -- Check if heading toward any of our sites
    for _, siteData in ipairs(self.sites) do
        local site = siteData.site
        if site and site.position then
            local bearing = self:calculateBearing(track.position, site.position)
            local headingDiff = math.abs(bearing - track.heading)
            if headingDiff > 180 then headingDiff = 360 - headingDiff end

            if headingDiff < 30 then  -- Heading toward site
                threatLevel = threatLevel + 20
                break
            end
        end
    end

    -- IFF status modifier
    if track.iffStatus == "HOSTILE" then
        threatLevel = threatLevel + 15
    elseif track.iffStatus == "FRIENDLY" then
        threatLevel = 0
        priority = SAMSIM_C2.Priority.MINIMAL
    end

    track.priority = priority
    track.threatLevel = math.min(100, threatLevel)
end

-- Assign target to optimal site
function SAMSIM_C2.CommandPost:assignTarget(trackId)
    local track = self.tracks[trackId]
    if not track then return false, "Track not found" end

    if track.engageStatus ~= SAMSIM_C2.EngageStatus.FREE then
        return false, "Track already assigned"
    end

    -- Find optimal site
    local bestSite = nil
    local bestScore = -1

    for _, siteData in ipairs(self.sites) do
        if siteData.status ~= "ACTIVE" then goto continue end

        local site = siteData.site
        if not site then goto continue end

        -- Check if target is in site's engagement envelope
        local inEnvelope, reason = self:checkEngagementEnvelope(site, track)
        if not inEnvelope then goto continue end

        -- Calculate engagement score
        local score = self:calculateEngagementScore(site, track, siteData)

        if score > bestScore then
            bestScore = score
            bestSite = siteData
        end

        ::continue::
    end

    if bestSite then
        track.engageStatus = SAMSIM_C2.EngageStatus.ASSIGNED
        track.assignedSite = bestSite.id
        table.insert(bestSite.assignedTargets, trackId)

        -- Send designation command to site
        self:sendDesignation(bestSite, track)

        env.info(string.format("[SAMSIM C2] Track %d assigned to %s", trackId, bestSite.id))
        return true, bestSite.id
    end

    return false, "No suitable site available"
end

function SAMSIM_C2.CommandPost:checkEngagementEnvelope(site, track)
    local config = site.config or {}
    local missileMaxRange = config.missileMaxRange or 45000
    local missileMinRange = config.missileMinRange or 7000
    local minAltitude = config.minAltitude or 100
    local maxAltitude = config.maxAltitude or 30000

    local distance = self:calculateDistance(track.position, site.position)

    if distance > missileMaxRange then
        return false, "Out of range (too far)"
    end

    if distance < missileMinRange then
        return false, "Out of range (too close)"
    end

    if track.altitude < minAltitude then
        return false, "Below minimum altitude"
    end

    if track.altitude > maxAltitude then
        return false, "Above maximum altitude"
    end

    return true
end

function SAMSIM_C2.CommandPost:calculateEngagementScore(site, track, siteData)
    local score = 100

    -- Distance factor (closer is better, but not too close)
    local distance = self:calculateDistance(track.position, site.position)
    local optimalRange = (site.config.missileMaxRange or 45000) * 0.6
    local rangeDeviation = math.abs(distance - optimalRange) / optimalRange
    score = score - rangeDeviation * 30

    -- Missiles available
    local missilesReady = site.state and site.state.missiles and site.state.missiles.ready or 0
    if missilesReady < 2 then
        score = score - 40
    elseif missilesReady < 4 then
        score = score - 20
    end

    -- Current engagement load
    local assignedCount = #siteData.assignedTargets
    score = score - assignedCount * 15

    -- Radar status (is site already tracking?)
    if site.state and site.state.track and site.state.track.valid then
        score = score - 25  -- Already engaged
    end

    -- Track quality from this site
    local hasDirectTrack = false
    for _, srcId in ipairs(track.sources) do
        if srcId == siteData.id then
            hasDirectTrack = true
            break
        end
    end
    if hasDirectTrack then
        score = score + 20
    end

    return score
end

function SAMSIM_C2.CommandPost:sendDesignation(siteData, track)
    local site = siteData.site
    if not site then return end

    -- Calculate bearing and range from site to target
    local bearing = self:calculateBearing(site.position, track.position)
    local range = self:calculateDistance(site.position, track.position)

    -- Send command through site's command interface
    if site.handleCommand then
        site:handleCommand({
            type = "DESIGNATE_C2",
            trackId = track.id,
            unitId = track.unitId,
            azimuth = bearing,
            range = range,
            altitude = track.altitude,
            priority = track.priority,
        })
    end
end

-- Target handoff between sites
function SAMSIM_C2.CommandPost:handoffTarget(trackId, fromSiteId, toSiteId)
    local track = self.tracks[trackId]
    if not track then return false, "Track not found" end

    local fromSite, toSite
    for _, s in ipairs(self.sites) do
        if s.id == fromSiteId then fromSite = s end
        if s.id == toSiteId then toSite = s end
    end

    if not fromSite or not toSite then
        return false, "Site not found"
    end

    -- Remove from old site
    for i, tid in ipairs(fromSite.assignedTargets) do
        if tid == trackId then
            table.remove(fromSite.assignedTargets, i)
            break
        end
    end

    -- Send drop command to old site
    if fromSite.site and fromSite.site.handleCommand then
        fromSite.site:handleCommand({type = "DROP_TRACK"})
    end

    -- Assign to new site
    track.assignedSite = toSiteId
    table.insert(toSite.assignedTargets, trackId)

    -- Send designation to new site
    self:sendDesignation(toSite, track)

    env.info(string.format("[SAMSIM C2] Track %d handed off from %s to %s",
        trackId, fromSiteId, toSiteId))

    return true
end

-- Auto-assign targets based on threat level
function SAMSIM_C2.CommandPost:autoAssignTargets()
    if not self.autoAssign then return end
    if self.engagementPolicy == "WEAPONS_HOLD" then return end

    -- Sort tracks by threat level
    local sortedTracks = {}
    for trackId, track in pairs(self.tracks) do
        if track.engageStatus == SAMSIM_C2.EngageStatus.FREE and
           track.status == "ACTIVE" then

            -- Check engagement policy
            if self.engagementPolicy == "WEAPONS_TIGHT" then
                if track.iffStatus ~= "HOSTILE" then
                    goto continue
                end
            elseif self.engagementPolicy == "WEAPONS_FREE" then
                if track.iffStatus == "FRIENDLY" then
                    goto continue
                end
            end

            table.insert(sortedTracks, {id = trackId, threat = track.threatLevel})
        end
        ::continue::
    end

    table.sort(sortedTracks, function(a, b) return a.threat > b.threat end)

    -- Assign top threats
    for _, t in ipairs(sortedTracks) do
        if t.threat >= 60 then  -- Only auto-assign high threats
            self:assignTarget(t.id)
        end
    end
end

-- Update loop
function SAMSIM_C2.CommandPost:update()
    local currentTime = timer.getTime()

    if currentTime - self.lastUpdate < self.updateRate then
        return
    end

    self.lastUpdate = currentTime

    -- Fuse track data from all sites
    self:fuseTrackData()

    -- Auto-assign if enabled
    self:autoAssignTargets()

    -- Update engagement status
    for trackId, track in pairs(self.tracks) do
        if track.engageStatus == SAMSIM_C2.EngageStatus.ASSIGNED then
            -- Check if assigned site is engaging
            for _, s in ipairs(self.sites) do
                if s.id == track.assignedSite and s.site then
                    local siteState = s.site.state
                    if siteState and siteState.track and siteState.track.valid then
                        if siteState.track.unitId == track.unitId then
                            track.engageStatus = SAMSIM_C2.EngageStatus.ENGAGING
                        end
                    end
                end
            end
        end
    end
end

-- Get state for export
function SAMSIM_C2.CommandPost:getState()
    local siteStates = {}
    for _, s in ipairs(self.sites) do
        table.insert(siteStates, {
            id = s.id,
            status = s.status,
            assignedCount = #s.assignedTargets,
        })
    end

    local trackStates = {}
    for trackId, track in pairs(self.tracks) do
        table.insert(trackStates, {
            id = track.id,
            typeName = track.typeName,
            position = track.position,
            altitude = track.altitude,
            speed = track.speed,
            heading = track.heading,
            priority = track.priority,
            threatLevel = track.threatLevel,
            iffStatus = track.iffStatus,
            engageStatus = track.engageStatus,
            assignedSite = track.assignedSite,
            quality = track.quality,
            sources = #track.sources,
        })
    end

    return {
        id = self.id,
        name = self.name,
        type = self.type,
        sectorStart = self.sectorStart,
        sectorEnd = self.sectorEnd,
        maxRange = self.maxRange,
        engagementPolicy = self.engagementPolicy,
        autoAssign = self.autoAssign,
        sites = siteStates,
        tracks = trackStates,
        dataLinkActive = self.dataLinkActive,
    }
end

-- Utility functions
function SAMSIM_C2.CommandPost:calculateDistance(pos1, pos2)
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function SAMSIM_C2.CommandPost:calculateBearing(from, to)
    local dx = to.x - from.x
    local dz = to.z - from.z
    local bearing = math.deg(math.atan2(dx, dz))
    if bearing < 0 then bearing = bearing + 360 end
    return bearing
end

-- Command handling
function SAMSIM_C2.CommandPost:handleCommand(cmd)
    if cmd.type == "SET_POLICY" then
        self.engagementPolicy = cmd.policy
        env.info(string.format("[SAMSIM C2] Policy set to %s", cmd.policy))

    elseif cmd.type == "SET_AUTO_ASSIGN" then
        self.autoAssign = cmd.enabled
        env.info(string.format("[SAMSIM C2] Auto-assign %s", cmd.enabled and "enabled" or "disabled"))

    elseif cmd.type == "ASSIGN_TARGET" then
        return self:assignTarget(cmd.trackId)

    elseif cmd.type == "HANDOFF" then
        return self:handoffTarget(cmd.trackId, cmd.fromSite, cmd.toSite)

    elseif cmd.type == "RELEASE_TARGET" then
        local track = self.tracks[cmd.trackId]
        if track then
            track.engageStatus = SAMSIM_C2.EngageStatus.FREE
            track.assignedSite = nil
        end
    end
end


--[[
    Network/DataLink simulation
]]
SAMSIM_C2.DataLink = {}
SAMSIM_C2.DataLink.__index = SAMSIM_C2.DataLink

function SAMSIM_C2.DataLink:new(config)
    local dl = setmetatable({}, self)

    dl.nodes = {}
    dl.messageQueue = {}
    dl.latency = config.latency or 0.5  -- seconds
    dl.reliability = config.reliability or 0.98
    dl.bandwidth = config.bandwidth or 100  -- tracks per second

    return dl
end

function SAMSIM_C2.DataLink:addNode(node)
    self.nodes[node.id] = node
end

function SAMSIM_C2.DataLink:sendMessage(fromId, toId, message)
    if math.random() > self.reliability then
        return false, "Message lost"
    end

    table.insert(self.messageQueue, {
        from = fromId,
        to = toId,
        message = message,
        sendTime = timer.getTime(),
        deliveryTime = timer.getTime() + self.latency,
    })

    return true
end

function SAMSIM_C2.DataLink:update()
    local currentTime = timer.getTime()
    local delivered = {}

    for i, msg in ipairs(self.messageQueue) do
        if currentTime >= msg.deliveryTime then
            local node = self.nodes[msg.to]
            if node and node.receiveMessage then
                node:receiveMessage(msg.from, msg.message)
            end
            table.insert(delivered, i)
        end
    end

    -- Remove delivered messages
    for i = #delivered, 1, -1 do
        table.remove(self.messageQueue, delivered[i])
    end
end


-- Global C2 manager
SAMSIM_C2.Manager = {
    commandPosts = {},
    dataLinks = {},
}

function SAMSIM_C2.Manager:createCommandPost(config)
    local cp = SAMSIM_C2.CommandPost:new(config)
    self.commandPosts[cp.id] = cp
    return cp
end

function SAMSIM_C2.Manager:update()
    for _, cp in pairs(self.commandPosts) do
        cp:update()
    end

    for _, dl in pairs(self.dataLinks) do
        dl:update()
    end
end

function SAMSIM_C2.Manager:getState()
    local states = {}
    for id, cp in pairs(self.commandPosts) do
        states[id] = cp:getState()
    end
    return states
end

env.info("[SAMSIM] C2 module loaded")
