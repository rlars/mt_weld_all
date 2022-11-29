
Command = {}
Command.Types = {
	Stop = 0,
	Move = 1,
	PrecisionMove = 2,
	Jump = 3,
	Mining = 16,
	PlaceObject = 32,
	OpenDoor = 62,
	CloseDoor = 63,
	RemoteControl = 128,
	Combined = 256,
}

function Command.Create(type, name, subcommands)
	return {
		completed = function() return not subcommands or #subcommands == 0 end,
		on_step = function(weld_all_entity)
			if not subcommands or #subcommands == 0 then return end
			local current_command = subcommands[1]
			current_command.on_step(weld_all_entity)
			if current_command.completed(weld_all_entity) then
				minetest.log("verbose", name .. " completed subcommand " .. current_command.name)
				table.remove(subcommands, 1)
				if #subcommands > 0 then
					minetest.log("verbose", name .. " next subcommand " .. subcommands[1].name)
				end
			end
		end,
		-- initialized = false, -- is only set after call to init
		name = name,
		subcommands = subcommands,
		type = type
	}
end


-- if the waypoint has been passed in the previous time step with given threshold
local function has_passed_waypoint(previous_pos, current_pos, waypoint, threshold)
	local dir = vector.subtract(current_pos, previous_pos)
	local q2_p2 = vector.dot(current_pos, current_pos) - vector.dot(previous_pos, previous_pos)
	local t = (vector.dot(waypoint, dir) - q2_p2 / 2) / (vector.dot(dir, dir))
	-- clamp t between -0.5 and 0.5
	t = t < -0.5 and -0.5 or t > 0.5 and 0.5 or t
	local m = vector.multiply(vector.add(previous_pos, current_pos), 0.5)
	local closest_point = vector.add(m, vector.multiply(dir, t))
	return vector.distance(closest_point, waypoint) < threshold
end


local function is_near(self, pos, distance)
	local p = self.object:getpos()
	-- p.y = p.y + 0.5
	return vector.distance(p, pos) < distance
end


local function create_inner_move_command(weld_all_entity, target_pos, speed_multiplier)
	local current_pos = weld_all_entity.object:get_pos()
	if target_pos.y > current_pos.y + 0.4 then
		return CreateJumpCommand(target_pos)
	else
		return CreatePrecisionMoveCommand(target_pos, speed_multiplier)
	end
end


function CreateMoveCommand(target_pos, close_is_enough)
	local command = Command.Create(Command.Types.Move, "Move")
	local target_pos = vector.new(target_pos.x, target_pos.y, target_pos.z)
	local path = nil
	local last_diff = 10000000
	local last_pos = nil
	local stall = 0
	local inner_command = nil
	command.completed = function (weld_all_entity)
		return #path == 0
	end
	command.on_step = function (weld_all_entity)
		if not path then
			if close_is_enough then
				path = weld_all_entity:find_path_close(target_pos)
			else
				path = weld_all_entity:find_path(target_pos)
			end
			if not path then
				path = {}
			end
		end
		if path and #path > 0 then
			local current_pos = weld_all_entity.object:get_pos()
			local pos_diff = vector.distance(current_pos, path[1])
			if pos_diff < 0.05 or (last_pos and has_passed_waypoint(last_pos, current_pos, path[1], 0.05)) then
				table.remove(path, 1)
				last_diff = 10000000
				stall = 0

				if #path == 0 then -- end of path
					weld_all_entity:stop_movement()
				else
					inner_command = create_inner_move_command(weld_all_entity, path[1])
				end
			elseif pos_diff > last_diff + 0.05 then
				inner_command = create_inner_move_command(weld_all_entity, path[1], 0.5)
				last_diff = pos_diff
			elseif pos_diff > last_diff - 0.00001 then
				stall = stall + 1
				if stall > 5 then
					inner_command = create_inner_move_command(weld_all_entity, path[1])
					stall = 0
				end
			else
				stall = 0
				last_diff = pos_diff
			end
			if inner_command then
				inner_command.on_step(weld_all_entity)
				if inner_command.completed(weld_all_entity) then
					inner_command = nil
				end
			end
			last_pos = current_pos
		end
	end
	return command
end

function CreateRemoteControlCommand(plate_user)
	local command = Command.Create(Command.Types.RemoteControl, "RemoteControl")
	local plate_user = plate_user
	local path = nil
	command.completed = function (weld_all_entity)
		return false
	end
	command.on_step = function (weld_all_entity)
		controls = plate_user:get_player_control()
		weld_all_entity.object:setyaw(plate_user: get_look_horizontal())
		local multiplier = 0
		if controls.up then multiplier = 1 end
		if controls.down then multiplier = multiplier - 1 end
		--if controls.jump then multiplier = 1 end
		--if controls.sneak then multiplier = multiplier - 1 end
		if multiplier ~= 0 then
			weld_all_entity:change_local_dir(vector.multiply(plate_user:get_look_dir(), multiplier))
		else
			weld_all_entity.object:set_velocity{x = 0, y = 0, z = 0}
		end
	end
	return command
end


function CreateStopCommand()
	local command = Command.Create(Command.Types.Stop, "Stop")
	local was_executed = false
	command.completed = function (weld_all_entity)
		return was_executed
	end
	command.on_step = function (weld_all_entity)
		weld_all_entity:stop_movement()
		was_executed = true
	end
	return command
end


-- calculate the vertical speed needed to jump to the given height
local function calc_jump_speed(desired_height, gravity)
	return math.sqrt(-2 * gravity * desired_height)
end


-- calculate the forward speed needed to not get stuck at the node side
-- horizontal distance is the minimum distance to the side of the blocking (front) node
local function calc_max_forward_speed(height, speed, gravity, horizontal_distance)
	local time_to_height = (-speed + math.sqrt(speed*speed + 2 * gravity * height)) / gravity
	return horizontal_distance / time_to_height
end


-- estimates the minimum distance to a wall in the given direction
local function distance_to_wall(pos, dir, collisionbox)
	if math.abs(dir.z) > math.abs(dir.x) then
		local _, fracz = math.modf(pos.z + .5)
		if dir.z > 0 then
			return 1 - (fracz + collisionbox[6])
		else
			return fracz + collisionbox[3]
		end
	else
		local _, fracx = math.modf(pos.x + .5)
		if dir.x > 0 then
			return 1 - (fracx + collisionbox[4])
		else
			return fracx + collisionbox[1]
		end
	end
end


function CreateJumpCommand(target_pos)
	local command = Command.Create(Command.Types.Jump, "Jump")
	local target_pos = target_pos
	local has_jumped = false
	local has_reached_target_pos = false
	command.completed = function (weld_all_entity)
		return has_reached_target_pos
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 0.05) then
			has_reached_target_pos = true
		elseif not has_reached_target_pos then
			local current_pos = weld_all_entity.object:get_pos()
			local must_jump = target_pos.y > current_pos.y + 0.001
			if must_jump and not has_jumped then
				local pos_diff = vector.subtract(target_pos, current_pos)
				local dir_2d = vector.normalize(vector.new(pos_diff.x, 0, pos_diff.z))
				local jump_vertical_speed = calc_jump_speed(1, get_gravity().y)
				local horizontal_distance = distance_to_wall(current_pos, dir_2d, weld_all_entity.initial_properties.collisionbox)
				local forward_speed = calc_max_forward_speed(1, jump_vertical_speed, get_gravity().y, horizontal_distance)
				minetest.debug("jump_vertical_speed: " .. jump_vertical_speed)
				minetest.debug("horizontal_distance: " .. horizontal_distance)
				weld_all_entity:jump(vector.add(vector.new(0, 1.1 * jump_vertical_speed, 0), vector.multiply(dir_2d, forward_speed * 0.8)))
				has_jumped = true
			else
				minetest.debug("change_direction, jumping: " .. dump(weld_all_entity.jumping))
				weld_all_entity:change_direction(target_pos)
			end
		end
	end
	return command
end


-- otionally, provide a face_dir
function CreatePrecisionMoveCommand(target_pos, face_dir)
	local command = Command.Create(Command.Types.PrecisionMove, "PrecisionMove")
	local target_pos = target_pos
	local face_dir = face_dir
	local has_reached_target_pos = false
	command.completed = function (weld_all_entity)
		return has_reached_target_pos
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 0.05) then
			weld_all_entity:stop_movement()
			has_reached_target_pos = true
		elseif not has_reached_target_pos then
			if face_dir then
				weld_all_entity:set_move_dir_and_face_dir(vector.subtract(target_pos, weld_all_entity.object:get_pos()), face_dir)
			else
				weld_all_entity:change_direction(target_pos)
			end
		end
	end
	return command
end

function CreateOpenDoorCommand(target_pos)
	local command = Command.Create(Command.Types.OpenDoor, "OpenDoor")
	local target_pos = target_pos
	command.completed = function ()
		return true
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 2) then
			weld_all_entity:interact_with_door(target_pos, true)
		else
			minetest.log("info", "OpenDoorCommand: cannot interact, target too far away!")
		end
	end
	return command
end

function CreateCloseDoorCommand(target_pos)
	local command = Command.Create(Command.Types.CloseDoor, "CloseDoor")
	local target_pos = target_pos
	command.completed = function ()
		return true
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 2) then
			weld_all_entity:interact_with_door(target_pos, false)
		else
			minetest.log("info", "CloseDoorCommand: cannot interact, target too far away!")
		end
	end
	return command
end

function CreateMiningCommand(target_pos)
	local command = Command.Create(Command.Types.Mining, "Mining")
	local target_pos = target_pos
	local has_interacted = false
	command.completed = function ()
		return has_interacted
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 2.9) then
			weld_all_entity:mine(target_pos)
		else
			minetest.log("info", "MiningCommand: cannot mine, target too far away!")
		end
		has_interacted = true
	end
	return command
end


-- optionally provide a function should_place_on that checks if the node should actually be placed
function CreatePlaceCommand(target_pos, node, should_place_on)
	local command = Command.Create(Command.Types.PlaceObject, "PlaceObject")
	local target_pos = target_pos
	local has_interacted = false
	local node = node
	command.completed = function ()
		return has_interacted
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 2) and (not should_place_on or should_place_on(target_pos)) then
			local inv = weld_all_entity:get_inventory()		
			local stack = inv:remove_item("main", node)
			if stack:get_count() == 1 then
				weld_all_entity:place(target_pos, node)
				minetest.log("info", "PlaceObjectCommand: placed " .. node.name)
			else
				minetest.log("info", "PlaceObjectCommand: node " .. node.name .. " not in inventory!")
			end
		elseif should_place_on and not should_place_on(target_pos) then
			minetest.log("info", "PlaceObjectCommand: skip placement.")
		else
			minetest.log("info", "PlaceObjectCommand: cannot place object, target too far away!")
		end
		has_interacted = true
	end
	return command
end



function CreateEnterMineCommmand(pos)
	local commands = {}
	table.insert(commands, CreateOpenDoorCommand(pos))
	table.insert(commands, CreateMiningCommand(vector.subtract(pos, vector.new(0, 1, 0))))
	table.insert(commands, CreatePrecisionMoveCommand(pos))
	table.insert(commands, CreatePrecisionMoveCommand(vector.subtract(pos, vector.new(0, 1, 0))))
	table.insert(commands, CreateCloseDoorCommand(pos))
	return Command.Create(Command.Types.Combined, "EnterMineCommmand", commands)
end


-- scan an area of size 2x2 below the bot
-- preferred_z - if mining in z direction is preferred
local function scan(scan_center, preferred_z)
	local mining_needed = {}
	for dx = -2, 2 do
		mining_needed[dx] = {}
		for dz = -2, 2 do
			local name = minetest.get_node(vector.offset(scan_center, dx, 0, dz)).name
			mining_needed[dx][dz] = name == "omg_moonrealm:ironore"
		end
	end
	-- need to get rid of the stone between us and the ore
	mining_needed[-1][ 0] = mining_needed[-1][ 0] or mining_needed[-2][ 0]
	mining_needed[ 1][ 0] = mining_needed[ 1][ 0] or mining_needed[ 2][ 0]
	mining_needed[ 0][-1] = mining_needed[ 0][-1] or mining_needed[ 0][-2]
	mining_needed[ 0][ 1] = mining_needed[ 0][ 1] or mining_needed[ 0][ 2]

	-- for diagonal access, mine a block that is not used for travelling vertically, if possible
	mining_needed[-1][ 0] = mining_needed[-1][ 0] or (not preferred_z and (mining_needed[-1][-1] or mining_needed[-1][ 1]))
	mining_needed[ 1][ 0] = mining_needed[ 1][ 0] or (not preferred_z and (mining_needed[ 1][-1] or mining_needed[ 1][ 1]))
	mining_needed[ 0][-1] = mining_needed[ 0][-1] or (preferred_z and (mining_needed[-1][-1] or mining_needed[ 1][-1]))
	mining_needed[ 0][ 1] = mining_needed[ 0][ 1] or (preferred_z and (mining_needed[-1][ 1] or mining_needed[ 1][ 1]))
	return mining_needed
end


function CreateScanAndMineCommand(scan_center, preferred_z)
	local commands = {}
	local mining_needed = scan(scan_center, preferred_z)
	-- TODO: cooldown...
	for dx = 0, 2 do
		for dz = 0, 2 do
			if mining_needed[dx][dz] then
				table.insert(commands, CreateMiningCommand(vector.offset(scan_center, dx, 0, dz)))
			end
			if mining_needed[-dx][dz] then
				table.insert(commands, CreateMiningCommand(vector.offset(scan_center, -dx, 0, dz)))
			end
			if mining_needed[dx][-dz] then
				table.insert(commands, CreateMiningCommand(vector.offset(scan_center, dx, 0, -dz)))
			end
			if mining_needed[-dx][-dz] then
				table.insert(commands, CreateMiningCommand(vector.offset(scan_center, -dx, 0, -dz)))
			end
		end
	end
	return Command.Create(Command.Types.Combined, "ScanAndMineCommand", commands)
end


local function place_on_air_or_vacuum(target_pos)
	local node_name = minetest.get_node(target_pos).name
	return node_name == "air" or node_name == "vacuum:vacuum"
end

-- Puts a stone on the side to be able to move down
-- preferred_z - if mining in z direction is preferred - this means blocks should be placed at the opposite direction
function CreateFixSidesCommand(mine_center, preferred_z)
	local commands = {}
	if preferred_z then
		commands = {
			CreatePlaceCommand(vector.offset(mine_center, 1, 0, 0), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum),
			CreatePlaceCommand(vector.offset(mine_center, -1, 0, 0), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum)
		}
	else
		commands = {
			CreatePlaceCommand(vector.offset(mine_center, 0, 0, 1), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum),
			CreatePlaceCommand(vector.offset(mine_center, 0, 0, -1), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum)
		}
	end
	return Command.Create(Command.Types.Combined, "FixSidesCommand", commands)
end


function CreateMineNextLayerCommand(mine_center, bot_forward_dir)
	-- if mining in z direction is preferred
	local preferred_z = bot_forward_dir.z ~= 0
	local commands = {
		CreateMiningCommand(mine_center),
		CreateScanAndMineCommand(mine_center, preferred_z),
		CreateFixSidesCommand(mine_center, preferred_z),
		CreatePrecisionMoveCommand(mine_center, bot_forward_dir)
	}
	return Command.Create(Command.Types.Combined, "MineNextLayerCommand", commands)
end

function CreateSetRotationCommand(forward_dir)
	local command = Command.Create(Command.Types.PrecisionMove, "SetRotationCommand")
	local forward_dir = forward_dir
	local has_reached_forward_dir = false
	command.completed = function (weld_all_entity)
		return has_reached_forward_dir
	end
	command.on_step = function (weld_all_entity)
		weld_all_entity:set_yaw_by_direction(forward_dir)
		has_reached_forward_dir = true
	end
	return command
end


-- mines along a tunnel leading straight down
-- allows to scan the area around for minerals
function CreateDigMineCommand(target_pos, depth, bot_forward_dir)
	local command = Command.Create(Command.Types.Combined, "DigMineCommand")
	local target_pos = target_pos
	local depth = depth
	-- current depth measured from the entrance
	local current_depth = 0
	local state = 0
	local inner_command = nil
	command.completed = function ()
		return not inner_command and current_depth == depth
	end
	command.on_step = function (weld_all_entity)
		--inner_command = CreatePlaceCommand(target_pos, {name="xpanes:trapdoor_steel_bar_open", param1=14, param2=0})
		if state == 0 and not inner_command then
			inner_command = CreateEnterMineCommmand(target_pos)
		elseif state == 1 and not inner_command then
			current_depth = 0
			inner_command = CreateSetRotationCommand(bot_forward_dir)
		elseif state >= 2 and current_depth < depth and not inner_command then
			inner_command = CreateMineNextLayerCommand(vector.offset(target_pos, 0, -(current_depth + 1), 0), bot_forward_dir)
		end
		if inner_command then
			inner_command.on_step(weld_all_entity)
			if inner_command.completed(weld_all_entity) then
				inner_command = nil
				current_depth = current_depth + 1
				state = state + 1
			end
		else
			minetest.log("verbose", "DigMineCommand idle in state: " .. state .. " at depth " .. current_depth .. " of " .. depth)
		end
	end
	return command
end


local function max_manhattan_component(a, b)
	local diff = vector.subtract(a, b)
	return math.max(math.abs(diff.x), math.abs(diff.y), math.abs(diff.z))
end


function CreateDumpAllCommand(target_zone)
	local command = Command.Create(Command.Types.Combined, "DumpAllCommand")
	local target_zone = target_zone
	local inner_command = nil
	local current_depth = 0
	command.completed = function ()
		return not inner_command and current_depth == 9
	end
	command.on_step = function (weld_all_entity)
		-- init
		if not inner_command and current_depth < 9 then
			local target_pos = MinMaxArea.get_lowest_empty(target_zone)
			if vector.distance(weld_all_entity.object:get_pos(), target_pos) > 2 or max_manhattan_component(weld_all_entity.object:get_pos(), target_pos) < 0.7 then
				inner_command = CreateMoveCommand(target_pos, true)
			else
				inner_command = CreatePlaceCommand(target_pos, {name="omg_moonrealm:stone"})
			end
		end

		if inner_command then
			minetest.log("verbose", "Current command: " .. inner_command.name)
			inner_command.on_step(weld_all_entity)
			if inner_command.completed(weld_all_entity) then
				inner_command = nil
				current_depth = current_depth + 1
			end
		end
	end
	return command
end


-- target_pos is the exit trapdoor
function CreateLeaveMineCommand(target_pos, preferred_z)
	local target_pos = target_pos
	local commands = {}
	table.insert(commands, CreatePrecisionMoveCommand(vector.offset(target_pos, 0, -1, 0)))
	table.insert(commands, CreateOpenDoorCommand(target_pos))
	table.insert(commands, CreatePrecisionMoveCommand(vector.offset(target_pos, 0, -.1, 0)))
	table.insert(commands, CreatePrecisionMoveCommand(vector.subtract(target_pos, vector.new(1, 0, 0))))
	table.insert(commands, CreateCloseDoorCommand(target_pos))
	return Command.Create(Command.Types.Combined, "LeaveMineCommmand", commands)
end