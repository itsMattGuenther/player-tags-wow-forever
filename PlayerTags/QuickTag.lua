-- QuickTag: the tagging popup, for your target or the player under your
-- mouse. Clicking a tag applies it straight away. It is the game's standard
-- frame: the player's portrait, their name as the title, and one icon
-- button per tag that glows while the tag is on.
local _, ns = ...
local UI = ns.UI

-- Full: icons with names under them. Compact: icons only, names on hover.
local MODES = {
	full = { cols = 5, w = 64, h = 56, icon = 26, gap = 4 },
	compact = { cols = 8, w = 30, h = 30, icon = 26, gap = 4 },
}
local PAD = 8             -- inside the inset
local INSET_LEFT, INSET_RIGHT = 4, 6
local INSET_TOP = 60

local frame
local current           -- identity being tagged
local buttons = {}      -- pool of tag buttons
local labels = {}       -- pool of family labels
local removeArmed = false

local function mode()
	return (ns.settings and ns.settings.compactPopup) and MODES.compact or MODES.full
end

local function saveNote()
	if current and frame then ns.SetNote(current, frame.note:GetText()) end
end

local function describe(id, rec)
	local level = id.level or (rec and rec.level)
	local race = id.race or (rec and rec.race)
	local class = UI.ClassName(id.class or (rec and rec.class))
	local parts = {}
	if level then parts[#parts + 1] = "Level " .. level end
	if race then parts[#parts + 1] = race end
	if class then parts[#parts + 1] = class end
	if #parts > 0 then return table.concat(parts, " ") end
	-- Tagged from a chat name, so the game never told us level, race or
	-- class. Say when and where, the same way the list's Last seen column does.
	if rec and rec.seen then
		local seen = "Last seen " .. ns.Ago(rec.seen)
		if ns.IsText(rec.seenZone) then seen = seen .. ", " .. rec.seenZone end
		return seen
	end
	return "Not tagged yet"
end

local function refresh()
	if not frame or not current then return end
	local rec = ns.Lookup(current)
	frame.sub:SetText(describe(current, rec))
	for _, b in ipairs(buttons) do
		if b:IsShown() then b:SetOn(rec ~= nil and rec.tags[b.tagId] ~= nil) end
	end
	if rec then frame.remove:Show() else frame.remove:Hide() end
	removeArmed = false
	frame.remove:SetLabel("Remove all")
end

local function makeButton()
	local b = UI.IconToggle(frame, MODES.full.icon, true)
	b:SetScript("OnClick", function(self)
		if not current then return end
		ns.ToggleTag(current, self.tagId)
		UI.Click()
		refresh()
	end)
	b:HookScript("OnEnter", function(self)
		local tag = ns.GetTag(self.tagId)
		if not tag then return end
		local r, g, bl = ns.TagColor(self.tagId)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(tag.name, r, g, bl)
		if tag.desc then GameTooltip:AddLine(tag.desc, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Lays the tag buttons out by family. Runs on every open because the tag
-- list and the popup's size setting can change.
local function layout()
	local m = mode()
	local tags = ns.AllTags(false)
	local inset = frame.Inset
	local y = PAD
	local used, usedLabels = 0, 0

	for _, family in ipairs(ns.FAMILIES) do
		local group = {}
		for _, tag in ipairs(tags) do
			if tag.family == family.id then group[#group + 1] = tag end
		end
		if #group > 0 then
			usedLabels = usedLabels + 1
			local label = labels[usedLabels]
			if not label then
				label = UI.Text(frame, "GameFontNormalSmall")
				labels[usedLabels] = label
			end
			label:ClearAllPoints()
			label:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD, -y)
			label:SetText(family.name)
			label:SetTextColor(family.r, family.g, family.b)
			label:Show()
			y = y + 16

			for i, tag in ipairs(group) do
				used = used + 1
				local b = buttons[used]
				if not b then
					b = makeButton()
					buttons[used] = b
				end
				local col = (i - 1) % m.cols
				local row = math.floor((i - 1) / m.cols)
				b:SetSize(m.w, m.h)
				b.text:SetWidth(m.w)
				if m == MODES.compact then b.text:Hide() else b.text:Show() end
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD + col * (m.w + m.gap), -(y + row * (m.h + m.gap)))
				b.tagId = tag.id
				b.badge:SetTag(tag.id)
				b.text:SetText(tag.name)
				b:Show()
			end
			y = y + math.ceil(#group / m.cols) * (m.h + m.gap) + 6
		end
	end

	for i = used + 1, #buttons do buttons[i]:Hide() end
	for i = usedLabels + 1, #labels do labels[i]:Hide() end

	local inner = PAD * 2 + m.cols * m.w + (m.cols - 1) * m.gap
	frame:SetWidth(INSET_LEFT + inner + INSET_RIGHT)

	frame.noteLabel:ClearAllPoints()
	frame.noteLabel:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD, -y)
	y = y + 16
	frame.note:SetWidth(inner - PAD * 2 - 6)
	frame.note:ClearAllPoints()
	frame.note:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD + 6, -y)
	y = y + 20 + PAD + 4
	frame:SetHeight(INSET_TOP + y + UI.BAR)
end

-- The portrait shows who is being tagged: their face when they are a unit
-- the game can draw, else their class, else the addon's own icon.
local ICON = "Interface\\AddOns\\PlayerTags\\Media\\icon"

local function portrait(id, rec)
	-- The class icon crops the texture; every other picture needs it whole.
	frame:SetPortraitTexCoord(0, 1, 0, 1)
	local unit = id.unit
	-- A unit token can point at someone else by now (a new target), so
	-- only use it while it is still the same player.
	if unit and UnitExists(unit) and (not id.guid or UnitGUID(unit) == id.guid) then
		frame:SetPortraitToUnit(unit)
		return
	end
	local class = id.class or (rec and rec.class)
	local coords = class and _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[class]
	if coords and frame.SetPortraitToClassIcon then
		frame:SetPortraitToClassIcon(class)
		return
	end
	frame:SetPortraitToAsset(ICON)
end

local function setPortrait(id, rec)
	local ok = pcall(portrait, id, rec)
	if not ok then
		pcall(frame.SetPortraitTexCoord, frame, 0, 1, 0, 1)
		pcall(frame.SetPortraitToAsset, frame, ICON)
	end
end

local function build()
	frame = UI.Window("PlayerTagsPopup", "Tag player", 360, 400)
	frame:SetFrameStrata("DIALOG")
	frame:Hide()
	UI.Movable(frame, "popup")
	UI.Place(frame, "popup")
	table.insert(UISpecialFrames, "PlayerTagsPopup")

	-- The title is the player's name, coloured by class.
	frame.who = frame:GetTitleText()

	frame.sub = UI.Text(frame, "GameFontHighlightSmall")
	frame.sub:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -34)
	frame.sub:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
	frame.sub:SetJustifyH("LEFT")
	frame.sub:SetWordWrap(false)

	frame.noteLabel = UI.Text(frame, "GameFontNormalSmall", "Note")
	frame.note = UI.Edit(frame, 300, 20, "Add a note (optional), then press Enter")
	frame.note.onEnter = saveNote
	frame.note.onBlur = saveNote

	frame.hint = UI.Text(frame, "GameFontDisableSmall", "Click a tag to turn it on or off.")
	frame.hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, UI.BAR_TEXT_Y)

	frame.remove = UI.Button(frame, "Remove all", 104, 22)
	frame.remove:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, UI.BAR_Y)
	frame.remove.tip = "Removes every tag and the note from this player."
	frame.remove:SetScript("OnClick", function(self)
		if not current then return end
		if not removeArmed then
			removeArmed = true
			self:SetLabel("Sure?")
			return
		end
		local _, key = ns.Lookup(current)
		frame.note:SetText("")
		if key then ns.DeleteRecord(key) end
	end)

	frame:SetScript("OnHide", function()
		saveNote()
		current = nil
	end)
end

--- Opens the popup for an identity. With an anchor (the list window) it
--- opens beside it. Otherwise it opens in the middle of the screen, or where
--- it was last dragged to, or at the mouse if that option is on.
function ns.OpenQuickTag(id, anchor)
	if not id or not id.key then return end
	if ns.IsMe(id) then
		ns.Print("That is you. Tags are for other players.")
		return
	end
	if not frame then build() end
	if frame:IsShown() then saveNote() end

	current = id
	UI.ApplyScale(frame)
	layout()

	local rec = ns.Lookup(id)
	local name = (id.live and id.name) or (rec and rec.name) or id.name
	frame:SetTitle(ns.ClassColorCode(id.class or (rec and rec.class)) .. name .. "|r")
	setPortrait(id, rec)
	frame.note:SetText(rec and rec.note or "")
	frame.note:ClearFocus()
	refresh()

	if anchor then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
	elseif ns.settings.popupAtCursor then
		local scale = frame:GetEffectiveScale()
		local x, y = GetCursorPosition()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale + 16)
	else
		UI.Place(frame, "popup")
	end
	frame:Show()
	frame:Raise()
end

function ns.CloseQuickTag()
	if frame and frame:IsShown() then frame:Hide() end
end

--- The player the key or /tag acts on: your target, else your mouseover.
function ns.QuickTagTarget()
	local id = ns.IdentifyUnit("target")
	if id and not ns.IsMe(id) then return id end
	id = ns.IdentifyUnit("mouseover")
	if id and not ns.IsMe(id) then return id end
	return nil
end

--- Key binding and "/tag": opens the popup, or closes it when it is open.
function ns.QuickTag()
	if frame and frame:IsShown() then
		frame:Hide()
		return
	end
	local id = ns.QuickTagTarget()
	if not id then
		ns.Print("Target a player, or point at one, then try again.")
		return
	end
	ns.OpenQuickTag(id)
end

_G.PlayerTags_QuickTag = function()
	ns.Safe("tagging popup", ns.QuickTag)
end

ns.Listen("RECORD_CHANGED", function()
	if frame and frame:IsShown() then refresh() end
end, "tagging popup")

ns.Listen("TAGS_CHANGED", function()
	if frame and frame:IsShown() and current then
		layout()
		refresh()
	end
end, "tagging popup")

ns.Listen("SETTINGS_CHANGED", function()
	if frame and frame:IsShown() and current then
		UI.ApplyScale(frame)
		layout()
		refresh()
	end
end, "tagging popup")
