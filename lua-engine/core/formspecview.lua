-- Client-side formspec presentation for the standalone LÖVR host.
-- Reads the ORIGINAL text emitted by core.show_formspec; never asks mods to
-- produce a second layout or invents a server-side field event.
-- This is a supported-element renderer, not Luanti's full GUI renderer.
local View={}
View.__index=View
local floor=math.floor
local function number(v)
 local n=tonumber(v)
 if not n or n~=n or n==math.huge or n==-math.huge then return nil end
 return n
end
local function pair(value)
 if type(value)~='string' then return nil,nil end
 local x,y=value:match('^%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*$')
 return number(x),number(y)
end
-- Formspec escaping: backslashes protect delimiter semicolons. Do not
-- unescape a texture modifier or other part of a value prematurely.
local function parts(value)
 local out,buf={},{}
 local i=1
 while i<=#value do
  local c=value:sub(i,i)
  if c=='\\' and i<#value then
   local nextchar=value:sub(i+1,i+1)
   if nextchar==';' or nextchar=='\\' then
    buf[#buf+1]=nextchar;i=i+2
   else
    buf[#buf+1]=c;i=i+1
   end
  elseif c==';' then
   out[#out+1]=table.concat(buf);buf={};i=i+1
  else
   buf[#buf+1]=c;i=i+1
  end
 end
 out[#out+1]=table.concat(buf)
 return out
end
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function within(x,y,c)
 return x>=c.x and y>=c.y and x<=c.x+c.w and y<=c.y+c.h
end
function View.new(runtime,playername)
 assert(runtime and type(runtime.getPlayerFormspec)=='function'
  and type(runtime.movePlayerInventoryStack)=='function')
 assert(type(playername)=='string' and playername~='')
 return setmetatable({runtime=runtime,playername=playername,
  selected=nil,scrolls={},last_formname=nil,message=''},View)
end
function View:session()
 return self.runtime:getPlayerFormspec(self.playername)
end
function View:layout(width,height)
 assert(number(width) and number(height) and width>150 and height>150,
  'invalid formspec viewport')
 local session=self:session()
 if not session then
  self.last_formname=nil;self.selected=nil;self.scrolls={}
  return nil
 end
 if self.last_formname~=session.formname then
  self.last_formname=session.formname
  self.selected=nil;self.scrolls={}
 end
 local elements=session.elements or {}
 local fw,fh=8,6
 for _,e in ipairs(elements) do
  if e.name=='size' then
   local x,y=pair(e.params)
   if x and y and x>0 and y>0 then fw,fh=x,y end
  end
 end
 local unit=math.min((width-48)/fw,(height-64)/fh,55)
 local left,top=(width-fw*unit)/2,(height-fh*unit)/2
 local controls={}
 local active_scroll=nil
 local all_scrolls={}
 local function add(kind,x,y,w,h,attrs)
  if not x or not y or not w or not h or w<=0 or h<=0 then return end
  if #controls>=900 then return end
  local ctl=attrs or {}
  ctl.kind=kind;ctl.x=left+x*unit;ctl.y=top+y*unit
  ctl.w=w*unit;ctl.h=h*unit
  if active_scroll then
   ctl.x=ctl.x+active_scroll.x
   ctl.y=ctl.y+active_scroll.y-(self.scrolls[active_scroll.name] or 0)*unit
   ctl.clip=active_scroll.clip
   active_scroll.bottom=math.max(active_scroll.bottom,y+h)
   -- Render only complete cells in this supported initial renderer.
   if ctl.x<ctl.clip.x-.01 or ctl.y<ctl.clip.y-.01 or
    ctl.x+ctl.w>ctl.clip.x+ctl.clip.w+.01 or
    ctl.y+ctl.h>ctl.clip.y+ctl.clip.h+.01 then return end
  end
  controls[#controls+1]=ctl
 end
 -- Coordinates of nested scroll containers are relative to the parent.
 -- The current supported subset handles one active scroll container.
 for _,e in ipairs(elements) do
  local t=e.name
  local p=parts(e.params)
  if t=='scroll_container' then
   local x,y=pair(p[1])
   local w,h=pair(p[2])
   if x and y and w and h and not active_scroll then
    local name=p[3] or ''
    active_scroll={name=name,x=x*unit,y=y*unit,
     clip={x=left+x*unit,y=top+y*unit,w=w*unit,h=h*unit},
     h=h,bottom=0,step=number(p[5]) or .875}
    all_scrolls[name]=active_scroll
   end
  elseif t=='scroll_container_end' then
   active_scroll=nil
  elseif t=='list' then
   local loc,list=p[1],p[2]
   if loc=='current_player' or loc=='player:'..self.playername then
    local x,y=pair(p[3]);local cols,rows=pair(p[4])
    local first=number(p[5]) or 0
    if x and y and cols and rows and first>=0 and
     floor(first)==first and cols>0 and rows>0 and
     floor(cols)==cols and floor(rows)==rows and cols*rows<=256 then
     for j=0,cols*rows-1 do
      add('slot',x+j%cols,y+floor(j/cols),1,1,
       {list=list,index=first+j+1})
     end
    end
   end
  elseif t=='label' then
   local x,y=pair(p[1])
   if x and y then add('label',x,y,math.max(.2,fw-x),.5,
     {label=p[2] or ''}) end
  elseif t=='button' or t=='button_exit' or
   t=='image_button' or t=='image_button_exit' or
   t=='item_image_button' or t=='item_image_button_exit' then
   local x,y=pair(p[1]);local w,h=pair(p[2])
   local isimage=t:find('image_button',1,true)~=nil
   local field=isimage and p[4] or p[3]
   local label=isimage and p[5] or p[4]
   if x and y and w and h and type(field)=='string' and field~='' then
    add('button',x,y,w,h,{field=field,label=label or '',
     item=t:find('item_image_button',1,true) and p[3] or nil,
     close=t:find('_exit',1,true)~=nil})
   end
  elseif t=='image' or t=='box' then
   local x,y=pair(p[1]);local w,h=pair(p[2])
   add('decoration',x,y,w,h,{label=p[3] or ''})
  end
 end
 for name,s in pairs(all_scrolls) do
  s.max=math.max(0,s.bottom-s.h)
  self.scrolls[name]=clamp(self.scrolls[name] or 0,0,s.max)
 end
 return {controls=controls,x=left,y=top,w=fw*unit,h=fh*unit,
  unit=unit,formname=session.formname,scrolls=all_scrolls}
end
function View:click(width,height,x,y,mousebutton)
 local layout=self:layout(width,height)
 if not layout then return false,'no_form' end
 if not number(x) or not number(y) or
  (mousebutton~=1 and mousebutton~=2) then
  return false,'invalid_pointer'
 end
 for i=#layout.controls,1,-1 do
  local ctl=layout.controls[i]
  if (ctl.kind=='button' or ctl.kind=='slot') and within(x,y,ctl) then
   if ctl.kind=='button' then
    self.selected=nil
    local fields={[ctl.field]='true'}
    if ctl.close then fields.quit='true' end
    return self.runtime:receiveFormFields(
     self.playername,layout.formname,fields)
   end
   local player=self.runtime.players[self.playername]
   if not player or not player.get_inventory then
    return false,'player_not_connected'
   end
   local inv=player:get_inventory()
   if ctl.index>inv:get_size(ctl.list) then
    return false,'invalid_slot'
   end
   local source=self.selected
   if not source then
    if inv:get_stack(ctl.list,ctl.index):is_empty() then
     return false,'empty_slot'
    end
    self.selected={list=ctl.list,index=ctl.index}
    return true,'selected'
   end
   if source.list==ctl.list and source.index==ctl.index then
    self.selected=nil
    return true,'deselected'
   end
   local stack=inv:get_stack(source.list,source.index)
   if stack:is_empty() then
    self.selected=nil
    return false,'empty_source'
   end
   local count=mousebutton==2 and 1 or stack:get_count()
   local ok,reason=self.runtime:movePlayerInventoryStack(self.playername,{
    from_list=source.list,from_index=source.index,
    to_list=ctl.list,to_index=ctl.index,count=count})
   if ok then self.selected=nil
   else self.message=tostring(reason) end
   return ok,reason
  end
 end
 return false,'outside_control'
end
function View:close()
 local session=self:session()
 if not session then return false,'no_form' end
 self.selected=nil
 return self.runtime:receiveFormFields(
  self.playername,session.formname,{quit='true'})
end
function View:wheel(width,height,x,y,amount)
 if not number(amount) or amount==0 then return false end
 local layout=self:layout(width,height)
 if not layout then return false end
 for name,scroll in pairs(layout.scrolls) do
  if within(x,y,scroll.clip) then
   local old=self.scrolls[name] or 0
   local new=clamp(old-amount*scroll.step,0,scroll.max)
   self.scrolls[name]=new
   return new~=old
  end
 end
 return false
end
local function label_for(stack,registered)
 local name=stack:get_name()
 local def=registered and registered[name]
 local title=def and def.description or name
 if type(title)~='string' or title=='' then title=name end
 return title
end
function View:draw(pass,width,height)
 local layout=self:layout(width,height)
 if not layout then return false end
 assert(pass and type(pass.plane)=='function' and
  type(pass.text)=='function','LÖVR formspec needs Pass')
 local player=self.runtime.players[self.playername]
 if not player or not player.get_inventory then return false end
 local inv=player:get_inventory()
 local registered=self.runtime.registry.items
 pass:push('state')
 pass:setViewPose(1,lovr.math.newMat4())
 pass:setProjection('orthographic')
 pass:setDepthTest()
 pass:setMaterial()
 pass:setColor(.10,.14,.19,.97)
 pass:plane(layout.x+layout.w/2,layout.y+layout.h/2,0,
  layout.w+22,layout.h+22)
 for _,ctl in ipairs(layout.controls) do
  local x,y=ctl.x+ctl.w/2,ctl.y+ctl.h/2
  if ctl.kind=='decoration' then
   pass:setColor(.19,.22,.28,.95)
   pass:plane(x,y,0,ctl.w,ctl.h)
  elseif ctl.kind=='label' then
   pass:setColor(.96,.97,.99,1)
   local clean=ctl.label:gsub('[%c]',''):sub(1,96)
   pass:text(clean,x,y,.1,math.max(11,layout.unit*.25))
  elseif ctl.kind=='button' then
   pass:setColor(.30,.39,.51,.97)
   pass:plane(x,y,0,ctl.w*.96,ctl.h*.94)
   local caption=ctl.label
   if ctl.item and ctl.item~='' then
    caption=label_for(self.runtime.api.ItemStack(ctl.item),registered)
   elseif caption=='' then caption=ctl.field end
   pass:setColor(.99,.99,1,1)
   pass:text(caption:sub(1,22),x,y,.1,
    clamp(layout.unit*.19,9,14))
  elseif ctl.kind=='slot' then
   local selected=self.selected and self.selected.list==ctl.list
    and self.selected.index==ctl.index
   if selected then pass:setColor(.97,.76,.29,.99)
   else pass:setColor(.28,.33,.41,.97) end
   pass:plane(x,y,0,ctl.w*.95,ctl.h*.95)
   if ctl.index<=inv:get_size(ctl.list) then
    local stack=inv:get_stack(ctl.list,ctl.index)
    if not stack:is_empty() then
     pass:setColor(.98,.98,.99,1)
     pass:text(label_for(stack,registered):sub(1,12),
      x,y-ctl.h*.12,.1,clamp(layout.unit*.15,9,12))
     pass:text(tostring(stack:get_count()),
      x+ctl.w*.23,y+ctl.h*.27,.1,clamp(layout.unit*.19,10,13))
    end
   end
  end
 end
 pass:setColor(1,1,1,1)
 pass:pop('state')
 return true
end
return View
