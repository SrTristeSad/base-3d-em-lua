-- Reproducible CPU-time benchmarks for the standalone Lua engine.
-- Never treat CI runner measurements as stable FPS or as regression gates.
-- Usage: lua5.4 benchmarks/lua_engine_perf.lua [--quick] [--samples=N]
--        [--output=dist/lua-engine-benchmark-lua54.json]
package.path='./lua-engine/?.lua;./lua-engine/?/init.lua;'..package.path
local Runtime=require('core.runtime')
local Index=require('core.spatialindex')
local Events=require('core.collisionevents')
local Geometry=require('core.collisiongeometry')
local Nodebox=require('core.nodebox')
local floor,sqrt,abs=math.floor,math.sqrt,math.abs

local quick=false
local samples=3
local output=nil
for _,argument in ipairs(arg or {}) do
 if argument=='--quick' then quick=true
 elseif argument:match('^%-%-samples=') then
  samples=tonumber(argument:match('=(.*)$'))
  assert(samples and samples==floor(samples) and samples>=1 and
   samples<=20,'samples must be an integer from 1 to 20')
 elseif argument:match('^%-%-output=') then
  output=argument:match('=(.*)$')
  assert(output~='','--output requires a path')
 else
  error('unknown benchmark argument: '..argument)
 end
end
local function p(x,y,z) return {x=x,y=y,z=z} end
local function fresh()
 local rt=Runtime.new({auto_pickup=false,item_physics=false})
 local api=rt.api
 api.register_entity('bench:mob',{
  initial_properties={physical=true,collide_with_objects=true,
   collisionbox={-.3,-.3,-.3,.3,.3,.3}},
 })
 api.register_entity('bench:ghost',{
  initial_properties={physical=false},
 })
 return rt,api
end
local function populate(n,layout,physical)
 local rt,api=fresh()
 local entities={}
 for i=1,n do
  local x,y,z
  if layout=='dense' then
   x=((i-1)%16)*.75
   y=3
   z=floor((i-1)/16)*.75
  else
   x=((i-1)%32)*8
   y=3
   z=floor((i-1)/32)*8
  end
  local name=physical and 'bench:mob' or
   (i%2==0 and 'bench:ghost' or 'bench:mob')
  entities[i]=assert(api.add_entity(p(x,y,z),name))
 end
 return {rt=rt,api=api,entities=entities}
end
local function brute_radius(rt,position,radius)
 local total=0
 local r2=radius*radius
 for _,obj in ipairs(rt.luaEntities) do
  if not obj.removed then
   local q=obj.pos
   local dx,dy,dz=q.x-position.x,q.y-position.y,q.z-position.z
   if dx*dx+dy*dy+dz*dz<=r2 then total=total+1 end
  end
 end
 return total
end
local function work_radius(ctx,iterations,indexed)
 local objects=ctx.entities
 local total=0
 for i=1,iterations do
  local obj=objects[1+((i*13-1)%#objects)]
  local position=obj.pos
  local radius=ctx.radius
  if indexed then
   total=total+#ctx.api.get_objects_inside_radius(position,radius)
  else
   total=total+brute_radius(ctx.rt,position,radius)
  end
 end
 return total
end
local function work_motion(ctx,iterations)
 for _=1,iterations do ctx.rt:step(1/30) end
 local checksum=0
 for i=1,#ctx.entities do
  local q=ctx.entities[i].pos
  checksum=checksum+q.x+q.y+q.z
 end
 return checksum
end
local function work_events(ctx,iterations)
 local total=0
 for _=1,iterations do
  local times=Events.schedule(ctx.entities,.2,5,ctx.rt)
  total=total+#times
 end
 return total
end
local function work_relocation(ctx,iterations)
 local entities=ctx.entities
 for i=1,iterations do
  local n=1+((i-1)%#entities)
  local obj=entities[n]
  local pos=obj:get_pos()
  pos.x=pos.x+(i%2==0 and .3 or -.3)
  obj:set_pos(pos)
 end
 return Index.ensure(ctx.rt).queries+#entities
end
-- Geometry benchmarks use identical world-space AABBs and the same
-- nodebox routine. Their reference path does not read the collision cache.
local function geometry_setup(n)
 local rt,api=fresh()
 api.register_node('bench:stone',{})
 api.register_node('bench:slab',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
 local positions={}
 for i=1,n do
  local pos=p(i*8,0,0)
  api.set_node(pos,{name=i%7==0 and 'bench:slab' or 'bench:stone'})
  positions[i]=pos
 end
 return {rt=rt,api=api,positions=positions}
end
local function geometry_reference(ctx,region,pad)
 local rt=ctx.rt
 pad=pad or 2
 local x1,x2=floor(region[1]-pad),floor(region[4]+pad)
 local y1,y2=floor(region[2]-pad),floor(region[5]+pad)
 local z1,z2=floor(region[3]-pad),floor(region[6]+pad)
 local total=0
 for x=x1,x2 do for y=y1,y2 do for z=z1,z2 do
  local pos=p(x,y,z)
  local node=rt.map:get_node(pos)
  local def=rt.registry.nodes[node.name]
  if def and def.walkable~=false and not def.buildable_to then
   total=total+#Nodebox.boxes(
    def,node,rt.map,pos,rt.registry.nodes,'collision_box')
  end
 end end end
 return total
end
local function work_geometry(ctx,iterations,cached)
 local total=0
 for i=1,iterations do
  local pos=ctx.positions[1+((i*13-1)%#ctx.positions)]
  local region={pos.x-.2,pos.y-.2,pos.z-.2,
   pos.x+.2,pos.y+.2,pos.z+.2}
  if cached then
   total=total+#Geometry.collect(ctx.rt,region,2,true)
  else
   total=total+geometry_reference(ctx,region)
  end
 end
 return total
end
-- Identical long horizontal sweeps compare sparse occupied-mapblock
-- broadphase against the original full voxel traversal.
local function work_wide_geometry(ctx,iterations,sparse)
 local total=0
 for i=1,iterations do
  local pos=ctx.positions[1+((i*13-1)%#ctx.positions)]
  local region={pos.x-20,pos.y-.2,pos.z-.2,
   pos.x+20,pos.y+.2,pos.z+.2}
  if sparse then
   total=total+#Geometry.collect(ctx.rt,region,2,true)
  else
   total=total+geometry_reference(ctx,region)
  end
 end
 return total
end
-- Dense solid terrain can make candidate enumeration/sorting more costly
-- than the straightforward voxel scan. Geometry.collect should select
-- the dense path adaptively for these fully occupied regions.
local function dense_geometry_setup(n)
 local rt,api=fresh()
 api.register_node('bench:stone',{})
 local extent=n==32 and 9 or n==128 and 16 or 20
 for x=0,extent-1 do for y=0,extent-1 do for z=0,extent-1 do
  api.set_node(p(x,y,z),{name='bench:stone'})
 end end end
 return {rt=rt,api=api,extent=extent}
end
local function work_dense_geometry(ctx,iterations,adaptive)
 local total=0
 local far=ctx.extent-1
 local region={0,0,0,far,far,far}
 for _=1,iterations do
  if adaptive then
   total=total+#Geometry.collect(ctx.rt,region,0,true)
  else
   total=total+geometry_reference(ctx,region,0)
  end
 end
 return total
end
-- Mixed-world fixture: dense stone clusters alternate with mostly
-- empty mapblocks, exercising the spatial selector and ordered merges.
local function mixed_geometry_setup(n)
 local rt,api=fresh()
 api.register_node('bench:stone',{})
 api.register_node('bench:slab',{drawtype='nodebox',
  node_box={type='fixed',fixed={-.5,-.5,-.5,.5,0,.5}}})
 for x=-32,47 do for y=-2,2 do for z=-4,4 do
  local block=floor(x/16)
  local dense=block%2==0
  if dense and (x+y+z)%5~=0 or
     (not dense and (x*7+y*11+z*3)%17==0) then
   api.set_node(p(x,y,z),{name=(x+y+z)%13==0 and
    'bench:slab' or 'bench:stone'})
  end
 end end end
 local positions={}
 for i=1,n do
  positions[i]=p(((i*7)%80)-32,0,0)
 end
 return {rt=rt,api=api,positions=positions}
end
local function work_mixed_geometry(ctx,iterations,cached)
 local total=0
 for i=1,iterations do
  local pos=ctx.positions[1+((i*13-1)%#ctx.positions)]
  local region={pos.x-12,-.2,-3,pos.x+12,.2,3}
  if cached then
   total=total+#Geometry.collect(ctx.rt,region,2,true)
  else
   total=total+geometry_reference(ctx,region)
  end
 end
 return total
end
local function median(data)
 table.sort(data)
 if #data%2==1 then return data[(#data+1)/2] end
 return (data[#data/2]+data[#data/2+1])/2
end
local results={}
local function measure(name,n,iterations,units,setup,work)
 local seconds,checks,candidates={}, {}, {}
 for sample=1,samples do
  local ctx=setup(n)
  local before=Index.ensure(ctx.rt)
  work(ctx,1) -- warm up compiled closures and the relevant lookup path
  collectgarbage('collect')
  local candidate_before=before.candidates_examined+
   before.proximity_candidates_examined
  local start=os.clock()
  local checksum=work(ctx,iterations)
  local duration=os.clock()-start
  assert(type(checksum)=='number' and checksum==checksum,
   'benchmark checksum must be finite')
  assert(duration>=0 and duration==duration,'invalid CPU timer')
  seconds[#seconds+1]=duration
  checks[#checks+1]=checksum
  candidates[#candidates+1]=before.candidates_examined+
   before.proximity_candidates_examined-candidate_before
 end
 for i=2,#checks do
  assert(abs(checks[i]-checks[1])<1e-5,
   'benchmark setup produced different results across samples: '..name)
 end
 local seconds_median=median(seconds)
 local result={name=name,entities=n,iterations=iterations,unit=units,
  cpu_seconds_median=seconds_median,
  units_per_cpu_second=seconds_median>0 and
   (units=='entity_steps' and n*iterations or iterations)/
   seconds_median or 0,
  checksum=checks[1],
  candidates_examined_median=median(candidates)}
 results[#results+1]=result
 print(string.format('%-23s n=%-4d iterations=%-5d CPU=%8.5fs rate=%10.1f %s/s candidates=%d',
  name,n,iterations,seconds_median,result.units_per_cpu_second,
  units,result.candidates_examined_median))
end
local sizes=quick and {32,128} or {32,128,256}
local radius_iterations=quick and 120 or 600
local motion_iterations=quick and 4 or 12
local event_iterations=quick and 8 or 32
local relocation_iterations=quick and 80 or 300
local geometry_iterations=quick and 80 or 240
local wide_iterations=quick and 40 or 120
local dense_iterations=quick and 4 or 10
local mixed_iterations=quick and 16 or 60
print('Lua engine performance baseline | '.._VERSION..
 (jit and (' / '..jit.version) or '')..
 ' | samples='..samples..' | quick='..tostring(quick))
print('Timing: os.clock() CPU seconds; not FPS; compare only on matching hardware.')
for _,n in ipairs(sizes) do
 local function radius_setup()
  local ctx=populate(n,'sparse',false)
  ctx.radius=2.0
  -- Count baseline agreement on the identical deterministic fixtures.
  for i=1,n do
   local q=ctx.entities[i].pos
   assert(#ctx.api.get_objects_inside_radius(q,ctx.radius)==
    brute_radius(ctx.rt,q,ctx.radius),'radius baseline mismatch')
  end
  return ctx
 end
 measure('radius_indexed_sparse',n,radius_iterations,'queries',
  radius_setup,function(c,it)return work_radius(c,it,true) end)
 measure('radius_linear_sparse',n,radius_iterations,'queries',
  radius_setup,function(c,it)return work_radius(c,it,false) end)
 local function dense_setup()
  local ctx=populate(n,'dense',false)
  ctx.radius=2.0
  return ctx
 end
 measure('radius_indexed_dense',n,radius_iterations,'queries',
  dense_setup,function(c,it)return work_radius(c,it,true) end)
 measure('radius_linear_dense',n,radius_iterations,'queries',
  dense_setup,function(c,it)return work_radius(c,it,false) end)
 local function movement_setup()
  local ctx=populate(n,'sparse',true)
  for _,obj in ipairs(ctx.entities) do
   obj:set_velocity(p(.4,0,.2))
  end
  return ctx
 end
 measure('physical_entity_step',n,motion_iterations,'entity_steps',
  movement_setup,work_motion)
 local function events_setup()
  local ctx=populate(n,'sparse',true)
  -- A reproducible head-on pair, far from the remaining NPC grid.
  local a,b=ctx.entities[1],ctx.entities[2]
  a:set_pos(p(0,3,-40));b:set_pos(p(4,3,-40))
  a:set_velocity(p(20,0,0))
  b:set_velocity(p(-20,0,0))
  return ctx
 end
 measure('collision_event_search',n,event_iterations,'event_batches',
  events_setup,work_events)
 measure('spatial_relocation',n,relocation_iterations,'set_pos',
  function()return populate(n,'sparse',true) end,work_relocation)
 measure('node_collision_cached',n,geometry_iterations,'geometry_queries',
  function()return geometry_setup(n) end,
  function(c,it)return work_geometry(c,it,true) end)
 measure('node_collision_uncached',n,geometry_iterations,'geometry_queries',
  function()return geometry_setup(n) end,
  function(c,it)return work_geometry(c,it,false) end)
 measure('node_wide_sparse',n,wide_iterations,'geometry_queries',
  function()return geometry_setup(n) end,
  function(c,it)return work_wide_geometry(c,it,true) end)
 measure('node_wide_linear',n,wide_iterations,'geometry_queries',
  function()return geometry_setup(n) end,
  function(c,it)return work_wide_geometry(c,it,false) end)
 measure('node_dense_adaptive',n,dense_iterations,'geometry_queries',
  function()return dense_geometry_setup(n) end,
  function(c,it)return work_dense_geometry(c,it,true) end)
 measure('node_dense_linear',n,dense_iterations,'geometry_queries',
  function()return dense_geometry_setup(n) end,
  function(c,it)return work_dense_geometry(c,it,false) end)
 measure('node_mixed_cached',n,mixed_iterations,'geometry_queries',
  function()return mixed_geometry_setup(n) end,
  function(c,it)return work_mixed_geometry(c,it,true) end)
 measure('node_mixed_linear',n,mixed_iterations,'geometry_queries',
  function()return mixed_geometry_setup(n) end,
  function(c,it)return work_mixed_geometry(c,it,false) end)
end

local function escaped(str)
 return '"'..str:gsub('\\','\\\\'):gsub('"','\\"')
  :gsub('\n','\\n'):gsub('\r','\\r')..'"'
end
local function json_value(value)
 local kind=type(value)
 if kind=='string' then return escaped(value) end
 if kind=='number' then
  assert(value==value and value~=math.huge and value~=-math.huge,
   'nonfinite JSON number')
  return string.format('%.10g',value)
 end
 if kind=='boolean' then return tostring(value) end
 error('unsupported benchmark JSON type: '..kind)
end
local report={
 schema_version=1,
 phase=47,
 lua_version=_VERSION,
 runtime=(jit and jit.version or _VERSION),
 quick=quick,
 samples=samples,
 clock='os.clock CPU seconds',
 notes='No hard-coded performance thresholds; compare on the same runner.',
}
local function encode()
 local fields={}
 for _,key in ipairs({'schema_version','phase','lua_version','runtime',
  'quick','samples','clock','notes'}) do
  fields[#fields+1]='  '..escaped(key)..': '..json_value(report[key])
 end
 local entries={}
 for _,row in ipairs(results) do
  local cols={}
  for _,key in ipairs({'name','entities','iterations','unit',
   'cpu_seconds_median','units_per_cpu_second','checksum',
   'candidates_examined_median'}) do
   cols[#cols+1]=escaped(key)..': '..json_value(row[key])
  end
  entries[#entries+1]='    {'..table.concat(cols,', ')..'}'
 end
 fields[#fields+1]='  "cases": [\n'..table.concat(entries,',\n')..'\n  ]'
 return '{\n'..table.concat(fields,',\n')..'\n}\n'
end
if output then
 local file,err=io.open(output,'wb')
 assert(file,'cannot open benchmark output: '..tostring(err))
 assert(file:write(encode()))
 assert(file:close())
 print('Wrote '..output..' ('..#results..' scenarios)')
end
print('LUA ENGINE PHASE 47 BENCHMARKS PASS ('..#results..' cases)')
