-- Host-driven transfers in a connected Luanti player InvRef.
-- This is the engine side of an inventory UI action, not a new mod API.
-- It works with the original allow/on_player_inventory_action callbacks.
local Transfers={}

local function positive_integer(value)
 return type(value)=='number' and value==math.floor(value)
  and value>0 and value<=65535
end

local function valid_slot(inv,list,index)
 return type(list)=='string' and list~='' and
  positive_integer(index) and index<=inv:get_size(list)
end

-- Only ordinary moves into an empty slot or a stackable slot are handled.
-- Swaps and cross-inventory moves must be supplied by a compatible backend
-- later, rather than treated as a successful but lossy transfer.
function Transfers.move(runtime,playername,request)
 assert(type(playername)=='string' and playername~='',
  'player inventory move requires player name')
 assert(type(request)=='table','player inventory move requires an action')
 local player=runtime.players[playername]
 if not player or type(player.get_inventory)~='function' then
  return false,'player_not_connected'
 end
 local inv=player:get_inventory()
 if not inv or type(inv.get_stack)~='function' or
  type(inv.set_stack)~='function' or
  type(inv.get_size)~='function' then
  return false,'inventory_unavailable'
 end
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
 if not destination:is_empty() and
  not destination:stackable(source) then
  return false,'swap_not_supported'
 end
 local capacity=destination:is_empty() and source:get_stack_max()
  or destination:get_free_space()
 local proposed=math.min(request.count,source:get_count(),capacity)
 if proposed<=0 then return false,'destination_full' end

 -- The callback sees the requested move after physical slot-capacity checks.
 -- A mod may narrow the count, or reject the move with zero.
 local info={from_list=from_list,from_index=from_index,
  to_list=to_list,to_index=to_index,count=proposed}
 local allowed=runtime:allowedInventoryAction(player,'move',inv,info)
 allowed=math.min(proposed,allowed)
 if allowed<=0 then return false,'not_allowed' end

 -- The origin/destination are read again after preflight to reject mods
 -- which modified slots inside a permission callback.
 if not source:equals(inv:get_stack(from_list,from_index)) or
  not destination:equals(inv:get_stack(to_list,to_index)) then
  return false,'inventory_changed_during_check'
 end
 local taken=source:take_item(allowed)
 local leftover=destination:add_item(taken)
 assert(leftover:is_empty(),'preflight transfer no longer fits')
 assert(inv:set_stack(from_list,from_index,source),
  'prevalidated source slot disappeared')
 assert(inv:set_stack(to_list,to_index,destination),
  'prevalidated destination slot disappeared')
 info.count=allowed
 -- Luanti notifies mods after the inventory has changed; original mods
 -- can then update selected recipes, output slots and formspec state.
 runtime:emit('on_player_inventory_action',player,'move',inv,info)
 return true,allowed
end

return Transfers
