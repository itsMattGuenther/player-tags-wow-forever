-- A fake slice of the WoW client, just enough to load the addon and run it
-- outside the game. Run from the project root:  lua5.1 tests/run.lua
--
-- It cannot prove the addon looks right in game. It does prove every file
-- loads, every code path below runs without a Lua error, and the data
-- logic (tags, renames, export/import, secrets) behaves.
local H = {}

H.world = {
	units = {},       -- unit token -> { name, surname, guid, class, level, race, faction, npc }
	cvars = {},
	chat = {},        -- lines printed to the chat frame
	banner = {},
	timers = {},
	now = 1763300000,
	inGroup = false,
	inRaid = false,
	combat = false,
	zone = "Riverglades",
	events = {},      -- event -> list of frames
	plates = {},      -- unit token -> plate frame
}
local world = H.world

-- A stand-in for a value the game hides from addons. Touching it the way
-- real code would (joining, comparing, indexing) raises an error, as in game.
H.SECRET = setmetatable({}, {
	__concat = function() error("attempt to use a secret value", 2) end,
	__index = function() error("attempt to index a secret value", 2) end,
	__tostring = function() return "<secret>" end,
})

---------------------------------------------------------------------------
-- Mock frames, textures and font strings
---------------------------------------------------------------------------
local Mock = {}
local methods = {}

local function new(kind, parent, name)
	local obj = setmetatable({ __kind = kind, __parent = parent, __shown = true, __scripts = {}, __text = "", __children = {} }, Mock)
	if name then _G[name] = obj end
	if type(parent) == "table" and rawget(parent, "__children") then table.insert(parent.__children, obj) end
	return obj
end
H.new = new

Mock.__index = function(_, key)
	local found = methods[key]
	if found then return found end
	-- Any other capitalised name is treated as a harmless widget method.
	if type(key) == "string" and key:match("^[A-Z]") then
		return function() end
	end
	return nil
end

function methods:CreateTexture() return new("Texture", self) end
function methods:CreateFontString() return new("FontString", self) end
function methods:SetScript(name, fn) self.__scripts[name] = fn end
function methods:GetScript(name) return self.__scripts[name] end
function methods:HookScript(name, fn) self.__scripts[name] = fn end
function methods:Show()
	local was = self.__shown
	self.__shown = true
	if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function methods:Hide()
	local was = self.__shown
	self.__shown = false
	if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function methods:IsShown() return self.__shown end
function methods:IsVisible() return self.__shown end
function methods:IsForbidden() return false end
function methods:IsProtected() return false end
function methods:HasFocus() return false end
function methods:SetText(text) self.__text = tostring(text or "") end
function methods:GetText() return self.__text end
function methods:SetWidth(w) self.__w = w end
function methods:SetHeight(h) self.__h = h end
function methods:SetSize(w, h) self.__w, self.__h = w, h end
function methods:GetWidth() return self.__w or 100 end
function methods:GetHeight() return self.__h or 20 end
function methods:GetStringWidth() return #self.__text * 6 end
function methods:GetFrameLevel() return 1 end
function methods:GetEffectiveScale() return 1 end
function methods:GetVerticalScroll() return 0 end
function methods:GetVerticalScrollRange() return 0 end
-- Anchors are recorded so the checks can see where a frame was put.
function methods:ClearAllPoints() self.__points = {} end
function methods:SetPoint(point, a, b, c, d)
	local rel, relPoint, x, y
	if type(a) == "number" then
		x, y = a, b
	else
		rel, relPoint, x, y = a, b, c, d
		if type(relPoint) == "number" then relPoint, x, y = nil, relPoint, x end
	end
	self.__points = self.__points or {}
	table.insert(self.__points, { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 })
end
function methods:GetPoint(index)
	local p = self.__points and self.__points[index or 1]
	if not p then return nil end
	return p.point, p.rel, p.relPoint, p.x, p.y
end
--- Where the middle of the frame is on a 2000 x 1200 screen. A frame the
--- checks have "dragged" reports the spot it was dropped at (see H.drag).
function methods:GetCenter()
	if self.__center then return self.__center[1], self.__center[2] end
	local p = self.__points and self.__points[1]
	if p and p.point == "CENTER" and p.relPoint == "CENTER" and (p.rel == nil or p.rel == _G.UIParent) then
		return 1000 + p.x, 600 + p.y
	end
	return 1000, 600
end
-- As in game: dragging marks a frame for the game's own position cache.
function methods:StartMoving() self.__userPlaced = true end
function methods:SetUserPlaced(placed) self.__userPlaced = placed end
function methods:SetJustifyH(j) self.__justify = j end
function methods:GetJustifyH() return self.__justify or "LEFT" end
function methods:GetParent() return self.__parent end
function methods:RegisterEvent(event)
	world.events[event] = world.events[event] or {}
	table.insert(world.events[event], self)
end
function methods:AddMessage(text) table.insert(self.__lines or world.chat, tostring(text)) end
function methods:AddLine(text) self.__lines = self.__lines or {} table.insert(self.__lines, tostring(text)) end
function methods:AddDoubleLine(left, right)
	self.__lines = self.__lines or {}
	table.insert(self.__lines, tostring(left) .. " | " .. tostring(right))
end
function methods:GetUnit() return self.__unitName, self.__unit end

--- Every object created under a frame, at any depth, that passes the test.
function H.find(root, test, out)
	out = out or {}
	for _, child in ipairs(rawget(root, "__children") or {}) do
		if test(child) then out[#out + 1] = child end
		H.find(child, test, out)
	end
	return out
end

--- The badge row the addon attached to a game frame, if any.
function H.badgeRow(host)
	return H.find(host, function(o) return rawget(o, "badges") ~= nil end)[1]
end

--- Drags a frame so its middle ends up at x, y on the 2000 x 1200 screen.
function H.drag(frame, x, y)
	H.run(frame, "OnDragStart")
	frame.__center = { x, y }
	H.run(frame, "OnDragStop")
	frame.__center = nil
end

--- The frame's first anchor, as a table: point, rel, relPoint, x, y.
function H.anchor(frame)
	return frame.__points and frame.__points[1] or {}
end

--- Runs a stored script as the game would (click, enter, wheel...).
function H.run(obj, script, ...)
	local fn = obj.__scripts[script]
	assert(fn, "no " .. script .. " script on this " .. tostring(obj.__kind))
	return fn(obj, ...)
end

--- Sends a game event to every frame registered for it.
function H.fire(event, ...)
	for _, frame in ipairs(world.events[event] or {}) do
		local handler = frame.__scripts.OnEvent
		if handler then handler(frame, event, ...) end
	end
end

--- Runs every pending timer (and any timers those start).
function H.flush()
	local guard = 0
	while #world.timers > 0 do
		guard = guard + 1
		assert(guard < 500, "timers never settle")
		local batch = world.timers
		world.timers = {}
		for _, fn in ipairs(batch) do fn() end
	end
end

--- A nameplate frame shaped like Forever's: plate.UnitFrame.name etc.
function H.plate(unit)
	local plate = new("NamePlate")
	plate.UnitFrame = new("Frame", plate)
	plate.UnitFrame.name = new("FontString", plate.UnitFrame)
	plate.UnitFrame.HealthBarsContainer = new("Frame", plate.UnitFrame)
	world.plates[unit] = plate
	return plate
end

---------------------------------------------------------------------------
-- Globals the addon touches
---------------------------------------------------------------------------
function H.install()
	local G = _G

	G.issecretvalue = function(v) return rawequal(v, H.SECRET) end
	G.CreateFrame = function(kind, name, parent) return new(kind, parent, name) end
	G.UIParent = new("Frame")
	G.UIParent.__center = { 1000, 600 }
	G.Minimap = new("Minimap", G.UIParent)
	G.Minimap:SetSize(198, 198)
	G.Minimap.__center = { 1850, 1050 }
	G.GameTooltip = new("GameTooltip")
	G.DEFAULT_CHAT_FRAME = new("ChatFrame")
	G.UIErrorsFrame = new("MessageFrame")
	G.UIErrorsFrame.__lines = world.banner
	G.UISpecialFrames = {}
	G.GameFontHighlightSmall = new("Font")
	G.SlashCmdList = {}
	G.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, RAID_WARNING = 8959 }
	G.RAID_CLASS_COLORS = {
		WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
		ROGUE = { r = 1, g = 0.96, b = 0.41 }, PRIEST = { r = 1, g = 1, b = 1 },
	}
	G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage", ROGUE = "Rogue", PRIEST = "Priest" }
	G.UNKNOWNOBJECT = "Unknown"
	G.UNKNOWN = "Unknown"
	G.Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " ", CHARACTERNAME_REALMNAME_SEPARATOR = "-" } }
	G.Enum = { TooltipDataType = { Unit = 2 } }

	G.time = function() return world.now end
	G.GetTime = function() return world.now end
	G.PlaySound = function(id) world.lastSound = id end
	G.GetBuildInfo = function() return "1.60.1", "70938", "Nov 13 2026", 16001 end
	G.GetCursorPosition = function() return 400, 300 end
	G.GetRealZoneText = function() return world.zone end
	G.GetZoneText = function() return world.zone end
	G.InCombatLockdown = function() return world.combat end
	G.IsInGroup = function() return world.inGroup end
	G.IsInRaid = function() return world.inRaid end
	G.GetNumGroupMembers = function() return world.groupSize or 0 end

	local function unit(token) return type(token) == "string" and world.units[token] or nil end
	G.UnitExists = function(token) return unit(token) ~= nil end
	G.UnitIsPlayer = function(token) local u = unit(token) return u ~= nil and not u.npc end
	G.UnitName = function(token)
		local u = unit(token)
		if not u then return nil end
		return u.name, u.surname
	end
	G.UnitGUID = function(token) local u = unit(token) return u and u.guid end
	G.UnitClass = function(token) local u = unit(token) if u then return u.class, u.class end end
	G.UnitLevel = function(token) local u = unit(token) return u and u.level or 0 end
	G.UnitRace = function(token) local u = unit(token) return u and u.race end
	G.UnitFactionGroup = function(token) local u = unit(token) return u and u.faction end

	G.C_Timer = { After = function(_, fn) table.insert(world.timers, fn) end }
	G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
	G.C_CVar = {
		GetCVar = function(name) return world.cvars[name] end,
		SetCVar = function(name, value) world.cvars[name] = tostring(value) end,
	}
	G.C_NamePlate = { GetNamePlateForUnit = function(token) return world.plates[token] end }
	G.C_ChatInfo = { GetChatLineSenderGUID = function(lineID) return world.chatGuids and world.chatGuids[lineID] end }
	G.C_LFGList = {
		GetSearchResultInfo = function(id) return world.listings and world.listings[id] end,
		GetSearchResultPlayerInfo = function(id, index)
			local listing = world.listings and world.listings[id]
			local name = listing and listing.members and listing.members[index]
			return name and { name = name } or nil
		end,
	}

	G.hooksecurefunc = function(name, hook)
		local original = G[name]
		assert(type(original) == "function", "hooksecurefunc: no global function " .. tostring(name))
		G[name] = function(...)
			original(...)
			hook(...)
		end
	end

	H.tooltipCalls, H.senderFilters, H.menuHooks = {}, {}, {}
	G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) H.tooltipCalls[#H.tooltipCalls + 1] = fn end }
	G.ChatFrameUtil = { AddSenderNameFilter = function(fn) H.senderFilters[#H.senderFilters + 1] = fn end }
	G.Menu = { ModifyMenu = function(tag, fn) H.menuHooks[tag] = fn end }

	-- Blizzard functions the addon hooks
	G.CompactUnitFrame_UpdateName = function() end
	G.LFGBrowseSearchEntry_Update = function() end
end

--- Loads the addon's files in .toc order, the way the game does.
function H.load(root)
	local ns = {}
	local toc = assert(io.open(root .. "/PlayerTags.toc"))
	local files = {}
	for line in toc:lines() do
		line = line:gsub("\r", "")
		if line:match("%.lua$") then files[#files + 1] = line end
	end
	toc:close()
	for _, file in ipairs(files) do
		local chunk, problem = loadfile(root .. "/" .. file)
		assert(chunk, problem)
		chunk("PlayerTags", ns)
	end
	return ns, files
end

return H
