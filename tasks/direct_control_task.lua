local direct_control_task_factory = {name = "direct_control"}

-- user may directly control the bot movement
DirectControlTask = CommandBasedTask:new()

function DirectControlTask:new (o)
    o = o or CommandBasedTask:new({})
    o.name = direct_control_task_factory.name
    o.command = CommandFactory["remote_control"]:new({user = o.user})
    setmetatable(o, self)
    self.__index = self
    return o
end

function DirectControlTask:completed()
    return self.command:completed()
end

function DirectControlTask:on_step(weld_all_entity)
    if self.command then
        self.command:on_step(weld_all_entity)
    end
end

function direct_control_task_factory.create(user)
    return DirectControlTask:new({user = user})
end

TaskFactory.register(direct_control_task_factory)
