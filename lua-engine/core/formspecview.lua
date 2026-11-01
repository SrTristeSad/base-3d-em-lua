-- Client-side formspec presentation for the standalone LÖVR host.
-- Reads the ORIGINAL text emitted by core.show_formspec; never asks mods to
-- produce a second layout or invents a server-side field event.
-- This is a supported-element renderer, not Luanti's full GUI renderer.
local Sprites=require('core.formspecsprites')
local View={}
View.__index=View
-- Items use their registered inventory_image (or the node's first tile),
-- never an invented icon catalog separate from Luanti's item definitions.
local function icon_for(runtime,name)
 local items=runtime.registry.items or {}
 local nodes=runtime.registry.nodes or {}
 local def=items[name] or nodes[name]
 if type(def)~='table' then return nil end
 local icon=def.inventory_image
 if type(icon)=='string' and icon~='' then return icon end
 icon=def.wield_image
 if type(icon)=='string' and icon~='' then return icon end
 local tiles=def.tiles
 if type(tiles)=='table' then
  local tile=tiles[1]
  if type(tile)=='table' then tile=tile.name end
  if type(tile)=='string' and tile~='' then return tile end
 end
 return nil
end
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
local function options(raw)
 local out,buf={},{}
 local i=1
 raw=raw or ''
 while i<=#raw do
  local c=raw:sub(i,i)
  if c=='\\' and i<#raw and raw:sub(i+1,i+1)==',' then
   buf[#buf+1]=',';i=i+2
  elseif c==',' then
   out[#out+1]=table.concat(buf);buf={};i=i+1
  else buf[#buf+1]=c;i=i+1 end
 end
 out[#out+1]=table.concat(buf)
 return out
end
local function last_utf8_boundary(s)
 local i=#s
 if i==0 then return 0 end
 while i>1 do
  local byte=s:byte(i)
  if byte<128 or byte>=192 then break end
  i=i-1
 end
 return i-1
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
  selected=nil,scrolls={},last_formname=nil,last_formspec=nil,
  values={},focus=nil,field_enter_close={},message=''},View)
end
function View:session()
 return self.runtime:getPlayerFormspec(self.playername)
end
function View:layout(width,height)
 assert(number(width) and number(height) and width>150 and height>150,
  'invalid formspec viewport')
 local session=self:session()
 if not session then
  self.last_formname=nil;self.last_formspec=nil
  self.selected=nil;self.scrolls={};self.values={}
  self.field_enter_close={};self.focus=nil
  return nil
 end
 if self.last_formname~=session.formname or
  self.last_formspec~=session.formspec then
  self.last_formname=session.formname
  self.last_formspec=session.formspec
  self.selected=nil;self.scrolls={};self.values={}
  self.field_enter_close={};self.focus=nil
 end
 local elements=session.elements or {}
 for _,e in ipairs(elements) do
  if e.name=='field_close_on_enter' then
   local p=parts(e.params)
   if p[1] and p[1]~='' then
    self.field_enter_close[p[1]]=(p[2]~='false')
   end
  end
 end
 local fw,fh=8,6
 local form_version=1
 for _,e in ipairs(elements) do
  if e.name=='formspec_version' then
   form_version=number(e.params) or 1
  end
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
 local named_styles,type_styles={},{}
 local function register_style(store,selector,params)
  for name in selector:gmatch('[^,]+') do
   local style=store[name] or {}
   for i=2,#params do
    local k,v=params[i]:match('^([^=]+)=(.*)$')
    if k=='bgimg' or k=='bgimg_middle' or k=='border' then
     style[k]=v
    end
   end
   store[name]=style
  end
 end
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
  if t=='style' or t=='style_type' then
   if p[1] and p[1]~='' then
    register_style(t=='style' and named_styles or type_styles,
     p[1],p)
   end
  elseif t=='scroll_container' then
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
    local base=t:gsub('_exit$','')
    local styles=type_styles[t] or type_styles[base] or {}
    local named=named_styles[field] or {}
    local function setting(key)return named[key] or styles[key] end
    add('button',x,y,w,h,{field=field,label=label or '',
     item=t:find('item_image_button',1,true) and p[3] or nil,
     texture=(t=='image_button' or t=='image_button_exit')
      and p[3] or nil,
     bgimg=setting('bgimg'),bgimg_middle=setting('bgimg_middle'),
     border=setting('border'),
     close=t:find('_exit',1,true)~=nil})
   end
  elseif t=='field' or t=='textarea' or t=='pwdfield' then
   local x,y=pair(p[1]);local w,h=pair(p[2])
   local field=p[3]
   if x and y and w and h and field and field~='' then
    if self.values[field]==nil then self.values[field]=p[5] or '' end
    add('field',x,y,w,h,{field=field,label=p[4] or '',
     multiline=t=='textarea',password=t=='pwdfield'})
   end
  elseif t=='checkbox' then
   local x,y=pair(p[1]);local field=p[2]
   if x and y and field and field~='' then
    if self.values[field]==nil then
     self.values[field]=(p[4]=='true') and 'true' or 'false'
    end
    add('checkbox',x,y,math.max(1.4,fw-x),.65,
     {field=field,label=p[3] or ''})
   end
  elseif t=='dropdown' then
   local x,y=pair(p[1])
   local w,h=pair(p[2])
   if not w then w=number(p[2]);h=.7 end
   local field=p[3]
   local entries=options(p[4])
   if x and y and w and h and field and field~='' and
    #entries>0 and #entries<=256 then
    local selected=clamp(floor(number(p[5]) or 1),1,#entries)
    if self.values[field]==nil then
     self.values[field]=selected
    end
    add('dropdown',x,y,w,h,{field=field,items=entries,
     index_event=p[6]=='true'})
   end
  elseif t=='item_image' then
   local x,y=pair(p[1]);local w,h=pair(p[2])
   add('item',x,y,w,h,{item=p[3]})
  elseif t=='image' or t=='box' or
   t=='background' or t=='background9' then
   local x,y=pair(p[1]);local w,h=pair(p[2])
   if (t=='background' or t=='background9') and p[4]=='true' then
    w,h=fw,fh
   end
   local nine
   if t=='background9' then nine=p[5]
   elseif t=='image' and form_version>=6 then nine=p[4] end
   add('decoration',x,y,w,h,{
    texture=t~='box' and p[3] or nil,
    middle=nine,label=p[3] or ''})
  end
 end
 for name,s in pairs(all_scrolls) do
  s.max=math.max(0,s.bottom-s.h)
  self.scrolls[name]=clamp(self.scrolls[name] or 0,0,s.max)
 end
 return {controls=controls,x=left,y=top,w=fw*unit,h=fh*unit,
  unit=unit,formname=session.formname,scrolls=all_scrolls}
end
-- Luanti submits currently edited fields on a button or close event.
-- User-authored values are kept only for the currently active formspec.
function View:form_values()
 local fields={}
 local layout=self:session()
 if not layout then return fields end
 local elements=layout.elements or {}
 for _,e in ipairs(elements) do
  local p=parts(e.params)
  if e.name=='field' or e.name=='textarea' or e.name=='pwdfield' then
   local field=p[3]
   if field and field~='' and self.values[field]~=nil then
    fields[field]=self.values[field]
   end
  elseif e.name=='checkbox' then
   local field=p[2]
   if field and field~='' and self.values[field]~=nil then
    fields[field]=self.values[field]
   end
  elseif e.name=='dropdown' then
   local field=p[3]
   if field and field~='' and self.values[field]~=nil then
    local entries=options(p[4])
    local index=self.values[field]
    if type(index)=='number' and entries[index] then
     fields[field]=p[6]=='true' and tostring(index) or entries[index]
    end
   end
  end
 end
 return fields
end
function View:submit(extra)
 local session=self:session()
 if not session then return false,'no_form' end
 local fields=self:form_values()
 for k,v in pairs(extra or {}) do fields[k]=v end
 return self.runtime:receiveFormFields(
  self.playername,session.formname,fields)
end
function View:textinput(input)
 if not self.focus then return false,'no_field_focus' end
 if type(input)~='string' or input=='' or input:find('%z') then
  return false,'invalid_input'
 end
 local old=self.values[self.focus]
 if type(old)~='string' or #old+#input>8192 then
  return false,'field_limit'
 end
 self.values[self.focus]=old..input
 return true
end
function View:keypressed(key)
 if not self.focus then return false,'no_field_focus' end
 local value=self.values[self.focus]
 if type(value)~='string' then return false,'invalid_focus' end
 if key=='backspace' then
  self.values[self.focus]=value:sub(1,last_utf8_boundary(value))
  return true
 elseif key=='return' or key=='kpenter' then
  local layout=self:layout(self.width or 1100,self.height or 800)
  local multiline=false
  if layout then
   for _,c in ipairs(layout.controls) do
    if c.kind=='field' and c.field==self.focus then
     multiline=c.multiline
     break
    end
   end
  end
  if multiline then
   return self:textinput('\n')
  end
  local fields={key_enter_field=self.focus}
  if self.field_enter_close[self.focus]~=false then
   fields.quit='true'
  end
  return self:submit(fields)
 end
 return false,'unsupported_key'
end
function View:click(width,height,x,y,mousebutton)
 local layout=self:layout(width,height)
 if not layout then return false,'no_form' end
 self.width,self.height=width,height
 if not number(x) or not number(y) or
  (mousebutton~=1 and mousebutton~=2) then
  return false,'invalid_pointer'
 end
 for i=#layout.controls,1,-1 do
  local ctl=layout.controls[i]
  if (ctl.kind=='button' or ctl.kind=='slot' or
   ctl.kind=='field' or ctl.kind=='checkbox' or
   ctl.kind=='dropdown') and within(x,y,ctl) then
   if ctl.kind=='field' then
    if mousebutton~=1 then return false,'unsupported_button' end
    self.focus=ctl.field
    self.selected=nil
    return true,'field_focused'
   elseif ctl.kind=='checkbox' then
    if mousebutton~=1 then return false,'unsupported_button' end
    self.focus=nil;self.selected=nil
    local selected=self.values[ctl.field]~='true'
    self.values[ctl.field]=selected and 'true' or 'false'
    return self:submit({[ctl.field]=self.values[ctl.field]})
   elseif ctl.kind=='dropdown' then
    if mousebutton~=1 then return false,'unsupported_button' end
    self.focus=nil;self.selected=nil
    local index=self.values[ctl.field] or 1
    index=index%#ctl.items+1
    self.values[ctl.field]=index
    local value=ctl.index_event and tostring(index) or ctl.items[index]
    return self:submit({[ctl.field]=value})
   elseif ctl.kind=='button' then
    self.focus=nil;self.selected=nil
    local fields={[ctl.field]='true'}
    if ctl.close then fields.quit='true' end
    return self:submit(fields)
   end
   self.focus=nil
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
 self.focus=nil
 return false,'outside_control'
end
function View:close()
 local session=self:session()
 if not session then return false,'no_form' end
 self.selected=nil;self.focus=nil
 return self:submit({quit='true'})
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
local function sprite_engine(view)
 local graphics=lovr and lovr.graphics
 if not graphics or type(graphics.newBuffer)~='function' or
  type(graphics.newTexture)~='function' then return nil end
 if not view.sprites then view.sprites=Sprites.new(graphics) end
 return view.sprites
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
 local sprites=sprite_engine(self)
 if sprites then sprites:beginFrame() end
 local function draw_sprite(tile,x,y,w,h,middle)
  if not sprites or not tile then return false end
  return sprites:draw(pass,tile,x,y,w,h,middle)
 end
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
   if not draw_sprite(ctl.texture,x,y,ctl.w,ctl.h,ctl.middle) then
    pass:setColor(.19,.22,.28,.95)
    pass:plane(x,y,0,ctl.w,ctl.h)
   end
  elseif ctl.kind=='item' then
   if not draw_sprite(icon_for(self.runtime,ctl.item),x,y,
     ctl.w*.9,ctl.h*.9) then
    pass:setColor(.97,.97,.98,1)
    pass:text((ctl.item or ''):sub(1,16),x,y,.1,
     clamp(layout.unit*.16,9,12))
   end
  elseif ctl.kind=='label' then
   pass:setColor(.96,.97,.99,1)
   local clean=ctl.label:gsub('[%c]',''):sub(1,96)
   pass:text(clean,x,y,.1,math.max(11,layout.unit*.25))
  elseif ctl.kind=='button' then
   local drawn_bg=draw_sprite(ctl.bgimg,x,y,
    ctl.w*.96,ctl.h*.94,ctl.bgimg_middle)
   if not drawn_bg and ctl.border~='false' then
    pass:setColor(.30,.39,.51,.97)
    pass:plane(x,y,0,ctl.w*.96,ctl.h*.94)
   end
   local textured=draw_sprite(ctl.texture or
    (ctl.item and icon_for(self.runtime,ctl.item)),
    x,y,ctl.w*.89,ctl.h*.85)
   local caption=ctl.label
   if ctl.item and ctl.item~='' and not textured then
    caption=label_for(self.runtime.api.ItemStack(ctl.item),registered)
   elseif caption=='' and not textured then caption=ctl.field end
   if caption~='' then
    pass:setColor(.99,.99,1,1)
    pass:text(caption:sub(1,22),x,y,.1,
     clamp(layout.unit*.19,9,14))
   end
   elseif ctl.kind=='field' then
   pass:setColor(self.focus==ctl.field and .33 or .22,
    self.focus==ctl.field and .40 or .28,.38,1)
   pass:plane(x,y,0,ctl.w*.98,ctl.h*.9)
   local value=self.values[ctl.field] or ''
   if ctl.password then value=string.rep('*',#value) end
   pass:setColor(.97,.97,.99,1)
   if ctl.label~='' then
    pass:text(ctl.label:sub(1,48),x,y-ctl.h*.52,.1,
     clamp(layout.unit*.16,9,13))
   end
   pass:text(value:sub(-96),x,y,.1,
    clamp(layout.unit*.18,10,14))
  elseif ctl.kind=='checkbox' then
   pass:setColor(.24,.31,.43,1)
   pass:plane(ctl.x+ctl.h*.28,y,0,ctl.h*.50,ctl.h*.50)
   pass:setColor(1,1,1,1)
   if self.values[ctl.field]=='true' then
    pass:text('X',ctl.x+ctl.h*.28,y,.1,
     clamp(layout.unit*.25,11,16))
   end
   pass:text(ctl.label:sub(1,40),x+ctl.h*.32,y,.1,
    clamp(layout.unit*.17,10,14))
  elseif ctl.kind=='dropdown' then
   pass:setColor(.28,.37,.49,1)
   pass:plane(x,y,0,ctl.w*.98,ctl.h*.92)
   pass:setColor(1,1,1,1)
   local chosen=ctl.items[self.values[ctl.field] or 1] or ''
   pass:text((chosen..'  v'):sub(1,50),x,y,.1,
    clamp(layout.unit*.18,10,14))
  elseif ctl.kind=='slot' then
   local selected=self.selected and self.selected.list==ctl.list
    and self.selected.index==ctl.index
   if selected then pass:setColor(.97,.76,.29,.99)
   else pass:setColor(.28,.33,.41,.97) end
   pass:plane(x,y,0,ctl.w*.95,ctl.h*.95)
   if ctl.index<=inv:get_size(ctl.list) then
    local stack=inv:get_stack(ctl.list,ctl.index)
    if not stack:is_empty() then
     local textured=draw_sprite(icon_for(self.runtime,stack:get_name()),
      x,y,ctl.w*.79,ctl.h*.79)
     pass:setColor(.98,.98,.99,1)
     if not textured then
      pass:text(label_for(stack,registered):sub(1,12),
       x,y-ctl.h*.12,.1,clamp(layout.unit*.15,9,12))
     end
     pass:text(tostring(stack:get_count()),
      x+ctl.w*.23,y+ctl.h*.27,.1,clamp(layout.unit*.19,10,13))
    end
   end
  end
 end
 if sprites then sprites:endFrame() end
 pass:setColor(1,1,1,1)
 pass:pop('state')
 return true
end
function View:release()
 if self.sprites then
  self.sprites:release()
  self.sprites=nil
 end
end
return View
