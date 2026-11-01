-- Phase 26: timed digging, groupcap mining, tool wear, cancellation.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local Digging=require('core.digging')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z)return {x=x,y=y,z=z} end
local after_events={}
api.register_node('test:stone',{
 groups={cracky=2,level=1},drop='test:cobble',
 after_dig_node=function(pos,old,meta,player)
  assert(old.name=='test:stone' and player:get_player_name()=='Alice')
  assert(meta.fields.owner=='Alice')
  assert(api.get_node(pos).name=='air')
  assert(api.get_meta(pos):get_string('owner')=='')
  after_events[#after_events+1]='after_dig_node'
 end
})
api.register_node('test:cobble',{groups={}})
api.register_node('test:instant',{groups={dig_immediate=3}})
api.register_node('test:hard',{groups={cracky=1,level=2}})
api.register_node('test:custom',{on_dig=function()error('never call') end,
 groups={cracky=2,level=1}})
api.register_tool('test:pick',{stack_max=1,
 tool_capabilities={groupcaps={cracky={
 maxlevel=1,uses=2,times={[2]=.25}}}}})
local player={name='Alice'}
function player:get_player_name()return self.name end
rt:connectPlayer(player,Physics.new(api,p(0,2,0)))
local inv=player:get_inventory()
inv:set_stack('main',1,'test:pick')
local tool=player:get_wielded_item()
local params=Digging.params(api.registered_nodes['test:stone'],tool,rt.registry)
assert(params.diggable and params.time==.25 and
 params.wear==32768 and params.group=='cracky')
assert(not Digging.params(api.registered_nodes['test:hard'],
 tool,rt.registry).diggable)
assert(Digging.params(api.registered_nodes['test:instant'],
 api.ItemStack(''),rt.registry).time==0)
assert(not pcall(Digging.params,{},nil,rt.registry))
local stone=p(1,2,3)
api.set_node(stone,{name='test:stone'})
api.get_meta(stone):set_string('owner','Alice')
local ok,duration=rt:beginDigNodeAsPlayer(player,stone)
assert(ok and duration==.25 and rt:getDigProgress(player)==0)
local finished,reason,progress=rt:advanceDigNodeAsPlayer(player,.1)
assert(not finished and reason=='in_progress' and
 progress>.39 and progress<.41)
assert(api.get_node(stone).name=='test:stone')
assert(player:get_wielded_item():get_wear()==0)
finished,reason,progress=rt:advanceDigNodeAsPlayer(player,.15)
assert(finished and #reason==1 and reason[1]=='test:cobble' and progress==1)
assert(api.get_node(stone).name=='air' and inv:contains_item('main','test:cobble'))
assert(#after_events==1 and after_events[1]=='after_dig_node')
assert(player:get_wielded_item():get_wear()==32768)
assert(rt:getDigProgress(player)==nil)
local empty,why=rt:advanceDigNodeAsPlayer(player,.1)
assert(not empty and why=='not_digging')
-- Full second use destroys pick only after successful mining.
local second=p(2,2,3)
api.set_node(second,{name='test:stone'})
api.get_meta(second):set_string('owner','Alice')
assert(rt:beginDigNodeAsPlayer(player,second))
assert(rt:advanceDigNodeAsPlayer(player,.25))
assert(player:get_wielded_item():is_empty())
assert(#after_events==2)
-- Tool identity, including wear metadata, is immutable for a mining session.
local third=p(3,2,3)
api.set_node(third,{name='test:stone'})
player:set_wielded_item('test:pick')
assert(rt:beginDigNodeAsPlayer(player,third))
player:set_wielded_item('test:pick 1 10')
local changed,why=rt:advanceDigNodeAsPlayer(player,.5)
assert(not changed and why=='target_changed')
assert(api.get_node(third).name=='test:stone')
assert(player:get_wielded_item():get_wear()==10)
-- Node param2 replacement cancels, including same node name.
player:set_wielded_item('test:pick')
assert(rt:beginDigNodeAsPlayer(player,third))
api.set_node(third,{name='test:stone',param2=1})
changed,why=rt:advanceDigNodeAsPlayer(player,.25)
assert(not changed and why=='target_changed')
assert(player:get_wielded_item():get_wear()==0)
api.set_node(third,{name='test:stone'})
api.get_meta(third):set_string('owner','Alice')
-- Manual cancellation is idempotent and never wears the tool.
assert(rt:beginDigNodeAsPlayer(player,third))
assert(rt:cancelDigNodeAsPlayer(player))
assert(not rt:cancelDigNodeAsPlayer(player))
assert(player:get_wielded_item():get_wear()==0)
assert(api.get_node(third).name=='test:stone')
-- Protection may change after mining started; cancel without rewards.
assert(rt:beginDigNodeAsPlayer(player,third))
api.is_protected=function() return true end
changed,why=rt:advanceDigNodeAsPlayer(player,.5)
assert(not changed and why=='protected')
assert(api.get_node(third).name=='test:stone')
api.is_protected=function()return false end
-- Simple unsupported tool/callback requests never start.
player:set_wielded_item(nil)
local blocked,reason=rt:beginDigNodeAsPlayer(player,third)
assert(not blocked and reason=='unsupported_tool')
player:set_wielded_item('test:pick')
api.set_node(third,{name='test:custom'})
blocked,reason=rt:beginDigNodeAsPlayer(player,third)
assert(not blocked and reason=='custom_on_dig_unsupported')
api.set_node(third,{name='test:hard'})
blocked,reason=rt:beginDigNodeAsPlayer(player,third)
assert(not blocked and reason=='unsupported_tool')
-- Dig-immediate works even without a tool and without elapsed time.
player:set_wielded_item(nil)
api.set_node(third,{name='test:instant'})
ok,duration=rt:beginDigNodeAsPlayer(player,third)
assert(ok and duration==0 and rt:getDigProgress(player)==1)
assert(rt:advanceDigNodeAsPlayer(player,0))
assert(api.get_node(third).name=='air')
assert(not pcall(rt.advanceDigNodeAsPlayer,rt,player,-.1))
assert(not pcall(rt.advanceDigNodeAsPlayer,rt,player,0/0))
-- Disconnect invalidates in-flight mining state.
player:set_wielded_item('test:pick')
api.set_node(third,{name='test:stone'})
assert(rt:beginDigNodeAsPlayer(player,third))
assert(rt:disconnectPlayer('Alice'))
assert(rt.playerDigSessions.Alice==nil)
assert(not pcall(rt.advanceDigNodeAsPlayer,rt,player,.3))
assert(api.get_node(third).name=='test:stone')
print('LUA ENGINE TIMED DIGGING AND WEAR PASS')
