-- Replay real layout functions in the order missing from the 2.5.7 tests:
-- loading ready -> main scene attached later -> scene replaced -> gameplay.
local function read(path)
    local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end
local helpers=read("diagnostics/test_loading_startup.lua")
local prefix=assert(helpers:match("^(.-)for _, kind in ipairs"))
local context,findUpvalue,put=assert(load(prefix .. "\nreturn context,findUpvalue,put"))()
local source=read("cet/UltrawideUIOverhaul/init.lua")
local block="if mainMenuWatchActive then" .. assert(source:match(
    "    if mainMenuWatchActive then(.-)    if hubLayoutWatchActive then"
))

local function tickFrom(update)
    -- Bind the actual onUpdate block back to the real callback's upvalues.
    local env=setmetatable({}, {
        __index=function(_,key)
            for i=1,255 do
                local n,v=debug.getupvalue(update,i)
                if n==nil then break end
                if n==key then return v end
            end
            return _G[key]
        end,
        __newindex=function(_,key,value) put(update,key,value) end
    })
    return assert(load("return function()\n"..block.."\nend", "mainMenuUpdate", "t", env))()
end

local function scene()
    local w={scale={X=1,Y=1},translation={X=0,Y=0},margin={left=0,top=0,right=0,bottom=0}}
    function w:GetScale() return self.scale end
    function w:SetScale(v) self.scale=v end
    function w:GetTranslation() return self.translation end
    function w:SetTranslation(v) self.translation=v end
    function w:GetMargin() return self.margin end
    function w:SetMargin(l,t,r,b) self.margin={left=l,top=t,right=r,bottom=b} end
    function w:FlagForVisualInvalidation() end
    return w
end

for _,kind in ipairs({"initial","default","fast"}) do
    local c=context()
    local preGame=true
    local currentScene=nil
    local root={size={X=3840,Y=2160}}
    function root:GetSize() return self.size end
    function root:SetSize(x,y) self.size={X=x,Y=y} end
    function root:FlagForVisualInvalidation() end
    local apply=assert(findUpvalue(c.update,"tryApplyMainMenuExact"))
    put(apply,"resolveMainMenuExact",function()
        if currentScene==nil then return nil end
        return {contentRoot=root,scene=currentScene}
    end)
    put(c.update,"isPreGame",function() return preGame end)
    local tick=tickFrom(c.update)
    c.ready()
    assert(c[kind]({},nil)==true)
    assert(c.last()==true,"auto-load loading screen must still suppress pillars")
    tick() -- menu scene not attached yet
    currentScene=scene()
    tick() -- now the menu scene arrives, after the loading hand-off
    assert(root.size.X==5160,
        kind..": early loading hand-off cancelled the late Main Menu refit")
    assert(currentScene.scale.X==5160/3840)
    assert(currentScene.margin.left==660)
    local crop=(2160*(5160/3840)-2160)*0.5
    assert(currentScene.translation.Y==-crop)
    assert(findUpvalue(c.main,"mainMenuPillarsReleased")==true,
        "loading must not disarm the Main Menu release gate")

    currentScene=scene() -- progression/Preem replaces the background later
    tick()
    assert(currentScene.scale.X==5160/3840,"replacement scene must also be refitted")
    preGame=false
    tick()
    assert(findUpvalue(c.update,"mainMenuWatchActive")==false,
        "watch must stop when the game actually leaves pre-game")
    print("PASS "..kind.." loading before Main Menu: late scene, replacement and gameplay cleanup")
end
