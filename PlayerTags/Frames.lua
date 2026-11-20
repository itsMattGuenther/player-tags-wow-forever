-- Frames: tag icons on the target, focus, party and raid frames. This is
-- where tags show inside dungeons and raids, where nameplates are locked.
local _, ns = ...

local rows = setmetatable({}, { __mode = "k" })    -- host frame -> badge row
local compact = setmetatable({}, { __mode = "k" }) -- raid-style frames seen so far

local function isGroupUnit(unit)
	return unit:match("^party%d$") ~= nil or unit:match("^raid%d+$") ~= nil
end

local function taggedRecord(unit)
	if not ns.settings.frames then return nil end
	if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
	local id = ns.IdentifyUnit(unit)
	if not id or ns.IsMe(id) then return nil end
	local rec = ns.Lookup(id)
	if rec and ns.HasTags(rec) then return rec end
	return nil
end

local function rowFor(host, size)
	local row = rows[host]
	if not row then
		-- Do not build new pieces on the game's protected frames mid-fight.
		if InCombatLockdown() then return nil end
		row = ns.CreateBadgeRow(host, size, 2)
		if host.GetFrameLevel and row.SetFrameLevel then
			row:SetFrameLevel((host:GetFrameLevel() or 1) + 6)
		end
		rows[host] = row
	end
	return row
end

local function hide(host)
	local row = rows[host]
	if row then row:Hide() end
end

local function plainWidth(fontString)
	local ok, width = pcall(fontString.GetStringWidth, fontString)
	width = ok and ns.Num(width) or nil
	local ok2, box = pcall(fontString.GetWidth, fontString)
	box = ok2 and ns.Num(box) or nil
	if width and box and box > 0 and width > box then width = box end
	return width or 0
end

-- Centred names (the target frame) get icons above them. Left-aligned
-- names (party frames) get icons straight after the text.
local function place(row, host, name)
	row:ClearAllPoints()
	if not name then
		row:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 4, 2)
		return
	end
	local justify = name.GetJustifyH and name:GetJustifyH() or "LEFT"
	if justify == "CENTER" then
		row:SetPoint("BOTTOM", name, "TOP", 0, 3)
	else
		row:SetPoint("LEFT", name, "LEFT", plainWidth(name) + 4, 0)
	end
end

local function apply(host, unit, size, name, max)
	local rec = taggedRecord(unit)
	if not rec then
		hide(host)
		return
	end
	local row = rowFor(host, size)
	if not row then return end
	row:SetTags(ns.TagIds(rec), max or 3)
	place(row, host, name)
end

local function targetName(frame)
	local content = frame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	return main and main.Name or nil
end

local function refresh()
	local target = _G.TargetFrame
	if target then apply(target, "target", 15, targetName(target), 4) end
	local focus = _G.FocusFrame
	if focus then apply(focus, "focus", 15, targetName(focus), 4) end

	local party = _G.PartyFrame
	local pool = party and party.PartyMemberFramePool
	if pool and pool.EnumerateActive then
		for member in pool:EnumerateActive() do
			local unit = member.unitToken
			if unit == nil and member.GetUnit then unit = member:GetUnit() end
			apply(member, unit, 14, member.Name, 3)
		end
	end

	for frame in pairs(compact) do
		local unit = frame.unit
		local rec
		if unit ~= nil and not ns.IsSecret(unit) and type(unit) == "string"
			and frame.IsVisible and frame:IsVisible() and isGroupUnit(unit) then
			rec = taggedRecord(unit)
		end
		if rec then
			local row = rowFor(frame, 12)
			if row then
				row:SetTags(ns.TagIds(rec), 2)
				row:ClearAllPoints()
				row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
			end
		else
			hide(frame)
		end
	end
end

local function queue()
	ns.Debounce("frames", 0.1, refresh)
end

ns.RefreshFrames = queue

ns.Module("frames", function()
	-- Raid-style frames are created as the group changes, so learn about
	-- each one the first time the game writes a name on it. This runs for
	-- every nameplate too, so it stays very cheap.
	if type(_G.CompactUnitFrame_UpdateName) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
			local unit = frame and frame.unit
			if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return end
			local first = unit:byte(1)
			if first ~= 112 and first ~= 114 then return end -- not "party..." or "raid..."
			if not isGroupUnit(unit) then return end
			compact[frame] = true
			queue()
		end)
	end

	ns.On("PLAYER_TARGET_CHANGED", queue, "frames")
	ns.On("PLAYER_FOCUS_CHANGED", queue, "frames")
	ns.On("GROUP_ROSTER_UPDATE", queue, "frames")
	ns.On("PLAYER_ENTERING_WORLD", queue, "frames")
	ns.On("PLAYER_REGEN_ENABLED", queue, "frames")
	ns.On("UNIT_NAME_UPDATE", function(unit)
		if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return end
		if unit == "target" or unit == "focus" or isGroupUnit(unit) then queue() end
	end, "frames")

	ns.Listen("RECORD_CHANGED", queue, "frames")
	ns.Listen("TAGS_CHANGED", queue, "frames")
	ns.Listen("SETTINGS_CHANGED", queue, "frames")
end)
