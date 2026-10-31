-- Ultrawide UI Overhaul v2.5.7
--
-- Active layout mutations:
--   MAIN MENU:
--     Root[0]/Root[0]                                  -> width = target UI Spread width
--     Root[0]/Root[0]/backgroundContainer[1]/child[0] -> physical-screen cover transform
--        (child name intentionally ignored: it depends on game progression)
--
--   HUB (width/edge placement follows UI Spread 0-100%):
--     Root[0]/Root[0]                                  -> width = target UI content width
--     Root[0]/Root[0]/mainMenu[1]/fluff[3]            -> width = target UI content width
--     Root[0]/Root[0]/Root[7]                          -> width = target UI content width
--     Root[0]/Root[0]/Root[7]/Right_fluff_elements[0] -> X = -3 + halfExtra
--     Root[0]/Root[0]/Root[7]/Right_lines[4]          -> X = vanilla + extraWidth
--
--   SAVE / LOAD:
--     LOAD pre-game Root[0]/Root[0], LOAD in-game Root[0]/Root[1]
--       fluff[5]/fluffs[0]/fluff1[0]                 -> shift left by halfExtra
--       fluff[5]/fluffs[0]/fluff5[2]                 -> shift left by halfExtra
--       fluff[5]/line[1]                              -> adaptive UW extension
--       button_hints[4]                               -> standard halfExtra right shift
--     SAVE in-game Root[0]/Root[1]
--       fluff[1]/fluffs[0]/fluff1[1]                 -> shift left by halfExtra
--       fluff[1]/fluffs[0]/fluff5[4]                 -> shift left by halfExtra
--       fluff[1]/line[1]                              -> same adaptive UW extension
--       button_hints[3]                               -> standard halfExtra right shift
--
--   BREACH PROTOCOL:
--     Root[0]/Root[0]/bg_loop[6]                      -> extend to UW edges
--     Root[0]/Root[0]/bg_loop[6]/bg_loop[0]           -> extend to UW edges
--     Root[0]/Root[0]/fullscreen_Fluff[9]/tempBG[17] -> extend to UW edges
--     Root[0]/Root[0]/fullscreen_Fluff[9]/header_ux_highlight[7]
--                                                      -> contentWidth x 170, left-aligned
--     Root[0]/Root[0]/fullscreen_Fluff[9]/fluff_columns[6]
--                                                      -> force Ink visual refresh only
--     AllParts[4] and the active minigame remain authored/centered at 3840x2160.
--     Tutorial overlay (inkGameNotificationsLayer):
--       Root[0]/TutorialOverlayContainer[2]/Root[1]
--                                                      -> +halfExtra left margin
--       Root[0]/TutorialOverlayContainer[2]/Root[1]/bg[12]
--                                                      -> contentWidth x 2160, -halfExtra left
--
--   LOADING SCREEN (fullscreen ultrawide refit, independent of UI Spread):
--     inkLoadingLayer/inkVirtualWindow/Root[0]          -> target UI width x 2160
--     Root[0]/Root[0]                                   -> target UI width x 2160
--     fluff_elements / fact_lines / borders / top_fluff / bg
--                                                       -> target UI width x 2160
--     borders                                           -> target UI width
--     top/bottom cut-corner flexR                       -> proportional width correction
--     bg/top_black + bg/bottom_black + bg/binks_here   -> target UI width, preserve height
--     BGImageContainer scale                            -> preserved (animation-safe)
--     MainImage                                         -> base geometry expanded to UW width
--     ExtendingIMage                                    -> untouched
--
--   DEFAULT / CHECKPOINT / QUICKLOAD LOADING MASK:
--     Root[0]/Root[0]/inkRectangleWidget3[1]            -> extend black Fill
--       beyond the authored 16:9 Root by physical halfExtra on both sides.
--     Keep both Roots and loading_progress at their vanilla geometry; only the
--     black concealment mask grows so the streaming world cannot show at UW edges.
--
--   ARCADE MINIGAMES:
--     Keep the authored arcade layout untouched at its original aspect ratio.
--     MenuScenario_ArcadeMinigame is the authoritative shared lifecycle gate:
--     entering that scenario temporarily restores the native black pillars so
--     oversized scrolling/parallax layers remain masked outside the authored
--     viewport; leaving it restores normal ultrawide pillar suppression.
--
--   CHARACTER / PERKS (real screen width > 4096 only):
--     Keep Character ultrawide; when the actual perk tree is visible,
--     constrain the shared Hub Root[1] to 4096 and hide three master_BG.
--     Restore normal Hub layout when leaving Perks; position hints separately
--     for Character and Perks. No change at physical widths <= 4096.
--
--   Strict menu hints:
--     cyberware_equip  -> button_hints[1] -> shift right by halfExtra
--     inventory_screen -> button_hints[2] -> shift right by halfExtra
--     temp_stats       -> button_hints[5] -> shift right by halfExtra
--     quest_log        -> button_hints[2] -> shift right by halfExtra
--     codex            -> button_hints[2] -> shift right by halfExtra
--     new_perks        -> button_hints[3] -> shift right by halfExtra
--     backpack / crafting_main -> no hint mutation; widened Root carries them
--
-- UI Spread affects the responsive UI layouts (Main Menu UI, Hub, Backpack, Crafting,
-- Save/Load, Storage/Stash, Vendors, Pause content, Revised Backpack, Shards, Gallery,
-- Settings/Mods, World Map UI/viewport and routed hints).
-- Pure fullscreen/background geometry (Main Menu cover, Breach backgrounds,
-- Character master_BG, notification canvases and StealthRunner vignette) normally
-- remains at the physical screen width (except hidden Character backgrounds
-- while the >4096-width Perks compatibility mode is active).
-- All compatibility/layout paths use exact GetWidget(index) chains only; no recursive scans.
-- No generic delayed layout passes.
--
-- Debug logging:
--   Disabled by default for release. It can be enabled at runtime from
--   Mods -> Ultrawide UI Overhaul -> Debug -> Activate Debug Logs.
--   The persisted Native Settings toggle takes precedence when present.
--   When disabled, diagnostic-only widget queries / formatting / file I/O
--   are not executed at all.

local ACTIVATE_DEBUG_LOGS = false

local LOG_FILE = "UltrawideUIOverhaul_debug.log"
local LOG_PREFIX = "[UWUI v2.5.7]"

local REFERENCE_HEIGHT = 2160.0
local WORLD_MAP_VIEWPORT_HEIGHT = 1080.0
local WORLD_MAP_CAMERA_HEIGHT = 720
local VANILLA_CONTENT_WIDTH = 3840.0
local LEGACY_21X9_CONTENT_WIDTH = 5160.0
local VANILLA_ASPECT = 16.0 / 9.0
local GALLERY_VANILLA_SCREENSHOTS_PER_PAGE = 10
local MIN_SUPPORTED_ASPECT = 1.99
local MAX_SUPPORTED_ASPECT = 3.65

-- User-controlled horizontal distribution for menu UI.
-- 100% uses the full ultrawide layout. 0% keeps supported UI inside a
-- centered vanilla 16:9 canvas. UI-facing layouts consume the interpolated
-- geometry; fullscreen/background treatments keep using physical screen geometry.
-- UI Spread and the debug-log toggle are persisted in SETTINGS_FILE.
local UI_SPREAD_PERCENT = 100
local SETTINGS_FILE = "UltrawideUIOverhaul_settings.ini"
-- Main Menu background scenes are inserted/replaced asynchronously below
-- backgroundContainer. While the game is in pre-game, watch only the exact
-- direct path and mutate a scene instance once. This replaces the old
-- recursive 1200-attempt discovery loop and 15-pass stabilization window.
local mainMenuWatchActive = false
local mainMenuSceneRefitted = false

-- Startup pillar lock:
--   true  = pillars must remain visible; all generic disable requests are blocked
--   false = normal menu behavior; generic disable requests are allowed
--
-- The lock is enabled explicitly on a real pre-game startup and is released
-- when the Main Menu scene or a real save-loading screen has been refitted.
local startupPillarLockActive = false

local mainMenuPillarReleaseArmed = false
local mainMenuPillarsReleased = false

-- Loading screens are themselves refitted ultrawide surfaces. If one appears
-- Main Menu -> gameplay initial loading screen lifecycle.
-- The exact scene subtree is attached a few frames after controller init on a
-- cold start, so keep a narrow exact-path readiness watch until that subtree
-- exists, then stop immediately after the first successful refit.
local initialLoadingScreenActive = false
local initialLoadingScreenController = nil
local initialLoadingCoverWatchActive = false

-- Standard/FastTravel loading can expose its controller before the exact Ink
-- subtree is attached on slower systems. Keep the controller only until the
-- exact path succeeds, then stop immediately.
local fastLoadingScreenController = nil
local fastLoadingLayoutWatchActive = false

-- Checkpoint reload / quickload uses a small default loading tree whose black
-- Fill rectangle is authored inside the centered 3840x2160 Root. Keep the UI
-- itself vanilla and extend only that concealment mask to the physical UW edges.
-- As with the other loading paths, retain a narrow exact-path readiness watch
-- until the two direct children are attached, then stop immediately.
UWUI_defaultLoadingScreenController = nil
UWUI_defaultLoadingMaskWatchActive = false

-- Settings has two validated exact roots:
--   * in-game Settings: Root[1]
--   * pre-game/Main Menu Settings: Root[0]
-- Runtime testing showed the earlier failure was a wrong-root problem, not a
-- construction-timing problem. Apply once at the dedicated controller event;
-- do not keep a readiness watcher unless a future user log proves one is needed.

-- Vehicle Selector Frontend is driven by a Native Settings integer range.
-- Native Settings calls the option callback synchronously from
-- SettingsSelectorControllerInt.Refresh(); that callback ends by recreating the
-- preview at 2950,950. UWUI therefore applies the responsive offset immediately
-- after Refresh returns.
local VEHICLE_SELECTOR_PREVIEW_BASE_LEFT = 2950.0
local VEHICLE_SELECTOR_PREVIEW_TOP = 950.0

-- HUB construction timing varies across systems. Both the main shell and its
-- late decorative Root[7] use exact-path readiness watches: retry only while
-- the validated direct path is absent, then stop immediately after success.
local hubLayoutWatchActive = false
local hubLayoutWatchReason = ""
local hubController = nil
local hubLastReadinessStatus = nil
local hubDecorFinalizePending = false
local hubDecorFinalizeReason = ""

-- World Map has two separately attached pieces: the Ink layout and the map
-- virtual camera. Never widen the camera before the Ink tree is refitted.
local worldMapLayoutWatchActive = false
local worldMapLayoutController = nil
local worldMapLayoutReady = false
local worldMapPendingCameraGameObject = nil

-- Arcade minigames intentionally retain their authored aspect ratio. Their
-- parallax layers can be wider than the visible arcade viewport and rely on the
-- stock black pillars as the outer mask. MenuScenario_ArcadeMinigame is the
-- engine-level shared lifecycle signal for all fullscreen arcade minigames.
local arcadePillarsActive = false

-- Hub submenu name captured from MenuScenario_HubMenu.OnOpenMenu.
-- Consumed by the first content ButtonHints.OnInitialize for that menu.
local pendingHubMenuName = nil

-- Only these proven menus may receive the halfExtra hint shift.
local buttonHintMenuRules = {
    cyberware_equip = 1,
    inventory_screen = 2,
    temp_stats = 5,
    quest_log = 2,
    codex = 2,
    new_perks = 3
}

-- These menus deliberately receive no hint correction: their own UI Root is widened to the current UI Spread width and naturally
-- carries the hints to that UI boundary.
local naturalHintMenus = {
    backpack = true,
    crafting_main = true,
    gallery = true,
    shards = true
}

-- Backpack's RMK search widget is injected by another mod and is positioned
-- once after BackpackMainGameController.OnInitialize.
local pendingBackpackSearchController = nil

-- Crafting's widget geometry is already correct before/after main init.
-- What becomes ready later is CraftingLogicController.virtualListController +
-- dataView. Poll only while Crafting is initializing; rebuild once, then stop.
local pendingCraftingGridRebuildController = nil
local pendingCraftingGridRebuildChecks = 0

-- Character's master backgrounds arrive later than both controller
-- OnInitialize and the next frame. Poll only the exact direct paths until all
-- three exist, apply once, then stop. The hint is handled separately by the
-- shared ButtonHints route (new_perks -> child[3]).
local pendingCharacterBackgroundWatch = false
local pendingCharacterReason = nil
local pendingCharacterChecks = 0

local pendingNotificationPopupWatch = false
local pendingNotificationPopupChecks = 0
local pendingNotificationPopupNeedsGalleryBackground = false
local pendingNotificationPopupRootName = "Root"

-- Breach main UI has a native intro animation: fullscreen_Fluff scales from
-- Y=0 to Y=1 and fluff_columns becomes visible as the intro completes.
-- Important lifecycle quirk: immediately after OnInitialize the tree briefly
-- reports the final scale=1 / visible=true state BEFORE that animation starts.
--
-- The finalize therefore uses two explicit phases:
--   1) wait until the intro is observed starting (scale != 1 or hidden);
--   2) only then accept a return to scale=1 / visible=true as truly settled.
-- Reapply the exact Breach refit once at that point, then stop. Do not collapse
-- this into a simple "is settled" check: that would fire before the intro.
local pendingBreachMainFinalizeWatch = false
local pendingBreachMainFinalizeReason = nil
local pendingBreachMainFinalizeChecks = 0
local pendingBreachMainIntroStarted = false

-- Breach Help/Tutorial is not announced reliably by PopupsManager when the
-- user opens the Help sub-view. Runtime testing showed the tutorial can
-- appear with no OnUpdateVisibility / OnUpdateData callbacks.
-- While the Breach controller is alive, watch only the proven exact tutorial
-- path until it becomes visible and is refitted once, then stop immediately.
local pendingBreachTutorialWatch = false
local pendingBreachTutorialReason = nil

-- Storage/Stash reuses FullscreenVendorGameController, so gate its layout by
-- the exact MenuScenario_Storage transition to avoid touching ordinary vendors.
local stashMenuActive = false
-- Vanilla Stash initializes the player-side filter to Invalid, then
-- PopulatePlayerInventory falls back to the first dynamically available
-- category (normally Ranged Weapons). After the FIRST population of each
-- Stash session, select the dynamically-created All Items toggle by its
-- stable label key / filter data. Later repopulations preserve the user's
-- manual filter choice.
local stashDefaultPlayerFilterForced = false

-- Runtime validation proved that geometry alone is not enough: the two
-- virtual-grid data views keep their pre-resize wrapping until the user changes
-- a filter. Re-run the native filter callbacks once, 0.20 s after BOTH player
-- and storage inventories have populated. This keeps the validated one-shot
-- native refresh without restoring any broad geometry retry window.
local stashPlayerInventoryPopulated = false
local stashVendorInventoryPopulated = false
local stashDataViewsRefreshed = false
local stashDataRefreshInProgress = false
local pendingStashDataRefreshController = nil
local pendingStashDataRefreshDelay = 0.0
local STASH_DATA_REFRESH_DELAY = 0.20

-- Ordinary buy/sell Vendor support.
-- Geometry is applied from FullscreenVendorGameController.OnInitialize.
-- The first virtual-item data bind is late enough to select player All Items.
-- Grid wrapping uses the same validated one-shot refresh as Stash: wait until
-- both player and vendor virtual grids have begun materializing, then replay
-- the current native filter callbacks once after 0.20 s. No retry/polling loop.
local vendorMenuActive = false
local vendorController = nil
local vendorPlayerItemMaterialized = false
local vendorVendorItemMaterialized = false
local vendorDefaultPlayerFilterForced = false
local vendorDataViewsRefreshed = false
local vendorDataRefreshInProgress = false
local pendingVendorDataRefreshController = nil
local pendingVendorDataRefreshDelay = 0.0
local VENDOR_DATA_REFRESH_DELAY = 0.20

local pendingGalleryLayoutWatch = false
local pendingGalleryLayoutReason = nil
local pendingGalleryLayoutChecks = 0

-- Shards can populate entryView after OnInitialize. Watch only the exact
-- reading-pane paths until they exist, apply once, then stop.
local pendingShardsLayoutWatch = false
local pendingShardsLayoutReason = nil
local pendingShardsLayoutChecks = 0

-- Optional Revised Backpack compatibility.
-- Observer registration is gated by quiet RTTI class-existence checks. If its
-- root children are not ready at OnInitialize, watch only the exact main-layout
-- paths until the first successful pass.
local pendingRevisedBackpackController = nil
local pendingRevisedBackpackReason = nil
local pendingRevisedBackpackChecks = 0

-- Optional StealthRunner compatibility.
-- Current StealthRunner does not fire the historical popup callbacks when its
-- stats popup opens. While the Hub is active, resolve only the exact popup
-- path at a low cadence. No recursive scan.
local stealthRunnerHubActive = false
local stealthRunnerPollFrames = 0
local STEALTHRUNNER_POLL_FRAME_INTERVAL = 15
local stealthRunnerAppliedVignette = nil

-- Forward declaration: StealthRunner resolver is defined earlier in the file
-- than the shared notifications helper implementation.
local getGameNotificationsVirtualWindow

local function writeDebugLog(message)
    -- This guard is defensive only. Call sites are ALSO guarded so that
    -- diagnostic arguments are never evaluated while logging is disabled.
    if not ACTIVATE_DEBUG_LOGS then return end

    local file = io.open(LOG_FILE, "a")
    if file ~= nil then
        file:write(string.format(
            "[%s] %s %s\n",
            os.date("%Y-%m-%d %H:%M:%S"),
            LOG_PREFIX,
            tostring(message)
        ))
        file:flush()
        file:close()
    end
end

local function initializeDebugLog()
    if not ACTIVATE_DEBUG_LOGS then return end

    local file = io.open(LOG_FILE, "w")
    if file ~= nil then
        file:write(string.format(
            "[%s] %s log initialized\n",
            os.date("%Y-%m-%d %H:%M:%S"),
            LOG_PREFIX
        ))
        file:flush()
        file:close()
    end
end

local function safe(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

-- CET exports every loaded RTTI class as a Lua class binding (dots in
-- native class names are replaced with underscores). Script aliases are also
-- exported. Prefer that very same registry used by CET's Observe() instead
-- of Game.GetRTTISystem(), which is not CET's class-resolution API.
--
-- DumpType() is a second, quiet check for native RTTI classes whose Lua
-- binding is not exposed under the expected spelling. An absent class gives
-- a Descriptor named "Unknown". Neither probe calls Observe() on a missing
-- class, so the CET console stays clean on installations without the mod.
local function optionalClassAvailable(className, classBinding)
    if classBinding ~= nil then
        return true, "CET class binding"
    end

    if type(DumpType) ~= "function" then
        return false, "CET DumpType unavailable"
    end

    local ok, description = pcall(function()
        return tostring(DumpType(className, false))
    end)
    if not ok then
        return false, "RTTI probe error: " .. tostring(description)
    end

    -- Compare the whole descriptor name, not a substring or an unrelated
    -- function/property name. In CET the default descriptor is "Unknown".
    local exactName = "\tname: " .. className .. ","
    local nativeName = "\tname: " ..
        className:gsub("%.", "_") .. ","
    if description:find(exactName, 1, true) ~= nil or
       description:find(nativeName, 1, true) ~= nil then
        return true, "CET RTTI descriptor"
    end

    return false, "class absent from CET RTTI"
end

local function isPreGame()
    return safe(function()
        local handler = Game.GetSystemRequestsHandler()
        if handler == nil then return nil end
        return handler:IsPreGame()
    end)
end

local function widgetName(widget)
    return safe(function() return widget:GetName().value end) or "<nil>"
end

local function cnameValue(value)
    return safe(function() return value.value end) or tostring(value)
end

local function directChild(parent, index, expectedName)
    if parent == nil then return nil end

    local child = safe(function()
        return parent:GetWidget(index)
    end)

    if child == nil then return nil end
    if expectedName ~= nil and widgetName(child) ~= expectedName then
        return nil
    end

    return child
end

local function interpolateToLegacy21x9(vanillaValue, legacy21x9Value, geometry)
    local progress = math.max(0.0, math.min(
        1.0,
        (geometry.contentWidth - VANILLA_CONTENT_WIDTH) /
        (LEGACY_21X9_CONTENT_WIDTH - VANILLA_CONTENT_WIDTH)
    ))

    return vanillaValue +
        (legacy21x9Value - vanillaValue) * progress
end

local function extendLegacy21x9Value(vanillaValue, legacy21x9Value, geometry)
    return interpolateToLegacy21x9(
        vanillaValue,
        legacy21x9Value,
        geometry
    ) + math.max(
        0.0,
        geometry.contentWidth - LEGACY_21X9_CONTENT_WIDTH
    )
end

local function clampUISpreadPercent(value)
    local numeric = tonumber(value) or 100
    return math.max(0, math.min(100, math.floor(numeric + 0.5)))
end

local function parseStoredBoolean(value, fallback)
    if value == nil then return fallback end

    local normalized = string.lower(tostring(value))
    if normalized == "true" or normalized == "1" or
       normalized == "yes" or normalized == "on" then
        return true
    end
    if normalized == "false" or normalized == "0" or
       normalized == "no" or normalized == "off" then
        return false
    end

    return fallback
end

local function loadPersistentSettings()
    local file = io.open(SETTINGS_FILE, "r")
    if file == nil then return end

    local content = file:read("*a") or ""
    file:close()

    local storedSpread = content:match("uiSpreadPercent%s*=%s*(%d+)")
    if storedSpread ~= nil then
        UI_SPREAD_PERCENT = clampUISpreadPercent(storedSpread)
    end

    local storedDebug = content:match("activateDebugLogs%s*=%s*([%w]+)")
    ACTIVATE_DEBUG_LOGS = parseStoredBoolean(
        storedDebug,
        ACTIVATE_DEBUG_LOGS
    )
end

local function savePersistentSettings()
    local file = io.open(SETTINGS_FILE, "w")
    if file == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "settings save failed: could not open " .. SETTINGS_FILE
            )
        end
        return false
    end

    file:write(
        "uiSpreadPercent=" .. tostring(UI_SPREAD_PERCENT) .. "\n" ..
        "activateDebugLogs=" .. tostring(ACTIVATE_DEBUG_LOGS) .. "\n"
    )
    file:flush()
    file:close()
    return true
end

-- Derive a second geometry for UI distribution without changing the physical
-- screen geometry. This is the key separation for the feature: fullscreen
-- backgrounds keep using getTargetGeometry(), while selected menu UI uses this
-- interpolated width. At 100% this is byte-for-byte equivalent numerically to
-- the pre-feature UI geometry; at 0% contentWidth/extraWidth/halfExtra are vanilla.
local function getUISpreadGeometry(screenGeometry)
    if screenGeometry == nil then return nil end

    local spread = clampUISpreadPercent(UI_SPREAD_PERCENT) / 100.0
    local uiContentWidth = VANILLA_CONTENT_WIDTH +
        (screenGeometry.contentWidth - VANILLA_CONTENT_WIDTH) * spread
    local uiExtraWidth = uiContentWidth - VANILLA_CONTENT_WIDTH

    return {
        displayWidth = screenGeometry.displayWidth,
        displayHeight = screenGeometry.displayHeight,
        aspect = uiContentWidth / REFERENCE_HEIGHT,
        screenAspect = screenGeometry.aspect,
        screenContentWidth = screenGeometry.contentWidth,
        screenExtraWidth = screenGeometry.extraWidth,
        screenHalfExtra = screenGeometry.halfExtra,
        contentWidth = uiContentWidth,
        extraWidth = uiExtraWidth,
        halfExtra = uiExtraWidth * 0.5,
        uiSpread = spread,
        uiSpreadPercent = UI_SPREAD_PERCENT
    }
end

local function registerNativeSettings()
    local ok, err = pcall(function()
        local nativeSettingsUI = GetMod("nativeSettings")
        if nativeSettingsUI == nil then
            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("Native Settings unavailable; UI Spread remains " .. tostring(UI_SPREAD_PERCENT) .. "%")
            end
            return
        end

        nativeSettingsUI.addTab("/uwui", "Ultrawide UI Overhaul")
        nativeSettingsUI.addSubcategory("/uwui/layout", "Layout")
        nativeSettingsUI.addRangeInt(
            "/uwui/layout",
            "UI Spread",
            "Controls how far menu UI elements spread across the screen. 0% keeps the UI inside a centered 16:9 area; 100% uses the full ultrawide width. Fullscreen backgrounds remain full-width.",
            0,
            100,
            5,
            UI_SPREAD_PERCENT,
            100,
            function(value)
                UI_SPREAD_PERCENT = clampUISpreadPercent(value)
                savePersistentSettings()

                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(
                        "UI SPREAD changed via Native Settings: " ..
                        tostring(UI_SPREAD_PERCENT) ..
                        "% (applies on the next relevant menu layout pass)"
                    )
                end
            end
        )

        nativeSettingsUI.addSubcategory("/uwui/debug", "Debug")
        nativeSettingsUI.addSwitch(
            "/uwui/debug",
            "Activate Debug Logs",
            "Writes detailed troubleshooting information to UltrawideUIOverhaul_debug.log. Keep this disabled unless you are diagnosing an issue.",
            ACTIVATE_DEBUG_LOGS,
            false,
            function(enabled)
                enabled = enabled == true

                if enabled == ACTIVATE_DEBUG_LOGS then
                    return
                end

                if enabled then
                    ACTIVATE_DEBUG_LOGS = true
                    savePersistentSettings()
                    initializeDebugLog()
                    writeDebugLog(
                        "debug logging enabled via Native Settings"
                    )
                else
                    writeDebugLog(
                        "debug logging disabled via Native Settings"
                    )
                    ACTIVATE_DEBUG_LOGS = false
                    savePersistentSettings()
                end
            end
        )

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "Native Settings registered: uiSpread=" ..
                tostring(UI_SPREAD_PERCENT) ..
                "% debugLogs=" .. tostring(ACTIVATE_DEBUG_LOGS)
            )
        end
    end)

    if not ok and ACTIVATE_DEBUG_LOGS then
        writeDebugLog("Native Settings registration failed: " .. tostring(err))
    end
end

-- Diagnostic helpers. These are never called unless ACTIVATE_DEBUG_LOGS=true.
local function debugWidgetSize(widget)
    if widget == nil then return "nil" end
    local size = safe(function() return widget:GetSize() end)
    if size == nil then return "?" end
    return string.format("%.2fx%.2f", size.X or -1, size.Y or -1)
end

local function debugWidgetMargin(widget)
    if widget == nil then return "nil" end
    local margin = safe(function() return widget:GetMargin() end)
    if margin == nil then return "?" end
    return string.format(
        "[%.2f, %.2f, %.2f, %.2f]",
        margin.left or -9999,
        margin.top or -9999,
        margin.right or -9999,
        margin.bottom or -9999
    )
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

    local contentWidth = aspect * REFERENCE_HEIGHT
    local extraWidth = contentWidth - VANILLA_CONTENT_WIDTH

    return {
        displayWidth = displayWidth,
        displayHeight = displayHeight,
        aspect = aspect,
        contentWidth = contentWidth,
        extraWidth = extraWidth,
        halfExtra = extraWidth * 0.5
    }
end

local function setPillarsDisabled(disabled, reason)
    local ok, err = pcall(function()
        local coordinator = GetMod("BlackPillarsCoordinator")

        if coordinator ~= nil and coordinator.SetPillarsDisabled ~= nil then
            coordinator.SetPillarsDisabled(disabled)
        elseif UWMenuSetPillarsDisabled ~= nil then
            UWMenuSetPillarsDisabled(disabled)
        elseif UWMapSetBlackBarsSuppressed ~= nil then
            UWMapSetBlackBarsSuppressed(disabled)
        else
            error("No black-pillar suppression API available")
        end
    end)

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "pillars %s (%s)",
                disabled and "DISABLED" or "ENABLED",
                tostring(reason or "unknown")
            ))
        else
            writeDebugLog(string.format(
                "pillar state change failed (%s, disabled=%s): %s",
                tostring(reason or "unknown"),
                tostring(disabled),
                tostring(err)
            ))
        end
    end

    return ok
end

local function disablePillars(reason)
    if startupPillarLockActive then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "pillar suppression BLOCKED by startup lock (" ..
                tostring(reason or "unknown") ..
                ")"
            )
        end
        return false
    end

    return setPillarsDisabled(true, reason)
end

-- Auto-load mods may skip displaying the Main Menu. A successfully refitted
-- save-loading screen is another valid hand-off from startup to ultrawide.
-- Keep the existing readiness watches active if the backend is unavailable.
local function releaseLoadingPillarsIfReady(reason)
    if not setPillarsDisabled(true, reason) then
        return false
    end

    startupPillarLockActive = false
    mainMenuPillarReleaseArmed = false
    mainMenuWatchActive = false
    return true
end

-- Arcade minigames are the one post-startup surface that intentionally wants
-- the stock pillars back. This goes through a dedicated coordinator override
-- instead of weakening the normal process-lifetime pillar suppression latch.
local function setTemporaryPillarsVisible(visible, reason)
    local ok, err = pcall(function()
        local coordinator = GetMod("BlackPillarsCoordinator")

        if coordinator ~= nil and
           coordinator.SetTemporaryPillarsVisible ~= nil then
            coordinator.SetTemporaryPillarsVisible(visible)
        elseif UWMenuSetTemporaryPillarsVisible ~= nil then
            UWMenuSetTemporaryPillarsVisible(visible)
        else
            error("No temporary black-pillar visibility API available")
        end
    end)

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "temporary pillars %s (%s)",
                visible and "VISIBLE" or "RELEASED",
                tostring(reason or "unknown")
            ))
        else
            writeDebugLog(string.format(
                "temporary pillar state change failed (%s, visible=%s): %s",
                tostring(reason or "unknown"),
                tostring(visible),
                tostring(err)
            ))
        end
    end

    return ok
end

local function getMenuVirtualWindow()
    local inkSystem = safe(function()
        return Game.GetInkSystem()
    end)
    if inkSystem == nil then return nil, "ink_system_unavailable" end

    local layer = safe(function()
        return inkSystem:GetLayer(CName.new("inkMenuLayer"))
    end)
    if layer == nil then return nil, "ink_menu_layer_unavailable" end

    local virtualWindow = safe(function()
        return layer:GetVirtualWindow()
    end)
    if virtualWindow == nil then
        return nil, "virtual_window_unavailable"
    end

    return virtualWindow, "ready"
end

local function getMenuContentRoot()
    local virtualWindow, windowStatus = getMenuVirtualWindow()
    if virtualWindow == nil then
        return nil, nil, nil, windowStatus
    end

    local outerRoot = safe(function()
        return virtualWindow:GetWidget(0)
    end)
    if outerRoot == nil then
        return virtualWindow, nil, nil, "outer_root_unavailable"
    end
    if widgetName(outerRoot) ~= "Root" then
        return virtualWindow, outerRoot, nil,
            "outer_root_unexpected_name=" .. widgetName(outerRoot)
    end

    local contentRoot = safe(function()
        return outerRoot:GetWidget(0)
    end)
    if contentRoot == nil then
        return virtualWindow, outerRoot, nil,
            "content_root_unavailable"
    end
    if widgetName(contentRoot) ~= "Root" then
        return virtualWindow, outerRoot, nil,
            "content_root_unexpected_name=" .. widgetName(contentRoot)
    end

    return virtualWindow, outerRoot, contentRoot, "ready"
end

-- The Hub can be initialized before inkMenuLayer's global lookup becomes
-- available. Retain the Hub controller and check ONLY its own root, its direct
-- Root[0] child and its immediate parent/Root[0] child. Each candidate must
-- have the validated mainMenu[1]/fluff[3] signature and an attached parent.
-- This is a targeted alternate entry point, not a tree scan or new signature.
local function hubContentSignatureReady(candidate)
    if candidate == nil or widgetName(candidate) ~= "Root" then
        return false
    end

    local mainMenu = directChild(candidate, 1, "mainMenu")
    return directChild(mainMenu, 3, "fluff") ~= nil
end

local function resolveHubContentRoot(controller)
    local virtualWindow, outerRoot, contentRoot, globalStatus =
        getMenuContentRoot()

    if hubContentSignatureReady(contentRoot) then
        return virtualWindow, outerRoot, contentRoot,
            "global inkMenuLayer", "ready"
    end

    local controllerRoot = controller ~= nil and safe(function()
        return controller:GetRootWidget()
    end) or nil

    if controllerRoot == nil then
        if contentRoot ~= nil then
            return virtualWindow, outerRoot, contentRoot,
                "global inkMenuLayer", "hub_signature_pending"
        end
        return virtualWindow, outerRoot, nil, "unavailable",
            tostring(globalStatus) .. ";controller_root_unavailable"
    end

    local parent = safe(function()
        return controllerRoot:GetParentWidget()
    end)
    local candidates = {
        { widget = controllerRoot, source = "controller.root" },
        { widget = directChild(controllerRoot, 0, "Root"),
          source = "controller.root/Root[0]" },
        { widget = parent, source = "controller.parent" },
        { widget = directChild(parent, 0, "Root"),
          source = "controller.parent/Root[0]" }
    }

    for _, candidate in ipairs(candidates) do
        local widget = candidate.widget
        if hubContentSignatureReady(widget) then
            local widgetParent = safe(function()
                return widget:GetParentWidget()
            end)
            if widgetParent ~= nil then
                return virtualWindow, widgetParent, widget,
                    candidate.source, "ready"
            end
        end
    end

    -- Retain a not-yet-complete global root for its ordinary exact-path
    -- readiness handling. No mutations are made until the signature exists.
    if contentRoot ~= nil then
        return virtualWindow, outerRoot, contentRoot,
            "global inkMenuLayer", "hub_signature_pending"
    end

    -- Only the log needs the extra widget names and child count. In release
    -- mode, do not perform diagnostic-only widget queries every frame.
    if not ACTIVATE_DEBUG_LOGS then
        return virtualWindow, outerRoot, nil, "unavailable", nil
    end

    return virtualWindow, outerRoot, nil, "unavailable",
        tostring(globalStatus) ..
        ";controller_root=" .. widgetName(controllerRoot) ..
        ";parent=" .. widgetName(parent) ..
        ";children=" .. tostring(safe(function()
            return controllerRoot:GetNumChildren()
        end))
end

-- Called only on initial failure or a readiness status transition. Do not
-- query widget diagnostics during ordinary release-mode watcher frames.
local function logHubControllerSnapshot(context)
    if not ACTIVATE_DEBUG_LOGS then return end

    local root = hubController ~= nil and safe(function()
        return hubController:GetRootWidget()
    end) or nil
    local parent = root ~= nil and safe(function()
        return root:GetParentWidget()
    end) or nil
    local grandparent = parent ~= nil and safe(function()
        return parent:GetParentWidget()
    end) or nil

    writeDebugLog(string.format(
        "HUB controller snapshot (%s): root=%s size=%s children=%s | parent=%s size=%s children=%s | grandparent=%s",
        tostring(context),
        widgetName(root),
        debugWidgetSize(root),
        tostring(root ~= nil and safe(function()
            return root:GetNumChildren()
        end) or nil),
        widgetName(parent),
        debugWidgetSize(parent),
        tostring(parent ~= nil and safe(function()
            return parent:GetNumChildren()
        end) or nil),
        widgetName(grandparent)
    ))
    writeDebugLog(string.format(
        "HUB controller direct children: root[0]=%s root[1]=%s parent[0]=%s parent[1]=%s",
        widgetName(directChild(root, 0)),
        widgetName(directChild(root, 1)),
        widgetName(directChild(parent, 0)),
        widgetName(directChild(parent, 1))
    ))
end

local function setWidgetWidth(widget, width)
    if widget == nil then return false end

    local size = safe(function() return widget:GetSize() end)
    if size == nil then return false end

    return pcall(function()
        widget:SetSize(width, size.Y)
    end)
end

-- ---------------------------------------------------------------------------
-- MAIN MENU
--
-- Current proven runtime path:
--
-- inkMenuLayer/inkVirtualWindow
-- └─ Root[0]
--    ├─ Root[0]  (pre-game content; in-game fullscreen background)
--    └─ Root[1]  (in-game content)
--       ├─ bganim[0]
--       └─ backgroundContainer[1]
--          └─ <dynamic scene>[0]
--
-- IMPORTANT:
-- The scene name is intentionally NEVER referenced. The game selects a
-- different scene according to progression (for example v_apt_shot1 in the
-- current dump), so only its stable parent + child index are used.
--
-- Main Menu deliberately separates UI and background geometry:
--   content Root width = UI Spread contentWidth
--   coverScale         = physical screen contentWidth / 3840
--   horizontalInset    = UI-local (uiContentWidth - 3840) / 2
--   verticalCrop       = (2160 * coverScale - 2160) / 2
--
-- This keeps the menu composition inside the selected UI Spread width while
-- the progression-dependent background scene always continues to cover and
-- remain centered on the full physical ultrawide viewport.
--
-- Lifecycle:
-- The scene is inserted/replaced asynchronously, including around
-- SingleplayerMenuGameController.OnSavesForLoadReady. Rather than recursively
-- scanning with retry budgets, keep a tiny exact-path watch active only while
-- IsPreGame() is true. Each scene instance is mutated once.
--
-- Preem Menu compatibility is deliberately NOT guessed here. The old script
-- knew only that Preem had a direct backgroundContainer and no bganim, but we
-- do not yet have a current dump proving its child index.
-- ---------------------------------------------------------------------------

local function resolveMainMenuExact()
    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return nil end

    local outerRoot = directChild(
        virtualWindow, 0, "Root"
    )
    local contentRoot = directChild(
        outerRoot, 0, "Root"
    )
    local backgroundContainer = directChild(
        contentRoot, 1, "backgroundContainer"
    )

    if outerRoot == nil or
       contentRoot == nil or
       backgroundContainer == nil then
        return nil
    end

    -- Intentionally do not validate the child name.
    local scene = directChild(
        backgroundContainer, 0, nil
    )

    return {
        contentRoot = contentRoot,
        backgroundContainer = backgroundContainer,
        scene = scene
    }
end

local function releaseMainMenuPillarsIfReady(reason)
    if not mainMenuPillarReleaseArmed or
       mainMenuPillarsReleased or
       not mainMenuSceneRefitted then
        return false
    end

    -- Alongside refitted save-loading screens, the dynamic Main Menu scene
    -- may lift the startup lock. Generic menu/hint callbacks cannot do so.
    startupPillarLockActive = false

    local ok = setPillarsDisabled(
        true,
        "main menu display gate " .. tostring(reason)
    )

    if ok then
        mainMenuPillarsReleased = true
        return true
    end

    -- If the backend call failed, restore the lock so a later exact-path pass
    -- can retry without allowing unrelated callbacks to suppress the pillars.
    startupPillarLockActive = true
    return false
end

local function tryApplyMainMenuExact(reason)
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil or screenGeometry == nil then return false end

    local tree = resolveMainMenuExact()
    if tree == nil then
        mainMenuSceneRefitted = false
        return false
    end

    local scene = tree.scene
    if scene == nil then
        mainMenuSceneRefitted = false
        return false
    end

    -- The menu root follows UI Spread, but the dynamic scene is a true
    -- fullscreen background and must always use physical screen geometry.
    local coverScale =
        screenGeometry.contentWidth / VANILLA_CONTENT_WIDTH

    -- The scene lives under the UI-width contentRoot. Its local horizontal
    -- inset must therefore be expressed in that parent's coordinate space.
    -- Using screenHalfExtra here would shift the fullscreen scene right by
    -- exactly half the difference between physical width and UI Spread width.
    -- uiHalfExtra cancels that parent offset while keeping the physical cover
    -- scale/crop untouched. At 100% it equals the historical screen inset.
    local horizontalInset = geometry.halfExtra

    local verticalCrop =
        (REFERENCE_HEIGHT * coverScale - REFERENCE_HEIGHT) * 0.5

    -- CET/Ink can return a fresh userdata wrapper for the same native widget,
    -- so Lua userdata identity is not a reliable "already applied" guard.
    --
    -- Instead, inspect the actual target geometry. This is both idempotent and
    -- robust if the game later replaces the progression-dependent scene:
    -- a newly attached vanilla scene will fail this test and get refitted once.
    local rootSize = safe(function()
        return tree.contentRoot:GetSize()
    end)
    local sceneScale = safe(function()
        return scene:GetScale()
    end)
    local sceneMargin = safe(function()
        return scene:GetMargin()
    end)
    local sceneTranslation = safe(function()
        return scene:GetTranslation()
    end)

    local tolerance = 0.05

    local alreadyRefitted =
        rootSize ~= nil and
        sceneScale ~= nil and
        sceneMargin ~= nil and
        sceneTranslation ~= nil and
        math.abs(rootSize.X - geometry.contentWidth) <= tolerance and
        math.abs(rootSize.Y - REFERENCE_HEIGHT) <= tolerance and
        math.abs(sceneScale.X - coverScale) <= tolerance and
        math.abs(sceneScale.Y - coverScale) <= tolerance and
        math.abs(sceneMargin.left - horizontalInset) <= tolerance and
        math.abs(sceneMargin.top) <= tolerance and
        math.abs(sceneMargin.right) <= tolerance and
        math.abs(sceneMargin.bottom) <= tolerance and
        math.abs(sceneTranslation.X) <= tolerance and
        math.abs(sceneTranslation.Y + verticalCrop) <= tolerance

    if alreadyRefitted then
        mainMenuSceneRefitted = true
        releaseMainMenuPillarsIfReady(
            tostring(reason) .. " (geometry already correct)"
        )
        return true
    end

    local beforeRootSize = rootSize
    local beforeSceneScale = sceneScale
    local beforeSceneMargin = sceneMargin
    local beforeSceneTranslation = sceneTranslation

    local rootOk, rootError = pcall(function()
        tree.contentRoot:SetSize(
            geometry.contentWidth,
            REFERENCE_HEIGHT
        )
        tree.contentRoot:FlagForVisualInvalidation()
    end)

    local sceneOk, sceneError = pcall(function()
        scene:SetScale(Vector2.new({
            X = coverScale,
            Y = coverScale
        }))

        scene:SetTranslation(Vector2.new({
            X = 0.0,
            Y = -verticalCrop
        }))

        scene:SetMargin(
            horizontalInset,
            0.0,
            0.0,
            0.0
        )

        scene:FlagForVisualInvalidation()
    end)

    local success = rootOk and sceneOk

    if success then
        mainMenuSceneRefitted = true
        releaseMainMenuPillarsIfReady(reason)
    else
        mainMenuSceneRefitted = false
    end

    if ACTIVATE_DEBUG_LOGS then
        if success then
            writeDebugLog(string.format(
                "MAIN MENU applied (%s) uiSpread=%d%% screenWidth=%.2f uiWidth=%.2f root=%s -> %.2fx%.2f | dynamicScene[0] scale=%s -> [%.5f,%.5f] localMargin=%s -> [%.2f,0,0,0] translation=%s -> [0,%.2f]",
                tostring(reason),
                geometry.uiSpreadPercent or UI_SPREAD_PERCENT,
                screenGeometry.contentWidth,
                geometry.contentWidth,
                beforeRootSize ~= nil and
                    string.format(
                        "%.2fx%.2f",
                        beforeRootSize.X,
                        beforeRootSize.Y
                    ) or "unknown",
                geometry.contentWidth,
                REFERENCE_HEIGHT,
                beforeSceneScale ~= nil and
                    string.format(
                        "[%.5f,%.5f]",
                        beforeSceneScale.X,
                        beforeSceneScale.Y
                    ) or "unknown",
                coverScale,
                coverScale,
                beforeSceneMargin ~= nil and
                    string.format(
                        "[%.2f,%.2f,%.2f,%.2f]",
                        beforeSceneMargin.left,
                        beforeSceneMargin.top,
                        beforeSceneMargin.right,
                        beforeSceneMargin.bottom
                    ) or "unknown",
                horizontalInset,
                beforeSceneTranslation ~= nil and
                    string.format(
                        "[%.2f,%.2f]",
                        beforeSceneTranslation.X,
                        beforeSceneTranslation.Y
                    ) or "unknown",
                -verticalCrop
            ))
        else
            writeDebugLog(
                "MAIN MENU apply error (" ..
                tostring(reason) ..
                ") root=" .. tostring(rootError) ..
                " scene=" .. tostring(sceneError)
            )
        end
    end

    return success
end

local function armMainMenuWatch(reason)
    mainMenuWatchActive = true
    mainMenuSceneRefitted = false

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(
            "MAIN MENU exact-path watch armed: " ..
            tostring(reason)
        )
    end

    -- Try immediately. If child[0] is not attached yet, onUpdate keeps
    -- watching only this exact path until it appears or pre-game ends.
    tryApplyMainMenuExact(reason)
end


-- ---------------------------------------------------------------------------
-- HUB
-- ---------------------------------------------------------------------------

local function applyHubImmediate(reason)
    local logThis = ACTIVATE_DEBUG_LOGS and reason ~= nil

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then
        if logThis then
            writeDebugLog("HUB immediate aborted: target geometry unavailable")
        end
        return false, "geometry_unavailable"
    end

    local virtualWindow, outerRoot, contentRoot, source, readinessStatus =
        resolveHubContentRoot(hubController)

    if logThis then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("HUB immediate BEGIN: " .. tostring(reason))
        writeDebugLog(string.format(
            "geometry: display=%dx%d aspect=%.6f screenWidth=%.2f uiSpread=%d%% uiWidth=%.2f uiExtra=%.2f uiHalfExtra=%.2f",
            geometry.displayWidth,
            geometry.displayHeight,
            geometry.aspect,
            geometry.screenContentWidth,
            geometry.uiSpreadPercent,
            geometry.contentWidth,
            geometry.extraWidth,
            geometry.halfExtra
        ))
        writeDebugLog(string.format(
            "source=%s status=%s virtualWindow=%s outerRoot=%s contentRoot=%s children=%s",
            tostring(source),
            tostring(readinessStatus),
            debugWidgetSize(virtualWindow),
            debugWidgetSize(outerRoot),
            debugWidgetSize(contentRoot),
            tostring(contentRoot ~= nil and safe(function()
                return contentRoot:GetNumChildren()
            end) or nil)
        ))
    end

    if contentRoot == nil then
        if logThis then
            writeDebugLog("HUB immediate aborted: content Root unavailable")
            logHubControllerSnapshot("initial content root unavailable")
        end
        return false, readinessStatus
    end

    local mainMenu = safe(function()
        return contentRoot:GetWidget(1)
    end)

    local mainFluff = mainMenu ~= nil and safe(function()
        return mainMenu:GetWidget(3)
    end) or nil

    if logThis then
        writeDebugLog(string.format(
            "mainMenu[1]: exists=%s name=%s size=%s children=%s",
            tostring(mainMenu ~= nil),
            widgetName(mainMenu),
            debugWidgetSize(mainMenu),
            tostring(mainMenu ~= nil and safe(function()
                return mainMenu:GetNumChildren()
            end) or nil)
        ))
        writeDebugLog(string.format(
            "mainMenu[1]/fluff[3]: exists=%s name=%s size=%s margin=%s",
            tostring(mainFluff ~= nil),
            widgetName(mainFluff),
            debugWidgetSize(mainFluff),
            debugWidgetMargin(mainFluff)
        ))
    end

    if mainMenu == nil or widgetName(mainMenu) ~= "mainMenu" then
        if logThis then
            writeDebugLog("HUB immediate aborted: mainMenu[1] unavailable or unexpected")
        end
        return false, ACTIVATE_DEBUG_LOGS and
            ("mainMenu[1]_pending;source=" .. tostring(source)) or nil
    end

    if mainFluff == nil or widgetName(mainFluff) ~= "fluff" then
        if logThis then
            writeDebugLog("HUB immediate aborted: mainMenu/fluff[3] unavailable or unexpected")
        end
        return false, ACTIVATE_DEBUG_LOGS and
            ("mainMenu/fluff[3]_pending;source=" .. tostring(source)) or nil
    end

    -- 1) Root[0]/Root[0]
    local contentRootOk = setWidgetWidth(contentRoot, geometry.contentWidth)

    -- 2) Root[0]/Root[0]/mainMenu[1]/fluff[3]
    local mainFluffOk = setWidgetWidth(mainFluff, geometry.contentWidth)

    if logThis then
        writeDebugLog(string.format(
            "HUB immediate mutations: contentRoot=%s mainFluff=%s",
            tostring(contentRootOk),
            tostring(mainFluffOk)
        ))
        writeDebugLog(string.format(
            "HUB AFTER immediate: contentRoot=%s mainFluff=%s",
            debugWidgetSize(contentRoot),
            debugWidgetSize(mainFluff)
        ))
    end

    -- Root[7] is late-created. Keep an exact-path readiness watch until
    -- that branch exists instead of assuming it appears on the next frame.
    hubDecorFinalizePending = true
    if reason ~= nil then
        hubDecorFinalizeReason = tostring(reason)
    end

    if logThis then
        local lateRoot = safe(function() return contentRoot:GetWidget(7) end)
        writeDebugLog(string.format(
            "late Root[7] during immediate pass: exists=%s name=%s | readiness finalize armed",
            tostring(lateRoot ~= nil),
            widgetName(lateRoot)
        ))
        writeDebugLog("HUB immediate END")
    end

    local applied = contentRootOk and mainFluffOk
    if not ACTIVATE_DEBUG_LOGS then return applied end
    return applied, applied and ("ready;source=" .. tostring(source)) or
        "hub_size_mutation_failed"
end

local function finalizeHubDecor(reason)
    local logThis = ACTIVATE_DEBUG_LOGS and reason ~= nil

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then
        if logThis then
            writeDebugLog("HUB finalize failed: target geometry unavailable")
        end
        return false
    end

    local _, _, contentRoot = resolveHubContentRoot(hubController)
    if contentRoot == nil then
        if logThis then
            writeDebugLog("HUB finalize failed: content Root unavailable")
        end
        return false
    end

    local decorRoot = safe(function()
        return contentRoot:GetWidget(7)
    end)

    if logThis then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("HUB finalize BEGIN: " .. tostring(reason))
        writeDebugLog(string.format(
            "UI SPREAD: %d%% | screenWidth=%.2f uiWidth=%.2f uiHalfExtra=%.2f",
            geometry.uiSpreadPercent,
            geometry.screenContentWidth,
            geometry.contentWidth,
            geometry.halfExtra
        ))
        writeDebugLog(string.format(
            "contentRoot=%s children=%s | Root[7] exists=%s name=%s size=%s",
            debugWidgetSize(contentRoot),
            tostring(safe(function() return contentRoot:GetNumChildren() end)),
            tostring(decorRoot ~= nil),
            widgetName(decorRoot),
            debugWidgetSize(decorRoot)
        ))
    end

    if decorRoot == nil or widgetName(decorRoot) ~= "Root" then
        if logThis then
            writeDebugLog("HUB finalize pending: Root[7] unavailable or unexpected")
        end
        return false
    end

    local rightFluff = safe(function()
        return decorRoot:GetWidget(0)
    end)

    local rightLines = safe(function()
        return decorRoot:GetWidget(4)
    end)

    if logThis then
        writeDebugLog(string.format(
            "Right_fluff_elements[0]: exists=%s name=%s size=%s margin=%s",
            tostring(rightFluff ~= nil),
            widgetName(rightFluff),
            debugWidgetSize(rightFluff),
            debugWidgetMargin(rightFluff)
        ))
        writeDebugLog(string.format(
            "Right_lines[4]: exists=%s name=%s size=%s margin=%s",
            tostring(rightLines ~= nil),
            widgetName(rightLines),
            debugWidgetSize(rightLines),
            debugWidgetMargin(rightLines)
        ))
    end

    if rightFluff == nil or widgetName(rightFluff) ~= "Right_fluff_elements" then
        if logThis then
            writeDebugLog("HUB finalize pending: Right_fluff_elements[0] unavailable or unexpected")
        end
        return false
    end

    if rightLines == nil or widgetName(rightLines) ~= "Right_lines" then
        if logThis then
            writeDebugLog("HUB finalize pending: Right_lines[4] unavailable or unexpected")
        end
        return false
    end

    -- 3) Root[7]
    local decorRootOk = setWidgetWidth(decorRoot, geometry.contentWidth)

    -- 4) Right_fluff_elements[0]
    -- Keep the authored 3840x2160 canvas and move the whole block.
    local rightFluffOk = pcall(function()
        rightFluff:SetSize(VANILLA_CONTENT_WIDTH, REFERENCE_HEIGHT)
        rightFluff:SetMargin(
            geometry.halfExtra - 3.0,
            -5.0,
            0.0,
            0.0
        )
    end)

    -- 5) Right_lines[4]
    -- Vanilla X is 3785 = 3840 - 55, therefore final X = contentWidth - 55.
    local rightLinesOk = pcall(function()
        rightLines:SetMargin(
            geometry.contentWidth - 55.0,
            0.0,
            0.0,
            0.0
        )
    end)

    if logThis then
        writeDebugLog(string.format(
            "HUB finalize mutations: decorRoot=%s rightFluff=%s rightLines=%s",
            tostring(decorRootOk),
            tostring(rightFluffOk),
            tostring(rightLinesOk)
        ))
        writeDebugLog(string.format(
            "HUB AFTER finalize: decorRoot=%s | rightFluff=%s margin=%s | rightLines margin=%s",
            debugWidgetSize(decorRoot),
            debugWidgetSize(rightFluff),
            debugWidgetMargin(rightFluff),
            debugWidgetMargin(rightLines)
        ))
        writeDebugLog("HUB finalize END")
    end

    return decorRootOk and rightFluffOk and rightLinesOk
end

-- ---------------------------------------------------------------------------
-- BACKPACK
--
-- Exact direct paths validated with Ink Tree Dumper:
--
-- Root[0]/Root[0]
-- ├─ wrapper[0]
-- │  ├─ inkCanvasWidget21[0]
-- │  │  └─ inkVerticalPanelWidget25[2]
-- │  │     ├─ filter_buttons[1]
-- │  │     │  └─ dropdownButton8[1]
-- │  │     └─ searchContainer[2]
-- │  └─ inventory_wrapper[2]
-- │     └─ inventory_panel[0]
-- │        └─ inkCanvasWidget16[0]
-- │           └─ scroller_wrapper[0]
-- │              ├─ scrollingBackground[1]
-- │              ├─ scrollingBackgroundshadow[2]
-- │              ├─ scroll_cache_widget[3]
-- │              │  └─ scroll_area[0]
-- │              │     └─ inkVirtualCompoundWidget4[0]
-- │              └─ ScrollCacheImage[4]
-- └─ dropdownContainer[2]
--
-- No recursive scans.
-- No Backpack-specific hint mutation: widening Root[0]/Root[0] carries the
-- hints naturally to the ultrawide edge.
-- No Backpack-specific Right_fluff mutation: the shared Hub treatment already
-- puts it in the correct place.
-- ---------------------------------------------------------------------------

local function resizeWidgetWidth(widget, width, invalidate)
    if widget == nil then return false end

    local size = safe(function() return widget:GetSize() end)
    if size == nil then return false end

    local ok = pcall(function()
        widget:SetSize(width, size.Y)
        if invalidate then
            widget:FlagForVisualInvalidation()
        end
    end)

    return ok
end

local function resolveBackpackTree()
    local _, _, contentRoot = getMenuContentRoot()
    if contentRoot == nil then return nil end

    -- Structural signature first: do not mutate a generic Root/Root unless
    -- wrapper[0]/inventory_wrapper[2] proves this is the Backpack layout.
    local wrapper = directChild(contentRoot, 0, "wrapper")
    if wrapper == nil then return nil end

    local inventoryWrapper = directChild(wrapper, 2, "inventory_wrapper")
    if inventoryWrapper == nil then return nil end

    local canvas21 = directChild(wrapper, 0, "inkCanvasWidget21")

    local inventoryPanel = directChild(
        inventoryWrapper, 0, "inventory_panel"
    )
    local canvas16 = directChild(
        inventoryPanel, 0, "inkCanvasWidget16"
    )
    local scrollerWrapper = directChild(
        canvas16, 0, "scroller_wrapper"
    )

    local scrollingBackground = directChild(
        scrollerWrapper, 1, "scrollingBackground"
    )
    local scrollingBackgroundShadow = directChild(
        scrollerWrapper, 2, "scrollingBackgroundshadow"
    )
    local scrollCacheWidget = directChild(
        scrollerWrapper, 3, "scroll_cache_widget"
    )
    local scrollArea = directChild(
        scrollCacheWidget, 0, "scroll_area"
    )
    local virtualGrid = directChild(
        scrollArea, 0, "inkVirtualCompoundWidget4"
    )
    local scrollCacheImage = directChild(
        scrollerWrapper, 4, "ScrollCacheImage"
    )

    local dropdownContainer = directChild(
        contentRoot, 2, "dropdownContainer"
    )

    return {
        contentRoot = contentRoot,
        wrapper = wrapper,
        canvas21 = canvas21,
        inventoryWrapper = inventoryWrapper,
        inventoryPanel = inventoryPanel,
        canvas16 = canvas16,
        scrollerWrapper = scrollerWrapper,
        scrollingBackground = scrollingBackground,
        scrollingBackgroundShadow = scrollingBackgroundShadow,
        scrollCacheWidget = scrollCacheWidget,
        scrollArea = scrollArea,
        virtualGrid = virtualGrid,
        scrollCacheImage = scrollCacheImage,
        dropdownContainer = dropdownContainer
    }
end

local function applyBackpackLayoutDirect(controller, reason)
    disablePillars("backpack " .. tostring(reason))

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil or controller == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("BACKPACK aborted: geometry/controller unavailable")
        end
        return false
    end

    local tree = resolveBackpackTree()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "BACKPACK aborted: exact Root/Root/wrapper/inventory_wrapper signature not found"
            )
        end
        return false
    end

    local inventoryCanvasWidth = extendLegacy21x9Value(
        2720.0, 3990.0, geometry
    )

    local rootOk = resizeWidgetWidth(
        tree.contentRoot,
        geometry.contentWidth,
        false
    )

    local canvas21Ok = resizeWidgetWidth(
        tree.canvas21,
        inventoryCanvasWidth,
        true
    )

    local targetColumns = nil
    local additionalGridWidth = 0.0
    local gridOk = false

    if tree.virtualGrid ~= nil then
        local gridController =
            safe(function() return tree.virtualGrid.logicController end) or
            safe(function() return tree.virtualGrid:GetController() end)

        local slotSize = gridController ~= nil and
            safe(function() return gridController.slotSize end) or nil
        local slotWidth = slotSize ~= nil and slotSize.X or 222.0

        local availableWidth = math.max(
            0.0,
            geometry.contentWidth - VANILLA_CONTENT_WIDTH
        )

        local additionalColumns = math.floor(
            availableWidth / slotWidth + 0.5
        )

        targetColumns = 12 + additionalColumns
        additionalGridWidth = additionalColumns * slotWidth

        if gridController ~= nil then
            gridOk = pcall(function()
                gridController.width = targetColumns
                tree.virtualGrid:SetSize(
                    1800.0 + additionalGridWidth,
                    1800.0
                )
                tree.virtualGrid:FlagForVisualInvalidation()
            end)
        end
    end

    -- Always write the derived widths, including at 0% spread. The pre-feature
    -- code only touched these widgets when ultrawide columns were added; the
    -- slider must also be able to restore a reused Backpack tree to its exact
    -- vanilla widths instead of relying on the controller being recreated.
    local canvas16Ok = resizeWidgetWidth(
        tree.canvas16,
        2740.0 + additionalGridWidth,
        true
    )
    local scrollingBackgroundOk = resizeWidgetWidth(
        tree.scrollingBackground,
        1800.0 + additionalGridWidth,
        true
    )
    local scrollingBackgroundShadowOk = resizeWidgetWidth(
        tree.scrollingBackgroundShadow,
        1800.0 + additionalGridWidth,
        true
    )
    local scrollCacheWidgetOk = resizeWidgetWidth(
        tree.scrollCacheWidget,
        2720.0 + additionalGridWidth,
        true
    )
    local scrollAreaOk = resizeWidgetWidth(
        tree.scrollArea,
        2720.0 + additionalGridWidth,
        true
    )
    local scrollCacheImageOk = resizeWidgetWidth(
        tree.scrollCacheImage,
        2740.0 + additionalGridWidth,
        true
    )

    local dropdownLeft = extendLegacy21x9Value(
        2879.0, 4146.0, geometry
    )

    local dropdownOk = false
    if tree.dropdownContainer ~= nil then
        dropdownOk = pcall(function()
            tree.dropdownContainer:SetMargin(
                dropdownLeft,
                188.0,
                0.0,
                0.0
            )
            tree.dropdownContainer:FlagForVisualInvalidation()
        end)
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("BACKPACK layout BEGIN: " .. tostring(reason))
        writeDebugLog(string.format(
            "geometry screenWidth=%.2f uiSpread=%d%% uiWidth=%.2f uiExtra=%.2f | inventoryCanvasWidth=%.2f",
            geometry.screenContentWidth,
            geometry.uiSpreadPercent,
            geometry.contentWidth,
            geometry.extraWidth,
            inventoryCanvasWidth
        ))
        writeDebugLog(string.format(
            "direct paths: root=%s canvas21=%s inventoryWrapper=%s canvas16=%s scroller=%s grid=%s dropdown=%s",
            widgetName(tree.contentRoot),
            widgetName(tree.canvas21),
            widgetName(tree.inventoryWrapper),
            widgetName(tree.canvas16),
            widgetName(tree.scrollerWrapper),
            widgetName(tree.virtualGrid),
            widgetName(tree.dropdownContainer)
        ))
        writeDebugLog(string.format(
            "grid: columns=%s extraWidth=%.2f mutation=%s",
            tostring(targetColumns),
            additionalGridWidth,
            tostring(gridOk)
        ))
        writeDebugLog(string.format(
            "mutations: root=%s canvas21=%s canvas16=%s bg=%s shadow=%s cache=%s scrollArea=%s cacheImage=%s dropdown=%s dropdownLeft=%.2f",
            tostring(rootOk),
            tostring(canvas21Ok),
            tostring(canvas16Ok),
            tostring(scrollingBackgroundOk),
            tostring(scrollingBackgroundShadowOk),
            tostring(scrollCacheWidgetOk),
            tostring(scrollAreaOk),
            tostring(scrollCacheImageOk),
            tostring(dropdownOk),
            dropdownLeft
        ))
        writeDebugLog("BACKPACK layout END")
    end

    return rootOk and gridOk
end

local function positionBackpackSearchDirect(controller, reason)
    if controller == nil then return false end

    local geometry = getTargetGeometry()
    if geometry == nil then return false end

    local tree = resolveBackpackTree()
    if tree == nil or tree.canvas21 == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "BACKPACK search aborted: Backpack direct tree unavailable"
            )
        end
        return false
    end

    local panel25 = directChild(
        tree.canvas21, 2, "inkVerticalPanelWidget25"
    )
    local filterButtons = directChild(
        panel25, 1, "filter_buttons"
    )
    local searchContainer = directChild(
        panel25, 2, "searchContainer"
    )
    local dropdownButton8 = directChild(
        filterButtons, 1, "dropdownButton8"
    )

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("BACKPACK search BEGIN: " .. tostring(reason))
        writeDebugLog(string.format(
            "direct path probe: panel25=%s filter_buttons=%s searchContainer=%s dropdownButton8=%s",
            widgetName(panel25),
            widgetName(filterButtons),
            widgetName(searchContainer),
            widgetName(dropdownButton8)
        ))
    end

    if panel25 == nil or filterButtons == nil or
       searchContainer == nil or dropdownButton8 == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "BACKPACK search skipped: exact modded path is not fully available"
            )
            writeDebugLog("BACKPACK search END")
        end
        return false
    end

    local ok = pcall(function()
        -- dropdownButton8 is currently child [1] of filter_buttons.
        -- Insert searchContainer immediately before it.
        searchContainer:Reparent(filterButtons, 1)
        searchContainer:SetMargin(0.0, 0.0, 0.0, 0.0)
        searchContainer:SetSize(620.0, 80.0)
        searchContainer:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "BACKPACK search mutation=%s | reparent before dropdownButton8, size=620x80",
            tostring(ok)
        ))
        writeDebugLog("BACKPACK search END")
    end

    return ok
end

-- ---------------------------------------------------------------------------
-- CRAFTING
--
-- Exact tree:
--
-- Root[0]/Root[0]
-- ├─ tabs[0]
-- ├─ craftingPanel[1]
-- │  └─ inkCanvasWidget2[0]
-- │     ├─ leftContainer[1]
-- │     │  └─ list_holder[2]
-- │     │     ├─ gridFrame[1]
-- │     │     └─ cache[2]
-- │     │        └─ scroll_area[0]
-- │     │           └─ virtualListContainer[0]
-- │     └─ inkCanvasWidget7[2]
-- ├─ upgradingPanel[2]
-- ├─ buttonHintContainer[3]
-- └─ tooltipContainer[4]
--
-- Apply geometry BEFORE CraftingMainGameController.OnInitialize. The old
-- implementation resized after initialization and needed a delayed grid
-- rebuild. The final widget sizes survive pre-initialize application, but the
-- virtual list still caches its data layout later; rebuild its source exactly
-- once when the virtual-list controller/data view become ready.
--
-- No recursive scans.
-- No hint mutation.
-- No Right_fluff mutation.
-- No delayed layout/retry.
-- ---------------------------------------------------------------------------

local function resolveCraftingTree()
    local _, _, contentRoot = getMenuContentRoot()
    if contentRoot == nil then return nil end

    -- Exact structural signature for Crafting.
    local tabs = directChild(contentRoot, 0, "tabs")
    local craftingPanel = directChild(contentRoot, 1, "craftingPanel")
    local upgradingPanel = directChild(contentRoot, 2, "upgradingPanel")
    local buttonHintContainer = directChild(
        contentRoot, 3, "buttonHintContainer"
    )

    if tabs == nil or craftingPanel == nil or
       upgradingPanel == nil or buttonHintContainer == nil then
        return nil
    end

    local panelCanvas = directChild(
        craftingPanel, 0, "inkCanvasWidget2"
    )
    local leftContainer = directChild(
        panelCanvas, 1, "leftContainer"
    )
    local listHolder = directChild(
        leftContainer, 2, "list_holder"
    )
    local gridFrame = directChild(
        listHolder, 1, "gridFrame"
    )
    local cache = directChild(
        listHolder, 2, "cache"
    )
    local scrollArea = directChild(
        cache, 0, "scroll_area"
    )
    local virtualList = directChild(
        scrollArea, 0, "virtualListContainer"
    )
    local detailsCanvas = directChild(
        panelCanvas, 2, "inkCanvasWidget7"
    )

    if panelCanvas == nil or leftContainer == nil or
       listHolder == nil or gridFrame == nil or cache == nil or
       scrollArea == nil or virtualList == nil or detailsCanvas == nil then
        return nil
    end

    return {
        contentRoot = contentRoot,
        tabs = tabs,
        craftingPanel = craftingPanel,
        upgradingPanel = upgradingPanel,
        buttonHintContainer = buttonHintContainer,
        panelCanvas = panelCanvas,
        leftContainer = leftContainer,
        listHolder = listHolder,
        gridFrame = gridFrame,
        cache = cache,
        scrollArea = scrollArea,
        virtualList = virtualList,
        detailsCanvas = detailsCanvas
    }
end

local function setWidgetSizeExact(widget, width, height)
    if widget == nil then return false end

    return pcall(function()
        widget:SetSize(width, height)
        widget:FlagForVisualInvalidation()
    end)
end

local function applyCraftingLayoutDirect(controller, reason)
    disablePillars("crafting " .. tostring(reason))

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil or controller == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("CRAFTING aborted: geometry/controller unavailable")
        end
        return false
    end

    local tree = resolveCraftingTree()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "CRAFTING aborted: exact Root/Root/craftingPanel signature not found"
            )
        end
        return false
    end

    local extraWidth = math.max(
        0.0,
        geometry.contentWidth - VANILLA_CONTENT_WIDTH
    )
    -- The validated full-spread layout adds one extra 220-wide cell beyond
    -- the raw ultrawide extension. Fade that bonus cell with UI Spread so
    -- 0% returns to the authored 1350-wide vanilla recipe viewport while
    -- 100% remains exactly identical to v2.3.0.
    local gridWidth = 1350.0 + extraWidth + 220.0 * geometry.uiSpread
    local listHolderWidth = gridWidth - 200.0
    local detailsLeft = 1435.0 + extraWidth

    local rootOk = setWidgetSizeExact(
        tree.contentRoot,
        geometry.contentWidth,
        REFERENCE_HEIGHT
    )
    local listHolderOk = setWidgetSizeExact(
        tree.listHolder,
        listHolderWidth,
        1400.0
    )
    local gridFrameOk = setWidgetSizeExact(
        tree.gridFrame,
        gridWidth + 2.0,
        1520.0
    )
    local cacheOk = setWidgetSizeExact(
        tree.cache,
        gridWidth,
        1400.0
    )
    local scrollAreaOk = setWidgetSizeExact(
        tree.scrollArea,
        gridWidth,
        1400.0
    )
    local virtualListOk = setWidgetSizeExact(
        tree.virtualList,
        gridWidth,
        1400.0
    )

    local detailsOk = false
    local currentDetailsMargin = safe(function()
        return tree.detailsCanvas:GetMargin()
    end)

    if currentDetailsMargin ~= nil then
        detailsOk = pcall(function()
            tree.detailsCanvas:SetMargin(
                detailsLeft,
                currentDetailsMargin.top,
                currentDetailsMargin.right,
                currentDetailsMargin.bottom
            )
            tree.detailsCanvas:FlagForVisualInvalidation()
        end)
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("CRAFTING layout BEGIN: " .. tostring(reason))
        writeDebugLog(string.format(
            "geometry contentWidth=%.2f extra=%.2f gridWidth=%.2f listHolderWidth=%.2f detailsLeft=%.2f",
            geometry.contentWidth,
            extraWidth,
            gridWidth,
            listHolderWidth,
            detailsLeft
        ))
        writeDebugLog(string.format(
            "direct paths: root=%s tabs=%s craftingPanel=%s panelCanvas=%s leftContainer=%s listHolder=%s gridFrame=%s cache=%s scrollArea=%s virtualList=%s details=%s hints=%s",
            widgetName(tree.contentRoot),
            widgetName(tree.tabs),
            widgetName(tree.craftingPanel),
            widgetName(tree.panelCanvas),
            widgetName(tree.leftContainer),
            widgetName(tree.listHolder),
            widgetName(tree.gridFrame),
            widgetName(tree.cache),
            widgetName(tree.scrollArea),
            widgetName(tree.virtualList),
            widgetName(tree.detailsCanvas),
            widgetName(tree.buttonHintContainer)
        ))
        writeDebugLog(string.format(
            "mutations: root=%s listHolder=%s gridFrame=%s cache=%s scrollArea=%s virtualList=%s details=%s",
            tostring(rootOk),
            tostring(listHolderOk),
            tostring(gridFrameOk),
            tostring(cacheOk),
            tostring(scrollAreaOk),
            tostring(virtualListOk),
            tostring(detailsOk)
        ))
        writeDebugLog(string.format(
            "AFTER: root=%s listHolder=%s gridFrame=%s cache=%s scrollArea=%s virtualList=%s detailsMargin=%s",
            debugWidgetSize(tree.contentRoot),
            debugWidgetSize(tree.listHolder),
            debugWidgetSize(tree.gridFrame),
            debugWidgetSize(tree.cache),
            debugWidgetSize(tree.scrollArea),
            debugWidgetSize(tree.virtualList),
            debugWidgetMargin(tree.detailsCanvas)
        ))
        writeDebugLog(
            "CRAFTING hints intentionally untouched; widened Root carries buttonHintContainer[3]"
        )
        writeDebugLog("CRAFTING layout END")
    end

    return rootOk and listHolderOk and gridFrameOk and
        cacheOk and scrollAreaOk and virtualListOk and detailsOk
end

local function tryFinalizeCraftingGridRebuild(controller)
    if controller == nil then return false end

    local tree = resolveCraftingTree()
    if tree == nil or tree.craftingPanel == nil then
        return false
    end

    local panelController =
        safe(function() return tree.craftingPanel:GetController() end) or
        safe(function() return tree.craftingPanel.logicController end)

    if panelController == nil then
        return false
    end

    local virtualListController = safe(function()
        return panelController.virtualListController
    end)
    local dataView = safe(function()
        return panelController.dataView
    end)
    local dataSource = safe(function()
        return panelController.dataSource
    end)

    -- This is the exact readiness condition used by the old working layout:
    -- the virtual grid controller and its existing data view must both exist.
    if virtualListController == nil or dataView == nil then
        return false
    end

    local rebuilt = pcall(function()
        virtualListController:SetSource(nil)
        virtualListController:SetSource(dataView)
    end)

    if ACTIVATE_DEBUG_LOGS then
        local panelControllerClass =
            safe(function() return panelController:GetClassName().value end) or
            "<nil>"

        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("CRAFTING grid rebuild READY")
        writeDebugLog(string.format(
            "checks=%d | panelController=%s virtualListController=true dataView=true dataSource=%s",
            pendingCraftingGridRebuildChecks,
            tostring(panelControllerClass),
            tostring(dataSource ~= nil)
        ))
        writeDebugLog(string.format(
            "SetSource(nil) -> SetSource(dataView) mutation=%s | virtualList=%s",
            tostring(rebuilt),
            debugWidgetSize(tree.virtualList)
        ))
        writeDebugLog("CRAFTING grid rebuild END")
    end

    return rebuilt
end

-- ---------------------------------------------------------------------------
-- WORLD MAP
--
-- Exact tree:
--
-- inkVirtualWindow
-- └─ Root[0]                                  <- viewport root
--    ├─ Root[0]                               <- map root
--    │  └─ Content[0]
--    │     ├─ EntityPreviewContainer[0]
--    │     │  └─ EntityPreview[0]
--    │     ├─ GPSPathContainer[1]
--    │     ├─ DistrictsRoot[2]
--    │     └─ SpawnContainer[3]
--    └─ Root[1]                               <- Hub/menu shell
--
-- Deliberately touch ONLY the map branch. The sibling Hub shell is already
-- handled by the validated shared Hub code.
--
-- Ink mutations:
--   viewport Root[0]                  -> aspect*1080 x 1080
--   map Root[0]/Root[0]               -> contentWidth x 2160
--   EntityPreviewContainer[0]         -> viewportWidth x 1080
--   EntityPreview[0]                  -> viewportWidth x 1080
--   SpawnContainer[3]                 -> viewportWidth x 1080
--   GPSPathContainer[1]               -> margins halfExtra / halfExtra
--   DistrictsRoot[2]                  -> margins halfExtra / halfExtra
--
-- Camera:
--   gameuiWorldMapGameObject.virtual_camera_comp
--   -> aspect*720 x 720, matching display aspect.
--
-- No recursive scans.
-- No applyMenuShellLayout().
-- One exact OnEntityAttached layout pass.
-- No delayed 0.75 s layout pass.
-- ---------------------------------------------------------------------------

local function resolveWorldMapTree(controller)
    if controller == nil then return nil end

    -- Primary path: preserve the validated controller-root implementation.
    -- Some systems expose the controller root correctly but return nil from
    -- GetParentWidget() even though the same widget is visibly attached in
    -- inkMenuLayer. In that case, fall back to the exact global layer path
    -- instead of waiting forever for a backlink that may never appear.
    local mapRoot = safe(function()
        return controller:GetRootWidget()
    end)
    local viewportRoot = mapRoot ~= nil and safe(function()
        return mapRoot:GetParentWidget()
    end) or nil
    local resolutionSource = "controller parent"

    if mapRoot == nil or viewportRoot == nil then
        local _, globalViewportRoot, globalMapRoot = getMenuContentRoot()
        if globalViewportRoot == nil or globalMapRoot == nil then
            return nil
        end

        viewportRoot = globalViewportRoot
        mapRoot = globalMapRoot
        resolutionSource = "global inkMenuLayer fallback"
    end

    -- Exact map-branch signature below the resolved map root.
    local content = directChild(mapRoot, 0, "Content")
    if content == nil then return nil end

    local entityPreviewContainer = directChild(
        content, 0, "EntityPreviewContainer"
    )
    local entityPreview = directChild(
        entityPreviewContainer, 0, "EntityPreview"
    )
    local gpsPathContainer = directChild(
        content, 1, "GPSPathContainer"
    )
    local districtsRoot = directChild(
        content, 2, "DistrictsRoot"
    )
    local spawnContainer = directChild(
        content, 3, "SpawnContainer"
    )

    if entityPreviewContainer == nil or entityPreview == nil or
       gpsPathContainer == nil or districtsRoot == nil or
       spawnContainer == nil then
        return nil
    end

    return {
        viewportRoot = viewportRoot,
        mapRoot = mapRoot,
        content = content,
        entityPreviewContainer = entityPreviewContainer,
        entityPreview = entityPreview,
        gpsPathContainer = gpsPathContainer,
        districtsRoot = districtsRoot,
        spawnContainer = spawnContainer,
        resolutionSource = resolutionSource
    }
end

local function setWorldMapSizeAndZeroMargin(widget, width, height)
    if widget == nil then return false end

    return pcall(function()
        widget:SetSize(width, height)
        widget:SetMargin(0.0, 0.0, 0.0, 0.0)
        widget:FlagForVisualInvalidation()
    end)
end

local function applyWorldMapLayoutDirect(controller, reason)
    local logThis = ACTIVATE_DEBUG_LOGS and reason ~= nil

    -- World Map is a functional menu surface, not merely a fullscreen
    -- background. Its viewport, map content and HUD containers therefore
    -- follow UI Spread just like the other menus.
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil or controller == nil then
        if logThis then
            writeDebugLog(
                "WORLD MAP aborted: geometry/controller unavailable"
            )
        end
        return false
    end

    local tree = resolveWorldMapTree(controller)
    if tree == nil then
        if logThis then
            writeDebugLog(
                "WORLD MAP aborted: controller root / exact Content signature not found"
            )
        end
        return false
    end

    local viewportWidth =
        geometry.aspect * WORLD_MAP_VIEWPORT_HEIGHT
    local districtInset =
        (geometry.contentWidth - VANILLA_CONTENT_WIDTH) * 0.5

    local viewportOk = setWorldMapSizeAndZeroMargin(
        tree.viewportRoot,
        viewportWidth,
        WORLD_MAP_VIEWPORT_HEIGHT
    )
    local mapRootOk = setWorldMapSizeAndZeroMargin(
        tree.mapRoot,
        geometry.contentWidth,
        REFERENCE_HEIGHT
    )
    local previewContainerOk = setWorldMapSizeAndZeroMargin(
        tree.entityPreviewContainer,
        viewportWidth,
        WORLD_MAP_VIEWPORT_HEIGHT
    )
    local previewOk = setWorldMapSizeAndZeroMargin(
        tree.entityPreview,
        viewportWidth,
        WORLD_MAP_VIEWPORT_HEIGHT
    )
    local spawnOk = setWorldMapSizeAndZeroMargin(
        tree.spawnContainer,
        viewportWidth,
        WORLD_MAP_VIEWPORT_HEIGHT
    )

    local districtsOk = pcall(function()
        tree.districtsRoot:SetMargin(
            districtInset,
            0.0,
            districtInset,
            0.0
        )
        tree.districtsRoot:FlagForVisualInvalidation()
    end)

    local gpsOk = pcall(function()
        tree.gpsPathContainer:SetMargin(
            districtInset,
            0.0,
            districtInset,
            0.0
        )
        tree.gpsPathContainer:FlagForVisualInvalidation()
    end)

    if logThis then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("WORLD MAP layout BEGIN: " .. tostring(reason))
        writeDebugLog(string.format(
            "geometry aspect=%.6f contentWidth=%.2f viewportWidth=%.2f districtInset=%.2f | resolver=%s",
            geometry.aspect,
            geometry.contentWidth,
            viewportWidth,
            districtInset,
            tostring(tree.resolutionSource)
        ))
        writeDebugLog(string.format(
            "direct paths: viewportRoot=%s mapRoot=%s content=%s previewContainer=%s preview=%s gps=%s districts=%s spawn=%s",
            widgetName(tree.viewportRoot),
            widgetName(tree.mapRoot),
            widgetName(tree.content),
            widgetName(tree.entityPreviewContainer),
            widgetName(tree.entityPreview),
            widgetName(tree.gpsPathContainer),
            widgetName(tree.districtsRoot),
            widgetName(tree.spawnContainer)
        ))
        writeDebugLog(string.format(
            "mutations: viewport=%s mapRoot=%s previewContainer=%s preview=%s spawn=%s districts=%s gps=%s",
            tostring(viewportOk),
            tostring(mapRootOk),
            tostring(previewContainerOk),
            tostring(previewOk),
            tostring(spawnOk),
            tostring(districtsOk),
            tostring(gpsOk)
        ))
        writeDebugLog(string.format(
            "AFTER sizes: viewport=%s mapRoot=%s previewContainer=%s preview=%s spawn=%s",
            debugWidgetSize(tree.viewportRoot),
            debugWidgetSize(tree.mapRoot),
            debugWidgetSize(tree.entityPreviewContainer),
            debugWidgetSize(tree.entityPreview),
            debugWidgetSize(tree.spawnContainer)
        ))
        writeDebugLog(string.format(
            "AFTER margins: districts=%s gps=%s",
            debugWidgetMargin(tree.districtsRoot),
            debugWidgetMargin(tree.gpsPathContainer)
        ))
        writeDebugLog(
            "WORLD MAP Hub shell intentionally untouched by map-specific layout"
        )
        writeDebugLog("WORLD MAP layout END")
    end

    return viewportOk and mapRootOk and
        previewContainerOk and previewOk and spawnOk and
        districtsOk and gpsOk
end

local function hasWorldMapVirtualCamera(gameObject)
    if gameObject == nil then return false end

    local camera = safe(function()
        return gameObject:FindComponentByName("virtual_camera_comp")
    end)

    return camera ~= nil
end

local function configureWorldMapCameraDirect(gameObject, reason)
    -- Match the virtual camera to the same logical UI aspect used by the map
    -- viewport. At 0% this is 16:9 even on a physical 32:9 display.
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil or gameObject == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "WORLD MAP camera aborted: geometry/gameObject unavailable"
            )
        end
        return false
    end

    local camera = safe(function()
        return gameObject:FindComponentByName("virtual_camera_comp")
    end)

    if camera == nil then
        return false
    end

    local cameraWidth = math.floor(
        geometry.aspect * WORLD_MAP_CAMERA_HEIGHT + 0.5
    )

    local ok = pcall(function()
        camera.resolutionWidth = cameraWidth
        camera.resolutionHeight = WORLD_MAP_CAMERA_HEIGHT
        camera.aspectRatio = geometry.aspect
    end)

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("WORLD MAP camera: " .. tostring(reason))
        writeDebugLog(string.format(
            "camera target=%dx%d aspect=%.6f mutation=%s",
            cameraWidth,
            WORLD_MAP_CAMERA_HEIGHT,
            geometry.aspect,
            tostring(ok)
        ))
    end

    return ok
end

-- ---------------------------------------------------------------------------
-- SHARED MENU BUTTON HINTS
--
-- Strict menuName routing. No multi-index probing:
--
--   cyberware_equip  -> Root[0]/Root[0]/button_hints[1]
--   inventory_screen -> Root[0]/Root[0]/button_hints[2]
--   temp_stats       -> Root[0]/Root[0]/button_hints[5]
--   quest_log        -> Root[0]/Root[0]/button_hints[2]
--   codex            -> Root[0]/Root[0]/button_hints[2]
--
-- backpack and crafting_main deliberately receive no hint mutation because
-- their own content Root is resized to the active UI Spread width.
--
-- Ripperdoc is intentionally not guessed. If a future layout needs it, add
-- only a validated menu/scenario identifier and an explicit child index.
-- ---------------------------------------------------------------------------

local adjustedButtonHintWidgets = setmetatable({}, { __mode = "k" })

local function shiftButtonHintsAtIndex(contentRoot, childIndex, geometry, reason)
    local buttonHints = safe(function()
        return contentRoot:GetWidget(childIndex)
    end)

    local previousState = buttonHints ~= nil and
        adjustedButtonHintWidgets[buttonHints] or nil

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "HINT target child[%d]: name=%s size=%s margin=%s hasBaseState=%s",
            childIndex,
            widgetName(buttonHints),
            debugWidgetSize(buttonHints),
            debugWidgetMargin(buttonHints),
            tostring(previousState ~= nil)
        ))
    end

    if buttonHints == nil or widgetName(buttonHints) ~= "button_hints" then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(string.format(
                "HINT child[%d] rejected: expected button_hints",
                childIndex
            ))
        end
        return false
    end

    local currentMargin = safe(function()
        return buttonHints:GetMargin()
    end)

    if currentMargin == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(string.format(
                "HINT child[%d] aborted: unable to read margin",
                childIndex
            ))
        end
        return false
    end

    -- UI Spread can change while Ink reuses the same widget instance. Preserve
    -- the first observed authored margin as the immutable base, then derive an
    -- absolute target from that base every time. Never subtract from an already
    -- shifted margin, or changing 100 -> 0 -> 50 would accumulate offsets.
    local base = previousState ~= nil and previousState.base or {
        left = currentMargin.left,
        top = currentMargin.top,
        right = currentMargin.right,
        bottom = currentMargin.bottom
    }

    local targetRight = base.right - geometry.halfExtra

    if math.abs(currentMargin.right - targetRight) <= 0.05 and
       math.abs(currentMargin.left - base.left) <= 0.05 and
       math.abs(currentMargin.top - base.top) <= 0.05 and
       math.abs(currentMargin.bottom - base.bottom) <= 0.05 then
        adjustedButtonHintWidgets[buttonHints] = {
            base = base,
            appliedHalfExtra = geometry.halfExtra
        }
        return true
    end

    local ok = pcall(function()
        buttonHints:SetMargin(
            base.left,
            base.top,
            targetRight,
            base.bottom
        )
    end)

    if ok then
        adjustedButtonHintWidgets[buttonHints] = {
            base = base,
            appliedHalfExtra = geometry.halfExtra
        }
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "HINT child[%d] MATCH (%s) | halfExtra=%.2f baseRight=%.2f targetRight=%.2f mutation=%s AFTER=%s",
            childIndex,
            tostring(reason),
            geometry.halfExtra,
            base.right,
            targetRight,
            tostring(ok),
            debugWidgetMargin(buttonHints)
        ))
    end

    return ok
end

local function applySharedMenuButtonHints(reason)
    disablePillars("strict menu hints " .. tostring(reason))

    local menuName = pendingHubMenuName

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("STRICT HINTS event: " .. tostring(reason))
        writeDebugLog("pending Hub menuName=" .. tostring(menuName))
    end

    -- No Hub menu is pending: this is typically the Hub shell's own ButtonHints.
    if menuName == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("STRICT HINTS skipped: no pending content menuName")
        end
        return
    end

    -- Consume the menu once. A later ButtonHints event must never inherit a
    -- stale menu name from the previous screen.
    pendingHubMenuName = nil

    if naturalHintMenus[menuName] then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "STRICT HINTS menu=" .. tostring(menuName) ..
                " -> intentional no-op (Root widened naturally)"
            )
        end
        return
    end

    local childIndex = buttonHintMenuRules[menuName]
    if childIndex == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "STRICT HINTS menu=" .. tostring(menuName) ..
                " -> no explicit rule; no mutation"
            )
        end
        return
    end

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("STRICT HINTS aborted: target geometry unavailable")
        end
        return
    end

    local _, _, contentRoot = getMenuContentRoot()
    if contentRoot == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("STRICT HINTS aborted: content Root unavailable")
        end
        return
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "STRICT HINTS route: menu=%s -> child[%d] | uiSpread=%d%% uiWidth=%.2f halfExtra=%.2f | contentRoot=%s children=%s",
            tostring(menuName),
            childIndex,
            geometry.uiSpreadPercent,
            geometry.contentWidth,
            geometry.halfExtra,
            debugWidgetSize(contentRoot),
            tostring(safe(function() return contentRoot:GetNumChildren() end))
        ))
    end

    local ok = shiftButtonHintsAtIndex(
        contentRoot,
        childIndex,
        geometry,
        "menuName=" .. tostring(menuName)
    )

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(
            "STRICT HINTS result menu=" .. tostring(menuName) ..
            " mutation=" .. tostring(ok)
        )
    end
end

-- ---------------------------------------------------------------------------
-- SAVE / LOAD
--
-- Load and Save share the same visual treatment but not the same direct child
-- indices. Both layouts are validated explicitly; there is no recursive scan
-- and no loose fallback.
--
-- LOAD (validated pre-game and in-game):
--   content Root = Root[0] pre-game / Root[1] in-game
--   holder[1]
--   button_hints[4]
--   fluff[5]
--     ├─ fluffs[0]
--     │  ├─ fluff1[0]   <- upper-left edge decoration
--     │  ├─ fluff4[1]   <- leave vanilla
--     │  ├─ fluff5[2]   <- left edge decoration
--     │  ├─ fluff7[3]   <- leave vanilla
--     │  └─ fluff6[4]   <- leave vanilla
--     └─ line[1]
--
-- SAVE (validated in-game):
--   content Root = Root[1]
--   holder[0]
--   fluff[1]
--     ├─ fluffs[0]
--     │  ├─ fluff2[0]   <- leave vanilla
--     │  ├─ fluff1[1]   <- upper-left edge decoration
--     │  ├─ fluff3[2]   <- leave vanilla
--     │  ├─ fluff4[3]   <- leave vanilla
--     │  ├─ fluff5[4]   <- left edge decoration
--     │  ├─ fluff7[5]   <- leave vanilla
--     │  └─ fluff6[6]   <- leave vanilla
--     └─ line[1]
--   button_hints[3]
--
-- Only fluff1 + fluff5 are moved. The historical implementation shifted the
-- entire fluffs container and then counter-shifted the centered decorations;
-- targeting the two real edge widgets directly is both simpler and safer.
-- ---------------------------------------------------------------------------

local function resolveSaveLoadTreeExact()
    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return nil end

    local outerRoot = directChild(virtualWindow, 0, "Root")
    if outerRoot == nil then return nil end

    -- Prefer the in-game content slot, then the pre-game slot. Within each
    -- slot, test the two proven structural signatures independently.
    for _, rootIndex in ipairs({ 1, 0 }) do
        local contentRoot = directChild(outerRoot, rootIndex, "Root")
        if contentRoot ~= nil then
            -- LOAD signature.
            local loadHolder = directChild(contentRoot, 1, "holder")
            local loadButtonHints = directChild(contentRoot, 4, "button_hints")
            local loadFluff = directChild(contentRoot, 5, "fluff")
            local loadFluffs = directChild(loadFluff, 0, "fluffs")
            local loadLine = directChild(loadFluff, 1, "line")
            local loadFluff1 = directChild(loadFluffs, 0, "fluff1")
            local loadFluff5 = directChild(loadFluffs, 2, "fluff5")

            if loadHolder ~= nil and loadButtonHints ~= nil and
               loadFluff ~= nil and loadFluffs ~= nil and
               loadLine ~= nil and loadFluff1 ~= nil and
               loadFluff5 ~= nil then
                return {
                    layoutKind = "LOAD",
                    rootIndex = rootIndex,
                    contentRoot = contentRoot,
                    hintIndex = 4,
                    buttonHints = loadButtonHints,
                    fluff1 = loadFluff1,
                    fluff5 = loadFluff5,
                    line = loadLine
                }
            end

            -- SAVE signature. Current runtime evidence exists for the in-game
            -- Root[1] tree. Keeping it as a strict signature means a future
            -- structural change fails closed instead of mutating the wrong UI.
            local saveHolder = directChild(contentRoot, 0, "holder")
            local saveFluff = directChild(contentRoot, 1, "fluff")
            local saveButtonHints = directChild(contentRoot, 3, "button_hints")
            local saveFluffs = directChild(saveFluff, 0, "fluffs")
            local saveLine = directChild(saveFluff, 1, "line")
            local saveFluff1 = directChild(saveFluffs, 1, "fluff1")
            local saveFluff5 = directChild(saveFluffs, 4, "fluff5")

            if saveHolder ~= nil and saveFluff ~= nil and
               saveButtonHints ~= nil and saveFluffs ~= nil and
               saveLine ~= nil and saveFluff1 ~= nil and
               saveFluff5 ~= nil then
                return {
                    layoutKind = "SAVE",
                    rootIndex = rootIndex,
                    contentRoot = contentRoot,
                    hintIndex = 3,
                    buttonHints = saveButtonHints,
                    fluff1 = saveFluff1,
                    fluff5 = saveFluff5,
                    line = saveLine
                }
            end
        end
    end

    return nil
end

local function applySaveLoadExact(reason)
    disablePillars("save/load " .. tostring(reason))

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then return false end

    local tree = resolveSaveLoadTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "SAVE/LOAD exact path unavailable: " .. tostring(reason)
            )
        end
        return false
    end

    -- Both validated layouts author the two edge decorations at the same
    -- margins, so one geometry calculation applies to Save and Load.
    local fluff1Left = 6.0 - geometry.halfExtra
    local fluff5Left = -200.0 - geometry.halfExtra

    local fluff1Ok = pcall(function()
        tree.fluff1:SetMargin(fluff1Left, 78.0, 0.0, 0.0)
    end)

    local fluff5Ok = pcall(function()
        tree.fluff5:SetMargin(fluff5Left, 847.0, 0.0, 0.0)
    end)

    -- line[1] is a TopFillHorizontaly decoration whose visible extent is not
    -- symmetric around its raw margins. Use the authored 16:9 geometry and
    -- the user-validated 21:9 geometry as calibration anchors.
    --
    -- Authored 16:9 margins:  left=100,  right=200
    -- Validated 21:9 margins:  left=-560, right=-1160
    --
    -- 16:9..21:9 interpolates continuously. Beyond 21:9, each side extends
    -- by half of the additional content width, preserving the validated 21:9
    -- visual alignment while following wider physical edges through 32:9.
    local beyond21x9Half = math.max(
        0.0,
        geometry.contentWidth - LEGACY_21X9_CONTENT_WIDTH
    ) * 0.5

    local lineLeft = interpolateToLegacy21x9(
        100.0, -560.0, geometry
    ) - beyond21x9Half
    local lineRight = interpolateToLegacy21x9(
        200.0, -1160.0, geometry
    ) - beyond21x9Half

    local lineOk = pcall(function()
        tree.line:SetMargin(
            lineLeft,
            155.0,
            lineRight,
            0.0
        )
    end)

    -- Reuse the same idempotent hint shifter as Hub/Flatlined/etc.; only the
    -- direct child index differs between the proven Load and Save trees.
    local hintsOk = shiftButtonHintsAtIndex(
        tree.contentRoot,
        tree.hintIndex,
        geometry,
        "SAVE/LOAD " .. tostring(reason)
    )

    local success = fluff1Ok and fluff5Ok and lineOk and hintsOk

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("SAVE/LOAD applied: " .. tostring(reason))
        writeDebugLog(string.format(
            "layout=%s contentRoot=Root[%d] hintIndex=%d contentWidth=%.2f halfExtra=%.2f success=%s",
            tree.layoutKind,
            tree.rootIndex,
            tree.hintIndex,
            geometry.contentWidth,
            geometry.halfExtra,
            tostring(success)
        ))
        writeDebugLog(string.format(
            "fluff1 left=%.2f mutation=%s after=%s",
            fluff1Left,
            tostring(fluff1Ok),
            debugWidgetMargin(tree.fluff1)
        ))
        writeDebugLog(string.format(
            "fluff5 left=%.2f mutation=%s after=%s",
            fluff5Left,
            tostring(fluff5Ok),
            debugWidgetMargin(tree.fluff5)
        ))
        writeDebugLog(string.format(
            "line margins=[%.2f,155.00,%.2f,0] mutation=%s after=%s | hints=%s",
            lineLeft,
            lineRight,
            tostring(lineOk),
            debugWidgetMargin(tree.line),
            tostring(hintsOk)
        ))
    end

    return success
end

-- ---------------------------------------------------------------------------
-- STORAGE / STASH
--
-- Exact runtime tree captured from MenuScenario_Storage:
-- inkMenuLayer/inkVirtualWindow
-- └─ Root[0]
--    ├─ Root[0]  <- fullscreen vendor/stash content, authored 3840x2160
--    │  ├─ wrapper[0]/wrapper[0]
--    │  │  ├─ playerPanel[0]
--    │  │  └─ vendorPanel[1]
--    │  ├─ dropdownContainer[1]
--    │  └─ button_hints[2]
--    └─ Root[1]  <- top vendor/stash header/fluff
--
-- The validated responsive layout uses 224-unit item slots: 6 columns at
-- 16:9, 10 at 21:9, and 15 at 32:9. Keep that proven responsive model, but
-- resolve every widget by exact index instead of scanning the tree.
--
-- Historical geometry retries are intentionally NOT carried over. Runtime
-- validation retained only one narrow correction: after both native inventories
-- populate, replay the CURRENT filter callbacks once so the virtual
-- grids rebuild their wrapping against the widened geometry.
-- ---------------------------------------------------------------------------

local function resolveStashTreeExact()
    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return nil end

    local outerRoot = directChild(virtualWindow, 0, "Root")
    local contentRoot = directChild(outerRoot, 0, "Root")
    local headerRoot = directChild(outerRoot, 1, "Root")
    if contentRoot == nil or headerRoot == nil then return nil end

    local wrapper = directChild(contentRoot, 0, "wrapper")
    local innerWrapper = directChild(wrapper, 0, "wrapper")
    local playerPanel = directChild(innerWrapper, 0, "playerPanel")
    local vendorPanel = directChild(innerWrapper, 1, "vendorPanel")
    local dropdownContainer = directChild(contentRoot, 1, "dropdownContainer")
    local buttonHints = directChild(contentRoot, 2, "button_hints")
    if playerPanel == nil or vendorPanel == nil or
       dropdownContainer == nil or buttonHints == nil then
        return nil
    end

    local playerHeader = directChild(playerPanel, 0, "playerHeader")
    local playerFilterRow = directChild(playerHeader, 2, "inkHorizontalPanelWidget2")
    local playerFilters = directChild(playerFilterRow, 0, "filtersContainer")
    local playerSort = directChild(playerFilterRow, 1, "dropdownButton5")
    local playerSearch = directChild(playerHeader, 3, "searchContainerPlayer")
    local playerInventory = directChild(playerPanel, 1, "inventoryContainer")
    local playerCacheRT = directChild(playerInventory, 2, "inventoryCacheRT")
    local playerBackground = directChild(playerInventory, 3, "inventoryBackgroundWrapper")
    local playerBgA = directChild(playerBackground, 0, "inkImageWidget2a")
    local playerBgB = directChild(playerBackground, 1, "inkImageWidget2")
    local playerScrollCache = directChild(playerInventory, 4, "inventory_scroll_area_cache")
    local playerScroll = directChild(playerScrollCache, 0, "scroll_area")
    local playerGrid = directChild(playerScroll, 0, "player_virtualgrid")

    local vendorHeader = directChild(vendorPanel, 0, "vendorHeader")
    local vendorFilterRow = directChild(vendorHeader, 2, "inkHorizontalPanelWidget2")
    local vendorFilters = directChild(vendorFilterRow, 0, "filtersContainer")
    local vendorSort = directChild(vendorFilterRow, 1, "dropdownButton5")
    local vendorSearch = directChild(vendorHeader, 3, "searchContainerStorage")
    local vendorInventory = directChild(vendorPanel, 2, "inventoryContainer")
    local vendorScrollCache = directChild(vendorInventory, 1, "stash_scroll_area_cache")
    local vendorScroll = directChild(vendorScrollCache, 0, "scrollArea")
    local vendorGrid = directChild(vendorScroll, 0, "vendor_virtualgrid")
    local vendorCacheRT = directChild(vendorInventory, 2, "stashCacheRT")
    local vendorBackground = directChild(vendorInventory, 3, "inventoryBackgroundWrapper")
    local vendorBgA = directChild(vendorBackground, 2, "inkImageWidget2a")
    local vendorBgB = directChild(vendorBackground, 3, "inkImageWidget2")

    if playerFilters == nil or playerSort == nil or playerSearch == nil or
       playerInventory == nil or playerCacheRT == nil or playerBgA == nil or
       playerBgB == nil or playerScrollCache == nil or playerScroll == nil or
       playerGrid == nil or vendorFilters == nil or vendorSort == nil or
       vendorSearch == nil or vendorInventory == nil or vendorScrollCache == nil or
       vendorScroll == nil or vendorGrid == nil or vendorCacheRT == nil or
       vendorBgA == nil or vendorBgB == nil then
        return nil
    end

    return {
        contentRoot = contentRoot,
        headerRoot = headerRoot,
        playerPanel = playerPanel,
        vendorPanel = vendorPanel,
        playerFilters = playerFilters,
        vendorFilters = vendorFilters,
        playerSort = playerSort,
        vendorSort = vendorSort,
        playerSearch = playerSearch,
        vendorSearch = vendorSearch,
        playerInventory = playerInventory,
        vendorInventory = vendorInventory,
        playerCacheRT = playerCacheRT,
        vendorCacheRT = vendorCacheRT,
        playerBgA = playerBgA,
        playerBgB = playerBgB,
        vendorBgA = vendorBgA,
        vendorBgB = vendorBgB,
        playerScrollCache = playerScrollCache,
        vendorScrollCache = vendorScrollCache,
        playerScroll = playerScroll,
        vendorScroll = vendorScroll,
        playerGrid = playerGrid,
        vendorGrid = vendorGrid,
        dropdownContainer = dropdownContainer,
        buttonHints = buttonHints
    }
end


-- ---------------------------------------------------------------------------
-- ARCADE MINIGAMES
-- ---------------------------------------------------------------------------

-- The scenario transition itself is the primary lifecycle signal. This exact
-- shell resolver exists only as a CET hot-reload recovery path: if mods are
-- reloaded while a fullscreen arcade is already open, the entry transition has
-- already happened, so the current ArcadeMachine shell lets us restore the
-- temporary pillar policy without any game-specific controller dependency.
local function resolveArcadeMachineExact()
    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return nil end

    local outerRoot = directChild(virtualWindow, 0, "Root")
    local contentRoot = directChild(outerRoot, 0, "Root")
    local arcadeMachine = directChild(contentRoot, 0, "ArcadeMachine")
    if arcadeMachine == nil then return nil end

    return {
        virtualWindow = virtualWindow,
        outerRoot = outerRoot,
        contentRoot = contentRoot,
        arcadeMachine = arcadeMachine
    }
end

local function enterArcadePillarMode(reason)
    if arcadePillarsActive then
        return true
    end

    if not setTemporaryPillarsVisible(
        true,
        "arcade " .. tostring(reason)
    ) then
        return false
    end

    arcadePillarsActive = true

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog(
            "ARCADE scenario active; native pillars restored: " ..
            tostring(reason)
        )
    end

    return true
end

local function leaveArcadePillarMode(reason)
    if not arcadePillarsActive then
        return
    end

    setTemporaryPillarsVisible(
        false,
        "arcade " .. tostring(reason)
    )

    arcadePillarsActive = false

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(
            "ARCADE scenario ended; ultrawide pillar suppression restored: " ..
            tostring(reason)
        )
    end
end

local function getStashColumnGeometry(geometry)
    local slotWidth = 224.0
    local columnsAt16x9 = 6
    local columnsAt21x9 = 10
    local columnsAt32x9 = 15
    local widthAt16x9 = VANILLA_CONTENT_WIDTH
    local widthAt21x9 = LEGACY_21X9_CONTENT_WIDTH
    local widthAt32x9 = 7680.0

    local targetColumns
    if geometry.contentWidth < widthAt21x9 then
        local progress = math.max(0.0, math.min(
            1.0,
            (geometry.contentWidth - widthAt16x9) /
            (widthAt21x9 - widthAt16x9)
        ))
        targetColumns = columnsAt16x9 + math.floor(
            progress * (columnsAt21x9 - columnsAt16x9) + 0.5
        )
    else
        local progress = math.max(0.0, math.min(
            1.0,
            (geometry.contentWidth - widthAt21x9) /
            (widthAt32x9 - widthAt21x9)
        ))
        targetColumns = columnsAt21x9 + math.floor(
            progress * (columnsAt32x9 - columnsAt21x9) + 0.5
        )
    end

    local gridWidth = targetColumns * slotWidth
    return targetColumns, gridWidth, gridWidth + 34.0
end

local function resizeStashWidgetWidth(widget, width)
    local size = safe(function() return widget:GetSize() end)
    if size == nil then return false end
    return pcall(function()
        widget:SetSize(width, size.Y)
        widget:FlagForVisualInvalidation()
    end)
end

local function resizeStashCenteredCache(widget, width)
    local size = safe(function() return widget:GetSize() end)
    local margin = safe(function() return widget:GetMargin() end)
    if size == nil or margin == nil then return false end

    local centerOffset = margin.left - size.X * 0.5
    return pcall(function()
        widget:SetSize(width, size.Y)
        widget:SetMargin(
            width * 0.5 + centerOffset,
            margin.top,
            margin.right,
            margin.bottom
        )
        widget:FlagForVisualInvalidation()
    end)
end

local function applyStashExact(reason)
    if not stashMenuActive then return false end

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then return false end

    local tree = resolveStashTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "STASH exact path unavailable: " .. tostring(reason)
            )
        end
        return false
    end

    disablePillars("stash " .. tostring(reason))

    local columns, gridWidth, zoneWidth = getStashColumnGeometry(geometry)
    local panelInset = interpolateToLegacy21x9(0.0, 235.0, geometry)

    -- Search containers were historically tuned at 21:9 to Right alignment
    -- with margins (0,-90,1060,50). Interpolate from authored vanilla margins
    -- so 2:1 modes do not inherit the full 21:9 displacement abruptly.
    local searchTop = interpolateToLegacy21x9(4.0, -90.0, geometry)
    local searchRight = interpolateToLegacy21x9(0.0, 1060.0, geometry)
    local searchBottom = interpolateToLegacy21x9(32.0, 50.0, geometry)

    local ok, errorMessage = pcall(function()
        tree.contentRoot:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
        tree.headerRoot:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)

        local playerSize = tree.playerPanel:GetSize()
        local vendorSize = tree.vendorPanel:GetSize()
        tree.playerPanel:SetSize(zoneWidth, playerSize.Y)
        tree.vendorPanel:SetSize(zoneWidth, vendorSize.Y)
        tree.playerPanel:SetMargin(panelInset, 0.0, 0.0, 0.0)
        tree.vendorPanel:SetMargin(0.0, 0.0, -panelInset, 0.0)

        local playerInventorySize = tree.playerInventory:GetSize()
        local vendorInventorySize = tree.vendorInventory:GetSize()
        tree.playerInventory:SetSize(zoneWidth, playerInventorySize.Y)
        tree.vendorInventory:SetSize(zoneWidth, vendorInventorySize.Y)

        tree.playerFilters:SetWrappingWidgetCount(8)
        tree.vendorFilters:SetWrappingWidgetCount(8)

        tree.playerSearch:SetHAlign(inkEHorizontalAlign.Right)
        tree.vendorSearch:SetHAlign(inkEHorizontalAlign.Right)
        tree.playerSearch:SetMargin(0.0, searchTop, searchRight, searchBottom)
        tree.vendorSearch:SetMargin(0.0, searchTop, searchRight, searchBottom)

        tree.contentRoot:FlagForVisualInvalidation()
        tree.headerRoot:FlagForVisualInvalidation()
        tree.playerPanel:FlagForVisualInvalidation()
        tree.vendorPanel:FlagForVisualInvalidation()
        tree.playerInventory:FlagForVisualInvalidation()
        tree.vendorInventory:FlagForVisualInvalidation()
        tree.playerFilters:FlagForVisualInvalidation()
        tree.vendorFilters:FlagForVisualInvalidation()
        tree.playerSearch:FlagForVisualInvalidation()
        tree.vendorSearch:FlagForVisualInvalidation()
    end)

    local widthsOk = true
    for _, widget in ipairs({
        tree.playerScrollCache,
        tree.playerScroll,
        tree.playerGrid,
        tree.vendorScrollCache,
        tree.vendorScroll,
        tree.vendorGrid,
        tree.playerBgA,
        tree.playerBgB,
        tree.vendorBgA,
        tree.vendorBgB
    }) do
        widthsOk = resizeStashWidgetWidth(widget, gridWidth) and widthsOk
    end

    local playerCacheOk = resizeStashCenteredCache(tree.playerCacheRT, gridWidth)
    local vendorCacheOk = resizeStashCenteredCache(tree.vendorCacheRT, gridWidth)

    local success = ok and widthsOk and playerCacheOk and vendorCacheOk

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("STASH geometry applied: " .. tostring(reason))
        writeDebugLog(string.format(
            "contentWidth=%.2f columns=%d gridWidth=%.2f zoneWidth=%.2f panelInset=%.2f success=%s",
            geometry.contentWidth,
            columns,
            gridWidth,
            zoneWidth,
            panelInset,
            tostring(success)
        ))
        if not ok then
            writeDebugLog("STASH core geometry error: " .. tostring(errorMessage))
        end
    end

    return success
end

local function getStashFilterController(filters)
    if filters == nil then return nil end
    return safe(function() return filters.logicController end) or
        safe(function() return filters:GetController() end)
end

local function getStashSelectedFilterIndex(radioGroup)
    if radioGroup == nil then return nil end
    return safe(function() return radioGroup:GetSelectedIndex() end) or
        safe(function() return radioGroup.selectedIndex end)
end

-- Stash-specific UX tweak. Player filters are dynamic, so never assume that
-- All Items lives at a fixed child/index. After PopulatePlayerInventory has
-- finished building FilterRadioGroup, find the live toggle whose stable label
-- key is UI-Filters-AllItems, then ask FilterRadioGroup to select that toggle
-- by its actual filter data. ToggleData() is the vanilla path used by
-- FullscreenVendorGameController itself, so this keeps visual state,
-- m_lastPlayerFilter, and the data view synchronized without reordering Ink
-- widgets or depending on which item categories happen to exist.
local function selectStashPlayerAllItemsExact(reason)
    if not stashMenuActive then return false end
    if stashDefaultPlayerFilterForced then return true end

    local tree = resolveStashTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "STASH default All Items exact path unavailable: " ..
                tostring(reason)
            )
        end
        return false
    end

    local playerRadio = getStashFilterController(tree.playerFilters)
    if playerRadio == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "STASH default All Items: player FilterRadioGroup unavailable"
            )
        end
        return false
    end

    local childCount = safe(function()
        return tree.playerFilters:GetNumChildren()
    end) or 0
    local selectedBefore = getStashSelectedFilterIndex(playerRadio)

    for index = 0, childCount - 1 do
        local child = safe(function()
            return tree.playerFilters:GetWidget(index)
        end)
        local toggleController = child ~= nil and (
            safe(function() return child.logicController end) or
            safe(function() return child:GetController() end)
        ) or nil
        local labelKey = toggleController ~= nil and safe(function()
            return toggleController:GetLabelKey()
        end) or nil

        if tostring(labelKey) == "UI-Filters-AllItems" then
            local filterData = safe(function()
                return toggleController:GetData()
            end)
            if filterData == nil then
                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(
                        "STASH default All Items found, but GetData() returned nil"
                    )
                end
                return false
            end

            local toggleOk, toggleError = pcall(function()
                playerRadio:ToggleData(filterData)
            end)
            local selectedAfter = getStashSelectedFilterIndex(playerRadio)
            local success = toggleOk and selectedAfter == index

            if success then
                stashDefaultPlayerFilterForced = true
            end

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("------------------------------------------------------------")
                writeDebugLog(
                    "STASH default All Items selection: " .. tostring(reason)
                )
                writeDebugLog(string.format(
                    "allIndex=%d filterData=%s selectedBefore=%s selectedAfter=%s toggleOk=%s success=%s",
                    index,
                    tostring(filterData),
                    tostring(selectedBefore),
                    tostring(selectedAfter),
                    tostring(toggleOk),
                    tostring(success)
                ))
                if not toggleOk then
                    writeDebugLog(
                        "STASH default All Items ToggleData error: " ..
                        tostring(toggleError)
                    )
                end
            end

            return success
        end
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "STASH default All Items toggle not found: children=%d selectedBefore=%s",
            childCount,
            tostring(selectedBefore)
        ))
    end
    return false
end

local function refreshStashDataViewsExact(controller, reason)
    if not stashMenuActive or controller == nil then return false end
    if stashDataViewsRefreshed then return true end

    local tree = resolveStashTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "STASH data-view refresh exact path unavailable: " ..
                tostring(reason)
            )
        end
        return false
    end

    local playerRadio = getStashFilterController(tree.playerFilters)
    local vendorRadio = getStashFilterController(tree.vendorFilters)
    local playerIndex = getStashSelectedFilterIndex(playerRadio)
    local vendorIndex = getStashSelectedFilterIndex(vendorRadio)

    if playerRadio == nil or vendorRadio == nil or
       playerIndex == nil or vendorIndex == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "STASH data-view refresh controllers not ready: " ..
                tostring(reason)
            )
        end
        return false
    end

    -- Calling these native callbacks with the CURRENT selected indices does
    -- not visibly change either filter. It only forces the same data/layout
    -- rebuild that the user's manual filter -> unfilter action triggers.
    stashDataRefreshInProgress = true

    local playerOk, playerError = pcall(function()
        controller:OnPlayerFilterChange(playerRadio, playerIndex)
    end)
    local vendorOk, vendorError = pcall(function()
        controller:OnVendorFilterChange(vendorRadio, vendorIndex)
    end)

    stashDataRefreshInProgress = false
    stashDataViewsRefreshed = playerOk and vendorOk

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("STASH data views refreshed: " .. tostring(reason))
        writeDebugLog(string.format(
            "player=%s vendor=%s selectedPlayer=%s selectedVendor=%s success=%s",
            tostring(playerOk),
            tostring(vendorOk),
            tostring(playerIndex),
            tostring(vendorIndex),
            tostring(stashDataViewsRefreshed)
        ))
        if not playerOk then
            writeDebugLog("STASH player filter refresh error: " .. tostring(playerError))
        end
        if not vendorOk then
            writeDebugLog("STASH vendor filter refresh error: " .. tostring(vendorError))
        end
    end

    return stashDataViewsRefreshed
end

local function scheduleStashDataViewRefresh(controller, source)
    if not stashMenuActive or stashDataViewsRefreshed or
       stashDataRefreshInProgress then
        return
    end

    if not (stashPlayerInventoryPopulated and
            stashVendorInventoryPopulated) then
        return
    end

    -- Re-arm from the latest population callback so the 0.20 s window starts
    -- only after both sides have completed their native population pass.
    pendingStashDataRefreshController = controller
    pendingStashDataRefreshDelay = STASH_DATA_REFRESH_DELAY

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "STASH data-view refresh scheduled by %s: delay=%.2fs",
            tostring(source),
            STASH_DATA_REFRESH_DELAY
        ))
    end
end

local function positionStashDropdownExact(zoneName, reason)
    if not stashMenuActive then return false end

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    local tree = resolveStashTreeExact()
    if geometry == nil or tree == nil then return false end

    local button = zoneName == "playerPanel" and
        tree.playerSort or tree.vendorSort
    local dropdown = tree.dropdownContainer

    local rootRect = safe(function() return GetScreenPosition(tree.contentRoot) end)
    local buttonRect = safe(function() return GetScreenPosition(button) end)
    if rootRect == nil or buttonRect == nil then return false end

    local rootScreenWidth = rootRect.Right - rootRect.Left
    local rootScreenHeight = rootRect.Bottom - rootRect.Top
    if rootScreenWidth <= 0.0 or rootScreenHeight <= 0.0 then return false end

    local targetX = (buttonRect.Left - rootRect.Left) *
        geometry.contentWidth / rootScreenWidth
    local targetY = (buttonRect.Bottom - rootRect.Top) *
        REFERENCE_HEIGHT / rootScreenHeight

    local x = targetX - 300.0
    local y = targetY - 300.0

    local positioned = pcall(function()
        dropdown:SetTranslation(Vector2.new({ X = x, Y = y }))
        dropdown:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "STASH dropdown %s (%s): positioned=%s translation=%.2f,%.2f",
            tostring(zoneName),
            tostring(reason),
            tostring(positioned),
            x,
            y
        ))
    end

    return positioned
end


-- ---------------------------------------------------------------------------
-- BUY / SELL VENDOR
--
-- Ordinary vendors use the same FullscreenVendorGameController skeleton as
-- Storage/Stash. The validated dump differs in one structural discriminator:
-- vendorHeader[0]/searchContainerVendor[3] replaces searchContainerStorage.
-- Keep a dedicated resolver so Storage remains strictly guarded and unchanged.
-- ---------------------------------------------------------------------------

local function resolveVendorTreeExact()
    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return nil end

    local outerRoot = directChild(virtualWindow, 0, "Root")
    local contentRoot = directChild(outerRoot, 0, "Root")
    local headerRoot = directChild(outerRoot, 1, "Root")
    if contentRoot == nil or headerRoot == nil then return nil end

    local wrapper = directChild(contentRoot, 0, "wrapper")
    local innerWrapper = directChild(wrapper, 0, "wrapper")
    local playerPanel = directChild(innerWrapper, 0, "playerPanel")
    local vendorPanel = directChild(innerWrapper, 1, "vendorPanel")
    local dropdownContainer = directChild(contentRoot, 1, "dropdownContainer")
    local buttonHints = directChild(contentRoot, 2, "button_hints")
    if playerPanel == nil or vendorPanel == nil or
       dropdownContainer == nil or buttonHints == nil then
        return nil
    end

    local playerHeader = directChild(playerPanel, 0, "playerHeader")
    local playerFilterRow = directChild(playerHeader, 2, "inkHorizontalPanelWidget2")
    local playerFilters = directChild(playerFilterRow, 0, "filtersContainer")
    local playerSort = directChild(playerFilterRow, 1, "dropdownButton5")
    local playerSearch = directChild(playerHeader, 3, "searchContainerPlayer")
    local playerInventory = directChild(playerPanel, 1, "inventoryContainer")
    local playerCacheRT = directChild(playerInventory, 2, "inventoryCacheRT")
    local playerBackground = directChild(playerInventory, 3, "inventoryBackgroundWrapper")
    local playerBgA = directChild(playerBackground, 0, "inkImageWidget2a")
    local playerBgB = directChild(playerBackground, 1, "inkImageWidget2")
    local playerScrollCache = directChild(playerInventory, 4, "inventory_scroll_area_cache")
    local playerScroll = directChild(playerScrollCache, 0, "scroll_area")
    local playerGrid = directChild(playerScroll, 0, "player_virtualgrid")

    local vendorHeader = directChild(vendorPanel, 0, "vendorHeader")
    local vendorFilterRow = directChild(vendorHeader, 2, "inkHorizontalPanelWidget2")
    local vendorFilters = directChild(vendorFilterRow, 0, "filtersContainer")
    local vendorSort = directChild(vendorFilterRow, 1, "dropdownButton5")
    local vendorSearch = directChild(vendorHeader, 3, "searchContainerVendor")
    local vendorInventory = directChild(vendorPanel, 2, "inventoryContainer")
    local vendorScrollCache = directChild(vendorInventory, 1, "stash_scroll_area_cache")
    local vendorScroll = directChild(vendorScrollCache, 0, "scrollArea")
    local vendorGrid = directChild(vendorScroll, 0, "vendor_virtualgrid")
    local vendorCacheRT = directChild(vendorInventory, 2, "stashCacheRT")
    local vendorBackground = directChild(vendorInventory, 3, "inventoryBackgroundWrapper")
    local vendorBgA = directChild(vendorBackground, 2, "inkImageWidget2a")
    local vendorBgB = directChild(vendorBackground, 3, "inkImageWidget2")

    if playerFilters == nil or playerSort == nil or playerSearch == nil or
       playerInventory == nil or playerCacheRT == nil or playerBgA == nil or
       playerBgB == nil or playerScrollCache == nil or playerScroll == nil or
       playerGrid == nil or vendorFilters == nil or vendorSort == nil or
       vendorSearch == nil or vendorInventory == nil or
       vendorScrollCache == nil or vendorScroll == nil or vendorGrid == nil or
       vendorCacheRT == nil or vendorBgA == nil or vendorBgB == nil then
        return nil
    end

    return {
        contentRoot = contentRoot,
        headerRoot = headerRoot,
        playerPanel = playerPanel,
        vendorPanel = vendorPanel,
        playerFilters = playerFilters,
        vendorFilters = vendorFilters,
        playerSort = playerSort,
        vendorSort = vendorSort,
        playerSearch = playerSearch,
        vendorSearch = vendorSearch,
        playerInventory = playerInventory,
        vendorInventory = vendorInventory,
        playerCacheRT = playerCacheRT,
        vendorCacheRT = vendorCacheRT,
        playerBgA = playerBgA,
        playerBgB = playerBgB,
        vendorBgA = vendorBgA,
        vendorBgB = vendorBgB,
        playerScrollCache = playerScrollCache,
        vendorScrollCache = vendorScrollCache,
        playerScroll = playerScroll,
        vendorScroll = vendorScroll,
        playerGrid = playerGrid,
        vendorGrid = vendorGrid,
        dropdownContainer = dropdownContainer,
        buttonHints = buttonHints
    }
end

local function applyVendorExact(reason)
    if not vendorMenuActive or stashMenuActive then return false end

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then return false end

    local tree = resolveVendorTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "VENDOR exact path unavailable: " .. tostring(reason)
            )
        end
        return false
    end

    disablePillars("vendor " .. tostring(reason))

    local columns, gridWidth, zoneWidth = getStashColumnGeometry(geometry)
    local panelInset = interpolateToLegacy21x9(0.0, 235.0, geometry)
    local searchTop = interpolateToLegacy21x9(4.0, -90.0, geometry)
    local searchRight = interpolateToLegacy21x9(0.0, 1060.0, geometry)
    local searchBottom = interpolateToLegacy21x9(32.0, 50.0, geometry)

    local ok, errorMessage = pcall(function()
        tree.contentRoot:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)
        tree.headerRoot:SetSize(geometry.contentWidth, REFERENCE_HEIGHT)

        local playerSize = tree.playerPanel:GetSize()
        local vendorSize = tree.vendorPanel:GetSize()
        tree.playerPanel:SetSize(zoneWidth, playerSize.Y)
        tree.vendorPanel:SetSize(zoneWidth, vendorSize.Y)
        tree.playerPanel:SetMargin(panelInset, 0.0, 0.0, 0.0)
        tree.vendorPanel:SetMargin(0.0, 0.0, -panelInset, 0.0)

        local playerInventorySize = tree.playerInventory:GetSize()
        local vendorInventorySize = tree.vendorInventory:GetSize()
        tree.playerInventory:SetSize(zoneWidth, playerInventorySize.Y)
        tree.vendorInventory:SetSize(zoneWidth, vendorInventorySize.Y)

        tree.playerFilters:SetWrappingWidgetCount(8)
        tree.vendorFilters:SetWrappingWidgetCount(8)

        tree.playerSearch:SetHAlign(inkEHorizontalAlign.Right)
        tree.vendorSearch:SetHAlign(inkEHorizontalAlign.Right)
        tree.playerSearch:SetMargin(0.0, searchTop, searchRight, searchBottom)
        tree.vendorSearch:SetMargin(0.0, searchTop, searchRight, searchBottom)

        tree.contentRoot:FlagForVisualInvalidation()
        tree.headerRoot:FlagForVisualInvalidation()
        tree.playerPanel:FlagForVisualInvalidation()
        tree.vendorPanel:FlagForVisualInvalidation()
        tree.playerInventory:FlagForVisualInvalidation()
        tree.vendorInventory:FlagForVisualInvalidation()
        tree.playerFilters:FlagForVisualInvalidation()
        tree.vendorFilters:FlagForVisualInvalidation()
        tree.playerSearch:FlagForVisualInvalidation()
        tree.vendorSearch:FlagForVisualInvalidation()
    end)

    local widthsOk = true
    for _, widget in ipairs({
        tree.playerScrollCache,
        tree.playerScroll,
        tree.playerGrid,
        tree.vendorScrollCache,
        tree.vendorScroll,
        tree.vendorGrid,
        tree.playerBgA,
        tree.playerBgB,
        tree.vendorBgA,
        tree.vendorBgB
    }) do
        widthsOk = resizeStashWidgetWidth(widget, gridWidth) and widthsOk
    end

    local playerCacheOk = resizeStashCenteredCache(tree.playerCacheRT, gridWidth)
    local vendorCacheOk = resizeStashCenteredCache(tree.vendorCacheRT, gridWidth)
    local success = ok and widthsOk and playerCacheOk and vendorCacheOk

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("VENDOR geometry applied: " .. tostring(reason))
        writeDebugLog(string.format(
            "contentWidth=%.2f columns=%d gridWidth=%.2f zoneWidth=%.2f panelInset=%.2f success=%s",
            geometry.contentWidth,
            columns,
            gridWidth,
            zoneWidth,
            panelInset,
            tostring(success)
        ))
        if not ok then
            writeDebugLog("VENDOR core geometry error: " .. tostring(errorMessage))
        end
    end

    return success
end

local function selectVendorPlayerAllItemsExact(reason)
    if not vendorMenuActive or stashMenuActive then return false end
    if vendorDefaultPlayerFilterForced then return true end

    local tree = resolveVendorTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "VENDOR default All Items exact path unavailable: " ..
                tostring(reason)
            )
        end
        return false
    end

    local playerRadio = getStashFilterController(tree.playerFilters)
    if playerRadio == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "VENDOR default All Items: player FilterRadioGroup unavailable"
            )
        end
        return false
    end

    local childCount = safe(function()
        return tree.playerFilters:GetNumChildren()
    end) or 0
    local selectedBefore = getStashSelectedFilterIndex(playerRadio)

    for index = 0, childCount - 1 do
        local child = safe(function()
            return tree.playerFilters:GetWidget(index)
        end)
        local toggleController = child ~= nil and (
            safe(function() return child.logicController end) or
            safe(function() return child:GetController() end)
        ) or nil
        local labelKey = toggleController ~= nil and safe(function()
            return toggleController:GetLabelKey()
        end) or nil

        if tostring(labelKey) == "UI-Filters-AllItems" then
            local filterData = safe(function()
                return toggleController:GetData()
            end)
            if filterData == nil then
                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(
                        "VENDOR default All Items found, but GetData() returned nil"
                    )
                end
                return false
            end

            local toggleOk, toggleError = pcall(function()
                playerRadio:ToggleData(filterData)
            end)
            local selectedAfter = getStashSelectedFilterIndex(playerRadio)
            local success = toggleOk and selectedAfter == index

            if success then
                vendorDefaultPlayerFilterForced = true
            end

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("------------------------------------------------------------")
                writeDebugLog(
                    "VENDOR default All Items selection: " .. tostring(reason)
                )
                writeDebugLog(string.format(
                    "allIndex=%d filterData=%s selectedBefore=%s selectedAfter=%s toggleOk=%s success=%s",
                    index,
                    tostring(filterData),
                    tostring(selectedBefore),
                    tostring(selectedAfter),
                    tostring(toggleOk),
                    tostring(success)
                ))
                if not toggleOk then
                    writeDebugLog(
                        "VENDOR default All Items ToggleData error: " ..
                        tostring(toggleError)
                    )
                end
            end

            return success
        end
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "VENDOR default All Items toggle not found: children=%d selectedBefore=%s",
            childCount,
            tostring(selectedBefore)
        ))
    end
    return false
end

local function refreshVendorDataViewsExact(controller, reason)
    if not vendorMenuActive or stashMenuActive or controller == nil then
        return false
    end
    if vendorDataViewsRefreshed then return true end

    local tree = resolveVendorTreeExact()
    if tree == nil then return false end

    local playerRadio = getStashFilterController(tree.playerFilters)
    local vendorRadio = getStashFilterController(tree.vendorFilters)
    local playerIndex = getStashSelectedFilterIndex(playerRadio)
    local vendorIndex = getStashSelectedFilterIndex(vendorRadio)

    if playerRadio == nil or vendorRadio == nil or
       playerIndex == nil or vendorIndex == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "VENDOR data-view refresh controllers not ready: " ..
                tostring(reason)
            )
        end
        return false
    end

    vendorDataRefreshInProgress = true
    local playerOk, playerError = pcall(function()
        controller:OnPlayerFilterChange(playerRadio, playerIndex)
    end)
    local vendorOk, vendorError = pcall(function()
        controller:OnVendorFilterChange(vendorRadio, vendorIndex)
    end)
    vendorDataRefreshInProgress = false
    vendorDataViewsRefreshed = playerOk and vendorOk

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("VENDOR data views refreshed: " .. tostring(reason))
        writeDebugLog(string.format(
            "player=%s vendor=%s selectedPlayer=%s selectedVendor=%s success=%s",
            tostring(playerOk),
            tostring(vendorOk),
            tostring(playerIndex),
            tostring(vendorIndex),
            tostring(vendorDataViewsRefreshed)
        ))
        if not playerOk then
            writeDebugLog("VENDOR player filter refresh error: " .. tostring(playerError))
        end
        if not vendorOk then
            writeDebugLog("VENDOR vendor filter refresh error: " .. tostring(vendorError))
        end
    end

    return vendorDataViewsRefreshed
end

local function scheduleVendorDataViewRefresh(controller, source)
    if not vendorMenuActive or stashMenuActive or
       vendorDataViewsRefreshed or vendorDataRefreshInProgress or
       pendingVendorDataRefreshController ~= nil then
        return
    end

    if not (vendorPlayerItemMaterialized and
            vendorVendorItemMaterialized) then
        return
    end

    -- Exact analogue of the retained Stash refresh: once both sides are
    -- known to be live, wait a single 0.20 s window so native virtual-list
    -- materialization/layout can finish, then replay the current filters once.
    pendingVendorDataRefreshController = controller
    pendingVendorDataRefreshDelay = VENDOR_DATA_REFRESH_DELAY

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "VENDOR data-view refresh scheduled by %s: delay=%.2fs",
            tostring(source),
            VENDOR_DATA_REFRESH_DELAY
        ))
    end
end

local function positionVendorDropdownExact(zoneName, reason)
    if not vendorMenuActive or stashMenuActive then return false end

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    local tree = resolveVendorTreeExact()
    if geometry == nil or tree == nil then return false end

    local button = zoneName == "playerPanel" and
        tree.playerSort or tree.vendorSort
    local dropdown = tree.dropdownContainer

    local rootRect = safe(function() return GetScreenPosition(tree.contentRoot) end)
    local buttonRect = safe(function() return GetScreenPosition(button) end)
    if rootRect == nil or buttonRect == nil then return false end

    local rootScreenWidth = rootRect.Right - rootRect.Left
    local rootScreenHeight = rootRect.Bottom - rootRect.Top
    if rootScreenWidth <= 0.0 or rootScreenHeight <= 0.0 then return false end

    local targetX = (buttonRect.Left - rootRect.Left) *
        geometry.contentWidth / rootScreenWidth
    local targetY = (buttonRect.Bottom - rootRect.Top) *
        REFERENCE_HEIGHT / rootScreenHeight

    local x = targetX - 300.0
    local y = targetY - 300.0

    local positioned = pcall(function()
        dropdown:SetTranslation(Vector2.new({ X = x, Y = y }))
        dropdown:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "VENDOR dropdown %s (%s): positioned=%s translation=%.2f,%.2f",
            tostring(zoneName),
            tostring(reason),
            tostring(positioned),
            x,
            y
        ))
    end

    return positioned
end

-- ---------------------------------------------------------------------------
-- BREACH PROTOCOL
--
-- Keep the authored 3840x2160 minigame centered. Only the proven fullscreen
-- decoration is extended into the ultrawide side space.
--
-- Current exact runtime tree:
-- inkMenuLayer/inkVirtualWindow
-- └─ Root[0]
--    └─ Root[0]
--       ├─ AllParts[4]                         <- leave untouched
--       ├─ bg_loop[6]
--       │  └─ bg_loop[0]
--       └─ fullscreen_Fluff[9]
--          ├─ fluff_columns[6]                <- refresh only
--          ├─ header_ux_highlight[7]
--          └─ tempBG[17]
--
-- These nodes already exist at OnInitialize, but their native intro animation
-- starts just afterward and can overwrite layout state. Apply geometry
-- immediately, then perform exactly one additional refit after the intro has
-- been observed starting and subsequently returning to its settled state.
-- This is a narrow lifecycle finalize, not a generic retry window.
--
-- Tutorial note:
-- The four TutorialBracketXX widgets belong to the base minigame and stay in
-- the centered 3840 space. The actual Help/Tutorial overlay is a separate
-- inkGameNotificationsLayer resource handled by its own exact-path treatment
-- below.
-- ---------------------------------------------------------------------------

local function resolveBreachProtocolTreeExact()
    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return nil end

    local outerRoot = directChild(virtualWindow, 0, "Root")
    local contentRoot = directChild(outerRoot, 0, "Root")
    if contentRoot == nil then return nil end

    -- Signature guard: AllParts[4] is the authored active minigame shell.
    local allParts = directChild(contentRoot, 4, "AllParts")

    local bgLoop = directChild(contentRoot, 6, "bg_loop")
    local bgLoopVideo = directChild(bgLoop, 0, "bg_loop")

    local fullscreenFluff = directChild(
        contentRoot, 9, "fullscreen_Fluff"
    )
    local fluffColumns = directChild(
        fullscreenFluff, 6, "fluff_columns"
    )
    local headerHighlight = directChild(
        fullscreenFluff, 7, "header_ux_highlight"
    )
    local tempBG = directChild(
        fullscreenFluff, 17, "tempBG"
    )

    if allParts == nil or bgLoop == nil or bgLoopVideo == nil or
       fullscreenFluff == nil or fluffColumns == nil or
       headerHighlight == nil or tempBG == nil then
        return nil
    end

    return {
        contentRoot = contentRoot,
        allParts = allParts,
        bgLoop = bgLoop,
        bgLoopVideo = bgLoopVideo,
        fullscreenFluff = fullscreenFluff,
        fluffColumns = fluffColumns,
        headerHighlight = headerHighlight,
        tempBG = tempBG
    }
end

local function isBreachProtocolIntroSettledExact()
    local tree = resolveBreachProtocolTreeExact()
    if tree == nil then return false, nil end

    local fluffScale = safe(function()
        return tree.fullscreenFluff:GetScale()
    end)
    local columnsScale = safe(function()
        return tree.fluffColumns:GetScale()
    end)
    local fluffVisible = safe(function()
        return tree.fullscreenFluff:IsVisible()
    end)
    local columnsVisible = safe(function()
        return tree.fluffColumns:IsVisible()
    end)

    if fluffScale == nil or columnsScale == nil or
       fluffVisible == nil or columnsVisible == nil then
        return false, nil
    end

    local settled =
        fluffVisible == true and
        columnsVisible == true and
        math.abs(fluffScale.Y - 1.0) <= 0.01 and
        math.abs(columnsScale.X - 1.0) <= 0.01

    return settled, {
        fluffScaleY = fluffScale.Y,
        columnsScaleX = columnsScale.X,
        fluffVisible = fluffVisible,
        columnsVisible = columnsVisible
    }
end

local function applyBreachProtocolExact(reason)
    disablePillars("breach protocol " .. tostring(reason))

    local geometry = getTargetGeometry()
    if geometry == nil then return false end

    local tree = resolveBreachProtocolTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "BREACH exact path unavailable: " .. tostring(reason)
            )
        end
        return false
    end

    local horizontalInset = math.max(
        0.0,
        (geometry.contentWidth - VANILLA_CONTENT_WIDTH) * 0.5
    )

    local tempBgOk = pcall(function()
        tree.tempBG:SetMargin(
            -horizontalInset, 0.0, -horizontalInset, 0.0
        )
        tree.tempBG:FlagForVisualInvalidation()
    end)

    local headerOk = pcall(function()
        tree.headerHighlight:SetAnchor(inkEAnchor.TopLeft)
        tree.headerHighlight:SetAnchorPoint(Vector2.new({
            X = 0.0,
            Y = 0.0
        }))
        tree.headerHighlight:SetMargin(
            -horizontalInset, 425.0, 0.0, 0.0
        )
        tree.headerHighlight:SetSize(
            geometry.contentWidth, 170.0
        )
        tree.headerHighlight:FlagForVisualInvalidation()
    end)

    -- Both bg_loop widgets require the same proven extension. Preserve that
    -- behavior explicitly instead of relying on recursive name discovery.
    local bgLoopOk = pcall(function()
        tree.bgLoop:SetMargin(
            -horizontalInset, 0.0, -horizontalInset, 0.0
        )
        tree.bgLoop:FlagForVisualInvalidation()

        tree.bgLoopVideo:SetMargin(
            -horizontalInset, 0.0, -horizontalInset, 0.0
        )
        tree.bgLoopVideo:FlagForVisualInvalidation()
    end)

    -- Ink can retain the pre-extension cached position for fluff_columns.
    -- Refresh only this exact widget; do not broaden this into a tree scan.
    local fluffRefreshOk = pcall(function()
        if tree.fluffColumns:IsVisible() then
            tree.fluffColumns:SetVisible(false)
            tree.fluffColumns:SetVisible(true)
        else
            tree.fluffColumns:FlagForVisualInvalidation()
        end
    end)

    local success =
        tempBgOk and headerOk and bgLoopOk and fluffRefreshOk

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("BREACH applied: " .. tostring(reason))
        writeDebugLog(string.format(
            "contentWidth=%.2f inset=%.2f success=%s | tempBG=%s header=%s bgLoop=%s fluffColumns=%s",
            geometry.contentWidth,
            horizontalInset,
            tostring(success),
            tostring(tempBgOk),
            tostring(headerOk),
            tostring(bgLoopOk),
            tostring(fluffRefreshOk)
        ))
        writeDebugLog(
            "AllParts[4] intentionally untouched; active minigame remains centered 3840x2160"
        )
    end

    return success
end

-- ---------------------------------------------------------------------------
-- BREACH PROTOCOL TUTORIAL OVERLAY
--
-- This is NOT part of the main inkMenuLayer minigame tree. It is spawned in
-- inkGameNotificationsLayer by gameuiPopupsManager.
--
-- Exact runtime tree captured with the Help/Tutorial view open:
-- inkGameNotificationsLayer/inkVirtualWindow
-- └─ Root[0]
--    └─ TutorialOverlayContainer[2]          <- already spans contentWidth
--       ├─ NotificationRoot[0]
--       └─ Root[1]                           <- authored 3840x2160 tutorial UI
--          ├─ glowListContainer3[0]          <- strict Breach tutorial signature
--          └─ bg[12]                         <- fullscreen tutorial background
--
-- Keep the tutorial UI itself authored at 3840x2160 and center it inside the
-- ultrawide overlay by +halfExtra. The background is then widened back out to
-- contentWidth and shifted -halfExtra so it still covers the whole display.
--
-- The exact indices are known. Opening Help can produce no useful
-- PopupsManager callback, so a Breach-session-only exact-path
-- visibility watcher is justified. It stops immediately after the tutorial is
-- refitted once.
-- ---------------------------------------------------------------------------

local function resolveBreachTutorialTreeExact()
    local virtualWindow = getGameNotificationsVirtualWindow()
    if virtualWindow == nil then return nil end

    local layerRoot = directChild(virtualWindow, 0, "Root")
    local tutorialOverlay = directChild(
        layerRoot, 2, "TutorialOverlayContainer"
    )
    if tutorialOverlay == nil then return nil end

    -- The overlay also owns NotificationRoot[0]. Root[1] is specifically the
    -- Breach tutorial UI, proven by glowListContainer3[0].
    local notificationRoot = directChild(
        tutorialOverlay, 0, "NotificationRoot"
    )
    local tutorialRoot = directChild(tutorialOverlay, 1, "Root")
    local glowSignature = directChild(
        tutorialRoot, 0, "glowListContainer3"
    )
    local background = directChild(tutorialRoot, 12, "bg")

    if notificationRoot == nil or tutorialRoot == nil or
       glowSignature == nil or background == nil then
        return nil
    end

    return {
        overlay = tutorialOverlay,
        tutorialRoot = tutorialRoot,
        glowSignature = glowSignature,
        background = background
    }
end

local function applyBreachTutorialExact(reason, logUnavailable)
    local geometry = getTargetGeometry()
    if geometry == nil then return false end

    local tree = resolveBreachTutorialTreeExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS and logUnavailable ~= false then
            writeDebugLog(
                "BREACH TUTORIAL exact path unavailable: " .. tostring(reason)
            )
        end
        return false
    end

    -- Ignore stale/hidden notification resources. The PopupsManager callbacks
    -- can also fire for unrelated notifications.
    local overlayVisible = safe(function()
        return tree.overlay:IsVisible()
    end)
    local tutorialVisible = safe(function()
        return tree.tutorialRoot:IsVisible()
    end)
    if overlayVisible ~= true or tutorialVisible ~= true then
        return false
    end

    local tutorialInset = math.max(
        0.0,
        (geometry.contentWidth - VANILLA_CONTENT_WIDTH) * 0.5
    )

    local rootMargin = safe(function()
        return tree.tutorialRoot:GetMargin()
    end)
    local backgroundMargin = safe(function()
        return tree.background:GetMargin()
    end)
    local backgroundSize = safe(function()
        return tree.background:GetSize()
    end)

    local rootNeedsUpdate =
        rootMargin == nil or
        math.abs(rootMargin.left - tutorialInset) > 0.05 or
        math.abs(rootMargin.top) > 0.05 or
        math.abs(rootMargin.right) > 0.05 or
        math.abs(rootMargin.bottom) > 0.05

    local backgroundNeedsUpdate =
        backgroundMargin == nil or backgroundSize == nil or
        math.abs(backgroundSize.X - geometry.contentWidth) > 0.05 or
        math.abs(backgroundSize.Y - REFERENCE_HEIGHT) > 0.05 or
        math.abs(backgroundMargin.left + tutorialInset) > 0.05 or
        math.abs(backgroundMargin.top) > 0.05 or
        math.abs(backgroundMargin.right) > 0.05 or
        math.abs(backgroundMargin.bottom) > 0.05

    if not rootNeedsUpdate and not backgroundNeedsUpdate then
        return true
    end

    disablePillars("breach tutorial " .. tostring(reason))

    local rootOk = true
    if rootNeedsUpdate then
        rootOk = pcall(function()
            tree.tutorialRoot:SetMargin(
                tutorialInset, 0.0, 0.0, 0.0
            )
            tree.tutorialRoot:FlagForVisualInvalidation()
        end)
    end

    local backgroundOk = true
    if backgroundNeedsUpdate then
        backgroundOk = pcall(function()
            tree.background:SetSize(
                geometry.contentWidth, REFERENCE_HEIGHT
            )
            tree.background:SetMargin(
                -tutorialInset, 0.0, 0.0, 0.0
            )
            tree.background:FlagForVisualInvalidation()
        end)
    end

    local success = rootOk and backgroundOk

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog("BREACH TUTORIAL applied: " .. tostring(reason))
        writeDebugLog(string.format(
            "contentWidth=%.2f inset=%.2f success=%s | Root[1]=%s bg[12]=%s",
            geometry.contentWidth,
            tutorialInset,
            tostring(success),
            tostring(rootOk),
            tostring(backgroundOk)
        ))
    end

    return success
end

-- ---------------------------------------------------------------------------
-- FLATLINED / DEATH MENU
--
-- The Flatlined screen contains many authored animations. Do not resize or
-- reposition its animated content widgets. Only adapt the structural
-- background/hint elements that are independent of those animations.
--
-- Exact runtime tree from the current dump:
--
-- inkMenuLayer/inkVirtualWindow
-- └─ Root[0]
--    ├─ Root[0]                       <- 3840x2160 background shell
--    └─ Root[1]
--       ├─ button_hints[2]            <- bottom-right hints
--       ├─ vignette[18]               <- full-height background vignette
--       └─ bg[19]                     <- fixed 3840x2160 background rectangle
--
-- Mutations:
--   1) Root[0]/Root[0] -> contentWidth x 2160
--   2) Root[0]/Root[1]/vignette[18] -> scale X by contentWidth / 3840,
--      preserving its authored Y scale
--   3) Root[0]/Root[1]/button_hints[2] -> standard halfExtra right shift
--   4) Root[0]/Root[1]/bg[19] -> contentWidth x 2160 and shift its left
--      margin by -halfExtra so the widened rectangle stays centered around
--      the original 3840-wide composition.
--
-- DeathMenuGameController is unique to this screen in the current v2 design,
-- so OnInitialize is sufficient. Previous scenario-state machinery existed
-- only to protect a shared PauseMenu background observer that is no longer used.
-- ---------------------------------------------------------------------------

local function applyFlatlinedExact(reason)
    local geometry = getTargetGeometry()
    local uiGeometry = getUISpreadGeometry(geometry)
    if geometry == nil or uiGeometry == nil then return false end

    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return false end

    local outerRoot = directChild(virtualWindow, 0, "Root")
    local backgroundRoot = directChild(outerRoot, 0, "Root")
    local contentRoot = directChild(outerRoot, 1, "Root")

    if backgroundRoot == nil or contentRoot == nil then
        return false
    end

    local buttonHints = directChild(contentRoot, 2, "button_hints")
    local vignette = directChild(contentRoot, 18, "vignette")
    local background = directChild(contentRoot, 19, "bg")

    if buttonHints == nil or vignette == nil or background == nil then
        return false
    end

    local vignetteScale = safe(function()
        return vignette:GetScale()
    end)
    if vignetteScale == nil then
        return false
    end

    local targetScaleX =
        geometry.contentWidth / VANILLA_CONTENT_WIDTH

    local halfExtra =
        (geometry.contentWidth - VANILLA_CONTENT_WIDTH) * 0.5

    local backgroundMargin = safe(function()
        return background:GetMargin()
    end)
    if backgroundMargin == nil then
        return false
    end

    local beforeBackground = nil
    local beforeVignetteScale = nil
    local beforeHintsMargin = nil
    local beforeBgSize = nil
    local beforeBgMargin = nil

    if ACTIVATE_DEBUG_LOGS then
        beforeBackground = safe(function()
            return backgroundRoot:GetSize()
        end)
        beforeVignetteScale = vignetteScale
        beforeHintsMargin = safe(function()
            return buttonHints:GetMargin()
        end)
        beforeBgSize = safe(function()
            return background:GetSize()
        end)
        beforeBgMargin = backgroundMargin
    end

    local backgroundOk, backgroundError = pcall(function()
        backgroundRoot:SetSize(
            geometry.contentWidth,
            REFERENCE_HEIGHT
        )
        backgroundRoot:FlagForVisualInvalidation()
    end)

    local vignetteOk, vignetteError = pcall(function()
        vignette:SetScale(Vector2.new({
            X = targetScaleX,
            Y = vignetteScale.Y
        }))
        vignette:FlagForVisualInvalidation()
    end)

    local hintsOk = shiftButtonHintsAtIndex(
        contentRoot,
        2,
        uiGeometry,
        "Flatlined." .. tostring(reason)
    )

    local bgOk, bgError = pcall(function()
        background:SetSize(
            geometry.contentWidth,
            REFERENCE_HEIGHT
        )
        background:SetMargin(
            -halfExtra,
            backgroundMargin.top,
            backgroundMargin.right,
            backgroundMargin.bottom
        )
        background:FlagForVisualInvalidation()
    end)

    local allOk =
        backgroundOk and vignetteOk and hintsOk and bgOk

    if allOk then
        disablePillars("Flatlined." .. tostring(reason))
    end

    if ACTIVATE_DEBUG_LOGS then
        if backgroundOk then
            writeDebugLog(string.format(
                "FLATLINED background Root[0] %s -> %.2fx%.2f",
                beforeBackground ~= nil and
                    string.format(
                        "%.2fx%.2f",
                        beforeBackground.X,
                        beforeBackground.Y
                    ) or
                    "unknown",
                geometry.contentWidth,
                REFERENCE_HEIGHT
            ))
        else
            writeDebugLog(
                "FLATLINED background resize error: " ..
                tostring(backgroundError)
            )
        end

        if vignetteOk then
            writeDebugLog(string.format(
                "FLATLINED vignette[18] scale [%.4f, %.4f] -> [%.4f, %.4f]",
                beforeVignetteScale.X,
                beforeVignetteScale.Y,
                targetScaleX,
                beforeVignetteScale.Y
            ))
        else
            writeDebugLog(
                "FLATLINED vignette scale error: " ..
                tostring(vignetteError)
            )
        end

        if beforeHintsMargin ~= nil then
            writeDebugLog(string.format(
                "FLATLINED button_hints[2] original margin=[%.2f, %.2f, %.2f, %.2f] shift=%s",
                beforeHintsMargin.left,
                beforeHintsMargin.top,
                beforeHintsMargin.right,
                beforeHintsMargin.bottom,
                tostring(hintsOk)
            ))
        end

        if bgOk and beforeBgMargin ~= nil then
            writeDebugLog(string.format(
                "FLATLINED bg[19] %s margin=[%.2f, %.2f, %.2f, %.2f] -> %.2fx%.2f marginLeft=%.2f",
                beforeBgSize ~= nil and
                    string.format(
                        "%.2fx%.2f",
                        beforeBgSize.X,
                        beforeBgSize.Y
                    ) or
                    "unknown",
                beforeBgMargin.left,
                beforeBgMargin.top,
                beforeBgMargin.right,
                beforeBgMargin.bottom,
                geometry.contentWidth,
                REFERENCE_HEIGHT,
                -halfExtra
            ))
        elseif not bgOk then
            writeDebugLog(
                "FLATLINED bg[19] resize/margin error: " ..
                tostring(bgError)
            )
        end
    end

    return allOk
end


-- ---------------------------------------------------------------------------
-- PAUSE MENU
--
-- Current runtime tree:
-- inkMenuLayer/inkVirtualWindow
-- └─ Root[0]
--    ├─ Root[0]  <- background/vignette branch, signature child:
--    │             inkRectangleWidget14[0]
--    └─ Root[1]  <- pause-menu content branch, signature child:
--                  bgFluff[0]
--
-- A previous implementation recursively found those two signature
-- widgets and resized their parents. The exact runtime paths are now known,
-- so mutate only those two parents.
-- ---------------------------------------------------------------------------

local function applyPauseMenuExact(reason)
    local geometry = getTargetGeometry()
    local uiGeometry = getUISpreadGeometry(geometry)
    if geometry == nil or uiGeometry == nil then return false end

    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return false end

    local outerRoot = directChild(virtualWindow, 0, "Root")
    local backgroundRoot = directChild(outerRoot, 0, "Root")
    local contentRoot = directChild(outerRoot, 1, "Root")

    if backgroundRoot == nil or contentRoot == nil then
        return false
    end

    -- Exact signatures from the current pause-menu dump. These prevent this
    -- path from touching another menu that happens to use two Root siblings.
    local backgroundSignature = directChild(
        backgroundRoot, 0, "inkRectangleWidget14"
    )
    local contentSignature = directChild(
        contentRoot, 0, "bgFluff"
    )

    if backgroundSignature == nil or contentSignature == nil then
        return false
    end

    local beforeBackground = nil
    local beforeContent = nil

    if ACTIVATE_DEBUG_LOGS then
        beforeBackground = safe(function()
            return backgroundRoot:GetSize()
        end)
        beforeContent = safe(function()
            return contentRoot:GetSize()
        end)
    end

    local ok, errorMessage = pcall(function()
        backgroundRoot:SetSize(
            geometry.contentWidth,
            REFERENCE_HEIGHT
        )
        backgroundRoot:FlagForVisualInvalidation()

        contentRoot:SetSize(
            uiGeometry.contentWidth,
            REFERENCE_HEIGHT
        )
        contentRoot:FlagForVisualInvalidation()
    end)

    if ok then
        disablePillars("PauseMenu." .. tostring(reason))
    end

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "PAUSE MENU applied (%s) background %.2fx%.2f -> %.2fx%.2f | content %.2fx%.2f -> %.2fx%.2f",
                tostring(reason),
                beforeBackground ~= nil and beforeBackground.X or -1.0,
                beforeBackground ~= nil and beforeBackground.Y or -1.0,
                geometry.contentWidth,
                REFERENCE_HEIGHT,
                beforeContent ~= nil and beforeContent.X or -1.0,
                beforeContent ~= nil and beforeContent.Y or -1.0,
                uiGeometry.contentWidth,
                REFERENCE_HEIGHT
            ))
        else
            writeDebugLog(
                "PAUSE MENU resize error: " ..
                tostring(errorMessage)
            )
        end
    end

    return ok
end


-- ---------------------------------------------------------------------------
-- SYSTEM NOTIFICATIONS (quit / exit confirmations)
--
-- ExitGame / system confirmation dialogs live on inkSystemNotificationsLayer
-- and do not expose a dedicated script Game Controller that CET can observe.
-- Runtime behavior therefore requires checking this layer from onUpdate.
--
-- Runtime path:
--   inkSystemNotificationsLayer/inkVirtualWindow/Root[0]/Canvas[0]
--
-- Keep that lifecycle choice, but make the work as narrow as possible:
-- no recursive scan, no retries, no delayed pass. We only follow the exact
-- two-child path and resize the authored 3840x2160 Canvas once when present.
-- ---------------------------------------------------------------------------

local function applySystemNotificationExact()
    local geometry = getTargetGeometry()
    if geometry == nil then return false end

    local layer = safe(function()
        return Game.GetInkSystem():GetLayer(
            CName.new("inkSystemNotificationsLayer")
        )
    end)
    if layer == nil then return false end

    local virtualWindow = safe(function()
        return layer:GetVirtualWindow()
    end)
    if virtualWindow == nil then return false end

    local root = directChild(virtualWindow, 0, "Root")
    local canvas = directChild(root, 0, "Canvas")
    if canvas == nil then return false end

    -- Signature guard: this confirmation Canvas is authored at 3840x2160.
    -- Once widened it no longer matches, so SetSize is naturally one-shot
    -- for each spawned confirmation dialog.
    local size = safe(function()
        return canvas:GetSize()
    end)
    if size == nil or
       size.X < 3800.0 or size.X > 3860.0 or
       size.Y < 2100.0 or size.Y > 2200.0 then
        return false
    end

    local ok, errorMessage = pcall(function()
        canvas:SetSize(
            geometry.contentWidth,
            REFERENCE_HEIGHT
        )
        canvas:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "SYSTEM NOTIFICATION applied Canvas %.2fx%.2f -> %.2fx%.2f",
                size.X,
                size.Y,
                geometry.contentWidth,
                REFERENCE_HEIGHT
            ))
        else
            writeDebugLog(
                "SYSTEM NOTIFICATION resize error: " ..
                tostring(errorMessage)
            )
        end
    end

    return ok
end


-- ---------------------------------------------------------------------------
-- SETTINGS MENU
--
-- There are TWO proven Settings shells, depending on where Settings is opened:
--
-- In-game:
-- inkMenuLayer/inkVirtualWindow
-- └─ Root[0]
--    └─ Root[1]      <- Settings content
--
-- Pre-game / Main Menu:
-- inkMenuLayer/inkVirtualWindow
-- └─ Root[0]
--    └─ Root[0]      <- Settings content
--
-- Do not choose a root by index alone. Validate the exact direct-child
-- signature shared by both variants:
--
--   BG[0]
--   wrapper[2]
--   edge_fluff[4]
--
-- This keeps the resolver deterministic and avoids recursive discovery.
-- ---------------------------------------------------------------------------

local function resolveSettingsContentRootExact()
    local virtualWindow = getMenuVirtualWindow()
    if virtualWindow == nil then return nil end

    local outerRoot = directChild(
        virtualWindow,
        0,
        "Root"
    )
    if outerRoot == nil then return nil end

    -- Prefer the already-validated in-game layout first, then the proven
    -- pre-game/Main Menu variant.
    for _, rootIndex in ipairs({ 1, 0 }) do
        local contentRoot = directChild(
            outerRoot,
            rootIndex,
            "Root"
        )

        if contentRoot ~= nil then
            local bg = directChild(
                contentRoot,
                0,
                "BG"
            )
            local wrapper = directChild(
                contentRoot,
                2,
                "wrapper"
            )
            local edgeFluff = directChild(
                contentRoot,
                4,
                "edge_fluff"
            )

            -- Native Settings / Settings description panel. The historical
            -- implementation kept this right-anchored panel attached to the
            -- centered settings/options area instead of the physical UW edge.
            -- Keep an exact signature down to richTextDescription so an
            -- unrelated wrapper child[3] can never be moved accidentally.
            local rightSide =
                wrapper ~= nil and
                directChild(
                    wrapper,
                    3,
                    "rightSide"
                ) or nil
            local tooltips =
                rightSide ~= nil and
                directChild(
                    rightSide,
                    2,
                    "tooltips"
                ) or nil
            local richTextDescription =
                tooltips ~= nil and
                directChild(
                    tooltips,
                    0,
                    "richTextDescription"
                ) or nil

            local background =
                bg ~= nil and
                directChild(
                    bg,
                    0,
                    "background"
                ) or nil

            if bg ~= nil and
               background ~= nil and
               wrapper ~= nil and
               edgeFluff ~= nil then
                return {
                    rootIndex = rootIndex,
                    contentRoot = contentRoot,
                    bg = bg,
                    background = background,
                    wrapper = wrapper,
                    edgeFluff = edgeFluff,
                    rightSide = rightSide,
                    tooltips = tooltips,
                    richTextDescription = richTextDescription
                }
            end
        end
    end

    return nil
end

local function applySettingsMenuExact(reason)
    -- Settings, Native Settings (Mods) and Mod Settings are menu UI and must
    -- obey the same logical UI width as Hub/Backpack.
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "SETTINGS skipped: target geometry unavailable (" ..
                tostring(reason) .. ")"
            )
        end
        return false
    end

    local tree = resolveSettingsContentRootExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "SETTINGS exact path unavailable: " .. tostring(reason)
            )
        end
        return false
    end

    local contentRoot = tree.contentRoot
    local background = tree.background
    local wrapper = tree.wrapper
    local edgeFluff = tree.edgeFluff
    local rightSide = tree.rightSide
    local richTextDescription = tree.richTextDescription

    -- Native Settings UI is optional. Its exact path is shared by the
    -- in-game and pre-game Settings shells:
    --   <contentRoot>/wrapper[2]/extraButtons[2]
    local extraButtons = directChild(
        wrapper,
        2,
        "extraButtons"
    )

    local beforeRoot = nil
    local beforeBackground = nil
    local beforeExtraButtonsMargin = nil
    local beforeRightSideMargin = nil
    local beforeEdge = nil

    if ACTIVATE_DEBUG_LOGS then
        beforeRoot = safe(function()
            return contentRoot:GetSize()
        end)
        beforeBackground = safe(function()
            return background:GetSize()
        end)
        if extraButtons ~= nil then
            beforeExtraButtonsMargin = safe(function()
                return extraButtons:GetMargin()
            end)
        end
        if rightSide ~= nil and richTextDescription ~= nil then
            beforeRightSideMargin = safe(function()
                return rightSide:GetMargin()
            end)
        end
        beforeEdge = safe(function()
            return edgeFluff:GetSize()
        end)
    end

    local ok, errorMessage = pcall(function()
        contentRoot:SetSize(
            geometry.contentWidth,
            REFERENCE_HEIGHT
        )
        contentRoot:FlagForVisualInvalidation()

        -- Keep the Settings visual background on the physical display while
        -- the functional Settings composition follows UI Spread. The BG node
        -- is extended out of the centered logical content root by the exact
        -- screen/UI half-width difference.
        local backgroundHalfInset =
            (screenGeometry.contentWidth - geometry.contentWidth) * 0.5
        tree.bg:SetSize(
            screenGeometry.contentWidth,
            REFERENCE_HEIGHT
        )
        tree.bg:SetMargin(
            -backgroundHalfInset,
            0.0,
            -backgroundHalfInset,
            0.0
        )
        tree.bg:FlagForVisualInvalidation()

        background:SetSize(
            screenGeometry.contentWidth,
            REFERENCE_HEIGHT
        )
        background:FlagForVisualInvalidation()

        -- Native Settings UI: keep the left-side dropdown/list attached to
        -- the left edge of the centered vanilla 3840-wide content area.
        if extraButtons ~= nil then
            local fullHorizontalInset =
                (geometry.contentWidth - VANILLA_CONTENT_WIDTH) * 0.5

            extraButtons:SetMargin(
                250.0 + fullHorizontalInset,
                320.0,
                0.0,
                0.0
            )
            extraButtons:FlagForVisualInvalidation()
        end

        -- Settings / Native Settings hover-description panel. It is anchored
        -- TopRight with vanilla right margin 885. Widening contentRoot without
        -- compensating this margin leaves the panel at the physical UW edge.
        -- Shift it left by half the added width so it stays attached to the
        -- centered options area. This is the exact-path equivalent of the
        -- historical treatment: right = 885 + halfExtra.
        if rightSide ~= nil and richTextDescription ~= nil then
            rightSide:SetMargin(
                0.0,
                346.0,
                885.0 + geometry.halfExtra,
                0.0
            )
            rightSide:FlagForVisualInvalidation()
        end

        edgeFluff:SetSize(
            geometry.contentWidth,
            REFERENCE_HEIGHT
        )
        edgeFluff:FlagForVisualInvalidation()
    end)

    if ok then
        disablePillars(
            "SettingsMenu." .. tostring(reason)
        )
    end

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "SETTINGS applied (%s) contentRoot=Root[%d] root %.2fx%.2f -> %.2fx%.2f | BG/background %.2fx%.2f -> %.2fx%.2f | extraButtons left %.2f -> %.2f | rightSide right %.2f -> %.2f (desc=%s) | edge_fluff %.2fx%.2f -> %.2fx%.2f",
                tostring(reason),
                tree.rootIndex,
                beforeRoot ~= nil and beforeRoot.X or -1.0,
                beforeRoot ~= nil and beforeRoot.Y or -1.0,
                geometry.contentWidth,
                REFERENCE_HEIGHT,
                beforeBackground ~= nil and beforeBackground.X or -1.0,
                beforeBackground ~= nil and beforeBackground.Y or -1.0,
                screenGeometry.contentWidth,
                REFERENCE_HEIGHT,
                beforeExtraButtonsMargin ~= nil and
                    beforeExtraButtonsMargin.left or -1.0,
                extraButtons ~= nil and
                    (
                        250.0 +
                        (
                            geometry.contentWidth -
                            VANILLA_CONTENT_WIDTH
                        ) * 0.5
                    ) or -1.0,
                beforeRightSideMargin ~= nil and
                    beforeRightSideMargin.right or -1.0,
                rightSide ~= nil and richTextDescription ~= nil and
                    (885.0 + geometry.halfExtra) or -1.0,
                tostring(richTextDescription ~= nil),
                beforeEdge ~= nil and beforeEdge.X or -1.0,
                beforeEdge ~= nil and beforeEdge.Y or -1.0,
                geometry.contentWidth,
                REFERENCE_HEIGHT
            ))
        else
            writeDebugLog(
                "SETTINGS resize error: " ..
                tostring(errorMessage)
            )
        end
    end

    return ok
end



-- ---------------------------------------------------------------------------
-- VEHICLE SELECTOR FRONTEND (optional Native Settings compatibility)
--
-- Validated runtime path from Ink Tree Dumper:
--   <Settings content Root>/Viewport[5]/Vehicle_Side_Image[0]
--
-- Source-confirmed creation path:
--   SettingsSelectorControllerInt.Refresh()
--     -> Native Settings data.callback(currentValue)
--     -> Vehicle Selector add_subcategory_plus_contents(value)
--     -> PreviewWindow.Draw(vehicleName)
--     -> removes old Viewport
--     -> PreviewWindow.CreateWidget(rootWidget)
--     -> creates Viewport at left=2950, top=950
--     -> creates Vehicle_Side_Image and reparents both
--
-- UWUI widens the Settings content root, so preserve the preview's original
-- position inside the centered 16:9 composition by adding the current UI
-- half-extra to that vanilla left margin.
--
-- Exact path/signature only; do not touch unrelated Viewport[5] widgets.
-- ---------------------------------------------------------------------------

local function applyVehicleSelectorPreviewExact(reason)
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then
        return false
    end

    local tree = resolveSettingsContentRootExact()
    if tree == nil then
        return false
    end

    local viewport = directChild(
        tree.contentRoot,
        5,
        "Viewport"
    )
    if viewport == nil then
        return false
    end

    local vehicleImage = directChild(
        viewport,
        0,
        "Vehicle_Side_Image"
    )
    if vehicleImage == nil then
        return false
    end

    local targetLeft =
        VEHICLE_SELECTOR_PREVIEW_BASE_LEFT +
        geometry.halfExtra

    local beforeMargin = nil
    if ACTIVATE_DEBUG_LOGS then
        beforeMargin = safe(function()
            return viewport:GetMargin()
        end)
    end

    local ok, errorMessage = pcall(function()
        viewport:SetMargin(
            targetLeft,
            VEHICLE_SELECTOR_PREVIEW_TOP,
            0.0,
            0.0
        )
        viewport:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "VEHICLE SELECTOR preview applied (%s) contentRoot=Root[%d] left %.2f -> %.2f top=%.2f image=%s",
                tostring(reason),
                tree.rootIndex,
                beforeMargin ~= nil and
                    beforeMargin.left or -1.0,
                targetLeft,
                VEHICLE_SELECTOR_PREVIEW_TOP,
                widgetName(vehicleImage)
            ))
        else
            writeDebugLog(
                "VEHICLE SELECTOR preview error: " ..
                tostring(errorMessage)
            )
        end
    end

    return ok
end



-- Mod Settings adds its own left-side mod list directly under the Settings
-- content root:
--
--   Root[0]/Root[1]/mod_settings[5]
--
-- Keep that list aligned to the left edge of the centered 3840-wide Settings
-- composition instead of the physical ultrawide edge. This is the same rule
-- used by the compatibility treatment:
--
--   left = 500 + (contentWidth - 3840) / 2
--
-- At 21:9 (contentWidth=5160), the target left margin is 1160.
--
-- Exact path only: no recursive search and no temporary fallback.
local function applyModSettingsListExact(reason)
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "MOD SETTINGS skipped: target geometry unavailable (" ..
                tostring(reason) .. ")"
            )
        end
        return false
    end

    local tree = resolveSettingsContentRootExact()
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "MOD SETTINGS exact Settings root unavailable: " ..
                tostring(reason)
            )
        end
        return false
    end

    -- [5] is the validated Mod Settings list index. The shared dual-root
    -- resolver may return Root[0] or Root[1]; require the exact child name so
    -- an unrelated widget at the same index is never mutated.
    local modSettings = directChild(
        tree.contentRoot,
        5,
        "mod_settings"
    )
    if modSettings == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "MOD SETTINGS exact mod_settings[5] unavailable: " ..
                tostring(reason)
            )
        end
        return false
    end

    local targetLeft =
        500.0 +
        (
            geometry.contentWidth -
            VANILLA_CONTENT_WIDTH
        ) * 0.5

    local beforeMargin = nil
    if ACTIVATE_DEBUG_LOGS then
        beforeMargin = safe(function()
            return modSettings:GetMargin()
        end)
    end

    local ok, errorMessage = pcall(function()
        modSettings:SetMargin(
            targetLeft,
            320.0,
            0.0,
            0.0
        )
        modSettings:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "MOD SETTINGS list applied (%s) contentRoot=Root[%d] left %.2f -> %.2f top=320.00",
                tostring(reason),
                tree.rootIndex,
                beforeMargin ~= nil and
                    beforeMargin.left or -1.0,
                targetLeft
            ))
        else
            writeDebugLog(
                "MOD SETTINGS list error: " ..
                tostring(errorMessage)
            )
        end
    end

    return ok
end



-- ---------------------------------------------------------------------------
-- REVISED BACKPACK (optional mod compatibility)
--
-- Current dump, controller root = Root/Root:
--   previewItem[0]
--   categories[1]
--   header[2]
--   scrollWrapper[3]
--   button_hints[4]      <- natural; do not mutate
--   itemListRoot[5]
--   previewGarment[6]
--   filters[7]
--   selectedItemsCount[8]
--
-- Item row controller root:
--   shadow[0]
--   selection[1]
--   item[2]
--     nameContainer[0]
--       name[3]
--     type[2]
--
-- No recursive scans. The 21:9 target geometry intentionally mirrors the
-- previously validated official compatibility layout, including the 21:9 cap
-- on the overall Revised Backpack composition for ratios wider than 21:9.
-- ---------------------------------------------------------------------------

local function resolveRevisedBackpackMainTree(controller)
    if controller == nil then return nil end

    local root = safe(function()
        return controller:GetRootWidget()
    end)
    if root == nil then return nil end

    -- Signature guards from the current Revised Backpack tree.
    local previewItem = directChild(root, 0, "previewItem")
    local categories = directChild(root, 1, "categories")
    local header = directChild(root, 2, "header")
    local scrollWrapper = directChild(root, 3, "scrollWrapper")
    local itemListRoot = directChild(root, 5, "itemListRoot")
    local previewGarment = directChild(root, 6, "previewGarment")
    local selectedItemsCount = directChild(
        root, 8, "selectedItemsCount"
    )

    if previewItem == nil or categories == nil or header == nil or
       scrollWrapper == nil or itemListRoot == nil or previewGarment == nil or
       selectedItemsCount == nil then
        return nil
    end

    local headerName = directChild(header, 0, "nameContainer")
    local headerType = directChild(header, 2, "typeContainer")
    local scrollArea = directChild(scrollWrapper, 1, "scrollArea")

    local previewItemRoot = directChild(previewItem, 0, "Root")
    local previewItemWrapper = directChild(
        previewItemRoot, 0, "wrapper"
    )
    local previewItemImage = directChild(
        previewItemWrapper, 0, "preview"
    )

    local previewGarmentRoot = directChild(
        previewGarment, 0, "Root"
    )
    local previewGarmentWrapper = directChild(
        previewGarmentRoot, 0, "wrapper"
    )
    local previewGarmentImage = directChild(
        previewGarmentWrapper, 0, "preview"
    )

    if headerName == nil or headerType == nil or scrollArea == nil or
       previewItemRoot == nil or previewItemWrapper == nil or
       previewItemImage == nil or previewGarmentRoot == nil or
       previewGarmentWrapper == nil or previewGarmentImage == nil then
        return nil
    end

    return {
        root = root,
        headerName = headerName,
        headerType = headerType,
        scrollWrapper = scrollWrapper,
        scrollArea = scrollArea,
        itemListRoot = itemListRoot,
        selectedItemsCount = selectedItemsCount,
        previewItem = previewItem,
        previewItemRoot = previewItemRoot,
        previewItemWrapper = previewItemWrapper,
        previewItemImage = previewItemImage,
        previewGarment = previewGarment,
        previewGarmentRoot = previewGarmentRoot,
        previewGarmentWrapper = previewGarmentWrapper,
        previewGarmentImage = previewGarmentImage
    }
end

local function tryApplyRevisedBackpackMainLayout(
    controller,
    reason
)
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil or controller == nil then return false end

    local tree = resolveRevisedBackpackMainTree(controller)
    if tree == nil then return false end

    local layoutWidth = math.min(
        geometry.contentWidth,
        LEGACY_21X9_CONTENT_WIDTH
    )

    local headerNameWidth = interpolateToLegacy21x9(
        772.0, 1272.0, geometry
    )
    local typeWidth = interpolateToLegacy21x9(
        418.0, 718.0, geometry
    )
    local selectedItemsRight = interpolateToLegacy21x9(
        1080.0, 1980.0, geometry
    )

    local narrowProgress = math.max(0.0, math.min(
        1.0,
        (geometry.contentWidth - VANILLA_CONTENT_WIDTH) /
        (LEGACY_21X9_CONTENT_WIDTH - VANILLA_CONTENT_WIDTH)
    ))
    local twoToOneProgress =
        (2.0 * REFERENCE_HEIGHT - VANILLA_CONTENT_WIDTH) /
        (LEGACY_21X9_CONTENT_WIDTH - VANILLA_CONTENT_WIDTH)

    local previewBoost = 1.0
    if narrowProgress <= twoToOneProgress then
        previewBoost =
            1.0 +
            0.10 * narrowProgress / twoToOneProgress
    elseif narrowProgress < 1.0 then
        previewBoost =
            1.0 +
            0.10 *
            (1.0 - narrowProgress) /
            (1.0 - twoToOneProgress)
    end

    local garmentPreviewSize = interpolateToLegacy21x9(
        1395.0, 1895.0, geometry
    ) * previewBoost
    local garmentPreviewTop = 120.0

    local itemPreviewWidth = interpolateToLegacy21x9(
        1395.0, 1995.0, geometry
    ) * previewBoost
    local itemPreviewHeight = interpolateToLegacy21x9(
        930.0, 1330.0, geometry
    ) * previewBoost
    local itemPreviewTop = 400.0
    local itemPreviewRight = interpolateToLegacy21x9(
        0.0, -300.0, geometry
    )

    local scrollAreaWidth =
        2188.0 +
        math.max(
            0.0,
            layoutWidth - VANILLA_CONTENT_WIDTH
        ) * (900.0 / 1320.0)

    -- On a physical super-ultrawide display with UI Spread reduced toward
    -- 16:9, Revised Backpack's list is still hosted inside its original UW
    -- controller tree. Give the list viewport a small fading allowance so the
    -- last stat column is not clipped by the inherited mask. 100% remains
    -- numerically identical to the already-validated v2.4.0 layout.
    local listClipCompensation = 100.0 * (1.0 - geometry.uiSpread)
    local revisedListViewportWidth = scrollAreaWidth + listClipCompensation

    local headerNameSize = safe(function()
        return tree.headerName:GetSize()
    end)
    local headerTypeSize = safe(function()
        return tree.headerType:GetSize()
    end)
    local scrollAreaSize = safe(function()
        return tree.scrollArea:GetSize()
    end)
    local itemListRootSize = safe(function()
        return tree.itemListRoot:GetSize()
    end)

    if headerNameSize == nil or headerTypeSize == nil or
       scrollAreaSize == nil or itemListRootSize == nil then
        return false
    end

    local ok, errorMessage = pcall(function()
        tree.root:SetSize(
            layoutWidth,
            REFERENCE_HEIGHT
        )
        tree.root:SetMargin(0.0, 0.0, 0.0, 0.0)
        tree.root:FlagForVisualInvalidation()

        tree.headerName:SetSize(
            headerNameWidth,
            headerNameSize.Y
        )
        tree.headerName:FlagForVisualInvalidation()

        tree.headerType:SetSize(
            typeWidth,
            headerTypeSize.Y
        )
        tree.headerType:FlagForVisualInvalidation()

        tree.scrollArea:SetSize(
            revisedListViewportWidth,
            scrollAreaSize.Y
        )
        tree.scrollArea:FlagForVisualInvalidation()

        -- itemListRoot is the virtual-list host immediately beside the
        -- scrollWrapper. Keep its clipping width in sync with the viewport.
        tree.itemListRoot:SetSize(
            revisedListViewportWidth,
            itemListRootSize.Y
        )
        tree.itemListRoot:FlagForVisualInvalidation()

        tree.selectedItemsCount:SetMargin(
            0.0,
            440.0,
            selectedItemsRight,
            0.0
        )
        tree.selectedItemsCount:FlagForVisualInvalidation()

        tree.previewGarment:SetSize(
            garmentPreviewSize,
            garmentPreviewSize
        )
        tree.previewGarment:SetMargin(
            0.0,
            garmentPreviewTop,
            0.0,
            0.0
        )
        tree.previewGarment:FlagForVisualInvalidation()

        tree.previewGarmentRoot:SetSize(
            garmentPreviewSize,
            garmentPreviewSize
        )
        tree.previewGarmentRoot:SetMargin(
            0.0, 0.0, 0.0, 0.0
        )
        tree.previewGarmentRoot:FlagForVisualInvalidation()

        tree.previewGarmentWrapper:SetSize(
            garmentPreviewSize,
            garmentPreviewSize
        )
        tree.previewGarmentWrapper:SetMargin(
            0.0, 0.0, 0.0, 0.0
        )
        tree.previewGarmentWrapper:FlagForVisualInvalidation()

        tree.previewGarmentImage:SetSize(
            garmentPreviewSize,
            garmentPreviewSize
        )
        tree.previewGarmentImage:SetMargin(
            0.0, 0.0, 0.0, 0.0
        )
        tree.previewGarmentImage:FlagForVisualInvalidation()

        tree.previewItem:SetSize(
            itemPreviewWidth,
            itemPreviewHeight
        )
        tree.previewItem:SetMargin(
            0.0,
            itemPreviewTop,
            itemPreviewRight,
            0.0
        )
        tree.previewItem:FlagForVisualInvalidation()

        tree.previewItemRoot:SetSize(
            itemPreviewWidth,
            itemPreviewHeight
        )
        tree.previewItemRoot:SetMargin(
            0.0, 0.0, 0.0, 0.0
        )
        tree.previewItemRoot:FlagForVisualInvalidation()

        tree.previewItemWrapper:SetSize(
            itemPreviewWidth,
            itemPreviewHeight
        )
        tree.previewItemWrapper:SetMargin(
            0.0, 0.0, 0.0, 0.0
        )
        tree.previewItemWrapper:FlagForVisualInvalidation()

        tree.previewItemImage:SetSize(
            itemPreviewWidth,
            itemPreviewHeight
        )
        tree.previewItemImage:SetMargin(
            0.0, 0.0, 0.0, 0.0
        )
        tree.previewItemImage:FlagForVisualInvalidation()
    end)

    if ok then
        disablePillars(
            "RevisedBackpack." .. tostring(reason)
        )
    end

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "REVISED BACKPACK main ready (%s) checks=%d layoutWidth=%.2f headerName=%.2f type=%.2f scrollArea=%.2f clipComp=%.2f garment=%.2f item=%.2fx%.2f itemRight=%.2f selectedRight=%.2f",
                tostring(reason),
                pendingRevisedBackpackChecks,
                layoutWidth,
                headerNameWidth,
                typeWidth,
                revisedListViewportWidth,
                listClipCompensation,
                garmentPreviewSize,
                itemPreviewWidth,
                itemPreviewHeight,
                itemPreviewRight,
                selectedItemsRight
            ))
        else
            writeDebugLog(
                "REVISED BACKPACK main resize error: " ..
                tostring(errorMessage)
            )
        end
    end

    return ok
end

local function tryApplyRevisedBackpackItemRow(controller)
    if controller == nil then return false end

    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then return false end

    local root = safe(function()
        return controller:GetRootWidget()
    end)
    if root == nil then return false end

    local shadow = directChild(root, 0, "shadow")
    local selection = directChild(root, 1, "selection")
    local item = directChild(root, 2, "item")

    local nameContainer = directChild(
        item, 0, "nameContainer"
    )
    local nameText = directChild(
        nameContainer, 3, "name"
    )
    local typeText = directChild(item, 2, "type")

    if shadow == nil or selection == nil or item == nil or
       nameContainer == nil or nameText == nil or
       typeText == nil then
        return false
    end

    local nameContainerWidth = interpolateToLegacy21x9(
        772.0, 1242.0, geometry
    )
    local nameTextWidth = interpolateToLegacy21x9(
        640.0, 1110.0, geometry
    )
    local typeWidth = interpolateToLegacy21x9(
        418.0, 718.0, geometry
    )
    local rowEffectWidth = interpolateToLegacy21x9(
        3840.0, 5200.0, geometry
    )
    local rowEffectMargin = interpolateToLegacy21x9(
        0.0, -1000.0, geometry
    )
    local selectionWidth = interpolateToLegacy21x9(
        2088.0, 2988.0, geometry
    )

    local nameContainerSize = safe(function()
        return nameContainer:GetSize()
    end)
    local nameTextSize = safe(function()
        return nameText:GetSize()
    end)
    local typeSize = safe(function()
        return typeText:GetSize()
    end)

    if nameContainerSize == nil or nameTextSize == nil or
       typeSize == nil then
        return false
    end

    local ok, errorMessage = pcall(function()
        nameContainer:SetSize(
            nameContainerWidth,
            nameContainerSize.Y
        )
        nameContainer:FlagForVisualInvalidation()

        nameText:SetSize(
            nameTextWidth,
            nameTextSize.Y
        )
        nameText:SetWrapping(
            false,
            nameTextWidth,
            textWrappingPolicy.Default
        )
        nameText:SetWrappingAtPosition(nameTextWidth)
        nameText:FlagForVisualInvalidation()

        typeText:SetSize(
            typeWidth,
            typeSize.Y
        )
        typeText:SetWrapping(
            false,
            typeWidth,
            textWrappingPolicy.Default
        )
        typeText:SetWrappingAtPosition(typeWidth)
        typeText:FlagForVisualInvalidation()

        shadow:SetMargin(
            rowEffectMargin,
            0.0,
            0.0,
            0.0
        )
        shadow:SetSize(
            rowEffectWidth,
            80.0
        )
        shadow:SetOpacity(0.03)
        shadow:FlagForVisualInvalidation()

        selection:SetSize(
            selectionWidth,
            80.0
        )
        selection:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS and not ok then
        writeDebugLog(
            "REVISED BACKPACK row resize error: " ..
            tostring(errorMessage)
        )
    end

    return ok
end


-- ---------------------------------------------------------------------------
-- STEALTHRUNNER STATS POPUP (optional mod compatibility)
--
-- Exact tree in inkGameNotificationsLayer:
-- inkVirtualWindow
-- └─ Root[0]
--    └─ NotificationsContainer[1]
--       └─ UNINITIALIZED_WIDGET[0]
--          └─ StealthRunner.HubMenu.StealthRunnerStatsPopup[0]
--             └─ Root[0]
--                └─ vignette[0]   <- widen only this widget
--
-- No recursive scan. If StealthRunner is not installed, this resolver simply
-- returns nil during the low-frequency Hub-only exact-path check.
-- ---------------------------------------------------------------------------

local function resolveStealthRunnerVignette()
    local virtualWindow = getGameNotificationsVirtualWindow()
    if virtualWindow == nil then return nil end

    local layerRoot = directChild(
        virtualWindow, 0, "Root"
    )
    local notificationsContainer = directChild(
        layerRoot, 1, "NotificationsContainer"
    )
    local slot = directChild(
        notificationsContainer, 0, "UNINITIALIZED_WIDGET"
    )
    -- Do not require the mod-owned popup's Inspector Name Path as GetName().
    -- The old implementation already found that translated/library names may
    -- not be exposed verbatim at runtime. Index 0 is authoritative here.
    local stealthPopup = directChild(
        slot, 0, nil
    )
    local popupRoot = directChild(
        stealthPopup, 0, "Root"
    )
    local vignette = directChild(
        popupRoot, 0, "vignette"
    )

    return vignette
end

local function tryApplyStealthRunnerLayoutDirect(reason)
    local geometry = getTargetGeometry()
    if geometry == nil then return false end

    local vignette = resolveStealthRunnerVignette()
    if vignette == nil then
        stealthRunnerAppliedVignette = nil
        return false
    end

    -- Resize each live popup instance once only.
    if stealthRunnerAppliedVignette == vignette then
        return true
    end

    local size = safe(function()
        return vignette:GetSize()
    end)
    if size == nil then return false end

    local beforeWidth = size.X
    local height = size.Y

    local ok, errorMessage = pcall(function()
        vignette:SetSize(
            geometry.contentWidth,
            height
        )
        vignette:FlagForVisualInvalidation()
    end)

    if ok then
        stealthRunnerAppliedVignette = vignette
    end

    if ACTIVATE_DEBUG_LOGS then
        if ok then
            writeDebugLog(string.format(
                "STEALTHRUNNER resized (%s) vignette %.2fx%.2f -> %.2fx%.2f",
                tostring(reason),
                beforeWidth,
                height,
                geometry.contentWidth,
                height
            ))
        else
            writeDebugLog(
                "STEALTHRUNNER vignette resize error: " ..
                tostring(errorMessage)
            )
        end
    end

    return ok
end

-- ---------------------------------------------------------------------------
-- SHARDS
--
-- Exact tree:
-- Root[0]/Root[0]
-- ├─ list_wrapper[0]
-- ├─ entryView[1]
-- │  └─ contentArea[0]
-- │     ├─ line2[1]
-- │     └─ EntryScrollArea[4]
-- │        └─ container[0]
-- │           └─ text[2]
-- └─ button_hints[2]
--
-- Only the content Root and reading pane are widened. button_hints are
-- intentionally untouched: the widened Root carries them naturally.
--
-- Width formulas from the validated official implementation:
--   entryWidth = max(2000, contentWidth - 1860)
--   lineWidth  = entryWidth - 80
--   scrollWidth = entryWidth - 175
--   textWidth  = entryWidth - 400
-- ---------------------------------------------------------------------------

local function resolveShardsTree()
    local _, _, contentRoot = getMenuContentRoot()
    if contentRoot == nil then return nil end

    -- Signature guard for the Shards screen.
    local listWrapper = directChild(
        contentRoot, 0, "list_wrapper"
    )
    local entryView = directChild(
        contentRoot, 1, "entryView"
    )
    local contentArea = directChild(
        entryView, 0, "contentArea"
    )
    local line2 = directChild(
        contentArea, 1, "line2"
    )
    local entryScrollArea = directChild(
        contentArea, 4, "EntryScrollArea"
    )
    local container = directChild(
        entryScrollArea, 0, "container"
    )
    local text = directChild(
        container, 2, "text"
    )

    if listWrapper == nil or
       entryView == nil or
       contentArea == nil or
       line2 == nil or
       entryScrollArea == nil or
       container == nil or
       text == nil then
        return nil
    end

    return {
        contentRoot = contentRoot,
        entryView = entryView,
        line2 = line2,
        entryScrollArea = entryScrollArea,
        text = text
    }
end

local function tryApplyShardsLayoutDirect(reason)
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then return false end

    local tree = resolveShardsTree()
    if tree == nil then return false end

    local entryWidth = math.max(
        2000.0,
        geometry.contentWidth - 1860.0
    )
    local lineWidth = entryWidth - 80.0
    local scrollWidth = entryWidth - 175.0
    local textWidth = entryWidth - 400.0

    local rootSize = safe(function()
        return tree.contentRoot:GetSize()
    end)
    local entrySize = safe(function()
        return tree.entryView:GetSize()
    end)
    local lineSize = safe(function()
        return tree.line2:GetSize()
    end)
    local scrollSize = safe(function()
        return tree.entryScrollArea:GetSize()
    end)
    local textSize = safe(function()
        return tree.text:GetSize()
    end)

    if rootSize == nil or
       entrySize == nil or
       lineSize == nil or
       scrollSize == nil or
       textSize == nil then
        return false
    end

    local rootOk, rootError = pcall(function()
        tree.contentRoot:SetSize(
            geometry.contentWidth,
            rootSize.Y
        )
        tree.contentRoot:FlagForVisualInvalidation()
    end)

    local entryOk, entryError = pcall(function()
        tree.entryView:SetSize(
            entryWidth,
            entrySize.Y
        )
        tree.entryView:FlagForVisualInvalidation()
    end)

    local lineOk, lineError = pcall(function()
        tree.line2:SetSize(
            lineWidth,
            lineSize.Y
        )
        tree.line2:FlagForVisualInvalidation()
    end)

    local scrollOk, scrollError = pcall(function()
        tree.entryScrollArea:SetSize(
            scrollWidth,
            scrollSize.Y
        )
        tree.entryScrollArea:FlagForVisualInvalidation()
    end)

    local textOk, textError = pcall(function()
        tree.text:SetSize(
            textWidth,
            textSize.Y
        )
        tree.text:SetWrapping(
            false,
            textWidth,
            textWrappingPolicy.Default
        )
        tree.text:SetWrappingAtPosition(textWidth)
        tree.text:FlagForVisualInvalidation()
    end)

    local success =
        rootOk and entryOk and lineOk and scrollOk and textOk

    if success then
        disablePillars("shards " .. tostring(reason))
    end

    if ACTIVATE_DEBUG_LOGS then
        if success then
            writeDebugLog(string.format(
                "SHARDS ready checks=%d rootWidth=%.2f entryWidth=%.2f lineWidth=%.2f scrollWidth=%.2f textWidth=%.2f",
                pendingShardsLayoutChecks,
                geometry.contentWidth,
                entryWidth,
                lineWidth,
                scrollWidth,
                textWidth
            ))
        else
            if not rootOk then
                writeDebugLog(
                    "SHARDS root resize error: " .. tostring(rootError)
                )
            end
            if not entryOk then
                writeDebugLog(
                    "SHARDS entryView resize error: " ..
                    tostring(entryError)
                )
            end
            if not lineOk then
                writeDebugLog(
                    "SHARDS line2 resize error: " ..
                    tostring(lineError)
                )
            end
            if not scrollOk then
                writeDebugLog(
                    "SHARDS EntryScrollArea resize error: " ..
                    tostring(scrollError)
                )
            end
            if not textOk then
                writeDebugLog(
                    "SHARDS text resize/wrapping error: " ..
                    tostring(textError)
                )
            end
        end
    end

    return success
end

-- ---------------------------------------------------------------------------
-- GALLERY
--
-- Main Gallery only. FrameSwitcherMenuGameController derives from
-- GalleryMenuGameController, so always verify the concrete class name.
--
-- Exact tree:
-- Root[0]/Root[0]
-- └─ global wrapper[1]
--    └─ scroll_listwrapper[0]
--       └─ screenshots_area[2]
--          └─ list[0]
--
-- inputHints are intentionally untouched: widening the content Root carries
-- them naturally to the correct ultrawide position.
-- ---------------------------------------------------------------------------

local function isMainGalleryController(controller)
    if controller == nil then return false end

    local className = safe(function()
        return controller:GetClassName().value
    end)

    return className == "GalleryMenuGameController"
end

local function getGalleryScreenshotsPerPage()
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then
        return GALLERY_VANILLA_SCREENSHOTS_PER_PAGE
    end

    if geometry.contentWidth < LEGACY_21X9_CONTENT_WIDTH then
        local twoToOneWidth = 2.0 * REFERENCE_HEIGHT
        local progress = math.max(0.0, math.min(
            1.0,
            (geometry.contentWidth - twoToOneWidth) /
            (LEGACY_21X9_CONTENT_WIDTH - twoToOneWidth)
        ))
        local columns = 5 + math.floor(progress * 2.0 + 0.5)
        return columns * 2
    end

    return math.max(
        GALLERY_VANILLA_SCREENSHOTS_PER_PAGE,
        math.ceil(
            GALLERY_VANILLA_SCREENSHOTS_PER_PAGE *
            geometry.aspect / VANILLA_ASPECT - 0.000001
        )
    )
end

local function getGalleryGridGeometry(geometry)
    local screenshotsWidth = geometry.contentWidth - 500.0

    if geometry.contentWidth < LEGACY_21X9_CONTENT_WIDTH then
        local twoToOneWidth = 2.0 * REFERENCE_HEIGHT
        local narrowProgress = math.max(0.0, math.min(
            1.0,
            (geometry.contentWidth - twoToOneWidth) /
            (LEGACY_21X9_CONTENT_WIDTH - twoToOneWidth)
        ))

        screenshotsWidth =
            3320.0 + (4660.0 - 3320.0) * narrowProgress
    end

    local listLeftMargin = math.max(0.0, math.min(
        200.0,
        200.0 *
        (geometry.contentWidth - LEGACY_21X9_CONTENT_WIDTH) /
        (7680.0 - LEGACY_21X9_CONTENT_WIDTH)
    ))

    return screenshotsWidth, listLeftMargin
end

local function resolveGalleryTree()
    local _, _, contentRoot = getMenuContentRoot()
    if contentRoot == nil then return nil end

    local globalWrapper = directChild(
        contentRoot, 1, "global wrapper"
    )
    local scrollListWrapper = directChild(
        globalWrapper, 0, "scroll_listwrapper"
    )
    local screenshotsArea = directChild(
        scrollListWrapper, 2, "screenshots_area"
    )
    local list = directChild(
        screenshotsArea, 0, "list"
    )

    if globalWrapper == nil or
       scrollListWrapper == nil or
       screenshotsArea == nil or
       list == nil then
        return nil
    end

    return {
        contentRoot = contentRoot,
        screenshotsArea = screenshotsArea,
        list = list
    }
end

local function tryApplyGalleryLayoutDirect(reason)
    local screenGeometry = getTargetGeometry()
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then return false end

    local tree = resolveGalleryTree()
    if tree == nil then return false end

    local screenshotsWidth, listLeftMargin =
        getGalleryGridGeometry(geometry)

    local contentSize = safe(function()
        return tree.contentRoot:GetSize()
    end)
    local areaSize = safe(function()
        return tree.screenshotsArea:GetSize()
    end)
    local listSize = safe(function()
        return tree.list:GetSize()
    end)
    local listMargin = safe(function()
        return tree.list:GetMargin()
    end)

    if contentSize == nil or areaSize == nil or
       listSize == nil or listMargin == nil then
        return false
    end

    local rootOk, rootError = pcall(function()
        tree.contentRoot:SetSize(
            geometry.contentWidth,
            contentSize.Y
        )
        tree.contentRoot:FlagForVisualInvalidation()
    end)

    local areaOk, areaError = pcall(function()
        tree.screenshotsArea:SetSize(
            screenshotsWidth,
            areaSize.Y
        )
        tree.screenshotsArea:FlagForVisualInvalidation()
    end)

    local listOk, listError = pcall(function()
        tree.list:SetSize(
            screenshotsWidth,
            listSize.Y
        )
        tree.list:SetMargin(
            listLeftMargin,
            listMargin.top,
            listMargin.right,
            listMargin.bottom
        )
        tree.list:FlagForVisualInvalidation()
    end)

    local success = rootOk and areaOk and listOk

    if success then
        disablePillars("gallery " .. tostring(reason))
    end

    if ACTIVATE_DEBUG_LOGS then
        if success then
            writeDebugLog(string.format(
                "GALLERY ready checks=%d rootWidth=%.2f screenshotsWidth=%.2f listLeft=%.2f",
                pendingGalleryLayoutChecks,
                geometry.contentWidth,
                screenshotsWidth,
                listLeftMargin
            ))
        else
            if not rootOk then
                writeDebugLog(
                    "GALLERY root resize error: " .. tostring(rootError)
                )
            end
            if not areaOk then
                writeDebugLog(
                    "GALLERY screenshots_area resize error: " ..
                    tostring(areaError)
                )
            end
            if not listOk then
                writeDebugLog(
                    "GALLERY list resize error: " .. tostring(listError)
                )
            end
        end
    end

    return success
end

-- ---------------------------------------------------------------------------
-- GAME NOTIFICATION POPUPS
--
-- Exact Ink path:
-- inkGameNotificationsLayer/inkVirtualWindow
-- └─ Root[0]
--    └─ NotificationsContainer[1]
--       └─ UNINITIALIZED_WIDGET[0]
--          └─ Root[0]
-- ---------------------------------------------------------------------------

getGameNotificationsVirtualWindow = function()
    local layer = safe(function()
        return Game.GetInkSystem():GetLayer(
            CName.new("inkGameNotificationsLayer")
        )
    end)
    if layer == nil then return nil end

    return safe(function()
        return layer:GetVirtualWindow()
    end)
end

local function resolveNotificationPopupRoot(expectedRootName)
    local virtualWindow = getGameNotificationsVirtualWindow()
    if virtualWindow == nil then return nil, nil end

    local layerRoot = directChild(
        virtualWindow, 0, "Root"
    )
    local notificationsContainer = directChild(
        layerRoot, 1, "NotificationsContainer"
    )
    local slot = directChild(
        notificationsContainer, 0, "UNINITIALIZED_WIDGET"
    )
    local popupRoot = directChild(
        slot, 0, expectedRootName or "Root"
    )

    local galleryBackground = nil
    if popupRoot ~= nil and
       (expectedRootName == nil or expectedRootName == "Root") then
        galleryBackground = directChild(
            popupRoot, 2, "bg"
        )
    end

    return popupRoot, galleryBackground
end

local function tryApplyNotificationPopupWidth(reason, resizeGalleryBackground, expectedRootName)
    local geometry = getTargetGeometry()
    if geometry == nil then return false end

    local popupRoot, galleryBackground =
        resolveNotificationPopupRoot(expectedRootName)

    if popupRoot == nil then return false end

    local rootSize = safe(function()
        return popupRoot:GetSize()
    end)
    if rootSize == nil then return false end

    local rootBeforeWidth = rootSize.X
    local rootHeight = rootSize.Y

    local rootOk, rootError = pcall(function()
        popupRoot:SetSize(
            geometry.contentWidth,
            rootHeight
        )
        popupRoot:FlagForVisualInvalidation()
    end)

    local bgOk = true
    local bgError = nil
    local bgBeforeWidth = nil
    local bgHeight = nil

    if resizeGalleryBackground then
        if galleryBackground == nil then
            return false
        end

        local bgSize = safe(function()
            return galleryBackground:GetSize()
        end)
        if bgSize == nil then
            return false
        end

        bgBeforeWidth = bgSize.X
        bgHeight = bgSize.Y

        bgOk, bgError = pcall(function()
            galleryBackground:SetSize(
                geometry.contentWidth,
                bgHeight
            )
            galleryBackground:FlagForVisualInvalidation()
        end)
    end

    local success = rootOk and bgOk

    if ACTIVATE_DEBUG_LOGS then
        if success then
            if resizeGalleryBackground then
                writeDebugLog(string.format(
                    "NOTIFICATION POPUP resized (%s) root %.2fx%.2f -> %.2fx%.2f | bg %.2fx%.2f -> %.2fx%.2f checks=%d",
                    tostring(reason),
                    rootBeforeWidth,
                    rootHeight,
                    geometry.contentWidth,
                    rootHeight,
                    bgBeforeWidth,
                    bgHeight,
                    geometry.contentWidth,
                    bgHeight,
                    pendingNotificationPopupChecks
                ))
            else
                writeDebugLog(string.format(
                    "NOTIFICATION POPUP resized (%s) %.2fx%.2f -> %.2fx%.2f checks=%d",
                    tostring(reason),
                    rootBeforeWidth,
                    rootHeight,
                    geometry.contentWidth,
                    rootHeight,
                    pendingNotificationPopupChecks
                ))
            end
        else
            if not rootOk then
                writeDebugLog(
                    "NOTIFICATION POPUP root resize error: " ..
                    tostring(rootError)
                )
            end
            if not bgOk then
                writeDebugLog(
                    "NOTIFICATION POPUP bg resize error: " ..
                    tostring(bgError)
                )
            end
        end
    end

    return success
end

-- ---------------------------------------------------------------------------
-- CHARACTER
--
-- Keep the authored 3840x2160 Character UI centered. Only extend the three
-- tiled master backgrounds horizontally and move Character's own button hints
-- to the ultrawide right edge.
--
-- Exact tree:
--
-- Root[0]/Root[0]
-- ├─ button_hints[3]
-- ├─ tabsContainer[9]
-- │  └─ Root[0]
-- │     └─ master_BG[5]
-- ├─ perksScreenWrapper[10]
-- │  └─ Root[0]
-- │     └─ master_BG[7]
-- └─ master_BG[17]
--
-- At 3440x1440:
--   scaleX = 5160 / 3840 = 1.34375
--   button_hints right margin: 100 -> -560
--
-- No Character Root resize.
-- No recursive scans.
-- No Character-specific Right_fluff.
-- Exact-path readiness watch only; stops after first successful scale pass.
-- ---------------------------------------------------------------------------

local function resolveCharacterBackgrounds()
    local _, _, contentRoot = getMenuContentRoot()
    if contentRoot == nil then
        return nil, nil, nil, nil
    end

    local tabsContainer = directChild(
        contentRoot, 9, "tabsContainer"
    )
    local tabsRoot = directChild(
        tabsContainer, 0, "Root"
    )
    local tabsMasterBG = directChild(
        tabsRoot, 5, "master_BG"
    )

    local perksScreenWrapper = directChild(
        contentRoot, 10, "perksScreenWrapper"
    )
    local perksRoot = directChild(
        perksScreenWrapper, 0, "Root"
    )
    local perksMasterBG = directChild(
        perksRoot, 7, "master_BG"
    )

    local rootMasterBG = directChild(
        contentRoot, 17, "master_BG"
    )

    return contentRoot, tabsMasterBG, perksMasterBG, rootMasterBG
end

-- Perks-only Ink 4096 safety mode. Never change the Hub's ordinary layout.
-- Strictly gated by REAL display width, and by the perk-category controller.
local perk4096 = { active = false, pending = false, applied = false }

function perk4096.enabled()
    if not perk4096.active then return false end
    local w = safe(function() return GetDisplayResolution() end)
    if type(w) ~= "number" or w <= 4096 then return false end
    local contentRoot = select(1, resolveCharacterBackgrounds())
    local wrapper = directChild(contentRoot, 10, "perksScreenWrapper")
    -- NewPerksCategoriesGameController can initialize on Character, too.
    -- Apply only once the actual perk tree wrapper is visible.
    return wrapper ~= nil and safe(function() return wrapper:IsVisible() end) == true
end

function perk4096.apply()
    if not perk4096.enabled() then return false end
    local _, _, hubRoot = resolveHubContentRoot(hubController)
    local characterRoot, tabsBG, perksBG, rootBG = resolveCharacterBackgrounds()
    if hubRoot == nil or characterRoot == nil or
       tabsBG == nil or perksBG == nil or rootBG == nil then
        return false
    end

    -- Same four Ink Inspector mutations that removed clipping, except that
    -- backgrounds are hidden rather than left visibly bounded at 4096.
    local widthOK = setWidgetWidth(hubRoot, 4096.0)
    local bgOK = pcall(function()
        tabsBG:SetVisible(false)
        perksBG:SetVisible(false)
        rootBG:SetVisible(false)
    end)

    -- Decorations on the shared Hub branch must follow the reduced width
    -- for as long as the perk tree is onscreen.
    local decor = directChild(hubRoot, 7, "Root")
    if decor ~= nil then
        setWidgetWidth(decor, 4096.0)
        local fluff = directChild(decor, 0, "Right_fluff_elements")
        if fluff ~= nil then
            pcall(function() fluff:SetMargin(125.0, -5.0, 0.0, 0.0) end)
        end
        local lines = directChild(decor, 4, "Right_lines")
        if lines ~= nil then
            pcall(function() lines:SetMargin(4041.0, 0.0, 0.0, 0.0) end)
        end
    end

    -- Perks hints are positioned by perk4096.fixHints() after transitions.

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("PERKS 4096 applied root=" .. tostring(widthOK) ..
            " backgrounds=" .. tostring(bgOK))
    end
    if widthOK and bgOK then perk4096.applied = true end
    return widthOK and bgOK
end

function perk4096.restore()
    perk4096.applied = false
    perk4096.pending = false
    local characterRoot, tabsBG, perksBG, rootBG = resolveCharacterBackgrounds()
    if tabsBG ~= nil and perksBG ~= nil and rootBG ~= nil then
        pcall(function()
            tabsBG:SetVisible(true)
            perksBG:SetVisible(true)
            rootBG:SetVisible(true)
        end)
    end
    -- Restore the original Hub code paths (including its decorative branch).
    if hubController ~= nil then
        applyHubImmediate(nil)
        finalizeHubDecor(nil)
    end
end

-- On the Character controller, button_hints[3] is anchored to the right side
-- of the fixed 3840-wide content Root (whose screen right is x=4480 at 5120).
-- Keep Character's full UI Spread position, but move it to the 4096-wide
-- safe area only while the perk tree is visible. Use absolute authored margin
-- (right=100) rather than the shared hint cache, which may have been seeded
-- from an already adjusted value when the same Ink widget was reused.
function perk4096.fixHints()
    if not perk4096.active then return end
    local screenGeometry = getTargetGeometry()
    if screenGeometry == nil or screenGeometry.displayWidth <= 4096 then return end
    local contentRoot = select(1, resolveCharacterBackgrounds())
    local hints = directChild(contentRoot, 3, "button_hints")
    if hints == nil then return end
    local geometry = getUISpreadGeometry(screenGeometry)
    if geometry == nil then return end
    local offset = geometry.halfExtra
    if perk4096.enabled() then
        offset = (4096.0 - VANILLA_CONTENT_WIDTH) * geometry.uiSpread * 0.5
    end
    local targetRight = 100.0 - offset
    local margin = safe(function() return hints:GetMargin() end)
    if margin == nil or math.abs(margin.right - targetRight) <= 0.05 then return end
    pcall(function()
        hints:SetMargin(margin.left, margin.top, targetRight, margin.bottom)
    end)
end

local function setCharacterBackgroundScaleX(widget, scaleX, label)
    if widget == nil then return false end

    local currentScale = safe(function()
        return widget:GetScale()
    end)
    if currentScale == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "CHARACTER " .. tostring(label) ..
                " scale mutation failed: GetScale() returned nil"
            )
        end
        return false
    end

    local ok, errorMessage = pcall(function()
        widget:SetScale(Vector2.new({
            X = scaleX,
            Y = currentScale.Y
        }))
        widget:FlagForVisualInvalidation()
    end)

    if not ok and ACTIVATE_DEBUG_LOGS then
        writeDebugLog(
            "CHARACTER " .. tostring(label) ..
            " scale mutation error: " .. tostring(errorMessage)
        )
    end

    return ok
end

local function tryFinalizeCharacterBackgrounds(reason)
    local geometry = getTargetGeometry()
    if geometry == nil then
        return false
    end

    local contentRoot, tabsMasterBG, perksMasterBG, rootMasterBG =
        resolveCharacterBackgrounds()

    if contentRoot == nil or
       tabsMasterBG == nil or
       perksMasterBG == nil or
       rootMasterBG == nil then

        return false
    end

    disablePillars("character " .. tostring(reason))

    local scaleX =
        geometry.contentWidth / VANILLA_CONTENT_WIDTH

    local tabsBgOk = setCharacterBackgroundScaleX(
        tabsMasterBG, scaleX, "tabs master_BG"
    )
    local perksBgOk = setCharacterBackgroundScaleX(
        perksMasterBG, scaleX, "perks master_BG"
    )
    local rootBgOk = setCharacterBackgroundScaleX(
        rootMasterBG, scaleX, "root master_BG"
    )

    local success = tabsBgOk and perksBgOk and rootBgOk

    if ACTIVATE_DEBUG_LOGS then
        local tabsScale = safe(function()
            return tabsMasterBG:GetScale()
        end)
        local perksScale = safe(function()
            return perksMasterBG:GetScale()
        end)
        local rootScale = safe(function()
            return rootMasterBG:GetScale()
        end)

        writeDebugLog(string.format(
            "CHARACTER ready checks=%d scaleX=%.6f mutations=[%s,%s,%s] afterX=[%.6f,%.6f,%.6f]",
            pendingCharacterChecks,
            scaleX,
            tostring(tabsBgOk),
            tostring(perksBgOk),
            tostring(rootBgOk),
            tabsScale ~= nil and tabsScale.X or -1,
            perksScale ~= nil and perksScale.X or -1,
            rootScale ~= nil and rootScale.X or -1
        ))
    end

    return success
end

-- ---------------------------------------------------------------------------
-- LOADING SCREEN
--
-- Runtime dump signature (Fast Travel loading screen):
--
-- inkLoadingLayer/inkVirtualWindow
-- └─ Root[0]                              3840x2160, centered, scale 2/3
--    └─ Root[0]                           3840x2160
--       ├─ SolidBGColor[0]                Fill
--       ├─ BGImageContainer[1]            static loading image
--       ├─ Background[2]                  video, Fill
--       ├─ fluff_elements[3]              3840x2160
--       │  ├─ fact_lines[0]               3840x2160
--       │  ├─ borders[1]                  3840x2160
--       │  ├─ top_fluff[2]                3840x2160
--       │  ├─ bottom_right[3]             authored absolute/right-edge carrier
--       │  └─ bg[4]                       3840x2160
--       ├─ Line1[4]
--       ├─ Line2[5]
--       └─ Line3[6]
--
-- The ultrawide treatment keeps the authored black vector bands at their
-- vanilla geometry and extends only their flat tails:
--   * top_black remains vanilla 3841x285, anchored left;
--     a flat black rectangle extends only its right-hand tail.
--   * bottom_black remains vanilla 3841x285, anchored right;
--     a flat black rectangle extends only its left-hand tail.
--   * top cut stays 1000 logical units from the LEFT edge of the UI canvas.
--   * bottom cut is already visually correct and remains untouched.
--
-- Vanilla dump:
--   root starts at physical x=440
--   top break is at physical x=1106.6667
--   delta = 666.6667 px = 1000 logical units at the 2/3 loading scale.
--
-- Keep that same edge spacing when the root expands to ultrawide.
-- This preserves the authored sloped/cut geometry instead of asking an
-- inkShapeWidget to reinterpret its vector path at 5160 width.
-- ---------------------------------------------------------------------------

-- Resolve the common inkLoadingLayer root pair without relying on a parent
-- backlink from a controller-owned root. Codeware exposes the global Ink
-- layers used here. Exact indices/names only; no tree scan.
local function getLoadingContentRootExact()
    local inkSystem = safe(function()
        return Game.GetInkSystem()
    end)
    if inkSystem == nil then return nil, nil, nil end

    local layer = safe(function()
        return inkSystem:GetLayer(CName.new("inkLoadingLayer"))
    end)
    if layer == nil then return nil, nil, nil end

    local virtualWindow = safe(function()
        return layer:GetVirtualWindow()
    end)
    if virtualWindow == nil then return nil, nil, nil end

    local outerRoot = safe(function()
        return virtualWindow:GetWidget(0)
    end)
    if outerRoot == nil or widgetName(outerRoot) ~= "Root" then
        return virtualWindow, nil, nil
    end

    local contentRoot = directChild(outerRoot, 0, "Root")
    if contentRoot == nil then
        return virtualWindow, outerRoot, nil
    end

    return virtualWindow, outerRoot, contentRoot
end

local function resolveLoadingRootPairExact(controller)
    local contentRoot = controller ~= nil and safe(function()
        return controller:GetRootWidget()
    end) or nil

    if contentRoot ~= nil and widgetName(contentRoot) == "Root" then
        local outerRoot = safe(function()
            return contentRoot:GetParentWidget()
        end)
        if outerRoot ~= nil and widgetName(outerRoot) == "Root" then
            return outerRoot, contentRoot, "controller parent"
        end
    end

    local _, globalOuterRoot, globalContentRoot =
        getLoadingContentRootExact()
    if globalOuterRoot == nil or globalContentRoot == nil then
        return nil, nil, nil
    end

    return globalOuterRoot, globalContentRoot,
        "global inkLoadingLayer fallback"
end

local function resolveLoadingScreenTreeExact(controller)
    if controller == nil then return nil end

    local outerRoot, contentRoot, resolutionSource =
        resolveLoadingRootPairExact(controller)
    if outerRoot == nil or contentRoot == nil then
        return nil
    end

    local solidBG = directChild(contentRoot, 0, "SolidBGColor")
    local bgImageContainer = directChild(contentRoot, 1, "BGImageContainer")
    local backgroundVideo = directChild(contentRoot, 2, "Background")
    local fluffElements = directChild(contentRoot, 3, "fluff_elements")

    if solidBG == nil or bgImageContainer == nil or
       backgroundVideo == nil or fluffElements == nil then
        return nil
    end

    local mainImage = directChild(bgImageContainer, 0, "MainImage")
    local extendingImage = directChild(
        bgImageContainer,
        1,
        "ExtendingIMage"
    )

    if mainImage == nil or extendingImage == nil then
        return nil
    end

    local factLines = directChild(fluffElements, 0, "fact_lines")
    local borders = directChild(fluffElements, 1, "borders")
    local topFluff = directChild(fluffElements, 2, "top_fluff")
    local bottomRight = directChild(fluffElements, 3, "bottom_right")
    local bg = directChild(fluffElements, 4, "bg")

    if factLines == nil or borders == nil or topFluff == nil or
       bottomRight == nil or bg == nil then
        return nil
    end

    local topLine = directChild(borders, 0, "topline")
    local botLine = directChild(borders, 1, "botline")
    local bottomCutCornerLine = directChild(
        borders,
        6,
        "bottomCutCornerLine"
    )
    local topCutCornerLine = directChild(
        borders,
        7,
        "topCutCornerLine"
    )

    if topLine == nil or botLine == nil or
       bottomCutCornerLine == nil or topCutCornerLine == nil then
        return nil
    end

    local bottomCutFlexR = directChild(
        bottomCutCornerLine,
        1,
        "flexR"
    )
    local topCutFlexR = directChild(
        topCutCornerLine,
        1,
        "flexR"
    )

    if bottomCutFlexR == nil or topCutFlexR == nil then
        return nil
    end

    -- Horizontal-panel sizing is actually driven by this hidden child:
    -- it is visible=false but affectsLayoutWhenHidden=true and carries the
    -- authored 2840x20 desired width. SetSize() on flexR itself does not move
    -- the split point.
    local topCutLayoutDriver = directChild(
        topCutFlexR,
        1,
        "inkBorderWidget4"
    )
    local bottomCutLayoutDriver = directChild(
        bottomCutFlexR,
        1,
        "inkBorderWidget4"
    )

    if topCutLayoutDriver == nil or bottomCutLayoutDriver == nil then
        return nil
    end

    local topBlack = directChild(bg, 0, "top_black")
    local bottomBlack = directChild(bg, 1, "bottom_black")
    local binksHere = directChild(bg, 2, "binks_here")

    if topBlack == nil or bottomBlack == nil or binksHere == nil then
        return nil
    end

    return {
        outerRoot = outerRoot,
        contentRoot = contentRoot,
        solidBG = solidBG,
        bgImageContainer = bgImageContainer,
        mainImage = mainImage,
        extendingImage = extendingImage,
        backgroundVideo = backgroundVideo,
        fluffElements = fluffElements,
        factLines = factLines,
        borders = borders,
        topFluff = topFluff,
        bottomRight = bottomRight,
        bg = bg,
        topLine = topLine,
        botLine = botLine,
        bottomCutCornerLine = bottomCutCornerLine,
        topCutCornerLine = topCutCornerLine,
        bottomCutFlexR = bottomCutFlexR,
        topCutFlexR = topCutFlexR,
        bottomCutLayoutDriver = bottomCutLayoutDriver,
        topCutLayoutDriver = topCutLayoutDriver,
        topBlack = topBlack,
        bottomBlack = bottomBlack,
        binksHere = binksHere,
        resolutionSource = resolutionSource
    }
end

-- Default checkpoint / quickload loading screen runtime signature:
--
-- inkLoadingLayer/inkVirtualWindow
-- └─ Root[0]                              3840x2160, centered / scaled
--    └─ Root[0]                           3840x2160
--       ├─ loading_progress[0]             authored UI, intentionally untouched
--       └─ inkRectangleWidget3[1]          opaque black Fill mask
--
-- The mask already fills the vanilla content Root, but because that Root stays
-- centered at 16:9 the streaming world can become visible in the ultrawide side
-- regions during checkpoint reload / quickload transitions. Extend only the
-- mask with symmetric negative horizontal margins. Canvas children are allowed
-- to render outside their parent bounds, so no Root or progress-bar geometry
-- needs to change.
function UWUI_resolveDefaultLoadingMaskExact(controller)
    if controller == nil then return nil end

    local outerRoot, contentRoot, resolutionSource =
        resolveLoadingRootPairExact(controller)
    if outerRoot == nil or contentRoot == nil then
        return nil
    end

    local loadingProgress = directChild(
        contentRoot,
        0,
        "loading_progress"
    )
    local blackMask = directChild(
        contentRoot,
        1,
        "inkRectangleWidget3"
    )

    if loadingProgress == nil or blackMask == nil then
        return nil
    end

    return {
        outerRoot = outerRoot,
        contentRoot = contentRoot,
        loadingProgress = loadingProgress,
        blackMask = blackMask,
        resolutionSource = resolutionSource
    }
end

function UWUI_applyDefaultLoadingMaskExact(controller, reason)
    local screenGeometry = getTargetGeometry()
    local logThis = ACTIVATE_DEBUG_LOGS and reason ~= nil

    if screenGeometry == nil or controller == nil then
        if logThis then
            writeDebugLog(
                "DEFAULT LOADING mask aborted: geometry/controller unavailable"
            )
        end
        return false
    end

    local tree = UWUI_resolveDefaultLoadingMaskExact(controller)
    if tree == nil then
        if logThis then
            writeDebugLog(
                "DEFAULT LOADING mask pending: exact loading_progress / black mask tree not ready"
            )
        end
        return false
    end

    -- Preserve the authored -1 logical-unit left bleed visible in the vanilla
    -- dump, then add physical ultrawide halfExtra symmetrically. This is
    -- idempotent: every pass writes the same absolute target margins.
    local halfExtra = screenGeometry.halfExtra
    local targetLeft = -(halfExtra + 1.0)
    local targetRight = -halfExtra

    local beforeMargin = nil
    if logThis then
        beforeMargin = safe(function()
            return tree.blackMask:GetMargin()
        end)
    end

    local maskOk = pcall(function()
        tree.blackMask:SetMargin(
            targetLeft,
            0.0,
            targetRight,
            0.0
        )
        tree.blackMask:FlagForVisualInvalidation()
    end)

    if logThis then
        local before = beforeMargin ~= nil and string.format(
            "[%.2f,%.2f,%.2f,%.2f]",
            beforeMargin.left or -9999.0,
            beforeMargin.top or -9999.0,
            beforeMargin.right or -9999.0,
            beforeMargin.bottom or -9999.0
        ) or "n/a"

        writeDebugLog(string.format(
            "DEFAULT LOADING mask %s | resolver=%s physicalWidth=%.2f halfExtra=%.2f margin=%s -> [%.2f,0.00,%.2f,0.00] applied=%s",
            tostring(reason),
            tostring(tree.resolutionSource),
            screenGeometry.contentWidth,
            halfExtra,
            before,
            targetLeft,
            targetRight,
            tostring(maskOk)
        ))
    elseif maskOk and ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "DEFAULT LOADING exact tree ready; black concealment mask extended to UW edges (halfExtra=%.2f)",
            halfExtra
        ))
    end

    return maskOk and releaseLoadingPillarsIfReady(
        "default loading mask ready"
    )
end

-- The initial-loading controller and LoadingPartsContainer[5] are common to
-- the observed loading compositions. Everything below this container is
-- treated structurally: no scene-specific widget names, indices or shot count.
-- Only direct scene slots and their single-child, fullscreen canvas wrappers
-- are traversed; internal image/video/lighting groups are never scanned.
local function initialLoadingIsFullFrameCanvas(widget)
    if widget == nil then return false end

    local className = safe(function()
        return widget:GetClassName().value
    end)
    if className ~= "inkCanvasWidget" then return false end

    local size = safe(function() return widget:GetSize() end)
    if size == nil then return false end

    return math.abs(size.X - VANILLA_CONTENT_WIDTH) < 1.0 and
        math.abs(size.Y - REFERENCE_HEIGHT) < 1.0
end

local function resolveInitialLoadingSceneTreeExact(controller)
    if controller == nil then return nil end

    local outerRoot, contentRoot, resolutionSource =
        resolveLoadingRootPairExact(controller)
    if outerRoot == nil or contentRoot == nil then
        return nil
    end

    local loadingPartsContainer = directChild(
        contentRoot,
        5,
        "LoadingPartsContainer"
    )
    if loadingPartsContainer == nil then return nil end

    local sceneCount = safe(function()
        return loadingPartsContainer:GetNumChildren()
    end)
    if sceneCount == nil or sceneCount < 1 then return nil end

    local scenes = {}
    for index = 0, sceneCount - 1 do
        local scene = directChild(loadingPartsContainer, index)
        if not initialLoadingIsFullFrameCanvas(scene) then
            -- Incomplete construction: retain the exact readiness watch.
            return nil
        end

        local wrapperDepth = 0
        while wrapperDepth < 8 do
            local childCount = safe(function()
                return scene:GetNumChildren()
            end)
            if childCount == nil then return nil end
            if childCount ~= 1 then break end

            local soleChild = directChild(scene, 0)
            if soleChild == nil then return nil end
            if not initialLoadingIsFullFrameCanvas(soleChild) then
                break
            end

            -- The parent's sole child is itself a fullscreen canvas.
            -- Mutate only the deepest such canvas, not both levels.
            scene = soleChild
            wrapperDepth = wrapperDepth + 1
        end

        -- An entirely empty scene canvas is not attached enough to be refit.
        local contents = safe(function()
            return scene:GetNumChildren()
        end)
        if contents == nil or contents < 1 then return nil end

        scenes[#scenes + 1] = {
            index = index,
            widget = scene,
            wrapperDepth = wrapperDepth
        }
    end

    return {
        outerRoot = outerRoot,
        contentRoot = contentRoot,
        loadingPartsContainer = loadingPartsContainer,
        scenes = scenes,
        resolutionSource = resolutionSource
    }
end

local function applyInitialLoadingSceneCoverExact(controller, reason)
    local screenGeometry = getTargetGeometry()
    local logThis = ACTIVATE_DEBUG_LOGS and reason ~= nil

    if screenGeometry == nil or controller == nil then
        if logThis then
            writeDebugLog(
                "INITIAL LOADING cover aborted: geometry/controller unavailable"
            )
        end
        return false
    end

    local tree = resolveInitialLoadingSceneTreeExact(controller)
    if tree == nil then
        if logThis then
            writeDebugLog(
                "INITIAL LOADING cover pending: shared container/scene canvases not ready"
            )
        end
        return false
    end

    -- Fullscreen loading backgrounds follow physical screen geometry,
    -- independently from UI Spread. Preserve the b17-validated cover math.
    local physicalWidth = screenGeometry.contentWidth
    local coverScale = physicalWidth / VANILLA_CONTENT_WIDTH
    local horizontalOffset =
        (physicalWidth - VANILLA_CONTENT_WIDTH) * 0.5
    local verticalCrop =
        (REFERENCE_HEIGHT * coverScale - REFERENCE_HEIGHT) * 0.5

    local outerBefore = nil
    if logThis then
        outerBefore = debugWidgetSize(tree.outerRoot)
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog(
            "INITIAL LOADING generic cover BEGIN: " .. tostring(reason)
        )
        writeDebugLog(string.format(
            "geometry screenAspect=%.6f physicalWidth=%.2f coverScale=%.6f horizontalOffset=%.2f verticalCrop=%.2f | outer=%s -> %.2fx%.2f | sceneCount=%d | resolver=%s",
            screenGeometry.aspect,
            physicalWidth,
            coverScale,
            horizontalOffset,
            verticalCrop,
            tostring(outerBefore),
            physicalWidth,
            REFERENCE_HEIGHT,
            #tree.scenes,
            tostring(tree.resolutionSource)
        ))
    end

    local outerOk = setWidgetSizeExact(
        tree.outerRoot,
        physicalWidth,
        REFERENCE_HEIGHT
    )

    local scenesOk = true
    for _, entry in ipairs(tree.scenes) do
        local scene = entry.widget
        local beforeScale = nil
        local beforeTranslation = nil
        if logThis then
            beforeScale = safe(function()
                return scene:GetScale()
            end)
            beforeTranslation = safe(function()
                return scene:GetTranslation()
            end)
        end

        local sceneOk = pcall(function()
            scene:SetScale(Vector2.new({
                X = coverScale,
                Y = coverScale
            }))
            scene:SetTranslation(Vector2.new({
                X = horizontalOffset,
                Y = -verticalCrop
            }))
            scene:SetMargin(0.0, 0.0, 0.0, 0.0)
            scene:FlagForVisualInvalidation()
        end)
        scenesOk = scenesOk and sceneOk

        if logThis then
            local oldScale = beforeScale ~= nil and string.format(
                "[%.5f,%.5f]", beforeScale.X, beforeScale.Y
            ) or "n/a"
            local oldTranslation = beforeTranslation ~= nil and string.format(
                "[%.2f,%.2f]", beforeTranslation.X, beforeTranslation.Y
            ) or "n/a"
            writeDebugLog(string.format(
                "scene[%d] wrapperDepth=%d scale=%s -> [%.5f,%.5f] translation=%s -> [%.2f,%.2f] applied=%s",
                entry.index,
                entry.wrapperDepth,
                oldScale,
                coverScale,
                coverScale,
                oldTranslation,
                horizontalOffset,
                -verticalCrop,
                tostring(sceneOk)
            ))
        end
    end

    local applied = outerOk and scenesOk
    if logThis then
        writeDebugLog(string.format(
            "INITIAL LOADING generic cover END: outer=%s scenes=%s applied=%s",
            tostring(outerOk),
            tostring(scenesOk),
            tostring(applied)
        ))
    elseif applied and ACTIVATE_DEBUG_LOGS then
        local depths = {}
        for _, entry in ipairs(tree.scenes) do
            depths[#depths + 1] = string.format(
                "%d:%d", entry.index, entry.wrapperDepth
            )
        end
        writeDebugLog(string.format(
            "INITIAL LOADING generic exact tree ready: %d scenes depths=[%s]; cover/root refit applied",
            #tree.scenes,
            table.concat(depths, ",")
        ))
    end

    return applied and releaseLoadingPillarsIfReady(
        "initial loading scene cover ready"
    )
end

local function applyLoadingScreenLayoutExact(controller, reason)
    local screenGeometry = getTargetGeometry()
    if screenGeometry == nil or controller == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "LOADING SCREEN aborted: geometry/controller unavailable"
            )
        end
        return false
    end

    local tree = resolveLoadingScreenTreeExact(controller)
    if tree == nil then
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "LOADING SCREEN aborted: exact FastTravel loading tree not found"
            )
        end
        return false
    end

    local beforeOuter = nil
    local beforeContent = nil
    local beforeFluff = nil
    local beforeTopBlack = nil
    local beforeBottomBlack = nil
    local beforeMainImage = nil
    local beforeBGImageScale = nil
    local beforeTopCutFlex = nil
    local beforeBottomCutFlex = nil
    local beforeTopCutDriver = nil
    local beforeBottomCutDriver = nil

    if ACTIVATE_DEBUG_LOGS then
        beforeOuter = debugWidgetSize(tree.outerRoot)
        beforeContent = debugWidgetSize(tree.contentRoot)
        beforeFluff = debugWidgetSize(tree.fluffElements)
        beforeTopBlack = debugWidgetSize(tree.topBlack)
        beforeBottomBlack = debugWidgetSize(tree.bottomBlack)
        beforeMainImage = debugWidgetSize(tree.mainImage)
        beforeBGImageScale = safe(function()
            return tree.bgImageContainer:GetScale()
        end)
        beforeTopCutFlex = debugWidgetSize(tree.topCutFlexR)
        beforeBottomCutFlex = debugWidgetSize(tree.bottomCutFlexR)
        beforeTopCutDriver = debugWidgetSize(tree.topCutLayoutDriver)
        beforeBottomCutDriver = debugWidgetSize(tree.bottomCutLayoutDriver)
    end

    -- Loading screens are fullscreen presentations. Their refit must always
    -- use the physical ultrawide viewport and must never be constrained by
    -- the UI Spread setting.
    local width = screenGeometry.contentWidth

    local outerOk = setWidgetSizeExact(
        tree.outerRoot, width, REFERENCE_HEIGHT
    )
    local contentOk = setWidgetSizeExact(
        tree.contentRoot, width, REFERENCE_HEIGHT
    )
    local fluffOk = setWidgetSizeExact(
        tree.fluffElements, width, REFERENCE_HEIGHT
    )
    local factsOk = setWidgetSizeExact(
        tree.factLines, width, REFERENCE_HEIGHT
    )
    local bordersOk = setWidgetSizeExact(
        tree.borders, width, REFERENCE_HEIGHT
    )
    local topFluffOk = setWidgetSizeExact(
        tree.topFluff, width, REFERENCE_HEIGHT
    )
    local bgOk = setWidgetSizeExact(
        tree.bg, width, REFERENCE_HEIGHT
    )

    -- Keep the animated BGImageContainer scale completely untouched.
    -- MainImage is authored at 3840x1600 (2.40:1). Grow only its base geometry
    -- so, after the container's existing scale, it covers the UWUI width while
    -- retaining that exact aspect ratio.
    local mainImageOk = true
    local targetMainImageWidth = nil
    local targetMainImageHeight = nil

    if width > VANILLA_CONTENT_WIDTH + 0.5 then
        mainImageOk = false

        local bgScale = safe(function()
            return tree.bgImageContainer:GetScale()
        end)

        if bgScale ~= nil and
           (bgScale.X or 0.0) > 0.0001 and
           (bgScale.Y or 0.0) > 0.0001 then
            local renderedHeight =
                width * (1600.0 / VANILLA_CONTENT_WIDTH)

            targetMainImageWidth =
                width / bgScale.X
            targetMainImageHeight =
                renderedHeight / bgScale.Y

            mainImageOk = pcall(function()
                tree.mainImage:SetFitToContent(false)
                tree.mainImage:SetSize(
                    targetMainImageWidth,
                    targetMainImageHeight
                )
                tree.mainImage:FlagForVisualInvalidation()
                tree.bgImageContainer:FlagForVisualInvalidation()
            end)
        end
    end

    -- Preserve the vanilla TOP cut spacing from the LEFT edge of the
    -- loading UI canvas. In the stock dump:
    --
    --   root left = 440 px
    --   top break = 1106.6667 px
    --   delta     = 666.6667 px = 1000 logical units at scale 2/3.
    --
    -- The bottom cut is already visually correct; do not alter it.
    local topCutLeftOffset = 1000.0

    local topCutTargetWidth =
        math.max(0.0, width - topCutLeftOffset)

    local topCutOk = pcall(function()
        -- This hidden border is the flex child's desired-width driver.
        tree.topCutLayoutDriver:SetSize(
            topCutTargetWidth,
            20.0
        )
        tree.topCutLayoutDriver:FlagForVisualInvalidation()
        tree.topCutFlexR:FlagForVisualInvalidation()
        tree.topCutCornerLine:FlagForVisualInvalidation()
    end)

    -- Bottom is already visually correct. Leave its authored 1038-wide
    -- layout driver untouched.
    local bottomCutOk = true

    -- inkShapeWidget does not stretch its authored vector path the way a
    -- rectangle does. Keep both shape widgets at their vanilla geometry.
    local topBlackOk = pcall(function()
        tree.topBlack:SetSize(3841.0, 285.0)
        tree.topBlack:FlagForVisualInvalidation()
    end)

    local bottomBlackOk = pcall(function()
        tree.bottomBlack:SetSize(3841.0, 285.0)
        tree.bottomBlack:FlagForVisualInvalidation()
    end)

    -- Only the flat tails need extending into the additional UW space:
    --   top    -> extend to the RIGHT
    --   bottom -> extend to the LEFT
    --
    -- These rectangles deliberately live in the same bg canvas as the
    -- original shapes so their depth/layering stays identical.
    local blackExtensionWidth =
        math.max(0.0, width - 3841.0)

    -- Adjacent Ink widgets can expose a one-pixel/sub-pixel seam while the
    -- animated background is moving. Overlap the flat UW extensions into the
    -- vanilla vector shapes instead of making them meet exactly edge-to-edge.
    local blackExtensionOverlap = 32.0
    local blackExtensionCoveredWidth =
        blackExtensionWidth > 0.5 and
        (blackExtensionWidth + blackExtensionOverlap) or 0.0

    local topBlackExtensionOk = true
    local bottomBlackExtensionOk = true

    if blackExtensionWidth > 0.5 then
        topBlackExtensionOk = pcall(function()
            local extension = inkRectangleWidget.new()
            extension:SetName(
                CName.new("UWUI_TopBlackExtension")
            )
            extension:SetFitToContent(false)
            extension:SetInteractive(false)
            extension:SetAnchor(inkEAnchor.TopRight)
            extension:SetAnchorPoint(Vector2.new({
                X = 1.0,
                Y = 0.0
            }))
            extension:SetSize(
                blackExtensionCoveredWidth,
                285.0
            )
            extension:SetTintColor(HDRColor.new({
                Red = 0.0,
                Green = 0.0,
                Blue = 0.0,
                Alpha = 1.0
            }))
            extension:SetOpacity(1.0)
            extension:SetVisible(true)
            extension:Reparent(tree.bg)
            extension:FlagForVisualInvalidation()
        end)

        bottomBlackExtensionOk = pcall(function()
            local extension = inkRectangleWidget.new()
            extension:SetName(
                CName.new("UWUI_BottomBlackExtension")
            )
            extension:SetFitToContent(false)
            extension:SetInteractive(false)
            extension:SetAnchor(inkEAnchor.BottomLeft)
            extension:SetAnchorPoint(Vector2.new({
                X = 0.0,
                Y = 1.0
            }))
            extension:SetSize(
                blackExtensionCoveredWidth,
                285.0
            )
            extension:SetTintColor(HDRColor.new({
                Red = 0.0,
                Green = 0.0,
                Blue = 0.0,
                Alpha = 1.0
            }))
            extension:SetOpacity(1.0)
            extension:SetVisible(true)
            extension:Reparent(tree.bg)
            extension:FlagForVisualInvalidation()
        end)
    end

    local binksOk = resizeWidgetWidth(tree.binksHere, width, true)

    -- Fill widgets should inherit the widened contentRoot; invalidate them
    -- explicitly so the loading layer redraws within the same frame.
    local fillOk = pcall(function()
        tree.solidBG:FlagForVisualInvalidation()
        tree.backgroundVideo:FlagForVisualInvalidation()
    end)

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog("------------------------------------------------------------")
        writeDebugLog(
            "LOADING SCREEN layout BEGIN: " .. tostring(reason) ..
            " | resolver=" .. tostring(tree.resolutionSource)
        )
        writeDebugLog(string.format(
            "geometry screenAspect=%.6f physicalWidth=%.2f uiSpread=%d%% (ignored for loading)",
            screenGeometry.aspect,
            screenGeometry.contentWidth,
            UI_SPREAD_PERCENT
        ))
        writeDebugLog(string.format(
            "BEFORE outer=%s content=%s fluff=%s topBlack=%s bottomBlack=%s mainImage=%s topCutFlex=%s bottomCutFlex=%s topCutDriver=%s bottomCutDriver=%s",
            tostring(beforeOuter),
            tostring(beforeContent),
            tostring(beforeFluff),
            tostring(beforeTopBlack),
            tostring(beforeBottomBlack),
            tostring(beforeMainImage),
            tostring(beforeTopCutFlex),
            tostring(beforeBottomCutFlex),
            tostring(beforeTopCutDriver),
            tostring(beforeBottomCutDriver)
        ))
        writeDebugLog(string.format(
            "BGImageContainer scale preserved=[%.6f, %.6f]",
            beforeBGImageScale ~= nil and
                (beforeBGImageScale.X or -1.0) or -1.0,
            beforeBGImageScale ~= nil and
                (beforeBGImageScale.Y or -1.0) or -1.0
        ))
        writeDebugLog(string.format(
            "mutations outer=%s content=%s fluff=%s facts=%s borders=%s topFluff=%s bg=%s mainImage=%s topCut=%s bottomCut=%s topBlack=%s bottomBlack=%s topExt=%s bottomExt=%s binks=%s fillInvalidate=%s",
            tostring(outerOk),
            tostring(contentOk),
            tostring(fluffOk),
            tostring(factsOk),
            tostring(bordersOk),
            tostring(topFluffOk),
            tostring(bgOk),
            tostring(mainImageOk),
            tostring(topCutOk),
            tostring(bottomCutOk),
            tostring(topBlackOk),
            tostring(bottomBlackOk),
            tostring(topBlackExtensionOk),
            tostring(bottomBlackExtensionOk),
            tostring(binksOk),
            tostring(fillOk)
        ))
        writeDebugLog(string.format(
            "targets mainImage=%.2fx%.2f rendered=%.2fx%.2f | topCut DRIVER=%.2f (leftOffset=1000) bottomDriver untouched=1038 | blackExt=%.2f overlap=%.2f covered=%.2f",
            targetMainImageWidth or -1.0,
            targetMainImageHeight or -1.0,
            width,
            width * (1600.0 / VANILLA_CONTENT_WIDTH),
            topCutTargetWidth,
            blackExtensionWidth,
            blackExtensionOverlap,
            blackExtensionCoveredWidth
        ))
        writeDebugLog(string.format(
            "AFTER outer=%s content=%s fluff=%s topBlack=%s bottomBlack=%s",
            debugWidgetSize(tree.outerRoot),
            debugWidgetSize(tree.contentRoot),
            debugWidgetSize(tree.fluffElements),
            debugWidgetSize(tree.topBlack),
            debugWidgetSize(tree.bottomBlack)
        ))
        writeDebugLog(
            "BGImageContainer scale preserved; ExtendingIMage untouched"
        )
        writeDebugLog("LOADING SCREEN layout END")
    end

    return outerOk and contentOk and fluffOk and factsOk and
        bordersOk and topFluffOk and bgOk and mainImageOk and
        topCutOk and bottomCutOk and topBlackOk and bottomBlackOk and
        topBlackExtensionOk and bottomBlackExtensionOk and
        binksOk and fillOk and releaseLoadingPillarsIfReady(
            "fast travel loading layout ready"
        )
end


-- ---------------------------------------------------------------------------
-- OBSERVERS
-- ---------------------------------------------------------------------------

registerForEvent("onInit", function()
    loadPersistentSettings()

    if ACTIVATE_DEBUG_LOGS then
        initializeDebugLog()

        local displayWidth, displayHeight = GetDisplayResolution()
        writeDebugLog(string.format(
            "onInit | display=%sx%s | uiSpread=%d%%",
            tostring(displayWidth),
            tostring(displayHeight),
            UI_SPREAD_PERCENT
        ))
    end

    registerNativeSettings()

    -- MAIN MENU -> GAMEPLAY INITIAL LOADING SCREEN
    --
    -- Runtime Ink Tree Dump signature:
    --   Root[0]/Root[0]
    --   controller = inkInitialLoadingScreenLogicController
    --
    -- This is NOT the FastTravel loading controller. Pillar policy is owned
    -- centrally by BlackPillarsCoordinator; after the exact scene-cover refit
    -- succeeds, release the startup pillars even if Main Menu was skipped.
    pcall(function()
        Observe(
            "inkInitialLoadingScreenLogicController",
            "OnInitialize",
            function(controller)
                initialLoadingScreenActive = true
                initialLoadingScreenController = controller
                initialLoadingCoverWatchActive = true

                if ACTIVATE_DEBUG_LOGS then
                    local root = safe(function()
                        return controller:GetRootWidget()
                    end)

                    writeDebugLog(
                        "inkInitialLoadingScreenLogicController.OnInitialize observed" ..
                        (root ~= nil and
                            (" root=" .. widgetName(root) ..
                             " size=" .. debugWidgetSize(root)) or "")
                    )
                end

                if applyInitialLoadingSceneCoverExact(
                    controller,
                    "inkInitialLoadingScreenLogicController.OnInitialize"
                ) then
                    initialLoadingCoverWatchActive = false
                end
            end
        )
    end)

    pcall(function()
        Observe(
            "inkInitialLoadingScreenLogicController",
            "SetLoadProgress;Float",
            function(controller)
                if not initialLoadingScreenActive or
                   not initialLoadingCoverWatchActive then
                    return
                end

                -- Refresh the live controller reference at a later lifecycle
                -- point. On slower systems the OnInitialize root can precede
                -- attachment of LoadingPartsContainer.
                initialLoadingScreenController = controller

                if applyInitialLoadingSceneCoverExact(
                    controller,
                    nil
                ) then
                    initialLoadingCoverWatchActive = false

                    if ACTIVATE_DEBUG_LOGS then
                        writeDebugLog(
                            "INITIAL LOADING exact tree ready on SetLoadProgress; cover/root refit applied"
                        )
                    end
                end
            end
        )
    end)

    pcall(function()
        Observe(
            "inkFastTravelLoadingScreenLogicController",
            "OnInitialize",
            function(controller)
                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(
                        "inkFastTravelLoadingScreenLogicController.OnInitialize observed"
                    )
                end

                fastLoadingScreenController = controller
                fastLoadingLayoutWatchActive = true

                if applyLoadingScreenLayoutExact(
                    controller,
                    "inkFastTravelLoadingScreenLogicController.OnInitialize"
                ) then
                    fastLoadingLayoutWatchActive = false
                end
            end
        )
    end)

    -- Checkpoint reload / quickload loading screen. This is a third loading
    -- controller, separate from Initial Loading and Fast Travel. It owns only a
    -- progress UI plus a black Fill rectangle; keep the UI authored at 16:9 and
    -- extend the black concealment rectangle into the UW side regions.
    pcall(function()
        Observe(
            "inkDefaultLoadingScreenLogicController",
            "OnInitialize",
            function(controller)
                UWUI_defaultLoadingScreenController = controller
                UWUI_defaultLoadingMaskWatchActive = true

                if ACTIVATE_DEBUG_LOGS then
                    local root = safe(function()
                        return controller:GetRootWidget()
                    end)
                    writeDebugLog(
                        "inkDefaultLoadingScreenLogicController.OnInitialize observed" ..
                        (root ~= nil and
                            (" root=" .. widgetName(root) ..
                             " size=" .. debugWidgetSize(root)) or "")
                    )
                end

                if UWUI_applyDefaultLoadingMaskExact(
                    controller,
                    "inkDefaultLoadingScreenLogicController.OnInitialize"
                ) then
                    UWUI_defaultLoadingMaskWatchActive = false
                end
            end
        )
    end)

    pcall(function()
        Observe(
            "inkDefaultLoadingScreenLogicController",
            "OnUninitialize",
            function(controller)
                if UWUI_defaultLoadingScreenController == controller then
                    UWUI_defaultLoadingScreenController = nil
                    UWUI_defaultLoadingMaskWatchActive = false
                end

                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(
                        "inkDefaultLoadingScreenLogicController.OnUninitialize observed"
                    )
                end
            end
        )
    end)

    pcall(function()
        Observe(
            "QuestTrackerGameController",
            "OnInitialize",
            function()
                local initialWasActive = initialLoadingScreenActive

                initialLoadingScreenActive = false
                initialLoadingScreenController = nil
                initialLoadingCoverWatchActive = false
                fastLoadingScreenController = nil
                fastLoadingLayoutWatchActive = false
                UWUI_defaultLoadingScreenController = nil
                UWUI_defaultLoadingMaskWatchActive = false

                if ACTIVATE_DEBUG_LOGS and initialWasActive then
                    writeDebugLog(
                        "initial loading lifecycle ended: QuestTrackerGameController.OnInitialize"
                    )
                end
            end
        )
    end)

    local preGameAtInit = isPreGame()

    if preGameAtInit == true then
        -- Real startup / pre-game:
        -- explicitly restore the black pillars, then lock out every generic
        -- suppression request until the refitted Main Menu scene is ready.
        startupPillarLockActive = true
        mainMenuPillarsReleased = false
        mainMenuPillarReleaseArmed = false
        mainMenuSceneRefitted = false

        setPillarsDisabled(
            false,
            "onInit pre-game startup"
        )
    elseif preGameAtInit == false then
        -- Reload All Mods while already in gameplay: normal ultrawide state.
        startupPillarLockActive = false
        disablePillars("onInit in-game reload")
    elseif ACTIVATE_DEBUG_LOGS then
        -- Unknown engine state: do not guess.
        writeDebugLog(
            "onInit IsPreGame unavailable; pillar state left unchanged"
        )
    end

    -- CET Reload All Mods can occur while a fullscreen arcade is already open,
    -- after the scenario-entry transition has happened. Recover that one case
    -- from the exact current ArcadeMachine shell; normal entry is scenario-led.
    if preGameAtInit == false then
        local currentArcadeTree = resolveArcadeMachineExact()
        if currentArcadeTree ~= nil then
            enterArcadePillarMode("onInit current ArcadeMachine shell")
        end
    end

    -- Capture the real Hub submenu CName. Backpack is already known; the
    -- The menuName is used only as a strict key into the validated
    -- menuName -> hint-index table below. Unknown menus are left untouched.
    ObserveBefore("MenuScenario_HubMenu", "OnOpenMenu", function(_, menuName)
        pendingHubMenuName = cnameValue(menuName)

        if pendingHubMenuName ~= "new_perks" then
            pendingCharacterBackgroundWatch = false
            pendingCharacterReason = nil
            pendingCharacterChecks = 0
        end

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "MenuScenario_HubMenu.OnOpenMenu menuName=" ..
                tostring(pendingHubMenuName)
            )
        end
    end)

    -- Debug-only generic scenario tracing, useful for discovering the real
    -- Ripperdoc/vendor scenario without keeping any release-time observer.
    if ACTIVATE_DEBUG_LOGS then
        local scenarioTransitionSources = {
            "MenuScenario_Idle",
            "MenuScenario_BaseMenu",
            "MenuScenario_PreGameSubMenu",
            "MenuScenario_SingleplayerMenu",
            "MenuScenario_HubMenu"
        }

        for _, scenarioClass in ipairs(scenarioTransitionSources) do
            local observedClass = scenarioClass

            pcall(function()
                ObserveBefore(observedClass, "OnLeaveScenario", function(firstArg, menuName)
                    if type(menuName) ~= "userdata" then
                        menuName = firstArg
                    end

                    writeDebugLog(
                        observedClass ..
                        ".OnLeaveScenario target=" ..
                        tostring(cnameValue(menuName))
                    )
                end)
            end)
        end
    end

    -- Main Menu. The progression scene can be attached/replaced after either
    -- controller initialization or OnSavesForLoadReady, so those events arm
    -- the exact-path scene watcher instead of starting a discovery scan.
    Observe(
        "gameuiPreGameMenuGameController",
        "OnInitialize",
        function()
            fastLoadingScreenController = nil
            fastLoadingLayoutWatchActive = false

            -- This is the lifecycle gate for pillar removal. The dynamic
            -- scene may already have been refitted by the pre-game watcher;
            -- if so, armMainMenuWatch() immediately releases the pillars.
            -- If not, the exact-path watcher will release them as soon as
            -- child[0] appears and is successfully refitted.
            mainMenuPillarReleaseArmed = true

            armMainMenuWatch(
                "gameuiPreGameMenuGameController.OnInitialize"
            )
        end
    )

    Observe(
        "SingleplayerMenuGameController",
        "OnInitialize",
        function()
            armMainMenuWatch(
                "SingleplayerMenuGameController.OnInitialize"
            )
        end
    )

    Observe(
        "SingleplayerMenuGameController",
        "OnSavesForLoadReady",
        function()
            -- The selected progression scene may be replaced asynchronously
            -- after this callback returns. Reset the per-instance guard and
            -- let the active pre-game watcher catch whichever child[0] wins.
            armMainMenuWatch(
                "SingleplayerMenuGameController.OnSavesForLoadReady"
            )
        end
    )

    -- Native Settings: both pre-game and in-game roots are validated. Apply
    -- once at controller initialization; no readiness watcher is retained
    -- because runtime testing found no timing failure after the dual-root fix.
    Observe("SettingsMainGameController", "OnInitialize", function()
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("SettingsMainGameController.OnInitialize observed")
        end

        applySettingsMenuExact(
            "SettingsMainGameController.OnInitialize"
        )
    end)

    -- Optional Vehicle Selector Frontend compatibility.
    -- Vehicle Selector uses nativeSettings.addRangeInt(), whose callback is
    -- executed synchronously inside SettingsSelectorControllerInt.Refresh().
    -- ObserveAfter therefore runs after PreviewWindow.Draw() has recreated the
    -- Viewport. The exact Viewport/Vehicle_Side_Image signature keeps this
    -- harmless for every other integer slider in Native Settings.
    pcall(function()
        ObserveAfter(
            "SettingsSelectorControllerInt",
            "Refresh",
            function(controller)
                local applied = applyVehicleSelectorPreviewExact(
                    "SettingsSelectorControllerInt.Refresh"
                )

                if ACTIVATE_DEBUG_LOGS and applied then
                    writeDebugLog(
                        "VEHICLE SELECTOR preview finalized after Native Settings integer slider refresh"
                    )
                end
            end
        )
    end)

    -- Optional Mod Settings compatibility: a CET class binding (or the
    -- native RTTI descriptor) must exist before Observe() is attempted.
    -- A failed probe is logged precisely and never disables other hooks.
    local modSettingsAvailable, modSettingsProbe =
        optionalClassAvailable(
            "ModStngsMainGameController",
            ModStngsMainGameController
        )
    if modSettingsAvailable then
        Observe("ModStngsMainGameController", "OnInitialize", function()
            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "ModStngsMainGameController.OnInitialize observed"
                )
            end

            applySettingsMenuExact(
                "ModStngsMainGameController.OnInitialize"
            )
            applyModSettingsListExact(
                "ModStngsMainGameController.OnInitialize"
            )
        end)
    end
    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "optional Mod Settings: %s (%s)",
            modSettingsAvailable and "observer registered" or "skipped",
            modSettingsProbe
        ))
    end

    -- Save / Load: visually equivalent treatment, but distinct validated
    -- child-index signatures for Save and Load. Apply once at their dedicated
    -- controller initialization; no retry/watch
    -- is justified unless a real configuration later proves the tree can be
    -- incomplete at this lifecycle point.
    ObserveBefore("SaveGameMenuGameController", "OnInitialize", function()
        pendingHubMenuName = nil
    end)

    Observe("SaveGameMenuGameController", "OnInitialize", function()
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("SaveGameMenuGameController.OnInitialize observed")
        end

        applySaveLoadExact(
            "SaveGameMenuGameController.OnInitialize"
        )
    end)

    ObserveBefore("LoadGameMenuGameController", "OnInitialize", function()
        pendingHubMenuName = nil
    end)

    Observe("LoadGameMenuGameController", "OnInitialize", function()
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("LoadGameMenuGameController.OnInitialize observed")
        end

        applySaveLoadExact(
            "LoadGameMenuGameController.OnInitialize"
        )
    end)

    -- Storage/Stash: FullscreenVendorGameController is shared with normal
    -- vendors, so enable the exact layout only while MenuScenario_Storage is
    -- the active scenario. Geometry still has no retry window; only the empirically
    -- required one-shot data-view refresh is delayed after both populations.
    local stashTransitionSources = {
        "MenuScenario_Idle",
        "MenuScenario_BaseMenu",
        "MenuScenario_SingleplayerMenu",
        "MenuScenario_HubMenu"
    }

    for _, scenarioClass in ipairs(stashTransitionSources) do
        local observedClass = scenarioClass
        pcall(function()
            ObserveBefore(observedClass, "OnLeaveScenario", function(firstArg, menuName)
                if type(menuName) ~= "userdata" then menuName = firstArg end
                if cnameValue(menuName) == "MenuScenario_Storage" then
                    stashMenuActive = true
                    stashDefaultPlayerFilterForced = false
                    stashPlayerInventoryPopulated = false
                    stashVendorInventoryPopulated = false
                    stashDataViewsRefreshed = false
                    stashDataRefreshInProgress = false
                    pendingStashDataRefreshController = nil
                    pendingStashDataRefreshDelay = 0.0
                    if ACTIVATE_DEBUG_LOGS then
                        writeDebugLog(
                            observedClass ..
                            ".OnLeaveScenario -> STASH active"
                        )
                    end
                end
            end)
        end)
    end

    pcall(function()
        ObserveBefore("MenuScenario_Storage", "OnLeaveScenario", function()
            stashMenuActive = false
            stashDefaultPlayerFilterForced = false
            stashPlayerInventoryPopulated = false
            stashVendorInventoryPopulated = false
            stashDataViewsRefreshed = false
            stashDataRefreshInProgress = false
            pendingStashDataRefreshController = nil
            pendingStashDataRefreshDelay = 0.0
            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("MenuScenario_Storage.OnLeaveScenario -> STASH inactive")
            end
        end)
    end)

    -- Shared fullscreen arcade lifecycle. The engine explicitly transitions to
    -- MenuScenario_ArcadeMinigame, which is game-agnostic and fires before the
    -- individual arcade title/controller tree is populated. Restore pillars on
    -- entry and release the temporary override as soon as that scenario exits.
    local arcadeTransitionSources = {
        "MenuScenario_Idle",
        "MenuScenario_BaseMenu",
        "MenuScenario_HubMenu",
        "MenuScenario_PreGameSubMenu",
        "MenuScenario_SingleplayerMenu"
    }

    for _, scenarioClass in ipairs(arcadeTransitionSources) do
        local observedClass = scenarioClass
        pcall(function()
            ObserveBefore(observedClass, "OnLeaveScenario", function(firstArg, menuName)
                if type(menuName) ~= "userdata" then
                    menuName = firstArg
                end

                if cnameValue(menuName) ~= "MenuScenario_ArcadeMinigame" then
                    return
                end

                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(
                        observedClass ..
                        ".OnLeaveScenario -> ARCADE active"
                    )
                end

                enterArcadePillarMode(
                    observedClass ..
                    ".OnLeaveScenario -> MenuScenario_ArcadeMinigame"
                )
            end)
        end)
    end

    pcall(function()
        ObserveBefore("MenuScenario_ArcadeMinigame", "OnLeaveScenario", function(firstArg, menuName)
            if type(menuName) ~= "userdata" then
                menuName = firstArg
            end

            local targetName = cnameValue(menuName)

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "MenuScenario_ArcadeMinigame.OnLeaveScenario target=" ..
                    tostring(targetName) ..
                    " -> ARCADE inactive"
                )
            end

            leaveArcadePillarMode(
                "MenuScenario_ArcadeMinigame.OnLeaveScenario -> " ..
                tostring(targetName)
            )
        end)
    end)

    ObserveBefore("gameuiInGameMenuGameController", "OnInitialize", function()
        if not stashMenuActive then return end
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("STASH gameuiInGameMenuGameController.BeforeOnInitialize observed")
        end
        applyStashExact("gameuiInGameMenuGameController.BeforeOnInitialize")
    end)

    Observe("gameuiInGameMenuGameController", "OnInitialize", function()
        if not stashMenuActive then return end
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("STASH gameuiInGameMenuGameController.OnInitialize observed")
        end
        applyStashExact("gameuiInGameMenuGameController.OnInitialize")
    end)

    pcall(function()
        Observe("FullscreenVendorGameController", "OnInitialize", function(controller)
            if stashMenuActive then
                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog("STASH FullscreenVendorGameController.OnInitialize observed")
                end
                applyStashExact("FullscreenVendorGameController.OnInitialize")
                return
            end

            vendorMenuActive = true
            vendorController = controller
            vendorPlayerItemMaterialized = false
            vendorVendorItemMaterialized = false
            vendorDefaultPlayerFilterForced = false
            vendorDataViewsRefreshed = false
            vendorDataRefreshInProgress = false
            pendingVendorDataRefreshController = nil
            pendingVendorDataRefreshDelay = 0.0

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "VENDOR FullscreenVendorGameController.OnInitialize observed -> active"
                )
            end
            applyVendorExact("FullscreenVendorGameController.OnInitialize")
        end)
    end)

    pcall(function()
        Observe("FullscreenVendorGameController", "OnUninitialize", function()
            if stashMenuActive then return end
            vendorMenuActive = false
            vendorController = nil
            vendorPlayerItemMaterialized = false
            vendorVendorItemMaterialized = false
            vendorDefaultPlayerFilterForced = false
            vendorDataViewsRefreshed = false
            vendorDataRefreshInProgress = false
            pendingVendorDataRefreshController = nil
            pendingVendorDataRefreshDelay = 0.0
            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("VENDOR FullscreenVendorGameController.OnUninitialize observed -> inactive")
            end
        end)
    end)

    -- Stash only: its proven data-view rebuild still uses the two native
    -- Populate* callbacks plus the one-shot 0.20 s deferred refresh.
    pcall(function()
        Observe("FullscreenVendorGameController", "PopulatePlayerInventory", function(controller)
            if not stashMenuActive or stashDataRefreshInProgress then return end

            stashPlayerInventoryPopulated = true
            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("STASH PopulatePlayerInventory observed")
            end
            scheduleStashDataViewRefresh(controller, "PopulatePlayerInventory")
        end)
    end)

    pcall(function()
        Observe("FullscreenVendorGameController", "PopulateVendorInventory", function(controller)
            if not stashMenuActive or stashDataRefreshInProgress then return end

            stashVendorInventoryPopulated = true
            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("STASH PopulateVendorInventory observed")
            end
            scheduleStashDataViewRefresh(controller, "PopulateVendorInventory")
        end)
    end)

    pcall(function()
        ObserveAfter(
            "VendorItemVirtualController",
            "OnDataChanged;Variant",
            function(itemController)
                if stashMenuActive or not vendorMenuActive or
                   vendorDataRefreshInProgress then
                    return
                end

                -- The first virtual-item bind is late enough for the
                -- dynamically-created player filter tree to be live.
                if not vendorDefaultPlayerFilterForced then
                    vendorDataRefreshInProgress = true
                    selectVendorPlayerAllItemsExact(
                        "first Vendor virtual item materialized"
                    )
                    vendorDataRefreshInProgress = false
                end

                -- Decode the Variant bound to this virtual item so player
                -- and vendor materialization can be tracked independently.
                local wrappedData = safe(function()
                    return FromVariant(itemController:GetData())
                end)

                local isVendorItem = nil
                if wrappedData ~= nil then
                    isVendorItem = safe(function()
                        return wrappedData.IsVendorItem
                    end)
                end

                local playerWasSeen = vendorPlayerItemMaterialized
                local vendorWasSeen = vendorVendorItemMaterialized

                if isVendorItem == true then
                    vendorVendorItemMaterialized = true
                elseif isVendorItem == false then
                    vendorPlayerItemMaterialized = true
                end

                if ACTIVATE_DEBUG_LOGS then
                    if not playerWasSeen and vendorPlayerItemMaterialized then
                        writeDebugLog(
                            "VENDOR player-side virtual grid materialization observed"
                        )
                    end
                    if not vendorWasSeen and vendorVendorItemMaterialized then
                        writeDebugLog(
                            "VENDOR vendor-side virtual grid materialization observed"
                        )
                    end
                end

                if vendorPlayerItemMaterialized and
                   vendorVendorItemMaterialized then
                    scheduleVendorDataViewRefresh(
                        vendorController,
                        "both Vendor virtual grids ready"
                    )
                end
            end
        )
    end)

    pcall(function()
        Observe(
            "FullscreenVendorGameController",
            "OnPlayerSortingButtonClicked",
            function()
                if stashMenuActive then
                    positionStashDropdownExact(
                        "playerPanel",
                        "OnPlayerSortingButtonClicked"
                    )
                elseif vendorMenuActive then
                    positionVendorDropdownExact(
                        "playerPanel",
                        "OnPlayerSortingButtonClicked"
                    )
                end
            end
        )
    end)

    pcall(function()
        Observe(
            "FullscreenVendorGameController",
            "OnVendorSortingButtonClicked",
            function()
                if stashMenuActive then
                    positionStashDropdownExact(
                        "vendorPanel",
                        "OnVendorSortingButtonClicked"
                    )
                elseif vendorMenuActive then
                    positionVendorDropdownExact(
                        "vendorPanel",
                        "OnVendorSortingButtonClicked"
                    )
                end
            end
        )
    end)

    -- Breach Protocol: preserve the active 16:9 minigame and extend only
    -- the proven fullscreen decoration. Apply immediately, then arm the
    -- native-intro-aware finalize described above.
    Observe("HackingMinigameGameController", "OnInitialize", function()
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "HackingMinigameGameController.OnInitialize observed"
            )
        end

        local breachApplied = applyBreachProtocolExact(
            "HackingMinigameGameController.OnInitialize"
        )

        if breachApplied then
            pendingBreachMainFinalizeWatch = true
            pendingBreachMainFinalizeReason =
                "HackingMinigameGameController.OnInitialize"
            pendingBreachMainFinalizeChecks = 0
            pendingBreachMainIntroStarted = false

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "BREACH intro start->settle exact-path finalize armed"
                )
            end
        end

        -- The Help/Tutorial overlay is created/shown later with no reliable
        -- callback of its own. Arm a tiny exact-path visibility watch for this
        -- Breach session; it stops on the first successful tutorial refit.
        pendingBreachTutorialWatch = true
        pendingBreachTutorialReason =
            "HackingMinigameGameController.OnInitialize"

        if applyBreachTutorialExact(
            "HackingMinigameGameController.OnInitialize -> immediate tutorial probe",
            false
        ) then
            pendingBreachTutorialWatch = false
            pendingBreachTutorialReason = nil
        elseif ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "BREACH TUTORIAL exact-path visibility watch armed"
            )
        end
    end)

    pcall(function()
        Observe("HackingMinigameGameController", "OnUninitialize", function()
            pendingBreachMainFinalizeWatch = false
            pendingBreachMainFinalizeReason = nil
            pendingBreachMainFinalizeChecks = 0
            pendingBreachMainIntroStarted = false
            pendingBreachTutorialWatch = false
            pendingBreachTutorialReason = nil

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "BREACH TUTORIAL exact-path visibility watch cleared: HackingMinigameGameController.OnUninitialize"
                )
            end
        end)
    end)

    -- Flatlined / Death Menu: exact-path structural refit only.
    -- A previous implementation used this controller solely as a guard against
    -- Pause/Gallery mutations; v2 now gives it its own dedicated treatment.
    Observe("DeathMenuGameController", "OnInitialize", function()
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("DeathMenuGameController.OnInitialize observed")
        end

        applyFlatlinedExact(
            "DeathMenuGameController.OnInitialize"
        )
    end)

    -- Pause Menu: the actual pause-menu controller is sufficient here.
    -- Unlike PauseMenuBackgroundGameController, it is not shared with the
    -- Flatline / Death Menu, so no death-menu discriminator is required.
    ObserveBefore("PauseMenuGameController", "OnInitialize", function()
        pendingHubMenuName = nil
    end)

    Observe("PauseMenuGameController", "OnInitialize", function()
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("PauseMenuGameController.OnInitialize observed")
        end

        applyPauseMenuExact(
            "PauseMenuGameController.OnInitialize"
        )
    end)

    -- Proven common shell for HUB and direct submenu access.
    Observe("MenuHubLogicController", "OnInitialize", function(controller)
        stealthRunnerHubActive = true
        stealthRunnerPollFrames = 0
        stealthRunnerAppliedVignette = nil

        hubController = controller
        hubLastReadinessStatus = nil
        hubLayoutWatchActive = true
        hubLayoutWatchReason = "MenuHubLogicController.OnInitialize"

        -- Pillar state belongs to this lifecycle event, never to the
        -- per-frame geometry readiness attempts.
        disablePillars("hub MenuHubLogicController.OnInitialize")

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("MenuHubLogicController.OnInitialize observed")
        end

        local applied, status = applyHubImmediate(hubLayoutWatchReason)
        if applied then
            hubLayoutWatchActive = false
        else
            hubLastReadinessStatus = status
            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "HUB exact-path readiness watch armed: " .. tostring(status)
                )
            end
        end
    end)

    pcall(function()
        Observe("MenuHubLogicController", "OnUninitialize", function()
            stealthRunnerHubActive = false
            stealthRunnerPollFrames = 0
            stealthRunnerAppliedVignette = nil

            hubLayoutWatchActive = false
            hubLayoutWatchReason = ""
            hubController = nil
            hubLastReadinessStatus = nil
            hubDecorFinalizePending = false
            hubDecorFinalizeReason = ""

            worldMapLayoutWatchActive = false
            worldMapLayoutController = nil
            worldMapLayoutReady = false
            worldMapPendingCameraGameObject = nil

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "MenuHubLogicController.OnUninitialize observed; STEALTHRUNNER polling stopped"
                )
            end
        end)
    end)

    -- Optional Revised Backpack compatibility. CET maps namespaced class
    -- bindings with underscores; also accept the exact RTTI descriptor.
    local revisedBackpackControllerAvailable, revisedBackpackControllerProbe =
        optionalClassAvailable(
            "RevisedBackpack.RevisedBackpackController",
            RevisedBackpack_RevisedBackpackController
        )
    local revisedBackpackItemControllerAvailable, revisedBackpackItemProbe =
        optionalClassAvailable(
            "RevisedBackpack.RevisedBackpackItemController",
            RevisedBackpack_RevisedBackpackItemController
        )

    if revisedBackpackControllerAvailable then
        Observe(
            "RevisedBackpack.RevisedBackpackController",
            "OnInitialize",
            function(controller)
                pendingRevisedBackpackController = controller
                pendingRevisedBackpackReason =
                    "RevisedBackpackController.OnInitialize"
                pendingRevisedBackpackChecks = 0

                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(
                        "REVISED BACKPACK controller observed"
                    )
                end

                if tryApplyRevisedBackpackMainLayout(
                    controller,
                    pendingRevisedBackpackReason
                ) then
                    pendingRevisedBackpackController = nil
                    pendingRevisedBackpackReason = nil
                    pendingRevisedBackpackChecks = 0
                end
            end
        )

        Observe(
            "RevisedBackpack.RevisedBackpackController",
            "OnUninitialize",
            function(controller)
                if pendingRevisedBackpackController == controller then
                    pendingRevisedBackpackController = nil
                    pendingRevisedBackpackReason = nil
                    pendingRevisedBackpackChecks = 0
                end
            end
        )
    end

    if revisedBackpackItemControllerAvailable then
        Observe(
            "RevisedBackpack.RevisedBackpackItemController",
            "OnInitialize",
            function(controller)
                tryApplyRevisedBackpackItemRow(controller)
            end
        )
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(string.format(
            "optional Revised Backpack controller: %s (%s); item controller: %s (%s)",
            revisedBackpackControllerAvailable and "observers registered" or "skipped",
            revisedBackpackControllerProbe,
            revisedBackpackItemControllerAvailable and "observer registered" or "skipped",
            revisedBackpackItemProbe
        ))
    end

    -- Shards: exact-path layout only.
    Observe("ShardsMenuGameController", "OnInitialize", function()
        pendingShardsLayoutChecks = 0
        pendingShardsLayoutReason = "ShardsMenuGameController.OnInitialize"

        if tryApplyShardsLayoutDirect(
            pendingShardsLayoutReason
        ) then
            pendingShardsLayoutWatch = false
            pendingShardsLayoutReason = nil
        else
            pendingShardsLayoutWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "ShardsMenuGameController.OnInitialize observed; exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("ShardsMenuGameController", "OnUninitialize", function()
            pendingShardsLayoutWatch = false
            pendingShardsLayoutReason = nil
            pendingShardsLayoutChecks = 0
        end)
    end)

    -- Gallery page size must be set before initialization.
    ObserveBefore("GalleryMenuGameController", "OnInitialize", function(controller)
        if not isMainGalleryController(controller) then return end

        local screenshotsPerPage = getGalleryScreenshotsPerPage()
        local ok, errorMessage = pcall(function()
            controller.screenshotsPerPage = screenshotsPerPage
        end)

        if ACTIVATE_DEBUG_LOGS then
            if ok then
                writeDebugLog(
                    "GALLERY screenshotsPerPage=" ..
                    tostring(screenshotsPerPage)
                )
            else
                writeDebugLog(
                    "GALLERY page-size update error: " ..
                    tostring(errorMessage)
                )
            end
        end
    end)

    -- Exact Gallery geometry. If the tree is not ready yet, watch only these
    -- direct paths until the first successful pass.
    Observe("GalleryMenuGameController", "OnInitialize", function(controller)
        if not isMainGalleryController(controller) then return end

        pendingGalleryLayoutChecks = 0
        pendingGalleryLayoutReason = "GalleryMenuGameController.OnInitialize"

        if tryApplyGalleryLayoutDirect(
            pendingGalleryLayoutReason
        ) then
            pendingGalleryLayoutWatch = false
            pendingGalleryLayoutReason = nil
        else
            pendingGalleryLayoutWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "GalleryMenuGameController.OnInitialize observed; exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("GalleryMenuGameController", "OnUninitialize", function(controller)
            if not isMainGalleryController(controller) then return end

            pendingGalleryLayoutWatch = false
            pendingGalleryLayoutReason = nil
            pendingGalleryLayoutChecks = 0
        end)
    end)

    -- Exact handler for GenericMessageNotification popups.
    Observe("GenericMessageNotification", "OnInitialize", function()
        pendingNotificationPopupChecks = 0

        pendingNotificationPopupNeedsGalleryBackground = false
        pendingNotificationPopupRootName = "Root"

        if tryApplyNotificationPopupWidth(
            "GenericMessageNotification.OnInitialize",
            false,
            "Root"
        ) then
            pendingNotificationPopupWatch = false
        else
            pendingNotificationPopupWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "GenericMessageNotification.OnInitialize observed; exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("GenericMessageNotification", "OnUninitialize", function()
            pendingNotificationPopupWatch = false
            pendingNotificationPopupChecks = 0
            pendingNotificationPopupNeedsGalleryBackground = false
            pendingNotificationPopupRootName = "Root"
        end)
    end)

    -- Vendor item preview uses the same exact 16:9 popup Root in
    -- inkGameNotificationsLayer:
    -- Root[0]/NotificationsContainer[1]/UNINITIALIZED_WIDGET[0]/Root[0]
    -- Reuse the generic notification-popup width treatment unchanged.
    Observe("ItemPreviewGameController", "OnInitialize", function()
        pendingNotificationPopupChecks = 0
        pendingNotificationPopupNeedsGalleryBackground = false
        pendingNotificationPopupRootName = "Root"

        if tryApplyNotificationPopupWidth(
            "ItemPreviewGameController.OnInitialize",
            false,
            "Root"
        ) then
            pendingNotificationPopupWatch = false
        else
            pendingNotificationPopupWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "ItemPreviewGameController.OnInitialize observed; exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("ItemPreviewGameController", "OnUninitialize", function()
            pendingNotificationPopupWatch = false
            pendingNotificationPopupChecks = 0
            pendingNotificationPopupNeedsGalleryBackground = false
            pendingNotificationPopupRootName = "Root"
        end)
    end)

    -- Wardrobe garment preview uses the same exact popup Root in
    -- inkGameNotificationsLayer. Reuse the notification-popup width handler.
    Observe("gameuiWardrobeSetPreviewGameController", "OnInitialize", function()
        pendingNotificationPopupChecks = 0
        pendingNotificationPopupNeedsGalleryBackground = false
        pendingNotificationPopupRootName = "Root"

        if tryApplyNotificationPopupWidth(
            "gameuiWardrobeSetPreviewGameController.OnInitialize",
            false,
            "Root"
        ) then
            pendingNotificationPopupWatch = false
        else
            pendingNotificationPopupWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "gameuiWardrobeSetPreviewGameController.OnInitialize observed; exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("gameuiWardrobeSetPreviewGameController", "OnUninitialize", function()
            pendingNotificationPopupWatch = false
            pendingNotificationPopupChecks = 0
            pendingNotificationPopupNeedsGalleryBackground = false
            pendingNotificationPopupRootName = "Root"
        end)
    end)

    -- Gallery full-screen screenshot preview uses the same exact popup canvas
    -- in inkGameNotificationsLayer, but a different controller.
    Observe("GalleryScreenshotFullPreview", "OnInitialize", function()
        pendingNotificationPopupChecks = 0

        pendingNotificationPopupNeedsGalleryBackground = true
        pendingNotificationPopupRootName = "Root"

        if tryApplyNotificationPopupWidth(
            "GalleryScreenshotFullPreview.OnInitialize",
            true,
            "Root"
        ) then
            pendingNotificationPopupWatch = false
        else
            pendingNotificationPopupWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "GalleryScreenshotFullPreview.OnInitialize observed; exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("GalleryScreenshotFullPreview", "OnUninitialize", function()
            pendingNotificationPopupWatch = false
            pendingNotificationPopupChecks = 0
            pendingNotificationPopupNeedsGalleryBackground = false
            pendingNotificationPopupRootName = "Root"
        end)
    end)

    -- Time Skip uses the same exact 16:9 popup Root in
    -- inkGameNotificationsLayer. No Gallery-specific bg resize.
    Observe("gameuiTimeskipGameController", "OnInitialize", function()
        pendingNotificationPopupChecks = 0
        pendingNotificationPopupNeedsGalleryBackground = false
        pendingNotificationPopupRootName = "Root"

        if tryApplyNotificationPopupWidth(
            "gameuiTimeskipGameController.OnInitialize",
            false,
            "Root"
        ) then
            pendingNotificationPopupWatch = false
        else
            pendingNotificationPopupWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "gameuiTimeskipGameController.OnInitialize observed; exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("gameuiTimeskipGameController", "OnUninitialize", function()
            pendingNotificationPopupWatch = false
            pendingNotificationPopupChecks = 0
            pendingNotificationPopupNeedsGalleryBackground = false
            pendingNotificationPopupRootName = "Root"
        end)
    end)

    -- Codex popup uses the same exact 16:9 popup Root in
    -- inkGameNotificationsLayer. No Gallery-specific bg resize.
    Observe("CodexPopupGameController", "OnInitialize", function()
        pendingNotificationPopupChecks = 0
        pendingNotificationPopupNeedsGalleryBackground = false
        pendingNotificationPopupRootName = "RootNotifications"

        if tryApplyNotificationPopupWidth(
            "CodexPopupGameController.OnInitialize",
            false,
            "RootNotifications"
        ) then
            pendingNotificationPopupWatch = false
        else
            pendingNotificationPopupWatch = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "CodexPopupGameController.OnInitialize observed; RootNotifications exact-path readiness watch armed"
                )
            end
        end
    end)

    pcall(function()
        Observe("CodexPopupGameController", "OnUninitialize", function()
            pendingNotificationPopupWatch = false
            pendingNotificationPopupChecks = 0
            pendingNotificationPopupNeedsGalleryBackground = false
            pendingNotificationPopupRootName = "Root"
        end)
    end)

    -- Character: arm an exact-path readiness watch. It stops immediately after
    -- the three master_BG widgets exist and are scaled.
    Observe("PerksMainGameController", "OnInitialize", function()
        pendingCharacterBackgroundWatch = true
        pendingCharacterReason = "PerksMainGameController.OnInitialize"
        pendingCharacterChecks = 0

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "PerksMainGameController.OnInitialize observed; Character background readiness watch armed"
            )
        end
    end)

    Observe("NewPerksCategoriesGameController", "OnInitialize", function()
        local realWidth = safe(function() return GetDisplayResolution() end)
        if type(realWidth) == "number" and realWidth > 4096 then
            perk4096.active = true
            perk4096.pending = false
        end
        pendingCharacterBackgroundWatch = true
        pendingCharacterReason = "NewPerksCategoriesGameController.OnInitialize"
        pendingCharacterChecks = 0

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "NewPerksCategoriesGameController.OnInitialize observed; Character background readiness watch armed"
            )
        end
    end)

    pcall(function()
        Observe("NewPerksCategoriesGameController", "OnUninitialize", function()
            if perk4096.applied then perk4096.restore() end
            perk4096.active = false
        end)
    end)

    -- World Map timing audit.
    -- OnInitialize is still too early for the usable map tree. Keep a tiny
    -- diagnostic here, but perform no mutation.
    Observe("WorldMapMenuGameController", "OnInitialize", function(controller)
        worldMapLayoutController = controller
        worldMapLayoutWatchActive = true
        worldMapLayoutReady = false
        worldMapPendingCameraGameObject = nil

        if ACTIVATE_DEBUG_LOGS then
            local root = safe(function()
                return controller:GetRootWidget()
            end)
            local parent = root ~= nil and safe(function()
                return root:GetParentWidget()
            end) or nil

            writeDebugLog("------------------------------------------------------------")
            writeDebugLog("WorldMapMenuGameController.OnInitialize observed")
            writeDebugLog(string.format(
                "WORLD MAP OnInitialize root=%s parent=%s rootChildren=%s",
                widgetName(root),
                widgetName(parent),
                tostring(root ~= nil and safe(function()
                    return root:GetNumChildren()
                end) or nil)
            ))
        end
    end)

    -- The official implementation also listens here. This is the first
    -- lifecycle point at which we now expect the map Ink tree to be attached.
    Observe("WorldMapMenuGameController", "OnEntityAttached", function(controller)
        disablePillars("world map WorldMapMenuGameController.OnEntityAttached")

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "WorldMapMenuGameController.OnEntityAttached observed"
            )
        end

        worldMapLayoutController = controller
        worldMapLayoutWatchActive = true

        if applyWorldMapLayoutDirect(
            controller,
            "WorldMapMenuGameController.OnEntityAttached"
        ) then
            worldMapLayoutWatchActive = false
            worldMapLayoutReady = true

            if worldMapPendingCameraGameObject ~= nil then
                configureWorldMapCameraDirect(
                    worldMapPendingCameraGameObject,
                    "World Map layout ready -> deferred camera"
                )
                worldMapPendingCameraGameObject = nil
            end
        elseif ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "WORLD MAP exact-path readiness watch armed"
            )
        end
    end)

    -- The map image is rendered by a separate virtual camera component.
    -- Many gameuiWorldMapGameObject instances attach during startup without
    -- the camera component; ignore those silently and log only the real map.
    Observe("gameuiWorldMapGameObject", "OnGameAttached", function(gameObject)
        if not hasWorldMapVirtualCamera(gameObject) then
            return
        end

        if worldMapLayoutReady then
            configureWorldMapCameraDirect(
                gameObject,
                "gameuiWorldMapGameObject.OnGameAttached"
            )
        else
            worldMapPendingCameraGameObject = gameObject

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "WORLD MAP camera ready before Ink layout; mutation deferred"
                )
            end
        end
    end)

    -- Crafting is laid out before its main controller initializes so the
    -- virtual recipe grid can see its final ultrawide viewport from the start.
    ObserveBefore("CraftingMainGameController", "OnInitialize", function(controller)
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "CraftingMainGameController.BeforeOnInitialize observed"
            )
        end

        applyCraftingLayoutDirect(
            controller,
            "CraftingMainGameController.BeforeOnInitialize"
        )
    end)

    -- Main init finishes before CraftingLogicController has connected its
    -- virtualListController/dataView. Arm a tiny readiness watch: no resize,
    -- no fixed delay, no repeated layout pass. It stops immediately after the
    -- first successful SetSource rebuild.
    Observe("CraftingMainGameController", "OnInitialize", function(controller)
        pendingCraftingGridRebuildController = controller
        pendingCraftingGridRebuildChecks = 0

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "CraftingMainGameController.OnInitialize observed; targeted grid readiness watch armed"
            )
        end
    end)

    pcall(function()
        Observe("CraftingMainGameController", "OnUninitialize", function(controller)
            if pendingCraftingGridRebuildController == controller then
                pendingCraftingGridRebuildController = nil
                pendingCraftingGridRebuildChecks = 0
            end

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("CraftingMainGameController.OnUninitialize observed")
            end
        end)
    end)

    -- Backpack core layout is applied before its controller initializes, as in
    -- the previous working implementation, but now with exact direct paths.
    ObserveBefore("BackpackMainGameController", "OnInitialize", function(controller)
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("BackpackMainGameController.BeforeOnInitialize observed")
        end

        applyBackpackLayoutDirect(
            controller,
            "BackpackMainGameController.BeforeOnInitialize"
        )
    end)

    -- The RMK search widget is mod-injected. Queue exactly one post-init
    -- next-frame direct-path pass; no recursive scan and no retry loop.
    Observe("BackpackMainGameController", "OnInitialize", function(controller)
        pendingBackpackSearchController = controller

        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog(
                "BackpackMainGameController.OnInitialize observed; one-shot search finalize queued"
            )
        end
    end)

    pcall(function()
        Observe("BackpackMainGameController", "OnUninitialize", function(controller)
            if pendingBackpackSearchController == controller then
                pendingBackpackSearchController = nil
            end

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog("BackpackMainGameController.OnUninitialize observed")
            end
        end)
    end)

    -- Timing hook for strictly menuName-routed right-side button hints.
    Observe("ButtonHints", "OnInitialize", function()
        if ACTIVATE_DEBUG_LOGS then
            writeDebugLog("ButtonHints.OnInitialize observed")
        end
        applySharedMenuButtonHints("ButtonHints.OnInitialize")
    end)

    -- On a fresh startup, this prepares the dynamic scene before it becomes
    -- visible while pillars remain present over logos/intros.
    --
    -- On a CET reload while already pre-game, it still restores the scene
    -- geometry. Pillar release itself remains tied to the real controller
    -- lifecycle rather than to IsPreGame() alone.
    if isPreGame() == true then
        armMainMenuWatch("onInit pre-game geometry preparation")
    end

    if ACTIVATE_DEBUG_LOGS then
        writeDebugLog(
            "loaded: Ultrawide UI Overhaul v2.5.7 + UI SPREAD + LOADING SCREEN + DEFAULT LOADING MASK + INITIAL LOADING COVER + MAIN MENU + STARTUP PILLAR LOCK + HUB + strict hints + BACKPACK + optional REVISED BACKPACK + CRAFTING + WORLD MAP + CHARACTER + NOTIFICATION POPUPS + ITEM PREVIEW + WARDROBE PREVIEW + GALLERY + SHARDS + PAUSE MENU + SAVE/LOAD + STORAGE/STASH + BUY/SELL VENDOR + BREACH PROTOCOL + BREACH TUTORIAL + SETTINGS DUAL ROOT + NATIVE SETTINGS + VEHICLE SELECTOR FRONTEND + optional MOD SETTINGS + SYSTEM NOTIFICATIONS + FLATLINED + ARCADE NATIVE PILLARS + optional STEALTHRUNNER exact paths"
        )
    end
end)

registerForEvent("onUpdate", function(deltaTime)
    applySystemNotificationExact()

    if pendingStashDataRefreshController ~= nil then
        pendingStashDataRefreshDelay = math.max(
            0.0,
            pendingStashDataRefreshDelay - (deltaTime or 0.0)
        )

        if pendingStashDataRefreshDelay <= 0.0 then
            local controller = pendingStashDataRefreshController
            -- Consume before invoking the native callbacks: they may trigger
            -- inventory-population events themselves.
            pendingStashDataRefreshController = nil
            pendingStashDataRefreshDelay = 0.0

            if not stashDefaultPlayerFilterForced then
                selectStashPlayerAllItemsExact(
                    "both inventories populated -> 0.20s deferred default selection"
                )
            end

            refreshStashDataViewsExact(
                controller,
                "both inventories populated -> 0.20s native filter refresh"
            )
        end
    end

    if pendingVendorDataRefreshController ~= nil then
        pendingVendorDataRefreshDelay = math.max(
            0.0,
            pendingVendorDataRefreshDelay - (deltaTime or 0.0)
        )

        if pendingVendorDataRefreshDelay <= 0.0 then
            local controller = pendingVendorDataRefreshController
            -- Consume before invoking callbacks, exactly like the Stash path.
            pendingVendorDataRefreshController = nil
            pendingVendorDataRefreshDelay = 0.0

            applyVendorExact(
                "both Vendor virtual grids ready -> 0.20s deferred finalize"
            )

            refreshVendorDataViewsExact(
                controller,
                "both Vendor virtual grids ready -> 0.20s native filter refresh"
            )
        end
    end

    if UWUI_defaultLoadingMaskWatchActive and
       UWUI_defaultLoadingScreenController ~= nil then
        if UWUI_applyDefaultLoadingMaskExact(
            UWUI_defaultLoadingScreenController,
            nil
        ) then
            UWUI_defaultLoadingMaskWatchActive = false
        end
    end

    if fastLoadingLayoutWatchActive and
       fastLoadingScreenController ~= nil then
        if applyLoadingScreenLayoutExact(
            fastLoadingScreenController,
            nil
        ) then
            fastLoadingLayoutWatchActive = false

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "LOADING SCREEN exact tree ready; layout refit applied"
                )
            end
        end
    end

    if initialLoadingCoverWatchActive and
       initialLoadingScreenActive and
       initialLoadingScreenController ~= nil then
        if applyInitialLoadingSceneCoverExact(
            initialLoadingScreenController,
            nil
        ) then
            initialLoadingCoverWatchActive = false

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "INITIAL LOADING exact tree ready; cover/root refit applied"
                )
            end
        end
    end

    if mainMenuWatchActive then
        local preGame = isPreGame()

        if preGame == false then
            mainMenuWatchActive = false
            mainMenuSceneRefitted = false
            startupPillarLockActive = false
            mainMenuPillarReleaseArmed = false
            mainMenuPillarsReleased = false

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "MAIN MENU exact-path watch stopped: engine left pre-game"
                )
            end
        else
            tryApplyMainMenuExact(
                "pre-game active scene watch"
            )
        end
    end


    if hubLayoutWatchActive then
        local applied, status = applyHubImmediate(nil)
        if applied then
            hubLayoutWatchActive = false
            hubLastReadinessStatus = nil

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "HUB exact tree ready; layout applied: " .. tostring(status)
                )
            end
        elseif ACTIVATE_DEBUG_LOGS and status ~= hubLastReadinessStatus then
            hubLastReadinessStatus = status
            writeDebugLog(
                "HUB readiness changed: " .. tostring(status)
            )
            logHubControllerSnapshot("readiness transition")
        end
    end

    if hubDecorFinalizePending then
        if finalizeHubDecor(nil) then
            hubDecorFinalizePending = false

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "HUB decorative exact tree ready; finalize applied"
                )
            end
        end
    end

    if worldMapLayoutWatchActive and
       worldMapLayoutController ~= nil then
        if applyWorldMapLayoutDirect(
            worldMapLayoutController,
            nil
        ) then
            worldMapLayoutWatchActive = false
            worldMapLayoutReady = true

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "WORLD MAP exact tree ready; Ink layout applied"
                )
            end

            if worldMapPendingCameraGameObject ~= nil then
                configureWorldMapCameraDirect(
                    worldMapPendingCameraGameObject,
                    "World Map readiness -> deferred camera"
                )
                worldMapPendingCameraGameObject = nil
            end
        end
    end

    if stealthRunnerHubActive then
        stealthRunnerPollFrames = stealthRunnerPollFrames + 1

        if stealthRunnerPollFrames >=
           STEALTHRUNNER_POLL_FRAME_INTERVAL then
            stealthRunnerPollFrames = 0

            tryApplyStealthRunnerLayoutDirect(
                "Hub exact-path poll"
            )
        end
    end

    if pendingRevisedBackpackController ~= nil then
        pendingRevisedBackpackChecks =
            pendingRevisedBackpackChecks + 1

        if tryApplyRevisedBackpackMainLayout(
            pendingRevisedBackpackController,
            (pendingRevisedBackpackReason or
                "RevisedBackpack.OnInitialize") ..
            " -> readiness finalize"
        ) then
            pendingRevisedBackpackController = nil
            pendingRevisedBackpackReason = nil
            pendingRevisedBackpackChecks = 0
        end
    end

    if pendingShardsLayoutWatch then
        pendingShardsLayoutChecks =
            pendingShardsLayoutChecks + 1

        if tryApplyShardsLayoutDirect(
            (pendingShardsLayoutReason or "Shards.OnInitialize") ..
            " -> readiness finalize"
        ) then
            pendingShardsLayoutWatch = false
            pendingShardsLayoutReason = nil
            pendingShardsLayoutChecks = 0
        end
    end

    if pendingGalleryLayoutWatch then
        pendingGalleryLayoutChecks =
            pendingGalleryLayoutChecks + 1

        if tryApplyGalleryLayoutDirect(
            (pendingGalleryLayoutReason or "Gallery.OnInitialize") ..
            " -> readiness finalize"
        ) then
            pendingGalleryLayoutWatch = false
            pendingGalleryLayoutReason = nil
            pendingGalleryLayoutChecks = 0
        end
    end

    if pendingNotificationPopupWatch then
        pendingNotificationPopupChecks =
            pendingNotificationPopupChecks + 1

        if tryApplyNotificationPopupWidth(
            "notification popup readiness finalize",
            pendingNotificationPopupNeedsGalleryBackground,
            pendingNotificationPopupRootName
        ) then
            pendingNotificationPopupWatch = false
            pendingNotificationPopupChecks = 0
            pendingNotificationPopupNeedsGalleryBackground = false
            pendingNotificationPopupRootName = "Root"
        end
    end

    if pendingBreachMainFinalizeWatch then
        pendingBreachMainFinalizeChecks =
            pendingBreachMainFinalizeChecks + 1

        local settled, state = isBreachProtocolIntroSettledExact()
        if state ~= nil then
            local introActive =
                state.fluffVisible ~= true or
                state.columnsVisible ~= true or
                math.abs(state.fluffScaleY - 1.0) > 0.01 or
                math.abs(state.columnsScaleX - 1.0) > 0.01

            -- Ignore the transient final-looking state exposed before the
            -- native intro begins. "Settled" is valid only after these exact
            -- widgets have first been observed in an animated state.
            if not pendingBreachMainIntroStarted then
                if introActive then
                    pendingBreachMainIntroStarted = true

                    if ACTIVATE_DEBUG_LOGS then
                        writeDebugLog(string.format(
                            "BREACH native intro START observed: checks=%d fluffScaleY=%.3f columnsScaleX=%.3f fluffVisible=%s columnsVisible=%s",
                            pendingBreachMainFinalizeChecks,
                            state.fluffScaleY,
                            state.columnsScaleX,
                            tostring(state.fluffVisible),
                            tostring(state.columnsVisible)
                        ))
                    end
                end
            elseif settled then
                local reason = pendingBreachMainFinalizeReason or
                    "HackingMinigameGameController.OnInitialize"

                -- Consume before applying: exactly one post-intro refit.
                pendingBreachMainFinalizeWatch = false
                pendingBreachMainFinalizeReason = nil
                pendingBreachMainIntroStarted = false
                local checks = pendingBreachMainFinalizeChecks
                pendingBreachMainFinalizeChecks = 0

                local applied = applyBreachProtocolExact(
                    reason .. " -> native intro completed finalize"
                )

                if ACTIVATE_DEBUG_LOGS then
                    writeDebugLog(string.format(
                        "BREACH intro completed finalize: checks=%d applied=%s fluffScaleY=%.3f columnsScaleX=%.3f fluffVisible=%s columnsVisible=%s",
                        checks,
                        tostring(applied),
                        state.fluffScaleY,
                        state.columnsScaleX,
                        tostring(state.fluffVisible),
                        tostring(state.columnsVisible)
                    ))
                end
            end
        end
    end

    if pendingBreachTutorialWatch then
        if applyBreachTutorialExact(
            (pendingBreachTutorialReason or
                "HackingMinigameGameController.OnInitialize") ..
            " -> exact-path visibility watch",
            false
        ) then
            pendingBreachTutorialWatch = false
            pendingBreachTutorialReason = nil

            if ACTIVATE_DEBUG_LOGS then
                writeDebugLog(
                    "BREACH TUTORIAL exact-path visibility watch completed"
                )
            end
        end
    end

    if pendingCharacterBackgroundWatch then
        pendingCharacterChecks = pendingCharacterChecks + 1

        if tryFinalizeCharacterBackgrounds(
            (pendingCharacterReason or "Character.OnInitialize") ..
            " -> readiness finalize"
        ) then
            pendingCharacterBackgroundWatch = false
            pendingCharacterReason = nil
            pendingCharacterChecks = 0
        end
    end

    -- Character and Perks share a controller: follow actual wrapper visibility.
    -- Restore the Hub immediately when leaving the perk tree.
    if perk4096.active then
        if perk4096.enabled() then
            if not perk4096.applied then perk4096.pending = true end
        elseif perk4096.applied then
            perk4096.restore()
        end
    end
    if perk4096.pending then
        if perk4096.apply() then perk4096.pending = false end
    end
    -- Correct hints for both Character and Perks; no impact on other menus.
    perk4096.fixHints()

    if pendingCraftingGridRebuildController ~= nil then
        pendingCraftingGridRebuildChecks =
            pendingCraftingGridRebuildChecks + 1

        if tryFinalizeCraftingGridRebuild(
            pendingCraftingGridRebuildController
        ) then
            pendingCraftingGridRebuildController = nil
            pendingCraftingGridRebuildChecks = 0
        end
    end

    if pendingBackpackSearchController ~= nil then
        local controller = pendingBackpackSearchController
        pendingBackpackSearchController = nil

        positionBackpackSearchDirect(
            controller,
            "BackpackMainGameController.OnInitialize -> next-frame search finalize"
        )
    end
end)

registerForEvent("onShutdown", function()
    mainMenuWatchActive = false
    mainMenuSceneRefitted = false
    startupPillarLockActive = false
    mainMenuPillarReleaseArmed = false
    mainMenuPillarsReleased = false
    arcadePillarsActive = false
    initialLoadingScreenActive = false
    initialLoadingScreenController = nil
    initialLoadingCoverWatchActive = false
    fastLoadingScreenController = nil
    fastLoadingLayoutWatchActive = false
    hubLayoutWatchActive = false
    hubLayoutWatchReason = ""
    hubController = nil
    hubLastReadinessStatus = nil
    hubDecorFinalizePending = false
    hubDecorFinalizeReason = ""
    worldMapLayoutWatchActive = false
    worldMapLayoutController = nil
    worldMapLayoutReady = false
    worldMapPendingCameraGameObject = nil
    pendingHubMenuName = nil
    pendingCraftingGridRebuildController = nil
    pendingCraftingGridRebuildChecks = 0
    pendingCharacterBackgroundWatch = false
    pendingCharacterReason = nil
    pendingCharacterChecks = 0
    pendingNotificationPopupWatch = false
    pendingNotificationPopupChecks = 0
    pendingNotificationPopupNeedsGalleryBackground = false
    pendingNotificationPopupRootName = "Root"
    stashMenuActive = false
    stashDefaultPlayerFilterForced = false
    stashPlayerInventoryPopulated = false
    stashVendorInventoryPopulated = false
    stashDataViewsRefreshed = false
    stashDataRefreshInProgress = false
    pendingStashDataRefreshController = nil
    pendingStashDataRefreshDelay = 0.0
    vendorMenuActive = false
    vendorController = nil
    vendorPlayerItemMaterialized = false
    vendorVendorItemMaterialized = false
    vendorDefaultPlayerFilterForced = false
    vendorDataViewsRefreshed = false
    vendorDataRefreshInProgress = false
    pendingVendorDataRefreshController = nil
    pendingVendorDataRefreshDelay = 0.0
    pendingBreachMainFinalizeWatch = false
    pendingBreachMainFinalizeReason = nil
    pendingBreachMainFinalizeChecks = 0
    pendingBreachMainIntroStarted = false
    pendingBreachTutorialWatch = false
    pendingBreachTutorialReason = nil
    pendingGalleryLayoutWatch = false
    pendingGalleryLayoutReason = nil
    pendingGalleryLayoutChecks = 0
    pendingShardsLayoutWatch = false
    pendingShardsLayoutReason = nil
    pendingShardsLayoutChecks = 0
    pendingRevisedBackpackController = nil
    pendingRevisedBackpackReason = nil
    pendingRevisedBackpackChecks = 0
    stealthRunnerHubActive = false
    stealthRunnerPollFrames = 0
    stealthRunnerAppliedVignette = nil
    pendingBackpackSearchController = nil
end)
