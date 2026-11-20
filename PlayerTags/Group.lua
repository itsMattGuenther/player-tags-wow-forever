-- Group: tells you once when players you have tagged are in your group.
local _, ns = ...

local announced = {} -- record key -> true for this group
local quietUntil = 0 -- after a /reload, do not repeat what was already said

local function groupUnits()
	local units = {}
	if IsInRaid() then
		local count = ns.Num(GetNumGroupMembers()) or 0
		for i = 1, count do units[#units + 1] = "raid" .. i end
	else
		for i = 1, 4 do units[#units + 1] = "party" .. i end
	end
	return units
end

local function announce(list)
	local summary = (#list == 1) and "1 tagged player in your group" or (#list .. " tagged players in your group")
	ns.Print(summary)

	local warn = false
	local chat = _G.DEFAULT_CHAT_FRAME
	for _, rec in ipairs(list) do
		local ids = ns.TagIds(rec)
		local line = "   " .. ns.TagsEscape(ids, 0) .. " " .. ns.ColoredName(rec) .. "  " .. ns.TagNames(ids)
		if ns.IsText(rec.note) then line = line .. "  |cffa7afb8\"" .. rec.note .. "\"|r" end
		if chat and chat.AddMessage then chat:AddMessage(line) end
		for _, tagId in ipairs(ids) do
			local tag = ns.GetTag(tagId)
			if tag and tag.family == "avoid" then warn = true end
		end
	end

	local banner = _G.UIErrorsFrame
	if banner and banner.AddMessage then
		banner:AddMessage("Player Tags: " .. summary, 1, 0.82, 0)
	end
	if warn and ns.settings.alertSound and PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING then
		pcall(PlaySound, _G.SOUNDKIT.RAID_WARNING)
	end
end

local function scan()
	if not IsInGroup() then
		announced = {}
		return
	end
	local fresh = {}
	for _, unit in ipairs(groupUnits()) do
		local id = ns.IdentifyUnit(unit)
		if id and not ns.IsMe(id) then
			local rec, key = ns.Touch(id)
			if rec and ns.HasTags(rec) and not announced[key] then
				announced[key] = true
				fresh[#fresh + 1] = rec
			end
		end
	end
	if #fresh == 0 or not ns.settings.groupAlert then return end
	if GetTime() < quietUntil then return end
	announce(fresh)
end

local function queue()
	ns.Debounce("group", 1, scan)
end

ns.Module("group alert", function()
	ns.On("GROUP_ROSTER_UPDATE", queue, "group alert")
	ns.On("PLAYER_ENTERING_WORLD", function(_, isReload)
		if isReload == true then quietUntil = GetTime() + 6 end
		queue()
	end, "group alert")
	-- Names of new members can arrive a moment after they join.
	ns.On("UNIT_NAME_UPDATE", function(unit)
		if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return end
		if unit:match("^party%d$") or unit:match("^raid%d+$") then queue() end
	end, "group alert")
end)
