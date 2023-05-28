
Command = {}

function Command:new (o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

CommandFactory = {}

function CommandFactory.register(command)
    if not command or not command.name then
        minetest.debug("Cannot register unknown object as command")
    end
    minetest.debug("Registering command '"..command.name.."'")
    if not command.new then
        minetest.debug("Cannot register invalid command '"..command.name.."'")
    end
	CommandFactory[command.name] = command
end


SequenceCommand = Command:new() -- needs subcommands
function SequenceCommand:completed(weld_all_entity)
	return not self.subcommands or #self.subcommands == 0
end
function SequenceCommand:on_step(weld_all_entity)
	if not self.subcommands or #self.subcommands == 0 then return end
	local current_command = self.subcommands[1]
	current_command:on_step(weld_all_entity)
	if current_command:completed(weld_all_entity) then
		minetest.log("verbose", self.name .. " completed subcommand " .. current_command.name)
		table.remove(self.subcommands, 1)
		if #self.subcommands > 0 then
			minetest.log("verbose", self.name .. " next subcommand " .. self.subcommands[1].name)
		end
	end
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
		return CommandFactory["jump"]:new({target_pos = target_pos})
	else
		return CommandFactory["precision_move"]:new({target_pos = target_pos})
	end
end

MoveCommand = Command:new()
MoveCommand.name = "move"
function MoveCommand:new(o)
	o = o or Command:new({})
    setmetatable(o, self)
    self.__index = self
	o.last_diff = 10000000
	return o
end
function MoveCommand:completed(weld_all_entity)
	return #self.path == 0
end
function MoveCommand:on_step(weld_all_entity)
	if not self.path then
		if self.close_is_enough then
			self.path = weld_all_entity:find_path_close(self.target_pos)
		else
			self.path = weld_all_entity:find_path(self.target_pos)
		end
		if not self.path then
			self.path = {}
		end
	end
	if self.path and #self.path > 0 then
		local current_pos = weld_all_entity.object:get_pos()
		local pos_diff = vector.distance(current_pos, self.path[1])
		if pos_diff < 0.05 or (self.last_pos and has_passed_waypoint(self.last_pos, current_pos, self.path[1], 0.05)) then
			table.remove(self.path, 1)
			self.last_diff = 10000000
			self.stall = 0

			if #self.path == 0 then -- end of path
				weld_all_entity:stop_movement()
				self.inner_command = nil
			else
				self.inner_command = create_inner_move_command(weld_all_entity, self.path[1])
			end
		elseif pos_diff > self.last_diff + 0.05 then
			self.inner_command = create_inner_move_command(weld_all_entity, self.path[1], 0.5)
			self.last_diff = pos_diff
		elseif pos_diff > self.last_diff - 0.00001 then
			self.stall = self.stall + 1
			if self.stall > 5 then
				self.inner_command = create_inner_move_command(weld_all_entity, self.path[1])
				self.stall = 0
			end
		else
			self.stall = 0
			self.last_diff = pos_diff
		end
		if self.inner_command then
			self.inner_command:on_step(weld_all_entity)
			if self.inner_command:completed(weld_all_entity) then
				self.inner_command = nil
			end
		end
		self.last_pos = current_pos
	end
end

CommandFactory.register(MoveCommand)


RemoteControlCommand = Command:new()
RemoteControlCommand.name = "remote_control"

function RemoteControlCommand:completed(weld_all_entity)
	return false
end
function RemoteControlCommand:on_step(weld_all_entity)
	local controls = self.user:get_player_control()
	weld_all_entity.object:setyaw(self.user: get_look_horizontal() + 3.14 / 2)
	local multiplier = 0
	if controls.up then multiplier = 1 end
	if controls.down then multiplier = multiplier - 1 end
	--if controls.jump then multiplier = 1 end
	--if controls.sneak then multiplier = multiplier - 1 end
	if multiplier ~= 0 then
		weld_all_entity:change_local_dir(vector.multiply(self.user:get_look_dir(), multiplier))
	else
		weld_all_entity.object:set_velocity{x = 0, y = 0, z = 0}
	end
end

CommandFactory.register(RemoteControlCommand)


StopCommand = Command:new()
StopCommand.name = "stop"

function StopCommand:completed(weld_all_entity)
	return self.was_executed
end
function StopCommand:on_step (weld_all_entity)
	weld_all_entity:stop_movement()
	self.was_executed = true
end
CommandFactory.register(StopCommand)


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
		fracz = fracz > 0 and fracz or (1 + fracz)
		if dir.z > 0 then
			return 1 - (fracz + collisionbox[6])
		else
			return fracz + collisionbox[3]
		end
	else
		local _, fracx = math.modf(pos.x + .5)
		fracx = fracx > 0 and fracx or (1 + fracx)
		if dir.x > 0 then
			return 1 - (fracx + collisionbox[4])
		else
			return fracx + collisionbox[1]
		end
	end
end

JumpCommand = Command:new() -- needs target_pos
JumpCommand.name = "jump"

function JumpCommand:completed(weld_all_entity)
	return self.has_reached_target_pos
end
function JumpCommand:on_step(weld_all_entity)
	if is_near(weld_all_entity, self.target_pos, 0.05) then
		self.has_reached_target_pos = true
	elseif not self.has_reached_target_pos then
		local current_pos = weld_all_entity.object:get_pos()
		local must_jump = self.target_pos.y > current_pos.y + 0.001
		if must_jump and not self.has_jumped then
			local pos_diff = vector.subtract(self.target_pos, current_pos)
			local dir_2d = vector.normalize(vector.new(pos_diff.x, 0, pos_diff.z))
			local jump_vertical_speed = calc_jump_speed(1, get_gravity().y)
			local horizontal_distance = distance_to_wall(current_pos, dir_2d, weld_all_entity.initial_properties.collisionbox)
			local forward_speed = calc_max_forward_speed(1, jump_vertical_speed, get_gravity().y, horizontal_distance)
			weld_all_entity:jump(vector.add(vector.new(0, 1.1 * jump_vertical_speed, 0), vector.multiply(dir_2d, forward_speed * 0.98)))
			self.has_jumped = true
		else
			weld_all_entity:change_direction(self.target_pos)
		end
	end
end
CommandFactory.register(JumpCommand)


PrecisionMoveCommand = Command:new() -- needs target_pos, optionally face_dir
PrecisionMoveCommand.name = "precision_move"
function PrecisionMoveCommand:completed(weld_all_entity)
	return self.has_reached_target_pos
end
function PrecisionMoveCommand:on_step(weld_all_entity)
	if is_near(weld_all_entity, self.target_pos, 0.05) then
		weld_all_entity:stop_movement()
		self.has_reached_target_pos = true
	elseif not self.has_reached_target_pos then
		if self.face_dir then
			weld_all_entity:set_move_dir_and_face_dir(vector.subtract(self.target_pos, weld_all_entity.object:get_pos()), self.face_dir)
		else
			weld_all_entity:change_direction(self.target_pos)
		end
	end
end
CommandFactory.register(PrecisionMoveCommand)

OpenDoorCommand = Command:new() -- needs target_pos
OpenDoorCommand.name = "open_door"
function OpenDoorCommand:completed(weld_all_entity)
	return self.was_executed
end
function OpenDoorCommand:on_step(weld_all_entity)
	if is_near(weld_all_entity, self.target_pos, 2) then
		weld_all_entity:interact_with_door(self.target_pos, true)
		self.was_executed = true
	else
		minetest.log("info", "OpenDoorCommand: cannot interact, target too far away!")
	end
end
CommandFactory.register(OpenDoorCommand)

CloseDoorCommand = Command:new() -- needs target_pos
CloseDoorCommand.name = "close_door"
function CloseDoorCommand:completed(weld_all_entity)
	return self.was_executed
end
function CloseDoorCommand:on_step(weld_all_entity)
	if is_near(weld_all_entity, self.target_pos, 2) then
		weld_all_entity:interact_with_door(self.target_pos, false)
		self.was_executed = true
	else
		minetest.log("info", "CloseDoorCommand: cannot interact, target too far away!")
	end
end
CommandFactory.register(CloseDoorCommand)

MineCommand = Command:new() -- needs target_pos
MineCommand.name = "mine"
function MineCommand:completed(weld_all_entity)
	return self.has_interacted
end
function MineCommand:on_step(weld_all_entity)
	if is_near(weld_all_entity, self.target_pos, 2.9) then
		-- TODO: cooldown...
		weld_all_entity:mine(self.target_pos)
	else
		minetest.log("info", "MiningCommand: cannot mine, target too far away!")
	end
	self.has_interacted = true
end
CommandFactory.register(MineCommand)


PlaceCommand = Command:new() -- needs target_pos, node, optionally provide a function should_place_on that checks if the node should actually be placed
PlaceCommand.name = "place"
function PlaceCommand:completed(weld_all_entity)
	return self.has_interacted
end
function PlaceCommand:on_step(weld_all_entity)
	if is_near(weld_all_entity, self.target_pos, 2) and (not self.should_place_on or self.should_place_on(self.target_pos)) then
		local inv = weld_all_entity:get_inventory()		
		local stack = inv:remove_item("main", self.node)
		if stack:get_count() == 1 then
			weld_all_entity:place(self.target_pos, self.node)
			minetest.log("info", "PlaceObjectCommand: placed " .. self.node.name)
		else
			minetest.log("info", "PlaceObjectCommand: node " .. self.node.name .. " not in inventory!")
		end
	elseif self.should_place_on and not self.should_place_on(self.target_pos) then
		minetest.log("info", "PlaceObjectCommand: skip placement.")
	else
		minetest.log("info", "PlaceObjectCommand: cannot place object, target too far away!")
	end
	self.has_interacted = true
end
CommandFactory.register(PlaceCommand)


EnterMineCommand = SequenceCommand:new() -- needs target_pos
EnterMineCommand.name = "enter_mine"
function EnterMineCommand:new(o)
	o = o or SequenceCommand:new({})
    setmetatable(o, self)
    self.__index = self
	o.subcommands = {}
	table.insert(o.subcommands, CommandFactory["open_door"]:new({target_pos = o.target_pos}))
	table.insert(o.subcommands, CommandFactory["mine"]:new({target_pos = vector.subtract(o.target_pos, vector.new(0, 1, 0))}))
	table.insert(o.subcommands, CommandFactory["precision_move"]:new({target_pos = o.target_pos}))
	table.insert(o.subcommands, CommandFactory["precision_move"]:new({target_pos = vector.subtract(o.target_pos, vector.new(0, 1, 0))}))
	table.insert(o.subcommands, CommandFactory["close_door"]:new({target_pos = o.target_pos}))
    return o
end
CommandFactory.register(EnterMineCommand)


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


ScanAndMineLayerCommand = SequenceCommand:new() -- needs scan_center, preferred_z
ScanAndMineLayerCommand.name = "scan_and_mine_layer"
function ScanAndMineLayerCommand:new(o)
	o = o or SequenceCommand:new({})
    setmetatable(o, self)
    self.__index = self
	local commands = {}
	local mining_needed = scan(o.scan_center, o.preferred_z)
	for dx = 0, 2 do
		for dz = 0, 2 do
			if mining_needed[dx][dz] then
				table.insert(commands, CommandFactory["mine"]:new({target_pos = vector.offset(o.scan_center, dx, 0, dz)}))
			end
			if mining_needed[-dx][dz] then
				table.insert(commands, CommandFactory["mine"]:new({target_pos = vector.offset(o.scan_center, -dx, 0, dz)}))
			end
			if mining_needed[dx][-dz] then
				table.insert(commands, CommandFactory["mine"]:new({target_pos = vector.offset(o.scan_center, dx, 0, -dz)}))
			end
			if mining_needed[-dx][-dz] then
				table.insert(commands, CommandFactory["mine"]:new({target_pos = vector.offset(o.scan_center, -dx, 0, -dz)}))
			end
		end
	end
	o.subcommands = commands
    return o
end
CommandFactory.register(ScanAndMineLayerCommand)


local function place_on_air_or_vacuum(target_pos)
	local node_name = minetest.get_node(target_pos).name
	return node_name == "air" or node_name == "vacuum:vacuum"
end

local function create_place_command(target_pos, node, should_place_on)
	return CommandFactory["place"]:new({target_pos = target_pos, node = node, should_place_on = should_place_on})
end
-- Puts a stone on the side to be able to move down
-- preferred_z - if mining in z direction is preferred - this means blocks should be placed at the opposite direction
PlaceSidesCommand = SequenceCommand:new() -- needs mine_center, preferred_z
PlaceSidesCommand.name = "place_sides"
function PlaceSidesCommand:new(o)
	o = o or SequenceCommand:new({})
    setmetatable(o, self)
    self.__index = self
	local commands = {}
	if o.preferred_z then
		commands = {
			create_place_command(vector.offset(o.mine_center, 1, 0, 0), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum),
			create_place_command(vector.offset(o.mine_center, -1, 0, 0), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum)
		}
	else
		commands = {
			create_place_command(vector.offset(o.mine_center, 0, 0, 1), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum),
			create_place_command(vector.offset(o.mine_center, 0, 0, -1), { name = "omg_moonrealm:stone" }, place_on_air_or_vacuum)
		}
	end
	o.subcommands = commands
    return o
end
CommandFactory.register(PlaceSidesCommand)

MineNextLayerCommand = SequenceCommand:new() -- needs mine_center, bot_forward_dir
MineNextLayerCommand.name = "mine_next_layer"
function MineNextLayerCommand:new(o)
	o = o or SequenceCommand:new({})
    setmetatable(o, self)
    self.__index = self
	-- if mining in z direction is preferred
	local preferred_z = o.bot_forward_dir.z ~= 0
	local commands = {
		CommandFactory["mine"]:new({target_pos = o.mine_center}),
		CommandFactory["scan_and_mine_layer"]:new({scan_center = o.mine_center, preferred_z = preferred_z}),
		CommandFactory["place_sides"]:new({mine_center = o.mine_center, preferred_z = preferred_z}),
		CommandFactory["precision_move"]:new({target_pos = o.mine_center, o.bot_forward_dir})
	}
	o.subcommands = commands
    return o
end
CommandFactory.register(MineNextLayerCommand)

SetRotationCommand = Command:new() -- needs forward_dir
SetRotationCommand.name = "set_rotation"
function SetRotationCommand:completed(weld_all_entity)
	return self.has_reached_forward_dir
end
function SetRotationCommand:on_step(weld_all_entity)
	weld_all_entity:set_yaw_by_direction(self.forward_dir)
	self.has_reached_forward_dir = true
end
CommandFactory.register(SetRotationCommand)

LeaveMineCommand = SequenceCommand:new() -- needs target_pos (the exit trapdoor), optionally preferred_z
LeaveMineCommand.name = "leave_mine"
function LeaveMineCommand:new(o)
	o = o or SequenceCommand:new({})
    setmetatable(o, self)
    self.__index = self
	local commands = {}
	table.insert(commands, CommandFactory["precision_move"]:new({target_pos = vector.offset(o.target_pos, 0, -1, 0)}))
	table.insert(commands, CommandFactory["open_door"]:new({target_pos = o.target_pos}))
	table.insert(commands, CommandFactory["precision_move"]:new({target_pos = vector.offset(o.target_pos, 0, -.1, 0)}))
	table.insert(commands, CommandFactory["precision_move"]:new({target_pos = vector.subtract(o.target_pos, vector.new(1, 0, 0))}))
	table.insert(commands, CommandFactory["close_door"]:new({target_pos = o.target_pos}))
	o.subcommands = commands
    return o
end
CommandFactory.register(LeaveMineCommand)
