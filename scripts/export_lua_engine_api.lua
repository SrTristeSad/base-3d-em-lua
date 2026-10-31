-- Exports actual runtime API keys, not documentation guesses.
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local runtime=require('core.runtime').new()
local names={}
for k,v in pairs(runtime.api) do
 if type(v)=='function' or type(v)=='table' then names[#names+1]=k end
end
table.sort(names)
for _,name in ipairs(names) do print(name) end
