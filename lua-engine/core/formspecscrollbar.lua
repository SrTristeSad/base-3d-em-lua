-- Core formspec scrollbar values and options, following Luanti GUIFormSpecMenu.
-- No GPU state or filesystem dependencies: used by the LÖVR host view.
local B={}
local floor=math.floor
local function finite(v)
 return type(v)=='number' and v==v and
  v~=math.huge and v~=-math.huge
end
local function integer(v)
 local n=tonumber(v)
 if finite(n) and n==floor(n) and n>=-2147483648 and
  n<=2147483647 then return n end
end
local defaults={min=0,max=1000,smallstep=10,largestep=100,
 thumbsize=1,arrows='default'}
function B.defaults()
 local o={}
 for k,v in pairs(defaults) do o[k]=v end
 return o
end
function B.options(previous,parts)
 local out={}
 for k,v in pairs(previous or defaults) do out[k]=v end
 for _,part in ipairs(parts or {}) do
  local key,value=part:match('^%s*([%a]+)%s*=%s*(.-)%s*$')
  if key=='arrows' then
   if value=='show' or value=='hide' or value=='default' then
    out.arrows=value
   end
  elseif defaults[key] and key~='arrows' then
   local n=integer(value)
   if n then
    if key=='smallstep' then n=n<0 and 10 or n
    elseif key=='largestep' then n=n<0 and 100 or n
    elseif key=='thumbsize' then n=n<=0 and 1 or n end
    out[key]=n
   end
  end
 end
 return out
end
function B.range(options,content,visible,padding,factor)
 local min,max=options.min,options.max
 -- Upstream only overrides scrollbar min/max if content padding was set.
 if padding~=nil and finite(content) and finite(visible) and
  finite(factor) and factor>0 then
  min=0
  max=math.ceil(math.max(0,content+padding-visible)/factor)
 end
 if max<min then max=min end
 return min,max
end
function B.clamp(value,min,max)
 if not finite(value) or not finite(min) or not finite(max) then
  return min
 end
 return math.max(min,math.min(max,floor(value+.5)))
end
function B.track(rect,axis,pointer,min,max)
 if not rect or not finite(pointer) or not finite(min) or
  not finite(max) then return nil end
 local start=axis=='horizontal' and rect.x or rect.y
 local length=axis=='horizontal' and rect.w or rect.h
 if not finite(start) or not finite(length) or length<=0 then
  return nil
 end
 return B.clamp(min+(max-min)*(pointer-start)/length,min,max)
end
function B.event(value,changed)
 return (changed and 'CHG:' or 'VAL:')..tostring(value)
end
return B
