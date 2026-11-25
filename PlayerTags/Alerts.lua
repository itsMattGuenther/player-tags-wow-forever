-- Alerts: a small box in the game's tooltip style for heads-ups, such as a
-- tagged player joining your group. It replaces the game's error-message
-- area, where "Not enough mana" shows, which is easy to miss or mistake for
-- an error.
--
-- The box is quiet: no sound of its own (sounds are separate settings), it
-- fades after a while or when clicked, and it never takes the Escape key.
-- Its position can be changed from the settings page ("Move").
local _, ns = ...
local UI = ns.UI

local WIDTH, MAX_ROWS, SHOW_FOR = 300, 4, 10
local DEFAULT_X, DEFAULT_Y = 0, 260 -- upper middle of the screen

local box
local rows = {}
local hideAt = 0
local moving = false

local function build()
	box = CreateFrame("Frame", "PlayerTagsAlert", UIParent, "TooltipBackdropTemplate")
	box:SetFrameStrata("DIALOG")
	box:SetWidth(WIDTH)
	box:SetClampedToScreen(true)
	box:EnableMouse(true)
	box:Hide()
	UI.Movable(box, "alert", DEFAULT_X, DEFAULT_Y)
	UI.Place(box, "alert", DEFAULT_X, DEFAULT_Y)
	-- Movable lets the box be dragged any time; only while moving is that wanted.
	box:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)

	box.head = UI.Text(box, "GameFontNormalSmall", "Player Tags")
	box.head:SetPoint("TOPLEFT", 10, -9)
	box.title = UI.Text(box, "GameFontHighlight")
	box.title:SetPoint("TOPLEFT", box.head, "BOTTOMLEFT", 0, -2)
	box.title:SetPoint("RIGHT", box, "RIGHT", -10, 0)
	box.more = UI.Text(box, "GameFontDisableSmall")

	box.done = UI.Button(box, "Done", 70, 20, true)
	box.done:SetPoint("BOTTOMRIGHT", -8, 8)
	box.done:Hide()
	box.done:SetScript("OnClick", function() ns.StopMovingAlert() end)

	box:SetScript("OnMouseUp", function(self, button)
		if not moving and button == "LeftButton" then self:Hide() end
	end)
	box:SetScript("OnUpdate", function(self)
		if moving or GetTime() < hideAt then return end
		if self:IsMouseOver() then return end -- stays while you read it
		self:Hide()
	end)
end

local function row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, box)
	r:SetSize(WIDTH - 20, 18)
	r.tags = ns.CreateBadgeRow(r, 16, 2)
	r.tags:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.text = UI.Text(r, "GameFontHighlightSmall")
	r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	r.text:SetWordWrap(false)
	rows[i] = r
	return r
end

--- Shows the box. `title` is the headline; `list` holds up to four lines,
--- each { ids = {tag ids}, text = "coloured name and tag names" }.
function ns.ShowAlert(title, list)
	if not box then build() end
	UI.ApplyScale(box)
	box.title:SetText(title or "")
	list = list or {}
	local y = 9 + 14 + 2 + 16 + 6
	local shown = math.min(#list, MAX_ROWS)
	for i = 1, shown do
		local r = row(i)
		r.tags:SetTags(list[i].ids or {}, 3)
		r.text:ClearAllPoints()
		local left = (r.tags:IsShown() and r.tags:GetWidth() or 0) + 6
		r.text:SetPoint("LEFT", r, "LEFT", left, 0)
		r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		r.text:SetText(list[i].text or "")
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -y)
		r:Show()
		y = y + 20
	end
	for i = shown + 1, #rows do rows[i]:Hide() end
	if #list > shown then
		box.more:ClearAllPoints()
		box.more:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -y)
		box.more:SetText("and " .. (#list - shown) .. " more")
		box.more:Show()
		y = y + 16
	else
		box.more:Hide()
	end
	box:SetHeight(y + 8)
	hideAt = GetTime() + SHOW_FOR
	box:Show()
end

--- Shows a sample box that can be dragged, with a Done button.
function ns.MoveAlert()
	if not box then build() end
	moving = true
	box:SetFrameStrata("FULLSCREEN_DIALOG")
	ns.ShowAlert("Drag this box to where alerts should appear.", {})
	box:SetHeight(76)
	box.done:Show()
end

function ns.StopMovingAlert()
	if not box then return end
	moving = false
	box.done:Hide()
	box:SetFrameStrata("DIALOG")
	box:Hide()
end

function ns.IsAlertShown()
	return box ~= nil and box:IsShown()
end

ns.Listen("SETTINGS_CHANGED", function() UI.ApplyScale(box) end, "alerts")
