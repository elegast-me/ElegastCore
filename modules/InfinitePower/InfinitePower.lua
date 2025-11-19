--[[
    InfinitePower Module for ElegastCore
    Displays XP stacks, stat points, and allows stat allocation
]]--

-- Create module table
local InfinitePowerModule = {
    version = "1.0.0",
    name = "InfinitePower"
}

-- Module configuration
local ADDON_PREFIX = "INF_PWR"
local UPDATE_INTERVAL = 0.5  -- Update check interval

-- Module-specific saved variables
local savedVars = {}

-- Main display frame and UI elements
local PowerFrame = nil
local StatFrame = nil

-- Current player data
local playerData = {} -- Initialize as empty table, will be populated on login

-- Reset playerData to default values
local function ResetPlayerData()
    playerData.xpStacks = 0
    playerData.xpPercentage = 0
    playerData.statPoints = 0
    playerData.totalKills = 0
    playerData.killsThisStack = 0
    playerData.killsNeeded = 25
    playerData.totalQuests = 0
    playerData.questsThisStack = 0
    playerData.questsNeeded = 3
    playerData.stats = {}
end

-- Stat type configuration
local STAT_TYPES = {
    {id = 0, name = "Strength", shortName = "STR", icon = "Interface\\Icons\\INV_Sword_27"},
    {id = 1, name = "Agility", shortName = "AGI", icon = "Interface\\Icons\\INV_Weapon_ShortBlade_25"},
    {id = 2, name = "Stamina", shortName = "STA", icon = "Interface\\Icons\\INV_Shield_06"},
    {id = 3, name = "Intellect", shortName = "INT", icon = "Interface\\Icons\\INV_Misc_Book_09"},
    {id = 4, name = "Spirit", shortName = "SPI", icon = "Interface\\Icons\\INV_Misc_ShadowEgg"},
    {id = 5, name = "Crit Rating", shortName = "CRIT", icon = "Interface\\Icons\\Ability_Rogue_Rupture"},
    {id = 6, name = "Haste Rating", shortName = "HASTE", icon = "Interface\\Icons\\Spell_Nature_Bloodlust"},
    {id = 7, name = "Spell Power", shortName = "SP", icon = "Interface\\Icons\\Spell_Holy_HolySmite"},
}

-- Chat filter to hide our messages from displaying in chat
local function ChatFilter(self, event, msg, ...)
    if string.match(msg, "^INF_PWR:") then
        return true  -- Block this message
    end
    return false
end

-- Save player data to SavedVariables
local function SavePlayerData()
    local charName = UnitName("player")
    if not charName then return end -- Should not happen on PLAYER_LOGIN

    if not ElegastCoreDB.InfinitePower then
        ElegastCoreDB.InfinitePower = {}
    end
    ElegastCoreDB.InfinitePower[charName] = {
        xpStacks = playerData.xpStacks,
        xpPercentage = playerData.xpPercentage,
        statPoints = playerData.statPoints,
        totalKills = playerData.totalKills,
        killsThisStack = playerData.killsThisStack,
        killsNeeded = playerData.killsNeeded,
        totalQuests = playerData.totalQuests,
        questsThisStack = playerData.questsThisStack,
        questsNeeded = playerData.questsNeeded,
        stats = playerData.stats
    }
end

-- Save minimal mode preference
local function SaveMinimalMode(enabled)
    if not ElegastCoreDB.InfinitePower then
        ElegastCoreDB.InfinitePower = {}
    end
    ElegastCoreDB.InfinitePower.minimal = enabled
end

-- Load minimal mode preference
local function LoadMinimalMode()
    if ElegastCoreDB.InfinitePower and ElegastCoreDB.InfinitePower.minimal ~= nil then
        return ElegastCoreDB.InfinitePower.minimal
    end
    return false -- Default to normal mode
end

-- Load player data from SavedVariables
local function LoadPlayerData()
    local charName = UnitName("player")
    if not charName then
        -- If no character name (e.g., during initial addon load before PLAYER_LOGIN),
        -- playerData should already be reset by OnInitialize.
        return false
    end

    if ElegastCoreDB.InfinitePower and ElegastCoreDB.InfinitePower[charName] then
        local saved = ElegastCoreDB.InfinitePower[charName]
        playerData.xpStacks = saved.xpStacks or 0
        playerData.xpPercentage = saved.xpPercentage or 0
        playerData.statPoints = saved.statPoints or 0
        playerData.totalKills = saved.totalKills or 0
        playerData.killsThisStack = saved.killsThisStack or 0
        playerData.killsNeeded = saved.killsNeeded or 25
        playerData.totalQuests = saved.totalQuests or 0 -- FIX: Corrected from saved.questsThisStack
        playerData.questsThisStack = saved.questsThisStack or 0
        playerData.questsNeeded = saved.questsNeeded or 3
        playerData.stats = saved.stats or {}
        return true
    end
    return false
end

-- Parse server message
local function ParseServerMessage(message)
    -- Message format: "XP:stacks:percentage|SP:points|KILLS:total:current:needed|QUESTS:total:current:needed|STATS:type:amt,type:amt"
    for segment in string.gmatch(message, "[^|]+") do
        local parts = {}
        for val in string.gmatch(segment, "[^:]+") do
            table.insert(parts, val)
        end

        local key = parts[1]
        if key == "XP" then
            playerData.xpStacks = tonumber(parts[2]) or 0
            playerData.xpPercentage = tonumber(parts[3]) or 0
        elseif key == "SP" then
            playerData.statPoints = tonumber(parts[2]) or 0
        elseif key == "KILLS" then
            playerData.totalKills = tonumber(parts[2]) or 0
            playerData.killsThisStack = tonumber(parts[3]) or 0
            playerData.killsNeeded = tonumber(parts[4]) or 25
        elseif key == "QUESTS" then
            playerData.totalQuests = tonumber(parts[2]) or 0
            playerData.questsThisStack = tonumber(parts[3]) or 0
            playerData.questsNeeded = tonumber(parts[4]) or 3
        elseif key == "STATS" then
            -- Parse stats: "type:amt,type:amt,..."
            playerData.stats = {}
            if parts[2] then
                local statsData = table.concat(parts, ":", 2)  -- Rejoin after "STATS"
                for statPair in string.gmatch(statsData, "[^,]+") do
                    local statType, statAmt = string.match(statPair, "(%d+):(%d+)")
                    if statType and statAmt then
                        playerData.stats[tonumber(statType)] = tonumber(statAmt)
                    end
                end
            end
        end
    end

    -- Save to persistent storage
    SavePlayerData()
end

-- Update display with current data
local function UpdateDisplay()
    if not PowerFrame then return end

    -- Always show the frame (even with 0 stacks) so players can see progress
    PowerFrame:Show()

    -- Check minimal mode state
    local isMinimal = LoadMinimalMode()

    if isMinimal then
        -- Minimal Mode: Hide icon, show only text
        PowerFrame.icon:Hide()

        -- Update text displays (compact format)
        PowerFrame.stackText:SetText(playerData.xpStacks)
        PowerFrame.xpBonusText:SetText("+" .. playerData.xpPercentage .. "%")

        -- Reposition text for minimal mode (centered, side-by-side)
        PowerFrame.stackText:ClearAllPoints()
        PowerFrame.stackText:SetPoint("RIGHT", PowerFrame, "CENTER", -5, 0)
        PowerFrame.stackText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")

        PowerFrame.xpBonusText:ClearAllPoints()
        PowerFrame.xpBonusText:SetPoint("LEFT", PowerFrame, "CENTER", 5, 0)
        PowerFrame.xpBonusText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    else
        -- Normal Mode: Show icon, position text as before
        PowerFrame.icon:Show()

        -- Update text displays
        PowerFrame.stackText:SetText(playerData.xpStacks)
        PowerFrame.xpBonusText:SetText("+" .. playerData.xpPercentage .. "%")

        -- Restore original positioning
        PowerFrame.stackText:ClearAllPoints()
        PowerFrame.stackText:SetPoint("CENTER", PowerFrame, "CENTER", 0, 5)
        PowerFrame.stackText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")

        PowerFrame.xpBonusText:ClearAllPoints()
        PowerFrame.xpBonusText:SetPoint("BOTTOM", PowerFrame, "BOTTOM", 0, -14)
        PowerFrame.xpBonusText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    end
end

-- Create the main power display frame
local function CreatePowerDisplay()
    -- Use core utility to create draggable frame
    PowerFrame = ElegastCore:CreateDraggableFrame(
        "ElegastCorePowerFrame",
        UIParent,
        60,
        60,
        {point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -140, y = -150}
    )

    -- Create power icon texture (custom "infinity" style)
    local icon = PowerFrame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(PowerFrame)
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_MindMastery")  -- Arcane power icon
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    PowerFrame.icon = icon  -- Store reference for showing/hiding

    -- Create border for animations
    local border = PowerFrame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAllPoints(PowerFrame)
    border:SetVertexColor(0.4, 0.8, 1.0, 0)
    PowerFrame.border = border

    -- Create stack count text (large)
    local stackText = PowerFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    stackText:SetPoint("CENTER", PowerFrame, "CENTER", 0, 5)
    stackText:SetTextColor(1, 1, 1)
    stackText:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    stackText:SetText("0")
    PowerFrame.stackText = stackText

    -- Create XP bonus text (below icon)
    local xpBonusText = PowerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xpBonusText:SetPoint("BOTTOM", PowerFrame, "BOTTOM", 0, -14)
    xpBonusText:SetTextColor(0.4, 1.0, 0.4)
    xpBonusText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    xpBonusText:SetText("+0%")
    PowerFrame.xpBonusText = xpBonusText

    -- Removed stat points display - stats auto-apply now

    -- Tooltip support
    PowerFrame:EnableMouse(true)
    PowerFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Infinite Power (Account)", 0.5, 0.8, 1.0, 1, true)
        GameTooltip:AddLine("Account XP Stacks: " .. playerData.xpStacks, 1, 1, 1, true)
        GameTooltip:AddLine("Account XP Bonus: +" .. playerData.xpPercentage .. "%", 0.4, 1.0, 0.4, true)
        GameTooltip:AddLine(" ")

        -- Show progress to next stack
        GameTooltip:AddLine("Next Stack (complete either):", 0.7, 0.7, 0.7, true)

        -- Kill progress
        local killsRemaining = playerData.killsNeeded - playerData.killsThisStack
        local killPercent = math.floor((playerData.killsThisStack / playerData.killsNeeded) * 100)
        GameTooltip:AddLine("Kills: " .. playerData.killsThisStack .. "/" .. playerData.killsNeeded .. " (" .. killPercent .. "%)", 1, 1, 0.4, true)

        -- Quest progress
        local questsRemaining = playerData.questsNeeded - playerData.questsThisStack
        local questPercent = math.floor((playerData.questsThisStack / playerData.questsNeeded) * 100)
        GameTooltip:AddLine("Quests: " .. playerData.questsThisStack .. "/" .. playerData.questsNeeded .. " (" .. questPercent .. "%)", 0.4, 1.0, 1.0, true)
        GameTooltip:AddLine(" ")

        -- Show stat bonuses
        local hasStats = false
        for statType, amount in pairs(playerData.stats) do
            if amount > 0 then
                hasStats = true
                break
            end
        end

        if hasStats then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Bonus Stats:", 0.7, 0.7, 0.7, true)
            for statType, amount in pairs(playerData.stats) do
                if amount > 0 then
                    local statName = "Unknown"
                    for _, stat in ipairs(STAT_TYPES) do
                        if stat.id == statType then
                            statName = stat.name
                            break
                        end
                    end
                    GameTooltip:AddLine("  +" .. amount .. " " .. statName, 0.4, 1.0, 0.4, true)
                end
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Lifetime Stats:", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Total Kills: " .. playerData.totalKills, 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Total Quests: " .. playerData.totalQuests, 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-Click to toggle minimal mode", 0.5, 0.5, 0.5, true)
        GameTooltip:AddLine("Shift + Drag to move", 0.5, 0.5, 0.5, true)
        GameTooltip:AddLine("/egc infinitepower unlock - to move/scale", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)

    PowerFrame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Right-click to toggle minimal mode
    PowerFrame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            local currentMode = LoadMinimalMode()
            SaveMinimalMode(not currentMode)
            UpdateDisplay()
            local statusText = (not currentMode) and "Minimal mode enabled" or "Normal mode enabled"
            print("|cff66FFCCElegastCore (InfinitePower):|r " .. statusText)
        end
    end)

    -- Custom position save callback
    PowerFrame.OnPositionChanged = function(self)
        if not savedVars then
            savedVars = {}
        end
        local point, _, relativePoint, x, y = self:GetPoint()
        savedVars.point = point
        savedVars.relativePoint = relativePoint
        savedVars.x = x
        savedVars.y = y

        if not ElegastCoreDB.InfinitePower then
            ElegastCoreDB.InfinitePower = {}
        end
        ElegastCoreDB.InfinitePower.position = savedVars

        if self.unlocked then
            print("|cff66FFCCElegastCore (InfinitePower):|r Position saved! Type |cffFFFFFF/egc infinitepower lock|r to lock it")
        end
    end

    -- Custom scale save callback
    PowerFrame.OnScaleChanged = function(self)
        if not savedVars then
            savedVars = {}
        end
        savedVars.scale = self:GetScale()

        if not ElegastCoreDB.InfinitePower then
            ElegastCoreDB.InfinitePower = {}
        end
        ElegastCoreDB.InfinitePower.position = savedVars
    end

    -- Make the frame scalable with griptape
    ElegastCore:MakeFrameScalable(PowerFrame)

    -- Initially hide griptape (show only when unlocked)
    if PowerFrame.griptape then
        PowerFrame.griptape:Hide()
    end

    return PowerFrame
end

-- Module initialization
function InfinitePowerModule:OnInitialize()
    -- Always reset player data to defaults first
    ResetPlayerData()

    -- Load saved variables (for position)
    if ElegastCoreDB.InfinitePower then
        savedVars = ElegastCoreDB.InfinitePower.position or {}
    end

    -- Load saved player data (persists through /reload)
    LoadPlayerData()

    -- Create power display
    CreatePowerDisplay()

    -- Restore saved position if available
    if savedVars.point then
        PowerFrame:ClearAllPoints()
        PowerFrame:SetPoint(
            savedVars.point,
            UIParent,
            savedVars.relativePoint,
            savedVars.x,
            savedVars.y
        )
    end

    -- Restore saved scale if available
    if savedVars.scale then
        PowerFrame:SetScale(savedVars.scale)
    end

    -- Register chat filter to hide INF_PWR messages
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)

    -- Listen for system messages from server (INF_PWR prefix)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:SetScript("OnEvent", function(self, event, message)
        -- Check if message starts with our prefix
        if string.match(message, "^" .. ADDON_PREFIX .. ":") then
            -- Remove prefix and parse
            local data = string.gsub(message, "^" .. ADDON_PREFIX .. ":", "")
            ParseServerMessage(data)
            UpdateDisplay()
        end
    end)

    -- Show initial display with loaded data
    UpdateDisplay()

    print("|cff66FFCCElegastCore:|r InfinitePower module initialized")
end

-- Module command handler
function InfinitePowerModule:OnCommand(args)
    local command = args[1] or ""

    if command == "reset" then
        PowerFrame:ClearAllPoints()
        PowerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -140, -150)
        PowerFrame:SetScale(1.0)
        savedVars = {}
        ElegastCoreDB.InfinitePower = {}
        print("|cff66FFCCElegastCore (InfinitePower):|r Position and scale reset to default!")

    elseif command == "unlock" or command == "move" then
        PowerFrame.unlocked = not PowerFrame.unlocked
        if PowerFrame.unlocked then
            PowerFrame:Show()
            PowerFrame.stackText:SetText("∞")
            PowerFrame.xpBonusText:SetText("+XP")
            PowerFrame.border:SetVertexColor(0.2, 1.0, 0.2, 0.8)
            -- Show griptape when unlocked
            if PowerFrame.griptape then
                PowerFrame.griptape:Show()
            end
            print("|cff66FFCCElegastCore (InfinitePower):|r |cff00FF00Unlocked!|r Drag to move, drag corner to scale")
        else
            PowerFrame.unlocked = false
            PowerFrame.border:SetVertexColor(0.4, 0.8, 1.0, 0)
            -- Hide griptape when locked
            if PowerFrame.griptape then
                PowerFrame.griptape:Hide()
            end
            UpdateDisplay()
            print("|cff66FFCCElegastCore (InfinitePower):|r |cffFF6666Locked!|r Position and scale saved")
        end

    elseif command == "lock" then
        PowerFrame.unlocked = false
        PowerFrame.border:SetVertexColor(0.4, 0.8, 1.0, 0)
        -- Hide griptape when locked
        if PowerFrame.griptape then
            PowerFrame.griptape:Hide()
        end
        UpdateDisplay()
        print("|cff66FFCCElegastCore (InfinitePower):|r |cffFF6666Locked!|r Position and scale saved")

    elseif command == "show" then
        PowerFrame:Show()
        print("|cff66FFCCElegastCore (InfinitePower):|r Display shown")

    elseif command == "hide" then
        PowerFrame:Hide()
        print("|cff66FFCCElegastCore (InfinitePower):|r Display hidden")

    elseif command == "minimal" then
        local setting = args[2]
        if setting == "on" then
            SaveMinimalMode(true)
            UpdateDisplay()
            print("|cff66FFCCElegastCore (InfinitePower):|r Minimal mode |cff00FF00enabled|r")
        elseif setting == "off" then
            SaveMinimalMode(false)
            UpdateDisplay()
            print("|cff66FFCCElegastCore (InfinitePower):|r Minimal mode |cffFF6666disabled|r")
        else
            -- Toggle minimal mode
            local currentMode = LoadMinimalMode()
            SaveMinimalMode(not currentMode)
            UpdateDisplay()
            local statusText = (not currentMode) and "|cff00FF00enabled|r" or "|cffFF6666disabled|r"
            print("|cff66FFCCElegastCore (InfinitePower):|r Minimal mode " .. statusText)
        end

    else
        print("|cff66FFCC===== ElegastCore - InfinitePower Module =====|r")
        print("|cffFFFFFF/egc infinitepower unlock|r - Unlock to move and scale the display")
        print("|cffFFFFFF/egc infinitepower lock|r - Lock the display in place")
        print("|cffFFFFFF/egc infinitepower reset|r - Reset position and scale to default")
        print("|cffFFFFFF/egc infinitepower show|r - Show the display")
        print("|cffFFFFFF/egc infinitepower hide|r - Hide the display")
        print("|cffFFFFFF/egc infinitepower minimal [on/off]|r - Toggle minimal display mode")
        print(" ")
        print("|cff888888Current Stats:|r")
        print("  XP Stacks: |cff00FF00" .. playerData.xpStacks .. "|r (+|cff00FF00" .. playerData.xpPercentage .. "%|r XP)")
        print("  Total Kills: |cffCCCCCC" .. playerData.totalKills .. "|r")
        print("  Total Quests: |cffCCCCCC" .. playerData.totalQuests .. "|r")
        print(" ")
        print("|cff888888Next Stack Progress:|r")
        print("  Kills: |cffFFFF00" .. playerData.killsThisStack .. "/" .. playerData.killsNeeded .. "|r")
        print("  Quests: |cffFFFF00" .. playerData.questsThisStack .. "/" .. playerData.questsNeeded .. "|r")
    end
end

-- Register the module with ElegastCore
ElegastCore:RegisterModule("InfinitePower", InfinitePowerModule)
