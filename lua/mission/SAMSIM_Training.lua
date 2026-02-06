--[[
    SAMSIM Training Module
    Phase 3: Training scenarios, engagement recording, and analysis

    Features:
    - Predefined training scenarios
    - Dynamic target generation
    - Engagement recording and replay
    - Performance metrics and scoring
    - Debriefing tools
]]

SAMSIM_Training = {}

-- Training difficulty levels
SAMSIM_Training.Difficulty = {
    BEGINNER = 1,
    INTERMEDIATE = 2,
    ADVANCED = 3,
    EXPERT = 4,
}

-- Scenario types
SAMSIM_Training.ScenarioType = {
    SINGLE_TARGET = 1,
    MULTI_TARGET = 2,
    ECM_ENVIRONMENT = 3,
    LOW_ALTITUDE = 4,
    SATURATION_ATTACK = 5,
    MIXED_RAID = 6,
    SEAD_MISSION = 7,
}

--[[
    Training Scenario Definition
]]
SAMSIM_Training.Scenarios = {
    -- Beginner scenarios
    {
        id = "basic_intercept",
        name = "Basic Intercept",
        description = "Single high-altitude target on predictable course",
        difficulty = 1,
        type = 1,
        targets = {
            {
                type = "F-16C",
                altitude = 8000,
                speed = 250,
                course = "INBOUND",
                startRange = 80000,
                ecm = false,
            }
        },
        successCriteria = {
            killsRequired = 1,
            maxMissiles = 2,
            maxTime = 180,
        },
        hints = {
            "Wait for target to enter engagement envelope",
            "Maintain track quality above 80%",
            "Launch when Pk exceeds 60%",
        },
    },

    {
        id = "two_targets",
        name = "Two Target Engagement",
        description = "Engage two targets sequentially",
        difficulty = 1,
        type = 2,
        targets = {
            {
                type = "F-15C",
                altitude = 7000,
                speed = 280,
                course = "INBOUND",
                startRange = 70000,
                ecm = false,
                delay = 0,
            },
            {
                type = "F-15C",
                altitude = 7500,
                speed = 280,
                course = "INBOUND",
                startRange = 75000,
                ecm = false,
                delay = 30,
            }
        },
        successCriteria = {
            killsRequired = 2,
            maxMissiles = 4,
            maxTime = 300,
        },
        hints = {
            "Prioritize the closer target first",
            "Prepare to re-engage quickly",
        },
    },

    -- Intermediate scenarios
    {
        id = "ecm_target",
        name = "ECM Environment",
        description = "Engage target using electronic countermeasures",
        difficulty = 2,
        type = 3,
        targets = {
            {
                type = "EA-18G",
                altitude = 9000,
                speed = 300,
                course = "STANDOFF",
                startRange = 60000,
                ecm = true,
                ecmType = "NOISE_SPOT",
                ecmPower = 28,
            }
        },
        successCriteria = {
            killsRequired = 1,
            maxMissiles = 3,
            maxTime = 240,
        },
        hints = {
            "Enable ECCM features",
            "Wait for burn-through range",
            "Use frequency agility",
        },
    },

    {
        id = "low_flyer",
        name = "Low Altitude Intercept",
        description = "Engage low-flying attack aircraft",
        difficulty = 2,
        type = 4,
        targets = {
            {
                type = "Tornado IDS",
                altitude = 200,
                speed = 280,
                course = "TERRAIN_FOLLOW",
                startRange = 40000,
                ecm = false,
            }
        },
        successCriteria = {
            killsRequired = 1,
            maxMissiles = 2,
            maxTime = 120,
        },
        hints = {
            "Watch for terrain masking",
            "Quick reaction required",
            "Predict pop-up location",
        },
    },

    -- Advanced scenarios
    {
        id = "saturation",
        name = "Saturation Attack",
        description = "Multiple simultaneous targets from different directions",
        difficulty = 3,
        type = 5,
        targets = {
            {type = "F-16C", altitude = 6000, speed = 300, azimuth = 0, startRange = 50000, ecm = false, delay = 0},
            {type = "F-16C", altitude = 6500, speed = 300, azimuth = 45, startRange = 55000, ecm = false, delay = 5},
            {type = "F-16C", altitude = 5500, speed = 300, azimuth = 315, startRange = 52000, ecm = false, delay = 10},
            {type = "F-16C", altitude = 7000, speed = 300, azimuth = 90, startRange = 48000, ecm = false, delay = 15},
        },
        successCriteria = {
            killsRequired = 3,
            maxMissiles = 8,
            maxTime = 300,
        },
        hints = {
            "Prioritize by threat level",
            "Use C2 for target assignment",
            "Manage missile inventory",
        },
    },

    {
        id = "mixed_raid",
        name = "Mixed Raid",
        description = "Fighter escort with strike package",
        difficulty = 3,
        type = 6,
        targets = {
            -- Escort fighters
            {type = "F-15C", altitude = 9000, speed = 350, course = "SWEEP", startRange = 70000, ecm = false, role = "ESCORT"},
            {type = "F-15C", altitude = 9000, speed = 350, course = "SWEEP", startRange = 72000, ecm = false, role = "ESCORT"},
            -- Strike aircraft
            {type = "F-15E", altitude = 5000, speed = 280, course = "INBOUND", startRange = 80000, ecm = true, role = "STRIKE", delay = 30},
            {type = "F-15E", altitude = 5000, speed = 280, course = "INBOUND", startRange = 82000, ecm = true, role = "STRIKE", delay = 30},
        },
        successCriteria = {
            killsRequired = 2,
            strikeKillsRequired = 2,  -- Must kill strike aircraft
            maxMissiles = 8,
            maxTime = 360,
        },
        hints = {
            "Strike aircraft are priority targets",
            "Escorts may try to draw fire",
            "Watch for ECM from strike package",
        },
    },

    -- Expert scenarios
    {
        id = "sead_defense",
        name = "SEAD Defense",
        description = "Survive coordinated SEAD attack with ARM shooters",
        difficulty = 4,
        type = 7,
        targets = {
            {type = "F-16CJ", altitude = 7000, speed = 350, course = "POPUP", startRange = 80000, ecm = true, role = "SEAD", hasARM = true},
            {type = "F-16CJ", altitude = 7500, speed = 350, course = "POPUP", startRange = 85000, ecm = true, role = "SEAD", hasARM = true},
            {type = "EA-18G", altitude = 10000, speed = 300, course = "STANDOFF", startRange = 100000, ecm = true, ecmType = "DRFM", role = "JAMMER"},
        },
        successCriteria = {
            killsRequired = 1,
            survive = true,  -- Must survive ARM attack
            maxMissiles = 6,
            maxTime = 300,
        },
        hints = {
            "Use emission control",
            "Alternate radar on/off",
            "Engage when SEAD aircraft commits",
            "Be ready to shut down if ARM detected",
        },
    },
}


--[[
    Engagement Recorder
]]
SAMSIM_Training.Recorder = {}
SAMSIM_Training.Recorder.__index = SAMSIM_Training.Recorder

function SAMSIM_Training.Recorder:new()
    local recorder = setmetatable({}, self)

    recorder.recording = false
    recorder.startTime = 0
    recorder.events = {}
    recorder.snapshots = {}
    recorder.snapshotInterval = 1.0  -- seconds

    return recorder
end

function SAMSIM_Training.Recorder:start()
    self.recording = true
    self.startTime = timer.getTime()
    self.events = {}
    self.snapshots = {}

    self:recordEvent("RECORDING_START", {})
    env.info("[SAMSIM Training] Recording started")
end

function SAMSIM_Training.Recorder:stop()
    self:recordEvent("RECORDING_STOP", {})
    self.recording = false
    env.info("[SAMSIM Training] Recording stopped")
    return self:getRecording()
end

function SAMSIM_Training.Recorder:recordEvent(eventType, data)
    if not self.recording then return end

    table.insert(self.events, {
        time = timer.getTime() - self.startTime,
        type = eventType,
        data = data,
    })
end

function SAMSIM_Training.Recorder:recordSnapshot(state)
    if not self.recording then return end

    table.insert(self.snapshots, {
        time = timer.getTime() - self.startTime,
        state = self:deepCopy(state),
    })
end

function SAMSIM_Training.Recorder:deepCopy(obj)
    if type(obj) ~= 'table' then return obj end
    local copy = {}
    for k, v in pairs(obj) do
        copy[k] = self:deepCopy(v)
    end
    return copy
end

function SAMSIM_Training.Recorder:getRecording()
    return {
        duration = timer.getTime() - self.startTime,
        events = self.events,
        snapshots = self.snapshots,
    }
end

-- Event types to record
SAMSIM_Training.EventTypes = {
    -- Radar events
    RADAR_POWER_ON = "RADAR_POWER_ON",
    RADAR_POWER_OFF = "RADAR_POWER_OFF",
    RADAR_MODE_CHANGE = "RADAR_MODE_CHANGE",
    TARGET_DETECTED = "TARGET_DETECTED",
    TARGET_LOST = "TARGET_LOST",
    TRACK_ACQUIRED = "TRACK_ACQUIRED",
    TRACK_LOST = "TRACK_LOST",

    -- Engagement events
    TARGET_DESIGNATED = "TARGET_DESIGNATED",
    MISSILE_LAUNCH = "MISSILE_LAUNCH",
    MISSILE_GUIDANCE = "MISSILE_GUIDANCE",
    MISSILE_TERMINAL = "MISSILE_TERMINAL",
    MISSILE_HIT = "MISSILE_HIT",
    MISSILE_MISS = "MISSILE_MISS",

    -- ECM events
    JAMMING_DETECTED = "JAMMING_DETECTED",
    JAMMING_BURNTHROUGH = "JAMMING_BURNTHROUGH",
    ECCM_ACTIVATED = "ECCM_ACTIVATED",
    CHAFF_DETECTED = "CHAFF_DETECTED",

    -- C2 events
    TARGET_ASSIGNED = "TARGET_ASSIGNED",
    TARGET_HANDOFF = "TARGET_HANDOFF",

    -- Threat events
    ARM_DETECTED = "ARM_DETECTED",
    ARM_IMPACT = "ARM_IMPACT",
    EMCON_ACTIVATED = "EMCON_ACTIVATED",
}


--[[
    Performance Metrics
]]
SAMSIM_Training.Metrics = {}
SAMSIM_Training.Metrics.__index = SAMSIM_Training.Metrics

function SAMSIM_Training.Metrics:new()
    local metrics = setmetatable({}, self)

    metrics.startTime = 0
    metrics.endTime = 0

    -- Engagement metrics
    metrics.targetsDetected = 0
    metrics.targetsTracked = 0
    metrics.targetsEngaged = 0
    metrics.targetsDestroyed = 0
    metrics.targetsSurvived = 0

    -- Missile metrics
    metrics.missilesLaunched = 0
    metrics.missilesHit = 0
    metrics.missilesMissed = 0
    metrics.missilesWasted = 0  -- Launched but target already destroyed

    -- Timing metrics
    metrics.avgDetectionTime = 0
    metrics.avgTrackTime = 0
    metrics.avgEngagementTime = 0
    metrics.avgReactionTime = 0

    -- Accuracy metrics
    metrics.trackQualityAvg = 0
    metrics.pkAtLaunch = {}
    metrics.missDistances = {}

    -- ECM metrics
    metrics.jammingEncountered = 0
    metrics.jammingDefeated = 0
    metrics.chaffEncountered = 0

    -- Survival metrics
    metrics.armLaunched = 0
    metrics.armEvaded = 0
    metrics.siteSurvived = true

    -- Detailed event log
    metrics.eventLog = {}

    return metrics
end

function SAMSIM_Training.Metrics:recordDetection(targetId, time)
    self.targetsDetected = self.targetsDetected + 1
    table.insert(self.eventLog, {
        time = time,
        event = "DETECTION",
        targetId = targetId,
    })
end

function SAMSIM_Training.Metrics:recordTrackAcquisition(targetId, time, quality)
    self.targetsTracked = self.targetsTracked + 1
    table.insert(self.eventLog, {
        time = time,
        event = "TRACK",
        targetId = targetId,
        quality = quality,
    })
end

function SAMSIM_Training.Metrics:recordLaunch(targetId, time, pk, missileId)
    self.missilesLaunched = self.missilesLaunched + 1
    self.targetsEngaged = self.targetsEngaged + 1
    table.insert(self.pkAtLaunch, pk)
    table.insert(self.eventLog, {
        time = time,
        event = "LAUNCH",
        targetId = targetId,
        pk = pk,
        missileId = missileId,
    })
end

function SAMSIM_Training.Metrics:recordHit(targetId, time, missileId, missDistance)
    self.missilesHit = self.missilesHit + 1
    self.targetsDestroyed = self.targetsDestroyed + 1
    table.insert(self.missDistances, missDistance or 0)
    table.insert(self.eventLog, {
        time = time,
        event = "HIT",
        targetId = targetId,
        missileId = missileId,
        missDistance = missDistance,
    })
end

function SAMSIM_Training.Metrics:recordMiss(targetId, time, missileId, missDistance)
    self.missilesMissed = self.missilesMissed + 1
    table.insert(self.missDistances, missDistance)
    table.insert(self.eventLog, {
        time = time,
        event = "MISS",
        targetId = targetId,
        missileId = missileId,
        missDistance = missDistance,
    })
end

function SAMSIM_Training.Metrics:calculateScore()
    local score = 0

    -- Base score for kills
    score = score + self.targetsDestroyed * 100

    -- Efficiency bonus (kills per missile)
    if self.missilesLaunched > 0 then
        local efficiency = self.missilesHit / self.missilesLaunched
        score = score + math.floor(efficiency * 50)
    end

    -- Pk bonus (average Pk at launch)
    if #self.pkAtLaunch > 0 then
        local avgPk = 0
        for _, pk in ipairs(self.pkAtLaunch) do
            avgPk = avgPk + pk
        end
        avgPk = avgPk / #self.pkAtLaunch
        score = score + math.floor(avgPk * 30)
    end

    -- Reaction time bonus
    if self.avgReactionTime > 0 and self.avgReactionTime < 30 then
        score = score + math.floor((30 - self.avgReactionTime) * 2)
    end

    -- Survival bonus
    if self.siteSurvived then
        score = score + 50
    end

    -- ECM defeat bonus
    score = score + self.jammingDefeated * 20

    -- Penalty for missed missiles
    score = score - self.missilesMissed * 10

    -- Penalty for wasted missiles
    score = score - self.missilesWasted * 15

    return math.max(0, score)
end

function SAMSIM_Training.Metrics:getGrade()
    local score = self:calculateScore()

    if score >= 250 then return "A+", "Outstanding"
    elseif score >= 200 then return "A", "Excellent"
    elseif score >= 170 then return "B+", "Very Good"
    elseif score >= 140 then return "B", "Good"
    elseif score >= 110 then return "C+", "Above Average"
    elseif score >= 80 then return "C", "Average"
    elseif score >= 50 then return "D", "Below Average"
    else return "F", "Failed"
    end
end

function SAMSIM_Training.Metrics:getSummary()
    local grade, gradeText = self:getGrade()

    return {
        score = self:calculateScore(),
        grade = grade,
        gradeText = gradeText,

        -- Kill stats
        targetsDetected = self.targetsDetected,
        targetsTracked = self.targetsTracked,
        targetsDestroyed = self.targetsDestroyed,
        targetsSurvived = self.targetsSurvived,

        -- Missile stats
        missilesLaunched = self.missilesLaunched,
        missilesHit = self.missilesHit,
        missilesMissed = self.missilesMissed,
        hitRate = self.missilesLaunched > 0 and
            (self.missilesHit / self.missilesLaunched * 100) or 0,

        -- Timing
        avgReactionTime = self.avgReactionTime,
        engagementDuration = self.endTime - self.startTime,

        -- ECM
        jammingEncountered = self.jammingEncountered,
        jammingDefeated = self.jammingDefeated,

        -- Survival
        siteSurvived = self.siteSurvived,
        armEvaded = self.armEvaded,
    }
end


--[[
    Training Session Manager
]]
SAMSIM_Training.Session = {}
SAMSIM_Training.Session.__index = SAMSIM_Training.Session

function SAMSIM_Training.Session:new(scenario)
    local session = setmetatable({}, self)

    session.scenario = scenario
    session.state = "READY"  -- READY, RUNNING, PAUSED, COMPLETE, FAILED
    session.startTime = 0
    session.elapsedTime = 0
    session.pauseTime = 0

    session.recorder = SAMSIM_Training.Recorder:new()
    session.metrics = SAMSIM_Training.Metrics:new()

    session.spawnedTargets = {}
    session.activeTargets = {}
    session.completedObjectives = {}

    session.hints = scenario.hints or {}
    session.currentHint = 1

    return session
end

function SAMSIM_Training.Session:start()
    if self.state ~= "READY" then return false end

    self.state = "RUNNING"
    self.startTime = timer.getTime()
    self.metrics.startTime = self.startTime

    self.recorder:start()

    -- Spawn initial targets
    self:spawnTargets()

    env.info(string.format("[SAMSIM Training] Session started: %s", self.scenario.name))
    return true
end

function SAMSIM_Training.Session:pause()
    if self.state ~= "RUNNING" then return false end

    self.state = "PAUSED"
    self.pauseTime = timer.getTime()

    return true
end

function SAMSIM_Training.Session:resume()
    if self.state ~= "PAUSED" then return false end

    self.state = "RUNNING"
    -- Adjust start time for pause duration
    self.startTime = self.startTime + (timer.getTime() - self.pauseTime)

    return true
end

function SAMSIM_Training.Session:stop()
    self.state = "COMPLETE"
    self.metrics.endTime = timer.getTime()

    local recording = self.recorder:stop()
    local summary = self.metrics:getSummary()

    -- Clean up spawned targets
    self:cleanupTargets()

    env.info(string.format("[SAMSIM Training] Session complete. Score: %d, Grade: %s",
        summary.score, summary.grade))

    return {
        recording = recording,
        summary = summary,
        scenario = self.scenario,
    }
end

function SAMSIM_Training.Session:spawnTargets()
    for i, targetDef in ipairs(self.scenario.targets) do
        local spawnTime = self.startTime + (targetDef.delay or 0)

        -- Schedule target spawn
        timer.scheduleFunction(function()
            self:spawnSingleTarget(targetDef, i)
        end, nil, spawnTime)
    end
end

function SAMSIM_Training.Session:spawnSingleTarget(targetDef, index)
    -- Calculate spawn position
    local azimuth = targetDef.azimuth or math.random(0, 359)
    local range = targetDef.startRange or 80000

    local spawnPos = {
        x = math.sin(math.rad(azimuth)) * range,
        y = targetDef.altitude or 5000,
        z = math.cos(math.rad(azimuth)) * range,
    }

    -- Create target data
    local target = {
        id = index,
        type = targetDef.type,
        position = spawnPos,
        altitude = targetDef.altitude,
        speed = targetDef.speed,
        heading = (azimuth + 180) % 360,  -- Heading toward center
        ecm = targetDef.ecm,
        ecmType = targetDef.ecmType,
        role = targetDef.role,
        hasARM = targetDef.hasARM,
        state = "ACTIVE",
        spawnTime = timer.getTime(),
    }

    table.insert(self.spawnedTargets, target)
    table.insert(self.activeTargets, target)

    self.recorder:recordEvent("TARGET_SPAWNED", target)

    env.info(string.format("[SAMSIM Training] Target spawned: %s at %d°, %dm",
        targetDef.type, azimuth, range))

    return target
end

function SAMSIM_Training.Session:cleanupTargets()
    -- Remove spawned targets
    for _, target in ipairs(self.spawnedTargets) do
        target.state = "REMOVED"
    end
    self.spawnedTargets = {}
    self.activeTargets = {}
end

function SAMSIM_Training.Session:update()
    if self.state ~= "RUNNING" then return end

    self.elapsedTime = timer.getTime() - self.startTime

    -- Update active targets
    for _, target in ipairs(self.activeTargets) do
        self:updateTarget(target)
    end

    -- Check success/failure conditions
    self:checkObjectives()

    -- Record snapshot
    self.recorder:recordSnapshot({
        time = self.elapsedTime,
        targets = self.activeTargets,
        metrics = self.metrics:getSummary(),
    })
end

function SAMSIM_Training.Session:updateTarget(target)
    if target.state ~= "ACTIVE" then return end

    local dt = 1.0  -- Assume 1 second update interval

    -- Update position based on heading and speed
    local headingRad = math.rad(target.heading)
    target.position.x = target.position.x + math.sin(headingRad) * target.speed * dt
    target.position.z = target.position.z + math.cos(headingRad) * target.speed * dt

    -- Update course behavior
    if target.course == "INBOUND" then
        -- Head toward origin
        target.heading = math.deg(math.atan2(-target.position.x, -target.position.z))
    elseif target.course == "TERRAIN_FOLLOW" then
        -- Vary altitude
        target.altitude = target.altitude + math.sin(self.elapsedTime * 0.5) * 10
    end
end

function SAMSIM_Training.Session:checkObjectives()
    local criteria = self.scenario.successCriteria

    -- Check time limit
    if criteria.maxTime and self.elapsedTime > criteria.maxTime then
        self.state = "FAILED"
        self.recorder:recordEvent("TIME_LIMIT_EXCEEDED", {})
        return
    end

    -- Check kills required
    if self.metrics.targetsDestroyed >= (criteria.killsRequired or 0) then
        -- Check if all strike targets killed (if required)
        if criteria.strikeKillsRequired then
            -- Additional check for strike kills
        else
            self.state = "COMPLETE"
            self.recorder:recordEvent("OBJECTIVES_COMPLETE", {})
        end
    end

    -- Check survival requirement
    if criteria.survive and not self.metrics.siteSurvived then
        self.state = "FAILED"
        self.recorder:recordEvent("SITE_DESTROYED", {})
    end
end

function SAMSIM_Training.Session:onTargetDestroyed(targetId)
    for i, target in ipairs(self.activeTargets) do
        if target.id == targetId then
            target.state = "DESTROYED"
            table.remove(self.activeTargets, i)
            break
        end
    end
end

function SAMSIM_Training.Session:getNextHint()
    if self.currentHint > #self.hints then
        return nil
    end

    local hint = self.hints[self.currentHint]
    self.currentHint = self.currentHint + 1
    return hint
end

function SAMSIM_Training.Session:getState()
    return {
        scenarioId = self.scenario.id,
        scenarioName = self.scenario.name,
        state = self.state,
        elapsedTime = self.elapsedTime,
        activeTargets = #self.activeTargets,
        metrics = self.metrics:getSummary(),
        hint = self.hints[self.currentHint],
    }
end


--[[
    Debriefing Tools
]]
SAMSIM_Training.Debrief = {}

function SAMSIM_Training.Debrief:generate(sessionResult)
    local summary = sessionResult.summary
    local scenario = sessionResult.scenario
    local recording = sessionResult.recording

    local debrief = {
        title = scenario.name .. " - Debriefing",
        date = os.date("%Y-%m-%d %H:%M"),
        duration = string.format("%d:%02d", math.floor(summary.engagementDuration / 60),
            math.floor(summary.engagementDuration % 60)),

        -- Overall assessment
        grade = summary.grade,
        gradeText = summary.gradeText,
        score = summary.score,

        -- Performance breakdown
        sections = {},

        -- Timeline of key events
        timeline = self:buildTimeline(recording),

        -- Recommendations
        recommendations = self:generateRecommendations(summary, scenario),
    }

    -- Detection performance
    table.insert(debrief.sections, {
        title = "Detection Performance",
        items = {
            {label = "Targets Detected", value = summary.targetsDetected},
            {label = "Detection Rate", value = string.format("%.0f%%",
                summary.targetsDetected / #scenario.targets * 100)},
        },
    })

    -- Tracking performance
    table.insert(debrief.sections, {
        title = "Tracking Performance",
        items = {
            {label = "Targets Tracked", value = summary.targetsTracked},
            {label = "Average Reaction Time", value = string.format("%.1f sec", summary.avgReactionTime)},
        },
    })

    -- Engagement performance
    table.insert(debrief.sections, {
        title = "Engagement Performance",
        items = {
            {label = "Targets Destroyed", value = summary.targetsDestroyed},
            {label = "Missiles Launched", value = summary.missilesLaunched},
            {label = "Hit Rate", value = string.format("%.0f%%", summary.hitRate)},
            {label = "Missiles per Kill", value = summary.targetsDestroyed > 0 and
                string.format("%.1f", summary.missilesLaunched / summary.targetsDestroyed) or "N/A"},
        },
    })

    -- ECM performance (if applicable)
    if summary.jammingEncountered > 0 then
        table.insert(debrief.sections, {
            title = "ECM Performance",
            items = {
                {label = "Jamming Encounters", value = summary.jammingEncountered},
                {label = "Jamming Defeated", value = summary.jammingDefeated},
                {label = "ECCM Effectiveness", value = string.format("%.0f%%",
                    summary.jammingDefeated / summary.jammingEncountered * 100)},
            },
        })
    end

    return debrief
end

function SAMSIM_Training.Debrief:buildTimeline(recording)
    local timeline = {}
    local keyEvents = {"TARGET_DETECTED", "TRACK_ACQUIRED", "MISSILE_LAUNCH",
                       "MISSILE_HIT", "MISSILE_MISS", "JAMMING_DETECTED"}

    for _, event in ipairs(recording.events) do
        for _, keyType in ipairs(keyEvents) do
            if event.type == keyType then
                table.insert(timeline, {
                    time = string.format("%d:%02d", math.floor(event.time / 60),
                        math.floor(event.time % 60)),
                    event = event.type:gsub("_", " "),
                    details = event.data,
                })
                break
            end
        end
    end

    return timeline
end

function SAMSIM_Training.Debrief:generateRecommendations(summary, scenario)
    local recommendations = {}

    -- Hit rate recommendations
    if summary.hitRate < 50 then
        table.insert(recommendations, "Practice tracking to improve hit rate. Ensure track quality is above 80% before launch.")
    end

    -- Missile efficiency
    if summary.missilesLaunched > 0 and summary.targetsDestroyed > 0 then
        local mpl = summary.missilesLaunched / summary.targetsDestroyed
        if mpl > 2 then
            table.insert(recommendations, "Work on missile conservation. Wait for higher Pk before launching.")
        end
    end

    -- Reaction time
    if summary.avgReactionTime > 45 then
        table.insert(recommendations, "Improve reaction time. Practice quick target acquisition and designation.")
    end

    -- ECM handling
    if summary.jammingEncountered > 0 and summary.jammingDefeated < summary.jammingEncountered then
        table.insert(recommendations, "Review ECCM procedures. Use frequency agility and wait for burn-through range.")
    end

    -- Survival
    if not summary.siteSurvived then
        table.insert(recommendations, "Practice emission control and radar shutdown procedures against SEAD threats.")
    end

    if #recommendations == 0 then
        table.insert(recommendations, "Excellent performance! Consider trying a harder difficulty level.")
    end

    return recommendations
end


--[[
    Global Training Manager
]]
SAMSIM_Training.Manager = {
    currentSession = nil,
    sessionHistory = {},
}

function SAMSIM_Training.Manager:getScenarioList()
    local list = {}
    for _, scenario in ipairs(SAMSIM_Training.Scenarios) do
        table.insert(list, {
            id = scenario.id,
            name = scenario.name,
            description = scenario.description,
            difficulty = scenario.difficulty,
            type = scenario.type,
        })
    end
    return list
end

function SAMSIM_Training.Manager:getScenario(id)
    for _, scenario in ipairs(SAMSIM_Training.Scenarios) do
        if scenario.id == id then
            return scenario
        end
    end
    return nil
end

function SAMSIM_Training.Manager:startSession(scenarioId)
    local scenario = self:getScenario(scenarioId)
    if not scenario then
        return nil, "Scenario not found"
    end

    if self.currentSession and self.currentSession.state == "RUNNING" then
        return nil, "Session already in progress"
    end

    self.currentSession = SAMSIM_Training.Session:new(scenario)
    self.currentSession:start()

    return self.currentSession
end

function SAMSIM_Training.Manager:stopSession()
    if not self.currentSession then
        return nil, "No active session"
    end

    local result = self.currentSession:stop()
    table.insert(self.sessionHistory, result)

    local debrief = SAMSIM_Training.Debrief:generate(result)
    result.debrief = debrief

    self.currentSession = nil

    return result
end

function SAMSIM_Training.Manager:update()
    if self.currentSession then
        self.currentSession:update()
    end
end

function SAMSIM_Training.Manager:getState()
    if self.currentSession then
        return self.currentSession:getState()
    end
    return nil
end


env.info("[SAMSIM] Training module loaded")
