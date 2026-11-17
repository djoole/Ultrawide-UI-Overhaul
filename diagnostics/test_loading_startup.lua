-- Replay the real Lua loading/pillar functions with mocked game boundaries.
-- Run from the repository root under Lua 5.4 (also supported by Python lupa).
local function findUpvalue(root, target, seen)
    seen = seen or {}
    if type(root) ~= "function" or seen[root] then return nil end
    seen[root] = true
    local children = {}
    for i = 1, 255 do
        local name, value = debug.getupvalue(root, i)
        if name == nil then break end
        if name == target then return value end
        if type(value) == "function" then children[#children + 1] = value end
    end
    for _, child in ipairs(children) do
        local value = findUpvalue(child, target, seen)
        if value ~= nil then return value end
    end
end

local function put(fn, target, value)
    for i = 1, 255 do
        local name = debug.getupvalue(fn, i)
        if name == nil then break end
        if name == target then debug.setupvalue(fn, i, value); return end
    end
    error("Missing test dependency: " .. target)
end

local function widget()
    return setmetatable({}, {__index = function(_, key)
        if key == "GetScale" then return function() return {X = 1, Y = 1} end end
        return function(self)
            if rawget(self, "fail") then error("simulated Ink mutation failure") end
        end
    end})
end

local function context()
    local events, observers, states = {}, {}, {}
    registerForEvent = function(name, fn) events[name] = fn end
    Observe = function(class, method, fn) observers[class .. "." .. method] = fn end
    ObserveBefore = Observe
    UWMapSetBlackBarsSuppressed = function(disabled) states[#states + 1] = disabled end
    Game = {GetPlayer = function() return nil end}
    Vector2 = {new = function(v) return v end}
    HDRColor = Vector2
    CName = Vector2
    inkEAnchor = {TopRight = 1, BottomLeft = 2}
    inkRectangleWidget = {new = widget}
    spdlog = {error = function() end}

    assert(loadfile("cet/UltrawideUIOverhaul/init.lua"))()
    local update = events.onUpdate
    local initial = assert(findUpvalue(update, "applyInitialLoadingSceneCoverExact"))
    local fast = assert(findUpvalue(update, "applyLoadingScreenLayoutExact"))
    local release = assert(findUpvalue(update, "releaseLoadingPillarsIfReady"))
    local main = assert(findUpvalue(update, "releaseMainMenuPillarsIfReady"))
    local coordinator = assert(loadfile("cet/BlackPillarsCoordinator/init.lua"))()
    GetMod = function() return coordinator end
    events.onInit()
    assert(#states == 0, "onInit must preserve the native startup state")

    local scene = widget()
    local initialTree = {outerRoot = widget(), scenes = {{widget = scene}}}
    local defaultTree = {blackMask = widget()}
    local fastTree = setmetatable({}, {__index = function(t, k)
        local value = widget(); rawset(t, k, value); return value
    end})
    local ready = false
    put(initial, "getTargetGeometry", function()
        return {aspect = 3440 / 1440, contentWidth = 5160, halfExtra = 660}
    end)
    put(initial, "setWidgetSizeExact", function(w) return not rawget(w, "fail") end)
    put(initial, "resolveInitialLoadingSceneTreeExact", function()
        return ready and initialTree or nil
    end)
    put(fast, "resolveLoadingScreenTreeExact", function() return ready and fastTree or nil end)
    put(fast, "resizeWidgetWidth", function() return true end)
    UWUI_resolveDefaultLoadingMaskExact = function() return ready and defaultTree or nil end
    put(release, "startupPillarLockActive", true)
    put(update, "mainMenuWatchActive", true)
    put(main, "mainMenuPillarReleaseArmed", true)
    return {
        states = states, observers = observers, coordinator = coordinator,
        initial = initial, default = UWUI_applyDefaultLoadingMaskExact, fast = fast,
        release = release, main = main, scene = scene, update = update,
        ready = function() ready = true end,
        count = function() return #states end,
        last = function() return states[#states] end,
    }
end

local function begin(c)
    c.observers["LoadingScreenProgressBarController.SetProgress"]()
end
local function verifyReleased(c)
    assert(c.last() == true, "pillars must be suppressed")
    assert(findUpvalue(c.release, "startupPillarLockActive") == false)
    assert(findUpvalue(c.update, "mainMenuWatchActive") == true)
    assert(findUpvalue(c.main, "mainMenuPillarReleaseArmed") == true)
    begin(c)
    assert(c.last() == true, "loading progress must not restore pillars")
    c.coordinator.SetPillarsDisabled(false)
    assert(c.last() == true, "startup callbacks must not undo the latch")
end

for _, kind in ipairs({"initial", "default", "fast"}) do
    local c = context()
    begin(c)
    local count = c.count()
    assert(c[kind]({}, nil) == false)
    assert(c.count() == count, "unready loading tree must not release pillars")
    c.ready()
    assert(c[kind]({}, nil) == true)
    verifyReleased(c)
    print("PASS direct-load " .. kind .. ": readiness gate and durable suppression")
end

do
    local c = context()
    begin(c); c.ready(); c.scene.fail = true
    local count = c.count()
    assert(c.initial({}, nil) == false)
    assert(c.count() == count, "failed refit must preserve bars")
    assert(findUpvalue(c.release, "startupPillarLockActive") == true)
    c.scene.fail = nil
    assert(c.initial({}, nil) == true)
    verifyReleased(c)
    print("PASS failed scene mutation waits for a successful retry")
end

do
    local c = context()
    c.ready()
    GetMod = function() error("backend temporarily unavailable") end
    assert(c.initial({}, nil) == false)
    assert(findUpvalue(c.release, "startupPillarLockActive") == true)
    GetMod = function() return c.coordinator end
    assert(c.initial({}, nil) == true)
    verifyReleased(c)
    print("PASS backend failure leaves the loading readiness retry active")
end

do
    local c = context()
    put(c.main, "mainMenuSceneRefitted", false)
    assert(c.main("test") == false and c.count() == 0)
    put(c.main, "mainMenuSceneRefitted", true)
    assert(c.main("test") == true and c.last() == true)
    begin(c); c.ready(); assert(c.initial({}, nil) == true)
    verifyReleased(c)
    print("PASS normal Main Menu still waits for its scene, then loads ultrawide")
end

do
    local c = context()
    c.ready(); assert(c.initial({}, nil) == true)
    c.coordinator.SetTemporaryPillarsVisible(true)
    assert(c.last() == false, "arcade must retain native pillars")
    c.coordinator.SetTemporaryPillarsVisible(false)
    assert(c.last() == true, "leaving arcade must restore ultrawide")
    print("PASS arcade's temporary authored-aspect scope still works")
end

do
    local c = context()
    begin(c)
    c.observers["QuestTrackerGameController.OnInitialize"]()
    assert(c.last() == true)
    begin(c)
    assert(c.last() == true, "world-entry fallback must also latch suppression")
    print("PASS world-entry fallback latches suppression without a Main Menu")
end
