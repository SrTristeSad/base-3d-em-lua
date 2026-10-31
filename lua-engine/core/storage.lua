-- Portable and deterministic save format. No load(), eval or deserialization code.
-- Format LUAENGINE 1, one node per line, followed by metadata and timers.
local Storage={}
local Map=require('core.map')
local function enc(value)
 if tostring(value)=='' then return '#' end
 return tostring(value):gsub('([^%w%._~%-])',function(c)
  return ('%%%02X'):format(c:byte())
 end)
end
local function dec(value)
 if value=='#' then return '' end
 return value:gsub('%%(%x%x)',function(h)
  return string.char(tonumber(h,16))
 end)
end
local function coords(k)
 local x,y,z=k:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
 return tonumber(x),tonumber(y),tonumber(z)
end
local function keys(t)
 local list={}
 for k in pairs(t) do list[#list+1]=k end
 table.sort(list)
 return list
end
function Storage.encode(map)
 assert(map and map.nodes and map.metadata and map.timers)
 local lines={'LUAENGINE 1'}
 for _,k in ipairs(keys(map.nodes)) do
  local node=map.nodes[k]
  local x,y,z=coords(k)
  lines[#lines+1]=('N %d %d %d %s %d %d'):format(
   x,y,z,enc(node.name),node.param1,node.param2)
 end
 for _,k in ipairs(keys(map.metadata)) do
  local x,y,z=coords(k)
  for _,field in ipairs(keys(map.metadata[k].fields)) do
   lines[#lines+1]=('M %d %d %d %s %s'):format(
    x,y,z,enc(field),enc(map.metadata[k].fields[field]))
  end
 end
 for _,k in ipairs(keys(map.timers)) do
  local x,y,z=coords(k)
  local t=map.timers[k]
  lines[#lines+1]=('T %d %d %d %.17g %.17g'):format(
   x,y,z,t.timeout,t.elapsed)
 end
 lines[#lines+1]='END'
 return table.concat(lines,'\n')..'\n'
end
function Storage.decode(data)
 assert(type(data)=='string' and #data<=16*1024*1024,
  'save too large or not a string')
 local map=Map.new()
 local lineNo=0
 local finished=false
 for line in (data..'\n'):gmatch('(.-)\n') do
  if line~='' then
   lineNo=lineNo+1
   if lineNo==1 then
    assert(line=='LUAENGINE 1','unsupported save header')
   elseif line=='END' then
    finished=true
   else
    assert(not finished,'data after END')
    local tag,x,y,z,rest=line:match('^([NMT]) (%-?%d+) (%-?%d+) (%-?%d+) (.+)$')
    assert(tag,'malformed save at line '..lineNo)
    local p={x=tonumber(x),y=tonumber(y),z=tonumber(z)}
    if tag=='N' then
     local name,p1,p2=rest:match('^(%S+) (%d+) (%d+)$')
     assert(name,'invalid node save')
     map:set_node(p,{name=dec(name),param1=tonumber(p1),param2=tonumber(p2)})
    elseif tag=='M' then
     local field,value=rest:match('^(%S+) (%S+)$')
     assert(field,'invalid metadata save')
     map:get_meta(p):set_string(dec(field),dec(value))
    elseif tag=='T' then
     local timeout,elapsed=rest:match('^(%S+) (%S+)$')
     timeout,elapsed=tonumber(timeout),tonumber(elapsed)
     assert(timeout and elapsed and timeout>0 and elapsed>=0,'invalid timer')
     map:get_timer(p):set(timeout,elapsed)
    end
   end
  end
 end
 assert(finished,'save is incomplete')
 map.modified={}
 return map
end
function Storage.save(map,path,fs)
 assert(fs and type(fs.write)=='function','filesystem.write required')
 return fs.write(path,Storage.encode(map))
end
function Storage.load(path,fs)
 assert(fs and type(fs.read)=='function','filesystem.read required')
 local data=fs.read(path)
 if not data then return nil,'not found' end
 local ok,map=pcall(Storage.decode,data)
 if not ok then return nil,map end
 return map
end
return Storage
