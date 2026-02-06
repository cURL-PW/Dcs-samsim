--[[
    SA-2 SAMSIM Example Mission Script

    This script demonstrates how to set up SA-2 sites for SAMSIM control.
    Add this script to your mission using the Mission Editor's
    "DO SCRIPT FILE" trigger action.

    Prerequisites:
    1. Place SA-2 groups in the mission editor with the following units:
       - SNR-75 Fan Song (tracking radar)
       - S-75 launcher units
       - P-19 early warning radar (optional)

    2. Name your SA-2 groups consistently (e.g., "SA-2 Site Alpha", "SA-2 Site Bravo")

    3. Load this script at mission start

    Example group setup in Mission Editor:
    Group: "SA-2 Site Alpha"
      - Unit 1: SNR-75 Fan Song (tracking radar)
      - Unit 2: 5P73 launcher
      - Unit 3: 5P73 launcher
      - Unit 4: 5P73 launcher
      - Unit 5: 5P73 launcher
      - Unit 6: 5P73 launcher
      - Unit 7: 5P73 launcher
      - Unit 8: P-19 radar (early warning)
]]

-- Load the main SAMSIM script if not already loaded
if not SAMSIM then
    -- Try to load from mission resources
    local status, err = pcall(function()
        -- This path should be adjusted based on your mission setup
        dofile(lfs.writedir() .. "Scripts/SAMSIM/SA2_SAMSIM.lua")
    end)

    if not status then
        env.warning("SAMSIM: Could not auto-load SA2_SAMSIM.lua: " .. tostring(err))
        env.info("SAMSIM: Please ensure SA2_SAMSIM.lua is loaded before this script")
    end
end

-- Wait for SAMSIM to be ready
if SAMSIM then
    env.info("SAMSIM Example: Initializing SA-2 sites...")

    -- Define your SA-2 sites here
    -- Format: { siteId = "unique_id", groupName = "DCS_group_name" }
    local SA2_SITES = {
        { siteId = "SA2-ALPHA", groupName = "SA-2 Site Alpha" },
        { siteId = "SA2-BRAVO", groupName = "SA-2 Site Bravo" },
        -- Add more sites as needed
    }

    -- Initialize sites with a small delay to ensure mission is fully loaded
    timer.scheduleFunction(function()
        for _, site in ipairs(SA2_SITES) do
            local result = SAMSIM.InitSite(site.groupName, site.siteId)
            if result then
                env.info("SAMSIM Example: Initialized site " .. site.siteId)

                -- Set initial state (powered on, search mode)
                SAMSIM.SetSystemState(site.siteId, SAMSIM.SystemState.READY)
                SAMSIM.SetRadarMode(site.siteId, SAMSIM.RadarMode.SEARCH)
            else
                env.warning("SAMSIM Example: Failed to initialize " .. site.siteId ..
                           " - Check if group '" .. site.groupName .. "' exists")
            end
        end

        env.info("SAMSIM Example: Site initialization complete")
        return nil -- Don't reschedule
    end, nil, timer.getTime() + 3) -- 3 second delay

    env.info("SAMSIM Example: Script loaded - sites will initialize in 3 seconds")
else
    env.error("SAMSIM Example: SAMSIM module not found! Please load SA2_SAMSIM.lua first")
end

--[[
    Advanced Usage Examples:

    -- Manual target designation
    SAMSIM.DesignateTarget("SA2-ALPHA", "TGT-1")

    -- Launch missile at tracked target
    SAMSIM.LaunchMissile("SA2-ALPHA")

    -- Set auto-engage mode
    SAMSIM.SetAutoEngage("SA2-ALPHA", true)
    SAMSIM.SetEngagementAuth("SA2-ALPHA", true)

    -- Command antenna position
    SAMSIM.CommandAntenna("SA2-ALPHA", 45, 10) -- azimuth 45, elevation 10

    -- Get site status
    local status = SAMSIM.GetSiteStatus("SA2-ALPHA")
    env.info("Site status: " .. tostring(status.radarMode))
]]
