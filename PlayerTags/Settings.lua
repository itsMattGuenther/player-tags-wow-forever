-- Settings: Player Tags' page in the game's own Settings panel
-- (Esc > Options > AddOns > Player Tags), built from the game's own
-- checkboxes, sliders and dropdowns. Every value lives in ns.settings
-- (PlayerTagsDB.settings), the same keys and shapes as before.
--
-- The explanation for each option is the game's tooltip beside it, as with
-- Blizzard's own options.
local _, ns = ...

local category

local function changed()
	ns.Fire("SETTINGS_CHANGED")
end

local function register()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
	local Bool, Num = Settings.VarType.Boolean, Settings.VarType.Number

	local function section(name, tip)
		if layout and CreateSettingsListSectionHeaderInitializer then
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name, tip))
		end
	end

	local function button(name, text, click, tip)
		if layout and CreateSettingsButtonInitializer then
			layout:AddInitializer(CreateSettingsButtonInitializer(name, text, click, tip, true))
		end
	end

	-- A yes/no option stored under ns.settings[key].
	local function check(key, name, tip, apply)
		local setting = Settings.RegisterProxySetting(category, "PLAYERTAGS_" .. key:upper(), Bool, name,
			ns.defaults[key] == true,
			function() return ns.settings[key] == true end,
			function(value)
				ns.settings[key] = value and true or false
				if apply then apply(value) end
				changed()
			end)
		Settings.CreateCheckbox(category, setting, tip)
		return setting
	end

	-- A choice of a few numbers, shown as a dropdown.
	local function choose(key, name, tip, choices)
		local setting = Settings.RegisterProxySetting(category, "PLAYERTAGS_" .. key:upper(), Num, name,
			ns.defaults[key],
			function() return ns.settings[key] end,
			function(value)
				ns.settings[key] = value
				changed()
			end)
		local function options()
			local container = Settings.CreateControlTextContainer()
			for _, c in ipairs(choices) do container:Add(c[1], c[2]) end
			return container:GetData()
		end
		Settings.CreateDropdown(category, setting, options, tip)
		return setting
	end

	-- A choice of a few words, shown as a dropdown.
	local function chooseText(key, name, tip, choices)
		local setting = Settings.RegisterProxySetting(category, "PLAYERTAGS_" .. key:upper(), Settings.VarType.String, name,
			ns.defaults[key],
			function() return ns.settings[key] end,
			function(value)
				ns.settings[key] = value
				changed()
			end)
		local function options()
			local container = Settings.CreateControlTextContainer()
			for _, c in ipairs(choices) do container:Add(c[1], c[2]) end
			return container:GetData()
		end
		Settings.CreateDropdown(category, setting, options, tip)
		return setting
	end

	section("Where tags show")
	check("tooltip", "Tags in tooltips",
		"Adds a tagged player's tags, your note and where you tagged them to their tooltip.")
	check("chat", "Tag icons in chat",
		"Small tag icons in front of the sender's name. Not inside dungeons and raids, where the game hides who is speaking.")
	check("frames", "Tag icons on unit frames",
		"Icons above your target, focus, party and raid frames.")
	check("finder", "Group Finder marks",
		"The leader's tags on a listing, and a count of other tagged players in the group.")
	choose("frameIconSize", "Unit frame icon size", "How big the icons above the target and focus frames are. Party and raid frames follow.",
		{ { 12, "Small" }, { 15, "Medium" }, { 19, "Large" } })
	chooseText("tooltipNote", "Notes in tooltips", "Show your note in a tagged player's tooltip always, or only while you hold Shift.",
		{ { "always", "Always" }, { "shift", "While holding Shift" } })
	check("hideInCombat", "Hide icons in combat", "Hides tag icons on nameplates and unit frames during fights. They come back when the fight ends.")
	check("showShared", "Tags from shared lists", "Shows tags from lists other players shared with you, with fainter icons. Manage the lists in the Shared lists tab of /tags.")
	check("nameplates", "Tag icons on nameplates",
		"Icons over enemy players' nameplates, and over friendly players if they have nameplates.")
	choose("plateSize", "Nameplate icon size", "How big the icons over nameplates are.",
		{ { 14, "Small" }, { 17, "Medium" }, { 21, "Large" } })
	choose("plateMax", "Most icons on a nameplate", "Avoid tags come first when there are more.",
		{ { 2, "2" }, { 3, "3" }, { 4, "4" } })
	do
		local setting = Settings.RegisterProxySetting(category, "PLAYERTAGS_FRIENDLYPLATES", Bool,
			"Friendly player nameplates", false,
			function() return ns.settings.friendlyPlates == "on" end,
			function(value)
				ns.settings.friendlyPlates = value and "on" or "off"
				if ns.ApplyFriendlyPlates then ns.ApplyFriendlyPlates() end
				changed()
			end)
		Settings.CreateCheckbox(category, setting,
			"Gives friendly players name-only nameplates, drawn to look like the game's own names, so tag icons can sit above them. Unticking it puts your previous game settings back.")
	end
	do
		local setting = Settings.RegisterProxySetting(category, "PLAYERTAGS_FRIENDLYNAMECOLOR", Settings.VarType.String,
			"Friendly name color", ns.defaults.friendlyNameColor,
			function() return ns.settings.friendlyNameColor end,
			function(value)
				ns.settings.friendlyNameColor = value
				changed()
			end)
		local function options()
			local container = Settings.CreateControlTextContainer()
			container:Add("game", "Blue, like the game")
			container:Add("class", "Class colors")
			container:Add("white", "White")
			return container:GetData()
		end
		Settings.CreateDropdown(category, setting, options,
			"The colour of friendly players' names on those nameplates. Blue matches the names the game draws by itself.")
	end
	do
		local setting = Settings.RegisterProxySetting(category, "PLAYERTAGS_FRIENDLYNAMESIZE", Num, "Friendly name size",
			ns.defaults.friendlyNameSize,
			function() return ns.settings.friendlyNameSize end,
			function(value)
				ns.settings.friendlyNameSize = math.floor(value * 20 + 0.5) / 20
				changed()
			end)
		local options = Settings.CreateSliderOptions(0.7, 1.5, 0.05)
		if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
				return math.floor(value * 100 + 0.5) .. "%"
			end)
		end
		Settings.CreateSlider(category, setting, options,
			"How big friendly players' names are on those nameplates.")
	end

	section("Alerts")
	chooseText("alertStyle", "Show alerts as", "Where heads-ups appear: the alert box, a line in chat, or both.",
		{ { "both", "Alert box and chat" }, { "box", "Alert box only" }, { "chat", "Chat only" } })
	check("groupAlert", "Group join alert",
		"When someone you tagged joins your group: a short alert box, and a line in chat.")
	check("nearbyAlert", "Avoid player nearby",
		"When someone you tagged Avoid shows up near you: their nameplate appears, you point at or target them, or they talk nearby. Not in dungeons or for your own group.")
	check("inviteWarn", "Tags on group invites",
		"Shows the inviter's tags and your note under the game's invite box, good tags as well as bad.")
	check("requestWarn", "Whispers, trades, duels",
		"Shows your tags under a duel request or the trade window, and a heads-up when someone you tagged Avoid whispers you.")
	check("lfgAlert", "Good players seeking group",
		"A line in chat when someone you tagged Good people or Skilled posts in a public channel that they are looking for a group.")
	choose("alertWait", "Alert again after", "How long before the same player can set off the same alert again.",
		{ { 5, "5 minutes" }, { 15, "15 minutes" }, { 30, "30 minutes" }, { 60, "1 hour" } })
	check("alertHoldCombat", "Hold alerts during combat", "Keeps alerts until the fight is over, then shows them.")
	check("alertSound", "Play a sound for Avoid tags",
		"The raid warning sound with alerts about someone you tagged Avoid.")
	button("Alert position", "Move", function() ns.MoveAlert() end,
		"Shows the alert box so you can drag it where you want it.")

	section("After a group or a death")
	chooseText("runCard", "Tag the group afterwards",
		"When a group of 5 minutes or more ends, a small window lists who was in it, with your most-used tags as buttons.",
		{ { "always", "After every group" }, { "dungeons", "After dungeons only" }, { "off", "Never" } })
	check("killerCard", "Tag who killed you",
		"After a death in world PvP, a small window lists the enemy players who were near you, with Ganker and Griefer as buttons.")

	section("Windows")
	do
		local setting = Settings.RegisterProxySetting(category, "PLAYERTAGS_SCALE", Num, "Window size",
			ns.defaults.scale,
			function() return ns.settings.scale end,
			function(value)
				ns.settings.scale = math.floor(value * 20 + 0.5) / 20
				changed()
			end)
		local options = Settings.CreateSliderOptions(0.7, 1.3, 0.05)
		if options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
				return math.floor(value * 100 + 0.5) .. "%"
			end)
		end
		Settings.CreateSlider(category, setting, options, "The size of the list, the tagging popup and the alert box.")
	end
	check("compactPopup", "Compact tagging popup",
		"Tag icons only, without their names. Point at an icon to see its name.")
	check("popupAtCursor", "Open popup at the mouse",
		"The tagging popup opens at your mouse pointer. Otherwise it opens in the middle of the screen, or where you last dragged it.")
	check("menu", "Tag player in menus",
		"Adds \"Tag player\" to the menu when you right-click a player, or a name in chat.")
	check("minimap", "Button on the minimap",
		"Player Tags is also in the game's addon menu by the minimap, even with this off.")

	section("Your list")
	button("Players you've tagged", "Open", function() ns.ShowWindow() end,
		"Opens your list. You can also type /tags.")
	button("Check that everything works", "Show status", function() ns.PrintStatus() end,
		"Lists in chat which parts of the addon are running and any problems it caught.")

	Settings.RegisterAddOnCategory(category)
end

--- Opens the game's Settings panel on Player Tags' page.
function ns.OpenSettings()
	if not category then register() end
	if not category then
		ns.Print("The game's Settings panel was not found.")
		return
	end
	if InCombatLockdown() then
		ns.Print("Settings can't open during combat. Try again when the fight is over.")
		return
	end
	Settings.OpenToCategory(category:GetID())
end

ns.Listen("READY", function()
	local ok, problem = pcall(register)
	if not ok then ns.Fail("settings", problem) end
end, "settings")
