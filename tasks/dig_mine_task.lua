local dig_mine_task_factory = {name = "dig_mine"}

-- mines along a tunnel leading straight down
-- allows to scan the area around for minerals
DigMineTask = CommandBasedTask:new()

function DigMineTask:new (o)
    o = o or CommandBasedTask:new({})
    o.name = dig_mine_task_factory.name
    setmetatable(o, self)
    self.__index = self
    o.current_depth = 0
    o.state = -1
    return o
end

function DigMineTask:completed()
    return not self.command and self.current_depth == self.depth
end

function DigMineTask:on_step(weld_all_entity) --dtime
    --inner_command = CreatePlaceCommand(target_pos, {name="xpanes:trapdoor_steel_bar_open", param1=14, param2=0})
    minetest.log("info", "DigMineTask state " .. self.state)
    minetest.log("info", "DigMineTask depth " .. self.current_depth)
    if self.state == -1 and not self.command then
        self.command = CommandFactory["move"]:new({target_pos = self.target_pos})
    elseif self.state == 0 and not self.command then
        self.command = CommandFactory["enter_mine"]:new({target_pos = self.target_pos})
    elseif self.state == 1 and not self.command then
        self.current_depth = 0
        self.command = CommandFactory["set_rotation"]:new({forward_dir = self.bot_forward_dir})
    elseif self.state >= 2 and self.current_depth < self.target_depth and not self.command then
        self.command = CommandFactory["mine_next_layer"]:new({mine_center = vector.offset(self.target_pos, 0, -(self.current_depth-1 + 1), 0), bot_forward_dir = self.bot_forward_dir})
    end
    if self.command then
        self.command:on_step(weld_all_entity)
        if self.command:completed(weld_all_entity) then
            self.command = nil
            self.current_depth = self.current_depth + 1
            self.state = self.state + 1
        end
    else
        minetest.log("verbose", "DigMineTask idle in state: " .. self.state .. " at depth " .. self.current_depth .. " of " .. self.target_depth)
    end
end

function dig_mine_task_factory.create(target_pos)
    return DigMineTask:new({target_pos = target_pos, target_depth = 6, bot_forward_dir=vector.new(0, 0, 1)})
end

TaskFactory.register(dig_mine_task_factory)
