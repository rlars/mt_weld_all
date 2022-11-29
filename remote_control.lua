

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

local function check_wielded_item(player, dtime)
	local item = player:get_wielded_item()
	local rc_context = datastore.get_or_create_table(player, "weld_all_rc")
    if item:get_name() == "weld_all_bot:remote_control" then
		if not rc_context.using_rc then
			local zones_hud = datastore.get_or_create_table(player, "zones_hud")
			if not zones_hud.hud then
				zones_hud.hud = Hud.Create()
			end
			local theHud = zones_hud.hud
			local bots = {}
			for _, object in ipairs(minetest.get_objects_inside_radius(player:get_pos(), 100)) do
				local entity = object.get_luaentity and object:get_luaentity()
				if entity and entity._owning_player_name and entity._owning_player_name == player:get_player_name() then
					table.insert(bots, HudPoint.Create(object:get_pos(), "weld_all_bot_remote_control.png"))
				end
			end
			Hud.add_hud_points(theHud, player, bots)
			rc_context.using_rc = true
		end
	else
		if rc_context.using_rc then
			local zones_hud = datastore.get_or_create_table(player, "zones_hud")
			if not zones_hud.hud then
				zones_hud.hud = Hud.Create()
			end
			local theHud = zones_hud.hud
			Hud.remove_all(theHud, player)
			rc_context.using_rc = false
		end
	end
end
GlobalStepCallback.register_globalstep_per_player("check_wielded_item", check_wielded_item)
