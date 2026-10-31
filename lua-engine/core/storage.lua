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
  local inv=map.metadata[k].inventory
  if inv then
   for _,list in ipairs(keys(inv.lists)) do
    local width=inv:get_width(list)
    lines[#lines+1]=('L %d %d %d %s %d %d'):format(
     x,y,z,enc(list),inv:get_size(list),width)
    for index=1,inv:get_size(list) do
     local stack=inv:get_stack(list,index)
     if not stack:is_empty() then
      lines[#lines+1]=('I %d %d %d %s %d %s %d %d'):format(
       x,y,z,enc(list),index,enc(stack:get_name()),
       stack:get_count(),stack:get_wear())
      local meta=stack:get_meta():to_table().fields
      for _,field in ipairs(keys(meta)) do
       lines[#lines+1]=('F %d %d %d %s %d %s %s'):format(
        x,y,z,enc(list),index,enc(field),enc(meta[field]))
      end
     end
    end
   end
  end
 end
 -- Optional generated-chunk markers prevent overwriting mined blocks on reload.
 for _,k in ipairs(keys(map.generatedChunks or {})) do
  local cx,cz=k:match('^(%-?%d+),(%-?%d+)$')
  assert(cx and cz,'invalid generated chunk key')
  local seed=map.generatedChunks[k]
  assert(type(seed)=='number' and seed==math.floor(seed)
   and seed>=0 and seed<=2147483646,'invalid generated chunk seed')
  lines[#lines+1]=('G %d %d %d'):format(tonumber(cx),tonumber(cz),seed)
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
    local cx,cz,seed=line:match('^G (%-?%d+) (%-?%d+) (%d+)$')
    if cx then
     cx,cz,seed=tonumber(cx),tonumber(cz),tonumber(seed)
     assert(cx>=-1936 and cx<=1936 and cz>=-1936 and
      cz<=1936 and seed<=2147483646,'invalid generated chunk marker')
     local chunk=cx..','..cz
     assert(map.generatedChunks[chunk]==nil,'duplicate generated chunk')
     map.generatedChunks[chunk]=seed
    else
     local tag,x,y,z,rest=line:match('^([NMTLIF]) (%-?%d+) (%-?%d+) (%-?%d+) (.+)$')
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
    elseif tag=='L' then
     local list,size,width=rest:match('^(%S+) (%d+) (%d+)$')
     size,width=tonumber(size),tonumber(width)
     assert(list and size and size<=65535 and width and width<=65535,
      'invalid inventory list')
     local inv=map:get_meta(p):get_inventory()
     inv:set_size(dec(list),size)
     inv:set_width(dec(list),width)
    elseif tag=='I' then
     local list,index,name,count,wear=
      rest:match('^(%S+) (%d+) (%S+) (%d+) (%d+)$')
     index,count,wear=tonumber(index),tonumber(count),tonumber(wear)
     assert(list and index and count and wear,'invalid inventory item')
     local inv=map:get_meta(p):get_inventory()
     assert(inv:set_stack(dec(list),index,{
      name=dec(name),count=count,wear=wear
     }),'item without inventory list')
    elseif tag=='F' then
     local list,index,field,value=rest:match('^(%S+) (%d+) (%S+) (%S+)$')
     index=tonumber(index)
     assert(list and index and field and value,'invalid item metadata')
     local inv=map:get_meta(p):get_inventory()
     local stack=inv:get_stack(dec(list),index)
     assert(not stack:is_empty(),'metadata without item')
     stack:get_meta():set_string(dec(field),dec(value))
     inv:set_stack(dec(list),index,stack)
    elseif tag=='T' then
     local timeout,elapsed=rest:match('^(%S+) (%S+)$')
     timeout,elapsed=tonumber(timeout),tonumber(elapsed)
     assert(timeout and elapsed and timeout>0 and elapsed>=0,'invalid timer')
     map:get_timer(p):set(timeout,elapsed)
    end
    end -- optional G record
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
