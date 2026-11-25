-- Nameplates: tag icons above a tagged player's nameplate.
--
-- Limits set by the game, not by this addon:
--   * Friendly nameplates inside dungeons and raids are locked. Party and
--     raid frames carry the tags there (see Frames.lua).
--   * Friendly players have no nameplate by default, so in the open world
--     icons appear over enemy players only. The game's own "friendly player
--     nameplates, name only" setting gives friendly players a plate, but it
--     also redraws every friendly name in nameplate text. That is a big
--     visual change, so it is strictly opt-in: off unless ticked in Options,
--     never suggested, and undone when unticked.
local _, ns = ...

local rows = setmetatable({}, { __mode = "k" }) -- plate frame -> badge row
local active = {}                                -- nameplate unit tokens on screen

-- The visible name if there is one, else the health bar, else the plate.
local function anchorFor(plate)
	local unitFrame = plate.UnitFrame
	if unitFrame then
		if unitFrame.ptStyled and unitFrame.ptName and unitFrame.ptName:IsShown() then return unitFrame.ptName end
		local name = unitFrame.name
		if name and name.IsVisible and name:IsVisible() then return name end
		local health = unitFrame.HealthBarsContainer or unitFrame.healthBar
		if health and health.IsVisible and health:IsVisible() then return health end
	end
	return plate
end

local function hideRow(plate)
	local row = plate and rows[plate]
	if row then row:Hide() end
end

local function update(unit)
	if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return end
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end

	if not ns.settings.nameplates then
		hideRow(plate)
		return
	end

	local id = ns.IdentifyUnit(unit)
	local rec = id and ns.Touch(id)
	if not rec or not ns.HasTags(rec) then
		hideRow(plate)
		return
	end

	local row = rows[plate]
	if not row then
		if InCombatLockdown() and plate.IsProtected and plate:IsProtected() then return end
		row = ns.CreateBadgeRow(plate, ns.settings.plateSize, 2)
		rows[plate] = row
	end
	row:SetBadgeSize(ns.settings.plateSize)
	row:SetTags(ns.TagIds(rec), ns.settings.plateMax)
	row:ClearAllPoints()
	row:SetPoint("BOTTOM", anchorFor(plate), "TOP", 0, 3)
end

local function refreshAll()
	for unit in pairs(active) do
		ns.Safe("nameplates", update, unit)
	end
end

ns.RefreshNameplates = refreshAll

---------------------------------------------------------------------------
-- Friendly players: name-only nameplates (opt-in)
---------------------------------------------------------------------------
local CVARS = { "nameplateShowFriendlyPlayers", "nameplateShowOnlyNameForFriendlyPlayerUnits" }

local function getCVar(name)
	if not (C_CVar and C_CVar.GetCVar) then return nil end
	local ok, value = pcall(C_CVar.GetCVar, name)
	if ok and ns.IsText(value) then return value end
	return nil
end

local function setCVar(name, value)
	if not (C_CVar and C_CVar.SetCVar) then return false end
	return pcall(C_CVar.SetCVar, name, value)
end

local waitingForCombat = false

--- Applies the friendlyPlates setting. "on" turns the two game settings on
--- and remembers what they were. Anything else puts back whatever this addon
--- changed and otherwise leaves the game's settings alone.
function ns.ApplyFriendlyPlates()
	if InCombatLockdown() then
		waitingForCombat = true
		return
	end
	local saved = ns.db.cvars
	if ns.settings.friendlyPlates == "on" then
		local showing = getCVar(CVARS[1])
		if showing == nil then return end
		if showing ~= "1" then
			for _, name in ipairs(CVARS) do
				if saved[name] == nil then saved[name] = getCVar(name) or "0" end
				setCVar(name, "1")
			end
		end
	else
		for _, name in ipairs(CVARS) do
			if saved[name] ~= nil then
				setCVar(name, saved[name])
				saved[name] = nil
			end
		end
	end
end

--- True when the game is currently showing friendly player nameplates.
function ns.FriendlyPlatesShowing()
	return getCVar(CVARS[1]) == "1"
end

---------------------------------------------------------------------------
-- Friendly names that look like the game's own. With friendly nameplates
-- on, the game draws friendly players' names as nameplate text: white,
-- outlined and smaller (it only colours them in its Legacy nameplate
-- style). These are restyled to match the names it floats over players'
-- heads otherwise: the same font and size, the same blue, a soft shadow
-- instead of an outline, <Away> and <Busy>, and the guild underneath.
---------------------------------------------------------------------------
local GAME_BLUE = { 96 / 255, 96 / 255, 1 } -- measured from the game's own floating names
local NAME_SIZE = 15                        -- their height at 100%, in the interface's own units

local function cvarOn(name)
	local value = getCVar(name)
	return value == nil or value == "1"
end

local function isFriendlyPlayer(unit)
	local ok, player, friend, me = pcall(function()
		return UnitIsPlayer(unit), UnitIsFriend("player", unit), UnitIsUnit(unit, "player")
	end)
	if not ok or ns.IsSecret(player) or ns.IsSecret(friend) or ns.IsSecret(me) then return false end
	return player == true and friend == true and not me
end

local function nameColor(unit)
	local choice = ns.settings.friendlyNameColor
	if choice == "white" then return 1, 1, 1 end
	if choice == "class" then
		local _, class = UnitClass(unit)
		local c = ns.IsText(class) and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
		if c then return c.r, c.g, c.b end
	end
	return GAME_BLUE[1], GAME_BLUE[2], GAME_BLUE[3]
end

-- Our own two lines of text: the name, and the guild under it. The game's
-- name text is kept where it is but hidden; it is never changed. Ours is
-- centred on it and has no width limit, so long names are never cut short
-- the way the nameplate's own text is.
local function lines(unitFrame)
	if not unitFrame.ptName then
		unitFrame.ptName = unitFrame:CreateFontString(nil, "OVERLAY")
		unitFrame.ptGuild = unitFrame:CreateFontString(nil, "OVERLAY")
		for _, line in ipairs({ unitFrame.ptName, unitFrame.ptGuild }) do
			-- Nameplates fade players you have not targeted; the game's own
			-- floating names never fade, so these keep their full colour.
			if line.SetIgnoreParentAlpha then line:SetIgnoreParentAlpha(true) end
			line:SetJustifyH("CENTER")
			line:SetWordWrap(false)
			line:SetShadowColor(0, 0, 0, 1)
			line:SetShadowOffset(1, -1)
		end
	end
	return unitFrame.ptName, unitFrame.ptGuild
end

-- Back to the game's own name.
local function unstyle(unitFrame)
	if unitFrame.ptName then
		unitFrame.ptName:Hide()
		unitFrame.ptGuild:Hide()
	end
	if unitFrame.ptStyled and unitFrame.name then unitFrame.name:SetAlpha(1) end
	unitFrame.ptStyled = nil
end

local function style(unitFrame, unit)
	local name = unitFrame.name
	if not name then return end
	if ns.settings.friendlyPlates ~= "on" or not isFriendlyPlayer(unit) or not name:IsShown() then
		unstyle(unitFrame)
		return
	end
	local text = GetUnitName(unit, false)
	if not ns.IsText(text) then
		unstyle(unitFrame)
		return
	end

	-- The same height on screen as the game's names. Those shrink a little
	-- with distance, as nameplates do, so only the nameplate's distance
	-- scaling is kept; any other scaling of the plate is cancelled out.
	local effective = unitFrame:GetEffectiveScale() or 1
	if effective <= 0 then effective = 1 end
	local plate = unitFrame:GetParent()
	local distance = plate and plate.GetScale and plate:GetScale() or 1
	if type(distance) ~= "number" or distance <= 0 or distance > 2 then distance = 1 end
	local uiScale = UIParent:GetEffectiveScale() or 1
	local chosen = tonumber(ns.settings.friendlyNameSize) or 1
	if chosen < 0.5 or chosen > 2 then chosen = 1 end
	local size = NAME_SIZE * chosen * uiScale * distance / effective
	local face = _G.UNIT_NAME_FONT or "Fonts\\FRIZQT__.TTF"
	local r, g, b = nameColor(unit)

	-- <Away> or <Busy> in front, as the game does.
	local prefix = ""
	if UnitIsAFK(unit) == true then
		prefix = _G.CHAT_FLAG_AFK or "<Away>"
	elseif UnitIsDND(unit) == true then
		prefix = _G.CHAT_FLAG_DND or "<Busy>"
	end

	local nameLine, guildLine = lines(unitFrame)
	nameLine:SetFont(face, size, "")
	nameLine:SetTextColor(r, g, b)
	nameLine:ClearAllPoints()
	nameLine:SetPoint("BOTTOM", name, "BOTTOM", 0, 0)
	nameLine:SetText(prefix .. text)
	nameLine:Show()
	name:SetAlpha(0)
	unitFrame.ptStyled = true

	-- The guild underneath, when the game's own "Guild names" option is on.
	local guild
	if cvarOn("UnitNameGuild") then
		local found = GetGuildInfo(unit)
		if ns.IsText(found) then guild = found end
	end
	if guild then
		guildLine:SetFont(face, size, "")
		guildLine:SetTextColor(r, g, b)
		guildLine:ClearAllPoints()
		guildLine:SetPoint("TOP", nameLine, "BOTTOM", 0, -1)
		guildLine:SetText("<" .. guild .. ">")
		guildLine:Show()
	else
		guildLine:Hide()
	end
end

local function styleUnit(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) or not plate.UnitFrame then return end
	style(plate.UnitFrame, unit)
end

local function styleAll()
	for unit in pairs(active) do
		ns.Safe("friendly names", styleUnit, unit)
	end
end

---------------------------------------------------------------------------
ns.Module("nameplates", function()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return "this client has no nameplate functions"
	end

	ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
		if unit == nil or ns.IsSecret(unit) then return end
		active[unit] = true
		ns.Safe("friendly names", styleUnit, unit)
		update(unit)
	end, "nameplates")

	-- The game redraws a plate's name on its own updates; restyle after it.
	if type(_G.CompactUnitFrame_UpdateName) == "function" then
		hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
			local unit = type(frame) == "table" and frame.unit
			if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" or not unit:match("^nameplate%d+$") then return end
			local ok, err = pcall(style, frame, unit)
			if not ok then ns.Fail("friendly names", err) end
		end)
	end

	-- Going away or coming back changes <Away> and <Busy>.
	ns.On("PLAYER_FLAGS_CHANGED", function(unit)
		if unit ~= nil and not ns.IsSecret(unit) and active[unit] then ns.Safe("friendly names", styleUnit, unit) end
	end, "nameplates")

	ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
		if unit == nil or ns.IsSecret(unit) then return end
		active[unit] = nil
		hideRow(C_NamePlate.GetNamePlateForUnit(unit))
	end, "nameplates")

	-- Names can arrive a moment after the plate does.
	ns.On("UNIT_NAME_UPDATE", function(unit)
		if unit ~= nil and not ns.IsSecret(unit) and active[unit] then update(unit) end
	end, "nameplates")

	ns.On("PLAYER_REGEN_ENABLED", function()
		if waitingForCombat then
			waitingForCombat = false
			ns.ApplyFriendlyPlates()
		end
		refreshAll()
	end, "nameplates")

	-- Bring the game's settings in line with the saved choice. This is also
	-- what undoes the change for anyone who turned the option off.
	ns.ApplyFriendlyPlates()
	local applied = false
	ns.On("PLAYER_ENTERING_WORLD", function()
		if applied then return end
		applied = true
		ns.ApplyFriendlyPlates()
	end, "nameplates")

	ns.Listen("RECORD_CHANGED", refreshAll, "nameplates")
	ns.Listen("TAGS_CHANGED", refreshAll, "nameplates")
	ns.Listen("SETTINGS_CHANGED", function()
		styleAll()
		refreshAll()
	end, "nameplates")
end)
