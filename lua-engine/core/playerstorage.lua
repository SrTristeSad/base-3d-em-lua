-- Standalone singleplayer profile sidecar, separate from map and entities.
-- Data-only format: never execute saved Lua or trust saved inventory indexes.
local Serialization=require('core.serialization')
local M={}
local HEADER='LUAENGINE PLAYER 1\n'
local MAX_BYTES=256*1024
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function integer(n,lo,hi)
 return finite(n) and n==math.floor(n) and n>=lo and n<=hi
end
local function pos(p)
 assert(type(p)=='table' and finite(p.x) and finite(p.y) and
  finite(p.z) and math.abs(p.x)<=31000 and math.abs(p.y)<=31000 and
  math.abs(p.z)<=31000,'invalid player coordinates')
 return {x=p.x,y=p.y,z=p.z}
end
local function stack(record)
 if record==false then return false end
 assert(type(record)=='table' and type(record.name)=='string' and
  #record.name>0 and #record.name<=256 and
  integer(record.count,1,65535) and integer(record.wear,0,65535),
  'invalid saved player ItemStack')
 local fields=record.fields or {}
 assert(type(fields)=='table','invalid saved player ItemStack metadata')
 local clean={}
 local count=0
 for k,v in pairs(fields) do
  count=count+1
  assert(count<=128 and type(k)=='string' and #k<=256 and
   type(v)=='string' and #v<=4096,
   'invalid saved item metadata field')
  clean[k]=v
 end
 return {name=record.name,count=record.count,wear=record.wear,
  fields=clean}
end
function M.encode(player,controller,yaw,pitch)
 assert(player and type(player.get_inventory)=='function' and
  type(player.get_wield_index)=='function','player ObjectRef required')
 local inv=player:get_inventory()
 local size=inv:get_size('main')
 assert(integer(size,1,256),'invalid player main inventory size')
 local items={}
 for i=1,size do
  local item=inv:get_stack('main',i):to_table()
  items[i]=item and stack(item) or false
 end
 assert(finite(yaw) and finite(pitch) and math.abs(yaw)<=1e6 and
  math.abs(pitch)<=math.pi/2,'invalid player camera angles')
 local state={pos=pos(controller:get_pos()),yaw=yaw,pitch=pitch,
  wield=player:get_wield_index(),size=size,items=items}
 assert(integer(state.wield,1,math.min(9,size)),'invalid saved wield slot')
 local data=HEADER..Serialization.serialize(state)
 assert(#data<=MAX_BYTES,'player profile save too large')
 return data
end
function M.decode(data)
 assert(type(data)=='string' and #data<=MAX_BYTES and
  data:sub(1,#HEADER)==HEADER,'invalid player profile header or size')
 local state=Serialization.deserialize(data:sub(#HEADER+1))
 assert(type(state)=='table','invalid player profile payload')
 local clean={pos=pos(state.pos),yaw=state.yaw,pitch=state.pitch}
 assert(finite(clean.yaw) and finite(clean.pitch) and
  math.abs(clean.yaw)<=1e6 and math.abs(clean.pitch)<=math.pi/2,
  'invalid saved camera angles')
 assert(integer(state.size,1,256) and
  integer(state.wield,1,math.min(state.size,9)) and
  type(state.items)=='table','invalid saved player inventory')
 clean.size=state.size
 clean.wield=state.wield
 clean.items={}
 for k in pairs(state.items) do
  assert(integer(k,1,state.size),'invalid persisted inventory index')
 end
 for i=1,state.size do
  local record=state.items[i]
  assert(record~=nil,'missing persisted inventory slot')
  clean.items[i]=stack(record)
 end
 return clean
end
-- Validation and allocation happen before mutating the connected player.
-- A malformed or incomplete profile therefore preserves the current spawn
-- position, active item, and the initial inventory.
function M.restore(player,controller,data)
 local state=M.decode(data)
 local inv=player:get_inventory()
 assert(type(inv.set_size)=='function' and
  type(inv.set_stack)=='function','player inventory not writable')
 -- Assemble every stack independently before touching the live inventory.
 local Stack=require('core.itemstack')
 local candidates={}
 for i=1,state.size do
  candidates[i]=Stack.new(state.items[i],controller.api.registered_items)
 end
 inv:set_size('main',state.size)
 for i=1,state.size do
  assert(inv:set_stack('main',i,candidates[i]),'failed to restore slot')
 end
 player:set_wield_index(state.wield)
 controller:set_pos(state.pos)
 return state
end
function M.save(player,controller,yaw,pitch,path,fs)
 assert(fs and type(fs.write)=='function','filesystem.write required')
 return fs.write(path,M.encode(player,controller,yaw,pitch))
end
function M.load(player,controller,path,fs)
 assert(fs and type(fs.read)=='function','filesystem.read required')
 local data=fs.read(path)
 if not data then return nil,'not found' end
 local ok,state=pcall(M.restore,player,controller,data)
 if not ok then return nil,state end
 return state
end
return M
