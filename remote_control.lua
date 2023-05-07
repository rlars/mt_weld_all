
-- stores the settings of the user
local function get_player_table(player)
	return datastore.get_or_create_table(player, "weld_all_rc")
end

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
	local rc_context = get_player_table(user)
	local target_pos = nil
	if pointed_thing.type == "node" then
		target_pos = pointed_thing.above
		if rc_context.selected_obj then
			if is_entrance_node(pointed_thing.under) then
				minetest.debug("going to entrance: " .. dump(pointed_thing.under))
				local bot_forward_dir = get_trapdoor_direction(pointed_thing.under)
				rc_context.selected_obj:set_commands({
					CreateMoveCommand(vector.subtract(pointed_thing.under, bot_forward_dir)),
					CreateDigMineCommand(pointed_thing.under, 12, bot_forward_dir),
					CreateLeaveMineCommand(pointed_thing.under)
				})
				rc_context.selected_obj = nil
			elseif MinMaxArea.find_area_in_list(zones.dropsites, target_pos) then
				local zone = MinMaxArea.find_area_in_list(zones.dropsites, target_pos)
				minetest.debug("drop into " .. dump(zone))
				--target_pos = MinMaxArea.get_lowest_empty(zone)
				rc_context.selected_obj:set_commands({CreateDumpAllCommand(zone)})
			elseif vector.length(vector.subtract(user:get_pos(), target_pos)) < 1 then
				minetest.debug("toggle plate: ")
				--user:set_pos(pointed_thing.under)
				rc_context.is_on_move_plate = not rc_context.is_on_move_plate
				if rc_context.is_on_move_plate then
					rc_context.selected_obj:set_commands({CreateRemoteControlCommand(user)})
					rc_context.old_physics = user:get_physics_override()
					user:set_physics_override(
						{
							speed = 0,
							jump = 0
						}
					)
				else
					rc_context.selected_obj:set_commands({})
					user:set_physics_override(rc_context.old_physics)
					rc_context.selected_obj = nil
				end
			elseif user:get_player_control().sneak then
				minetest.debug("create mine")
				rc_context.selected_obj:set_commands({
					-- todo: space must be free there!
					CreateMoveCommand(vector.add(target_pos, get_trapdoor_direction(target_pos))),
					CreateDigMineCommand(target_pos, 6)})
					rc_context.selected_obj = nil
			else
				minetest.debug("send to location")
				rc_context.selected_obj:set_commands({CreateMoveCommand(target_pos)})
				rc_context.selected_obj = nil
			end
		end

	elseif pointed_thing.type == "object" then
		local obj = pointed_thing.ref:get_luaentity()
		if obj and obj.set_commands then
			if rc_context.selected_obj then
				show_inventory(user:get_player_name(), obj:get_inventory_name())
			else
				minetest.debug("selected")
				rc_context.selected_obj = obj
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

local function is_holding_rc(player, dtime)
	local item = player:get_wielded_item()
	local rc_context = get_player_table(player)
    if item:get_name() == "weld_all_bot:remote_control" then
		if not rc_context.using_rc then
			local zones_hud = datastore.get_table(player, "zones_hud")
			local theHud = zones_hud.hud
			local bots = {}
			for _, object in ipairs(minetest.get_objects_inside_radius(player:get_pos(), 100)) do
				local entity = object.get_luaentity and object:get_luaentity()
				if entity and entity._owning_player_name and entity._owning_player_name == player:get_player_name() then
					table.insert(bots, HudPoint.Create(object:get_pos(), "weld_all_bot_remote_control.png"))
				end
			end
			Hud.add_hud_points(theHud, player, bots)
			zones_hud.bots = bots
			rc_context.using_rc = true
		end
	else
		if rc_context.using_rc then
			local zones_hud = datastore.get_table(player, "zones_hud")
			local theHud = zones_hud.hud
			Hud.remove(theHud, player, zones_hud.bots)
			zones_hud.bots = {}
			rc_context.using_rc = false
		end
	end
end
GlobalStepCallback.register_globalstep_per_player("is_holding_rc", is_holding_rc)
