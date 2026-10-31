-- Fase 7: seeded chunk generation, deterministic tree boundaries and save flags.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Worldgen=require('core.worldgen')
local Storage=require('core.storage')
local names={'grass','dirt','stone','sand','water','wood','leaves','coal_ore'}
local function new(seed)
 local rt=Runtime.new()
 for _,name in ipairs(names) do
  rt.api.register_node('lua:'..name,{description=name})
 end
 local callbacks=0
 rt.api.register_on_generated(function(minp,maxp,s)
  assert(minp.x%16==0 and maxp.x%16==15)
  assert(s==seed)
  callbacks=callbacks+1
 end)
 local gen=Worldgen.new(rt,{seed=seed,nodes={ore='lua:coal_ore'}})
 return rt,gen,function()return callbacks end
end
local function eq(a,b)
 assert(a==b,'expected '..tostring(b)..' got '..tostring(a))
end
local a,g,events=new(42)
local ok,writes=g:generate(0,0)
assert(ok and writes>100,'generator must place actual terrain')
eq(events(),1)
assert(a.map.generatedChunks['0,0']==42)
assert(a.api.get_node({x=0,y=-16,z=0}).name~='air')
eq(g:generate(0,0),false)
eq(events(),1)
eq(a.map.count,writes,'written blocks tracked')
local biome=g:biome(0,0)
assert(biome=='forest' or biome=='desert' or biome=='plains')
assert(g:height(0,0)<=31 and g:height(0,0)>=-16)
-- The chunk-generation marker must survive saving. Removing a stone
-- cannot magically regenerate the next time the same chunk is requested.
local pos={x=0,y=-16,z=0}
a.api.remove_node(pos)
eq(a.api.get_node(pos).name,'air')
local saved=Storage.encode(a.map)
assert(saved:find('G 0 0 42',1,true))
local loaded=Storage.decode(saved)
a.map=loaded
a.map.registry=a.registry.items
local regen=Worldgen.new(a,{seed=42})
eq(regen:generate(0,0),false)
eq(a.api.get_node(pos).name,'air')
local status,msg=pcall(function()Worldgen.new(a,{seed=43}):generate(0,0)end)
assert(not status and tostring(msg):find('seed changed'),
 'reseed must never overwrite a stored chunk')
-- Existing player blocks in an ungenerated region must be retained.
local p={x=-16,y=20,z=0}
a.api.set_node(p,{name='lua:wood'})
local more,n=regen:generate(-1,0)
assert(more and n>0)
eq(a.api.get_node(p).name,'lua:wood')
eq(a.map.generatedChunks['-1,0'],42)
-- Procedural terrain is purely coordinate-based; generation order must
-- not change leaves at chunk edges, caves, ores, or all saved nodes.
local first,one=new(947)
local second,two=new(947)
assert(one:generate(-1,0))
assert(one:generate(0,0))
assert(two:generate(0,0))
assert(two:generate(-1,0))
eq(Storage.encode(first.map),Storage.encode(second.map))
local diff,third=new(948)
assert(third:generate(0,0))
assert(Storage.encode(second.map)~=Storage.encode(diff.map))
-- Pure noise queries are independent from chunk generation state.
local sample=Worldgen.new(first,{seed=947})
eq(sample:height(-14,7),one:height(-14,7))
eq(sample:biome(-14,7),one:biome(-14,7))
assert(not pcall(function()g:generate(2000,0)end))
assert(not pcall(function()Worldgen.new(a,{seed=9007199254740992})end))
local legacy=Storage.decode('LUAENGINE 1\nN 0 0 0 lua%3Astone 0 0\nEND\n')
assert(next(legacy.generatedChunks)==nil,'old save remains valid')
local invalid='LUAENGINE 1\nG 0 0 42\nG 0 0 42\nEND\n'
assert(not pcall(Storage.decode,invalid),'duplicate chunk marker rejected')
print('lua_engine_worldgen: OK')
