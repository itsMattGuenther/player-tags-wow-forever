-- QuickTag: the tagging popup, for your target or the player under your
-- mouse. Clicking a tag applies it straight away.
local _, ns = ...
local UI = ns.UI

local COLS, BTN_W, BTN_H, GAP, PAD = 5, 64, 52, 4, 12
local WIDTH = PAD * 2 + COLS * BTN_W + (COLS - 1) * GAP

local frame
local current           -- identity being tagged
local buttons = {}      -- pool of tag buttons
local labels = {}       -- pool of family labels
local removeArmed = false

local function saveNote()
	if current and frame then ns.SetNote(current, frame.note:GetText()) end
end

local function paintButton(b, on)
	local r, g, b2 = ns.TagColor(b.tagId)
	if on then
		b.fill:SetColorTexture(0.078 + r * 0.16, 0.098 + g * 0.16, 0.133 + b2 * 0.16, 1)
		b:SetEdgeColor(r, g, b2, 1)
		b.text:SetTextColor(1, 1, 1)
		b.badge:SetDim(false)
	else
		b.fill:SetColorTexture(0.078, 0.098, 0.133, 1)
		b:SetEdgeColor(0.17, 0.20, 0.25, 1)
		b.text:SetTextColor(0.65, 0.69, 0.72)
		b.badge:SetDim(true)
	end
	b.isOn = on
end

local function refresh()
	if not frame or not current then return end
	local rec = ns.Lookup(current)
	for _, b in ipairs(buttons) do
		if b:IsShown() then paintButton(b, rec ~= nil and rec.tags[b.tagId] ~= nil) end
	end
	if rec then frame.remove:Show() else frame.remove:Hide() end
	removeArmed = false
	frame.remove:SetLabel("Remove all")
end

local function makeButton()
	local b = CreateFrame("Button", nil, frame)
	b:SetSize(BTN_W, BTN_H)
	UI.Fill(b, 0.078, 0.098, 0.133, 1)
	UI.Edges(b, 0.17, 0.20, 0.25, 1)

	b.badge = ns.CreateBadge(b, 22)
	b.badge:SetPoint("TOP", 0, -5)

	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.text:SetPoint("TOP", b.badge, "BOTTOM", 0, -2)
	b.text:SetWidth(BTN_W - 4)
	b.text:SetJustifyH("CENTER")
	b.text:SetJustifyV("TOP")
	b.text:SetWordWrap(true)
	if b.text.SetMaxLines then b.text:SetMaxLines(2) end

	b:SetScript("OnClick", function(self)
		if not current then return end
		ns.ToggleTag(current, self.tagId)
		UI.Click()
	end)
	b:SetScript("OnEnter", function(self)
		local tag = ns.GetTag(self.tagId)
		if not tag then return end
		local r, g, bl = ns.TagColor(self.tagId)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(tag.name, r, g, bl)
		GameTooltip:AddLine(tag.desc, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return b
end

-- Lays the tag buttons out by family. Runs on every open because the tag
-- list can change (custom, hidden or edited tags).
local function layout()
	local tags = ns.AllTags(false)
	local y = 62
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
			label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
			label:SetText(family.name:upper())
			label:SetTextColor(family.r, family.g, family.b)
			label:Show()
			y = y + 15

			for i, tag in ipairs(group) do
				used = used + 1
				local b = buttons[used]
				if not b then
					b = makeButton()
					buttons[used] = b
				end
				local col = (i - 1) % COLS
				local row = math.floor((i - 1) / COLS)
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * (BTN_W + GAP), -(y + row * (BTN_H + GAP)))
				b.tagId = tag.id
				b.badge:SetTag(tag.id)
				b.text:SetText(tag.name)
				b:Show()
			end
			y = y + math.ceil(#group / COLS) * (BTN_H + GAP) + 6
		end
	end

	for i = used + 1, #buttons do buttons[i]:Hide() end
	for i = usedLabels + 1, #labels do labels[i]:Hide() end

	frame.noteLabel:ClearAllPoints()
	frame.noteLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 14
	frame.note:ClearAllPoints()
	frame.note:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
	y = y + 24 + 10
	frame.hint:ClearAllPoints()
	frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y - 3)
	frame.remove:ClearAllPoints()
	frame.remove:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
	y = y + 20 + PAD
	frame:SetHeight(y)
end

local function build()
	frame = UI.Panel("PlayerTagsPopup")
	frame:SetFrameStrata("DIALOG")
	frame:SetWidth(WIDTH)
	frame:Hide()
	UI.Movable(frame, "popup")
	UI.Place(frame, "popup")
	table.insert(UISpecialFrames, "PlayerTagsPopup")

	frame.title = UI.Text(frame, "GameFontNormal", "Tag player")
	frame.title:SetPoint("TOPLEFT", PAD, -PAD)

	frame.close = UI.Button(frame, "x", 20, 20)
	frame.close:SetPoint("TOPRIGHT", -8, -8)
	frame.close:SetScript("OnClick", function() frame:Hide() end)

	frame.who = UI.Text(frame, "GameFontHighlight")
	frame.who:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
	frame.sub = UI.Text(frame, "GameFontDisableSmall")
	frame.sub:SetPoint("TOPLEFT", frame.who, "BOTTOMLEFT", 0, -2)

	frame.noteLabel = UI.Text(frame, "GameFontDisableSmall", "NOTE")
	frame.note = UI.Edit(frame, WIDTH - PAD * 2, 24, "Add a note (optional), then press Enter")
	frame.note.onEnter = saveNote
	frame.note.onBlur = saveNote

	frame.hint = UI.Text(frame, "GameFontDisableSmall", "Click tags to toggle. Esc closes.")

	frame.remove = UI.Button(frame, "Remove all", 96, 20)
	frame.remove.tip = "Removes every tag and the note from this player."
	frame.remove:SetScript("OnClick", function(self)
		if not current then return end
		if not removeArmed then
			removeArmed = true
			self:SetLabel("Click to confirm")
			return
		end
		local _, key = ns.Lookup(current)
		frame.note:SetText("")
		frame.note:Refresh()
		if key then ns.DeleteRecord(key) end
	end)

	frame:SetScript("OnHide", function()
		saveNote()
		current = nil
	end)
end

local function describe(id, rec)
	local level = id.level or (rec and rec.level)
	local race = id.race or (rec and rec.race)
	local class = UI.ClassName(id.class or (rec and rec.class))
	local parts = {}
	if level then parts[#parts + 1] = "Level " .. level end
	if race then parts[#parts + 1] = race end
	if class then parts[#parts + 1] = class end
	if #parts == 0 then return "Not seen in person yet" end
	return table.concat(parts, " ")
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
	layout()

	local rec = ns.Lookup(id)
	local name = (id.live and id.name) or (rec and rec.name) or id.name
	frame.who:SetText(ns.ClassColorCode(id.class or (rec and rec.class)) .. name .. "|r")
	frame.sub:SetText(describe(id, rec))
	frame.note:SetText(rec and rec.note or "")
	frame.note:ClearFocus()
	frame.note:Refresh()
	refresh()

	if anchor then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
	elseif ns.settings.popupAtCursor then
		local scale = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, y / scale + 16)
	else
		UI.Place(frame, "popup")
	end
	frame:Show()
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
