-- Nearby: a heads-up when someone you tagged Avoid shows up near you.
--
-- How the addon can tell someone is near, all from the game's own events:
--   * their nameplate appears: enemy players, and friendly players when
--     friendly nameplates are on (they are off unless you turn them on);
--   * you point at them or target them;
--   * they talk in /say, /yell or an emote, which only carries a short way.
-- Group members are left out (the group alert covers them), and so are
-- dungeons, raids and battlegrounds, where everyone is in your group or on
-- the other team anyway. Each player alerts once, then waits (15 minutes
-- by default) before alerting again.
local _, ns = ...

local function inInstance()
	local ok, inside = pcall(IsInInstance)
	return ok and inside == true
end

local function inMyGroup(unit, guid)
	if unit then
		local ok, party = pcall(UnitInParty, unit)
		local ok2, raid = pcall(UnitInRaid, unit)
		if (ok and party == true) or (ok2 and raid ~= nil and raid ~= false and not ns.IsSecret(raid)) then return true end
	end
	if ns.IsText(guid) and IsGUIDInGroup then
		local ok, inGroup = pcall(IsGUIDInGroup, guid)
		if ok and inGroup == true then return true end
	end
	return false
end

-- `how` finishes the sentence: "is nearby", "is talking nearby".
local function consider(id, unit, how)
	if not ns.settings.nearbyAlert or not id or ns.IsMe(id) then return end
	if inInstance() or inMyGroup(unit, id.guid) then return end
	local info = ns.TagsFor(id)
	if not ns.ShouldWarn(info) then return end
	local name = info.rec and ns.ColoredName(info.rec) or (ns.ClassColorCode(id.class) .. (id.name or "?") .. "|r")
	local headline = name .. " " .. how
	ns.Notify({
		kind = "nearby", key = info.key or id.key,
		wait = (tonumber(ns.settings.alertWait) or 15) * 60,
		title = headline, rows = ns.DescribeRows(info),
		chat = ns.DescribeChat(headline, info), avoid = true,
	})
end

local function fromUnit(unit)
	if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return end
	local ok, isPlayer = pcall(UnitIsPlayer, unit)
	if not ok or isPlayer ~= true then return end
	consider(ns.IdentifyUnit(unit), unit, "is nearby")
end

local function fromChat(_, sender, _, _, _, _, _, _, _, _, _, guid)
	if not ns.IsText(sender) then return end
	local id = { key = ns.Key(sender), name = sender }
	if ns.IsText(guid) then id.guid = guid end
	if not id.key then return end
	consider(id, nil, "is talking nearby")
end

ns.Module("nearby alert", function()
	ns.On("NAME_PLATE_UNIT_ADDED", function(unit) ns.Safe("nearby alert", fromUnit, unit) end, "nearby alert")
	ns.On("UPDATE_MOUSEOVER_UNIT", function() ns.Safe("nearby alert", fromUnit, "mouseover") end, "nearby alert")
	ns.On("PLAYER_TARGET_CHANGED", function() ns.Safe("nearby alert", fromUnit, "target") end, "nearby alert")
	for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }) do
		ns.On(event, function(...) ns.Safe("nearby alert", fromChat, ...) end, "nearby alert")
	end
end)

ns.NearbyConsider = consider

-- You just tagged or edited this player, so you know they are there.
ns.Listen("RECORD_CHANGED", function(key)
	if type(key) ~= "string" then return end
	ns.StartAlertWait("nearby", key)
	ns.StartAlertWait("whisper", key)
end, "nearby alert")
