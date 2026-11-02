-- Luanti 5.18 LoadingBlockModifiers on mapblock activation, Lua 5.4/LuaJIT.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local rt=Runtime.new()
local api=rt.api
assert(api.features.bulk_lbms==true)
api.register_node('audit:legacy',{groups={upgrade=1}})
api.register_node('audit:new',{groups={upgrade=2}})
api.register_node('audit:other',{})
api.set_node({x=-16,y=1,z=0},{name='audit:legacy'})
api.set_node({x=-1,y=1,z=0},{name='audit:legacy'})
api.set_node({x=0,y=1,z=0},{name='audit:legacy'})
local once,repeat_count,bulk_count=0,0,0
api.register_lbm({name='audit:migrate',nodenames={'audit:legacy'},
 action=function(pos,node,elapsed)
  assert(elapsed==8 and node.name=='audit:legacy')
  once=once+1
  api.swap_node(pos,{name='audit:new'})
 end})
api.register_lbm({name='audit:every',nodenames={'group:upgrade'},
 run_at_every_load=true,action=function(pos,node,elapsed)
  assert(elapsed==8 and node.name=='audit:new')
  repeat_count=repeat_count+1
 end})
api.register_lbm({name='audit:bulk',nodenames={'audit:new'},
 run_at_every_load=true,bulk_action=function(positions,elapsed)
  assert(elapsed==8 and #positions==2)
  bulk_count=bulk_count+1
 end})
assert(api.registered_lbms==rt.registry.lbms)
assert(#rt.registry.lbms==3)
-- x=-16 and x=-1 share block -1, but x=0 is in block 0.
assert(rt:activateMapBlock({x=-15,y=1,z=0},8)==5)
assert(once==2 and repeat_count==2 and bulk_count==1)
assert(api.get_node({x=0,y=1,z=0}).name=='audit:legacy')
assert(rt:activateMapBlock({x=-1,y=1,z=0},8)==3)
assert(once==2 and repeat_count==4 and bulk_count==2)
-- Activation persists across saves. Reloading does NOT replay one-shot
-- migrations, while run_at_every_load is fired on each new activation.
local saved=Storage.encode(rt.map)
assert(saved:find('A %-1 0 0 audit%%3Amigrate'))
local restored=Storage.decode(saved)
assert(restored.lbm_applied['-1,0,0']['audit:migrate'])
local second=Runtime.new()
second.api.register_node('audit:legacy',{groups={upgrade=1}})
second.api.register_node('audit:new',{groups={upgrade=2}})
second:replaceMap(restored)
local replayed,always=0,0
second.api.register_lbm({name='audit:migrate',nodenames={'audit:legacy'},
 action=function() replayed=replayed+1 end})
second.api.register_lbm({name='audit:every',nodenames={'audit:new'},
 run_at_every_load=true,
 action=function(_,node,dtime)
  assert(node.name=='audit:new' and dtime==12)
  always=always+1
 end})
assert(second:activateMapBlock({x=-16,y=1,z=0},12)==2)
assert(replayed==0 and always==2)
-- A previously unseen LBM name must still process historical blocks.
local introduced=0
second.api.register_lbm({name='audit:introduced_later',
 nodenames={'audit:new'},action=function() introduced=introduced+1 end})
assert(second:activateMapBlock({x=-1,y=1,z=0},12)==4)
assert(introduced==2 and replayed==0)
-- Generated blocks are newer than the currently registered one-shot LBMs.
second.api.set_node({x=16,y=0,z=0},{name='audit:legacy'})
second:markGeneratedMapBlocks({x=16,y=0,z=0},{x=31,y=15,z=15})
assert(second:activateMapBlock({x=16,y=0,z=0},12)==0)
assert(replayed==0)
local late=0
second.api.register_lbm({name='audit:added_after_generation',
 nodenames={'audit:legacy'},action=function() late=late+1 end})
assert(second:activateMapBlock({x=16,y=0,z=0},0)==1)
assert(late==1)
assert(second:activateMapBlock({x=16,y=0,z=0},0)==0)
-- Snapshot is acquired before callbacks. A newly inserted node is NOT
-- processed by the same LBM during the current activation.
local third=Runtime.new()
third.api.register_node('audit:spawn',{})
third.api.set_node({x=2,y=2,z=2},{name='audit:spawn'})
local calls=0
third.api.register_lbm({name='audit:snapshot',nodenames={'audit:spawn'},
 run_at_every_load=true,action=function(pos)
  calls=calls+1
  if pos.x==2 then
   third.api.set_node({x=3,y=2,z=2},{name='audit:spawn'})
  end
 end})
assert(third:activateMapBlock({x=2,y=2,z=2})==1)
assert(calls==1)
assert(third:activateMapBlock({x=2,y=2,z=2})==2)
assert(calls==3)
-- Input and save validation cannot silently manufacture a modifier.
assert(not pcall(third.api.register_lbm,{name='audit:snapshot',
 nodenames={'audit:spawn'},action=function() end}))
assert(not pcall(third.api.register_lbm,{name='audit:bad',
 nodenames={'audit:spawn'},action=function() end,
 bulk_action=function() end}))
assert(not pcall(third.api.register_lbm,{name='audit:missing',
 nodenames={'audit:spawn'}}))
assert(not pcall(third.activateMapBlock,third,{x=1.5,y=0,z=0},0))
assert(not pcall(third.activateMapBlock,third,{x=0,y=0,z=0},-1))
assert(not pcall(Storage.decode,'LUAENGINE 1\nA 0 0 0 audit%3Ax\nA 0 0 0 audit%3Ax\nEND\n'))
assert(not pcall(Storage.decode,'LUAENGINE 1\nA 9999 0 0 audit%3Ax\nEND\n'))
print('LUA ENGINE LOADING BLOCK MODIFIERS PASS')
