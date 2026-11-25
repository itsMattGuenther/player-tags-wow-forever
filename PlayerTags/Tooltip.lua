-- Tooltip: tags, their age and your note when you point at a player.
local _, ns = ...

local DIM = { 0.65, 0.69, 0.72 }

local function resolve(tooltip, data)
	-- The unit the tooltip reports. Some tooltips hand back a hidden unit
	-- that cannot be inspected, so fall back to the mouseover unit.
	local id
	local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
	if ok then id = ns.IdentifyUnit(unit) end
	if not id then id = ns.IdentifyUnit("mouseover") end

	-- The tooltip's own GUID is the surest match and survives renames.
	local guid = type(data) == "table" and data.guid or nil
	if ns.IsText(guid) then
		local rec, key = ns.GetRecordByGUID(guid)
		if rec then
			-- Pointing at someone counts as seeing them: it fills in the
			-- class of a player who was tagged from a chat name.
			if id and id.guid == guid then ns.Touch(id) end
			return ns.TagsFor(id or { guid = guid, key = key }, rec, key)
		end
		if not id then id = { guid = guid } end
	end
	if id and id.key then
		local rec, key = ns.Touch(id)
		return ns.TagsFor(id, rec, key)
	end
	if id then return ns.TagsFor(id) end
	return nil
end

local function addLines(tooltip, data)
	if not ns.settings.tooltip then return end
	local info = resolve(tooltip, data)
	if not info then return end
	local rec = info.rec

	tooltip:AddLine(" ")
	for _, tagId in ipairs(info.ids) do
		local tag = ns.GetTag(tagId)
		local entry = rec and rec.tags[tagId]
		local r, g, b = ns.TagColor(tagId)
		local age = type(entry) == "table" and ns.Ago(entry.t) or ""
		tooltip:AddDoubleLine(ns.TagEscape(tagId, 0) .. " " .. tag.name, age, r, g, b, DIM[1], DIM[2], DIM[3])
	end
	if rec and ns.IsText(rec.note) then
		if ns.settings.tooltipNote ~= "shift" or IsShiftKeyDown() then
			tooltip:AddLine("\"" .. rec.note .. "\"", 1, 1, 1, true)
		else
			tooltip:AddLine("Hold Shift for your note", DIM[1], DIM[2], DIM[3])
		end
	end
	local latest = rec and ns.LatestTag(rec)
	if latest and ns.IsText(latest.zone) then
		local where = "Tagged in " .. latest.zone
		if ns.IsText(latest.by) and latest.by ~= ns.me then where = where .. " on " .. latest.by end
		tooltip:AddLine(where, DIM[1], DIM[2], DIM[3])
	end
	-- What other people's shared lists say, marked as theirs.
	for _, from in ipairs(info.shared) do
		local names = #from.ids > 0 and (ns.TagsEscape(from.ids, 0) .. " " .. ns.TagNames(from.ids)) or ""
		tooltip:AddLine("From " .. from.list .. ": " .. names, DIM[1], DIM[2], DIM[3], true)
		if ns.IsText(from.note) then
			tooltip:AddLine("\"" .. from.note .. "\"", DIM[1], DIM[2], DIM[3], true)
		end
	end
end

ns.Module("tooltip", function()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
		and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit) then
		return "the tooltip hook was not found"
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		if tooltip ~= GameTooltip then return end
		local ok, err = pcall(addLines, tooltip, data)
		if not ok then ns.Fail("tooltip", err) end
	end)
end)
