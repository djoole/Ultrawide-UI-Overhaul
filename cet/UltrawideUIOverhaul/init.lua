local MOD_NAME = "Ultrawide UI Overhaul"
local VERSION = "1.1.0"
local LOG_PREFIX = "[UltrawideUIOverhaul]"
local DEBUG = false

-- Diagnostic build switch:
--   true  = write live main-menu diagnostics for testers
--   false = production build; no diagnostic file or diagnostic I/O
local MAIN_MENU_DIAGNOSTICS = false
local MAIN_MENU_DIAGNOSTIC_FILE = "main_menu_diagnostic.log"

local REFERENCE_HEIGHT = 2160.0
local VIEWPORT_HEIGHT = 1080.0
local CAMERA_HEIGHT = 720
local MIN_SUPPORTED_ASPECT = 2.30
local MAX_SUPPORTED_ASPECT = 2.45

local pendingLayouts = {}
local activeHubMenu = ""
local settingsProbePrinted = false
local mainMenuRetryBudget = 1200
local mainMenuRetryTimer = 0.0
local mainMenuPillarTimer = 0.0
local mainMenuPillarPending = false
local mainMenuPillarsDisabled = false
local mainMenuDiagnosticAttempt = 0
local mainMenuDiagnosticSignature = ""
local mainMenuSceneReadyPasses = 0
local stealthRunnerRetryBudget = 0
local stealthRunnerRetryTimer = 0.0
local stealthRunnerProbePrinted = false
local stealthRunnerScanTimer = 0.0
local menuHintWidgetNames = {
    cyberware_equip = "button_hints",
    backpack = "button_hints",
    crafting_main = "buttonHintContainer",
    temp_stats = "button_hints",
    gallery = "inputHints",
    shards = "button_hints"
}

local function debugLog(message)
    if DEBUG then print(message) end
end

local function initializeDiagnosticLog()
    if not MAIN_MENU_DIAGNOSTICS then return end

    local file = io.open(MAIN_MENU_DIAGNOSTIC_FILE, "w")
    if file ~= nil then
        file:write(string.format(
            "[%s] [MainMenuDiagnostics] diagnostic logging initialized\n",
            os.date("%Y-%m-%d %H:%M:%S")
        ))
        file:flush()
        file:close()
    end
end

local function diagnosticLog(message)
    if not MAIN_MENU_DIAGNOSTICS then return end

    local file = io.open(MAIN_MENU_DIAGNOSTIC_FILE, "a")
    if file ~= nil then
        file:write(string.format(
            "[%s] [MainMenuDiagnostics] %s\n",
            os.date("%Y-%m-%d %H:%M:%S"), tostring(message)
        ))
        file:flush()
        file:close()
    end
end

local function safe(callback)
    local ok, value = pcall(callback)
    return ok and value or nil
end

local function widgetName(widget)
    return safe(function() return widget:GetName().value end) or ""
end

local function cnameEquals(value, expected)
    local rawValue = safe(function() return value.value end)
    return rawValue == expected or tostring(value) == expected
end

local function cnameValue(value)
    return safe(function() return value.value end) or tostring(value)
end

local function collectByName(root, wantedName, maxDepth)
    local matches = {}

    local function visit(widget, depth)
        if widget == nil then return end

        if widgetName(widget) == wantedName then
            table.insert(matches, widget)
        end

        if depth >= maxDepth then return end

        local count = safe(function() return widget:GetNumChildren() end)
        if count == nil then return end

        for index = 0, count - 1 do
            visit(safe(function() return widget:GetWidget(index) end), depth + 1)
        end
    end

    visit(root, 0)
    return matches
end

local function resizeNamedWidgets(root, name, width, height)
    local resized = 0
    for _, widget in ipairs(collectByName(root, name, 12)) do
        local ok = pcall(function()
            widget:SetSize(width, height)
            widget:SetMargin(0.0, 0.0, 0.0, 0.0)
        end)
        if ok then resized = resized + 1 end
    end
    return resized
end

local function getTargetGeometry()
    local displayWidth, displayHeight = GetDisplayResolution()
    if displayWidth == nil or displayHeight == nil or displayHeight <= 0 then
        return nil
    end

    local aspect = displayWidth / displayHeight
    if aspect < MIN_SUPPORTED_ASPECT or aspect > MAX_SUPPORTED_ASPECT then
        return nil
    end

    return {
        aspect = aspect,
        viewportWidth = aspect * VIEWPORT_HEIGHT,
        contentWidth = aspect * REFERENCE_HEIGHT,
        cameraWidth = math.floor(aspect * CAMERA_HEIGHT + 0.5),
        cameraHeight = CAMERA_HEIGHT
    }
end

local function positionRightFluff(root, geometry, maxDepth)
    if root == nil or geometry == nil then return 0 end

    local positioned = 0
    local horizontalInset = (geometry.contentWidth - 3840.0) * 0.5
    for _, widget in ipairs(collectByName(root, "Right_fluff_elements", maxDepth or 24)) do
        local ok = pcall(function()
            -- Keep the vanilla canvas intact and translate it to the 21:9
            -- right edge. Resizing it reverses the apparent displacement due
            -- to the anchoring of its internal artwork.
            widget:SetSize(3840.0, REFERENCE_HEIGHT)
            widget:SetMargin(horizontalInset - 3.0, -5.0, 0.0, 0.0)
        end)
        if ok then positioned = positioned + 1 end
    end
    return positioned
end

local function applyMenuShellLayout(geometry)
    local layer = safe(function()
        return Game.GetInkSystem():GetLayer(CName.new("inkMenuLayer"))
    end)
    local virtualWindow = layer ~= nil and safe(function()
        return layer:GetVirtualWindow()
    end) or nil
    if virtualWindow == nil then
        print(LOG_PREFIX .. " menu VirtualWindow unavailable")
        return
    end

    local resizedRoots = 0
    local function visitShell(widget, depth)
        if widget == nil or depth > 2 then return end

        local size = safe(function() return widget:GetSize() end)
        local name = widgetName(widget)
        if name == "Root" and size ~= nil and
            size.X >= 3800.0 and size.X <= 3860.0 and
            size.Y >= 2100.0 and size.Y <= 2200.0 then
            local ok = pcall(function()
                widget:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
                widget:SetMargin(0.0, 0.0, 0.0, 0.0)
            end)
            if ok then resizedRoots = resizedRoots + 1 end
        end

        local count = safe(function() return widget:GetNumChildren() end)
        if count == nil then return end
        for index = 0, count - 1 do
            visitShell(safe(function() return widget:GetWidget(index) end), depth + 1)
        end
    end

    visitShell(virtualWindow, 0)
    local topPanels = resizeNamedWidgets(
        virtualWindow, "topPanels", geometry.contentWidth, REFERENCE_HEIGHT
    )
    local backgroundFluff = resizeNamedWidgets(
        virtualWindow, "bgFluff", geometry.contentWidth, REFERENCE_HEIGHT
    )

    local rightLines = 0
    for _, widget in ipairs(collectByName(virtualWindow, "Right_lines", 12)) do
        local ok = pcall(function()
            widget:SetMargin(geometry.contentWidth - 55.0, 0.0, 0.0, 0.0)
        end)
        if ok then rightLines = rightLines + 1 end
    end

    local rightFluff = positionRightFluff(virtualWindow, geometry, 12)

    debugLog(string.format(
        "%s shell: roots=%d topPanels=%d bgFluff=%d rightLines=%d rightFluff=%d width=%.2f",
        LOG_PREFIX, resizedRoots, topPanels, backgroundFluff, rightLines, rightFluff,
        geometry.contentWidth
    ))
end

local function applyWorldMapLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local root = safe(function() return controller:GetRootWidget() end)
    local viewportRoot = root ~= nil and safe(function() return root:GetParentWidget() end) or nil
    if root == nil or viewportRoot == nil then
        print(LOG_PREFIX .. " roots unavailable during " .. reason)
        return
    end

    viewportRoot:SetSize(geometry.viewportWidth, VIEWPORT_HEIGHT)
    viewportRoot:SetMargin(0.0, 0.0, 0.0, 0.0)
    root:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
    root:SetMargin(0.0, 0.0, 0.0, 0.0)

    applyMenuShellLayout(geometry)

    local containers = resizeNamedWidgets(
        root, "EntityPreviewContainer", geometry.viewportWidth, VIEWPORT_HEIGHT
    )
    local previews = resizeNamedWidgets(
        root, "EntityPreview", geometry.viewportWidth, VIEWPORT_HEIGHT
    )
    local spawns = resizeNamedWidgets(
        root, "SpawnContainer", geometry.viewportWidth, VIEWPORT_HEIGHT
    )

    -- District outlines are a 2D overlay authored in the original 3840-wide
    -- coordinate space. Keep that overlay centered instead of stretching it
    -- with the new 5160-wide map canvas; otherwise its error grows with zoom.
    local districtRoots = 0
    local districtInset = (geometry.contentWidth - 3840.0) * 0.5
    for _, widget in ipairs(collectByName(root, "DistrictsRoot", 12)) do
        local ok = pcall(function()
            widget:SetMargin(districtInset, 0.0, districtInset, 0.0)
        end)
        if ok then districtRoots = districtRoots + 1 end
    end

    local gpsPathContainers = 0
    for _, widget in ipairs(collectByName(root, "GPSPathContainer", 12)) do
        local ok = pcall(function()
            widget:SetMargin(districtInset, 0.0, districtInset, 0.0)
        end)
        if ok then gpsPathContainers = gpsPathContainers + 1 end
    end

    debugLog(string.format(
        "%s %s: viewport=%.2fx%.2f root=%.2fx%.2f containers=%d previews=%d spawns=%d districts=%d gpsPaths=%d",
        LOG_PREFIX, reason,
        geometry.viewportWidth, VIEWPORT_HEIGHT,
        geometry.contentWidth, REFERENCE_HEIGHT,
        containers, previews, spawns, districtRoots, gpsPathContainers
    ))
end

local function applyInventoryLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local root = safe(function() return controller:GetRootWidget() end)
    if root == nil then
        print(LOG_PREFIX .. " inventory root unavailable during " .. reason)
        return
    end

    -- The controller root is Root1: keep the actual inventory layout at 16:9.
    -- Widen its sibling Root2, which owns the fullscreen background.
    local shellRoot = safe(function() return root:GetParentWidget() end)
    local widenedRoots = 0
    local childCount = shellRoot ~= nil and safe(function()
        return shellRoot:GetNumChildren()
    end) or 0

    for index = 0, childCount - 1 do
        local child = safe(function() return shellRoot:GetWidget(index) end)
        if child ~= nil and widgetName(child) == "Root" then
            local ok = pcall(function()
                child:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            end)
            if ok then widenedRoots = widenedRoots + 1 end
        end
    end

    -- Restore Root1 after the sibling pass, independently of child ordering.
    root:SetSize(3840.0, REFERENCE_HEIGHT)

    local rightLines = 0
    for _, widget in ipairs(collectByName(shellRoot, "Right_lines", 12)) do
        local ok = pcall(function()
            widget:SetMargin(geometry.contentWidth - 55.0, 0.0, 0.0, 0.0)
        end)
        if ok then rightLines = rightLines + 1 end
    end

    local buttonHints = 0
    for _, widget in ipairs(collectByName(root, "button_hints", 12)) do
        local ok = pcall(function()
            widget:SetMargin(50.0, 50.0, -540.0, 50.0)
        end)
        if ok then buttonHints = buttonHints + 1 end
    end

    local rightFluff = positionRightFluff(shellRoot, geometry, 12)

    debugLog(string.format(
        "%s inventory %s: siblingRoots=%d root1=3840x%.2f root2=%.2fx%.2f rightLines=%d rightFluff=%d buttonHints=%d",
        LOG_PREFIX, reason, widenedRoots, REFERENCE_HEIGHT,
        geometry.contentWidth, REFERENCE_HEIGHT, rightLines, rightFluff, buttonHints
    ))
end

local function getMenuVirtualWindow()
    local layer = safe(function()
        return Game.GetInkSystem():GetLayer(CName.new("inkMenuLayer"))
    end)
    return layer ~= nil and safe(function()
        return layer:GetVirtualWindow()
    end) or nil
end

local function applyCyberwareLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local buttonHints = 0
    for _, widget in ipairs(collectByName(searchRoot, "button_hints", 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 0.0, -540.0, 50.0)
        end)
        if ok then buttonHints = buttonHints + 1 end
    end

    local rightFluff = positionRightFluff(searchRoot, geometry, 24)

    debugLog(string.format(
        "%s cyberware %s: buttonHints=%d rightFluff=%d",
        LOG_PREFIX, reason, buttonHints, rightFluff
    ))
end

local function applyCharacterLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local backgroundInset = (geometry.contentWidth - 3840.0) * 0.5
    local backgrounds = 0
    for _, widget in ipairs(collectByName(searchRoot, "master_BG", 12)) do
        local ok = pcall(function()
            -- master_BG is a tiled Fill widget. Negative horizontal margins
            -- extend its drawing area without resizing its UI parent.
            widget:SetMargin(-backgroundInset, 0.0, -backgroundInset, 0.0)
        end)
        if ok then backgrounds = backgrounds + 1 end
    end

    local buttonHints = 0
    for _, widget in ipairs(collectByName(searchRoot, "button_hints", 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 0.0, -540.0, 50.0)
        end)
        if ok then buttonHints = buttonHints + 1 end
    end

    local rightFluff = positionRightFluff(searchRoot, geometry, 24)

    debugLog(string.format(
        "%s character %s: backgrounds=%d buttonHints=%d rightFluff=%d",
        LOG_PREFIX, reason, backgrounds, buttonHints, rightFluff
    ))
end

local function applyJournalLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local buttonHints = 0
    for _, widget in ipairs(collectByName(searchRoot, "button_hints", 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 0.0, -540.0, 50.0)
        end)
        if ok then buttonHints = buttonHints + 1 end
    end

    local rightFluff = positionRightFluff(searchRoot, geometry, 24)

    debugLog(string.format(
        "%s journal %s: buttonHints=%d rightFluff=%d",
        LOG_PREFIX, reason, buttonHints, rightFluff
    ))
end

local function applyBackpackLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local buttonHints = 0
    for _, widget in ipairs(collectByName(searchRoot, "button_hints", 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 0.0, -540.0, 50.0)
        end)
        if ok then buttonHints = buttonHints + 1 end
    end

    local rightFluff = positionRightFluff(searchRoot, geometry, 24)

    debugLog(string.format(
        "%s backpack %s: buttonHints=%d rightFluff=%d",
        LOG_PREFIX, reason, buttonHints, rightFluff
    ))
end

local function applyAuxiliaryMenuLayout(controller, reason, menuLabel, hintWidgetName)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local buttonHints = 0
    for _, widget in ipairs(collectByName(searchRoot, hintWidgetName, 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 0.0, -540.0, 50.0)
        end)
        if ok then buttonHints = buttonHints + 1 end
    end

    local rightFluff = positionRightFluff(searchRoot, geometry, 24)
    debugLog(string.format(
        "%s %s %s: %s=%d rightFluff=%d",
        LOG_PREFIX, menuLabel, reason, hintWidgetName, buttonHints, rightFluff
    ))
end

local function applyHubLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local rightLines = 0
    local widenedRoots = 0
    for _, widget in ipairs(collectByName(searchRoot, "Right_lines", 24)) do
        local ok = pcall(function()
            widget:SetMargin(geometry.contentWidth - 55.0, 0.0, 0.0, 0.0)
        end)
        if ok then rightLines = rightLines + 1 end

        -- Path: root/root2/root2/Right_lines. Two parents above the widget is
        -- the root/root2 layer that must be widened; no sibling order needed.
        local parent = safe(function() return widget:GetParentWidget() end)
        local targetRoot = parent ~= nil and safe(function()
            return parent:GetParentWidget()
        end) or nil
        if targetRoot ~= nil then
            local rootOk = pcall(function()
                targetRoot:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            end)
            if rootOk then widenedRoots = widenedRoots + 1 end
        end
    end

    local fluffWidgets = 0
    for _, widget in ipairs(collectByName(searchRoot, "fluff", 24)) do
        local ok = pcall(function()
            widget:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
        end)
        if ok then fluffWidgets = fluffWidgets + 1 end
    end

    local rightFluffRoots = 0
    for _, widget in ipairs(collectByName(searchRoot, "Right_fluff_elements", 24)) do
        local targetRoot = safe(function() return widget:GetParentWidget() end)
        if targetRoot ~= nil then
            local ok = pcall(function()
                targetRoot:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            end)
            if ok then rightFluffRoots = rightFluffRoots + 1 end
        end
    end

    local rightFluff = positionRightFluff(searchRoot, geometry, 24)

    debugLog(string.format(
        "%s hub %s: root2=%d rightLines=%d fluff=%d rightFluffRoots=%d rightFluff=%d",
        LOG_PREFIX, reason, widenedRoots, rightLines, fluffWidgets, rightFluffRoots,
        rightFluff
    ))
end

local function applyPauseMenuLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local rectangleRoots = 0
    for _, widget in ipairs(collectByName(searchRoot, "inkRectangleWidget14", 24)) do
        local parent = safe(function() return widget:GetParentWidget() end)
        if parent ~= nil then
            local ok = pcall(function()
                parent:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            end)
            if ok then rectangleRoots = rectangleRoots + 1 end
        end
    end

    local bgFluffRoots = 0
    for _, widget in ipairs(collectByName(searchRoot, "bgFluff", 24)) do
        local parent = safe(function() return widget:GetParentWidget() end)
        if parent ~= nil then
            local ok = pcall(function()
                parent:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            end)
            if ok then bgFluffRoots = bgFluffRoots + 1 end
        end
    end

    debugLog(string.format(
        "%s pause %s: rectangleRoots=%d bgFluffRoots=%d",
        LOG_PREFIX, reason, rectangleRoots, bgFluffRoots
    ))
end

local function applyMainMenuLayout(reason)
    mainMenuDiagnosticAttempt = mainMenuDiagnosticAttempt + 1

    local geometry = getTargetGeometry()
    if geometry == nil then
        diagnosticLog("apply " .. reason .. ": unsupported or unavailable display geometry")
        return false, false
    end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then
        diagnosticLog("apply " .. reason .. ": inkMenuLayer virtual window unavailable")
        return false, false
    end

    -- Preem Menu replaces the vanilla bganim hierarchy with this specific
    -- runtime layout:
    --   VirtualWindow / Root (550x400) / Root (3840x2160) /
    --   backgroundContainer / <dynamic scene>
    -- Keep this compatibility path deliberately strict so a different main
    -- menu replacement is not treated as Preem merely because bganim is
    -- absent. Accept the already-expanded width on subsequent retry passes.
    local preemMenuDetected = false
    local preemRootsResized = 0
    local preemRootDescription = "none"
    local directChildCount = safe(function() return searchRoot:GetNumChildren() end) or 0
    for outerIndex = 0, directChildCount - 1 do
        local outerRoot = safe(function() return searchRoot:GetWidget(outerIndex) end)
        local outerSize = outerRoot ~= nil and safe(function() return outerRoot:GetSize() end) or nil
        local outerMatches = outerRoot ~= nil and widgetName(outerRoot) == "Root" and
            outerSize ~= nil and math.abs(outerSize.X - 550.0) <= 5.0 and
            math.abs(outerSize.Y - 400.0) <= 5.0

        if outerMatches then
            local innerChildCount = safe(function() return outerRoot:GetNumChildren() end) or 0
            for innerIndex = 0, innerChildCount - 1 do
                local innerRoot = safe(function() return outerRoot:GetWidget(innerIndex) end)
                local innerSize = innerRoot ~= nil and safe(function() return innerRoot:GetSize() end) or nil
                local innerWidthMatches = innerSize ~= nil and (
                    math.abs(innerSize.X - 3840.0) <= 5.0 or
                    math.abs(innerSize.X - geometry.contentWidth) <= 5.0
                )
                local innerMatches = innerRoot ~= nil and widgetName(innerRoot) == "Root" and
                    innerWidthMatches and innerSize ~= nil and
                    math.abs(innerSize.Y - REFERENCE_HEIGHT) <= 5.0

                if innerMatches then
                    local hasDirectBackgroundContainer = false
                    local contentCount = safe(function() return innerRoot:GetNumChildren() end) or 0
                    for contentIndex = 0, contentCount - 1 do
                        local content = safe(function() return innerRoot:GetWidget(contentIndex) end)
                        if content ~= nil and widgetName(content) == "backgroundContainer" then
                            hasDirectBackgroundContainer = true
                            break
                        end
                    end

                    if hasDirectBackgroundContainer then
                        preemMenuDetected = true
                        preemRootDescription = string.format(
                            "outer[%d]=%.1fx%.1f inner[%d]=%.1fx%.1f",
                            outerIndex, outerSize.X, outerSize.Y,
                            innerIndex, innerSize.X, innerSize.Y
                        )
                        local ok, errorMessage = pcall(function()
                            innerRoot:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
                        end)
                        if ok then
                            preemRootsResized = preemRootsResized + 1
                        else
                            diagnosticLog("Preem Menu root resize failed: " .. tostring(errorMessage))
                        end
                    end
                end
            end
        end
    end

    local backgroundRoots = 0
    local bganimWidgets = collectByName(searchRoot, "bganim", 12)
    for _, widget in ipairs(bganimWidgets) do
        local parent = safe(function() return widget:GetParentWidget() end)
        if parent ~= nil then
            local ok, errorMessage = pcall(function()
                parent:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            end)
            if ok then
                backgroundRoots = backgroundRoots + 1
            else
                diagnosticLog("bganim parent resize failed: " .. tostring(errorMessage))
            end
        end
    end

    local backgroundScenes = 0
    local childDescriptions = {}
    local coverScale = geometry.contentWidth / 3840.0
    local verticalCrop = (REFERENCE_HEIGHT * coverScale - REFERENCE_HEIGHT) * 0.5
    local horizontalInset = (geometry.contentWidth - 3840.0) * 0.5
    local backgroundContainers = collectByName(searchRoot, "backgroundContainer", 12)
    for containerIndex, container in ipairs(backgroundContainers) do
        local childCount = safe(function() return container:GetNumChildren() end) or 0
        table.insert(childDescriptions, string.format(
            "container%d children=%d", containerIndex, childCount
        ))
        for index = 0, childCount - 1 do
            local child = safe(function() return container:GetWidget(index) end)
            if child ~= nil then
                local childName = widgetName(child)
                table.insert(childDescriptions, string.format(
                    "container%d[%d]=%s", containerIndex, index, childName
                ))
                local ok, errorMessage = pcall(function()
                    -- The game dynamically selects the scene placed inside
                    -- backgroundContainer. Scale that scene by position in
                    -- the hierarchy instead of depending on a resource name
                    -- such as v_apt_shot1.
                    child:SetScale(Vector2.new({
                        X = coverScale,
                        Y = coverScale
                    }))
                    child:SetTranslation(Vector2.new({
                        X = 0.0,
                        Y = -verticalCrop
                    }))
                    child:SetMargin(horizontalInset, 0.0, 0.0, 0.0)
                end)
                if ok then
                    backgroundScenes = backgroundScenes + 1
                else
                    diagnosticLog(string.format(
                        "scene transform failed for %s: %s",
                        childName, tostring(errorMessage)
                    ))
                end
            end
        end
    end

    debugLog(string.format(
        "%s mainMenu %s: backgroundRoots=%d backgroundScenes=%d",
        LOG_PREFIX, reason, backgroundRoots, backgroundScenes
    ))

    -- Vanilla/Cleaner use bganim. Preem Menu intentionally has no bganim and
    -- is authorized only by the exact hierarchy signature checked above.
    local vanillaBackgroundReady = backgroundRoots > 0
    local supportedLayoutReady = vanillaBackgroundReady or preemMenuDetected
    local sceneReady = backgroundScenes > 0
    local signature = string.format(
        "bganim=%d preem=%s preemRoots=%d preemPath={%s} containers=%d scenes=%d children={%s}",
        #bganimWidgets, tostring(preemMenuDetected), preemRootsResized,
        preemRootDescription, #backgroundContainers, backgroundScenes,
        table.concat(childDescriptions, ", ")
    )
    local signatureChanged = signature ~= mainMenuDiagnosticSignature
    if signatureChanged or mainMenuDiagnosticAttempt % 10 == 0 then
        diagnosticLog(string.format(
            "apply #%d (%s): %s scale=%.4f inset=%.2f crop=%.2f",
            mainMenuDiagnosticAttempt, reason, signature,
            coverScale, horizontalInset, verticalCrop
        ))
        mainMenuDiagnosticSignature = signature
    end

    if signatureChanged and sceneReady and not supportedLayoutReady then
        diagnosticLog(
            "BLOCKED: scene is ready but pillar removal was not scheduled; " ..
            "neither vanilla bganim nor the strict Preem Menu hierarchy was detected"
        )
    end

    -- The container may exist several seconds before its selected scene is
    -- attached. Use the actual child as the readiness signal for both the
    -- transform and pillar removal.
    if supportedLayoutReady and sceneReady and
       not mainMenuPillarPending and not mainMenuPillarsDisabled then
        mainMenuPillarPending = true
        mainMenuPillarTimer = 0.10
        diagnosticLog(string.format(
            "main-menu scene ready (%s); pillar removal scheduled in 0.10s",
            preemMenuDetected and "Preem Menu" or "vanilla-compatible layout"
        ))
    end
    return supportedLayoutReady, sceneReady
end

local function applySystemNotificationLayout()
    local geometry = getTargetGeometry()
    if geometry == nil then return end

    local layer = safe(function()
        return Game.GetInkSystem():GetLayer(CName.new("inkSystemNotificationsLayer"))
    end)
    local virtualWindow = layer ~= nil and safe(function()
        return layer:GetVirtualWindow()
    end) or nil
    if virtualWindow == nil then return end

    -- ExitGame has no script Game Controller. Its Context identifies the
    -- resource as system_notifications.inkwidget / ExitGame / Root/Canvas.
    -- Follow that fixed two-level path; do not recursively scan this layer
    -- every frame while no notification is visible.
    local root = safe(function() return virtualWindow:GetWidget(0) end)
    local canvas = root ~= nil and safe(function() return root:GetWidget(0) end) or nil
    local size = canvas ~= nil and safe(function() return canvas:GetSize() end) or nil
    if canvas ~= nil and widgetName(canvas) == "Canvas" and size ~= nil and
        size.X >= 3800.0 and size.X <= 3860.0 and
        size.Y >= 2100.0 and size.Y <= 2200.0 then
        pcall(function()
            canvas:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
        end)
    end
end

local function applyTimeSkipLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    -- Context: gameuiTimeskipGameController, Root/NotificationsContainer/
    -- UNINITIALIZED_WIDGET/Root. The controller root is the popup's 16:9
    -- canvas, so it can be widened directly without touching the shared
    -- inkGameNotificationsLayer.
    local root = safe(function() return controller:GetRootWidget() end)
    if root == nil then
        debugLog(LOG_PREFIX .. " time skip root unavailable during " .. reason)
        return
    end

    local ok, errorMessage = pcall(function()
        root:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
    end)
    if not ok then
        print(LOG_PREFIX .. " time skip layout failed: " .. tostring(errorMessage))
    end
end

local function applyStealthRunnerPopupLayout()
    local geometry = getTargetGeometry()
    if geometry == nil then return false end

    local layer = safe(function()
        return Game.GetInkSystem():GetLayer(CName.new("inkGameNotificationsLayer"))
    end)
    local virtualWindow = layer ~= nil and safe(function() return layer:GetVirtualWindow() end) or nil
    if virtualWindow == nil then return false end

    -- StealthRunner's popup is spawned dynamically below the notifications
    -- layer. Restrict the search to this short-lived retry window; never scan
    -- the notification tree continuously while the game is running.
    local changed = false
    local vignetteWidgets = collectByName(virtualWindow, "vignette", 12)
    for index, widget in ipairs(vignetteWidgets) do
        -- The popup contains a rectangle and an image with the same name.
        -- Only the first (the rectangle shown by Ink Inspector) is the
        -- 16:9 canvas that must be widened; leave the image texture intact.
        if index > 1 then break end
        if not stealthRunnerProbePrinted then
            local names = {}
            local ancestor = widget
            for level = 0, 8 do
                if ancestor == nil then break end
                table.insert(names, widgetName(ancestor))
                ancestor = safe(function() return ancestor:GetParentWidget() end)
            end
            print(LOG_PREFIX .. " StealthRunner vignette path=" .. table.concat(names, "/"))
            stealthRunnerProbePrinted = true
        end
        -- The notifications layer only contains live popup widgets here;
        -- resize the discovered vignette without relying on a translated
        -- Name Path segment that may not be exposed by GetName().
        local ok = pcall(function()
            widget:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            widget:FlagForVisualInvalidation()
        end)
        if ok then changed = true end
    end
    return changed
end

local function applySaveGameLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local fluffs = 0
    for _, widget in ipairs(collectByName(searchRoot, "fluffs", 24)) do
        local ok = pcall(function()
            widget:SetMargin(-604.0, 16.0, 0.0, 0.0)
        end)
        if ok then fluffs = fluffs + 1 end
    end

    local revealedFluffs = 0
    for _, name in ipairs({ "fluff2", "fluff3" }) do
        for _, widget in ipairs(collectByName(searchRoot, name, 24)) do
            local ok = pcall(function()
                widget:SetVisible(true)
            end)
            if ok then revealedFluffs = revealedFluffs + 1 end
        end
    end


    local recenteredFluffs = 0
    for _, name in ipairs({ "fluff4", "fluff6", "fluff7" }) do
        for _, widget in ipairs(collectByName(searchRoot, name, 24)) do
            local margin = safe(function() return widget:GetMargin() end)
            if margin ~= nil then
                local ok = pcall(function()
                    widget:SetMargin(
                        margin.left + 600.0,
                        margin.top,
                        margin.right,
                        margin.bottom
                    )
                end)
                if ok then recenteredFluffs = recenteredFluffs + 1 end
            end
        end
    end

    local buttonHints = 0
    for _, widget in ipairs(collectByName(searchRoot, "button_hints", 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 0.0, -540.0, 120.0)
        end)
        if ok then buttonHints = buttonHints + 1 end
    end

    local lines = 0
    for _, widget in ipairs(collectByName(searchRoot, "line", 24)) do
        local ok = pcall(function()
            widget:SetMargin(-520.0, 155.0, -1020.0, 0.0)
        end)
        if ok then lines = lines + 1 end
    end

    debugLog(string.format(
        "%s saveGame %s: fluffs=%d revealedFluffs=%d recenteredFluffs=%d buttonHints=%d lines=%d",
        LOG_PREFIX, reason, fluffs, revealedFluffs, recenteredFluffs, buttonHints, lines
    ))
end

local function applySettingsLayout(controller, reason)
    local geometry = getTargetGeometry()
    if geometry == nil or controller == nil then return end

    local searchRoot = getMenuVirtualWindow()
    if searchRoot == nil then return end

    local backgroundRoots = 0
    local backgrounds = 0
    local backgroundLayers = 0
    for _, widget in ipairs(collectByName(searchRoot, "BG", 24)) do
        local parent = safe(function() return widget:GetParentWidget() end)
        if parent ~= nil then
            local parentOk = pcall(function()
                parent:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
            end)
            if parentOk then backgroundRoots = backgroundRoots + 1 end
        end

        backgrounds = backgrounds + 1

        local childCount = safe(function() return widget:GetNumChildren() end) or 0
        for index = 0, childCount - 1 do
            local child = safe(function() return widget:GetWidget(index) end)
            local name = child ~= nil and widgetName(child) or ""
            if name == "background" then
                local ok = pcall(function()
                    -- Invisible vanilla sizing spacer: it intentionally stays
                    -- hidden but drives BG and all Fill children to 21:9.
                    child:SetWidth(geometry.contentWidth)
                    child:FlagForVisualInvalidation()
                end)
                if ok then backgroundLayers = backgroundLayers + 1 end
            elseif name == "bg1" or name == "bg2" or name == "bg3" then
                local scale = safe(function() return child:GetScale() end)
                if scale ~= nil then
                    pcall(function() child:SetScale(1.0, scale.Y) end)
                end
            end
        end

        if not settingsProbePrinted and reason == "probe" then
            local function vectorText(value)
                return value ~= nil and string.format("%.1f,%.1f", value.X, value.Y) or "nil"
            end

            local function marginText(value)
                return value ~= nil and string.format(
                    "%.1f,%.1f,%.1f,%.1f",
                    value.left, value.top, value.right, value.bottom
                ) or "nil"
            end

            local function rectText(value)
                return value ~= nil and string.format(
                    "L%.1f T%.1f R%.1f B%.1f W%.1f",
                    value.Left, value.Top, value.Right, value.Bottom,
                    value.Right - value.Left
                ) or "nil"
            end

            local function dumpWidget(label, target)
                if target == nil then return end
                print(string.format(
                    "[UW SETTINGS PROBE] %s name=%s screen=%s size=%s desired=%s margin=%s padding=%s anchor=%s h=%s v=%s rule=%s fit=%s scale=%s translation=%s",
                    label,
                    widgetName(target),
                    rectText(safe(function() return GetScreenPosition(target) end)),
                    vectorText(safe(function() return target:GetSize() end)),
                    vectorText(safe(function() return target:GetDesiredSize() end)),
                    marginText(safe(function() return target:GetMargin() end)),
                    marginText(safe(function() return target:GetPadding() end)),
                    tostring(safe(function() return target:GetAnchor() end)),
                    tostring(safe(function() return target:GetHAlign() end)),
                    tostring(safe(function() return target:GetVAlign() end)),
                    tostring(safe(function() return target:GetSizeRule() end)),
                    tostring(safe(function() return target:GetFitToContent() end)),
                    vectorText(safe(function() return target:GetScale() end)),
                    vectorText(safe(function() return target:GetTranslation() end))
                ))
            end

            local ancestor = widget
            for level = 0, 5 do
                if ancestor == nil then break end
                dumpWidget("ancestor" .. tostring(level), ancestor)
                ancestor = safe(function() return ancestor:GetParentWidget() end)
            end

            local childCount = safe(function() return widget:GetNumChildren() end) or 0
            for index = 0, childCount - 1 do
                local child = safe(function() return widget:GetWidget(index) end)
                local name = child ~= nil and widgetName(child) or ""
                if name == "bg1" or name == "bg2" or name == "bg3" then
                    dumpWidget(name, child)
                end
            end
            settingsProbePrinted = true
        end
    end

    local rightSides = 0
    for _, widget in ipairs(collectByName(searchRoot, "rightSide", 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 346.0, 1545.0, 0.0)
        end)
        if ok then rightSides = rightSides + 1 end
    end

    local bottomFluffs = 0
    for _, widget in ipairs(collectByName(searchRoot, "inkHorizontalPanelWidget47", 24)) do
        local ok = pcall(function()
            widget:SetMargin(0.0, 0.0, -360.0, 70.0)
        end)
        if ok then bottomFluffs = bottomFluffs + 1 end
    end

    local edgeFluffs = 0
    for _, widget in ipairs(collectByName(searchRoot, "edge_fluff", 24)) do
        local ok = pcall(function()
            -- Keep the vanilla animation coordinate space. Only its right
            -- decoration needs to move to the new physical edge.
            widget:SetSize(3840.0, REFERENCE_HEIGHT)

            local rightOffset = geometry.contentWidth - 3840.0
            for _, rightIcon in ipairs(collectByName(widget, "letter_icon_right", 8)) do
                rightIcon:SetMargin(0.0, 300.0, 20.0 - rightOffset, 0.0)
            end
        end)
        if ok then edgeFluffs = edgeFluffs + 1 end
    end

    debugLog(string.format(
        "%s settings %s: backgroundRoots=%d backgrounds=%d backgroundLayers=%d rightSides=%d bottomFluffs=%d edgeFluffs=%d",
        LOG_PREFIX, reason, backgroundRoots, backgrounds, backgroundLayers,
        rightSides, bottomFluffs, edgeFluffs
    ))
end

local function configureMapCamera(gameObject)
    local geometry = getTargetGeometry()
    if geometry == nil or gameObject == nil then return end

    local camera = gameObject:FindComponentByName("virtual_camera_comp")
    if camera == nil then
        debugLog(LOG_PREFIX .. " virtual_camera_comp unavailable")
        return
    end

    camera.resolutionWidth = geometry.cameraWidth
    camera.resolutionHeight = geometry.cameraHeight
    camera.aspectRatio = geometry.aspect

    debugLog(string.format(
        "%s camera=%dx%d aspect=%.6f",
        LOG_PREFIX, geometry.cameraWidth, geometry.cameraHeight, geometry.aspect
    ))
end

registerForEvent("onInit", function()
    initializeDiagnosticLog()
    local displayWidth, displayHeight = GetDisplayResolution()
    diagnosticLog(string.format(
        "%s v%s initialized at %dx%d",
        MOD_NAME, VERSION, displayWidth or -1, displayHeight or -1
    ))
    debugLog(string.format("%s %s v%s initialized", LOG_PREFIX, MOD_NAME, VERSION))

    pcall(function()
        Observe("gameuiPreGameMenuGameController", "OnInitialize", function()
            diagnosticLog("event: gameuiPreGameMenuGameController.OnInitialize")
        end)
    end)

    pcall(function()
        Observe("SingleplayerMenuGameController", "OnInitialize", function()
            diagnosticLog("event: SingleplayerMenuGameController.OnInitialize")
        end)
    end)

    Observe("WorldMapMenuGameController", "OnInitialize", function(controller)
        applyWorldMapLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "map", elapsed = 0.0 })
    end)

    Observe("WorldMapMenuGameController", "OnEntityAttached", function(controller)
        applyWorldMapLayout(controller, "OnEntityAttached")
    end)

    Observe("gameuiWorldMapGameObject", "OnGameAttached", function(gameObject)
        local ok, errorMessage = pcall(function()
            configureMapCamera(gameObject)
        end)
        if not ok then
            print(LOG_PREFIX .. " camera configuration failed: " .. tostring(errorMessage))
        end
    end)

    Observe("gameuiInventoryGameController", "OnInitialize", function(controller)
        applyInventoryLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "inventory", elapsed = 0.0 })
    end)

    Observe("CyberwareMainGameController", "OnInitialize", function(controller)
        applyCyberwareLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "cyberware", elapsed = 0.0 })
    end)

    ObserveBefore("MenuScenario_HubMenu", "OnOpenMenu", function(_, menuName)
        activeHubMenu = cnameValue(menuName)
    end)

    Observe("MenuScenario_HubMenu", "OnOpenMenu", function(scenario, menuName)
        if cnameEquals(menuName, "cyberware_equip") then
            applyCyberwareLayout(scenario, "OnOpenMenu")
            table.insert(pendingLayouts, { controller = scenario, kind = "cyberware", elapsed = 0.0 })
        elseif cnameEquals(menuName, "backpack") then
            applyBackpackLayout(scenario, "OnOpenMenu")
            table.insert(pendingLayouts, { controller = scenario, kind = "backpack", elapsed = 0.0, delay = 0.0 })
        end
    end)

    ObserveBefore("MenuScenario_RadialHubMenu", "OnOpenMenu", function(_, menuName)
        activeHubMenu = cnameValue(menuName)
    end)

    Observe("MenuScenario_RadialHubMenu", "OnOpenMenu", function(scenario, menuName)
        if cnameEquals(menuName, "cyberware_equip") then
            applyCyberwareLayout(scenario, "OnOpenMenu")
            table.insert(pendingLayouts, { controller = scenario, kind = "cyberware", elapsed = 0.0 })
        elseif cnameEquals(menuName, "backpack") then
            applyBackpackLayout(scenario, "OnOpenMenu")
            table.insert(pendingLayouts, { controller = scenario, kind = "backpack", elapsed = 0.0, delay = 0.0 })
        end
    end)

    Observe("ButtonHints", "OnInitialize", function(controller)
        local expectedName = menuHintWidgetNames[activeHubMenu]
        if expectedName == nil then return end

        local widget = safe(function() return controller:GetRootWidget() end)
        for _ = 1, 4 do
            if widget == nil then return end
            if widgetName(widget) == expectedName then
                widget:SetMargin(0.0, 0.0, -540.0, 50.0)
                debugLog(LOG_PREFIX .. " " .. activeHubMenu .. " " .. expectedName .. " initialized")
                return
            end
            widget = safe(function() return widget:GetParentWidget() end)
        end
    end)

    Observe("BackpackMainGameController", "OnInitialize", function(controller)
        applyBackpackLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "backpack", elapsed = 0.0, delay = 0.0 })
    end)

    Observe("CraftingMainGameController", "OnInitialize", function(controller)
        applyAuxiliaryMenuLayout(controller, "OnInitialize", "crafting", "buttonHintContainer")
        table.insert(pendingLayouts, { controller = controller, kind = "auxiliary", label = "crafting", hintName = "buttonHintContainer", elapsed = 0.0 })
    end)

    Observe("StatsMainGameController", "OnInitialize", function(controller)
        applyAuxiliaryMenuLayout(controller, "OnInitialize", "stats", "button_hints")
        table.insert(pendingLayouts, { controller = controller, kind = "auxiliary", label = "stats", hintName = "button_hints", elapsed = 0.0 })
    end)

    Observe("GalleryMenuGameController", "OnInitialize", function(controller)
        applyAuxiliaryMenuLayout(controller, "OnInitialize", "gallery", "inputHints")
        table.insert(pendingLayouts, { controller = controller, kind = "auxiliary", label = "gallery", hintName = "inputHints", elapsed = 0.0 })
    end)

    Observe("ShardsMenuGameController", "OnInitialize", function(controller)
        applyAuxiliaryMenuLayout(controller, "OnInitialize", "shards", "button_hints")
        table.insert(pendingLayouts, { controller = controller, kind = "auxiliary", label = "shards", hintName = "button_hints", elapsed = 0.0 })
    end)

    Observe("gameuiTimeskipGameController", "OnInitialize", function(controller)
        applyTimeSkipLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, {
            controller = controller,
            kind = "timeskip",
            elapsed = 0.0,
            delay = 0.10
        })
    end)

    Observe("PerksMainGameController", "OnInitialize", function(controller)
        applyCharacterLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "character", elapsed = 0.0 })
    end)

    Observe("NewPerksCategoriesGameController", "OnInitialize", function(controller)
        applyCharacterLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "character", elapsed = 0.0 })
    end)

    Observe("questLogGameController", "OnInitialize", function(controller)
        applyJournalLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "journal", elapsed = 0.0 })
    end)

    Observe("MenuHubLogicController", "OnInitialize", function(controller)
        applyHubLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "hub", elapsed = 0.0, delay = 0.0 })
    end)

    Observe("RadialMenuHubLogicController", "OnInitialize", function(controller)
        applyHubLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "hub", elapsed = 0.0, delay = 0.0 })
    end)

    ObserveBefore("PauseMenuBackgroundGameController", "OnInitialize", function()
        activeHubMenu = ""
    end)

    Observe("PauseMenuBackgroundGameController", "OnInitialize", function(controller)
        applyPauseMenuLayout(controller, "Background.OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "pause", elapsed = 0.0, delay = 0.0 })
    end)

    ObserveBefore("PauseMenuGameController", "OnInitialize", function()
        activeHubMenu = ""
    end)

    Observe("PauseMenuGameController", "OnInitialize", function(controller)
        applyPauseMenuLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "pause", elapsed = 0.0, delay = 0.0 })
    end)

    Observe("SingleplayerMenuGameController", "OnSavesForLoadReady", function(controller)
        diagnosticLog("event: SingleplayerMenuGameController.OnSavesForLoadReady")
        mainMenuPillarPending = false
        mainMenuPillarsDisabled = false
        mainMenuPillarTimer = 0.0
        mainMenuDiagnosticAttempt = 0
        mainMenuDiagnosticSignature = ""
        mainMenuSceneReadyPasses = 0
        applyMainMenuLayout("OnSavesForLoadReady")
        mainMenuRetryBudget = 1200
        mainMenuRetryTimer = 0.0
    end)

    -- StealthRunner's status popup is created after the notifications layer
    -- is initialized. These callbacks arm a short retry window so the newly
    -- spawned vignette can be found without a permanent recursive scan.
    pcall(function()
        Observe("gameuiPopupsManager", "OnUpdateVisibility", function()
            stealthRunnerRetryBudget = 20
            stealthRunnerRetryTimer = 0.0
        end)
        Observe("gameuiPopupsManager", "OnUpdateData", function()
            stealthRunnerRetryBudget = 20
            stealthRunnerRetryTimer = 0.0
        end)
        -- Generic notification controllers are also used for popup resources
        -- that do not update PopupsManager's tutorial blackboard.
        Observe("gameuiGenericNotificationGameController", "OnInitialize", function()
            stealthRunnerRetryBudget = 20
            stealthRunnerRetryTimer = 0.0
        end)
        Observe("GenericNotificationController", "OnInitialize", function()
            stealthRunnerRetryBudget = 20
            stealthRunnerRetryTimer = 0.0
        end)
    end)

    Observe("SaveGameMenuGameController", "OnInitialize", function(controller)
        applySaveGameLayout(controller, "OnInitialize")
    end)

    Observe("LoadGameMenuGameController", "OnInitialize", function(controller)
        applySaveGameLayout(controller, "LoadGame.OnInitialize")
    end)

    Observe("SettingsMainGameController", "OnInitialize", function(controller)
        applySettingsLayout(controller, "OnInitialize")
        table.insert(pendingLayouts, { controller = controller, kind = "settingsFinalize", elapsed = 0.0, delay = 0.75 })
    end)

    -- Optional compatibility: Mod Settings is not required by this mod.
    pcall(function()
        Observe("ModStngsMainGameController", "OnInitialize", function(controller)
            applySettingsLayout(controller, "ModSettings.OnInitialize")
            table.insert(pendingLayouts, { controller = controller, kind = "settingsFinalize", elapsed = 0.0, delay = 0.75 })
        end)
    end)
end)

registerForEvent("onUpdate", function(deltaTime)
    applySystemNotificationLayout()

    if mainMenuPillarPending then
        mainMenuPillarTimer = mainMenuPillarTimer - deltaTime
        if mainMenuPillarTimer <= 0.0 then
            diagnosticLog("pillar timer elapsed; requesting disabled pillars")
            local ok, errorMessage = pcall(function()
                local coordinator = GetMod("BlackPillarsCoordinator")
                if coordinator ~= nil and coordinator.SetPillarsDisabled ~= nil then
                    diagnosticLog("calling BlackPillarsCoordinator.SetPillarsDisabled(true)")
                    coordinator.SetPillarsDisabled(true)
                elseif UWMenuSetPillarsDisabled ~= nil then
                    diagnosticLog("calling legacy UWMenuSetPillarsDisabled(true)")
                    UWMenuSetPillarsDisabled(true)
                else
                    diagnosticLog("coordinator unavailable; calling UWMapSetBlackBarsSuppressed(true)")
                    UWMapSetBlackBarsSuppressed(true)
                end
            end)
            mainMenuPillarPending = false
            mainMenuPillarsDisabled = ok
            diagnosticLog(ok and "pillar disable request completed" or
                ("pillar disable request failed: " .. tostring(errorMessage)))
        end
    end

    -- StealthRunner creates this notification without reliably notifying the
    -- PopupsManager blackboard. A throttled scan of this small layer is cheap
    -- and avoids a recursive walk every frame.
    stealthRunnerScanTimer = stealthRunnerScanTimer - deltaTime
    if stealthRunnerScanTimer <= 0.0 then
        applyStealthRunnerPopupLayout()
        stealthRunnerScanTimer = 0.25
    end
    if stealthRunnerRetryBudget > 0 then
        stealthRunnerRetryTimer = stealthRunnerRetryTimer - deltaTime
        if stealthRunnerRetryTimer <= 0.0 then
            local found = applyStealthRunnerPopupLayout()
            stealthRunnerRetryBudget = stealthRunnerRetryBudget - 1
            stealthRunnerRetryTimer = 0.10
            if found then
                stealthRunnerRetryBudget = 0
            end
        end
    end
    if mainMenuRetryBudget > 0 then
        mainMenuRetryTimer = mainMenuRetryTimer - deltaTime
        if mainMenuRetryTimer <= 0.0 then
            local backgroundReady, sceneReady = applyMainMenuLayout("retry")
            if sceneReady then
                mainMenuSceneReadyPasses = mainMenuSceneReadyPasses + 1
                if mainMenuSceneReadyPasses >= 15 then
                    diagnosticLog("scene transform stable for 15 passes; retries stopped")
                    mainMenuRetryBudget = 0
                else
                    mainMenuRetryBudget = mainMenuRetryBudget - 1
                    mainMenuRetryTimer = 0.10
                end
            else
                mainMenuSceneReadyPasses = 0
                -- The selected scene is inserted asynchronously into
                -- backgroundContainer. Once bganim exists, allow it a short
                -- grace period to appear, then stop scanning.
                if backgroundReady and mainMenuRetryBudget > 300 then
                    diagnosticLog("bganim ready; limiting scene search to 30 seconds")
                    mainMenuRetryBudget = 300
                end
                mainMenuRetryBudget = mainMenuRetryBudget - 1
                mainMenuRetryTimer = backgroundReady and 0.10 or 0.05
                if mainMenuRetryBudget == 0 then
                    diagnosticLog("scene search budget exhausted without a stable child")
                end
            end
        end
    end

    for index = #pendingLayouts, 1, -1 do
        local item = pendingLayouts[index]
        item.elapsed = item.elapsed + deltaTime
        if item.elapsed >= (item.delay or 0.75) then
            local ok, errorMessage = pcall(function()
                if item.kind == "inventory" then
                    applyInventoryLayout(item.controller, "delayed")
                elseif item.kind == "cyberware" then
                    applyCyberwareLayout(item.controller, "delayed")
                elseif item.kind == "character" then
                    applyCharacterLayout(item.controller, "delayed")
                elseif item.kind == "journal" then
                    applyJournalLayout(item.controller, "delayed")
                elseif item.kind == "backpack" then
                    applyBackpackLayout(item.controller, "delayed")
                elseif item.kind == "auxiliary" then
                    applyAuxiliaryMenuLayout(item.controller, "delayed", item.label, item.hintName)
                elseif item.kind == "hub" then
                    applyHubLayout(item.controller, "delayed")
                elseif item.kind == "pause" then
                    applyPauseMenuLayout(item.controller, "delayed")
                elseif item.kind == "settingsFinalize" then
                    applySettingsLayout(item.controller, "finalize")
                elseif item.kind == "timeskip" then
                    applyTimeSkipLayout(item.controller, "delayed")
                else
                    applyWorldMapLayout(item.controller, "delayed")
                end
            end)
            if not ok then
                print(LOG_PREFIX .. " delayed layout failed: " .. tostring(errorMessage))
            end
            table.remove(pendingLayouts, index)
        end
    end
end)

registerForEvent("onShutdown", function()
    pendingLayouts = {}
    settingsProbePrinted = false
    mainMenuRetryBudget = 0
    mainMenuRetryTimer = 0.0
    mainMenuPillarTimer = 0.0
    mainMenuPillarPending = false
    mainMenuPillarsDisabled = false
    mainMenuDiagnosticAttempt = 0
    mainMenuDiagnosticSignature = ""
    mainMenuSceneReadyPasses = 0
    stealthRunnerRetryBudget = 0
    stealthRunnerRetryTimer = 0.0
    stealthRunnerProbePrinted = false
    stealthRunnerScanTimer = 0.0
end)
