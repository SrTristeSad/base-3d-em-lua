-- Luanti formspec nine-slice geometry. Pure Lua, independent of the GPU.
-- See doc/lua_api.md: background9[] middle (x / x,y / x,y,x2,y2).
-- A negative x2/y2 measures the far boundary from the right/bottom edge.
local Nine={}
local function integer(v)
 if type(v)~='string' or not v:match('^%s*[+-]?%d+%s*$') then
  return nil
 end
 local n=tonumber(v)
 if n and n==math.floor(n) and n>=-4096 and n<=4096 then
  return n
 end
end
local function valid(n)
 return type(n)=='number' and n==n and n~=math.huge and
  n~=-math.huge
end
function Nine.middle(spec,width,height)
 if not valid(width) or not valid(height) or
  width<1 or height<1 or
  type(spec)~='string' or #spec>64 then
  return nil,'invalid_nine_slice'
 end
 local values={}
 for token in (spec..','):gmatch('(.-),') do
  local n=integer(token)
  if not n then return nil,'invalid_middle' end
  values[#values+1]=n
 end
 if #values~=1 and #values~=2 and #values~=4 then
  return nil,'invalid_middle'
 end
 local x0,y0,x1,y1
 if #values==1 then
  x0,y0=values[1],values[1]
  x1,y1=width-x0,height-y0
 elseif #values==2 then
  x0,y0=values[1],values[2]
  x1,y1=width-x0,height-y0
 else
  x0,y0=values[1],values[2]
  x1=values[3]>=0 and values[3] or width+values[3]
  y1=values[4]>=0 and values[4] or height+values[4]
 end
 if x0<0 or y0<0 or x1>width or y1>height or
  x0>=x1 or y0>=y1 then
  return nil,'invalid_middle_bounds'
 end
 return {x0=x0,y0=y0,x1=x1,y1=y1}
end
local function vertex(x,y,u,v)
 return {x,y,.06,0,0,1,u,v,1,1,1,1}
end
local function scaled_edges(first,last,total,limit)
 local sum=first+last
 if sum>limit then
  return first*limit/sum,last*limit/sum
 end
 return first,last
end
local function append_quad(vertices,x0,y0,x1,y1,u0,v0,u1,v1)
 if x1<=x0 or y1<=y0 or u1<=u0 or v1<=v0 then return end
 local a=vertex(x0,y0,u0,v0)
 local b=vertex(x0,y1,u0,v1)
 local c=vertex(x1,y1,u1,v1)
 local d=vertex(x1,y0,u1,v0)
 vertices[#vertices+1]=a;vertices[#vertices+1]=b
 vertices[#vertices+1]=c;vertices[#vertices+1]=a
 vertices[#vertices+1]=c;vertices[#vertices+1]=d
end
function Nine.vertices(source,x,y,w,h,spec)
 if type(source)~='table' or not source.original or
  not source.uv or not valid(source.width) or
  not valid(source.height) or
  not valid(x) or not valid(y) or
  not valid(w) or not valid(h) or w<=0 or h<=0 then
  return nil,'original_dimensions_required'
 end
 local u0,v0,u1,v1=source.uv[1],source.uv[2],
  source.uv[3],source.uv[4]
 if not valid(u0) or not valid(u1) or not valid(v0) or
  not valid(v1) or u0>=u1 or v0>=v1 then
  return nil,'invalid_texture_uv'
 end
 local tw=source.width
 local th=source.height*(v1-v0)
 if th~=math.floor(th) then return nil,'fractional_frame_height' end
 local middle,err=Nine.middle(spec,tw,th)
 if not middle then return nil,err end
 local left,right=middle.x0,tw-middle.x1
 local top,bottom=middle.y0,th-middle.y1
 local dl,dr=scaled_edges(left,right,tw,w)
 local dt,db=scaled_edges(top,bottom,th,h)
 local xs={x-w/2,x-w/2+dl,x+w/2-dr,x+w/2}
 local ys={y-h/2,y-h/2+dt,y+h/2-db,y+h/2}
 local su={u0,u0+(u1-u0)*middle.x0/tw,
  u0+(u1-u0)*middle.x1/tw,u1}
 local sv={v0,v0+(v1-v0)*middle.y0/th,
  v0+(v1-v0)*middle.y1/th,v1}
 local out={}
 for row=1,3 do
  for col=1,3 do
   append_quad(out,xs[col],ys[row],xs[col+1],ys[row+1],
    su[col],sv[row],su[col+1],sv[row+1])
  end
 end
 if #out==0 then return nil,'empty_nine_slice' end
 return out
end
return Nine
