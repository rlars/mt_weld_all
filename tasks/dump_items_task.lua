local dump_items_task_factory = {name = "dump_items"}

DumpItemsTask = CommandBasedTask:new()

function DumpItemsTask:new (o)
    o = o or CommandBasedTask:new({})
    o.name = dump_items_task_factory.name
    minetest.debug("create DumpItemsTask")
    setmetatable(o, self)
    self.__index = self
    return o
end

function DumpItemsTask:completed(weld_all_entity)
    local inv = weld_all_entity:get_or_create_inventory()
    return not self.command and inv:is_empty("main")
end


local function max_manhattan_component(a, b)
	local diff = vector.subtract(a, b)
	return math.max(math.abs(diff.x), math.abs(diff.y), math.abs(diff.z))
end

function DumpItemsTask:on_step(weld_all_entity)
    -- init
    local inv = weld_all_entity:get_or_create_inventory()
    if not self.command and not inv:is_empty("main") then
        local target_pos = MinMaxArea.get_lowest_empty(self.target_zone)
        if not target_pos then
            -- no more space in zone
            return
        end
        
        if vector.distance(weld_all_entity.object:get_pos(), target_pos) > 2 or max_manhattan_component(weld_all_entity.object:get_pos(), target_pos) < 0.7 then
            self.command = CreateMoveCommand(target_pos, true)
        else
            local item_name = nil
            local items = inv:get_list("main")
            for i, stack in ipairs(items) do
                if stack:get_count() > 0 then
                    item_name = stack:get_name()
                end
            end
            minetest.debug("dump item " .. item_name)
            self.command = CreatePlaceCommand(target_pos, {name=item_name})
        end
    end

    if self.command then
        minetest.log("verbose", "Current command: " .. self.command.name)
        self.command.on_step(weld_all_entity)
        if self.command.completed(weld_all_entity) then
            self.command = nil
        end
    end
end

function dump_items_task_factory.create(target_zone)
    return DumpItemsTask:new({target_zone = target_zone})
end

TaskFactory.register(dump_items_task_factory)
