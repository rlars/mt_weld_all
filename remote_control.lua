
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


local function check_if_entrance(pointed_thing, user, rc_context)
	if is_entrance_node(pointed_thing.under) then
		minetest.debug("going to entrance: " .. dump(pointed_thing.under))
		local bot_forward_dir = get_trapdoor_direction(pointed_thing.under)
		rc_context.selected_obj:queue_task(TaskFactory["move"].create(vector.subtract(pointed_thing.under, bot_forward_dir)))
		rc_context.selected_obj:queue_task(TaskFactory["dig_mine"].create(pointed_thing.under)) -- 12, bot_forward_dir
			--CreateLeaveMineCommand(pointed_thing.under)
		rc_context.selected_obj = nil
		return true
	end
end

local function check_if_dropsite(pointed_thing, user, rc_context)
	local zone = MinMaxArea.find_area_in_list(zones.dropsites, pointed_thing.above)
	if zone then
		minetest.chat_send_player(user:get_player_name(), "Place items in given zone.")
		minetest.debug("drop into " .. dump(zone))
		rc_context.selected_obj:queue_task(TaskFactory["dump_items"].create(zone))
		return true
	end
end

local function check_if_close_on_floor(pointed_thing, user, rc_context)
	if vector.length(vector.subtract(user:get_pos(), pointed_thing.above)) < 1 then
		--user:set_pos(pointed_thing.under)
		rc_context.is_on_move_plate = not rc_context.is_on_move_plate
		if rc_context.is_on_move_plate then
			minetest.chat_send_player(user:get_player_name(), "Activated direct control of bot.")
			rc_context.selected_obj:assign_task(TaskFactory["direct_control"].create(user))
			rc_context.old_physics = user:get_physics_override()
			user:set_physics_override(
				{
					speed = 0,
					jump = 0
				}
			)
		else
			minetest.chat_send_player(user:get_player_name(), "Deactivated direct control of bot.")
			local current_task = rc_context.selected_obj:get_current_task()
			if current_task and current_task.name == "direct_control" then
				rc_context.selected_obj:get_current_task().completed = function() return true end
			end
			user:set_physics_override(rc_context.old_physics)
			rc_context.selected_obj = nil
		end
		return true
	end
end

local function check_if_sneak(pointed_thing, user, rc_context)
	if user:get_player_control().sneak then
		minetest.debug("create mine")
		rc_context.selected_obj:queue_task(
			-- todo: space must be free there!
			--CreateMoveCommand(vector.add(target_pos, get_trapdoor_direction(target_pos))),
			--CreateDigMineCommand(target_pos, 6)
			TaskFactory["dig_mine"].create(pointed_thing.above)
		)
		rc_context.selected_obj = nil
		return true
	end
end


local function use_tool(_, user, pointed_thing)
	local rc_context = get_player_table(user)
	local target_pos = nil
	if pointed_thing.type == "node" then
		if rc_context.selected_obj then
			if  check_if_entrance(pointed_thing, user, rc_context) or
				check_if_dropsite(pointed_thing, user, rc_context) or
				check_if_close_on_floor(pointed_thing, user, rc_context) or
				check_if_sneak(pointed_thing, user, rc_context)
				then
					-- do nothing, check_... has already consumed the action
			else
				minetest.debug("send to location")
				rc_context.selected_obj:queue_task(TaskFactory["move"].create(pointed_thing.above))
				rc_context.selected_obj = nil
			end
		end

	elseif pointed_thing.type == "object" then
		local obj = pointed_thing.ref:get_luaentity()
		if obj and obj.queue_task then
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
			local bots_in_range = {}
			local bot_hud_points = {}
			for _, object in ipairs(minetest.get_objects_inside_radius(player:get_pos(), 100)) do
				local entity = object.get_luaentity and object:get_luaentity()
				if entity and entity._owning_player_name and entity._owning_player_name == player:get_player_name() then
					table.insert(bots_in_range, object)
					table.insert(bot_hud_points, HudPoint.new(object:get_pos(), "([combine:48x48:8,8=weld_all_bot_back.png:^[resize:32x32)"))
				end
			end
			Hud.add_hud_points(theHud, player, bot_hud_points)
			zones_hud.bot_hud_points = bot_hud_points
			rc_context.bots_in_range = bots_in_range
			rc_context.using_rc = true
		else
			local zones_hud = datastore.get_table(player, "zones_hud")
			for i, object in ipairs(rc_context.bots_in_range) do
				if object and object.get_pos and object:get_pos() then -- if object is out of range, object:get_pos() might return nil
					zones_hud.bot_hud_points[i].pos = object:get_pos()
				end
			end
			Hud.update_hud(zones_hud.hud, player, true)
		end
	else
		if rc_context.using_rc then
			local zones_hud = datastore.get_table(player, "zones_hud")
			local theHud = zones_hud.hud
			Hud.remove(theHud, player, zones_hud.bot_hud_points)
			zones_hud.bot_hud_points = {}
			rc_context.using_rc = false
		end
	end
end
GlobalStepCallback.register_globalstep_per_player("is_holding_rc", is_holding_rc)
