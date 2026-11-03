-- Executable CLI for the full original VoxeLibre mod manifest.
-- python3 scripts/boot_voxelibre.py generates the manifest safely.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local ModLoader=require('core.modloader')
local Bootstrap=require('core.gamebootstrap')
local manifest_path=assert(arg[1],'expected manifest path')
local game_root=assert(arg[2],'expected game root')
local fail_fast=arg[3]=='fail-fast'
local function read(path)
 local file,err=io.open(path,'rb')
 if not file then return nil,err end
 local data=file:read('*a')
 file:close()
 return data
end
local function discover(manifest_file)
 local file=assert(io.open(manifest_file,'rb'))
 local mods={}
 local seen={}
 for line in file:lines() do
  local name,dir=line:match('^([%w_%-]+)\t([^\t\r\n]+)$')
  assert(name and dir,'invalid full-game mod manifest line')
  assert(not seen[name],'duplicate mod name: '..name)
  seen[name]=true
  local conf=assert(read(dir..'/mod.conf'))
  local spec=ModLoader.parse(conf,read(dir..'/depends.txt'))
  assert(not spec.name or spec.name==name,
   'manifest name differs from mod.conf name: '..name)
  spec.name=name
  spec.path=dir
  mods[#mods+1]=spec
 end
 file:close()
 assert(#mods>0,'full-game manifest contains no mods')
 return mods
end
local manifest=discover(manifest_path)
local runtime=Runtime.new({
 mapgen={seed=42,mg_name='v7',chunksize=5,mapgen_limit=31000},
 settings={mcl_keepInventory='false',mcl_node_particles='medium'},
 game_info={path=game_root,title='VoxeLibre'},
 worldpath='worlds/lua-voxelibre'
})
local ok,report=Bootstrap.load(runtime,manifest,{
 continue_on_error=not fail_fast
})
print(('VOXELIBRE BOOT: discovered=%d attempted=%d passed=%d failed=%d executed_lua=%d complete=%s')
 :format(report.discovered,#report.results,report.passed,
 report.failed,report.executed_files,tostring(ok)))
for _,result in ipairs(report.results) do
 if result.ok then
  print('BOOT OK  '..result.name)
 else
  print('BOOT FAIL '..result.name..': '..result.error:gsub('\n',' | '))
 end
end
if not ok then
 print('BOOT INCOMPLETE: missing Luanti functionality must be implemented; no partial boot is called playable.')
end
os.exit(ok and 0 or 1)
