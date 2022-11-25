
WeldAllEntity = {
	initial_properties = {
		physical = true,
		collide_with_objects = true,
		--pointable = true,
		collisionbox = {-0.35, -0.5, -0.35, 0.35, 0.5, 0.35},
		visual_size = {x = 4, y = 4 },
		mesh = "weld_all_bot_weld_all_bot.obj",
		textures = { "weld_all_bot_yellow.png" },
		visual = "mesh",
		--static_save = false,
		use_texture_alpha = true,
	},
	commands = {},
	on_punch = function(self, puncher, time_from_last_punch, tool_capabilities, dir, damage)
		self.object:remove()
	end,
}


function get_inventory(unique_name)
	return minetest.get_inventory({type="detached", name=unique_name})
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
	self.object:setyaw(math.atan2(direction.z, direction.x) - math.pi / 2)
end


-- change direction to destination and velocity vector.
function WeldAllEntity.change_direction(self, destination, forward_speed)
	local position = self.object:getpos()
	local direction = vector.subtract(destination, position)
	--direction.y = 0
	if not forward_speed then forward_speed = 1.5 end
	local velocity = vector.multiply(vector.normalize(direction), forward_speed)
	if direction.y > 0.01 then
		velocity.y = 5
	end
  
	self.object:setvelocity(velocity)
	self:set_yaw_by_direction(direction)
end

-- turn according to a vector in local coordinates
function WeldAllEntity.change_local_dir(self, dir, forward_speed)
	dir.y = 0
	if not forward_speed then forward_speed = 1.5 end
	local velocity = vector.multiply(vector.normalize(dir), 1.5)
  
	self.object:setvelocity(velocity)
	self:set_yaw_by_direction(dir)
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

function WeldAllEntity.stop_movement(self)
	self.object:setvelocity{x = 0, y = 0, z = 0}
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
	minetest.debug("checking entrance: " .. dump(pos))
	if not is_entrance_node(pos) then
		minetest.debug("not an entrance: " .. node.name)
	end
	if is_trapdoor_open(pos) ~= do_open then
		--minetest.debug(dump(nod))
		nod.on_rightclick(pos, nod, nil, nil, nil)
		--nod.on_rightclick(pos, nod, self.object, nil, nil)
		--doors.get(pos):toggle(self.object)
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
		inv:add_item("main", ItemStack(item))
	end
end


local can_dig_drop = function(pos)

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

		local inv = get_inventory("my_test_inv")
		-- TODO: move inventory creation to object loading / initialization
		if not inv then inv = create_inventory("my_test_inv") end

		minetest.remove_node(pos)

		return true
	end

	return false
end



-- if there is a wall left and right to the object
function WeldAllEntity.has_left_right_support(self)
	local right_node_name = minetest.get_node(self:get_right_node_pos()).name
	local left_node_name = minetest.get_node(self:get_left_node_pos()).name
	return right_node_name.name ~= "air" and right_node_name.name ~= "vacuum:vacuum" and
		left_node_name.name ~= "air" and left_node_name.name ~= "vacuum:vacuum"
end


function WeldAllEntity.on_step(self)
	local current_command = #self.commands > 0 and self.commands[1] or nil

	if not current_command then return end

	if not current_command.initialized then
		current_command.initialized = true
		if current_command.type == Command.Types.Combined then
		end
	end

	current_command.on_step(self)
	if current_command.completed(self) then
		table.remove(self.commands, 1)
	end
	
	if self:has_left_right_support() then
		self.object:set_acceleration(vector.new(0, 0, 0))
	else
		self.object:set_acceleration(vector.new(0, -9, 0))
	end
end


function WeldAllEntity.mine(self, pos)
	can_dig_drop(pos)
end


function WeldAllEntity.place(self, pos, node)
	minetest.add_node(pos, node)
end


function WeldAllEntity.set_commands(self, commands)
	self.path = {}
	self.commands = commands
end


minetest.register_entity("weld_all_bot:weld_all_bot", WeldAllEntity)
