wa_path = minetest.get_modpath("weld_all_bot")



-- TODO: allow to modify
function get_gravity()
	return vector.new(0, -2, 0)
end


dofile(wa_path.."/weld_all_entity.lua");
dofile(wa_path.."/remote_control.lua");
dofile(wa_path.."/commands.lua");

