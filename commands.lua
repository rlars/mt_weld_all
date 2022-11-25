
Command = {}
Command.Types = {
	Move = 1,
	PrecisionMove = 2,
	OpenDoor = 3,
	CloseDoor = 4,
	Mining = 5,
	PlaceObject = 6,
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
				minetest.debug(name .. " completed subcommand " .. current_command.name)
				table.remove(subcommands, 1)
				if #subcommands > 0 then
					minetest.debug(name .. " next subcommand " .. subcommands[1].name)
				end
			end
		end,
		-- initialized = false, -- is only set after call to init
		name = name,
		subcommands = subcommands,
		type = type
	}
end


local function is_near(self, pos, distance)
	local p = self.object:getpos()
	-- p.y = p.y + 0.5
	return vector.distance(p, pos) < distance
end


function CreateMoveCommand(target_pos, close_is_enough)
	local command = Command.Create(Command.Types.Move, "Move")
	local target_pos = vector.new(target_pos.x, target_pos.y, target_pos.z)
	local path = nil
	local last_diff = 10000000
	local stall = 0
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
			if path and #path > 0 then
				if path[1].y < weld_all_entity.object:get_pos().y then
					weld_all_entity:change_direction(path[1])
				else
					weld_all_entity:change_direction(path[1])
				end
			else
				path = {}
			end
		end
		if path and #path > 0 then
			local pos_diff = vector.distance(weld_all_entity.object:get_pos(), path[1])
			minetest.debug("follow_path pos_diff: " .. dump(pos_diff))
			if pos_diff < 0.05 then
				table.remove(path, 1)
				last_diff = 10000000
				stall = 0

				minetest.debug("follow_path: " .. #path)
				if #path == 0 then -- end of path
					weld_all_entity:stop_movement()
				else -- else next step, follow next path.
					weld_all_entity:change_direction(path[1])
				end
			elseif pos_diff > last_diff + 0.05 then
				minetest.debug("follow_path: " .. last_diff .. " vs " .. pos_diff)
				weld_all_entity:change_direction(path[1], 0.5)
				last_diff = pos_diff
			elseif pos_diff > last_diff - 0.00001 then
				stall = stall + 1
				if stall > 5 then
					weld_all_entity:change_direction(path[1])
					stall = 0
				end
			else
				stall = 0
				last_diff = pos_diff
			end
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
		if multiplier ~= 0 then
			weld_all_entity:change_local_dir(vector.multiply(plate_user:get_look_dir(), multiplier))
		else
			weld_all_entity.object:setvelocity{x = 0, y = 0, z = 0}
		end
	end
	return command
end

function CreatePrecisionMoveCommand(target_pos)
	local command = Command.Create(Command.Types.PrecisionMove, "PrecisionMove")
	local target_pos = target_pos
	local has_reached_target_pos = false
	command.completed = function (weld_all_entity)
		return has_reached_target_pos
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 0.05) then
			weld_all_entity:stop_movement()
			has_reached_target_pos = true
		elseif not has_reached_target_pos then -- else next step, follow next path.
			weld_all_entity:change_direction(target_pos)
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
			minetest.debug("OpenDoorCommand: cannot interact, target too far away!")
		end
	end
	return command
end

function CreateCloseDoorCommand(target_pos)
	local command = Command.Create(Command.Types.OpenDoor, "OpenDoor")
	local target_pos = target_pos
	command.completed = function ()
		return true
	end
	command.on_step = function (weld_all_entity)
		if is_near(weld_all_entity, target_pos, 2) then
			weld_all_entity:interact_with_door(target_pos, false)
		else
			minetest.debug("CloseDoorCommand: cannot interact, target too far away!")
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
			minetest.debug("MiningCommand: cannot mine, target too far away!")
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
			weld_all_entity:place(target_pos, node)
			minetest.debug("PlaceObjectCommand: placed " .. node.name)
		elseif should_place_on and not should_place_on(target_pos) then
			minetest.debug("PlaceObjectCommand: skip placement.")
		else
			minetest.debug("PlaceObjectCommand: cannot place object, target too far away!")
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
			mining_needed[dx][dz] = name == "moonrealm:ironore"
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
function CreateFixSidesCommand(mine_center, preferred_z)
	local commands = {}
	if preferred_z then
		commands = {
			CreatePlaceCommand(vector.offset(mine_center, 0, 0, 1), { name = "moonrealm:stone" }, place_on_air_or_vacuum),
			CreatePlaceCommand(vector.offset(mine_center, 0, 0, -1), { name = "moonrealm:stone" }, place_on_air_or_vacuum)
		}
	else
		commands = {
			CreatePlaceCommand(vector.offset(mine_center, 1, 0, 0), { name = "moonrealm:stone" }, place_on_air_or_vacuum),
			CreatePlaceCommand(vector.offset(mine_center, -1, 0, 0), { name = "moonrealm:stone" }, place_on_air_or_vacuum)
		}
	end
	return Command.Create(Command.Types.Combined, "FixSidesCommand", commands)
end


function CreateMineNextLayerCommand(mine_center, preferred_z)
	minetest.debug("mining: " .. dump(mine_center))
	local commands = {
		CreateMiningCommand(mine_center),
		CreateScanAndMineCommand(mine_center, preferred_z),
		CreateFixSidesCommand(mine_center, preferred_z),
		CreatePrecisionMoveCommand(mine_center)
	}
	return Command.Create(Command.Types.Combined, "MineNextLayerCommand", commands)
end


-- mines along a tunnel leading straight down
-- allows to scan the area around for minerals
function CreateDigMineCommand(target_pos, depth, preferred_z)
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
			current_depth = 1
			state = 5
		elseif state > 1 and current_depth < depth and not inner_command then
			inner_command = CreateMineNextLayerCommand(vector.offset(target_pos, 0, -(current_depth + 1), 0), preferred_z)
		end
		if inner_command then
			inner_command.on_step(weld_all_entity)
			if inner_command.completed(weld_all_entity) then
				inner_command = nil
				current_depth = current_depth + 1
				state = state + 1
			end
		else
			minetest.debug("DigMineCommand idle in state: " .. state .. " at depth " .. current_depth .. " of " .. depth)
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
				inner_command = CreatePlaceCommand(target_pos, {name="default:sand"})
			end
		end

		if inner_command then
			minetest.debug("Current command: " .. inner_command.name)
			inner_command.on_step(weld_all_entity)
			if inner_command.completed(weld_all_entity) then
				inner_command = nil
				current_depth = current_depth + 1
			end
		end
	end
	return command
end
