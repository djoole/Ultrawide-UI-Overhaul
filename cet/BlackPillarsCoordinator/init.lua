-- Ultrawide UI Overhaul v2.5.6
-- Black Pillars Coordinator
--
-- Policy:
--   * Stock pillars are allowed only during the real startup / pre-game phase.
--   * Once UltrawideUIOverhaul declares the refitted Main Menu ready and asks
--     for pillars OFF, that becomes the normal process-lifetime latch.
--   * After that point, no loading path (quickload, fast travel, load game,
--     initial loading, return to Main Menu, etc.) may re-enable pillars.
--   * Arcade minigames are the intentional exception: while their authored
--     aspect-ratio screen is active, a temporary scope may restore the native
--     pillars without clearing the process-lifetime latch.
--
-- The native plugin owns the compositor hook. This CET module only coordinates
-- the desired state and exposes the shared SetPillarsDisabled API.

local pillarsDisabled = nil
local loadingActive = false
local pillarsLockedOff = false
local temporaryPillarsVisible = false
local publicApi = {}


---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------

local function logError(message)
    pcall(function()
        spdlog.error(
            "[BlackPillarsCoordinator] "
            .. tostring(message)
        )
    end)
end


---------------------------------------------------------------------------
-- Pillar state
---------------------------------------------------------------------------

local function setPillarsDisabled(disabled, force)
    -- Arcade minigames intentionally keep their authored aspect ratio and use
    -- the native pillars as an outer mask for oversized scrolling/parallax
    -- layers. While that temporary scope is active, it takes precedence over
    -- the normal post-startup "pillars locked off" policy.
    if temporaryPillarsVisible then
        disabled = false
        force = true
    -- Once the Main Menu / gameplay ultrawide state has been released, pillars
    -- are otherwise forbidden for the remainder of this process session.
    elseif pillarsLockedOff and not disabled then
        disabled = true
        force = true
    end

    if not force and pillarsDisabled == disabled then
        return
    end

    local ok, err = pcall(function()
        UWMapSetBlackBarsSuppressed(disabled)
    end)

    if ok then
        pillarsDisabled = disabled
    else
        logError(
            "UWMapSetBlackBarsSuppressed failed: "
            .. tostring(err)
        )
    end
end


-- Shared entry point used by UltrawideUIOverhaul.
--
-- The first request for pillars OFF is the hand-off from startup/pre-game to
-- the refitted ultrawide UI. From that moment on, pillars stay disabled until
-- process shutdown.
UWMenuSetPillarsDisabled = function(disabled)
    if disabled then
        pillarsLockedOff = true
        loadingActive = false
        setPillarsDisabled(true, true)
        return
    end

    -- Re-enabling is legal only before the first ultrawide hand-off.
    if pillarsLockedOff then
        setPillarsDisabled(true, true)
        return
    end

    setPillarsDisabled(false, false)
end

publicApi.SetPillarsDisabled = function(disabled)
    UWMenuSetPillarsDisabled(disabled)
end


-- Temporary authored-aspect-ratio scope used by arcade minigames.
-- This does not clear pillarsLockedOff; it only overrides the compositor state
-- for the duration of the arcade screen. Releasing the scope immediately
-- restores the normal post-startup ultrawide suppression policy.
UWMenuSetTemporaryPillarsVisible = function(visible)
    temporaryPillarsVisible = visible == true

    if temporaryPillarsVisible then
        setPillarsDisabled(false, true)
        return
    end

    if pillarsLockedOff then
        setPillarsDisabled(true, true)
    else
        setPillarsDisabled(false, true)
    end
end

publicApi.SetTemporaryPillarsVisible = function(visible)
    UWMenuSetTemporaryPillarsVisible(visible)
end


---------------------------------------------------------------------------
-- Loading lifecycle
---------------------------------------------------------------------------

local function beginLoading()
    if loadingActive then
        return
    end

    loadingActive = true

    if pillarsLockedOff then
        -- Loading screens are now refitted by UltrawideUIOverhaul, so after
        -- the Main Menu hand-off they must never restore 16:9 pillars.
        setPillarsDisabled(true, true)
        return
    end

    -- Before the first Main Menu hand-off we are still in stock startup /
    -- pre-game presentation, where pillars are intentional.
    setPillarsDisabled(false, true)
end


local function endLoading()
    if not loadingActive then
        return
    end

    loadingActive = false

    -- Playable world and every post-Main-Menu presentation are ultrawide.
    setPillarsDisabled(true, true)
end


---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

registerForEvent("onInit", function()

    -- Do not overwrite native compositor state here. The DLL starts with stock
    -- pillars enabled on a real process launch. On CET Reload All Mods, the
    -- main UltrawideUIOverhaul module will immediately reassert the correct
    -- state for the currently attached screen.

    Observe(
        "LoadingScreenProgressBarController",
        "SetProgress",
        function()
            beginLoading()
        end
    )

    -- Main Menu -> Continue.
    pcall(function()
        ObserveBefore(
            "gameuiMenuItemListGameController",
            "OnMenuItemActivated",
            function(_, _, target)
                if target == nil then return end

                local data = nil
                local dataOk = pcall(function()
                    data = target:GetData()
                end)
                if not dataOk or data == nil then return end

                local action = -1
                pcall(function()
                    action = tonumber(EnumInt(data.action)) or -1
                end)

                if action == 5 then
                    beginLoading()
                end
            end
        )
    end)

    -- Main Menu -> Load Game -> select save.
    pcall(function()
        ObserveBefore(
            "LoadGameMenuGameController",
            "OnRelease",
            function(_, event)
                if event == nil then return end

                local isClick = false
                pcall(function()
                    isClick = event:IsAction(CName.new("click"))
                end)
                if not isClick then return end

                local validSlot = false
                pcall(function()
                    local widget = event:GetCurrentTarget()
                    if widget == nil then return end

                    local controller = widget:GetController()
                    if controller ~= nil and controller:ValidSlot() then
                        validSlot = true
                    end
                end)

                if validSlot then
                    beginLoading()
                end
            end
        )
    end)

    pcall(function()
        ObserveBefore(
            "LoadGameMenuGameController",
            "LoadGame;LoadListItem",
            function()
                beginLoading()
            end
        )
    end)

    pcall(function()
        ObserveBefore(
            "inkISystemRequestsHandler",
            "LoadLastCheckpoint",
            function()
                beginLoading()
            end
        )
    end)

    pcall(function()
        ObserveBefore(
            "inkISystemRequestsHandler",
            "LoadSavedGame",
            function()
                beginLoading()
            end
        )
    end)

    pcall(function()
        ObserveBefore(
            "gameuiSaveHandlingController",
            "LoadModdedSave",
            function()
                beginLoading()
            end
        )
    end)

    pcall(function()
        ObserveBefore(
            "gameuiSaveHandlingController",
            "PreSpawnInitialLoadingScreen",
            function()
                beginLoading()
            end
        )
    end)

    pcall(function()
        ObserveBefore(
            "gameuiSaveHandlingController",
            "LoadSaveInGame",
            function()
                beginLoading()
            end
        )
    end)

    -- Quickload from gameplay.
    pcall(function()
        ObserveBefore(
            "gameuiInGameMenuGameController",
            "OnQuickLoadSavesReady",
            function()
                beginLoading()
            end
        )
    end)

    Observe(
        "QuestTrackerGameController",
        "OnInitialize",
        function()
            endLoading()
        end
    )

    Observe(
        "QuestTrackerGameController",
        "OnUninitialize",
        function()
            if Game.GetPlayer() == nil then
                beginLoading()
            end
        end
    )
end)


---------------------------------------------------------------------------
-- Shutdown
---------------------------------------------------------------------------

registerForEvent("onShutdown", function()
    loadingActive = false
    pillarsDisabled = nil
    pillarsLockedOff = false
    temporaryPillarsVisible = false

    -- Keep native compositor state intact across CET hot reloads.
    UWMenuSetPillarsDisabled = nil
    UWMenuSetTemporaryPillarsVisible = nil
end)

return publicApi
