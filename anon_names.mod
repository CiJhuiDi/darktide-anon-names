return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`anon_names` encountered an error loading the Darktide Mod Framework.")

		new_mod("anon_names", {
			mod_script       = "anon_names/scripts/mods/anon_names/anon_names",
			mod_data         = "anon_names/scripts/mods/anon_names/anon_names_data",
			mod_localization = "anon_names/scripts/mods/anon_names/anon_names_localization",
		})
	end,
	packages = {},
}
