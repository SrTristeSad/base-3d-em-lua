-- Diagnostic bootstrap for original VoxeLibre documentation modules.
-- Runs independently of the successful 14-mod smoke suite.
-- Failures are reported, not disguised with a simulated doc table.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local Environment=require('core.modenvironment')
local root=(arg and arg[1] or 'games/voxelibre'):gsub('/$','')
local paths={
 doc=root..'/mods/HELP/doc/doc',
 doc_items=root..'/mods/HELP/doc/doc_items',
 mcl_core=root..'/mods/ITEMS/mcl_core',
}
for name,path in pairs(paths) do
 local f=assert(io.open(path..'/mod.conf','rb'),
  'missing upstream mod.conf for '..name..': '..path)
 f:close()
end
local rt=Engine.new({settings={},mapgen={seed=42,mg_name='v7'},
 game_info={path=root,title='VoxeLibre'},modpaths=paths})
local fired=0
rt.api.register_on_shutdown(function() fired=fired+1 end)
assert(#rt.callbacks.shutdown==1)
assert(rt:shutdown()==true)
assert(rt:shutdown()==false)
assert(fired==1,'shutdown callbacks must execute exactly once')
rt.api.register_privilege('test:example',{
 description='Example privilege',give_to_singleplayer=false})
assert(rt.api.registered_privileges['test:example'].description=='Example privilege')
assert(not pcall(rt.api.register_privilege,'test:example',{}),
 'duplicate privilege definition must fail')
-- Node punches must notify without mining or removing blocks.
rt.api.register_node('probe:punch_block',{description='Punch target'})
local pos={x=2,y=3,z=4}
rt.api.set_node(pos,{name='probe:punch_block'})
local punched=0
rt.api.register_on_punchnode(function(p,node,puncher,pointed)
 assert(p.x==2 and p.y==3 and p.z==4)
 assert(node.name=='probe:punch_block')
 assert(puncher==nil and pointed.type=='node')
 punched=punched+1
end)
rt:punchNode(pos,nil,{type='node',under=pos})
assert(punched==1 and rt.api.get_node(pos).name=='probe:punch_block',
 'punch must not dig or replace node')
-- Real host-managed players: lookup, deterministic enumeration and lifecycle.
local joined,left=0,0
rt.api.register_on_joinplayer(function(player) joined=joined+1 end)
rt.api.register_on_leaveplayer(function(player) left=left+1 end)
local testplayer={get_player_name=function() return 'ProbePlayer' end}
assert(#rt.api.get_connected_players()==0)
rt:connectPlayer(testplayer)
assert(rt.players['ProbePlayer']==testplayer,'host registry did not retain player')
assert(rt.api.get_player_by_name('ProbePlayer')==testplayer,
 'get_player_by_name lookup failed for attached player')
assert(rt.api.get_connected_players()[1]==testplayer)
assert(joined==1)
assert(rt:disconnectPlayer('ProbePlayer')==true)
assert(rt:disconnectPlayer('ProbePlayer')==false)
assert(left==1 and #rt.api.get_connected_players()==0)
local crafted,eaten=0,0
rt.api.register_on_craft(function() crafted=crafted+1 end)
rt.api.register_on_item_eat(function() eaten=eaten+1 end)
rt:emit('on_craft')
rt:emit('on_item_eat')
assert(crafted==1 and eaten==1)
-- Real item use: callback dispatch, stack consumption and player HP.
rt.api.register_craftitem('probe:fruit',{description='Fruit'})
rt.api.register_craftitem('probe:bowl',{description='Bowl'})
local player_hp=8
local hp_reason
local consumer={
 get_hp=function() return player_hp end,
 set_hp=function(_,n,reason) player_hp=n;hp_reason=reason end,
}
local fruit=rt.api.ItemStack('probe:fruit 2')
local eat=rt.api.item_eat(3)
assert(eat(fruit,nil)==nil and fruit:get_count()==2)
assert(eat(fruit,consumer)==nil)
assert(fruit:get_count()==1 and player_hp==11)
assert(hp_reason.custom_type=='__builtin:item_eat')
local last=rt.api.ItemStack('probe:fruit 1')
rt.api.item_eat(1,'probe:bowl')(last,consumer)
assert(last:get_name()=='probe:bowl' and last:get_count()==1)
assert(player_hp==12)
local cancelled=rt.api.ItemStack('probe:fruit 1')
rt.api.register_on_item_eat(function() return cancelled end)
local hp_before=player_hp
assert(eat(cancelled,consumer)==cancelled)
assert(cancelled:get_count()==1 and player_hp==hp_before,
 'an on_item_eat override must prevent default consumption')
-- Liquid callbacks receive the changed-node list without inventing flow.
local transformed
rt.api.register_on_liquid_transformed(function(list) transformed=list end)
local changed={{x=4,y=5,z=6}}
rt:liquidTransformed(changed)
assert(transformed and transformed[1].x==4 and transformed[1].y==5)
changed[1].x=99
assert(transformed[1].x==4,'liquid callback must receive an independent snapshot')
local runner=Environment.new(rt)
local split=runner.globals.string.split
local parts=split('pickaxey,shovely,axey',',')
assert(#parts==3 and parts[1]=='pickaxey' and parts[3]=='axey')
parts=split('one,,three',',',true)
assert(#parts==3 and parts[2]=='')
parts=split('one,two,three',',',false,1)
assert(#parts==2 and parts[2]=='two,three')
-- Permission regression: no arbitrary host file reads or writes.
local file,err=runner.globals.io.open('lua-engine/main.lua','r')
assert(file==nil and type(err)=='string','host file read must be denied')
file,err=runner.globals.io.open(rt.api.get_worldpath()..'/doc.mt','w')
assert(file==nil and type(err)=='string','documentation write must be denied')
rt.opts.executeMod=function(path,name) return runner:executeMod(path,name) end
local report={'# Original documentation module bootstrap probe','',
 'This is an isolated diagnostic, NOT an additional verified gameplay module.',
 'The original VoxeLibre source files are executed unchanged.',''}
local loaded={}
for _,name in ipairs({'doc','doc_items'}) do
 local ok,err=pcall(rt.loadMod,rt,name,paths[name])
 assert(rt.current_mod==nil,'mod context leaked: '..name)
 report[#report+1]=('- %s: **%s**'):format(name,ok and 'loaded' or 'blocked')
 if ok then
  loaded[#loaded+1]=name
 else
  report[#report+1]='  - First error: '..tostring(err):gsub('[\r\n]+',' '):sub(1,800)
  break
 end
end
if #loaded==2 then
 local doc=runner.globals.doc
 assert(type(doc)=='table' and type(doc.sub)=='table'
  and type(doc.sub.items)=='table'
  and type(doc.sub.items.temp.build)=='string',
  'documentation source loaded without the expected upstream templates')
 report[#report+1]='- Real item documentation templates: available'
 rt:finishMods()
 assert(type(doc.data.categories.nodes)=='table',
  'doc_items must create the original nodes help category')
 assert(doc.data.categories.nodes.entries['probe:punch_block'],
  'upstream doc_items must enumerate a registered runtime node')
 report[#report+1]='- Original on_mods_loaded help-page generation: verified'
end
report[#report+1]=('- Original Lua files executed: %d'):format(runner.read_count)
report[#report+1]='- The mcl_core module is NOT marked as loaded by this probe.'
local output=table.concat(report,'\n')..'\n'
io.write(output)
if arg and arg[2] then
 local f=assert(io.open(arg[2],'wb'));f:write(output);f:close()
end
