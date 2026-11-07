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

local Config = Config
do
	local ok, real = pcall(function()
		return type(Config.ReadInt) == "function" and type(Config.ReadString) == "function"
			and type(Config.WriteInt) == "function" and type(Config.WriteString) == "function"
	end)
	if not (ok and real) then
		local mem = {}
		Config = {
			mem = true,
			ReadInt = function(c, k, d)
				local v = mem[tostring(c) .. "|" .. tostring(k)]
				return type(v) == "number" and v or d or 0
			end,
			ReadString = function(c, k, d)
				local v = mem[tostring(c) .. "|" .. tostring(k)]
				return type(v) == "string" and v or d or ""
			end,
			WriteInt = function(c, k, v) mem[tostring(c) .. "|" .. tostring(k)] = v end,
			WriteString = function(c, k, v) mem[tostring(c) .. "|" .. tostring(k)] = v end,
		}
		pcall(function() Log.Write("[Build Brain] global Config was replaced by another script, settings will not be saved") end)
	end
end

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
		bb_shop_core = "CORE ITEMS",
		bb_shop_sit = "ALSO BUILT",
		bb_shop_vs = "AGAINST ENEMIES",
		bb_vs_brk = "strong passives, break them",
		bb_vs_eva = "evasion, you need true strike",
		bb_vs_heal = "lots of healing, cut it",
		bb_vs_inv = "goes invisible",
		bb_vs_vision = "top players buy it %.1fx more often",
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
		bb_how_crellas_crozier = "aura cuts healing of enemies nearby",
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
		bb_how_orb_of_corrosion = "attacks cut enemy healing a little, armor and speed",
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
		bb_pick_meta = "meta pick, %d%% wins in this role",
		bb_pk_pick = "Pick",
		bb_mate_title = "For teammates",
		bb_mate_free = "open role",
		bb_mate_name = "Teammate",
		bb_pick_own = "your hero",
		bb_scout_title = "Enemies play (30 days)",
		bb_scout_hint = "frame: many games and high win rate, worth a ban",
		bb_foe_title = "Who to watch out for",
		bb_next_usual = "usually bought at %d min · %d%% of games",
		bb_route_title = "Route",
		bb_ld_builds = "Hero builds",
		bb_ld_vs = "Matchups against enemies",
		bb_ld_wr = "Hero win rates",
		bb_ld_picks = "Picking heroes for you",
		bb_ld_wait = "Waiting for enemy picks",
		bb_ld_offline = "No connection, using saved builds from %s",
		bb_pool_title = "My heroes",
		bb_pool_all = "all heroes",
		bb_pool_count = "%d heroes",
		bb_pool_pick = "Choose",
		bb_pool_clear = "Clear",
		bb_pool_done = "Done",
		bb_pool_hint = "The draft shows your 2 best heroes from this list plus the best meta picks.",
		bb_attr_str = "Strength",
		bb_attr_agi = "Agility",
		bb_attr_int = "Intelligence",
		bb_attr_all = "Universal",
		bb_onb_heroes_q = "Who do you play?",
		bb_onb_heroes_s = "Mark your heroes and the draft will suggest them. Mark nobody and we suggest everyone",
		bb_next_share = "bought in %d%% of games",
		bb_card_usual = "Bought in %d%% of games, usually at %d min",
		bb_card_cost = "%d gold",
		bb_card_skip = "Skip",
		bb_card_back = "Bring back",
		bb_card_replace = "Replace ▾",
		bb_card_none = "Nothing to swap",
		bb_card_alts = "Taken instead on this role",
		bb_card_share = "%d%% of games",
		bb_card_always = "Remember for this hero",
		bb_card_from = "Instead of %s",
		bb_card_skipped = "skip",
		bb_eta = "~%d min",
		bb_set_mode = "Game mode",
		bb_mode_0 = "normal games",
		bb_mode_1 = "Turbo",
		bb_mode_2 = "both",
		bb_set_style = "Style",
		bb_style_0 = "Scoreboard",
		bb_style_1 = "Mono",
		bb_style_2 = "Gold",
		bb_style_3 = "Ruby",
		bb_need = "%s gold to go",
		bb_enough = "Enough gold",
		bb_tl_hint = "items stand at the minute they are usually bought",
		bb_tl_hint_turbo = "minute at your income",
		bb_status_link = "Opening in your browser",
		bb_vs_route = "vs %s on %s",
		bb_menu_tg = "Telegram channel",
		bb_onb_hello = "Let's set everything up for you",
		bb_news_head = "Build Brain %s",
		bb_news_title = "What's new",
		bb_news_sub = "Fixed from your feedback",
		bb_news_13 = "Pick advice for teammates: click a hero to suggest it to your team",
		bb_news_16 = "Ctrl or Shift + left click in the shop adds an item to quick buy",
		bb_news_17 = "Rank for win rates is now a range: Ancient+, Divine+",
		bb_news_18 = "New Party tab: find teammates and join a party in one click",
		bb_news_19 = "Your party shows avatars, roles and rank, it closes by itself when you start a search",
		bb_news_20 = "Auto-buy tells you in chat when it could not buy an item",
		bb_news_tg = "Telegram channel",
		bb_news_ok = "Got it",
		bb_news_note = "News, test builds and giveaways go there first",
		bb_onb_start = "Start",
		bb_onb_note = "Takes 20 seconds, you can change it any time",
		bb_onb_skip = "Skip",
		bb_onb_step = "Step %d of 5",
		bb_onb_role_q = "Which role do you play?",
		bb_onb_role_s = "We pick heroes and builds for it",
		bb_onb_r0 = "Different",
		bb_onb_r1 = "Carry",
		bb_onb_r2 = "Mid",
		bb_onb_r3 = "Offlane",
		bb_onb_r4 = "Support 4",
		bb_onb_r5 = "Support 5",
		bb_onb_rs0 = "role from the lobby",
		bb_onb_rs1 = "safe lane",
		bb_onb_rs2 = "middle",
		bb_onb_rs3 = "hard lane",
		bb_onb_rs4 = "roamer",
		bb_onb_rs5 = "full support",
		bb_onb_lobby = "Role from lobby",
		bb_onb_mode_q = "Which mode do you play more?",
		bb_onb_mode_s = "In Turbo items come at other times",
		bb_onb_m0 = "Normal games",
		bb_onb_m1 = "Turbo",
		bb_onb_m2 = "Both",
		bb_onb_ms0 = "Ranked and unranked All Pick",
		bb_onb_ms1 = "More gold, items earlier",
		bb_onb_ms2 = "We check the mode every match",
		bb_onb_where_q = "Where should we help?",
		bb_onb_where_s = "The window always opens with its key, these work by themselves",
		bb_onb_shop = "Shop panel",
		bb_onb_shop_s = "Our build next to the shop instead of Dota's guide",
		bb_onb_auto = "Draft hints",
		bb_onb_auto_s = "Who to pick shows up by itself during picks",
		bb_onb_back = "Back",
		bb_onb_next = "Next",
		bb_onb_finish = "Done",
		bb_onb_done = "All set",
		bb_onb_change = "You can change it in the gear",
		bb_onb_go = "Let's go",
		bb_onb_shop_on = "Shop panel",
		bb_onb_shop_off = "No shop panel",
		bb_chance_title = "Win chance",
		bb_top = "Top",
		bb_set_scale = "Window size",
		bb_upd_title = "Updates",
		bb_set_update = "Update automatically",
		bb_upd_idle = "Checks GitHub on start and every hour",
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
		bb_tab_party = "Party",
		bb_lfg_new = "+ Create party",
		bb_lfg_join = "Join",
		bb_lfg_rank_no = "not your rank",
		bb_lfg_my_rank = "Only my rank",
		bb_lfg_mode_0 = "All Pick",
		bb_lfg_mode_1 = "Ranked",
		bb_lfg_mode_2 = "Turbo",
		bb_lfg_mode_3 = "Single Draft",
		bb_lfg_want = "Looking for:",
		bb_lfg_any = "any role",
		bb_lfg_anyone = "Anyone",
		bb_lfg_closed_full = "The party is full, it is off the list",
		bb_lfg_closed_leave = "You left the party, it is off the list",
		bb_lfg_closed_find = "You started a search, the party is off the list",
		bb_lfg_joined_chat = "Build Brain: %s is joining your party",
		bb_lfg_extend = "+10 min",
		bb_lfg_range_all = "Lets everyone in",
		bb_lfg_range_one = "Lets in: %s only",
		bb_lfg_range = "Lets in: %s to %s",
		bb_lfg_f_lang = "Language",
		bb_lfg_we = "need %s",
		bb_lfg_they = "looking for %s",
		bb_lfg_empty = "No open parties right now",
		bb_lfg_form = "New party",
		bb_lfg_f_mode = "Mode",
		bb_lfg_f_roles = "Roles you need",
		bb_lfg_f_rank = "Who can join by rank",
		bb_lfg_spread_0 = "Close",
		bb_lfg_spread_1 = "Wider",
		bb_lfg_spread_2 = "Any",
		bb_lfg_auto = "Accept by myself",
		bb_lfg_create = "Create",
		bb_lfg_mine = "Your party",
		bb_lfg_left = "%d min left",
		bb_lfg_close = "Cancel",
		bb_lfg_asks = "%s wants in",
		bb_lfg_yes = "Accept",
		bb_lfg_no = "No",
		bb_lfg_wait = "Waiting for an invite from %s",
		bb_lfg_in = "Invite accepted, you are in the party",
		bb_lfg_declined = "The host declined",
		bb_lfg_gone = "The party is gone",
		bb_lfg_err_full = "The party is full",
		bb_lfg_err_rank = "Your rank does not fit this party",
		bb_lfg_err_busy = "You are already waiting to join a party",
		bb_lfg_err_net = "No connection to the party server",
		bb_lfg_consent_title = "Find a teammate",
		bb_lfg_consent = "When on, the script sends your Steam ID, nickname, rank and roles to our party server. Players with Build Brain see your party and can join it in one click.",
		bb_lfg_enable = "Turn on",
		bb_lfg_pick_role = "Pick at least one role",
		bb_lfg_norank = "Uncalibrated",
		bb_medal_1 = "Herald",
		bb_medal_2 = "Guardian",
		bb_medal_3 = "Crusader",
		bb_medal_4 = "Archon",
		bb_medal_5 = "Legend",
		bb_medal_6 = "Ancient",
		bb_medal_7 = "Divine",
		bb_medal_8 = "Immortal",
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
		bb_best_loading = "Loading data...",
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
		bb_gold_of = "%d of %d",
		bb_why_popular = "Popular on this hero at this stage",
		bb_why_magic = "%d%% of damage to you is magic",
		bb_why_control = "%.0f s disabled per death",
		bb_why_disablers = "%d disablers in their draft",
		bb_why_item = "%s has %s",
		bb_why_invis = "%s goes invisible",
		bb_fight_title = "Damage from enemy heroes",
		bb_fight_hint = "this game",
		bb_fight_hint_death = "before death",
		bb_fight_match = "Game",
		bb_fight_death = "Last death",
		bb_fight_death_n = "Death %d, %s, last 15 s",
		bb_fight_sec = "%d s ago",
		bb_fight_min = "%d min ago",
		bb_fight_empty = "No damage taken yet",
		bb_magic = "magic",
		bb_phys = "physical",
		bb_pure = "pure",
		bb_control = "disabled",
		bb_deaths = "deaths",
		bb_enemies = "Enemy items",
		bb_enemies_hint = "seen on them",
		bb_enemies_empty = "No enemies seen yet",
		bb_set_rank = "Rank for hero win rates",
		bb_set_role = "Your role",
		bb_set_auto = "Open on hero pick",
		bb_set_autobuy = "Auto-buy",
		bb_ab_0 = "Off",
		bb_ab_1 = "Starting items",
		bb_ab_2 = "Whole game",
		bb_ab_part = "%s for %s",
		bb_ab_done = "%s is complete",
		bb_ab_full = "no free slot, waiting",
		bb_ab_fail = "could not buy %s, trying again in 30 s",
		bb_ab_tag = "Auto-buy:",
		bb_ab_start = "starting items bought, %d for %d gold",
		bb_on = "on",
		bb_off = "off",
		bb_rank_0 = "All ranks",
		bb_rank_1 = "Herald+",
		bb_rank_2 = "Guardian+",
		bb_rank_3 = "Crusader+",
		bb_rank_4 = "Archon+",
		bb_rank_5 = "Legend+",
		bb_rank_6 = "Ancient+",
		bb_rank_7 = "Divine+",
		bb_rank_8 = "Immortal",
		bb_role_0 = "auto",
		bb_role_1 = "carry",
		bb_role_2 = "mid",
		bb_role_3 = "offlane",
		bb_role_4 = "soft support",
		bb_role_5 = "hard support",
		bb_role_45 = "support",
		bb_status_ready = "Ready",
		bb_status_wait = "Waiting for the draft",
		bb_status_loading = "Loading OpenDota stats",
		bb_status_offline = "OpenDota is not answering, draft uses STRATZ data",
		bb_status_quick = "Quick buy: %s",
		bb_rc_from = "Built from",
		bb_rc_into = "Builds into",
		bb_rc_whole = "Bought as is, no parts",
		bb_rc_hint = "Right click buys, drag to quick buy",
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
		bb_shop_core = "ОСНОВНЫЕ ПРЕДМЕТЫ",
		bb_shop_sit = "ЕЩЁ БЕРУТ",
		bb_shop_vs = "ПРОТИВ ВРАГОВ",
		bb_vs_brk = "сильные пассивки, их надо отключать",
		bb_vs_eva = "уклонение, нужна точность по атаке",
		bb_vs_heal = "много лечения, его надо резать",
		bb_vs_inv = "уходит в невидимость",
		bb_vs_vision = "топы берут в %.1f раза чаще",
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
		bb_how_crellas_crozier = "аура режет лечение врагов рядом",
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
		bb_how_orb_of_corrosion = "атаки немного режут лечение, броню и скорость врага",
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
		bb_pick_meta = "мета, %d%% побед на этой роли",
		bb_pk_pick = "Пикнуть",
		bb_mate_title = "Тиммейтам",
		bb_mate_free = "свободная роль",
		bb_mate_name = "Тиммейт",
		bb_pick_own = "твой герой",
		bb_scout_title = "Враги играют (30 дней)",
		bb_scout_hint = "рамка: много игр и высокий винрейт, стоит банить",
		bb_foe_title = "Кого опасаться",
		bb_next_usual = "обычно берут на %d мин · %d%% игр",
		bb_route_title = "Маршрут",
		bb_ld_builds = "Сборки героев",
		bb_ld_vs = "Матчапы против врагов",
		bb_ld_wr = "Винрейты героев",
		bb_ld_picks = "Подбираем героев под тебя",
		bb_ld_wait = "Ждём пики врагов",
		bb_ld_offline = "Нет связи, работаем на сохранённых сборках от %s",
		bb_pool_title = "Мои герои",
		bb_pool_all = "все герои",
		bb_pool_count = "героев: %d",
		bb_pool_pick = "Выбрать",
		bb_pool_clear = "Очистить",
		bb_pool_done = "Готово",
		bb_pool_hint = "Драфт покажет 2 лучших героя из этого списка и лучшие пики меты.",
		bb_attr_str = "Сила",
		bb_attr_agi = "Ловкость",
		bb_attr_int = "Интеллект",
		bb_attr_all = "Универсальные",
		bb_onb_heroes_q = "На ком играешь?",
		bb_onb_heroes_s = "Отметь своих героев, драфт будет предлагать их. Никого не отметишь, предложим всех",
		bb_next_share = "берут в %d%% игр",
		bb_card_usual = "Берут в %d%% игр, обычно на %d мин",
		bb_card_cost = "%d золота",
		bb_card_skip = "Пропустить",
		bb_card_back = "Вернуть",
		bb_card_replace = "Заменить ▾",
		bb_card_none = "Заменить нечем",
		bb_card_alts = "Вместо него на этой роли берут",
		bb_card_share = "%d%% игр",
		bb_card_always = "Запомнить для этого героя",
		bb_card_from = "Вместо %s",
		bb_card_skipped = "пропуск",
		bb_eta = "~%d мин",
		bb_set_mode = "Режим игры",
		bb_mode_0 = "обычные игры",
		bb_mode_1 = "Турбо",
		bb_mode_2 = "оба режима",
		bb_set_style = "Стиль",
		bb_style_0 = "Табло",
		bb_style_1 = "Тишина",
		bb_style_2 = "Золото",
		bb_style_3 = "Рубин",
		bb_need = "не хватает %s",
		bb_enough = "Хватает золота",
		bb_tl_hint = "предмет стоит на минуте, когда его обычно покупают",
		bb_tl_hint_turbo = "минута при твоём доходе",
		bb_status_link = "Открываю в браузере",
		bb_vs_route = "против %s у %s",
		bb_menu_tg = "Telegram канал",
		bb_onb_hello = "Давай настроим всё под тебя",
		bb_news_head = "Build Brain %s",
		bb_news_title = "Что нового",
		bb_news_sub = "Исправили по вашим отзывам",
		bb_news_13 = "Советы пиков тиммейтам: клик по герою предлагает его команде",
		bb_news_16 = "Ctrl или Shift + ЛКМ в лавке кидает предмет в квикбай",
		bb_news_17 = "Ранг для винрейта теперь с плюсом: Властелин+, Божество+",
		bb_news_18 = "Новая вкладка «Пати»: найди тиммейтов и зайди в пати в один клик",
		bb_news_19 = "Своя пати с аватарками, ролями и рангом, сама закрывается при поиске игры",
		bb_news_20 = "Автобай пишет в чат, если не смог что-то купить",
		bb_news_tg = "Telegram канал",
		bb_news_ok = "Понятно",
		bb_news_note = "Новости, тестовые версии и розыгрыши сначала там",
		bb_onb_start = "Начать",
		bb_onb_note = "Займёт 20 секунд, поменять можно в любой момент",
		bb_onb_skip = "Пропустить",
		bb_onb_step = "Шаг %d из 5",
		bb_onb_role_q = "На какой роли играешь?",
		bb_onb_role_s = "Подбираем героев и сборку под неё",
		bb_onb_r0 = "Разные",
		bb_onb_r1 = "Керри",
		bb_onb_r2 = "Мид",
		bb_onb_r3 = "Оффлейн",
		bb_onb_r4 = "Саппорт 4",
		bb_onb_r5 = "Саппорт 5",
		bb_onb_rs0 = "берём роль из лобби",
		bb_onb_rs1 = "лёгкая линия",
		bb_onb_rs2 = "центр",
		bb_onb_rs3 = "сложная линия",
		bb_onb_rs4 = "роумер",
		bb_onb_rs5 = "полный саппорт",
		bb_onb_lobby = "Роль из лобби",
		bb_onb_mode_q = "В каком режиме играешь чаще?",
		bb_onb_mode_s = "В Турбо предметы собирают в другое время",
		bb_onb_m0 = "Обычные игры",
		bb_onb_m1 = "Турбо",
		bb_onb_m2 = "И то и то",
		bb_onb_ms0 = "Рейтинг и обычный All Pick",
		bb_onb_ms1 = "Больше золота, предметы раньше",
		bb_onb_ms2 = "Режим смотрим в каждом матче",
		bb_onb_where_q = "Где подсказывать?",
		bb_onb_where_s = "Окно всегда открывается своей клавишей, а это работает само",
		bb_onb_shop = "Панель в магазине",
		bb_onb_shop_s = "Наша сборка вместо гайда Доты рядом с магазином",
		bb_onb_auto = "Подсказки на драфте",
		bb_onb_auto_s = "Кого пикнуть появляется само, пока идут пики",
		bb_onb_back = "Назад",
		bb_onb_next = "Дальше",
		bb_onb_finish = "Готово",
		bb_onb_done = "Готово",
		bb_onb_change = "Поменять можно в шестерёнке",
		bb_onb_go = "Поехали",
		bb_onb_shop_on = "Панель в магазине",
		bb_onb_shop_off = "Без панели в магазине",
		bb_chance_title = "Шанс на победу",
		bb_top = "Топ",
		bb_set_scale = "Размер окна",
		bb_upd_title = "Обновления",
		bb_set_update = "Обновлять автоматически",
		bb_upd_idle = "Проверяю GitHub при запуске и раз в час",
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
		bb_tab_party = "Пати",
		bb_lfg_new = "+ Создать пати",
		bb_lfg_join = "Зайти",
		bb_lfg_rank_no = "не твой ранг",
		bb_lfg_my_rank = "Только мой ранг",
		bb_lfg_mode_0 = "All Pick",
		bb_lfg_mode_1 = "Рейтинг",
		bb_lfg_mode_2 = "Турбо",
		bb_lfg_mode_3 = "Сингл драфт",
		bb_lfg_want = "Ищут:",
		bb_lfg_any = "любая роль",
		bb_lfg_anyone = "Любые",
		bb_lfg_closed_full = "Пати полная, она убрана из списка",
		bb_lfg_closed_leave = "Ты вышел из пати, она убрана из списка",
		bb_lfg_closed_find = "Ты начал поиск игры, пати убрана из списка",
		bb_lfg_joined_chat = "Build Brain: %s заходит к тебе в пати",
		bb_lfg_extend = "+10 мин",
		bb_lfg_range_all = "Пустим всех",
		bb_lfg_range_one = "Пустим только «%s»",
		bb_lfg_range = "Пустим: от «%s» до «%s»",
		bb_lfg_f_lang = "Язык",
		bb_lfg_we = "ищем %s",
		bb_lfg_they = "ищут %s",
		bb_lfg_empty = "Сейчас открытых пати нет",
		bb_lfg_form = "Новая пати",
		bb_lfg_f_mode = "Режим",
		bb_lfg_f_roles = "Кого ищу",
		bb_lfg_f_rank = "Кого пускать по рангу",
		bb_lfg_spread_0 = "Близкий",
		bb_lfg_spread_1 = "Пошире",
		bb_lfg_spread_2 = "Любой",
		bb_lfg_auto = "Принимать сам",
		bb_lfg_create = "Создать",
		bb_lfg_mine = "Твоя пати",
		bb_lfg_left = "ещё %d мин",
		bb_lfg_close = "Отменить",
		bb_lfg_asks = "%s хочет зайти",
		bb_lfg_yes = "Принять",
		bb_lfg_no = "Нет",
		bb_lfg_wait = "Ждём приглашение от %s",
		bb_lfg_in = "Приглашение принято, ты в пати",
		bb_lfg_declined = "Хост отказал",
		bb_lfg_gone = "Этой пати уже нет",
		bb_lfg_err_full = "Пати уже полная",
		bb_lfg_err_rank = "Твой ранг не подходит этой пати",
		bb_lfg_err_busy = "Ты уже ждёшь вход в другую пати",
		bb_lfg_err_net = "Нет связи с сервером пати",
		bb_lfg_consent_title = "Найти тиммейта",
		bb_lfg_consent = "Если включить, скрипт отправит на наш сервер пати твой Steam ID, ник, ранг и роли. Игроки с Build Brain увидят твою пати и смогут зайти в один клик.",
		bb_lfg_enable = "Включить",
		bb_lfg_pick_role = "Выбери хотя бы одну роль",
		bb_lfg_norank = "Калибровка",
		bb_medal_1 = "Рекрут",
		bb_medal_2 = "Страж",
		bb_medal_3 = "Рыцарь",
		bb_medal_4 = "Герой",
		bb_medal_5 = "Легенда",
		bb_medal_6 = "Властелин",
		bb_medal_7 = "Божество",
		bb_medal_8 = "Титан",
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
		bb_best_loading = "Загружаю данные...",
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
		bb_gold_of = "%d из %d",
		bb_why_popular = "Популярно на этом герое на этой стадии",
		bb_why_magic = "%d%% урона по тебе магия",
		bb_why_control = "%.0f с в контроле за смерть",
		bb_why_disablers = "%d героя с контролем у них",
		bb_why_item = "у %s есть %s",
		bb_why_invis = "%s уходит в инвиз",
		bb_fight_title = "Урон от вражеских героев",
		bb_fight_hint = "за игру",
		bb_fight_hint_death = "перед смертью",
		bb_fight_match = "Игра",
		bb_fight_death = "Смерть",
		bb_fight_death_n = "Смерть %d, %s, последние 15 с",
		bb_fight_sec = "%d с назад",
		bb_fight_min = "%d мин назад",
		bb_fight_empty = "Урона по тебе пока не было",
		bb_magic = "магия",
		bb_phys = "физический",
		bb_pure = "чистый",
		bb_control = "в контроле",
		bb_deaths = "смертей",
		bb_enemies = "Предметы врагов",
		bb_enemies_hint = "что на них видели",
		bb_enemies_empty = "Врагов пока не видели",
		bb_set_rank = "Ранг для винрейта героев",
		bb_set_role = "Твоя роль",
		bb_set_auto = "Открывать на пиках",
		bb_set_autobuy = "Автобай",
		bb_ab_0 = "Выкл",
		bb_ab_1 = "Только старт",
		bb_ab_2 = "Вся игра",
		bb_ab_part = "%s для %s",
		bb_ab_done = "%s собран",
		bb_ab_full = "нет свободного слота, жду",
		bb_ab_fail = "не получилось купить %s, попробую через 30 с",
		bb_ab_tag = "Автобай:",
		bb_ab_start = "стартовый закуп куплен, %d шт. за %d золота",
		bb_on = "вкл",
		bb_off = "выкл",
		bb_rank_0 = "Все ранги",
		bb_rank_1 = "Рекрут+",
		bb_rank_2 = "Страж+",
		bb_rank_3 = "Рыцарь+",
		bb_rank_4 = "Герой+",
		bb_rank_5 = "Легенда+",
		bb_rank_6 = "Властелин+",
		bb_rank_7 = "Божество+",
		bb_rank_8 = "Титан",
		bb_role_0 = "авто",
		bb_role_1 = "керри",
		bb_role_2 = "мид",
		bb_role_3 = "оффлейн",
		bb_role_4 = "саппорт 4",
		bb_role_5 = "саппорт 5",
		bb_role_45 = "саппорт",
		bb_status_ready = "Готово",
		bb_status_wait = "Жду драфт",
		bb_status_loading = "Загружаю статистику OpenDota",
		bb_status_offline = "OpenDota не отвечает, драфт по данным STRATZ",
		bb_status_quick = "В квикбай: %s",
		bb_rc_from = "Собирается из",
		bb_rc_into = "Входит в",
		bb_rc_whole = "Покупается целиком",
		bb_rc_hint = "ПКМ купить, перетащи в квикбай",
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

local LINK = {}

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

	ui.tg = g_main:Button("bb_menu_tg", function() LINK.open("tg") end)
	ui.tg:Icon("\u{f1d8}")
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
	POS_PRIOR = 2000,
	POS_BITS = { 1, 4, 2, 8, 16 },
	WIN_W = 940,
	WIN_H = 660,
	TAB_ICONS = { draft = "\u{f0c0}", build = "\u{f6e3}", fight = "\u{f05b}", settings = "\u{f013}" },
	LOGO = "\u{f5dc}",
	CLOSE = "\u{f00d}",
	ICON_OPEN = "\u{f2d0}",
	ICON_FLAG = "\u{f024}",
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
	MIRRORS = {
		"https://raw.githubusercontent.com/BraVoEw/Scripts-Umbrella/%s/%s",
		"https://gcore.jsdelivr.net/gh/BraVoEw/Scripts-Umbrella@%s/%s",
		"https://fastly.jsdelivr.net/gh/BraVoEw/Scripts-Umbrella@%s/%s",
		"https://cdn.jsdelivr.net/gh/BraVoEw/Scripts-Umbrella@%s/%s",
	},
	SZ_CHECK = 3600,
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
	SHOP_SETTLE = 1.5,
	MORE_MAX = 12,
	ATTRS = {
		{ "STRENGTH", "bb_attr_str", Color(236, 92, 76) },
		{ "AGILITY", "bb_attr_agi", Color(76, 200, 120) },
		{ "INTELLECT", "bb_attr_int", Color(80, 160, 245) },
		{ "ALL", "bb_attr_all", Color(176, 128, 236) },
	},
	INCOME_BLEND = 180,
	ONB_ROLES = { 1, 2, 3, 4, 5, 0 },
	ONB_MODE_ICONS = { "\u{f132}", "\u{f0e7}", "\u{f021}" },
	ONB_CHECK = "\u{f00c}",
	GUIDE_W = 210,
	GUIDE_PLUS_W = 540,
	SHOP_GROW = 1.45,
	SHOP_MIN = 0.8,
	VS_MAX = 6,
	VS_STEP = 0.5,
	START_MAX = 5,
	GPM_DEFAULT = { 600, 620, 520, 380, 320 },
	IDENTIFIER = "build_brain",
	VERSION = "2.3.0",
	STYLES = { { 255, 90, 44, 0 }, { 242, 242, 242, 0 }, { 217, 180, 95, 0 }, { 229, 72, 77, 1 } },
	LINKS = { tg = "https://t.me/+JYe25eMFs7tkYjky" },
	NEWS = { "bb_news_18", "bb_news_19", "bb_news_20", "bb_news_13", "bb_news_16", "bb_news_17" },
	NEWS_W = 420,
	CHAT_BAN_TTL = 900,
	VISION = { "item_dust", "item_ward_sentry", "item_ward_observer" },
	FIGHT_TABS = { { "death", "bb_fight_death" }, { "match", "bb_fight_match" } },
	RECAP_WIN = 15,
	RECAP_MAX = 400,
	RECAP_LAG = 0.5,
	META_GAMES = 200,
	PK_SEL = 8,
	LFG_URL = "https://bb-party.bravoyt11.workers.dev",
	LFG_LIST = 10,
	LFG_HOST = 3,
	LFG_HOST_IDLE = 6,
	LFG_JOIN = 2,
	LFG_WAIT = 120,
	LFG_TTL = 600,
	LFG_MSG = 6,
	LFG_SPREAD = { 1, 2, 99 },
	LFG_LANGS = { "ru", "en" },
	LFG_ROW = 68,
	LFG_AV_STEP = 1,
	LFG_AV_RETRY = 10,
	LFG_AV_BATCH = 10,
	LFG_AV_MIN = 100,
	LFG_TINTS = { Color(59, 91, 219), Color(194, 65, 12), Color(15, 118, 110), Color(109, 40, 217), Color(161, 98, 7), Color(190, 24, 93) },
	MSG_INVITE = 4501,
	MSG_CREATED = 4502,
	MSG_ACCEPT = 4503,
	MSG_LEAVE = 4505,
	MSG_FIND = 7033,
	LFG_EXTEND_AT = 180,
	MSG_CARD = 7534,
	MSG_CARD_REPLY = 7535,
	MATE_HEROES = 3,
	META_W = 0.5,
	TAL_REACH = { 0.92, 0.74, 0.44 },
	SUGGEST = "suggest_hero_pick %s 0",
	SUGGEST_GAP = 1.5,
	SUGGEST_MAX = 2,
	POOL_SHOW = 2,
	STEAM_BASE = 76561197960265728,
	SCOUT_DAYS = 30,
	SCOUT_MIN = 3,
	SCOUT_BAN_G = 8,
	SCOUT_BAN_WR = 60,
	AB_DELAY = 1,
	AB_LATE = 30,
	AB_STEP = 0.5,
	AB_WAIT = 1.5,
	AB_GAP = 0.3,
	AB_JIT = 0.4,
	AB_HOLD = 30,
	AB_FAIL = 30,
	AB_MINE = 6,
	RC_W = 252,
	QB_DELAY = 3,
	QB_MAX = 8,
	QB_KEYS = { Enum.ButtonCode.KEY_LCONTROL, Enum.ButtonCode.KEY_RCONTROL, Enum.ButtonCode.KEY_LSHIFT, Enum.ButtonCode.KEY_RSHIFT },
	NEWS_BLUR = 1.5,
	TG_ICON = "\u{f1d8}",
	BUY_MIN = 3,
	GRID_OFF = { "Banned", "AlreadyPicked", "Unavailable" },
	UPD_NAME = "build_brain.lua",
	UPD_EVERY = 3600,
	UPD_RETRY = 600,
	UPD_MIN = 100000,
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
		{ tag = "heal", items = { "item_spirit_vessel", "item_skadi", "item_crellas_crozier", "item_orb_of_corrosion" } },
		{ tag = "inv", items = { "item_dust", "item_ward_sentry" } },
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
	PASS_COST = 1500,
	PASS_LATE = 600,
	ITEM_COUNTERS = {
		item_abyssal_blade = { "item_sphere", "item_lotus_orb", "item_aeon_disk" },
		item_aeon_disk = { "item_nullifier", "item_disperser" },
		item_black_king_bar = { "item_abyssal_blade", "item_ghost", "item_force_staff" },
		item_blade_mail = { "item_black_king_bar" },
		item_bloodstone = { "item_spirit_vessel", "item_skadi", "item_crellas_crozier", "item_orb_of_corrosion" },
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
		item_guardian_greaves = { "item_spirit_vessel", "item_skadi", "item_crellas_crozier", "item_orb_of_corrosion" },
		item_gungir = { "item_manta", "item_cyclone", "item_black_king_bar" },
		item_heart = { "item_spirit_vessel", "item_skadi", "item_crellas_crozier", "item_orb_of_corrosion" },
		item_heavens_halberd = { "item_black_king_bar", "item_sphere", "item_lotus_orb" },
		item_holy_locket = { "item_spirit_vessel", "item_skadi", "item_crellas_crozier", "item_orb_of_corrosion" },
		item_hurricane_pike = { "item_sheepstick", "item_abyssal_blade", "item_harpoon" },
		item_invis_sword = { "item_dust", "item_ward_sentry" },
		item_lotus_orb = { "item_nullifier", "item_disperser" },
		item_manta = { "item_mjollnir", "item_bfury", "item_shivas_guard", "item_radiance" },
		item_monkey_king_bar = { "item_ghost", "item_heavens_halberd" },
		item_nullifier = { "item_sphere", "item_lotus_orb" },
		item_orchid = { "item_manta", "item_lotus_orb", "item_black_king_bar", "item_disperser" },
		item_refresher = { "item_black_king_bar", "item_aeon_disk" },
		item_rod_of_atos = { "item_manta", "item_cyclone", "item_black_king_bar", "item_disperser" },
		item_satanic = { "item_spirit_vessel", "item_skadi", "item_crellas_crozier", "item_heavens_halberd" },
		item_shadow_amulet = { "item_dust", "item_ward_sentry" },
		item_sheepstick = { "item_sphere", "item_lotus_orb", "item_black_king_bar" },
		item_silver_edge = { "item_dust", "item_ward_sentry" },
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
		item_crellas_crozier = "c",
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
	ANYONE = {
		item_dust = true,
		item_ward_sentry = true,
		item_ward_observer = true,
		item_gem = true,
	},
	UNIVERSAL = {
		item_dust = true,
		item_ward_sentry = true,
		item_ward_observer = true,
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
		{ key = "rank", title = "bb_set_rank", count = 9, default = 0, label = "bb_rank_", skip = { [1] = true } },
		{ key = "role", title = "bb_set_role", count = 6, default = 0, label = "bb_role_" },
		{ key = "mode", title = "bb_set_mode", count = 3, default = 0, label = "bb_mode_" },
		{ key = "auto", title = "bb_set_auto", count = 2, default = 1, flag = true },
		{ key = "shop", title = "bb_set_shop", count = 2, default = 1, flag = true },
		{ key = "autobuy", title = "bb_set_autobuy", count = 3, default = 0, label = "bb_ab_", right = true },
		{ key = "style", title = "bb_set_style", count = 4, default = 0, label = "bb_style_", right = true },
		{ key = "scale", title = "bb_set_scale", count = 5, default = 1, values = { 90, 100, 110, 120, 130 } },
		{ key = "update", title = "bb_set_update", count = 2, default = 1, flag = true, own = true },
	},
}

local C = {
	WHITE = Color(255, 255, 255),
	BG_TOP = Color(255, 255, 255, 10),
	BG_BOTTOM = Color(255, 255, 255, 0),
	EDGE = Color(255, 255, 255, 20),
	CARD = Color(29, 29, 32, 255),
	ACCENT = Color(229, 72, 77),
	BG_CLEAR = Color(22, 22, 24, 0),
	SHOP_DONE = Color(255, 255, 255, 120),
	DOT_DARK = Color(20, 22, 28),
	ROLE_DIM = Color(150, 156, 166),
	TAL_HOT = Color(48, 51, 60, 235),
	DOT_DARK2 = Color(18, 19, 23),
	LINE_FAINT = Color(255, 255, 255, 10),
	DRAG_TINT = Color(255, 255, 255, 215),
	SHADOW_SOFT = Color(0, 0, 0, 80),
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
	GOLD_HI = Color(245, 216, 154),
	GOLD_LO = Color(184, 137, 59),
	GOLD_CLEAR = Color(232, 195, 122, 0),
	GOLD_TEXT = Color(42, 28, 5),
	WIN = Color(52, 211, 153),
	LOSE = Color(251, 113, 133),
	MAGIC = Color(96, 165, 250),
	PHYS = Color(251, 146, 60),
	PURE = Color(245, 240, 230),
	SEG = Color(255, 255, 255, 13),
	SEG_ON = Color(255, 255, 255, 26),
	BADGE = Color(0, 0, 0, 165),
	EMPTY = Color(232, 195, 122, 16),
	EMPTY_EDGE = Color(232, 195, 122, 150),
	SHADOW = Color(0, 0, 0, 130),
	SHOP_BG = Color(13, 15, 19, 242),
	SHOP_TOP = Color(255, 255, 255, 8),
	TITLE = Color(226, 229, 234),
	PICKED = Color(232, 195, 122, 46),
	UNPICKED = Color(0, 0, 0, 110),
	TIP = Color(32, 32, 36, 252),
	TOGGLE_ON = Color(201, 154, 69),
}

local fonts = {
	w500 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.MEDIUM),
	w600 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.SEMIBOLD),
	w700 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.BOLD),
	w800 = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.EXTRABOLD),
	icon = Render.LoadFont("FontAwesomeEx", Enum.FontCreate.FONTFLAG_ANTIALIAS, 400),
}

do
	local function bahn(weight, fallback)
		local ok, f = pcall(Render.LoadFont, "Bahnschrift", Enum.FontCreate.FONTFLAG_ANTIALIAS, weight)
		if ok and f and f ~= 0 then return f end
		return fallback
	end
	fonts.d500 = bahn(Enum.FontWeight.MEDIUM, fonts.w500)
	fonts.d600 = bahn(Enum.FontWeight.SEMIBOLD, fonts.w600)
	fonts.d700 = bahn(Enum.FontWeight.BOLD, fonts.w700)
end

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
	edits = {},
	net = { busy = false, queue = {}, queued = {}, failed = {}, offline = false },
	draft = { ours = {}, theirs = {}, bans = {}, my_team = nil, my_hero = nil, my_pos = nil, sig = "", phase = false },
	chat_bans = {},
	qb_pending = {},
	qb_at = nil,
	ab = { done = false, at = nil },
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
	return { phys = 0, mag = 0, pure = 0, src = {}, ctrl = 0, deaths = 0, alive = true, next_state = 0, first = false, log = {}, last = nil }
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
		local short = short_name(name)
		path = "panorama/images/items/" .. (short:find("^recipe_") and "recipe" or short) .. "_png.vtex_c"
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
				cat.by_name[name] = { id = id, cost = tonumber(entry.ItemCost) or 0, recipe = entry.ItemRecipe == "1", gone = entry.ItemPurchasable == "0" or entry.IsObsolete == "1", stack = entry.ItemStackable == "1" }
				cat.by_id[id] = name
			end
		end
	end
	for name, entry in pairs(root) do
		if type(entry) == "table" and entry.ItemRecipe == "1" and type(entry.ItemResult) == "string" then
			local reqs = type(entry.ItemRequirements) == "table" and entry.ItemRequirements or K.NONE
			local req = reqs["01"] or reqs["02"] or reqs["03"]
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
	if not row then
		local wr = state.sz_wr and state.sz_wr[id]
		return wr and logit(wr) or 0
	end
	local rank = setting("rank")
	local picks, wins = 0, 0
	for b = 1, 8 do
		if b >= rank then
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

local function valid_hero(id)
	local unit = id and id > 0 and hero_unit(id)
	return type(unit) == "string" and unit:find("^npc_dota_hero_") ~= nil
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
	local my_pos, my_flags = nil, 0
	for _, p in ipairs(Players.GetAll()) do
		local team = team_of(p)
		if team == 2 or team == 3 then
			local ok, data = pcall(Player.GetTeamData, p)
			data = ok and type(data) == "table" and data or {}
			local id = math.tointeger(tonumber(data.selected_hero_id) or 0) or 0
			if not valid_hero(id) then id = 0 end
			if id <= 0 then
				local ok_hero, hero = pcall(Player.GetAssignedHero, p)
				id = ok_hero and hero and hero_id(NPC.GetUnitName(hero)) or 0
			end
			local okslot, slot = pcall(Player.GetPlayerTeamSlot, p)
			local flags = math.tointeger(tonumber(data.lane_selection_flags) or 0) or 0
			local pos = K.LANE_BITS[flags]
			local entry = { id = id > 0 and id or nil, slot = okslot and slot or 9, me = Player.GetPlayerID(p) == my_id, pos = pos, flags = flags }
			local okd, pd = pcall(Player.GetPlayerData, p)
			pd = okd and type(pd) == "table" and pd or K.NONE
			local raw = pd.steamid
			local sid = math.type(raw) == "integer" and raw or (type(raw) == "string" and math.tointeger(tonumber(raw) or 0)) or 0
			if sid > K.STEAM_BASE and not pd.fakeClient then entry.acc = sid - K.STEAM_BASE end
			entry.pname = type(pd.PlayerName) == "string" and pd.PlayerName or nil
			if entry.me then my_pos, my_flags = pos, flags end
			if team == my_team then ours[#ours + 1] = entry else theirs[#theirs + 1] = entry end
		end
	end
	table.sort(ours, function(a, b) return a.slot < b.slot end)
	table.sort(theirs, function(a, b) return a.slot < b.slot end)
	local bans = {}
	local okb, list = pcall(GameRules.GetBannedHeroes)
	if okb and type(list) == "table" then
		for _, id in pairs(list) do
			local bid = math.tointeger(tonumber(id) or 0) or 0
			if valid_hero(bid) then bans[#bans + 1] = bid end
		end
	end
	for bid, at in pairs(state.chat_bans) do
		if state.clock - at > K.CHAT_BAN_TTL then
			state.chat_bans[bid] = nil
		else
			local dup = false
			for _, b in ipairs(bans) do
				if b == bid then dup = true end
			end
			if not dup then bans[#bans + 1] = bid end
		end
	end
	table.sort(bans)
	local my_hero = nil
	for _, e in ipairs(ours) do
		if e.me then my_hero = e.id end
	end
	local game_state = GameRules.GetGameState()
	d.ours, d.theirs, d.bans, d.my_team, d.my_hero, d.my_pos, d.my_flags = ours, theirs, bans, my_team, my_hero, my_pos, my_flags
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
	for _, e in ipairs(ours) do parts[#parts + 1] = tostring(e.id) .. ":" .. tostring(e.pos) .. ":" .. tostring(e.flags) end
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
		return sh.main == pos or n / sh.total >= K.ROLE_SHARE or (pos >= 4 and sh.main >= 4)
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
	state.sz_has_vs = state.sz_text:find("\nV\t", 1, true) ~= nil
	state.sz_date = tonumber(state.sz_text:match("^BB1\t[^\t\n]+\t(%d+)") or "")
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
		local n, wr, total, from, main = {}, {}, 0, e + 1, nil
		while true do
			local p1, p2, pos, count = text:find('"([1-5])":{"n":(%d+)', from)
			if not p1 or p1 > stop then break end
			local v, p = tonumber(count) or 0, tonumber(pos)
			n[p] = v
			local g, w = text:match('^,"g":(%d+),"w":(%d+)', p2 + 1)
			if g then wr[p] = { g = tonumber(g), w = tonumber(w) } end
			total = total + v
			out.total[p] = (out.total[p] or 0) + v
			if not main or v > n[main] then main = p end
			from = p2 + 1
		end
		if total > 0 then out.heroes[tonumber(id)] = { n = n, wr = wr, total = total, main = main } end
		at = stop
	end
	state.sz_pos = out
	return out
end

local function pos_logit(id, pos, shares)
	local sh = shares and shares.heroes[id]
	local r = sh and sh.wr[pos]
	if not r or r.g <= 0 then return base_logit(id) end
	return logit((r.w + K.POS_PRIOR * 0.5) / (r.g + K.POS_PRIOR))
end

local function draft_positions(ours)
	local role = setting("role")
	if role > 0 then return { role }, role end
	local d = state.draft
	if d.my_pos then return { d.my_pos }, d.my_pos end
	local shares = sz_shares()
	local used = {}
	for _, e in ipairs(ours) do
		local sh = e.id and not e.me and shares and shares.heroes[e.id]
		local p = e.id and not e.me and (e.pos or (sh and sh.main))
		if p then used[p] = true end
	end
	local flags = d.my_flags or 0
	local wanted, open = {}, {}
	for p = 1, 5 do
		local ok = flags == 0 or flags & K.POS_BITS[p] ~= 0
		if ok and flags ~= 0 then wanted[#wanted + 1] = p end
		if ok and not used[p] then open[#open + 1] = p end
	end
	local list = #open > 0 and open or #wanted > 0 and wanted or { 1, 2, 3, 4, 5 }
	if #list == 1 then return list, list[1] end
	if #list == 2 and list[1] == 4 and list[2] == 5 then return list, 45 end
	return list, 0
end

local function sz_vision()
	if state.sz_vis ~= nil then return state.sz_vis or nil end
	local text = sz_file()
	if not text then return nil end
	local out, any = {}, false
	for item, group, base, list in text:gmatch("\nE\t(item_[%w_]+)\t(%d)\t(%d+)\t([^\n]*)") do
		local foes = {}
		for id, lift in list:gmatch("(%d+):(%d+)") do foes[tonumber(id)] = tonumber(lift) end
		out[item] = out[item] or {}
		out[item][tonumber(group)] = { base = tonumber(base), foes = foes }
		any = true
	end
	state.sz_vis = any and out or false
	return state.sz_vis or nil
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

local function sz_wr()
	if state.sz_wr then return state.sz_wr end
	local text = sz_file()
	if not text then return nil end
	local map = {}
	for id, v in (text:match("\nW\t([^\n]+)") or ""):gmatch("(%d+):(%d+)") do map[tonumber(id)] = tonumber(v) / 1000 end
	state.sz_wr = map
	return map
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
	table.sort(route, function(p, q) return p.tm < q.tm end)
	for _, r in ipairs(e.sit or {}) do
		if cat.by_name[r[1]] then pop[#pop + 1] = { name = r[1], share = (r[2] or 0) / 100 } end
	end
	if #route == 0 then return nil end
	local buy = nil
	if type(e.buy) == "string" then
		for iid, pct in e.buy:gmatch("(%d+):(%d+)") do
			local name = cat.by_id[tonumber(iid)]
			if name then
				buy = buy or {}
				buy[name] = tonumber(pct)
			end
		end
	end
	local counts = {}
	for k, v in pairs(e.talents or {}) do counts[tonumber(k) or k] = v end
	return { start = start, route = route, pop = pop, buy = buy, pos = shown, n = e.n or 0, src = "sz", skills = e.skills or {}, data = { n = e.n or 0, counts = counts } }
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

local function carried(hero, fn, last)
	if not hero then return end
	for slot = 0, last or 16 do
		local item = NPC.GetItemByIndex(hero, slot)
		local name = item and Ability.GetName(item)
		if name then fn(item, name) end
	end
	local okc, courier = pcall(Couriers.GetLocal)
	if not okc or not courier then return end
	for slot = 0, 8 do
		local oki, item = pcall(NPC.GetItemByIndex, courier, slot)
		local name = oki and item and Ability.GetName(item)
		if name then fn(item, name) end
	end
end

local function owned_items(hero)
	local owned = {}
	carried(hero, function(_, name) owned[name] = (owned[name] or 0) + 1 end)
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
	local buy = role and role.buy
	local function fits(name)
		if buy and not K.ANYONE[name] then return have[name] == true or (buy[name] or 0) >= K.BUY_MIN end
		local who = K.ROLE_ITEMS[name] or "a"
		return who == "a" or (who == "s") == support
	end
	local function options(list)
		local out = {}
		for pass = 1, 2 do
			for _, name in ipairs(list) do
				local entry = load_catalog().by_name[name]
				if entry and not entry.gone and fits(name) and (have[name] == true) == (pass == 1) then out[#out + 1] = name end
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
	local function threat(units, text, reason, opts, rank, live, foe_item)
		local avail = {}
		for _, name in ipairs(opts) do
			if not is_owned(name, owned) then avail[#avail + 1] = name end
		end
		if #avail == 0 then return end
		rows[#rows + 1] = { units = units, text = text, options = avail, how = how(avail[1]), rank = rank, live = live, foe_item = foe_item, foe_unit = foe_item and units[1] or nil }
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
			if buy or have[name] or K.UNIVERSAL[name] then
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
				threat({ unit }, hero_title(unit) .. ": " .. reason, reason, options(counters), 1, nil, item)
			end
		end
	end
	local vis = sz_vision()
	local covered = {}
	if vis then
		local group = support and 2 or 1
		for _, item in ipairs(K.VISION) do
			local row = vis[item] and vis[item][group]
			local units, best = {}, 0
			for _, unit in ipairs(row and foes or K.NONE) do
				local lift = row.foes[hero_id(unit)]
				if lift then
					units[#units + 1] = unit
					covered[unit] = true
					best = math.max(best, lift)
				end
			end
			if #units > 0 then
				local names = {}
				for k, unit in ipairs(units) do
					if k <= 2 then names[#names + 1] = hero_title(unit) end
				end
				local who = table.concat(names, ", ") .. (#units > 2 and (" +" .. (#units - 2)) or "")
				local reason = string.format(L("bb_vs_vision"), best / 100)
				threat(units, who .. ": " .. reason, reason, options({ item }), 1)
			end
		end
	end
	for r, rule in ipairs(K.RULES) do
		local units = {}
		for _, unit in ipairs(foes) do
			local short = unit:gsub("^npc_dota_hero_", "")
			local skip = rule.tag == "inv" and covered[unit]
			if not skip and (" " .. (K.FOE_TAGS[short] or "") .. " "):find(" " .. rule.tag .. " ", 1, true) then units[#units + 1] = unit end
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
	local t = GameRules.GetDOTATime() or 0
	local base = K.GPM_DEFAULT[my_position()] or 500
	if player and t > 30 then
		local ok, data = pcall(Player.GetTeamPlayer, player)
		local earned = ok and data and tonumber(data.totalearned_gold) or 0
		if earned > 0 then
			local b = math.min(1, t / K.INCOME_BLEND)
			return base * (1 - b) + earned / (t / 60) * b
		end
	end
	return base
end

local EDIT = {}

function EDIT.get(id)
	if not id then return nil end
	local ed = state.edits[id]
	if ed then return ed end
	ed = { skip = {}, repl = {}, share = {}, always = false }
	local raw = Config.ReadString(K.CONFIG, "ed_" .. id, "")
	if raw ~= "" then
		ed.always = true
		for kind, a, b in raw:gmatch("([sr]):([%w_]+)>?([%w_]*)") do
			if kind == "s" then
				ed.skip[a] = true
			elseif b ~= "" then
				ed.repl[a] = b
			end
		end
	end
	state.edits[id] = ed
	return ed
end

function EDIT.save(id)
	local ed = state.edits[id]
	if not ed then return end
	if not ed.always then
		Config.WriteString(K.CONFIG, "ed_" .. id, "")
		return
	end
	local parts = {}
	for name in pairs(ed.skip) do parts[#parts + 1] = "s:" .. name end
	for a, b in pairs(ed.repl) do parts[#parts + 1] = "r:" .. a .. ">" .. b end
	table.sort(parts)
	Config.WriteString(K.CONFIG, "ed_" .. id, #parts > 0 and table.concat(parts, ",") or "-")
end

function EDIT.apply(route, id)
	local ed = EDIT.get(id)
	if not ed or (next(ed.skip) == nil and next(ed.repl) == nil) then return route end
	local seen, out = {}, {}
	for _, step in ipairs(route) do seen[step.name] = true end
	for _, step in ipairs(route) do
		local alt = ed.repl[step.name]
		if alt and not seen[alt] then
			out[#out + 1] = { name = alt, stage = step.stage, tm = step.tm, early = step.early, share = ed.share[alt], from = step.name,
				reason = string.format(L("bb_card_from"), item_title(step.name)), skipped = ed.skip[alt] or nil }
		else
			step.skipped = ed.skip[step.name] or nil
			out[#out + 1] = step
		end
	end
	return out
end

function EDIT.alts(name, view)
	local role = view and view.role
	if not role then return K.NONE end
	local cost = item_cost(name)
	local boots = K.BOOTS[name] ~= nil
	local used, cand = {}, {}
	for _, step in ipairs(view.route or K.NONE) do used[step.name] = true end
	local function add(n, share)
		if used[n] or n == name or K.SKIP[n] or (K.BOOTS[n] ~= nil) ~= boots then return end
		local c = item_cost(n)
		if c < cost * 0.4 or c > cost * 2.5 then return end
		local e = cand[n]
		if e then
			e.share = math.max(e.share, share)
		else
			cand[n] = { name = n, share = share }
		end
	end
	for _, c in ipairs(role.pop or K.NONE) do add(c.name, c.share or 0) end
	for n, pct in pairs(role.buy or K.NONE) do add(n, pct / 100) end
	local list = {}
	for _, e in pairs(cand) do list[#list + 1] = e end
	table.sort(list, function(a, b) return a.share > b.share end)
	while #list > 3 do table.remove(list) end
	return list
end

function EDIT.act(id, orig, name, kind, alt)
	local ed = EDIT.get(id)
	if not ed then return end
	if kind == "skip" then
		ed.skip[name] = true
	elseif kind == "back" then
		ed.skip[name] = nil
		ed.repl[orig] = nil
	elseif kind == "alt" and alt then
		ed.repl[orig] = alt.name
		ed.skip[orig] = nil
		ed.share[alt.name] = alt.share
	elseif kind == "always" then
		ed.always = not ed.always
	end
	EDIT.save(id)
	state.next_model = 0
end

local function route_adjust(route, owned, rows)
	local out = {}
	for i, step in ipairs(route) do
		step.done = is_owned(step.name, owned)
		step.cost = item_cost(step.name)
		step.passed, step.counter, step.vs_reason = nil, nil, nil
		out[i] = step
	end
	local t = math.max(0, GameRules.GetDOTATime() or 0)
	local later = false
	for i = #out, 1, -1 do
		local step = out[i]
		if not step.done and not step.skipped and step.cost <= K.PASS_COST and (later or (step.tm and step.tm > 0 and t > step.tm + K.PASS_LATE)) then step.passed = true end
		if step.done then later = true end
	end
	for _, row in ipairs(rows or K.NONE) do
		local name = row.foe_item and row.options[1]
		if name and row.foe_unit and not is_owned(name, owned) then
			local at, pos = nil, nil
			for i, step in ipairs(out) do
				if step.name == name then at = i end
				if not pos and not step.done and not step.skipped and not step.passed then pos = i end
			end
			local why = string.format(L("bb_vs_route"), item_title(row.foe_item), hero_title(row.foe_unit))
			local where = pos and pos + 1 or #out + 1
			local step
			if at and at <= where then
				step = out[at]
			else
				if at then
					step = table.remove(out, at)
				else
					step = { name = name, cost = item_cost(name), done = false, reason = why }
				end
				table.insert(out, math.min(where, #out + 1), step)
			end
			step.counter, step.vs_reason = true, why
			break
		end
	end
	return out
end

local function build_view(view)
	local d = state.draft
	local hero = Heroes.GetLocal()
	local id = d.my_hero or state.preview_hero or (view.best[1] and view.best[1].id)
	view.build_hero = id
	local start, route = base_route(id)
	local role = role_route(id)
	if role then start, route = role.start, role.route end
	if route then route = EDIT.apply(route, id) end
	view.role, view.edit_id = role, id
	local sit, rows, foes = foe_counters(role, hero)
	view.vs, view.sit, view.vs_rows, view.foes = sit, sit, rows, foes
	if not route then return end
	local owned = owned_items(hero)
	local extra = 0
	for _, step in ipairs(route) do
		if step.early then extra = extra + 1 end
	end
	while #route > K.ROUTE_MAX + 2 + extra do table.remove(route) end
	route = route_adjust(route, owned, rows)
	local gpm = income()
	local now_min = math.max(0, (GameRules.GetDOTATime() or 0) / 60)
	local spent, next_step = 0, nil
	for _, name in ipairs(start) do spent = spent + item_cost(name) end
	local gold = 0
	local player = Players.GetLocal()
	if player then gold = Player.GetTotalGold(player) end
	for _, step in ipairs(route) do
		if step.done then
			spent = spent + step.cost
			step.minute = nil
		elseif step.skipped or step.passed then
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
		if not step.skipped and (not K.BOOTS[step.name] or #finals < 5) then table.insert(finals, 1, step) end
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

local HEROES = { data = nil }

function HEROES.list()
	if HEROES.data then return HEROES.data end
	local dir = Engine.GetCheatDirectory() or ""
	if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
	local raw = read_file(dir .. "assets\\data\\npc_heroes.json")
	local groups, index = {}, {}
	for _, a in ipairs(K.ATTRS) do
		local g = { attr = a[1], key = a[2], color = a[3], heroes = {} }
		groups[#groups + 1] = g
		index[a[1]] = g
	end
	if raw then
		local at = 1
		while true do
			local _, e, short = raw:find('\n    "npc_dota_hero_([%w_]+)": {', at)
			if not e then break end
			local stop = raw:find('\n    "npc_dota_hero_', e, true) or #raw
			local block = raw:sub(e, stop)
			local id = tonumber(block:match('"HeroID": "(%d+)"'))
			local attr = block:match('"AttributePrimary": "DOTA_ATTRIBUTE_(%u+)"')
			if id and attr and index[attr] and block:match('"Enabled": "(%d)"') == "1" then
				local unit = "npc_dota_hero_" .. short
				table.insert(index[attr].heroes, { id = id, unit = unit, title = hero_title(unit) })
			end
			at = stop
		end
	end
	for _, g in ipairs(groups) do table.sort(g.heroes, function(a, b) return a.title < b.title end) end
	HEROES.data = groups
	return groups
end

local POOL = { set = nil, n = 0 }

function POOL.get()
	if POOL.set then return POOL.set end
	local set, n = {}, 0
	for id in Config.ReadString(K.CONFIG, "pool", ""):gmatch("%d+") do
		set[tonumber(id)] = true
		n = n + 1
	end
	POOL.set, POOL.n = set, n
	return set
end

function POOL.save()
	local ids = {}
	for id in pairs(POOL.get()) do ids[#ids + 1] = id end
	table.sort(ids)
	POOL.n = #ids
	Config.WriteString(K.CONFIG, "pool", table.concat(ids, ","))
	state.next_model = 0
end

function POOL.toggle(id)
	local set = POOL.get()
	id = tonumber(id)
	if not id then return end
	set[id] = not set[id] or nil
	POOL.save()
end

function POOL.clear()
	POOL.set = {}
	POOL.save()
end

function POOL.label()
	POOL.get()
	return POOL.n > 0 and string.format(L("bb_pool_count"), POOL.n) or L("bb_pool_all")
end

local function grid_off(id)
	local grid = state.grid
	local unit = grid and hero_unit(id)
	local cards = unit and grid[unit:sub(15)]
	for _, card in ipairs(cards or K.NONE) do
		for _, cls in ipairs(K.GRID_OFF) do
			local ok, has = pcall(card.HasClass, card, cls)
			if ok and has then return true end
		end
	end
	return false
end

local MATE = {}

function MATE.roles(d, shares)
	local used, open = {}, {}
	local mine = setting("role")
	if mine == 0 then mine = d.my_pos end
	for _, e in ipairs(d.ours) do
		local sh = e.id and shares and shares.heroes[e.id]
		if e.me then
			local p = mine or (sh and sh.main)
			if p then used[p] = true end
		elseif e.id then
			local p = e.pos or (sh and sh.main)
			if p then used[p] = true end
		else
			open[#open + 1] = { e = e }
		end
	end
	for _, m in ipairs(open) do
		local p = m.e.pos
		if p and not used[p] then m.pos, m.known, used[p] = p, true, true end
	end
	for _, m in ipairs(open) do
		local flags = m.e.flags or 0
		if not m.pos and flags ~= 0 then
			for p = 1, 5 do
				if not m.pos and not used[p] and flags & K.POS_BITS[p] ~= 0 then m.pos, used[p] = p, true end
			end
		end
	end
	for _, m in ipairs(open) do
		if not m.pos then
			for p = 1, 5 do
				if not m.pos and not used[p] then m.pos, used[p] = p, true end
			end
		end
	end
	return open
end

function MATE.build(d, x, pool, theirs, view)
	local shares = sz_shares()
	local mates = MATE.roles(d, shares)
	if #mates == 0 then return nil end
	local taken = {}
	for _, e in ipairs(d.ours) do
		if e.id then taken[e.id] = true end
	end
	for _, id in ipairs(theirs) do taken[id] = true end
	for _, id in ipairs(d.bans) do taken[id] = true end
	for _, b in ipairs(view.best) do taken[b.id] = true end
	local out = {}
	for _, m in ipairs(mates) do
		if m.pos then
			local list = {}
			for id in pairs(pool) do
				if not taken[id] and role_fits(id, m.pos, shares) and not grid_off(id) then
					local meta = pos_logit(id, m.pos, shares)
					local add, good = meta, {}
					for _, b in ipairs(theirs) do
						local v = pair_vs(id, b)
						add = add + v
						if v > 0 then good[#good + 1] = { id = b, v = v } end
					end
					table.sort(good, function(p, q) return p.v > q.v end)
					local score = add - meta * (1 - K.META_W)
					list[#list + 1] = { id = id, gain = (sigmoid(x + score) - sigmoid(x)) * 100, score = score, strong = good[1] and good[1].id, strong2 = good[2] and good[2].id }
				end
			end
			table.sort(list, function(p, q) return p.score > q.score end)
			local heroes = {}
			for i = 1, math.min(K.MATE_HEROES, #list) do
				local b = list[i]
				taken[b.id] = true
				local names = {}
				for _, sid in ipairs({ b.strong, b.strong2 }) do
					local su = hero_unit(sid)
					if su then names[#names + 1] = hero_title(su) end
				end
				if #names > 0 then
					b.why = string.format(L("bb_pick_vs"), table.concat(names, ", "))
				else
					local sh = shares and shares.heroes[b.id]
					local r = sh and sh.wr[m.pos]
					if r and r.g >= K.META_GAMES then b.why = string.format(L("bb_pick_meta"), math.floor(r.w / r.g * 100 + 0.5)) end
				end
				heroes[#heroes + 1] = b
			end
			if #heroes > 0 then out[#out + 1] = { name = m.e.pname, pos = m.pos, known = m.known, heroes = heroes } end
		end
	end
	return #out > 0 and out or nil
end

local function compute_view()
	local d = state.draft
	local ours, theirs = picked(d.ours), picked(d.theirs)
	local view = { ours = ours, theirs = theirs, cells = {}, totals = {}, best = {}, threats = {}, threat_counts = {}, danger = {} }
	local positions, label = draft_positions(d.ours)
	view.pick_role = label
	for _, id in ipairs(ours) do sz_vs(id) end
	for _, id in ipairs(theirs) do sz_vs(id) end
	sz_wr()
	local pool = state.stats
	if not pool then
		local shares = sz_shares()
		pool = shares and next(shares.heroes) and shares.heroes or nil
	end
	if pool then
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
		if not d.my_hero and d.phase then
			local shares = sz_shares()
			local taken = {}
			for _, id in ipairs(ours) do taken[id] = true end
			for _, id in ipairs(theirs) do taken[id] = true end
			for _, id in ipairs(d.bans) do taken[id] = true end
			local list = {}
			local mine = POOL.get()
			local only = POOL.n > 0
			for id in pairs(pool) do
				local pos, best_n, fits = nil, -1, true
				if not taken[id] and not grid_off(id) then
					for _, p in ipairs(positions) do
						if role_fits(id, p, shares) then
							local sh = shares and shares.heroes[id]
							local c = sh and sh.n[p] or 0
							if c > best_n then pos, best_n = p, c end
						end
					end
					if not pos and only and mine[id] then
						local sh = shares and shares.heroes[id]
						fits = false
						for _, p in ipairs(positions) do
							local c = sh and sh.n[p] or 0
							if c > best_n then pos, best_n = p, c end
						end
					end
				end
				if pos then
					local add = pos_logit(id, pos, shares)
					local good = {}
					for _, b in ipairs(theirs) do
						local v = pair_vs(id, b)
						add = add + v
						if v > 0 then good[#good + 1] = { id = b, v = v } end
					end
					table.sort(good, function(p, q) return p.v > q.v end)
					local score = add - pos_logit(id, pos, shares) * (1 - K.META_W)
					local gain = (sigmoid(x + score) - sigmoid(x)) * 100
					list[#list + 1] = { id = id, pos = pos, gain = gain, score = score, fits = fits, strong = good[1] and good[1].id, strong2 = good[2] and good[2].id }
				end
			end
			table.sort(list, function(p, q)
				if p.fits ~= q.fits then return p.fits end
				return p.score > q.score
			end)
			if only then
				local own, rest = {}, {}
				for _, b in ipairs(list) do
					if mine[b.id] then
						if #own < K.POOL_SHOW then
							b.own = true
							own[#own + 1] = b
						end
					elseif b.fits then
						rest[#rest + 1] = b
					end
				end
				list = own
				for _, b in ipairs(rest) do list[#list + 1] = b end
			end
			for i = 1, math.min(4, #list) do
				local b = list[i]
				local names = {}
				for _, sid in ipairs({ b.strong, b.strong2 }) do
					local su = hero_unit(sid)
					if su then names[#names + 1] = hero_title(su) end
				end
				if #names > 0 then
					b.why = string.format(L("bb_pick_vs"), table.concat(names, ", "))
				else
					local sh = shares and shares.heroes[b.id]
					local r = sh and sh.wr[b.pos]
					if r and r.g >= K.META_GAMES then b.why = string.format(L("bb_pick_meta"), math.floor(r.w / r.g * 100 + 0.5)) end
				end
				if b.own then b.why = b.why and (L("bb_pick_own") .. " · " .. b.why) or L("bb_pick_own") end
				view.best[i] = b
			end
			if view.best[1] and view.chance then view.hint = { id = view.best[1].id, chance = math.floor(view.chance + view.best[1].gain + 0.5) } end
		end
		if d.phase and #ours + #theirs > 0 then view.mates = MATE.build(d, x, pool, theirs, view) end
		for _, t in ipairs(K.THREATS) do
			local units = {}
			for _, id in ipairs(theirs) do
				local row = state.stats and state.stats[id]
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

local MIRROR = { pick = nil }

function MIRROR.get(ref, file, check, done, tag)
	local list = K.MIRRORS
	if not MIRROR.pick then
		MIRROR.pick = Config.ReadInt(K.CONFIG, "mirror", 1)
		if not list[MIRROR.pick] then MIRROR.pick = 1 end
	end
	local tried = 0
	local function try(i)
		tried = tried + 1
		local function fail()
			if tried < #list then return try(i % #list + 1) end
			done(nil)
		end
		local ok, sent = pcall(HTTP.Request, "GET", string.format(list[i], ref, file), { timeout = K.NET_TIMEOUT }, function(res)
			local body = tonumber(res and res.code) == 200 and type(res.response) == "string" and res.response or nil
			if not body or not check(body) then return fail() end
			if MIRROR.pick ~= i then
				MIRROR.pick = i
				Config.WriteInt(K.CONFIG, "mirror", i)
			end
			done(body)
		end, tag .. i)
		if not ok or sent == false then fail() end
	end
	try(MIRROR.pick)
end

local UPD = { st = "idle", latest = nil, err = nil, next_check = 0, path = nil, reload_at = nil, loaded = false, first = true, shown = nil, text = nil, tone = nil, title = "Build Brain " .. K.VERSION }

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
	MIRROR.get("main", "build_brain/latest.txt", function(body)
		return body:match("^%s*(%d+%.%d+%.%d+)%s*$") ~= nil
	end, function(body)
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
	end, "bb_update")
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
	MIRROR.get("build-brain-v" .. want, "build_brain/build_brain.lua", function(body)
		return #body >= K.UPD_MIN and body:match('\n\tVERSION = "([%d%.]+)",') == want and body:match("return script%s*$") ~= nil
	end, function(body)
		if not body then
			UPD.st, UPD.err = "error", "bb_upd_err_net"
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
	end, "bb_update_file")
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
	if not UPD.first and os.time() - Config.ReadInt(K.CONFIG, "upd_checked", 0) < K.UPD_EVERY then return end
	UPD.first = false
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

local N = {
	BG = Color(0, 0, 0, 255),
	PANEL = Color(12, 12, 13, 255),
	SLOT = Color(18, 18, 19, 255),
	LINE = Color(32, 32, 34, 255),
	HOT = Color(255, 255, 255, 12),
	TEXT = Color(242, 242, 242),
	MUTED = Color(142, 142, 146),
	DIM = Color(88, 88, 92),
	TRACK = Color(40, 40, 42),
	WIN = Color(104, 214, 150),
	LOSE = Color(240, 100, 110),
	DONE = Color(255, 255, 255, 92),
	SHADE = Color(0, 0, 0, 170),
	ACCENT = Color(255, 90, 44),
	ACCENT_HOT = Color(255, 122, 84),
	ACCENT_SOFT = Color(255, 90, 44, 36),
	INK = Color(0, 0, 0),
	TG = Color(42, 171, 238),
	TG_HOT = Color(74, 186, 244),
	TEXT_ON = Color(255, 255, 255),
	X = 28,
	TOP = 80,
	HEAD = 56,
	R = 18,
}

local W = { dead = {}, seen = {}, seen_at = {}, todo_at = {}, todo_n = 0, foe_at = {}, item_at = {}, drop = {}, base_a = 1, base_y = 0, base_x = 0, dir = 0, flat = false, nums = {}, nums_n = 0 }

W.TABS = { "draft", "build", "fight", "party" }
W.ORDER = { draft = 1, build = 2, fight = 3, party = 4, settings = 5 }
W.WHERE = { "shop", "auto" }

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
	G.ox = W.base_x + (1 - e) * 16 * G.s * W.dir
	return e
end

function W.unblock()
	G.alpha, G.oy, G.ox = W.base_a, W.base_y, W.base_x
end

function W.count(key, value)
	return math.floor(tween(key, value, 7) + 0.5)
end

function W.num(n)
	n = math.floor(n + 0.5)
	local s = W.nums[n]
	if s then return s end
	s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
	if n < 0 then s = "-" .. s end
	if W.nums_n > 4000 then W.nums, W.nums_n = {}, 0 end
	W.nums[n] = s
	W.nums_n = W.nums_n + 1
	return s
end

function W.soft(x, y, w, h, r, size)
	Render.Shadow(P(x, y), P(x + w, y + h), A(C.SHADOW_SOFT), size * G.s, r * G.s)
end

function W.dots(x, y)
	for i = 0, 2 do
		local a = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(state.clock * 5 - i * 0.8))
		dot(x + i * 9, y, 2.5, alpha(N.MUTED, a))
	end
end

function W.empty(label, x, y, w)
	W.dots(x + 3, y + 10)
	for i, l in ipairs(wrap(fonts.w500, 14, label, w - 40, 2)) do text(fonts.w500, 14, l, x + 34, y + (i - 1) * 20, N.MUTED) end
end

function W.head(title, x, y, w, hint)
	text(fonts.w500, 13, title, x, y, N.MUTED)
	if hint then
		local room = w - measure(fonts.w500, 13, title) - 24
		if room > 40 then text(fonts.w500, 13, fit(fonts.w500, 13, hint, room), x + w, y, N.DIM, "right") end
	end
end

function W.pic(handle, x, y, w, h, r, gray, crop, tint)
	if not handle then
		rect(x, y, w, h, N.SLOT, r)
		return
	end
	picture(handle, x, y, w, h, r, gray, crop, tint)
end

function W.ring(x, y, w, h, r, a)
	frame_line(x - 3, y - 3, w + 6, h + 6, alpha(N.ACCENT, a or 1), (r or 0) + 3, 2)
end

function W.glyph(ch, size, x, y, color)
	local w, h = measure(fonts.icon, size, ch)
	text(fonts.icon, size, ch, x - w / 2, y - h / 2, color)
end

function W.pressed(hot)
	return hot > 0.5 and Input.IsKeyDown(Enum.ButtonCode.KEY_MOUSE1, true)
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
		W.pic(handle, x - w * k / 2, y - h * k / 2, w * (1 + k), h * (1 + k), r, gray, false, tint)
	else
		W.pic(handle, x, y, w, h, r, gray, false, tint)
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

function W.button_main(key, label, x, y, w, h, kind, value)
	local bx, by, bw, bh, hot = W.btn(key, x, y, w, h)
	rect(bx, by, bw, bh, mix(N.ACCENT, N.ACCENT_HOT, hot), 12)
	local s = fit(fonts.w600, 14, label, w - 20)
	local _, th = measure(fonts.w600, 14, s)
	text(fonts.w600, 14, s, bx + bw / 2, by + (bh - th) / 2, N.INK, "center")
	button(kind, x, y, w, h, value)
end

function W.button_ghost(key, label, x, y, w, h, kind, value, on)
	local bx, by, bw, bh, hot = W.btn(key, x, y, w, h)
	if hot > 0.01 then rect(bx, by, bw, bh, alpha(N.HOT, hot), 12) end
	frame_line(bx, by, bw, bh, on and N.ACCENT or mix(N.LINE, N.DIM, hot), 12)
	local s = fit(fonts.w600, 13, label, w - 16)
	local _, th = measure(fonts.w600, 13, s)
	text(fonts.w600, 13, s, bx + bw / 2, by + (bh - th) / 2, N.TEXT, "center")
	button(kind, x, y, w, h, value)
end

function W.skeleton(x, y, w, h, i)
	local a = 0.5 + 0.5 * math.sin(state.clock * 3 - i * 0.6)
	rect(x, y, w, h, N.SLOT, 10)
	rect(x + 12, y + (h - 30) / 2, 54, 30, alpha(N.LINE, 0.6 + 0.4 * a), 6)
	rect(x + 78, y + h / 2 - 8, w * 0.35, 7, alpha(N.LINE, 0.6 + 0.4 * a), 3)
	rect(x + 78, y + h / 2 + 5, w * 0.22, 5, alpha(N.LINE, 0.4 + 0.3 * a), 2)
end

W.st = { key = nil, from = nil, to = nil, at = -10, done = true, pals = {} }
W.ST_FIELDS = { "ACCENT", "ACCENT_HOT", "ACCENT_SOFT", "INK" }

function W.style_pal(i)
	local pal = W.st.pals[i]
	if pal then return pal end
	local s = K.STYLES[i + 1] or K.STYLES[1]
	local r, g, b = s[1], s[2], s[3]
	pal = {
		ACCENT = Color(r, g, b),
		ACCENT_HOT = Color(math.floor(r + (255 - r) * 0.18 + 0.5), math.floor(g + (255 - g) * 0.18 + 0.5), math.floor(b + (255 - b) * 0.18 + 0.5)),
		ACCENT_SOFT = Color(r, g, b, 36),
		INK = s[4] == 1 and Color(255, 255, 255) or Color(0, 0, 0),
	}
	W.st.pals[i] = pal
	return pal
end

function W.style_tick()
	local st = W.st
	local key = setting("style")
	if key ~= st.key then
		local now = {}
		for _, f in ipairs(W.ST_FIELDS) do now[f] = N[f] end
		st.from, st.to = now, W.style_pal(key)
		st.at = st.key == nil and -10 or state.clock
		st.key, st.done = key, false
	end
	if st.done then return end
	local k = math.min(1, (state.clock - st.at) / 0.35)
	if k >= 1 then
		for _, f in ipairs(W.ST_FIELDS) do N[f] = st.to[f] end
		st.done = true
	else
		local e = W.ease(k)
		for _, f in ipairs(W.ST_FIELDS) do N[f] = mix(st.from[f], st.to[f], e) end
	end
end

function W.shell(w, h)
	shadow(0, 0, w, h, N.R, 28)
	rect(0, 0, w, h, N.BG, N.R)
	frame_line(0, 0, w, h, N.LINE, N.R)
end

function W.header(w)
	local win = state.win
	local view = state.view
	button("header", 0, 0, w, N.HEAD)
	rect(0, N.HEAD - 1, w, 1, N.LINE)
	local title = L("bb_title")
	text(fonts.d600, 17, title, N.X, 17, N.TEXT)
	local x = N.X + measure(fonts.d600, 17, title) + 40
	local cur_x, cur_w = nil, nil
	for _, t in ipairs(W.TABS) do
		local label = L("bb_tab_" .. t)
		local tw = measure(fonts.d500, 16, label)
		local on = win.tab == t
		local hot = hover_t("tab_" .. t, x - 10, 0, tw + 20, N.HEAD)
		local lit = math.max(tween("tab_on_" .. t, on and 1 or 0, 14), hot * 0.7)
		text(fonts.d500, 16, label, x, 18, mix(N.MUTED, N.TEXT, lit))
		button("tab", x - 10, 0, tw + 20, N.HEAD, t)
		if on then cur_x, cur_w = x, tw end
		x = x + tw + 28
	end
	local ia = tween("tab_ia", cur_x and 1 or 0, 14)
	if cur_x then W.ind_x, W.ind_w = tween("tab_ix", cur_x, 16), tween("tab_iw", cur_w, 16) end
	if ia > 0.01 and W.ind_x then rect(W.ind_x, N.HEAD - 2, W.ind_w, 2, alpha(N.ACCENT, ia), 1) end
	local cx = w - 46
	local bx, by, bw, bh, hot = W.btn("close", cx, 13, 30, 30)
	if hot > 0.01 then rect(bx, by, bw, bh, alpha(N.HOT, hot), 10) end
	W.glyph(K.CLOSE, 14, bx + bw / 2, by + bh / 2, mix(N.MUTED, N.TEXT, hot))
	button("close", cx, 13, 30, 30)
	local gx = cx - 38
	local gon = win.tab == "settings"
	local qx, qy, qw, qh, gh = W.btn("gear", gx, 13, 30, 30)
	if gh > 0.01 then rect(qx, qy, qw, qh, alpha(N.HOT, gh), 10) end
	W.glyph(K.TAB_ICONS.settings, 15, qx + qw / 2, qy + qh / 2, gon and N.ACCENT or mix(N.MUTED, N.TEXT, gh))
	if UPD.st == "available" or UPD.st == "done" then dot(qx + qw - 6, qy + 6, 3.5, N.ACCENT) end
	button("tab", gx, 13, 30, 30, "settings")
	local tgx = gx - 38
	local ux, uy, uw, uh, th = W.btn("tg", tgx, 13, 30, 30)
	local tr = 13 + th
	dot(ux + uw / 2, uy + uh / 2, tr, mix(N.TG, N.TG_HOT, th))
	W.glyph(K.TG_ICON, 12, ux + uw / 2 - 1, uy + uh / 2 + 1, N.TEXT_ON)
	button("link", tgx, 13, 30, 30, "tg")
	if th > 0.5 then W.tip = { text = L("bb_menu_tg"), x = tgx + 15, y = N.HEAD + 6 } end
	local right = tgx - 16
	local room = right - x - 4
	if room < 60 then return end
	local busy = (state.net.busy and L("bb_status_loading")) or (state.net.offline and L("bb_status_offline"))
	local info
	if win.status then
		info = win.status
	elseif busy and win.tab ~= "build" then
		info = busy
	elseif win.tab == "build" and view and view.gold then
		info = "GPM " .. W.count("hdr_gpm", math.floor(view.gpm or 0))
	else
		local rank, pos = setting("rank"), my_position()
		local key = rank * 10 + (tonumber(pos) or 0)
		if win.info_key ~= key then
			win.info_key = key
			win.info = L("bb_rank_" .. rank) .. " · " .. L("bb_role") .. " " .. L("bb_role_" .. pos)
		end
		info = win.info
	end
	text(fonts.w500, 13, fit(fonts.w500, 13, info, room), right, 21, N.MUTED, "right")
end

function W.team(x, y, w, list, label, color, key)
	text(fonts.w500, 13, label, x, y, N.MUTED)
	local gap = 6
	local bw = (w - 4 * gap) / 5
	local bh = math.floor(bw * 0.5625 + 0.5)
	y = y + 22
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 3)
	for i = 1, 5 do
		local e = list[i]
		local px = x + (i - 1) * (bw + gap)
		local unit = e and e.id and hero_unit(e.id)
		if unit then
			local t = W.first_seen(key .. i, e.id)
			local sc = W.pop(t)
			local cw, ch = bw * sc, bh * sc
			W.pic(hero_image(unit), px + (bw - cw) / 2, y + (bh - ch) / 2, cw, ch, 8)
			local flash = 1 - math.min(1, t / 0.45)
			if flash > 0 then rect(px, y, bw, bh, alpha(N.TEXT, 0.22 * flash), 8) end
			if e.me then W.ring(px, y, bw, bh, 8) end
		else
			W.seen[key .. i] = nil
			rect(px, y, bw, bh, N.SLOT, 8)
			if e and e.me then frame_line(px, y, bw, bh, alpha(N.ACCENT, 0.3 + 0.5 * pulse), 8, 1.5) end
		end
		rect(px + 6, y + bh + 4, bw - 12, 2, color, 1)
		if e and e.pos then
			rect(px + 4, y + 4, 18, 17, N.SHADE, 5)
			text(fonts.d600, 12, tostring(e.pos), px + 13, y + 5, N.TEXT, "center")
		end
	end
	return y + bh + 6
end

function W.chance(x, y, w)
	local d = state.draft
	local view = state.view
	local light = d.my_team ~= 3
	local chance = view and view.chance
	W.head(L("bb_chance_title"), x, y, w)
	local ny = y + 22
	local by = ny + 60
	if chance then
		if state.anim.chance == nil then state.anim.chance = 50 end
		local shown = tween("chance", chance, 5)
		local str = math.floor(shown + 0.5) .. "%"
		text(fonts.d600, 46, str, x, ny - 4, N.TEXT)
		local nw = measure(fonts.d600, 46, str)
		local rad = light and shown or (100 - shown)
		local r = math.floor(rad + 0.5)
		text(fonts.w500, 13, L("bb_light") .. " " .. r .. "   " .. (100 - r) .. " " .. L("bb_dark"), x + nw + 16, ny + 26, N.MUTED)
		local split = w * rad / 100
		rect(x, by, split, 4, N.WIN, 2)
		rect(x + split, by, w - split, 4, N.LOSE, 2)
		rect(x + w / 2, by - 4, 1, 12, N.MUTED)
	else
		text(fonts.w500, 14, L("bb_chance_sub"), x, ny + 18, N.MUTED)
		rect(x, by, w, 4, N.TRACK, 2)
		local p = (state.clock * 0.5) % 1
		rect(x + (w - 70) * p, by, 70, 4, N.DIM, 2)
	end
	return by + 16
end

function W.heat(x, y, w, h)
	local view = state.view
	W.head(L("bb_heat"), x, y, w, L("bb_heat_hint"))
	if not view or #view.ours == 0 or #view.theirs == 0 then return W.empty(L("bb_heat_empty"), x, y + 32, w) end
	local order = view.heat_order
	if not order then
		order = {}
		for i, a in ipairs(view.ours) do order[i] = a end
		table.sort(order, function(p, q) return (view.totals[p] or 0) > (view.totals[q] or 0) end)
		view.heat_order = order
	end
	local tw = 54
	local gx = x + 40
	local col = (w - 40 - tw - 8) / 5
	for j, b in ipairs(view.theirs) do
		local unit = hero_unit(b)
		if unit then W.pic(hero_image(unit), gx + (j - 1) * col + (col - 26) / 2, y + 26, 26, 26, 13, 0, true) end
	end
	local ry0 = y + 62
	local row_h = math.min(36, (y + h - ry0) / math.max(1, #order))
	local me = state.draft.my_hero
	local ba = G.alpha
	for idx, a in ipairs(order) do
		local ry = ry0 + tween("hr" .. a, (idx - 1) * row_h, 10)
		local e = W.since(state.win.open_at, 0.1 + idx * 0.04, 0.24)
		G.alpha = ba * e
		if idx > 1 then rect(x, ry, w, 1, N.LINE) end
		local unit = hero_unit(a)
		if unit then
			local py = ry + (row_h - 26) / 2
			W.pic(hero_image(unit), x, py, 26, 26, 13, 0, true)
			if a == me then frame_line(x - 2, py - 2, 30, 30, N.ACCENT, 15, 1.5) end
		end
		for j, b in ipairs(view.theirs) do
			local v = view.cells[a] and view.cells[a][b] or 0
			local mid = gx + (j - 1) * col + col / 2
			local c = v > 0.05 and N.WIN or (v < -0.05 and N.LOSE or N.MUTED)
			text(fonts.d500, 14, string.format("%+.1f", v), mid, ry + row_h / 2 - 9, c, "center")
		end
		local total = view.totals[a] or 0
		text(fonts.d600, 15, string.format("%+.1f", total), x + w - tw / 2, ry + row_h / 2 - 10, total >= 0 and N.WIN or N.LOSE, "center")
	end
	G.alpha = ba
end

function W.stages(x, y, w)
	local view = state.view
	local theirs = view and #view.theirs > 0
	local rows = {
		{ "bb_ld_builds", state.sz_text and "done" or (state.sync.busy and "busy" or "wait") },
		{ "bb_ld_vs", state.sz_has_vs and "done" or "wait" },
		{ "bb_ld_wr", (state.stats or (state.sz_wr and next(state.sz_wr))) and "done" or (state.net.busy and "busy" or "wait") },
		{ theirs and "bb_ld_picks" or "bb_ld_wait", theirs and "busy" or "wait" },
	}
	for i, r in ipairs(rows) do
		local ry = y + (i - 1) * 36
		local cx, cy = x + 10, ry + 10
		if r[2] == "done" then
			W.glyph(K.ONB_CHECK, 12, cx, cy, N.TEXT)
		elseif r[2] == "busy" then
			Render.Circle(P(cx, cy), 8 * G.s, A(N.TRACK), 2 * G.s, 0, 1, false, 24)
			Render.Circle(P(cx, cy), 8 * G.s, A(N.ACCENT), 2 * G.s, (state.clock * 360) % 360, 0.25, true, 24)
		else
			Render.Circle(P(cx, cy), 8 * G.s, A(N.TRACK), 2 * G.s, 0, 1, false, 24)
		end
		text(fonts.w500, 14, L(r[1]), x + 30, ry + 2, r[2] == "wait" and N.MUTED or N.TEXT)
	end
	local ny = y + #rows * 36 + 8
	if state.sync.failed and state.sz_date then
		for i, l in ipairs(wrap(fonts.w500, 13, string.format(L("bb_ld_offline"), os.date("%d.%m", state.sz_date)), w, 2)) do
			text(fonts.w500, 13, l, x, ny + (i - 1) * 18, N.ACCENT)
		end
	end
end

function W.picks(x, y, w, h)
	local view = state.view
	W.head(string.format(L("bb_pick_title"), L("bb_role_" .. (view and view.pick_role or my_position()))), x, y, w)
	if not view or #view.best == 0 then return W.stages(x, y + 34, w) end
	local ba = G.alpha
	local ry = y + 24
	for i, b in ipairs(view.best) do
		local first = i == 1
		local rh = 78
		if ry + rh > y + h then break end
		local unit = hero_unit(b.id)
		if unit then
			local e = W.since(state.win.open_at, 0.12 + i * 0.05, 0.24)
			G.alpha = ba * e
			local hot = hover_t("best" .. i, x, ry, w, rh)
			if hot > 0.01 then rect(x - 10, ry + 4, w + 20, rh - 8, alpha(N.HOT, hot), 12) end
			if i > 1 then rect(x, ry, w, 1, N.LINE) end
			local py = ry + (rh - 44) / 2
			W.pic(hero_image(unit), x, py, 78, 44, 8)
			if first then W.ring(x, py, 78, 44, 8, 0.7 + 0.3 * math.sin(state.clock * 2.4)) end
			text(fonts.d600, 22, string.format("%+.1f", b.gain), x + w, ry + 16, b.gain >= 0 and N.WIN or N.LOSE, "right")
			text(fonts.w500, 12, L("bb_best_hint"), x + w, ry + 46, N.DIM, "right")
			local tx = x + 96
			local room = w - 96 - 92
			local name = hero_title(unit)
			if first then
				local tag = L("bb_top")
				local tw = measure(fonts.w700, 11, tag) + 12
				rect(tx, ry + 19, tw, 18, N.ACCENT, 6)
				text(fonts.w700, 11, tag, tx + tw / 2, ry + 21, N.INK, "center")
				text(fonts.w600, 16, fit(fonts.w600, 16, name, room - tw - 8), tx + tw + 8, ry + 18, N.TEXT)
			else
				text(fonts.w600, 16, fit(fonts.w600, 16, name, room), tx, ry + 18, N.TEXT)
			end
			if b.why then text(fonts.w500, 13, fit(fonts.w500, 13, b.why, room), tx, ry + 43, N.MUTED) end
			button("hero", x, ry, w, rh, b.id)
		end
		ry = ry + rh
	end
	G.alpha = ba
end

function W.foes(x, y, w, h)
	local view = state.view
	W.head(L("bb_foe_title"), x, y, w)
	local list = view and view.foes or K.NONE
	if #list == 0 then
		for i = 0, 3 do W.skeleton(x, y + 30 + i * 70, w, 60, i) end
		return
	end
	local ba = G.alpha
	local ry = y + 24
	for i, f in ipairs(list) do
		local n = math.min(#f.items, 3)
		local room = w - 96 - n * 44 - 8
		local lines = wrap(fonts.w500, 13, f.line, room, 2)
		local rh = math.max(66, 34 + #lines * 18 + 12)
		if ry + rh > y + h then break end
		G.alpha = ba * W.since(state.win.open_at, 0.12 + i * 0.05, 0.24)
		if i > 1 then rect(x, ry, w, 1, N.LINE) end
		W.pic(hero_image(f.unit), x, ry + (rh - 44) / 2, 78, 44, 8)
		text(fonts.w600, 15, fit(fonts.w600, 15, hero_title(f.unit), room), x + 94, ry + 11, N.TEXT)
		for k, l in ipairs(lines) do text(fonts.w500, 13, l, x + 94, ry + 33 + (k - 1) * 18, N.MUTED) end
		local px = x + w
		for k = n, 1, -1 do
			px = px - 40
			W.icon(item_image(f.items[k]), px, ry + (rh - 29) / 2, 40, 29, 5, "fi" .. i .. k)
			button("item", px, ry + (rh - 29) / 2, 40, 29, f.items[k])
			px = px - 4
		end
		ry = ry + rh
	end
	G.alpha = ba
end

function W.draft(w, h)
	local d = state.draft
	local view = state.view
	local lx, lw = N.X, 404
	local rx = lx + lw + 44
	local rw = w - N.X - rx
	local top, bottom = N.TOP, h - 24
	local light = d.my_team ~= 3
	W.block(0)
	local y = W.chance(lx, top, lw)
	y = W.team(lx, y + 4, lw, d.ours, light and L("bb_light") or L("bb_dark"), light and N.WIN or N.LOSE, "so")
	y = W.team(lx, y + 12, lw, d.theirs, light and L("bb_dark") or L("bb_light"), light and N.LOSE or N.WIN, "st")
	W.block(1)
	rect(lx, y + 16, lw, 1, N.LINE)
	W.heat(lx, y + 34, lw, bottom - y - 34)
	W.block(2)
	rect(rx - 22, top, 1, bottom - top, N.LINE)
	if d.my_hero and view then W.foes(rx, top, rw, bottom - top) else W.picks(rx, top, rw, bottom - top) end
	W.unblock()
end

function W.why(step)
	if step.vs_reason then return step.vs_reason end
	if step.why_text then return step.why_text end
	local why = step.reason or L("bb_why_popular")
	if state.turbo and step.share then
		why = string.format(L("bb_next_share"), math.floor(step.share * 100 + 0.5))
	elseif step.tm and step.tm > 0 and step.share then
		why = string.format(L("bb_next_usual"), math.floor(step.tm / 60 + 0.5), math.floor(step.share * 100 + 0.5))
	end
	step.why_text = why
	return why
end

function W.next_block(x, y, w)
	local view = state.view
	local win = state.win
	local step = view and view.next
	W.head(L("bb_next"), x, y, w)
	if not step then
		W.empty(L("bb_route_empty"), x, y + 34, w)
		return y + 110
	end
	local gold = view.gold or 0
	local can = gold >= step.cost
	if can and win.afford_name ~= step.name then win.afford_name, win.afford_at = step.name, state.clock end
	if not can then win.afford_name = nil end
	local iy = y + 26
	local iw, ih = 112, 82
	W.icon(item_image(step.name), x, iy, iw, ih, 12, "next_icon")
	W.ring(x, iy, iw, ih, 12, can and (0.55 + 0.45 * (0.5 + 0.5 * math.sin(state.clock * 3))) or 1)
	button("item", x, iy, iw, ih, step.name)
	local rw0 = 270
	local rx = x + w - rw0
	local tx = x + iw + 28
	local tw = rx - 36 - tx
	local big = W.num(W.count("next_gold", math.min(gold, step.cost)))
	text(fonts.d600, 46, big, tx, iy - 9, N.TEXT)
	local bw = measure(fonts.d600, 46, big)
	text(fonts.d500, 22, "/ " .. W.num(step.cost), tx + bw + 10, iy + 12, N.MUTED)
	local name = fit(fonts.w600, 17, item_title(step.name), tw)
	local nw = measure(fonts.w600, 17, name)
	text(fonts.w600, 17, name, tx, iy + 46, N.TEXT)
	if tw - nw - 14 > 60 then text(fonts.w500, 13, fit(fonts.w500, 13, W.why(step), tw - nw - 14), tx + nw + 14, iy + 50, N.MUTED) end
	local by = iy + 76
	local share = tween("gold_bar", step.cost > 0 and math.min(1, gold / step.cost) or 0, 6)
	rect(tx, by, tw, 2, N.TRACK, 1)
	if share > 0.005 then rect(tx, by, tw * share, 2, N.ACCENT, 1) end
	local line
	if can then
		line = L("bb_enough")
	else
		line = string.format(L("bb_need"), W.num(step.cost - gold))
		if step.minute then line = line .. "  ·  " .. string.format(L("bb_eta"), step.minute) end
	end
	text(fonts.w500, 13, line, tx, by + 10, can and N.ACCENT or N.MUTED)
	local parts = step.parts or K.NONE
	local py = y + 22
	local shown = math.min(#parts, 4)
	for i, part in ipairs(parts) do
		if i > shown then break end
		local okp = not part.have and part.cost <= gold
		local hh = hover_t("part" .. i, rx - 8, py, rw0 + 16, 26)
		if hh > 0.01 then rect(rx - 8, py, rw0 + 16, 26, alpha(N.HOT, hh), 8) end
		W.pic(item_image(part.name), rx, py + 3, 28, 20, 4, part.have and 1 or 0, false, (part.have or not okp) and N.DONE or nil)
		text(fonts.w500, 13, fit(fonts.w500, 13, item_title(part.name), rw0 - 130), rx + 38, py + 5, (okp or part.have) and N.TEXT or N.MUTED)
		local price = part.have and "✓" or W.num(part.cost)
		text(part.have and fonts.w600 or fonts.d500, 14, price, rx + rw0, py + 4, part.have and N.MUTED or (okp and N.TEXT or N.DIM), "right")
		if okp then text(fonts.w600, 12, L("bb_vs_now"), rx + rw0 - measure(fonts.d500, 14, price) - 10, py + 6, N.ACCENT, "right") end
		button("item", rx - 8, py, rw0 + 16, 26, part.name)
		py = py + 26
	end
	local main_label = L("bb_buy_all")
	if can then
		main_label = string.format(L("bb_buy_part"), item_title(step.name))
	else
		for i, part in ipairs(parts) do
			if i > shown then break end
			if not part.have and part.cost <= gold then
				main_label = string.format(L("bb_buy_part"), item_title(part.name))
				break
			end
		end
	end
	local b1y = y + 22 + math.max(3, shown) * 26 + 10
	W.button_main("buy", main_label, rx, b1y, rw0 - 106, 38, "buy", step.name)
	W.button_ghost("quick", L("bb_quick"), rx + rw0 - 98, b1y, 98, 38, "quick", step.name)
	return b1y + 38
end

local function start_slots(list, max)
	local groups, index = {}, {}
	for _, name in ipairs(list) do
		local e = index[name]
		if e then
			e.count = e.count + 1
		else
			e = { name = name, count = 1 }
			index[name] = e
			groups[#groups + 1] = e
		end
	end
	local out, room = {}, max - #groups
	for _, e in ipairs(groups) do
		if e.count > 1 and e.count - 1 <= room then
			room = room - (e.count - 1)
			for _ = 1, e.count do out[#out + 1] = { name = e.name, count = 1 } end
		else
			out[#out + 1] = e
		end
	end
	return out
end

function W.shelf_data(view)
	if view.shelves then return view.shelves end
	local sh = { start = start_slots(view.start or K.NONE, 12), early = {}, core = {}, more = {} }
	local used, any = {}, false
	for _, step in ipairs(view.route) do
		used[step.name] = true
		if step.done then any = true end
		if not step.sit then
			local list = step.early and sh.early or sh.core
			list[#list + 1] = step
		end
	end
	for _, e in ipairs(sh.start) do e.done = any end
	for _, c in ipairs(view.role and view.role.pop or K.NONE) do
		if not used[c.name] and #sh.more < K.MORE_MAX then sh.more[#sh.more + 1] = { name = c.name } end
	end
	view.shelves = sh
	return sh
end

function W.tl_layout(view, aw)
	if view.tl and view.tl_w == aw then return view.tl end
	local items = {}
	local last = 0
	for i, step in ipairs(view.route) do
		if not step.sit then
			local m = state.turbo and step.minute or ((step.tm and step.tm > 0) and step.tm / 60 or step.minute)
			if m then last = m else m = last end
			items[#items + 1] = { step = step, m = m, i = i }
		end
	end
	table.sort(items, function(a, b)
		if a.m ~= b.m then return a.m < b.m end
		return a.i < b.i
	end)
	local maxm = 30
	for _, it in ipairs(items) do maxm = math.max(maxm, it.m + 4) end
	maxm = math.min(90, math.ceil(maxm / 5) * 5)
	local iw, gap = 44, 6
	local free = { -1000, -1000 }
	for _, it in ipairs(items) do
		local cx = it.m / maxm * aw
		local p1 = math.max(cx, free[1] + gap + iw / 2)
		local p2 = math.max(cx, free[2] + gap + iw / 2)
		local lane = p2 < p1 and 2 or 1
		cx = lane == 1 and p1 or p2
		free[lane] = cx + iw / 2
		it.cx, it.lane = cx, lane
	end
	for l = 1, 2 do
		local limit = aw - iw / 2
		for k = #items, 1, -1 do
			local it = items[k]
			if it.lane == l then
				it.cx = math.max(iw / 2, math.min(it.cx, limit))
				limit = it.cx - iw - gap
			end
		end
	end
	local tl = { items = items, max = maxm }
	view.tl, view.tl_w = tl, aw
	return tl
end

function W.timeline(x, y, w)
	local view = state.view
	W.head(L("bb_route_title"), x, y, w, state.turbo and L("bb_tl_hint_turbo") or L("bb_tl_hint"))
	if not view or not view.route then
		W.empty(L("bb_route_empty"), x, y + 34, w)
		return y + 164
	end
	local sh = W.shelf_data(view)
	local top = y + 30
	text(fonts.w500, 12, L("bb_shelf_start"), x, top, N.DIM)
	local cols = #sh.start > 8 and 3 or 2
	local iw = cols == 3 and 27 or 32
	local ih = cols == 3 and 20 or 23
	for i, e in ipairs(sh.start) do
		if i > cols * 4 then break end
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local px, py = x + col * (iw + 4), top + 20 + row * (ih + 5)
		W.pic(item_image(e.name), px, py, iw, ih, 5, e.done and 1 or 0, false, e.done and N.DONE or nil)
		if e.count and e.count > 1 then
			rect(px + iw - 14, py + ih - 12, 14, 12, N.SHADE, 3)
			text(fonts.d600, 11, tostring(e.count), px + iw - 7, py + ih - 12, N.TEXT, "center")
		end
		button("item", px, py, iw, ih, e.name)
	end
	local ax0 = x + 100
	local aw = w - 100
	local tl = W.tl_layout(view, aw)
	local lane_y = { top + 18, top + 64 }
	local axis_y = top + 110
	rect(ax0, axis_y, aw, 1, N.DIM)
	local step_m = tl.max > 50 and 10 or 5
	for m = 0, tl.max, step_m do
		local tx = ax0 + m / tl.max * aw
		rect(tx, axis_y - 3, 1, 4, N.DIM)
		text(fonts.d500, 12, tostring(m), tx, axis_y + 6, N.DIM, "center")
	end
	local now_m = Engine.IsInGame() and math.max(0, (GameRules.GetDOTATime() or 0) / 60) or 0
	if now_m > 0 then
		local nx = ax0 + math.min(1, now_m / tl.max) * aw
		rect(nx - 1, top - 2, 2, axis_y - top + 6, N.ACCENT)
		text(fonts.d600, 12, string.format("%d:%02d", math.floor(now_m), math.floor((now_m % 1) * 60)), nx - 7, top - 2, N.ACCENT, "right")
	end
	local ba = G.alpha
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 3)
	for i, it in ipairs(tl.items) do
		local iy = lane_y[it.lane]
		G.alpha = ba * W.since(state.win.open_at, 0.12 + i * 0.03, 0.22)
		rect(ax0 + it.cx, iy + 32, 1, axis_y - iy - 32, (it.step.done or it.step.skipped or it.step.passed) and N.LINE or N.DIM)
	end
	local card_hit = W.card_hit()
	for i, it in ipairs(tl.items) do
		local step = it.step
		local ix = ax0 + it.cx - 22
		local iy = lane_y[it.lane]
		local e = W.since(state.win.open_at, 0.12 + i * 0.03, 0.22)
		G.alpha = ba * e
		local dim = step.done or step.skipped or step.passed
		local hot = W.icon(item_image(step.name), ix, iy + (1 - e) * 6, 44, 32, 6, "tl" .. i, dim and 1 or 0, dim and N.DONE or nil)
		if hot > 0.5 and not card_hit then W.hov_cand = { name = step.name, orig = step.from or step.name, x = ix, y = iy, w = 44, h = 32 } end
		if view.next == step then W.ring(ix, iy, 44, 32, 6, 0.6 + 0.4 * pulse) end
		if step.skipped then rect(ix + 6, iy + 15, 32, 2, N.MUTED, 1) end
		if step.counter and not dim then
			dot(ix + 42, iy + 2, 5, N.BG)
			dot(ix + 42, iy + 2, 3.5, N.ACCENT)
		end
		button("item", ix, iy, 44, 32, step.name)
	end
	G.alpha = ba
	return axis_y + 24
end

function W.vs(x, y, w, h)
	local view = state.view
	W.head(L("bb_vs_title"), x, y, w)
	local list = view and view.vs_rows or K.NONE
	if #list == 0 then return W.empty(L("bb_vs_empty"), x, y + 32, w) end
	local ba = G.alpha
	local ry = y + 22
	local gold = view.gold or 0
	for i, t in ipairs(list) do
		local rh = 46
		if ry + rh > y + h then break end
		G.alpha = ba * W.since(state.win.open_at, 0.12 + i * 0.05, 0.24)
		if i > 1 then rect(x, ry, w, 1, N.LINE) end
		local first = t.options[1]
		local np = math.min(3, #t.units)
		for k = np, 1, -1 do W.pic(hero_image(t.units[k]), x + (k - 1) * 16, ry + 11, 24, 24, 12, 0, true) end
		local tx = x + (np > 0 and (np - 1) * 16 + 36 or 0)
		local cost = item_cost(first)
		local now = cost <= gold
		local label = now and L("bb_vs_now") or string.format(L("bb_vs_eta"), math.max(1, math.floor((cost - gold) / math.max(100, view.gpm or 400) + 0.5)))
		local lw = measure(fonts.w600, 12, label)
		text(fonts.w600, 12, label, x + w, ry + 16, now and N.ACCENT or N.MUTED, "right")
		local ix = x + w - lw - 12
		local room0 = ix - tx - 160
		for k = math.max(1, math.min(4, #t.options, math.floor((room0 + 4) / 44))), 1, -1 do
			ix = ix - 40
			W.icon(item_image(t.options[k]), ix, ry + 9, 38, 28, 5, t.key .. k)
			button("item", ix, ry + 9, 38, 28, t.options[k])
			ix = ix - 4
		end
		local room = ix - 12 - tx
		if not t.sub then t.sub = (t.how and t.how ~= "") and (item_title(first) .. ": " .. t.how) or item_title(first) end
		text(fonts.w500, 14, fit(fonts.w500, 14, t.text, room), tx, ry + 6, t.live and N.ACCENT or N.TEXT)
		text(fonts.w500, 12, fit(fonts.w500, 12, t.sub, room), tx, ry + 26, N.MUTED)
		ry = ry + rh
	end
	G.alpha = ba
end

function W.more(x, y, w, h)
	local view = state.view
	W.head(L("bb_shelf_more"), x, y, w)
	if not view or not view.route then return end
	local sh = W.shelf_data(view)
	local iw, ih, gap = 44, 32, 8
	local per = math.max(1, math.floor((w + gap) / (iw + gap)))
	local ba = G.alpha
	for i, e in ipairs(sh.more) do
		local col, row = (i - 1) % per, math.floor((i - 1) / per)
		local sx, sy = x + col * (iw + gap), y + 26 + row * (ih + gap)
		if sy + ih > y + h then break end
		G.alpha = ba * W.since(state.win.open_at, 0.15 + i * 0.02, 0.22)
		W.icon(item_image(e.name), sx, sy, iw, ih, 6, "sh_m" .. i)
		button("item", sx, sy, iw, ih, e.name)
	end
	G.alpha = ba
end

function W.build(w, h)
	local x, cw = N.X, w - 2 * N.X
	local top, bottom = N.TOP, h - 24
	W.block(0)
	local y = W.next_block(x, top, cw)
	W.block(1)
	rect(x, y + 16, cw, 1, N.LINE)
	y = W.timeline(x, y + 32, cw)
	W.block(2)
	rect(x, y + 12, cw, 1, N.LINE)
	local cy = y + 28
	local lw = math.floor(cw * 0.58)
	W.vs(x, cy, lw, bottom - cy)
	W.block(3)
	W.more(x + lw + 40, cy, cw - lw - 40, bottom - cy)
	W.unblock()
end

function W.donut(cx, cy, r, th, mag, phys, grow)
	local start = -90
	if mag > 0.001 then Render.Circle(P(cx, cy), r * G.s, A(C.MAGIC), th * G.s, start, mag * grow, false, 64) end
	start = start + mag * 360 * grow
	if phys > 0.001 then Render.Circle(P(cx, cy), r * G.s, A(C.PHYS), th * G.s, start, phys * grow, false, 64) end
	start = start + phys * 360 * grow
	local pure = math.max(0, 1 - mag - phys)
	if pure > 0.001 then Render.Circle(P(cx, cy), r * G.s, A(C.PURE), th * G.s, start, pure * grow, false, 64) end
end

function W.fight_killers(src, total)
	if src.kk and src.kk_total == total then return src.kk end
	local list = {}
	for unit, value in pairs(src.src) do list[#list + 1] = { unit = unit, value = value, share = total > 0 and value / total or 0 } end
	table.sort(list, function(p, q) return p.value > q.value end)
	while #list > 3 do table.remove(list) end
	src.kk, src.kk_total = list, total
	return list
end

function W.fight_tabs(xr, y, death)
	local x = xr
	for _, t in ipairs(K.FIGHT_TABS) do
		local label = L(t[2])
		local tw = measure(fonts.w600, 13, label)
		x = x - tw
		local on = death == (t[1] == "death")
		local hot = hover_t("fm_" .. t[1], x - 6, y - 4, tw + 12, 26)
		text(fonts.w600, 13, label, x, y, on and N.TEXT or mix(N.MUTED, N.TEXT, hot))
		local u = tween("fm_on_" .. t[1], on and 1 or 0, 14)
		if u > 0.01 then rect(x, y + 20, tw * u, 2, N.ACCENT, 1) end
		button("fmode", x - 6, y - 4, tw + 12, 26, t[1])
		x = x - 20
	end
end

function W.fight(w, h)
	local view = state.view
	local dmg = state.dmg
	local death = W.fmode == "death" and dmg.last ~= nil
	local src = death and dmg.last or dmg
	local total = src.phys + src.mag + src.pure
	local lx, lw = N.X, 404
	local rx = lx + lw + 44
	local rw = w - N.X - rx
	local top, bottom = N.TOP, h - 24
	W.block(0)
	if dmg.last then
		W.head(L("bb_fight_title"), lx, top, lw)
		W.fight_tabs(lx + lw, top, death)
	else
		W.head(L("bb_fight_title"), lx, top, lw, dmg.deaths > 0 and string.format(L("bb_kill_deaths"), dmg.deaths) or nil)
	end
	local ky = top + 30
	if total <= 0 then
		W.empty(L("bb_fight_empty"), lx, ky + 4, lw)
	else
		local cx, cy = lx + 66, ky + 70
		local grow = tween("fight_ring", 1, 3.6)
		local mag = tween("f_mag", src.mag / total, 6)
		local phys = tween("f_phys", src.phys / total, 6)
		Render.Circle(P(cx, cy), 60 * G.s, A(N.TRACK), 8 * G.s, 0, 1, false, 64)
		W.donut(cx, cy, 60, 8, mag, phys, grow)
		text(fonts.d600, 24, W.num(W.count("f_total", math.floor(total * grow))), cx, cy - 18, N.TEXT, "center")
		text(fonts.w500, 12, L(death and "bb_fight_hint_death" or "bb_fight_hint"), cx, cy + 10, N.MUTED, "center")
		local gx, gr = lx + 162, lx + lw
		for i, r in ipairs(K.DMG_ROWS) do
			local ly = ky + 28 + (i - 1) * 30
			local part = i == 1 and mag or (i == 2 and phys or math.max(0, 1 - mag - phys))
			rect(gx, ly + 5, 8, 8, C[r[1]], 2)
			text(fonts.w500, 14, L(r[2]), gx + 18, ly, N.TEXT)
			text(fonts.d600, 15, math.floor(part * 100 + 0.5) .. "%", gr, ly, N.TEXT, "right")
		end
		local ry = ky + 154
		if death then
			local ago = math.floor(state.clock - src.at)
			text(fonts.w500, 13, fit(fonts.w500, 13, string.format(L("bb_fight_death_n"), src.n, ago < 60 and string.format(L("bb_fight_sec"), ago) or string.format(L("bb_fight_min"), math.floor(ago / 60))), lw), lx, ry, N.MUTED)
			ry = ry + 28
		elseif dmg.deaths > 0 then
			text(fonts.w500, 13, fit(fonts.w500, 13, string.format(L("bb_kill_ctrl"), dmg.ctrl / dmg.deaths), lw), lx, ry, N.MUTED)
			ry = ry + 28
		end
		for i, s in ipairs(W.fight_killers(src, total)) do
			if ry + 34 > top + 300 then break end
			if s.unit:match("^npc_dota_hero_") then W.pic(hero_image(s.unit), lx, ry, 26, 26, 13, 0, true) end
			text(fonts.w500, 14, fit(fonts.w500, 14, hero_title(s.unit), lw - 150), lx + 38, ry, N.TEXT)
			local share = tween("src_" .. s.unit, s.share, 6) * W.since(state.win.open_at, 0.15 + i * 0.06, 0.45)
			rect(lx + 38, ry + 22, lw - 100, 2, N.TRACK, 1)
			rect(lx + 38, ry + 22, (lw - 100) * share, 2, N.ACCENT, 1)
			text(fonts.d600, 15, math.floor(s.share * 100 + 0.5) .. "%", lx + lw, ry + 5, N.TEXT, "right")
			ry = ry + 38
		end
	end
	local ty = top + 330
	W.block(1)
	rect(lx, ty - 18, lw, 1, N.LINE)
	W.head(L("bb_todo_title"), lx, ty, lw)
	local todo = view and view.todo or K.NONE
	if #todo == 0 then
		W.empty(L("bb_todo_empty"), lx, ty + 30, lw)
	else
		local ba = G.alpha
		local ly = ty + 28
		for i, line in ipairs(todo) do
			local lines = wrap(fonts.w500, 15, line, lw - 22, 2)
			if ly + #lines * 21 > bottom then break end
			local tkey = line:match("^[^:]*")
			if not W.todo_at[tkey] then
				W.todo_n = W.todo_n + 1
				if W.todo_n > 40 then W.todo_at, W.todo_n = {}, 1 end
				W.todo_at[tkey] = state.clock
			end
			local flash = 1 - math.min(1, (state.clock - W.todo_at[tkey]) / 0.7)
			G.alpha = ba * W.since(state.win.open_at, 0.1 + i * 0.05, 0.24)
			if flash > 0 then dot(lx + 4, ly + 10, 3 + 5 * flash, alpha(N.ACCENT, 0.35 * flash)) end
			dot(lx + 4, ly + 10, 3, N.ACCENT)
			for _, l in ipairs(lines) do
				text(fonts.w500, 15, l, lx + 20, ly, N.TEXT)
				ly = ly + 21
			end
			ly = ly + 8
		end
		G.alpha = ba
	end
	W.block(2)
	rect(rx - 22, top, 1, bottom - top, N.LINE)
	W.head(L("bb_fight_foes"), rx, top, rw)
	local live = view and view.live or K.NONE
	if #live == 0 then
		W.empty(L("bb_enemies_empty"), rx, top + 32, rw)
		return W.unblock()
	end
	local ba = G.alpha
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 4)
	local ey = top + 26
	for i, f in ipairs(live) do
		if ey + 82 > bottom then break end
		local fresh = not W.foe_at[f.unit]
		if fresh then W.foe_at[f.unit] = state.clock end
		G.alpha = ba * W.since(W.foe_at[f.unit], 0, 0.3)
		if i > 1 then rect(rx, ey, rw, 1, N.LINE) end
		W.pic(hero_image(f.unit), rx, ey + 12, 44, 44, 10, f.alive and 0 or 1, true, (not f.alive) and N.DONE or nil)
		local name = hero_title(f.unit)
		if f.fog then name = name .. " · " .. string.format(L("bb_foe_fog"), f.fog) end
		local pw = 0
		if f.go then
			pw = measure(fonts.w600, 12, L("bb_foe_go")) + 14
			dot(rx + rw - pw + 3, ey + 21, 3, N.WIN)
			text(fonts.w600, 12, L("bb_foe_go"), rx + rw, ey + 14, N.WIN, "right")
		end
		text(fonts.w600, 15, fit(fonts.w600, 15, name, rw - 72 - pw), rx + 58, ey + 11, f.fog and N.MUTED or N.TEXT)
		local cx = rx + 58
		if f.hp then
			local hp = tween("hp_" .. f.unit, f.hp, 8)
			rect(cx, ey + 39, 56, 3, N.TRACK, 1)
			rect(cx, ey + 39, 56 * hp, 3, hp < 0.35 and N.WIN or N.LOSE, 1)
			cx = cx + 68
		end
		for k = 1, 2 do
			local label, ok = f.ult, f.ult_ok
			if k == 2 then label, ok = f.bkb, f.bkb_ok end
			if label then
				local lw2 = measure(fonts.w500, 12, label) + 14
				if cx + lw2 <= rx + rw then
					local warn = k == 1 and label == L("bb_foe_ult_ready")
					local c = ok and N.WIN or (warn and alpha(N.LOSE, 0.55 + 0.45 * pulse) or N.LOSE)
					dot(cx + 3, ey + 40, 3, c)
					text(fonts.w500, 12, label, cx + 11, ey + 33, ok and N.MUTED or N.TEXT)
					cx = cx + lw2 + 10
				end
			end
		end
		local seen = W.item_at[f.unit]
		if not seen then
			seen = {}
			W.item_at[f.unit] = seen
		end
		local ix = rx + 58
		for _, item in ipairs(f.items or K.NONE) do
			if ix + 30 > rx + rw then break end
			if not seen[item] then seen[item] = fresh and -10 or state.clock end
			W.pic(item_image(item), ix, ey + 52, 30, 22, 4)
			local glow = 1 - math.min(1, (state.clock - seen[item]) / 2)
			if glow > 0 then frame_line(ix - 2, ey + 50, 34, 26, alpha(N.ACCENT, glow), 6, 1.5) end
			ix = ix + 34
		end
		ey = ey + 84
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
	rect(x, y, 40, 22, mix(N.TRACK, N.ACCENT, t), 11)
	dot(x + 11 + 18 * t, y + 11, 8, mix(N.MUTED, N.INK, t))
end

function W.steps(s, x, y, value)
	local cw = 48
	frame_line(x, y, cw * s.count, 32, N.LINE, 10)
	local sx = tween("steps_x_" .. s.key, x + value * cw, 18)
	rect(sx + 3, y + 3, cw - 6, 26, N.ACCENT, 8)
	for v = 0, s.count - 1 do
		local bx = x + v * cw
		local hot = hover_t("step_" .. s.key .. v, bx, y, cw, 32)
		text(fonts.d500, 14, tostring(s.values[v + 1]), bx + cw / 2, y + 7, v == value and N.INK or mix(N.MUTED, N.TEXT, hot), "center")
		button("step", bx, y, cw, 32, v)
	end
end

function W.dropdown(drop, h)
	local s = drop.def
	local t = tween("dropdown", 1, 16)
	local row = 34
	local shown = {}
	for v = 0, s.count - 1 do
		if not (s.skip and s.skip[v]) then shown[#shown + 1] = v end
	end
	local full = #shown * row + 8
	local y = drop.y
	if y + full > h - 16 then y = drop.y - 41 - full end
	local k = 0.03 * (1 - t)
	local dx, dy, dw, dh = drop.x + drop.w * k / 2, y + full * k / 2, drop.w * (1 - k), full * (1 - k)
	local ba = G.alpha
	G.alpha = ba * t
	W.soft(dx, dy, dw, dh, 12, 22)
	rect(dx, dy, dw, dh, N.PANEL, 12)
	frame_line(dx, dy, dw, dh, N.LINE, 12)
	local current = setting(s.key)
	for i, v in ipairs(shown) do
		local oy = y + 4 + (i - 1) * row
		local hot = hover_t("option" .. v, drop.x + 4, oy, drop.w - 8, row - 2)
		if hot > 0.01 then rect(drop.x + 4, oy, drop.w - 8, row - 2, alpha(N.HOT, hot), 8) end
		text(fonts.w500, 14, fit(fonts.w500, 14, W.label(s, v), drop.w - 44), drop.x + 14, oy + 8, v == current and N.ACCENT or N.TEXT)
		if v == current then W.glyph(K.ONB_CHECK, 11, drop.x + drop.w - 20, oy + row / 2 - 1, N.ACCENT) end
		if t > 0.6 then button("option", drop.x + 4, oy, drop.w - 8, row - 2, v) end
	end
	G.alpha = ba
end

function W.set_row(key, x, y, w, h)
	local hot = hover_t(key, x - 10, y, w + 20, h)
	if hot > 0.01 then rect(x - 10, y + 2, w + 20, h - 4, alpha(N.HOT, hot), 10) end
	rect(x, y + h - 1, w, 1, N.LINE)
	return hot
end

function W.updates(x, y, cw, half, x1, x2)
	W.head(L("bb_upd_title"), x, y, cw)
	local ry = y + 26
	local rh = 56
	rect(x1, ry + rh - 1, half, 1, N.LINE)
	text(fonts.w600, 15, UPD.title, x1, ry + 8, N.TEXT)
	local nl = L("bb_news_title")
	local nx = x1 + measure(fonts.w600, 15, UPD.title) + 14
	local nw = measure(fonts.w500, 13, nl)
	local nh = hover_t("news_open", nx - 4, ry + 6, nw + 8, 22)
	text(fonts.w500, 13, nl, nx, ry + 10, mix(N.ACCENT, N.TEXT, nh))
	rect(nx, ry + 27, nw, 1, alpha(N.ACCENT, 0.4 + 0.6 * nh))
	button("news", nx - 4, ry + 6, nw + 8, 22, "open")
	local line, tone = UPD.line()
	local col = (tone == C.LOSE and N.LOSE) or (tone == C.WIN and N.WIN) or (tone == C.ACCENT and N.ACCENT) or N.MUTED
	local act = UPD.action()
	local bw = 150
	text(fonts.w500, 13, fit(fonts.w500, 13, line, act and half - bw - 12 or half), x1, ry + 30, col)
	if act then
		if act == "check" then
			W.button_ghost("upd_" .. act, L("bb_upd_" .. act), x1 + half - bw, ry + 9, bw, 36, "upd", act)
		else
			W.button_main("upd_" .. act, L("bb_upd_" .. act), x1 + half - bw, ry + 9, bw, 36, "upd", act)
		end
	end
	W.set_row("set_update", x2, ry, half, rh)
	text(fonts.w500, 15, fit(fonts.w500, 15, L("bb_set_update"), half - 60), x2, ry + 18, N.TEXT)
	W.toggle("update", x2 + half - 40, ry + 17, setting("update") == 1)
	button("toggle", x2 - 10, ry, half + 20, rh, "update")
	return ry + rh
end

function W.draw_tip()
	local t = W.tip
	if not t then return end
	W.tip = nil
	local tw = measure(fonts.w500, 13, t.text) + 20
	local tx = math.max(6, math.min(K.WIN_W - 6 - tw, t.x - tw / 2))
	rect(tx, t.y, tw, 28, N.PANEL, 8)
	frame_line(tx, t.y, tw, 28, N.LINE, 8)
	text(fonts.w500, 13, t.text, tx + tw / 2, t.y + 6, N.TEXT, "center")
end

function W.hero_grid(x, y, w, cell, kind)
	local sel = POOL.get()
	local any = POOL.n > 0
	local gap = 5
	local per = math.max(1, math.floor((w + gap) / (cell + gap)))
	W.grid_tip = nil
	for _, g in ipairs(HEROES.list()) do
		dot(x + 3, y + 8, 3, g.color)
		text(fonts.w500, 13, L(g.key), x + 12, y, N.MUTED)
		y = y + 20
		for i, hro in ipairs(g.heroes) do
			local col, row = (i - 1) % per, math.floor((i - 1) / per)
			local hx, hy = x + col * (cell + gap), y + row * (cell + gap)
			local on = sel[hro.id]
			local off = any and not on
			local hot = hover_t(kind .. hro.id, hx, hy, cell, cell)
			W.pic(hero_image(hro.unit), hx, hy, cell, cell, 8, off and 1 or 0, true, off and N.DONE or nil)
			if on then
				frame_line(hx - 2, hy - 2, cell + 4, cell + 4, N.ACCENT, 10, 2)
			elseif hot > 0.01 then
				frame_line(hx, hy, cell, cell, alpha(N.TEXT, 0.4 * hot), 8)
			end
			button(kind, hx, hy, cell, cell, hro.id)
			if hot > 0.5 then W.grid_tip = { name = hro.title, x = hx + cell / 2, y = hy } end
		end
		y = y + math.ceil(#g.heroes / per) * (cell + gap) + 6
	end
	local t = W.grid_tip
	if t then
		local tw = measure(fonts.w600, 13, t.name) + 18
		local tx = math.max(6, math.min(K.WIN_W - 6 - tw, t.x - tw / 2))
		rect(tx, t.y - 30, tw, 26, N.PANEL, 8)
		frame_line(tx, t.y - 30, tw, 26, N.LINE, 8)
		text(fonts.w600, 13, t.name, tx + tw / 2, t.y - 25, N.TEXT, "center")
	end
	return y
end

function W.pool_page(w, h)
	local x, cw = N.X, w - 2 * N.X
	local top = N.TOP
	W.block(0)
	local title = L("bb_pool_title")
	text(fonts.d600, 20, title, x, top - 4, N.TEXT)
	text(fonts.w500, 13, POOL.label(), x + measure(fonts.d600, 20, title) + 14, top + 2, N.MUTED)
	local bx = x + cw - 120
	W.button_main("pool_done", L("bb_pool_done"), bx, top - 8, 120, 36, "pool_done")
	if POOL.n > 0 then W.button_ghost("pool_clear", L("bb_pool_clear"), bx - 128, top - 8, 120, 36, "pool_clear") end
	text(fonts.w500, 13, L("bb_pool_hint"), x, top + 38, N.MUTED)
	W.hero_grid(x, top + 66, cw, 40, "pool")
	W.unblock()
end

function W.onb_heroes(w)
	W.onb_title(L("bb_onb_heroes_q"), L("bb_onb_heroes_s"))
	W.hero_grid(56, 166, w - 112, 34, "pool")
end

function W.settings(w, h)
	if state.win.pool_page then return W.pool_page(w, h) end
	local win = state.win
	local x, cw = N.X, w - 2 * N.X
	local top = N.TOP
	local half = (cw - 56) / 2
	local x1, x2 = x, x + half + 56
	local y1, y2 = top + 24, top + 24
	local rh = 52
	W.block(0)
	W.head(L("bb_tab_settings"), x, top, cw)
	local drop
	for _, s in ipairs(K.SETTINGS) do
		if not s.own then
			local rx, ry = x1, y1
			if s.flag or s.right then rx, ry = x2, y2 end
			local hot = s.values and 0 or W.set_row("set_" .. s.key, rx, ry, half, rh)
			if s.values then rect(rx, ry + rh - 1, half, 1, N.LINE) end
			local value = setting(s.key)
			if s.flag then
				text(fonts.w500, 15, fit(fonts.w500, 15, L(s.title), half - 60), rx, ry + 16, N.TEXT)
				W.toggle(s.key, rx + half - 40, ry + 15, value == 1)
				button("toggle", rx - 10, ry, half + 20, rh, s.key)
			elseif s.values then
				local sx = rx + half - 48 * s.count
				text(fonts.w500, 15, fit(fonts.w500, 15, L(s.title), sx - rx - 12), rx, ry + 16, N.TEXT)
				W.steps(s, sx, ry + 10, value)
			else
				local open = win.dropdown == s.key
				local bw = 190
				local bx = rx + half - bw
				text(fonts.w500, 15, fit(fonts.w500, 15, L(s.title), bx - rx - 12), rx, ry + 16, N.TEXT)
				local ot = tween("open_" .. s.key, open and 1 or 0, 18)
				frame_line(bx, ry + 9, bw, 34, mix(mix(N.LINE, N.DIM, hot), N.ACCENT, ot), 10)
				text(fonts.w500, 14, fit(fonts.w500, 14, W.label(s, value), bw - 40), bx + 12, ry + 17, N.TEXT)
				chevron(bx + bw - 16, ry + 26, ot, mix(N.MUTED, N.ACCENT, ot))
				button("dropdown", rx - 10, ry, half + 20, rh, s.key)
				if open then
					drop = W.drop
					drop.def, drop.x, drop.y, drop.w = s, bx, ry + 46, bw
				end
			end
			if s.flag or s.right then y2 = ry + rh else y1 = ry + rh end
		end
	end
	W.set_row("set_pool", x1, y1, half, rh)
	text(fonts.w500, 15, L("bb_pool_title"), x1, y1 + 7, N.TEXT)
	text(fonts.w500, 13, POOL.label(), x1, y1 + 28, N.MUTED)
	W.button_ghost("pool_open", L("bb_pool_pick"), x1 + half - 150, y1 + 9, 150, 34, "pool_open")
	y1 = y1 + rh
	text(fonts.w500, 13, L("bb_set_key_hint"), x2, y2 + 16, N.MUTED)
	W.block(1)
	W.updates(x, math.max(y1, y2) + 24, cw, half, x1, x2)
	W.block(0)
	if drop then W.dropdown(drop, h) end
	W.unblock()
end

W.onb = { active = nil, step = 0, at = 0, step_at = 0, role = 0, mode = 0, shop = 1, auto = 1 }

function W.onb_start()
	local o = W.onb
	o.active, o.step, o.at, o.step_at = true, 0, state.clock, state.clock
	o.role, o.mode, o.shop, o.auto = setting("role"), setting("mode"), setting("shop"), setting("auto")
	state.win.visible, state.win.dropdown = true, nil
end

function W.onb_finish()
	local o = W.onb
	set_setting("role", o.role)
	set_setting("mode", o.mode)
	set_setting("shop", o.shop)
	set_setting("auto", o.auto)
	Config.WriteInt(K.CONFIG, "onboard2", 1)
	o.active = false
	local win = state.win
	win.tab = Heroes.GetLocal() and "build" or "draft"
	win.drawn_tab, win.prev_tab, win.open_at = win.tab, nil, state.clock
	win.visible, win.closed_by_user = true, false
	state.next_model, state.next_data = 0, 0
end

function W.onb_act(v)
	local o = W.onb
	local kind, arg = tostring(v):match("^(%a+):?(%w*)$")
	if kind == "next" then
		o.step, o.step_at = math.min(5, o.step + 1), state.clock
	elseif kind == "back" then
		o.step, o.step_at = math.max(0, o.step - 1), state.clock
		if o.step == 0 then o.at = state.clock end
	elseif kind == "skip" then
		o.step, o.step_at = 5, state.clock
	elseif kind == "role" then
		o.role = tonumber(arg) or 0
	elseif kind == "mode" then
		o.mode = tonumber(arg) or 0
	elseif kind == "flip" and (arg == "shop" or arg == "auto") then
		o[arg] = 1 - o[arg]
	elseif kind == "go" then
		W.onb_finish()
	end
end

function W.role_icon(pos)
	local path = state.role_paths[pos]
	if not path then
		path = "panorama/images/rank_tier_icons/handicap/" .. K.ROLE_ICONS[pos] .. "icon_psd.vtex_c"
		state.role_paths[pos] = path
	end
	return load_image(path)
end

function W.onb_rise(t, delay, ba, by0)
	local k = W.ease((t - delay) / 0.5)
	G.alpha, G.oy = ba * k, by0 + (1 - k) * 14 * G.s
end

function W.onb_main_btn(key, label, x, y, w, h, value)
	W.button_main(key, label, x, y, w, h, "onb", value)
end

function W.onb_card(key, x, y, cw, ch, on, value)
	local hot = hover_t(key, x, y, cw, ch)
	local t = tween(key .. "_on", on and 1 or 0, 16)
	rect(x, y, cw, ch, mix(N.PANEL, N.SLOT, hot), 16)
	frame_line(x, y, cw, ch, mix(mix(N.LINE, N.DIM, hot), N.ACCENT, t), 16, 1 + t * 0.6)
	button("onb", x, y, cw, ch, value)
	return t
end

function W.onb_check(x, y, t)
	if t > 0.01 then W.glyph(K.ONB_CHECK, 12, x, y, alpha(N.ACCENT, t)) end
end

function W.onb_title(q, s)
	text(fonts.d600, 30, q, 56, 86, N.TEXT)
	text(fonts.w500, 15, s, 56, 130, N.MUTED)
end

function W.onb_intro(w)
	local o = W.onb
	local ba, by0 = G.alpha, G.oy
	local cx, cy = w / 2, 214
	local t = state.clock - o.at
	local e = W.ease(t / 0.6)
	G.alpha = ba * e
	W.glyph(K.LOGO, 40, cx, cy + (1 - e) * 10, N.ACCENT)
	W.onb_rise(t, 0.25, ba, by0)
	local title = L("bb_title")
	text(fonts.d700, 54, title, cx, cy + 40, N.TEXT, "center")
	local lw = measure(fonts.d700, 54, title) * W.ease((t - 0.5) / 0.6)
	if lw > 1 then rect(cx - lw / 2, cy + 112, lw, 2, N.ACCENT, 1) end
	W.onb_rise(t, 0.55, ba, by0)
	text(fonts.w500, 18, L("bb_onb_hello"), cx, cy + 134, N.MUTED, "center")
	W.onb_rise(t, 0.75, ba, by0)
	W.onb_main_btn("onb_start", L("bb_onb_start"), cx - 100, cy + 186, 200, 46, "next")
	text(fonts.w500, 13, L("bb_onb_note"), cx, cy + 250, N.DIM, "center")
	G.alpha, G.oy = ba, by0
end

function W.onb_roles(w)
	local o = W.onb
	W.onb_title(L("bb_onb_role_q"), L("bb_onb_role_s"))
	local cw, ch = (w - 112 - 24) / 3, 112
	for i, id in ipairs(K.ONB_ROLES) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local x, y = 56 + col * (cw + 12), 172 + row * (ch + 12)
		local t = W.onb_card("onb_r" .. id, x, y, cw, ch, o.role == id, "role:" .. id)
		local icon = id > 0 and W.role_icon(id)
		local tint = mix(N.MUTED, N.ACCENT, t)
		if icon then
			picture(icon, x + 20, y + 20, 26, 26, nil, 0, false, tint)
		else
			text(fonts.d700, 20, "A", x + 33, y + 21, tint, "center")
		end
		W.onb_check(x + cw - 24, y + 33, t)
		text(fonts.w600, 16, L("bb_onb_r" .. id), x + 20, y + 62, N.TEXT)
		text(fonts.w500, 13, fit(fonts.w500, 13, L("bb_onb_rs" .. id), cw - 40), x + 20, y + 84, N.MUTED)
	end
end

function W.onb_modes(w)
	local o = W.onb
	W.onb_title(L("bb_onb_mode_q"), L("bb_onb_mode_s"))
	local cw, ch = (w - 112 - 24) / 3, 210
	for m = 0, 2 do
		local x, y = 56 + m * (cw + 12), 172
		local t = W.onb_card("onb_m" .. m, x, y, cw, ch, o.mode == m, "mode:" .. m)
		W.glyph(K.ONB_MODE_ICONS[m + 1], 24, x + 38, y + 42, mix(N.MUTED, N.ACCENT, t))
		W.onb_check(x + cw - 26, y + 36, t)
		text(fonts.d600, 20, L("bb_onb_m" .. m), x + 22, y + 132, N.TEXT)
		for k, l in ipairs(wrap(fonts.w500, 13, L("bb_onb_ms" .. m), cw - 44, 2)) do text(fonts.w500, 13, l, x + 22, y + 162 + (k - 1) * 19, N.MUTED) end
	end
end

function W.onb_where(w)
	local o = W.onb
	W.onb_title(L("bb_onb_where_q"), L("bb_onb_where_s"))
	local cw, ch = (w - 112 - 16) / 2, 262
	for i, key in ipairs(W.WHERE) do
		local x, y = 56 + (i - 1) * (cw + 16), 172
		local on = o[key] == 1
		local t = W.onb_card("onb_w" .. key, x, y, cw, ch, on, "flip:" .. key)
		local a, b = i == 1 and 96 or 150, i == 1 and 150 or 96
		local ix = x + (cw - a - b - 8) / 2
		if t > 0.01 then rect(ix, y + 22, a, 110, alpha(N.ACCENT_SOFT, t), 10) end
		frame_line(ix, y + 22, a, 110, mix(N.LINE, N.ACCENT, t), 10, 1.5)
		frame_line(ix + a + 8, y + 22, b, 110, N.LINE, 10)
		text(fonts.w600, 16, L("bb_onb_" .. key), x + 22, y + 164, N.TEXT)
		for k, l in ipairs(wrap(fonts.w500, 13, L("bb_onb_" .. key .. "_s"), cw - 110, 2)) do text(fonts.w500, 13, l, x + 22, y + 190 + (k - 1) * 19, N.MUTED) end
		W.toggle("onb_" .. key, x + cw - 62, y + 166, on)
	end
end

function W.onb_nav(w, h)
	local o = W.onb
	local y = h - 66
	W.button_ghost("onb_back", L("bb_onb_back"), 56, y, 110, 42, "onb", "back")
	local dx = w / 2 - 46
	for i = 1, 5 do
		local dw = tween("onb_dot" .. i, i == o.step and 28 or 8, 14)
		rect(dx, y + 18, dw, 6, i <= o.step and N.ACCENT or N.TRACK, 3)
		dx = dx + dw + 8
	end
	W.onb_main_btn("onb_next", L(o.step == 4 and "bb_onb_finish" or "bb_onb_next"), w - 56 - 140, y, 140, 42, "next")
end

function W.onb_done(w)
	local o = W.onb
	local ba, by0 = G.alpha, G.oy
	local t = state.clock - o.step_at
	local cx, cy = w / 2, 226
	local sc = W.pop(t)
	G.alpha = ba * math.min(1, t / 0.2)
	local r = 40 * sc
	frame_line(cx - r, cy - r, r * 2, r * 2, N.ACCENT, r, 2)
	W.glyph(K.ONB_CHECK, math.floor(28 * sc + 0.5), cx, cy, N.ACCENT)
	W.onb_rise(t, 0.2, ba, by0)
	text(fonts.d600, 34, L("bb_onb_done"), cx, cy + 62, N.TEXT, "center")
	W.onb_rise(t, 0.35, ba, by0)
	local pills = { o.role > 0 and L("bb_onb_r" .. o.role) or L("bb_onb_lobby"), L("bb_onb_m" .. o.mode), L(o.shop == 1 and "bb_onb_shop_on" or "bb_onb_shop_off"), POOL.label() }
	local ws, total = {}, -8
	for i, p in ipairs(pills) do
		ws[i] = measure(fonts.w600, 14, p) + 28
		total = total + ws[i] + 8
	end
	local px = cx - total / 2
	for i, p in ipairs(pills) do
		frame_line(px, cy + 116, ws[i], 34, N.LINE, 17)
		text(fonts.w600, 14, p, px + ws[i] / 2, cy + 124, N.TEXT, "center")
		px = px + ws[i] + 8
	end
	text(fonts.w500, 14, L("bb_onb_change"), cx, cy + 166, N.MUTED, "center")
	W.onb_rise(t, 0.5, ba, by0)
	W.onb_main_btn("onb_go", L("bb_onb_go"), cx - 100, cy + 206, 200, 46, "go")
	G.alpha, G.oy = ba, by0
end

function W.onboard(w, h)
	local o = W.onb
	local ba, bx0 = G.alpha, G.ox
	W.shell(w, h)
	rect(0, N.HEAD - 1, w, 1, N.LINE)
	button("header", 0, 0, w - 160, N.HEAD)
	text(fonts.d600, 17, L("bb_title"), N.X, 17, N.TEXT)
	if o.step >= 1 and o.step <= 4 then text(fonts.w500, 13, string.format(L("bb_onb_step"), o.step), w / 2, 21, N.MUTED, "center") end
	if o.step < 5 then
		local label = L("bb_onb_skip")
		local lw = measure(fonts.w600, 13, label)
		local hot = hover_t("onb_skip", w - 36 - lw, 12, lw + 16, 32)
		text(fonts.w600, 13, label, w - N.X, 21, mix(N.MUTED, N.TEXT, hot), "right")
		button("onb", w - 36 - lw, 12, lw + 16, 32, "skip")
	end
	if o.step == 0 then
		W.onb_intro(w)
	elseif o.step == 5 then
		W.onb_done(w)
	else
		local e = W.ease((state.clock - o.step_at) / 0.35)
		G.alpha, G.ox = ba * e, bx0 + (1 - e) * 24 * G.s
		if o.step == 1 then
			W.onb_roles(w)
		elseif o.step == 2 then
			W.onb_heroes(w)
		elseif o.step == 3 then
			W.onb_modes(w)
		else
			W.onb_where(w)
		end
		G.alpha, G.ox = ba, bx0
		W.onb_nav(w, h)
	end
	G.alpha, G.ox = ba, bx0
end

W.news = { active = false, pending = false, at = 0, x = 0, y = 0, w = 0, h = 0, was = false }

function W.news_close()
	W.news.active = false
	Config.WriteString(K.CONFIG, "news_seen", K.VERSION)
	state.win.visible = W.news.was
end

function W.news_act(v)
	if v == "none" then return end
	if v == "open" then
		W.news.active, W.news.pending, W.news.at, W.news.was = true, false, state.clock, state.win.visible
		state.win.dropdown = nil
		return
	end
	if v == "tg" then LINK.open("tg") end
	W.news_close()
end

function W.news_draw(open)
	local n = W.news
	local s, screen = W.scale()
	local w = K.NEWS_W
	local x = 28
	local rows, rows_h = {}, 0
	for i, key in ipairs(K.NEWS) do
		rows[i] = wrap(fonts.w500, 13, L(key), w - x * 2 - 30, 2)
		rows_h = rows_h + 32 + (#rows[i] - 1) * 18
	end
	local h = 150 + rows_h + 104
	n.w, n.h = w * s, h * s
	n.x, n.y = math.floor((screen.x - n.w) / 2), math.floor((screen.y - n.h) / 2)
	local t = state.clock - n.at
	local e = W.ease(t / 0.45)
	local fade = open * W.ease(t / 0.3)
	G.ox, G.oy, G.s, G.alpha = 0, 0, 1, fade
	pcall(Render.Blur, Vec2(0, 0), Vec2(screen.x, screen.y), K.NEWS_BLUR, fade, 0)
	rect(0, 0, screen.x, screen.y, alpha(N.BG, 0.45))
	button("news", 0, 0, screen.x, screen.y, "ok")
	G.ox, G.oy, G.s, G.alpha = n.x, n.y + (1 - e) * 12 * s, s, open * e
	local ba, by0 = G.alpha, G.oy
	W.shell(w, h)
	button("news", 0, 0, w, h, "none")
	text(fonts.w500, 12, string.format(L("bb_news_head"), K.VERSION), x, 24, N.MUTED)
	local bx, by, bw, bh, hot = W.btn("news_x", w - 48, 14, 28, 28)
	if hot > 0.01 then rect(bx, by, bw, bh, alpha(N.HOT, hot), 9) end
	W.glyph(K.CLOSE, 13, bx + bw / 2, by + bh / 2, mix(N.MUTED, N.TEXT, hot))
	button("news", w - 48, 14, 28, 28, "ok")
	W.onb_rise(t, 0.08, ba, by0)
	text(fonts.d600, 26, L("bb_news_title"), x, 52, N.TEXT)
	text(fonts.w500, 13, L("bb_news_sub"), x, 92, N.MUTED)
	local y = 130
	for i, lines in ipairs(rows) do
		W.onb_rise(t, 0.16 + i * 0.07, ba, by0)
		rect(x, y - 8, w - x * 2, 1, N.LINE)
		W.glyph(K.ONB_CHECK, 11, x + 7, y + 12, N.ACCENT)
		for k, line in ipairs(lines) do text(fonts.w500, 13, line, x + 24, y + 3 + (k - 1) * 18, N.TEXT) end
		y = y + 32 + (#lines - 1) * 18
	end
	rect(x, y - 8, w - x * 2, 1, N.LINE)
	W.onb_rise(t, 0.2 + #K.NEWS * 0.07, ba, by0)
	y = y + 16
	local okw = 104
	local tw = w - x * 2 - okw - 10
	local tx, ty, tww, thh, th = W.btn("news_tg", x, y, tw, 40)
	rect(tx, ty, tww, thh, mix(N.TG, N.TG_HOT, th), 10)
	local label = L("bb_news_tg")
	local lw, lh = measure(fonts.w600, 14, label)
	local gx = tx + tww / 2 - (lw + 22) / 2
	W.glyph(K.TG_ICON, 13, gx + 7, ty + thh / 2 + 1, N.TEXT_ON)
	text(fonts.w600, 14, label, gx + 22, ty + (thh - lh) / 2, N.TEXT_ON)
	button("news", x, y, tw, 40, "tg")
	W.button_ghost("news_ok", L("bb_news_ok"), x + tw + 10, y, okw, 40, "news", "ok")
	text(fonts.w500, 12, L("bb_news_note"), w / 2, y + 54, N.DIM, "center")
	G.alpha, G.oy = ba, by0
end

function W.card_hit()
	local r = W.cardst and W.cardst.rect
	return r ~= nil and cursor_in(r.x1, r.y1, r.x2, r.y2)
end

function W.item_vs(view, name)
	for _, t in ipairs(view.vs_rows or K.NONE) do
		for _, o in ipairs(t.options or K.NONE) do
			if o == name then return t.text end
		end
	end
	return nil
end

function W.item_card(w, h)
	local c = W.cardst
	local cand = W.hov_cand
	local now = state.clock
	local view = state.view
	if cand then
		if not c or c.name ~= cand.name then
			c = { name = cand.name, orig = cand.orig, at = now, menu = false, alts = EDIT.alts(cand.orig, view) }
			W.cardst = c
		end
		c.x, c.y, c.iw, c.ih, c.seen = cand.x, cand.y, cand.w, cand.h, now
	elseif c then
		local r = c.rect
		local cx, cy = Input.GetCursorPos()
		if r and cx >= r.x1 and cx <= r.x2 and cy >= r.y1 and cy <= r.y2 then
			c.seen = now
		elseif now - c.seen > 0.3 then
			W.cardst = nil
			return
		end
	end
	if not c or now - c.at < 0.25 then return end
	local step = nil
	for _, st in ipairs(view and view.route or K.NONE) do
		if st.name == c.name then step = st end
	end
	if not step then
		W.cardst = nil
		return
	end
	local ed = EDIT.get(view.edit_id)
	local cw = 300
	local lines = {}
	if step.from then lines[#lines + 1] = { string.format(L("bb_card_from"), item_title(step.from)), N.MUTED } end
	if step.share and state.turbo then
		lines[#lines + 1] = { string.format(L("bb_next_share"), math.floor(step.share * 100 + 0.5)), N.MUTED }
	elseif step.share and step.tm and step.tm > 0 then
		lines[#lines + 1] = { string.format(L("bb_card_usual"), math.floor(step.share * 100 + 0.5), math.floor(step.tm / 60 + 0.5)), N.MUTED }
	end
	local vs = W.item_vs(view, step.name)
	if vs then lines[#lines + 1] = { vs, N.TEXT } end
	local wrapped = {}
	for _, l in ipairs(lines) do
		for _, part in ipairs(wrap(fonts.w500, 13, l[1], cw - 28, 2)) do wrapped[#wrapped + 1] = { part, l[2] } end
	end
	local alts = c.alts or K.NONE
	local menu = c.menu and #alts > 0
	local ch = 14 + 42 + 12 + #wrapped * 19 + 10 + 34 + (menu and (12 + 18 + #alts * 42) or 0) + 12 + 20 + 14
	local x = math.max(N.X, math.min(w - 16 - cw, c.x - 20))
	local y = c.y + c.ih + 24
	if y + ch > h - 8 then
		y = c.y - ch - 8
		if y < 8 then
			y = math.max(8, math.min(h - 8 - ch, c.y - 60))
			x = c.x + c.iw + 12
			if x + cw > w - 8 then x = c.x - cw - 12 end
		end
	end
	local ba = G.alpha
	G.alpha = ba * W.ease((now - c.at - 0.25) / 0.15)
	W.soft(x, y, cw, ch, 14, 22)
	rect(x, y, cw, ch, N.PANEL, 14)
	frame_line(x, y, cw, ch, N.LINE, 14)
	button("card_bg", x, y, cw, ch)
	W.pic(item_image(step.name), x + 14, y + 14, 56, 41, 6)
	text(fonts.w600, 15, fit(fonts.w600, 15, item_title(step.name), cw - 96), x + 82, y + 16, N.TEXT)
	text(fonts.d500, 14, string.format(L("bb_card_cost"), step.cost or item_cost(step.name)), x + 82, y + 38, N.MUTED)
	local ly = y + 68
	for _, l in ipairs(wrapped) do
		text(fonts.w500, 13, l[1], x + 14, ly, l[2])
		ly = ly + 19
	end
	ly = ly + 10
	local bw = (cw - 36) / 2
	local back = step.skipped or step.from
	W.button_ghost("card_a", L(back and "bb_card_back" or "bb_card_skip"), x + 14, ly, bw, 34, "card", back and "back" or "skip")
	local rx = x + 22 + bw
	if #alts > 0 then
		W.button_ghost("card_b", L("bb_card_replace"), rx, ly, bw, 34, "card", "menu", menu)
	else
		text(fonts.w500, 13, L("bb_card_none"), rx + bw / 2, ly + 9, N.DIM, "center")
	end
	ly = ly + 34
	if menu then
		ly = ly + 12
		rect(x + 14, ly - 6, cw - 28, 1, N.LINE)
		text(fonts.w500, 12, L("bb_card_alts"), x + 14, ly, N.MUTED)
		ly = ly + 18
		for i, a in ipairs(alts) do
			local ah = hover_t("card_alt" .. i, x + 8, ly, cw - 16, 40)
			if ah > 0.01 then rect(x + 8, ly, cw - 16, 40, alpha(N.HOT, ah), 8) end
			W.pic(item_image(a.name), x + 14, ly + 5, 40, 29, 4)
			text(fonts.w600, 13, fit(fonts.w600, 13, item_title(a.name), cw - 150), x + 64, ly + 11, N.TEXT)
			text(fonts.d500, 13, string.format(L("bb_card_share"), math.floor(a.share * 100 + 0.5)), x + cw - 16, ly + 12, N.MUTED, "right")
			button("card", x + 8, ly, cw - 16, 40, "alt:" .. i)
			ly = ly + 42
		end
	end
	ly = ly + 12
	local on = ed and ed.always
	local kh = hover_t("card_keep", x + 10, ly - 2, cw - 20, 24)
	if on then
		rect(x + 14, ly + 2, 16, 16, N.ACCENT, 5)
		W.glyph(K.ONB_CHECK, 9, x + 22, ly + 10, N.INK)
	else
		frame_line(x + 14, ly + 2, 16, 16, mix(N.LINE, N.MUTED, kh), 5)
	end
	text(fonts.w500, 13, L("bb_card_always"), x + 40, ly + 2, mix(N.MUTED, N.TEXT, kh))
	button("card", x + 10, ly - 2, cw - 20, 24, "always")
	local a, b = P(x, y), P(x + cw, y + ch)
	c.rect = { x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y }
	G.alpha = ba
end

function W.card_act(v)
	local c = W.cardst
	local view = state.view
	if not c or not view then return end
	local kind, arg = tostring(v):match("^(%a+):?(%d*)$")
	if kind == "menu" then
		c.menu = not c.menu
		return
	end
	if kind == "alt" then
		local a = c.alts and c.alts[tonumber(arg) or 0]
		if not a then return end
		EDIT.act(view.edit_id, c.orig, c.name, "alt", a)
	else
		EDIT.act(view.edit_id, c.orig, c.name, kind)
	end
	if kind ~= "always" then W.cardst = nil end
end

function W.tab(name, w, h)
	if name == "draft" then
		W.draft(w, h)
	elseif name == "build" then
		W.build(w, h)
	elseif name == "fight" then
		W.fight(w, h)
	elseif name == "party" then
		W.party(w, h)
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
	if W.onb.active == nil then
		W.onb.active = false
		if not Config.mem and Config.ReadInt(K.CONFIG, "onboard2", 0) == 0 then
			W.onb_start()
			Config.WriteString(K.CONFIG, "news_seen", K.VERSION)
		elseif not Config.mem and Config.ReadString(K.CONFIG, "news_seen", "") ~= K.VERSION then
			W.news.pending = true
		end
	elseif W.news.pending then
		local okg, gs = pcall(GameRules.GetGameState)
		if not okg or gs ~= Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
			W.news.pending = false
			W.news.active, W.news.at, W.news.was = true, state.clock, win.visible
			win.visible, win.dropdown = true, nil
		end
	elseif W.news.active and not win.visible then
		W.news.active = false
		Config.WriteString(K.CONFIG, "news_seen", K.VERSION)
	elseif W.onb.active and not win.visible then
		W.onb.active = false
		Config.WriteInt(K.CONFIG, "onboard2", 1)
	end
	local open = tween("win", win.visible and 1 or 0, 14)
	if open < 0.01 then
		win.was_open = false
		return
	end
	if not win.was_open then
		win.was_open = true
		win.open_at = state.clock
		win.drawn_tab, win.prev_tab = win.tab, nil
		win.dir = 0
		state.anim.fight_ring = 0
	end
	if win.drawn_tab ~= win.tab then
		win.dir = (W.ORDER[win.tab] or 0) > (W.ORDER[win.drawn_tab] or 0) and 1 or -1
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
	local base_y = win.y + (1 - open) * 10 * s
	G.ox, G.oy, G.s, G.alpha = win.x, base_y, s, open
	G.buttons = list
	W.base_x, W.base_y, W.base_a, W.dir = win.x, base_y, open, 0
	if W.onb.active then
		W.onboard(w, h)
		G.alpha, G.oy, G.ox = 1, base_y, win.x
		return
	end
	if W.news.active then
		W.news_draw(open)
		G.alpha = 1
		return
	end
	W.shell(w, h)
	W.header(w)
	local out = win.prev_tab and (state.clock - win.tab_at) / 0.14 or 1
	if out < 1 then
		local dead = W.dead
		for i = #dead, 1, -1 do dead[i] = nil end
		G.buttons = dead
		W.base_a, W.flat = open * (1 - W.ease(out)), true
		W.tab(win.prev_tab, w, h)
		W.flat = false
		G.buttons = list
	else
		win.prev_tab = nil
	end
	W.base_a = open
	W.dir = (win.tab_at and state.clock - win.tab_at < 0.6) and (win.dir or 0) or 0
	W.hov_cand = nil
	W.tab(win.tab, w, h)
	if win.tab == "build" then W.item_card(w, h) else W.cardst = nil end
	G.alpha, G.oy, G.ox = open, base_y, win.x
	W.draw_tip()
	G.alpha = 1
end

local LFG = { av = {}, need = {}, next_av = 0, list = {}, list_at = 0, next_list = 0, busy = {}, filter = { rank = true, mode = nil, lang = nil }, form = { open = false, mode = 1, roles = 31, spread = 1, lang = nil, auto = true }, own = nil, next_host = 0, asks = {}, invited = {}, waiting = {}, join = nil, next_join = 0, rank = nil, rank_asked = false, version = nil, msg = nil, msg_at = 0, pb = nil }

function LFG.ok()
	if LFG.on == nil then LFG.on = Config.ReadInt(K.CONFIG, "lfg_ok", 0) == 1 end
	return LFG.on
end

function LFG.sid()
	local ok, sid = pcall(GC.GetSteamID)
	sid = ok and tostring(sid or "") or ""
	if sid:match("^7656119%d%d%d%d%d%d%d%d%d%d$") then return sid end
	return nil
end

function LFG.name()
	local ok, name = pcall(Steam.GetPersonaName)
	return ok and type(name) == "string" and name ~= "" and name or "?"
end

function LFG.lang()
	if LFG.form.lang then return LFG.form.lang end
	local ok, lang = pcall(Steam.GetGameLanguage)
	LFG.form.lang = ok and lang == "russian" and "ru" or "en"
	return LFG.form.lang
end

function LFG.say(key, arg)
	LFG.msg = arg and string.format(L(key), arg) or L(key)
	LFG.msg_at = state.clock
end

function LFG.ver()
	return LFG.version
end

function LFG.proto()
	if LFG.pb == nil then
		local ok, pb = pcall(require, "protobuf")
		LFG.pb = ok and pb or false
	end
	return LFG.pb or nil
end

function LFG.gc(name, data, id)
	local pb = LFG.proto()
	if not pb then return false end
	local ok, req = pcall(pb.encodeFromJSON, name, encode(data))
	if not ok or not req then return false end
	return pcall(GC.SendMessage, req.binary, id, req.size)
end

function LFG.read(name, buffer, size)
	local pb = LFG.proto()
	if not pb or not buffer then return nil end
	local ok, text = pcall(pb.decodeToJSON, name, buffer, size)
	return ok and decode(text) or nil
end

function LFG.req(method, path, body, done)
	local key = method .. path:match("^/%w+")
	local since = LFG.busy[key]
	if since and state.clock - since < K.NET_TIMEOUT + 5 then return end
	LFG.busy[key] = state.clock
	LFG.seq = (LFG.seq or 0) + 1
	local tag = "lfg" .. LFG.seq
	local opts = { timeout = K.NET_TIMEOUT }
	if body then
		opts.headers = { ["Content-Type"] = "application/json" }
		opts.data = encode(body)
	end
	local ok, sent = pcall(HTTP.Request, method, K.LFG_URL .. path, opts, function(res)
		if LFG.busy[key] then LFG.busy[key] = nil end
		local data = type(res) == "table" and decode(res.response) or nil
		local code = type(res) == "table" and tonumber(res.code) or 0
		local okd, err = pcall(done, type(data) == "table" and data or {}, code or 0)
		if not okd then Log.Write("[Build Brain] party " .. path .. ": " .. tostring(err)) end
	end, tag)
	if not ok or sent == false then
		LFG.busy[key] = nil
		LFG.offline = true
	end
end

function LFG.ask_rank()
	if LFG.rank_asked then return end
	local sid = LFG.sid()
	if not sid then return end
	LFG.rank_asked = true
	LFG.gc("CMsgClientToGCGetProfileCard", { account_id = math.tointeger(tonumber(sid)) - K.STEAM_BASE }, K.MSG_CARD)
end

function LFG.fits(p)
	if not LFG.rank or not p.rank then return true end
	local spread = K.LFG_SPREAD[(p.spread or 2) + 1] or 99
	return math.abs(LFG.rank // 10 - p.rank // 10) <= spread
end

function LFG.rank_label(r)
	r = tonumber(r) or 0
	local medal, star = r // 10, r % 10
	if medal < 1 or medal > 8 then return L("bb_lfg_norank") end
	if medal == 8 or star == 0 then return L("bb_medal_" .. medal) end
	return L("bb_medal_" .. medal) .. " " .. star
end

function LFG.medal_name(m)
	if m < 1 or m > 8 then return L("bb_lfg_norank") end
	return L("bb_medal_" .. m)
end

function LFG.range_text(spread)
	local d = K.LFG_SPREAD[(spread or 2) + 1] or 99
	if d >= 8 then return L("bb_lfg_range_all") end
	local m = (LFG.rank or 0) // 10
	local lo, hi = math.max(0, m - d), math.min(8, m + d)
	if lo == hi then return string.format(L("bb_lfg_range_one"), LFG.medal_name(lo)) end
	return string.format(L("bb_lfg_range"), LFG.medal_name(lo), LFG.medal_name(hi))
end

function LFG.save()
	local own = LFG.own
	if not own then
		Config.WriteString(K.CONFIG, "lfg_own", "")
		return
	end
	local left = math.max(0, math.floor(own.ends - state.clock))
	Config.WriteString(K.CONFIG, "lfg_own", table.concat({ own.token, own.id, os.time() + left, own.mode, own.roles, LFG.sid() or "0" }, "|"))
end

function LFG.restore()
	if LFG.restored then return end
	LFG.restored = true
	local raw = Config.ReadString(K.CONFIG, "lfg_own", "")
	local token, id, epoch, mode, roles, sid = raw:match("^(%x+)|(%x+)|(%d+)|(%d+)|(%d+)|(%d+)$")
	local left = epoch and (tonumber(epoch) - os.time()) or 0
	if not token or left < 20 or sid ~= LFG.sid() then return end
	LFG.own = { token = token, id = id, ends = state.clock + left, size = 1, mode = tonumber(mode), roles = tonumber(roles) }
	LFG.next_host = 0
end

function LFG.finish(key)
	if not LFG.own then return end
	LFG.act("close")
	if key then LFG.say(key) end
end

function LFG.medal(x, y, size, r)
	r = tonumber(r) or 0
	local medal, star = r // 10, r % 10
	if medal < 0 or medal > 8 then medal, star = 0, 0 end
	W.pic(load_image("panorama/images/rank_tier_icons/rank" .. medal .. "_psd.vtex_c"), x, y, size, size, 0)
	if medal >= 1 and medal <= 7 and star >= 1 and star <= 7 then
		W.pic(load_image("panorama/images/rank_tier_icons/pip" .. star .. "_psd.vtex_c"), x, y, size, size, 0)
	end
end

function LFG.tint(key)
	local hsum = 0
	for i = 1, #key do hsum = (hsum * 31 + key:byte(i)) % 997 end
	return K.LFG_TINTS[hsum % #K.LFG_TINTS + 1]
end

function LFG.path(sid)
	local dir = Engine.GetCheatDirectory() or ""
	if dir ~= "" and not dir:match("[\\/]$") then dir = dir .. "\\" end
	return dir .. "images\\bb_av_" .. sid .. ".b64"
end

function LFG.load(sid, b64)
	if not b64 then b64 = read_file(LFG.path(sid)) end
	if type(b64) ~= "string" or #b64 < K.LFG_AV_MIN then return nil end
	local svg = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64" viewBox="0 0 64 64"><image width="64" height="64" xlink:href="data:image/jpeg;base64,' .. b64 .. '"/></svg>'
	local ok, handle = pcall(Render.LoadSvgString, svg, Vec2(64, 64), "bbav" .. sid)
	if ok and type(handle) == "number" and handle > 0 then return handle end
	return nil
end

function LFG.avatar(sid)
	local h = LFG.av[sid]
	if h then return h end
	if h == false then return nil end
	local okp, sh = pcall(Steam.GetProfilePictureBySteamId, math.tointeger(tonumber(sid)), false)
	if okp and type(sh) == "number" and sh > 0 then
		LFG.av[sid] = sh
		return sh
	end
	local disk = LFG.load(sid)
	LFG.av[sid] = disk or false
	if not disk then LFG.need[sid] = true end
	return disk
end

function LFG.fetch_avatars()
	if state.clock < LFG.next_av or not next(LFG.need) then return end
	LFG.next_av = state.clock + K.LFG_AV_STEP
	local ids = {}
	for sid in pairs(LFG.need) do
		if #ids < K.LFG_AV_BATCH then ids[#ids + 1] = sid end
	end
	for _, sid in ipairs(ids) do LFG.need[sid] = nil end
	LFG.req("GET", "/avatars?ids=" .. table.concat(ids, ","), nil, function(data, code)
		if code ~= 200 then
			for _, sid in ipairs(ids) do
				if LFG.av[sid] == false then LFG.av[sid] = nil end
			end
			LFG.next_av = state.clock + K.LFG_AV_RETRY
			return
		end
		for sid, b64 in pairs(data) do
			if type(sid) == "string" and sid:match("^%d+$") and type(b64) == "string" and #b64 > K.LFG_AV_MIN then
				local okb, fb = pcall(io.open, LFG.path(sid), "wb")
				if okb and fb then
					fb:write(b64)
					fb:close()
				end
				LFG.av[sid] = LFG.load(sid, b64) or false
			end
		end
	end)
end

function LFG.over()
	local win = state.win
	if not win.visible or not win.x then return false end
	local sc = win.scale or G.s
	return cursor_in(win.x, win.y, win.x + K.WIN_W * sc, win.y + K.WIN_H * sc)
end

function LFG.wheel(dir)
	LFG.scroll_to = math.max(0, math.min(LFG.scroll_max or 0, (LFG.scroll_to or 0) - dir * K.LFG_ROW))
end

function LFG.roles(mask)
	local out = {}
	for p = 1, 5 do
		if mask & (1 << (p - 1)) ~= 0 then out[#out + 1] = L("bb_role_" .. p) end
	end
	if #out == 5 then return { L("bb_lfg_any") } end
	return out
end

function LFG.tick()
	if not LFG.ok() then return end
	LFG.restore()
	local now = state.clock
	local win = state.win
	local open = win.visible and win.tab == "party"
	if open then LFG.ask_rank() end
	if open and now >= LFG.next_list then
		LFG.next_list = now + K.LFG_LIST
		local q = {}
		if LFG.filter.mode then q[#q + 1] = "mode=" .. LFG.filter.mode end
		if LFG.filter.lang then q[#q + 1] = "lang=" .. LFG.filter.lang end
		LFG.req("GET", "/parties" .. (#q > 0 and ("?" .. table.concat(q, "&")) or ""), nil, function(data, code)
			if code ~= 200 then
				LFG.offline = true
				return
			end
			LFG.offline = false
			LFG.list = type(data.parties) == "table" and data.parties or {}
			LFG.list_at = state.clock
		end)
	end
	if open then LFG.fetch_avatars() end
	local own = LFG.own
	if own and now >= own.ends then
		LFG.own, LFG.asks = nil, {}
		LFG.save()
		own = nil
	end
	if own and now >= LFG.next_host then
		LFG.next_host = now + (open and K.LFG_HOST or K.LFG_HOST_IDLE)
		LFG.req("GET", "/host?token=" .. own.token, nil, function(data, code)
			if not LFG.own or LFG.own.token ~= own.token then return end
			if code == 404 then
				LFG.own, LFG.asks = nil, {}
				LFG.save()
				return
			end
			if code ~= 200 then return end
			if type(data.members) == "table" then own.members = data.members end
			if type(data.party) == "table" then
				own.size = tonumber(data.party.size) or own.size
				local left = tonumber(data.party.expires) and data.now and (tonumber(data.party.expires) - tonumber(data.now))
				if left then own.ends = state.clock + left end
			end
			if (own.size or 1) >= 5 then return LFG.finish("bb_lfg_closed_full") end
			local asks = {}
			for _, j in ipairs(type(data.joins) == "table" and data.joins or K.NONE) do
				if j.status == "wait" and not LFG.invited[j.id] then
					LFG.invited[j.id] = true
					LFG.waiting[j.sid] = { id = j.id, name = j.name }
					local body = { steam_id = j.sid }
					if LFG.ver() then body.client_version = LFG.version end
					LFG.gc("CMsgInviteToParty", body, K.MSG_INVITE)
				elseif j.status == "ask" then
					asks[#asks + 1] = j
				end
			end
			LFG.asks = asks
		end)
	end
	local join = LFG.join
	if join and now >= join.ends then
		LFG.join = nil
		LFG.say("bb_lfg_gone")
		join = nil
	end
	if join and now >= LFG.next_join then
		LFG.next_join = now + K.LFG_JOIN
		LFG.req("GET", "/status?id=" .. join.id .. "&secret=" .. join.secret, nil, function(data, code)
			if LFG.join ~= join then return end
			if code == 404 then
				LFG.join = nil
				LFG.say("bb_lfg_gone")
				return
			end
			if data.status == "no" then
				LFG.join = nil
				LFG.say("bb_lfg_declined")
			elseif data.status == "invited" and type(data.group) == "string" and data.group ~= "" then
				local body = { party_id = data.group, accept = true }
				if LFG.ver() then body.client_version = LFG.version end
				LFG.gc("CMsgPartyInviteResponse", body, K.MSG_ACCEPT)
				LFG.join = nil
				LFG.say("bb_lfg_in")
			end
		end)
	end
end

function LFG.on_gc(msg)
	local kind = msg.msg_type
	if msg.binary_buffer_send and kind == K.MSG_INVITE then
		local data = LFG.read("CMsgInviteToParty", msg.binary_buffer_send, msg.size)
		local v = data and tonumber(data.client_version)
		if v and v > 0 then LFG.version = math.tointeger(v) end
	elseif msg.binary_buffer_recv and kind == K.MSG_CREATED then
		local data = LFG.read("CMsgInvitationCreated", msg.binary_buffer_recv, msg.size)
		local sid = data and tostring(data.steam_id or "")
		local w = sid and LFG.waiting[sid]
		if w and LFG.own and data.group_id then
			LFG.waiting[sid] = nil
			LFG.req("POST", "/invited", { token = LFG.own.token, join = w.id, group = tostring(data.group_id) }, function(_, code)
				if code ~= 200 then return end
				LFG.next_host, LFG.next_list = 0, 0
				pcall(Chat.Print, "ConsoleChat", string.format(L("bb_lfg_joined_chat"), tostring(w.name or "?")))
			end)
		end
	elseif msg.binary_buffer_send and (kind == K.MSG_LEAVE or kind == K.MSG_FIND) and LFG.own then
		LFG.finish(kind == K.MSG_FIND and "bb_lfg_closed_find" or "bb_lfg_closed_leave")
	elseif msg.binary_buffer_recv and kind == K.MSG_CARD_REPLY and LFG.rank_asked and not LFG.rank then
		local data = LFG.read("CMsgDOTAProfileCard", msg.binary_buffer_recv, msg.size)
		local sid = LFG.sid()
		if data and sid and tonumber(data.account_id) == math.tointeger(tonumber(sid)) - K.STEAM_BASE then
			LFG.rank = math.tointeger(tonumber(data.rank_tier) or 0) or 0
		end
	end
end

function LFG.err(code, data)
	local e = data and data.error
	if e == "full" then return LFG.say("bb_lfg_err_full") end
	if e == "rank" then return LFG.say("bb_lfg_err_rank") end
	if e == "busy" then return LFG.say("bb_lfg_err_busy") end
	if e == "gone" then return LFG.say("bb_lfg_gone") end
	if code == 0 or code >= 500 then return LFG.say("bb_lfg_err_net") end
	LFG.say("bb_lfg_err_net")
end

function LFG.act(value)
	local cmd, arg = tostring(value):match("^(%w+):?(.*)$")
	local f = LFG.form
	if cmd == "ok" then
		Config.WriteInt(K.CONFIG, "lfg_ok", 1)
		LFG.on = true
		LFG.next_list = 0
	elseif cmd == "new" then
		f.open = true
		state.anim.lfg_form = 0
	elseif cmd == "x" then
		f.open = false
	elseif cmd == "fmode" then
		f.mode = tonumber(arg) or f.mode
	elseif cmd == "fany" then
		f.roles = 31
	elseif cmd == "frole" then
		local bit = 1 << ((tonumber(arg) or 1) - 1)
		f.roles = f.roles == 31 and bit or (f.roles ~ bit)
		if f.roles == 0 then f.roles = 31 end
	elseif cmd == "fspread" then
		f.spread = tonumber(arg) or f.spread
	elseif cmd == "flang" then
		f.lang = arg
	elseif cmd == "fauto" then
		f.auto = not f.auto
	elseif cmd == "lrank" then
		LFG.filter.rank = not LFG.filter.rank
	elseif cmd == "lmode" then
		local m = tonumber(arg)
		LFG.filter.mode = LFG.filter.mode ~= m and m or nil
		LFG.next_list = 0
	elseif cmd == "llang" then
		LFG.filter.lang = LFG.filter.lang ~= arg and arg or nil
		LFG.next_list = 0
	elseif cmd == "create" then
		local sid = LFG.sid()
		if f.roles == 0 then return LFG.say("bb_lfg_pick_role") end
		if not sid then return LFG.say("bb_lfg_err_net") end
		LFG.req("POST", "/party", { sid = sid, name = LFG.name(), rank = LFG.rank or 0, mode = f.mode, roles = f.roles, lang = LFG.lang(), spread = f.spread, auto = f.auto, size = 1 }, function(data, code)
			if code ~= 200 or not data.token then return LFG.err(code, data) end
			LFG.own = { id = data.id, token = data.token, ends = state.clock + K.LFG_TTL, size = 1, mode = f.mode, roles = f.roles }
			LFG.save()
			LFG.invited, LFG.waiting, LFG.asks = {}, {}, {}
			LFG.next_host, LFG.next_list = 0, 0
			f.open = false
		end)
	elseif cmd == "close" then
		local own = LFG.own
		LFG.own, LFG.asks = nil, {}
		LFG.next_list = 0
		LFG.save()
		if own then LFG.req("POST", "/close", { token = own.token }, function() end) end
	elseif cmd == "extend" then
		local own = LFG.own
		if not own then return end
		LFG.req("POST", "/extend", { token = own.token }, function(data, code)
			if code ~= 200 or not LFG.own or LFG.own.token ~= own.token then return end
			local left = tonumber(data.expires) and tonumber(data.now) and (tonumber(data.expires) - tonumber(data.now))
			if left then
				own.ends = state.clock + left
				LFG.save()
			end
		end)
	elseif cmd == "join" then
		local sid = LFG.sid()
		if not sid or LFG.join then return end
		local host = nil
		for _, p in ipairs(LFG.list) do
			if p.id == arg then host = p end
		end
		LFG.req("POST", "/join", { party = arg, sid = sid, name = LFG.name(), rank = LFG.rank or 0, role = my_position() }, function(data, code)
			if code ~= 200 or not data.id then return LFG.err(code, data) end
			LFG.join = { id = data.id, secret = data.secret, name = host and host.name or "?", ends = state.clock + K.LFG_WAIT }
			LFG.next_join = state.clock + K.LFG_JOIN
		end)
	elseif cmd == "yes" or cmd == "no" then
		local own = LFG.own
		if not own then return end
		for i = #LFG.asks, 1, -1 do
			if LFG.asks[i].id == arg then table.remove(LFG.asks, i) end
		end
		LFG.req("POST", "/decide", { token = own.token, join = arg, ok = cmd == "yes" }, function() LFG.next_host = 0 end)
	end
end

function W.chip(key, label, x, y, on, kind, value)
	local tw = measure(fonts.w500, 13, label) + 20
	local hot = hover_t("chip_" .. key, x, y, tw, 28)
	local t = tween("chip_on_" .. key, on and 1 or 0, 16)
	rect(x, y, tw, 28, mix(mix(N.SLOT, N.TRACK, hot), N.ACCENT, t), 8)
	text(fonts.w500, 13, label, x + 10, y + 6, mix(N.TEXT, N.INK, t))
	if kind then button(kind, x, y, tw, 28, value) end
	return tw
end

function W.party(w, h)
	local x, cw = N.X, w - 2 * N.X
	local top = N.TOP
	W.block(0)
	if not LFG.ok() then
		local bw = 520
		local bx = (w - bw) / 2
		local by = top + 90
		text(fonts.d600, 22, L("bb_lfg_consent_title"), w / 2, by, N.TEXT, "center")
		local lines = wrap(fonts.w500, 15, L("bb_lfg_consent"), bw, 5)
		for i, l in ipairs(lines) do text(fonts.w500, 15, l, w / 2, by + 44 + (i - 1) * 22, N.MUTED, "center") end
		W.button_main("lfg_ok", L("bb_lfg_enable"), (w - 200) / 2, by + 60 + #lines * 22, 200, 44, "lfg", "ok")
		W.unblock()
		return
	end
	local f = LFG.filter
	local cx = x
	cx = cx + W.chip("lrank", L("bb_lfg_my_rank"), cx, top, f.rank, "lfg", "lrank") + 6
	for m = 0, 3 do cx = cx + W.chip("lm" .. m, L("bb_lfg_mode_" .. m), cx, top, f.mode == m, "lfg", "lmode:" .. m) + 6 end
	for _, lg in ipairs(K.LFG_LANGS) do cx = cx + W.chip("ll" .. lg, lg:upper(), cx, top, f.lang == lg, "lfg", "llang:" .. lg) + 6 end
	if not LFG.own then W.button_main("lfg_new", L("bb_lfg_new"), x + cw - 170, top - 4, 170, 36, "lfg", "new") end
	W.unblock()
	local strip = ((LFG.own and #LFG.asks > 0) or LFG.join or (LFG.msg and state.clock - LFG.msg_at < K.LFG_MSG)) and 64 or 0
	local y = top + 48
	local bottom = h - 16 - strip
	W.block(1)
	local rows = {}
	local own = LFG.own
	if own then
		local sid = LFG.sid() or ""
		rows[1] = { id = own.id, sid = sid, name = LFG.name(), rank = LFG.rank or 0, mode = own.mode, roles = own.roles, lang = LFG.lang(), size = own.size or 1, members = own.members or { sid } }
	end
	for _, p in ipairs(LFG.list) do
		if own and p.id == own.id then
			if type(p.members) == "table" then own.members = p.members end
		elseif not f.rank or LFG.fits(p) then
			rows[#rows + 1] = p
		end
	end
	if LFG.list_at == 0 and not LFG.offline and not own then
		for i = 0, 2 do
			W.skeleton(x, y + i * 70, cw, 62, i)
		end
	elseif #rows == 0 then
		W.empty(LFG.offline and L("bb_lfg_err_net") or L("bb_lfg_empty"), x, y + 12, cw)
	end
	local total = #rows * K.LFG_ROW
	LFG.scroll_max = math.max(0, total - (bottom - y))
	LFG.scroll_to = math.max(0, math.min(LFG.scroll_max, LFG.scroll_to or 0))
	local sc = tween("lfg_scroll", LFG.scroll_to, 14)
	Render.PushClip(P(x - 4, y - 4), P(x + cw + 4, bottom), true)
	for i, p in ipairs(rows) do
		local ry = y + (i - 1) * K.LFG_ROW - sc
		if ry > bottom then break end
		local live = ry >= y - 1 and ry + 60 <= bottom + 1
		if ry + 60 >= y then
			local mine = LFG.own and p.id == LFG.own.id
			local fits = mine or LFG.fits(p)
			local hot = hover_t("lfg_row_" .. p.id, x, ry, cw, 60)
			local bg = mix(N.PANEL, N.SLOT, hot)
			rect(x, ry, cw, 60, bg, 14)
			if mine then frame_line(x, ry, cw, 60, alpha(N.ACCENT, 0.55), 14, 1.2) end
			local members = type(p.members) == "table" and p.members or { p.sid }
			local filled = math.max(#members, math.min(5, tonumber(p.size) or 1))
			local cxs, rs = {}, {}
			local ax = x + 14
			for k = 1, 5 do
				local r = k == 1 and 19 or 14
				if k == 1 then
					cxs[k] = ax + r
				else
					cxs[k] = cxs[k - 1] + rs[k - 1] + r - 8
				end
				rs[k] = r
			end
			local cy = ry + 30
			for k = 5, 1, -1 do
				local r, cx = rs[k], cxs[k]
				dot(cx, cy, r + 2, bg)
				if k <= filled then
					local sid = members[k]
					local handle = sid and LFG.avatar(sid)
					if handle then
						W.pic(handle, cx - r, cy - r, r * 2, r * 2, r)
					else
						dot(cx, cy, r, LFG.tint(sid or p.id .. k))
						if k == 1 then
							local name = tostring(p.name or "?")
							local first = name:sub(1, (utf8.offset(name, 2) or (#name + 1)) - 1)
							text(fonts.d600, 15, first:upper(), cx, cy - 9, N.TEXT, "center")
						end
					end
				else
					Render.Circle(P(cx, cy), r * G.s, A(N.LINE), 1.5 * G.s, 0, 1, false, 32)
					text(fonts.w500, 13, "+", cx, cy - 8, N.DIM, "center")
				end
			end
			local tx = cxs[5] + rs[5] + 16
			local right = x + cw - ((mine and LFG.own and LFG.own.ends - state.clock < K.LFG_EXTEND_AT) and 248 or 132)
			local title = mine and L("bb_lfg_mine") or tostring(p.name or "?")
			text(fonts.w600, 15, fit(fonts.w600, 15, title, right - tx), tx, ry + 11, N.TEXT)
			LFG.medal(tx - 2, ry + 31, 20, p.rank)
			local roles = table.concat(LFG.roles(tonumber(p.roles) or 0), ", ")
			local info = LFG.rank_label(p.rank) .. " · " .. tostring(p.lang or ""):upper() .. " · " .. L("bb_lfg_mode_" .. (tonumber(p.mode) or 0)) .. " · " .. string.format(L(mine and "bb_lfg_we" or "bb_lfg_they"), roles)
			if mine and LFG.own then info = info .. " · " .. string.format(L("bb_lfg_left"), math.max(0, math.ceil((LFG.own.ends - state.clock) / 60))) end
			text(fonts.w500, 12, fit(fonts.w500, 12, info, right - tx - 22), tx + 22, ry + 35, N.MUTED)
			if mine then
				W.button_ghost("lfg_cancel_" .. p.id, L("bb_lfg_close"), x + cw - 120, ry + 12, 108, 36, live and "lfg" or "none", "close")
				if LFG.own and LFG.own.ends - state.clock < K.LFG_EXTEND_AT then
					W.button_ghost("lfg_extend", L("bb_lfg_extend"), x + cw - 236, ry + 12, 108, 36, live and "lfg" or "none", "extend")
				end
			elseif fits and not LFG.join and not LFG.own then
				W.button_main("lfg_join_" .. p.id, L("bb_lfg_join"), x + cw - 120, ry + 12, 108, 36, live and "lfg" or "none", "join:" .. p.id)
			elseif not fits then
				text(fonts.w500, 12, L("bb_lfg_rank_no"), x + cw - 14, ry + 23, N.DIM, "right")
			end
		end
	end
	Render.PopClip()
	if LFG.scroll_max > 0 then
		local view = bottom - y
		local bh = math.max(24, view * view / total)
		local by = y + (view - bh) * (sc / LFG.scroll_max)
		if LFG.drag then
			if Input.IsKeyDown(Enum.ButtonCode.KEY_MOUSE1, true) then
				local _, cy = Input.GetCursorPos()
				LFG.scroll_to = LFG.drag.s + (cy - LFG.drag.y) / G.s * LFG.scroll_max / math.max(1, view - bh)
			else
				LFG.drag = nil
			end
		end
		local bhot = hover_t("lfg_bar", x + cw, y, 16, view)
		rect(x + cw + 6 - bhot, by, 3 + bhot * 2, bh, mix(N.LINE, N.DIM, math.max(bhot, LFG.drag and 1 or 0)), 3)
		button("lfgbar", x + cw, y, 16, view, "bar")
		if state.win.tab == "party" and LFG.over() and state.clock - (LFG.wheel_at or -10) > 0.2 then
			if Input.IsKeyDownOnce(Enum.ButtonCode.KEY_MWHEELUP, true) then
				LFG.wheel(1)
			elseif Input.IsKeyDownOnce(Enum.ButtonCode.KEY_MWHEELDOWN, true) then
				LFG.wheel(-1)
			end
		end
	end
	W.unblock()
	if strip > 0 then
		W.block(2)
		local sy = h - 16 - 52
		rect(x, sy, cw, 52, N.PANEL, 12)
		frame_line(x, sy, cw, 52, N.LINE, 12)
		if LFG.own and LFG.asks[1] then
			local ask = LFG.asks[1]
			dot(x + 20, sy + 26, 4, N.WIN)
			if ask then
				local line = string.format(L("bb_lfg_asks"), tostring(ask.name or "?")) .. " · " .. LFG.rank_label(ask.rank)
				text(fonts.w600, 14, fit(fonts.w600, 14, line, cw - 320), x + 36, sy + 16, N.TEXT)
				W.button_main("lfg_yes", L("bb_lfg_yes"), x + cw - 236, sy + 9, 110, 34, "lfg", "yes:" .. ask.id)
				W.button_ghost("lfg_no", L("bb_lfg_no"), x + cw - 118, sy + 9, 106, 34, "lfg", "no:" .. ask.id)
			end
		elseif LFG.join then
			W.dots(x + 22, sy + 26)
			text(fonts.w600, 14, fit(fonts.w600, 14, string.format(L("bb_lfg_wait"), LFG.join.name), cw - 80), x + 50, sy + 16, N.TEXT)
		else
			text(fonts.w600, 14, fit(fonts.w600, 14, LFG.msg or "", cw - 40), x + 20, sy + 16, N.TEXT)
		end
		W.unblock()
	end
	if LFG.form.open then
		local fo = LFG.form
		local t = tween("lfg_form", 1, 18)
		button("lfg", 0, N.HEAD, w, h - N.HEAD, "x")
		local pw, ph = 380, 456
		local px, py = x + cw - pw, top + 40 - (1 - t) * 8
		local base = G.alpha
		G.alpha = base * t
		W.soft(px, py, pw, ph, 14, 24)
		rect(px, py, pw, ph, N.PANEL, 14)
		frame_line(px, py, pw, ph, N.LINE, 14)
		button("lfg", px, py, pw, ph, "none")
		text(fonts.w600, 16, L("bb_lfg_form"), px + 18, py + 16, N.TEXT)
		local qx, qy, qw, qh, xh = W.btn("lfg_fx", px + pw - 42, py + 10, 30, 30)
		if xh > 0.01 then rect(qx, qy, qw, qh, alpha(N.HOT, xh), 10) end
		W.glyph(K.CLOSE, 13, qx + qw / 2, qy + qh / 2, mix(N.MUTED, N.TEXT, xh))
		button("lfg", px + pw - 42, py + 10, 30, 30, "x")
		local fy = py + 56
		local function label(key)
			text(fonts.w500, 13, L(key), px + 18, fy, N.MUTED)
			fy = fy + 22
		end
		label("bb_lfg_f_mode")
		local fx = px + 18
		for m = 0, 3 do
			local ml = L("bb_lfg_mode_" .. m)
			if fx + measure(fonts.w500, 13, ml) + 20 > px + pw - 18 then fy, fx = fy + 34, px + 18 end
			fx = fx + W.chip("fm" .. m, ml, fx, fy, fo.mode == m, "lfg", "fmode:" .. m) + 6
		end
		fy = fy + 42
		label("bb_lfg_f_roles")
		fx = px + 18
		fx = fx + W.chip("frany", L("bb_lfg_anyone"), fx, fy, fo.roles == 31, "lfg", "fany") + 6
		for p = 1, 5 do
			local on = fo.roles ~= 31 and fo.roles & (1 << (p - 1)) ~= 0
			fx = fx + W.chip("fr" .. p, tostring(p), fx, fy, on, "lfg", "frole:" .. p) + 6
		end
		fy = fy + 42
		label("bb_lfg_f_rank")
		fx = px + 18
		for s = 0, 2 do fx = fx + W.chip("fs" .. s, L("bb_lfg_spread_" .. s), fx, fy, fo.spread == s, "lfg", "fspread:" .. s) + 6 end
		fy = fy + 34
		text(fonts.w500, 12, fit(fonts.w500, 12, LFG.range_text(fo.spread), pw - 36), px + 18, fy, N.DIM)
		fy = fy + 26
		label("bb_lfg_f_lang")
		fx = px + 18
		for _, lg in ipairs(K.LFG_LANGS) do fx = fx + W.chip("fl" .. lg, lg:upper(), fx, fy, LFG.lang() == lg, "lfg", "flang:" .. lg) + 6 end
		fy = fy + 44
		text(fonts.w500, 15, L("bb_lfg_auto"), px + 18, fy + 2, N.TEXT)
		W.toggle("lfg_auto", px + pw - 58, fy, fo.auto)
		button("lfg", px + 10, fy - 6, pw - 20, 34, "fauto")
		W.button_main("lfg_create", L("bb_lfg_create"), px + 18, py + ph - 58, pw - 36, 42, "lfg", "create")
		G.alpha = base
	end
end

local SC = { data = {}, asked = {} }

function SC.compact(rows)
	local out = {}
	for _, r in ipairs(type(rows) == "table" and rows or K.NONE) do
		local id, g, w = tonumber(r.hero_id), tonumber(r.games) or 0, tonumber(r.win) or 0
		if id and g >= K.SCOUT_MIN then out[#out + 1] = { id = id, g = g, w = w } end
	end
	table.sort(out, function(a, b) return a.g > b.g end)
	while #out > 3 do table.remove(out) end
	return out
end

function SC.tick()
	local d = state.draft
	if not d.phase then return end
	for _, e in ipairs(d.theirs) do
		local acc = e.acc
		if acc and not SC.asked[acc] then
			SC.asked[acc] = true
			local net = state.net
			net.queue[#net.queue + 1] = {
				key = "scout",
				path = "players/" .. acc .. "/heroes?date=" .. K.SCOUT_DAYS,
				done = function(data) SC.data[acc] = SC.compact(data) end,
			}
		end
	end
end

function SC.draw(y, w)
	local rows = {}
	for _, e in ipairs(state.draft.theirs) do
		local list = e.acc and SC.data[e.acc]
		if list and #list > 0 then rows[#rows + 1] = { e = e, list = list } end
	end
	if #rows == 0 then return y end
	y = y + 8
	rect(16, y, w - 32, 1, N.LINE)
	y = y + 12
	text(fonts.w600, 14, L("bb_scout_title"), 16, y, N.TEXT)
	y = y + 26
	for _, r in ipairs(rows) do
		text(fonts.w500, 13, fit(fonts.w500, 13, r.e.pname or "?", 96), 16, y + 2, N.MUTED)
		local x = 120
		for _, h in ipairs(r.list) do
			local unit = hero_unit(h.id)
			if unit then
				local wr = math.floor(h.w / h.g * 100 + 0.5)
				local hot = h.g >= K.SCOUT_BAN_G and wr >= K.SCOUT_BAN_WR
				W.pic(hero_image(unit), x, y, 34, 19, 4)
				if hot then frame_line(x, y, 34, 19, N.ACCENT, 4, 1.5) end
				text(fonts.d600, 12, wr .. "%", x + 38, y + 2, hot and N.ACCENT or N.TEXT)
				x = x + 68
			end
		end
		y = y + 27
	end
	text(fonts.w500, 12, fit(fonts.w500, 12, L("bb_scout_hint"), w - 32), 16, y, N.DIM)
	return y + 18
end

local PK = { flags = {}, sug_at = 0, cards = {}, buttons = {}, stack = {}, map = nil, fresh = nil, next_scan = 0, next_pos = 0, hl = { {}, {}, {} }, leader = nil, flash_at = -10, h = 300, x = nil, y = nil, drag = nil }

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
				local unit = hero_unit(b.value)
				if PK.sel and PK.sel.id == b.value then
					PK.sel = nil
				elseif unit then
					PK.sel = { id = b.value, at = state.clock }
					local ok = pcall(Engine.ExecuteCommand, "possible_hero " .. unit)
					log("pick select " .. unit .. ": " .. tostring(ok))
				end
			elseif b.kind == "suggest" then
				PK.suggest(b.value)
			elseif b.kind == "pick" then
				local unit = hero_unit(b.value)
				PK.sel = nil
				if unit then
					local ok = pcall(Engine.ExecuteCommand, "dota_select_hero " .. unit)
					log("pick lock " .. unit .. ": " .. tostring(ok))
				end
			end
			return
		end
	end
end

function PK.flagged(id)
	for _, f in ipairs(PK.flags) do
		if f == id then return true end
	end
	return false
end

function PK.suggest(id)
	local unit = hero_unit(id)
	if not unit or PK.flagged(id) or state.clock < PK.sug_at then return end
	PK.sug_at = state.clock + K.SUGGEST_GAP
	local ok = pcall(Engine.ExecuteCommand, string.format(K.SUGGEST, unit:sub(15)))
	log("suggest " .. unit .. ": " .. tostring(ok))
	PK.flags[#PK.flags + 1] = id
	while #PK.flags > K.SUGGEST_MAX do table.remove(PK.flags, 1) end
end

function PK.mates(y, w, view)
	local mates = view and view.mates
	if not mates then return y end
	y = y + 8
	rect(16, y, w - 32, 1, N.LINE)
	y = y + 12
	text(fonts.w600, 14, L("bb_mate_title"), 16, y, N.TEXT)
	y = y + 26
	local tip = nil
	local iw, ih = 44, 25
	for i, m in ipairs(mates) do
		if i > 1 then rect(16, y - 4, w - 32, 1, N.LINE) end
		rect(16, y + 7, 22, 22, N.SLOT, 6)
		text(fonts.d600, 13, tostring(m.pos), 27, y + 10, N.TEXT, "center")
		local n = #m.heroes
		local room = w - 32 - 38 - n * (iw + 4)
		local name = (m.name and m.name ~= "") and m.name or L("bb_mate_name")
		text(fonts.w600, 13, fit(fonts.w600, 13, name, room), 46, y + 3, N.TEXT)
		local sub = m.known and L("bb_role_" .. m.pos) or L("bb_mate_free")
		text(fonts.w500, 12, fit(fonts.w500, 12, sub, room), 46, y + 20, N.MUTED)
		local px = w - 16 - n * (iw + 4) + 4
		for _, b in ipairs(m.heroes) do
			local unit = hero_unit(b.id)
			if unit then
				local hot = hover_t("pkm" .. b.id, px, y + 6, iw, ih)
				W.pic(hero_image(unit), px, y + 6, iw, ih, 5)
				if PK.flagged(b.id) then
					frame_line(px, y + 6, iw, ih, N.ACCENT, 5, 1.5)
					rect(px + iw - 14, y + 7, 13, 12, N.SHADE, 4)
					W.glyph(K.ICON_FLAG, 8, px + iw - 7.5, y + 13, N.ACCENT)
				elseif hot > 0.01 then
					frame_line(px, y + 6, iw, ih, alpha(N.TEXT, 0.6 * hot), 5, 1)
				end
				if hot > 0.5 then tip = { unit = unit, why = b.why, gain = b.gain } end
				button("suggest", px, y + 6, iw, ih, b.id)
			end
			px = px + iw + 4
		end
		y = y + 40
	end
	if tip then
		local gain = string.format("%+.1f%%", tip.gain)
		local gw = measure(fonts.d600, 12, gain)
		text(fonts.d600, 12, gain, w - 16, y, tip.gain >= 0 and N.WIN or N.LOSE, "right")
		local line = hero_title(tip.unit) .. (tip.why and (" · " .. tip.why) or "")
		text(fonts.w500, 12, fit(fonts.w500, 12, line, w - 40 - gw), 16, y, N.MUTED)
	end
	return y + 18
end

function PK.scan()
	if state.clock >= PK.next_scan and #PK.stack == 0 then
		PK.next_scan = state.clock + K.GRID_SCAN
		local ok, root = pcall(Panorama.GetPanelByName, "HeroGrid", false)
		if ok and root then
			PK.stack[1] = root
			PK.fresh = {}
			PK.root = root
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
			if name and PK.fresh then
				local list = PK.fresh[name]
				if not list then
					list = {}
					PK.fresh[name] = list
				end
				list[#list + 1] = p
			end
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
	if #PK.stack == 0 and PK.fresh then
		PK.map, PK.fresh = PK.fresh, nil
		state.grid = PK.map
	end
end

function PK.shown(card)
	local p, depth = card, 0
	while p and depth < 40 do
		local okv, vis = pcall(p.IsVisible, p)
		if not okv or not vis then return false end
		local okw, pw = pcall(p.GetLayoutWidth, p)
		local okh, ph = pcall(p.GetLayoutHeight, p)
		if not okw or not okh or (tonumber(pw) or 0) < 2 or (tonumber(ph) or 0) < 2 then return false end
		if PK.root and p == PK.root then return true end
		local okp, parent = pcall(p.GetParent, p)
		p = okp and parent or nil
		depth = depth + 1
	end
	return true
end

function PK.area()
	local root = PK.root
	if not root then return nil end
	local okp, pos = pcall(root.GetPositionWithinWindow, root)
	local okw, rw = pcall(root.GetLayoutWidth, root)
	local okh, rh = pcall(root.GetLayoutHeight, root)
	if not okp or not pos or not okw or not okh then return nil end
	return { x = pos.x, y = pos.y, w = tonumber(rw) or 0, h = tonumber(rh) or 0 }
end

function PK.grid(view)
	if not PK.map or not view or #view.best == 0 then return end
	if state.clock >= PK.next_pos then
		PK.next_pos = state.clock + K.GRID_HL
		local area = PK.area()
		for i = 1, 3 do
			local slot = PK.hl[i]
			slot.on = false
			local b = view.best[i]
			local unit = b and hero_unit(b.id)
			local cards = unit and PK.map[unit:sub(15)]
			for _, card in ipairs(cards or K.NONE) do
				if not slot.on and PK.shown(card) then
					local okp, pos = pcall(card.GetPositionWithinWindow, card)
					local okw, cw = pcall(card.GetLayoutWidth, card)
					local okh, ch = pcall(card.GetLayoutHeight, card)
					cw, ch = okw and tonumber(cw) or 0, okh and tonumber(ch) or 0
					if okp and pos and cw > 4 and ch > 4 then
						local mx, my = pos.x + cw / 2, pos.y + ch / 2
						local inside = not area or (mx >= area.x and mx <= area.x + area.w and my >= area.y and my <= area.y + area.h)
						if inside then slot.on, slot.x, slot.y, slot.w, slot.h, slot.gain = true, pos.x, pos.y, cw, ch, b.gain end
					end
				end
			end
		end
	end
	G.ox, G.oy, G.s = 0, 0, 1
	local pulse = 0.5 + 0.5 * math.sin(state.clock * 3)
	for i = 1, 3 do
		local slot = PK.hl[i]
		if slot.on then
			local lead = i == 1
			frame_line(slot.x - 2, slot.y - 2, slot.w + 4, slot.h + 4, alpha(lead and N.ACCENT or N.TEXT, (lead and 0.6 or 0.3) + 0.4 * pulse), 6, lead and 2.5 or 1.5)
			local label = string.format("%+.1f%%", slot.gain)
			local lw = measure(fonts.d600, 13, label) + 12
			rect(slot.x + slot.w / 2 - lw / 2, slot.y + slot.h - 10, lw, 20, N.SHADE, 6)
			text(fonts.d600, 13, label, slot.x + slot.w / 2, slot.y + slot.h - 8, slot.gain >= 0 and N.WIN or N.LOSE, "center")
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
	if hot > 0.01 then rect(cx, cy, cw2, ch2, alpha(N.HOT, hot), 10) end
	if leader then
		local flash = 1 - math.min(1, (state.clock - PK.flash_at) / 0.5)
		if flash > 0 then rect(cx, cy, cw2, ch2, alpha(N.ACCENT_SOFT, flash), 10) end
	end
	if sc < 0.9 then return end
	local ph = leader and 40 or 32
	local pw = ph * 1.78
	local py = cy + (ch2 - ph) / 2
	W.pic(hero_image(unit), cx + 8, py, pw, ph, 6)
	if leader then W.ring(cx + 8, py, pw, ph, 6, 0.7 + 0.3 * math.sin(state.clock * 2.4)) end
	local tx = cx + 18 + pw
	local left = w - 30 - pw
	c.g = c.g + (b.gain - c.g) * (1 - math.exp(-8 * state.dt))
	if math.abs(b.gain - c.g) < 0.01 then c.g = b.gain end
	local gain = string.format("%+.1f%%", c.g)
	local gsize = leader and 18 or 15
	local sel = PK.sel and PK.sel.id == b.id and state.clock < PK.sel.at + K.PK_SEL
	if not sel then text(fonts.d600, gsize, gain, cx + cw2 - 10, cy + (leader and 9 or 7), b.gain >= 0 and N.WIN or N.LOSE, "right") end
	local room = left - measure(fonts.d600, gsize, "+00.0%") - 8
	if leader then
		local tw = measure(fonts.w700, 11, L("bb_top")) + 12
		rect(tx, cy + 10, tw, 17, N.ACCENT, 5)
		text(fonts.w700, 11, L("bb_top"), tx + tw / 2, cy + 12, N.INK, "center")
		text(fonts.w600, 15, fit(fonts.w600, 15, hero_title(unit), room - tw - 6), tx + tw + 6, cy + 9, N.TEXT)
	else
		text(fonts.w600, 14, fit(fonts.w600, 14, hero_title(unit), room), tx, cy + 8, N.TEXT)
	end
	if sel then
		rect(cx, cy, cw2, ch2, alpha(N.ACCENT, 0.12), 10)
		frame_line(cx, cy, cw2, ch2, N.ACCENT, 10, 1.5)
	end
	if b.why then text(fonts.w500, 13, fit(fonts.w500, 13, b.why, left - (sel and 90 or 0)), tx, cy + ch2 - 22, N.MUTED) end
	button("hero", cx, cy, cw2, ch2, b.id)
	if sel then
		local label = L("bb_pk_pick")
		local bw = measure(fonts.w700, 13, label) + 24
		local bx, by = cx + cw2 - bw - 8, cy + 8
		local bh = ch2 - 16
		local bhot = hover_t("pk_pick", bx, by, bw, bh)
		rect(bx, by, bw, bh, mix(N.ACCENT, N.TEXT, bhot * 0.25), 8)
		text(fonts.w700, 13, label, bx + bw / 2, by + (bh - 16) / 2, N.INK, "center")
		button("pick", bx, by, bw, bh, b.id)
	end
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
	if not d.phase and #PK.flags > 0 then PK.flags = {} end
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
	shadow(0, 0, w, h, 16, 22)
	rect(0, 0, w, h, N.BG, 16)
	frame_line(0, 0, w, h, N.LINE, 16)
	W.glyph(K.LOGO, 16, 22, 23, N.ACCENT)
	text(fonts.d600, 16, L("bb_tab_draft"), 40, 13, N.TEXT)
	button("drag", 0, 0, w - 50, 46)
	local bx, by, bw, bh, hot = W.btn("pk_open", w - 44, 8, 30, 30)
	if hot > 0.01 then rect(bx, by, bw, bh, alpha(N.HOT, hot), 10) end
	W.glyph(K.ICON_OPEN, 14, bx + bw / 2, by + bh / 2, mix(N.MUTED, N.TEXT, hot))
	button("open", w - 44, 8, 30, 30)
	rect(0, 45, w, 1, N.LINE)
	local light = d.my_team ~= 3
	local chance = view and view.chance
	local y = 58
	text(fonts.w500, 13, L("bb_chance_title"), 16, y, N.MUTED)
	if chance then
		if state.anim.pk_chance == nil then state.anim.pk_chance = 50 end
		local shown = tween("pk_chance", chance, 5)
		local rad = light and shown or (100 - shown)
		text(fonts.d600, 20, math.floor(shown + 0.5) .. "%", w - 16, y - 4, N.TEXT, "right")
		local split = (w - 32) * rad / 100
		rect(16, y + 26, split, 4, N.WIN, 2)
		rect(16 + split, y + 26, w - 32 - split, 4, N.LOSE, 2)
		rect(16 + (w - 32) / 2, y + 22, 1, 12, N.MUTED)
	else
		rect(16, y + 26, w - 32, 4, N.TRACK, 2)
		local p = (state.clock * 0.5) % 1
		rect(16 + (w - 32 - 50) * p, y + 26, 50, 4, N.DIM, 2)
	end
	y = y + 42
	local sw = (w - 32 - 4 * 5) / 5
	local sh = math.floor(sw * 0.5625 + 0.5)
	for row = 1, 2 do
		local team = row == 1 and d.ours or d.theirs
		local color = (row == 1) == light and N.WIN or N.LOSE
		for i = 1, 5 do
			local e = team[i]
			local px = 16 + (i - 1) * (sw + 5)
			local unit = e and e.id and hero_unit(e.id)
			rect(px, y, sw, sh, N.SLOT, 6)
			if unit then
				local t = W.first_seen((row == 1 and "pko" or "pkt") .. i, e.id)
				local sc = W.pop(t)
				W.pic(hero_image(unit), px + sw * (1 - sc) / 2, y + sh * (1 - sc) / 2, sw * sc, sh * sc, 6)
				local flash = 1 - math.min(1, t / 0.45)
				if flash > 0 then rect(px, y, sw, sh, alpha(N.TEXT, 0.22 * flash), 6) end
			else
				W.seen[(row == 1 and "pko" or "pkt") .. i] = nil
			end
			rect(px + 5, y + sh - 2, sw - 10, 2, color, 1)
		end
		y = y + sh + 5
	end
	y = y + 12
	local mine = d.my_hero and view and view.foes and #view.foes > 0
	text(fonts.w600, 14, mine and L("bb_foe_title") or string.format(L("bb_pick_title"), L("bb_role_" .. (view and view.pick_role or my_position()))), 16, y, N.TEXT)
	y = y + 26
	if mine then
		for i, f in ipairs(view.foes) do
			if i > 5 then break end
			local n = math.min(#f.items, 2)
			local room = w - 130 - n * 38
			if i > 1 then rect(16, y - 3, w - 32, 1, N.LINE) end
			W.pic(hero_image(f.unit), 16, y + 9, 57, 32, 6)
			text(fonts.w600, 14, fit(fonts.w600, 14, hero_title(f.unit), room), 84, y + 7, N.TEXT)
			text(fonts.w500, 13, fit(fonts.w500, 13, f.line, room), 84, y + 27, N.MUTED)
			local px = w - 16
			for k = n, 1, -1 do
				px = px - 34
				W.icon(item_image(f.items[k]), px, y + 13, 34, 25, 5, "pki" .. i .. k)
				px = px - 4
			end
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
		text(fonts.w500, 13, (view and #view.theirs > 0) and L("bb_best_loading") or L("bb_best_empty"), 16, y + 2, N.MUTED)
		y = y + 22
	end
	y = PK.mates(y, w, view)
	y = SC.draw(y, w)
	PK.h = y + 14
	G.alpha, G.buttons = 1, nil
end

local function draw_pick()
	PK.draw()
end

local function quick_buy(name)
	local ok = pcall(Engine.SetQuickBuy, short_name(name), false)
	if not Heroes.GetLocal() and #state.qb_pending < K.QB_MAX then state.qb_pending[#state.qb_pending + 1] = name end
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

function LINK.open(kind)
	local url = K.LINKS[kind]
	if not url then return end
	local js = ("$.DispatchEvent(%q, %q)"):format("ExternalBrowserGoToURL", url)
	local ok, res = pcall(Engine.RunScript, js)
	if not (ok and res) then pcall(Engine.RunScript, js, "Hud") end
	state.win.status = L("bb_status_link")
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
			elseif b.kind == "fmode" and left then
				W.fmode = b.value
			elseif b.kind == "tab" and left then
				if win.tab ~= b.value then state.anim.tab = 0 end
				win.tab = b.value
				win.pool_page = nil
				win.status = nil
				win.dropdown = nil
			elseif b.kind == "hero" and left then
				state.preview_hero = b.value
				state.next_model = 0
				state.next_data = 0
			elseif b.kind == "pool" and left then
				POOL.toggle(b.value)
			elseif b.kind == "pool_open" and left then
				win.pool_page = true
				state.win.open_at = state.clock
			elseif b.kind == "pool_done" and left then
				win.pool_page = nil
				state.win.open_at = state.clock
			elseif b.kind == "pool_clear" and left then
				POOL.clear()
			elseif b.kind == "card" and left then
				W.card_act(b.value)
			elseif b.kind == "onb" and left then
				W.onb_act(b.value)
			elseif b.kind == "news" and left then
				W.news_act(b.value)
			elseif b.kind == "link" and left then
				LINK.open(b.value)
			elseif b.kind == "upd" and left then
				UPD.act(b.value)
			elseif b.kind == "lfg" and left then
				LFG.act(b.value)
			elseif b.kind == "lfgbar" and left then
				local _, cy = Input.GetCursorPos()
				LFG.drag = { y = cy, s = LFG.scroll_to or 0 }
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
	if not win.visible then return false end
	if W.news.active then return true end
	if not win.x then return false end
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
		if p and p.area and p.area:IsValid() and p.flyout:IsValid() then return p end
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
			s.start_list = start_slots(items, 99)
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
			if not step.sit and not step.skipped and (step.early == true) == early then
				local i = #list + 1
				local tip = step.share and string.format(L("bb_shop_popular"), math.floor(step.share * 100 + 0.5), math.floor((step.tm or 0) / 60 + 0.5)) or step.reason
				list[i] = { name = step.name, key = key .. i, done = step.done, next = view.next == step,
					minute = not step.done and (state.turbo and step.minute or (step.tm and step.tm > 0 and math.floor(step.tm / 60 + 0.5))) or nil, tip = tip }
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

	function shop.talent_split(talents, counts)
		local tiers, totals = {}, {}
		for pair = 1, 4 do
			local cr, cl = counts[talents[pair * 2 - 1].id], counts[talents[pair * 2].id]
			tiers[pair] = { r = cr, l = cl }
			if cr and cl then totals[pair] = cr + cl end
		end
		for pair = 1, 4 do
			local t = tiers[pair]
			if (t.r == nil) ~= (t.l == nil) then
				local reach = nil
				if totals[pair - 1] then
					reach = totals[pair - 1] * K.TAL_REACH[pair - 1]
				elseif totals[pair + 1] then
					reach = totals[pair + 1] / K.TAL_REACH[pair]
				end
				if reach then
					for up = pair + 1, 4 do reach = math.max(reach, (tiers[up].r or 0) + (tiers[up].l or 0)) end
					local miss = math.max(0, reach - (t.r or t.l))
					if t.r then t.l = miss else t.r = miss end
				end
			end
		end
		return tiers
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
		local split = od and od.counts and shop.talent_split(talents, od.counts)
		for pair = 4, 1, -1 do
			local right, left = talents[pair * 2 - 1], talents[pair * 2]
			local left_pick, share_l, share_r = false, nil, nil
			local pt = role.src == "pt" and role.talents and role.talents[pair]
			if pt then
				left_pick = pt.pick == left.name
			elseif split and split[pair].r and split[pair].l then
				local cr, cl = split[pair].r, split[pair].l
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
		local x, y = bw + 8 + (state.shop.recipe_w or 0), math.max(4, math.min(bh - th - 4, tip.y))
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

	function shop.into(name)
		local cat = load_catalog()
		if not cat.into then
			local into = {}
			for result, parts in pairs(cat.parts) do
				local entry = cat.by_name[result]
				if entry and not entry.gone then
					for _, part in ipairs(parts) do
						local list = into[part]
						if not list then
							list = {}
							into[part] = list
						end
						local dup = false
						for _, v in ipairs(list) do
							if v == result then dup = true end
						end
						if not dup then list[#list + 1] = result end
					end
				end
			end
			for _, list in pairs(into) do
				table.sort(list, function(a, b)
					local ca, cb = item_cost(a), item_cost(b)
					if ca ~= cb then return ca < cb end
					return a < b
				end)
			end
			cat.into = into
		end
		return cat.into[name] or K.NONE
	end

	function shop.draw_recipe(bw, bh)
		local s = state.shop
		local r = s.recipe
		s.recipe_rect, s.recipe_w = nil, nil
		if not r then return end
		local cat = load_catalog()
		local name = r.name
		local parts, rname, rcost = {}, nil, 0
		for _, part in ipairs(cat.parts[name] or K.NONE) do
			local entry = cat.by_name[part]
			if entry and entry.recipe then
				rname, rcost = part, rcost + entry.cost
			else
				parts[#parts + 1] = part
			end
		end
		local into = shop.into(name)
		local w, iw, ih, gap = K.RC_W, 40, 29, 6
		local per = math.floor((w - 24 + gap) / (iw + gap))
		local slots = #parts + (rname and 1 or 0)
		local shown = math.min(#into, per * 2)
		local h = 58 + 18 + (slots > 0 and math.ceil(slots / per) * (ih + gap) or 20) + (shown > 0 and 20 + math.ceil(shown / per) * (ih + gap) or 0) + 24
		local x = bw + 8
		local y = math.max(4, math.min(bh - h - 4, (r.y - G.oy) / G.s - 20))
		local saved = G.alpha
		G.alpha = saved * W.ease((state.clock - r.at) / 0.18)
		shadow(x, y, w, h, 8, 16)
		rect(x, y, w, h, C.TIP, 8)
		frame_line(x, y, w, h, C.EDGE, 8)
		local a, b = P(x, y), P(x + w, y + h)
		s.recipe_rect, s.recipe_w = { x = a.x, y = a.y, w = b.x - a.x, h = b.y - a.y }, w + 8
		picture(item_image(name), x + 12, y + 12, 46, 34, 5, 0, false)
		text(fonts.w700, 13, fit(fonts.w700, 13, item_title(name), w - 100), x + 68, y + 12, C.TEXT)
		text(fonts.w700, 12, tostring(item_cost(name)), x + 68, y + 31, C.GOLD)
		local cx, cy = x + w - 22, y + 8
		local hot = hover_t("rc_close", cx, cy, 16, 16)
		W.glyph(K.CLOSE, 10, cx + 8, cy + 8, mix(C.MUTED, C.TEXT, hot))
		button("rclose", cx - 2, cy - 2, 20, 20)
		local ly = y + 58
		text(fonts.w600, 11, L("bb_rc_from"), x + 12, ly, C.MUTED)
		ly = ly + 18
		if slots == 0 then
			text(fonts.w500, 11, L("bb_rc_whole"), x + 12, ly, C.DIM)
			ly = ly + 20
		else
			local col = 0
			for i, part in ipairs(parts) do
				shop.item(part, x + 12 + col * (iw + gap), ly, iw, ih, { key = "rcp" .. i .. part })
				col = col + 1
				if col >= per then col, ly = 0, ly + ih + gap end
			end
			if rname then
				local px = x + 12 + col * (iw + gap)
				picture(item_image(rname), px, ly, iw, ih, 5, 0, false)
				frame_line(px, ly, iw, ih, C.EDGE, 5)
				rect(px + 2, ly + ih - 13, iw - 4, 12, C.BADGE, 3)
				text(fonts.w700, 10, tostring(rcost), px + iw / 2, ly + ih - 14, C.GOLD, "center")
				col = col + 1
			end
			if col > 0 then ly = ly + ih + gap end
		end
		if shown > 0 then
			text(fonts.w600, 11, L("bb_rc_into"), x + 12, ly + 2, C.MUTED)
			ly = ly + 20
			local col = 0
			for i = 1, shown do
				shop.item(into[i], x + 12 + col * (iw + gap), ly, iw, ih, { key = "rci" .. i .. into[i] })
				col = col + 1
				if col >= per then col, ly = 0, ly + ih + gap end
			end
			if col > 0 then ly = ly + ih + gap end
		end
		text(fonts.w500, 10, L("bb_rc_hint"), x + 12, ly + 4, C.DIM)
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

	function shop.measure(p)
		local s = state.shop
		local screen = Render.ScreenSize()
		local key = screen.x .. "x" .. screen.y
		if s.screen ~= key then
			s.screen, s.geom, s.settle = key, nil, state.clock + K.SHOP_SETTLE
		end
		if not s.open then
			s.open, s.settle = true, state.clock + K.SHOP_SETTLE
		end
		if s.geom and state.clock < s.next_geom then return end
		local f = p.flyout
		local pos = f:GetPositionWithinWindow()
		if not pos then return end
		local w, h = f:GetLayoutWidth() or 0, f:GetLayoutHeight() or 0
		local plus, q = false, f:GetParent()
		for _ = 1, 4 do
			if not q then break end
			if q:HasClass("PlusGuide") then
				plus = true
				break
			end
			q = q:GetParent()
		end
		local g = { x = pos.x, y = pos.y, w = w, h = h, ui = w / (plus and K.GUIDE_PLUS_W or K.GUIDE_W), left = pos.x + w / 2 < screen.x / 2 }
		local old = s.geom
		if old and (math.abs(old.x - g.x) > 1 or math.abs(old.y - g.y) > 1 or math.abs(old.w - g.w) > 1 or math.abs(old.h - g.h) > 1) then
			s.settle = state.clock + K.SHOP_SETTLE
		end
		s.geom = g
		s.next_geom = state.clock < (s.settle or 0) and state.clock or state.clock + K.SHOP_GEOM
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
			s.press, s.open, s.recipe, s.recipe_rect = nil, false, nil, nil
			return
		end
		local p = shop.shop_panels()
		if not p then return end
		local on = setting("shop") == 1
		shop.guide_hidden(p, on and not s.off)
		if not on then return end
		shop.measure(p)
		local g = s.geom
		if not g or g.w < 60 or g.h < 120 then return end
		local base = g.ui * K.GUIDE_W / K.SHOP_BASE_W
		G.buttons = s.buttons
		if s.off then
			G.ox, G.oy, G.s, G.alpha = g.x, g.y, base, 1
			shop.draw_pill(K.SHOP_BASE_W)
			return
		end
		local want = s.content_h and (g.h - 6) / (s.content_h + 14) or base
		local scale = tween("shop_scale", math.max(base * K.SHOP_MIN, math.min(base * K.SHOP_GROW, want)), 8)
		local pw = K.SHOP_BASE_W * scale
		local px = g.left and g.x or math.max(4, g.x + g.w - pw)
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
		local okr, errr = pcall(shop.draw_recipe, bw, bh)
		if not okr then
			s.recipe = nil
			Log.Write("[Build Brain] recipe: " .. tostring(errr))
		end
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
			if s.recipe and s.recipe.name == press.name then
				s.recipe = nil
			else
				s.recipe = { name = press.name, y = s.recipe and s.recipe.y or press.y, at = state.clock }
			end
		end
		return true
	end

	function shop.draw_drag()
		local s = state.shop
		local press = s.press
		if not press then return end
		local cx, cy = Input.GetCursorPos()
		if not press.drag and math.abs(cx - press.x) + math.abs(cy - press.y) > K.DRAG_MIN then press.drag = true end
		if not Input.IsKeyDown(Enum.ButtonCode.KEY_MOUSE1, true) then
			shop.release()
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
		local rc = state.shop.recipe_rect
		if rc and cursor_in(rc.x, rc.y, rc.x + rc.w, rc.y + rc.h) then return true end
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
				elseif b.kind == "rclose" and left then
					s.recipe = nil
				elseif b.kind == "collapse" and left then
					s.off = true
				elseif b.kind == "expand" and left then
					s.off = false
					state.anim.shop = 0
				elseif b.kind == "item" then
					local mod = false
					for _, k in ipairs(K.QB_KEYS) do
						if Input.IsKeyDown(k, true) then mod = true end
					end
					if left and mod then
						quick_buy(b.value)
					elseif left then
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

local function death_recap(dmg)
	local at = dmg.died_at or state.clock
	dmg.recap_at, dmg.died_at = nil, nil
	local last = { phys = 0, mag = 0, pure = 0, src = {}, at = at, n = dmg.deaths }
	for _, e in ipairs(dmg.log) do
		if at - e.t <= K.RECAP_WIN then
			last[e.kind] = last[e.kind] + e.d
			last.src[e.unit] = (last.src[e.unit] or 0) + e.d
		end
	end
	dmg.log = {}
	if last.phys + last.mag + last.pure > 0 then
		dmg.last = last
		W.fmode = "death"
	end
end

local function track_damage(hero)
	local dmg = state.dmg
	local alive = Entity.IsAlive(hero)
	if dmg.alive and not alive then
		dmg.deaths = dmg.deaths + 1
		dmg.died_at, dmg.recap_at = state.clock, state.clock + K.RECAP_LAG
		state.next_model = 0
		log("death " .. dmg.deaths)
	end
	if dmg.recap_at and state.clock >= dmg.recap_at then death_recap(dmg) end
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
	MIRROR.get("build-brain-data", "version.txt", function(body)
		return body:match("^%s*[^\t\n]+\t%d+%s*$") ~= nil
	end, function(body)
		local version = body and body:match("^%s*(.-)%s*$") or ""
		if version == "" then
			sync.busy, sync.done, sync.failed = false, true, true
			log("builds version check failed")
			return
		end
		Config.WriteInt(K.CONFIG, "sz_checked", os.time())
		if exists and version == Config.ReadString(K.CONFIG, "sz_version", "") then
			sync.busy, sync.done = false, true
			return
		end
		MIRROR.get("build-brain-data", "builds.txt", function(b)
			return b:match("^BB1\t") ~= nil and select(2, b:gsub("\n", "")) >= 100
		end, function(body)
			sync.busy, sync.done = false, true
			if not body then
				sync.failed = true
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
			Config.WriteString(K.CONFIG, "sz_version", body:match("^BB1\t([^\t\n]+\t%d+)") or version)
			state.sz, state.sz_text, state.sz_next, state.sz_pos, state.sz_vs, state.sz_vidx, state.sz_wr, state.sz_vis = {}, nil, 0, nil, {}, nil, nil, nil
			state.next_model = 0
			log("builds updated " .. version)
		end, "bb_builds")
	end, "bb_builds_version")
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
	local okm, gm = pcall(GameRules.GetGameMode)
	gm = okm and gm or 0
	state.turbo = gm == Enum.GameMode.DOTA_GAMEMODE_TURBO or (gm == 0 and setting("mode") == 1)
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
	local okt, errt = pcall(W.style_tick)
	if not okt then report("style", errt) end
	local okw, errw = pcall(draw_window)
	if not okw then report("window", errw) end
	pcall(draw_pick)
	if Engine.IsInGame() then
		local ok, err = pcall(shop.draw)
		if not ok and err ~= state.shop.error then
			state.shop.error = err
			Log.Write("[Build Brain] shop: " .. tostring(err))
		end
	end
end

local function quick_restore(hero)
	if not hero or #state.qb_pending == 0 then return end
	if not state.qb_at then state.qb_at = state.clock + K.QB_DELAY end
	if state.clock < state.qb_at then return end
	for i, name in ipairs(state.qb_pending) do pcall(Engine.SetQuickBuy, short_name(name), i == 1) end
	log("quickbuy restored " .. #state.qb_pending)
	state.qb_pending, state.qb_at = {}, nil
end

local AB = {}

function AB.owned(hero)
	local owned = {}
	local cat = load_catalog()
	carried(hero, function(item, name)
		local count = 1
		local entry = cat.by_name[name]
		if entry and entry.stack then
			local okc, cur = pcall(Item.GetCurrentCharges, item)
			local oki, init = pcall(Item.GetInitialCharges, item)
			cur, init = okc and tonumber(cur) or 0, oki and tonumber(init) or 0
			if init > 0 then count = math.max(1, math.ceil(cur / init)) end
		end
		if name == "item_ward_dispenser" then
			owned.item_ward_observer = (owned.item_ward_observer or 0) + 1
			owned.item_ward_sentry = (owned.item_ward_sentry or 0) + 1
		end
		owned[name] = (owned[name] or 0) + count
	end)
	return owned
end

function AB.chat(names, msg)
	local icons = {}
	for _, name in ipairs(names) do icons[#icons + 1] = '<img class="ChatItemIcon" src="file://{images}/items/' .. short_name(name) .. '.png"/>' end
	local c = N.ACCENT
	local tag = string.format('<font color="#%02x%02x%02x">%s</font>', math.floor(c.r + 0.5), math.floor(c.g + 0.5), math.floor(c.b + 0.5), L("bb_ab_tag"))
	local ok, err = pcall(Chat.Print, "ConsoleChat", table.concat(icons) .. " " .. tag .. " " .. msg)
	if not ok then Log.Write("[Build Brain] chat: " .. tostring(err)) end
end

function AB.start(hero)
	local ab = state.ab
	if ab.done or not hero or setting("autobuy") < 1 then return end
	local gs = GameRules.GetGameState()
	local early = ab.queue ~= nil or gs == Enum.GameState.DOTA_GAMERULES_STATE_PRE_GAME
		or (gs == Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS and (GameRules.GetDOTATime() or 0) < K.AB_LATE)
	if not early and gs == Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		early = true
		for slot = 0, 14 do
			local item = NPC.GetItemByIndex(hero, slot)
			local name = item and Ability.GetName(item)
			if name and name ~= "item_tpscroll" then early = false end
		end
	end
	if not early then
		ab.done = true
		local view = state.view
		log("auto start skipped: state " .. tostring(gs) .. ", time " .. math.floor(GameRules.GetDOTATime() or 0) .. ", start items " .. #(view and view.start or K.NONE))
		return
	end
	if not ab.at then ab.at = state.clock + K.AB_DELAY end
	if state.clock < ab.at then return end
	local player = Players.GetLocal()
	if not player then return end
	if not ab.queue then
		local view = state.view
		local list = view and view.start
		if not list or #list == 0 then return end
		local owned = AB.owned(hero)
		ab.queue, ab.bought, ab.spent, ab.gold, ab.qnext = {}, {}, 0, Player.GetTotalGold(player) or 0, 0
		for _, name in ipairs(list) do
			if (owned[name] or 0) > 0 then
				owned[name] = owned[name] - 1
			else
				ab.queue[#ab.queue + 1] = name
			end
		end
	end
	if state.clock < ab.qnext then return end
	local name = table.remove(ab.queue, 1)
	if name then
		local entry = load_catalog().by_name[name]
		ab.gold = math.min(ab.gold, Player.GetTotalGold(player) or 0)
		if entry and not entry.gone and entry.cost <= ab.gold and purchase(entry.id) then
			ab.gold, ab.spent = ab.gold - entry.cost, ab.spent + entry.cost
			ab.bought[#ab.bought + 1] = name
			ab.mine = ab.mine or {}
			ab.mine[name] = state.clock + K.AB_MINE
			ab.qnext = state.clock + K.AB_GAP + math.random() * K.AB_JIT
		end
		if #ab.queue > 0 then return end
	end
	ab.done, ab.next, ab.queue = true, state.clock + K.AB_WAIT, nil
	local bought = ab.bought
	log("auto start: bought " .. #bought .. ", " .. ab.spent .. " gold")
	if #bought == 0 then return end
	local titles = {}
	for _, item in ipairs(bought) do titles[#titles + 1] = item_title(item) end
	state.win.status = string.format(L("bb_status_buy"), table.concat(titles, ", "))
	AB.chat(bought, string.format(L("bb_ab_start"), #bought, ab.spent))
end

function AB.need(name, owned)
	local need = {}
	local function walk(item, depth)
		if depth > 0 and (owned[item] or 0) > 0 then
			owned[item] = owned[item] - 1
			return
		end
		local parts = load_catalog().parts[item]
		if not parts or depth > 6 then
			need[#need + 1] = item
			return
		end
		for _, part in ipairs(parts) do walk(part, depth + 1) end
	end
	walk(name, 0)
	return need
end

function AB.snapshot(hero)
	local counts, free = {}, 0
	for slot = 0, 14 do
		if not NPC.GetItemByIndex(hero, slot) then free = free + 1 end
	end
	carried(hero, function(_, name) counts[name] = (counts[name] or 0) + 1 end, 14)
	return counts, free
end

function AB.related(name, view)
	for _, step in ipairs(view and view.route or K.NONE) do
		if step.name == name or contains(step.name, name) then return true end
	end
	return false
end

function AB.game(hero)
	local ab = state.ab
	if not hero or not ab.done or setting("autobuy") ~= 2 then return end
	if state.clock < (ab.next or 0) then return end
	ab.next = state.clock + K.AB_STEP
	local gs = GameRules.GetGameState()
	if gs ~= Enum.GameState.DOTA_GAMERULES_STATE_PRE_GAME and gs ~= Enum.GameState.DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then return end
	local player = Players.GetLocal()
	local view = state.view
	if not player or not view then return end
	local gold = Player.GetTotalGold(player) or 0
	local counts, free = AB.snapshot(hero)
	ab.mine = ab.mine or {}
	ab.fail = ab.fail or {}
	if ab.snap then
		for name, n in pairs(counts) do
			local was = ab.snap[name] or 0
			if n > was then
				local mine = ab.mine[name]
				if mine and state.clock < mine then
					ab.mine[name] = nil
				elseif not AB.related(name, view) then
					ab.hold = state.clock + K.AB_HOLD
					log("autobuy pause, bought by hand: " .. name)
				end
			end
		end
	end
	ab.snap = counts
	local pend = ab.pending
	if pend then
		if state.clock < pend.at then return end
		ab.pending = nil
		if gold > pend.gold - pend.cost * 0.5 and (counts[pend.name] or 0) <= pend.had and (counts[pend.step] or 0) <= pend.had_step then
			ab.fail[pend.name] = state.clock + K.AB_FAIL
			AB.chat({ pend.name }, string.format(L("bb_ab_fail"), item_title(pend.name)))
		end
	end
	if state.clock < (ab.hold or 0) then return end
	local step = view.next
	if not step or step.skipped or step.done then return end
	if free < 1 then
		if not ab.full then
			ab.full = true
			AB.chat({}, L("bb_ab_full"))
		end
		return
	end
	ab.full = nil
	local need = AB.need(step.name, owned_items(hero))
	if #need == 0 then return end
	local cat = load_catalog()
	local parts_left = false
	for _, part in ipairs(need) do
		local entry = cat.by_name[part]
		if entry and not entry.recipe then parts_left = true end
	end
	local pick = nil
	for _, part in ipairs(need) do
		local entry = cat.by_name[part]
		if entry and not entry.gone and entry.cost > 0 and entry.cost <= gold and state.clock >= (ab.fail[part] or 0) and not (entry.recipe and parts_left) then
			if not pick or entry.cost > pick.cost then pick = { name = part, cost = entry.cost, id = entry.id } end
		end
	end
	if not pick or not purchase(pick.id) then return end
	ab.pending = { name = pick.name, cost = pick.cost, gold = gold, had = counts[pick.name] or 0, step = step.name, had_step = counts[step.name] or 0, at = state.clock + K.AB_WAIT }
	ab.mine[pick.name] = state.clock + K.AB_MINE
	ab.mine[step.name] = state.clock + K.AB_MINE
	state.next_model = state.clock + 0.4
	state.win.status = string.format(L("bb_status_buy"), item_title(pick.name))
	local msg
	if #need == 1 then
		msg = pick.name == step.name and item_title(step.name) or string.format(L("bb_ab_done"), item_title(step.name))
	else
		msg = string.format(L("bb_ab_part"), item_title(pick.name), item_title(step.name))
	end
	if step.vs_reason then msg = msg .. ", " .. step.vs_reason end
	AB.chat(#need == 1 and { step.name } or { pick.name }, msg)
	log("autobuy " .. pick.name .. " for " .. step.name)
end

local function update()
	local hero = Heroes.GetLocal()
	if hero then track_damage(hero) end
	quick_restore(hero)
	AB.start(hero)
	SC.tick()
	AB.game(hero)
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
	local okl, errl = pcall(LFG.tick)
	if not okl and errl ~= state.lfg_error then
		state.lfg_error = errl
		Log.Write("[Build Brain] party: " .. tostring(errl))
	end
end

function script.OnGCMessage(msg)
	if ui.enable:Get() and type(msg) == "table" then
		local ok, err = pcall(LFG.on_gc, msg)
		if not ok then log("lfg gc: " .. tostring(err)) end
	end
	return true
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
	if (key == Enum.ButtonCode.KEY_MWHEELUP or key == Enum.ButtonCode.KEY_MWHEELDOWN) and state.win.tab == "party" and window_hit() then
		if event ~= Enum.EKeyEvent.EKeyEvent_KEY_UP then
			LFG.wheel_at = state.clock
			LFG.wheel(key == Enum.ButtonCode.KEY_MWHEELUP and 1 or -1)
		end
		return false
	end
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

local function hurt_owner(source, me)
	if not source then return nil end
	local okt, team = pcall(Entity.GetTeamNum, source)
	local okm, mine = pcall(Entity.GetTeamNum, me)
	if not okt or not okm or team == mine or (team ~= 2 and team ~= 3) then return nil end
	local unit = source
	for _ = 1, 4 do
		local okh, is_hero = pcall(NPC.IsHero, unit)
		if okh and is_hero then
			local okn, name = pcall(NPC.GetUnitName, unit)
			if okn and type(name) == "string" and name:match("^npc_dota_hero_") then return name end
		end
		local oko, owner = pcall(NPC.GetOwnerNPC, unit)
		owner = oko and owner or nil
		if not owner then
			local oke, ent = pcall(Entity.GetOwner, unit)
			owner = oke and ent or nil
			local okp, is_player = false, false
			if owner then okp, is_player = pcall(Entity.IsPlayer, owner) end
			if okp and is_player then
				local oka, h = pcall(Player.GetAssignedHero, owner)
				owner = oka and h or nil
			end
		end
		if not owner or owner == unit then return nil end
		unit = owner
	end
	return nil
end

local function on_hurt(data)
	if not data.target then return end
	local hero = Heroes.GetLocal()
	if not hero or not same(data.target, hero) then return end
	local unit = hurt_owner(data.source, hero)
	if not unit then return end
	local damage = tonumber(data.damage) or 0
	if damage <= 0 then return end
	local dmg = state.dmg
	local kind = "phys"
	if data.ability then
		local ok, dtype = pcall(Ability.GetDamageType, data.ability)
		if ok and (dtype == Enum.DamageTypes.DAMAGE_TYPE_PURE or dtype == Enum.DamageTypes.DAMAGE_TYPE_HP_REMOVAL) then
			kind = "pure"
		elseif not ok or dtype ~= Enum.DamageTypes.DAMAGE_TYPE_PHYSICAL then
			kind = "mag"
		end
	end
	dmg[kind] = dmg[kind] + damage
	dmg.src[unit] = (dmg.src[unit] or 0) + damage
	local list = dmg.log
	list[#list + 1] = { t = state.clock, kind = kind, unit = unit, d = damage }
	while #list > 0 and state.clock - list[1].t > K.RECAP_WIN + 1 do table.remove(list, 1) end
	if #list > K.RECAP_MAX then table.remove(list, 1) end
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
	state.edits = {}
	state.dmg = new_damage()
	state.foes = {}
	state.view = nil
	state.next_model = 0
	state.win.closed_by_user = false
	state.preview_hero = nil
	state.grid = nil
	state.route_sig = ""
	state.draft = { ours = {}, theirs = {}, bans = {}, my_team = nil, my_hero = nil, my_pos = nil, sig = "", phase = false }
	state.chat_bans = {}
	state.qb_pending, state.qb_at = {}, nil
	state.ab = { done = false, at = nil }
	SC.data, SC.asked = {}, {}
	PK.flags = {}
end

function script.OnChatEvent(data)
	if not ui.enable:Get() or type(data) ~= "table" then return end
	if data.type ~= Enum.DotaChatMessage.CHAT_MESSAGE_HERO_BANNED then return end
	local id = math.tointeger(tonumber(data.value) or 0) or 0
	if id > 0 and valid_hero(id) then
		state.chat_bans[id] = state.clock
		state.next_model = 0
		log("chat ban " .. id .. " " .. tostring(hero_unit(id)))
	end
end

return script
