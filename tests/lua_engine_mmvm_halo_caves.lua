-- Luanti 5.18 cavegen.cpp: CavesRandomWalk::carveRoute uses
-- vm->m_area.contains(p), not node_min/node_max, when ground is known.
-- Verify X/Z-overlap carve, durable sidecars and first-writer preservation.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Chunk=require('core.mapgen_chunk')
local Buffer=require('core.mapgen_voxelbuffer')
local Walk=require('core.caves_randomwalk')
local PRNG=require('core.pseudorandom')
local function runtime()
 local rt=Runtime.new({mapgen={seed=42,mg_name='v7',water_level=1},
  emerge_blocks_per_step=1,active_block_range=0})
 rt.api.register_node('test:stone',{})
 rt.api.register_node('test:water',{})
 return rt
end
local function disk()
 local fs={files={}}
 function fs.read(path)
  return fs.files[path],fs.files[path] and nil or 'not found'
 end
 function fs.write_atomic(path,content) fs.files[path]=content;return true end
 return fs
end
local function constant(n)
 return {offset=n,scale=0,spread={x=16,y=16,z=16},
  seed=1,octaves=1,persist=.5,lacunarity=2}
end
local opts={stone='test:stone',water='test:water',
 spflags='nomountains,noridges,nocaverns',
 noise={terrain_base=constant(-25),terrain_alt=constant(-25),
  terrain_persist=constant(.5),height_select=constant(1)}}
local g=Chunk.geometry({x=0,y=-1,z=0},{x=2,y=1,z=2})
assert(g.node_min.x==-16 and g.node_max.x==15)
assert(g.node_min.y==-16 and g.node_max.y==-1)
assert(g.full_node_max.x==31)
local fs=disk()
local rt=runtime()
rt:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
local store=rt:attachMapBlockStore(fs,'overlap88')
local border=rt.mapgenBorder
-- Simulate an already overgenerated strip from a neighboring chunk's
-- Y±1 stage, with known stone and unknown cells mixed in the halo.
local expected={}
for z=-4,4 do for y=-5,-1 do for x=16,19 do
 local p={x=x,y=y,z=z}
 local block=rt.map:blockkey(p)
 border:loadBlock(block)
 local key=x..','..y..','..z
 border.pending[block][key]={name='test:stone',param1=0,param2=0}
 border.dirty[block]=true
 expected[key]=true
end end end
local buf=Buffer.new(rt.map,g)
assert(border:seed(buf,g)==0)
local seeded=border:seedExpanded(buf,g)
assert(seeded==180)
assert(buf:get_node({x=16,y=-1,z=0}).name=='test:stone')
assert(buf:get_node({x=20,y=-1,z=0}).name=='ignore')
assert(buf:get_node({x=16,y=0,z=0}).name=='ignore')
assert(buf:get_flags({x=20,y=-1,z=0})==Buffer.FLAG_NO_DATA)
buf:mark_imports_clean()
local walk=Walk.new({map=buf,seed=42,
 node_min=g.node_min,node_max=g.node_max,
 stone='test:stone',water='test:water',
 max_stone_height=10,water_level=1})
walk.ps=PRNG.new(1467)
walk.rs=7
walk.orp={x=16,y=-2,z=0}
walk.of={x=0,y=0,z=0}
walk.large=false
walk.flooded=false
walk.large_cave_is_flat=false
walk:_carveRoute({x=0,y=0,z=0},0,false)
assert(walk.metrics.carved>0,'native bounds must carve known halo stone')
local changed=0
local before={}
for key in pairs(buf.modified) do
 local p=key:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 if expected[key] then
  assert(buf.overlay[key].name=='air')
  changed=changed+1
  before[#before+1]=key
 end
end
assert(changed>0,'at least one X-positive border voxel excavated')
assert(buf:get_node({x=20,y=-1,z=0}).name=='ignore',
 'CONTENT_IGNORE must remain unmodified outside seeded rock')
assert(buf:get_flags({x=20,y=-1,z=0})==Buffer.FLAG_NO_DATA)
local published=border:publishModifiedHalo(buf)
assert(published==changed)
local k=before[1]
local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
local p={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
local block=rt.map:blockkey(p)
assert(border.pending[block][k].name=='air')
assert(rt.api.get_node(p).name=='ignore',
 'written halo sidecar must not prematurely emerge the neighboring block')
assert(store:flush())
local savedpath=border:path(block)
assert(fs.files[savedpath] and fs.files[savedpath]:find(' air 0 0',1,true))
-- Restart and import the modified halo from disk. Later generating the
-- destination core must use the carved air rather than replacing it.
local reboot=runtime()
local v7=reboot:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
reboot:attachMapBlockStore(fs,'overlap88')
local stage=Buffer.new(reboot.map,g)
assert(reboot.mapgenBorder:seedExpanded(stage,g)==180)
assert(stage:get_node(p).name=='air')
local dest={x=16,y=-16,z=0}
local action
reboot.api.emerge_area(dest,dest,
 function(_,a) action=a end)
reboot:step(.1)
assert(action==reboot.api.EMERGE_GENERATED)
assert(v7.lastChunkBorderStats.seeded>=1)
assert(reboot.api.get_node(p).name=='air')
assert(reboot.mapgenBorder.pending[block][k]==nil)
-- A completed neighbor is never changed by a later cave overlapping it.
local resident=runtime()
resident:enableMapgenV7Chunks(opts,{x=2,y=1,z=2})
local rg=Chunk.geometry({x=0,y=-1,z=0},{x=2,y=1,z=2})
resident.map:set_node(p,{name='test:stone'})
local protected=Buffer.new(resident.map,rg)
assert(protected:get_node(p).name=='test:stone')
assert(not protected:set_node(p,{name='air'}))
assert(protected:get_node(p).name=='test:stone')
-- No halo seed means a tunnel cannot invent rock in CONTENT_IGNORE.
local blank=Buffer.new(runtime().map,g)
local skipped=Walk.new({map=blank,seed=42,node_min=g.node_min,
 node_max=g.node_max,stone='test:stone',water_level=1})
skipped.ps=PRNG.new(1467);skipped.rs=7
skipped.orp={x=16,y=-2,z=0}
skipped.of={x=0,y=0,z=0}
skipped.large=false;skipped.flooded=false
skipped.large_cave_is_flat=false
skipped:_carveRoute({x=0,y=0,z=0},0,false)
assert(skipped.metrics.carved==0)
print('LUANTI 5.18 MMVMANIP XZ OVERLAP CAVE CARVE AND PERSISTENCE PASS')
