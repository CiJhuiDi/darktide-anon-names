local mod = get_mod("anon_names")

-- 化名风格：AnonPlayers 决定「谁被匿名」，这里只决定「用什么名字」
local style_dropdown = {
	{ text = "style_jieqi", value = "jieqi" },
	{ text = "style_flora", value = "flora" },
	{ text = "style_flower", value = "flower" },
	{ text = "style_herb", value = "herb" },
	{ text = "style_vine", value = "vine" },
	{ text = "style_tree", value = "tree" },
	{ text = "style_garden", value = "garden" },
	{ text = "style_star", value = "star" },
	{ text = "style_mixed", value = "mixed" },
	{ text = "style_off", value = "off" },
}

-- 机器人：AnonPlayers 会把机器人一起匿名（其源码注释写明 INCLUDING BOTS），
-- 这里决定机器人要不要也用化名。第一项 = 开，第二项 = 关。
local bot_dropdown = {
	{ text = "bot_use_pool", value = "use_pool" },
	{ text = "bot_keep_masked", value = "keep_masked" },
	{ text = "bot_original", value = "original" },
}

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id    = "mask_style",
				type          = "dropdown",
				default_value = "jieqi",
				options       = style_dropdown,
			},
			{
				setting_id    = "bot_handling",
				type          = "dropdown",
				default_value = "use_pool",
				options       = bot_dropdown,
			},
			{
				setting_id    = "apply_to_accounts",
				type          = "checkbox",
				default_value = true,
			},
		},
	},
}
