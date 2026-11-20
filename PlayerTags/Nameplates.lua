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
ns.Module("nameplates", function()
	if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
		return "this client has no nameplate functions"
	end

	ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
		if unit == nil or ns.IsSecret(unit) then return end
		active[unit] = true
		update(unit)
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
	ns.Listen("SETTINGS_CHANGED", refreshAll, "nameplates")
end)
