-- Server-to-host sound bridge compatible with Luanti's SoundSpec and
-- sound_play/sound_stop/sound_fade control flow. A real host must supply a
-- playback backend. No backend => no fabricated audible result or handle.
local Sound={}
Sound.__index=Sound
local huge=math.huge
local floor=math.floor
local function finite(v)
 return type(v)=='number' and v==v and v~=huge and v~=-huge
end
local function number(v,label,default,minval)
 if v==nil then return default end
 assert(finite(v) and (minval==nil or v>=minval),
  'invalid sound '..label)
 return v
end
local function stringopt(v,label)
 assert(v==nil or type(v)=='string','invalid sound '..label)
 return v
end
local function position(p)
 assert(type(p)=='table' and finite(p.x) and finite(p.y) and
  finite(p.z),'invalid sound position')
 return {x=p.x,y=p.y,z=p.z}
end
local function normalize(spec,params)
 if spec==nil then spec='' end
 local input
 if type(spec)=='string' then input={name=spec}
 elseif type(spec)=='table' then input=spec
 else error('sound spec must be a name or table',2) end
 local name=input.name or ''
 assert(type(name)=='string','sound name must be a string')
 local src={
  name=name,
  gain=number(input.gain,'spec gain',1,0),
  fade=number(input.fade,'spec fade',0),
  pitch=number(input.pitch,'spec pitch',1,0),
  start_time=number(input.start_time,'spec start_time',0,0),
  loop=input.loop or false
 }
 assert(type(src.loop)=='boolean','invalid sound loop flag')
 assert(params==nil or type(params)=='table',
  'sound parameters must be a table')
 params=params or {}
 local p={
  gain=number(params.gain,'gain',1,0),
  max_hear_distance=number(params.max_hear_distance,
   'max_hear_distance',32,0),
  to_player=stringopt(params.to_player,'to_player'),
  exclude_player=stringopt(params.exclude_player,'exclude_player')
 }
 if params.pos~=nil then p.pos=position(params.pos) end
 if params.object~=nil then
  assert(type(params.object)=='table' and
   type(params.object.get_pos)=='function',
   'invalid sound object reference')
  p.object=params.object
 end
 if params.fade~=nil then src.fade=number(params.fade,'fade',0) end
 if params.pitch~=nil then
  src.pitch=number(params.pitch,'pitch',1,0)
 end
 if params.start_time~=nil then
  src.start_time=number(params.start_time,'start_time',0,0)
 end
 if params.loop~=nil then
  assert(type(params.loop)=='boolean','invalid sound loop flag')
  src.loop=params.loop
 end
 return src,p
end
local function check_backend(backend)
 assert(backend==nil or (type(backend)=='table' and
  type(backend.play)=='function' and
  type(backend.stop)=='function' and
  type(backend.fade)=='function'),
  'sound backend requires play, stop and fade methods')
end
function Sound.new(backend)
 check_backend(backend)
 return setmetatable({backend=backend,active={},next_id=0},Sound)
end
function Sound:set_backend(backend)
 check_backend(backend)
 assert(next(self.active)==nil,
  'cannot replace sound backend with active handles')
 self.backend=backend
end
function Sound:play(spec,params,ephemeral)
 assert(ephemeral==nil or type(ephemeral)=='boolean',
  'ephemeral sound flag must be boolean')
 local sound,options=normalize(spec,params)
 -- Luanti's server may return an invalid handle if no listener/audio
 -- asset exists. Do not fabricate playback if the host has no backend.
 if sound.name=='' or not self.backend then return nil end
 local backend_ref=self.backend:play(sound,options,ephemeral==true)
 if backend_ref==nil or backend_ref==false then return nil end
 if ephemeral then return nil end
 assert(self.next_id<2147483647,'sound handle space exhausted')
 self.next_id=self.next_id+1
 local handle=self.next_id
 self.active[handle]=backend_ref
 return handle
end
local function handle(v)
 assert(type(v)=='number' and v==floor(v),
  'sound handle must be an integer')
end
function Sound:stop(id)
 handle(id)
 local ref=self.active[id]
 if ref==nil then return false end
 self.active[id]=nil
 self.backend:stop(ref)
 return true
end
function Sound:fade(id,step,gain)
 handle(id)
 step=number(step,'fade step',nil,0)
 gain=number(gain,'fade target',nil,0)
 local ref=self.active[id]
 if ref==nil then return false end
 self.backend:fade(ref,step,gain)
 return true
end
-- The audio host may notify that playback ended naturally, without
-- asking the server bridge to stop the already finished native source.
function Sound:finished(id)
 handle(id)
 if self.active[id]==nil then return false end
 self.active[id]=nil
 return true
end
function Sound:stop_all()
 local ids={}
 for id in pairs(self.active) do ids[#ids+1]=id end
 table.sort(ids)
 for _,id in ipairs(ids) do self:stop(id) end
 return #ids
end
return Sound
