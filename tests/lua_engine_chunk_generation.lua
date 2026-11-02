-- Luanti 5.18 chunk-alignment, generated core, emerge and persistence.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Chunk=require('core.mapgen_chunk')
local Runtime=require('core.runtime')
local Walk=require('core.caves_randomwalk')
local function eq3(p,x,y,z)
 assert(p.x==x and p.y==y and p.z==z,
  ('unexpected coords %s,%s,%s expected %s,%s,%s'):format(
   p.x,p.y,p.z,x,y,z))
end
eq3(Chunk.containing({x=0,y=0,z=0},5),-2,-2,-2)
eq3(Chunk.containing({x=2,y=-3,z=3},5),-2,-7,3)
eq3(Chunk.containing({x=0,y=0,z=-2},2),-1,-1,-3)
eq3(Chunk.containing({x=1,y=1,z=1},2),1,1,1)
local geom=Chunk.geometry({x=0,y=0,z=0},{x=2,y=1,z=2})
eq3(geom.block_min,-1,0,-1)
eq3(geom.block_max,0,0,0)
eq3(geom.node_min,-16,0,-16)
eq3(geom.node_max,15,15,15)
eq3(geom.full_node_min,-32,-16,-32)
eq3(geom.full_node_max,31,31,31)
assert(#Chunk.each_block(geom)==4)
assert(not pcall(Chunk.geometry,{x=1936,y=0,z=0},{x=2,y=1,z=2}))
assert(not pcall(Chunk.size,{x=13,y=1,z=1}))
assert(not pcall(Chunk.size,{x=12,y=12,z=12+1}))
local function constant(v)
 return {offset=v,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local opts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 randomwalk_caves=true,small_cave_num_min=1,
 small_cave_num_max=1,large_cave_num_min=0,
 large_cave_num_max=0,
 noise={terrain_base=constant(45),terrain_alt=constant(-20),
  terrain_persist=constant(.5),height_select=constant(1)}}
local function runtime()
 local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
  emerge_blocks_per_step=1,active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:water',{})
 return rt
end
local fs={files={}}
function fs.read(path)
 return fs.files[path],fs.files[path] and nil or 'not found'
end
function fs.write_atomic(path,content) fs.files[path]=content;return true end
local rt=runtime()
local gen=rt:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
local store=rt:attachMapBlockStore(fs,'chunk84')
local calls={}
rt.api.register_on_generated(function(minp,maxp,seed)
 calls[#calls+1]={minp=minp,maxp=maxp,seed=seed}
end)
local selected={x=0,y=0,z=0}
assert(rt.api.get_node(selected).name=='ignore')
local actions={}
rt.api.emerge_area(selected,selected,function(p,action,remaining,param)
 actions[#actions+1]={p=p,action=action,remaining=remaining,param=param}
end,'chunk')
rt:step(.1)
assert(#actions==1 and actions[1].action==rt.api.EMERGE_GENERATED)
assert(actions[1].param=='chunk')
assert(#calls==1,'chunk callback must execute once for full core')
eq3(calls[1].minp,-16,0,-16)
eq3(calls[1].maxp,15,15,15)
assert(gen.generated==1 and gen.generatedMapBlocks==4)
assert(gen.lastRandomWalkMetrics.caves==1)
assert(#gen.lastRandomWalkEvents==2)
eq3(gen.lastChunkGeometry.full_node_min,-32,-16,-32)
assert(rt.api.get_node({x=-16,y=0,z=-16}).name~='ignore')
assert(rt.api.get_node({x=15,y=15,z=15}).name~='ignore')
local loaded=rt.api.get_loaded_blocks()
assert(#loaded==4,'all mapblocks of generated chunk must be resident')
local same={}
rt.api.emerge_area({x=-16,y=0,z=-16},
 {x=-16,y=0,z=-16},function(_,action) same[#same+1]=action end)
rt:step(.1)
assert(same[1]==rt.api.EMERGE_FROM_MEMORY)
assert(gen.generated==1,'chunk cannot regenerate on second emerge')
assert(store:flush())
for _,b in ipairs(Chunk.each_block(geom)) do
 assert(type(fs.files[store:path(b.key)])=='string',
  'chunk flush must persist every mapblock, including empty ones')
end
local rt2=runtime()
local gen2=rt2:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
rt2:attachMapBlockStore(fs,'chunk84')
local from_disk
rt2.api.emerge_area(selected,selected,
 function(_,action) from_disk=action end)
rt2:step(.1)
assert(from_disk==rt2.api.EMERGE_FROM_DISK)
assert(gen2.generated==0)
for x=-16,15 do for z=-16,15 do for y=0,15 do
 local p={x=x,y=y,z=z}
 local before=rt.api.get_node(p).name
 local after=rt2.api.get_node_or_nil(p)
 if after==nil then
  -- Only requested block loaded from disk so far.
  local block={x=math.floor(x/16),y=0,z=math.floor(z/16)}
  assert(block.x~=0 or block.z~=0)
 else
  assert(after.name==before)
 end
end end end
-- A saved neighbor MUST block whole-chunk regeneration. The missing
-- requested mapblock is generated alone, leaving the old edits untouched.
local rt3=runtime()
local gen3=rt3:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
local fs3={files={}}
function fs3.read(path)
 return fs3.files[path],fs3.files[path] and nil or 'not found'
end
function fs3.write_atomic(path,data) fs3.files[path]=data;return true end
local store3=rt3:attachMapBlockStore(fs3,'chunk84partial')
rt3.api.set_node({x=-16,y=2,z=-16},{name='test:water'})
local oldnode=rt3.api.get_node({x=-16,y=2,z=-16}).name
local partial
rt3.api.emerge_area(selected,selected,function(_,a) partial=a end)
rt3:step(.1)
assert(partial==rt3.api.EMERGE_GENERATED)
assert(gen3.generated==1)
assert(gen3.generatedMapBlocks==nil,
 'mixed resident chunk must use isolated mapblock fallback')
assert(rt3.api.get_node({x=-16,y=2,z=-16}).name==oldnode)
assert(rt3.api.get_node_or_nil({x=-16,y=0,z=0})==nil,
 'fallback must not mark unrelated blocks generated')
assert(store3:flush())
-- Legacy generator remains one mapblock; default is unchanged.
local legacy=runtime()
local old=legacy:enableMapgenV7Base(opts)
local oldaction
legacy.api.emerge_area(selected,selected,function(_,a) oldaction=a end)
legacy:step(.1)
assert(oldaction==legacy.api.EMERGE_GENERATED)
assert(old.generated==1 and old.generatedMapBlocks==nil)
local lb=legacy.api.get_loaded_blocks()
assert(#lb==1)
-- The callback bounds must be mapblock-aligned and contain the request.
assert(not pcall(rt.enableMapgenV7Chunks,rt,opts,{x=3,y=1,z=1}))
-- A malformed third-party generator range must report an emerge error
-- without corrupting LBM markers or breaking the runtime tick.
local bad=runtime()
bad:setMapBlockGenerator(function()
 return true,{minp={x=16,y=0,z=0},maxp={x=31,y=15,z=15}}
end)
local bad_action
bad.api.emerge_area(selected,selected,
 function(_,action) bad_action=action end)
bad:step(.1)
assert(bad_action==bad.api.EMERGE_ERRORED)
assert(#bad.api.get_loaded_blocks()==0)
print('LUANTI 5.18 CHUNK ALIGNMENT, STAGING AND STREAMING PASS')
