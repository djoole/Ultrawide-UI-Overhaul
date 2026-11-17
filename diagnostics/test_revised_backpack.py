"""Replay the real resolver/layout with both authored and reordered root children."""
from pathlib import Path
import random
import subprocess
from lupa.lua54 import LuaRuntime

SOURCE = Path('cet/UltrawideUIOverhaul/init.lua').read_text(encoding='utf-8')
BASELINE = subprocess.check_output(['git', 'show', '5d44e03:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')
RUNTIME = ['previewItem', 'categories', 'header', 'scrollWrapper', 'button_hints',
           'itemListRoot', 'previewGarment', 'filters', 'selectedItemsCount']
AUTHORED = ['categories', 'header', 'scrollWrapper', 'button_hints', 'tooltipContainer',
            'itemListRoot', 'previewItem', 'previewGarment', 'filters', 'selectedItemsCount']


def setup(source, order, width=3840, height=1600, spread=100):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        events={}; writes=0; logs={}; suppressed=false
        function registerForEvent(n,f) events[n]=f end
        CName={new=function(n) return n end}
        function GetMod() return nil end
        function UWMapSetBlackBarsSuppressed(v) suppressed=v end
        function captureLog(v) logs[#logs+1]=v end
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
        nodes={}
        function node(name,id)
            local n={name=name,children={},size={X=3840,Y=80},margin={left=0,top=0,right=0,bottom=0}}
            function n:GetName() return {value=self.name} end
            function n:GetNumChildren() local count=0;for _ in pairs(self.children) do count=count+1 end;return count end
            function n:GetWidget(i) return self.children[i] end
            function n:GetSize() return self.size end
            function n:SetSize(x,y) self.size={X=x,Y=y};writes=writes+1 end
            function n:SetMargin(l,t,r,b) self.margin={left=l,top=t,right=r,bottom=b};writes=writes+1 end
            function n:FlagForVisualInvalidation() end
            nodes[id or name]=n;return n
        end
        root=node('Root','root');root.size={X=3840,Y=2160}
        controller={GetRootWidget=function() return root end}
    ''')
    nodes = lua.globals().nodes
    make = lua.globals().node
    for i, name in enumerate(order):
        child = make(name, f'{name}-{i}' if name in nodes else name)
        lua.globals().root.children[i] = child
    for preview in ['previewItem', 'previewGarment']:
        parent = nodes[preview]
        for name in ['Root', 'wrapper', 'preview']:
            key = preview + '/' + name
            child = make(name, key)
            parent.children[0] = child
            parent = child
    nodes.header.children[0] = make('nameContainer', 'headerName')
    nodes.header.children[1] = make('questContainer', 'headerQuest')
    nodes.header.children[2] = make('typeContainer', 'headerType')
    nodes.scrollWrapper.children[0] = make('sliderArea')
    nodes.scrollWrapper.children[1] = make('scrollArea')
    lua.globals().screenWidth, lua.globals().screenHeight = width, height
    lua.execute('function GetDisplayResolution() return screenWidth,screenHeight end')
    lua.execute(source)
    find = lua.globals().find
    apply = find(lua.globals().events.onInit, 'tryApplyRevisedBackpackMainLayout')
    assert apply is not None
    assert find(apply, 'UI_SPREAD_PERCENT', spread, True) is not None
    return lua, apply


def snapshot(lua):
    return {name: (n.size.X, n.size.Y, n.margin.left, n.margin.top, n.margin.right, n.margin.bottom)
            for name, n in lua.globals().nodes.items()}


# Demonstrate the real 2.5.10 failure before validating its correction.
old, old_apply = setup(BASELINE, AUTHORED)
assert not old_apply(old.globals().controller, 'official order')
assert old.globals().writes == 0
old, old_apply = setup(BASELINE, RUNTIME)
assert old_apply(old.globals().controller, 'previous runtime order')
print('PASS reproduced 2.5.10 rejection of authored order; prior runtime order succeeds')

for width, height in [(3840,1600), (3440,1440), (5120,1440), (2880,1440)]:
    for spread in [0,50,100]:
        prior, prior_apply = setup(BASELINE, RUNTIME, width, height, spread)
        current, current_apply = setup(SOURCE, RUNTIME, width, height, spread)
        assert prior_apply(prior.globals().controller, 'baseline')
        assert current_apply(current.globals().controller, 'candidate')
        assert snapshot(prior) == snapshot(current)
        authored, authored_apply = setup(SOURCE, AUTHORED, width, height, spread)
        assert authored_apply(authored.globals().controller, 'official order')
        expected = snapshot(current)
        actual = snapshot(authored)
        assert {k: actual[k] for k in expected} == expected
        assert authored_apply(authored.globals().controller, 'repeat')
        assert snapshot(authored) == actual
print('PASS identical prior geometry, 21:9 cap and previews across 12 ratio/spread cases; authored order works')

# Ensure the top-level lookup does not depend on any sibling positions.
rng = random.Random(17642)
for _ in range(16):
    order = AUTHORED.copy(); rng.shuffle(order)
    lua, apply = setup(SOURCE, order)
    assert apply(lua.globals().controller, 'permuted order')
print('PASS 16 sibling-order permutations')

# Safety and readiness behavior: no mutation until every required widget exists.
lua, apply = setup(SOURCE, AUTHORED)
find = lua.globals().find
assert find(apply, 'ACTIVATE_DEBUG_LOGS', True, True) is not None
assert find(apply, 'writeDebugLog', lua.globals().captureLog, True) is not None
root = lua.globals().root
preview = lua.globals().nodes.previewItem
spawned = preview.children[0]; preview.children[0] = None
assert not apply(lua.globals().controller, 'before spawn')
assert lua.globals().writes == 0
assert 'previewItem/Root[0]' in lua.globals().logs[1]
for _ in range(20): assert not apply(lua.globals().controller, 'still waiting')
assert len(lua.globals().logs) == 1
preview.children[0] = spawned
assert apply(lua.globals().controller, 'spawn ready')
assert lua.globals().UWUI_revisedBackpack.lastPendingReason is None
ready = [line for line in lua.globals().logs.values() if 'REVISED BACKPACK main ready' in line]
assert len(ready) == 1 and 'rootChildren=[' in ready[0]
print('PASS delayed preview readiness, specific pending log, no per-frame log spam, eventual success')

lua, apply = setup(SOURCE, AUTHORED + ['header'])
assert not apply(lua.globals().controller, 'duplicate header')
assert lua.globals().writes == 0
for missing in ['previewItem','categories','header','scrollWrapper','itemListRoot','previewGarment','selectedItemsCount']:
    lua, apply = setup(SOURCE, AUTHORED)
    for _, child in lua.globals().root.children.items():
        if child.name == missing: child.name = 'unexpected'
    assert not apply(lua.globals().controller, 'missing required widget')
    assert lua.globals().writes == 0
lua, apply = setup(SOURCE, AUTHORED, 1920, 1080)
assert not apply(lua.globals().controller, 'unsupported aspect')
assert lua.globals().writes == 0
print('PASS ambiguous/missing signatures and unsupported ratio rejected without mutation')
