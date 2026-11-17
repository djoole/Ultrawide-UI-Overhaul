"""Compare Crafting to the pre-fix 2f0aff5 revision on the captured Ink tree."""
import re
import subprocess
from pathlib import Path
from lupa.lua54 import LuaRuntime
from fixture_io import read_ink_dump

SOURCE = Path('cet/UltrawideUIOverhaul/init.lua').read_text(encoding='utf-8')
BASELINE = subprocess.check_output(['git', 'show', '2f0aff5:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')
DUMP = read_ink_dump('ink_tree_dump_20261116-094834_01_inkMenuLayer.json')
HOLDER = 'inkMenuLayer/inkVirtualWindow/Root[0]/Root[0]/craftingPanel[1]/inkCanvasWidget2[0]/leftContainer[1]/list_holder[2]'


def run(source, width, height, spread):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        events = {}; writes = {}
        function registerForEvent(name, fn) events[name] = fn end
        CName = {new=function(s) return s end}
        function GetMod() return nil end
        function UWMapSetBlackBarsSuppressed() end
        function makeWidget(n)
            n.childWidgets = {}
            function n:GetWidget(i) return self.childWidgets[i] end
            function n:GetName() return {value=self.name} end
            function n:GetSize() return {X=self.size[1],Y=self.size[2]} end
            function n:SetSize(x,y)
                self.size = {x,y}; writes[self.path] = {size={x,y}}
            end
            function n:GetMargin()
                return {left=self.margin[1],top=self.margin[2],right=self.margin[3],bottom=self.margin[4]}
            end
            function n:SetMargin(l,t,r,b)
                self.margin={l,t,r,b}; writes[self.path]={margin={l,t,r,b}}
            end
            function n:FlagForVisualInvalidation() end
            return n
        end
        function findValue(fn,wanted,value,replace,seen)
            seen=seen or {}; if seen[fn] then return nil end; seen[fn]=true
            for i=1,255 do
                local name,v=debug.getupvalue(fn,i); if not name then break end
                if name==wanted then
                    if replace then debug.setupvalue(fn,i,value) end
                    return v
                end
                if type(v)=='function' then
                    local found=findValue(v,wanted,value,replace,seen)
                    if found~=nil then return found end
                end
            end
        end
    ''')
    widgets = {n['path']: lua.globals().makeWidget(lua.table_from(n, recursive=True)) for n in DUMP['nodes']}
    for path, widget in widgets.items():
        if path == DUMP['root']:
            continue
        parent, child = path.rsplit('/', 1)
        widgets[parent].childWidgets[int(re.search(r'\[(\d+)\]$', child).group(1))] = widget
    lua.globals().window = widgets[DUMP['root']]
    lua.globals().screenWidth, lua.globals().screenHeight = width, height
    lua.execute('''
        function GetDisplayResolution() return screenWidth,screenHeight end
        Game={GetInkSystem=function() return {GetLayer=function()
            return {GetVirtualWindow=function() return window end}
        end} end}
    ''')
    lua.execute(source)
    find = lua.globals().findValue
    apply = find(lua.globals().events.onInit, 'applyCraftingLayoutDirect')
    assert apply is not None
    assert find(apply, 'UI_SPREAD_PERCENT', spread, True) is not None
    assert apply(lua.table(), 'captured crafting test')
    output = {path: tuple(widget.size.values()) + tuple(widget.margin.values()) for path, widget in widgets.items()}
    assert apply(lua.table(), 'repeat')
    assert output == {path: tuple(widget.size.values()) + tuple(widget.margin.values()) for path, widget in widgets.items()}
    return output


for width, height in [(3440,1440), (5120,1440), (2880,1440)]:
    for spread in [0,25,50,100]:
        before, after = run(BASELINE,width,height,spread), run(SOURCE,width,height,spread)
        changed = {path for path in before if before[path] != after[path]}
        assert changed == ({HOLDER} if spread < 100 else set()), changed
        assert abs(after[HOLDER][0] - before[HOLDER][0] - 200*(1-spread/100)) < 1e-6
        if spread == 0:
            assert after[HOLDER][0] == 1350
        print(f'PASS {width}x{height} spread {spread}%: holder {before[HOLDER][0]} -> {after[HOLDER][0]}, all other sizes/margins unchanged')
