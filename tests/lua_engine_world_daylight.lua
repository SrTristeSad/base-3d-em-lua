-- Runtime Luanti time-of-day controls with monotonic timers and safe saves.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Storage=require('core.storage')
local function near(a,b)
 assert(type(a)=='number' and type(b)=='number' and
  math.abs(a-b)<1e-9,
  ('timeofday mismatch: %.17g / %.17g'):format(a,b))
end
local function fsnew()
 local fs={files={}}
 function fs.read(p) return fs.files[p],fs.files[p] and nil or 'not found' end
 function fs.write_atomic(p,data) fs.files[p]=data;return true end
 return fs
end
local rt=Runtime.new({active_block_range=0})
local api=rt.api
near(api.get_timeofday(),0)
assert(api.get_day_count()==0)
assert(not pcall(api.set_timeofday,-.1))
assert(not pcall(api.set_timeofday,1.1))
assert(not pcall(api.set_timeofday,0/0))
assert(not pcall(api.set_timeofday,'noon'))
rt:step(600)
near(api.get_timeofday(),.5)
api.set_timeofday(.75)
near(api.get_timeofday(),.75)
assert(api.get_gametime()==600)
rt:step(150)
near(api.get_timeofday(),.875)
assert(api.get_day_count()==0)
local saved=Storage.encode(rt.map)
assert(saved:find('\nD ',1,true),'daylight offset must persist')
local image=Storage.decode(saved)
local reload=Runtime.new({active_block_range=0})
reload:replaceMap(image)
near(reload.api.get_timeofday(),.875)
assert(reload.api.get_gametime()==750)
reload:step(1200)
near(reload.api.get_timeofday(),.875)
assert(reload.api.get_day_count()==1)
reload.api.set_timeofday(1)
near(reload.api.get_timeofday(),0)
local reset=Storage.decode(Storage.encode(reload.map))
local again=Runtime.new({active_block_range=0})
again:replaceMap(reset)
near(again.api.get_timeofday(),0)
for _,bad in ipairs({
 'D -0.1','D 1','D 2','D nan','D garbage',
 'D 0.2\nD 0.4'
}) do
 assert(not pcall(Storage.decode,'LUAENGINE 1\n'..bad..'\nEND\n'),
  'invalid time of day record was accepted')
end
-- Segmented world daylight offset belongs only to world.map; other
-- MapBlock image files remain free of global time-of-day metadata.
local fs=fsnew()
local rt2=Runtime.new({active_block_range=0})
local store=rt2:attachMapBlockStore(fs,'daylight')
rt2.map:set_node({x=0,y=0,z=0},{name='test:stone'})
rt2.map.last_active['0,0,0']=0
rt2.api.set_timeofday(.32)
rt2:step(60)
assert(store:flush())
local world=fs.files['daylight/world.map']
local block=fs.files[store:path('0,0,0')]
assert(world:find('\nD ',1,true))
assert(not block:find('\nD ',1,true))
local loaded=Runtime.new({active_block_range=0})
local loadstore=loaded:attachMapBlockStore(fs,'daylight')
near(loaded.api.get_timeofday(),.37)
assert(loadstore:emerge('0,0,0'))
assert(loaded.api.get_gametime()==60)
assert(loaded.api.get_day_count()==0)
print('LUA ENGINE PERSISTED TIME-OF-DAY AND DAY COUNT PASS')
