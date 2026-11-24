"""Exercise real Vendor observers/timer with an empty inventory on either side."""
import subprocess
from pathlib import Path
from lupa.lua54 import LuaRuntime

SOURCE = Path('cet/UltrawideUIOverhaul/init.lua').read_text(encoding='utf-8')
BUILD8 = subprocess.check_output(['git', 'show', '617211b:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')


def setup(source=SOURCE):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        events={}; observers={}; geometryCalls=0; playerCalls=0; vendorCalls=0
        playerColumns=6;vendorColumns=6
        function registerForEvent(n,f) events[n]=f end
        function Observe(c,m,f) observers[c..'.'..m]=f end
        ObserveAfter=Observe; ObserveBefore=Observe
        function Override() end
        function GetMod() return nil end
        function GetDisplayResolution() return 3440,1440 end
        function FromVariant(v) return v end
        function print() end
        io={open=function() return nil end}
        function find(fn,wanted,value,replace,seen)
            seen=seen or {};if seen[fn] then return nil end;seen[fn]=true
            for i=1,255 do
                local n,v=debug.getupvalue(fn,i);if not n then break end
                if n==wanted then
                    if replace then debug.setupvalue(fn,i,value) end
                    return v
                end
                if type(v)=='function' then
                    local found=find(v,wanted,value,replace,seen)
                    if found~=nil then return found end
                end
            end
        end
        playerRadio={GetSelectedIndex=function() return 9 end}
        vendorRadio={GetSelectedIndex=function() return 0 end}
        tree={playerFilters={GetController=function() return playerRadio end},
            vendorFilters={GetController=function() return vendorRadio end}}
        function resolveTree() return tree end
        function applyGeometry() geometryCalls=geometryCalls+1;return true end
        function virtualItem(side)
            return {GetClassName=function() return {value='VendorItemVirtualController'} end,
                GetRootWidget=function() return nil end,
                GetData=function() return {IsVendorItem=side} end}
        end
        main={}
        function main:OnPlayerFilterChange(r,i)
            assert(r==playerRadio and i==9,'preserve selected player filter')
            playerCalls=playerCalls+1;playerColumns=10
            observers['VendorItemVirtualController.OnDataChanged;Variant'](virtualItem(false))
        end
        function main:OnVendorFilterChange(r,i)
            assert(r==vendorRadio and i==0,'preserve selected vendor filter')
            vendorCalls=vendorCalls+1;vendorColumns=10
            observers['VendorItemVirtualController.OnDataChanged;Variant'](virtualItem(true))
        end
    ''')
    lua.execute(source)
    find = lua.globals().find
    find(lua.globals().events.onInit, 'applyVendorExact', lua.globals().applyGeometry, True)
    find(lua.globals().events.onUpdate, 'resolveVendorTreeExact', lua.globals().resolveTree, True)
    lua.globals().events.onInit()
    lua.globals().observers['FullscreenVendorGameController.OnInitialize'](lua.globals().main)
    # Initial All Items selection is tested separately. Start with the observed
    # selected indices, then verify the deferred refresh preserves them.
    find(lua.globals().events.onInit, 'vendorDefaultPlayerFilterForced', True, True)
    return lua


def bind(lua, vendor):
    lua.globals().observers['VendorItemVirtualController.OnDataChanged;Variant'](lua.globals().virtualItem(vendor))


# The previous gate waits forever for an item from the empty Drop Point.
lua = setup(BUILD8)
bind(lua, False)
lua.globals().events.onUpdate(1)
assert lua.globals().playerColumns == 6 and lua.globals().playerCalls == 0
print('PASS build8 reproduces the six-column layout with an empty vendor inventory')

for sides in [[], [False], [True], [False, True], [True, False]]:
    lua = setup()
    for side in sides:
        for _ in range(4): bind(lua, side)
    lua.globals().events.onUpdate(0.10)
    assert lua.globals().playerCalls == lua.globals().vendorCalls == 0
    lua.globals().events.onUpdate(0.11)
    expected = int(bool(sides))
    assert lua.globals().playerCalls == lua.globals().vendorCalls == expected, sides
    assert lua.globals().playerColumns == (10 if sides else 6), sides
    if sides:
        # Late binds or synchronous binds from the refresh must not arm a loop.
        bind(lua, False); bind(lua, True)
    for _ in range(100): lua.globals().events.onUpdate(0.1)
    assert lua.globals().playerCalls == lua.globals().vendorCalls == expected
print('PASS empty player/vendor, both populated and both empty; one deferred refresh preserving filters, no recurring work')

lua = setup(); bind(lua, False)
lua.globals().observers['FullscreenVendorGameController.OnUninitialize']()
lua.globals().events.onUpdate(1)
assert lua.globals().playerCalls == 0
lua.globals().observers['FullscreenVendorGameController.OnInitialize'](lua.globals().main)
lua.globals().find(lua.globals().events.onInit, 'vendorDefaultPlayerFilterForced', True, True)
bind(lua, False);lua.globals().events.onUpdate(0.21)
assert lua.globals().playerCalls == lua.globals().vendorCalls == 1
print('PASS closure cancels pending work; reopening schedules a fresh one-shot refresh')

lua = setup()
lua.globals().find(lua.globals().events.onInit, 'stashMenuActive', True, True)
bind(lua, False);lua.globals().events.onUpdate(1)
assert lua.globals().playerCalls == lua.globals().vendorCalls == 0
print('PASS Stash remains excluded from the Vendor refresh')
