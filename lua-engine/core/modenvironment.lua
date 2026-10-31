-- Explicit mod execution environment, separate from the host Lua globals.
-- Smoke-test launcher only, NOT a security sandbox for untrusted Lua code.
-- Native game mods may use APIs that are deliberately absent here.
local Vector=require('core.vector')
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
  print=function(...)
   local args={}
   for i=1,select('#',...) do args[#args+1]=tostring(select(i,...)) end
   runtime.api.log('action',table.concat(args,'\t'))
  end,
 }
 if utf8 then std.utf8=shallow(utf8) end
 if bit32 then std.bit32=shallow(bit32) end
 if bit then std.bit=shallow(bit) end
 return std
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
