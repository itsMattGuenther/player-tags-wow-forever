-- Widgets: the addon's windows are built from the game's own templates, so
-- they look like every other Blizzard window: the standard frame with its
-- portrait and close button, red buttons, check boxes, search box and tabs
-- along the bottom. Only the tag icons are our own drawing.
--
-- Rules that keep these templates out of trouble during combat:
--   * windows close with :Hide(), never the game's panel manager
--     (HideUIPanel), which addons may not call in combat;
--   * nothing here is registered with UIPanelWindows.
local _, ns = ...

local UI = {}
ns.UI = UI

local HIGHLIGHT_SQUARE = "Interface\\Buttons\\ButtonHilight-Square"
local CHECKED_SQUARE = "Interface\\Buttons\\CheckButtonHilight"
local ROW_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local ICON = "Interface\\AddOns\\PlayerTags\\Media\\icon"

-- The bar of buttons along the bottom of a window. The template's own bar
-- is 26 high, which puts 22-high buttons on top of the gold border; ours
-- is a little taller, so buttons sit in it with room above and below.
UI.BAR = 34      -- height of the bar under the inset
UI.BAR_Y = 7     -- where a 22-high button sits, from the window's bottom
UI.BAR_TEXT_Y = 13 -- where a line of small text sits, level with the buttons

function UI.Text(parent, font, text)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	if text then fs:SetText(text) end
	return fs
end

local function showTip(owner)
	if not owner.tip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(owner.tip, 1, 1, 1, 1, true)
	GameTooltip:Show()
end

local function hideTip(owner)
	if owner.tip then GameTooltip:Hide() end
end

UI.ShowTip, UI.HideTip = showTip, hideTip

--- Scales one of our windows by the "Window size" setting.
function UI.ApplyScale(frame)
	if frame and frame.SetScale then
		local scale = ns.settings and tonumber(ns.settings.scale) or 1
		if scale < 0.5 or scale > 1.5 then scale = 1 end
		frame:SetScale(scale)
	end
end

--- The game's standard window: rock background, gold title, round portrait
--- top left, red close button, an inset for content and a bar of buttons
--- along the bottom. `portrait` false hides the portrait.
function UI.Window(name, title, width, height, portrait)
	local f = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	f:SetSize(width, height)
	f:SetTitle(title or "")
	if portrait == false then
		ButtonFrameTemplate_HidePortrait(f)
	else
		f:SetPortraitToAsset(ICON)
	end
	f.Inset:ClearAllPoints()
	f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -60)
	f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, UI.BAR)
	f:EnableMouse(true)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	-- The template's close button goes through the game's panel manager,
	-- which is blocked for addons in combat. Hide the window directly.
	f.CloseButton:SetScript("OnClick", function(self) self:GetParent():Hide() end)
	UI.ApplyScale(f)
	return f
end

--- A red game button. `tip` on the button shows the game's tooltip.
function UI.Button(parent, text, width, height, small)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 80, height or 22)
	if small then
		b:SetNormalFontObject("GameFontNormalSmall")
		b:SetHighlightFontObject("GameFontHighlightSmall")
		b:SetDisabledFontObject("GameFontDisableSmall")
	end
	b:SetText(text or "")
	b:HookScript("OnEnter", showTip)
	b:HookScript("OnLeave", hideTip)

	--- Marks the button as the chosen one of a group, the way the game
	--- shows a pressed filter: the highlight stays lit.
	function b:SetOn(on)
		self.on = on and true or false
		if self.on then self:LockHighlight() else self:UnlockHighlight() end
	end

	function b:SetLabel(newText)
		self:SetText(newText)
	end

	return b
end

--- The game's check box with a label. `help` adds a second, dim line that
--- is always visible, for options that need a word of explanation.
function UI.Check(parent, text, help)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(26, 26)
	c.Text:ClearAllPoints()
	c.Text:SetPoint("LEFT", c, "RIGHT", 2, 1)
	c.Text:SetFontObject("GameFontHighlight")
	c.Text:SetText(text or "")
	if help then
		c.help = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		c.help:SetPoint("TOPLEFT", c.Text, "BOTTOMLEFT", 0, -3)
		c.help:SetJustifyH("LEFT")
		c.help:SetText(help)
	end
	c:SetScript("OnClick", function(self)
		UI.Click()
		if self.onChange then self.onChange(self:GetChecked() and true or false) end
	end)
	return c
end

--- The game's round radio button with a label.
function UI.Radio(parent, text)
	local r = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
	r.text:SetFontObject("GameFontHighlightSmall")
	r.text:SetText(text or "")
	return r
end

--- The game's text box. `placeholder` is the grey hint shown while empty.
--- onChange runs for typing; onEnter and onBlur when editing ends.
function UI.Edit(parent, width, height, placeholder)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxInstructionsTemplate")
	e:SetSize(width, height or 20)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontNormal")
	e:SetMaxLetters(200)
	e.Instructions:SetText(placeholder or "")
	e:HookScript("OnTextChanged", function(self, userInput)
		if userInput and self.onChange then self.onChange(self) end
	end)
	e:SetScript("OnEnterPressed", function(self)
		if self.onEnter then self.onEnter(self) end
		self:ClearFocus()
	end)
	e:HookScript("OnEditFocusLost", function(self)
		if self.onBlur then self.onBlur(self) end
	end)
	--- Kept for callers that set text and want the hint redrawn; the
	--- template redraws it on every change by itself.
	function e:Refresh()
		if self.Instructions then self.Instructions:SetShown(self:GetText() == "") end
	end
	return e
end

--- The game's search box: magnifying glass, grey hint, clear button.
--- onChange runs whenever the text changes, typed or cleared.
function UI.Search(parent, width, placeholder)
	local e = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	e:SetSize(width, 20)
	e:SetAutoFocus(false)
	e:SetMaxLetters(60)
	e.Instructions:SetText(placeholder or SEARCH or "Search")
	local last = ""
	e:HookScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		if text == last then return end
		last = text
		if self.onChange then self.onChange(self) end
	end)
	function e:Refresh()
		last = self:GetText() or ""
		if self.Instructions then self.Instructions:SetShown(last == "") end
	end
	return e
end

--- Tabs along the bottom of a window, as on the character and spellbook
--- windows. onSelect(id) runs when one is clicked.
function UI.Tabs(frame, list, onSelect)
	local tabs = {}
	for i, item in ipairs(list) do
		local name = frame:GetName() and (frame:GetName() .. "Tab" .. i) or nil
		local tab = CreateFrame("Button", name, frame, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(item.label)
		if i == 1 then
			tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 12, 2)
		else
			tab:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", 3, 0)
		end
		tab:SetScript("OnClick", function()
			UI.Click()
			onSelect(item.id)
		end)
		tab.tabId = item.id
		PanelTemplates_TabResize(tab, 0)
		tabs[i] = tab
	end
	PanelTemplates_SetNumTabs(frame, #tabs)

	--- Shows which tab is chosen.
	function frame:SelectTabId(id)
		for i, tab in ipairs(tabs) do
			if tab.tabId == id then PanelTemplates_SetTab(self, i) end
		end
	end
	return tabs
end

--- A clickable row in a list, lit the way the quest log and friends list
--- light theirs: a soft band on hover, the same band held when chosen.
function UI.Row(parent, height)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(height)
	row:SetHighlightTexture(ROW_HIGHLIGHT, "ADD")
	function row:SetOn(on)
		self.on = on and true or false
		if self.on then self:LockHighlight() else self:UnlockHighlight() end
	end
	return row
end

--- A square icon button that can be on or off, like an action button:
--- the game's square highlight on hover and its gold glow when on.
--- Holds one tag badge; `label` adds the tag's name underneath.
function UI.IconToggle(parent, size, label)
	local b = CreateFrame("CheckButton", nil, parent)
	b.badge = ns.CreateBadge(b, size)
	b.badge:SetPoint("TOP", 0, 0)
	-- The badge is a child frame, so it draws over the button's own
	-- textures. The hover square and the glow sit on a frame above it.
	local over = CreateFrame("Frame", nil, b)
	over:SetAllPoints(b.badge)
	over:SetFrameLevel((b.badge:GetFrameLevel() or 1) + 2)
	local hl = over:CreateTexture(nil, "ARTWORK")
	hl:SetTexture(HIGHLIGHT_SQUARE)
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	hl:Hide()
	local glow = over:CreateTexture(nil, "OVERLAY")
	glow:SetTexture(CHECKED_SQUARE)
	glow:SetBlendMode("ADD")
	glow:SetAllPoints()
	glow:Hide()
	b.hover, b.glow = hl, glow
	b:HookScript("OnEnter", function(self) self.hover:Show() end)
	b:HookScript("OnLeave", function(self) self.hover:Hide() end)
	if label then
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("TOP", b.badge, "BOTTOM", 0, -3)
		b.text:SetJustifyH("CENTER")
		b.text:SetJustifyV("TOP")
		b.text:SetWordWrap(true)
		if b.text.SetMaxLines then b.text:SetMaxLines(2) end
	end
	--- On shows the badge bright with the glow; off shows it dimmed.
	function b:SetOn(on)
		self.on = on and true or false
		self:SetChecked(self.on)
		self.glow:SetShown(self.on)
		self.badge:SetDim(not self.on)
		if self.text then
			if self.on then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(0.62, 0.62, 0.62) end
		end
	end
	return b
end

---------------------------------------------------------------------------
-- Window positions. A window opens at its default spot (the middle of the
-- screen unless the caller gives another) until it has been dragged; after
-- that it opens where it was left. A position is kept as the distance of
-- the window's centre from the centre of the screen.
---------------------------------------------------------------------------

--- The game keeps its own record of where dragged windows were and can put
--- them back by itself. These windows are placed by the addon only.
local function placedByUs(frame)
	if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
end

--- Puts a window at its remembered spot, or at its default.
function UI.Place(frame, key, defaultX, defaultY)
	local saved = key and ns.db and ns.db.positions and ns.db.positions[key]
	local x, y = defaultX or 0, defaultY or 0
	if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
		x, y = saved.x, saved.y
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

--- Lets a window be dragged. With a key, where it is dropped is remembered
--- and used by UI.Place from then on.
function UI.Movable(frame, key, defaultX, defaultY)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		placedByUs(self)
		if not key then return end
		local x, y = self:GetCenter()
		local cx, cy = UIParent:GetCenter()
		local mine, screen = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
		if not (x and y and cx and cy and mine and screen and mine > 0) then return end
		local ratio = screen / mine
		ns.db.positions[key] = {
			x = math.floor((x - cx * ratio) * 10 + 0.5) / 10,
			y = math.floor((y - cy * ratio) * 10 + 0.5) / 10,
		}
		UI.Place(self, key, defaultX, defaultY)
	end)
	placedByUs(frame)
end

function UI.Click()
	local kit = _G.SOUNDKIT
	if kit and kit.IG_MAINMENU_OPTION_CHECKBOX_ON and PlaySound then
		pcall(PlaySound, kit.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
end

--- "Warrior" for "WARRIOR".
function UI.ClassName(class)
	if not class then return nil end
	local names = _G.LOCALIZED_CLASS_NAMES_MALE
	if names and names[class] then return names[class] end
	return class:sub(1, 1) .. class:sub(2):lower()
end
