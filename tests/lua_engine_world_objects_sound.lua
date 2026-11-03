-- Luanti server API used by gameplay mods: object radius/cuboid queries,
-- positional/object sounds, ephemeral playback, stop/fade and host lifecycle.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local function eq(a,b,msg)
 assert(a==b,(msg or 'mismatch')..' '..tostring(a)..' != '..tostring(b))
end
local function contains(t,value)
 for _,v in ipairs(t) do if v==value then return true end end
 return false
end
local rt=Runtime.new({active_block_range=0})
rt.api.register_craftitem('test:coin',{description='Coin'})
rt.api.register_entity('test:mob',{
 initial_properties={physical=false,pointable=true},
 on_activate=function(self)
  eq(self.object:get_pos().y,1)
 end
})
local mob=assert(rt.api.add_entity({x=0,y=1,z=0},'test:mob'))
local far=assert(rt.api.add_entity({x=5,y=1,z=0},'test:mob'))
local item=assert(rt.api.add_item({x=1,y=1,z=0},'test:coin 2'))
local gone=assert(rt.api.add_item({x=0,y=1,z=0},'test:coin'))
gone:remove()
local player={
 get_player_name=function() return 'Alpha' end,
 get_pos=function() return {x=0,y=1,z=1} end
}
local player2={
 get_player_name=function() return 'NoPosition' end
}
assert(rt:connectPlayer(player))
assert(rt:connectPlayer(player2))
local center={x=0,y=1,z=0}
local around=rt.api.get_objects_inside_radius(center,1.1)
eq(#around,3)
eq(around[1],mob)
eq(around[2],item)
eq(around[3],player)
eq(contains(around,far),false)
eq(contains(around,gone),false)
eq(contains(around,player2),false)
eq(around[1]:get_luaentity().name,'test:mob')
eq(center.x,0)
local tiny=rt.api.get_objects_inside_radius(center,0)
eq(#tiny,1)
eq(tiny[1],mob)
local all=rt.api.get_objects_inside_radius(center,100)
eq(#all,4)
assert(contains(all,far))
assert(contains(all,player))
local area=rt.api.get_objects_in_area(
 {x=-1,y=1,z=-1},{x=1,y=1,z=1})
eq(#area,3)
eq(area[1],mob)
eq(area[2],item)
eq(area[3],player)
local slice=rt.api.get_objects_in_area(
 {x=1,y=1,z=0},{x=1,y=1,z=0})
eq(#slice,1)
eq(slice[1],item)
eq(#rt.api.get_objects_in_area(
 {x=2,y=0,z=0},{x=4,y=2,z=2}),0)
for _,arg in ipairs({
 {{x=0,y=0,z=0},-1},
 {{x=0,y=0,z=0},math.huge},
 {{x=0/0,y=0,z=0},1},
 {{x=0,y=0},2}
}) do assert(not pcall(rt.api.get_objects_inside_radius,arg[1],arg[2])) end
assert(not pcall(rt.api.get_objects_in_area,
 {x=1,y=0,z=0},{x=0,y=0,z=0}))
assert(not pcall(rt.api.get_objects_in_area,
 {x=0,y=0,z=0},{x=0/0,y=0,z=0}))
mob:set_pos({x=10,y=1,z=0})
eq(#rt.api.get_objects_inside_radius(center,1.1),2)
eq(#rt.api.get_objects_in_area(
 {x=10,y=1,z=0},{x=10,y=1,z=0}),1)
assert(rt:disconnectPlayer('Alpha'))
eq(#rt.api.get_objects_inside_radius(center,1.1),1)
item:remove()
eq(#rt.api.get_objects_inside_radius(center,1.1),0)
eq(#rt.api.get_objects_in_area(
 {x=0,y=0,z=-1},{x=1,y=2,z=2}),0)

-- Headless worlds must not fabricate a server-side sound handle.
local silent=Runtime.new()
eq(silent.api.sound_play('test:footstep'),nil)
silent.api.sound_stop(1)
silent.api.sound_fade(1,1,0)
local plays,stops,fades={},{},{}
local backend={}
function backend:play(spec,params,ephemeral)
 local ref={n=#plays+1}
 plays[#plays+1]={ref=ref,spec=spec,params=params,ephemeral=ephemeral}
 return ref
end
function backend:stop(ref)
 stops[#stops+1]=ref
end
function backend:fade(ref,step,gain)
 fades[#fades+1]={ref=ref,step=step,gain=gain}
end
local audio=Runtime.new({sound_backend=backend})
local sound_spec={name='test:stone_place',gain=.4,pitch=1.5}
local sound_pos={x=-3.5,y=7,z=8}
local sound_params={pos=sound_pos,gain=.6,
 max_hear_distance=24,loop=true,fade=.2,start_time=1.25,
 to_player='Alpha',exclude_player='Beta'}
local handle1=audio.api.sound_play(sound_spec,sound_params)
eq(handle1,1)
eq(#plays,1)
eq(plays[1].spec.name,'test:stone_place')
eq(plays[1].spec.gain,.4)
eq(plays[1].spec.pitch,1.5)
eq(plays[1].spec.loop,true)
eq(plays[1].spec.fade,.2)
eq(plays[1].spec.start_time,1.25)
eq(plays[1].params.gain,.6)
eq(plays[1].params.max_hear_distance,24)
eq(plays[1].params.to_player,'Alpha')
eq(plays[1].params.exclude_player,'Beta')
eq(plays[1].params.pos.x,-3.5)
plays[1].params.pos.x=100
plays[1].spec.name='changed_by_backend'
eq(sound_spec.name,'test:stone_place')
eq(sound_pos.x,-3.5)
local sound_obj={
 get_pos=function() return {x=2,y=3,z=4} end
}
local handle2=audio.api.sound_play(
 {name='test:door',loop=false,pitch=1.0},
 {object=sound_obj,pitch=1.2})
eq(handle2,2)
eq(plays[2].spec.pitch,1.2)
eq(plays[2].params.object,sound_obj)
audio.api.sound_fade(handle1,2,.1)
eq(#fades,1)
eq(fades[1].ref,plays[1].ref)
eq(fades[1].step,2)
eq(fades[1].gain,.1)
audio.api.sound_stop(handle1)
eq(#stops,1)
eq(stops[1],plays[1].ref)
audio.api.sound_stop(handle1)
eq(#stops,1)
audio.api.sound_fade(handle1,1,.3)
eq(#fades,1)
local before=#plays
eq(audio.api.sound_play({name=''}),nil)
eq(#plays,before)
eq(audio.api.sound_play('test:ambient',nil,true),nil)
eq(#plays,before+1)
eq(plays[#plays].ephemeral,true)
eq(audio.sounds.active[3],nil)
assert(not pcall(audio.setSoundBackend,audio,nil),
 'cannot change sound backend while a handle is active')
assert(audio.sounds:finished(handle2))
audio.api.sound_stop(handle2)
eq(#stops,1)
audio:setSoundBackend(backend)
local h3=audio.api.sound_play('test:after_fade',{gain=1})
eq(h3,3)
local failing_inputs={
 function() audio.api.sound_play({},'wrong') end,
 function() audio.api.sound_play(55) end,
 function() audio.api.sound_play({name='x',pitch=-1}) end,
 function() audio.api.sound_play({name='x',gain=math.huge}) end,
 function() audio.api.sound_play({name='x'}, {pos={x=0/0,y=0,z=0}}) end,
 function() audio.api.sound_play({name='x'}, {object={}}) end,
 function() audio.api.sound_play({name='x'}, {loop='true'}) end,
 function() audio.api.sound_play('test:a',{},'yes') end,
 function() audio.api.sound_stop('1') end,
 function() audio.api.sound_fade(2,-1,1) end,
 function() audio.api.sound_fade(2,1,0/0) end
}
for _,fn in ipairs(failing_inputs) do
 assert(not pcall(fn),'invalid sound data unexpectedly accepted')
end
eq(#plays,4)
local callbacks=0
audio.api.register_on_shutdown(function() callbacks=callbacks+1 end)
assert(audio:shutdown())
eq(callbacks,1)
eq(#stops,2)
eq(stops[2],plays[4].ref)
eq(audio.sounds.active[3],nil)
eq(audio:shutdown(),false)
eq(callbacks,1)
eq(#stops,2)
-- Playback host failure cannot produce a fake usable integer handle.
local failed=Runtime.new({sound_backend={
 play=function() return nil end,
 stop=function() end,fade=function() end
}})
eq(failed.api.sound_play('test:missing'),nil)
assert(not pcall(failed.setSoundBackend,failed,{play=function() end}))
print('WORLD OBJECTS AND AUDIO HOST BRIDGE PASS')
