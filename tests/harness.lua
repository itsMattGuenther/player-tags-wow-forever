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
function methods:HookScript(name, fn)
	local before = self.__scripts[name]
	if not before then
		self.__scripts[name] = fn
	else
		self.__scripts[name] = function(...) before(...) fn(...) end
	end
end
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
function methods:SetText(text)
	self.__text = tostring(text or "")
	-- As in game, an edit box tells its own handler when code changes its text.
	if self.__kind == "EditBox" and self.__scripts.OnTextChanged then self.__scripts.OnTextChanged(self, false) end
end
function methods:SetChecked(on) self.__checked = on and true or false end
function methods:SetFont(font, size, flags) self.__font = { font, size, flags } return true end
function methods:GetFont() local f = self.__font or { "Fonts\\FRIZQT__.TTF", 9, "OUTLINE" } return f[1], f[2], f[3] end
function methods:SetVertexColor(r, g, b) self.__color = { r, g, b } end
function methods:SetTextColor(r, g, b) self.__color = { r, g, b } end
function methods:SetShadowOffset(x, y) self.__shadow = { x, y } end
function methods:GetShadowOffset() local s = self.__shadow or { 0, 0 } return s[1], s[2] end
function methods:GetChecked() return self.__checked == true end
function methods:LockHighlight() self.__locked = true end
function methods:UnlockHighlight() self.__locked = false end
function methods:SetID(id) self.__id = id end
function methods:GetID() return self.__id or 0 end
function methods:SetEnabled(on) self.__disabled = not on end
function methods:Enable() self.__disabled = false end
function methods:Disable() self.__disabled = true end
function methods:IsEnabled() return not self.__disabled end
function methods:SetScale(scale) self.__scale = scale end
function methods:GetScale() return self.__scale or 1 end
function methods:IsMouseOver() return self.__mouseOver == true end
function methods:SetAlpha(a) self.__alpha = a end
function methods:SetIgnoreParentAlpha(on) self.__ignoreParentAlpha = on end
function methods:GetAlpha() return self.__alpha or 1 end
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
function methods:GetChildren() return unpack(self.__children) end
function methods:GetObjectType() return self.__kind end
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
-- Blizzard templates. CreateFrame in game builds these children from the
-- game's XML; here each template adds the pieces the addon uses, under the
-- same keys as Forever's own SharedXML (read from the forever branch of the
-- game's interface source).
---------------------------------------------------------------------------
local templates = {}

local function closeButton(parent)
	local b = new("Button", parent)
	b:SetScript("OnClick", function(self) _G.HideUIPanel(self:GetParent()) end)
	return b
end

local function titled(f)
	f.TitleContainer = new("Frame", f)
	f.TitleContainer.TitleText = new("FontString", f.TitleContainer)
	f.SetTitle = function(self, text) self.TitleContainer.TitleText:SetText(text) end
	f.GetTitleText = function(self) return self.TitleContainer.TitleText end
end

templates.PortraitFrameTemplate = function(f)
	titled(f)
	f.PortraitContainer = new("Frame", f)
	f.PortraitContainer.portrait = new("Texture", f.PortraitContainer)
	f.SetPortraitToAsset = function(self, asset) self.__portrait = asset end
	f.SetPortraitToUnit = function(self, unit) self.__portrait = "unit:" .. tostring(unit) end
	f.SetPortraitToClassIcon = function(self, class) self.__portrait = "class:" .. tostring(class) end
	f.CloseButton = closeButton(f)
end
templates.ButtonFrameTemplate = function(f)
	templates.PortraitFrameTemplate(f)
	f.Inset = new("Frame", f)
end
templates.DefaultPanelFlatTemplate = function(f) titled(f) end
templates.UIPanelCloseButton = function(b)
	b:SetScript("OnClick", function(self) _G.HideUIPanel(self:GetParent()) end)
end
templates.UIPanelCloseButtonDefaultAnchors = templates.UIPanelCloseButton
templates.UIPanelButtonTemplate = function(b) b.Text = new("FontString", b) end
templates.UICheckButtonTemplate = function(c) c.Text = new("FontString", c) end
templates.UIRadioButtonTemplate = function(c) c.text = new("FontString", c) end
templates.InputBoxTemplate = function(e)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
end
templates.InputBoxInstructionsTemplate = function(e)
	templates.InputBoxTemplate(e)
	e.Instructions = new("FontString", e)
	e:SetScript("OnTextChanged", function(self)
		if self:GetText() == "" then self.Instructions:Show() else self.Instructions:Hide() end
	end)
end
templates.SearchBoxTemplate = function(e)
	templates.InputBoxInstructionsTemplate(e)
	e.searchIcon = new("Texture", e)
	e.clearButton = new("Button", e)
	e.clearButton:SetScript("OnClick", function(self)
		local box = self:GetParent()
		box:SetText("")
		box:ClearFocus()
	end)
end
templates.PanelTabButtonTemplate = function(t, parent)
	t.Text = new("FontString", t)
	if parent then
		parent.Tabs = rawget(parent, "Tabs") or {}
		table.insert(parent.Tabs, t)
	end
end

local function applyTemplates(obj, parent, list)
	if type(list) ~= "string" then return end
	for name in list:gmatch("[^,%s]+") do
		local build = templates[name]
		if build then build(obj, parent) end
	end
end

---------------------------------------------------------------------------
-- Globals the addon touches
---------------------------------------------------------------------------
function H.install()
	local G = _G

	G.issecretvalue = function(v) return rawequal(v, H.SECRET) end
	G.CreateFrame = function(kind, name, parent, template)
		local obj = new(kind, parent, name)
		applyTemplates(obj, parent, template)
		return obj
	end
	G.HideUIPanel = function(frame) frame:Hide() end
	G.PanelTemplates_SetNumTabs = function(frame, n) frame.numTabs = n end
	G.PanelTemplates_SetTab = function(frame, id)
		frame.selectedTab = id
		for i, tab in ipairs(rawget(frame, "Tabs") or {}) do tab.__selected = (i == id) end
	end
	G.PanelTemplates_TabResize = function() end
	G.ButtonFrameTemplate_HidePortrait = function(frame) frame.__noPortrait = true end
	G.ButtonFrameTemplate_HideButtonBar = function(frame) frame.__noButtonBar = true end

	-- The game's Settings panel. Registered pages, settings and rows are kept
	-- in H.settings so the checks can find them and change values.
	H.settings = { categories = {}, byVariable = {}, rows = {}, opened = nil }
	local function addRow(row) table.insert(H.settings.rows, row) return row end
	G.Settings = {
		VarType = { Boolean = "boolean", Number = "number", String = "string" },
		Default = { True = true, False = false },
		RegisterVerticalLayoutCategory = function(name)
			local category = { name = name, id = #H.settings.categories + 1 }
			function category:GetID() return self.id end
			local layout = { AddInitializer = function(_, init) addRow(init) end }
			table.insert(H.settings.categories, category)
			return category, layout
		end,
		RegisterAddOnCategory = function(category) category.registered = true end,
		RegisterProxySetting = function(_, variable, kind, name, default, get, set)
			local setting = { variable = variable, kind = kind, name = name, default = default }
			function setting:GetValue() return get() end
			function setting:SetValue(value) set(value) end
			H.settings.byVariable[variable] = setting
			return setting
		end,
		CreateCheckbox = function(_, setting, tooltip) return addRow({ control = "checkbox", setting = setting, tooltip = tooltip }) end,
		CreateSlider = function(_, setting, options, tooltip) return addRow({ control = "slider", setting = setting, options = options, tooltip = tooltip }) end,
		CreateDropdown = function(_, setting, options, tooltip) return addRow({ control = "dropdown", setting = setting, options = options, tooltip = tooltip }) end,
		CreateSliderOptions = function(min, max, step)
			local options = { min = min, max = max, step = step }
			function options:SetLabelFormatter(_, fn) self.format = fn end
			return options
		end,
		CreateControlTextContainer = function()
			local data = {}
			return {
				Add = function(_, value, label, tooltip) table.insert(data, { value = value, label = label, tooltip = tooltip }) end,
				GetData = function() return data end,
			}
		end,
		OpenToCategory = function(id) H.settings.opened = id end,
	}
	G.MinimalSliderWithSteppersMixin = { Label = { Right = 3 } }
	G.CreateSettingsListSectionHeaderInitializer = function(name, tooltip) return { header = name, tooltip = tooltip } end
	G.CreateSettingsButtonInitializer = function(name, text, click, tooltip, search)
		assert(search ~= nil, "the game asserts that addSearchTags is given")
		return { control = "button", name = name, text = text, click = click, tooltip = tooltip }
	end
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
	G.UnitIsFriend = function(_, token) local u = unit(token) return u ~= nil and not u.hostile end
	G.UnitIsUnit = function(a, b) return unit(a) ~= nil and unit(a) == unit(b) end
	G.GetUnitName = function(token)
		local u = unit(token)
		if not u then return nil end
		if u.surname then return u.name .. " " .. u.surname end
		return u.name
	end
	G.UnitIsAFK = function(token) local u = unit(token) return u ~= nil and u.afk == true end
	G.UnitIsDND = function(token) local u = unit(token) return u ~= nil and u.dnd == true end
	G.GetGuildInfo = function(token) local u = unit(token) return u and u.guild end
	G.UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
	G.CHAT_FLAG_AFK = "<Away>"
	G.CHAT_FLAG_DND = "<Busy>"

	G.C_Timer = { After = function(_, fn) table.insert(world.timers, fn) end }
	G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
	G.C_CVar = {
		GetCVar = function(name) return world.cvars[name] end,
		SetCVar = function(name, value) world.cvars[name] = tostring(value) end,
	}
	G.C_NamePlate = { GetNamePlateForUnit = function(token) return world.plates[token] end }
	G.C_ChatInfo = { GetChatLineSenderGUID = function(lineID) return world.chatGuids and world.chatGuids[lineID] end }
	-- The game's memory of players it has shown you. Empty unless a check
	-- fills world.playerCache, and then it answers with the real 8 values.
	G.GetPlayerInfoByGUID = function(guid)
		local p = world.playerCache and world.playerCache[guid]
		if not p then return end
		local localized = G.LOCALIZED_CLASS_NAMES_MALE[p.class] or p.class
		return localized, p.class, p.race, p.race, 2, p.name or "", "", p.level
	end
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
