--[[
    ElegastCore - Modular Server-Specific Addon
    Main core file for module registration and initialization
]]--

-- Create main addon namespace
ElegastCore = ElegastCore or {}
ElegastCore.modules = {}
ElegastCore.version = "1.0.0"

-- Saved variables (initialized on load)
ElegastCoreDB = ElegastCoreDB or {}

-- Module registration system
function ElegastCore:RegisterModule(name, moduleTable)
    if not name or not moduleTable then
        print("|cffFF6666ElegastCore Error:|r Invalid module registration")
        return false
    end

    if self.modules[name] then
        print("|cffFF6666ElegastCore Warning:|r Module '" .. name .. "' already registered, overwriting...")
    end

    self.modules[name] = moduleTable

    -- Set up module namespace
    moduleTable.name = name
    moduleTable.enabled = true

    print("|cff66FFCCElegastCore:|r Registered module '" .. name .. "'")
    return true
end

-- Initialize a specific module
function ElegastCore:InitializeModule(name)
    local module = self.modules[name]
    if not module then
        print("|cffFF6666ElegastCore Error:|r Module '" .. name .. "' not found")
        return false
    end

    if not module.enabled then
        return false
    end

    -- Call module's OnInitialize if it exists
    if module.OnInitialize and type(module.OnInitialize) == "function" then
        local success, err = pcall(module.OnInitialize, module)
        if not success then
            print("|cffFF6666ElegastCore Error:|r Failed to initialize module '" .. name .. "': " .. tostring(err))
            module.enabled = false
            return false
        end
    end

    return true
end

-- Initialize all registered modules
function ElegastCore:InitializeAllModules()
    local count = 0
    for name, module in pairs(self.modules) do
        if self:InitializeModule(name) then
            count = count + 1
        end
    end
    return count
end

-- Enable/disable a module
function ElegastCore:SetModuleEnabled(name, enabled)
    local module = self.modules[name]
    if not module then
        print("|cffFF6666ElegastCore Error:|r Module '" .. name .. "' not found")
        return false
    end

    module.enabled = enabled

    -- Call module's OnEnable/OnDisable if they exist
    if enabled and module.OnEnable and type(module.OnEnable) == "function" then
        module:OnEnable()
    elseif not enabled and module.OnDisable and type(module.OnDisable) == "function" then
        module:OnDisable()
    end

    -- Save to DB
    if not ElegastCoreDB.modules then
        ElegastCoreDB.modules = {}
    end
    ElegastCoreDB.modules[name] = enabled

    return true
end

-- Get module by name
function ElegastCore:GetModule(name)
    return self.modules[name]
end

-- Get module by name (case-insensitive)
function ElegastCore:GetModuleCaseInsensitive(name)
    if not name then return nil end

    local lowerName = string.lower(name)

    -- First try exact match
    if self.modules[name] then
        return self.modules[name], name
    end

    -- Then try case-insensitive match
    for moduleName, module in pairs(self.modules) do
        if string.lower(moduleName) == lowerName then
            return module, moduleName
        end
    end

    return nil, nil
end

-- Utility: Create a draggable frame with saved position
function ElegastCore:CreateDraggableFrame(name, parent, width, height, defaultPoint)
    local frame = CreateFrame("Frame", name, parent or UIParent)
    frame:SetSize(width, height)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(10)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    -- Set default position
    if defaultPoint then
        frame:SetPoint(defaultPoint.point or "CENTER", UIParent, defaultPoint.relativePoint or "CENTER",
                      defaultPoint.x or 0, defaultPoint.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    -- Dragging behavior
    frame:SetScript("OnDragStart", function(self)
        if self.unlocked or IsShiftKeyDown() then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position callback
        if self.OnPositionChanged then
            self:OnPositionChanged()
        end
    end)

    return frame
end

-- Utility: Make a frame scalable with a griptape handle
function ElegastCore:MakeFrameScalable(frame)
    if not frame then return end

    -- Create griptape button (resize handle)
    local griptape = CreateFrame("Button", nil, frame)
    griptape:SetSize(16, 16)
    griptape:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    griptape:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Create griptape texture (diagonal lines pattern)
    local gripTexture = griptape:CreateTexture(nil, "OVERLAY")
    gripTexture:SetAllPoints(griptape)
    gripTexture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTexture:SetAlpha(0.5)

    -- Highlight texture for mouse over
    local gripHighlight = griptape:CreateTexture(nil, "HIGHLIGHT")
    gripHighlight:SetAllPoints(griptape)
    gripHighlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    gripHighlight:SetBlendMode("ADD")

    -- Scaling variables
    local isScaling = false
    local startScale = 1.0
    local startX, startY = 0, 0

    -- Mouse down: Start scaling
    griptape:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            isScaling = true
            startScale = frame:GetScale()
            startX, startY = GetCursorPosition()
            self:SetScript("OnUpdate", function(self)
                if isScaling then
                    local cursorX, cursorY = GetCursorPosition()
                    local effectiveScale = UIParent:GetEffectiveScale()

                    -- Calculate delta from starting position
                    local deltaX = (cursorX - startX) / effectiveScale
                    local deltaY = (cursorY - startY) / effectiveScale

                    -- Griptape is in bottom-right, so:
                    -- Dragging right (positive X) OR down (negative Y) = bigger
                    -- Dragging left (negative X) OR up (positive Y) = smaller
                    -- Use the average, but invert Y since screen Y increases downward
                    local delta = (deltaX - deltaY) / 2

                    -- Calculate new scale (scale by distance / 150 for sensitivity)
                    local newScale = startScale + (delta / 150)

                    -- Clamp scale between 0.5 and 3.0
                    newScale = math.max(0.5, math.min(3.0, newScale))

                    frame:SetScale(newScale)
                end
            end)
        end
    end)

    -- Mouse up: Stop scaling and save
    griptape:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and isScaling then
            isScaling = false
            self:SetScript("OnUpdate", nil)

            -- Call save callback if it exists
            if frame.OnScaleChanged then
                frame:OnScaleChanged()
            end
        end
    end)

    -- Store reference to griptape
    frame.griptape = griptape

    return griptape
end

-- Utility: Smooth easing functions for animations
ElegastCore.Easing = {
    EaseOutElastic = function(t)
        local p = 0.3
        return math.pow(2, -10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
    end,

    EaseOutBack = function(t)
        local s = 1.70158
        t = t - 1
        return t * t * ((s + 1) * t + s) + 1
    end,

    EaseInOutQuad = function(t)
        if t < 0.5 then
            return 2 * t * t
        else
            return -1 + (4 - 2 * t) * t
        end
    end
}

-- Main initialization on login
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Initialize saved variables
        if not ElegastCoreDB then
            ElegastCoreDB = {}
        end

        if not ElegastCoreDB.modules then
            ElegastCoreDB.modules = {}
        end

        -- Restore module enabled states from DB
        for name, module in pairs(ElegastCore.modules) do
            if ElegastCoreDB.modules[name] ~= nil then
                module.enabled = ElegastCoreDB.modules[name]
            end
        end

        -- Initialize all modules
        local moduleCount = ElegastCore:InitializeAllModules()

        -- Welcome message
        print("|cff66FFCC========================================|r")
        print("|cff66FFCCElegastCore|r |cffFFFFFFv" .. ElegastCore.version .. "|r loaded!")
        print("|cffFFFFFF" .. moduleCount .. " module(s) initialized|r")
        print("|cffFFFFFFType|r |cff66FFCC/egc|r |cffFFFFFFfor options|r")
        print("|cff66FFCC========================================|r")
    end
end)

-- Slash command handler
SLASH_ELEGASTCORE1 = "/elegastcore"
SLASH_ELEGASTCORE2 = "/egc"
SLASH_ELEGASTCORE3 = "/elegast"
SlashCmdList["ELEGASTCORE"] = function(msg)
    local args = {}
    for word in string.gmatch(msg, "%S+") do
        table.insert(args, string.lower(word))
    end

    local command = args[1] or ""

    if command == "" or command == "help" then
        -- Show help
        print("|cff66FFCC===== ElegastCore v" .. ElegastCore.version .. " =====|r")
        print("|cffFFFFFF/egc modules|r - List all registered modules")
        print("|cffFFFFFF/egc enable <module>|r - Enable a module")
        print("|cffFFFFFF/egc disable <module>|r - Disable a module")
        print("|cffFFFFFF/egc <module> <args>|r - Pass command to specific module")
        print(" ")
        print("|cff888888Registered Modules:|r")
        for name, module in pairs(ElegastCore.modules) do
            local status = module.enabled and "|cff00FF00enabled|r" or "|cffFF6666disabled|r"
            print("  |cff66FFCC" .. name .. "|r - " .. status)
        end

    elseif command == "modules" then
        -- List modules
        print("|cff66FFCC===== Registered Modules =====|r")
        local hasModules = false
        for name, module in pairs(ElegastCore.modules) do
            hasModules = true
            local status = module.enabled and "|cff00FF00enabled|r" or "|cffFF6666disabled|r"
            local version = module.version or "unknown"
            print("|cff66FFCC" .. name .. "|r v" .. version .. " - " .. status)
        end
        if not hasModules then
            print("|cff888888No modules registered|r")
        end

    elseif command == "enable" then
        local moduleName = args[2]
        if not moduleName then
            print("|cffFF6666ElegastCore:|r Please specify a module name")
            return
        end

        -- Use case-insensitive lookup
        local module, actualName = ElegastCore:GetModuleCaseInsensitive(moduleName)
        if actualName and ElegastCore:SetModuleEnabled(actualName, true) then
            print("|cff66FFCCElegastCore:|r Module '" .. actualName .. "' enabled")
            -- Reinitialize the module
            ElegastCore:InitializeModule(actualName)
        else
            print("|cffFF6666ElegastCore:|r Module '" .. moduleName .. "' not found")
        end

    elseif command == "disable" then
        local moduleName = args[2]
        if not moduleName then
            print("|cffFF6666ElegastCore:|r Please specify a module name")
            return
        end

        -- Use case-insensitive lookup
        local module, actualName = ElegastCore:GetModuleCaseInsensitive(moduleName)
        if actualName and ElegastCore:SetModuleEnabled(actualName, false) then
            print("|cff66FFCCElegastCore:|r Module '" .. actualName .. "' disabled")
        else
            print("|cffFF6666ElegastCore:|r Module '" .. moduleName .. "' not found")
        end

    else
        -- Try to pass command to a module (case-insensitive)
        local module, actualName = ElegastCore:GetModuleCaseInsensitive(command)

        if module and module.OnCommand and type(module.OnCommand) == "function" then
            -- Remove module name from args
            table.remove(args, 1)
            module:OnCommand(args)
        else
            print("|cffFF6666ElegastCore:|r Unknown command or module '" .. command .. "'")
            print("|cffFFFFFFType|r |cff66FFCC/egc help|r |cffFFFFFFfor available commands|r")
        end
    end
end
