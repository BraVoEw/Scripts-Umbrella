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
		hc_group_main = "Main",
		hc_group_rows = "History rows",
		hc_enable = "Enable",
		hc_enable_tip = "Changes rows of your match history,\nonly on your screen",
		hc_gear_extra = "Extra",
		hc_debug = "Debug log",
		hc_debug_tip = "Writes what the script is doing\nto the log",
		hc_dump_key = "Dump panel to log",
		hc_dump_key_tip = "Open History and press it,\nthe panel layout goes to the log",
		hc_bind_name = "History Changer dump",
		hc_day = "MMR pill",
		hc_day_tip = "Pill above the profile card with wins,\nlosses and MMR for the period",
		hc_period = "Period",
		hc_periods_day = "24 hours",
		hc_periods_week = "Week",
		hc_periods_month = "Month",
		hc_chip_day = "24 hours",
		hc_chip_week = "7 days",
		hc_chip_month = "30 days",
		hc_chip_record = "%d W · %d L",
		hc_mmr = "MMR in result",
		hc_mmr_tip = "Shows MMR after the match and the change\ninstead of Win or Loss",
		hc_gear_mmr = "Result",
		hc_format = "Format",
		hc_formats_mmr = "1569 (+25)",
		hc_formats_full = "Win 1569 (+25)",
		hc_word_win = "Win",
		hc_word_loss = "Loss",
		hc_formats_delta = "+25",
		hc_win_color = "Win color",
		hc_loss_color = "Loss color",
		hc_zero_color = "No change color",
		hc_custom = "Custom hero text",
		hc_custom_tip = "Replaces the hero name\nwith your text in every row",
		hc_custom_color = "Text color",
		hc_custom_text = "Text",
	},
	ru = {
		hc_group_main = "Основное",
		hc_group_rows = "Строки истории",
		hc_enable = "Включить",
		hc_enable_tip = "Меняет строки истории матчей,\nвидно только у тебя на экране",
		hc_gear_extra = "Дополнительно",
		hc_debug = "Отладка в лог",
		hc_debug_tip = "Пишет в лог, что сейчас делает скрипт",
		hc_dump_key = "Панель в лог",
		hc_dump_key_tip = "Открой историю и нажми,\nустройство панели уйдет в лог",
		hc_bind_name = "History Changer, лог панели",
		hc_day = "Плашка MMR",
		hc_day_tip = "Плашка над карточкой профиля:\nвины, лузы и MMR за период",
		hc_period = "Период",
		hc_periods_day = "За сутки",
		hc_periods_week = "За неделю",
		hc_periods_month = "За месяц",
		hc_chip_day = "24 часа",
		hc_chip_week = "7 дней",
		hc_chip_month = "30 дней",
		hc_chip_record = "%d вин · %d луз",
		hc_mmr = "MMR в результате",
		hc_mmr_tip = "Показывает MMR после матча и изменение\nвместо Win или Loss",
		hc_gear_mmr = "Результат",
		hc_format = "Формат",
		hc_formats_mmr = "1569 (+25)",
		hc_formats_full = "Победа 1569 (+25)",
		hc_word_win = "Победа",
		hc_word_loss = "Поражение",
		hc_formats_delta = "+25",
		hc_win_color = "Цвет победы",
		hc_loss_color = "Цвет поражения",
		hc_zero_color = "Цвет без изменения",
		hc_custom = "Свой текст вместо героя",
		hc_custom_tip = "Заменяет имя героя\nтвоим текстом в каждой строке",
		hc_custom_color = "Цвет текста",
		hc_custom_text = "Текст",
	},
})

local UI = localization.WrapLibrary(Menu)
local L = localization.Get

local ui = {}

do
	local tab = UI.Create("Scripts", "Scripts", "History Changer")
	tab:Icon("\u{f1da}")

	local page = tab:Create("Settings")
	local g_main = page:Create("hc_group_main", Enum.GroupSide.Left)
	local g_rows = page:Create("hc_group_rows", Enum.GroupSide.Right)

	ui.enable = g_main:Switch("hc_enable", false, "\u{f011}")
	ui.enable:ToolTip("hc_enable_tip")
	local g_gear = ui.enable:Gear("hc_gear_extra")
	ui.debug = g_gear:Switch("hc_debug", false, "\u{f188}")
	ui.debug:ToolTip("hc_debug_tip")
	ui.dump_key = g_gear:Bind("hc_dump_key", Enum.ButtonCode.KEY_NONE, "\u{f11c}")
	ui.dump_key:ToolTip("hc_dump_key_tip")

	ui.day = g_main:Switch("hc_day", true, "\u{f073}")
	ui.day:ToolTip("hc_day_tip")
	ui.period = g_main:Combo("hc_period", { "hc_periods_day", "hc_periods_week", "hc_periods_month" }, 1)
	ui.period:Icon("\u{f017}")

	ui.mmr = g_rows:Switch("hc_mmr", true, "\u{f201}")
	ui.mmr:ToolTip("hc_mmr_tip")
	local g_mmr = ui.mmr:Gear("hc_gear_mmr")
	ui.format = g_mmr:Combo("hc_format", { "hc_formats_mmr", "hc_formats_full", "hc_formats_delta" }, 0)
	ui.format:Icon("\u{f1de}")

	ui.win_color = g_rows:ColorPicker("hc_win_color", Color(111, 214, 111), "\u{f53f}")
	ui.loss_color = g_rows:ColorPicker("hc_loss_color", Color(232, 98, 90), "\u{f53f}")
	ui.zero_color = g_rows:ColorPicker("hc_zero_color", Color(150, 154, 160), "\u{f53f}")

	ui.custom = g_rows:Switch("hc_custom", false, "\u{f036}")
	ui.custom:ToolTip("hc_custom_tip")
	ui.custom_color = ui.custom:ColorPicker("hc_custom_color", Color(120, 180, 255))
	ui.custom_text = g_rows:Input("hc_custom_text", "", "\u{f031}")

	ui.dump_key:Properties(L("hc_bind_name"))
end

local function refresh_disabled()
	local on = ui.enable:Get()
	local mmr = on and ui.mmr:Get()
	ui.debug:Disabled(not on)
	ui.dump_key:Disabled(not on)
	ui.day:Disabled(not on)
	ui.period:Disabled(not on or not ui.day:Get())
	ui.mmr:Disabled(not on)
	ui.format:Disabled(not mmr)
	ui.win_color:Disabled(not on)
	ui.loss_color:Disabled(not on)
	ui.zero_color:Disabled(not on)
	ui.custom:Disabled(not on)
	ui.custom_text:Disabled(not on or not ui.custom:Get())
end

ui.enable:SetCallback(refresh_disabled, true)
ui.day:SetCallback(refresh_disabled)
ui.mmr:SetCallback(refresh_disabled)
ui.custom:SetCallback(refresh_disabled)

local function log(text)
	if ui.debug:Get() then
		Log.Write("[History Changer] " .. text)
	end
end

local protobuf = require("protobuf")
local JSON = require("assets.JSON")

local K = {
	MSG_HISTORY_REQUEST = 7408,
	MSG_HISTORY_RESPONSE = 7409,
	OWN_REQUEST_ID = 24301,
	MATCHES_REQUESTED = 20,
	MAX_PAGES = 6,
	REQUEST_RETRY = 30,
	STEAM64_BASE = 76561197960265728,
	APPLY_INTERVAL = 0.25,
	SEARCH_INTERVAL = 1.0,
	SEARCH_BUDGET = 6000,
	ROW_DEPTH = 4,
	CLIMB_DEPTH = 5,
	ROOT_IDS = { "DOTAHeroesPage", "DotaDashboard" },
	DUMP_LINES = 400,
	DUMP_DEPTH = 7,
	DUMP_LABELS = 40,
	WEEK = 7 * 86400,
	MONTH = 30 * 86400,
	PERIODS = { 86400, 7 * 86400, 30 * 86400 },
	PERIOD_TITLES = { "hc_chip_day", "hc_chip_week", "hc_chip_month" },
	HEADER_MIN = 60,
	FALLBACK_HEADER = 150,
	CARD_DEPTH = 12,
	CARD_WIDTH_RATIO = 1.3,
	PAGE_DEPTH = 16,
	PAGE_MANAGER = "PageManager",
	CHIP_SCALE = 1.46,
	CHIP_SHIFT_X = 12,
	CHIP_SHIFT_Y = 64,
	CHIP_ABOVE = 14,
	PILL_H = 32,
	FONT_MAIN = 12,
	FONT_SUB = 11,
	FONT_ICON = 13,
	BG = Color(14, 16, 18, 184),
	TEXT = Color(240, 240, 242),
	GRAY = Color(150, 154, 160),
	SEPARATOR = Color(255, 255, 255, 46),
}

local fonts = {
	bold = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.BOLD),
	normal = Render.LoadFont("Inter", Enum.FontCreate.FONTFLAG_ANTIALIAS, Enum.FontWeight.NORMAL),
	icon = Render.LoadFont("FontAwesomeEx", Enum.FontCreate.FONTFLAG_ANTIALIAS, 400),
}

local state = {
	clock = 0,
	next_apply = 0,
	next_search = 0,
	requests = {},
	own_account = nil,
	next_request = 0,
	shown_account = nil,
	row_accounts = {},
	matches = {},
	by_duration = {},
	container = nil,
	anchor = nil,
	geo_summary = nil,
	page_visible = false,
	left = false,
	siblings = {},
	triggers = {},
	track_error = nil,
	periods_text = nil,
	summary = nil,
	own_loaded = false,
	own_pages = 0,
	page_from = nil,
	applied = false,
	frame_error = nil,
}

local function decode(name, buffer, size)
	local ok, text = pcall(protobuf.decodeToJSON, name, buffer, size)
	if not ok or type(text) ~= "string" then return nil end
	local ok_json, data = pcall(JSON.decode, JSON, text)
	if ok_json then return data end
end

local function own_account()
	if not state.own_account then
		local steam64 = tonumber(GC.GetSteamID() or "")
		if steam64 and steam64 > K.STEAM64_BASE then
			state.own_account = steam64 - K.STEAM64_BASE
		end
	end
	return state.own_account
end

local function store_history(resp)
	local req = state.requests[tonumber(resp.request_id) or 0] or {}
	local account = req.account or own_account() or 0

	local count, ranked = 0, 0
	for _, m in ipairs(resp.matches or {}) do
		local id = tostring(m.match_id)
		local prev = tonumber(m.previous_rank) or 0
		local entry = state.matches[id]
		if not entry then
			entry = {}
			state.matches[id] = entry
		end
		entry.account = account
		entry.start = tonumber(m.start_time) or 0
		entry.win = m.winner == true
		entry.prev = prev
		entry.change = tonumber(m.rank_change) or 0
		entry.ranked = prev > 0
		if not entry.duration then
			entry.duration = tonumber(m.duration) or 0
			local list = state.by_duration[entry.duration] or {}
			list[#list + 1] = entry
			state.by_duration[entry.duration] = list
		end
		count = count + 1
		if entry.ranked then ranked = ranked + 1 end
	end
	log("history " .. count .. " matches, ranked " .. ranked .. ", account " .. tostring(account)
		.. (req.more and ", next page" or ""))

	if tonumber(resp.request_id) ~= K.OWN_REQUEST_ID then return end
	state.own_loaded = true
	state.own_pages = state.own_pages + 1

	local oldest_id, oldest_start
	for _, m in ipairs(resp.matches or {}) do
		local start = tonumber(m.start_time) or 0
		if not oldest_start or start < oldest_start then
			oldest_start, oldest_id = start, tonumber(m.match_id)
		end
	end
	if oldest_id and oldest_start > os.time() - K.MONTH and state.own_pages < K.MAX_PAGES then
		state.page_from = oldest_id - 1
	end
end

local function request_own_history(start_at)
	local account = own_account()
	if not account then return end
	local ok, request = pcall(protobuf.encodeFromJSON, "CMsgDOTAGetPlayerMatchHistory", JSON:encode({
		account_id = account,
		start_at_match_id = start_at,
		matches_requested = K.MATCHES_REQUESTED,
		request_id = K.OWN_REQUEST_ID,
	}))
	if not ok or not request then return end
	state.requests[K.OWN_REQUEST_ID] = { account = account, more = start_at ~= nil }
	GC.SendMessage(request.binary, K.MSG_HISTORY_REQUEST, request.size)
	log("requested own history, account " .. account .. (start_at and (", from " .. start_at) or ""))
end

local function request_pages()
	if state.page_from then
		local from = state.page_from
		state.page_from = nil
		request_own_history(from)
	elseif not state.own_loaded and state.clock >= state.next_request then
		state.next_request = state.clock + K.REQUEST_RETRY
		request_own_history(nil)
	end
end

local function parse_duration(text)
	local h, m, s = text:match("^(%d+):(%d%d):(%d%d)$")
	if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) end
	m, s = text:match("^(%d+):(%d%d)$")
	if m then return tonumber(m) * 60 + tonumber(s) end
end

local function is_date(text)
	return text:match("^%d+[/%.%-]%d+[/%.%-]%d%d%d%d") ~= nil
end

local function collect_labels(panel, depth, out)
	if depth > K.ROW_DEPTH then return out end
	for i = 0, panel:GetChildCount() - 1 do
		local child = panel:GetChild(i)
		if child and child:IsVisible() then
			if child:GetPanelType() == "Label" then
				out[#out + 1] = child
			end
			collect_labels(child, depth + 1, out)
		end
	end
	return out
end

local function parse_row(row)
	local labels = collect_labels(row, 1, {})
	local date_i
	for i, label in ipairs(labels) do
		if is_date(label:GetText() or "") then
			date_i = i
			break
		end
	end
	if not date_i or date_i < 2 then return nil end

	local date_text = labels[date_i]:GetText()
	local dur_i = date_text:find(":", 1, true) and date_i + 1 or date_i + 2
	local seconds = labels[dur_i] and parse_duration(labels[dur_i]:GetText() or "")
	if not seconds then return nil end

	return {
		hero = date_i >= 3 and labels[1] or nil,
		result = labels[date_i - 1],
		date = date_text,
		seconds = seconds,
	}
end

local function match_for_row(info)
	local list = state.by_duration[info.seconds]
	if not list then return nil end
	if #list == 1 then return list[1] end
	local nums = {}
	for n in info.date:gmatch("%d+") do
		nums[tonumber(n)] = true
	end
	for _, m in ipairs(list) do
		local d = os.date("*t", m.start)
		if nums[d.day] and nums[d.month] and nums[d.year] then return m end
	end
	return list[1]
end

local function strip_tags(text)
	return (text:gsub("<[^>]->", ""))
end

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colored(color, text)
	return string.format("<font color='#%02x%02x%02x'>%s</font>",
		math.floor(color.r), math.floor(color.g), math.floor(color.b), text)
end

local function looks_ours(text)
	return text:find("<", 1, true) ~= nil
		or text:find("%([%+%-]%d+%)") ~= nil
		or text:match("^[%+%-]%d+$") ~= nil
end

local function original_text(label)
	local current = label:GetText() or ""
	if current ~= "" and current ~= (label:GetAttribute("hc_seen", "") or "") and not looks_ours(current) then
		label:SetAttribute("hc_orig", current)
	end
	local orig = label:GetAttribute("hc_orig", "") or ""
	if looks_ours(orig) then return "" end
	return orig
end

local function write_label(label, text)
	original_text(label)
	local current = label:GetText() or ""
	if text ~= (label:GetAttribute("hc_set", "") or "") or current ~= (label:GetAttribute("hc_seen", "") or "") then
		label:SetTextType(3)
		label:SetText(text)
		label:SetAttribute("hc_set", text)
		label:SetAttribute("hc_seen", label:GetText() or "")
	end
end

local function restore_label(label)
	local set = label:GetAttribute("hc_set", "") or ""
	if set == "" then return end
	local orig = label:GetAttribute("hc_orig", "") or ""
	if orig ~= "" and not looks_ours(orig) and (label:GetText() or "") == (label:GetAttribute("hc_seen", "") or "") then
		label:SetText(orig)
	end
	label:SetAttribute("hc_set", "")
	label:SetAttribute("hc_seen", "")
end

local function change_color(match)
	if match.change == 0 then return ui.zero_color:Get() end
	return match.win and ui.win_color:Get() or ui.loss_color:Get()
end

local function result_text(match, label)
	local after = tostring(match.prev + match.change)
	local delta = string.format("%+d", match.change)
	local format = ui.format:Get()
	local text
	if format == 2 then
		text = delta
	elseif format == 1 then
		local word = strip_tags(original_text(label))
		if word == "" then
			word = L(match.win and "hc_word_win" or "hc_word_loss")
		end
		text = word .. " " .. after .. " (" .. delta .. ")"
	else
		text = after .. " (" .. delta .. ")"
	end
	return colored(change_color(match), text)
end

local function apply_row(info, enabled)
	local match = enabled and match_for_row(info)
	if match then
		state.row_accounts[match.account] = (state.row_accounts[match.account] or 0) + 1
	end

	if match and match.ranked and ui.mmr:Get() then
		write_label(info.result, result_text(match, info.result))
	else
		restore_label(info.result)
	end

	if info.hero then
		local text = ui.custom_text:Get() or ""
		if enabled and ui.custom:Get() and text ~= "" then
			write_label(info.hero, colored(ui.custom_color:Get(), escape(text)))
		else
			restore_label(info.hero)
		end
	end
end

local function apply_rows(container, enabled)
	state.row_accounts = {}
	for i = 0, container:GetChildCount() - 1 do
		local row = container:GetChild(i)
		if row and row:IsVisible() then
			local info = parse_row(row)
			if info then
				apply_row(info, enabled)
			end
		end
	end

	local best, best_count = nil, 0
	for account, count in pairs(state.row_accounts) do
		if count > best_count then
			best, best_count = account, count
		end
	end
	state.shown_account = best
end

local function is_shown(panel)
	if not panel:IsValid() then return false end
	local p, depth = panel, 0
	while p and depth < 64 do
		if not p:IsVisible() then return false end
		p = p:GetParent()
		depth = depth + 1
	end
	return true
end

local function find_root()
	for _, id in ipairs(K.ROOT_IDS) do
		local panel = Panorama.GetPanelByName(id, false)
		if panel then
			local root = panel
			local parent = root:GetParent()
			while parent do
				root = parent
				parent = root:GetParent()
			end
			return root
		end
	end
end

local function container_from_label(label)
	local row = label:GetParent()
	for _ = 1, K.CLIMB_DEPTH do
		if not row then return nil end
		local parent = row:GetParent()
		if parent and parse_row(row) then
			return parent
		end
		row = parent
	end
end

local function search_container(root)
	local stack, seen = { root }, 0
	while #stack > 0 and seen < K.SEARCH_BUDGET do
		local panel = table.remove(stack)
		seen = seen + 1
		if panel:IsVisible() then
			if panel:GetPanelType() == "Label" then
				local seconds = parse_duration(panel:GetText() or "")
				if seconds and state.by_duration[seconds] then
					local container = container_from_label(panel)
					if container then return container end
				end
			end
			for i = panel:GetChildCount() - 1, 0, -1 do
				local child = panel:GetChild(i)
				if child then stack[#stack + 1] = child end
			end
		end
	end
end

local function window_stats(window, now)
	local stats = { wins = 0, losses = 0, mmr = 0, ranked = 0 }
	for _, m in pairs(state.matches) do
		if m.account == state.shown_account and now - (m.start + m.duration) <= window then
			if m.win then stats.wins = stats.wins + 1 else stats.losses = stats.losses + 1 end
			stats.mmr = stats.mmr + m.change
			if m.ranked then stats.ranked = stats.ranked + 1 end
		end
	end
	return stats
end

local function log_periods(now)
	if not ui.debug:Get() then return end
	local parts, oldest = {}, nil
	for i, window in ipairs(K.PERIODS) do
		local s = window_stats(window, now)
		parts[i] = string.format("%dd %dW %dL %+d MMR (%d ranked)", window // 86400, s.wins, s.losses, s.mmr, s.ranked)
	end
	for _, m in pairs(state.matches) do
		if m.account == state.shown_account and (not oldest or m.start < oldest) then oldest = m.start end
	end
	local text = table.concat(parts, ", ") .. ", oldest loaded " .. (oldest and os.date("%d.%m.%Y", oldest) or "none")
	if text ~= state.periods_text then
		state.periods_text = text
		log("periods: " .. text)
	end
end

local function period_stats()
	local now = os.time()
	local period = ui.period:Get()
	local stats = window_stats(K.PERIODS[period + 1] or K.WEEK, now)
	stats.title = L(K.PERIOD_TITLES[period + 1] or "hc_chip_week")
	log_periods(now)
	return stats
end

local function find_page(container)
	local p = container
	for _ = 1, K.PAGE_DEPTH do
		local parent = p:GetParent()
		if not parent then return nil end
		if parent:GetPanelType() == K.PAGE_MANAGER then return p end
		p = parent
	end
end

local function track_pages(container)
	local page = find_page(container)
	if not page then return end
	local manager = page:GetParent()

	local own_visible = page:IsVisible()
	if own_visible and not state.page_visible then
		state.left = false
		state.triggers = {}
	end
	state.page_visible = own_visible

	for i = 0, manager:GetChildCount() - 1 do
		local sibling = manager:GetChild(i)
		if sibling and not (sibling == page) then
			local visible = sibling:IsVisible()
			local was = state.siblings[i]
			if visible and was == false then
				state.left = true
				state.triggers[i] = true
				log("page opened: " .. sibling:GetPanelType() .. (sibling:HasID() and ("#" .. sibling:GetID()) or ""))
			elseif not visible and was and state.triggers[i] then
				state.triggers[i] = nil
				if next(state.triggers) == nil then state.left = false end
			end
			state.siblings[i] = visible
		end
	end
end

local function geometry(container)
	local cpos = container:GetPositionWithinWindow()
	if not cpos then return nil end
	local w = container:GetLayoutWidth() or 0
	local geo = { shown = is_shown(container), x = cpos.x, y = cpos.y - K.FALLBACK_HEADER, w = w, scale = 1 }
	local p = container:GetParent()
	for _ = 1, K.CARD_DEPTH do
		if not p then break end
		local pos = p:GetPositionWithinWindow()
		if pos and pos.y < cpos.y - K.HEADER_MIN then
			local pw = p:GetLayoutWidth() or 0
			if pw > 0 and (w <= 0 or pw <= w * K.CARD_WIDTH_RATIO) then
				geo.x, geo.y, geo.w = pos.x, pos.y, pw
			end
			break
		end
		p = p:GetParent()
	end
	return geo
end

local function geometry_text(geo)
	return tostring(geo.shown) .. " x " .. math.floor(geo.x) .. " y " .. math.floor(geo.y) .. " w " .. math.floor(geo.w)
end

local function update_anchor(container)
	local geo = geometry(container)
	if not geo then
		state.anchor = nil
		return
	end
	local summary = geometry_text(geo)
	if summary ~= state.geo_summary then
		state.geo_summary = summary
		log("card " .. summary)
	end
	state.anchor = geo.shown and { x = geo.x + geo.w / 2, y = geo.y, scale = geo.scale } or nil
end

local function mmr_color(value)
	if value > 0 then return ui.win_color:Get() end
	if value < 0 then return ui.loss_color:Get() end
	return ui.zero_color:Get()
end

local function draw_chip()
	local anchor = state.anchor
	local stats = state.summary
	if not anchor or not stats then return end

	local ui_scale = anchor.scale
	local s = K.CHIP_SCALE * ui_scale
	local h = math.floor(K.PILL_H * s / 2 + 0.5) * 2
	local r = h / 2
	local main, sub, icon_size = K.FONT_MAIN * s, K.FONT_SUB * s, K.FONT_ICON * s

	local icon = "\u{f073}"
	local title = stats.title
	local record = string.format(L("hc_chip_record"), stats.wins, stats.losses)
	local delta = string.format("%+d MMR", stats.mmr)

	local icon_sz = Render.TextSize(fonts.icon, icon_size, icon)
	local title_sz = Render.TextSize(fonts.bold, main, title)
	local record_sz = Render.TextSize(fonts.normal, sub, record)
	local delta_sz = Render.TextSize(fonts.bold, main, delta)

	local content = r + 18 * s
	local w = content + title_sz.x + 17 * s + record_sz.x + 8 * s + delta_sz.x + 12 * s
	w = math.floor(w / 2 + 0.5) * 2

	local x = math.floor(anchor.x - w / 2 + K.CHIP_SHIFT_X * ui_scale + 0.5)
	local y = math.floor(anchor.y - h - K.CHIP_ABOVE * s + K.CHIP_SHIFT_Y * ui_scale + 0.5)
	local cy = y + r

	Render.FilledRect(Vec2(x, y), Vec2(x + w, y + h), K.BG, r, Enum.DrawFlags.RoundCornersAll)
	Render.PushClip(Vec2(x, y), Vec2(x + w, y + h), true)
	Render.Text(fonts.icon, icon_size, icon, Vec2(x + r - icon_sz.x / 2, cy - icon_sz.y / 2), K.TEXT)

	local tx = x + content
	Render.Text(fonts.bold, main, title, Vec2(tx, cy - title_sz.y / 2), K.TEXT)
	tx = tx + title_sz.x + 8 * s
	Render.FilledRect(Vec2(tx, cy - 7 * s), Vec2(tx + 1, cy + 7 * s), K.SEPARATOR)
	tx = tx + 1 + 8 * s
	Render.Text(fonts.normal, sub, record, Vec2(tx, cy - record_sz.y / 2), K.GRAY)
	tx = tx + record_sz.x + 8 * s
	Render.Text(fonts.bold, main, delta, Vec2(tx, cy - delta_sz.y / 2), mmr_color(stats.mmr))
	Render.PopClip()
end

local function panel_line(panel, depth)
	local parts = { string.rep("  ", depth), panel:GetPanelType() }
	if panel:HasID() then parts[#parts + 1] = " #" .. panel:GetID() end
	local classes = panel:GetClassList()
	if classes and #classes > 0 then parts[#parts + 1] = " ." .. table.concat(classes, ".") end
	if not panel:IsVisible() then parts[#parts + 1] = " (hidden)" end
	if panel:GetPanelType() == "Label" then parts[#parts + 1] = " \"" .. (panel:GetText() or "") .. "\"" end
	return table.concat(parts)
end

local function dump_tree(panel, depth, lines)
	if #lines >= K.DUMP_LINES then return end
	lines[#lines + 1] = panel_line(panel, depth)
	if depth >= K.DUMP_DEPTH then return end
	for i = 0, panel:GetChildCount() - 1 do
		local child = panel:GetChild(i)
		if child then dump_tree(child, depth + 1, lines) end
	end
end

local function chain_text(panel)
	local chain = {}
	local p = panel
	while p and #chain < 12 do
		chain[#chain + 1] = p:GetPanelType() .. (p:HasID() and ("#" .. p:GetID()) or "")
		p = p:GetParent()
	end
	return table.concat(chain, " < ")
end

local function dump_labels(root, lines)
	local stack, found = { root }, 0
	while #stack > 0 and found < K.DUMP_LABELS and #lines < K.DUMP_LINES do
		local panel = table.remove(stack)
		if panel:IsVisible() then
			if panel:GetPanelType() == "Label" then
				local text = panel:GetText() or ""
				if parse_duration(text) or is_date(text) then
					found = found + 1
					lines[#lines + 1] = "\"" .. text .. "\" in " .. chain_text(panel)
				end
			end
			for i = panel:GetChildCount() - 1, 0, -1 do
				local child = panel:GetChild(i)
				if child then stack[#stack + 1] = child end
			end
		end
	end
end

local function dump()
	local total, ranked = 0, 0
	for _, m in pairs(state.matches) do
		total = total + 1
		if m.ranked then ranked = ranked + 1 end
	end

	local lines = { "dump: matches " .. total .. ", ranked " .. ranked .. ", own account " .. tostring(own_account())
		.. ", shown account " .. tostring(state.shown_account) }
	local root = find_root()
	lines[#lines + 1] = "root " .. (root and panel_line(root, 0) or "not found")
	local container = state.container or (root and search_container(root))
	if container then
		lines[#lines + 1] = "container " .. chain_text(container)
		local geo = geometry(container)
		lines[#lines + 1] = "card " .. (geo and geometry_text(geo) or "unknown")
		local page = find_page(container)
		lines[#lines + 1] = "page " .. (page and panel_line(page, 0) or "not found") .. ", left " .. tostring(state.left)
		dump_tree(container:GetParent() or container, 0, lines)
	elseif root then
		lines[#lines + 1] = "container not found, date and time labels:"
		dump_labels(root, lines)
	end

	for _, line in ipairs(lines) do
		Log.Write("[History Changer] " .. line)
	end
end

local function tick()
	if ui.dump_key:IsPressed() then
		dump()
	end
	request_pages()
	if next(state.matches) == nil then return end

	if state.clock >= state.next_apply then
		state.next_apply = state.clock + K.APPLY_INTERVAL
		if state.container and not is_shown(state.container) then
			state.container = nil
			state.anchor = nil
			state.geo_summary = nil
			state.page_visible = false
			log("history panel closed")
		end
		if not state.container and state.clock >= state.next_search then
			state.next_search = state.clock + K.SEARCH_INTERVAL
			local root = find_root()
			state.container = root and search_container(root)
			if state.container then
				log("history panel found: " .. chain_text(state.container))
			end
		end
		if state.container then
			apply_rows(state.container, true)
			state.applied = true
			update_anchor(state.container)
			state.summary = period_stats()
		end
	end

	if state.container and state.container:IsValid() then
		local ok, err = pcall(track_pages, state.container)
		if not ok then
			state.left = false
			if err ~= state.track_error then
				state.track_error = err
				log("page tracking: " .. tostring(err))
			end
		end
		if ui.day:Get() and not state.left then
			draw_chip()
		end
	end
end

local script = {}

function script.OnGCMessage(msg)
	if msg.msg_type == K.MSG_HISTORY_REQUEST and msg.binary_buffer_send then
		local req = decode("CMsgDOTAGetPlayerMatchHistory", msg.binary_buffer_send, msg.size)
		if req then
			state.requests[tonumber(req.request_id) or 0] = {
				account = tonumber(req.account_id),
				more = (tonumber(req.start_at_match_id) or 0) > 0,
			}
		end
	elseif msg.msg_type == K.MSG_HISTORY_RESPONSE and msg.binary_buffer_recv then
		local resp = decode("CMsgDOTAGetPlayerMatchHistoryResponse", msg.binary_buffer_recv, msg.size)
		if resp then
			store_history(resp)
		end
	end
	return true
end

function script.OnFrame()
	if not ui.enable:Get() then
		if state.applied then
			state.applied = false
			if state.container and state.container:IsValid() then
				pcall(apply_rows, state.container, false)
			end
			state.container = nil
		end
		return
	end

	state.clock = state.clock + math.min(0.1, GlobalVars.GetAbsFrameTime())
	local ok, err = pcall(tick)
	if not ok and err ~= state.frame_error then
		state.frame_error = err
		Log.Write("[History Changer] " .. tostring(err))
	end
end

return script
