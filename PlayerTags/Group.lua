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
	local rows, chat, warn = {}, { "|cffffd100Player Tags:|r " .. summary }, false
	for _, info in ipairs(list) do
		local ids = ns.DisplayIds(info)
		local name = info.rec and ns.ColoredName(info.rec) or ns.ClassColorCode(info.class) .. (info.name or "?") .. "|r"
		rows[#rows + 1] = { ids = ids, text = name .. "  |cffa7afb8" .. ns.TagNames(ids) .. "|r" }
		local line = "   " .. ns.TagsEscape(ids, 0) .. " " .. name .. "  " .. ns.TagNames(ids)
		if info.rec and ns.IsText(info.rec.note) then line = line .. "  |cffa7afb8\"" .. info.rec.note .. "\"|r" end
		chat[#chat + 1] = line
		if ns.ShouldWarn(info) then warn = true end
	end
	ns.Notify({ kind = "group", title = summary, rows = rows, chat = chat, avoid = warn })
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
			local info = ns.TagsFor(id, rec, key)
			-- Your own tags always count. A shared list only counts when
			-- you turned its alerts on.
			local counts = info and (#info.ids > 0 or info.sharedAvoid)
			if counts then
				for _, from in ipairs(info.shared) do
					if not from.alerts then from.ids = {} end
				end
			end
			local slot = key or id.key
			if counts and not announced[slot] then
				announced[slot] = true
				info.name, info.class = id.name, id.class
				fresh[#fresh + 1] = info
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
