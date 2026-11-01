-- A deliberately limited player -> node interaction path.
-- Reuses registered Lua nodes, drops, ItemStack and host-connected InvRef.
-- Not equivalent to Luanti's full node_dig/item_place lifecycle yet.
local Inventory=require('core.inventory')
local Stack=require('core.itemstack')
local Digging=require('core.digging')
local Actions={}
local function position(pos)
 assert(type(pos)=='table' and
  type(pos.x)=='number' and pos.x==math.floor(pos.x) and
  type(pos.y)=='number' and pos.y==math.floor(pos.y) and
  type(pos.z)=='number' and pos.z==math.floor(pos.z),
  'player node action needs integer node coordinates')
 return {x=pos.x,y=pos.y,z=pos.z}
end
local function player_inventory(rt,player)
 assert(type(player)=='table' and
  type(player.get_player_name)=='function','host player required')
 local name=player:get_player_name()
 assert(rt.players[name]==player,'player must be connected to runtime')
 assert(type(player.get_inventory)=='function' and
  type(player.get_wielded_item)=='function' and
  type(player.set_wielded_item)=='function',
  'player needs a valid inventory and wield methods')
 local inv=player:get_inventory()
 assert(inv and type(inv.get_size)=='function' and
  type(inv.get_list)=='function' and type(inv.add_item)=='function',
  'player inventory has no supported main list')
 return inv,name
end
local function drops_fit(inv,items,registry)
 local size=inv:get_size('main')
 if size==0 then return #items==0 end
 local scratch=Inventory.new(registry)
 scratch:set_size('main',size)
 scratch:set_list('main',inv:get_list('main'))
 for _,item in ipairs(items) do
  local rest=scratch:add_item('main',item)
  if not rest:is_empty() then return false end
 end
 return true
end
function Actions.dig(rt,player,where)
 local pos=position(where)
 local inventory,name=player_inventory(rt,player)
 local api=rt.api
 if api.is_protected(pos,name) then return false,'protected' end
 local old=api.get_node(pos)
 if old.name=='air' or old.name=='ignore' then return false,'empty' end
 local def=rt.registry.nodes[old.name]
 if not def then return false,'unknown_node' end
 if def.diggable==false then return false,'not_diggable' end
 if def.can_dig and not def.can_dig(pos,player) then
  return false,'can_dig'
 end
 if def.on_dig then
  -- Original mods own their custom dig implementation, not this subset.
  return false,'custom_on_dig_unsupported'
 end
 local tool=player:get_wielded_item():get_name()
 local drops=api.get_node_drops(old.name,tool)
 if not drops_fit(inventory,drops,rt.registry.items) then
  return false,'inventory_full'
 end
 if def.on_destruct then def.on_destruct(pos) end
 if not api.remove_node(pos) then return false,'remove_failed' end
 if def.after_destruct then def.after_destruct(pos,old) end
 for _,drop in ipairs(drops) do
  local rest=inventory:add_item('main',drop)
  assert(rest:is_empty(),'inventory changed during drop transfer')
 end
 for _,callback in ipairs(rt.callbacks.on_dignode) do
  callback(pos,old,player)
 end
 return true,drops
end
function Actions.place(rt,player,where)
 local pos=position(where)
 local _,name=player_inventory(rt,player)
 local api=rt.api
 if api.is_protected(pos,name) then return false,'protected' end
 local wield=player:get_wielded_item()
 if wield:is_empty() then return false,'empty_hand' end
 local def=rt.registry.nodes[wield:get_name()]
 if not def then return false,'not_placeable_node' end
 if def.on_place then return false,'custom_on_place_unsupported' end
 local old=api.get_node(pos)
 local olddef=rt.registry.nodes[old.name]
 if old.name~='air' and not (olddef and olddef.buildable_to) then
  return false,'occupied'
 end
 local next_node={name=wield:get_name(),param1=0,param2=0}
 if not api.set_node(pos,next_node) then return false,'place_failed' end
 wield:take_item(1)
 assert(player:set_wielded_item(wield),'wield slot changed during place')
 if def.on_construct then def.on_construct(pos) end
 if def.after_place_node then def.after_place_node(pos,player,wield,{
  type='node',under=pos,above=pos}) end
 for _,callback in ipairs(rt.callbacks.on_placenode) do
  callback(pos,api.get_node(pos),player,old,wield,nil)
 end
 return true
end
-- Staged interaction: the host starts digging on mouse-down, advances
-- with a frame delta, and cancels on mouse-up or target/tool change.
-- The legacy digNodeAsPlayer remains intentionally instant for old callers.
local function sessions(rt)
 if not rt.playerDigSessions then rt.playerDigSessions={} end
 return rt.playerDigSessions
end
function Actions.cancel(rt,player)
 local _,name=player_inventory(rt,player)
 local active=sessions(rt)[name]~=nil
 sessions(rt)[name]=nil
 return active
end
function Actions.begin(rt,player,where)
 local pos=position(where)
 local _,name=player_inventory(rt,player)
 sessions(rt)[name]=nil
 local node=rt.api.get_node(pos)
 if node.name=='air' or node.name=='ignore' then return false,'empty' end
 local def=rt.registry.nodes[node.name]
 if not def then return false,'unknown_node' end
 if def.diggable==false then return false,'not_diggable' end
 if rt.api.is_protected(pos,name) then return false,'protected' end
 if def.can_dig and not def.can_dig(pos,player) then
  return false,'can_dig'
 end
 if def.on_dig then return false,'custom_on_dig_unsupported' end
 local tool=player:get_wielded_item()
 local params=Digging.params(def,tool,rt.registry)
 if not params.diggable then return false,params.reason end
 sessions(rt)[name]={
  pos=pos,node=node,tool=tool,elapsed=0,time=params.time,
  wear=params.wear
 }
 return true,params.time
end
function Actions.advance(rt,player,dt)
 assert(type(dt)=='number' and dt==dt and dt>=0 and
  dt~=math.huge,'invalid digging frame duration')
 local _,name=player_inventory(rt,player)
 local current=sessions(rt)[name]
 if not current then return false,'not_digging' end
 local tool=player:get_wielded_item()
 local target=rt.api.get_node(current.pos)
 if target.name~=current.node.name or
  (target.param1 or 0)~=(current.node.param1 or 0) or
  (target.param2 or 0)~=(current.node.param2 or 0) or
  not tool:equals(current.tool) then
  sessions(rt)[name]=nil
  return false,'target_changed'
 end
 if rt.api.is_protected(current.pos,name) then
  sessions(rt)[name]=nil
  return false,'protected'
 end
 current.elapsed=current.elapsed+dt
 if current.elapsed+1e-8<current.time then
  return false,'in_progress',min(1,current.elapsed/current.time)
 end
 sessions(rt)[name]=nil
 local ok,drops=Actions.dig(rt,player,current.pos)
 if not ok then return false,drops end
 if current.wear>0 then
  -- Only registered tools receive wear.  Clear the stack at 65535.
  local remaining=player:get_wielded_item()
  if remaining:equals(current.tool) then
   local wear=remaining:get_wear()+current.wear
   if wear>=65535 then remaining:clear()
   else remaining:set_wear(wear) end
   assert(player:set_wielded_item(remaining),
    'wield slot changed while applying wear')
  end
 end
 return true,drops,1
end
function Actions.progress(rt,player)
 local _,name=player_inventory(rt,player)
 local current=sessions(rt)[name]
 if not current then return nil end
 if current.time==0 then return 1 end
 return min(1,current.elapsed/current.time)
end
return Actions
