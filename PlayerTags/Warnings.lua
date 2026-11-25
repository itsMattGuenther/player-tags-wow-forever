-- Warnings: your tags at the moments you decide something about a player.
--   * a group invite: their tags beside the game's invite box, good or bad;
--   * a duel request or a trade window: the same, beside those;
--   * a whisper from someone you tagged Avoid: a heads-up;
--   * someone you tagged Good people or Skilled posting in a public channel
--     that they are looking for a group: a line in chat with their name.
--
-- The warning beside a game box sits under it, in the game's tooltip
-- style, and goes away with it. Nothing about the game's own box changes.
-- When the box cannot be found, the alert box says it instead.
local _, ns = ...
local UI = ns.UI

local MAX_ROWS = 6
local strip
local stripRows = {}

local function buildStrip()
	strip = CreateFrame("Frame", "PlayerTagsWarning", UIParent, "TooltipBackdropTemplate")
	strip:SetFrameStrata("DIALOG")
	strip:SetClampedToScreen(true)
	strip:Hide()
	strip.head = UI.Text(strip, "GameFontNormalSmall", "Player Tags")
	strip.head:SetPoint("TOPLEFT", 10, -8)
	strip.title = UI.Text(strip, "GameFontHighlight")
	strip.title:SetPoint("TOPLEFT", strip.head, "BOTTOMLEFT", 0, -2)
	strip.title:SetPoint("RIGHT", strip, "RIGHT", -10, 0)
	strip.title:SetWordWrap(false)
	-- Goes away with the box it belongs to.
	strip:SetScript("OnUpdate", function(self)
		if self.anchor and not self.anchor:IsShown() then self:Hide() end
	end)
	strip:SetScript("OnHide", function(self) self.anchor = nil end)
end

local function stripRow(i)
	local r = stripRows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, strip)
	r:SetHeight(18)
	r.tags = ns.CreateBadgeRow(r, 16, 2)
	r.tags:SetPoint("LEFT", r, "LEFT", 0, 0)
	r.text = UI.Text(r, "GameFontHighlightSmall")
	r.text:SetWordWrap(true)
	stripRows[i] = r
	return r
end

--- Shows a player's tags under one of the game's boxes. `anchor` is that
--- box; without one, the alert box says it instead.
function ns.ShowWarning(anchor, headline, info, avoid)
	if not info then return end
	if not anchor or not anchor.IsShown or not anchor:IsShown() then
		ns.Notify({ kind = "warning", title = headline, rows = ns.DescribeRows(info),
			chat = ns.DescribeChat(headline, info), avoid = avoid })
		return
	end
	if not strip then buildStrip() end
	UI.ApplyScale(strip)
	local width = math.max(260, math.min(420, (anchor:GetWidth() or 320)))
	strip:SetWidth(width)
	strip.title:SetText(headline)
	local rows = ns.DescribeRows(info)
	local y = 8 + 14 + 2 + 16 + 6
	for i = 1, math.min(#rows, MAX_ROWS) do
		local r = stripRow(i)
		r:SetWidth(width - 20)
		r.tags:SetTags(rows[i].ids or {}, 4)
		local left = (r.tags:IsShown() and r.tags:GetWidth() or 0) + 6
		r.text:ClearAllPoints()
		r.text:SetPoint("LEFT", r, "LEFT", left, 0)
		r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		r.text:SetText(rows[i].text or "")
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", strip, "TOPLEFT", 10, -y)
		r:Show()
		y = y + 20
	end
	for i = math.min(#rows, MAX_ROWS) + 1, #stripRows do stripRows[i]:Hide() end
	strip:SetHeight(y + 6)
	strip:ClearAllPoints()
	strip:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
	strip.anchor = anchor
	strip:Show()
	if avoid and ns.settings.alertSound and PlaySound and _G.SOUNDKIT and _G.SOUNDKIT.RAID_WARNING then
		pcall(PlaySound, _G.SOUNDKIT.RAID_WARNING)
	end
end

function ns.HideWarning()
	if strip then strip:Hide() end
end

local function visiblePopup(which)
	if type(_G.StaticPopup_FindVisible) ~= "function" then return nil end
	local ok, frame = pcall(_G.StaticPopup_FindVisible, which)
	if ok and type(frame) == "table" then return frame end
	return nil
end

-- Who someone is from a name the game gave and maybe a GUID.
local function identify(name, guid)
	local id = { }
	if ns.IsText(name) then
		id.key = ns.Key(name)
		id.name = name
	end
	if ns.IsText(guid) then id.guid = guid end
	if not id.key and not id.guid then return nil end
	return id
end

local function colored(info, fallback)
	if info.rec then return ns.ColoredName(info.rec) end
	return fallback or "?"
end

---------------------------------------------------------------------------
-- Group invites. The event names the inviter by GUID, so the match is
-- exact. Good tags show too: a Great Healer inviting you is worth knowing.
---------------------------------------------------------------------------
local function onInvite(name, _, _, _, _, _, _, guid)
	if not ns.settings.inviteWarn then return end
	local id = identify(name, guid)
	local info = id and ns.TagsFor(id)
	if not info then return end
	-- The game shows its invite box in its own handler for this event; look
	-- for it a moment later.
	C_Timer.After(0.1, function()
		local box = visiblePopup("PARTY_INVITE")
		if not box and _G.LFGInvitePopup and _G.LFGInvitePopup:IsShown() then box = _G.LFGInvitePopup end
		ns.ShowWarning(box, colored(info, name) .. " invites you to a group", info, ns.ShouldWarn(info))
	end)
end

---------------------------------------------------------------------------
-- Duels give only a name. It is matched against your list as written, and
-- no GUID is ever taken from it.
---------------------------------------------------------------------------
local function onDuel(name)
	if not ns.settings.requestWarn then return end
	local id = identify(name, nil)
	local info = id and ns.TagsFor(id)
	if not info then return end
	C_Timer.After(0.1, function()
		ns.ShowWarning(visiblePopup("DUEL_REQUESTED"), colored(info, name) .. " wants to duel", info, ns.ShouldWarn(info))
	end)
end

---------------------------------------------------------------------------
-- Trades: while the trade window is open the game calls the other player
-- "NPC", a unit like any other, so the match is exact.
---------------------------------------------------------------------------
local function onTrade()
	if not ns.settings.requestWarn then return end
	local id = ns.IdentifyUnit("NPC")
	local info = id and ns.TagsFor(id)
	if not info then return end
	local window = _G.TradeFrame
	if window and not window:IsShown() then window = nil end
	ns.ShowWarning(window, colored(info, id.name) .. " wants to trade", info, ns.ShouldWarn(info))
end

---------------------------------------------------------------------------
-- Whispers from someone you tagged Avoid (or a shared list with alerts on).
---------------------------------------------------------------------------
local function onWhisper(_, sender, _, _, _, _, _, _, _, _, _, guid)
	if not ns.settings.requestWarn then return end
	local id = identify(sender, guid)
	local info = id and ns.TagsFor(id)
	if not ns.ShouldWarn(info) then return end
	local name = colored(info, sender)
	ns.Notify({
		kind = "whisper", key = info.key or id.key, wait = 30 * 60,
		title = name .. " is whispering you",
		rows = ns.DescribeRows(info), chat = ns.DescribeChat(name .. " is whispering you", info), avoid = true,
	})
end

---------------------------------------------------------------------------
-- Good players looking for a group. Public channels only, and only when
-- the message reads like a group search (or it is the LookingForGroup
-- channel), so trade chatter does not set it off.
---------------------------------------------------------------------------
-- Words that mean a group search, not a trade ("LF enchanter", "need a
-- port" are not).
local LFG_PATTERNS = {
	"%f[%w]lfg%f[%W]", "%f[%w]lf%d*m%f[%W]", "%f[%w]lf%s?%d%f[%W]",
	"looking for a? ?group", "looking for more", "%f[%w]lf a? ?group",
	"%f[%w]lf a? ?tank", "%f[%w]lf a? ?heal", "%f[%w]lf a? ?dps", "%f[%w]lf a? ?party",
	"need a? ?tank", "need a? ?heal", "need %d* ?dps", "need %d+ more",
}

local function looksLikeGroupSearch(text, channel)
	if type(channel) == "string" and channel:lower():find("lookingforgroup", 1, true) then return true end
	local lower = " " .. text:lower() .. " "
	for _, pattern in ipairs(LFG_PATTERNS) do
		if lower:find(pattern) then return true end
	end
	return false
end

local GOOD_FAMILIES = { good = true, skill = true }

local function onChannel(text, sender, _, _, _, _, _, _, channelBaseName, _, _, guid)
	if not ns.settings.lfgAlert then return end
	if not ns.IsText(text) or not ns.IsText(sender) then return end
	local id = identify(sender, guid)
	if not id or ns.IsMe(id) then return end
	local info = ns.TagsFor(id)
	if not info or #info.ids == 0 then return end
	local good = {}
	for _, tagId in ipairs(info.ids) do
		local tag = ns.GetTag(tagId)
		if tag and GOOD_FAMILIES[tag.family] then good[#good + 1] = tagId end
	end
	if #good == 0 or info.avoid then return end
	if not looksLikeGroupSearch(text, ns.IsText(channelBaseName) and channelBaseName or nil) then return end

	local short = sender:match("^([^%-]+)") or sender
	local link = "|Hplayer:" .. sender .. "|h[" .. (info.rec and info.rec.name or short) .. "]|h"
	ns.Notify({
		kind = "lfg", key = info.key or id.key, wait = 30 * 60, style = "chat",
		title = colored(info, short) .. " is looking for a group",
		rows = { { ids = good, text = ns.TagNames(good) } },
		chat = { "|cffffd100Player Tags:|r " .. ns.TagsEscape(good, 0) .. " " .. link
			.. " is looking for a group. You tagged them |cffa7afb8" .. ns.TagNames(good) .. "|r." },
	})
end

ns.LooksLikeGroupSearch = looksLikeGroupSearch

ns.Module("warnings", function()
	ns.On("PARTY_INVITE_REQUEST", function(...) ns.Safe("invite warning", onInvite, ...) end, "warnings")
	ns.On("DUEL_REQUESTED", function(...) ns.Safe("duel warning", onDuel, ...) end, "warnings")
	ns.On("TRADE_SHOW", function() ns.Safe("trade warning", onTrade) end, "warnings")
	ns.On("CHAT_MSG_WHISPER", function(...) ns.Safe("whisper warning", onWhisper, ...) end, "warnings")
	ns.On("CHAT_MSG_CHANNEL", function(...) ns.Safe("looking for group", onChannel, ...) end, "warnings")
end)
