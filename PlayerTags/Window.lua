-- Window: the main window (/tags), in the game's standard frame. Two tabs
-- along the bottom: Players and Tags. Settings live in the game's own
-- Settings panel (Settings.lua); the Settings button here opens it.
-- Also the export/import dialog.
local _, ns = ...
local UI = ns.UI

local W, H = 800, 548
-- The standard frame's inset starts 60 below the top (the title and the
-- strip beside the portrait) and stops UI.BAR above the bottom.

local frame
local pages = {}
local currentTab = "players"
local refreshers = {}

local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

---------------------------------------------------------------------------
-- Players tab
---------------------------------------------------------------------------
local ROW_H, VISIBLE, LIST_TOP = 26, 15, 24
local players = { rows = {}, list = {}, offset = 0, search = "", family = nil, sort = "seen", confirm = nil }

local function buildPlayerList()
	local list = {}
	local needle = players.search:lower()
	for key, rec in pairs(ns.db.players) do
		local ids = ns.TagIds(rec)
		local keep = true
		if players.family then
			keep = false
			for _, tagId in ipairs(ids) do
				if ns.GetTag(tagId).family == players.family then
					keep = true
					break
				end
			end
		end
		if keep and needle ~= "" then
			local hay = (rec.name or key):lower() .. " " .. (rec.note or ""):lower() .. " " .. ns.TagNames(ids):lower()
			keep = hay:find(needle, 1, true) ~= nil
		end
		if keep then list[#list + 1] = { key = key, rec = rec, ids = ids } end
	end
	if players.sort == "name" then
		table.sort(list, function(a, b) return a.key < b.key end)
	else
		table.sort(list, function(a, b)
			local sa = a.rec.seen or a.rec.created or 0
			local sb = b.rec.seen or b.rec.created or 0
			if sa ~= sb then return sa > sb end
			return a.key < b.key
		end)
	end
	players.list = list
end

-- Players tagged from a chat name have no class until the game tells us.
-- Ask its memory of them each time the list is drawn.
local function learnMissing()
	local changed = false
	for key, rec in pairs(ns.db.players) do
		if rec.guid and not (rec.class and rec.race and rec.level) and ns.Learn(rec, key) then
			changed = true
		end
	end
	return changed
end

local function seenText(rec)
	local seen = ns.Ago(rec.seen or rec.created)
	if ns.IsText(rec.seenZone) then seen = seen .. ", " .. rec.seenZone end
	return seen
end

local function refreshPlayers()
	local page = pages.players
	if not page then return end
	learnMissing()
	buildPlayerList()
	local total = #players.list
	players.offset = clamp(players.offset, 0, math.max(0, total - VISIBLE))

	for i = 1, VISIBLE do
		local row, item = players.rows[i], players.list[i + players.offset]
		if item then
			local rec = item.rec
			row.key = item.key
			row.name:SetText(ns.ColoredName(rec, item.key))
			row.tags:SetTags(item.ids, 6)
			row.seen:SetText(seenText(rec))
			row.note:SetText(rec.note or "")
			local confirming = players.confirm == item.key
			row.del:SetLabel(confirming and "Sure?" or "Remove")
			if confirming or row:IsMouseOver() then row.del:Show() else row.del:Hide() end
			row:Show()
		else
			row.key = nil
			row:Hide()
		end
	end

	if total == 0 then
		if ns.PlayerCount() == 0 then
			page.empty:SetText("Nobody tagged yet.\nTarget a player and type /tag, or right-click a name and choose Tag player.")
		else
			page.empty:SetText("No players match.")
		end
		page.empty:Show()
	else
		page.empty:Hide()
	end

	local all = ns.PlayerCount()
	page.count:SetText(total == all and (all .. (all == 1 and " player" or " players")) or (total .. " of " .. all .. " players"))

	local track = VISIBLE * ROW_H
	if total > VISIBLE then
		local height = math.max(18, track * VISIBLE / total)
		local y = (track - height) * (players.offset / (total - VISIBLE))
		page.thumb:SetHeight(height)
		page.thumb:ClearAllPoints()
		page.thumb:SetPoint("TOPRIGHT", frame.Inset, "TOPRIGHT", -3, -(LIST_TOP + y))
		page.thumb:Show()
	else
		page.thumb:Hide()
	end

	for _, chip in ipairs(page.chips) do chip:SetOn(chip.family == players.family) end
	page.sortName:SetOn(players.sort == "name")
	page.sortSeen:SetOn(players.sort == "seen")
end

-- The full last-seen text and note, for rows where they are cut short.
local function rowTip(row)
	local rec = row.key and ns.GetRecord(row.key)
	if not rec then return end
	if not (row.seen:IsTruncated() or row.note:IsTruncated()) then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.ColoredName(rec, row.key))
	GameTooltip:AddLine("Last seen " .. seenText(rec), 0.8, 0.8, 0.8, true)
	if ns.IsText(rec.note) then GameTooltip:AddLine("\"" .. rec.note .. "\"", 1, 1, 1, true) end
	GameTooltip:Show()
end

local function makePlayerRow(page, index)
	local inset = frame.Inset
	local row = UI.Row(page, ROW_H)
	row:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -(LIST_TOP + (index - 1) * ROW_H))
	row:SetPoint("RIGHT", inset, "RIGHT", -12, 0)

	row.name = UI.Text(row, "GameFontHighlight")
	row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.name:SetWidth(170)
	row.name:SetWordWrap(false)

	row.tags = ns.CreateBadgeRow(row, 16, 2)
	row.tags:SetPoint("LEFT", row, "LEFT", 184, 0)

	row.seen = UI.Text(row, "GameFontHighlightSmall")
	row.seen:SetPoint("LEFT", row, "LEFT", 330, 0)
	row.seen:SetWidth(186)
	row.seen:SetWordWrap(false)

	row.note = UI.Text(row, "GameFontDisableSmall")
	row.note:SetPoint("LEFT", row, "LEFT", 524, 0)
	row.note:SetPoint("RIGHT", row, "RIGHT", -74, 0)
	row.note:SetWordWrap(false)

	row.del = UI.Button(row, "Remove", 64, 20, true)
	row.del:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.del.tip = "Remove this player and their tags"
	row.del:Hide()
	row.del:SetScript("OnClick", function()
		if not row.key then return end
		if players.confirm == row.key then
			players.confirm = nil
			ns.DeleteRecord(row.key)
		else
			players.confirm = row.key
			refreshPlayers()
		end
	end)
	-- The Remove button shows while the pointer is on the row.
	row.del:HookScript("OnLeave", function()
		if not row:IsMouseOver() and players.confirm ~= row.key then row.del:Hide() end
	end)

	row:SetScript("OnEnter", function(self)
		self.del:Show()
		rowTip(self)
	end)
	row:SetScript("OnLeave", function(self)
		GameTooltip:Hide()
		if not self.del:IsMouseOver() and players.confirm ~= self.key then self.del:Hide() end
	end)
	row:SetScript("OnClick", function(self)
		local rec = self.key and ns.GetRecord(self.key)
		if not rec then return end
		local id = ns.IdentifyName(rec.name or self.key, rec.guid)
		if id then
			id.class = id.class or rec.class
			id.level = id.level or rec.level
			id.race = id.race or rec.race
			ns.OpenQuickTag(id, frame)
		end
	end)
	return row
end

-- A column heading. Headings that sort the list light up when chosen.
local function header(page, label, x, sort)
	local b = CreateFrame("Button", nil, page)
	b:SetSize(8 + #label * 7, 18)
	b:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", x, -4)
	b.text = UI.Text(b, sort and "GameFontNormalSmall" or "GameFontDisableSmall", label)
	b.text:SetPoint("LEFT", 2, 0)
	function b:SetOn(on)
		self.on = on and true or false
		if not sort then return end
		if self.on then self.text:SetFontObject("GameFontHighlightSmall") else self.text:SetFontObject("GameFontNormalSmall") end
	end
	if sort then
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		b.tip = "Sort by " .. label:lower()
		b:SetScript("OnEnter", UI.ShowTip)
		b:SetScript("OnLeave", UI.HideTip)
		b:SetScript("OnClick", function()
			UI.Click()
			players.sort = sort
			players.offset = 0
			refreshPlayers()
		end)
	end
	return b
end

local function buildPlayers(page)
	page.search = UI.Search(page, 220, "Search a name, tag or note")
	page.search:SetPoint("TOPLEFT", frame, "TOPLEFT", 74, -32)
	page.search.onChange = function(self)
		players.search = ns.Trim(self:GetText())
		players.offset = 0
		refreshPlayers()
	end

	page.chips = {}
	local previous
	local function chip(label, family)
		local b = UI.Button(page, label, 14 + #label * 6.2, 22, true)
		b.family = family
		if previous then
			b:SetPoint("LEFT", previous, "RIGHT", 2, 0)
		else
			b:SetPoint("LEFT", page.search, "RIGHT", 12, 0)
		end
		b:SetScript("OnClick", function()
			players.family = family
			players.offset = 0
			refreshPlayers()
		end)
		previous = b
		page.chips[#page.chips + 1] = b
	end
	chip("All", nil)
	for _, family in ipairs(ns.FAMILIES) do chip(family.name, family.id) end

	page.sortName = header(page, "PLAYER", 10, "name")
	header(page, "TAGS", 188)
	page.sortSeen = header(page, "LAST SEEN", 334, "seen")
	header(page, "NOTE", 528)

	for i = 1, VISIBLE do players.rows[i] = makePlayerRow(page, i) end

	page.thumb = page:CreateTexture(nil, "ARTWORK")
	page.thumb:SetWidth(4)
	page.thumb:SetColorTexture(0.55, 0.55, 0.55, 0.6)
	page.thumb:Hide()

	page.empty = UI.Text(page, "GameFontDisable")
	page.empty:SetPoint("TOP", frame.Inset, "TOP", 0, -(LIST_TOP + 60))
	page.empty:SetWidth(460)
	page.empty:SetJustifyH("CENTER")
	page.empty:Hide()

	page.count = UI.Text(page, "GameFontHighlightSmall")
	page.count:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 106, UI.BAR_TEXT_Y)

	local import = UI.Button(page, "Import", 80, 22)
	import:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, UI.BAR_Y)
	import.tip = "Paste a backup made with Export."
	import:SetScript("OnClick", function() ns.ShowShare("import") end)
	local export = UI.Button(page, "Export", 80, 22)
	export:SetPoint("RIGHT", import, "LEFT", -2, 0)
	export.tip = "Your whole list as text, to copy somewhere safe."
	export:SetScript("OnClick", function() ns.ShowShare("export") end)

	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		players.offset = players.offset - delta * 3
		refreshPlayers()
	end)
end

refreshers.players = refreshPlayers

---------------------------------------------------------------------------
-- Tags tab: the tag list on the left, an editor on the right
---------------------------------------------------------------------------
local TAG_COLS, TAG_ROWS, CELL_W, CELL_H = 2, 16, 168, 24
local tagsPage = { cells = {}, offset = 0, editing = nil, deleteArmed = false }
local editTag, paintEditor

local function refreshTags()
	local page = pages.tags
	if not page then return end
	local all = ns.AllTags(true)
	local rowsTotal = math.ceil(#all / TAG_COLS)
	tagsPage.offset = clamp(tagsPage.offset, 0, math.max(0, rowsTotal - TAG_ROWS))
	local editing = tagsPage.editing
	for i, cell in ipairs(tagsPage.cells) do
		local tag = all[i + tagsPage.offset * TAG_COLS]
		if tag then
			cell.tag = tag
			cell.badge:SetTag(tag.id)
			cell.badge:SetDim(tag.hidden)
			cell.label:SetText(tag.name .. (tag.hidden and " |cff808080(hidden)|r" or ""))
			cell:SetOn(editing ~= nil and editing.id == tag.id)
			cell:Show()
		else
			cell.tag = nil
			cell:Hide()
		end
	end
	paintEditor()
end

function paintEditor()
	local page = pages.tags
	local e = tagsPage.editing
	if not page or not e then return end
	local family = ns.familyById[e.family] or ns.familyById.info

	page.editorTitle:SetText(e.id and "Edit tag" or "New tag")
	for _, r in ipairs(page.familyButtons) do r:SetChecked(r.family == e.family) end
	for index, b in ipairs(page.glyphButtons) do
		b.badge:SetGlyph(index - 1, family.r, family.g, family.b)
		b:SetOn(index - 1 == e.glyph)
	end
	page.showCheck:SetChecked(not e.hidden)

	if not e.id then
		page.third:Hide()
	elseif e.builtin then
		page.third:SetLabel("Reset")
		page.third.tip = "Put this starter tag back to its original name, family and picture."
		if e.edited then page.third:Show() else page.third:Hide() end
	else
		page.third:SetLabel(tagsPage.deleteArmed and "Sure?" or "Delete")
		page.third.tip = "Delete this tag and take it off every player."
		page.third:Show()
	end
end

function editTag(tag)
	local page = pages.tags
	local e
	if tag then
		e = { id = tag.id, name = tag.name, family = tag.family, glyph = tag.glyph,
			hidden = tag.hidden, builtin = tag.builtin, edited = tag.edited }
	else
		e = { name = "", family = "info", glyph = 22, hidden = false }
	end
	tagsPage.editing = e
	tagsPage.deleteArmed = false
	if page then
		page.nameEdit:SetText(e.name)
		page.message:SetText("")
	end
	refreshTags()
end

local function buildTags(page)
	local inset = frame.Inset
	local hint = UI.Text(page, "GameFontHighlightSmall", "Click a tag to edit it. Hidden tags stay on players but leave the tagging popup.")
	hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 74, -38)

	for i = 1, TAG_COLS * TAG_ROWS do
		local col = (i - 1) % TAG_COLS
		local row = math.floor((i - 1) / TAG_COLS)
		local cell = UI.Row(page, CELL_H)
		cell:SetWidth(CELL_W)
		cell:SetPoint("TOPLEFT", inset, "TOPLEFT", 8 + col * (CELL_W + 4), -(8 + row * CELL_H))
		cell.badge = ns.CreateBadge(cell, 16)
		cell.badge:SetPoint("LEFT", cell, "LEFT", 4, 0)
		cell.label = UI.Text(cell, "GameFontHighlight")
		cell.label:SetPoint("LEFT", cell.badge, "RIGHT", 6, 0)
		cell.label:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
		cell.label:SetWordWrap(false)
		cell:SetScript("OnClick", function(self)
			UI.Click()
			if self.tag then editTag(ns.GetTag(self.tag.id)) end
		end)
		tagsPage.cells[i] = cell
	end
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		tagsPage.offset = tagsPage.offset - delta
		refreshTags()
	end)

	-- the editor, to the right of the list
	local divider = page:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.08)
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", inset, "TOPLEFT", 356, -8)
	divider:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 356, 8)

	local X = 376
	local function at(widget, y, x)
		widget:SetPoint("TOPLEFT", inset, "TOPLEFT", X + (x or 0), -y)
	end

	page.editorTitle = UI.Text(page, "GameFontNormalLarge", "New tag")
	at(page.editorTitle, 12)

	local nameLabel = UI.Text(page, "GameFontNormalSmall", "Name")
	at(nameLabel, 44)
	page.nameEdit = UI.Edit(page, 230, 20, "Tag name")
	at(page.nameEdit, 58, 6)
	page.nameEdit:SetMaxLetters(24)
	page.nameEdit.onChange = function(self)
		if tagsPage.editing then tagsPage.editing.name = self:GetText() end
	end

	local familyLabel = UI.Text(page, "GameFontNormalSmall", "Family")
	at(familyLabel, 90)
	page.familyButtons = {}
	for i, family in ipairs(ns.FAMILIES) do
		local r = UI.Radio(page, family.name)
		r.family = family.id
		at(r, 106 + math.floor((i - 1) / 2) * 20, ((i - 1) % 2) * 150)
		r:SetScript("OnClick", function()
			UI.Click()
			if not tagsPage.editing then return end
			tagsPage.editing.family = family.id
			paintEditor()
		end)
		page.familyButtons[i] = r
	end

	local glyphLabel = UI.Text(page, "GameFontNormalSmall", "Picture")
	at(glyphLabel, 152)
	page.glyphButtons = {}
	for index = 0, ns.GLYPH_COUNT - 1 do
		local col, row = index % 8, math.floor(index / 8)
		local b = UI.IconToggle(page, 26)
		b:SetSize(26, 26)
		at(b, 168 + row * 32, col * 32)
		b:SetScript("OnClick", function()
			UI.Click()
			if not tagsPage.editing then return end
			tagsPage.editing.glyph = index
			paintEditor()
		end)
		page.glyphButtons[index + 1] = b
	end

	page.showCheck = UI.Check(page, "Show in the tagging popup")
	at(page.showCheck, 300, -4)
	page.showCheck.onChange = function(checked)
		if tagsPage.editing then tagsPage.editing.hidden = not checked end
	end

	local save = UI.Button(page, "Save", 90, 22)
	at(save, 336)
	save:SetScript("OnClick", function()
		local e = tagsPage.editing
		if not e then return end
		e.name = page.nameEdit:GetText()
		page.nameEdit:ClearFocus()
		local id, problem = ns.SaveTag(e.id, e)
		if not id then
			page.message:SetText("|cffff2020" .. (problem or "That did not save.") .. "|r")
			return
		end
		ns.SetTagHidden(id, e.hidden)
		editTag(ns.GetTag(id))
		page.message:SetText("|cff20ff20Saved.|r")
	end)

	local new = UI.Button(page, "New tag", 90, 22)
	new:SetPoint("LEFT", save, "RIGHT", 4, 0)
	new:SetScript("OnClick", function() editTag(nil) end)

	page.third = UI.Button(page, "Delete", 90, 22)
	page.third:SetPoint("LEFT", new, "RIGHT", 4, 0)
	page.third:SetScript("OnClick", function()
		local e = tagsPage.editing
		if not e or not e.id then return end
		if e.builtin then
			ns.ResetTag(e.id)
			ns.SetTagHidden(e.id, false)
			editTag(ns.GetTag(e.id))
			page.message:SetText("|cff20ff20Back to the original.|r")
			return
		end
		if not tagsPage.deleteArmed then
			tagsPage.deleteArmed = true
			paintEditor()
			return
		end
		ns.DeleteTag(e.id)
		editTag(nil)
		page.message:SetText("|cff20ff20Deleted.|r")
	end)

	page.message = UI.Text(page, "GameFontHighlightSmall")
	at(page.message, 368)
	page.message:SetWidth(380)

	editTag(nil)
end

refreshers.tags = refreshTags

---------------------------------------------------------------------------
-- Shared lists tab: lists other players gave you, kept apart from yours
---------------------------------------------------------------------------
local SHARED_ROWS = 10
local sharedPage = { rows = {}, confirm = nil }

local function refreshShared()
	local page = pages.shared
	if not page then return end
	local lists = ns.SharedLists()
	for i, row in ipairs(sharedPage.rows) do
		local item = lists[i]
		if item then
			local list = item.list
			row.listId = item.id
			row.name:SetText(list.name or "Shared list")
			local bits = {}
			if ns.IsText(list.from) then bits[#bits + 1] = "from " .. list.from end
			local count = ns.SharedPlayerCount(list)
			bits[#bits + 1] = count .. (count == 1 and " player" or " players")
			if list.added then bits[#bits + 1] = "added " .. ns.Ago(list.added) end
			row.info:SetText(table.concat(bits, " · "))
			row.alerts:SetChecked(list.alerts == true)
			local confirming = sharedPage.confirm == item.id
			row.remove:SetLabel(confirming and "Sure?" or "Remove")
			row:Show()
		else
			row.listId = nil
			row:Hide()
		end
	end
	if #lists == 0 then page.empty:Show() else page.empty:Hide() end
	page.count:SetText(#lists .. (#lists == 1 and " shared list" or " shared lists"))
end

local function buildShared(page)
	local inset = frame.Inset
	local hint = UI.Text(page, "GameFontHighlightSmall",
		"Tags other players shared with you. They stay separate from your own and are never in what you export or share.")
	hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 74, -30)
	hint:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
	hint:SetJustifyV("TOP")

	for i = 1, SHARED_ROWS do
		local row = CreateFrame("Frame", nil, page)
		row:SetHeight(38)
		row:SetPoint("TOPLEFT", inset, "TOPLEFT", 10, -(8 + (i - 1) * 40))
		row:SetPoint("RIGHT", inset, "RIGHT", -10, 0)
		row.name = UI.Text(row, "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)
		row.name:SetWidth(420)
		row.name:SetWordWrap(false)
		row.info = UI.Text(row, "GameFontDisableSmall")
		row.info:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
		row.info:SetWidth(420)
		row.alerts = UI.Check(row, "Alerts")
		row.alerts:SetPoint("RIGHT", row, "RIGHT", -150, 0)
		row.alerts.onChange = function(on)
			if row.listId then ns.SetSharedAlerts(row.listId, on) end
		end
		row.remove = UI.Button(row, "Remove", 80, 22)
		row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.remove.tip = "Removes this whole list. Your own tags are not touched."
		row.remove:SetScript("OnClick", function()
			if not row.listId then return end
			if sharedPage.confirm == row.listId then
				sharedPage.confirm = nil
				ns.RemoveSharedList(row.listId)
			else
				sharedPage.confirm = row.listId
			end
			refreshShared()
		end)
		sharedPage.rows[i] = row
	end

	page.empty = UI.Text(page, "GameFontDisable",
		"No shared lists. If someone shares their tags with you, paste their text into Import.")
	page.empty:SetPoint("TOP", inset, "TOP", 0, -80)
	page.empty:SetWidth(460)
	page.empty:SetJustifyH("CENTER")

	page.count = UI.Text(page, "GameFontHighlightSmall")
	page.count:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 106, UI.BAR_TEXT_Y)

	local import = UI.Button(page, "Import", 80, 22)
	import:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, UI.BAR_Y)
	import.tip = "Paste a list someone shared with you."
	import:SetScript("OnClick", function() ns.ShowShare("import") end)
	local shareButton = UI.Button(page, "Share your tags", 130, 22)
	shareButton:SetPoint("RIGHT", import, "LEFT", -2, 0)
	shareButton.tip = "Your own tags as text you can give to a friend. You choose what goes in."
	shareButton:SetScript("OnClick", function() ns.ShowShare("share") end)
end

refreshers.shared = refreshShared

---------------------------------------------------------------------------
-- Window shell
---------------------------------------------------------------------------
local TABS = {
	{ id = "players", label = "Players", build = buildPlayers },
	{ id = "tags", label = "Tags", build = buildTags },
	{ id = "shared", label = "Shared lists", build = buildShared },
}

local function selectTab(id)
	if not pages[id] then id = "players" end
	currentTab = id
	for _, tab in ipairs(TABS) do
		local page = pages[tab.id]
		if tab.id == id then page:Show() else page:Hide() end
	end
	frame:SelectTabId(id)
	players.confirm = nil
	refreshers[id]()
end

local function build()
	frame = UI.Window("PlayerTagsFrame", "Player Tags", W, H)
	UI.Movable(frame, "window")
	UI.Place(frame, "window")
	frame:Hide()
	table.insert(UISpecialFrames, "PlayerTagsFrame")

	local settings = UI.Button(frame, "Settings", 92, 22)
	settings:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, UI.BAR_Y)
	settings.tip = "Player Tags settings, in the game's Options under AddOns."
	settings:SetScript("OnClick", function() ns.OpenSettings() end)

	for _, tab in ipairs(TABS) do
		local page = CreateFrame("Frame", nil, frame)
		page:SetAllPoints(frame)
		page:Hide()
		pages[tab.id] = page
		tab.build(page)
	end
	UI.Tabs(frame, TABS, selectTab)

	frame:SetScript("OnShow", function() selectTab(currentTab) end)
	frame:SetScript("OnHide", function()
		players.confirm = nil
		ns.CloseQuickTag()
	end)
end

--- Opens the window on a tab ("players", "tags"), optionally with the
--- player search filled in. With no tab it opens on Players: everything
--- that says "open your list" means the list of players, not whichever tab
--- was used last. "options" opens the game's Settings instead.
function ns.ShowWindow(tab, search)
	if tab == "options" then
		ns.OpenSettings()
		return
	end
	if not frame then build() end
	currentTab = (tab and pages[tab]) and tab or "players"
	if search and pages.players then
		players.search = ns.Trim(search)
		players.offset = 0
		pages.players.search:SetText(players.search)
		pages.players.search:Refresh()
	end
	if frame:IsShown() then selectTab(currentTab) else frame:Show() end
	-- The game's Settings panel shares this window's layer; opened from
	-- there, the list must come out on top of it.
	sharedPage.confirm = nil
	frame:Raise()
	-- The game can need a moment to look up a player it has not seen this
	-- session, so ask once more shortly after the list opens.
	ns.Debounce("list learn", 2, function()
		if frame:IsShown() and currentTab == "players" and learnMissing() then refreshPlayers() end
	end)
end

function ns.ToggleWindow()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		ns.ShowWindow()
	end
end

local function refreshIfOpen()
	if frame and frame:IsShown() then refreshers[currentTab]() end
end

ns.Listen("RECORD_CHANGED", refreshIfOpen, "window")
ns.Listen("SETTINGS_CHANGED", function()
	UI.ApplyScale(frame)
	UI.ApplyScale(_G.PlayerTagsShare)
	refreshIfOpen()
end, "window")
ns.Listen("TAGS_CHANGED", function()
	if not (frame and frame:IsShown()) then return end
	-- An edited tag keeps its editor open; a deleted one falls back to "New tag".
	local e = tagsPage.editing
	if e and e.id and not ns.GetTag(e.id) then
		editTag(nil)
	else
		refreshers[currentTab]()
	end
end, "window")

---------------------------------------------------------------------------
-- Export / import dialog
---------------------------------------------------------------------------
local share

local function buildShare()
	share = UI.Window("PlayerTagsShare", "Export", 540, 400)
	share:SetFrameStrata("DIALOG")
	share:SetPoint("CENTER")
	share:Hide()
	UI.Movable(share)
	table.insert(UISpecialFrames, "PlayerTagsShare")

	share.hint = UI.Text(share, "GameFontHighlightSmall")
	share.hint:SetPoint("TOPLEFT", share, "TOPLEFT", 74, -30)
	share.hint:SetPoint("RIGHT", share, "RIGHT", -12, 0)
	share.hint:SetJustifyV("TOP")

	-- Share: what goes in. Import: a name for a shared list.
	share.options = CreateFrame("Frame", nil, share)
	share.options:SetPoint("TOPLEFT", share.Inset, "TOPLEFT", 6, -4)
	share.options:SetPoint("RIGHT", share.Inset, "RIGHT", -6, 0)
	share.options:SetHeight(56)
	share.familyChecks = {}
	for i, family in ipairs(ns.FAMILIES) do
		local c = UI.Check(share.options, family.name)
		c:SetPoint("TOPLEFT", share.options, "TOPLEFT", (i - 1) * 125, 0)
		c.family = family.id
		c:SetChecked(true)
		c.onChange = function() ns.ShowShare("share", true) end
		share.familyChecks[i] = c
	end
	share.notesCheck = UI.Check(share.options, "Include my notes")
	share.notesCheck:SetPoint("TOPLEFT", share.options, "TOPLEFT", 0, -26)
	share.notesCheck.onChange = function() ns.ShowShare("share", true) end
	share.listName = UI.Edit(share, 300, 20, "Name for a shared list (optional)")
	share.listName:SetPoint("TOPLEFT", share.Inset, "TOPLEFT", 12, -8)

	local scroll = CreateFrame("ScrollFrame", nil, share)
	scroll:SetPoint("TOPLEFT", share.Inset, "TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", share.Inset, "BOTTOMRIGHT", -8, 8)
	share.scroll = scroll
	scroll:EnableMouse(true)
	scroll:EnableMouseWheel(true)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject("ChatFontNormal")
	edit:SetWidth(500)
	edit:SetMaxLetters(0)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	scroll:SetScrollChild(edit)
	share.edit = edit

	local function scrollTo(value)
		local range = scroll:GetVerticalScrollRange() or 0
		scroll:SetVerticalScroll(clamp(value, 0, math.max(0, range)))
	end
	scroll:SetScript("OnMouseWheel", function(self, delta)
		scrollTo((self:GetVerticalScroll() or 0) - delta * 40)
	end)
	scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
	-- keep the text cursor in view while typing or pasting
	edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
		local top = -(y or 0)
		local view = scroll:GetHeight() or 0
		local current = scroll:GetVerticalScroll() or 0
		if top < current then
			scrollTo(top)
		elseif top + (height or 0) > current + view then
			scrollTo(top + (height or 0) - view)
		end
	end)

	share.message = UI.Text(share, "GameFontHighlightSmall")
	share.message:SetPoint("BOTTOMLEFT", share, "BOTTOMLEFT", 14, UI.BAR_TEXT_Y)
	share.message:SetWidth(380)

	share.action = UI.Button(share, "Import", 100, 22)
	share.action:SetPoint("BOTTOMRIGHT", share, "BOTTOMRIGHT", -10, UI.BAR_Y)
	share.action:SetScript("OnClick", function()
		if share.mode == "import" then
			local summary, problem = ns.Import(edit:GetText(), share.listName:GetText())
			if summary then
				share.message:SetText("|cff20ff20" .. summary .. "|r")
			else
				share.message:SetText("|cffff2020" .. (problem or "That did not import.") .. "|r")
			end
		else
			edit:SetFocus()
			edit:HighlightText()
		end
	end)
end

-- The text box starts lower when there are options above it.
local function placeText(top)
	share.scroll:ClearAllPoints()
	share.scroll:SetPoint("TOPLEFT", share.Inset, "TOPLEFT", 8, -top)
	share.scroll:SetPoint("BOTTOMRIGHT", share.Inset, "BOTTOMRIGHT", -8, 8)
end

--- Opens the dialog: "export" (a backup of your list), "share" (your own
--- tags for someone else, with choices), or "import" (either kind).
--- `keep` redraws a share after a choice changes without moving focus.
function ns.ShowShare(mode, keep)
	if not share then buildShare() end
	share.mode = mode
	share.message:SetText("")
	share.options:Hide()
	share.listName:Hide()
	if mode == "import" then
		share:SetTitle("Import")
		share.hint:SetText("Paste a Player Tags backup or a shared list below, then press Import. A backup merges into your list; a shared list is kept separate.")
		share.action:SetLabel("Import")
		share.listName:SetText("")
		share.listName:Show()
		placeText(34)
		share.edit:SetText("")
		share:Show()
		share.edit:SetFocus()
	elseif mode == "share" then
		local families = {}
		for _, c in ipairs(share.familyChecks) do
			if c:GetChecked() then families[c.family] = true end
		end
		local text, count = ns.ExportShare({ families = families, notes = share.notesCheck:GetChecked() })
		share:SetTitle("Share your tags")
		share.hint:SetText(count .. (count == 1 and " player. " or " players. ") .. "Only tags you made go in, never lists you were given. Copy it with Ctrl+C and give it to whoever you like.")
		share.action:SetLabel("Select all")
		share.options:Show()
		placeText(62)
		share.edit:SetText(text)
		share:Show()
		if not keep then
			share.edit:SetFocus()
			share.edit:HighlightText()
		end
	else
		local text, count = ns.Export()
		share:SetTitle("Export")
		share.hint:SetText(count .. (count == 1 and " player. " or " players. ") .. "A backup of your own list. Press Ctrl+C to copy, then paste it into a text file to keep.")
		share.action:SetLabel("Select all")
		placeText(8)
		share.edit:SetText(text)
		share:Show()
		share.edit:SetFocus()
		share.edit:HighlightText()
	end
end
