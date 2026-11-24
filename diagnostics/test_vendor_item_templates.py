"""Replay stale Vendor templates and asynchronous item changes without a game."""
from pathlib import Path
from lupa.lua54 import LuaRuntime

SOURCE = Path('cet/UltrawideUIOverhaul/init.lua').read_text(encoding='utf-8')


def setup():
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        events={}; messages={}; removals=0; spawns=0; sizeWrites=0
        function registerForEvent(n,fn) events[n]=fn end
        function print(s) messages[#messages+1]=s end
        function GetDisplayResolution() return screenWidth or 3440,screenHeight or 1440 end
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
        function widget(name,w,h)
            local n={name=name,size={X=w,Y=h},children={}}
            function n:GetName() return {value=self.name} end
            function n:GetWidget(i) return self.children[i] end
            function n:GetSize() return self.size end
            function n:SetSize() sizeWrites=sizeWrites+1 end
            function n:RemoveChild(child)
                assert(self.children[0]==child,'retire only the current child')
                self.children[0]=nil;removals=removals+1
            end
            return n
        end
        function item(weapon)
            return {weapon=weapon,IsWeapon=function(self) return self.weapon end}
        end
        function view(slot)
            local n=widget('container',slot=='weaponDisplay' and 650 or 216,194)
            n.children[2]=widget(slot=='weaponDisplay' and 'weaponWrapper' or 'itemWrapper',0,0)
            -- Both templates actually report InventoryWeaponDisplayController
            -- in the observed dump. The class alone cannot distinguish them.
            return {GetRootWidget=function() return n end,
                GetClassName=function() return {value='InventoryWeaponDisplayController'} end}
        end
        function controller()
            local c={root=widget('root',224,202),m_isSpawnInProgress=false,
                class='VendorItemVirtualController',requests=0}
            function c:GetClassName() return {value=self.class} end
            function c:GetRootWidget() return self.root end
            function c:GetData() return self.current end
            -- Model the native rule established from VendorItemVirtualController:
            -- choose the template only if no view is present. While loading, a
            -- data change updates the item but does not change the pending asset.
            function c:OnDataChanged(value)
                self.current=value;self.m_newData=value
                self.root.size.X=value.Item:IsWeapon() and 672 or 224
                if not self.m_isSpawnInProgress and self.m_itemViewController==nil then
                    self.requested=value.Item:IsWeapon() and 'weaponDisplay' or 'itemDisplay'
                    self.m_isSpawnInProgress=true;self.requests=self.requests+1
                end
                UWUI_vendorItems.enqueue(self,'OnDataChanged')
            end
            function c:complete()
                assert(self.m_isSpawnInProgress)
                self.m_itemViewController=view(self.requested)
                self.root.children[0]=self.m_itemViewController:GetRootWidget()
                self.m_isSpawnInProgress=false;spawns=spawns+1
                UWUI_vendorItems.enqueue(self,'OnSpawned')
            end
            function c:bind(weapon) self:OnDataChanged({Item=item(weapon)}) end
            return c
        end
    ''')
    lua.execute(SOURCE)
    inspect=lua.globals().UWUI_vendorItems.inspect
    lua.globals().find(inspect,'vendorMenuActive',True,True)
    return lua


# The supplied dump shows a 672-wide reserved root containing a 216-wide
# itemWrapper template. A correct weapon root instead contains weaponWrapper
# and a 650-wide display child. Reproduce the pending-spawn race exactly.
lua=setup()
c=lua.globals().controller()
c.bind(c,False)
c.bind(c,True)
c.complete(c)
assert c.root.size.X==672 and c.root.children[0].size.X==216
assert len(lua.globals().UWUI_vendorItems.pending)==1
assert lua.globals().removals==0  # Enqueue never mutates during a native callback.
lua.globals().UWUI_vendorItems.process()
assert c.requested=='weaponDisplay' and c.m_isSpawnInProgress
assert c.root.size.X==672 and lua.globals().removals==1
c.complete(c)
assert c.root.children[0].size.X==650
assert len(lua.globals().UWUI_vendorItems.pending)==0
assert lua.globals().sizeWrites==0
print('PASS captured 672/216 mismatch: deferred native respawn restores the weapon template at 650 without resizing items or grid slots')

# Existing views are also reused for another kind of item, in either direction.
c.bind(c,False)
assert c.root.size.X==224 and c.root.children[0].size.X==650
lua.globals().UWUI_vendorItems.process()
c.complete(c)
assert c.root.children[0].size.X==216 and lua.globals().removals==2
c.bind(c,True)
lua.globals().UWUI_vendorItems.enqueue(c,'duplicate callback')
lua.globals().UWUI_vendorItems.process()
assert lua.globals().removals==3  # Duplicate entries cannot spawn twice.
c.complete(c)
for _ in range(8):
    c.bind(c,True)
    lua.globals().UWUI_vendorItems.process()
assert lua.globals().removals==3
print('PASS small/weapon template reuse, reverse changes, duplicate callbacks and stable same-type rebinds')

# Current data is authoritative if it changes between enqueue and processing,
# or while a corrective spawn itself is in flight.
lua=setup();c=lua.globals().controller()
c.bind(c,False);c.complete(c);c.bind(c,True);c.bind(c,False)
lua.globals().UWUI_vendorItems.process()
assert lua.globals().removals==0 and c.root.children[0].size.X==216
c.bind(c,True);lua.globals().UWUI_vendorItems.process();c.bind(c,False)
c.complete(c)
assert c.root.children[0].size.X==650 and c.root.size.X==224
lua.globals().UWUI_vendorItems.process();c.complete(c)
assert c.root.children[0].size.X==216 and c.root.size.X==224
print('PASS source changes before processing and during corrective async spawn settle on the newest item/template')

for mode in ['closed','stash','subclass','custom','expired','16:9']:
    lua=setup();c=lua.globals().controller()
    c.bind(c,False);c.complete(c);c.bind(c,True)
    if mode=='closed':lua.globals().find(lua.globals().UWUI_vendorItems.inspect,'vendorMenuActive',False,True)
    if mode=='stash':lua.globals().find(lua.globals().UWUI_vendorItems.inspect,'stashMenuActive',True,True)
    if mode=='subclass':c['class']='InventoryGridItemController'
    if mode=='custom':c.root.children[0].children[2].name='customWrapper'
    if mode=='expired':lua.execute('function expired() error("expired weak handle") end');c.GetClassName=lua.globals().expired
    if mode=='16:9':lua.globals().screenWidth,lua.globals().screenHeight=1920,1080
    lua.globals().UWUI_vendorItems.process()
    assert lua.globals().removals==0 and len(lua.globals().UWUI_vendorItems.pending)==0,mode
print('PASS menu closure, Stash, derived controllers, custom templates, expired weak handles and unsupported ratio are left untouched')

lua=setup();controllers=[]
for _ in range(40):
    c=lua.globals().controller();c.bind(c,False);c.complete(c);c.bind(c,True)
    controllers.append(c)
lua.globals().UWUI_vendorItems.process()
assert lua.globals().removals==32 and len(lua.globals().UWUI_vendorItems.pending)==8
lua.globals().UWUI_vendorItems.process()
assert lua.globals().removals==40 and len(lua.globals().UWUI_vendorItems.pending)==0
for c in controllers:c.complete(c)
lua.globals().UWUI_vendorItems.process()
assert lua.globals().removals==40
print('PASS event queue processes at most 32 corrections per update and stops after the pending events')

lua=setup();c=lua.globals().controller()
c.bind(c,False);c.complete(c);c.bind(c,True)
old=c.m_itemViewController
lua.execute('function cannotRemove() error("removal rejected") end')
c.root.RemoveChild=lua.globals().cannotRemove
lua.globals().UWUI_vendorItems.process()
assert c.m_itemViewController is not None and c.root.children[0].size.X==216
assert c.requests==1 and len(lua.globals().messages)==1
print('PASS failed child removal restores the existing view and reports the error without issuing another spawn')
