--[[
    SpeedBuff Module for ElegastCore
    Shows speed buff stacks with Sprint-like appearance
]]--

-- Create module table
local SpeedBuffModule = {
    version = "1.0.0",
    name = "SpeedBuff"
}

-- Spell IDs from the module
local SPELL_IDS = {
    [900001] = 1,  -- Stack 1 (20% speed)
    [900002] = 2,  -- Stack 2 (40% speed)
    [900003] = 3,  -- Stack 3 (60% speed)
    [900004] = 4,  -- Stack 4 (80% speed)
}

-- Sprint icon texture path
local SPRINT_ICON = "Interface\\Icons\\Ability_Rogue_Sprint"

-- Module-specific saved variables
local savedVars = {}

-- Main display frame (will be created on initialization)
local SpeedBuffFrame = nil

-- Chat filter to hide our messages from displaying in chat
local function ChatFilter(self, event, msg, ...)
    if string.match(msg, "^SPEEDBUFF:") then
        return true  -- Block this message
    end
    return false
end

-- Save minimal mode preference
local function SaveMinimalMode(enabled)
    if not ElegastCoreDB.SpeedBuff then
        ElegastCoreDB.SpeedBuff = {}
    end
    ElegastCoreDB.SpeedBuff.minimal = enabled
end

-- Load minimal mode preference
local function LoadMinimalMode()
    if ElegastCoreDB.SpeedBuff and ElegastCoreDB.SpeedBuff.minimal ~= nil then
        return ElegastCoreDB.SpeedBuff.minimal
    end
    return false -- Default to normal mode
end

-- Smooth easing helper (uses core easing functions)
local function EaseOutElastic(t)
    return ElegastCore.Easing.EaseOutElastic(t)
end

local function EaseOutBack(t)
    return ElegastCore.Easing.EaseOutBack(t)
end

-- Function to update display based on server-sent stack level
local function UpdateSpeedBuffDisplay()
    if not SpeedBuffFrame then return end

    -- Don't update if in test mode
    if SpeedBuffFrame.testMode then
        return
    end

    local currentStack = SpeedBuffFrame.serverStack or 0
    local isMinimal = LoadMinimalMode()

    -- Update display
    if currentStack > 0 then
        SpeedBuffFrame.currentStack = currentStack

        -- Calculate speed percentage
        local speedPercent = currentStack * 20

        if isMinimal then
            -- Minimal mode: Hide icon and edges, show compact text
            SpeedBuffFrame.icon:Hide()
            if SpeedBuffFrame.cooldownEdge then
                SpeedBuffFrame.cooldownEdge:Hide()
            end
            SpeedBuffFrame.stackText:SetText(currentStack)
            SpeedBuffFrame.durationText:SetText("+" .. speedPercent .. "%")

            -- Reposition for minimal mode (side-by-side)
            SpeedBuffFrame.stackText:ClearAllPoints()
            SpeedBuffFrame.stackText:SetPoint("RIGHT", SpeedBuffFrame, "CENTER", -5, 0)
            SpeedBuffFrame.stackText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

            SpeedBuffFrame.durationText:ClearAllPoints()
            SpeedBuffFrame.durationText:SetPoint("LEFT", SpeedBuffFrame, "CENTER", 5, 0)
            SpeedBuffFrame.durationText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        else
            -- Normal mode: Show icon and edges, restore original positioning
            SpeedBuffFrame.icon:Show()
            if SpeedBuffFrame.cooldownEdge then
                SpeedBuffFrame.cooldownEdge:Show()
            end
            SpeedBuffFrame.stackText:SetText(currentStack)
            SpeedBuffFrame.durationText:SetText("+" .. speedPercent .. "%")

            -- Restore original positioning
            SpeedBuffFrame.stackText:ClearAllPoints()
            SpeedBuffFrame.stackText:SetPoint("BOTTOMRIGHT", SpeedBuffFrame, "BOTTOMRIGHT", -3, 3)
            SpeedBuffFrame.stackText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")

            SpeedBuffFrame.durationText:ClearAllPoints()
            SpeedBuffFrame.durationText:SetPoint("BOTTOM", SpeedBuffFrame, "BOTTOM", 0, -14)
            SpeedBuffFrame.durationText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        end

        SpeedBuffFrame:Show()

        -- Mark when we received this stack update (even if stack level didn't change)
        -- This is important because at max stacks, the server refreshes every 5 seconds
        SpeedBuffFrame.lastStackUpdateTime = GetTime()

        -- Pulse effect when gaining new stack
        if SpeedBuffFrame.lastStack ~= currentStack then
            SpeedBuffFrame.lastStack = currentStack

            -- Start smooth scale animation
            SpeedBuffFrame.animationTime = 0
            SpeedBuffFrame.animationDuration = 0.4  -- 400ms
            SpeedBuffFrame.animationStartScale = 1.0
            SpeedBuffFrame.animationTargetScale = 1.0
            SpeedBuffFrame.isAnimating = true

            -- Start border glow
            SpeedBuffFrame.borderGlowTime = 0
            SpeedBuffFrame.borderGlowDuration = 0.5  -- 500ms
            SpeedBuffFrame.isBorderGlowing = true
        end
    else
        SpeedBuffFrame.currentStack = 0
        SpeedBuffFrame.lastStack = 0
        SpeedBuffFrame.isFadingOut = true
        SpeedBuffFrame.fadeOutTime = 0
        SpeedBuffFrame.fadeOutDuration = 0.3  -- 300ms
    end
end

-- Create the display frame
local function CreateDisplayFrame()
    -- Use core utility to create draggable frame
    SpeedBuffFrame = ElegastCore:CreateDraggableFrame(
        "ElegastCoreSpeedBuffFrame",
        UIParent,
        44,
        44,
        {point = "TOPRIGHT", relativePoint = "TOPRIGHT", x = -200, y = -150}
    )

    -- Create icon texture (fills entire frame)
    local icon = SpeedBuffFrame:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(SpeedBuffFrame)
    icon:SetTexture(SPRINT_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- Crop icon edges for cleaner look
    SpeedBuffFrame.icon = icon  -- Store reference for showing/hiding

    -- Create cooldown-style edge for depth
    local cooldownEdge = SpeedBuffFrame:CreateTexture(nil, "BORDER")
    cooldownEdge:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    cooldownEdge:SetBlendMode("ADD")
    cooldownEdge:SetAllPoints(SpeedBuffFrame)
    cooldownEdge:SetVertexColor(0.5, 0.5, 0.5, 0.3)  -- Subtle edge
    SpeedBuffFrame.cooldownEdge = cooldownEdge  -- Store reference for showing/hiding

    -- Create border glow (for animations)
    local border = SpeedBuffFrame:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetAllPoints(SpeedBuffFrame)
    border:SetVertexColor(0.4, 0.8, 1.0, 0)  -- Start invisible
    SpeedBuffFrame.border = border

    -- Create stack count text
    local stackText = SpeedBuffFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    stackText:SetPoint("BOTTOMRIGHT", SpeedBuffFrame, "BOTTOMRIGHT", -3, 3)
    stackText:SetTextColor(1, 1, 1)
    stackText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    SpeedBuffFrame.stackText = stackText

    -- Create duration text (speed percentage)
    local durationText = SpeedBuffFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationText:SetPoint("BOTTOM", SpeedBuffFrame, "BOTTOM", 0, -14)
    durationText:SetTextColor(0.4, 1.0, 0.4)  -- Bright green for speed
    durationText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    SpeedBuffFrame.durationText = durationText

    -- Create timer text (countdown)
    local timerText = SpeedBuffFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerText:SetPoint("TOP", SpeedBuffFrame, "TOP", 0, 14)
    timerText:SetTextColor(1.0, 1.0, 0.4)  -- Yellow for timer
    timerText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    SpeedBuffFrame.timerText = timerText

    -- Tooltip support
    SpeedBuffFrame:EnableMouse(true)
    SpeedBuffFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Speed Buff", 0.4, 0.8, 1.0, 1, true)

        local currentStack = self.currentStack or 0
        local speeds = {
            [1] = "20%",
            [2] = "40%",
            [3] = "60%",
            [4] = "80%"
        }

        if currentStack > 0 then
            GameTooltip:AddLine("Stack " .. currentStack .. " of 4", 0.4, 1.0, 0.4, true)
            GameTooltip:AddLine("Movement speed increased by " .. (speeds[currentStack] or "0%"), 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            if currentStack < 4 then
                GameTooltip:AddLine("Keep running to gain more stacks!", 0.7, 0.7, 1.0, true)
            else
                GameTooltip:AddLine("Maximum stacks reached!", 1.0, 0.8, 0.2, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Right-Click to toggle minimal mode", 0.5, 0.5, 0.5, true)
            GameTooltip:AddLine("Shift + Drag to move", 0.5, 0.5, 0.5, true)
            GameTooltip:AddLine("/egc speedbuff unlock - to move/scale", 0.5, 0.5, 0.5, true)
        end

        GameTooltip:Show()
    end)

    SpeedBuffFrame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Right-click to toggle minimal mode
    SpeedBuffFrame:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            local currentMode = LoadMinimalMode()
            SaveMinimalMode(not currentMode)
            UpdateSpeedBuffDisplay()
            local statusText = (not currentMode) and "Minimal mode enabled" or "Normal mode enabled"
            print("|cff66FFCCElegastCore (SpeedBuff):|r " .. statusText)
        end
    end)

    -- Custom position save callback
    SpeedBuffFrame.OnPositionChanged = function(self)
        if not savedVars then
            savedVars = {}
        end
        local point, _, relativePoint, x, y = self:GetPoint()
        savedVars.point = point
        savedVars.relativePoint = relativePoint
        savedVars.x = x
        savedVars.y = y

        -- Save to global DB
        if not ElegastCoreDB.SpeedBuff then
            ElegastCoreDB.SpeedBuff = {}
        end
        ElegastCoreDB.SpeedBuff.position = savedVars

        -- Give feedback
        if self.unlocked then
            print("|cff66FFCCElegastCore (SpeedBuff):|r Position saved! Type |cffFFFFFF/egc speedbuff lock|r to lock it")
        end
    end

    -- Custom scale save callback
    SpeedBuffFrame.OnScaleChanged = function(self)
        if not savedVars then
            savedVars = {}
        end
        savedVars.scale = self:GetScale()
        self.baseScale = self:GetScale()  -- Update base scale for animations

        -- Save to global DB
        if not ElegastCoreDB.SpeedBuff then
            ElegastCoreDB.SpeedBuff = {}
        end
        ElegastCoreDB.SpeedBuff.position = savedVars
    end

    -- Animation variables
    SpeedBuffFrame.serverStack = 0
    SpeedBuffFrame.animationTime = 0
    SpeedBuffFrame.animationDuration = 0
    SpeedBuffFrame.animationStartScale = 1.0
    SpeedBuffFrame.animationTargetScale = 1.0
    SpeedBuffFrame.isAnimating = false
    SpeedBuffFrame.baseScale = 1.0  -- Store the base scale for animations
    SpeedBuffFrame.borderGlowTime = 0
    SpeedBuffFrame.borderGlowDuration = 0
    SpeedBuffFrame.isBorderGlowing = false

    -- Timer variables
    SpeedBuffFrame.lastStackUpdateTime = 0  -- When we last received a stack update
    SpeedBuffFrame.buffDuration = 15  -- 15 seconds duration
    SpeedBuffFrame.showTimerDelay = 6.0  -- Only show timer after 6 seconds of no updates (means we stopped running)

    -- Make the frame scalable with griptape
    ElegastCore:MakeFrameScalable(SpeedBuffFrame)

    -- Initially hide griptape (show only when unlocked)
    if SpeedBuffFrame.griptape then
        SpeedBuffFrame.griptape:Hide()
    end

    -- Main update loop for smooth animations
    local updateTimer = 0
    SpeedBuffFrame:SetScript("OnUpdate", function(self, elapsed)
        -- Update timer display
        if self.currentStack > 0 and not self.testMode and self.lastStackUpdateTime > 0 then
            local currentTime = GetTime()
            local timeSinceLastUpdate = currentTime - self.lastStackUpdateTime

            -- Only show timer if we haven't received an update in showTimerDelay seconds
            -- While running: server refreshes every 5s, so timeSinceLastUpdate < 6s, timer hidden
            -- When stopped: no updates, timeSinceLastUpdate > 6s, timer shows
            if timeSinceLastUpdate >= self.showTimerDelay then
                local timeRemaining = self.buffDuration - timeSinceLastUpdate

                if timeRemaining > 0 then
                    -- Format timer text
                    local timerStr
                    if timeRemaining >= 10 then
                        timerStr = string.format("%ds", math.ceil(timeRemaining))
                    else
                        timerStr = string.format("%.1fs", timeRemaining)
                    end
                    self.timerText:SetText(timerStr)

                    -- Color code based on time remaining
                    if timeRemaining > 10 then
                        self.timerText:SetTextColor(0.4, 1.0, 0.4)  -- Green
                    elseif timeRemaining > 5 then
                        self.timerText:SetTextColor(1.0, 1.0, 0.4)  -- Yellow
                    else
                        self.timerText:SetTextColor(1.0, 0.4, 0.4)  -- Red
                    end
                else
                    self.timerText:SetText("")
                end
            else
                -- Still actively running (receiving regular updates)
                self.timerText:SetText("")
            end
        else
            self.timerText:SetText("")
        end

        -- Handle scale animation (bounce effect)
        if self.isAnimating then
            self.animationTime = self.animationTime + elapsed
            local progress = math.min(self.animationTime / self.animationDuration, 1.0)

            if progress < 1.0 then
                -- Bounce from baseScale -> baseScale*1.3 -> baseScale using smooth easing
                local scale
                local baseScale = self.baseScale or 1.0
                if progress < 0.5 then
                    -- First half: scale up by 30%
                    local t = progress * 2  -- 0 to 1
                    scale = baseScale + (baseScale * 0.3 * EaseOutBack(t))
                else
                    -- Second half: scale back to base
                    local t = (progress - 0.5) * 2  -- 0 to 1
                    scale = (baseScale * 1.3) - (baseScale * 0.3 * t)
                end
                self:SetScale(scale)
            else
                self:SetScale(self.baseScale or 1.0)
                self.isAnimating = false
            end
        end

        -- Handle border glow animation
        if self.isBorderGlowing then
            self.borderGlowTime = self.borderGlowTime + elapsed
            local progress = math.min(self.borderGlowTime / self.borderGlowDuration, 1.0)

            if progress < 1.0 then
                -- Fade green glow in then out
                local alpha
                if progress < 0.3 then
                    -- Fade in
                    alpha = progress / 0.3
                    self.border:SetVertexColor(0.2, 1.0, 0.2, alpha)
                else
                    -- Fade out
                    alpha = 1.0 - ((progress - 0.3) / 0.7)
                    self.border:SetVertexColor(0.2, 1.0, 0.2, alpha)
                end
            else
                self.border:SetVertexColor(0.4, 0.8, 1.0, 0)
                self.isBorderGlowing = false
            end
        end

        -- Handle fade out animation
        if self.isFadingOut then
            self.fadeOutTime = self.fadeOutTime + elapsed
            local progress = math.min(self.fadeOutTime / self.fadeOutDuration, 1.0)

            if progress < 1.0 then
                self:SetAlpha(1.0 - progress)
            else
                self:Hide()
                self:SetAlpha(1.0)
                self.isFadingOut = false
            end
        end

        -- Periodic update check
        updateTimer = updateTimer + elapsed
        if updateTimer >= 0.5 then
            updateTimer = 0
        end
    end)

    return SpeedBuffFrame
end

-- Module initialization
function SpeedBuffModule:OnInitialize()
    -- Load saved variables
    if ElegastCoreDB.SpeedBuff then
        savedVars = ElegastCoreDB.SpeedBuff.position or {}
    end

    -- Create display frame
    CreateDisplayFrame()

    -- Restore saved position if available
    if savedVars.point then
        SpeedBuffFrame:ClearAllPoints()
        SpeedBuffFrame:SetPoint(
            savedVars.point,
            UIParent,
            savedVars.relativePoint,
            savedVars.x,
            savedVars.y
        )
    end

    -- Restore saved scale if available
    if savedVars.scale then
        SpeedBuffFrame:SetScale(savedVars.scale)
        SpeedBuffFrame.baseScale = savedVars.scale
    end

    -- ElvUI compatibility
    if ElvUI then
        local E = unpack(ElvUI)
        if E and E.FrameLocks then
            E.FrameLocks[SpeedBuffFrame:GetName()] = true
        end
        print("|cff66FFCCElegastCore (SpeedBuff):|r ElvUI compatibility enabled")
    end

    -- Register chat filter
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)

    -- Chat message listener to receive stack updates from server
    local chatFrame = CreateFrame("Frame")
    chatFrame:RegisterEvent("CHAT_MSG_SYSTEM")
    chatFrame:SetScript("OnEvent", function(self, event, msg)
        -- Look for our special message format: "SPEEDBUFF:STACK:X"
        local stack = string.match(msg, "SPEEDBUFF:STACK:(%d+)")
        if stack then
            SpeedBuffFrame.serverStack = tonumber(stack) or 0
            UpdateSpeedBuffDisplay()
        end
    end)

    print("|cff66FFCCElegastCore:|r SpeedBuff module initialized")
end

-- Module command handler
function SpeedBuffModule:OnCommand(args)
    local command = args[1] or ""

    if command == "reset" then
        SpeedBuffFrame:ClearAllPoints()
        SpeedBuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -150)
        SpeedBuffFrame:SetScale(1.0)
        SpeedBuffFrame.baseScale = 1.0
        savedVars = {}
        ElegastCoreDB.SpeedBuff = {}
        print("|cff66FFCCElegastCore (SpeedBuff):|r Position and scale reset to default!")

    elseif command == "unlock" or command == "move" then
        SpeedBuffFrame.unlocked = not SpeedBuffFrame.unlocked
        if SpeedBuffFrame.unlocked then
            -- Show a visible indicator that it's unlocked
            SpeedBuffFrame.testMode = true
            SpeedBuffFrame.currentStack = 4
            SpeedBuffFrame.stackText:SetText("4")
            SpeedBuffFrame.durationText:SetText("+80%")
            SpeedBuffFrame:Show()
            -- Add pulsing glow to show it's movable
            SpeedBuffFrame.border:SetVertexColor(0.2, 1.0, 0.2, 0.8)
            -- Show griptape when unlocked
            if SpeedBuffFrame.griptape then
                SpeedBuffFrame.griptape:Show()
            end
            print("|cff66FFCCElegastCore (SpeedBuff):|r |cff00FF00Unlocked!|r Drag to move, drag corner to scale")
        else
            SpeedBuffFrame.testMode = false
            SpeedBuffFrame.unlocked = false
            SpeedBuffFrame.border:SetVertexColor(0.4, 0.8, 1.0, 0)
            -- Hide griptape when locked
            if SpeedBuffFrame.griptape then
                SpeedBuffFrame.griptape:Hide()
            end
            UpdateSpeedBuffDisplay()
            print("|cff66FFCCElegastCore (SpeedBuff):|r |cffFF6666Locked!|r Position and scale saved")
        end

    elseif command == "lock" then
        SpeedBuffFrame.testMode = false
        SpeedBuffFrame.unlocked = false
        SpeedBuffFrame.border:SetVertexColor(0.4, 0.8, 1.0, 0)
        -- Hide griptape when locked
        if SpeedBuffFrame.griptape then
            SpeedBuffFrame.griptape:Hide()
        end
        UpdateSpeedBuffDisplay()
        print("|cff66FFCCElegastCore (SpeedBuff):|r |cffFF6666Locked!|r Position and scale saved")

    elseif command == "test" then
        -- Show test display with animation
        SpeedBuffFrame.testMode = false  -- Enable timer during test
        SpeedBuffFrame.currentStack = 1
        SpeedBuffFrame.serverStack = 1
        SpeedBuffFrame.lastStackUpdateTime = GetTime()
        UpdateSpeedBuffDisplay()

        print("|cff66FFCCElegastCore (SpeedBuff):|r Testing stack progression...")

        C_Timer.After(1.5, function()
            SpeedBuffFrame.serverStack = 2
            UpdateSpeedBuffDisplay()
        end)

        C_Timer.After(3, function()
            SpeedBuffFrame.serverStack = 3
            UpdateSpeedBuffDisplay()
        end)

        C_Timer.After(4.5, function()
            SpeedBuffFrame.serverStack = 4
            UpdateSpeedBuffDisplay()
        end)

        C_Timer.After(6.5, function()
            print("|cff66FFCCElegastCore (SpeedBuff):|r Test will show timer after 6 seconds of no updates...")
            -- Don't clear serverStack - let timer countdown play out
        end)

        C_Timer.After(20, function()
            print("|cff66FFCCElegastCore (SpeedBuff):|r Test complete, returning to normal...")
            SpeedBuffFrame.testMode = false
            SpeedBuffFrame.serverStack = 0
            UpdateSpeedBuffDisplay()
        end)

    elseif command == "minimal" then
        local setting = args[2]
        if setting == "on" then
            SaveMinimalMode(true)
            UpdateSpeedBuffDisplay()
            print("|cff66FFCCElegastCore (SpeedBuff):|r Minimal mode |cff00FF00enabled|r")
        elseif setting == "off" then
            SaveMinimalMode(false)
            UpdateSpeedBuffDisplay()
            print("|cff66FFCCElegastCore (SpeedBuff):|r Minimal mode |cffFF6666disabled|r")
        else
            -- Toggle minimal mode
            local currentMode = LoadMinimalMode()
            SaveMinimalMode(not currentMode)
            UpdateSpeedBuffDisplay()
            local statusText = (not currentMode) and "|cff00FF00enabled|r" or "|cffFF6666disabled|r"
            print("|cff66FFCCElegastCore (SpeedBuff):|r Minimal mode " .. statusText)
        end

    else
        print("|cff66FFCC===== ElegastCore - SpeedBuff Module =====|r")
        print("|cffFFFFFF/egc speedbuff unlock|r - Unlock to move and scale the buff display")
        print("|cffFFFFFF/egc speedbuff lock|r - Lock the buff display in place")
        print("|cffFFFFFF/egc speedbuff reset|r - Reset position and scale to default")
        print("|cffFFFFFF/egc speedbuff test|r - Test the display animation")
        print("|cffFFFFFF/egc speedbuff minimal [on/off]|r - Toggle minimal display mode")
        print(" ")
        print("|cff888888Shift + Drag also works when buff is active|r")
    end
end

-- Register the module with ElegastCore
ElegastCore:RegisterModule("SpeedBuff", SpeedBuffModule)
