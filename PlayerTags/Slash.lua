-- Slash commands.
--   /tags                 open the list          (also /playertags, /ptags)
--   /tags options|tags    open that tab
--   /tags status          what is loaded, and any problems
--   /tags export|import   backup as text
--   /tag                  tagging popup for your target or mouseover
--   /tag rude, leaver     add tags to your target, no window (good in macros)
--   /tag note <text>      set the note on your target
--   /untag rude           remove a tag; /untag alone removes them all
local ADDON, ns = ...

local function version()
	local get = C_AddOns and C_AddOns.GetAddOnMetadata
	local ok, v = pcall(get or function() end, ADDON, "Version")
	return (ok and ns.IsText(v)) and v or "?"
end

--- Prints what is loaded and any problems caught so far.
function ns.PrintStatus()
	local interface = select(4, GetBuildInfo())
	ns.Print("version " .. version() .. " on interface " .. tostring(interface) .. ". " .. ns.PlayerCount() .. " players tagged.")
	local chat = _G.DEFAULT_CHAT_FRAME
	local function say(text) chat:AddMessage("   " .. text) end
	for _, name in ipairs(ns.moduleOrder) do
		local state = ns.moduleState[name] or "?"
		local color = (state:sub(1, 2) == "ok") and "|cff4bdb69" or "|cffff5a52"
		say(name .. ": " .. color .. state .. "|r")
	end
	say("friendly nameplates: " .. tostring(ns.settings.friendlyPlates)
		.. (ns.FriendlyPlatesShowing and (ns.FriendlyPlatesShowing() and " (showing)" or " (not showing)") or ""))
	if #ns.errors == 0 then
		say("problems: |cff4bdb69none|r")
	else
		say("|cffff5a52problems (" .. #ns.errors .. "):|r")
		for _, text in ipairs(ns.errors) do
			say("|cffff5a52" .. text .. "|r  x" .. ns.ErrorCount(text))
		end
	end
end

local function help()
	ns.Print("commands")
	local chat = _G.DEFAULT_CHAT_FRAME
	local lines = {
		"|cffffd100/tag|r  open the tagging popup for your target or mouseover",
		"|cffffd100/tag rude, leaver|r  add tags to your target without a window",
		"|cffffd100/tag note <text>|r  set the note on your target",
		"|cffffd100/untag rude|r  remove a tag (|cffffd100/untag|r alone removes all of them)",
		"|cffffd100/tags|r  open your list. Also: |cffffd100/tags options|r, |cffffd100/tags tags|r, |cffffd100/tags status|r, |cffffd100/tags export|r, |cffffd100/tags import|r",
	}
	for _, line in ipairs(lines) do chat:AddMessage("   " .. line) end
end

local function handleTags(message)
	local text = ns.Trim(message)
	local command = text:lower()
	if command == "" then
		ns.ToggleWindow()
	elseif command == "options" or command == "config" or command == "settings" then
		ns.ShowWindow("options")
	elseif command == "tags" then
		ns.ShowWindow("tags")
	elseif command == "status" or command == "debug" then
		ns.PrintStatus()
	elseif command == "export" or command == "import" then
		ns.ShowShare(command)
	elseif command == "help" or command == "?" then
		help()
	else
		ns.ShowWindow("players", text)
	end
end

local function targetOrComplain()
	local id = ns.QuickTagTarget()
	if not id then ns.Print("Target a player, or point at one, then try again.") end
	return id
end

local function handleTag(message)
	local text = ns.Trim(message)
	if text == "" then
		ns.QuickTag()
		return
	end

	local noteText = text:match("^[Nn][Oo][Tt][Ee]%s+(.+)$")
	if noteText or text:lower() == "note" then
		local id = targetOrComplain()
		if not id then return end
		ns.SetNote(id, noteText or "")
		ns.Print((noteText and "Note saved for " or "Note cleared for ") .. id.name .. ".")
		return
	end

	local id = targetOrComplain()
	if not id then return end
	local done, unknown = {}, {}
	for piece in (text .. ","):gmatch("(.-),") do
		piece = ns.Trim(piece)
		if piece ~= "" then
			local tagId = ns.FindTag(piece)
			if tagId then
				ns.SetTag(id, tagId, true)
				done[#done + 1] = tagId
			else
				unknown[#unknown + 1] = piece
			end
		end
	end
	if #done > 0 then
		ns.Print("Tagged " .. id.name .. ": " .. ns.TagsEscape(done, 0) .. " " .. ns.TagNames(done))
	end
	for _, piece in ipairs(unknown) do
		ns.Print("There is no tag called \"" .. piece .. "\". Type |cffffd100/tags tags|r to see them all.")
	end
end

local function handleUntag(message)
	local text = ns.Trim(message)
	local id = targetOrComplain()
	if not id then return end
	local rec = ns.Lookup(id)
	if not rec then
		ns.Print(id.name .. " has no tags.")
		return
	end
	if text == "" then
		for _, tagId in ipairs(ns.TagIds(rec)) do ns.SetTag(id, tagId, false) end
		ns.Print("Removed every tag from " .. id.name .. ".")
		return
	end
	for piece in (text .. ","):gmatch("(.-),") do
		piece = ns.Trim(piece)
		if piece ~= "" then
			local tagId = ns.FindTag(piece)
			if tagId and ns.SetTag(id, tagId, false) then
				ns.Print("Removed " .. ns.GetTag(tagId).name .. " from " .. id.name .. ".")
			elseif tagId then
				ns.Print(id.name .. " is not tagged " .. ns.GetTag(tagId).name .. ".")
			else
				ns.Print("There is no tag called \"" .. piece .. "\".")
			end
		end
	end
end

_G.SLASH_PLAYERTAGS1 = "/tags"
_G.SLASH_PLAYERTAGS2 = "/playertags"
_G.SLASH_PLAYERTAGS3 = "/ptags"
SlashCmdList["PLAYERTAGS"] = function(message) ns.Safe("/tags", handleTags, message or "") end

_G.SLASH_PLAYERTAGSTAG1 = "/tag"
SlashCmdList["PLAYERTAGSTAG"] = function(message) ns.Safe("/tag", handleTag, message or "") end

_G.SLASH_PLAYERTAGSUNTAG1 = "/untag"
SlashCmdList["PLAYERTAGSUNTAG"] = function(message) ns.Safe("/untag", handleUntag, message or "") end

_G.PlayerTags_ToggleWindow = function()
	ns.Safe("window", ns.ToggleWindow)
end

-- A short hello the first time the addon runs on this account.
ns.Listen("READY", function()
	if ns.db.welcomed then return end
	ns.db.welcomed = true
	ns.After(6, function()
		ns.Print("ready. Target a player and type |cffffd100/tag|r, or set a key in Options > Keybindings > AddOns. |cffffd100/tags|r opens your list.")
	end, "welcome")
end, "welcome")
