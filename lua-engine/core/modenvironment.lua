-- Explicit mod execution environment, separate from the host Lua globals.
-- Smoke-test launcher only, NOT a security sandbox for untrusted Lua code.
-- Native game mods may use APIs that are deliberately absent here.
local Vector=require('core.vector')
local Bitops=require('core.bitops')
local PcgRandom=require('core.pcgrandom')
local PseudoRandom=require('core.pseudorandom')
local Voxel=require('core.voxel')
local ValueNoise=require('core.valuenoise')
local ModEnvironment={}
ModEnvironment.__index=ModEnvironment

local function shallow(t)
 local out={}
 for k,v in pairs(t or {}) do out[k]=v end
 return out
end

local function normal(path)
 assert(type(path)=='string' and path~='','invalid mod filename')
 path=path:gsub('\\','/')
 local rooted=path:sub(1,1)=='/'
 local components={}
 for component in path:gmatch('[^/]+') do
  assert(component~='..','relative parent path forbidden')
  if component~='.' then components[#components+1]=component end
 end
 return (rooted and '/' or '')..table.concat(components,'/')
end

local function within(file,dir)
 return file:sub(1,#dir+1)==dir..'/'
end

local function stdlib(runtime)
 local std={
  assert=assert,error=error,collectgarbage=nil,
  ipairs=ipairs,pairs=pairs,next=next,select=select,
  tonumber=tonumber,tostring=tostring,type=type,
  pcall=pcall,xpcall=xpcall,rawequal=rawequal,
  rawget=rawget,rawset=rawset,setmetatable=setmetatable,
  getmetatable=getmetatable,unpack=unpack or table.unpack,
  math=shallow(math),table=shallow(table),string=shallow(string),
  coroutine=shallow(coroutine),
  os={time=os.time,date=os.date,difftime=os.difftime,clock=os.clock},
  print=function(...)
   local args={}
   for i=1,select('#',...) do args[#args+1]=tostring(select(i,...)) end
   runtime.api.log('action',table.concat(args,'\t'))
  end,
 }
 if utf8 then std.utf8=shallow(utf8) end
 if bit32 then std.bit32=shallow(bit32) end
 std.bit=bit and shallow(bit) or Bitops
 return std
end

local function settings_file(filename)
 assert(type(filename)=='string','Settings requires a filename')
 local fields={}
 local file=io.open(filename,'rb')
 if file then
  for line in file:lines() do
   local k,v=line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
   if k then fields[k]=v end
  end
  file:close()
 end
 return {
  get=function(_,key) return fields[key] end,
  get_bool=function(_,key,default)
   local x=fields[key]
   if x==nil then return default end
   if x=='true' or x=='1' then return true end
   if x=='false' or x=='0' then return false end
   return default
  end,
  get_num=function(_,key,default) return tonumber(fields[key]) or default end
 }
end
local function recursive_copy(value,seen)
 if type(value)~='table' then return value end
 seen=seen or {}
 if seen[value] then return seen[value] end
 local dest={}
 seen[value]=dest
 for k,v in pairs(value) do
  dest[recursive_copy(k,seen)]=recursive_copy(v,seen)
 end
 return dest
end

function ModEnvironment.new(runtime)
 assert(type(runtime)=='table' and type(runtime.api)=='table',
  'a runtime is required')
 local self=setmetatable({runtime=runtime,read_count=0,files={}},ModEnvironment)
 local env=stdlib(runtime)
 env.core=runtime.api
 env.minetest=runtime.api
 env.vector=Vector
 env.ItemStack=runtime.api.ItemStack
 env.PcgRandom=PcgRandom.new
 env.PseudoRandom=PseudoRandom.new
 env.VoxelArea=Voxel.VoxelArea
 env.ValueNoise=ValueNoise.global_scalar
 env.PerlinNoise=ValueNoise.global_scalar
 env.ValueNoiseMap=ValueNoise.global_map
 env.PerlinNoiseMap=ValueNoise.global_map
 env.DIR_DELIM=package.config:sub(1,1)
 env.Settings=settings_file
 env.table.copy=recursive_copy
 -- Luanti string.split used by original group recipe documentation.
 env.string.split=function(value,separator,include_empty,max_splits,separator_is_pattern)
  assert(type(value)=='string','string.split expects a string')
  separator=separator or ','
  assert(type(separator)=='string' and separator~='',
   'string.split requires a nonempty separator')
  local result={}
  local at,count=1,0
  local limit=max_splits or -1
  assert(type(limit)=='number','invalid split limit')
  while limit<0 or count<limit do
   local first,last=value:find(separator,at,not separator_is_pattern)
   if not first then break end
   assert(last>=first,'zero-width string.split separator is unsupported')
   local piece=value:sub(at,first-1)
   if include_empty or piece~='' then result[#result+1]=piece end
   at=last+1
   count=count+1
  end
  local tail=value:sub(at)
  if include_empty or tail~='' then result[#result+1]=tail end
  return result
 end
 env.table.indexof=function(tbl,item)
  for i,v in ipairs(tbl) do if v==item then return i end end
  return -1
 end
 -- Luanti's table.pairs_by_keys is used directly by VoxeLibre formspecs.
 env.table.pairs_by_keys=function(tbl,comparison)
  local keys={}
  for key in pairs(tbl) do keys[#keys+1]=key end
  table.sort(keys,comparison)
  local i=0
  return function()
   i=i+1
   local key=keys[i]
   if key~=nil then return key,tbl[key] end
  end
 end
 -- Restrict legacy documentation reads to its world-local doc.mt file.
 -- This is compatibility plumbing, not a general-purpose io sandbox.
 env.io={
  open=function(path,mode)
   assert(type(path)=='string','io.open expects a path')
   if path~=runtime.api.get_worldpath()..'/doc.mt' then
    return nil,'file access outside documentation save is disabled'
   end
   if mode~='r' and mode~='rb' then
    return nil,'write access is disabled in this bootstrap'
   end
   return io.open(path,mode)
  end,
  close=function(file) return file:close() end,
 }
 env._G=env
 env.dofile=function(path) return self:runfile(path) end
 self.globals=env
 return self
end

function ModEnvironment:runfile(path)
 local filename=normal(path)
 local allowed=false
 for _,root in pairs(self.runtime.opts.modpaths or {}) do
  if within(filename,normal(root)) then allowed=true;break end
 end
 assert(allowed,'mod file is outside registered mod directories: '..filename)
 assert(filename:sub(-4)=='.lua','only Lua mod files are supported')
 -- Lua 5.1 (LuaJIT) uses setfenv; Lua 5.2+ takes env in loadfile.
 local chunk,err
 if setfenv then
  chunk,err=loadfile(filename)
  if chunk then setfenv(chunk,self.globals) end
 else
  chunk,err=loadfile(filename,'t',self.globals)
 end
 if not chunk then error(err,0) end
 self.read_count=self.read_count+1
 self.files[#self.files+1]=filename
 return chunk()
end

function ModEnvironment:executeMod(path,name)
 local old=self.runtime.current_mod
 assert(old==name,'mod context must match dependency loader')
 return self:runfile(path)
end

return ModEnvironment
