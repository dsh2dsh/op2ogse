--xr_effects.messege_help_to_scoryi()
--ogse.spawn_item_in_inv("af_blood_tutorial")
--db.actor:give_info_portion("val_x18_door_open")
--[[db.actor:give_info_portion("no_kill_actor")
db.actor:give_info_portion("esc_kill_bandits_quest_done")
db.actor:give_info_portion("esc_kill_bandits_quest_done")]]
--[[db.actor:set_character_community("bandit", 0, 0)
ogse.spawn_objects(ogse_spawn_db.script_spawn_registry.task_functor.orlov_and_actor_teleport_to_fab_2)
ogse.spawn_item_in_inv("device_torch")]]

--[[ogse.spawn_item_in_inv("wpn_montirovka_weak")
ogse.spawn_item_in_inv("salo")
ogse.spawn_item_in_inv("autodoctor")]]
--[[
for i = 1,65535 do
	local obj = alife():object(i)
	if obj and string.find(obj:section_name(), "zombie_ghost") then
		log1("found zombie ghost")
		alife():release(obj, true)
	end
end
]]
--[[
local npc = level.object_by_id(119)
for i = 1,65535 do
	local obj = level.object_by_id(i)
	if obj and (obj:is_monster() or obj:is_stalker()) then
		obj:set_goodwill(5000, db.actor)
		if obj:id() ~= 119 then
			obj:set_goodwill(5000, npc)
		end
	end
end]]

local npc_online = {}
for i = 1,65535 do
	local obj = level.object_by_id(i)
	if obj and (obj:is_monster() or obj:is_stalker()) then
		npc_online[alife():object(i)] = true
	end
end
--[[
for k,v in pairs(npc_online) do
	local cnt = 0
	for _k,_v in pairs(npc_online) do
		if cnt < 10 then
			if k.id ~= _k.id then
				local o1 = level.object_by_id(k.id)
				local o2 = level.object_by_id(_k.id)
				o1:set_goodwill(5000, o2)
				cnt = cnt + 1
			end
		end
	end
end]]

local pt = ogse_profiler.profiler("ogse_rel_delete"):start()
local j = 0
for k,v in pairs(npc_online) do
	alife():release(k, true)
	j = j + 1
end
pt:save("end_deleting")
pt:stop()
ogse_profiler.print_stat("ogse_rel_delete")
log1("NPC DELETED COUNT IS "..tostring(j))