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

local function is_facing_pos(weld_all_entity, pos)
	local current_face_yaw = weld_all_entity.object:get_yaw()
    local target_dir = vector.direction(weld_all_entity.object:get_pos(), pos)
    return MathHelpers.angles_are_close(current_face_yaw, MathHelpers.dir_to_yaw(target_dir, current_face_yaw), 0.03)
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
            self.command = CommandFactory["move"]:new({target_pos = target_pos, close_is_enough = true})
        elseif not is_facing_pos(weld_all_entity, target_pos) then
            self.command = CommandFactory["set_rotation"]:new({target_dir = vector.direction(weld_all_entity.object:get_pos(), target_pos)})
        else
            local item_name = nil
            local items = inv:get_list("main")
            for i, stack in ipairs(items) do
                if stack:get_count() > 0 then
                    item_name = stack:get_name()
                end
            end
            minetest.debug("dump item " .. item_name)
            self.command = CommandFactory["place"]:new({target_pos = target_pos, node = {name=item_name}})
        end
    end

    if self.command then
        self.command:on_step(weld_all_entity)
        if self.command:completed(weld_all_entity) then
            self.command = nil
        end
    end
end

function DumpItemsTask:get_error(weld_all_entity)
    return self.command:get_error(weld_all_entity)
end

function dump_items_task_factory.create(target_zone)
    return DumpItemsTask:new({target_zone = target_zone})
end

TaskFactory.register(dump_items_task_factory)
