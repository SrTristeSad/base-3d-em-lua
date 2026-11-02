-- Luanti 5.18 emergence, callback status and unloaded-node semantics.
-- All modes run under Lua 5.4 and LuaJIT in GitHub Actions.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local fs={files={}}
function fs.read(path)
 return fs.files[path],fs.files[path] and nil or 'not found'
end
function fs.write_atomic(path,content)
 fs.files[path]=content;return true
end
-- Seed one previously generated mapblock to test disk emergence on restart.
local seed=Runtime.new()
seed.api.register_node('audit:saved',{})
seed.api.set_node({x=16,y=2,z=0},{name='audit:saved'})
local seedstore=seed:attachMapBlockStore(fs,'emergeWorld')
assert(seedstore:flush())
local rt=Runtime.new({active_block_range=0,emerge_blocks_per_step=1})
local api=rt.api
api.register_node('audit:saved',{})
api.register_node('audit:generated',{})
local on_generated,one_shots={},0
api.register_on_generated(function(minp,maxp)
 on_generated[#on_generated+1]={minp.x,maxp.x}
end)
api.register_lbm({name='audit:old',nodenames={'audit:generated'},
 action=function() one_shots=one_shots+1 end})
local store=rt:attachMapBlockStore(fs,'emergeWorld')
local n={x=16,y=2,z=0}
assert(api.get_node(n).name=='ignore')
assert(api.get_node_or_nil(n)==nil)
local id,p1,p2,ok=api.get_node_raw(16,2,0)
assert(id==api.CONTENT_IGNORE and p1==0 and p2==0 and ok==false)
assert(api.compare_block_status(n,'unknown'))
assert(api.compare_block_status(n,'loaded')==false)
assert(api.compare_block_status(n,'invalid')==nil)
local generated_calls=0
rt:setMapBlockGenerator(function(runtime,minp,maxp)
 generated_calls=generated_calls+1
 if minp.x==0 then
  assert(minp.y==0 and minp.z==0 and maxp.x==15)
  runtime.api.set_node({x=0,y=0,z=0},{name='audit:generated'})
  return true
 end
 return false
end)
-- load_area is synchronous but MUST NOT generate absent mapblocks.
assert(api.load_area({x=48,y=0,z=0})==0)
assert(generated_calls==0)
local calls={}
local context={identifier='user-token'}
api.emerge_area({x=0,y=0,z=0},{x=32,y=0,z=0},
 function(block,action,remaining,param)
  assert(param==context)
  calls[#calls+1]={x=block.x,action=action,remaining=remaining}
 end,context)
assert(#calls==0,'emerge_area must enqueue, not synchronously call callbacks')
assert(api.compare_block_status({x=32,y=0,z=0},'emerging'))
assert(not api.compare_block_status({x=32,y=0,z=0},'unknown'))
rt:step(.1)
assert(#calls==1 and calls[1].x==0 and
 calls[1].action==api.EMERGE_GENERATED and calls[1].remaining==2)
assert(generated_calls==1 and api.get_node({x=0,y=0,z=0}).name=='audit:generated')
assert(#on_generated==1 and on_generated[1][1]==0 and
 on_generated[1][2]==15)
assert(one_shots==0,'generation must not invoke one-shot LBMs')
assert(api.get_node(n).name=='ignore')
rt:step(.1)
assert(#calls==2 and calls[2].x==1 and
 calls[2].action==api.EMERGE_FROM_DISK and calls[2].remaining==1)
assert(api.get_node(n).name=='audit:saved')
assert(api.get_node_or_nil(n).name=='audit:saved')
id,p1,p2,ok=api.get_node_raw(16,2,0)
assert(id==api.get_content_id('audit:saved') and ok)
rt:step(.1)
assert(#calls==3 and calls[3].x==2 and
 calls[3].action==api.EMERGE_CANCELLED and calls[3].remaining==0)
assert(generated_calls==2)
assert(not api.compare_block_status({x=32,y=0,z=0},'emerging'))
assert(api.compare_block_status({x=32,y=0,z=0},'unknown'))
local loaded=api.get_loaded_blocks()
assert(#loaded==2 and loaded[1].x==0 and loaded[2].x==1)
assert(#api.get_active_blocks()==0)
-- An existing block results in FROM_MEMORY and never calls mapgen.
local second={}
api.emerge_area(n,n,function(b,a,remaining)
 second[#second+1]={b.x,a,remaining}
end)
rt:step(.1)
assert(#second==1 and second[1][1]==1 and
 second[1][2]==api.EMERGE_FROM_MEMORY and second[1][3]==0)
assert(generated_calls==2)
-- A bad disk image reports ERRORED instead of claiming the area exists.
fs.files[store:path('3,0,0')]='BROKEN SAVE\n'
-- An external file appeared after a cached miss: host invalidates that key.
store:invalidate('3,0,0')
local failure={}
api.emerge_area({x=48,y=0,z=0},{x=48,y=0,z=0},
 function(b,a,remaining) failure[#failure+1]={a,remaining} end)
rt:step(.1)
assert(#failure==1 and failure[1][1]==api.EMERGE_ERRORED and
 failure[1][2]==0)
assert(api.get_node({x=48,y=0,z=0}).name=='ignore')
-- Real player activation of generated block must not run old LBMs.
local playerpos={x=0,y=0,z=0}
rt:connectPlayer({get_player_name=function() return 'Alice' end,
 get_pos=function() return playerpos end})
rt:step(.1)
assert(api.compare_block_status({x=0,y=0,z=0},'active'))
assert(not api.compare_block_status({x=0,y=0,z=0},'loaded'))
assert(#api.get_active_blocks()==1 and one_shots==0)
assert(api.compare_block_status({x=16,y=0,z=0},'loaded'))
local before=generated_calls
assert(not pcall(api.emerge_area,{x=0.5,y=0,z=0},{x=16,y=0,z=0}))
assert(not pcall(api.emerge_area,{x=-31000,y=-31000,z=0},
 {x=31000,y=31000,z=0}))
assert(not pcall(api.emerge_area,{x=0,y=0,z=0},{x=0,y=0,z=0},true))
assert(generated_calls==before)
-- Headless mode (without streaming) retains historical sparse implicit air.
local legacy=Runtime.new()
assert(legacy.api.get_node({x=0,y=0,z=0}).name=='air')
assert(legacy.api.get_node_or_nil({x=0,y=0,z=0}).name=='air')
local legacy_result
legacy.api.emerge_area({x=0,y=0,z=0},nil,
 function(_,action) legacy_result=action end)
legacy:step(.1)
assert(legacy_result==legacy.api.EMERGE_CANCELLED)
print('LUA ENGINE MAPBLOCK EMERGE AREA PASS')
