-- Widgets: a small, self-drawn UI kit. Drawing our own panels and buttons
-- keeps the addon independent of Blizzard templates that change between
-- client versions.
local _, ns = ...

local UI = {}
ns.UI = UI

local LINE = { 0.17, 0.20, 0.25 }
local GOLD = { 1, 0.82, 0 }

function UI.Fill(frame, r, g, b, a)
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(r, g, b, a or 1)
	frame.fill = bg
	return bg
end

function UI.Edges(frame, r, g, b, a)
	local e = {}
	for i = 1, 4 do
		e[i] = frame:CreateTexture(nil, "BORDER")
		e[i]:SetColorTexture(r, g, b, a or 1)
	end
	e[1]:SetPoint("TOPLEFT")
	e[1]:SetPoint("TOPRIGHT")
	e[1]:SetHeight(1)
	e[2]:SetPoint("BOTTOMLEFT")
	e[2]:SetPoint("BOTTOMRIGHT")
	e[2]:SetHeight(1)
	e[3]:SetPoint("TOPLEFT")
	e[3]:SetPoint("BOTTOMLEFT")
	e[3]:SetWidth(1)
	e[4]:SetPoint("TOPRIGHT")
	e[4]:SetPoint("BOTTOMRIGHT")
	e[4]:SetWidth(1)
	frame.edges = e
	function frame:SetEdgeColor(nr, ng, nb, na)
		for i = 1, 4 do self.edges[i]:SetColorTexture(nr, ng, nb, na or 1) end
	end
	return e
end

--- A dark panel with a thin border. Swallows clicks so they do not fall
--- through to the game world.
function UI.Panel(name, parent)
	local f = CreateFrame("Frame", name, parent or UIParent)
	UI.Fill(f, 0.047, 0.063, 0.086, 0.97)
	UI.Edges(f, LINE[1], LINE[2], LINE[3], 1)
	f:EnableMouse(true)
	return f
end

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

function UI.Button(parent, text, width, height)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 80, height or 22)
	UI.Fill(b, 0.078, 0.098, 0.133, 1)
	UI.Edges(b, LINE[1], LINE[2], LINE[3], 1)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("CENTER")
	b.label:SetText(text or "")
	b.on = false

	function b:Paint(hover)
		if self.on then
			self:SetEdgeColor(GOLD[1], GOLD[2], GOLD[3], 1)
			self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		elseif hover then
			self:SetEdgeColor(0.60, 0.65, 0.70, 1)
			self.label:SetTextColor(1, 1, 1)
		else
			self:SetEdgeColor(LINE[1], LINE[2], LINE[3], 1)
			self.label:SetTextColor(0.85, 0.87, 0.90)
		end
	end

	--- Marks the button as the selected one of a group.
	function b:SetOn(on)
		self.on = on and true or false
		self:Paint(false)
	end

	function b:SetLabel(newText)
		self.label:SetText(newText)
	end

	b:SetScript("OnEnter", function(self)
		self:Paint(true)
		showTip(self)
	end)
	b:SetScript("OnLeave", function(self)
		self:Paint(false)
		hideTip(self)
	end)
	b:Paint(false)
	return b
end

--- A checkbox with a label. `help` adds a dim second line that is always
--- visible, for options that need a word of explanation. (A hover tooltip
--- here would float over whatever sits beside the option.)
function UI.Check(parent, text, help)
	local c = CreateFrame("Button", nil, parent)

	c.box = CreateFrame("Frame", nil, c)
	c.box:SetSize(14, 14)
	c.box:SetPoint("TOPLEFT", 0, -3)
	UI.Fill(c.box, 0.03, 0.04, 0.055, 1)
	UI.Edges(c.box, 0.35, 0.40, 0.46, 1)

	c.mark = c.box:CreateTexture(nil, "ARTWORK")
	c.mark:SetPoint("TOPLEFT", 3, -3)
	c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
	c.mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)

	c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	c.label:SetPoint("LEFT", c.box, "RIGHT", 8, 0)
	c.label:SetJustifyH("LEFT")
	c.label:SetText(text or "")

	local width, height = c.label:GetStringWidth() or 0, 20
	if help then
		c.help = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		c.help:SetPoint("TOPLEFT", c.label, "BOTTOMLEFT", 0, -3)
		c.help:SetJustifyH("LEFT")
		c.help:SetText(help)
		width = math.max(width, c.help:GetStringWidth() or 0)
		height = 36
	end
	-- Only the box and its text are clickable, not the empty space beside them.
	c:SetSize(22 + width + 4, height)
	c.checked = false

	function c:SetChecked(value)
		self.checked = value and true or false
		if self.checked then self.mark:Show() else self.mark:Hide() end
	end

	function c:GetChecked()
		return self.checked
	end

	c:SetScript("OnClick", function(self)
		self:SetChecked(not self.checked)
		if self.onChange then self.onChange(self.checked) end
	end)
	c:SetChecked(false)
	return c
end

function UI.Edit(parent, width, height, placeholder)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(width, height or 22)
	e:SetAutoFocus(false)
	e:SetFontObject(GameFontHighlightSmall)
	e:SetTextInsets(6, 6, 0, 0)
	e:SetMaxLetters(200)
	UI.Fill(e, 0.03, 0.04, 0.055, 1)
	UI.Edges(e, LINE[1], LINE[2], LINE[3], 1)

	e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	e.hint:SetPoint("LEFT", 7, 0)
	e.hint:SetText(placeholder or "")

	function e:Refresh()
		if self:GetText() == "" and not self:HasFocus() then self.hint:Show() else self.hint:Hide() end
	end

	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self)
		if self.onEnter then self.onEnter(self) end
		self:ClearFocus()
	end)
	e:SetScript("OnEditFocusGained", function(self)
		self:SetEdgeColor(GOLD[1], GOLD[2], GOLD[3], 1)
		self:Refresh()
	end)
	e:SetScript("OnEditFocusLost", function(self)
		self:SetEdgeColor(LINE[1], LINE[2], LINE[3], 1)
		self:Refresh()
		if self.onBlur then self.onBlur(self) end
	end)
	e:SetScript("OnTextChanged", function(self, userInput)
		self:Refresh()
		if userInput and self.onChange then self.onChange(self) end
	end)
	e:Refresh()
	return e
end

---------------------------------------------------------------------------
-- Window positions. A window opens in the middle of the screen until it has
-- been dragged; after that it opens where it was left. A position is kept as
-- the distance of the window's centre from the centre of the screen.
---------------------------------------------------------------------------

--- The game keeps its own record of where dragged windows were and can put
--- them back by itself. These windows are placed by the addon only.
local function placedByUs(frame)
	if frame.SetUserPlaced then pcall(frame.SetUserPlaced, frame, false) end
end

--- Puts a window at its remembered spot, or dead centre when it has none.
function UI.Place(frame, key)
	local saved = key and ns.db and ns.db.positions and ns.db.positions[key]
	local x, y = 0, 0
	if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
		x, y = saved.x, saved.y
	end
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

--- Lets a window be dragged. With a key, where it is dropped is remembered
--- and used by UI.Place from then on.
function UI.Movable(frame, key)
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
		UI.Place(self, key)
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
