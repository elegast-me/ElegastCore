--[[
    InfinitePower Module for ElegastCore
    Displays XP stacks, stat points, gear bonuses, and allows stat allocation
]]--

-- Create module table
local InfinitePowerModule = {
    version = "1.1.0",
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
    playerData.gearBonuses = {} -- Gear bonus data: slot -> {statType, amount}
    playerData.unconfiguredGearSlots = 0 -- Server-calculated count of unconfigured gear slots
    playerData.statAllocations = {} -- Stat allocation percentages: addonStatID -> percentage
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
    {id = 8, name = "Attack Power", shortName = "AP", icon = "Interface\\Icons\\Ability_Warrior_OffensiveStance"},
}

-- Equipment slot ID to name mapping (for gear bonus display)
local EQUIPMENT_SLOTS = {
    [0] = "Head",
    [1] = "Neck",
    [2] = "Shoulders",
    [3] = "Shirt",
    [4] = "Chest",
    [5] = "Waist",
    [6] = "Legs",
    [7] = "Feet",
    [8] = "Wrists",
    [9] = "Hands",
    [10] = "Finger 1",
    [11] = "Finger 2",
    [12] = "Trinket 1",
    [13] = "Trinket 2",
    [14] = "Back",
    [15] = "Main Hand",
    [16] = "Off Hand",
    [17] = "Ranged",
    [18] = "Tabard",
}

-- Equipment slot ID to inventory slot ID mapping (for item tooltip matching)
-- WoW inventory slot IDs are 1-indexed for GetInventoryItemLink
local SLOT_TO_INVENTORY = {
    [0] = 1,   -- Head
    [1] = 2,   -- Neck
    [2] = 3,   -- Shoulders
    [3] = 4,   -- Shirt
    [4] = 5,   -- Chest
    [5] = 6,   -- Waist
    [6] = 7,   -- Legs
    [7] = 8,   -- Feet
    [8] = 9,   -- Wrists
    [9] = 10,  -- Hands
    [10] = 11, -- Finger 1
    [11] = 12, -- Finger 2
    [12] = 13, -- Trinket 1
    [13] = 14, -- Trinket 2
    [14] = 15, -- Back
    [15] = 16, -- Main Hand
    [16] = 17, -- Off Hand
    [17] = 18, -- Ranged
    [18] = 19, -- Tabard
}

-- Reverse mapping: inventory slot ID to our slot ID
local INVENTORY_TO_SLOT = {}
for slot, invSlot in pairs(SLOT_TO_INVENTORY) do
    INVENTORY_TO_SLOT[invSlot] = slot
end

-- Server ID -> Addon ID mapping for stat allocations
local SERVER_TO_ADDON_STAT_MAP = {
    [0] = 2,  -- Server STA (0) -> Addon STA (2)
    [1] = 0,  -- Server STR (1) -> Addon STR (0)
    [2] = 1,  -- Server AGI (2) -> Addon AGI (1)
    [3] = 3,  -- Server INT (3) -> Addon INT (3)
    [4] = 4,  -- Server SPI (4) -> Addon SPI (4)
    [5] = 7,  -- Server SP (5) -> Addon SP (7)
    [6] = 8,  -- Server AP (6) -> Addon AP (8)
    [7] = 5,  -- Server CRIT (7) -> Addon CRIT (5)
    [8] = 6,  -- Server HASTE (8) -> Addon HASTE (6)
}

-- Helper: Get stat name from stat type ID
local function GetStatName(statType)
    for _, stat in ipairs(STAT_TYPES) do
        if stat.id == statType then
            return stat.name
        end
    end
    return "Unknown"
end

-- Helper: Build allocation summary string (e.g., "40% STA, 40% STR, 20% AGI")
local function BuildAllocationSummary()
    if not playerData.statAllocations then return "" end

    local allocList = {}
    for addonStatID, percentage in pairs(playerData.statAllocations) do
        if percentage > 0 then
            local statShortName = nil
            for _, stat in ipairs(STAT_TYPES) do
                if stat.id == addonStatID then
                    statShortName = stat.shortName
                    break
                end
            end
            if statShortName then
                table.insert(allocList, {pct = percentage, name = statShortName})
            end
        end
    end

    table.sort(allocList, function(a, b) return a.pct > b.pct end)

    local parts = {}
    for _, alloc in ipairs(allocList) do
        table.insert(parts, alloc.pct .. "% " .. alloc.name)
    end

    return table.concat(parts, ", ")
end

-- Helper: Calculate gear bonus totals by stat type
local function CalculateGearBonusTotals()
    local totals = {}
    for slot, bonus in pairs(playerData.gearBonuses) do
        if bonus.amount > 0 then
            local statType = bonus.statType
            totals[statType] = (totals[statType] or 0) + bonus.amount
        end
    end
    return totals
end

-- Helper: Validate allocations total 100%
local function ValidateAllocations()
    if not playerData.statAllocations then return true end

    -- Check if there are any allocations at all
    local hasAllocations = false
    local total = 0
    for _, percentage in pairs(playerData.statAllocations) do
        hasAllocations = true
        total = total + percentage
    end

    -- If there are allocations, they should total 100%
    if hasAllocations then
        return total == 100
    else
        -- No allocations is valid (default state)
        return true
    end
end

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
        stats = playerData.stats,
        gearBonuses = playerData.gearBonuses,
        unconfiguredGearSlots = playerData.unconfiguredGearSlots,
        statAllocations = playerData.statAllocations
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
        playerData.gearBonuses = saved.gearBonuses or {}
        playerData.unconfiguredGearSlots = saved.unconfiguredGearSlots or 0
        playerData.statAllocations = saved.statAllocations or {}
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
        elseif key == "GEAR" then
            -- Parse gear bonuses: "slot:statType:amount,slot:statType:amount,..."
            playerData.gearBonuses = {}
            if parts[2] then
                local gearData = table.concat(parts, ":", 2)  -- Rejoin after "GEAR"
                for gearEntry in string.gmatch(gearData, "[^,]+") do
                    local slot, statType, amount = string.match(gearEntry, "(%d+):(%d+):(%d+)")
                    if slot and statType and amount then
                        playerData.gearBonuses[tonumber(slot)] = {
                            statType = tonumber(statType),
                            amount = tonumber(amount)
                        }
                    end
                end
            end
        elseif key == "UNCFG" then
            -- Parse unconfigured gear slots count (from server, Issue #7)
            playerData.unconfiguredGearSlots = tonumber(parts[2]) or 0
        elseif key == "PCT" then
            playerData.statAllocations = {}
            if parts[2] then
                local pctData = table.concat(parts, ":", 2)
                local serverAllocations = {}
                local i = 0

                for pct in string.gmatch(pctData, "(%d+)") do
                    serverAllocations[i] = tonumber(pct) or 0
                    i = i + 1
                end

                -- Map server IDs to addon IDs
                for serverID = 0, 8 do
                    local addonID = SERVER_TO_ADDON_STAT_MAP[serverID]
                    local percentage = serverAllocations[serverID] or 0
                    if addonID and percentage > 0 then
                        playerData.statAllocations[addonID] = percentage
                    end
                end
            end
        end
    end

    -- Save to persistent storage
    SavePlayerData()
end

-- Update the gear bonus notification badge
-- Uses server-provided unconfigured count (Issue #7)
local function UpdateBadge()
    if not PowerFrame or not PowerFrame.gearBadge then return end

    -- Use server-calculated count (matches Book of Power logic exactly)
    local unconfiguredCount = playerData.unconfiguredGearSlots or 0

    if unconfiguredCount > 0 then
        -- Show orange badge with count
        PowerFrame.gearBadge:SetText("|cffFF8800[" .. unconfiguredCount .. "]|r")
        PowerFrame.gearBadge:Show()
    else
        -- Hide badge when all configured or no gear equipped
        PowerFrame.gearBadge:Hide()
    end
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

    -- Update gear bonus notification badge
    UpdateBadge()
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

    -- Create gear bonus notification badge (top-right corner)
    local gearBadge = PowerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gearBadge:SetPoint("TOPRIGHT", PowerFrame, "TOPRIGHT", 5, 5)
    gearBadge:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    gearBadge:SetText("")
    gearBadge:Hide()  -- Initially hidden
    PowerFrame.gearBadge = gearBadge

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

        -- Show stat bonuses with gear bonuses aggregated by stat type
        local gearBonusTotals = next(playerData.gearBonuses) and CalculateGearBonusTotals() or {}
        local hasStats = false
        for statType, amount in pairs(playerData.stats) do
            if amount > 0 then
                hasStats = true
                break
            end
        end

        if hasStats then
            GameTooltip:AddLine("Stats:", 0.7, 0.7, 0.7, true)
            for statType, amount in pairs(playerData.stats) do
                if amount > 0 then
                    local statName = GetStatName(statType)
                    local gearBonus = gearBonusTotals[statType] or 0
                    if gearBonus > 0 then
                        GameTooltip:AddLine("  " .. statName .. ": +" .. amount .. " (+" .. gearBonus .. " gear)", 0.4, 1.0, 0.4, true)
                    else
                        GameTooltip:AddLine("  " .. statName .. ": +" .. amount, 0.4, 1.0, 0.4, true)
                    end
                end
            end
        else
            GameTooltip:AddLine("Stats: No active stat bonuses", 0.7, 0.7, 0.7, true)
        end

        -- Show total gear bonus count
        local totalGearBonus = 0
        for _, bonus in pairs(gearBonusTotals) do
            totalGearBonus = totalGearBonus + bonus
        end
        if totalGearBonus > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Total Gear Bonus: +" .. totalGearBonus .. " stats", 0.4, 1.0, 0.8, true)
        end

        -- Show gear bonus badge explanation if there are unconfigured slots (using server count)
        local unconfiguredCount = playerData.unconfiguredGearSlots or 0
        if unconfiguredCount > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffFF8800[" .. unconfiguredCount .. "]|r = Unconfigured gear slots", 1, 0.8, 0.4, true)
            GameTooltip:AddLine("Use Book of Power to configure bonuses", 0.7, 0.7, 0.7, true)
        end

        -- Show allocation validation warning if needed (only if allocations exist)
        if next(playerData.statAllocations) and not ValidateAllocations() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffff0000WARNING: Allocations don't total 100%!|r", 1, 0.3, 0.3, true)
        end

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

-- Hook item tooltips to show gear bonuses
local function SetupTooltipHooks()
    -- Helper function to find gear bonus for an equipped item
    local function GetGearBonusForItem(tooltip)
        -- Get the item link from the tooltip
        local _, itemLink = tooltip:GetItem()
        if not itemLink then return nil, nil end

        -- Check each equipment slot to see if this item is equipped there
        for slot, invSlot in pairs(SLOT_TO_INVENTORY) do
            local equippedLink = GetInventoryItemLink("player", invSlot)
            if equippedLink and equippedLink == itemLink then
                -- This item is equipped in this slot, check for gear bonus
                local bonus = playerData.gearBonuses[slot]
                if bonus and bonus.amount > 0 then
                    return bonus, slot
                end
            end
        end

        return nil, nil
    end

    -- Hook GameTooltip for item tooltips
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local bonus, slot = GetGearBonusForItem(tooltip)
        if bonus then
            local statName = GetStatName(bonus.statType)
            tooltip:AddLine(" ")
            tooltip:AddLine("|cff00FF00Infinite Power: +" .. bonus.amount .. " " .. statName .. "|r")
            tooltip:Show()  -- Refresh tooltip to show new line
        end
    end)

    -- Also hook ItemRefTooltip for shift-clicked items in chat
    ItemRefTooltip:HookScript("OnTooltipSetItem", function(tooltip)
        local bonus, slot = GetGearBonusForItem(tooltip)
        if bonus then
            local statName = GetStatName(bonus.statType)
            tooltip:AddLine(" ")
            tooltip:AddLine("|cff00FF00Infinite Power: +" .. bonus.amount .. " " .. statName .. "|r")
            tooltip:Show()
        end
    end)

    -- Hook ShoppingTooltip for comparison tooltips
    ShoppingTooltip1:HookScript("OnTooltipSetItem", function(tooltip)
        local bonus, slot = GetGearBonusForItem(tooltip)
        if bonus then
            local statName = GetStatName(bonus.statType)
            tooltip:AddLine(" ")
            tooltip:AddLine("|cff00FF00Infinite Power: +" .. bonus.amount .. " " .. statName .. "|r")
            tooltip:Show()
        end
    end)

    ShoppingTooltip2:HookScript("OnTooltipSetItem", function(tooltip)
        local bonus, slot = GetGearBonusForItem(tooltip)
        if bonus then
            local statName = GetStatName(bonus.statType)
            tooltip:AddLine(" ")
            tooltip:AddLine("|cff00FF00Infinite Power: +" .. bonus.amount .. " " .. statName .. "|r")
            tooltip:Show()
        end
    end)
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

    -- Setup tooltip hooks for gear bonuses
    SetupTooltipHooks()

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
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")  -- Track gear changes
    eventFrame:SetScript("OnEvent", function(self, event, message)
        if event == "CHAT_MSG_SYSTEM" then
            -- Check if message starts with our prefix
            if string.match(message, "^" .. ADDON_PREFIX .. ":") then
                -- Remove prefix and parse
                local data = string.gsub(message, "^" .. ADDON_PREFIX .. ":", "")
                ParseServerMessage(data)
                UpdateDisplay()
            end
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            -- Update badge when equipment changes
            UpdateBadge()
        end
    end)

    -- Show initial display with loaded data
    UpdateDisplay()

    print("|cff66FFCCElegastCore:|r InfinitePower module v" .. InfinitePowerModule.version .. " initialized")
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

    elseif command == "gear" or command == "gearbonuses" then
        -- Show gear bonus summary
        print("|cff66FFCC===== Gear Bonuses =====|r")
        local hasAny = false
        local totalBonus = 0
        for slot, bonus in pairs(playerData.gearBonuses) do
            if bonus.amount > 0 then
                hasAny = true
                totalBonus = totalBonus + bonus.amount
                local slotName = EQUIPMENT_SLOTS[slot] or "Unknown"
                local statName = GetStatName(bonus.statType)
                print("  " .. slotName .. ": |cff00FF00+" .. bonus.amount .. " " .. statName .. "|r")
            end
        end
        if not hasAny then
            print("  |cff888888No gear bonuses configured.|r")
            print("  |cff888888Use the Book of Power to set up gear bonuses!|r")
        else
            print(" ")
            print("  Total: |cff00FFCC+" .. totalBonus .. " stats|r from gear")
        end

    else
        print("|cff66FFCC===== ElegastCore - InfinitePower Module =====|r")
        print("|cffFFFFFF/egc infinitepower unlock|r - Unlock to move and scale the display")
        print("|cffFFFFFF/egc infinitepower lock|r - Lock the display in place")
        print("|cffFFFFFF/egc infinitepower reset|r - Reset position and scale to default")
        print("|cffFFFFFF/egc infinitepower show|r - Show the display")
        print("|cffFFFFFF/egc infinitepower hide|r - Hide the display")
        print("|cffFFFFFF/egc infinitepower minimal [on/off]|r - Toggle minimal display mode")
        print("|cffFFFFFF/egc infinitepower gear|r - Show gear bonus summary")
        print(" ")
        print("|cff888888Current Stats:|r")
        print("  XP Stacks: |cff00FF00" .. playerData.xpStacks .. "|r (+|cff00FF00" .. playerData.xpPercentage .. "%|r XP)")
        print("  Total Kills: |cffCCCCCC" .. playerData.totalKills .. "|r")
        print("  Total Quests: |cffCCCCCC" .. playerData.totalQuests .. "|r")
        print(" ")
        print("|cff888888Next Stack Progress:|r")
        print("  Kills: |cffFFFF00" .. playerData.killsThisStack .. "/" .. playerData.killsNeeded .. "|r")
        print("  Quests: |cffFFFF00" .. playerData.questsThisStack .. "/" .. playerData.questsNeeded .. "|r")


        -- Show gear bonus count
        local gearBonusCount = 0
        for slot, bonus in pairs(playerData.gearBonuses) do
            if bonus.amount > 0 then
                gearBonusCount = gearBonusCount + 1
            end
        end
        if gearBonusCount > 0 then
            print(" ")
            print("|cff888888Gear Bonuses:|r |cff00FFCC" .. gearBonusCount .. " slots configured|r (use /egc infinitepower gear for details)")
        end
    end
end

-- Register the module with ElegastCore
ElegastCore:RegisterModule("InfinitePower", InfinitePowerModule)
