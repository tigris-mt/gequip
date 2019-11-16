gequip = {}

gequip.types = {}

-- Register a type of equipment.
function gequip.register_type(name, def)
	def = b.t.combine({
		-- Human readable description.
		description = "?",

		-- Maximum number of equipment in the inventory.
		slots = 1,

		-- Inventory list name.
		list_name = "gequip_" .. name,

		-- Default definition of individual equipment.
		-- Defaults below.
		defaults = {},
	}, def)

	def.defaults = b.t.combine({
	}, def.defaults)

	function def.on_player_inventory_action(player, action, inv, info)
		if (action == "move" and (info.to_list == def.list_name or info.from_list == def.list_name)) or (action == "put" and info.listname == def.list_name) then
			gequip.refresh(player)
			return
		end
	end

	function def.allow_player_inventory_action(player, action, inv, info)
		local stack
		if action == "move" and info.to_list == def.list_name and info.from_list ~= def.list_name then
			stack = ItemStack(player:get_inventory():get_list(info.from_list)[info.from_index])
			stack:set_count(info.count)
		elseif action == "put" and info.listname == def.list_name then
			stack = info.stack
		else
			return nil
		end

		-- Invalid items can't be inserted.
		if stack:get_definition()._eqtype ~= name then
			return 0
		end

		return nil
	end

	minetest.register_on_player_inventory_action(def.on_player_inventory_action)
	minetest.register_allow_player_inventory_action(def.allow_player_inventory_action)

	gequip.types[name] = def
end

minetest.register_on_joinplayer(function(player)
	for _,def in pairs(gequip.types) do
		player:get_inventory():set_size(def.list_name, def.slots)
	end

	gequip.refresh(player)
end)

gequip.actions = {}

function gequip.register_action(name, def)
	gequip.actions[name] = b.t.combine({
		-- State is a table for arbitrary data storage between adds.
		-- State is shared between all actions, use a unique sub key.
		init = function(state) end,
		-- Add an item's equipment def to the state.
		add = function(state, eqdef, stack) end,
		-- Apply the state to a player.
		apply = function(state, player) end,
	}, def)
end

gequip.eqdef_inits = {}

-- Register init function.
-- Passed static eqdef and stack.
function gequip.register_eqdef_init(func)
	table.insert(gequip.eqdef_inits, func)
end

-- Get the eqdef of a stack.
-- Table is deep copied and can be modified freely.
function gequip.get_eqdef(stack, skip_meta)
	local def = stack:get_definition()
	local typedef = gequip.types[def._eqtype]

	local eqdef_static = b.t.combine(typedef.defaults, def._eqdef or {})
	for _,func in ipairs(gequip.eqdef_inits) do
		func(eqdef_static, stack)
	end

	local metadef = (stack:get_meta():contains("eqdef") and not skip_meta) and minetest.deserialize(stack:get_meta():get_string("eqdef")) or {}
	return b.t.combine(table.copy(eqdef_static), metadef)
end

-- Apply all equipment to the player.
function gequip.refresh(player)
	local state = {}
	for _,action in pairs(gequip.actions) do
		action.init(state)
	end

	for _,type in pairs(gequip.types) do
		for _,stack in ipairs(player:get_inventory():get_list(type.list_name)) do
			if stack:get_count() > 0 then
				local eqdef = gequip.get_eqdef(stack)
				for _,action in pairs(gequip.actions) do
					action.add(state, eqdef, stack)
				end
			end
		end
	end

	for _,action in pairs(gequip.actions) do
		action.apply(state, player)
	end
end
