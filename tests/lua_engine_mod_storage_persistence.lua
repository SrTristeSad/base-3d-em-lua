-- Phase 56: Luanti per-mod StorageRef data must survive runtime reload,
-- preserve mod boundaries and never execute saved Lua code.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local ModStorage=require('core.modstorage')
local ModLoader=require('core.modloader')
local function eq(a,b,label)
 assert(a==b,(label or 'value')..': '..tostring(a)..' != '..tostring(b))
end
local fs={files={},writes=0}
function fs.read(path) return fs.files[path] end
function fs.write(path,data)
 fs.writes=fs.writes+1
 fs.files[path]=data
 return true
end
local path='worlds/voxelibre/mod_storage.dat'
local settings={mod_storage_path=path,mod_storage_fs=fs}
local rt=Runtime.new(settings)
assert(next(rt.mod_storage)==nil)
local api=rt.api
assert(not pcall(api.get_mod_storage),
 'get_mod_storage must require a valid loading mod')
local order={}
local fake_mods={
 {name='alpha',path='mods/alpha'},
 {name='beta',path='mods/beta',depends={'alpha'}}}
rt.opts.executeMod=function(filename,name)
 local ref=api.get_mod_storage()
 assert(ref==api.get_mod_storage(),'same mod StorageRef identity')
 order[#order+1]=name
 eq(ref:get_string('shared'),'')
 if name=='alpha' then
  ref:set_string('shared','α beta unicode')
  ref:set_int('counter',-42)
  ref:set_float('rate',1.25)
  ref:set_string('removed','temporary')
  ref:set_string('removed','')
  eq(ref:get_int('counter'),-42)
  eq(ref:get_float('rate'),1.25)
  assert(not ref:contains('removed'))
 else
  ref:set_string('shared','beta only')
  ref:set_int('counter',13)
 end
end
local ok,results=ModLoader.load(rt,ModLoader.plan(fake_mods))
assert(ok and #results==2)
eq(table.concat(order,','),'alpha,beta')
local alpha,beta=rt.mod_storage.alpha,rt.mod_storage.beta
eq(alpha:get_string('shared'),'α beta unicode')
eq(beta:get_string('shared'),'beta only')
eq(alpha:get_string('unknown'),'')
eq(alpha:get_int('unknown'),0)
eq(alpha:get_float('unknown'),0)
assert(alpha:get_keys()[1]=='counter')
local copied=alpha:to_table()
copied.fields.shared='changed elsewhere'
eq(alpha:get_string('shared'),'α beta unicode',
 'to_table must not expose mod storage internal fields')
local other=ModStorage.new()
other:from_table(alpha:to_table())
assert(other:equals(alpha) and alpha:equals(other))
other:set_string('shared','modified')
assert(not alpha:equals(other))
assert(other:from_table(nil))
eq(other:get_string('shared'),'')
assert(other:from_table({fields={hello='world'}}))
eq(other:get_string('hello'),'world')
assert(not pcall(alpha.set_int,alpha,'invalid',2147483648))
assert(not pcall(alpha.set_float,alpha,'invalid',math.huge))
assert(not pcall(alpha.set_string,alpha,'invalid',true))
assert(not pcall(alpha.from_table,alpha,{fields={illegal=42}}))
eq(alpha:get_string('shared'),'α beta unicode',
 'invalid from_table must never partially overwrite storage')
local encoded=ModStorage.encode(rt.mod_storage)
assert(encoded:sub(1,23)=='LUAENGINE MODSTORAGE 1\n')
eq(ModStorage.encode(rt.mod_storage),encoded,
 'mod storage serialization must be deterministic')
local decoded=ModStorage.decode(encoded)
eq(decoded.alpha.shared,'α beta unicode')
eq(decoded.beta.shared,'beta only')
decoded.alpha.shared='outside'
eq(alpha:get_string('shared'),'α beta unicode')
local bads={
 'return os.execute("evil")',
 'LUAENGINE MODSTORAGE 1\nreturn os.execute("evil")',
 'LUAENGINE MODSTORAGE 1\nreturn {[12]={}}',
 'LUAENGINE MODSTORAGE 1\nreturn {bad={[1]="invalid"}}',
 'LUAENGINE MODSTORAGE 1\nreturn {alpha={x=123}}',
 'LUAENGINE MODSTORAGE 1\nreturn {alpha="bad"}',
 'LUAENGINE MODSTORAGE 1\nreturn {alpha={bad=false}}',
 'LUAENGINE MODSTORAGE 1\nreturn {alpha={x="a"',
}
for _,bad in ipairs(bads) do
 local before=ModStorage.encode(rt.mod_storage)
 assert(not pcall(rt.restoreModStorage,rt,bad))
 eq(ModStorage.encode(rt.mod_storage),before,
  'malformed storage must leave all mods unchanged')
end
-- Save after registered on_shutdown callbacks; a real Luanti mod can
-- update its world data during shutdown without losing the final value.
rt.api.register_on_shutdown(function()
 alpha:set_string('saved_on_shutdown','yes')
 beta:set_int('counter',99)
end)
assert(rt:shutdown())
eq(fs.writes,1)
assert(not rt:shutdown())
eq(fs.writes,1)
local restarted=Runtime.new(settings)
assert(restarted.mod_storage.alpha and restarted.mod_storage.beta,
 'world metadata must load before original mod init')
local order2={}
restarted.opts.executeMod=function(filename,name)
 local ref=restarted.api.get_mod_storage()
 order2[#order2+1]=name
 if name=='alpha' then
  eq(ref:get_string('shared'),'α beta unicode')
  eq(ref:get_string('saved_on_shutdown'),'yes')
  eq(ref:get_int('counter'),-42)
 else
  eq(ref:get_string('shared'),'beta only')
  eq(ref:get_int('counter'),99)
 end
end
assert(ModLoader.load(restarted,ModLoader.plan(fake_mods)))
eq(table.concat(order2,','),'alpha,beta')
local handle=restarted.mod_storage.alpha
-- Explicit world restore retains handles referenced by already loaded mods.
alpha:set_string('restored','through older mod')
restarted:restoreModStorage(ModStorage.encode(rt.mod_storage))
assert(restarted.mod_storage.alpha==handle)
eq(handle:get_string('shared'),'α beta unicode')
local before=ModStorage.encode(restarted.mod_storage)
local corrupt=fs.files[path]
fs.files[path]='LUAENGINE MODSTORAGE 1\nreturn {[13]="oops"}'
local loaded,err=restarted:loadModStorage(path,fs)
assert(loaded==nil and type(err)=='string')
eq(ModStorage.encode(restarted.mod_storage),before)
fs.files[path]=corrupt
-- Missing/independent worlds never inherit another world's mod state.
local elsewhere=Runtime.new({mod_storage_path='worlds/other/mod_storage.dat',
 mod_storage_fs=fs})
assert(next(elsewhere.mod_storage)==nil)
local empty=Runtime.new()
local missing,reason=empty:loadModStorage('missing',fs)
assert(missing==nil and reason=='not found')
-- Malformed storage in a configured world aborts boot BEFORE any mod loads.
fs.files['corrupt']='LUAENGINE MODSTORAGE 1\nreturn false'
assert(not pcall(Runtime.new,{mod_storage_path='corrupt',
 mod_storage_fs=fs}))
-- Failure to save must never pretend that world mod metadata was stored.
local failed=Runtime.new({mod_storage_path='cannot-write',
 mod_storage_fs={read=function()return nil end,
  write=function()return false,'disk full' end}})
failed.current_mod='dummy'
failed.api.get_mod_storage():set_string('key','progress')
failed.current_mod=nil
assert(not pcall(failed.shutdown,failed))
assert(not failed.shut_down)
print('LUA ENGINE PHASE 56 VOXELIBRE WORLD MOD STORAGE PASS')
