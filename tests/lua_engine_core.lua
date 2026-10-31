-- API slice regression: run from project root with Lua 5.4.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local Vec=require('core.vector')
local Storage=require('core.storage')
local function eq(a,b,what)
 assert(a==b,(what or 'value')..': expected '..tostring(b)..', got '..tostring(a))
end
local env=Engine.new({settings={test_bool='true',val='21'},
 mapgen={seed=444},worldpath='worlds/demo'})
local api=env:installGlobals({})
eq(api.MAP_BLOCKSIZE,16)
eq(api.get_current_modname(),nil)
eq(api.settings:get('val'),'21')
eq(api.settings:get_num('val',0),21)
eq(api.settings:get_bool('test_bool',false),true)
eq(api.get_mapgen_setting('seed'),'444')
eq(api.get_worldpath(),'worlds/demo')
local translated=api.get_translator('sample')
eq(translated('Item @1 x @2','wood',3),'Item wood x 3')
api.register_node('example:grass',{
 description='Green',groups={crumbly=2,soil=1},light_source=4,
 on_construct=function(p)
  api.get_meta(p):set_int('built',1)
 end,
 on_destruct=function(p) eq(api.get_node(p).name,'example:grass') end
})
api.register_node('example:soil',{groups={crumbly=1}})
api.register_tool('example:pick',{groups={tool=1}})
api.register_craftitem('example:apple',{description='Apple'})
api.register_entity('example:mob',{initial_properties={hp_max=10}})
api.register_craft({output='example:grass',recipe={{'example:soil'}}})
api.register_alias('old:grass','example:grass')
eq(api.get_item_group('example:grass','crumbly'),2)
eq(api.get_node_group('old:grass','soil'),1)
eq(api.get_node_group('example:soil','missing'),0)
eq(api.registered_items['example:pick'].stack_max,1)
eq(api.registered_entities['example:mob'].initial_properties.hp_max,10)
eq(#env.registry.crafts,1)
local p={x=-17,y=3,z=0}
eq(env.map:blockkey(p),'-2,0,0','negative mapblock floor')
eq(env.map:get_node(p).name,'air')
local placed={}
api.register_on_placenode(function(pos,node,placer,old)
 placed[#placed+1]={pos=pos,node=node,old=old}
end)
assert(api.place_node(p,{name='old:grass',param2=5}))
eq(api.get_node(p).name,'example:grass')
eq(api.get_node(p).param2,5)
eq(env.map.count,1)
eq(env.map.revisions['-2,0,0'],1)
eq(placed[1].old.name,'air')
eq(api.get_meta(p):get_int('built'),1)
local meta=api.get_meta(p)
meta:set_string('empty','')
eq(meta:get_string('empty'),'')
meta:set_string('chars','ola\n& = 😀')
eq(meta:get_string('chars'),'ola\n& = 😀')
local snap=meta:to_table()
meta:set_int('counter',25)
eq(meta:get_int('counter'),25)
meta:from_table(snap)
eq(meta:get_int('counter'),0)
eq(meta:get_string('chars'),'ola\n& = 😀')
local copy=api.get_node(p)
copy.name='fake'
eq(api.get_node(p).name,'example:grass','get_node returns copy')
local timerCount=0
api.register_node('example:clock',{
 on_timer=function(pos,elapsed)
  timerCount=timerCount+1
  assert(elapsed>=.2)
  return timerCount==1
 end
})
local timerPos={x=1,y=0,z=3}
assert(api.set_node(timerPos,{name='example:clock'}))
api.get_node_timer(timerPos):start(.2)
local calls={}
api.register_globalstep(function(dt) calls[#calls+1]=dt end)
local delayed={}
api.after(.1,function(a,b)
 delayed[#delayed+1]=a..b
 api.after(0,function() delayed[#delayed+1]='nested' end)
end,'x','y')
local c=api.after(.2,function() delayed[#delayed+1]='cancelled' end)
c:cancel()
env:step(.1)
eq(delayed[1],'xy')
eq(delayed[2],nil,'nested callback deferred')
env:step(.1)
eq(timerCount,1)
eq(delayed[2],'nested')
env:step(.2)
eq(timerCount,2,'timer repeated once')
eq(api.get_node_timer(timerPos):is_started(),false)
eq(#calls,3)
eq(api.get_gametime(),0)
local grow=0
api.register_abm({nodenames={'group:soil'},interval=.2,chance=1,
 action=function(pos,node)
  eq(node.name,'example:grass')
  grow=grow+1
 end})
env:step(.2)
eq(grow,1)
local nearby=api.find_nodes_in_area({x=-18,y=3,z=0},{x=-16,y=3,z=0},'group:soil')
eq(#nearby,1)
eq(nearby[1].x,-17)
eq(api.get_node_light(p),4)
local generated=0
api.register_on_generated(function(minp,maxp,seed)
 eq(seed,33)
 generated=generated+1
end)
env:generate({x=0,y=0,z=0},{x=1,y=1,z=1},33)
eq(generated,1)
local modsLoaded=0
api.register_on_mods_loaded(function() modsLoaded=modsLoaded+1 end)
env:finishMods()
eq(modsLoaded,1)
local v=Vec.new(1,2,3)
eq((v+Vec.new(2,3,4)).z,7)
eq((v*2).x,2)
eq(Vec.length(Vec.new(3,4,0)),5)
eq(Vec.dot(Vec.new(1,0,0),Vec.new(0,1,0)),0)
eq(Vec.cross(Vec.new(1,0,0),Vec.new(0,1,0)).z,1)
eq(Vec.round(Vec.new(-1.5,2.5,0)).x,-1)
local encoded=Storage.encode(env.map)
assert(encoded:find('LUAENGINE 1',1,true))
local restored=Storage.decode(encoded)
eq(restored:get_node(p).param2,5)
eq(restored:get_meta(p):get_string('chars'),'ola\n& = 😀')
eq(restored:get_meta(p):get_string('empty'),'')
eq(restored:get_node(timerPos).name,'example:clock')
local fsdata={}
local fs={write=function(path,data) fsdata[path]=data;return true end,
 read=function(path) return fsdata[path] end}
assert(Storage.save(env.map,'world.map',fs))
local saved=Storage.load('world.map',fs)
eq(saved:get_node(p).name,'example:grass')
eq(select(2,Storage.load('missing',fs)),'not found')
assert(not pcall(Storage.decode,'LUAENGINE 1\nN 2 3 4 evil 999 0\nEND'))
assert(not pcall(Storage.decode,'LUAENGINE 1\nN 1 2 3 stone 0 0\n'))
assert(not pcall(api.set_node,{x=.1,y=1,z=0},{name='example:soil'}))
local dug={}
api.register_on_dignode(function(pos,old)
 dug[#dug+1]=old.name
end)
assert(api.dig_node(p))
eq(dug[1],'example:grass')
eq(api.get_node(p).name,'air')
eq(env.map.count,1)
assert(not api.dig_node(p))
print('lua_engine_core: OK')
