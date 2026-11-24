"""Replay Crafting geometry and verify whole columns across viewport thresholds."""
import math
import re
import subprocess
from pathlib import Path
from lupa.lua54 import LuaRuntime
from fixture_io import read_ink_dump

SOURCE = Path('cet/UltrawideUIOverhaul/init.lua').read_text(encoding='utf-8')
BASELINE = subprocess.check_output(['git', 'show', '7d0c98d5cce9be768e4fdc678a712faee9028583:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')
DUMP = read_ink_dump('ink_tree_dump_20261116-094834_01_inkMenuLayer.json')
HOLDER = 'inkMenuLayer/inkVirtualWindow/Root[0]/Root[0]/craftingPanel[1]/inkCanvasWidget2[0]/leftContainer[1]/list_holder[2]'
CACHE = HOLDER + '/cache[2]'
SCROLL = CACHE + '/scroll_area[0]'
VIRTUAL = SCROLL + '/virtualListContainer[0]'
FRAME = HOLDER + '/gridFrame[1]'
GRID_PATHS = {HOLDER,CACHE,SCROLL,VIRTUAL,FRAME}

# Independently establish the cell pitch from the real recipe widgets. Large
# weapons span three cells (672), while small recipes occupy one (224).
recipe_widths = {round(n['size'][0]) for n in DUMP['nodes']
                 if n['path'].startswith(VIRTUAL+'/') and n['depth']==10 and n['name']=='recipeItem'}
assert 224 in recipe_widths and 672 in recipe_widths
assert math.gcd(*recipe_widths)==224
mask = next(n for n in DUMP['nodes'] if n['path']==HOLDER+'/gradient_mask[0]')
assert mask['margin'][0]==-5 and mask['margin'][2]==5


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


for width, height in [(3440,1440), (5120,1440), (2880,1440), (5120,2160)]:
    for spread in [0,25,50,75,95,100]:
        before, after = run(BASELINE,width,height,spread), run(SOURCE,width,height,spread)
        changed = {path for path in before if before[path] != after[path]}
        assert changed <= GRID_PATHS, changed
        for path in before:
            assert before[path][1:]==after[path][1:],path
        visible_width=after[HOLDER][0]
        columns=math.floor(after[VIRTUAL][0]/224)
        assert after[CACHE][0]==after[SCROLL][0]==after[VIRTUAL][0]==visible_width
        assert after[FRAME][0]==visible_width+2
        assert columns*224 <= visible_width-5
        assert 0 <= visible_width-columns*224 < 224
        if spread == 0:
            assert not changed and visible_width==1350 and columns==6
        if (width,height,spread)==(3440,1440,95):
            assert before[VIRTUAL][0]==2813 and before[HOLDER][0]==2623
            assert math.floor(before[VIRTUAL][0]/224)*224 > before[HOLDER][0]
            assert columns==11 and visible_width==2470
        if (width,height,spread)==(3440,1440,100):
            assert columns==12 and visible_width==2694
        print(f'PASS {width}x{height} spread {spread}%: {columns} whole columns, viewport={visible_width}; details, heights and margins unchanged')

lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('function registerForEvent() end')
lua.execute(SOURCE)
calculate=lua.globals().UWUI_crafting.getColumnGeometry
cases=0
for aspect in [1.99,2,2.1,2560/1080,3440/1440,2.4,3,32/9,3.65]:
    previous=0
    for step in range(1001):
        spread=step/1000
        geometry=lua.table_from({'contentWidth':3840+(aspect*2160-3840)*spread,'uiSpread':spread})
        result=calculate(geometry)
        columns=result.columns
        assert columns>=previous
        previous=columns
        assert columns==math.floor(result.width/224)
        assert columns*224 <= result.width-5
        assert (columns+1)*224 > result.visibleBudget-1e-6
        assert columns*224 <= result.visibleBudget+1e-6
        assert result.width <= result.visibleBudget+6+1e-6
        assert result.detailsLeft-(result.width+2)>=57-1e-6
        cases+=1
    # Check both sides of every column-count transition, not only round
    # percentages. The extra 20 is the legacy visible-holder spread term.
    total=aspect*2160-3840+20
    for columns in range(7,50):
        threshold=(columns*224-1350)/total
        if 0<threshold<1:
            for delta,expected in [(-1e-7,columns-1),(1e-7,columns)]:
                spread=threshold+delta
                geometry=lua.table_from({'contentWidth':3840+(aspect*2160-3840)*spread,'uiSpread':spread})
                assert calculate(geometry).columns==expected
print(f'PASS {cases} ratio/spread samples plus every column threshold: complete cells, native count consistency and details-panel clearance')
