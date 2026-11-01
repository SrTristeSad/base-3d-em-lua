package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Engine=require('core.runtime')
local api=Engine.new().api
local original={
 enchantments={sharpness=4,unbreaking=2},
 flags={active=true,disabled=false},count=7,
 quote='A "quoted"\nline',negative=-1.25,slots={[1]='first',[3]='third'},
}
local bytes=api.serialize(original)
assert(type(bytes)=='string' and bytes:sub(1,7)=='return ')
local restored=api.deserialize(bytes)
assert(restored.enchantments.sharpness==4)
assert(restored.enchantments.unbreaking==2)
assert(restored.flags.active and restored.flags.disabled==false)
assert(restored.count==7 and restored.negative==-1.25)
assert(restored.quote==original.quote)
assert(restored.slots[1]=='first' and restored.slots[3]=='third')
assert(api.deserialize('')==nil)
assert(api.deserialize('return nil')==nil)
assert(api.deserialize('return false')==false)
assert(api.deserialize('return {["power"]=3;["luck"]=true,}') .luck==true)
assert(api.deserialize('return {"line\\n", "quote\\""}')[1]=='line\n')
assert(api.deserialize('return os.execute("echo broken")')==nil)
assert(api.deserialize('return {x=1}; error("injected")')==nil)
assert(api.deserialize('return { [1] = function() end }')==nil)
assert(api.deserialize('return { missing = { "brace" }')==nil)
local cyclic={}
cyclic.itself=cyclic
assert(not pcall(api.serialize,cyclic),'cyclic table must reject')
assert(not pcall(api.serialize,0/0),'nan must reject')
assert(not pcall(api.serialize,function() end),'functions cannot serialize')
print('LUA ENGINE SERIALIZATION PASS')
