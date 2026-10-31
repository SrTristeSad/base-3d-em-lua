-- Node-position hashes and particle-spawner registrations.
-- CPU-side bookkeeping only: there is no GPU particle renderer in this port.
local Particles={}
Particles.__index=Particles
local floor=math.floor
local function coord(pos)
 assert(type(pos)=='table','position must be a table')
 local out={}
 for _,axis in ipairs({'x','y','z'}) do
  local n=pos[axis]
  assert(type(n)=='number' and n==floor(n) and n>=-32768
   and n<=32767,'node position out of hash range: '..axis)
  out[axis]=n
 end
 return out
end
local function dup(t,seen)
 if type(t)~='table' then return t end
 seen=seen or {}
 if seen[t] then return seen[t] end
 local out={}
 seen[t]=out
 for k,v in pairs(t) do out[dup(k,seen)]=dup(v,seen) end
 return out
end
function Particles.hash_node_position(pos)
 local p=coord(pos)
 -- Luanti v3s16 48-bit packed hash, exactly representable by Lua double.
 return (p.z+32768)*4294967296+(p.y+32768)*65536+(p.x+32768)
end
function Particles.get_position_from_hash(hash)
 assert(type(hash)=='number' and hash==floor(hash) and
  hash>=0 and hash<281474976710656,'invalid node hash')
 return {x=hash%65536-32768,y=floor(hash/65536)%65536-32768,
  z=floor(hash/4294967296)%65536-32768}
end
function Particles.new()
 return setmetatable({spawners={},next_id=0},Particles)
end
function Particles:add_spawner(def)
 assert(type(def)=='table','particle definition must be a table')
 self.next_id=self.next_id+1
 self.spawners[self.next_id]=dup(def)
 return self.next_id
end
function Particles:delete_spawner(id)
 assert(type(id)=='number' and id==floor(id),'invalid spawner id')
 if not self.spawners[id] then return false end
 self.spawners[id]=nil
 return true
end
function Particles:get_spawner(id)
 local def=self.spawners[id]
 return def and dup(def) or nil
end
function Particles:add_particle(def)
 assert(type(def)=='table','invalid particle')
 -- This API requires an active renderer and should never claim to spawn one.
 return false,'particle renderer not implemented'
end
return Particles
