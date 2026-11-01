-- Phase 27: exercise custom mod node/item callbacks without fake fallback.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Physics=require('core.physics')
local rt=Runtime.new()
local api=rt.api
local function p(x,y,z)return {x=x,y=y,z=z} end
local user={name='Alice'}
function user:get_player_name()return self.name end
local events,global_dig,global_place={},{},{}
api.register_craftitem('test:gem',{})
api.register_node('test:ore',{drop='test:gem',
 on_dig=function(pos,node,digger)
  assert(digger==user and node.name=='test:ore')
  events[#events+1]='custom_on_dig'
  return api.node_dig(pos,node,digger)
 end,
 after_dig_node=function(pos,old,metadata,digger)
  assert(digger==user and metadata.fields.id=='ore-1')
  events[#events+1]='after_dig'
 end
})
api.register_node('test:reject',{on_dig=function(pos,node,digger)
 events[#events+1]='custom_reject'
 return false
end,drop='test:gem'})
api.register_node('test:handled',{on_dig=function()
 events[#events+1]='custom_handled'
 -- nil signifies handled in the Luanti on_dig return contract.
 return nil
end,drop='test:gem'})
api.register_node('test:manual',{on_dig=function(pos)
 events[#events+1]='custom_manual'
 api.remove_node(pos)
 return true
end,drop='test:gem'})
api.register_node('test:placed',{
 after_place_node=function(pos,placer,stack,pointed)
  assert(placer==user and pointed.under.y==pos.y-1)
  events[#events+1]='after_place'
 end,
})
api.register_node('test:keep',{after_place_node=function()
 events[#events+1]='no_consume'
 return true
end})
api.register_node('test:custom_place',{on_place=function(stack,placer,pointed)
 assert(placer==user and pointed.type=='node')
 assert(pointed.under.x==pointed.above.x and
  pointed.under.y==pointed.above.y-1)
 events[#events+1]='custom_place'
 return api.item_place_node(stack,placer,pointed,3)
end})
api.register_craftitem('test:wand',{on_place=function(stack,placer,pointed)
 assert(placer==user and stack:get_name()=='test:wand')
 events[#events+1]='wand'
 api.set_node(pointed.above,{name='test:placed'})
 stack:take_item(1)
 return stack
end})
api.register_craftitem('test:noop',{on_place=function(stack)
 events[#events+1]='noop'
 stack:take_item(1)
 return nil  -- nil means keep player's original stack.
end})
api.register_craftitem('test:mutator',{on_place=function(stack,placer)
 events[#events+1]='mutator'
 placer:set_wielded_item('test:gem 7')
 stack:take_item(1)
 return stack
end})
api.register_node('test:panel',{on_rightclick=function(pos,node,clicker,stack,pt)
 assert(node.name=='test:panel' and clicker==user)
 assert(pt.under.y==pos.y and pt.above.y==pos.y+1)
 events[#events+1]='rightclick'
 stack:take_item(1)
 return stack
end})
api.register_on_dignode(function(pos,node,digger)
 global_dig[#global_dig+1]={pos=pos,node=node,digger=digger}
end)
api.register_on_placenode(function(pos,node,placer)
 global_place[#global_place+1]={pos=pos,node=node,placer=placer}
end)
api.register_tool('test:pick',{tool_capabilities={groupcaps={
 cracky={times={[1]=.2},maxlevel=1,uses=3}}}})
rt:connectPlayer(user,Physics.new(api,p(0,2,0)))
local inv=user:get_inventory()
inv:set_stack('main',1,'test:pick')
local site=p(1,3,2)
api.set_node(site,{name='test:ore'})
api.get_meta(site):set_string('id','ore-1')
local ok,out=rt:digNodeAsPlayer(user,site)
assert(ok and out=='custom_handled')
assert(api.get_node(site).name=='air')
assert(#events==2 and events[1]=='custom_on_dig' and
 events[2]=='after_dig')
assert(#global_dig==1 and global_dig[1].digger==user,
 'core.node_dig default must not call callbacks twice')
assert(inv:contains_item('main','test:gem'))
api.set_node(site,{name='test:reject'})
local count=inv:get_list('main')
ok,out=rt:digNodeAsPlayer(user,site)
assert(not ok and out=='custom_dig_rejected')
assert(api.get_node(site).name=='test:reject')
assert(#global_dig==1)
api.set_node(site,{name='test:handled'})
ok,out=rt:digNodeAsPlayer(user,site)
assert(ok and out=='custom_handled')
assert(api.get_node(site).name=='test:handled',
 'nil on_dig return must not cause an automatic dig')
assert(#global_dig==1)
api.set_node(site,{name='test:manual'})
ok,out=rt:digNodeAsPlayer(user,site)
assert(ok and out=='custom_handled')
assert(api.get_node(site).name=='air')
assert(#global_dig==1,'custom dig owns callbacks and drops')
-- True node custom on_place uses same ItemStack as builtin placement
-- but through the optional core.item_place_node helper.
local dest=p(5,2,4)
local pt={type='node',under=p(5,1,4),above=dest}
user:set_wielded_item('test:custom_place 3')
local before=#global_place
ok,out=rt:placeNodeAsPlayer(user,dest,pt)
assert(ok and out=='custom_handled')
assert(api.get_node(dest).name=='test:custom_place' and
 api.get_node(dest).param2==3)
assert(user:get_wielded_item():get_count()==2)
assert(#global_place==before+1 and global_place[#global_place].placer==user)
assert(events[#events]=='custom_place')
-- Helper does not promise automatic consumption when after_place requests
-- to keep the stack. It also accepts an explicit pointed target.
local keep=p(6,2,4)
user:set_wielded_item('test:keep 4')
ok,out=rt:placeNodeAsPlayer(user,keep,
 {type='node',under=p(6,1,4),above=keep})
assert(ok and user:get_wielded_item():get_count()==4)
assert(events[#events]=='no_consume')
-- Craftitem-defined on_place can mutate the world and return leftovers.
local handmade=p(7,2,4)
user:set_wielded_item('test:wand 2')
ok,out=rt:placeNodeAsPlayer(user,handmade,
 {type='node',under=p(7,1,4),above=handmade})
assert(ok and out=='custom_handled')
assert(user:get_wielded_item():get_count()==1)
assert(api.get_node(handmade).name=='test:placed')
assert(#global_place==before+2,
 'custom craftitem placement must not fabricate on_placenode events')
-- Returning nil must not consume player's original stack.
user:set_wielded_item('test:noop 3')
assert(rt:placeNodeAsPlayer(user,p(8,2,4)))
assert(user:get_wielded_item():get_count()==3)
user:set_wielded_item('test:mutator 2')
assert(rt:placeNodeAsPlayer(user,p(9,2,4)))
assert(user:get_wielded_item():get_name()=='test:gem' and
 user:get_wielded_item():get_count()==7,
 'mod-owned inventory mutations must not be overwritten')
-- Rightclick takes priority over held item on_place.
api.set_node(p(10,1,4),{name='test:panel'})
user:set_wielded_item('test:wand 3')
ok,out=rt:placeNodeAsPlayer(user,p(10,2,4),
 {type='node',under=p(10,1,4),above=p(10,2,4)})
assert(ok and out=='rightclick_handled')
assert(user:get_wielded_item():get_count()==2)
assert(events[#events]=='rightclick')
assert(api.get_node(p(10,2,4)).name=='air')
-- Protection checked before custom callback on both destination and under.
local was=#events
api.is_protected=function(pos)
 return pos.x==11
end
user:set_wielded_item('test:wand 2')
ok,out=rt:placeNodeAsPlayer(user,p(11,2,4))
assert(not ok and out=='protected' and #events==was)
api.set_node(p(11,1,4),{name='test:panel'})
ok,out=rt:placeNodeAsPlayer(user,p(12,2,4),
 {type='node',under=p(11,1,4),above=p(12,2,4)})
assert(not ok and out=='protected' and #events==was)
api.is_protected=function()return false end
assert(not pcall(rt.placeNodeAsPlayer,rt,user,p(14,2,4),
 {type='node',under=p(14,1,4),above=p(15,2,4)}))
-- Timed path now also dispatches custom on_dig AFTER elapsed dig time.
api.register_node('test:timed',{groups={cracky=1},on_dig=function(pos,node,digger)
 events[#events+1]='timed'
 return api.node_dig(pos,node,digger)
end})
user:set_wielded_item('test:pick')
local delayed=p(15,2,4)
api.set_node(delayed,{name='test:timed'})
local started,duration=rt:beginDigNodeAsPlayer(user,delayed)
assert(started and duration==.2)
local ready,why=rt:advanceDigNodeAsPlayer(user,.1)
assert(not ready and why=='in_progress')
assert(api.get_node(delayed).name=='test:timed')
assert(rt:advanceDigNodeAsPlayer(user,.1))
assert(api.get_node(delayed).name=='air')
assert(events[#events]=='timed')
rt:disconnectPlayer('Alice')
print('LUA ENGINE CUSTOM NODE CALLBACKS PASS')
