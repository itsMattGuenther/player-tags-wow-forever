-- Menu: "Tag player" in the right-click menu of players.
local _, ns = ...

-- Right-click menus that belong to a player. The game names each one
-- "MENU_UNIT_" plus one of these.
local MENUS = {
	"PLAYER", "ENEMY_PLAYER", "TARGET", "FOCUS", "PARTY", "RAID", "RAID_PLAYER",
	"FRIEND", "FRIEND_OFFLINE", "GUILD", "GUILD_OFFLINE", "CHAT_ROSTER",
	"COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER",
	"RECENT_ALLY", "RECENT_ALLY_OFFLINE", "PVP_SCOREBOARD", "WORLD_STATE_SCORE",
}

-- Works out who a menu is about from the data the game attaches to it.
local function identity(context)
	if type(context) ~= "table" then return nil end

	local unit = context.unit
	if unit ~= nil and not ns.IsSecret(unit) and type(unit) == "string" and UnitExists(unit) then
		if not UnitIsPlayer(unit) then return nil end -- an NPC or a pet
		local id = ns.IdentifyUnit(unit)
		if id then return id end
	end

	local name = context.name
	if not ns.IsText(name) then return nil end
	local full = name
	local surname = context.surname
	if ns.IsText(surname) and not name:find(surname, 1, true) then
		full = ns.FullName(name, surname)
	end

	-- Friends, guild and recent-ally lists hand over the GUID directly; a
	-- chat name gives its line, which the game can turn into one.
	local guid
	if ns.IsText(context.guid) then guid = context.guid end
	local lineID = context.lineID
	if not guid and lineID ~= nil and not ns.IsSecret(lineID) and C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID then
		local ok, found = pcall(C_ChatInfo.GetChatLineSenderGUID, lineID)
		if ok and ns.IsText(found) then guid = found end
	end
	return ns.IdentifyName(full, guid)
end

local function onMenu(_, root, context)
	if not ns.settings.menu then return end
	local id = identity(context)
	if not id or ns.IsMe(id) then return end

	root:CreateDivider()
	root:CreateTitle("Player Tags")
	root:CreateButton("Tag player", function()
		ns.Safe("menu", ns.OpenQuickTag, id)
	end)
	if ns.Lookup(id) then
		root:CreateButton("Remove tags", function()
			local _, key = ns.Lookup(id)
			if key then ns.DeleteRecord(key) end
		end)
	end
end

ns.Module("menu", function()
	if not (Menu and Menu.ModifyMenu) then
		return "the right-click menu hook was not found"
	end
	for _, which in ipairs(MENUS) do
		Menu.ModifyMenu("MENU_UNIT_" .. which, function(owner, root, context)
			local ok, err = pcall(onMenu, owner, root, context)
			if not ok then ns.Fail("menu", err) end
		end)
	end
end)
