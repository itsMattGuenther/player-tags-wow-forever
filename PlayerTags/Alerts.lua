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

---------------------------------------------------------------------------
-- Notify: the one door every heads-up goes through, so they all behave the
-- same: a per-player wait before the same alert repeats, the box or chat
-- (or both) as chosen in settings, the Avoid sound, and holding alerts
-- until a fight ends when that is switched on.
---------------------------------------------------------------------------
local lastShown = {}  -- kind .. key -> time
local held = {}       -- alerts waiting for the end of combat

local function deliver(alert)
	local style = alert.style or ns.settings.alertStyle or "both"
	if style ~= "chat" then ns.ShowAlert(alert.title, alert.rows) end
	if style ~= "box" and alert.chat then
		local frame = _G.DEFAULT_CHAT_FRAME
		if frame and frame.AddMessage then
			for _, line in ipairs(alert.chat) do frame:AddMessage(line) end
		end
	end
	if alert.avoid and ns.settings.alertSound and PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING then
		pcall(PlaySound, _G.SOUNDKIT.RAID_WARNING)
	end
end

--- Shows a heads-up. alert = {
---   kind     "nearby", "invite", "whisper", "lfg", ...
---   key      the player's record key, for the wait before repeating
---   wait     seconds before the same kind repeats for that player (optional)
---   title    the box's headline
---   rows     the box's lines: { ids = {tag ids}, text = "..." }
---   chat     lines for the chat frame
---   avoid    true plays the Avoid sound when that is on
--- }
--- Returns true when it was shown or held for later.
function ns.Notify(alert)
	if type(alert) ~= "table" then return false end
	if alert.key and alert.wait then
		local slot = (alert.kind or "") .. ":" .. alert.key
		local now = GetTime()
		if lastShown[slot] and now - lastShown[slot] < alert.wait then return false end
		lastShown[slot] = now
	end
	if ns.settings.alertHoldCombat and InCombatLockdown() then
		if #held < 6 then held[#held + 1] = alert end
		return true
	end
	deliver(alert)
	return true
end

--- Forgets the waits (used by the test command so samples always show).
function ns.ResetAlertWaits()
	lastShown = {}
end

--- Starts a player's wait as if an alert had just shown, so tagging
--- someone does not set off an alert about them a moment later.
function ns.StartAlertWait(kind, key)
	if key then lastShown[kind .. ":" .. key] = GetTime() end
end

ns.On("PLAYER_REGEN_ENABLED", function()
	if #held == 0 then return end
	local waiting = held
	held = {}
	for _, alert in ipairs(waiting) do ns.Safe("alerts", deliver, alert) end
end, "alerts")

---------------------------------------------------------------------------
-- What an alert or warning says about a player: their tags, your note and
-- where you tagged them. Shared lists add a line saying whose list it is.
---------------------------------------------------------------------------
local DIM = "|cffa7afb8"

--- Lines describing a player for alerts and warnings, as { ids, text } rows.
--- `info` is what ns.TagsFor returns.
function ns.DescribeRows(info)
	local rows = {}
	if not info then return rows end
	local own = info.ids or {}
	if #own > 0 then
		rows[#rows + 1] = { ids = own, text = ns.TagNames(own) }
	end
	local rec = info.rec
	if rec and ns.IsText(rec.note) then
		rows[#rows + 1] = { text = "|cffffffff\"" .. rec.note .. "\"|r" }
	end
	local latest = rec and ns.LatestTag(rec)
	if latest and latest.t then
		local where = "Tagged " .. ns.Ago(latest.t)
		if ns.IsText(latest.zone) then where = where .. " in " .. latest.zone end
		rows[#rows + 1] = { text = DIM .. where .. "|r" }
	end
	for _, from in ipairs(info.shared or {}) do
		rows[#rows + 1] = { ids = from.ids, text = DIM .. "From " .. from.list .. ":|r " .. ns.TagNames(from.ids) }
	end
	return rows
end

--- The same, as chat lines with the addon's prefix in front of the first.
function ns.DescribeChat(headline, info)
	local lines = { "|cffffd100Player Tags:|r " .. headline }
	for _, row in ipairs(ns.DescribeRows(info)) do
		local icons = row.ids and (ns.TagsEscape(row.ids, 0) .. " ") or ""
		lines[#lines + 1] = "   " .. icons .. row.text
	end
	return lines
end
