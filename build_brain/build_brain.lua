--[[
     ~ qLocalization
     ~ automatic localization wrapper for Lua menu interfaces

     ~ author: qfun (qfun_g9s)
]]

local qLocalization = (function()
	local lib = {}

	local a = function(...)
		return ...
	end

	local state = {
		lang = Menu.Find("SettingsHidden", "", "", "", "Main", "Language"),
		instances = {},
	}

	local setters = {
		ToolTip = "tooltip",
	}

	local helpers
	do
		helpers = {
			resolve = a(function(root, path)
				for key in path:gmatch("[^.]+") do
					if type(root) ~= "table" then
						return
					end

					root = root[key]
				end

				return root
			end),

			is_object = a(function(value)
				return type(value) == "table" or type(value) == "userdata"
			end),

			has_method = a(function(object, name)
				return helpers.is_object(object) and type(object[name]) == "function"
			end),

			is_menu_object = a(function(value)
				return helpers.has_method(value, "Name") and helpers.has_method(value, "Type")
			end),

			is_list = a(function(value)
				if type(value) ~= "table" or #value == 0 then
					return false
				end

				for i = 1, #value do
					if type(value[i]) ~= "string" then
						return false
					end
				end

				return true
			end),

			is_indexed_list = a(function(object)
				return helpers.has_method(object, "List") and not helpers.has_method(object, "ListEnabled")
			end),
		}
	end

	function lib.new(translations)
		local languages = {}

		for i, name in ipairs(state.lang and state.lang:List() or {}) do
			local code = name:match("%a+")

			if code and translations[code] then
				languages[i - 1] = code
			end
		end

		local localization = {
			translations = translations,
			languages = languages,
			objects = {},
		}

		local methods
		do
			methods = {
				get_language = a(function(language_index)
					if language_index == nil and state.lang then
						language_index = state.lang:Get()
					end

					return localization.languages[language_index] or "en"
				end),

				localize = a(function(path, language_index)
					if type(path) ~= "string" then
						return path
					end

					local language = methods.get_language(language_index)

					return helpers.resolve(localization.translations[language], path)
						or helpers.resolve(localization.translations.en, path)
						or path
				end),

				has = a(function(path)
					if type(path) ~= "string" then
						return false
					end

					return helpers.resolve(localization.translations.en, path) ~= nil
						or helpers.resolve(localization.translations[methods.get_language()], path) ~= nil
				end),

				localize_items = a(function(items, language_index)
					local result, localized = {}, false

					for i = 1, #items do
						local value = items[i]

						if methods.has(value) then
							result[i] = methods.localize(value, language_index)
							localized = true
						else
							result[i] = value
						end
					end

					return result, localized
				end),

				apply = a(function(object, kind, path, language_index)
					if kind == "label" then
						object:ForceLocalization(methods.localize(path, language_index))
					elseif kind == "tooltip" then
						object:ToolTip(methods.localize(path, language_index))
					elseif kind == "items" then
						local value = object:Get()

						object:Update((methods.localize_items(path, language_index)))
						object:Set(value)
					end
				end),

				track = a(function(object, kind, path, apply_now)
					local record = localization.objects[object]

					if record == nil then
						record = {}
						localization.objects[object] = record
					end

					record[kind] = path

					if apply_now then
						methods.apply(object, kind, path)
					end
				end),

				register = a(function(object, path)
					if not methods.has(path) or not helpers.has_method(object, "ForceLocalization") then
						return
					end

					methods.track(object, "label", path, true)
				end),

				update = a(function(language_index)
					for object, record in pairs(localization.objects) do
						for kind, path in pairs(record) do
							methods.apply(object, kind, path, language_index)
						end
					end
				end),

				wrap = a(function(target, bind_self)
					if not helpers.is_object(target) then
						return target
					end

					local proxy

					proxy = setmetatable({}, {
						__index = function(_, key)
							local member = target[key]

							if type(member) ~= "function" then
								return member
							end

							return function(...)
								local args = table.pack(...)

								if bind_self and args[1] == proxy then
									table.remove(args, 1)
									args.n = args.n - 1
								end

								if key == "Switch" and args.n < 2 then
									args[2] = false
									args.n = 2
								end

								local name_path, item_paths

								if setters[key] then
									if methods.has(args[1]) then
										methods.track(target, setters[key], args[1], false)

										args[1] = methods.localize(args[1])
									end
								else
									local name_index = bind_self and 1 or args.n

									if methods.has(args[name_index]) then
										name_path = args[name_index]
									end

									local items_index

									if key == "Combo" then
										items_index = 2
									elseif key == "Update" and helpers.is_indexed_list(target) then
										items_index = 1
									end

									if items_index ~= nil and helpers.is_list(args[items_index]) then
										local items, localized = methods.localize_items(args[items_index])

										if localized then
											item_paths = args[items_index]
											args[items_index] = items
										end
									end
								end

								local results

								if bind_self then
									results = table.pack(member(target, table.unpack(args, 1, args.n)))
								else
									results = table.pack(member(table.unpack(args, 1, args.n)))
								end

								for i = 1, results.n do
									local result = results[i]

									if helpers.is_menu_object(result) then
										if name_path then
											methods.register(result, name_path)
										end

										if item_paths then
											methods.track(result, "items", item_paths, false)
											item_paths = nil
										end

										results[i] = methods.wrap(result, true)
									end
								end

								if item_paths then
									methods.track(target, "items", item_paths, false)
								end

								return table.unpack(results, 1, results.n)
							end
						end,

						__newindex = function(_, key, value)
							target[key] = value
						end,
					})

					return proxy
				end),
			}
		end

		state.instances[methods] = true

		return {
			GetLanguage = methods.get_language,

			Get = methods.localize,
			Localize = methods.localize,

			Update = methods.update,
			Register = methods.register,

			Wrap = methods.wrap,

			WrapLibrary = function(library)
				return methods.wrap(library, false)
			end,
		}
	end

	if state.lang then
		state.lang:SetCallback(function(this)
			local language_index = this:Get()

			for methods in pairs(state.instances) do
				methods.update(language_index)
			end
		end, true)
	else
		Log.Write("[qLocalization] Language widget not found, using English fallback")
	end

	return lib
end)()

local localization = qLocalization.new({
	en = {
		bb_group_main = "Main",
		bb_enable = "Enable",
		bb_enable_tip = "Draft help and item advice for this match\nin its own window",
		bb_window_key = "Window key",
		bb_window_key_tip = "Opens and closes the Build Brain window",
		bb_bind_window = "Build Brain window",
		bb_light_of = "Radiant",
		bb_dark_of = "Dire",
		bb_chance_of = "%s win chance",
		bb_shop_role = "Role: %s",
		bb_shop_role_auto = "Role from lobby: %s",
		bb_shop_none = "no games for this role, showing %s",
		bb_shop_role_main = "Most played: %s",
		bb_shop_start = "STARTING ITEMS",
		bb_shop_early = "EARLY GAME",
		bb_why_bottle = "Mid: regen and runes",
		bb_shop_core = "CORE ITEMS",
		bb_shop_sit = "ALSO BUILT",
		bb_shop_vs = "AGAINST ENEMIES",
		bb_vs_brk = "strong passives, break them",
		bb_vs_eva = "evasion, you need true strike",
		bb_vs_heal = "lots of healing, cut it",
		bb_vs_inv = "goes invisible",
		bb_vs_ill = "illusions and summons",
		bb_vs_save = "saves and buffs, dispel them",
		bb_vs_tgt = "single-target disables (hex, stuns, ults on you)",
		bb_vs_sil = "silences",
		bb_vs_esc = "escapes fast, needs to be caught",
		bb_vs_ctl = "lots of disables",
		bb_vs_mag = "lots of magic damage",
		bb_vs_phys = "lots of physical damage",
		bb_vs_tank = "lots of armor and HP",
		bb_vs_item = "has %s",
		bb_h_abaddon = "Dispelling shield on allies, damage heals him in ult",
		bb_h_abyssal_underlord = "Pit roots you, aura cuts your damage, team portal",
		bb_h_alchemist = "Farms fast, stuns with concoction, huge regen in ult",
		bb_h_ancient_apparition = "Ult stops healing and shatters, lots of slows",
		bb_h_antimage = "Blinks, burns mana, reflects targeted spells",
		bb_h_arc_warden = "Clone with his items, field makes attacks miss",
		bb_h_axe = "Taunts you, counter-helixes, finishes with ult",
		bb_h_bane = "Sleep and grip disable one target for long",
		bb_h_batrider = "Lassoes you away from your team, flies fast",
		bb_h_beastmaster = "Roar stuns one target, boar and hawks root",
		bb_h_bloodseeker = "AoE silence, heals on kills, ult punishes moving",
		bb_h_bounty_hunter = "Goes invisible and tracks you",
		bb_h_brewmaster = "Ult splits him into spirits, storm stance evades",
		bb_h_bristleback = "Barely takes damage from behind, quills stack",
		bb_h_broodmother = "Spiders push, lifesteal, fast on her webs",
		bb_h_centaur = "AoE stun, returns attack damage, very tanky",
		bb_h_chaos_knight = "Illusions, single-target stun, lifesteal crits",
		bb_h_chen = "Heals the whole team globally, leads creeps",
		bb_h_clinkz = "Walks invisible, leaves archers, high damage",
		bb_h_crystal_maiden = "Roots you, AoE ult, slips away with her clone",
		bb_h_dark_seer = "Wall copies your heroes, vacuum pulls you together",
		bb_h_dark_willow = "Brambles root, crown stuns, hides from damage",
		bb_h_dawnbreaker = "Heals allies and flies to them across the map",
		bb_h_dazzle = "Keeps an ally from dying, heals with waves",
		bb_h_death_prophet = "Silence, drains life, ult heals her and wrecks towers",
		bb_h_disruptor = "Fields trap you, Glimpse sends you back, ult silences",
		bb_h_doom_bringer = "Doom dispels and stops your spells and healing",
		bb_h_dragon_knight = "Very tanky from regen and armor, shield stun",
		bb_h_drow_ranger = "Huge ranged damage, silence and knockback",
		bb_h_earth_spirit = "Rolls in and stuns, silences, hard to catch",
		bb_h_earthshaker = "Huge AoE stuns, fissure blocks your path",
		bb_h_elder_titan = "AoE sleep, ult strips armor and magic resistance",
		bb_h_ember_spirit = "Chains root you, jumps between remnants",
		bb_h_enchantress = "Slows attacks on her, heals, hits harder from range",
		bb_h_enigma = "Black Hole holds your team, summons eidolons",
		bb_h_faceless_void = "Chronosphere freezes everyone, Time Walk undoes damage",
		bb_h_furion = "Traps you in trees, treant army, teleports",
		bb_h_grimstroke = "Binds you to an ally, phantom silences, lots of magic",
		bb_h_gyrocopter = "Lots of AoE damage, homing missile stuns",
		bb_h_hoodwink = "Redirects attacks into trees, goes invisible with a decoy",
		bb_h_huskar = "Stronger with more regen at low HP, silences",
		bb_h_invoker = "Lots of magic and disables, goes invisible",
		bb_h_jakiro = "Lots of AoE magic, stun and slows",
		bb_h_juggernaut = "Spins immune to disables, heals with a ward",
		bb_h_keeper_of_the_light = "Lots of long-range magic, knocks back and blinds",
		bb_h_kez = "Grapples in, silences, lots of damage",
		bb_h_kunkka = "AoE stun and big cleaving hits",
		bb_h_largo = "Buffs allies with songs, dispels them",
		bb_h_legion_commander = "Single-target duel, stronger with every win",
		bb_h_leshrac = "Huge AoE magic damage, stun",
		bb_h_lich = "Bouncing ult and lots of slows",
		bb_h_life_stealer = "Rage makes him immune to disables, heals from hits",
		bb_h_lina = "Burst magic, stun and single-target ult",
		bb_h_lion = "Hex and stun, single-target ult finishes you",
		bb_h_lone_druid = "Bear with items pushes towers and heroes",
		bb_h_luna = "Attacks bounce, ult rains beams in an area",
		bb_h_lycan = "Wolves and shapeshift, very fast",
		bb_h_magnataur = "Pulls everyone with ult and buffs allies' damage",
		bb_h_marci = "Rebounds in and stuns, rapid strikes in ult",
		bb_h_mars = "Arena traps you, shield blocks attacks from the front",
		bb_h_medusa = "Mana shield, split arrows, ult turns you to stone",
		bb_h_meepo = "Many clones, net roots, poofs between clones",
		bb_h_mirana = "Long-range arrow stun and team invisibility",
		bb_h_monkey_king = "Leaps from trees, disguises, lifesteal on hits",
		bb_h_morphling = "Invulnerable in Waveform, shifts stats to survive",
		bb_h_muerta = "Ult makes her attacks magic and immune to physical, silences",
		bb_h_naga_siren = "Many illusions, evasion, song puts your team to sleep",
		bb_h_necrolyte = "Heals himself and allies, ult executes one target",
		bb_h_nevermore = "Huge damage, razes and AoE ult",
		bb_h_night_stalker = "Very strong at night, fear silences, flies in ult",
		bb_h_nyx_assassin = "Invisible, spike stun, carapace reflects damage",
		bb_h_obsidian_destroyer = "Pure AoE damage, hides allies in his prison",
		bb_h_ogre_magi = "Multicast: stuns and buffs several times",
		bb_h_omniknight = "Makes allies immune to physical damage, heals",
		bb_h_oracle = "Ult saves an ally from death and dispels",
		bb_h_pangolier = "Rolls and stuns, debuff immune while rolling",
		bb_h_phantom_assassin = "Evades attacks and lands huge crits",
		bb_h_phantom_lancer = "Huge army of illusions",
		bb_h_phoenix = "Supernova revives her, Sun Ray heals allies",
		bb_h_primal_beast = "Charges in and pulverizes one target, tanky",
		bb_h_puck = "Elusive: silence, jumps, ult leashes you",
		bb_h_pudge = "Hook and ult hold one target, very tanky",
		bb_h_pugna = "Drains HP, ward punishes every spell",
		bb_h_queenofpain = "Blink and AoE magic, hard to catch",
		bb_h_rattletrap = "Hookshot catches from afar, stuns and cogs",
		bb_h_razor = "Steals your damage, lightning strikes back",
		bb_h_riki = "Always invisible, backstabs, smoke silences",
		bb_h_ringmaster = "Whip fears you, boxes allies to save them",
		bb_h_rubick = "Steals your spells, lifts you up",
		bb_h_sand_king = "AoE stun, invisible inside his sandstorm",
		bb_h_shadow_demon = "Banishes allies to save them, purges buffs, makes copies",
		bb_h_shadow_shaman = "Hex and shackles on one target, wards wreck towers",
		bb_h_shredder = "Lots of pure damage, chains away, armor stacks",
		bb_h_silencer = "Global silence, steals intelligence",
		bb_h_skeleton_king = "Reincarnates, heals from hits",
		bb_h_skywrath_mage = "Huge magic and a silencing seal",
		bb_h_slardar = "AoE stun and armor reduction",
		bb_h_slark = "Steals stats, purges disables, escapes",
		bb_h_snapfire = "Lots of AoE magic, cookie stun",
		bb_h_sniper = "Hits from very far away",
		bb_h_spectre = "Passively reflects damage, ult jumps to you",
		bb_h_spirit_breaker = "Charges across the map and stuns",
		bb_h_storm_spirit = "Flies as lightning, very hard to catch",
		bb_h_sven = "AoE stun and huge damage in ult",
		bb_h_techies = "Mines and AoE blasts, jumps in with a stun",
		bb_h_templar_assassin = "Barrier blocks damage, melds invisible, big hits",
		bb_h_terrorblade = "Illusions and HP swap ult",
		bb_h_tidehunter = "Huge stun ult, very tanky",
		bb_h_tinker = "Missiles and laser, rearms everything, teleports",
		bb_h_tiny = "Tosses and stuns, huge damage",
		bb_h_treant = "Invisible in trees, heals with armor, ult holds everyone",
		bb_h_troll_warlord = "Can't die in ult, attacks very fast",
		bb_h_tusk = "Snowball and a punch that launches you",
		bb_h_undying = "Zombies and tombstone, heals and steals strength",
		bb_h_ursa = "Each hit is stronger than the last",
		bb_h_vengefulspirit = "Stuns and swaps places with you",
		bb_h_venomancer = "Poison and wards everywhere",
		bb_h_viper = "Poison, ult breaks passives, resists magic",
		bb_h_visage = "Familiars stun, layered damage shield",
		bb_h_void_spirit = "Jumps through portals, hard to catch",
		bb_h_warlock = "Golem ult and heals for allies",
		bb_h_weaver = "Invisibility and time rewind",
		bb_h_windrunner = "Single-target shackle, evades attacks",
		bb_h_winter_wyvern = "Curse makes you hit your ally, heals allies",
		bb_h_wisp = "Tethered to an ally and heals them",
		bb_h_witch_doctor = "Death ward, cask stun and heals",
		bb_h_zuus = "Global ult and lots of magic",
		bb_it_abyssal_blade = "Abyssal Blade: stun through BKB",
		bb_it_aeon_disk = "Aeon Disk: saves him from burst",
		bb_it_black_king_bar = "BKB: immune to magic and disables",
		bb_it_blade_mail = "Blade Mail: returns damage",
		bb_it_bloodstone = "Bloodstone: heals from spells",
		bb_it_bloodthorn = "Bloodthorn: silence and crits",
		bb_it_butterfly = "Butterfly: evades attacks",
		bb_it_cyclone = "Eul's: lifts himself and dispels",
		bb_it_dagon = "Dagon: magic burst",
		bb_it_desolator = "Desolator: reduces armor",
		bb_it_ethereal_blade = "Ethereal Blade: dodges attacks, hits with magic",
		bb_it_force_staff = "Force Staff: pushes himself away",
		bb_it_ghost = "Ghost: your attacks can't hit him",
		bb_it_glimmer_cape = "Glimmer Cape: invisibility and a magic barrier",
		bb_it_greater_crit = "Daedalus: huge crits",
		bb_it_guardian_greaves = "Greaves: heal and dispel allies",
		bb_it_gungir = "Gleipnir: AoE root",
		bb_it_heart = "Heart: huge regeneration",
		bb_it_heavens_halberd = "Halberd: disarms you",
		bb_it_holy_locket = "Holy Locket: big heals for allies",
		bb_it_hurricane_pike = "Hurricane Pike: pushes you away and escapes",
		bb_it_invis_sword = "Shadow Blade: goes invisible",
		bb_it_lotus_orb = "Lotus Orb: reflects spells back",
		bb_it_manta = "Manta: illusions and dispel",
		bb_it_monkey_king_bar = "MKB: pierces evasion",
		bb_it_nullifier = "Nullifier: removes your saves",
		bb_it_orchid = "Orchid: silences you",
		bb_it_refresher = "Refresher: two ults in a row",
		bb_it_rod_of_atos = "Rod of Atos: roots you",
		bb_it_satanic = "Satanic: heals hard from hits",
		bb_it_shadow_amulet = "Shadow Amulet: hides invisible",
		bb_it_sheepstick = "Scythe of Vyse: hexes you",
		bb_it_silver_edge = "Silver Edge: invisibility and break",
		bb_it_sphere = "Linken's: blocks a targeted spell",
		bb_it_wind_waker = "Wind Waker: flies away from damage",
		bb_how_abyssal_blade = "stuns even through BKB",
		bb_how_aeon_disk = "saves you from burst",
		bb_how_assault = "armor for you, minus armor for enemies",
		bb_how_bfury = "cleave hits illusions and summons",
		bb_how_black_king_bar = "immunity to magic and most disables",
		bb_how_blade_mail = "returns damage to attackers",
		bb_how_bloodthorn = "silence and attacks that pierce evasion",
		bb_how_butterfly = "evasion from attacks",
		bb_how_crimson_guard = "blocks physical damage for your team",
		bb_how_cyclone = "lift yourself and dispel",
		bb_how_dagon = "pops Linken's and finishes with magic",
		bb_how_desolator = "minus armor: kill tanky heroes faster",
		bb_how_diffusal_blade = "slows and burns mana on hit",
		bb_how_disperser = "dispels Ghost, Glimmer and buffs, slows",
		bb_how_dust = "reveals invisible enemies nearby",
		bb_how_ethereal_blade = "use on yourself: attacks can't hit you",
		bb_how_force_staff = "push yourself or an ally out of danger",
		bb_how_gem = "reveals all invisible units around you",
		bb_how_ghost = "attacks can't hit you for a few seconds",
		bb_how_glimmer_cape = "invisibility and a magic barrier for you or an ally",
		bb_how_guardian_greaves = "heals and dispels your team",
		bb_how_gungir = "roots in an area",
		bb_how_harpoon = "pulls the enemy to you",
		bb_how_heavens_halberd = "disarms a carry for a few seconds",
		bb_how_lotus_orb = "reflects the spell back and dispels",
		bb_how_maelstrom = "chain lightning on illusions",
		bb_how_mage_slayer = "cuts enemy spell damage",
		bb_how_manta = "removes silence and roots, makes illusions",
		bb_how_mjollnir = "lightning clears illusions and summons",
		bb_how_monkey_king_bar = "attacks pierce evasion",
		bb_how_nullifier = "dispels Ghost, Glimmer and buffs for 4 seconds",
		bb_how_orchid = "silence: no casting, no escape",
		bb_how_pipe = "magic shield for the whole team",
		bb_how_radiance = "burns illusions and summons around",
		bb_how_rod_of_atos = "roots and pops Linken's",
		bb_how_sheepstick = "hex: no spells, no items",
		bb_how_shivas_guard = "armor, slows nearby enemy attacks and movement",
		bb_how_silver_edge = "breaks passives and gives invisibility",
		bb_how_skadi = "halves enemy healing and slows",
		bb_how_solar_crest = "armor, attack speed and a physical barrier for an ally",
		bb_how_sphere = "blocks one targeted spell",
		bb_how_spirit_vessel = "cuts enemy healing and regen",
		bb_how_urn_of_shadows = "damage and heal, cheaper than Vessel",
		bb_how_ward_sentry = "sentry reveals invisible units",
		bb_how_wind_waker = "fly away from damage and disables",
		bb_vs_helps = "helps: %s",
		bb_live_magic = "most damage you take is magic (%d%%)",
		bb_live_phys = "most damage you take is from attacks (%d%%)",
		bb_live_ctrl = "you spend %.0f s disabled per death",
		bb_tag_brk = "passives", bb_tag_eva = "evasion", bb_tag_heal = "healing", bb_tag_inv = "invisibility", bb_tag_ill = "illusions",
		bb_tag_save = "saves", bb_tag_tgt = "single-target disables", bb_tag_sil = "silences", bb_tag_esc = "mobility", bb_tag_ctl = "disables",
		bb_tag_mag = "magic damage", bb_tag_phys = "physical damage", bb_tag_tank = "tanky",
		bb_pick_title = "Who to pick (%s)",
		bb_pick_vs = "strong against %s",
		bb_foe_title = "Who to watch out for",
		bb_next_usual = "usually bought at %d min · %d%% of games",
		bb_shelf_title = "Build",
		bb_shelf_hint = "minute = when it is usually bought",
		bb_next_title = "Next item",
		bb_chance_title = "Win chance",
		bb_top = "Top",
		bb_set_scale = "Window size",
		bb_upd_title = "Updates",
		bb_set_update = "Update automatically",
		bb_upd_idle = "Checks GitHub every few hours",
		bb_upd_checking = "Checking...",
		bb_upd_latest = "You have the latest version",
		bb_upd_available = "Version %s is available",
		bb_upd_loading = "Downloading %s...",
		bb_upd_done = "Updated to %s, reload scripts",
		bb_upd_check = "Check",
		bb_upd_install = "Update",
		bb_upd_reload = "Reload scripts",
		bb_upd_err_net = "GitHub did not answer, try later",
		bb_upd_err_file = "The file came broken, try later",
		bb_upd_err_write = "Cannot write the script file",
		bb_upd_err_path = "Script file not found, download it manually",
		bb_set_key_hint = "The window key is set in the Umbrella menu",
		bb_shelf_start = "Start",
		bb_shelf_lane = "Laning",
		bb_shelf_core = "Core",
		bb_shelf_more = "Also built",
		bb_vs_title = "Against enemies",
		bb_vs_empty = "No enemies seen yet",
		bb_vs_now = "can buy",
		bb_vs_eta = "~%d min",
		bb_kill_title = "What kills you",
		bb_kill_deaths = "%d deaths",
		bb_kill_empty = "No damage taken yet",
		bb_kill_ctrl = "%.0f s disabled per death",
		bb_todo_title = "What to do",
		bb_todo_empty = "Nothing urgent",
		bb_todo_buy = "Buy %s: %s",
		bb_todo_hit = "Fight %s: %s",
		bb_fight_foes = "Enemies now",
		bb_foe_fog = "fog %d s",
		bb_foe_go = "can fight",
		bb_foe_hp = "HP %d%%",
		bb_foe_ult_ready = "ult ready",
		bb_foe_ult_cd = "ult %d s",
		bb_foe_bkb_ready = "BKB ready",
		bb_foe_bkb_cd = "BKB %d s",
		bb_shop_skills = "SKILL ORDER",
		bb_shop_talents = "TALENTS",
		bb_shop_back = "Dota guide",
		bb_shop_popular = "%d%% of games, ~%d min",
		bb_shop_loading = "loading builds",
		bb_pos_1 = "Carry (1)",
		bb_pos_2 = "Mid (2)",
		bb_pos_3 = "Offlane (3)",
		bb_pos_4 = "Support (4)",
		bb_pos_5 = "Hard support (5)",
		bb_set_shop = "Own panel in the shop",
		bb_title = "Build Brain",
		bb_tab_draft = "Draft",
		bb_tab_build = "Build",
		bb_tab_fight = "Fight",
		bb_tab_settings = "Settings",
		bb_light = "Radiant",
		bb_dark = "Dire",
		bb_role = "role",
		bb_chance_sub = "draft chance",
		bb_chance_with = "with %s: %d%%",
		bb_heat = "Who beats whom",
		bb_heat_hint = "% to win chance",
		bb_heat_empty = "Shows up when heroes are picked",
		bb_best = "Best pick: %s",
		bb_best_hint = "to win chance",
		bb_best_vs = "strong vs %s",
		bb_best_empty = "Waiting for enemy picks",
		bb_threats = "Their draft",
		bb_threats_hint = "what to prepare for",
		bb_danger = "Most dangerous for you",
		bb_threat_disable = "Disables x%d",
		bb_threat_disable_sub = "stuns, hexes, silences",
		bb_threat_nuke = "Burst x%d",
		bb_threat_nuke_sub = "magic damage",
		bb_threat_init = "Initiators x%d",
		bb_threat_init_sub = "jump into fights",
		bb_threat_escape = "Elusive x%d",
		bb_threat_escape_sub = "hard to catch",
		bb_threat_durable = "Tanky x%d",
		bb_threat_durable_sub = "lots of HP and armor",
		bb_threat_carry = "Carries x%d",
		bb_threat_carry_sub = "strong late game",
		bb_next = "Next item",
		bb_route = "Route for the game",
		bb_route_hint = "minute at your income, gold dot = changed for this game",
		bb_route_empty = "Pick a hero and the route shows up here",
		bb_situational = "Situational",
		bb_situational_hint = "why now",
		bb_situational_empty = "Nothing special yet",
		bb_final = "Final slots",
		bb_final_hint = "by minute %d",
		bb_buy_part = "Buy %s",
		bb_buy_all = "Buy",
		bb_quick = "Quick buy",
		bb_now = "now",
		bb_later = "later",
		bb_new = "new",
		bb_minutes = "~%d min at your GPM",
		bb_gold_of = "%d of %d",
		bb_why_popular = "Popular on this hero at this stage",
		bb_why_magic = "%d%% of damage to you is magic",
		bb_why_control = "%.0f s disabled per death",
		bb_why_disablers = "%d disablers in their draft",
		bb_why_item = "%s has %s",
		bb_why_invis = "%s goes invisible",
		bb_fight_title = "What kills you",
		bb_fight_hint = "this game",
		bb_fight_empty = "No damage taken yet",
		bb_magic = "magic",
		bb_phys = "physical",
		bb_pure = "pure",
		bb_control = "disabled",
		bb_deaths = "deaths",
		bb_enemies = "Enemy items",
		bb_enemies_hint = "seen on them",
		bb_enemies_empty = "No enemies seen yet",
		bb_set_rank = "Rank for stats",
		bb_set_role = "Your role",
		bb_set_auto = "Open on hero pick",
		bb_on = "on",
		bb_off = "off",
		bb_rank_0 = "All ranks",
		bb_rank_1 = "Herald",
		bb_rank_2 = "Guardian",
		bb_rank_3 = "Crusader",
		bb_rank_4 = "Archon",
		bb_rank_5 = "Legend",
		bb_rank_6 = "Ancient",
		bb_rank_7 = "Divine",
		bb_rank_8 = "Immortal",
		bb_role_0 = "auto",
		bb_role_1 = "carry",
		bb_role_2 = "mid",
		bb_role_3 = "offlane",
		bb_role_4 = "soft support",
		bb_role_5 = "hard support",
		bb_status_ready = "Ready",
		bb_status_wait = "Waiting for the draft",
		bb_status_loading = "Loading OpenDota stats",
		bb_status_offline = "OpenDota is not answering, using saved stats",
		bb_status_quick = "Quick buy: %s",
		bb_status_buy = "Buying: %s",
		bb_status_poor = "Not enough gold for %s",
	},
	ru = {
		bb_group_main = "Основное",
		bb_enable = "Включить",
		bb_enable_tip = "Помощь на драфте и советы по предметам\nпод эту игру в своём окне",
		bb_window_key = "Клавиша окна",
		bb_window_key_tip = "Открывает и закрывает окно Build Brain",
		bb_bind_window = "Окно Build Brain",
		bb_light_of = "Света",
		bb_dark_of = "Тьмы",
		bb_chance_of = "шанс %s",
		bb_shop_role = "Выбрана роль: %s",
		bb_shop_role_auto = "Роль по лобби: %s",
		bb_shop_none = "на этой роли нет игр, показываю %s",
		bb_shop_role_main = "Чаще всего: %s",
		bb_shop_start = "НАЧАЛЬНЫЕ ПРЕДМЕТЫ",
		bb_shop_early = "РАННЯЯ ИГРА",
		bb_why_bottle = "Мид: реген и руны",
		bb_shop_core = "ОСНОВНЫЕ ПРЕДМЕТЫ",
		bb_shop_sit = "ЕЩЁ БЕРУТ",
		bb_shop_vs = "ПРОТИВ ВРАГОВ",
		bb_vs_brk = "сильные пассивки, их надо отключать",
		bb_vs_eva = "уклонение, нужна точность по атаке",
		bb_vs_heal = "много лечения, его надо резать",
		bb_vs_inv = "уходит в невидимость",
		bb_vs_ill = "иллюзии и призванные юниты",
		bb_vs_save = "сейвы и защитные баффы, их надо снимать",
		bb_vs_tgt = "контроль в одну цель (хекс, станы, ульты в тебя)",
		bb_vs_sil = "сайленсы",
		bb_vs_esc = "быстро убегает, его надо ловить",
		bb_vs_ctl = "много контроля",
		bb_vs_mag = "много магического урона",
		bb_vs_phys = "много физического урона",
		bb_vs_tank = "много брони и HP",
		bb_vs_item = "у него %s",
		bb_h_abaddon = "Щит с развеиванием на союзника, в ульте урон его лечит",
		bb_h_abyssal_underlord = "Яма держит на месте, аура режет урон, портал для команды",
		bb_h_alchemist = "Быстро фармит, станит банкой, в ульте сильно регенит",
		bb_h_ancient_apparition = "Ульта запрещает лечение и добивает, много замедлений",
		bb_h_antimage = "Блинк, жжёт ману, отражает заклинания в одну цель",
		bb_h_arc_warden = "Двойник с его предметами, поле заставляет атаки промахиваться",
		bb_h_axe = "Заставляет бить себя, отвечает спиралью, добивает ультой",
		bb_h_bane = "Сон и ульта надолго выключают одну цель",
		bb_h_batrider = "Утаскивает лассо из команды, быстро летает",
		bb_h_beastmaster = "Рык станит одну цель, кабан и ястребы держат на месте",
		bb_h_bloodseeker = "Сайленс по площади, лечится с убийств, ульта бьёт за бег",
		bb_h_bounty_hunter = "Уходит в инвиз и видит тебя меткой",
		bb_h_brewmaster = "Ульта делит его на духов, в стойке шторма уклоняется",
		bb_h_bristleback = "Со спины почти не получает урон, иглы стакаются",
		bb_h_broodmother = "Пауки давят линию, вампиризм, быстрая на своей паутине",
		bb_h_centaur = "Стан по площади, бьёт в ответ на атаки, очень толстый",
		bb_h_chaos_knight = "Иллюзии, стан в одну цель и криты с вампиризмом",
		bb_h_chen = "Лечит всю команду с карты, водит армию крипов",
		bb_h_clinkz = "Ходит в инвизе и оставляет лучников, много урона",
		bb_h_crystal_maiden = "Держит на месте, ульта бьёт по площади, уходит клоном",
		bb_h_dark_seer = "Стена делает ваши копии, вакуум стягивает в кучу",
		bb_h_dark_willow = "Лабиринт держит, корона станит, прячется от урона",
		bb_h_dawnbreaker = "Лечит союзников и прилетает к ним через всю карту",
		bb_h_dazzle = "Не даёт союзнику умереть, лечит волной",
		bb_h_death_prophet = "Сайленс, высасывает жизнь, ульта лечит её и ломает башни",
		bb_h_disruptor = "Запирает полем, возвращает назад, ульта сайленсит",
		bb_h_doom_bringer = "Ульта развеивает, запрещает заклинания и лечение",
		bb_h_dragon_knight = "Очень толстый от регена и брони, стан щитом",
		bb_h_drow_ranger = "Огромный урон издалека, сайленс с отталкиванием",
		bb_h_earth_spirit = "Катится и станит, сайленс камнями, трудно поймать",
		bb_h_earthshaker = "Огромный стан по площади, разлом перекрывает путь",
		bb_h_elder_titan = "Усыпляет по площади, ульта снимает броню и защиту от магии",
		bb_h_ember_spirit = "Цепи держат на месте, прыгает по ремнантам",
		bb_h_enchantress = "Замедляет атаки по себе, лечится, бьёт сильнее издалека",
		bb_h_enigma = "Чёрная дыра держит всю команду, есть призванные юниты",
		bb_h_faceless_void = "Хроносфера останавливает всех, прыжок откатывает урон",
		bb_h_furion = "Запирает в деревьях, армия трентов, ТП по карте",
		bb_h_grimstroke = "Связывает с союзником, сайленс фантомом, много магии",
		bb_h_gyrocopter = "Много урона по площади, ракета станит",
		bb_h_hoodwink = "Уводит атаки в деревья, уходит в инвиз приманкой",
		bb_h_huskar = "Чем меньше HP, тем сильнее и больше регенит, сайленсит",
		bb_h_invoker = "Много магии и контроля, уходит в инвиз",
		bb_h_jakiro = "Много магии по площади, стан и замедление",
		bb_h_juggernaut = "Крутится и не ловится контролем, лечится вардом",
		bb_h_keeper_of_the_light = "Много магии издалека, отталкивает и ослепляет",
		bb_h_kez = "Прыгает крюком, сайленсит, много урона",
		bb_h_kunkka = "Стан по площади и мощные удары по толпе",
		bb_h_largo = "Баффает союзников песнями, снимает с них контроль",
		bb_h_legion_commander = "Дуэль в одну цель, с каждой победой сильнее",
		bb_h_leshrac = "Огромный магический урон по площади, стан",
		bb_h_lich = "Прыгающая ульта и много замедлений",
		bb_h_life_stealer = "В ярости не ловится контролем, лечится с ударов",
		bb_h_lina = "Взрывная магия, стан и ульта в одну цель",
		bb_h_lion = "Хекс и стан, ульта добивает в одну цель",
		bb_h_lone_druid = "Медведь с предметами давит башни и героев",
		bb_h_luna = "Удары рикошетят по всем, ульта бьёт лучами по площади",
		bb_h_lycan = "Волки и превращение, очень быстро бегает",
		bb_h_magnataur = "Стягивает всех ультой и баффает урон союзникам",
		bb_h_marci = "Прыгает к союзнику и станит, в ульте бьёт сериями",
		bb_h_mars = "Арена запирает внутри, щит блокирует атаки спереди",
		bb_h_medusa = "Щит из маны, стрелы по всем, ульта превращает в камень",
		bb_h_meepo = "Много клонов, держит сетью, прыгает к своим",
		bb_h_mirana = "Стрела-стан издалека и инвиз для команды",
		bb_h_monkey_king = "Прыгает с деревьев, маскируется, вампиризм с ударов",
		bb_h_morphling = "Неуязвим в волне, меняет статы, чтобы выжить",
		bb_h_muerta = "В ульте бьёт магией и не получает физ урон, сайленс",
		bb_h_naga_siren = "Много иллюзий, уклонение, ульта усыпляет всю команду",
		bb_h_necrolyte = "Лечится и лечит, ульта казнит в одну цель",
		bb_h_nevermore = "Огромный урон, рейзы и ульта по площади",
		bb_h_night_stalker = "Ночью очень силён, страх сайленсит, летает в ульте",
		bb_h_nyx_assassin = "Инвиз, стан шипами, панцирь отражает урон",
		bb_h_obsidian_destroyer = "Чистый урон по площади, прячет союзников в астрал",
		bb_h_ogre_magi = "Мультикаст: станы и баффы по несколько раз",
		bb_h_omniknight = "Даёт союзникам защиту от физ урона и лечит",
		bb_h_oracle = "Ульта спасает союзника от смерти, развеивает",
		bb_h_pangolier = "Катится и станит, в шаре не ловится контролем",
		bb_h_phantom_assassin = "Уклоняется от атак и бьёт огромными критами",
		bb_h_phantom_lancer = "Огромная армия иллюзий",
		bb_h_phoenix = "Яйцо-ульта возрождает её, луч лечит союзников",
		bb_h_primal_beast = "Таранит и мнёт в одну цель, толстый",
		bb_h_puck = "Неуловимый: сайленс, прыжки, ульта держит на месте",
		bb_h_pudge = "Хук и ульта держат в одну цель, очень толстый",
		bb_h_pugna = "Высасывает HP, вард наказывает за каждый каст",
		bb_h_queenofpain = "Блинк и магия по площади, трудно поймать",
		bb_h_rattletrap = "Хук ловит издалека, станы и клетка",
		bb_h_razor = "Крадёт твой урон, молнии бьют в ответ",
		bb_h_riki = "Постоянно в инвизе, бьёт в спину, дым сайленсит",
		bb_h_ringmaster = "Кнут пугает, прячет союзников в ящик",
		bb_h_rubick = "Крадёт ваши заклинания, подбрасывает",
		bb_h_sand_king = "Стан по площади, в своей буре невидим",
		bb_h_shadow_demon = "Прячет союзников, снимает баффы, делает копии",
		bb_h_shadow_shaman = "Хекс и путы в одну цель, змеи ломают башни",
		bb_h_shredder = "Много чистого урона, уходит цепями, броня растёт",
		bb_h_silencer = "Сайленс на всю карту, ворует интеллект",
		bb_h_skeleton_king = "Воскресает после смерти, лечится с ударов",
		bb_h_skywrath_mage = "Огромная магия и сайленс-печать",
		bb_h_slardar = "Стан по площади и минус броня",
		bb_h_slark = "Крадёт статы, снимает с себя контроль, уходит",
		bb_h_snapfire = "Много магии по площади, стан печеньем",
		bb_h_sniper = "Бьёт с очень большого расстояния",
		bb_h_spectre = "Пассивно отражает урон, прыгает к тебе ультой",
		bb_h_spirit_breaker = "Разгоняется через всю карту и станит",
		bb_h_storm_spirit = "Летает молнией, очень трудно поймать",
		bb_h_sven = "Стан по площади и огромный урон в ульте",
		bb_h_techies = "Мины и взрывы по площади, прыгает со станом",
		bb_h_templar_assassin = "Барьер блокирует урон, прячется в инвиз, мощный удар",
		bb_h_terrorblade = "Иллюзии и обмен HP ультой",
		bb_h_tidehunter = "Огромная ульта-стан, очень толстый",
		bb_h_tinker = "Ракеты и лазер, всё перезаряжает, телепортируется",
		bb_h_tiny = "Подбрасывает и станит, огромный урон",
		bb_h_treant = "Невидим в лесу, лечит бронёй, ульта держит всех",
		bb_h_troll_warlord = "Не умирает в ульте, очень быстро бьёт",
		bb_h_tusk = "Снежок и удар, который подбрасывает",
		bb_h_undying = "Зомби и надгробие, лечится и крадёт силу",
		bb_h_ursa = "Каждый удар сильнее предыдущего",
		bb_h_vengefulspirit = "Стан и меняется с тобой местами",
		bb_h_venomancer = "Яд и варды по площади",
		bb_h_viper = "Яд, ульта выключает пассивки, стойкий к магии",
		bb_h_visage = "Птицы-фамильяры станят, щит из слоёв",
		bb_h_void_spirit = "Прыгает порталами, трудно поймать",
		bb_h_warlock = "Голем-ульта и лечение союзников",
		bb_h_weaver = "Инвиз и откат во времени",
		bb_h_windrunner = "Шакл в одну цель, уклоняется от атак",
		bb_h_winter_wyvern = "Проклятие заставляет бить своего, лечит союзников",
		bb_h_wisp = "Привязан к союзнику и лечит его",
		bb_h_witch_doctor = "Ульта-вард, стан бочкой и лечение",
		bb_h_zuus = "Ульта по всей карте и много магии",
		bb_it_abyssal_blade = "Абиссал: стан даже через BKB",
		bb_it_aeon_disk = "Аеон: спасает от быстрого убийства",
		bb_it_black_king_bar = "BKB: на него не действуют магия и контроль",
		bb_it_blade_mail = "Блейд Мейл: возвращает урон",
		bb_it_bloodstone = "Бладстоун: лечится от заклинаний",
		bb_it_bloodthorn = "Бладторн: сайленс и криты",
		bb_it_butterfly = "Бабочка: уклоняется от атак",
		bb_it_cyclone = "Еул: подкидывает себя и снимает контроль",
		bb_it_dagon = "Дагон: взрыв магией",
		bb_it_desolator = "Дезолятор: снижает броню",
		bb_it_ethereal_blade = "Е-Блейд: прячется от атак и бьёт магией",
		bb_it_force_staff = "Форс: отталкивается и убегает",
		bb_it_ghost = "Гост: атаки по нему не проходят",
		bb_it_glimmer_cape = "Глиммер: невидимость и щит от магии",
		bb_it_greater_crit = "Даедалус: огромные криты",
		bb_it_guardian_greaves = "Гривзы: лечат и снимают контроль с союзников",
		bb_it_gungir = "Гунгнир: держит на месте по площади",
		bb_it_heart = "Хард: огромная регенерация",
		bb_it_heavens_halberd = "Халберд: обезоруживает",
		bb_it_holy_locket = "Холи Локет: сильно лечит союзников",
		bb_it_hurricane_pike = "Пайк: отталкивает тебя и убегает",
		bb_it_invis_sword = "Шадоу Блейд: уходит в невидимость",
		bb_it_lotus_orb = "Лотус: отражает заклинания обратно",
		bb_it_manta = "Манта: иллюзии и снятие контроля",
		bb_it_monkey_king_bar = "МКБ: бьёт сквозь уклонение",
		bb_it_nullifier = "Нуллифаер: снимает твои сейвы",
		bb_it_orchid = "Орчид: сайленсит",
		bb_it_refresher = "Рефрешер: две ульты подряд",
		bb_it_rod_of_atos = "Атос: держит тебя на месте",
		bb_it_satanic = "Сатаник: сильно лечится с ударов",
		bb_it_shadow_amulet = "Шадоу Амулет: прячется в невидимость",
		bb_it_sheepstick = "Хекс: превращает тебя в зверька",
		bb_it_silver_edge = "Сильвер Эдж: невидимость и выключает пассивки",
		bb_it_sphere = "Линка: блокирует заклинание в одну цель",
		bb_it_wind_waker = "Винд Вейкер: улетает от урона",
		bb_how_abyssal_blade = "станит даже через BKB",
		bb_how_aeon_disk = "спасает тебя от быстрого убийства",
		bb_how_assault = "броня тебе и минус броня врагам",
		bb_how_bfury = "сплеш бьёт иллюзии и юнитов",
		bb_how_black_king_bar = "иммунитет к магии и большинству контроля",
		bb_how_blade_mail = "возвращает урон тому, кто тебя бьёт",
		bb_how_bloodthorn = "сайленс и атаки сквозь уклонение",
		bb_how_butterfly = "уклонение от атак",
		bb_how_crimson_guard = "блокирует физ урон всей команде",
		bb_how_cyclone = "подкидываешь себя и снимаешь контроль",
		bb_how_dagon = "сбивает Линку и добивает магией",
		bb_how_desolator = "минус броня: быстрее ломаешь толстых",
		bb_how_diffusal_blade = "замедляет и жжёт ману ударами",
		bb_how_disperser = "снимает с врага Гост, Глиммер и баффы и замедляет",
		bb_how_dust = "пыль показывает невидимых рядом",
		bb_how_ethereal_blade = "прожми на себя: атаки по тебе не проходят",
		bb_how_force_staff = "выталкиваешь себя или союзника из опасности",
		bb_how_gem = "показывает всех невидимых вокруг тебя",
		bb_how_ghost = "атаки по тебе не проходят несколько секунд",
		bb_how_glimmer_cape = "невидимость и щит от магии тебе или союзнику",
		bb_how_guardian_greaves = "лечит и снимает контроль с команды",
		bb_how_gungir = "держит на месте по площади",
		bb_how_harpoon = "притягивает врага к тебе",
		bb_how_heavens_halberd = "обезоруживает керри на несколько секунд",
		bb_how_lotus_orb = "отражает заклинание обратно и снимает контроль",
		bb_how_maelstrom = "молнии по иллюзиям и юнитам",
		bb_how_mage_slayer = "режет магический урон врага",
		bb_how_manta = "снимает сайленс и путы, даёт иллюзии",
		bb_how_mjollnir = "молнии чистят иллюзии и призыв",
		bb_how_monkey_king_bar = "атаки пробивают уклонение",
		bb_how_nullifier = "снимает с врага Гост, Глиммер и баффы на 4 секунды",
		bb_how_orchid = "сайленс: не даст кастовать и убежать",
		bb_how_pipe = "щит от магии на всю команду",
		bb_how_radiance = "жжёт иллюзии и юнитов вокруг",
		bb_how_rod_of_atos = "держит на месте и сбивает Линку",
		bb_how_sheepstick = "хекс: он не может кастовать и юзать предметы",
		bb_how_shivas_guard = "броня, режет скорость атаки врагов рядом и замедляет",
		bb_how_silver_edge = "выключает пассивки и даёт инвиз",
		bb_how_skadi = "вдвое режет лечение врага и замедляет",
		bb_how_solar_crest = "броня, скорость атаки и щит от физ урона союзнику",
		bb_how_sphere = "блокирует одно заклинание в тебя",
		bb_how_spirit_vessel = "режет лечение и регенерацию врага",
		bb_how_urn_of_shadows = "урон и лечение, дешевле Весселя",
		bb_how_ward_sentry = "сентри видит невидимых на месте",
		bb_how_wind_waker = "улетаешь от урона и контроля",
		bb_vs_helps = "поможет: %s",
		bb_live_magic = "тебя в основном бьют магией (%d%%)",
		bb_live_phys = "тебя в основном бьют атаками (%d%%)",
		bb_live_ctrl = "ты стоишь в контроле %.0f с за смерть",
		bb_tag_brk = "пассивки", bb_tag_eva = "уклонение", bb_tag_heal = "лечение", bb_tag_inv = "невидимость", bb_tag_ill = "иллюзии",
		bb_tag_save = "сейвы", bb_tag_tgt = "контроль в одну цель", bb_tag_sil = "сайленсы", bb_tag_esc = "убегает", bb_tag_ctl = "контроль",
		bb_tag_mag = "магия", bb_tag_phys = "физ урон", bb_tag_tank = "толстый",
		bb_pick_title = "Кого пикнуть (%s)",
		bb_pick_vs = "силён против: %s",
		bb_foe_title = "Кого опасаться",
		bb_next_usual = "обычно берут на %d мин · %d%% игр",
		bb_shelf_title = "Сборка",
		bb_shelf_hint = "минута = когда обычно берут",
		bb_next_title = "Следующий предмет",
		bb_chance_title = "Шанс на победу",
		bb_top = "Топ",
		bb_set_scale = "Размер окна",
		bb_upd_title = "Обновления",
		bb_set_update = "Обновлять автоматически",
		bb_upd_idle = "Проверяю GitHub раз в несколько часов",
		bb_upd_checking = "Проверяю...",
		bb_upd_latest = "У тебя последняя версия",
		bb_upd_available = "Доступна версия %s",
		bb_upd_loading = "Скачиваю %s...",
		bb_upd_done = "Обновлено до %s, перезагрузи скрипты",
		bb_upd_check = "Проверить",
		bb_upd_install = "Обновить",
		bb_upd_reload = "Перезагрузить",
		bb_upd_err_net = "GitHub не ответил, попробуй позже",
		bb_upd_err_file = "Файл скачался битым, попробуй позже",
		bb_upd_err_write = "Не могу записать файл скрипта",
		bb_upd_err_path = "Не нашёл файл скрипта, скачай вручную",
		bb_set_key_hint = "Клавиша окна меняется в меню Umbrella",
		bb_shelf_start = "Старт",
		bb_shelf_lane = "Лайнинг",
		bb_shelf_core = "Основные",
		bb_shelf_more = "Ещё берут",
		bb_vs_title = "Против врагов",
		bb_vs_empty = "Враги пока не видны",
		bb_vs_now = "можно",
		bb_vs_eta = "~%d мин",
		bb_kill_title = "Тебя убивает",
		bb_kill_deaths = "смертей: %d",
		bb_kill_empty = "Урона пока не было",
		bb_kill_ctrl = "%.0f с в контроле за смерть",
		bb_todo_title = "Что сделать",
		bb_todo_empty = "Ничего срочного",
		bb_todo_buy = "Купи %s: %s",
		bb_todo_hit = "Бей %s: %s",
		bb_fight_foes = "Враги сейчас",
		bb_foe_fog = "в тумане %d с",
		bb_foe_go = "можно бить",
		bb_foe_hp = "HP %d%%",
		bb_foe_ult_ready = "ульта готова",
		bb_foe_ult_cd = "ульта %d с",
		bb_foe_bkb_ready = "BKB готов",
		bb_foe_bkb_cd = "BKB %d с",
		bb_shop_skills = "ПОРЯДОК ИЗУЧЕНИЯ",
		bb_shop_talents = "ТАЛАНТЫ",
		bb_shop_back = "Гайд Доты",
		bb_shop_popular = "%d%% игр, ~%d мин",
		bb_shop_loading = "загружаю сборки",
		bb_pos_1 = "Керри (1)",
		bb_pos_2 = "Центр (2)",
		bb_pos_3 = "Сложная линия (3)",
		bb_pos_4 = "Поддержка (4)",
		bb_pos_5 = "Полная поддержка (5)",
		bb_set_shop = "Своя панель в магазине",
		bb_title = "Build Brain",
		bb_tab_draft = "Драфт",
		bb_tab_build = "Сборка",
		bb_tab_fight = "Бой",
		bb_tab_settings = "Настройки",
		bb_light = "Свет",
		bb_dark = "Тьма",
		bb_role = "роль",
		bb_chance_sub = "шанс по драфту",
		bb_chance_with = "с %s станет %d%%",
		bb_heat = "Кто кого",
		bb_heat_hint = "% к шансу",
		bb_heat_empty = "Появится, когда выберут героев",
		bb_best = "Лучший пик: %s",
		bb_best_hint = "к шансу",
		bb_best_vs = "сильный против %s",
		bb_best_empty = "Жду пики врагов",
		bb_threats = "Их драфт",
		bb_threats_hint = "к чему готовиться",
		bb_danger = "Опаснее всего для тебя",
		bb_threat_disable = "Контроль ×%d",
		bb_threat_disable_sub = "станы, хексы, сайленсы",
		bb_threat_nuke = "Взрыв ×%d",
		bb_threat_nuke_sub = "магический урон",
		bb_threat_init = "Инициаторы ×%d",
		bb_threat_init_sub = "прыгают в драку",
		bb_threat_escape = "Скользкие ×%d",
		bb_threat_escape_sub = "трудно поймать",
		bb_threat_durable = "Толстые ×%d",
		bb_threat_durable_sub = "много HP и брони",
		bb_threat_carry = "Керри ×%d",
		bb_threat_carry_sub = "сильны в поздней игре",
		bb_next = "Следующий предмет",
		bb_route = "Маршрут на игру",
		bb_route_hint = "минута при твоём доходе, золотая точка = под эту игру",
		bb_route_empty = "Выбери героя, и здесь будет маршрут",
		bb_situational = "По ситуации",
		bb_situational_hint = "почему именно сейчас",
		bb_situational_empty = "Пока ничего особенного",
		bb_final = "Финальные слоты",
		bb_final_hint = "к %d-й минуте",
		bb_buy_part = "Купить %s",
		bb_buy_all = "Купить",
		bb_quick = "В квикбай",
		bb_now = "сейчас",
		bb_later = "позже",
		bb_new = "новое",
		bb_minutes = "~%d мин при твоём доходе",
		bb_gold_of = "%d из %d",
		bb_why_popular = "Популярно на этом герое на этой стадии",
		bb_why_magic = "%d%% урона по тебе магия",
		bb_why_control = "%.0f с в контроле за смерть",
		bb_why_disablers = "%d героя с контролем у них",
		bb_why_item = "у %s есть %s",
		bb_why_invis = "%s уходит в инвиз",
		bb_fight_title = "Тебя убивает",
		bb_fight_hint = "за игру",
		bb_fight_empty = "Урона по тебе пока не было",
		bb_magic = "магия",
		bb_phys = "физический",
		bb_pure = "чистый",
		bb_control = "в контроле",
		bb_deaths = "смертей",
		bb_enemies = "Предметы врагов",
		bb_enemies_hint = "что на них видели",
		bb_enemies_empty = "Врагов пока не видели",
		bb_set_rank = "Ранг для статистики",
		bb_set_role = "Твоя роль",
		bb_set_auto = "Открывать на пиках",
		bb_on = "вкл",
		bb_off = "выкл",
		bb_rank_0 = "Все ранги",
		bb_rank_1 = "Рекрут",
		bb_rank_2 = "Страж",
		bb_rank_3 = "Рыцарь",
		bb_rank_4 = "Герой",
		bb_rank_5 = "Легенда",
		bb_rank_6 = "Властелин",
		bb_rank_7 = "Божество",
		bb_rank_8 = "Титан",
		bb_role_0 = "авто",
		bb_role_1 = "керри",
		bb_role_2 = "мид",
		bb_role_3 = "оффлейн",
		bb_role_4 = "саппорт 4",
		bb_role_5 = "саппорт 5",
		bb_status_ready = "Готово",
		bb_status_wait = "Жду драфт",
		bb_status_loading = "Загружаю статистику OpenDota",
		bb_status_offline = "OpenDota не отвечает, беру сохранённое",
		bb_status_quick = "В квикбай: %s",
		bb_status_buy = "Покупаю: %s",
		bb_status_poor = "Не хватает золота на %s",
	},
})

local UI = localization.WrapLibrary(Menu)
local lcache = {}
local lget = localization.Get

localization.Get = function(key, lang)
	if lang ~= nil or type(key) ~= "string" then return lget(key, lang) end
	local v = lcache[key]
	if v == nil then
		v = lget(key)
		lcache[key] = v
	end
	return v
end

local L = localization.Get
local JSON = require("assets.JSON")

local ui = {}

do
	local tab = UI.Create("Scripts", "Scripts", "Build Brain")
	tab:Icon("\u{f5dc}")

	local page = tab:Create("Settings")
	local g_main = page:Create("bb_group_main", Enum.GroupSide.Left)

	ui.enable = g_main:Switch("bb_enable", true, "\u{f011}")
	ui.enable:ToolTip("bb_enable_tip")

	ui.window_key = g_main:Bind("bb_window_key", Enum.ButtonCode.KEY_NONE, "\u{f2d0}")
	ui.window_key:ToolTip("bb_window_key_tip")


	ui.window_key:Properties(L("bb_bind_window"))
end

local function refresh_disabled()
	local on = ui.enable:Get()
	ui.window_key:Disabled(not on)
end

ui.enable:SetCallback(refresh_disabled, true)

local function log()
end

local K = {
	CONFIG = "build_brain",
	API = "https://api.opendota.com/api/",
	STATS_AGE = 86400,
	HERO_AGE = 3 * 86400,
	NET_TIMEOUT = 15,
	NET_RETRY = 60,
	PRIOR = 250,
	PAIR = 2000,
	ROLE_SHARE = 0.4,
	ROLE_META = 0.015,
	ROLE_MIN = 200,
	WIN_W = 940,
	WIN_H = 660,
	RAIL_W = 56,
	CX = 72,
	COL_L = 410,
	GAP = 14,
	TOP = 66,
	TAB_ICONS = { draft = "\u{f0c0}", build = "\u{f6e3}", fight = "\u{f05b}", settings = "\u{f013}" },
	LOGO = "\u{f5dc}",
	CLOSE = "\u{f00d}",
	ICON_OPEN = "\u{f2d0}",
	PICK_W = 340,
	GRID_SCAN = 4,
	GRID_STEP = 12,
	GRID_HL = 0.2,
	DMG_ROWS = { { "MAGIC", "bb_magic" }, { "PHYS", "bb_phys" }, { "PURE", "bb_pure" } },
	BASE_H = 1080,
	CLICK_GAP = 0.25,
	DRAFT_STEP = 0.5,
	DRAFT_SLOW = 3.0,
	MODEL_STEP = 1.0,
	DATA_STEP = 2.0,
	FOE_STEP = 1.0,
	STATE_STEP = 0.1,
	ROUTE_MAX = 9,
	EARLY_MAX = 3,
	SHOP_BASE_W = 280,
	RB_ROWS = 500,
	RB_MIN = 8,
	RB_FEW = 3,
	PT_RETRY = 30,
	SZ_FILE = "build_brain_builds.txt",
	SZ_BASE = "https://raw.githubusercontent.com/BraVoEw/Scripts-Umbrella/build-brain-data/",
	SZ_CHECK = 86400,
	PT_ITEMS = { ["Aghanim's Shard"] = "item_aghanims_shard", ["Aghanim's Blessing"] = "item_ultimate_scepter_2" },
	RN_POS = { 2, 1, 3, 4, 5 },
	CORE_SHARE = 0.3,
	SIT_SHARE = 0.08,
	PART_SHARE = 0.15,
	PART_GAP = 720,
	CORE_MAX = 10,
	POP_MAX = 12,
	ANIM = 12,
	CACHE_RESET = 300,
	ROLE_ICONS = { "safelane", "midlane", "offlane", "softsupport", "hardsupport" },
	SHOP_FIND = 2.0,
	SHOP_GEOM = 0.25,
	SHOP_GROW = 1.45,
	SHOP_MIN = 0.8,
	VS_MAX = 6,
	VS_STEP = 0.5,
	START_MAX = 5,
	GPM_DEFAULT = { 600, 620, 520, 380, 320 },
	IDENTIFIER = "build_brain",
	VERSION = "1.0.0",
	UPD_NAME = "build_brain.lua",
	UPD_LATEST = "https://raw.githubusercontent.com/BraVoEw/Scripts-Umbrella/main/build_brain/latest.txt",
	UPD_FILE = "https://raw.githubusercontent.com/BraVoEw/Scripts-Umbrella/build-brain-v%s/build_brain/build_brain.lua",
	UPD_EVERY = 21600,
	UPD_RETRY = 600,
	UPD_MIN = 100000,
	TABS = { "draft", "build", "fight", "settings" },
	LANE_BITS = { [1] = 1, [2] = 3, [4] = 2, [8] = 4, [16] = 5 },
	CROP_MIN = Vec2(0.21875, 0),
	CROP_MAX = Vec2(0.78125, 1),
	STAGES = {
		{ key = "start_game_items", min_cost = 0 },
		{ key = "early_game_items", min_cost = 400 },
		{ key = "mid_game_items", min_cost = 1400 },
		{ key = "late_game_items", min_cost = 2500 },
	},
	SKIP = {
		item_tpscroll = true, item_ward_observer = true, item_ward_sentry = true, item_ward_dispenser = true,
		item_smoke_of_deceit = true, item_clarity = true, item_flask = true, item_enchanted_mango = true,
		item_dust = true, item_tome_of_knowledge = true, item_blood_grenade = true, item_faerie_fire = true,
	},
	BOOTS = {
		item_boots = true, item_phase_boots = true, item_power_treads = true, item_tranquil_boots = true,
		item_arcane_boots = true, item_guardian_greaves = true, item_boots_of_bearing = true,
	},
	INVIS = {
		npc_dota_hero_riki = true, npc_dota_hero_clinkz = true, npc_dota_hero_bounty_hunter = true,
		npc_dota_hero_weaver = true, npc_dota_hero_nyx_assassin = true, npc_dota_hero_mirana = true,
		npc_dota_hero_invoker = true, npc_dota_hero_templar_assassin = true, npc_dota_hero_sand_king = true,
		npc_dota_hero_treant = true, npc_dota_hero_hoodwink = true,
	},
	ITEM_RULES = {
		item_butterfly = "item_monkey_king_bar",
		item_aeon_disk = "item_nullifier",
		item_ghost = "item_nullifier",
		item_glimmer_cape = "item_nullifier",
		item_invis_sword = "item_dust",
		item_silver_edge = "item_dust",
	},
	FOE_TAGS = {
		abaddon = "save heal", abyssal_underlord = "ctl tank", alchemist = "heal tank ctl", ancient_apparition = "mag ctl", antimage = "esc",
		arc_warden = "eva", axe = "ctl brk tgt tank", bane = "ctl tgt", batrider = "ctl tgt esc", beastmaster = "ill ctl tgt",
		bloodseeker = "sil heal tgt", bounty_hunter = "inv", brewmaster = "ctl eva", bristleback = "brk tank", broodmother = "ill heal esc",
		centaur = "ctl brk tank", chaos_knight = "ill ctl tgt heal", chen = "heal ill", clinkz = "inv phys", crystal_maiden = "ctl mag",
		dark_seer = "ill ctl", dark_willow = "ctl mag tgt", dawnbreaker = "heal ctl", dazzle = "save heal", death_prophet = "sil heal mag",
		disruptor = "ctl sil mag", doom_bringer = "ctl tgt sil", dragon_knight = "brk tank heal ctl", drow_ranger = "phys sil brk", earth_spirit = "ctl sil esc",
		earthshaker = "ctl mag", elder_titan = "ctl", ember_spirit = "esc mag ctl", enchantress = "heal brk", enigma = "ctl ill",
		faceless_void = "ctl esc brk", furion = "ill esc", grimstroke = "ctl mag tgt sil", gyrocopter = "mag phys", hoodwink = "esc inv",
		huskar = "heal brk sil", invoker = "mag inv ctl", jakiro = "mag ctl", juggernaut = "heal phys brk", keeper_of_the_light = "mag",
		kez = "esc phys sil", kunkka = "ctl phys", largo = "save", legion_commander = "ctl tgt phys", leshrac = "mag ctl",
		lich = "mag ctl", life_stealer = "heal brk", lina = "mag tgt", lion = "ctl mag tgt", lone_druid = "phys ctl",
		luna = "phys mag", lycan = "ill phys heal", magnataur = "ctl", marci = "phys heal ctl", mars = "ctl brk tank",
		medusa = "phys ctl", meepo = "ill ctl esc", mirana = "inv ctl", monkey_king = "phys esc heal", morphling = "esc",
		muerta = "mag sil", naga_siren = "ill eva ctl", necrolyte = "heal mag tgt", nevermore = "phys mag", night_stalker = "ctl phys sil heal",
		nyx_assassin = "inv mag ctl", obsidian_destroyer = "mag", ogre_magi = "ctl tgt", omniknight = "save heal", oracle = "save heal",
		pangolier = "esc ctl", phantom_assassin = "eva phys brk", phantom_lancer = "ill esc", phoenix = "mag heal", primal_beast = "ctl tgt tank",
		puck = "esc mag sil", pudge = "ctl tgt tank heal", pugna = "mag heal", queenofpain = "esc mag heal", rattletrap = "ctl",
		razor = "phys", riki = "inv brk sil", ringmaster = "ctl save", rubick = "mag ctl tgt", sand_king = "ctl mag inv",
		shadow_demon = "save ctl", shadow_shaman = "ctl tgt", shredder = "mag esc tank brk", silencer = "sil", skeleton_king = "brk heal tgt",
		skywrath_mage = "mag tgt sil", slardar = "ctl phys", slark = "esc brk heal", snapfire = "mag ctl", sniper = "phys tgt",
		spectre = "brk phys", spirit_breaker = "ctl tgt", storm_spirit = "esc mag", sven = "phys ctl", techies = "mag ctl",
		templar_assassin = "phys inv", terrorblade = "ill phys", tidehunter = "ctl brk tank", tinker = "mag esc", tiny = "ctl phys",
		treant = "heal ctl inv save", troll_warlord = "phys brk heal", tusk = "ctl", undying = "heal", ursa = "phys brk",
		vengefulspirit = "ctl tgt", venomancer = "mag ill", viper = "brk mag", visage = "ill ctl", void_spirit = "esc mag",
		warlock = "ctl heal", weaver = "inv esc", windrunner = "eva ctl tgt", winter_wyvern = "save ctl tgt heal", wisp = "heal save",
		witch_doctor = "mag heal ctl", zuus = "mag",
	},
	RULES = {
		{ tag = "brk", items = { "item_silver_edge" } },
		{ tag = "eva", items = { "item_monkey_king_bar", "item_bloodthorn" } },
		{ tag = "heal", items = { "item_spirit_vessel", "item_skadi" } },
		{ tag = "inv", items = { "item_dust", "item_ward_sentry", "item_gem" } },
		{ tag = "ill", items = { "item_mjollnir", "item_bfury", "item_radiance", "item_shivas_guard", "item_maelstrom" } },
		{ tag = "save", items = { "item_nullifier", "item_disperser", "item_sheepstick" } },
		{ tag = "tgt", items = { "item_sphere", "item_lotus_orb", "item_aeon_disk", "item_black_king_bar" } },
		{ tag = "sil", items = { "item_manta", "item_black_king_bar", "item_lotus_orb", "item_disperser", "item_cyclone", "item_guardian_greaves" } },
		{ tag = "esc", items = { "item_orchid", "item_bloodthorn", "item_abyssal_blade", "item_sheepstick", "item_rod_of_atos", "item_gungir", "item_harpoon", "item_disperser", "item_diffusal_blade" } },
		{ tag = "ctl", items = { "item_black_king_bar", "item_sphere", "item_lotus_orb", "item_manta", "item_aeon_disk", "item_glimmer_cape", "item_force_staff", "item_cyclone", "item_wind_waker" } },
		{ tag = "mag", items = { "item_black_king_bar", "item_pipe", "item_mage_slayer", "item_glimmer_cape" } },
		{ tag = "phys", items = { "item_ghost", "item_heavens_halberd", "item_shivas_guard", "item_crimson_guard", "item_assault", "item_blade_mail", "item_butterfly", "item_solar_crest", "item_force_staff", "item_ethereal_blade" } },
		{ tag = "tank", items = { "item_desolator", "item_assault", "item_spirit_vessel", "item_skadi" } },
	},
	ITEM_COUNTERS = {
		item_abyssal_blade = { "item_sphere", "item_lotus_orb", "item_aeon_disk" },
		item_aeon_disk = { "item_nullifier", "item_disperser" },
		item_black_king_bar = { "item_abyssal_blade", "item_ghost", "item_force_staff" },
		item_blade_mail = { "item_black_king_bar" },
		item_bloodstone = { "item_spirit_vessel", "item_skadi" },
		item_bloodthorn = { "item_manta", "item_lotus_orb", "item_black_king_bar" },
		item_butterfly = { "item_monkey_king_bar", "item_bloodthorn" },
		item_cyclone = { "item_sheepstick", "item_abyssal_blade" },
		item_dagon = { "item_black_king_bar", "item_lotus_orb", "item_glimmer_cape", "item_pipe" },
		item_desolator = { "item_ghost", "item_shivas_guard", "item_assault", "item_solar_crest" },
		item_ethereal_blade = { "item_nullifier", "item_disperser", "item_black_king_bar", "item_lotus_orb" },
		item_force_staff = { "item_sheepstick", "item_abyssal_blade", "item_harpoon" },
		item_ghost = { "item_nullifier", "item_disperser" },
		item_glimmer_cape = { "item_nullifier", "item_dust", "item_ward_sentry", "item_disperser" },
		item_greater_crit = { "item_ghost", "item_heavens_halberd", "item_shivas_guard", "item_butterfly" },
		item_guardian_greaves = { "item_spirit_vessel", "item_skadi" },
		item_gungir = { "item_manta", "item_cyclone", "item_black_king_bar" },
		item_heart = { "item_spirit_vessel", "item_skadi" },
		item_heavens_halberd = { "item_black_king_bar", "item_sphere", "item_lotus_orb" },
		item_holy_locket = { "item_spirit_vessel", "item_skadi" },
		item_hurricane_pike = { "item_sheepstick", "item_abyssal_blade", "item_harpoon" },
		item_invis_sword = { "item_dust", "item_ward_sentry", "item_gem" },
		item_lotus_orb = { "item_nullifier", "item_disperser" },
		item_manta = { "item_mjollnir", "item_bfury", "item_shivas_guard", "item_radiance" },
		item_monkey_king_bar = { "item_ghost", "item_heavens_halberd" },
		item_nullifier = { "item_sphere", "item_lotus_orb" },
		item_orchid = { "item_manta", "item_lotus_orb", "item_black_king_bar", "item_disperser" },
		item_refresher = { "item_black_king_bar", "item_aeon_disk" },
		item_rod_of_atos = { "item_manta", "item_cyclone", "item_black_king_bar", "item_disperser" },
		item_satanic = { "item_spirit_vessel", "item_skadi", "item_heavens_halberd" },
		item_shadow_amulet = { "item_dust", "item_ward_sentry" },
		item_sheepstick = { "item_sphere", "item_lotus_orb", "item_black_king_bar" },
		item_silver_edge = { "item_dust", "item_ward_sentry", "item_gem" },
		item_sphere = { "item_rod_of_atos", "item_force_staff", "item_orchid", "item_cyclone", "item_dagon", "item_harpoon" },
		item_wind_waker = { "item_sheepstick", "item_abyssal_blade" },
	},
	ROLE_ITEMS = {
		item_nullifier = "c",
		item_disperser = "c",
		item_diffusal_blade = "c",
		item_abyssal_blade = "c",
		item_black_king_bar = "c",
		item_manta = "c",
		item_sphere = "c",
		item_aeon_disk = "c",
		item_skadi = "c",
		item_monkey_king_bar = "c",
		item_bloodthorn = "c",
		item_mjollnir = "c",
		item_bfury = "c",
		item_radiance = "c",
		item_maelstrom = "c",
		item_heavens_halberd = "c",
		item_assault = "c",
		item_butterfly = "c",
		item_silver_edge = "c",
		item_desolator = "c",
		item_mage_slayer = "c",
		item_harpoon = "c",
		item_hurricane_pike = "c",
		item_dagon = "c",
		item_ethereal_blade = "c",
		item_shivas_guard = "c",
		item_crimson_guard = "c",
		item_blade_mail = "c",
		item_orchid = "c",
		item_ward_sentry = "s",
		item_gem = "s",
		item_glimmer_cape = "s",
		item_solar_crest = "s",
		item_guardian_greaves = "s",
		item_urn_of_shadows = "s",
	},
	UNIVERSAL = {
		item_dust = true,
		item_ward_sentry = true,
		item_gem = true,
		item_glimmer_cape = true,
		item_force_staff = true,
		item_ghost = true,
		item_spirit_vessel = true,
		item_black_king_bar = true,
	},
	UV0 = Vec2(0, 0),
	UV1 = Vec2(1, 1),
	NONE = {},
	WEAK = { __mode = "k" },
	QB_PANELS = { "QuickBuyRows", "StickyItemSlotContainer" },
	QB_FALLBACK = "quickbuy",
	DRAG_MIN = 6,
	IMG_BUDGET = 3,
	LABEL_BUDGET = 1,
	BOTTLE_TM = 150,
	BOTTLE = {
		storm_spirit = true, puck = true, queenofpain = true, pudge = true, kunkka = true, tinker = true, zuus = true,
		ember_spirit = true, void_spirit = true, invoker = true, lina = true, leshrac = true, death_prophet = true,
		templar_assassin = true, nevermore = true, batrider = true, mirana = true, windrunner = true, pugna = true,
		shredder = true, tiny = true, magnataur = true, skywrath_mage = true,
	},
	THREATS = {
		{ role = "Disabler", key = "disable", color = Color(251, 113, 133), letter = "C" },
		{ role = "Nuker", key = "nuke", color = Color(96, 165, 250), letter = "M" },
		{ role = "Initiator", key = "init", color = Color(232, 195, 122), letter = "I" },
		{ role = "Escape", key = "escape", color = Color(242, 243, 245), letter = "E" },
		{ role = "Durable", key = "durable", color = Color(52, 211, 153), letter = "D" },
		{ role = "Carry", key = "carry", color = Color(251, 146, 60), letter = "K" },
	},
	STATES = {
		Enum.ModifierState.MODIFIER_STATE_STUNNED,
		Enum.ModifierState.MODIFIER_STATE_HEXED,
		Enum.ModifierState.MODIFIER_STATE_SILENCED,
		Enum.ModifierState.MODIFIER_STATE_ROOTED,
	},
	SETTINGS = {
		{ key = "rank", title = "bb_set_rank", count = 9, default = 0, label = "bb_rank_" },
		{ key = "role", title = "bb_set_role", count = 6, default = 0, label = "bb_role_" },
		{ key = "auto", title = "bb_set_auto", count = 2, default = 1, flag = true },
		{ key = "shop", title = "bb_set_shop", count = 2, default = 1, flag = true },
		{ key = "scale", title = "bb_set_scale", count = 5, default = 1, values = { 90, 100, 110, 120, 130 } },
		{ key = "update", title = "bb_set_update", count = 2, default = 1, flag = true, own = true },
	},
}

local C = {
	WHITE = Color(255, 255, 255),
	BG = Color(22, 22, 24, 242),
	BG_TOP = Color(255, 255, 255, 10),
	BG_BOTTOM = Color(255, 255, 255, 0),
	EDGE = Color(255, 255, 255, 20),
	CARD = Color(29, 29, 32, 255),
	CARD_EDGE = Color(44, 44, 48, 255),
	RAIL = Color(17, 17, 19, 252),
	SLOT = Color(36, 36, 40, 255),
	ACCENT = Color(229, 72, 77),
	ACCENT_HOT = Color(240, 98, 102),
	TOGGLE_TRACK = Color(48, 48, 52),
	TOGGLE_OFF = Color(130, 132, 138),
	GO_EDGE = Color(52, 211, 153, 70),
	SHOP_DONE = Color(255, 255, 255, 120),
	DOT_DARK = Color(20, 22, 28),
	ROLE_DIM = Color(150, 156, 166),
	TAL_HOT = Color(48, 51, 60, 235),
	DOT_DARK2 = Color(18, 19, 23),
	LINE_FAINT = Color(255, 255, 255, 10),
	DRAG_TINT = Color(255, 255, 255, 215),
	SHADOW_SOFT = Color(0, 0, 0, 80),
	TOP_EDGE = Color(255, 255, 255, 13),
	SHINE_0 = Color(255, 255, 255, 0),
	SHINE_1 = Color(255, 255, 255, 24),
	GSHINE_0 = Color(255, 236, 190, 0),
	GSHINE_1 = Color(255, 240, 200, 150),
	MARK = Color(237, 237, 240, 150),
	TOGGLE_ON_TRACK = Color(229, 72, 77, 60),
	ROW = Color(255, 255, 255, 7),
	HOVER = Color(232, 195, 122, 22),
	TEXT = Color(237, 237, 240),
	MUTED = Color(168, 168, 179),
	DIM = Color(140, 140, 150),
	GOLD = Color(232, 195, 122),
	TAL_ON_OUT = Color(70, 44, 22, 240),
	TAL_ON_IN = Color(156, 96, 40, 240),
	TAL_OFF = Color(30, 32, 38, 235),
	TAL_BOX = Color(12, 13, 16, 230),
	VS = Color(232, 140, 80),
	GOLD_DEEP = Color(201, 154, 69),
	TALENT_BG = Color(44, 37, 24),
	DONE_TINT = Color(255, 255, 255, 110),
	DEAD_TINT = Color(255, 255, 255, 90),
	PILL_WIN = Color(52, 211, 153, 30),
	PILL_LOSE = Color(251, 113, 133, 30),
	GO_ROW = Color(52, 211, 153, 16),
	GOLD_HI = Color(245, 216, 154),
	GOLD_LO = Color(184, 137, 59),
	GOLD_GLOW = Color(232, 195, 122, 40),
	GOLD_CLEAR = Color(232, 195, 122, 0),
	GOLD_TEXT = Color(42, 28, 5),
	WIN = Color(52, 211, 153),
	LOSE = Color(251, 113, 133),
	MAGIC = Color(96, 165, 250),
	PHYS = Color(251, 146, 60),
	PURE = Color(245, 240, 230),
	TRACK = Color(255, 255, 255, 18),
	SEG = Color(255, 255, 255, 13),
	SEG_ON = Color(255, 255, 255, 26),
	BADGE = Color(0, 0, 0, 165),
	EMPTY = Color(232, 195, 122, 16),
	EMPTY_EDGE = Color(232, 195, 122, 150),
	ROW_HOT = Color(255, 255, 255, 16),
	SHADOW = Color(0, 0, 0, 130),
	SHOP_BG = Color(13, 15, 19, 242),
	SHOP_TOP = Color(255, 255, 255, 8),
	TITLE = Color(226, 229, 234),
	PICKED = Color(232, 195, 122, 46),
	UNPICKED = Color(0, 0, 0, 110),
	TIP = Color(32, 32, 36, 252),
	TOGGLE_ON = Color(201, 154, 69),
	CLOSE_HOT = Color(251, 113, 133, 60),
}

local fonts = {
	w500 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.MEDIUM),
	w600 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.SEMIBOLD),
	w700 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.BOLD),
	w800 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.EXTRABOLD),
	icon = Render.LoadFont("FontAwesomeEx", Enum.FontCreate.FONTFLAG_ANTIALIAS, 400),
}

local state = {
	images = {},
	names = {},
	ids = {},
	sizes = {},
	fits = {},
	settings = {},
	win = { visible = false, closed_by_user = false, tab = "draft", x = nil, y = nil, drag = nil, buttons = {}, status = nil, scale = 1, dropdown = nil },
	next_click = 0,
	cat = nil,
	flat = {},
	stats = nil,
	matchups = {},
	pop = {},
	net = { busy = false, queue = {}, queued = {}, failed = {}, offline = false },
	draft = { ours = {}, theirs = {}, bans = {}, my_team = nil, my_hero = nil, my_pos = nil, sig = "", phase = false },
	view = nil,
	preview_hero = nil,
	clock = 0,
	next_draft = 0,
	next_model = 0,
	next_data = 0,
	next_foes = 0,
	dmg = nil,
	foes = {},
	route_sig = "",
	route_changed = nil,
	shop = { buttons = {}, rect = nil, panels = nil, next_find = 0, next_geom = 0, geom = nil, hidden = nil, off = false, tip = nil },
	rb = {},
	pt = {},
	pt_next = {},
	item_img = {},
	img_budget = 0,
	label_budget = 0,
	sync = { busy = false, done = false },
	role_paths = {},
	mixes = setmetatable({}, { __mode = "k" }),
	points = {},
	btn_pool = {},
	btn_used = 0,
	alphas = setmetatable({}, { __mode = "k" }),
	hero_img = {},
	sz = {},
	sz_vs = {},
	sz_next = 0,
	anim = { win = 0 },
	dt = 0,
	wraps = {},
	abil_text = nil,
	next_cache_reset = 0,
	names_logged = false,
	abilities = {},
	talent_text = {},
	frame_error = nil,
	errors = {},
	update_error = nil,
}

local G = { ox = 0, oy = 0, s = 1, buttons = nil, alpha = 1 }

local function new_damage()
	return { phys = 0, mag = 0, pure = 0, src = {}, ctrl = 0, deaths = 0, alive = true, next_state = 0, first = false }
end

state.dmg = new_damage()

local function setting(key)
	local value = state.settings[key]
	if value == nil then
		for _, s in ipairs(K.SETTINGS) do
			if s.key == key then
				value = Config.ReadInt(K.CONFIG, "set_" .. key, s.default)
				if value < 0 or value >= s.count then value = s.default end
				state.settings[key] = value
			end
		end
	end
	return value or 0
end

local function set_setting(key, value)
	state.settings[key] = value
	Config.WriteInt(K.CONFIG, "set_" .. key, value)
end

local function same(a, b)
	return a ~= nil and b ~= nil and Entity.GetIndex(a) == Entity.GetIndex(b)
end

local function short_name(name)
	return (name:gsub("^item_", ""))
end

local function logit(p)
	p = math.max(0.001, math.min(0.999, p))
	return math.log(p / (1 - p))
end

local function sigmoid(x)
	return 1 / (1 + math.exp(-x))
end

local function hero_unit(id)
	if not id or id <= 0 then return nil end
	local row = state.stats and state.stats[id]
	if row and row.n then return row.n end
	local ok, name = pcall(Engine.GetHeroNameByID, id)
	return ok and name or nil
end

local function hero_id(unit)
	local id = state.ids[unit]
	if id == nil then
		local ok, value = pcall(Engine.GetHeroIDByName, unit)
		id = ok and value or false
		state.ids[unit] = id
	end
	return id or nil
end

local function load_image(path)
	local handle = state.images[path]
	if handle == nil then
		if state.img_budget <= 0 then return nil end
		state.img_budget = state.img_budget - 1
		local ok, h = pcall(Render.LoadImage, path)
		handle = ok and h or false
		state.images[path] = handle
	end
	return handle or nil
end

local function item_image(name)
	local path = state.item_img[name]
	if not path then
		path = "panorama/images/items/" .. short_name(name) .. "_png.vtex_c"
		state.item_img[name] = path
	end
	return load_image(path)
end

local function hero_image(unit)
	local path = state.hero_img[unit]
	if not path then
		path = "panorama/images/heroes/" .. unit .. "_png.vtex_c"
		state.hero_img[unit] = path
	end
	return load_image(path)
end

local function game_text(token)
	local ok, text = pcall(GameLocalizer.Find, token)
	if ok and type(text) == "string" and text ~= "" and not text:find("#", 1, true) and not text:find("DOTA_", 1, true) then return text end
	return nil
end

local function item_title(name)
	local key = "i" .. name
	local title = state.names[key]
	if not title then
		title = game_text("#DOTA_Tooltip_ability_" .. name)
		if not title then
			local ok, text = pcall(GameLocalizer.FindItem, name)
			title = ok and text and text ~= "" and text or short_name(name)
		end
		state.names[key] = title
		if not state.names_logged then
			state.names_logged = true
			log("item name " .. name .. " -> " .. title)
		end
	end
	return title
end

local function hero_title(unit)
	local key = "h" .. unit
	local title = state.names[key]
	if not title then
		local id = hero_id(unit)
		local row = id and state.stats and state.stats[id]
		if row and row.t then
			title = row.t
		else
			local ok, text = pcall(GameLocalizer.FindNPC, unit)
			title = ok and text and text ~= "" and text or unit:gsub("^npc_dota_hero_", "")
		end
		state.names[key] = title
	end
	return title
end

local function read_file(path)
	if not io or not io.open then return nil end
	local ok, f = pcall(io.open, path, "rb")
	if not ok or not f then return nil end
	local data = f:read("a")
	f:close()
	return data
end

local function decode(text)
	if type(text) ~= "string" or text == "" then return nil end
	local ok, data = pcall(JSON.decode, JSON, text)
	if ok then return data end
end

local function encode(data)
	local ok, text = pcall(JSON.encode, JSON, data)
	if ok then return text end
end

local function load_catalog()
	if state.cat then return state.cat end
	local cat = { by_name = {}, by_id = {}, parts = {} }
	state.cat = cat
	local dir = Engine.GetCheatDirectory() or ""
	if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
	local data = decode(read_file(dir .. "assets\\data\\items.json"))
	local root = type(data) == "table" and (data.DOTAAbilities or data) or nil
	if not root then
		log("catalog: items.json not read")
		return cat
	end
	for name, entry in pairs(root) do
		if type(entry) == "table" and name:match("^item_") then
			local id = tonumber(entry.ID)
			if id then
				cat.by_name[name] = { id = id, cost = tonumber(entry.ItemCost) or 0, recipe = entry.ItemRecipe == "1", gone = entry.ItemPurchasable == "0" or entry.IsObsolete == "1" }
				cat.by_id[id] = name
			end
		end
	end
	for name, entry in pairs(root) do
		if type(entry) == "table" and entry.ItemRecipe == "1" and type(entry.ItemResult) == "string" then
			local req = type(entry.ItemRequirements) == "table" and entry.ItemRequirements["01"] or nil
			if type(req) == "string" then
				local parts = {}
				for part in req:gmatch("[^;]+") do parts[#parts + 1] = (part:gsub("%*", "")) end
				if (tonumber(entry.ItemCost) or 0) > 0 then parts[#parts + 1] = name end
				cat.parts[entry.ItemResult] = parts
			end
		end
	end
	return cat
end

local function item_cost(name)
	local entry = load_catalog().by_name[name]
	return entry and entry.cost or 0
end

local function flat_parts(name)
	local cached = state.flat[name]
	if cached then return cached end
	local out = {}
	local cat = load_catalog()
	local function walk(item, depth)
		local parts = cat.parts[item]
		if not parts or depth > 6 then
			out[#out + 1] = item
			return
		end
		for _, part in ipairs(parts) do walk(part, depth + 1) end
	end
	walk(name, 0)
	state.flat[name] = out
	return out
end

local function contains(big, small)
	if big == small then return false end
	for _, part in ipairs(flat_parts(big)) do
		if part == small then return true end
	end
	local parts = load_catalog().parts[big]
	for _, part in ipairs(parts or {}) do
		if part == small or contains(part, small) then return true end
	end
	return false
end

local function cache_read(key, max_age)
	local text = Config.ReadString(K.CONFIG, key, "")
	if text == "" then return nil, false end
	return decode(text), os.time() - Config.ReadInt(K.CONFIG, key .. "_t", 0) <= max_age
end

local function cache_write(key, data)
	local text = encode(data)
	if not text then return end
	Config.WriteString(K.CONFIG, key, text)
	Config.WriteInt(K.CONFIG, key .. "_t", os.time())
end

local function compact_stats(rows)
	local out = {}
	for _, row in ipairs(rows) do
		local id = tonumber(row.id)
		if id then
			local p, w = {}, {}
			for b = 1, 8 do
				p[b] = tonumber(row[b .. "_pick"]) or 0
				w[b] = tonumber(row[b .. "_win"]) or 0
			end
			out[#out + 1] = { id = id, n = row.name, t = row.localized_name, r = table.concat(row.roles or {}, ","), p = p, w = w }
		end
	end
	return out
end

local function apply_stats(list)
	local stats = {}
	for _, row in ipairs(list or {}) do
		if row.id then stats[row.id] = row end
	end
	state.stats = stats
	state.names = {}
end

local function compact_matchups(rows)
	local out = {}
	for _, row in ipairs(rows) do
		local id = tonumber(row.hero_id)
		if id then out[#out + 1] = { id, tonumber(row.games_played) or 0, tonumber(row.wins) or 0 } end
	end
	return out
end

local function apply_matchups(hero, list)
	local map = {}
	for _, row in ipairs(list or {}) do map[row[1]] = { g = row[2], w = row[3] } end
	state.matchups[hero] = map
end

local function compact_pop(data)
	local out = {}
	for _, stage in ipairs(K.STAGES) do
		local list = {}
		for id, count in pairs(type(data[stage.key]) == "table" and data[stage.key] or {}) do
			list[#list + 1] = { tonumber(id), tonumber(count) or 0 }
		end
		table.sort(list, function(a, b) return a[2] > b[2] end)
		out[stage.key] = list
	end
	return out
end

local function net_request(job)
	local net = state.net
	net.busy = true
	local ok = pcall(HTTP.Request, "GET", K.API .. job.path, { timeout = K.NET_TIMEOUT }, function(res)
		net.busy = false
		net.queued[job.key] = nil
		local data = tonumber(res and res.code) == 200 and decode(res.response) or nil
		if not data then
			net.failed[job.key] = state.clock + K.NET_RETRY
			net.offline = true
			log("net " .. job.key .. " failed, code " .. tostring(res and res.code))
			return
		end
		net.offline = false
		local ok_apply, err = pcall(job.done, data)
		if not ok_apply then log("net " .. job.key .. " apply: " .. tostring(err)) end
		state.next_model = 0
		log("net " .. job.key .. " ok")
	end, job.key)
	if not ok then
		net.busy = false
		net.queued[job.key] = nil
		net.failed[job.key] = state.clock + K.NET_RETRY
	end
end

local function net_want(key, path, max_age, apply, compact)
	local net = state.net
	if net.queued[key] or (net.failed[key] and state.clock < net.failed[key]) then return end
	local cached, fresh = cache_read(key, max_age)
	if cached then
		apply(cached)
		if fresh then return end
	end
	net.queued[key] = true
	net.queue[#net.queue + 1] = {
		key = key,
		path = path,
		done = function(data)
			local small = compact(data)
			cache_write(key, small)
			apply(small)
		end,
	}
end

local function net_pump()
	local net = state.net
	if net.busy or #net.queue == 0 then return end
	net_request(table.remove(net.queue, 1))
end

local function want_hero(id)
	if id and id > 0 and not state.matchups[id] and not state.sz_vs[id] then
		net_want("mu_" .. id, "heroes/" .. id .. "/matchups", K.HERO_AGE, function(list) apply_matchups(id, list) end, compact_matchups)
	end
end

local function urlencode(str)
	return (str:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function rb_sql(id)
	return table.concat({
		"WITH ids AS (SELECT match_id FROM player_matches WHERE hero_id = ", id, " ORDER BY match_id DESC LIMIT ", K.RB_ROWS, "), ",
		"t AS (SELECT p.match_id, p.hero_id, p.player_slot, p.purchase_log, p.ability_upgrades_arr, ROW_NUMBER() OVER (PARTITION BY p.match_id, p.player_slot < 128 ",
		"ORDER BY CASE WHEN p.lane_role = 2 THEN 0 ELSE 1 END, p.gold_per_min DESC) AS rn FROM player_matches p JOIN ids USING(match_id)), ",
		"h AS (SELECT t.match_id, t.rn, t.purchase_log, t.ability_upgrades_arr, ((t.player_slot < 128) = m.radiant_win)::int AS win ",
		"FROM t JOIN matches m USING(match_id) WHERE t.hero_id = ", id, " AND t.purchase_log IS NOT NULL), ",
		"e AS (SELECT h.match_id, h.rn, h.win, x->>'key' AS item, (x->>'time')::int AS tm FROM h, unnest(h.purchase_log) x), ",
		"f AS (SELECT match_id, rn, win, item, min(tm) tm FROM e WHERE tm > 0 GROUP BY 1, 2, 3, 4), ",
		"st AS (SELECT match_id, rn, win, string_agg(item, ',' ORDER BY item) s FROM e WHERE tm <= 0 GROUP BY 1, 2, 3), ",
		"ss AS (SELECT rn, s, count(*) n, avg(win) w, ROW_NUMBER() OVER (PARTITION BY rn ORDER BY count(*) DESC) r FROM st GROUP BY rn, s), ",
		"ii AS (SELECT rn, item, count(*) n, avg(tm)::int tm, avg(win) w, ROW_NUMBER() OVER (PARTITION BY rn ORDER BY count(*) DESC) r FROM f GROUP BY rn, item), ",
		"lv AS (SELECT h.rn, u.lvl, u.ab, count(*) n, ROW_NUMBER() OVER (PARTITION BY h.rn, u.lvl ORDER BY count(*) DESC) r ",
		"FROM h, unnest(h.ability_upgrades_arr) WITH ORDINALITY u(ab, lvl) GROUP BY 1, 2, 3), ",
		"ab AS (SELECT h.rn, u.ab, count(DISTINCT h.match_id) n FROM h, unnest(h.ability_upgrades_arr) u(ab) GROUP BY 1, 2) ",
		"SELECT 'm' k, rn, NULL a, NULL::int b, count(*) n, NULL::int tm, round(avg(win), 3) w FROM h GROUP BY rn ",
		"UNION ALL SELECT 's', rn, s, NULL, n, NULL, round(w, 3) FROM ss WHERE r <= 3 ",
		"UNION ALL SELECT 'i', rn, item, NULL, n, tm, round(w, 3) FROM ii WHERE r <= 40 ",
		"UNION ALL SELECT 'l', rn, lvl::text, ab, n, NULL, NULL FROM lv WHERE r <= 3 AND lvl <= 25 ",
		"UNION ALL SELECT 'c', rn, NULL, ab, n, NULL, NULL FROM ab",
	})
end

local function compact_rb(data)
	local out = {}
	for pos = 1, 5 do out[pos] = { n = 0, w = 0, s = {}, i = {}, l = {}, c = {} } end
	for _, row in ipairs(type(data) == "table" and data.rows or {}) do
		local pos = K.RN_POS[tonumber(row.rn) or 0]
		local p = pos and out[pos]
		if p then
			local k, n, w = row.k, tonumber(row.n) or 0, tonumber(row.w) or 0
			if k == "m" then
				p.n, p.w = n, w
			elseif k == "s" and type(row.a) == "string" then
				p.s[#p.s + 1] = { row.a, n, w }
			elseif k == "i" and type(row.a) == "string" then
				p.i[#p.i + 1] = { row.a, n, tonumber(row.tm) or 0, w }
			elseif k == "l" then
				p.l[#p.l + 1] = { tonumber(row.a) or 0, tonumber(row.b) or 0, n }
			elseif k == "c" then
				p.c[#p.c + 1] = { tonumber(row.b) or 0, n }
			end
		end
	end
	return out
end

local function apply_rb(id, data)
	local out = {}
	for pos = 1, 5 do
		local p = type(data) == "table" and type(data[pos]) == "table" and data[pos] or {}
		local sets, levels, counts = {}, {}, {}
		for _, r in ipairs(p.s or {}) do
			local items = {}
			for name in tostring(r[1]):gmatch("[^,]+") do
				if name ~= "tpscroll" then items[#items + 1] = "item_" .. name end
			end
			sets[#sets + 1] = { items = items, n = r[2] or 0, w = r[3] or 0 }
		end
		table.sort(sets, function(a, b) return a.n > b.n end)
		for _, r in ipairs(p.l or {}) do
			local t = levels[r[1]] or {}
			t[#t + 1] = { r[2], r[3] }
			levels[r[1]] = t
		end
		for _, t in pairs(levels) do table.sort(t, function(a, b) return a[2] > b[2] end) end
		for _, r in ipairs(p.c or {}) do counts[r[1]] = r[2] end
		out[pos] = { n = p.n or 0, w = p.w or 0, sets = sets, items = p.i or {}, levels = levels, counts = counts }
	end
	state.rb[id] = out
end

local function want_rb(id)
	if not id or id <= 0 or state.rb[id] then return end
	net_want("rb_" .. id, "explorer?sql=" .. urlencode(rb_sql(id)), K.HERO_AGE, function(data) apply_rb(id, data) end, compact_rb)
end

local function want_pop(id)
	if id and id > 0 and not state.pop[id] then
		net_want("ip_" .. id, "heroes/" .. id .. "/itemPopularity", K.HERO_AGE, function(data) state.pop[id] = data end, compact_pop)
	end
end

local function base_logit(id)
	local row = state.stats and state.stats[id]
	if not row then return 0 end
	local rank = setting("rank")
	local picks, wins = 0, 0
	for b = 1, 8 do
		if rank == 0 or b == rank then
			picks = picks + (row.p[b] or 0)
			wins = wins + (row.w[b] or 0)
		end
	end
	return logit((wins + K.PRIOR * 0.5) / (picks + K.PRIOR))
end

local function pair_vs(a, b)
	local sv = state.sz_vs
	local s = sv[a]
	if s then return s[b] or 0 end
	s = sv[b]
	if s then return -(s[a] or 0) end
	local map = state.matchups[a]
	local m = map and map[b]
	if m then
		local e = sigmoid(base_logit(a) - base_logit(b))
		return logit((m.w + K.PAIR * e) / (m.g + K.PAIR)) - logit(e)
	end
	local back = state.matchups[b]
	m = back and back[a]
	if m then
		local e = sigmoid(base_logit(b) - base_logit(a))
		return -(logit((m.w + K.PAIR * e) / (m.g + K.PAIR)) - logit(e))
	end
	return 0
end

local function draft_logit(ours, theirs)
	local x = 0
	for _, a in ipairs(ours) do x = x + base_logit(a) end
	for _, b in ipairs(theirs) do x = x - base_logit(b) end
	for _, a in ipairs(ours) do
		for _, b in ipairs(theirs) do x = x + pair_vs(a, b) end
	end
	return x
end

local function team_of(player)
	local ok, team = pcall(Entity.GetTeamNum, player)
	return ok and team or nil
end

local function read_draft()
	local d = state.draft
	local okm, me = pcall(Players.GetLocal)
	if not okm or not me then
		d.phase = false
		return
	end
	local my_team, my_id = team_of(me), Player.GetPlayerID(me)
	if my_team ~= 2 and my_team ~= 3 then
		d.phase = false
		return
	end
	local ours, theirs = {}, {}
	local my_pos = nil
	for _, p in ipairs(Players.GetAll()) do
		local team = team_of(p)
		if team == 2 or team == 3 then
			local ok, data = pcall(Player.GetTeamData, p)
			data = ok and type(data) == "table" and data or {}
			local id = math.tointeger(tonumber(data.selected_hero_id) or 0) or 0
			if id <= 0 then
				local ok_hero, hero = pcall(Player.GetAssignedHero, p)
				id = ok_hero and hero and hero_id(NPC.GetUnitName(hero)) or 0
			end
			local okslot, slot = pcall(Player.GetPlayerTeamSlot, p)
			local pos = K.LANE_BITS[math.tointeger(tonumber(data.lane_selection_flags) or 0) or 0]
			local entry = { id = id > 0 and id or nil, slot = okslot and slot or 9, me = Player.GetPlayerID(p) == my_id, pos = pos }
			if entry.me then my_pos = pos end
			if team == my_team then ours[#ours + 1] = entry else theirs[#theirs + 1] = entry end
		end
	end
	table.sort(ours, function(a, b) return a.slot < b.slot end)
	table.sort(theirs, function(a, b) return a.slot < b.slot end)
	local bans = {}
	local okb, list = pcall(GameRules.GetBannedHeroes)
	if okb and type(list) == "table" then
		for _, id in pairs(list) do
			if tonumber(id) and tonumber(id) > 0 then bans[#bans + 1] = math.tointeger(tonumber(id)) end
		end
	end
	local my_hero = nil
	for _, e in ipairs(ours) do
		if e.me then my_hero = e.id end
	end
	local game_state = GameRules.GetGameState()
	d.ours, d.theirs, d.bans, d.my_team, d.my_hero, d.my_pos = ours, theirs, bans, my_team, my_hero, my_pos
	local pick = game_state == Enum.GameState.DOTA_GAMERULES_STATE_HERO_SELECTION
		or game_state == Enum.GameState.DOTA_GAMERULES_STATE_STRATEGY_TIME
	if not pick and game_state ~= Enum.GameState.DOTA_GAMERULES_STATE_PRE_GAME
		and game_state ~= Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		local ok, pre = pcall(Panorama.GetPanelByName, "PreGame", false)
		if ok and pre then
			local okv, vis = pcall(pre.IsVisible, pre)
			pick = okv and vis == true
		end
	end
	local okg, mode = pcall(GameRules.GetGameMode)
	if okg and (mode == Enum.GameMode.DOTA_GAMEMODE_CUSTOM or mode == Enum.GameMode.DOTA_GAMEMODE_ABILITY_DRAFT) then pick = false end
	d.phase = pick
	local parts = {}
	for _, e in ipairs(ours) do parts[#parts + 1] = tostring(e.id) .. ":" .. tostring(e.pos) end
	parts[#parts + 1] = "|"
	for _, e in ipairs(theirs) do parts[#parts + 1] = tostring(e.id) end
	parts[#parts + 1] = "|" .. table.concat(bans, ",")
	local sig = table.concat(parts, " ")
	if sig ~= d.sig then
		d.sig = sig
		state.next_model = 0
		state.next_data = 0
		log("draft team " .. tostring(my_team) .. ": " .. sig .. ", state " .. tostring(game_state))
	end
end

local function picked(list)
	local ids = {}
	for _, e in ipairs(list) do
		if e.id then ids[#ids + 1] = e.id end
	end
	return ids
end

local function my_position()
	local role = setting("role")
	if role > 0 then return role end
	return state.draft.my_pos or 1
end

local function role_fits(id, pos, shares)
	local sh = shares and shares.heroes[id]
	if sh then
		local n = sh.n[pos] or 0
		if n < K.ROLE_MIN or n < (shares.total[pos] or 0) * K.ROLE_META then return false end
		return sh.main == pos or n / sh.total >= K.ROLE_SHARE
	end
	local row = state.stats and state.stats[id]
	local roles = row and row.r or ""
	local support = roles:find("Support", 1, true) ~= nil
	if pos >= 4 then return support end
	if pos == 1 then return roles:find("Carry", 1, true) ~= nil end
	if pos == 3 then return roles:find("Initiator", 1, true) ~= nil or roles:find("Durable", 1, true) ~= nil end
	return not support or roles:find("Nuker", 1, true) ~= nil
end

local function pt_text(unit)
	local ok, text = pcall(Config.ReadString, "db", "protracker_shop." .. unit .. ".json", "")
	if ok and type(text) == "string" and text:sub(1, 1) == "{" then return text end
	local dir = Engine.GetCheatDirectory() or ""
	if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
	local raw = read_file(dir .. "db.json")
	local line = raw and raw:match('"db%.protracker_shop%.' .. unit .. '%.json":%s*([^\n]+)')
	if not line then return nil end
	line = line:gsub("%s*,?%s*$", "")
	local value = decode(line)
	if type(value) == "string" then return value end
	local body = line:match('^"(.*)"$')
	if not body then return nil end
	local out = body:gsub("\\(.)", function(c) return c == "n" and "\n" or (c == "t" and "\t" or c) end)
	return out
end

local function pt_load(unit)
	if not unit then return nil end
	local cached = state.pt[unit]
	if cached then return cached end
	local tries = state.pt_next[unit] or { at = 0, n = 0 }
	if tries.n >= 3 or tries.at > state.clock then return nil end
	tries.at, tries.n = state.clock + K.PT_RETRY, tries.n + 1
	state.pt_next[unit] = tries
	local text = pt_text(unit)
	local data = text and decode(text)
	if type(data) ~= "table" or type(data.data) ~= "table" then return nil end
	state.pt[unit] = data.data
	log("protracker build found for " .. unit)
	return data.data
end

local function pt_item(raw)
	if type(raw) ~= "string" then return nil end
	if K.PT_ITEMS[raw] then return K.PT_ITEMS[raw] end
	if raw:match("^item_") and load_catalog().by_name[raw] then return raw end
	return nil
end

local function pt_main(pt)
	local role = tostring(pt.default_role or ""):lower()
	if role:find("mid", 1, true) then return 2 end
	if role:find("off", 1, true) then return 3 end
	if role:find("hard", 1, true) then return 5 end
	if role:find("support", 1, true) or role:find("soft", 1, true) then return 4 end
	if role:find("carry", 1, true) or role:find("safe", 1, true) then return 1 end
	return nil
end

local function pt_route(pt, pos)
	local d = pt[tostring(pos)]
	if type(d) ~= "table" then return nil end
	local route, seen = {}, {}
	for i, raw in ipairs(type(d.anchor_build) == "table" and d.anchor_build or {}) do
		local name = pt_item(raw)
		if name and not seen[name] then
			seen[name] = true
			route[#route + 1] = { name = name, stage = i <= 3 and 2 or (i <= 6 and 3 or 4) }
		end
	end
	if #route == 0 then return nil end
	local pop = {}
	for _, raw in ipairs(type(d.anchor_item_stats) == "table" and d.anchor_item_stats or {}) do
		local name = pt_item(raw)
		if name and not seen[name] and #pop < K.POP_MAX then
			seen[name] = true
			pop[#pop + 1] = { name = name }
		end
	end
	local start = {}
	local first = type(d.starting_items_new) == "table" and d.starting_items_new[1] or nil
	if type(first) == "table" and type(first[1]) == "table" then
		for _, raw in ipairs(first[1]) do
			local name = pt_item(raw)
			if name then start[#start + 1] = name end
		end
	end
	local skills, talents = {}, {}
	for _, name in ipairs(type(d.abilities_new) == "table" and d.abilities_new or {}) do
		if type(name) == "string" then skills[#skills + 1] = name end
	end
	local visual = type(d.talents_visual) == "table" and d.talents_visual or {}
	for i, side in ipairs(type(d.talents) == "table" and d.talents or {}) do
		local right, left = visual[i * 2 - 1], visual[i * 2]
		if right and left then talents[i] = { right = right, left = left, pick = side == "left" and left or right } end
	end
	return { start = start, route = route, pop = pop, pos = pos, src = "pt", skills = skills, talents = talents }
end

local function sz_file()
	if state.sz_text then return state.sz_text end
	if state.clock < state.sz_next then return nil end
	state.sz_next = state.clock + K.PT_RETRY
	local dir = Engine.GetCheatDirectory() or ""
	if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
	state.sz_text = read_file(dir .. K.SZ_FILE)
	if not state.sz_text then return nil end
	state.sz_patch = state.sz_text:match("^BB1\t([^\t\n]+)") or ""
	log("stratz builds loaded, patch " .. state.sz_patch)
	return state.sz_text
end

local function sz_load(id)
	if not id then return nil end
	local cached = state.sz[id]
	if cached ~= nil then return cached or nil end
	local text = sz_file()
	if not text then return nil end
	local line = text:match("\n" .. id .. "\t([^\n]+)")
	local data = line and decode(line)
	state.sz[id] = type(data) == "table" and data or false
	return state.sz[id] or nil
end

local function sz_shares()
	if state.sz_pos then return state.sz_pos end
	local text = sz_file()
	if not text then return nil end
	local out, at = { heroes = {}, total = {} }, 1
	while true do
		local s, e, id = text:find("\n(%d+)\t", at)
		if not s then break end
		local stop = text:find("\n", e + 1, true) or #text + 1
		local n, total, from, main = {}, 0, e + 1, nil
		while true do
			local p1, p2, pos, count = text:find('"([1-5])":{"n":(%d+)', from)
			if not p1 or p1 > stop then break end
			local v, p = tonumber(count) or 0, tonumber(pos)
			n[p] = v
			total = total + v
			out.total[p] = (out.total[p] or 0) + v
			if not main or v > n[main] then main = p end
			from = p2 + 1
		end
		if total > 0 then out.heroes[tonumber(id)] = { n = n, total = total, main = main } end
		at = stop
	end
	state.sz_pos = out
	return out
end

local function sz_vs(id)
	local sv = state.sz_vs
	if not id or sv[id] ~= nil then return end
	local text = sz_file()
	if not text then return end
	if not state.sz_vidx then
		local idx, at = {}, 1
		while true do
			local s, e, hid = text:find("\nV\t(%d+)\t", at)
			if not s then break end
			idx[tonumber(hid)] = e + 1
			at = e + 1
		end
		state.sz_vidx = idx
	end
	local from = state.sz_vidx[id]
	if not from then
		sv[id] = false
		return
	end
	local stop = text:find("\n", from, true) or #text + 1
	local map = {}
	for h2, v in text:sub(from, stop - 1):gmatch("(%d+):(%-?%d+)") do map[tonumber(h2)] = tonumber(v) / 1000 end
	sv[id] = map
end

local function sz_main(d)
	local best, best_n = nil, 0
	for p = 1, 5 do
		local e = d[tostring(p)]
		if e and (e.n or 0) > best_n then best, best_n = p, e.n end
	end
	return best
end

local function sz_route(d, pos, unit)
	local shown, e = pos, d[tostring(pos)]
	if not e then
		shown = sz_main(d)
		e = shown and d[tostring(shown)]
	end
	if not e then return nil end
	local cat = load_catalog()
	local start, route, pop = {}, {}, {}
	for _, name in ipairs(e.start or {}) do
		if cat.by_name[name] then start[#start + 1] = name end
	end
	for _, r in ipairs(e.early or {}) do
		if cat.by_name[r[1]] then route[#route + 1] = { name = r[1], stage = 2, share = (r[3] or 0) / 100, tm = r[2] or 0, early = true } end
	end
	for _, r in ipairs(e.core or {}) do
		local tm = r[2] or 0
		if cat.by_name[r[1]] then route[#route + 1] = { name = r[1], stage = tm <= 720 and 2 or (tm <= 1560 and 3 or 4), share = (r[3] or 0) / 100, tm = tm } end
	end
	local short = unit and unit:gsub("^npc_dota_hero_", "")
	if shown == 2 and short and K.BOTTLE[short] then
		local has = false
		for _, step in ipairs(route) do
			if step.name == "item_bottle" then has = true end
		end
		if not has then route[#route + 1] = { name = "item_bottle", stage = 2, tm = K.BOTTLE_TM, early = true, reason = L("bb_why_bottle") } end
	end
	table.sort(route, function(p, q) return p.tm < q.tm end)
	for _, r in ipairs(e.sit or {}) do
		if cat.by_name[r[1]] then pop[#pop + 1] = { name = r[1], share = (r[2] or 0) / 100 } end
	end
	if #route == 0 then return nil end
	local counts = {}
	for k, v in pairs(e.talents or {}) do counts[tonumber(k) or k] = v end
	return { start = start, route = route, pop = pop, pos = shown, n = e.n or 0, src = "sz", skills = e.skills or {}, data = { n = e.n or 0, counts = counts } }
end

local function build_position(id)
	local role = setting("role")
	if role > 0 then return role, "set" end
	if state.draft.my_pos then return state.draft.my_pos, "lobby" end
	local sz = sz_load(id)
	local main = sz and sz_main(sz)
	if main then return main, "main" end
	local unit = hero_unit(id)
	local pt = unit and pt_load(unit)
	local pos = pt and pt_main(pt)
	if pos then return pos, "main" end
	local rb = id and state.rb[id]
	if rb then
		local best, best_n = nil, 0
		for p, e in ipairs(rb) do
			if e.n > best_n then best, best_n = p, e.n end
		end
		if best then return best, "main" end
	end
	return 1, "main"
end

local function od_route(id, pos)
	local rb = id and state.rb[id]
	if not rb then return nil end
	local shown, d = pos, rb[pos]
	if not d or d.n < K.RB_FEW then
		local best = nil
		for p, e in ipairs(rb) do
			if not best or e.n > best.n then best, shown = e, p end
		end
		d = best
	end
	if not d or d.n <= 0 then return nil end
	local cat = load_catalog()
	local cand = {}
	for _, r in ipairs(d.items) do
		local name = "item_" .. tostring(r[1])
		local entry = cat.by_name[name]
		local share = (r[2] or 0) / math.max(1, d.n)
		if entry and not entry.recipe and not K.SKIP[name] and share >= K.SIT_SHARE then
			cand[#cand + 1] = { name = name, share = share, tm = r[3] or 0, w = r[4] or 0, cost = entry.cost }
		end
	end
	local function covered(c)
		for _, o in ipairs(cand) do
			if o ~= c and o.share >= K.PART_SHARE and o.tm >= c.tm and o.tm - c.tm <= K.PART_GAP and contains(o.name, c.name) then return true end
		end
		return false
	end
	local core, pop, boots = {}, {}, false
	for _, c in ipairs(cand) do
		if not covered(c) then
			if c.share >= K.CORE_SHARE and c.cost >= 400 then
				if not K.BOOTS[c.name] or not boots then
					core[#core + 1] = c
					if K.BOOTS[c.name] then boots = true end
				end
			elseif c.cost >= 1000 then
				pop[#pop + 1] = c
			end
		end
	end
	table.sort(core, function(a, b) return a.tm < b.tm end)
	while #core > K.CORE_MAX do table.remove(core) end
	while #pop > K.POP_MAX do table.remove(pop) end
	local route = {}
	for _, c in ipairs(core) do
		route[#route + 1] = { name = c.name, stage = c.tm <= 720 and 2 or (c.tm <= 1560 and 3 or 4), share = c.share, tm = c.tm }
	end
	local start = d.sets[1] and d.sets[1].items or {}
	return { start = start, route = route, pop = pop, pos = shown, n = d.n, data = d, src = "od" }
end

local function role_route(id)
	if not id then return nil end
	local pos, how = build_position(id)
	local unit = hero_unit(id)
	local sz = sz_load(id)
	local role = sz and sz_route(sz, pos, unit)
	if not role then
		local pt = unit and pt_load(unit)
		role = (pt and pt_route(pt, pos)) or od_route(id, pos)
	end
	if not role then return nil end
	role.wanted, role.how = pos, how
	local rb = state.rb[id]
	role.od = rb and rb[pos] or nil
	return role
end

local function owned_items(hero)
	local owned = {}
	if not hero then return owned end
	for slot = 0, 16 do
		local item = NPC.GetItemByIndex(hero, slot)
		local name = item and Ability.GetName(item)
		if name then owned[name] = (owned[name] or 0) + 1 end
	end
	return owned
end

local function is_owned(name, owned)
	if owned[name] then return true end
	for have in pairs(owned) do
		if contains(have, name) then return true end
	end
	return false
end

local function base_route(id)
	local pop = id and state.pop[id]
	if not pop then return nil end
	local cat = load_catalog()
	local start, core, seen = {}, {}, {}
	for i, stage in ipairs(K.STAGES) do
		local taken = 0
		for _, row in ipairs(pop[stage.key] or {}) do
			local name = cat.by_id[row[1]]
			local entry = name and cat.by_name[name]
			if entry and not entry.recipe and not seen[name] then
				if i == 1 then
					if #start < K.START_MAX and name ~= "item_tpscroll" and not name:match("^item_ward") then
						start[#start + 1] = name
						seen[name] = true
					end
				elseif not K.SKIP[name] and entry.cost >= stage.min_cost and (i ~= 2 or taken < K.EARLY_MAX) then
					core[#core + 1] = { name = name, stage = i }
					seen[name] = true
					taken = taken + 1
				end
			end
		end
	end
	local route, boots = {}, false
	for i, step in ipairs(core) do
		local keep = true
		for j = i + 1, #core do
			if contains(core[j].name, step.name) then keep = false end
		end
		if keep and K.BOOTS[step.name] then
			if boots then keep = false else boots = true end
		end
		if keep and #route < K.ROUTE_MAX then route[#route + 1] = { name = step.name, stage = step.stage } end
	end
	return start, route
end

local function foe_counters(role, hero)
	local support = (role and role.wanted or my_position()) >= 4
	local have = {}
	for _, step in ipairs(role and role.route or K.NONE) do have[step.name] = true end
	for _, c in ipairs(role and role.pop or K.NONE) do have[c.name] = true end
	local function options(list)
		local out = {}
		for pass = 1, 2 do
			for _, name in ipairs(list) do
				local who = K.ROLE_ITEMS[name] or "a"
				local entry = load_catalog().by_name[name]
				if entry and not entry.gone and (who == "a" or (who == "s") == support) and (have[name] == true) == (pass == 1) then out[#out + 1] = name end
			end
		end
		return out
	end
	local function how(name)
		local key = "bb_how_" .. short_name(name)
		local text = L(key)
		return text ~= key and text or ""
	end
	local foes, seen = {}, {}
	for unit in pairs(state.foes) do
		foes[#foes + 1] = unit
		seen[unit] = true
	end
	for _, id in ipairs(picked(state.draft.theirs)) do
		local unit = hero_unit(id)
		if unit and not seen[unit] then
			foes[#foes + 1] = unit
			seen[unit] = true
		end
	end
	table.sort(foes)
	local owned = owned_items(hero)
	local rows, list, index, by_unit = {}, {}, {}, {}
	local function add(name, unit, reason, rank)
		local e = index[name]
		if not e then
			e = { name = name, key = "vs_" .. name, vs = true, foes = {}, why = {}, notes = {}, rank = rank }
			index[name] = e
			list[#list + 1] = e
		end
		e.rank = math.min(e.rank, rank)
		if not unit then
			e.notes[#e.notes + 1] = reason
			return
		end
		if not e.why[unit] then
			e.why[unit] = {}
			e.foes[#e.foes + 1] = unit
		end
		table.insert(e.why[unit], reason)
	end
	local function threat(units, text, reason, opts, rank, live)
		local avail = {}
		for _, name in ipairs(opts) do
			if not is_owned(name, owned) then avail[#avail + 1] = name end
		end
		if #avail == 0 then return end
		rows[#rows + 1] = { units = units, text = text, options = avail, how = how(avail[1]), rank = rank, live = live }
		for _, unit in ipairs(units) do
			by_unit[unit] = by_unit[unit] or {}
			local mine = by_unit[unit]
			local dup = false
			for _, n in ipairs(mine) do
				if n == avail[1] then dup = true end
			end
			if not dup and #mine < 3 then mine[#mine + 1] = avail[1] end
		end
		for _, name in ipairs(avail) do
			if have[name] or K.UNIVERSAL[name] then
				if #units == 0 then
					add(name, nil, reason, rank)
				else
					for _, unit in ipairs(units) do add(name, unit, reason, rank) end
				end
				return
			end
		end
	end
	local rules = {}
	for _, rule in ipairs(K.RULES) do rules[rule.tag] = rule end
	local dmg = state.dmg
	local total = dmg.phys + dmg.mag + dmg.pure
	if total > 1500 and dmg.mag / total >= 0.5 then
		local why = string.format(L("bb_live_magic"), math.floor(dmg.mag / total * 100 + 0.5))
		threat(K.NONE, why, why, options(rules.mag.items), 0, true)
	end
	if total > 1500 and dmg.phys / total >= 0.6 then
		local why = string.format(L("bb_live_phys"), math.floor(dmg.phys / total * 100 + 0.5))
		threat(K.NONE, why, why, options(rules.phys.items), 0, true)
	end
	if dmg.deaths >= 2 and dmg.ctrl / dmg.deaths >= 4 then
		local why = string.format(L("bb_live_ctrl"), dmg.ctrl / dmg.deaths)
		threat(K.NONE, why, why, options(rules.ctl.items), 0, true)
	end
	for _, unit in ipairs(foes) do
		for _, item in ipairs(state.foes[unit] and state.foes[unit].items or K.NONE) do
			local counters = K.ITEM_COUNTERS[item]
			if counters then
				local reason = L("bb_it_" .. short_name(item))
				threat({ unit }, hero_title(unit) .. ": " .. reason, reason, options(counters), 1)
			end
		end
	end
	for r, rule in ipairs(K.RULES) do
		local units = {}
		for _, unit in ipairs(foes) do
			local short = unit:gsub("^npc_dota_hero_", "")
			if (" " .. (K.FOE_TAGS[short] or "") .. " "):find(" " .. rule.tag .. " ", 1, true) then units[#units + 1] = unit end
		end
		if #units > 0 then
			local names = {}
			for k, unit in ipairs(units) do
				if k <= 2 then names[#names + 1] = hero_title(unit) end
			end
			local who = table.concat(names, ", ") .. (#units > 2 and (" +" .. (#units - 2)) or "")
			local reason = L("bb_vs_" .. rule.tag)
			threat(units, who .. ": " .. reason, reason, options(rule.items), 1 + r)
		end
	end
	table.sort(rows, function(p, q)
		if (p.live == true) ~= (q.live == true) then return p.live == true end
		if #p.units ~= #q.units then return #p.units > #q.units end
		return p.rank < q.rank
	end)
	while #rows > 8 do table.remove(rows) end
	for i, row in ipairs(rows) do row.key = "vt" .. i end
	table.sort(list, function(p, q)
		local a, b = #p.foes + #p.notes * 2, #q.foes + #q.notes * 2
		if a ~= b then return a > b end
		return p.rank < q.rank
	end)
	while #list > K.VS_MAX do table.remove(list) end
	for _, e in ipairs(list) do
		local parts = {}
		for _, note in ipairs(e.notes) do parts[#parts + 1] = note end
		for _, unit in ipairs(e.foes) do parts[#parts + 1] = hero_title(unit) .. ": " .. table.concat(e.why[unit], ", ") end
		local help = how(e.name)
		e.tip = table.concat(parts, "; ") .. (help ~= "" and (". " .. string.format(L("bb_vs_helps"), help)) or "")
	end
	local foe_rows = {}
	for _, unit in ipairs(foes) do
		local hero_short = unit:gsub("^npc_dota_hero_", "")
		local key = "bb_h_" .. hero_short
		local line = L(key)
		if line == key then
			local tags = {}
			for tag in (K.FOE_TAGS[hero_short] or ""):gmatch("%a+") do tags[#tags + 1] = L("bb_vs_" .. tag) end
			line = table.concat(tags, ", ")
		end
		foe_rows[#foe_rows + 1] = { unit = unit, line = line, items = by_unit[unit] or K.NONE }
	end
	return list, rows, foe_rows
end

local function income()
	local player = Players.GetLocal()
	local minutes = math.max(1, (GameRules.GetDOTATime() or 0) / 60)
	if player and (GameRules.GetDOTATime() or 0) > 180 then
		local ok, data = pcall(Player.GetTeamPlayer, player)
		local earned = ok and data and tonumber(data.totalearned_gold) or 0
		if earned > 0 then return earned / minutes end
	end
	return K.GPM_DEFAULT[my_position()] or 500
end

local function build_view(view)
	local d = state.draft
	local hero = Heroes.GetLocal()
	local id = d.my_hero or state.preview_hero or (view.best[1] and view.best[1].id)
	view.build_hero = id
	local start, route = base_route(id)
	local role = role_route(id)
	if role then start, route = role.start, role.route end
	view.role = role
	local sit, rows, foes = foe_counters(role, hero)
	view.vs, view.sit, view.vs_rows, view.foes = sit, sit, rows, foes
	if not route then return end
	local owned = owned_items(hero)
	local extra = 0
	for _, step in ipairs(route) do
		if step.early then extra = extra + 1 end
	end
	while #route > K.ROUTE_MAX + 2 + extra do table.remove(route) end
	local gpm = income()
	local now_min = math.max(0, (GameRules.GetDOTATime() or 0) / 60)
	local spent, next_step = 0, nil
	for _, name in ipairs(start) do spent = spent + item_cost(name) end
	local gold = 0
	local player = Players.GetLocal()
	if player then gold = Player.GetTotalGold(player) end
	for _, step in ipairs(route) do
		step.done = is_owned(step.name, owned)
		step.cost = item_cost(step.name)
		if step.done then
			spent = spent + step.cost
			step.minute = nil
		else
			local left = step.cost
			if not next_step then
				left = math.max(0, step.cost - gold)
				for _, part in ipairs(load_catalog().parts[step.name] or {}) do
					if owned[part] then left = math.max(0, left - item_cost(part)) end
				end
			end
			spent = spent + left
			step.minute = math.floor(math.max(now_min, now_min + left / gpm) + 0.5)
			now_min = step.minute
			if not next_step then next_step = step end
		end
	end
	view.start, view.route, view.next, view.sit, view.gpm, view.gold = start, route, next_step, sit, gpm, gold
	local finals = {}
	for i = #route, 1, -1 do
		local step = route[i]
		if not K.BOOTS[step.name] or #finals < 5 then table.insert(finals, 1, step) end
		if #finals >= 6 then break end
	end
	view.finals = finals
	view.final_minute = route[#route] and route[#route].minute or nil
	local sig = {}
	for _, step in ipairs(route) do sig[#sig + 1] = step.name end
	local text = table.concat(sig, ",")
	if text ~= state.route_sig then
		if state.route_sig ~= "" then state.route_changed = state.clock end
		state.route_sig = text
		log("route " .. text)
	end
	if next_step then
		local parts = {}
		for _, part in ipairs(load_catalog().parts[next_step.name] or {}) do
			parts[#parts + 1] = { name = part, cost = item_cost(part), have = owned[part] ~= nil }
		end
		next_step.parts = parts
	end
end

local function compute_view()
	local d = state.draft
	local ours, theirs = picked(d.ours), picked(d.theirs)
	local view = { ours = ours, theirs = theirs, cells = {}, totals = {}, best = {}, threats = {}, threat_counts = {}, danger = {} }
	for _, id in ipairs(ours) do sz_vs(id) end
	for _, id in ipairs(theirs) do sz_vs(id) end
	if state.stats then
		local x = draft_logit(ours, theirs)
		if #ours > 0 and #theirs > 0 then view.chance = math.floor(sigmoid(x) * 100 + 0.5) end
		for _, a in ipairs(ours) do
			local row, total = {}, 0
			for _, b in ipairs(theirs) do
				local v = pair_vs(a, b) * 25
				row[b] = v
				total = total + v
			end
			view.cells[a], view.totals[a] = row, total
		end
		local pos = my_position()
		if not d.my_hero and #theirs > 0 then
			local shares = sz_shares()
			local taken = {}
			for _, id in ipairs(ours) do taken[id] = true end
			for _, id in ipairs(theirs) do taken[id] = true end
			for _, id in ipairs(d.bans) do taken[id] = true end
			local list = {}
			for id in pairs(state.stats) do
				if not taken[id] and role_fits(id, pos, shares) then
					local with = {}
					for _, a in ipairs(ours) do with[#with + 1] = a end
					with[#with + 1] = id
					local gain = (sigmoid(draft_logit(with, theirs)) - sigmoid(x)) * 100
					local good = {}
					for _, b in ipairs(theirs) do
						local v = pair_vs(id, b)
						if v > 0 then good[#good + 1] = { id = b, v = v } end
					end
					table.sort(good, function(p, q) return p.v > q.v end)
					list[#list + 1] = { id = id, gain = gain, strong = good[1] and good[1].id, strong2 = good[2] and good[2].id }
				end
			end
			table.sort(list, function(p, q) return p.gain > q.gain end)
			for i = 1, math.min(4, #list) do
				local b = list[i]
				local names = {}
				for _, sid in ipairs({ b.strong, b.strong2 }) do
					local su = hero_unit(sid)
					if su then names[#names + 1] = hero_title(su) end
				end
				if #names > 0 then b.why = string.format(L("bb_pick_vs"), table.concat(names, ", ")) end
				view.best[i] = b
			end
			if view.best[1] and view.chance then view.hint = { id = view.best[1].id, chance = math.floor(view.chance + view.best[1].gain + 0.5) } end
		end
		for _, t in ipairs(K.THREATS) do
			local units = {}
			for _, id in ipairs(theirs) do
				local row = state.stats[id]
				if row and row.r:find(t.role, 1, true) then units[#units + 1] = hero_unit(id) end
			end
			view.threat_counts[t.key] = #units
			if #units > 0 then view.threats[#view.threats + 1] = { def = t, units = units } end
		end
		table.sort(view.threats, function(p, q) return #p.units > #q.units end)
		if d.my_hero then
			local list = {}
			for _, b in ipairs(theirs) do list[#list + 1] = { id = b, v = pair_vs(d.my_hero, b) * 25 } end
			table.sort(list, function(p, q) return p.v < q.v end)
			for i = 1, math.min(2, #list) do view.danger[i] = list[i] end
		end
	end
	local dmg = state.dmg
	local dtotal = dmg.phys + dmg.mag + dmg.pure
	local killers = {}
	for unit, value in pairs(dmg.src) do killers[#killers + 1] = { unit = unit, value = value, share = dtotal > 0 and value / dtotal or 0 } end
	table.sort(killers, function(p, q) return p.value > q.value end)
	while #killers > 3 do table.remove(killers) end
	view.killers = killers
	build_view(view)
	local live, todo = {}, {}
	for _, e in ipairs(view.vs or {}) do
		if #todo >= 2 then break end
		todo[#todo + 1] = string.format(L("bb_todo_buy"), item_title(e.name), e.tip or "")
	end
	local units = {}
	for unit in pairs(state.foes) do units[#units + 1] = unit end
	table.sort(units)
	for _, unit in ipairs(units) do
		local info = state.foes[unit]
		local age = state.clock - (info.at or 0)
		local hp = info.max and info.max > 0 and info.hp and info.hp / info.max or nil
		local row = { unit = unit, hp = hp, fog = age > 3 and math.floor(age) or nil, items = info.items, alive = info.alive ~= false }
		if info.ult_lvl and info.ult_lvl > 0 and info.ult_cd then
			local left = math.max(0, info.ult_cd - age)
			row.ult = left > 0.5 and string.format(L("bb_foe_ult_cd"), math.ceil(left)) or L("bb_foe_ult_ready")
			row.ult_ok = left > 5
		end
		if info.bkb_cd then
			local left = math.max(0, info.bkb_cd - age)
			row.bkb = left > 0.5 and string.format(L("bb_foe_bkb_cd"), math.ceil(left)) or L("bb_foe_bkb_ready")
			row.bkb_ok = left > 5
		end
		local low = hp and hp < 0.35
		local ready = (row.ult and not row.ult_ok) or (row.bkb and not row.bkb_ok)
		row.go = row.alive and age < 30 and not ready and (row.ult_ok or row.bkb_ok or low) and true or false
		if row.go and #todo < 4 then
			local why = {}
			if row.ult_ok then why[#why + 1] = row.ult end
			if row.bkb_ok then why[#why + 1] = row.bkb end
			if low then why[#why + 1] = string.format(L("bb_foe_hp"), math.floor(hp * 100 + 0.5)) end
			todo[#todo + 1] = string.format(L("bb_todo_hit"), hero_title(unit), table.concat(why, ", "))
		end
		live[#live + 1] = row
	end
	view.live, view.todo = live, todo
	state.view = view
end

local function want_data()
	if not state.stats then net_want("hero_stats", "heroStats", K.STATS_AGE, apply_stats, compact_stats) end
	local d = state.draft
	for _, e in ipairs(d.ours) do
		sz_vs(e.id)
		want_hero(e.id)
	end
	for _, e in ipairs(d.theirs) do
		sz_vs(e.id)
		want_hero(e.id)
	end
	local view = state.view
	local build_id = d.my_hero or state.preview_hero or (view and view.best[1] and view.best[1].id)
	if not sz_load(build_id) then
		want_pop(build_id)
		want_rb(build_id)
	end
end

local UPD = { st = "idle", latest = nil, err = nil, next_check = 0, path = nil, reload_at = nil, loaded = false, shown = nil, text = nil, tone = nil, title = "Build Brain " .. K.VERSION }

function UPD.num(v)
	local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)$")
	if not a then return 0 end
	return tonumber(a) * 1000000 + tonumber(b) * 1000 + tonumber(c)
end

function UPD.file()
	if UPD.path ~= nil then return UPD.path or nil end
	local list = {}
	local getinfo = type(debug) == "table" and debug.getinfo or nil
	if getinfo then
		local ok, info = pcall(getinfo, 1, "S")
		local src = ok and type(info) == "table" and type(info.source) == "string" and info.source or ""
		if src:match("^@.+%.lua$") then list[#list + 1] = src:sub(2) end
	end
	local dir = Engine.GetCheatDirectory() or ""
	if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
	list[#list + 1] = dir .. "scripts\\" .. K.UPD_NAME
	UPD.path = false
	for _, path in ipairs(list) do
		local ok, f = pcall(io.open, path, "rb")
		if ok and f then
			f:close()
			UPD.path = path
			break
		end
	end
	return UPD.path or nil
end

function UPD.get(url, done)
	local ok, sent = pcall(HTTP.Request, "GET", url, { timeout = K.NET_TIMEOUT }, function(res)
		done(tonumber(res and res.code) == 200 and type(res.response) == "string" and res.response or nil)
	end, "bb_update")
	if not ok or sent == false then done(nil) end
end

function UPD.save(path, body)
	local ok, f = pcall(io.open, path, "wb")
	if not ok or not f then return false end
	local written = f:write(body)
	f:close()
	return written ~= nil
end

function UPD.check(manual)
	if UPD.st == "checking" or UPD.st == "loading" or UPD.st == "done" then return end
	UPD.st, UPD.err = "checking", nil
	UPD.get(K.UPD_LATEST, function(body)
		local v = body and body:match("^%s*(%d+%.%d+%.%d+)%s*$")
		if not v then
			UPD.st, UPD.err = manual and "error" or "idle", "bb_upd_err_net"
			return
		end
		Config.WriteInt(K.CONFIG, "upd_checked", os.time())
		Config.WriteString(K.CONFIG, "upd_latest", v)
		UPD.latest = v
		if UPD.num(v) <= UPD.num(K.VERSION) then
			UPD.st = "latest"
			return
		end
		UPD.st = "available"
		if setting("update") == 1 then UPD.install() end
	end)
end

function UPD.install()
	local want = UPD.latest
	if not want or UPD.num(want) <= UPD.num(K.VERSION) or UPD.st == "loading" or UPD.st == "done" then return end
	local path = UPD.file()
	if not path then
		UPD.st, UPD.err = "error", "bb_upd_err_path"
		return
	end
	UPD.st, UPD.err = "loading", nil
	UPD.get(string.format(K.UPD_FILE, want), function(body)
		if not body then
			UPD.st, UPD.err = "error", "bb_upd_err_net"
			return
		end
		local found = body:match('\n\tVERSION = "([%d%.]+)",')
		if #body < K.UPD_MIN or found ~= want or not body:match("return script%s*$") then
			UPD.st, UPD.err = "error", "bb_upd_err_file"
			return
		end
		local tmp = path .. ".tmp"
		if not UPD.save(tmp, body) then
			UPD.st, UPD.err = "error", "bb_upd_err_write"
			return
		end
		pcall(os.remove, path)
		local okr, moved = pcall(os.rename, tmp, path)
		if not okr or not moved then
			if not UPD.save(path, body) then
				UPD.st, UPD.err = "error", "bb_upd_err_write"
				return
			end
			pcall(os.remove, tmp)
		end
		UPD.st = "done"
		Log.Write("[Build Brain] updated to " .. want)
	end)
end

function UPD.tick()
	if UPD.reload_at and state.clock >= UPD.reload_at then
		UPD.reload_at = nil
		pcall(Engine.ReloadScriptSystem)
		return
	end
	if state.clock < 5 or state.clock < UPD.next_check then return end
	UPD.next_check = state.clock + K.UPD_RETRY
	if not UPD.loaded then
		UPD.loaded = true
		local v = Config.ReadString(K.CONFIG, "upd_latest", "")
		if UPD.num(v) > UPD.num(K.VERSION) then
			UPD.latest, UPD.st = v, "available"
			if setting("update") == 1 then UPD.install() end
		end
	end
	if os.time() - Config.ReadInt(K.CONFIG, "upd_checked", 0) < K.UPD_EVERY then return end
	UPD.check(false)
end

function UPD.action()
	local st = UPD.st
	if st == "checking" or st == "loading" then return nil end
	if st == "done" then return "reload" end
	if UPD.latest and UPD.num(UPD.latest) > UPD.num(K.VERSION) and UPD.err ~= "bb_upd_err_path" then return "install" end
	return "check"
end

function UPD.act(kind)
	if kind == "check" then
		UPD.check(true)
	elseif kind == "install" then
		UPD.install()
	elseif kind == "reload" then
		UPD.reload_at = state.clock + 0.2
	end
end

function UPD.line()
	local key = UPD.st .. (UPD.err or "")
	if UPD.shown ~= key then
		UPD.shown = key
		local st = UPD.st
		if st == "error" then
			UPD.text, UPD.tone = L(UPD.err or "bb_upd_err_net"), C.LOSE
		elseif st == "available" or st == "loading" or st == "done" then
			UPD.text, UPD.tone = string.format(L("bb_upd_" .. st), UPD.latest or "?"), st == "done" and C.WIN or C.ACCENT
		else
			UPD.text, UPD.tone = L("bb_upd_" .. st), C.MUTED
		end
	end
	return UPD.text, UPD.tone
end

local function vec(px, py)
	local col = state.points[px]
	if not col then
		col = {}
		state.points[px] = col
	end
	local v = col[py]
	if not v then
		v = Vec2(px, py)
		col[py] = v
	end
	return v
end

local function P(x, y)
	return vec(math.floor(G.ox + x * G.s + 0.5), math.floor(G.oy + y * G.s + 0.5))
end

local function cursor_in(x1, y1, x2, y2)
	local cx, cy = Input.GetCursorPos()
	return cx >= x1 and cx <= x2 and cy >= y1 and cy <= y2
end

local function hovered(x, y, w, h)
	local a, b = P(x, y), P(x + w, y + h)
	return cursor_in(a.x, a.y, b.x, b.y)
end

local function button(kind, x, y, w, h, value)
	local a, b = P(x, y), P(x + w, y + h)
	local y1, y2 = a.y, b.y
	if G.clip1 then
		if y2 <= G.clip1.y or y1 >= G.clip2.y then return end
		y1, y2 = math.max(y1, G.clip1.y), math.min(y2, G.clip2.y)
	end
	local list = G.buttons or state.win.buttons
	state.btn_used = state.btn_used + 1
	local e = state.btn_pool[state.btn_used]
	if not e then
		e = {}
		state.btn_pool[state.btn_used] = e
	end
	e.kind, e.x1, e.y1, e.x2, e.y2, e.value = kind, a.x, y1, b.x, y2, value
	list[#list + 1] = e
end

local function alpha(c, t)
	local q = math.floor(math.max(0, math.min(1, t)) * 255 + 0.5)
	local slot = state.alphas[c]
	if not slot then
		slot = {}
		state.alphas[c] = slot
	end
	local out = slot[q]
	if not out then
		out = Color(c.r, c.g, c.b, math.floor(c.a * q / 255 + 0.5))
		slot[q] = out
	end
	return out
end

local function A(c)
	if G.alpha >= 1 then return c end
	return alpha(c, G.alpha)
end

local function mix(a, b, t)
	local q = math.floor(t * 32 + 0.5)
	if q <= 0 then return a end
	if q >= 32 then return b end
	local slot = state.mixes[a]
	if not slot then
		slot = setmetatable({}, K.WEAK)
		state.mixes[a] = slot
	end
	local row = slot[b]
	if not row then
		row = {}
		slot[b] = row
	end
	local out = row[q]
	if not out then
		local f = q / 32
		out = Color(math.floor(a.r + (b.r - a.r) * f + 0.5), math.floor(a.g + (b.g - a.g) * f + 0.5),
			math.floor(a.b + (b.b - a.b) * f + 0.5), math.floor(a.a + (b.a - a.a) * f + 0.5))
		row[q] = out
	end
	return out
end

local function tween(key, target, speed)
	local v = state.anim[key]
	if v == nil then
		state.anim[key] = target
		return target
	end
	if v ~= target then
		v = v + (target - v) * (1 - math.exp(-(speed or K.ANIM) * state.dt))
		if math.abs(target - v) < 0.002 then v = target end
		state.anim[key] = v
	end
	return v
end

local function hover_t(key, x, y, w, h)
	return tween(key, hovered(x, y, w, h) and 1 or 0, 16)
end

local function rect(x, y, w, h, color, r)
	Render.FilledRect(P(x, y), P(x + w, y + h), A(color), (r or 0) * G.s, r and Enum.DrawFlags.RoundCornersAll or Enum.DrawFlags.None)
end

local function frame_line(x, y, w, h, color, r, t)
	Render.Rect(P(x, y), P(x + w, y + h), A(color), (r or 0) * G.s, r and Enum.DrawFlags.RoundCornersAll or Enum.DrawFlags.None, t or 1)
end

local function grad(x, y, w, h, tl, tr, bl, br, r)
	Render.Gradient(P(x, y), P(x + w, y + h), A(tl), A(tr), A(bl), A(br), (r or 0) * G.s, r and Enum.DrawFlags.RoundCornersAll or Enum.DrawFlags.None)
end

local function shadow(x, y, w, h, r, size)
	Render.Shadow(P(x, y), P(x + w, y + h), A(C.SHADOW), size * G.s, r * G.s)
end

local function font_px(size)
	return math.max(1, math.floor(size * G.s + 0.5))
end

local function cache_slot(root, a, b, c)
	local t1 = root[a]
	if not t1 then
		t1 = {}
		root[a] = t1
	end
	local t2 = t1[b]
	if not t2 then
		t2 = {}
		t1[b] = t2
	end
	if c == nil then return t2 end
	local t3 = t2[c]
	if not t3 then
		t3 = {}
		t2[c] = t3
	end
	return t3
end

local function measure(font, size, str)
	local px = font_px(size)
	local slot = cache_slot(state.sizes, font, px)
	local v = slot[str]
	if not v then
		v = Render.TextSize(font, px, str)
		slot[str] = v
	end
	return v.x / G.s, v.y / G.s
end

local function fit(font, size, str, max_w)
	local slot = cache_slot(state.fits, font, font_px(size), math.floor(max_w))
	local out = slot[str]
	if out then return out end
	out = str
	if measure(font, size, str) > max_w then
		local len = utf8.len(str) or #str
		while len > 1 do
			len = len - 1
			local cut = str:sub(1, (utf8.offset(str, len + 1) or (#str + 1)) - 1) .. "…"
			if measure(font, size, cut) <= max_w then
				out = cut
				break
			end
		end
	end
	slot[str] = out
	return out
end

local function wrap(font, size, str, max_w, max_lines)
	local slot = cache_slot(state.wraps, font, font_px(size), math.floor(max_w) * 10 + max_lines)
	local out = slot[str]
	if out then return out end
	out = {}
	local line = ""
	for word in str:gmatch("%S+") do
		local joined = line == "" and word or (line .. " " .. word)
		if line == "" or measure(font, size, joined) <= max_w then
			line = joined
		else
			out[#out + 1] = line
			line = word
		end
	end
	if line ~= "" then out[#out + 1] = line end
	if #out > max_lines then
		local rest = table.concat(out, " ", max_lines)
		for i = #out, max_lines + 1, -1 do out[i] = nil end
		out[max_lines] = rest
	end
	for i, l in ipairs(out) do out[i] = fit(font, size, l, max_w) end
	slot[str] = out
	return out
end

local function text(font, size, str, x, y, color, align)
	if align then
		local w = measure(font, size, str)
		x = align == "center" and x - w / 2 or x - w
	end
	Render.Text(font, font_px(size), str, P(x, y), A(color))
end

local function picture(handle, x, y, w, h, r, gray, crop, tint)
	if not handle then
		rect(x, y, w, h, C.CARD, r)
		return
	end
	Render.Image(handle, P(x, y), vec(math.floor(w * G.s + 0.5), math.floor(h * G.s + 0.5)), A(tint or C.WHITE), (r or 0) * G.s,
		r and Enum.DrawFlags.RoundCornersAll or Enum.DrawFlags.None, crop and K.CROP_MIN or K.UV0, crop and K.CROP_MAX or K.UV1, gray or 0)
end

local function dot(x, y, r, color)
	Render.FilledCircle(P(x, y), r * G.s, A(color))
end

local function chevron(x, y, t, color)
	local dy = 2.5 * (1 - 2 * t)
	local mid = P(x, y + dy)
	Render.Line(P(x - 5, y - dy), mid, A(color), 1.6 * G.s)
	Render.Line(mid, P(x + 5, y - dy), A(color), 1.6 * G.s)
end

local W = { dead = {}, seen = {}, seen_at = {}, todo_at = {}, todo_n = 0, foe_at = {}, item_at = {}, drop = {}, base_a = 1, base_y = 0, flat = false }

function W.ease(t)
	if t <= 0 then return 0 end
	if t >= 1 then return 1 end
	local u = 1 - t
	return 1 - u * u * u
end

function W.since(t0, delay, dur)
	if W.flat then return 1 end
	return W.ease((state.clock - (t0 or 0) - delay) / dur)
end

function W.block(i)
	local e = W.since(state.win.open_at, i * 0.04, 0.24)
	G.alpha = W.base_a * e
	G.oy = W.base_y + (1 - e) * 8 * G.s
	return e
end

function W.unblock()
	G.alpha, G.oy = W.base_a, W.base_y
end

function W.count(key, value)
	return math.floor(tween(key, value, 7) + 0.5)
end

function W.soft(x, y, w, h, r, size)
	Render.Shadow(P(x, y), P(x + w, y + h), A(C.SHADOW_SOFT), size * G.s, r * G.s)
end

function W.card(x, y, w, h, title, hint)
	rect(x, y, w, h, C.CARD, 10)
	rect(x + 10, y, w - 20, 1, C.TOP_EDGE)
	frame_line(x, y, w, h, C.CARD_EDGE, 10)
	if title then text(fonts.w600, 16, title, x + 16, y + 14, C.TEXT) end
	if hint then text(fonts.w500, 13, hint, x + w - 16, y + 16, C.MUTED, "right") end
end

function W.dots(x, y)
	for i = 0, 2 do
		local a = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(state.clock * 5 - i * 0.8))
		dot(x + i * 11, y, 3, alpha(C.MUTED, a))
	end
end

function W.note(label, x, y, w)
	W.dots(x + 20, y + 59)
	for i, l in ipairs(wrap(fonts.w500, 14, label, w - 76, 2)) do text(fonts.w500, 14, l, x + 52, y + 50 + (i - 1) * 20, C.MUTED) end
end

function W.shine(x, y, w, h, t, c0, c1)
	if t <= 0 or t >= 1 then return end
	local bw = math.max(36, w * 0.3)
	local bx = x - bw + (w + bw) * t
	Render.PushClip(P(x, y), P(x + w, y + h), true)
	grad(bx, y, bw / 2, h, c0, c1, c0, c1)
	grad(bx + bw / 2, y, bw / 2, h, c1, c0, c1, c0)
	Render.PopClip()
end

function W.skeleton(x, y, w, h, i)
	rect(x, y, w, h, C.SLOT, 8)
	rect(x + 12, y + (h - 34) / 2, 60, 34, C.ROW_HOT, 6)
	rect(x + 84, y + h / 2 - 9, w * 0.35, 8, C.ROW_HOT, 4)
	rect(x + 84, y + h / 2 + 5, w * 0.22, 6, C.ROW, 3)
	W.shine(x, y, w, h, ((state.clock * 0.7 + i * 0.15) % 1.6) / 1.6, C.SHINE_0, C.SHINE_1)
end

function W.glow(x, y, w, h, r, a)
	frame_line(x - 2, y - 2, w + 4, h + 4, alpha(C.GOLD, a or 1), r + 2, 2)
	frame_line(x - 5, y - 5, w + 10, h + 10, alpha(C.GOLD_GLOW, a or 1), r + 5, 3)
end

function W.glyph(ch, size, x, y, color)
	local w, h = measure(fonts.icon, size, ch)
	text(fonts.icon, size, ch, x - w / 2, y - h / 2, color)
end

function W.pressed(hot)
	return hot > 0.5 and Input.IsKeyDown(Enum.ButtonCode.KEY_MOUSE1)
end

function W.btn(key, x, y, w, h)
	local hot = hover_t(key, x, y, w, h)
	local p = tween("pr_" .. key, W.pressed(hot) and 1 or 0, 30)
	local k = 0.03 * p
	return x + w * k / 2, y + h * k / 2 - hot * 1.5, w * (1 - k), h * (1 - k), hot
end

function W.icon(handle, x, y, w, h, r, key, gray, tint)
	local hot = hover_t(key, x, y, w, h)
	if hot > 0.01 then
		local k = 0.08 * hot
		picture(handle, x - w * k / 2, y - h * k / 2, w * (1 + k), h * (1 + k), r, gray, false, tint)
	else
		picture(handle, x, y, w, h, r, gray, false, tint)
	end
	return hot
end

function W.pop(t)
	if t >= 0.3 then return 1 end
	if t < 0.18 then return 0.7 + 0.38 * W.ease(t / 0.18) end
	return 1.08 - 0.08 * W.ease((t - 0.18) / 0.12)
end

function W.first_seen(key, value)
	if W.seen[key] ~= value then
		W.seen[key] = value
		W.seen_at[key] = state.clock
	end
	return state.clock - W.seen_at[key]
end

function W.shell(w, h)
	W.soft(0, 0, w, h, 12, 36)
	rect(0, 0, w, h, C.BG, 12)
	rect(0, 0, K.RAIL_W, h, C.RAIL, 12)
	rect(K.RAIL_W - 12, 0, 12, h, C.RAIL)
	rect(12, 0, w - 24, 1, C.TOP_EDGE)
	frame_line(0, 0, w, h, C.EDGE, 12)
end

function W.rail_y(tab, h)
	if tab == "settings" then return h - 60 end
	local y = 70
	for _, t in ipairs(K.TABS) do
		if t == tab then return y end
		if t ~= "settings" then y = y + 50 end
	end
	return y
end

function W.rail_item(tab, y)
	local on = state.win.tab == tab
	local hot = hover_t("rail_" .. tab, 0, y, K.RAIL_W, 46)
	local lit = math.max(tween("rail_on_" .. tab, on and 1 or 0, 14), hot * 0.6)
	if hot > 0.01 and not on then rect(7, y + 2 - hot, K.RAIL_W - 14, 42, alpha(C.ROW_HOT, hot), 8) end
	W.glyph(K.TAB_ICONS[tab], 18, K.RAIL_W / 2, y + 23 - hot, mix(mix(C.DIM, C.TEXT, lit), C.ACCENT, tween("rail_red_" .. tab, on and 1 or 0, 14)))
	if tab == "settings" and (UPD.st == "available" or UPD.st == "done") then dot(K.RAIL_W / 2 + 11, y + 12 - hot, 4, C.ACCENT) end
	button("tab", 0, y, K.RAIL_W, 46, tab)
end

function W.rail(h)
	W.glyph(K.LOGO, 21, K.RAIL_W / 2, 31, C.ACCENT)
	local iy = tween("rail_ind", W.rail_y(state.win.tab, h), 16)
	rect(0, iy + 11, 3, 24, C.ACCENT, 2)
	for _, tab in ipairs(K.TABS) do W.rail_item(tab, W.rail_y(tab, h)) end
end

function W.header(w)
	local win = state.win
	local view = state.view
	button("header", K.RAIL_W, 0, w - K.RAIL_W - 56, 56)
	local x = K.RAIL_W + 20
	text(fonts.w500, 16, L("bb_title"), x, 19, C.MUTED)
	x = x + measure(fonts.w500, 16, L("bb_title"))
	text(fonts.w500, 16, " / ", x, 19, C.DIM)
	x = x + measure(fonts.w500, 16, " / ")
	text(fonts.w600, 16, L("bb_tab_" .. win.tab), x, 19, C.ACCENT)
	local cx = w - 46
	local bx, by, bw, bh, hot = W.btn("close", cx, 14, 30, 30)
	if hot > 0.01 then rect(bx, by, bw, bh, alpha(C.CLOSE_HOT, hot), 8) end
	W.glyph(K.CLOSE, 15, bx + bw / 2, by + bh / 2, mix(C.DIM, C.TEXT, hot))
	button("close", cx, 14, 30, 30)
	local right = cx - 16
	local busy = (state.net.busy and L("bb_status_loading")) or (state.net.offline and L("bb_status_offline"))
	if win.status or (busy and win.tab ~= "build") then
		text(fonts.w500, 14, fit(fonts.w500, 14, win.status or busy, 320), right, 20, C.MUTED, "right")
	elseif win.tab == "build" and view and view.gold then
		local gpm = W.count("hdr_gpm", math.floor(view.gpm or 0))
		local label = "GPM " .. gpm
		text(fonts.w500, 14, label, right, 20, C.MUTED, "right")
		right = right - measure(fonts.w500, 14, label) - 16
		text(fonts.w700, 15, tostring(W.count("hdr_gold", view.gold)), right, 19, C.GOLD, "right")
	else
		local rank, pos = setting("rank"), my_position()
		local key = rank * 10 + (tonumber(pos) or 0)
		if win.info_key ~= key then
			win.info_key = key
			win.info = L("bb_rank_" .. rank) .. " · " .. L("bb_role") .. " " .. L("bb_role_" .. pos)
		end
		text(fonts.w500, 14, win.info, right, 20, C.MUTED, "right")
	end
end

function W.slots(x, y, w, list, label, color, key)
	dot(x + 5, y + 9, 4, color)
	text(fonts.w500, 14, label, x + 17, y, C.MUTED)
	local bw = (w - 4 * 8) / 5
	local bh = math.floor(bw * 0.5625 + 0.5)
	y = y + 24
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 3)
	for i = 1, 5 do
		local e = list[i]
		local px = x + (i - 1) * (bw + 8)
		local unit = e and e.id and hero_unit(e.id)
		rect(px, y, bw, bh + 5, C.SLOT, 8)
		if unit then
			local t = W.first_seen(key .. i, e.id)
			local sc = W.pop(t)
			local cw, ch = bw * sc, bh * sc
			picture(hero_image(unit), px + (bw - cw) / 2, y + (bh - ch) / 2, cw, ch, 8, 0, false)
			local flash = 1 - math.min(1, t / 0.45)
			if flash > 0 then rect(px, y, bw, bh, alpha(color, 0.5 * flash), 8) end
			if e.me then W.glow(px, y, bw, bh, 8) end
		else
			W.seen[key .. i] = nil
			frame_line(px, y, bw, bh + 5, alpha((e and e.me) and C.GOLD or C.MUTED, 0.2 + 0.35 * pulse), 8, 1.5)
		end
		rect(px + 8, y + bh + 1, bw - 16, 3, color, 2)
		if e and e.pos then
			rect(px + 4, y + 4, 18, 17, C.BADGE, 5)
			text(fonts.w600, 12, tostring(e.pos), px + 13, y + 5, C.TEXT, "center")
		end
	end
	return y + bh + 5
end

function W.chance(x, y, w, h)
	local d = state.draft
	local view = state.view
	local light = d.my_team ~= 3
	local chance = view and view.chance
	W.card(x, y, w, h, L("bb_chance_title"))
	local bx, bw, by = x + 16, w - 32, y + 52
	if chance then
		if state.anim.chance == nil then state.anim.chance = 50 end
		local shown = tween("chance", chance, 5)
		local rad = light and shown or (100 - shown)
		text(fonts.w700, 22, math.floor(shown + 0.5) .. "%", x + w - 16, y + 10, light and C.WIN or C.LOSE, "right")
		local split = bw * rad / 100
		rect(bx, by, split, 8, C.WIN, 4)
		rect(bx + split, by, bw - split, 8, C.LOSE, 4)
		rect(bx + bw / 2, by - 4, 1, 16, C.MARK)
		local r = math.floor(rad + 0.5)
		text(fonts.w600, 13, L("bb_light") .. " " .. r, bx, by + 16, C.WIN)
		text(fonts.w600, 13, (100 - r) .. " " .. L("bb_dark"), bx + bw, by + 16, C.LOSE, "right")
	else
		rect(bx, by, bw, 8, C.TRACK, 4)
		W.shine(bx, by, bw, 8, ((state.clock * 0.6) % 1.4) / 1.4, C.SHINE_0, C.SHINE_1)
		text(fonts.w500, 13, L("bb_chance_sub"), bx, by + 16, C.MUTED)
	end
	local ty = W.slots(bx, by + 44, bw, d.ours, light and L("bb_light") or L("bb_dark"), light and C.WIN or C.LOSE, "so")
	W.slots(bx, ty + 14, bw, d.theirs, light and L("bb_dark") or L("bb_light"), light and C.LOSE or C.WIN, "st")
end

function W.heat(x, y, w, h)
	local view = state.view
	W.card(x, y, w, h, L("bb_heat"), L("bb_heat_hint"))
	if not view or #view.ours == 0 or #view.theirs == 0 then return W.note(L("bb_heat_empty"), x, y, w) end
	local order = view.heat_order
	if not order then
		order = {}
		for i, a in ipairs(view.ours) do order[i] = a end
		table.sort(order, function(p, q) return (view.totals[p] or 0) > (view.totals[q] or 0) end)
		view.heat_order = order
	end
	local lx = x + 16
	local tw = 58
	local gx = lx + 40
	local col = (w - 32 - 40 - tw - 6) / 5
	for j, b in ipairs(view.theirs) do
		local unit = hero_unit(b)
		if unit then picture(hero_image(unit), gx + (j - 1) * col + (col - 28) / 2, y + 46, 28, 28, 6, 0, true) end
	end
	local ry0 = y + 84
	local row_h = math.min(36, (y + h - ry0 - 10) / math.max(1, #order))
	local me = state.draft.my_hero
	local ba = G.alpha
	for idx, a in ipairs(order) do
		local ry = ry0 + tween("hr" .. a, (idx - 1) * row_h, 10)
		local e = W.since(state.win.open_at, 0.1 + idx * 0.04, 0.24)
		G.alpha = ba * e
		local unit = hero_unit(a)
		if unit then
			picture(hero_image(unit), lx, ry + (row_h - 28) / 2, 28, 28, 6, 0, true)
			if a == me then frame_line(lx, ry + (row_h - 28) / 2, 28, 28, C.GOLD, 6, 2) end
		end
		for j, b in ipairs(view.theirs) do
			local v = view.cells[a] and view.cells[a][b] or 0
			local cx = gx + (j - 1) * col
			local mid = cx + col / 2
			rect(cx + 2, ry + 2, col - 4, row_h - 4, C.ROW, 6)
			local len = math.min(1, math.abs(v) / 4) * (col / 2 - 6) * e
			if v >= 0 then rect(mid, ry + row_h - 8, len, 3, C.WIN, 1) else rect(mid - len, ry + row_h - 8, len, 3, C.LOSE, 1) end
			text(fonts.w600, 13, string.format("%+.1f", v), mid, ry + row_h / 2 - 11, C.TEXT, "center")
		end
		local total = view.totals[a] or 0
		local tx = x + w - 16 - tw
		local tmid = tx + tw / 2
		local tlen = math.min(1, math.abs(total) / 8) * (tw / 2 - 2) * e
		if total >= 0 then rect(tmid, ry + row_h - 8, tlen, 3, C.WIN, 1) else rect(tmid - tlen, ry + row_h - 8, tlen, 3, C.LOSE, 1) end
		text(fonts.w700, 14, string.format("%+.1f", total), tmid, ry + row_h / 2 - 12, total >= 0 and C.WIN or C.LOSE, "center")
	end
	G.alpha = ba
end

function W.chips(b, x, y, room)
	if not b.chips then
		local list = {}
		local first = true
		for k = 1, 2 do
			local sid = k == 1 and b.strong or b.strong2
			local su = sid and hero_unit(sid)
			if su then
				list[#list + 1] = first and string.format(L("bb_pick_vs"), hero_title(su)) or hero_title(su)
				first = false
			end
		end
		b.chips = list
	end
	local cx = x
	for _, label in ipairs(b.chips) do
		local cw = measure(fonts.w500, 13, label) + 16
		if cx + cw > x + room then break end
		rect(cx, y, cw, 22, C.SEG, 6)
		text(fonts.w500, 13, label, cx + 8, y + 4, C.MUTED)
		cx = cx + cw + 6
	end
end

function W.picks(x, y, w, h)
	local view = state.view
	W.card(x, y, w, h, string.format(L("bb_pick_title"), L("bb_role_" .. my_position())))
	if not view or #view.best == 0 then
		for i = 0, 3 do W.skeleton(x + 14, y + 50 + i * 72, w - 28, 62, i) end
		text(fonts.w500, 13, L("bb_best_empty"), x + 16, y + 50 + 4 * 72 + 2, C.MUTED)
		return
	end
	local top = math.max(0.1, view.best[1].gain)
	local ba = G.alpha
	local ry = y + 50
	for i, b in ipairs(view.best) do
		local first = i == 1
		local chh = first and 82 or 70
		if ry + chh > y + h - 10 then break end
		local unit = hero_unit(b.id)
		if unit then
			local e = W.since(state.win.open_at, 0.12 + i * 0.05, 0.24)
			G.alpha = ba * e
			local cx, cy, cw, ch, hot = W.btn("best" .. i, x + 14, ry, w - 28, chh - 10)
			rect(cx, cy, cw, ch, first and C.ROW_HOT or mix(C.ROW, C.ROW_HOT, hot), 8)
			if first then W.glow(cx, cy, cw, ch, 8, 0.75 + 0.25 * math.sin(state.clock * 2.4)) end
			picture(hero_image(unit), cx + 10, cy + (ch - 42) / 2, 74, 42, 6)
			local rx, rcy = cx + cw - 32, cy + ch / 2
			local share = math.max(0.06, math.min(1, b.gain / top)) * e
			Render.Circle(P(rx, rcy), 20 * G.s, A(C.TRACK), 4 * G.s, 0, 1, false, 48)
			Render.Circle(P(rx, rcy), 20 * G.s, A(b.gain >= 0 and C.WIN or C.LOSE), 4 * G.s, -90, share, false, 48)
			text(fonts.w700, 12, string.format("%+.1f", b.gain), rx, rcy - 8, C.TEXT, "center")
			local room = w - 178
			text(fonts.w600, first and 16 or 15, fit(fonts.w600, first and 16 or 15, hero_title(unit), room), cx + 96, cy + (first and 12 or 9), C.TEXT)
			W.chips(b, cx + 96, cy + ch - 32, room)
			button("hero", cx, cy, cw, ch, b.id)
		end
		ry = ry + chh
	end
	G.alpha = ba
end

function W.foes(x, y, w, h)
	local view = state.view
	W.card(x, y, w, h, L("bb_foe_title"))
	local list = view and view.foes or K.NONE
	if #list == 0 then
		for i = 0, 3 do W.skeleton(x + 14, y + 50 + i * 72, w - 28, 62, i) end
		return
	end
	local ba = G.alpha
	local ry = y + 50
	for i, f in ipairs(list) do
		local n = math.min(#f.items, 3)
		local room = w - 128 - n * 44
		local lines = wrap(fonts.w500, 13, f.line, room, 2)
		local ch = math.max(62, 34 + #lines * 18)
		if ry + ch > y + h - 10 then break end
		G.alpha = ba * W.since(state.win.open_at, 0.12 + i * 0.05, 0.24)
		rect(x + 14, ry, w - 28, ch, C.ROW, 8)
		picture(hero_image(f.unit), x + 24, ry + (ch - 42) / 2, 74, 42, 6)
		text(fonts.w600, 15, fit(fonts.w600, 15, hero_title(f.unit), room), x + 110, ry + 8, C.TEXT)
		for k, l in ipairs(lines) do text(fonts.w500, 13, l, x + 110, ry + 30 + (k - 1) * 18, C.MUTED) end
		local px = x + w - 24
		for k = n, 1, -1 do
			px = px - 40
			W.icon(item_image(f.items[k]), px, ry + (ch - 29) / 2, 40, 29, 5, "fi" .. i .. k)
			frame_line(px, ry + (ch - 29) / 2, 40, 29, C.VS, 5)
			button("item", px, ry + (ch - 29) / 2, 40, 29, f.items[k])
			px = px - 4
		end
		ry = ry + ch + 8
	end
	G.alpha = ba
end

function W.draft(w, h)
	local d = state.draft
	local view = state.view
	local lx, lw, rx, rw = K.CX, K.COL_L, K.CX + K.COL_L + K.GAP, w - K.CX - K.COL_L - K.GAP - 16
	local top, bottom = K.TOP, h - 16
	W.block(0)
	W.chance(lx, top, lw, 254)
	W.block(1)
	W.heat(lx, top + 254 + K.GAP, lw, bottom - top - 254 - K.GAP)
	W.block(2)
	if d.my_hero and view then W.foes(rx, top, rw, bottom - top) else W.picks(rx, top, rw, bottom - top) end
	W.unblock()
end

function W.next(x, y, w, h)
	local view = state.view
	local win = state.win
	W.card(x, y, w, h, L("bb_next_title"))
	local step = view and view.next
	if not step then return W.note(L("bb_route_empty"), x, y, w) end
	local can = view.gold >= step.cost
	if can and win.afford_name ~= step.name then win.afford_name, win.afford_at = step.name, state.clock end
	if not can then win.afford_name = nil end
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 3)
	local ix, iy = x + 16, y + 50
	W.icon(item_image(step.name), ix, iy, 80, 58, 8, "next_icon")
	W.glow(ix, iy, 80, 58, 8, can and (0.6 + 0.4 * pulse) or 1)
	button("item", ix, iy, 80, 58, step.name)
	local tx, tw = ix + 96, w - 128
	text(fonts.w600, 16, fit(fonts.w600, 16, item_title(step.name), tw), tx, iy, C.TEXT)
	local why = step.reason or L("bb_why_popular")
	if step.tm and step.tm > 0 and step.share then why = string.format(L("bb_next_usual"), math.floor(step.tm / 60 + 0.5), math.floor(step.share * 100 + 0.5)) end
	for i, l in ipairs(wrap(fonts.w500, 14, why, tw, 2)) do text(fonts.w500, 14, l, tx, iy + 24 + (i - 1) * 20, C.MUTED) end
	local by = y + 126
	local share = tween("gold_bar", step.cost > 0 and math.min(1, view.gold / step.cost) or 0, 6)
	rect(x + 16, by, w - 32, 8, C.TRACK, 4)
	if share > 0.005 then grad(x + 16, by, (w - 32) * share, 8, C.GOLD_LO, C.GOLD_HI, C.GOLD_LO, C.GOLD_HI, 4) end
	if can then W.shine(x + 16, by, w - 32, 8, (state.clock - (win.afford_at or 0)) / 0.8, C.GSHINE_0, C.GSHINE_1) end
	text(fonts.w500, 14, string.format(L("bb_gold_of"), W.count("next_gold", math.min(view.gold, step.cost)), step.cost), x + 16, by + 16, C.MUTED)
	if step.minute then text(fonts.w500, 14, string.format(L("bb_minutes"), step.minute), x + w - 16, by + 16, C.MUTED, "right") end
	local parts = step.parts or K.NONE
	local ry = by + 44
	if #parts > 0 then
		local px = x + 16
		for i, part in ipairs(parts) do
			local label = part.have and "✓" or tostring(part.cost)
			local lw = measure(fonts.w600, 14, label) + 50
			if px + lw > x + w - 16 then break end
			local okp = not part.have and part.cost <= view.gold
			local bx, bby, bw, bh, hot = W.btn("part" .. i, px, ry, lw, 32)
			rect(bx, bby, bw, bh, mix(C.ROW, C.ROW_HOT, hot), 8)
			frame_line(bx, bby, bw, bh, okp and C.WIN or C.CARD_EDGE, 8)
			picture(item_image(part.name), bx + 4, bby + 4, 32, 24, 4, part.have and 1 or 0)
			text(fonts.w600, 14, label, bx + 42, bby + 7, okp and C.WIN or C.MUTED)
			button("item", px, ry, lw, 32, part.name)
			px = px + lw + 8
		end
		ry = ry + 42
	end
	local bw0 = math.floor((w - 40) * 0.58)
	local main_label = L("bb_buy_all")
	if not can then
		for _, part in ipairs(parts) do
			if not part.have and part.cost <= view.gold then
				main_label = fit(fonts.w600, 14, string.format(L("bb_buy_part"), item_title(part.name)), bw0 - 18)
				break
			end
		end
	end
	local bx, bby, bw, bh, hb = W.btn("buy", x + 16, ry, bw0, 38)
	if can then frame_line(bx - 3, bby - 3, bw + 6, bh + 6, alpha(C.ACCENT, 0.25 + 0.35 * pulse), 10, 2) end
	rect(bx, bby, bw, bh, mix(C.ACCENT, C.ACCENT_HOT, hb), 8)
	text(fonts.w600, 14, main_label, bx + bw / 2, bby + 10, C.WHITE, "center")
	button("buy", x + 16, ry, bw0, 38, step.name)
	local qx, qw = x + 16 + bw0 + 8, w - 40 - bw0
	local qx2, qy2, qw2, qh2, hq = W.btn("quick", qx, ry, qw, 38)
	rect(qx2, qy2, qw2, qh2, mix(C.ROW, C.ROW_HOT, hq), 8)
	frame_line(qx2, qy2, qw2, qh2, C.CARD_EDGE, 8)
	text(fonts.w600, 14, fit(fonts.w600, 14, L("bb_quick"), qw - 14), qx2 + qw2 / 2, qy2 + 10, C.TEXT, "center")
	button("quick", qx, ry, qw, 38, step.name)
end

function W.vs(x, y, w, h)
	local view = state.view
	W.card(x, y, w, h, L("bb_vs_title"))
	local list = view and view.vs_rows or K.NONE
	if #list == 0 then return W.note(L("bb_vs_empty"), x, y, w) end
	local ba = G.alpha
	local ry = y + 48
	for i, t in ipairs(list) do
		local first = t.options[1]
		local px = x + 26
		local np = math.min(3, #t.units)
		local tx = px + (np > 0 and np * 25 + 4 or 0)
		local cost, gold = item_cost(first), view.gold or 0
		local now = cost <= gold
		local label = now and L("bb_vs_now") or string.format(L("bb_vs_eta"), math.max(1, math.floor((cost - gold) / math.max(100, view.gpm or 400) + 0.5)))
		local pw = measure(fonts.w600, 13, label) + 18
		local title = wrap(fonts.w600, 14, t.text, x + w - 34 - pw - tx, 2)
		if t.how ~= "" and not t.how_line then t.how_line = item_title(first) .. ": " .. t.how end
		local how = t.how_line and wrap(fonts.w500, 13, t.how_line, w - 52, 2) or K.NONE
		local th = #title * 19
		local ch = 12 + th + 8 + 30 + (#how > 0 and (8 + #how * 18) or 0) + 12
		if ry + ch > y + h - 8 then break end
		G.alpha = ba * W.since(state.win.open_at, 0.12 + i * 0.05, 0.24)
		rect(x + 14, ry, w - 28, ch, C.ROW, 8)
		for k, unit in ipairs(t.units) do
			if k > 3 then break end
			picture(hero_image(unit), px + (k - 1) * 25, ry + 12, 22, 22, 6, 0, true)
		end
		for k, l in ipairs(title) do text(fonts.w600, 14, l, tx, ry + 12 + (k - 1) * 19, t.live and C.GOLD or C.TEXT) end
		local sc = now and W.pop(W.first_seen("can" .. t.key, true)) or 1
		if not now then W.seen["can" .. t.key] = nil end
		local pcx = x + w - 24 - pw / 2
		rect(pcx - pw * sc / 2, ry + 11 + 11 * (1 - sc), pw * sc, 22 * sc, now and C.PILL_WIN or C.SEG, 6)
		if sc > 0.85 then text(fonts.w600, 13, label, pcx, ry + 15, now and C.WIN or C.MUTED, "center") end
		local iy = ry + 12 + th + 8
		local ix = x + 26
		for k, name in ipairs(t.options) do
			if k > 7 or ix + 42 > x + w - 26 then break end
			W.icon(item_image(name), ix, iy, 42, 30, 6, t.key .. k)
			frame_line(ix, iy, 42, 30, k == 1 and C.VS or C.EDGE, 6, k == 1 and 1.3 or 1)
			button("item", ix, iy, 42, 30, name)
			ix = ix + 48
		end
		for k, l in ipairs(how) do text(fonts.w500, 13, l, x + 26, iy + 38 + (k - 1) * 18, C.MUTED) end
		ry = ry + ch + 8
	end
	G.alpha = ba
end

function W.shelf(label, list, x, y, w, key, row0)
	local view = state.view
	local ba = G.alpha
	text(fonts.w500, 14, label, x, y, C.MUTED)
	local iw, ih, gap = 46, 34, 6
	local per = math.max(1, math.floor((w + gap) / (iw + gap)))
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 3)
	for i, step in ipairs(list) do
		local col, row = (i - 1) % per, math.floor((i - 1) / per)
		local sx, sy = x + col * (iw + gap), y + 24 + row * (ih + 24)
		local e = W.since(state.win.open_at, 0.12 + (row0 + row) * 0.05 + col * 0.02, 0.22)
		G.alpha = ba * e
		local now = view and view.next == step
		local hot = W.icon(item_image(step.name), sx, sy + (1 - e) * 6, iw, ih, 6, key .. i, step.done and 1 or 0, step.done and C.DONE_TINT or nil)
		if now then
			W.glow(sx, sy, iw, ih, 6, 0.6 + 0.4 * pulse)
		else
			frame_line(sx, sy, iw, ih, hot > 0.01 and alpha(C.WHITE, 0.15 + hot * 0.3) or C.EDGE, 6)
		end
		if step.count and step.count > 1 then text(fonts.w700, 13, tostring(step.count), sx + iw - 4, sy + ih - 17, C.WHITE, "right") end
		if step.done then
			text(fonts.w700, 13, "✓", sx + iw / 2, sy + ih + 4, C.WIN, "center")
		elseif step.tm and step.tm > 0 then
			text(fonts.w600, 13, math.floor(step.tm / 60 + 0.5) .. "'", sx + iw / 2, sy + ih + 4, now and C.GOLD or C.MUTED, "center")
		end
		button("item", sx, sy, iw, ih, step.name)
	end
	G.alpha = ba
	local rows = math.max(1, math.ceil(#list / per))
	return y + 24 + rows * (ih + 24) + 8, row0 + rows
end

function W.shelves(x, y, w, h)
	local view = state.view
	W.card(x, y, w, h, L("bb_shelf_title"), L("bb_shelf_hint"))
	if not view or not view.route then return W.note(L("bb_route_empty"), x, y, w) end
	local sh = view.shelves
	if not sh then
		sh = { start = {}, early = {}, core = {}, more = {} }
		local index, used = {}, {}
		for _, name in ipairs(view.start or {}) do
			local e = index[name]
			if e then
				e.count = e.count + 1
			else
				e = { name = name, count = 1 }
				index[name] = e
				sh.start[#sh.start + 1] = e
			end
		end
		for _, step in ipairs(view.route) do
			used[step.name] = true
			if not step.sit then
				local list = step.early and sh.early or sh.core
				list[#list + 1] = step
			end
		end
		for _, c in ipairs(view.role and view.role.pop or {}) do
			if not used[c.name] and #sh.more < 7 then sh.more[#sh.more + 1] = { name = c.name } end
		end
		view.shelves = sh
	end
	local ry, iw, r0 = y + 50, w - 32, 0
	local per = math.max(1, math.floor((iw + 6) / 52))
	if #sh.start > 0 then ry, r0 = W.shelf(L("bb_shelf_start"), sh.start, x + 16, ry, iw, "sh_s", r0) end
	if #sh.early > 0 then ry, r0 = W.shelf(L("bb_shelf_lane"), sh.early, x + 16, ry, iw, "sh_e", r0) end
	ry, r0 = W.shelf(L("bb_shelf_core"), sh.core, x + 16, ry, iw, "sh_c", r0)
	if #sh.more > 0 and ry + 24 + math.ceil(#sh.more / per) * 58 <= y + h - 8 then W.shelf(L("bb_shelf_more"), sh.more, x + 16, ry, iw, "sh_m", r0) end
end

function W.build(w, h)
	local view = state.view
	local step = view and view.next
	local nh = (step and step.parts and #step.parts > 0) and 270 or 228
	local lx, lw, rx, rw = K.CX, K.COL_L, K.CX + K.COL_L + K.GAP, w - K.CX - K.COL_L - K.GAP - 16
	local top, bottom = K.TOP, h - 16
	W.block(0)
	W.next(lx, top, lw, nh)
	W.block(1)
	W.vs(lx, top + nh + K.GAP, lw, bottom - top - nh - K.GAP)
	W.block(2)
	W.shelves(rx, top, rw, bottom - top)
	W.unblock()
end

function W.ring(cx, cy, r, th, mag, phys, grow)
	local start = -90
	if mag > 0.001 then Render.Circle(P(cx, cy), r * G.s, A(C.MAGIC), th * G.s, start, mag * grow, false, 64) end
	start = start + mag * 360 * grow
	if phys > 0.001 then Render.Circle(P(cx, cy), r * G.s, A(C.PHYS), th * G.s, start, phys * grow, false, 64) end
	start = start + phys * 360 * grow
	local pure = math.max(0, 1 - mag - phys)
	if pure > 0.001 then Render.Circle(P(cx, cy), r * G.s, A(C.PURE), th * G.s, start, pure * grow, false, 64) end
end

function W.fight(w, h)
	local view = state.view
	local dmg = state.dmg
	local total = dmg.phys + dmg.mag + dmg.pure
	local lx, lw, rx, rw = K.CX, K.COL_L, K.CX + K.COL_L + K.GAP, w - K.CX - K.COL_L - K.GAP - 16
	local top, bottom = K.TOP, h - 16
	local kh = 350
	W.block(0)
	W.card(lx, top, lw, kh, L("bb_fight_title"), dmg.deaths > 0 and string.format(L("bb_kill_deaths"), dmg.deaths) or nil)
	if total <= 0 then
		W.note(L("bb_fight_empty"), lx, top, lw)
	else
		local cx, cy = lx + 86, top + 122
		local grow = tween("fight_ring", 1, 3.6)
		local mag = tween("f_mag", dmg.mag / total, 6)
		local phys = tween("f_phys", dmg.phys / total, 6)
		Render.Circle(P(cx, cy), 54 * G.s, A(C.TRACK), 12 * G.s, 0, 1, false, 64)
		W.ring(cx, cy, 54, 12, mag, phys, grow)
		text(fonts.w700, 18, tostring(W.count("f_total", math.floor(total * grow))), cx, cy - 16, C.TEXT, "center")
		text(fonts.w500, 13, L("bb_fight_hint"), cx, cy + 6, C.MUTED, "center")
		local gx, gr = lx + 172, lx + lw - 16
		for i, r in ipairs(K.DMG_ROWS) do
			local ly = top + 74 + (i - 1) * 30
			local part = i == 1 and mag or (i == 2 and phys or math.max(0, 1 - mag - phys))
			rect(gx, ly + 4, 10, 10, C[r[1]], 3)
			text(fonts.w500, 15, L(r[2]), gx + 18, ly, C.TEXT)
			text(fonts.w600, 15, math.floor(part * 100 + 0.5) .. "%", gr, ly, C.TEXT, "right")
		end
		local ry = top + 194
		if dmg.deaths > 0 then
			text(fonts.w500, 14, fit(fonts.w500, 14, string.format(L("bb_kill_ctrl"), dmg.ctrl / dmg.deaths), lw - 32), lx + 16, ry, C.MUTED)
			ry = ry + 30
		end
		for i, s in ipairs(view and view.killers or K.NONE) do
			if ry + 34 > top + kh - 10 then break end
			if s.unit:match("^npc_dota_hero_") then picture(hero_image(s.unit), lx + 16, ry, 28, 28, 6, 0, true) end
			text(fonts.w500, 15, fit(fonts.w500, 15, hero_title(s.unit), lw - 170), lx + 54, ry, C.TEXT)
			local share = tween("src_" .. s.unit, s.share, 6) * W.since(state.win.open_at, 0.15 + i * 0.06, 0.45)
			rect(lx + 54, ry + 23, lw - 130, 5, C.TRACK, 2)
			rect(lx + 54, ry + 23, (lw - 130) * share, 5, C.GOLD, 2)
			text(fonts.w600, 15, math.floor(s.share * 100 + 0.5) .. "%", lx + lw - 16, ry + 6, C.TEXT, "right")
			ry = ry + 40
		end
	end
	local ty = top + kh + K.GAP
	W.block(1)
	W.card(lx, ty, lw, bottom - ty, L("bb_todo_title"))
	local todo = view and view.todo or K.NONE
	if #todo == 0 then
		W.note(L("bb_todo_empty"), lx, ty, lw)
	else
		local ba = G.alpha
		local ly = ty + 50
		for i, line in ipairs(todo) do
			local lines = wrap(fonts.w500, 15, line, lw - 52, 2)
			if ly + #lines * 21 > bottom - 10 then break end
			local tkey = line:match("^[^:]*")
			if not W.todo_at[tkey] then
				W.todo_n = W.todo_n + 1
				if W.todo_n > 40 then W.todo_at, W.todo_n = {}, 1 end
				W.todo_at[tkey] = state.clock
			end
			local flash = 1 - math.min(1, (state.clock - W.todo_at[tkey]) / 0.7)
			G.alpha = ba * W.since(state.win.open_at, 0.1 + i * 0.05, 0.24)
			if flash > 0 then dot(lx + 21, ly + 10, 3 + 5 * flash, alpha(C.ACCENT, 0.35 * flash)) end
			dot(lx + 21, ly + 10, 3, C.ACCENT)
			for _, l in ipairs(lines) do
				text(fonts.w500, 15, l, lx + 34, ly, C.TEXT)
				ly = ly + 21
			end
			ly = ly + 8
		end
		G.alpha = ba
	end
	W.block(2)
	W.card(rx, top, rw, bottom - top, L("bb_fight_foes"))
	local live = view and view.live or K.NONE
	if #live == 0 then
		W.note(L("bb_enemies_empty"), rx, top, rw)
		return W.unblock()
	end
	local ba = G.alpha
	local ready = L("bb_foe_ult_ready")
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 4)
	local ey = top + 50
	for _, f in ipairs(live) do
		if ey + 84 > bottom - 8 then break end
		local fresh = not W.foe_at[f.unit]
		if fresh then W.foe_at[f.unit] = state.clock end
		G.alpha = ba * W.since(W.foe_at[f.unit], 0, 0.3)
		rect(rx + 12, ey - 6, rw - 24, 84, f.go and C.GO_ROW or C.ROW, 8)
		if f.go then frame_line(rx + 12, ey - 6, rw - 24, 84, C.GO_EDGE, 8) end
		picture(hero_image(f.unit), rx + 22, ey + 2, 44, 44, 6, 0, true, f.alive and nil or C.DEAD_TINT)
		local name = hero_title(f.unit)
		if f.fog then name = name .. " · " .. string.format(L("bb_foe_fog"), f.fog) end
		local pw = 0
		if f.go then
			pw = measure(fonts.w600, 13, L("bb_foe_go")) + 18
			rect(rx + rw - 22 - pw, ey, pw, 22, C.PILL_WIN, 6)
			text(fonts.w600, 13, L("bb_foe_go"), rx + rw - 22 - pw / 2, ey + 4, C.WIN, "center")
		end
		text(fonts.w600, 15, fit(fonts.w600, 15, name, rw - 112 - pw), rx + 78, ey + 1, f.fog and C.MUTED or C.TEXT)
		local cx = rx + 78
		if f.hp then
			local hp = tween("hp_" .. f.unit, f.hp, 8)
			rect(cx, ey + 31, 58, 6, C.TRACK, 3)
			rect(cx, ey + 31, 58 * hp, 6, hp < 0.35 and C.WIN or C.LOSE, 3)
			cx = cx + 66
		end
		if f.ult then
			local lw2 = measure(fonts.w600, 13, f.ult) + 16
			local warn = f.ult == ready
			rect(cx, ey + 24, lw2, 22, f.ult_ok and C.PILL_WIN or (warn and alpha(C.LOSE, 0.12 + 0.18 * pulse) or C.PILL_LOSE), 6)
			text(fonts.w600, 13, f.ult, cx + lw2 / 2, ey + 28, f.ult_ok and C.WIN or C.LOSE, "center")
			cx = cx + lw2 + 6
		end
		if f.bkb then
			local lw2 = measure(fonts.w600, 13, f.bkb) + 16
			if cx + lw2 <= rx + rw - 22 then
				rect(cx, ey + 24, lw2, 22, f.bkb_ok and C.PILL_WIN or C.PILL_LOSE, 6)
				text(fonts.w600, 13, f.bkb, cx + lw2 / 2, ey + 28, f.bkb_ok and C.WIN or C.LOSE, "center")
			end
		end
		local seen = W.item_at[f.unit]
		if not seen then
			seen = {}
			W.item_at[f.unit] = seen
		end
		local ix = rx + 78
		for _, item in ipairs(f.items or K.NONE) do
			if ix + 30 > rx + rw - 22 then break end
			if not seen[item] then seen[item] = fresh and -10 or state.clock end
			picture(item_image(item), ix, ey + 54, 30, 22, 4)
			local glow = 1 - math.min(1, (state.clock - seen[item]) / 2)
			if glow > 0 then frame_line(ix - 1, ey + 53, 32, 24, alpha(C.GOLD, glow), 5, 1.5) end
			ix = ix + 34
		end
		ey = ey + 92
	end
	G.alpha = ba
	W.unblock()
end

function W.label(s, value)
	if s.flag then return L(value == 1 and "bb_on" or "bb_off") end
	if s.values then return s.values[value + 1] .. "%" end
	return L(s.label .. value)
end

function W.toggle(key, x, y, on)
	local t = tween("toggle_" .. key, on and 1 or 0, 20)
	rect(x, y, 40, 22, mix(C.TOGGLE_TRACK, C.TOGGLE_ON_TRACK, t), 11)
	dot(x + 11 + 18 * t, y + 11, 8, mix(C.TOGGLE_OFF, C.ACCENT, t))
end

function W.steps(s, x, y, value)
	local cw = 48
	rect(x, y, cw * s.count, 32, C.ROW, 8)
	frame_line(x, y, cw * s.count, 32, C.CARD_EDGE, 8)
	local sx = tween("steps_x_" .. s.key, x + value * cw, 18)
	rect(sx + 2, y + 2, cw - 4, 28, C.ACCENT, 6)
	for v = 0, s.count - 1 do
		local bx = x + v * cw
		local hot = hover_t("step_" .. s.key .. v, bx, y, cw, 32)
		if hot > 0.01 and v ~= value then rect(bx + 2, y + 2, cw - 4, 28, alpha(C.ROW_HOT, hot), 6) end
		text(fonts.w600, 14, tostring(s.values[v + 1]), bx + cw / 2, y + 7, v == value and C.WHITE or mix(C.MUTED, C.TEXT, hot), "center")
		button("step", bx, y, cw, 32, v)
	end
end

function W.dropdown(drop, h)
	local s = drop.def
	local t = tween("dropdown", 1, 16)
	local row = 32
	local full = s.count * row + 8
	local y = drop.y
	local up = y + full > h - 16
	if up then y = drop.y - 46 - full end
	local k = 0.02 * (1 - t)
	local dx, dy, dw, dh = drop.x + drop.w * k / 2, y + full * k / 2, drop.w * (1 - k), full * (1 - k)
	local ba = G.alpha
	G.alpha = ba * t
	W.soft(dx, dy, dw, dh, 10, 20)
	rect(dx, dy, dw, dh, C.TIP, 10)
	rect(dx + 10, dy, dw - 20, 1, C.TOP_EDGE)
	frame_line(dx, dy, dw, dh, C.CARD_EDGE, 10)
	local current = setting(s.key)
	for v = 0, s.count - 1 do
		local oy = y + 4 + v * row
		local hot = hover_t("option" .. v, drop.x + 4, oy, drop.w - 8, row - 2)
		if hot > 0 then rect(drop.x + 4, oy, drop.w - 8, row - 2, alpha(C.ROW_HOT, hot), 6) end
		text(fonts.w500, 14, fit(fonts.w500, 14, W.label(s, v), drop.w - 44), drop.x + 14, oy + 7, v == current and C.ACCENT or C.TEXT)
		if v == current then text(fonts.w700, 14, "✓", drop.x + drop.w - 14, oy + 7, C.ACCENT, "right") end
		if t > 0.6 then button("option", drop.x + 4, oy, drop.w - 8, row - 2, v) end
	end
	G.alpha = ba
end

function W.updates(x, y, cw, half, x1, x2)
	W.card(x, y, cw, 52 + 54 + 6, L("bb_upd_title"))
	local ry = y + 52
	text(fonts.w600, 15, UPD.title, x1, ry + 4, C.TEXT)
	local line, tone = UPD.line()
	local act = UPD.action()
	local bw = 150
	text(fonts.w500, 13, fit(fonts.w500, 13, line, act and half - bw - 12 or half), x1, ry + 26, tone)
	if act then
		local bx, by, bww, bh, hot = W.btn("upd_" .. act, x1 + half - bw, ry + 7, bw, 34)
		local main = act ~= "check"
		rect(bx, by, bww, bh, main and mix(C.ACCENT, C.ACCENT_HOT, hot) or mix(C.ROW, C.ROW_HOT, hot), 8)
		if not main then frame_line(bx, by, bww, bh, C.CARD_EDGE, 8) end
		text(fonts.w600, 14, L("bb_upd_" .. act), bx + bww / 2, by + 8, main and C.WHITE or C.TEXT, "center")
		button("upd", x1 + half - bw, ry + 7, bw, 34, act)
	end
	local hot = hover_t("set_update", x2 - 8, ry, half + 16, 48)
	if hot > 0.01 then rect(x2 - 8, ry, half + 16, 48, alpha(C.ROW_HOT, hot), 8) end
	text(fonts.w500, 15, fit(fonts.w500, 15, L("bb_set_update"), half - 60), x2, ry + 14, C.TEXT)
	W.toggle("update", x2 + half - 40, ry + 13, setting("update") == 1)
	button("toggle", x2 - 8, ry, half + 16, 48, "update")
end

function W.settings(w, h)
	local win = state.win
	local x, cw = K.CX, w - K.CX - 16
	local top = K.TOP
	local half = (cw - 48) / 2
	local x1, x2, y1, y2 = x + 16, x + 32 + half, top + 52, top + 52
	W.block(0)
	W.card(x, top, cw, 52 + 3 * 54 + 10, L("bb_tab_settings"))
	local drop
	for _, s in ipairs(K.SETTINGS) do
		if not s.own then
			local rx, ry = x1, y1
			if s.flag then rx, ry = x2, y2 end
			local hot = hover_t("set_" .. s.key, rx - 8, ry, half + 16, 48)
			if hot > 0.01 and not s.values then rect(rx - 8, ry, half + 16, 48, alpha(C.ROW_HOT, hot), 8) end
			local value = setting(s.key)
			if s.flag then
				text(fonts.w500, 15, fit(fonts.w500, 15, L(s.title), half - 60), rx, ry + 14, C.TEXT)
				W.toggle(s.key, rx + half - 40, ry + 13, value == 1)
				button("toggle", rx - 8, ry, half + 16, 48, s.key)
			elseif s.values then
				local sx = rx + half - 48 * s.count
				text(fonts.w500, 15, fit(fonts.w500, 15, L(s.title), sx - rx - 12), rx, ry + 14, C.TEXT)
				W.steps(s, sx, ry + 8, value)
			else
				local open = win.dropdown == s.key
				local bw = 190
				local bx = rx + half - bw
				text(fonts.w500, 15, fit(fonts.w500, 15, L(s.title), bx - rx - 12), rx, ry + 14, C.TEXT)
				local ot = tween("open_" .. s.key, open and 1 or 0, 18)
				rect(bx, ry + 7, bw, 34, mix(C.ROW, C.ROW_HOT, math.max(ot, hot * 0.5)), 8)
				frame_line(bx, ry + 7, bw, 34, mix(C.CARD_EDGE, C.ACCENT, ot), 8)
				text(fonts.w500, 14, fit(fonts.w500, 14, W.label(s, value), bw - 40), bx + 12, ry + 15, C.TEXT)
				chevron(bx + bw - 16, ry + 24, ot, mix(C.MUTED, C.ACCENT, ot))
				button("dropdown", rx - 8, ry, half + 16, 48, s.key)
				if open then
					drop = W.drop
					drop.def, drop.x, drop.y, drop.w = s, bx, ry + 44, bw
				end
			end
			if s.flag then y2 = ry + 54 else y1 = ry + 54 end
		end
	end
	text(fonts.w500, 13, L("bb_set_key_hint"), x2, y2 + 10, C.MUTED)
	W.block(1)
	W.updates(x, top + 52 + 3 * 54 + 10 + K.GAP, cw, half, x1, x2)
	W.block(0)
	if drop then W.dropdown(drop, h) end
	W.unblock()
end

function W.tab(name, w, h)
	if name == "draft" then
		W.draft(w, h)
	elseif name == "build" then
		W.build(w, h)
	elseif name == "fight" then
		W.fight(w, h)
	else
		W.settings(w, h)
	end
end

function W.scale()
	local screen = Render.ScreenSize()
	return math.max(0.5, screen.y / K.BASE_H) * (90 + setting("scale") * 10) / 100, screen
end

local function draw_window()
	local win = state.win
	local list = win.buttons
	for i = #list, 1, -1 do list[i] = nil end
	local open = tween("win", win.visible and 1 or 0, 14)
	if open < 0.01 then
		win.was_open = false
		return
	end
	if not win.was_open then
		win.was_open = true
		win.open_at = state.clock
		win.drawn_tab, win.prev_tab = win.tab, nil
		state.anim.fight_ring = 0
	end
	if win.drawn_tab ~= win.tab then
		win.prev_tab, win.drawn_tab = win.drawn_tab, win.tab
		win.tab_at, win.open_at = state.clock, state.clock + 0.06
		if win.tab == "fight" then state.anim.fight_ring = 0 end
	end
	local s, screen = W.scale()
	if s ~= win.scale then
		win.scale = s
		state.sizes, state.fits, state.wraps = {}, {}, {}
	end
	local w, h = K.WIN_W, K.WIN_H
	if not win.x then
		win.x = Config.ReadInt(K.CONFIG, "win_x", math.floor((screen.x - w * s) / 2))
		win.y = Config.ReadInt(K.CONFIG, "win_y", math.floor((screen.y - h * s) / 2))
	end
	if win.drag then
		local cx, cy = Input.GetCursorPos()
		win.x, win.y = cx - win.drag.dx, cy - win.drag.dy
	end
	win.x = math.max(0, math.min(screen.x - w * s, win.x))
	win.y = math.max(0, math.min(screen.y - h * s, win.y))
	local base_y = win.y + (1 - open) * 8 * s
	G.ox, G.oy, G.s, G.alpha = win.x, base_y, s, open
	G.buttons = list
	W.shell(w, h)
	W.rail(h)
	W.header(w)
	local out = win.prev_tab and (state.clock - win.tab_at) / 0.14 or 1
	if out < 1 then
		local dead = W.dead
		for i = #dead, 1, -1 do dead[i] = nil end
		G.buttons = dead
		W.base_a, W.base_y, W.flat = open * (1 - W.ease(out)), base_y, true
		W.tab(win.prev_tab, w, h)
		W.flat = false
		G.buttons = list
	else
		win.prev_tab = nil
	end
	W.base_a, W.base_y = open, base_y
	W.tab(win.tab, w, h)
	G.alpha, G.oy = 1, base_y
end

local PK = { cards = {}, buttons = {}, stack = {}, map = nil, fresh = nil, next_scan = 0, next_pos = 0, hl = { {}, {}, {} }, leader = nil, flash_at = -10, h = 300, x = nil, y = nil, drag = nil }

function PK.hit()
	return PK.x1 ~= nil and cursor_in(PK.x1, PK.y1, PK.x2, PK.y2)
end

function PK.click(key)
	if key ~= Enum.ButtonCode.KEY_MOUSE1 then return end
	for i = #PK.buttons, 1, -1 do
		local b = PK.buttons[i]
		if cursor_in(b.x1, b.y1, b.x2, b.y2) then
			if b.kind == "open" then
				state.win.visible, state.win.closed_by_user, state.win.tab = true, false, "draft"
				state.next_model = 0
			elseif b.kind == "drag" then
				local cx, cy = Input.GetCursorPos()
				PK.drag = { dx = cx - PK.x, dy = cy - PK.y }
			elseif b.kind == "hero" then
				state.preview_hero = b.value
				state.next_model, state.next_data = 0, 0
			end
			return
		end
	end
end

function PK.scan()
	if state.clock >= PK.next_scan and #PK.stack == 0 then
		PK.next_scan = state.clock + K.GRID_SCAN
		local ok, root = pcall(Panorama.GetPanelByName, "HeroGrid", false)
		if ok and root then
			PK.stack[1] = root
			PK.fresh = {}
		end
	end
	local n = 0
	while #PK.stack > 0 and n < K.GRID_STEP do
		local p = PK.stack[#PK.stack]
		PK.stack[#PK.stack] = nil
		n = n + 1
		local okc, card = pcall(p.HasClass, p, "HeroCard")
		if okc and card then
			local oki, img = pcall(p.FindChildTraverse, p, "HeroImage")
			local oks, src = false, nil
			if oki and img then oks, src = pcall(img.GetImageSrc, img) end
			local name = oks and type(src) == "string" and src:match("npc_dota_hero_([%w_]+)") or nil
			if name and PK.fresh then PK.fresh[name] = p end
		elseif okc then
			local okn, count = pcall(p.GetChildCount, p)
			if okn and count then
				for i = count - 1, 0, -1 do
					local okg, child = pcall(p.GetChild, p, i)
					if okg and child then PK.stack[#PK.stack + 1] = child end
				end
			end
		end
	end
	if #PK.stack == 0 and PK.fresh then PK.map, PK.fresh = PK.fresh, nil end
end

function PK.grid(view)
	if not PK.map or not view or #view.best == 0 then return end
	if state.clock >= PK.next_pos then
		PK.next_pos = state.clock + K.GRID_HL
		for i = 1, 3 do
			local slot = PK.hl[i]
			slot.on = false
			local b = view.best[i]
			local unit = b and hero_unit(b.id)
			local card = unit and PK.map[unit:sub(15)]
			if card then
				local okv, vis = pcall(card.IsVisible, card)
				local okp, pos = pcall(card.GetPositionWithinWindow, card)
				local okw, cw = pcall(card.GetLayoutWidth, card)
				local okh, ch = pcall(card.GetLayoutHeight, card)
				if okv and vis and okp and pos and okw and okh and cw > 4 and ch > 4 then
					slot.on, slot.x, slot.y, slot.w, slot.h, slot.gain = true, pos.x, pos.y, cw, ch, b.gain
				end
			end
		end
	end
	G.ox, G.oy, G.s = 0, 0, 1
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 3)
	for i = 1, 3 do
		local slot = PK.hl[i]
		if slot.on then
			local c = i == 1 and C.GOLD or C.WHITE
			frame_line(slot.x - 2, slot.y - 2, slot.w + 4, slot.h + 4, alpha(c, 0.55 + 0.45 * pulse), 6, i == 1 and 2.5 or 1.5)
			local label = string.format("%+.1f%%", slot.gain)
			local lw = measure(fonts.w700, 13, label) + 12
			rect(slot.x + slot.w / 2 - lw / 2, slot.y + slot.h - 10, lw, 20, C.BADGE, 6)
			text(fonts.w700, 13, label, slot.x + slot.w / 2, slot.y + slot.h - 8, slot.gain >= 0 and C.WIN or C.LOSE, "center")
		end
	end
end

function PK.card(c, b, x, y, w, leader)
	local unit = hero_unit(b.id)
	if not unit then return end
	local ch = leader and 70 or 56
	local sc = c.sc
	local cw2, ch2 = w * sc, ch * sc
	local cx, cy = x + (w - cw2) / 2, y + (ch - ch2) / 2
	local hot = hover_t("pkc" .. b.id, cx, cy, cw2, ch2)
	cy = cy - hot * 1.5
	rect(cx, cy, cw2, ch2, leader and C.ROW_HOT or mix(C.ROW, C.ROW_HOT, hot), 8)
	if leader then
		local flash = 1 - math.min(1, (state.clock - PK.flash_at) / 0.5)
		W.glow(cx, cy, cw2, ch2, 8, 0.75 + 0.25 * math.sin(state.clock * 2.4))
		if flash > 0 then rect(cx, cy, cw2, ch2, alpha(C.GOLD, 0.3 * flash), 8) end
	end
	if sc < 0.9 then return end
	local ph = leader and 40 or 32
	picture(hero_image(unit), cx + 8, cy + (ch2 - ph) / 2, ph * 1.78, ph, 6)
	local tx = cx + 16 + ph * 1.78
	local left = w - 28 - ph * 1.78
	c.g = c.g + (b.gain - c.g) * (1 - math.exp(-8 * state.dt))
	if math.abs(b.gain - c.g) < 0.01 then c.g = b.gain end
	local gain = string.format("%+.1f%%", c.g)
	local gsize = leader and 16 or 14
	text(fonts.w700, gsize, gain, cx + cw2 - 12, cy + (leader and 10 or 8), b.gain >= 0 and C.WIN or C.LOSE, "right")
	local room = left - measure(fonts.w700, gsize, "+00.0%") - 8
	if leader then
		local tw = measure(fonts.w700, 11, L("bb_top")) + 12
		rect(tx, cy + 8, tw, 17, C.GOLD, 5)
		text(fonts.w700, 11, L("bb_top"), tx + tw / 2, cy + 10, C.GOLD_TEXT, "center")
		text(fonts.w600, 15, fit(fonts.w600, 15, hero_title(unit), room - tw - 6), tx + tw + 6, cy + 8, C.TEXT)
	else
		text(fonts.w600, 14, fit(fonts.w600, 14, hero_title(unit), room), tx, cy + 7, C.TEXT)
	end
	if b.chips == nil then W.chips(b, -10000, -10000, 0) end
	local reason = b.chips[1]
	if reason then text(fonts.w500, 13, fit(fonts.w500, 13, reason, left), tx, cy + ch2 - 22, C.MUTED) end
	button("hero", cx, cy, cw2, ch2, b.id)
end

function PK.draw()
	local d = state.draft
	local view = state.view
	local list = PK.buttons
	for i = #list, 1, -1 do list[i] = nil end
	local want = d.phase and setting("auto") == 1 and not state.win.visible
	local vis = tween("pick_vis", want and 1 or 0, 12)
	if vis < 0.01 then
		PK.x1 = nil
		return
	end
	if d.phase then PK.scan() end
	local screen = Render.ScreenSize()
	local s = math.max(0.5, screen.y / K.BASE_H) * (90 + setting("scale") * 10) / 100
	G.alpha = vis
	PK.grid(view)
	local w = K.PICK_W
	local h = tween("pick_h", PK.h, 12)
	if not PK.x then
		PK.x = Config.ReadInt(K.CONFIG, "pk_x", math.floor(screen.x - (w + 16) * s))
		PK.y = Config.ReadInt(K.CONFIG, "pk_y", math.floor(92 * s))
	end
	if PK.drag then
		local cx, cy = Input.GetCursorPos()
		PK.x, PK.y = cx - PK.drag.dx, cy - PK.drag.dy
	end
	PK.x = math.max(0, math.min(screen.x - w * s, PK.x))
	PK.y = math.max(0, math.min(screen.y - 48 * s, PK.y))
	local ox, oy = PK.x + (1 - vis) * 18 * s, PK.y
	G.ox, G.oy, G.s, G.alpha = ox, oy, s, vis
	G.buttons = list
	PK.x1, PK.y1, PK.x2, PK.y2 = ox, oy, ox + w * s, oy + h * s
	W.soft(0, 0, w, h, 12, 30)
	rect(0, 0, w, h, C.BG, 12)
	rect(12, 0, w - 24, 1, C.TOP_EDGE)
	frame_line(0, 0, w, h, C.EDGE, 12)
	W.glyph(K.LOGO, 17, 22, 24, C.ACCENT)
	text(fonts.w600, 16, L("bb_tab_draft"), 40, 14, C.TEXT)
	button("drag", 0, 0, w - 50, 46)
	local bx, by, bw, bh, hot = W.btn("pk_open", w - 44, 9, 30, 30)
	rect(bx, by, bw, bh, mix(C.ROW, C.ROW_HOT, hot), 8)
	W.glyph(K.ICON_OPEN, 14, bx + bw / 2, by + bh / 2, mix(C.MUTED, C.TEXT, hot))
	button("open", w - 44, 9, 30, 30)
	local light = d.my_team ~= 3
	local chance = view and view.chance
	local y = 52
	text(fonts.w500, 13, L("bb_chance_title"), 16, y, C.MUTED)
	if chance then
		if state.anim.pk_chance == nil then state.anim.pk_chance = 50 end
		local shown = tween("pk_chance", chance, 5)
		local rad = light and shown or (100 - shown)
		text(fonts.w700, 18, math.floor(shown + 0.5) .. "%", w - 16, y - 3, light and C.WIN or C.LOSE, "right")
		local split = (w - 32) * rad / 100
		rect(16, y + 24, split, 6, C.WIN, 3)
		rect(16 + split, y + 24, w - 32 - split, 6, C.LOSE, 3)
		rect(16 + (w - 32) / 2, y + 21, 1, 12, C.MARK)
	else
		rect(16, y + 24, w - 32, 6, C.TRACK, 3)
		W.shine(16, y + 24, w - 32, 6, ((state.clock * 0.6) % 1.4) / 1.4, C.SHINE_0, C.SHINE_1)
	end
	y = y + 42
	local sw = (w - 32 - 4 * 5) / 5
	local sh = math.floor(sw * 0.5625 + 0.5)
	for row = 1, 2 do
		local team = row == 1 and d.ours or d.theirs
		local color = (row == 1) == light and C.WIN or C.LOSE
		for i = 1, 5 do
			local e = team[i]
			local px = 16 + (i - 1) * (sw + 5)
			local unit = e and e.id and hero_unit(e.id)
			rect(px, y, sw, sh, C.SLOT, 5)
			if unit then
				local t = W.first_seen((row == 1 and "pko" or "pkt") .. i, e.id)
				local sc = W.pop(t)
				picture(hero_image(unit), px + sw * (1 - sc) / 2, y + sh * (1 - sc) / 2, sw * sc, sh * sc, 5, 0, false)
				local flash = 1 - math.min(1, t / 0.45)
				if flash > 0 then rect(px, y, sw, sh, alpha(color, 0.5 * flash), 5) end
			else
				W.seen[(row == 1 and "pko" or "pkt") .. i] = nil
			end
			rect(px + 4, y + sh - 2, sw - 8, 2, color, 1)
		end
		y = y + sh + 5
	end
	y = y + 10
	text(fonts.w600, 14, string.format(L("bb_pick_title"), L("bb_role_" .. my_position())), 16, y, C.TEXT)
	y = y + 26
	if d.my_hero and view and view.foes and #view.foes > 0 then
		for i, f in ipairs(view.foes) do
			if i > 4 then break end
			rect(16, y, w - 32, 50, C.ROW, 8)
			picture(hero_image(f.unit), 24, y + 9, 57, 32, 6)
			text(fonts.w600, 14, fit(fonts.w600, 14, hero_title(f.unit), w - 130), 90, y + 7, C.TEXT)
			text(fonts.w500, 13, fit(fonts.w500, 13, f.line, w - 130), 90, y + 27, C.MUTED)
			y = y + 56
		end
	elseif view and #view.best > 0 then
		local best = view.best
		if best[1].id ~= PK.leader then
			if PK.leader then PK.flash_at = state.clock end
			PK.leader = best[1].id
		end
		for _, c in pairs(PK.cards) do c.live = false end
		local ty = 0
		for i, b in ipairs(best) do
			local c = PK.cards[b.id]
			if not c then
				c = { y = ty + 30, a = 0, sc = 1, g = b.gain }
				PK.cards[b.id] = c
			end
			c.live, c.b, c.target, c.leader = true, b, ty, i == 1
			ty = ty + (i == 1 and 70 or 56) + 6
		end
		local k = 1 - math.exp(-12 * state.dt)
		for id, c in pairs(PK.cards) do
			if c.live then
				c.y = c.y + (c.target - c.y) * k
				c.a = c.a + (1 - c.a) * k
				c.sc = c.sc + (1 - c.sc) * k
				if math.abs(c.target - c.y) < 0.3 then c.y = c.target end
				if c.a > 0.995 then c.a = 1 end
				if c.sc > 0.998 then c.sc = 1 end
			else
				c.a = c.a - c.a * k * 1.4
				c.sc = c.sc + (0.85 - c.sc) * k
				if c.a < 0.02 then PK.cards[id] = nil end
			end
			if PK.cards[id] then
				G.alpha = vis * c.a
				PK.card(c, c.b, 16, y + c.y, w - 32, c.leader)
			end
		end
		G.alpha = vis
		y = y + ty
	else
		for i = 0, 2 do
			W.skeleton(16, y, w - 32, 56, i)
			y = y + 62
		end
		text(fonts.w500, 13, L("bb_best_empty"), 16, y + 2, C.MUTED)
		y = y + 22
	end
	PK.h = y + 14
	G.alpha, G.buttons = 1, nil
end

local function draw_pick()
	PK.draw()
end

local function quick_buy(name)
	local ok = pcall(Engine.SetQuickBuy, short_name(name), false)
	log("quickbuy " .. name .. ": " .. tostring(ok))
	state.win.status = string.format(L("bb_status_quick"), item_title(name))
end

local function purchase(id)
	local player, hero = Players.GetLocal(), Heroes.GetLocal()
	if not player or not hero then return false end
	return pcall(Player.PrepareUnitOrders, player, Enum.UnitOrder.DOTA_UNIT_ORDER_PURCHASE_ITEM, id,
		Vector(0, 0, 0), id, Enum.PlayerOrderIssuer.DOTA_ORDER_ISSUER_PASSED_UNIT_ONLY, hero,
		false, false, false, true, K.IDENTIFIER, false)
end

local function buy_item(name)
	local player, hero = Players.GetLocal(), Heroes.GetLocal()
	if not player or not hero then return end
	local cat = load_catalog()
	local gold = Player.GetTotalGold(player)
	local owned = owned_items(hero)
	local need = {}
	for _, part in ipairs(flat_parts(name)) do
		if owned[part] and owned[part] > 0 then
			owned[part] = owned[part] - 1
		else
			need[#need + 1] = part
		end
	end
	if #need == 0 then
		for _, part in ipairs(flat_parts(name)) do need[#need + 1] = part end
	end
	table.sort(need, function(a, b) return item_cost(a) > item_cost(b) end)
	local bought = {}
	for _, part in ipairs(need) do
		local entry = cat.by_name[part]
		if entry and entry.cost <= gold then
			purchase(entry.id)
			gold = gold - entry.cost
			bought[#bought + 1] = item_title(part)
		end
	end
	if #bought > 0 then
		state.win.status = string.format(L("bb_status_buy"), table.concat(bought, ", "))
		log("buy " .. name .. ": " .. table.concat(bought, ", "))
	else
		state.win.status = string.format(L("bb_status_poor"), item_title(name))
	end
	state.next_model = state.clock + 0.4
end

local function click(key)
	local win = state.win
	local left = key == Enum.ButtonCode.KEY_MOUSE1
	for i = #win.buttons, 1, -1 do
		local b = win.buttons[i]
		if cursor_in(b.x1, b.y1, b.x2, b.y2) then
			if win.dropdown and b.kind ~= "option" and b.kind ~= "dropdown" then
				win.dropdown = nil
				return
			end
			if b.kind == "option" and left then
				if win.dropdown then set_setting(win.dropdown, b.value) end
				win.dropdown = nil
				state.next_model = 0
				state.next_data = 0
			elseif b.kind == "dropdown" and left then
				win.dropdown = win.dropdown ~= b.value and b.value or nil
				state.anim.dropdown = 0
			elseif b.kind == "step" and left then
				set_setting("scale", b.value)
			elseif b.kind == "toggle" and left then
				set_setting(b.value, 1 - setting(b.value))
				state.next_model = 0
			elseif b.kind == "close" and left then
				win.visible = false
				win.closed_by_user = true
				win.dropdown = nil
			elseif b.kind == "header" and left then
				local cx, cy = Input.GetCursorPos()
				win.drag = { dx = cx - win.x, dy = cy - win.y }
			elseif b.kind == "tab" and left then
				if win.tab ~= b.value then state.anim.tab = 0 end
				win.tab = b.value
				win.status = nil
				win.dropdown = nil
			elseif b.kind == "hero" and left then
				state.preview_hero = b.value
				state.next_model = 0
				state.next_data = 0
			elseif b.kind == "upd" and left then
				UPD.act(b.value)
			elseif state.clock >= state.next_click and (b.kind == "item" or b.kind == "buy" or b.kind == "quick") then
				state.next_click = state.clock + K.CLICK_GAP
				if b.kind == "quick" or (b.kind == "item" and left) then
					quick_buy(b.value)
				else
					buy_item(b.value)
				end
			end
			return
		end
	end
	win.dropdown = nil
end

local function window_hit()
	local win = state.win
	if not win.visible or not win.x then return false end
	local sc = win.scale or G.s
	return cursor_in(win.x, win.y, win.x + K.WIN_W * sc, win.y + K.WIN_H * sc)
end

local function scan_foes()
	local me = Heroes.GetLocal()
	if not me then return end
	for _, h in ipairs(Heroes.GetAll()) do
		if not Entity.IsSameTeam(h, me) and not NPC.IsIllusion(h) and not Entity.IsDormant(h) then
			local items = {}
			for slot = 0, 5 do
				local item = NPC.GetItemByIndex(h, slot)
				local name = item and Ability.GetName(item)
				if name and item_cost(name) >= 500 then items[#items + 1] = name end
			end
			table.sort(items, function(a, b) return item_cost(a) > item_cost(b) end)
			local info = { items = items, at = state.clock, hp = Entity.GetHealth(h), max = Entity.GetMaxHealth(h), alive = Entity.IsAlive(h) }
			for i = 0, 15 do
				local ab = NPC.GetAbilityByIndex(h, i)
				local ok, ult = false, false
				if ab then ok, ult = pcall(Ability.IsUltimate, ab) end
				if ok and ult then
					info.ult_lvl = Ability.GetLevel(ab)
					info.ult_cd = Ability.GetCooldown(ab)
					break
				end
			end
			local bkb = NPC.GetItem(h, "item_black_king_bar")
			if bkb then info.bkb_cd = Ability.GetCooldown(bkb) end
			state.foes[NPC.GetUnitName(h)] = info
		end
	end
end


local shop = {}

do
	function shop.panel_line(panel, depth)
		local parts = { string.rep("  ", depth), panel:GetPanelType() }
		if panel:HasID() then parts[#parts + 1] = "#" .. panel:GetID() end
		local classes = panel:GetClassList()
		if classes and #classes > 0 then parts[#parts + 1] = "." .. table.concat(classes, ".") end
		local pos = panel:GetPositionWithinWindow()
		if pos then parts[#parts + 1] = string.format(" @%d,%d %dx%d", pos.x, pos.y, panel:GetLayoutWidth() or 0, panel:GetLayoutHeight() or 0) end
		if not panel:IsVisible() then parts[#parts + 1] = " (hidden)" end
		return table.concat(parts)
	end

	function shop.dump_panel(panel, depth, max_depth, lines)
		if #lines > 120 then return end
		lines[#lines + 1] = shop.panel_line(panel, depth)
		if depth >= max_depth then return end
		for i = 0, panel:GetChildCount() - 1 do
			local child = panel:GetChild(i)
			if child then shop.dump_panel(child, depth + 1, max_depth, lines) end
		end
	end

	function shop.shop_root()
		local hud = Panorama.GetPanelByName("Hud", false)
		local root = hud and hud:FindChildTraverse("shop")
		if not root then root = Panorama.GetPanelByName("shop", false) end
		return root
	end

	function shop.check()
		local root = shop.shop_root()
		log("shop root " .. (root and shop.panel_line(root, 0) or "not found") .. ", open " .. tostring(Engine.IsShopOpen()))
		if not root then return end
		local flyout = root:FindChildTraverse("GuideFlyout")
		local lines = {}
		shop.dump_panel(flyout or root, 0, flyout and 4 or 2, lines)
		for _, line in ipairs(lines) do Log.Write("[Build Brain] " .. line) end
	end

	function shop.shop_panels()
		local s = state.shop
		local p = s.panels
		if p and p.area and p.area:IsValid() then return p end
		if state.clock < s.next_find then return nil end
		s.next_find = state.clock + K.SHOP_FIND
		local root = shop.shop_root()
		local flyout = root and root:FindChildTraverse("GuideFlyout")
		if not flyout then return nil end
		local area = flyout:FindChildTraverse("ItemsArea") or flyout:FindChildTraverse("GuideFlyoutContainer") or flyout
		s.panels = { root = root, flyout = flyout, area = area }
		s.hidden = nil
		log("shop panels: " .. shop.panel_line(area, 0))
		return s.panels
	end

	function shop.guide_hidden(p, hide)
		local s = state.shop
		if s.hidden == hide or not p or not p.area or not p.area:IsValid() then return end
		s.hidden = hide
		pcall(p.area.SetStyle, p.area, hide and "opacity: 0.0;" or "opacity: 1.0;")
		local flag = hide and "false" or "true"
		local js = "(function(){var p=$.GetContextPanel();while(p.GetParent())p=p.GetParent();var f=p.FindChildTraverse('GuideFlyout');"
			.. "if(!f)return;var a=f.FindChildTraverse('ItemsArea')||f;a.hittestchildren=" .. flag .. ";a.hittest=" .. flag .. ";})();"
		local ok, ran = pcall(Engine.RunScript, js, p.area)
		log("guide " .. (hide and "hidden" or "shown") .. ", hittest js " .. tostring(ok and ran))
	end

	function shop.hero_abilities(hero)
		local unit = NPC.GetUnitName(hero)
		local map = state.abilities[unit]
		if map then return map end
		map = { by_id = {}, by_name = {}, talents = {} }
		for i = 0, 31 do
			local ability = NPC.GetAbilityByIndex(hero, i)
			local name = ability and Ability.GetName(ability)
			if name and name ~= "" then
				local okm, max = pcall(Ability.GetMaxLevel, ability)
				local entry = { name = name, ability = ability, id = Ability.GetAbilityID(ability), max = math.max(1, okm and tonumber(max) or 1) }
				map.by_id[entry.id] = entry
				map.by_name[name] = entry
				if name:match("^special_bonus_") and name ~= "special_bonus_attributes" and #map.talents < 8 then map.talents[#map.talents + 1] = entry end
			end
		end
		state.abilities[unit] = map
		return map
	end

	function shop.ability_title(name)
		local key = "a" .. name
		local title = state.names[key]
		if not title then
			title = game_text("#DOTA_Tooltip_ability_" .. name)
			if not title then
				local ok, t = pcall(GameLocalizer.FindAbility, name)
				title = ok and type(t) == "string" and t ~= "" and t or name
			end
			state.names[key] = title
		end
		return title
	end

	function shop.ability_text()
		if state.abil_text == nil then
			local dir = Engine.GetCheatDirectory() or ""
			if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
			state.abil_text = read_file(dir .. "assets\\data\\npc_abilities.json") or false
		end
		return state.abil_text or nil
	end

	function shop.number_text(v)
		if v == math.floor(v) then return tostring(math.floor(v)) end
		local out = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
		return out
	end

	function shop.talent_value(entry, key)
		local raw = shop.ability_text()
		local found = nil
		if raw then
			local base = key:gsub("^bonus_", "")
			found = raw:match('"' .. base .. '":%s*{[^}]-"' .. entry.name .. '":%s*"([^"]*)"')
			if not found then
				local at = raw:find('"' .. entry.name .. '":%s*{')
				if at then
					local chunk = raw:sub(at, at + 1500)
					found = chunk:match('"' .. key .. '":%s*{%s*"value":%s*"([^"]*)"') or chunk:match('"' .. key .. '":%s*"([^"]*)"')
				end
			end
		end
		local v = nil
		if found then
			local token = (found:match("^%s*(%S+)") or ""):gsub("^%+", "")
			v = tonumber(token)
		end
		if not v then
			for lvl = 1, 0, -1 do
				local ok, value = pcall(Ability.GetLevelSpecialValueFor, entry.ability, key, lvl)
				if ok and type(value) == "number" and value ~= 0 then
					v = value
					break
				end
			end
		end
		return v
	end

	function shop.talent_label(entry)
		local label = state.talent_text[entry.name]
		if label then return label end
		if state.label_budget <= 0 then return "" end
		state.label_budget = state.label_budget - 1
		label = game_text("#DOTA_Tooltip_ability_" .. entry.name)
		if not label then
			local ok, raw = pcall(GameLocalizer.FindAbility, entry.name)
			label = ok and type(raw) == "string" and raw ~= "" and raw or entry.name
		end
		label = label:gsub("([%+%-]?)%s*{s:([%w_]+)}", function(sign, key)
			local v = shop.talent_value(entry, key)
			if not v then return sign end
			if sign ~= "" then return sign .. shop.number_text(math.abs(v)) end
			return shop.number_text(v)
		end)
		label = label:gsub("%%%%", "%%"):gsub("<[^>]->", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
		state.talent_text[entry.name] = label
		return label
	end


	function shop.skill_list(map, role)
		local s = state.shop
		if s.skills_role == role and s.skills_map == map then return s.skills_list end
		local list, points = {}, {}
		for _, name in ipairs(role.skills or {}) do
			local e = map.by_name[name]
			list[#list + 1] = e or false
			if e then points[e.id] = (points[e.id] or 0) + 1 end
		end
		local d = role.src == "od" and role.data or role.od
		if d and d.levels and d.n >= K.RB_FEW then
			for lvl = #list + 1, 18 do
				local pick = false
				for _, cand in ipairs(d.levels[lvl] or {}) do
					local e = map.by_id[cand[1]]
					if e and (points[e.id] or 0) < e.max then
						pick = e
						break
					end
				end
				if pick then points[pick.id] = (points[pick.id] or 0) + 1 end
				list[lvl] = pick
			end
		end
		s.skills_role, s.skills_map, s.skills_list = role, map, list
		return list
	end

	function shop.group_items(list)
		local out, index = {}, {}
		for _, name in ipairs(list) do
			local e = index[name]
			if e then
				e.count = e.count + 1
			else
				e = { name = name, count = 1 }
				index[name] = e
				out[#out + 1] = e
			end
		end
		return out
	end

	function shop.title(label, y, bw)
		local w = measure(fonts.w800, 11, label)
		text(fonts.w800, 11, label, bw / 2, y, C.TITLE, "center")
		rect(bw / 2 - w / 2 - 22, y + 7, 14, 1, alpha(C.GOLD, 0.6))
		rect(bw / 2 + w / 2 + 8, y + 7, 14, 1, alpha(C.GOLD, 0.6))
		return y + 19
	end

	function shop.item(name, x, y, w, h, o)
		local hot = hover_t(o.key, x, y, w, h)
		local iy = y - hot * 2
		picture(item_image(name), x, iy, w, h, 5, o.done and 1 or 0, false, o.done and C.SHOP_DONE or nil)
		if o.next then
			local pulse = 0.55 + 0.45 * math.sin(state.clock * 3.2)
			frame_line(x - 1, iy - 1, w + 2, h + 2, C.GOLD, 6, 1.5)
			frame_line(x - 3, iy - 3, w + 6, h + 6, alpha(C.GOLD, 0.35 * pulse), 8, 2)
		elseif o.vs then
			frame_line(x, iy, w, h, alpha(C.VS, 0.75 + 0.25 * hot), 5, 1.3)
		elseif hot > 0.01 then
			frame_line(x, iy, w, h, alpha(C.WHITE, 0.5 * hot), 5)
		else
			frame_line(x, iy, w, h, C.EDGE, 5)
		end
		if o.count and o.count > 1 then
			text(fonts.w800, 11, tostring(o.count), x + w - 2, iy + h - 13, C.BADGE, "right")
			text(fonts.w800, 11, tostring(o.count), x + w - 3, iy + h - 14, C.WHITE, "right")
		end
		if o.minute then
			local label = o.minute .. "'"
			local lw = measure(fonts.w700, 10, label) + 6
			rect(x + 2, iy + h - 14, lw, 12, C.BADGE, 3)
			text(fonts.w700, 10, label, x + 5, iy + h - 14, C.TEXT)
		end
		if o.done then text(fonts.w800, 11, "✓", x + w - 3, iy + 1, C.WIN, "right") end
		if o.match then
			dot(x + w - 2, iy + 2, 5, C.DOT_DARK)
			dot(x + w - 2, iy + 2, 3.6, C.GOLD)
		end
		for k, unit in ipairs(o.foes or K.NONE) do
			if k > 2 then break end
			local bx, by = x + w - 10 - (k - 1) * 11, iy + h - 10
			dot(bx + 6, by + 6, 7.5, C.DOT_DARK)
			picture(hero_image(unit), bx, by, 12, 12, 6, 0, true)
		end
		button("item", x, y, w, h, name)
		if hot > 0.5 then state.shop.tip = { title = item_title(name), line = o.tip, y = y } end
	end

	function shop.grid(list, y, bw, key)
		local per_row = 6
		local iw = (bw - 24 - (per_row - 1) * 5) / per_row
		local ih = iw * 0.73
		for i, e in ipairs(list) do
			local col, row = (i - 1) % per_row, math.floor((i - 1) / per_row)
			e.key = e.key or (key .. i)
			shop.item(e.name, 12 + col * (iw + 5), y + row * (ih + 7), iw, ih, e)
		end
		return y + math.ceil(#list / per_row) * (ih + 7) + 6
	end

	function shop.draw_header(bw, role)
		local hero = Heroes.GetLocal()
		local unit = hero and NPC.GetUnitName(hero)
		local y = 10
		if unit then
			picture(hero_image(unit), 12, y, 42, 42, 8, 0, true)
			frame_line(12, y, 42, 42, C.EDGE, 8)
		end
		local current = role and role.wanted or my_position()
		for pos = 1, 5 do
			local x = 62 + (pos - 1) * 36
			local hot = hover_t("shop_role" .. pos, x, y + 5, 32, 32)
			local t = tween("shop_role_on" .. pos, pos == current and 1 or 0, 14)
			rect(x, y + 5, 32, 32, mix(C.SEG, C.PICKED, math.max(t, hot * 0.5)), 8)
			if t > 0.01 then frame_line(x, y + 5, 32, 32, alpha(C.GOLD, t), 8, 1.5) end
			local path = state.role_paths[pos]
			if not path then
				path = "panorama/images/rank_tier_icons/handicap/" .. K.ROLE_ICONS[pos] .. "icon_psd.vtex_c"
				state.role_paths[pos] = path
			end
			local icon = load_image(path)
			if icon then
				picture(icon, x + 5, y + 10, 22, 22, nil, 0, false, mix(C.ROLE_DIM, C.WHITE, math.max(t, hot)))
			else
				text(fonts.w800, 14, tostring(pos), x + 16, y + 12, mix(C.MUTED, C.GOLD, t), "center")
			end
			button("role", x, y + 5, 32, 32, pos)
			if hot > 0.5 then state.shop.tip = { title = L("bb_pos_" .. pos), y = y + 5 } end
		end
		local cx = bw - 10 - 24
		local hc = hover_t("shop_collapse", cx, y + 9, 24, 24)
		rect(cx, y + 9, 24, 24, mix(C.SEG, C.SEG_ON, hc), 7)
		text(fonts.w800, 15, "»", cx + 12, y + 11, mix(C.MUTED, C.TEXT, hc), "center")
		button("collapse", cx, y + 9, 24, 24)
		if hc > 0.5 then state.shop.tip = { title = L("bb_shop_back"), y = y + 9 } end
		y = y + 52
		local how = role and role.how or "main"
		local key = how == "set" and "bb_shop_role" or (how == "lobby" and "bb_shop_role_auto" or "bb_shop_role_main")
		text(fonts.w600, 12, fit(fonts.w600, 12, string.format(L(key), L("bb_pos_" .. current)), bw - 24), bw / 2, y, C.TEXT, "center")
		if role and role.pos ~= role.wanted then
			local note = string.format(L("bb_shop_none"), L("bb_pos_" .. role.pos))
			text(fonts.w500, 11, fit(fonts.w500, 11, note, bw - 24), bw / 2, y + 17, C.GOLD, "center")
			return y + 38
		end
		return y + 24
	end

	function shop.draw_start(y, bw, view, role)
		local items = role and role.start or (view and view.start) or K.NONE
		if #items == 0 then return y end
		local s = state.shop
		if s.start_src ~= items then
			s.start_src = items
			s.start_list = shop.group_items(items)
		end
		y = shop.title(L("bb_shop_start"), y, bw)
		for i, e in ipairs(s.start_list) do e.key = "start" .. i end
		return shop.grid(s.start_list, y, bw, "start")
	end

	function shop.route_list(view, early)
		local s = state.shop
		local key = early and "early" or "core"
		s.lists = s.lists or {}
		local cached = s.lists[key]
		if cached and cached.view == view then return cached.list end
		local list = {}
		for _, step in ipairs(view and view.route or {}) do
			if not step.sit and (step.early == true) == early then
				local i = #list + 1
				local tip = step.share and string.format(L("bb_shop_popular"), math.floor(step.share * 100 + 0.5), math.floor((step.tm or 0) / 60 + 0.5)) or step.reason
				list[i] = { name = step.name, key = key .. i, done = step.done, next = view.next == step,
					minute = not step.done and step.tm and step.tm > 0 and math.floor(step.tm / 60 + 0.5) or nil, tip = tip }
			end
		end
		s.lists[key] = { view = view, list = list }
		return list
	end

	function shop.draw_early(y, bw, view)
		local list = shop.route_list(view, true)
		if #list == 0 then return y end
		y = shop.title(L("bb_shop_early"), y, bw)
		return shop.grid(list, y, bw, "early")
	end

	function shop.draw_core(y, bw, view)
		y = shop.title(L("bb_shop_core"), y, bw)
		local route = view and view.route or K.NONE
		if #route == 0 then
			text(fonts.w500, 11, L("bb_shop_loading"), bw / 2, y, C.DIM, "center")
			return y + 24
		end
		return shop.grid(shop.route_list(view, false), y, bw, "core")
	end

	function shop.pop_list(view, role)
		local s = state.shop
		if s.pop_view == view then return s.pop_list end
		local list, seen = {}, {}
		for _, step in ipairs(view and view.route or {}) do seen[step.name] = true end
		local owned = owned_items(Heroes.GetLocal())
		for _, c in ipairs(role and role.pop or {}) do
			if not seen[c.name] and #list < 12 then
				seen[c.name] = true
				local tip = c.share and string.format(L("bb_shop_popular"), math.floor(c.share * 100 + 0.5), math.floor((c.tm or 0) / 60 + 0.5)) or nil
				list[#list + 1] = { name = c.name, done = is_owned(c.name, owned), tip = tip }
			end
		end
		s.pop_view, s.pop_list = view, list
		return list
	end

	function shop.counters()
		return state.view and state.view.vs or K.NONE
	end

	function shop.draw_vs(y, bw, role, hero)
		local list = shop.counters(role, hero)
		if #list == 0 then return y end
		y = shop.title(L("bb_shop_vs"), y, bw)
		return shop.grid(list, y, bw, "vs")
	end

	function shop.draw_sit(y, bw, view, role)
		local list = shop.pop_list(view, role)
		if #list == 0 then return y end
		y = shop.title(L("bb_shop_sit"), y, bw)
		return shop.grid(list, y, bw, "pop")
	end

	function shop.draw_skills(hero, y, bw, role)
		if not role then return y end
		local map = shop.hero_abilities(hero)
		local list = shop.skill_list(map, role)
		if #list == 0 then return y end
		y = shop.title(L("bb_shop_skills"), y, bw)
		local level = math.floor(NPC.GetCurrentLevel(hero) or 1)
		local per, gap = 9, 3
		local size = (bw - 24 - (per - 1) * gap) / per
		local count = math.min(#list, 18)
		local slot = 0
		for lvl = 1, count do
			local entry = list[lvl]
			if entry then
				slot = slot + 1
				local col, row = (slot - 1) % per, math.floor((slot - 1) / per)
				local x, sy = 12 + col * (size + gap), y + row * (size + gap + 2)
				local passed = lvl <= level
				local hot = hover_t("skill" .. lvl, x, sy, size, size)
				local tint = passed and alpha(C.WHITE, 0.4) or nil
				if entry.name:match("^special_bonus_") then
					rect(x, sy, size, size, C.TALENT_BG, 4)
					local icon = load_image(entry.name == "special_bonus_attributes" and "panorama/images/spellicons/attribute_bonus_png.vtex_c"
						or "panorama/images/hud/reborn/stat_branch_large_png.vtex_c")
					if icon then
						picture(icon, x + 2, sy + 2, size - 4, size - 4, 3, 0, false, tint)
					else
						text(fonts.w800, 12, "T", x + size / 2, sy + size / 2 - 8, C.GOLD, "center")
					end
					if hot > 0.5 then state.shop.tip = { title = entry.name == "special_bonus_attributes" and shop.ability_title(entry.name) or shop.talent_label(entry), y = sy } end
				else
					entry.icon = entry.icon or ("panorama/images/spellicons/" .. entry.name .. "_png.vtex_c")
					picture(load_image(entry.icon), x, sy, size, size, 4, 0, false, tint)
					if hot > 0.5 then state.shop.tip = { title = shop.ability_title(entry.name), y = sy } end
				end
				if lvl == level + 1 then
					local pulse = 0.55 + 0.45 * math.sin(state.clock * 3.2)
					frame_line(x - 1, sy - 1, size + 2, size + 2, C.GOLD, 5, 1.5)
					frame_line(x - 3, sy - 3, size + 6, size + 6, alpha(C.GOLD, 0.35 * pulse), 7, 2)
				else
					frame_line(x, sy, size, size, alpha(C.WHITE, 0.08 + 0.35 * hot), 4)
				end
				rect(x + 1, sy + 1, 13, 10, C.BADGE, 2)
				text(fonts.w700, 9, tostring(lvl), x + 7.5, sy + 1, passed and C.MUTED or C.TEXT, "center")
			end
		end
		return y + math.max(1, math.ceil(slot / per)) * (size + gap + 2) + 6
	end

	function shop.talent_box(entry, x, y, w, h, picked, key, share, left)
		local hot = hover_t(key, x, y, w, h)
		if picked then
			local outer, inner = mix(C.TAL_ON_OUT, C.TAL_ON_IN, hot * 0.3), mix(C.TAL_ON_IN, C.GOLD, hot * 0.25)
			if left then
				grad(x, y, w, h, outer, inner, outer, inner, 4)
			else
				grad(x, y, w, h, inner, outer, inner, outer, 4)
			end
		else
			rect(x, y, w, h, mix(C.TAL_OFF, C.TAL_HOT, hot), 4)
		end
		local label = shop.talent_label(entry)
		local lines = wrap(fonts.w600, 10, label, w - 10, 2)
		local ty = y + h / 2 - #lines * 6
		for _, line in ipairs(lines) do
			text(fonts.w600, 10, line, x + w / 2, ty, picked and C.WHITE or C.MUTED, "center")
			ty = ty + 12
		end
		if hot > 0.5 then state.shop.tip = { title = label, line = share and (share .. "%") or nil, y = y } end
	end

	function shop.draw_talents(hero, y, bw, role)
		if not role then return y end
		local map = shop.hero_abilities(hero)
		local talents = map.talents
		local od = (role.src == "od" or role.src == "sz") and role.data or role.od
		if #talents < 8 or (role.src ~= "pt" and not od) then return y end
		y = shop.title(L("bb_shop_talents"), y, bw)
		local row_h, gap, mid = 32, 3, 30
		local box_h = 4 * row_h + 3 * gap + 10
		rect(10, y, bw - 20, box_h, C.TAL_BOX, 8)
		frame_line(10, y, bw - 20, box_h, C.EDGE, 8)
		local cw = (bw - 30 - mid) / 2
		local ry = y + 5
		for pair = 4, 1, -1 do
			local right, left = talents[pair * 2 - 1], talents[pair * 2]
			local left_pick, share_l, share_r = false, nil, nil
			local pt = role.src == "pt" and role.talents and role.talents[pair]
			if pt then
				left_pick = pt.pick == left.name
			elseif od and od.counts then
				local cr, cl = od.counts[right.id] or 0, od.counts[left.id] or 0
				local total = cl + cr
				left_pick = cl > cr
				if total > 0 then share_l, share_r = math.floor(cl / total * 100 + 0.5), math.floor(cr / total * 100 + 0.5) end
			end
			local known = pt or share_l
			shop.talent_box(left, 15, ry, cw, row_h, known and left_pick, "tl" .. pair, share_l, true)
			shop.talent_box(right, 15 + cw + mid, ry, cw, row_h, known and not left_pick, "tr" .. pair, share_r, false)
			local cx, cy = 15 + cw + mid / 2, ry + row_h / 2
			dot(cx, cy, 12.5, C.DOT_DARK2)
			Render.Circle(P(cx, cy), 12.5 * G.s, A(alpha(C.GOLD, 0.75)), 1.3 * G.s)
			text(fonts.w800, 11, tostring(5 + pair * 5), cx, cy - 7, C.GOLD, "center")
			if pair > 1 then rect(15, ry + row_h + gap / 2, bw - 30, 1, C.LINE_FAINT) end
			ry = ry + row_h + gap
		end
		return y + box_h + 8
	end

	function shop.draw_tip(bw, bh)
		local tip = state.shop.tip
		if not tip then
			state.anim.shop_tip = 0
			return
		end
		local t = tween("shop_tip", 1, 18)
		local saved = G.alpha
		G.alpha = saved * t
		local title_lines = wrap(fonts.w700, 12, tip.title or "", 220, 3)
		local lines = tip.line and wrap(fonts.w500, 11, tip.line, 240, 4) or K.NONE
		local tw = 0
		for _, l in ipairs(title_lines) do tw = math.max(tw, measure(fonts.w700, 12, l)) end
		for _, l in ipairs(lines) do tw = math.max(tw, measure(fonts.w500, 11, l)) end
		tw = tw + 20
		local th = 12 + #title_lines * 16 + #lines * 14
		local x, y = bw + 8, math.max(4, math.min(bh - th - 4, tip.y))
		shadow(x, y, tw, th, 8, 16)
		rect(x, y, tw, th, C.TIP, 8)
		frame_line(x, y, tw, th, C.EDGE, 8)
		local ly = y + 6
		for _, l in ipairs(title_lines) do
			text(fonts.w700, 12, l, x + 10, ly, C.TEXT)
			ly = ly + 16
		end
		for _, l in ipairs(lines) do
			text(fonts.w500, 11, l, x + 10, ly, C.GOLD)
			ly = ly + 14
		end
		G.alpha = saved
	end

	function shop.draw_toast(bw, bh)
		local s = state.shop
		local status = state.win.status
		if status ~= s.last_status then s.last_status, s.status_at = status, state.clock end
		if not status or not s.status_at then return end
		local age = state.clock - s.status_at
		if age > 2.6 then return end
		local saved = G.alpha
		G.alpha = saved * math.min(1, age * 6, (2.6 - age) * 3)
		local label = fit(fonts.w600, 11, status, bw - 48)
		local w = measure(fonts.w600, 11, label) + 24
		shadow(bw / 2 - w / 2, bh - 38, w, 26, 13, 14)
		rect(bw / 2 - w / 2, bh - 38, w, 26, C.TIP, 13)
		frame_line(bw / 2 - w / 2, bh - 38, w, 26, alpha(C.GOLD, 0.5), 13)
		text(fonts.w600, 11, label, bw / 2, bh - 32, C.GOLD, "center")
		G.alpha = saved
	end

	function shop.draw_pill(bw)
		local x, y, w, h = bw - 12 - 30, 8, 30, 30
		local hot = hover_t("shop_pill", x, y, w, h)
		shadow(x, y, w, h, 8, 12)
		local top = mix(C.GOLD_HI, C.WHITE, hot * 0.3)
		grad(x, y, w, h, top, top, C.GOLD_LO, C.GOLD_LO, 8)
		text(fonts.w800, 15, "«", x + w / 2, y + 6, C.GOLD_TEXT, "center")
		button("expand", x, y, w, h)
		local a, b = P(x, y), P(x + w, y + h)
		state.shop.rect = { x = a.x, y = a.y, w = b.x - a.x, h = b.y - a.y }
	end

	function shop.body(bw, bh)
		local s = state.shop
		local view = state.view
		local role = view and view.role
		local hero = Heroes.GetLocal()
		local y = shop.draw_header(bw, role)
		y = shop.draw_start(y, bw, view, role)
		y = shop.draw_early(y, bw, view)
		y = shop.draw_core(y, bw, view)
		y = shop.draw_vs(y, bw, role, hero)
		y = shop.draw_sit(y, bw, view, role)
		if hero then
			y = shop.draw_skills(hero, y, bw, role)
			y = shop.draw_talents(hero, y, bw, role)
		end
		s.content_h = y
		shop.draw_toast(bw, bh)
	end

	function shop.draw()
		local s = state.shop
		s.buttons, s.rect, s.tip = {}, nil, nil
		if not Engine.IsShopOpen() then
			state.anim.shop = 0
			s.press = nil
			return
		end
		local p = shop.shop_panels()
		if not p then return end
		local on = setting("shop") == 1
		shop.guide_hidden(p, on and not s.off)
		if not on then return end
		if not s.geom or state.clock >= s.next_geom then
			s.next_geom = state.clock + K.SHOP_GEOM
			local pos = p.area:GetPositionWithinWindow()
			s.geom = pos and { x = pos.x, y = pos.y, w = p.area:GetLayoutWidth() or 0, h = p.area:GetLayoutHeight() or 0 } or nil
		end
		local g = s.geom
		if not g or g.w < 60 or g.h < 120 then return end
		local base = g.w / K.SHOP_BASE_W
		G.buttons = s.buttons
		if s.off then
			G.ox, G.oy, G.s, G.alpha = g.x, g.y, base, 1
			shop.draw_pill(K.SHOP_BASE_W)
			return
		end
		local want = s.content_h and (g.h - 6) / (s.content_h + 14) or base
		local scale = tween("shop_scale", math.max(base * K.SHOP_MIN, math.min(base * K.SHOP_GROW, want)), 8)
		local pw = K.SHOP_BASE_W * scale
		local px = math.max(4, g.x + g.w - pw)
		local t = tween("shop", 1, 10)
		G.ox, G.oy, G.s, G.alpha = px - (1 - t) * 14 * scale, g.y, scale, t
		s.rect = { x = px, y = g.y, w = pw, h = g.h }
		local bw, bh = K.SHOP_BASE_W, g.h / scale
		rect(0, 0, bw, bh, C.SHOP_BG, 10)
		grad(0, 0, bw, 160, C.SHOP_TOP, C.SHOP_TOP, C.BG_BOTTOM, C.BG_BOTTOM, 10)
		frame_line(0, 0, bw, bh, C.EDGE, 10)
		Render.PushClip(P(0, 0), P(bw, bh), true)
		local ok, err = pcall(shop.body, bw, bh)
		Render.PopClip()
		if not ok then error(err, 0) end
		if s.press and s.press.drag then s.tip = nil end
		shop.draw_tip(bw, bh)
		shop.draw_drag()
		G.alpha = 1
	end

	function shop.drop_zones()
		local s = state.shop
		if s.zones and state.clock < (s.zones_at or 0) then return s.zones end
		s.zones_at = state.clock + K.SHOP_GEOM
		local hud = Panorama.GetPanelByName("Hud", false)
		local zones, names = {}, {}
		local function take(id)
			local p = hud and hud:FindChildTraverse(id)
			local pos = p and p:IsVisible() and p:GetPositionWithinWindow()
			if not pos then return end
			local w, h = p:GetLayoutWidth() or 0, p:GetLayoutHeight() or 0
			if w > 10 and h > 10 then
				zones[#zones + 1] = { x = pos.x, y = pos.y, w = w, h = h }
				names[#names + 1] = id
			end
		end
		for _, id in ipairs(K.QB_PANELS) do take(id) end
		if #zones == 0 then take(K.QB_FALLBACK) end
		local sig = table.concat(names, ",")
		if sig ~= s.zones_sig then
			s.zones_sig = sig
			log("quickbuy drop zones: " .. (sig ~= "" and sig or "none"))
		end
		s.zones = zones
		return zones
	end

	function shop.over_zone()
		local cx, cy = Input.GetCursorPos()
		for _, z in ipairs(shop.drop_zones()) do
			if cx >= z.x and cx <= z.x + z.w and cy >= z.y and cy <= z.y + z.h then return true end
		end
		return false
	end

	function shop.release()
		local s = state.shop
		local press = s.press
		s.press = nil
		if not press then return false end
		if press.drag then
			if shop.over_zone() then quick_buy(press.name) end
		elseif shop.hit() then
			quick_buy(press.name)
		end
		return true
	end

	function shop.draw_drag()
		local s = state.shop
		local press = s.press
		if not press then return end
		local cx, cy = Input.GetCursorPos()
		if not press.drag and math.abs(cx - press.x) + math.abs(cy - press.y) > K.DRAG_MIN then press.drag = true end
		if not Input.IsKeyDown(Enum.ButtonCode.KEY_MOUSE1) then
			if press.drag then shop.release() else s.press = nil end
			return
		end
		if not press.drag then return end
		local ox, oy, sc, al = G.ox, G.oy, G.s, G.alpha
		G.ox, G.oy, G.s, G.alpha = 0, 0, 1, 1
		local over = false
		for _, z in ipairs(shop.drop_zones()) do
			local hot = cx >= z.x and cx <= z.x + z.w and cy >= z.y and cy <= z.y + z.h
			over = over or hot
			rect(z.x - 3, z.y - 3, z.w + 6, z.h + 6, alpha(C.GOLD, hot and 0.22 or 0.08), 6)
			frame_line(z.x - 3, z.y - 3, z.w + 6, z.h + 6, alpha(C.GOLD, hot and 0.95 or 0.45), 6, 1.5)
		end
		local w, h = 52, 38
		picture(item_image(press.name), cx - w / 2, cy - h / 2, w, h, 5, 0, false, C.DRAG_TINT)
		frame_line(cx - w / 2, cy - h / 2, w, h, over and C.GOLD or C.EDGE, 5, 1.5)
		G.ox, G.oy, G.s, G.alpha = ox, oy, sc, al
	end

	function shop.hit()
		local r = state.shop.rect
		if not r then return false end
		return cursor_in(r.x, r.y, r.x + r.w, r.y + r.h)
	end

	function shop.click(key)
		local s = state.shop
		if state.clock < state.next_click then return end
		local left = key == Enum.ButtonCode.KEY_MOUSE1
		for i = #s.buttons, 1, -1 do
			local b = s.buttons[i]
			if cursor_in(b.x1, b.y1, b.x2, b.y2) then
				state.next_click = state.clock + K.CLICK_GAP
				if b.kind == "role" and left then
					if setting("role") ~= b.value then
						set_setting("role", b.value)
						state.next_model, state.next_data = 0, 0
						log("shop role " .. b.value)
					end
				elseif b.kind == "collapse" and left then
					s.off = true
				elseif b.kind == "expand" and left then
					s.off = false
					state.anim.shop = 0
				elseif b.kind == "item" then
					if left then
						local cx, cy = Input.GetCursorPos()
						s.press = { name = b.value, x = cx, y = cy }
					else
						buy_item(b.value)
					end
				end
				return
			end
		end
	end
end

local function track_damage(hero)
	local dmg = state.dmg
	local alive = Entity.IsAlive(hero)
	if dmg.alive and not alive then
		dmg.deaths = dmg.deaths + 1
		state.next_model = 0
		log("death " .. dmg.deaths)
	end
	dmg.alive = alive
	if state.clock < dmg.next_state then return end
	dmg.next_state = state.clock + K.STATE_STEP
	for _, s in ipairs(K.STATES) do
		if NPC.HasState(hero, s) then
			dmg.ctrl = dmg.ctrl + K.STATE_STEP
			break
		end
	end
end

local function sz_sync()
	local sync = state.sync
	if sync.busy or sync.done then return end
	local dir = Engine.GetCheatDirectory() or ""
	if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
	local path = dir .. K.SZ_FILE
	local okf, f = pcall(io.open, path, "rb")
	local exists = okf and f ~= nil
	if exists then f:close() end
	if exists and os.time() - Config.ReadInt(K.CONFIG, "sz_checked", 0) < K.SZ_CHECK then
		sync.done = true
		return
	end
	sync.busy = true
	local ok = pcall(HTTP.Request, "GET", K.SZ_BASE .. "version.txt", { timeout = K.NET_TIMEOUT }, function(res)
		local version = tonumber(res and res.code) == 200 and tostring(res.response or ""):match("^%s*(.-)%s*$") or ""
		if version == "" then
			sync.busy, sync.done = false, true
			log("builds version check failed")
			return
		end
		Config.WriteInt(K.CONFIG, "sz_checked", os.time())
		if exists and version == Config.ReadString(K.CONFIG, "sz_version", "") then
			sync.busy, sync.done = false, true
			return
		end
		local ok2 = pcall(HTTP.Request, "GET", K.SZ_BASE .. "builds.txt", { timeout = K.NET_TIMEOUT }, function(res2)
			sync.busy, sync.done = false, true
			local body = tonumber(res2 and res2.code) == 200 and res2.response or nil
			if type(body) ~= "string" or not body:match("^BB1\t") or select(2, body:gsub("\n", "")) < 100 then
				log("builds download failed")
				return
			end
			local okw, out = pcall(io.open, path, "wb")
			if not okw or not out then
				log("builds file is not writable")
				return
			end
			out:write(body)
			out:close()
			Config.WriteString(K.CONFIG, "sz_version", version)
			state.sz, state.sz_text, state.sz_next, state.sz_pos, state.sz_vs, state.sz_vidx = {}, nil, 0, nil, {}, nil
			state.next_model = 0
			log("builds updated " .. version)
		end, "bb_builds")
		if not ok2 then sync.busy, sync.done = false, true end
	end, "bb_builds_version")
	if not ok then sync.busy, sync.done = false, true end
end

local function report(tag, err)
	if err ~= state.errors[tag] then
		state.errors[tag] = err
		Log.Write("[Build Brain] " .. tag .. ": " .. tostring(err))
	end
end

local function frame()
	local dt = math.min(0.2, math.max(0, GlobalVars.GetAbsFrameTime() or 0))
	state.dt = dt
	state.clock = state.clock + dt
	state.btn_used = 0
	state.img_budget, state.label_budget = K.IMG_BUDGET, K.LABEL_BUDGET
	if state.clock > 3 and not state.sync.done then sz_sync() end
	pcall(UPD.tick)
	if state.clock >= state.next_cache_reset then
		state.next_cache_reset = state.clock + K.CACHE_RESET
		state.sizes, state.fits, state.wraps, state.points = {}, {}, {}, {}
	end
	local win = state.win
	if ui.window_key:IsPressed() and not Input.IsInputCaptured() then
		win.visible = not win.visible
		win.closed_by_user = not win.visible
		win.dropdown = nil
		state.next_model = 0
		log("window " .. (win.visible and "open" or "closed"))
	end
	if state.clock >= state.next_draft then
		state.next_draft = state.clock + (state.draft.phase and K.DRAFT_STEP or K.DRAFT_SLOW)
		local okd, errd = pcall(read_draft)
		if not okd then report("draft", errd) end
	end
	local in_shop = Engine.IsInGame() and Engine.IsShopOpen() and setting("shop") == 1
	if win.visible or state.draft.phase or in_shop then
		if state.clock >= state.next_data then
			state.next_data = state.clock + K.DATA_STEP
			want_data()
		end
		net_pump()
		if state.clock >= state.next_model then
			state.next_model = state.clock + K.MODEL_STEP
			local okv, errv = pcall(compute_view)
			if not okv then report("model", errv) end
		end
	end
	draw_window()
	pcall(draw_pick)
	if Engine.IsInGame() then
		local ok, err = pcall(shop.draw)
		if not ok and err ~= state.shop.error then
			state.shop.error = err
			log("shop: " .. tostring(err))
		end
	end
end

local function update()
	local hero = Heroes.GetLocal()
	if hero then track_damage(hero) end
	if state.clock >= state.next_foes then
		state.next_foes = state.clock + K.FOE_STEP
		scan_foes()
		local lang = localization.GetLanguage()
		if lang ~= state.lang then
			state.lang = lang
			for key in pairs(lcache) do lcache[key] = nil end
		end
	end
end

local script = {}

function script.OnFrame()
	if not ui.enable:Get() then
		if state.shop.hidden then pcall(shop.guide_hidden, state.shop.panels, false) end
		return
	end
	local ok, err = pcall(frame)
	if not ok and err ~= state.frame_error then
		state.frame_error = err
		Log.Write("[Build Brain] frame: " .. tostring(err))
	end
end

function script.OnUpdate()
	if not ui.enable:Get() then return end
	local ok, err = pcall(update)
	if not ok and err ~= state.update_error then
		state.update_error = err
		Log.Write("[Build Brain] update: " .. tostring(err))
	end
end

function script.OnKeyEvent(data)
	if not ui.enable:Get() then return true end
	local key, event = data.key, data.event
	if key ~= Enum.ButtonCode.KEY_MOUSE1 and key ~= Enum.ButtonCode.KEY_MOUSE2 then return true end
	local win = state.win
	if event == Enum.EKeyEvent.EKeyEvent_KEY_UP then
		if state.shop.press and key == Enum.ButtonCode.KEY_MOUSE1 then
			local ok, err = pcall(shop.release)
			if not ok then log("shop drop: " .. tostring(err)) end
			return false
		end
		if PK.drag and key == Enum.ButtonCode.KEY_MOUSE1 then
			PK.drag = nil
			Config.WriteInt(K.CONFIG, "pk_x", math.floor(PK.x))
			Config.WriteInt(K.CONFIG, "pk_y", math.floor(PK.y))
			return false
		end
		if win.drag and key == Enum.ButtonCode.KEY_MOUSE1 then
			win.drag = nil
			Config.WriteInt(K.CONFIG, "win_x", math.floor(win.x))
			Config.WriteInt(K.CONFIG, "win_y", math.floor(win.y))
			return false
		end
		return not (shop.hit() or window_hit() or PK.hit())
	end
	if event ~= Enum.EKeyEvent.EKeyEvent_KEY_DOWN then return true end
	if PK.hit() then
		pcall(PK.click, key)
		return false
	end
	if shop.hit() then
		local ok, err = pcall(shop.click, key)
		if not ok then log("shop click: " .. tostring(err)) end
		return false
	end
	if not window_hit() then return true end
	local ok, err = pcall(click, key)
	if not ok then log("click: " .. tostring(err)) end
	return false
end

local function on_hurt(data)
	if not data.target then return end
	local hero = Heroes.GetLocal()
	if not hero or not same(data.target, hero) then return end
	local dmg = state.dmg
	local kind = "phys"
	if data.ability then
		local ok, dtype = pcall(Ability.GetDamageType, data.ability)
		if ok and dtype == Enum.DamageTypes.DAMAGE_TYPE_MAGICAL then
			kind = "mag"
		elseif ok and dtype == Enum.DamageTypes.DAMAGE_TYPE_PURE then
			kind = "pure"
		end
	end
	local damage = tonumber(data.damage) or 0
	dmg[kind] = dmg[kind] + damage
	local source = data.source
	local unit = source and NPC.GetUnitName(source) or "unknown"
	if not unit:match("^npc_dota_hero_") and source then
		local owner = Entity.GetOwner(source)
		local ok, oname = pcall(NPC.GetUnitName, owner)
		if owner and ok and oname and oname:match("^npc_dota_hero_") then unit = oname end
	end
	dmg.src[unit] = (dmg.src[unit] or 0) + damage
	if not dmg.first then
		dmg.first = true
		log("OnEntityHurt works: " .. unit .. " " .. kind .. " " .. math.floor(damage))
	end
end

function script.OnEntityHurt(data)
	if not ui.enable:Get() then return end
	on_hurt(data)
end

function script.OnGameEnd()
	if state.shop.hidden then pcall(shop.guide_hidden, state.shop.panels, false) end
	state.shop = { buttons = {}, rect = nil, panels = nil, next_find = 0, next_geom = 0, geom = nil, hidden = nil, off = false, tip = nil }
	state.abilities = {}
	state.dmg = new_damage()
	state.foes = {}
	state.view = nil
	state.next_model = 0
	state.win.closed_by_user = false
	state.preview_hero = nil
	state.route_sig = ""
	state.draft = { ours = {}, theirs = {}, bans = {}, my_team = nil, my_hero = nil, my_pos = nil, sig = "", phase = false }
end

return script
