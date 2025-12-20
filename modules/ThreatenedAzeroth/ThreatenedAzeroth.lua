--[[
    ThreatenedAzeroth Module for ElegastCore
    Displays active/inactive status for the Threatened Azeroth system.
]]--

-- Create module table
local ThreatenedAzerothModule = {
    version = "1.0.0",
    name = "ThreatenedAzeroth"
}

-- Module configuration
local ADDON_PREFIX = "INF_PWR:TA" -- Matches the server-side prefix for TA messages
local UPDATE_INTERVAL = 0.5  -- Update check interval

-- Module-specific saved variables
local savedVars = {}

-- Main display frame and UI elements
local TAFrame = nil

-- Current player data
local taData = {
    difficultyLevel = 0  -- 0=OFF, 1=TA-1, 2=TA-2 EXTREME
}

-- Save player data to SavedVariables
local function SavePlayerData()
    if not ElegastCoreDB.ThreatenedAzeroth then
        ElegastCoreDB.ThreatenedAzeroth = {}
    end
    ElegastCoreDB.ThreatenedAzeroth.playerData = {
        difficultyLevel = taData.difficultyLevel
    }
end

-- Load player data from SavedVariables
local function LoadPlayerData()
    if ElegastCoreDB.ThreatenedAzeroth and ElegastCoreDB.ThreatenedAzeroth.playerData then
        local saved = ElegastCoreDB.ThreatenedAzeroth.playerData
        taData.difficultyLevel = saved.difficultyLevel or 0
        return true
    end
    return false
end

-- Save minimal mode preference
local function SaveMinimalMode(enabled)
    if not ElegastCoreDB.ThreatenedAzeroth then
        ElegastCoreDB.ThreatenedAzeroth = {}
    end
    ElegastCoreDB.ThreatenedAzeroth.minimal = enabled
end

-- Load minimal mode preference
local function LoadMinimalMode()
    if ElegastCoreDB.ThreatenedAzeroth and ElegastCoreDB.ThreatenedAzeroth.minimal ~= nil then
        return ElegastCoreDB.ThreatenedAzeroth.minimal
    end
    return false -- Default to normal mode
end

-- Parse server message - format: "TA:status" where status is 0, 1, or 2
local function ParseServerMessage(message)
    local status = string.match(message, "^TA:(%d)")

    if status then
        taData.difficultyLevel = tonumber(status)
        SavePlayerData() -- Save to persistent storage
        return true -- Data was found and parsed
    end

    return false -- No TA data found
end

-- Update display with current data
local function UpdateDisplay()
    if not TAFrame then return end

    -- Always show the frame so players can see the status
    TAFrame:Show()

    -- Check minimal mode state
    local isMinimal = LoadMinimalMode()

    -- Determine colors and text based on difficulty level
    local statusText, statusIndicator, textColor, iconColor
    if taData.difficultyLevel == 0 then  -- OFF
        statusText = "TA"
        statusIndicator = "OFF"
        textColor = {0.4, 1.0, 0.4}      -- Green
        iconColor = {0.4, 1.0, 0.4, 1.0} -- Green
    elseif taData.difficultyLevel == 1 then  -- TA-1
        statusText = "TA"
        statusIndicator = "TA-1"
        textColor = {1.0, 0.8, 0.0}      -- Orange/Yellow
        iconColor = {1.0, 0.8, 0.0, 1.0} -- Orange/Yellow
    else  -- TA-2 EXTREME
        statusText = "TA"
        statusIndicator = "TA-2 EXT"
        textColor = {0.8, 0.2, 0.2}      -- Red
        iconColor = {0.8, 0.2, 0.2, 1.0} -- Red
    end

    if isMinimal then
        -- Minimal Mode: Hide icon, show only text
        TAFrame.icon:Hide()

        -- Update text based on difficulty level
        TAFrame.statusText:SetText(statusText)
        TAFrame.statusText:SetTextColor(unpack(textColor))
        TAFrame.statusIndicator:SetText(statusIndicator)
        TAFrame.statusIndicator:SetTextColor(unpack(textColor))

        -- Reposition text for minimal mode (side-by-side)
        TAFrame.statusText:ClearAllPoints()
        TAFrame.statusText:SetPoint("RIGHT", TAFrame, "CENTER", -5, 0)
        TAFrame.statusText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

        TAFrame.statusIndicator:ClearAllPoints()
        TAFrame.statusIndicator:SetPoint("LEFT", TAFrame, "CENTER", 5, 0)
        TAFrame.statusIndicator:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    else
        -- Normal Mode: Show icon, position text as before
        TAFrame.icon:Show()

        -- Update icon color and text based on difficulty level
        TAFrame.icon:SetVertexColor(unpack(iconColor))
        TAFrame.statusText:SetText(statusText)
        TAFrame.statusText:SetTextColor(unpack(textColor))
        TAFrame.statusIndicator:SetText(statusIndicator)
        TAFrame.statusIndicator:SetTextColor(unpack(textColor))

        -- Restore original positioning
        TAFrame.statusText:ClearAllPoints()
        TAFrame.statusText:SetPoint("CENTER", TAFrame, "CENTER", 0, 5)
        TAFrame.statusText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")

        TAFrame.statusIndicator:ClearAllPoints()
        TAFrame.statusIndicator:SetPoint("BOTTOM", TAFrame, "BOTTOM", 0, -10)
        TAFrame.statusIndicator:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    end
end

-- Create the main display frame (similar to InfinitePower style)
local function CreateDisplay()
    -- Use core utility to create draggable frame
    TAFrame = ElegastCore:CreateDraggableFrame(
        "ElegastCoreTAFrame",
        UIParent,
        60,
        60,
        {point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -200, y = -150}  -- Similar to InfinitePower position
    )

    -- Create power icon texture (custom "TA" style)
    local icon = TAFrame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(TAFrame)
    icon:SetTexture("Interface\\Icons\\Spell_Shadow_SummonFelHunter")  -- An appropriate icon for Threatened Azeroth
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    TAFrame.icon = icon  -- Store reference for later use

    -- Create border for animations
    local border = TAFrame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAllPoints(TAFrame)
    border:SetVertexColor(0.4, 0.8, 1.0, 0)
    TAFrame.border = border

    -- Create status text (similar to stack count but just "TA")
    local statusText = TAFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
    statusText:SetPoint("CENTER", TAFrame, "CENTER", 0, 5)
    statusText:SetTextColor(1, 1, 1)
    statusText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    statusText:SetText("TA")
    TAFrame.statusText = statusText

    -- Create status indicator text below icon
    local statusIndicator = TAFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusIndicator:SetPoint("BOTTOM", TAFrame, "BOTTOM", 0, -10)
    statusIndicator:SetTextColor(0.4, 1.0, 0.4)
    statusIndicator:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    statusIndicator:SetText("Active")
    TAFrame.statusIndicator = statusIndicator

    -- Tooltip support
    TAFrame:EnableMouse(true)
    TAFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Threatened Azeroth", 0.5, 0.8, 1.0, 1, true)

        if taData.difficultyLevel == 0 then  -- OFF
            GameTooltip:AddLine("Status: |cffFF6666Inactive|r", 1, 1, 1, true)
            GameTooltip:AddLine("Speak to the Time-Keeper to activate", 0.8, 0.8, 0.8, true)
        elseif taData.difficultyLevel == 1 then  -- TA-1
            GameTooltip:AddLine("Status: |cffFFA500TA-1 ACTIVE|r", 1, 1, 1, true)
            GameTooltip:AddLine("Creatures have increased health and damage", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("5 stacks per threshold (vs 1 without TA)", 0.8, 0.8, 0.8, true)
        else  -- TA-2 EXTREME
            GameTooltip:AddLine("Status: |cffFF0000TA-2 EXTREME ACTIVE|r", 1, 1, 1, true)
            GameTooltip:AddLine("Creatures have significantly increased health and damage", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("10 stacks per threshold (vs 1 without TA)", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-Click to toggle minimal mode", 0.5, 0.5, 0.5, true)
        GameTooltip:AddLine("Shift + Drag to move", 0.5, 0.5, 0.5, true)
        GameTooltip:AddLine("/egc threatenedazeroth unlock - to move/scale", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)

    TAFrame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Right-click to toggle minimal mode
    TAFrame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            local currentMode = LoadMinimalMode()
            SaveMinimalMode(not currentMode)
            UpdateDisplay()
            local statusText = (not currentMode) and "Minimal mode enabled" or "Normal mode enabled"
            print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r " .. statusText)
        end
    end)

    -- Custom position save callback
    TAFrame.OnPositionChanged = function(self)
        if not savedVars then
            savedVars = {}
        end
        local point, _, relativePoint, x, y = self:GetPoint()
        savedVars.point = point
        savedVars.relativePoint = relativePoint
        savedVars.x = x
        savedVars.y = y

        if not ElegastCoreDB.ThreatenedAzeroth then
            ElegastCoreDB.ThreatenedAzeroth = {}
        end
        ElegastCoreDB.ThreatenedAzeroth.position = savedVars

        if self.unlocked then
            print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r Position saved! Type |cffFFFFFF/egc threatenedazeroth lock|r to lock it")
        end
    end

    -- Custom scale save callback
    TAFrame.OnScaleChanged = function(self)
        if not savedVars then
            savedVars = {}
        end
        savedVars.scale = self:GetScale()

        if not ElegastCoreDB.ThreatenedAzeroth then
            ElegastCoreDB.ThreatenedAzeroth = {}
        end
        ElegastCoreDB.ThreatenedAzeroth.position = savedVars
    end

    -- Make the frame scalable with griptape
    ElegastCore:MakeFrameScalable(TAFrame)

    -- Initially hide griptape (show only when unlocked)
    if TAFrame.griptape then
        TAFrame.griptape:Hide()
    end

    return TAFrame
end

-- Module initialization
function ThreatenedAzerothModule:OnInitialize()
    -- Load saved variables
    if ElegastCoreDB.ThreatenedAzeroth then
        savedVars = ElegastCoreDB.ThreatenedAzeroth.position or {}
    end

    -- Load saved player data (persists through /reload)
    LoadPlayerData()

    -- Create power display
    CreateDisplay()

    -- Restore saved position if available
    if savedVars.point then
        TAFrame:ClearAllPoints()
        TAFrame:SetPoint(
            savedVars.point,
            UIParent,
            savedVars.relativePoint,
            savedVars.x,
            savedVars.y
        )
    end

    -- Restore saved scale if available
    if savedVars.scale then
        TAFrame:SetScale(savedVars.scale)
    end

    -- Listen for system messages from the server
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    eventFrame:SetScript("OnEvent", function(self, event, message)
        if string.match(message, "^TA:") then
            if ParseServerMessage(message) then
                UpdateDisplay()
            end
        end
    end)

    -- Show initial display with loaded data
    UpdateDisplay()

    print("|cff66FFCCElegastCore:|r ThreatenedAzeroth module initialized")
end

-- Module command handler
function ThreatenedAzerothModule:OnCommand(args)
    local command = args[1] or ""

    if command == "reset" then
        TAFrame:ClearAllPoints()
        TAFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -150)
        TAFrame:SetScale(1.0)
        savedVars = {}
        ElegastCoreDB.ThreatenedAzeroth = {}
        print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r Position and scale reset to default!")

    elseif command == "unlock" or command == "move" then
        TAFrame.unlocked = not TAFrame.unlocked
        if TAFrame.unlocked then
            TAFrame:Show()
            TAFrame.statusText:SetText("∞")
            TAFrame.statusIndicator:SetText("MOVE")
            TAFrame.border:SetVertexColor(0.2, 1.0, 0.2, 0.8)
            -- Show griptape when unlocked
            if TAFrame.griptape then
                TAFrame.griptape:Show()
            end
            print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r |cff00FF00Unlocked!|r Drag to move, drag corner to scale")
        else
            TAFrame.unlocked = false
            TAFrame.border:SetVertexColor(0.4, 0.8, 1.0, 0)
            -- Hide griptape when locked
            if TAFrame.griptape then
                TAFrame.griptape:Hide()
            end
            UpdateDisplay()
            print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r |cffFF6666Locked!|r Position and scale saved")
        end

    elseif command == "lock" then
        TAFrame.unlocked = false
        TAFrame.border:SetVertexColor(0.4, 0.8, 1.0, 0)
        -- Hide griptape when locked
        if TAFrame.griptape then
            TAFrame.griptape:Hide()
        end
        UpdateDisplay()
        print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r |cffFF6666Locked!|r Position and scale saved")

    elseif command == "show" then
        TAFrame:Show()
        print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r Display shown")

    elseif command == "hide" then
        TAFrame:Hide()
        print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r Display hidden")

    elseif command == "minimal" then
        local setting = args[2]
        if setting == "on" then
            SaveMinimalMode(true)
            UpdateDisplay()
            print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r Minimal mode |cff00FF00enabled|r")
        elseif setting == "off" then
            SaveMinimalMode(false)
            UpdateDisplay()
            print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r Minimal mode |cffFF6666disabled|r")
        else
            -- Toggle minimal mode
            local currentMode = LoadMinimalMode()
            SaveMinimalMode(not currentMode)
            UpdateDisplay()
            local statusText = (not currentMode) and "|cff00FF00enabled|r" or "|cffFF6666disabled|r"
            print("|cff66FFCCElegastCore (ThreatenedAzeroth):|r Minimal mode " .. statusText)
        end

    else
        print("|cff66FFCC===== ElegastCore - ThreatenedAzeroth Module =====|r")
        print("|cffFFFFFF/egc threatenedazeroth unlock|r - Unlock to move and scale the display")
        print("|cffFFFFFF/egc threatenedazeroth lock|r - Lock the display in place")
        print("|cffFFFFFF/egc threatenedazeroth reset|r - Reset position and scale to default")
        print("|cffFFFFFF/egc threatenedazeroth show|r - Show the display")
        print("|cffFFFFFF/egc threatenedazeroth hide|r - Hide the display")
        print("|cffFFFFFF/egc threatenedazeroth minimal [on/off]|r - Toggle minimal display mode")
        print(" ")
        print("|cff888888Current Status:|r")
        local statusText
        if taData.difficultyLevel == 0 then
            statusText = "|cffFF6666Inactive|r"
        elseif taData.difficultyLevel == 1 then
            statusText = "|cffFFA500TA-1|r"
        else
            statusText = "|cffFF0000TA-2 EXTREME|r"
        end
        print("  Status: " .. statusText)
    end
end

-- Register the module with ElegastCore
ElegastCore:RegisterModule("threatenedazeroth", ThreatenedAzerothModule)