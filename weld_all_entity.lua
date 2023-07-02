
local serialize_inventory_list = function(list)
	local list_table = {}
	for _, stack in ipairs(list) do
		table.insert(list_table, stack:to_string())
	end
	return minetest.serialize(list_table)
end

local deserialize_inventory_list = function(list_string)
	local list_table = minetest.deserialize(list_string)
	local list = {}
	for _, stack in ipairs(list_table or {}) do
		table.insert(list, ItemStack(stack))
	end
	return list
end

WeldAllEntity = {
	initial_properties = {
		physical = true,
		collide_with_objects = true,
		--pointable = true,
		collisionbox = {-0.35, -0.5, -0.35, 0.35, 0.5, 0.35},
		visual_size = {x = 1, y = 1 },
		mesh = "weld_all_bot_weld_all_bot.obj",
		textures = { "weld_all_bot_yellow.png" },
		visual = "mesh",
		--static_save = false,
		use_texture_alpha = true,
	},
	_owning_player_name = nil,
	tasks = {},
	jumping = false,
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		self.object:remove()
	end,
	on_activate = function(self, staticdata, dtime_s)
		local state = minetest.deserialize(staticdata, true)
		self.tasks = {}
		if not state then return end
		self._name = state.name
		self._owning_player_name = state.owning_player_name
		if state.name and state.serialized_inventory then
			self:get_or_create_inventory():set_list("main", deserialize_inventory_list(state.serialized_inventory))
		end
	end,
	get_staticdata = function(self)
		if self._name then
			local inv = {}
			if self:get_inventory() then
				inv = self:get_inventory():get_list("main")
			end
			return minetest.serialize(
				{
					name = self._name,
					owning_player_name = self._owning_player_name,
					serialized_inventory = serialize_inventory_list(inv)
				})
			end
	end,
}


function WeldAllEntity.init_after_spawn(self, user)
	local time = os.date("!*t")
	local datetimestr = time.year .. time.month .. time.day .. "_" .. time.hour .. time.min .. time.sec
	-- set a most likely unique name
	self._name = datetimestr
	self._owning_player_name = user:get_player_name()

	-- if the inventory already exists, there exists a currently loaded entity with the same name. Count up.
	local check_existing_inv = self:get_inventory()
	local index = 2
	while check_existing_inv do
		self._name = datetimestr .. "_" .. tostring(index)
		index = index + 1
		check_existing_inv = self:get_inventory()
	end
	
	local inv = create_inventory(self:get_inventory_name())
	inv:set_size("main", 6)
	--inv:set_width("main",8)
end


function WeldAllEntity.get_or_create_inventory(self)
	local inv = self:get_inventory()
	if inv then return inv end
	return create_inventory(self:get_inventory_name())
end

function WeldAllEntity.get_inventory(self)
	return minetest.get_inventory({type="detached", name=self:get_inventory_name()})
end


function create_inventory(unique_name)
	return minetest.create_detached_inventory(unique_name,
		{
			allow_move = function(inv, from_list, from_index, to_list, to_index, count, player) return count end,
			-- Called when a player wants to move items inside the inventory.
			-- Return value: number of items allowed to move.
			
			allow_put = function(inv, listname, index, stack, player) return 1 end,
			-- Called when a player wants to put something into the inventory.
			-- Return value: number of items allowed to put.
			-- Return value -1: Allow and don't modify item count in inventory.
			
			allow_take = function(inv, listname, index, stack, player) return 1 end,
			-- Called when a player wants to take something out of the inventory.
			-- Return value: number of items allowed to take.
			-- Return value -1: Allow and don't modify item count in inventory.


			allow_metadata_inventory_move = function(inv, from_list, from_index, to_list, to_index, count, player) return count end,
			-- Called when a player wants to move items inside the inventory.
			-- Return value: number of items allowed to move.
			
			allow_metadata_inventory_put = function(inv, listname, index, stack, player) return -1 end,
			-- Called when a player wants to put something into the inventory.
			-- Return value: number of items allowed to put.
			-- Return value -1: Allow and don't modify item count in inventory.
			
			allow_metadata_inventory_take = function(inv, listname, index, stack, player) return -1 end,
			-- Called when a player wants to take something out of the inventory.
			-- Return value: number of items allowed to take.
			-- Return value -1: Allow and don't modify item count in inventory.
		}
	)
end


function show_inventory(playername, unique_name)
	minetest.show_formspec(playername, "weld_all_bot:" .. unique_name, 
	"size[8,9]"..
	"style_type[list;noclip=false;size=1.0,1.0;spacing=0.25,0.25]"..
	"list[detached:" .. unique_name .. ";main;0,0;8,4;]" ..
	"list[current_player;main;0,5;8,4;]")
end


function  WeldAllEntity.get_inventory_name(self)
	return self._owning_player_name .. "/weld_all_bot:" .. self._name
end


function WeldAllEntity.get_right_node_pos(self)
	local right = vector.rotate(vector.new(1, 0, 0), self.object:get_rotation())
	local direction = minetest.facedir_to_dir(minetest.dir_to_facedir(right, true))
	return vector.add(vector.round(self.object:getpos()), direction)
end


function WeldAllEntity.get_left_node_pos(self)
	local right = vector.rotate(vector.new(1, 0, 0), self.object:get_rotation())
	local direction = minetest.facedir_to_dir(minetest.dir_to_facedir(right, true))
	return vector.subtract(vector.round(self.object:getpos()), direction)
end



function WeldAllEntity.set_yaw_by_direction(self, direction)
	if self.jumping then return end
	self.object:setyaw(math.atan2(direction.z, direction.x))
end


function WeldAllEntity.step_forward(self, forward_speed)
	if self.jumping then return end
	local dir = vector.rotate(vector.new(1, 0, 0), self.object:get_rotation())
	dir.y = 0
	if not forward_speed then forward_speed = 1.5 end
	local velocity = vector.multiply(vector.normalize(dir), forward_speed)
	self.object:set_velocity(velocity)
end


-- initiates a jump, entity can´t change direction while in the air
function WeldAllEntity.jump(self, speed)
	if self.jumping then return end
	self.object:set_velocity(speed)
	self.jumping = true
	self.has_control_command = true
	--self.object:set_acceleration(get_gravity())
end


function WeldAllEntity.turn_towards(self, target_face_yaw)
	self.target_face_yaw = target_face_yaw
	self.target_pos = nil
	self.has_control_command = true
end


function WeldAllEntity.move_to(self, target_pos)
	self.target_pos = target_pos
	self.target_face_yaw = nil
	self.has_control_command = true
end


-- find a path to a point close to destination
function WeldAllEntity.find_path_close(self, destination)
	local paths = {}
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				if dx ~= 0 or dy ~= 0 or dz ~= 0 then
					local path = minetest.find_path(self.object:getpos(), vector.add(destination, vector.new(dx, dy, dz)), 10, 1, 1, "A*")
					if path and #path > 0 then
						table.insert(paths, path)
					end
				end
			end
		end
	end

	local shortest_path = nil
	local shortest_path_length = 10000000
	for _, path in ipairs(paths) do
		local overwrite_path = false
		if #path == shortest_path_length then
			overwrite_path = vector.distance(path[#path], self.object:get_pos()) < vector.distance(shortest_path[#shortest_path], self.object:get_pos())
		end
		if #path < shortest_path_length or overwrite_path then
			shortest_path = path
			shortest_path_length = #path
		end
	end

	if shortest_path then
		local path = shortest_path
		print("-- path length:" .. tonumber(#path))
		for _,pos in pairs(path) do

			minetest.add_particle({
				pos = pos,
				velocity = {x=0, y=0, z=0},
				acceleration = {x=0, y=0, z=0},
				expirationtime = 1,
				size = 4,
				collisiondetection = false,
				vertical = false,
				texture = "heart.png",
			})
		end
	end
	return shortest_path
end



function WeldAllEntity.find_path(self, destination)
	local path = minetest.find_path(self.object:getpos(), destination, 10, 1, 1, "A*")
	if path and #path > 0 then

		print("-- path length:" .. tonumber(#path))

		for _,pos in pairs(path) do

			minetest.add_particle({
				pos = pos,
				velocity = {x=0, y=0, z=0},
				acceleration = {x=0, y=0, z=0},
				expirationtime = 1,
				size = 4,
				collisiondetection = false,
				vertical = false,
				texture = "heart.png",
			})
		end
	end
	return path
end

function WeldAllEntity.get_owner(self)
	return minetest.get_player_by_name(self._owning_player_name)
end

function WeldAllEntity.stop_movement(self)
	self.object:setvelocity{x = 0, y = self.object:getvelocity().y, z = 0}
end

function is_entrance_node(pos)
	local node = minetest.get_node(pos)
	return string.match(node.name, "trapdoor")
end


local function is_trapdoor_open(pos)
	local node = minetest.get_node(pos)
	return string.match(node.name, "open") ~= nil
end

function WeldAllEntity.interact_with_door(self, pos, do_open)
	local node = minetest.get_node(pos)
	local nod = minetest.registered_nodes[node.name]
	if not is_entrance_node(pos) then
		minetest.log("info", "not an entrance: " .. node.name)
	end
	if is_trapdoor_open(pos) ~= do_open then
		--nod.on_rightclick(pos, nod, nil, nil, nil)
		doors.get(pos):toggle(self:get_owner())
	end
end


-- get node but use fallback for nil or unknown
local node_ok = function(pos, fallback)

	local node = minetest.get_node_or_nil(pos)

	if node and minetest.registered_nodes[node.name] then
		return node
	end

	return minetest.registered_nodes[(fallback or mobs.fallback_node)]
end


local function drop_items(pos, drops)
	for _, item in ipairs(drops) do

		minetest.add_item({
			x = pos.x - 0.5 + math.random(),
			y = pos.y - 0.5 + math.random(),
			z = pos.z - 0.5 + math.random()
		}, item)
	end
end


function WeldAllEntity.can_dig_drop(self, pos)

	if minetest.is_protected(pos, "") then
		return false
	end

	local node = node_ok(pos, "air").name
	local ndef = minetest.registered_nodes[node]

	if node ~= "ignore"
	and ndef
	and ndef.drawtype ~= "airlike"
	and not ndef.groups.level
	and not ndef.groups.unbreakable
	and not ndef.groups.liquid then

		local drops = minetest.get_node_drops(node)

		local inv = self:get_inventory()
		
		for _, item in ipairs(drops) do
			local leftover_items = inv:add_item("main", ItemStack(item))
		end

		minetest.remove_node(pos)

		return true
	end

	return false
end


local function on_step_internal(self, dtime, moveresult)
	if not moveresult.touching_ground then return end
	if self.target_pos then
		if vector.distance(self.target_pos, self.object:getpos()) > 0.05 then
			self:step_forward(1)
		else
			self.target_pos = nil
		end
	end
	if self.target_face_yaw then
		local current_face_yaw = self.object:get_yaw()
		if not MathHelpers.angles_are_close(current_face_yaw, self.target_face_yaw, 0.03) then
			local last_turn_speed = self.last_turn_speed or 0
			self:stop_movement()
			local turn_speed = math.min(6*math.abs(current_face_yaw - self.target_face_yaw), 6, 0.5 + last_turn_speed)
			self.object:set_yaw(current_face_yaw + math.sign(self.target_face_yaw - current_face_yaw) * turn_speed * dtime)
			self.last_turn_speed = turn_speed
		else
			self.object:set_yaw(self.target_face_yaw)
			self.target_face_yaw = nil
		end
	end
end



-- if there is a wall left and right to the object
function WeldAllEntity.has_left_right_support(self)
	local right_node_name = minetest.get_node(self:get_right_node_pos()).name
	local left_node_name = minetest.get_node(self:get_left_node_pos()).name
	return right_node_name ~= "air" and right_node_name ~= "vacuum:vacuum" and
		left_node_name ~= "air" and left_node_name ~= "vacuum:vacuum"
end


function WeldAllEntity.on_step(self, dtime, moveresult)
	local current_task = #self.tasks > 0 and self.tasks[1] or nil
	
	if not self.jumping and not self.has_control_command then
		self:stop_movement()
	end
	
	if self:has_left_right_support() then
		self.object:set_acceleration(vector.new(0, 0, 0))
	else
		self.object:set_acceleration(get_gravity())
	end

	if not current_task then return end
	
	if moveresult.touching_ground then
		self.jumping = false
	end

	if not current_task.initialized then
		current_task.initialized = true
	end

	self.has_control_command = false

	current_task:on_step(self, dtime)
	if current_task:completed(self) then
		table.remove(self.tasks, 1)
	end
	
	if not self.jumping then
		if self.has_control_command then
			on_step_internal(self, dtime, moveresult)
		else
			self:stop_movement()
		end
	end
end


function WeldAllEntity.mine(self, pos)
	self:can_dig_drop(pos)
end


function WeldAllEntity.place(self, pos, node)
	minetest.add_node(pos, node)
end


function WeldAllEntity.queue_task(self, task)
	table.insert(self.tasks, task)
end


function WeldAllEntity.assign_task(self, task)
	table.insert(self.tasks, 1, task)
end


function WeldAllEntity.get_current_task(self)
	return self.tasks[1]
end


minetest.register_entity("weld_all_bot:weld_all_bot", WeldAllEntity)


local function spawn_bot_at_pos(user, pos)
	local new_obj = minetest.add_entity(pos, "weld_all_bot:weld_all_bot")
	local weld_all_entity = new_obj:get_luaentity()
	weld_all_entity:init_after_spawn(user)
	return weld_all_entity
end


local function use_bot_spawner(itemstack, user, pointed_thing)
	if pointed_thing.type == "node" then
		local target_pos = pointed_thing.above
		spawn_bot_at_pos(user, target_pos)
		itemstack:set_count(itemstack:get_count() - 1)
		return itemstack
	end
end

minetest.register_craftitem("weld_all_bot:weld_all_bot_placer", {
	description = "Spawn a bot",
	inventory_image = "weld_all_bot_back.png",
	--on_use = use_tool,
	--on_secondary_use = use_tool,
	on_place = use_bot_spawner,
	stack_max = 1,

})


minetest.register_node("weld_all_bot:weld_all_bot_boxed", {
    description = "Weld All bot packed in a box",
    tiles = {"weld_all_bot_box_top.png", "weld_all_bot_box_top.png", "weld_all_bot_box_right.png", "weld_all_bot_box_left.png", "weld_all_bot_box_front.png", "weld_all_bot_box_front.png"},
    is_ground_content = false,
    groups = {dig_immediate = 3},
    paramtype2 = "facedir",
	on_dig = function(pos, node, digger)
		local dir = vector.subtract(vector.new(), minetest.facedir_to_dir(node.param2))
		minetest.remove_node(pos)
		local weld_all_entity = spawn_bot_at_pos(digger, pos)
		weld_all_entity:set_yaw_by_direction(dir)
		return true
	end
})
