-- Standalone demo inventory + 2x2 crafting screen. Uses the real
-- connected Player Inventory (main/craft) and the registered Lua recipes.
-- This screen is not a replacement for the full Luanti formspec API.
local M={}
M.__index=M
local function finite(n)
 return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function slot_info(stack,registry,index)
 local name=stack:get_name()
 local def=registry[name]
 local label=def and def.description or name
 if type(label)~='string' or label=='' then label=name end
 return {index=index,name=name,count=stack:get_count(),
  wear=stack:get_wear(),empty=stack:is_empty(),label=label:sub(1,18)}
end
function M.new(player,api)
 assert(player and type(player.get_inventory)=='function' and
  type(player.get_wield_index)=='function','connected player required')
 assert(api and type(api.get_craft_result)=='function' and
  type(api.lua_engine_craft_inventory)=='function','crafting API required')
 local inv=player:get_inventory()
 assert(inv and inv:get_size('main')>=9,'main inventory needs nine slots')
 if inv:get_size('craft')==0 then
  inv:set_size('craft',4)
  inv:set_width('craft',2)
 end
 assert(inv:get_size('craft')==4 and inv:get_width('craft')==2,
  'demo 2x2 crafting grid required')
 return setmetatable({player=player,api=api,selected=1,
  selectedCraft=1,message='',open=false},M)
end
function M:main_slots()
 local inv=self.player:get_inventory()
 local result={}
 for i=1,inv:get_size('main') do
  result[i]=slot_info(inv:get_stack('main',i),self.api.registered_items,i)
 end
 return result
end
function M:craft_slots()
 local inv=self.player:get_inventory()
 local result={}
 for i=1,4 do
  result[i]=slot_info(inv:get_stack('craft',i),self.api.registered_items,i)
 end
 return result
end
function M:preview()
 local inv=self.player:get_inventory()
 local result=self.api.get_craft_result({
  method='normal',width=2,items=inv:get_list('craft')})
 return result.item
end
function M:select(index)
 local size=self.player:get_inventory():get_size('main')
 if not finite(index) or index~=math.floor(index) or
  index<1 or index>size then return false end
 self.selected=index
 return true
end
-- Move exactly one item from the selected main slot into a 2x2 cell.
-- All preconditions are checked before mutating either inventory list.
function M:put(slot)
 if not finite(slot) or slot~=math.floor(slot) or
  slot<1 or slot>4 then return false,'invalid craft cell' end
 local inv=self.player:get_inventory()
 local source=inv:get_stack('main',self.selected)
 local target=inv:get_stack('craft',slot)
 if source:is_empty() then return false,'select an item first' end
 if not target:is_empty() and not target:stackable(source) then
  return false,'craft cell contains a different item'
 end
 if not target:is_empty() and target:get_free_space()<1 then
  return false,'craft cell full'
 end
 local next_target=target:copy()
 if target:is_empty() then next_target=source:peek_item(1)
 else
  local left=next_target:add_item(source:peek_item(1))
  if not left:is_empty() then return false,'craft cell full' end
 end
 source:take_item(1)
 assert(inv:set_stack('craft',slot,next_target))
 assert(inv:set_stack('main',self.selected,source))
 self.selectedCraft=slot
 return true,next_target
end
-- Return one item from a crafting cell to the player's main inventory.
-- Return may fail when main inventory is full, without losing ingredients.
function M:take(slot)
 if not finite(slot) or slot~=math.floor(slot) or
  slot<1 or slot>4 then return false,'invalid craft cell' end
 local inv=self.player:get_inventory()
 local source=inv:get_stack('craft',slot)
 if source:is_empty() then return false,'empty craft cell' end
 local one=source:peek_item(1)
 if not inv:room_for_item('main',one) then
  return false,'main inventory full'
 end
 local left=inv:add_item('main',one)
 assert(left:is_empty(),'prechecked main inventory changed')
 source:take_item(1)
 assert(inv:set_stack('craft',slot,source))
 self.selectedCraft=slot
 return true,one
end
function M:craft()
 local ok,result=self.api.lua_engine_craft_inventory(
  self.player:get_inventory(),'craft','main')
 if not ok then return false,result end
 return true,result
end
function M:toggle()
 self.open=not self.open
 self.message=''
 return self.open
end
function M:layout(width,height)
 assert(finite(width) and finite(height) and width>200 and
  height>200,'invalid inventory viewport')
 local tile=clamp(math.min((width-80)/8,(height-155)/7),34,65)
 local cx=width/2
 local top=height*.20
 local mainTop=top+3.25*tile
 local mainLeft=cx-4*tile
 local craftLeft=cx-1.75*tile
 return {tile=tile,center=cx,top=top,
  mainLeft=mainLeft,mainTop=mainTop,
  craftLeft=craftLeft,craftTop=top+.55*tile,
  resultX=cx+2.0*tile,resultY=top+1.05*tile}
end
local function inside(x,y,cx,cy,half)
 return x>=cx-half and x<=cx+half and
  y>=cy-half and y<=cy+half
end
function M:hit(width,height,x,y)
 if not finite(x) or not finite(y) then return nil end
 local l=self:layout(width,height)
 local t=l.tile
 if inside(x,y,l.resultX,l.resultY,t*.45) then
  return 'result',1
 end
 for i=1,4 do
  local col=(i-1)%2
  local row=math.floor((i-1)/2)
  local sx=l.craftLeft+(col+.5)*t
  local sy=l.craftTop+(row+.5)*t
  if inside(x,y,sx,sy,t*.45) then return 'craft',i end
 end
 local main=self.player:get_inventory():get_size('main')
 for i=1,math.min(32,main) do
  local col=(i-1)%8
  local row=math.floor((i-1)/8)
  local sx=l.mainLeft+(col+.5)*t
  local sy=l.mainTop+(row+.5)*t
  if inside(x,y,sx,sy,t*.45) then return 'main',i end
 end
 return nil
end
function M:click(width,height,x,y,button)
 if not self.open then return false,'closed' end
 local kind,index=self:hit(width,height,x,y)
 if kind=='main' then
  self:select(index)
  self.message='Selected slot '..index
  return true,'selected'
 elseif kind=='craft' then
  local ok,reason
  if button==2 then ok,reason=self:take(index)
  else ok,reason=self:put(index) end
  self.message=ok and 'Craft grid updated' or reason
  return ok,reason
 elseif kind=='result' then
  local ok,result=self:craft()
  self.message=ok and ('Crafted '..result:get_name()) or result
  return ok,result
 end
 return false,'outside inventory'
end
function M:key(key)
 if not self.open then return false,'closed' end
 if key=='left' then return self:select(
  ((self.selected-2)%self.player:get_inventory():get_size('main'))+1)
 elseif key=='right' then return self:select(
  (self.selected%self.player:get_inventory():get_size('main'))+1)
 elseif key=='up' then
  return self:select(math.max(1,self.selected-8))
 elseif key=='down' then
  return self:select(math.min(
   self.player:get_inventory():get_size('main'),self.selected+8))
 elseif key=='c' then
  local ok,result=self:craft()
  self.message=ok and ('Crafted '..result:get_name()) or result
  return ok,result
 elseif key=='r' then
  local ok,result=self:take(self.selectedCraft)
  self.message=ok and 'Ingredient returned' or result
  return ok,result
 end
 local n=tonumber(key)
 if n and n==math.floor(n) and n>=1 and n<=4 then
  local ok,result=self:put(n)
  self.message=ok and 'Ingredient added' or result
  return ok,result
 end
 return false,'unhandled key'
end
-- Draw a compact menu on top of the existing scene using the same LÖVR
-- primitives as the demo hotbar. Hit testing shares this exact layout.
function M:draw(pass,width,height)
 if not self.open then return end
 assert(pass and type(pass.text)=='function' and
  type(pass.plane)=='function','LÖVR Pass required')
 local l=self:layout(width,height)
 local t=l.tile
 local main=self:main_slots()
 local craft=self:craft_slots()
 local result=self:preview()
 pass:push('state')
 pass:setViewPose(1,lovr.math.newMat4())
 pass:setProjection('orthographic')
 pass:setDepthTest()
 pass:setMaterial()
 pass:setColor(.08,.11,.16,.94)
 pass:plane(l.center,l.top+3.2*t,0,8.7*t,7.6*t)
 pass:setColor(1,1,1,1)
 pass:text('INVENTORY  -  E / ESC to close',
  l.center,l.top-.45*t,.1,math.max(12,t*.24))
 pass:text('2x2 CRAFTING',l.craftLeft+t,l.top+.15*t,.1,math.max(11,t*.22))
 local function drawslot(x,y,slot,selected)
  if selected then pass:setColor(.98,.79,.30,.98)
  else pass:setColor(.23,.29,.38,.97) end
  pass:plane(x,y,0,t*.91,t*.91)
  if selected then pass:setColor(.13,.16,.20,1)
  else pass:setColor(.96,.96,.98,1) end
  if slot and not slot.empty then
   pass:text(slot.label,x,y-t*.12,.1,clamp(t*.16,9,13))
   pass:text(tostring(slot.count),x,y+t*.24,.1,clamp(t*.20,10,14))
  end
 end
 for i=1,4 do
  local x=l.craftLeft+((i-1)%2+.5)*t
  local y=l.craftTop+(math.floor((i-1)/2)+.5)*t
  drawslot(x,y,craft[i],i==self.selectedCraft)
 end
 drawslot(l.resultX,l.resultY,
  {empty=result:is_empty(),label=result:get_name():sub(1,18),
   count=result:get_count()},not result:is_empty())
 for i=1,math.min(#main,32) do
  local x=l.mainLeft+((i-1)%8+.5)*t
  local y=l.mainTop+(math.floor((i-1)/8)+.5)*t
  drawslot(x,y,main[i],i==self.selected)
 end
 pass:setColor(1,1,1,1)
 pass:text('Click item to select; click craft cell to add 1; right-click cell returns 1',
  l.center,l.mainTop+4.25*t,.1,clamp(t*.19,10,13))
 pass:text('Click result or press C to craft; keys 1-4 add; R returns',
  l.center,l.mainTop+4.55*t,.1,clamp(t*.19,10,13))
 if self.message~='' then
  pass:text(self.message,l.center,l.mainTop+4.85*t,.1,
   clamp(t*.19,10,13))
 end
 pass:pop('state')
end
return M
