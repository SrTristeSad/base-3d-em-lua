-- Player inventory transactions modeled after Luanti 5.18's
-- IMoveAction and player_inventory_Allow*/On* callback contracts.
-- Host-only entry points; never expose a method that fabricates a client.
local Transfers={}

local function positive_integer(value)
 return type(value)=='number' and value==math.floor(value)
  and value>0 and value<=65535
end
local function valid_slot(inv,list,index)
 return type(list)=='string' and list~='' and
  positive_integer(index) and index<=inv:get_size(list)
end
local function connected(runtime,name)
 assert(type(name)=='string' and name~='',
  'player inventory action requires player name')
 local player=runtime.players[name]
 if not player or type(player.get_inventory)~='function' then
  return nil,nil,'player_not_connected'
 end
 local inv=player:get_inventory()
 if not inv or type(inv.get_stack)~='function' or
  type(inv.set_stack)~='function' or
  type(inv.get_size)~='function' then
  return nil,nil,'inventory_unavailable'
 end
 return player,inv
end
local function unchanged(inv,list,index,expected)
 return valid_slot(inv,list,index) and
  expected:equals(inv:get_stack(list,index))
end
local function move_info(from_list,from_index,to_list,to_index,count)
 return {from_list=from_list,from_index=from_index,
  to_list=to_list,to_index=to_index,count=count}
end
local function event(runtime,player,action,inv,info)
 runtime:emit('on_player_inventory_action',player,action,inv,info)
end

function Transfers.move(runtime,playername,request)
 assert(type(request)=='table','player inventory move requires an action')
 local player,inv,reason=connected(runtime,playername)
 if not player then return false,reason end
 local from_list,from_index=request.from_list,request.from_index
 local to_list,to_index=request.to_list,request.to_index
 if not valid_slot(inv,from_list,from_index) or
  not valid_slot(inv,to_list,to_index) or
  not positive_integer(request.count) then
  return false,'invalid_slot_or_count'
 end
 if from_list==to_list and from_index==to_index then
  return false,'same_slot'
 end
 local source=inv:get_stack(from_list,from_index)
 local destination=inv:get_stack(to_list,to_index)
 if source:is_empty() then return false,'empty_source' end

 local incompatible=not destination:is_empty() and
  not destination:stackable(source)
 -- Luanti swaps the complete original source and destination stacks if the
 -- requested item does not fit; permissions are checked in BOTH directions.
 -- The original engine does not split the two stacks on an item swap.
 if incompatible then
  local forward=move_info(from_list,from_index,to_list,to_index,
   source:get_count())
  local reverse=move_info(to_list,to_index,from_list,from_index,
   destination:get_count())
  local can_forward=runtime:allowedInventoryAction(
   player,'move',inv,forward)
  local can_reverse=runtime:allowedInventoryAction(
   player,'move',inv,reverse)
  if can_forward<source:get_count() or
   can_reverse<destination:get_count() then
   return false,'not_allowed'
  end
  if not unchanged(inv,from_list,from_index,source) or
   not unchanged(inv,to_list,to_index,destination) then
   return false,'inventory_changed_during_check'
  end
  if source:get_count()>source:get_stack_max() or
   destination:get_count()>destination:get_stack_max() then
   return false,'invalid_stack_size'
  end
  assert(inv:set_stack(from_list,from_index,destination))
  assert(inv:set_stack(to_list,to_index,source))
  -- Upstream triggers onMove twice after a swap, with reversed endpoints.
  event(runtime,player,'move',inv,forward)
  -- A callback may have modified the new stack in the first (source) slot.
  reverse.count=inv:get_stack(from_list,from_index):get_count()
  event(runtime,player,'move',inv,reverse)
  return true,source:get_count()
 end

 local capacity=destination:is_empty() and source:get_stack_max()
  or destination:get_free_space()
 local proposed=math.min(request.count,source:get_count(),capacity)
 if proposed<=0 then return false,'destination_full' end
 local info=move_info(from_list,from_index,to_list,to_index,proposed)
 local allowed=runtime:allowedInventoryAction(player,'move',inv,info)
 allowed=math.min(proposed,allowed)
 if allowed<=0 then return false,'not_allowed' end
 if not unchanged(inv,from_list,from_index,source) or
  not unchanged(inv,to_list,to_index,destination) then
  return false,'inventory_changed_during_check'
 end
 local taken=source:take_item(allowed)
 local leftover=destination:add_item(taken)
 assert(leftover:is_empty(),'preflight transfer no longer fits')
 assert(inv:set_stack(from_list,from_index,source))
 assert(inv:set_stack(to_list,to_index,destination))
 info.count=allowed
 event(runtime,player,'move',inv,info)
 return true,allowed
end

-- A host holds the returned ItemStack (for a mouse cursor or external
-- inventory). This does not claim that a remote client is authoritative.
function Transfers.take(runtime,playername,request)
 assert(type(request)=='table','player inventory take requires an action')
 local player,inv,reason=connected(runtime,playername)
 if not player then return false,reason end
 local list,index=request.listname,request.index
 if not valid_slot(inv,list,index) or not positive_integer(request.count) then
  return false,'invalid_slot_or_count'
 end
 local source=inv:get_stack(list,index)
 if source:is_empty() then return false,'empty_source' end
 local proposed=math.min(request.count,source:get_count())
 local info={listname=list,index=index,stack=source:peek_item(proposed)}
 local allowed=runtime:allowedInventoryAction(player,'take',inv,info)
 allowed=math.min(proposed,allowed)
 if allowed<=0 then return false,'not_allowed' end
 if not unchanged(inv,list,index,source) then
  return false,'inventory_changed_during_check'
 end
 local taken=source:take_item(allowed)
 assert(inv:set_stack(list,index,source))
 info.stack=taken:copy()
 event(runtime,player,'take',inv,info)
 return true,taken
end

-- The trusted host MUST pass its actual mutable ItemStack (not an itemstring).
-- We decrement this exact stack after the inventory accepts the transfer,
-- so a partial put keeps its remainder with the host.
function Transfers.put(runtime,playername,request)
 assert(type(request)=='table','player inventory put requires an action')
 local player,inv,reason=connected(runtime,playername)
 if not player then return false,reason end
 local list,index,held=request.listname,request.index,request.stack
 if not valid_slot(inv,list,index) then return false,'invalid_slot_or_count' end
 if type(held)~='table' or type(held.get_count)~='function' or
  type(held.peek_item)~='function' or
  type(held.take_item)~='function' or
  type(held.equals)~='function' then
  return false,'invalid_held_stack'
 end
 if held:is_empty() then return false,'empty_held_stack' end
 local count=request.count or held:get_count()
 if not positive_integer(count) then return false,'invalid_slot_or_count' end
 local destination=inv:get_stack(list,index)
 if not destination:is_empty() and not destination:stackable(held) then
  return false,'destination_incompatible'
 end
 local capacity=destination:is_empty() and held:get_stack_max()
  or destination:get_free_space()
 local proposed=math.min(count,held:get_count(),capacity)
 if proposed<=0 then return false,'destination_full' end
 local original_held=held:copy()
 local info={listname=list,index=index,stack=held:peek_item(proposed)}
 local allowed=runtime:allowedInventoryAction(player,'put',inv,info)
 allowed=math.min(proposed,allowed)
 if allowed<=0 then return false,'not_allowed' end
 if not unchanged(inv,list,index,destination) or
  not original_held:equals(held) then
  return false,'inventory_changed_during_check'
 end
 local item=held:peek_item(allowed)
 local leftover=destination:add_item(item)
 assert(leftover:is_empty(),'preflight transfer no longer fits')
 assert(inv:set_stack(list,index,destination))
 held:take_item(allowed)
 info.stack=item:copy()
 event(runtime,player,'put',inv,info)
 return true,allowed
end

return Transfers
