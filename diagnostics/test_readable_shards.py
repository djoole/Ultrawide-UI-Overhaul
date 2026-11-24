"""Exercise the real CET adapter with the two observed Shards hierarchies."""
from pathlib import Path
import subprocess
from lupa.lua54 import LuaRuntime

SOURCE = Path('cet/UltrawideUIOverhaul/init.lua').read_text(encoding='utf-8')
BASELINE = subprocess.check_output(['git', 'show', 'v2.5.11:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')
BUILD1 = subprocess.check_output(['git', 'show', '86fef3d:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')
BUILD2 = subprocess.check_output(['git', 'show', '3f88ec0:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')
BUILD3 = subprocess.check_output(['git', 'show', '803dfce:cet/UltrawideUIOverhaul/init.lua']).decode('utf-8')

# Actual relevant descriptor fields from the failed build2 session. The class
# exists, but its global scripted static functions are absent from DumpType.
LIVE_DESCRIPTOR = '{\n\tname: MisterChedda.ReadableShards.ReadableShardRenderer,\n\tfunctions: {\n\t\tToString() => (String),\n\t},\n\tstaticFunctions: {\n\t\tDetectScriptableCycles(),\n\t},\n\tproperties: {\n\t}\n}'


def static_lookup(lua, present=True):
    lua.globals().staticPresent=present
    lua.execute('''
        function GetSingleton(class)
            assert(class=='MisterChedda.ReadableShards.ReadableShardRenderer')
            staticLookups=(staticLookups or 0)+1
            if not staticPresent then return {} end
            return {['ApplyCodex;inkWidgetReadableShardsSettingsGameInstanceBool']=function()
                error('presence probe must not execute the renderer')
            end}
        end
    ''')


def setup(source=SOURCE, width=3440, height=1440, spread=100):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        events={}; writes={}; messages={}; overrides={}; cloneCount=0
        function registerForEvent(n,f) events[n]=f end
        function print(s) messages[#messages+1]=s end
        function Override(class,method,fn) overrides[class..'.'..method]=fn end
        CName={new=function(n) return n end}
        textWrappingPolicy={Default=0}
        function UWMapSetBlackBarsSuppressed() end
        function GetMod() return nil end
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
        function node(id,name,w,h)
            local n={name=name,size={X=w or 0,Y=h or 0},children={}}
            function n:GetName() return {value=self.name} end
            function n:GetWidget(i) return self.children[i] end
            function n:GetSize() return self.size end
            function n:SetSize(x,y) self.size={X=x,Y=y};writes[#writes+1]={id,'size',x,y} end
            function n:SetWrapping(on,width,policy) self.wrap=width;writes[#writes+1]={id,'wrap',width} end
            function n:SetWrappingAtPosition(width) self.wrap=width end
            function n:FlagForVisualInvalidation() end
            nodes[id]=n;return n
        end
        window=node('window','Base Window',3440,1440)
        outer=node('outer','Root',1920,1080)
        root=node('root','Root',3840,2160)
        list=node('list','list_wrapper',1400,1600)
        entry=node('entry','entryView',2000,1600)
        content=node('content','contentArea',100,100)
        line=node('line','line2',1920,2)
        scroll=node('scroll','EntryScrollArea',1825,1600)
        container=node('container','container')
        title=node('title','title',50,100)
        body=node('text','text',1600,1600)
        crackHint=node('crack','crackHintContainer',100,100)
        shardImage=node('image','shardImage',32,32)
        window.children[0]=outer;outer.children[0]=root
        root.children[0]=list;root.children[1]=entry
        entry.children[0]=content;content.children[1]=line;content.children[4]=scroll
        scroll.children[0]=container;container.children[0]=title;container.children[1]=crackHint
        container.children[2]=body;container.children[3]=shardImage
        Game={GetInkSystem=function() return {GetLayer=function(_,n)
            if n~='inkMenuLayer' then error('unrelated layer') end
            return {GetVirtualWindow=function() return window end}
        end} end}
        function GetDisplayResolution() return screenWidth,screenHeight end
        function NewObject(class)
            assert(class=='MisterChedda.ReadableShards.ReadableShardsSettings')
            cloneCount=cloneCount+1;return {}
        end
        settings={enabled=true,fontSize=52,lineHeight=1,wrapWidth=1600,
            paragraphSpacing=18,backgroundOpacity=.75,containerWidthPercent=100,
            containerHeightPercent=120,styleConversations=true,tintDialogueText=false,
            alignSpeakerNames=true,speakerAlignment=0,conversationSpacing=12}
        function callOriginal(...)
            assert(select('#',...)==3,'CET wrapped renderer expects 3 arguments; GameInstance is injected')
            local menuRoot,s,encrypted=...
            called=(called or 0)+1;capturedSettings=s
            assert(menuRoot:GetName().value=='entryView' and type(encrypted)=='boolean')
        end
        function alias(widget)
            return setmetatable({}, {__index=function(_,key)
                local value=widget[key]
                if type(value)=='function' then
                    return function(_,...) return value(widget,...) end
                end
                return value
            end})
        end
    ''')
    lua.globals().screenWidth, lua.globals().screenHeight = width, height
    lua.execute(source)
    apply = lua.globals().find(lua.globals().events.onInit, 'tryApplyShardsLayoutDirect')
    assert apply is not None
    lua.globals().find(apply, 'UI_SPREAD_PERCENT', spread, True)
    return lua, apply


def dimensions(lua):
    return {name: (node.size.X, node.size.Y) for name, node in lua.globals().nodes.items()}


for width, height in [(3440,1440),(5120,1440),(2880,1440)]:
    for spread in [0,50,100]:
        old, old_apply = setup(BASELINE,width,height,spread)
        new, new_apply = setup(SOURCE,width,height,spread)
        assert old_apply('baseline') and new_apply('candidate')
        assert dimensions(old)==dimensions(new)
print('PASS vanilla Shards geometry unchanged across 9 ratio/spread cases')

for width,height,spread,configured,expected in [
    (3440,1440,100,1600,2900), (3440,1440,95,1600,2834),
    (3440,1440,50,1600,2240), (5120,1440,100,1600,5420),
    (2880,1440,100,1600,2060), (3440,1440,100,1200,2175),
]:
    lua, _ = setup(SOURCE,width,height,spread)
    lua.globals().settings.wrapWidth=configured
    before=dict(lua.globals().settings.items())
    adapter=lua.globals().UWUI_readableShards
    adapter.render(lua.globals().entry,lua.globals().settings,'game',False,lua.globals().callOriginal)
    copy=lua.globals().capturedSettings
    assert copy.wrapWidth==expected,(expected,copy.wrapWidth)
    assert dict(lua.globals().settings.items())==before
    assert {k:v for k,v in copy.items() if k!='wrapWidth'}=={k:v for k,v in before.items() if k!='wrapWidth'}
    assert lua.globals().called==1 and lua.globals().cloneCount==1
    # A conversation's asynchronous controller keeps the copied settings after
    # this call returns. Later changes to global settings cannot shrink it.
    lua.globals().settings.wrapWidth=1000
    assert copy.wrapWidth==expected
    lua.globals().settings.wrapWidth=configured
    adapter.render(lua.globals().entry,lua.globals().settings,'game',False,lua.globals().callOriginal)
    assert lua.globals().capturedSettings.wrapWidth==expected
print('PASS per-render copy supplies paragraphs and asynchronous conversations; user styling/settings preserved; repeated selections stable')

for mode in ['16:9','spread0','disabled','encrypted','unrelated']:
    lua,_=setup(width=1920 if mode=='16:9' else 3440,height=1080 if mode=='16:9' else 1440,spread=0 if mode=='spread0' else 100)
    if mode=='disabled':lua.globals().settings.enabled=False
    if mode=='unrelated':lua.globals().content.children[4]=None
    lua.globals().UWUI_readableShards.render(lua.globals().entry,lua.globals().settings,'game',mode=='encrypted',lua.globals().callOriginal)
    assert lua.globals().cloneCount==0 and lua.globals().called==1 and len(lua.globals().writes)==0
    lua.execute('assert(capturedSettings==settings)')
print('PASS 16:9, UI Spread 0, disabled/encrypted entries and unrelated menus pass through without mutation')

lua,_=setup()
lua.execute('function NewObject() return nil end')
for _ in range(2):
    lua.globals().UWUI_readableShards.render(lua.globals().entry,lua.globals().settings,'game',False,lua.globals().callOriginal)
assert lua.globals().called==2 and len(lua.globals().messages)==1 and len(lua.globals().writes)==0
lua.execute('assert(capturedSettings==settings)')
print('PASS allocation failure forwards original once and logs a throttled error')

old,_=setup(BUILD3)
old_alias=old.globals().alias(old.globals().entry)
copy,reason=old.globals().UWUI_readableShards.prepare(old_alias,old.globals().settings,False)
assert copy is None and reason=='renderer root does not match active Shards tree'
try:
    old.globals().UWUI_readableShards.render(old.globals().entry,old.globals().settings,'game',False,old.globals().callOriginal)
except Exception as error:
    assert 'expects 3 arguments' in str(error)
else:
    raise AssertionError('build3 must fail the real CET wrapped-call argument contract')
lua,_=setup()
wrapped_entry=lua.globals().alias(lua.globals().entry)
lua.globals().UWUI_readableShards.render(wrapped_entry,lua.globals().settings,'game',False,lua.globals().callOriginal)
assert lua.globals().called==1 and lua.globals().capturedSettings.wrapWidth==2900
assert lua.globals().settings.wrapWidth==1600
print('PASS reproduced build3 wrapper-identity rejection and excess GameInstance argument; build4 supports aliased widget wrappers and original rendering')

for descriptor,present,expected in [
    ('{name: Unknown}',True,False),
    (LIVE_DESCRIPTOR,False,False),
    (LIVE_DESCRIPTOR,True,True),
]:
    lua,_=setup()
    lua.globals().descriptor=descriptor
    static_lookup(lua,present)
    lua.execute('function DumpType(class,detail) return descriptor end')
    lua.globals().UWUI_readableShards.register()
    lua.globals().UWUI_readableShards.register()
    assert len(list(lua.globals().overrides.items()))==int(expected)
    assert lua.globals().UWUI_readableShards.registered==expected
print('PASS optional class and exact static-callable guards, including a class descriptor without ApplyCodex')

for prior in [BUILD1,BUILD2]:
    old,_=setup(prior)
    old.globals().descriptor=LIVE_DESCRIPTOR
    static_lookup(old)
    old.execute('function DumpType() return descriptor end')
    old.globals().UWUI_readableShards.register()
    assert not old.globals().UWUI_readableShards.registered
lua,apply=setup()
lua.globals().descriptor=LIVE_DESCRIPTOR
static_lookup(lua)
lua.execute('''
    debugLines={}
    function captureDebug(line) debugLines[#debugLines+1]=line end
    function DumpType() return descriptor end
''')
lua.globals().find(apply,'ACTIVATE_DEBUG_LOGS',True,True)
lua.globals().find(apply,'writeDebugLog',lua.globals().captureDebug,True)
lua.globals().UWUI_readableShards.register()
method='MisterChedda.ReadableShards.ReadableShardRenderer.ApplyCodex;inkWidgetReadableShardsSettingsGameInstanceBool'
hook=lua.globals().overrides[method]
assert hook is not None
hook(lua.globals().entry,lua.globals().settings,'game',False,lua.globals().callOriginal)
debug='\n'.join(lua.globals().debugLines.values())
assert 'READABLE SHARDS adapter registered: ApplyCodex;inkWidgetReadableShardsSettingsGameInstanceBool' in debug
assert 'READABLE SHARDS render available=2900.00 configured=1600 effective=2900' in debug
assert 'READABLE SHARDS original renderer completed; settings=private UW copy' in debug
assert lua.globals().called==1 and lua.globals().capturedSettings.wrapWidth==2900
print('PASS actual build2 descriptor reproduces prior failures; exact extension hook logs width and successful original-renderer completion')
