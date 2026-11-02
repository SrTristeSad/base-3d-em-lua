-- Luanti 5.18 src/map.cpp:894-935: MMVManip::blitBackAll
-- and src/voxel.cpp:231-246: VoxelManipulator::copyTo.
-- Explicit overwrite=true may modify generated nodes; default cannot.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Map=require('core.map')
local Buffer=require('core.mapgen_voxelbuffer')
local Chunk=require('core.mapgen_chunk')
local Runtime=require('core.runtime')
local function eq(a,b,label)
 assert(a==b,(label or 'mismatch')..': '..tostring(a)..' ~= '..tostring(b))
end
local function fs()
 local out={files={}}
 function out.read(p) return out.files[p],out.files[p] and nil or 'not found' end
 function out.write_atomic(p,s) out.files[p]=s;return true end
 return out
end
local function runtime()
 local rt=Runtime.new({mapgen={seed=98,mg_name='v7'},
  active_block_range=0,emerge_blocks_per_step=1})
 for _,id in ipairs({'test:marker','test:stone','test:gem'}) do
  rt.api.register_node(id,{})
 end
 return rt
end
local geom=Chunk.geometry({x=0,y=0,z=0},1)
local core='0,0,0'
local blank='-1,0,0'
local missing='0,0,1'
local corepos={x=0,y=0,z=0}
local coreair={x=1,y=0,z=0}
local empty={x=2,y=0,z=0}
local blankold={x=-16,y=0,z=0}
local blanknew={x=-15,y=0,z=0}
local blankunknown={x=-14,y=0,z=0}
local missingnew={x=0,y=0,z=16}
local missingunknown={x=0,y=0,z=17}
-- Default (overwrite_generated=false): staged edits to generated
-- blocks are ignored, but partial and newly emerged blocks are copied.
local w=runtime()
local d=fs()
local store=w:attachMapBlockStore(d,'blit98')
local map=w.map
map:set_node(corepos,{name='test:stone',param1=8,param2=12})
map.last_active[core]=0
map:set_node(coreair,{name='air',param1=37,param2=21})
map:get_meta(corepos):set_string('owner','keeper')
map:get_timer(corepos):set(12,3)
assert(map:create_blank_block(blank))
map:set_node(blankold,{name='test:marker',param1=2,param2=4})
local vm=Buffer.new(map,geom)
eq(vm:initialEmerge(false),2)
assert(not vm:set_node(corepos,{name='test:marker'}),
 'terrain writer must NOT override generated mapblocks')
assert(not pcall(vm.stage_vmanip_node,vm,corepos,{name='ignore'}))
assert(not pcall(vm.stage_vmanip_node,vm,corepos,
 {name='air',param1=256}))
assert(vm:stage_vmanip_node(corepos,{name='test:marker',param1=5,param2=6}))
assert(vm:stage_vmanip_node(blanknew,
 {name='air',param1=17,param2=23}))
assert(vm:stage_vmanip_node(missingnew,
 {name='test:marker',param1=33,param2=44}))
assert(vm:getCoveredBlocks()[core])
assert(vm:getCoveredBlocks()[blank])
assert(vm:getCoveredBlocks()[missing])
eq(map:get_node(corepos).name,'test:stone','staging has no live effects')
eq(map:get_node(blanknew).name,'ignore')
eq(map:get_node(missingnew).name,'air',
 'missing blocks are not implicitly emerged by the staging operation')
local blocks,changed,created=vm:blitBackAll()
eq(blocks[core],nil,'default skips already generated mapblocks')
assert(blocks[blank] and blocks[missing])
eq(changed,2)
eq(created,1)

assert(not pcall(vm.blitBackAll,vm,false),'an explicit blit is one-shot')
eq(map:get_node(corepos).name,'test:stone')
eq(map:get_node(coreair).param1,37)
eq(map:get_meta(corepos):get_string('owner'),'keeper')
eq(map:get_timer(corepos):get_timeout(),12)
eq(map:get_node(blankold).param2,4)
eq(map:get_node(blanknew).name,'air')
eq(map:get_node(blanknew).param1,17)
eq(map:get_node(blanknew).param2,23)
eq(map:get_node(blankunknown).name,'ignore')
eq(map:get_node(missingnew).param2,44)
eq(map:get_node(missingunknown).name,'ignore')
assert(map.blank_blocks[blank] and map.blank_blocks[missing])
assert(not map.last_active[blank] and not map.last_active[missing])
assert(store:flush())
assert(d.files[store:partial_path(blank)])
assert(d.files[store:partial_path(missing)])
assert(not d.files[store:path(blank)] and not d.files[store:path(missing)])
local reboot=runtime()
local reload=reboot:attachMapBlockStore(d,'blit98')
assert(reload:load_or_create_blank(blank))
assert(reload:load_or_create_blank(missing))
eq(reboot.map:get_node(blankold).param2,4)
eq(reboot.map:get_node(blanknew).param2,23)
eq(reboot.map:get_node(missingnew).param1,33)
eq(reboot.map:get_node(blankunknown).name,'ignore')
eq(reboot.map:get_node(missingunknown).name,'ignore')
-- Overwrite=true uses the full 16^3 initialEmerge snapshot.
-- Imported implicit AIR is data, CONTENT_IGNORE isn't.
local revised=runtime()
local rm=revised.map
rm:set_node(corepos,{name='test:stone',param1=1,param2=2})
rm:set_node(coreair,{name='air',param1=39,param2=41})
rm.last_active[core]=0
rm:get_meta(corepos):set_string('owner','remain')
rm:get_timer(corepos):set(20,4)
assert(rm:create_blank_block(blank))
rm:set_node(blankold,{name='test:marker',param1=7,param2=9})
local bv=Buffer.new(rm,geom)
eq(bv:initialEmerge(false),2)
assert(bv:stage_vmanip_node(corepos,
 {name='air',param1=18,param2=27}))
assert(bv:stage_vmanip_node(coreair,
 {name='test:marker',param1=21,param2=31}))
assert(bv:stage_vmanip_node(blanknew,
 {name='test:marker',param1=44,param2=55}))
local modified,updates,newblocks=bv:blitBackAll(true)
eq(newblocks,0)
assert(modified[core] and modified[blank])
eq(updates,3)
eq(rm:get_node(corepos).name,'air')
eq(rm:get_node(corepos).param1,18)
eq(rm:get_node(corepos).param2,27)
eq(rm:get_node(coreair).name,'test:marker')
eq(rm:get_node(coreair).param1,21)
eq(rm:get_node(empty).name,'air','known implicit AIR is copied')
eq(rm:get_meta(corepos):get_string('owner'),'remain',
 'native MapBlock::copyFrom does not clear metadata')
eq(rm:get_timer(corepos):get_elapsed(),4)
assert(rm.last_active[core]~=nil,'overwrite=true cannot unset generated state')
assert(rm.blank_blocks[blank],'overwritten blank stays ungenerated')
eq(rm:get_node(blankold).param1,7)
eq(rm:get_node(blanknew).param2,55)
eq(rm:get_node(blankunknown).name,'ignore',
 'copyTo does not touch CONTENT_IGNORE')
-- Even a bit-identical blit marks the covered MapBlock modified.
local unchanged=runtime()
unchanged.map:set_node(corepos,{name='test:stone'})
unchanged.map.last_active[core]=0
local identity=Buffer.new(unchanged.map,geom)
identity:initialEmerge(false)
local mod,n=identity:blitBackAll(true)
assert(mod[core] and unchanged.map.modified[core])
eq(n,0)
-- Source preflight is all-or-nothing for both generated and partial
-- blocks: a concurrent edit cannot be silently overwritten.
local conflict=runtime()
local cm=conflict.map
cm:set_node(corepos,{name='test:stone'})
cm.last_active[core]=0
assert(cm:create_blank_block(blank))
local race=Buffer.new(cm,geom)
race:initialEmerge(false)
race:stage_vmanip_node(corepos,{name='test:marker'})
race:stage_vmanip_node(blanknew,{name='test:marker'})
cm:set_node(corepos,{name='test:gem'})
assert(not pcall(race.blitBackAll,race,true))
eq(cm:get_node(blanknew).name,'ignore',
 'preflight failure must not mutate the other target')
eq(cm:get_node(corepos).name,'test:gem')
-- A missing block which emerges concurrently must also fail before
-- any writes; do not create an incomplete MapBlock over player edits.
local late=runtime()
local lv=Buffer.new(late.map,geom)
lv:initialEmerge(false)
lv:stage_vmanip_node(missingnew,{name='test:marker'})
lv:stage_vmanip_node(blanknew,{name='test:marker'})
late.map:set_node(missingnew,{name='test:gem'})
assert(not pcall(lv.blitBackAll,lv,false))
eq(late.map:get_node(blanknew).name,'air')
assert(not late.map.blank_blocks[blank])
eq(late.map:get_node(missingnew).name,'test:gem')
print('LUANTI 5.18 EXPLICIT MMVM BLITBACKALL OVERWRITE AND DISK PASS')
