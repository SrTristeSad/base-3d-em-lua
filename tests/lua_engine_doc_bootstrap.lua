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
rt:emit('shutdown')
assert(fired==1,'shutdown event must fire registered callbacks')
rt.api.register_privilege('test:example',{
 description='Example privilege',give_to_singleplayer=false})
assert(rt.api.registered_privileges['test:example'].description=='Example privilege')
assert(not pcall(rt.api.register_privilege,'test:example',{}),
 'duplicate privilege definition must fail')
local runner=Environment.new(rt)
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
end
report[#report+1]=('- Original Lua files executed: %d'):format(runner.read_count)
report[#report+1]='- The mcl_core module is NOT marked as loaded by this probe.'
local output=table.concat(report,'\n')..'\n'
io.write(output)
if arg and arg[2] then
 local f=assert(io.open(arg[2],'wb'));f:write(output);f:close()
end
