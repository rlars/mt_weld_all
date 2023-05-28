TaskFactory = {}

--RegisteredTaskFactories = {}

CommandBasedTask = {}

function CommandBasedTask:new (o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function CommandBasedTask:completed() return not self.commands or #self.commands == 0 end

function CommandBasedTask:on_step(weld_all_entity)
    if not self.commands or #self.commands == 0 then return end
    local current_command = self.commands[1]
    current_command.on_step(weld_all_entity)
    if current_command.completed(weld_all_entity) then
        minetest.log("verbose", "Task " .. self.name .. " completed command " .. current_command.name)
        table.remove(subcommands, 1)
        if #self.commands > 0 then
            minetest.log("verbose", "Task " .. self.name .. " will execute next command " .. self.commands[1].name)
        end
    end
end

function TaskFactory.register(task_factory)
    if not task_factory or not task_factory.name then
        minetest.debug("Cannot register unknown object as task factory")
    end
    minetest.debug("Registering task factory '"..task_factory.name.."'")
    if not task_factory.create then
        minetest.debug("Cannot register invalid task factory '"..task_factory.name.."'")
    end
    TaskFactory[task_factory.name] = task_factory
end

dofile(wa_path.."/tasks/dig_mine_task.lua");
dofile(wa_path.."/tasks/direct_control_task.lua");
dofile(wa_path.."/tasks/dump_items_task.lua");
dofile(wa_path.."/tasks/move_task.lua");
