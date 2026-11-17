"""Replay tooltip-mode changes against the user's Cyberware Ink dump."""
import re
from pathlib import Path

from lupa.lua54 import LuaRuntime
from fixture_io import read_ink_dump

dump = read_ink_dump("ink_tree_dump_20261031-123907_01_inkMenuLayer.json")
source = Path("cet/UltrawideUIOverhaul/init.lua").read_text(encoding="utf-8")
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
    events = {}; before = {}; after = {}; writes = {}
    function registerForEvent(n,f) events[n]=f end
    function ObserveBefore(c,m,f) before[c..'.'..m]=f end
    function ObserveAfter(c,m,f) after[c..'.'..m]=f end
    function Observe() end
    CName={new=function(v) return v end}
    Vector2={new=function(v) return v end}
    function makeWidget(n)
        n.childWidgets={}
        function n:GetWidget(i) return self.childWidgets[i] end
        function n:GetName() return {value=self.name} end
        function n:GetSize() return {X=self.size[1],Y=self.size[2]} end
        function n:GetTranslation() return {X=self.translation[1],Y=self.translation[2]} end
        function n:SetTranslation(v)
            self.translation[1]=v.X; self.translation[2]=v.Y
            writes[#writes+1]=self.path
        end
        function n:FlagForVisualInvalidation() end
        return n
    end
""")
widgets = {n["path"]: lua.globals().makeWidget(lua.table_from(n, recursive=True)) for n in dump["nodes"]}
for path, widget in widgets.items():
    if path == dump["root"]:
        continue
    parent, child = path.rsplit("/", 1)
    widgets[parent].childWidgets[int(re.search(r"\[(\d+)\]$", child).group(1))] = widget
root_path = "inkMenuLayer/inkVirtualWindow/Root[0]/Root[0]"
tip_path = root_path + "/tooltipContainer[5]"
lua.globals().window = widgets[dump["root"]]
lua.globals().contentRoot = widgets[root_path]
lua.globals().tooltip = widgets[tip_path]
lua.execute("""
    screenWidth=3440;screenHeight=1440
    function GetDisplayResolution() return screenWidth,screenHeight end
    Game={GetInkSystem=function() return {GetLayer=function()
        return {GetVirtualWindow=function() return window end}
    end} end}
    manager={GetRootWidget=function() return contentRoot end}
""")
lua.execute(source)
# Register the actual unique-method observer block without initializing all
# unrelated game controllers and Native Settings in the mocked environment.
start = source.index("    -- These are unique script methods")
end = source.index("    -- Native Settings: both pre-game", start)
lua.execute(source[start:end])
lua.execute("""
    function expect(x)
        assert(math.abs(tooltip.translation[1]-x)<0.00001)
        assert(tooltip.translation[2]==0)
        assert(tooltip.margin[1]==1105.5 and tooltip.margin[2]==813)
    end
    after['RipperDocGameController.OnInitialize'](); expect(0)
    after['gameuiTooltipsManager.AttachToCursor'](manager); expect(-660)
    -- The final callback must restore the correction even if the native show
    -- path reset the translation in between AttachToCursor and OnBarHover.
    tooltip.translation[1]=0
    after['RipperDocGameController.OnBarHover'](); expect(-660)
    after['RipperDocGameController.OnBarHover'](); expect(-660)
    print('PASS capacity/armor cursor tooltips: -660, native reset, no cumulative drift')
    before['RipperDocGameController.ShowCWTooltip'](); expect(0)
    after['RipperDocGameController.OnBarHover']()
    before['RipperDocGameController.ShowCWPerkTooltip'](); expect(0)
    before['RipperDocGameController.ShowCategoryTooltip']()
    after['RipperDocGameController.ShowCategoryTooltip'](); expect(0)
    print('PASS item, perk and widget-attached category tooltips reset the translation')
    before['RipperDocGameController.ShowCategoryTooltip']()
    after['gameuiTooltipsManager.AttachToCursor'](manager)
    tooltip.translation[1]=0
    after['RipperDocGameController.ShowCategoryTooltip'](); expect(-660)
    after['RipperDocGameController.OnBarUnhover'](); expect(0)
    print('PASS category tooltip cursor fallback and hover-out cleanup')
    local n=#writes
    assert(not UWUI_cyberwareTooltips.apply(true,'foreign manager',{
        GetRootWidget=function() return window end
    }))
    assert(#writes==n); expect(0)
    print('PASS unrelated tooltip managers do not change this container')
    for _,case in ipairs({{2880,1440,-240},{5120,1440,-1920},{3440,1440,-660},{1920,1080,0}}) do
        screenWidth=case[1]
        screenHeight=case[2]
        assert(UWUI_cyberwareTooltips.apply(true,'ratio test'))
        expect(case[3])
    end
    screenWidth=3440; screenHeight=1440
    contentRoot.size[1]=5160
    assert(UWUI_cyberwareTooltips.apply(true,'already widened root')); expect(0)
    print('PASS 2:1 / 21:9 / 32:9 / 16:9 and a root already widened by another layout')
    for _,path in ipairs(writes) do assert(path==tooltip.path) end
    print('PASS only tooltip translation changed; native margins and all other widgets preserved')
""")
