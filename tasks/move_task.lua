local move_task_factory = {name = "move"}

-- move to given position
MoveTask = CommandBasedTask:new()

function MoveTask:new (o)
    o = o or CommandBasedTask:new({})
    o.name = move_task_factory.name
    o.command = CommandFactory["move"]:new({target_pos = o.target_pos})--, o.target_pos)
    setmetatable(o, self)
    self.__index = self
    return o
end

function MoveTask:completed()
    return self.command:completed()
end

function MoveTask:on_step(weld_all_entity)
    if self.command then
        self.command:on_step(weld_all_entity)
    end
    minetest.debug("Command is " .. self.command.name)
end

function move_task_factory.create(target_pos)
    return MoveTask:new({target_pos = target_pos})
end

TaskFactory.register(move_task_factory)
