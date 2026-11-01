-- Desktop-only 2D HUD for the standalone LÖVR demo. This is not the
-- Luanti HUD API: it visualizes the actual connected player's inventory.
local M={}
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
function M.select(player,index)
 assert(type(index)=='number' and index==math.floor(index),
  'wield index must be an integer')
 local slots=math.min(9,player:get_inventory():get_size('main'))
 if index<1 or index>slots then return false end
 player:set_wield_index(index)
 return true
end
function M.scroll(player,delta)
 assert(type(delta)=='number' and delta==delta and
  delta~=math.huge and delta~=-math.huge,
  'invalid hotbar wheel delta')
 local slots=math.min(9,player:get_inventory():get_size('main'))
 if slots==0 or delta==0 then return false end
 local steps=math.max(1,math.floor(math.abs(delta)))
 local index=player:get_wield_index()
 -- Scroll up selects the previous item, down selects the next.
 index=((index-1+(delta<0 and steps or -steps))%slots)+1
 player:set_wield_index(index)
 return true
end
function M.slots(player,registered)
 local slots={}
 local inventory=player:get_inventory()
 for i=1,math.min(9,inventory:get_size('main')) do
  local stack=inventory:get_stack('main',i)
  local name=stack:get_name()
  local definition=registered and registered[name] or nil
  local description=definition and definition.description or name
  if type(description)~='string' or description=='' then
   description=name
  end
  slots[i]={index=i,selected=i==player:get_wield_index(),
   name=name,count=stack:get_count(),wear=stack:get_wear(),
   label=description:sub(1,16),empty=stack:is_empty()}
 end
 return slots
end
-- Paint after the 3D world with an orthographic projection. Pass state
-- changes are restored, but the view/projection are reset by main.draw on
-- the next frame. A graphics mock can test this without a GPU.
function M.draw(pass,player,registered,width,height)
 assert(pass and type(pass.text)=='function' and
  type(pass.plane)=='function','HUD needs a LÖVR Pass')
 assert(type(width)=='number' and type(height)=='number' and
  width>0 and height>0,'invalid viewport')
 local slots=M.slots(player,registered)
 local count=#slots
 if count==0 then return end
 pass:push('state')
 pass:setViewPose(1,lovr.math.newMat4())
 -- This is the standalone desktop host, which provides lovr.math.
 pass:setProjection('orthographic')
 pass:setDepthTest()
 pass:setMaterial()
 local tile=clamp((width-36)/count,52,100)
 local left=(width-count*tile)/2
 local midy=height-48
 for i,slot in ipairs(slots) do
  local x=left+(i-.5)*tile
  if slot.selected then pass:setColor(.95,.78,.32,.94)
  else pass:setColor(.12,.17,.24,.82) end
  pass:plane(x,midy,0,tile-4,72)
  if slot.selected then pass:setColor(.19,.20,.25,1)
  else pass:setColor(.95,.95,.97,1) end
  pass:text(tostring(i),x-tile*.30,midy-20,.1,12)
  if not slot.empty then
   pass:text(slot.label,x,midy-5,.1,math.min(12,tile/8))
   pass:text(tostring(slot.count),x,midy+20,.1,12)
  end
 end
 pass:setColor(1,1,1,1)
 pass:text('+',width/2,height/2,.1,18)
 pass:text('WASD mover  |  mouse mirar  |  1-9/roda itens  |  F6 salvar',
  width/2,height-94,.1,13)
 pass:pop('state')
end
return M
