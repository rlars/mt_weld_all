

-- stores the physics settings of the user
-- TODO: move to per-user store
local old_physics = nil

local selected_obj = nil

local is_on_move_plate = false


-- TODO: find an entrance cose to the object
local function find_mine_entrance(pos)
	-- nodenames = "group:door"
	--minetest.find_node_near(pos, radius, nodenames
	--minetest.find_nodes_in_area(pos1, pos2, nodenames,
	--minetest.find_nodes_in_area_under_air(pos1, pos2, nodenames)
end


local function get_trapdoor_direction(pos)
	if not is_entrance_node(pos) then
		minetest.debug("Could not determine trapdoor direction!")
	end
	return minetest.facedir_to_dir(minetest.get_node(pos).param2)
end


local function use_tool(_, user, pointed_thing)
    	local target_pos = nil

	if pointed_thing.type == "node" then
		target_pos = pointed_thing.above
		if selected_obj then
			if is_entrance_node(pointed_thing.under) then
				minetest.debug("going to entrance: " .. dump(pointed_thing.under))
				local bot_forward_dir = get_trapdoor_direction(pointed_thing.under)
				selected_obj:set_commands({
					CreateMoveCommand(vector.subtract(pointed_thing.under, bot_forward_dir)),
					CreateDigMineCommand(pointed_thing.under, 12, bot_forward_dir),
					CreateLeaveMineCommand(pointed_thing.under)
				})
				selected_obj = nil
			elseif MinMaxArea.find_area_in_list(zones.dropsites, target_pos) then
				local zone = MinMaxArea.find_area_in_list(zones.dropsites, target_pos)
				minetest.debug("drop into " .. dump(zone))
				--target_pos = MinMaxArea.get_lowest_empty(zone)
				selected_obj:set_commands({CreateDumpAllCommand(zone)})
			elseif vector.length(vector.subtract(user:get_pos(), target_pos)) < 1 then
				minetest.debug("toggle plate: ")
				--user:set_pos(pointed_thing.under)
				is_on_move_plate = not is_on_move_plate
				if is_on_move_plate then
					selected_obj:set_commands({CreateRemoteControlCommand(user)})
					old_physics = user:get_physics_override()
					user:set_physics_override(
						{
							speed = 0,
							jump = 0
						}
					)
				else
					selected_obj:set_commands({})
					user:set_physics_override(old_physics)
					selected_obj = nil
				end
			elseif user:get_player_control().sneak then
				minetest.debug("create mine")
				selected_obj:set_commands({
					-- todo: space must be free there!
					CreateMoveCommand(vector.add(target_pos, get_trapdoor_direction(target_pos))),
					CreateDigMineCommand(target_pos, 6)})
				selected_obj = nil
			else
				minetest.debug("send to location")
				selected_obj:set_commands({CreateMoveCommand(target_pos)})
				selected_obj = nil
			end
		else
			local new_obj = minetest.add_entity(target_pos, "weld_all_bot:weld_all_bot")
			local weld_all_entity = new_obj:get_luaentity()
			weld_all_entity:init_after_spawn(user)
		end

	elseif pointed_thing.type == "object" then
		local obj = pointed_thing.ref:get_luaentity()
		if obj and obj.set_commands then
			if selected_obj then
				show_inventory(user:get_player_name(), obj:get_inventory_name())
			else
				minetest.debug("selected")
				selected_obj = obj
			end
		end
		return
	end
end


minetest.register_craftitem("weld_all_bot:remote_control", {
	description = "Remote control",
	inventory_image = "weld_all_bot_remote_control.png",
	on_use = use_tool,
	on_secondary_use = use_tool,
	on_place = use_tool

})
