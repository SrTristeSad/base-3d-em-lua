-- A deliberately limited player -> node interaction path.
-- Reuses registered Lua nodes, drops, ItemStack and host-connected InvRef.
-- Not equivalent to Luanti's full node_dig/item_place lifecycle yet.
local Inventory=require('core.inventory')
local Stack=require('core.itemstack')
local Digging=require('core.digging')
local Placement=require('core.placement')
local Attached=require('core.attached')
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
function Actions.dig(rt,player,where,default_only)
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
 if def.on_dig and not default_only then
  -- Mod-controlled diggers receive the genuine host Player ObjectRef.
  -- Per Luanti: nil is deprecated but means successful handling.
  -- Never duplicate callback-owned drops, node removal, or lifecycle.
  local result=def.on_dig(pos,old,player)
  if result==false then return false,'custom_dig_rejected' end
  return true,'custom_handled'
 end
 local wield=player:get_wielded_item()
 local drops=api.get_node_drops(old.name,wield:get_name())
 -- The original Luanti builtin sends mutable ItemStacks to
 -- preserve_metadata, allowing mods to keep enchantments, palette, etc.
 local oldmetadata=api.get_meta(pos):to_table()
 if def.preserve_metadata then
  local fields={}
  for key,value in pairs(oldmetadata.fields or {}) do
   fields[key]=value
  end
  for i,drop in ipairs(drops) do
   drops[i]=Stack.new(drop,rt.registry.items)
  end
  def.preserve_metadata(pos,old,fields,drops)
 end
 if not drops_fit(inventory,drops,rt.registry.items) then
  return false,'inventory_full'
 end
 if def.on_destruct then def.on_destruct(pos) end
 if not api.remove_node(pos) then return false,'remove_failed' end
 -- Player mining clears old node inventory/fields to avoid leaking a
 -- previous chest's data into another node at the same coordinates.
 api.get_meta(pos):from_table({fields={},inventory={}})
 if def.after_destruct then def.after_destruct(pos,old) end
 if def.after_dig_node then
  def.after_dig_node(pos,old,oldmetadata,player)
 end
 for _,drop in ipairs(drops) do
  local rest=inventory:add_item('main',drop)
  assert(rest:is_empty(),'inventory changed during drop transfer')
 end
 for _,callback in ipairs(rt.callbacks.on_dignode) do
  callback(pos,old,player)
 end
 -- The builtin node_dig path owns tool wear. A custom on_dig that calls
 -- core.node_dig reaches this path once; staged digging must not wear twice.
 -- Keep inventory changes made by callbacks instead of overwriting them.
 if not wield:is_empty() then
  local before=player:get_wielded_item()
  if before:equals(wield) then
   local params=Digging.params(def,wield)
   local tooldef=rt.registry.items[wield:get_name()]
   if tooldef and type(tooldef.after_use)=='function' then
    local mutated=wield:copy()
    local returned=tooldef.after_use(mutated,player,old,params) or mutated
    if player:get_wielded_item():equals(wield) then
     assert(player:set_wielded_item(Stack.new(returned,rt.registry.items)),
      'failed to commit custom after_use stack')
    end
   elseif params.wear>0 and not api.is_creative_enabled(name) then
    local updated=wield:copy()
    local wear=updated:get_wear()+params.wear
    if wear>=65536 then updated:clear()
    else updated:set_wear(wear) end
    assert(player:set_wielded_item(updated),'failed to apply tool wear')
   end
  end
 end
 -- Builtin falling.lua checks neighbors after the mining lifecycle.
 api.check_for_falling(pos)
 return true,drops
end
-- Explicit pointed_thing is required for full orientation-sensitive
-- interactions. Older callers may pass only a destination position.
local function pointed_for(pos,pointed)
 if pointed==nil then
  return {type='node',above=pos,
   under={x=pos.x,y=pos.y-1,z=pos.z}}
 end
 assert(type(pointed)=='table' and pointed.type=='node' and
  type(pointed.under)=='table' and type(pointed.above)=='table',
  'node interaction requires pointed_thing with under and above')
 local under,above=position(pointed.under),position(pointed.above)
 assert(above.x==pos.x and above.y==pos.y and above.z==pos.z,
  'placement destination must match pointed_thing.above')
 return {type='node',under=under,above=above}
end
local function update_wield_if_unchanged(player,before,after)
 if after==nil then return end
 local current=player:get_wielded_item()
 -- Callbacks may modify the player's inventory directly; never overwrite
 -- their newer stack state with an outdated returned value.
 if current:equals(before) then
  assert(player:set_wielded_item(Stack.new(after,before.registry)),
   'failed to update wield after custom placement')
 end
end
-- Minimal core.item_place_node equivalent for mods' custom on_place.
-- Work on the supplied ItemStack and return (remaining_stack, placed).
-- The caller, not this helper, commits the result to player's wield slot.
function Actions.default_place(rt,itemstack,player,pointed,param2,prevent_after_place)
 local _,name=player_inventory(rt,player)
 assert(type(pointed)=='table' and pointed.type=='node',
  'item_place_node requires a pointed node')
 local above=position(pointed.above)
 local hit=pointed_for(above,pointed)
 local stack=Stack.new(itemstack,rt.registry.items)
 local def=rt.registry.nodes[stack:get_name()]
 if not def or stack:is_empty() then return stack,nil end
 local api=rt.api
 local under=api.get_node(hit.under)
 local underdef=rt.registry.nodes[under.name]
 -- Luanti replaces the pointed node itself when it is buildable_to
 -- (snow/grass), instead of always placing at pointed_thing.above.
 local dest=(under.name~='air' and underdef and underdef.buildable_to)
  and hit.under or above
 if api.is_protected(dest,name) then return stack,nil end
 local old=api.get_node(dest)
 local olddef=rt.registry.nodes[old.name]
 if old.name~='air' and not (olddef and olddef.buildable_to) then
  return stack,nil
 end
 local oriented=Placement.param2(def,stack,player,hit,param2)
 local proposed={name=stack:get_name(),param1=0,param2=oriented}
 local attachment=api.get_item_group(proposed.name,'attached_node')
 if attachment~=0 and not Attached.check_attached(
   api,rt.registry.nodes,dest,proposed,attachment) then
  return stack,nil
 end
 if not api.set_node(dest,proposed) then return stack,nil end
 -- Replacing a buildable_to node must never leak its former metadata.
 -- Reset the old node's timer before callbacks can start a fresh one.
 api.get_node_timer(dest):stop()
 api.get_meta(dest):from_table({fields={},inventory={}})
 if def.on_construct then def.on_construct(dest) end
 local dont_take=false
 if not prevent_after_place and def.after_place_node then
  dont_take=def.after_place_node(position(dest),player,stack,{
   type='node',under=position(hit.under),above=position(hit.above)
  })==true
 end
 for _,callback in ipairs(rt.callbacks.on_placenode) do
  if callback(position(dest),api.get_node(dest),player,old,stack,{
   type='node',under=position(hit.under),above=position(hit.above)
  }) then dont_take=true end
 end
 if not dont_take then stack:take_item(1) end
 api.check_for_falling(dest)
 return stack,position(dest)
end
-- Mod-facing core.item_place: on_rightclick first, then default node
-- placement.  This is not an implicit call to a craftitem's on_place.
function Actions.item_place(rt,itemstack,placer,pointed,param2)
 local stack=Stack.new(itemstack,rt.registry.items)
 if not placer or not pointed or pointed.type~='node' then
  return stack,nil
 end
 local _,name=player_inventory(rt,placer)
 local dest=position(pointed.above)
 local hit=pointed_for(dest,pointed)
 local api=rt.api
 local under=api.get_node(hit.under)
 local underdef=rt.registry.nodes[under.name]
 local controls=type(placer.get_player_control)=='function'
  and placer:get_player_control() or {}
 if underdef and underdef.on_rightclick and not controls.sneak then
  if api.is_protected(hit.under,name) then return stack,nil end
  local outcome=underdef.on_rightclick(hit.under,under,placer,stack,hit)
  return outcome and Stack.new(outcome,rt.registry.items) or stack,nil
 end
 if stack:is_empty() then return stack,nil end
 local def=rt.registry.nodes[stack:get_name()]
 if not def then return stack,nil end
 return Actions.default_place(rt,stack,placer,hit,param2)
end
function Actions.place(rt,player,where,pointed)
 local pos=position(where)
 local _,name=player_inventory(rt,player)
 local api=rt.api
 local hit=pointed_for(pos,pointed)
 if api.is_protected(pos,name) then return false,'protected' end
 local wield=player:get_wielded_item()
 local old=api.get_node(pos)
 local olddef=rt.registry.nodes[old.name]
 -- Right-clicking the pointed node takes priority over the selected
 -- item's on_place, just as Luanti's default item_place does.
 local undernode=api.get_node(hit.under)
 local underdef=rt.registry.nodes[undernode.name]
 local controls=type(player.get_player_control)=='function'
  and player:get_player_control() or {}
 if underdef and underdef.on_rightclick and not controls.sneak then
  if api.is_protected(hit.under,name) then return false,'protected' end
  local outcome=underdef.on_rightclick(hit.under,undernode,
   player,wield:copy(),hit)
  update_wield_if_unchanged(player,wield,outcome)
  return true,'rightclick_handled'
 end
 if wield:is_empty() then return false,'empty_hand' end
 local def=rt.registry.items[wield:get_name()]
 if not def then return false,'unknown_item' end
 if def.on_place then
  local outcome=def.on_place(wield:copy(),player,hit)
  -- nil means "leave itemstack unchanged", not an empty stack.
  update_wield_if_unchanged(player,wield,outcome)
  return true,'custom_handled'
 end
 if def.type~='node' then return false,'not_placeable_node' end
 if old.name~='air' and not (olddef and olddef.buildable_to) and
   not (undernode.name~='air' and underdef and underdef.buildable_to) then
  return false,'occupied'
 end
 local remaining,placed=Actions.default_place(rt,wield,player,hit)
 if not placed then return false,'place_failed' end
 update_wield_if_unchanged(player,wield,remaining)
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
 local tool=player:get_wielded_item()
 local params=Digging.params(def,tool,rt.registry)
 if not params.diggable then return false,params.reason end
 sessions(rt)[name]={
  pos=pos,node=node,tool=tool,elapsed=0,time=params.time
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
  return false,'in_progress',math.min(1,current.elapsed/current.time)
 end
 sessions(rt)[name]=nil
 local ok,drops=Actions.dig(rt,player,current.pos)
 if not ok then return false,drops end

 return true,drops,1
end
function Actions.progress(rt,player)
 local _,name=player_inventory(rt,player)
 local current=sessions(rt)[name]
 if not current then return nil end
 if current.time==0 then return 1 end
 return math.min(1,current.elapsed/current.time)
end
return Actions
