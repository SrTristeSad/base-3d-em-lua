-- Phase 53: actual singleplayer inventory/wield/position persistence and
-- renderable hotbar controls. No filesystem, GPU, or native Luanti needed.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local Profile=require('core.playerstorage')
local Hud=require('core.demohud')
local Storage=require('core.storage')
local Geometry=require('core.collisiongeometry')
local function p(x,y,z)return {x=x,y=y,z=z} end
local function eq(a,b,why)
 assert(a==b,(why or 'mismatch')..' '..tostring(a)..' != '..tostring(b))
end
local function world()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_node('test:stone',{description='Granite',groups={cracky=1}})
 api.register_node('test:slab',{description='Half stone',drawtype='nodebox',
  node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
 api.register_tool('test:pick',{description='Iron pickaxe',stack_max=1})
 local player={name='singleplayer'}
 function player:get_player_name()return self.name end
 local controller=Physics.new(api,p(0,4,0),{profile='luanti'})
 rt:connectPlayer(player,controller)
 return rt,api,player,controller
end
local rt,api,player,controller=world()
local inv=player:get_inventory()
eq(inv:get_size('main'),32)
inv:set_stack('main',1,'test:stone 23')
inv:set_stack('main',2,'test:pick')
inv:set_stack('main',9,'test:slab 64')
local custom=api.ItemStack('test:stone 3')
custom:get_meta():set_string('origin','overworld')
custom:get_meta():set_string('utf','coração')
inv:set_stack('main',27,custom)
player:set_wield_index(9)
controller:set_pos(p(24.25,8.5,-41.75))
local saved=Profile.encode(player,controller,.75,-.22)
assert(saved:sub(1,#'LUAENGINE PLAYER 1')=='LUAENGINE PLAYER 1')
local state=Profile.decode(saved)
eq(state.wield,9)
eq(state.size,32)
eq(state.pos.x,24.25)
eq(state.items[27].fields.origin,'overworld')
eq(state.items[27].fields.utf,'coração')
eq(state.items[9].count,64)
assert(state.items[3]==false)
local mockfs={data={}}
function mockfs.read(name)return mockfs.data[name] end
function mockfs.write(name,data)mockfs.data[name]=data;return true end
assert(Profile.save(player,controller,.75,-.22,'test.player',mockfs))
eq(mockfs.data['test.player'],saved)
local loaded_rt,loaded_api,loaded_player,loaded_controller=world()
local missing,why=Profile.load(loaded_player,loaded_controller,'missing',mockfs)
assert(missing==nil and why=='not found')
local restored=Profile.load(loaded_player,loaded_controller,'test.player',mockfs)
eq(restored.pos.x,24.25)
eq(restored.yaw,.75)
eq(restored.pitch,-.22)
eq(loaded_player:get_wield_index(),9)
eq(loaded_player:get_wielded_item():get_name(),'test:slab')
eq(loaded_player:get_wielded_item():get_count(),64)
eq(loaded_player:get_inventory():get_stack('main',27)
 :get_meta():get_string('origin'),'overworld')
eq(loaded_player:get_inventory():get_stack('main',27)
 :get_meta():get_string('utf'),'coração')
eq(loaded_player:get_inventory():get_stack('main',1):get_count(),23)
eq(loaded_controller:get_pos().z,-41.75)
eq(Profile.encode(loaded_player,loaded_controller,.75,-.22),saved,
 'player save must round-trip byte-for-byte')
-- Failed loads cannot overwrite the existing connected player session.
local before=Profile.encode(loaded_player,loaded_controller,.75,-.22)
for _,bad in ipairs({
 'this is executable Lua',
 'LUAENGINE PLAYER 1\nreturn os.execute("bad")',
 saved:sub(1,#saved-6),
 'LUAENGINE PLAYER 1\nreturn {pos={x=32000,y=0,z=0}}',
 'LUAENGINE PLAYER 1\nreturn {pos={x=0,y=0,z=0},yaw=0,pitch=0,wield=0,size=32,items={}}',
 'LUAENGINE PLAYER 1\nreturn {pos={x=0,y=0,z=0},yaw=0,pitch=0,wield=1,size=1,items={[1]={name="stone",count=2,wear=0,fields={[5]="bad"}}}}',
}) do
 mockfs.data.bad=bad
 local invalid,reason=Profile.load(loaded_player,loaded_controller,'bad',mockfs)
 assert(invalid==nil and type(reason)=='string' and #reason>0)
 eq(Profile.encode(loaded_player,loaded_controller,.75,-.22),before,
  'bad save must preserve every inventory slot and camera position')
end
local slots=Hud.slots(loaded_player,loaded_rt.registry.items)
eq(#slots,9)
eq(slots[1].name,'test:stone')
eq(slots[1].label,'Granite')
assert(slots[3].empty)
assert(slots[9].selected)
assert(not Hud.select(loaded_player,0))
assert(not Hud.select(loaded_player,10))
assert(Hud.select(loaded_player,1))
eq(loaded_player:get_wield_index(),1)
Hud.scroll(loaded_player,1)
eq(loaded_player:get_wield_index(),9)
Hud.scroll(loaded_player,-1)
eq(loaded_player:get_wield_index(),1)
Hud.scroll(loaded_player,-2)
eq(loaded_player:get_wield_index(),3)
assert(not Hud.scroll(loaded_player,0))
assert(not pcall(Hud.scroll,loaded_player,math.huge))
assert(not pcall(Hud.select,loaded_player,2.5))
-- GPU commands are tested against a mock LÖVR Pass, not just HUD state.
local oldlovr=_G.lovr
_G.lovr={math={newMat4=function() return {identity=true} end}}
local calls={}
local pass={}
for _,name in ipairs({'push','pop','setViewPose','setProjection',
 'setDepthTest','setMaterial','setColor','plane','text'}) do
 pass[name]=function(_,...)calls[#calls+1]={name=name,args={...}} end
end
Hud.draw(pass,loaded_player,loaded_rt.registry.items,1280,720)
_G.lovr=oldlovr
assert(calls[1].name=='push' and calls[1].args[1]=='state')
eq(calls[#calls].name,'pop')
local tiles,labels=0,{}
for _,c in ipairs(calls) do
 if c.name=='plane' then tiles=tiles+1 end
 if c.name=='text' then labels[#labels+1]=c.args[1] end
end
eq(tiles,9,'nine rendered inventory cells')
assert(#labels>=12,'HUD must show slot keys, item labels and crosshair')
assert(not pcall(Hud.draw,pass,loaded_player,{},0,720))
-- A decoded map must retain callbacks so placing a block after reload
-- immediately evicts only the changed collision geometry.
api.set_node(p(0,0,0),{name='test:stone'})
api.set_node(p(20,0,0),{name='test:stone'})
Geometry.collect(rt,{-1,-1,-1,21,1,1},2,true)
local oldcache=Geometry.cache(rt)
local remote=oldcache.data['20,0,0']
assert(remote,'expected distant cached collision shape')
local decoded=Storage.decode(Storage.encode(rt.map))
rt:replaceMap(decoded)
assert(rt.map==decoded and decoded.registry==rt.registry.items)
Geometry.collect(rt,{-1,-1,-1,21,1,1},2,true)
local live=Geometry.cache(rt)
local retained=live.data['20,0,0']
assert(retained,'loaded map collision must be cached')
api.swap_node(p(0,0,0),{name='test:slab'})
assert(Geometry.cache(rt)==live and
 live.data['20,0,0']==retained and
 live.data['0,0,0']==nil,
 'loaded world must keep selective collision invalidation')
assert(Geometry.collect(rt,{-1,-1,-1,1,1,1},2,true)[1])
assert(Geometry.cache(rt).selective_updates>=1)
print('LUA ENGINE PHASE 53 PERSISTENT PLAYER HOTBAR PASS')
