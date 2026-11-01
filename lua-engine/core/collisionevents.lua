-- Event-assisted moving LuaEntity collisions. Fixed substeps stay as
-- fallback; imminent opposing-body contacts add an exact TOI boundary.
-- This is a bounded kinematic approximation, NOT an impulse/mass solver.
local M={}
local abs,min,max,sqrt,ceil=math.abs,math.min,math.max,math.sqrt,math.ceil
local EPS=1e-7
local AXES={'x','y','z'}
local function eligible(o)
 return not o.removed and o.properties.physical==true and
  o.properties.collide_with_objects~=false
end
local function bounds(o)
 local p,b=o.pos,o.properties.collisionbox
 return {p.x+b[1],p.y+b[2],p.z+b[3],
  p.x+b[4],p.y+b[5],p.z+b[6]}
end
local function delta(o,dt,axis)
 return (o.velocity[axis]+.5*o.acceleration[axis]*dt)*dt
end
local function pair_event(a,b,dt)
 local aa,bb=bounds(a),bounds(b)
 local lower,upper=-math.huge,math.huge
 local axis
 for i,key in ipairs(AXES) do
  local d=delta(a,dt,key)-delta(b,dt,key)
  local lo,hi=aa[i],aa[i+3]
  local blo,bhi=bb[i],bb[i+3]
  if abs(d)<EPS then
   if hi<=blo+EPS or bhi<=lo+EPS then return nil end
  else
   local entry=(blo-hi)/d
   local departure=(bhi-lo)/d
   if entry>departure then entry,departure=departure,entry end
   if entry>lower then lower=entry;axis=key end
   upper=min(upper,departure)
   if lower>upper+EPS then return nil end
  end
 end
 if not axis or lower<=EPS or lower>=1-EPS or upper<0 then
  return nil
 end
 -- Stationary blockers and pursuing objects use the existing swept
 -- solver. Event scheduling is needed for genuinely head-on motion.
 if a.velocity[axis]*b.velocity[axis]>=-EPS then return nil end
 return lower
end
-- Sorted time fractions, including fixed safe substeps and approaching
-- pair events. Restrict quadratic discovery to modest local simulations.
function M.schedule(objects,dt,base)
 local times={}
 for i=1,base do times[#times+1]=i/base end
 if dt<=0 or #objects>128 then return times end
 local events={}
 for i=1,#objects-1 do
  local a=objects[i]
  if eligible(a) then
   for j=i+1,#objects do
    local b=objects[j]
    if eligible(b) then
     local at=pair_event(a,b,dt)
     if at then events[#events+1]=at end
    end
   end
  end
 end
 table.sort(events)
 -- The 24 earliest events are sufficient to add near-term precise
 -- boundaries without exploding the number of physics passes.
 for i=1,min(24,#events) do
  times[#times+1]=events[i]
 end
 table.sort(times)
 local unique,previous={},0
 for _,t in ipairs(times) do
  if t>previous+1e-7 then
   unique[#unique+1]=t;previous=t
  end
 end
 -- Always include the end-of-frame boundary even if an event rounded
 -- dangerously close to it.
 if unique[#unique]<1 then unique[#unique+1]=1 end
 return unique
end
local function overlap(a,b,c,d)
 return a<d-EPS and c<b-EPS
end
local function adjacent(a,b,axis)
 local index=axis=='x' and 1 or axis=='y' and 2 or 3
 for i=1,3 do
  if i~=index and not overlap(a[i],a[i+3],b[i],b[i+3]) then
   return nil
  end
 end
 if abs(a[index+3]-b[index])<1e-6 then return 1 end
 if abs(b[index+3]-a[index])<1e-6 then return -1 end
 return nil
end
local function velocity(v) return {x=v.x,y=v.y,z=v.z} end
local function append(result,other,axis,normal,old,new)
 for _,c in ipairs(result.collisions) do
  if c.type=='object' and c.object==other and
    c.axis==axis and c.normal[axis]==normal then return end
 end
 local n={x=0,y=0,z=0};n[axis]=normal
 result.collisions[#result.collisions+1]={
  type='object',object=other,axis=axis,normal=n,
  old_velocity=velocity(old),new_velocity=velocity(new),
  coordinated=true}
 result.collides=true
end
-- A pair arriving exactly at its shared face has no penetration and the
-- per-object sweeps may report no hit. Stop BOTH closing normal velocities
-- at the event and notify both LuaEntities once (not once per substep).
function M.resolve(objects,results)
 if #objects>128 then return end
 for i=1,#objects-1 do
  local a=objects[i]
  if eligible(a) then
   for j=i+1,#objects do
    local b=objects[j]
    if eligible(b) then
     local ab,bb=bounds(a),bounds(b)
     for _,axis in ipairs(AXES) do
      local sign=adjacent(ab,bb,axis)
      if sign and (a.velocity[axis]-b.velocity[axis])*sign>EPS then
       local va,vb=velocity(a.velocity),velocity(b.velocity)
       a.velocity[axis]=0
       b.velocity[axis]=0
       append(results[a],b,axis,-sign,va,a.velocity)
       append(results[b],a,axis,sign,vb,b.velocity)
      end
     end
    end
   end
  end
 end
end
return M
