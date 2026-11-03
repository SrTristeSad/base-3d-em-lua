-- Consolidated Lua 5.4/LuaJIT dynamic-liquid regression.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local Map=require('core.map')
local function eq(a,b,label)
 assert(a==b,(label or 'liquid')..': '..tostring(a)..' ~= '..tostring(b))
end
local function pos(x,y,z) return {x=x,y=y,z=z} end
local function runtime()
 local rt=Runtime.new({active_block_range=0})
 rt.api.register_node('fluid:stone',{walkable=true})
 rt.api.register_node('fluid:water',{liquidtype='source',
  liquid_alternative_source='fluid:water',
  liquid_alternative_flowing='fluid:water_flowing',liquid_range=3,
  liquid_renewable=true,walkable=false})
 rt.api.register_node('fluid:water_flowing',{liquidtype='flowing',
  liquid_alternative_source='fluid:water',
  liquid_alternative_flowing='fluid:water_flowing',walkable=false})
 rt.api.register_node('fluid:lava',{liquidtype='source',
  liquid_alternative_source='fluid:lava',
  liquid_alternative_flowing='fluid:lava_flowing',liquid_range=2,
  walkable=false})
 rt.api.register_node('fluid:lava_flowing',{liquidtype='flowing',
  liquid_alternative_source='fluid:lava',
  liquid_alternative_flowing='fluid:lava_flowing',walkable=false})
 return rt
end
local function ground(rt,r)
 for x=-r,r do for z=-r,r do
  rt.map:set_node(pos(x,0,z),{name='fluid:stone'})
 end end
end
-- Existing runtimes do not modify liquids unless the host opts in.
local idle=runtime()
idle.map:set_node(pos(0,2,0),{name='fluid:water'})
idle:step(4)
eq(idle.map:get_node(pos(0,1,0)).name,'air')
local rt=runtime()
ground(rt,5)
rt.map:set_node(pos(0,2,0),{name='fluid:water'})
local callbacks,events={},{}
rt.api.register_on_liquid_transformed(function(changed)
 callbacks[#callbacks+1]=changed
end)
rt.map:add_event_receiver(function(e) events[#events+1]=e end)
local simulation=rt:enableLiquidSimulation({interval=.5,budget=128})
eq(simulation.byname['fluid:water'].flowing,'fluid:water_flowing')
eq(simulation.byname['fluid:lava'].range,2)
assert(simulation:pending_count()>0)
rt:step(.2)
eq(rt.map:get_node(pos(0,1,0)).name,'air')
rt:step(.3)
eq(rt.map:get_node(pos(0,1,0)).name,'fluid:water_flowing')
eq(rt.map:get_node(pos(0,1,0)).param2,0)
eq(rt.map:get_node(pos(1,2,0)).name,'fluid:water_flowing')
eq(rt.map:get_node(pos(1,2,0)).param2,1)
eq(#callbacks,1)
eq(#events,1)
eq(events[1].type,Map.MEET_OTHER)
eq(events[1].low_priority,true)
eq(events[1].p,nil)
assert(#callbacks[1]>1)
callbacks[1][1].x=99
eq(rt.map:get_node(pos(0,1,0)).name,'fluid:water_flowing')
for i=1,4 do rt:step(.5) end
eq(rt.map:get_node(pos(3,2,0)).name,'fluid:water_flowing')
eq(rt.map:get_node(pos(4,2,0)).name,'air')
eq(rt.map:get_node(pos(0,2,0)).name,'fluid:water')
eq(rt.map:get_node(pos(0,3,0)).name,'air')
rt.api.get_meta(pos(1,0,0)):set_string('owner','solid')
eq(rt.map:get_node(pos(1,0,0)).name,'fluid:stone')
eq(rt.api.get_meta(pos(1,0,0)):get_string('owner'),'solid')
eq(rt.map:get_mapblock_modified_state('0,0,0'),4)
-- Flow state persists and is requeued when a decoded map is installed.
local image=Storage.decode(Storage.encode(rt.map))
eq(image:get_node(pos(1,2,0)).name,'fluid:water_flowing')
local reboot=runtime()
local restarted=reboot:enableLiquidSimulation({interval=.5,budget=96})
reboot:replaceMap(image)
assert(restarted:pending_count()>0)
reboot:step(.5)
assert(reboot:disableLiquidSimulation())
eq(reboot:disableLiquidSimulation(),false)
local snapshot=reboot.map:get_node(pos(0,1,0)).name
reboot:step(1.5)
eq(reboot.map:get_node(pos(0,1,0)).name,snapshot)
-- Unemerged blank blocks are CONTENT_IGNORE, not fillable air.
local border=runtime()
assert(border.map:create_blank_block('-1,0,0'))
border.map:set_node(pos(0,1,0),{name='fluid:water'})
border:enableLiquidSimulation({interval=.5,budget=128})
border:step(.5)
eq(border.map:get_node(pos(-1,1,0)).name,'ignore')
-- Source regeneration requires two adjacent sources and solid support.
local renew=runtime()
renew.map:set_node(pos(0,0,0),{name='fluid:stone'})
renew.map:set_node(pos(-1,1,0),{name='fluid:water'})
renew.map:set_node(pos(1,1,0),{name='fluid:water'})
renew:enableLiquidSimulation({interval=.5,budget=256})
renew:step(.5)
eq(renew.map:get_node(pos(0,1,0)).name,'fluid:water')
-- Two liquid kinds cannot take over a contested empty location.
local mixed=runtime()
mixed.map:set_node(pos(-1,1,0),{name='fluid:water'})
mixed.map:set_node(pos(1,1,0),{name='fluid:lava'})
mixed:enableLiquidSimulation({interval=.5,budget=256})
mixed:step(.5)
eq(mixed.map:get_node(pos(0,1,0)).name,'air')
eq(mixed.map:get_node(pos(1,1,0)).name,'fluid:lava')
-- Lava is shorter range than water on the same solid floor.
local lava=runtime()
ground(lava,5)
lava.map:set_node(pos(0,1,0),{name='fluid:lava'})
lava:enableLiquidSimulation({interval=.5,budget=256})
for i=1,5 do lava:step(.5) end
eq(lava.map:get_node(pos(2,1,0)).name,'fluid:lava_flowing')
eq(lava.map:get_node(pos(3,1,0)).name,'air')
-- Large dt and tiny budget cannot trigger an unlimited work loop.
local bounded=runtime()
bounded.map:set_node(pos(0,2,0),{name='fluid:water'})
local tiny=bounded:enableLiquidSimulation({interval=.5,budget=1})
eq(tiny:step(25),4)
eq(tiny.tick_count,4)
assert(tiny.changed_count<=4)
-- Flow disappears after its upstream source is removed.
local drain=runtime()
for x=-1,1 do for z=-1,1 do
 drain.map:set_node(pos(x,0,z),{name='fluid:stone'})
 if x==-1 or x==1 or z==-1 or z==1 then
  drain.map:set_node(pos(x,1,z),{name='fluid:stone'})
 end
end end
drain.map:set_node(pos(0,2,0),{name='fluid:water'})
drain:enableLiquidSimulation({interval=.5,budget=256})
drain:step(.5)
eq(drain.map:get_node(pos(0,1,0)).name,'fluid:water_flowing')
drain.map:remove_node(pos(0,2,0))
for i=1,16 do drain:step(.5) end
eq(drain.map:get_node(pos(0,1,0)).name,'air')
assert(not pcall(rt.enableLiquidSimulation,rt,{}))
local invalid=runtime()
assert(not pcall(invalid.enableLiquidSimulation,invalid,{budget=0}))
assert(not pcall(invalid.enableLiquidSimulation,invalid,{interval=-1}))
print('DYNAMIC WATER/LAVA FLOW, EVENTS, PERSISTENCE AND BUDGET PASS')
