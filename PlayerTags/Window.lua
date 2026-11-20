-- Window: the main window (/tags). Three tabs: Players, Tags, Options.
-- Also the export/import dialog.
local _, ns = ...
local UI = ns.UI

local W, H = 740, 520
local TOP = 46 -- height of the title and tab strip

local frame
local pages, tabButtons = {}, {}
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
local ROW_H, VISIBLE, LIST_TOP = 26, 14, 66
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

local function refreshPlayers()
	local page = pages.players
	if not page then return end
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
			local seen = ns.Ago(rec.seen or rec.created)
			if ns.IsText(rec.seenZone) then seen = seen .. ", " .. rec.seenZone end
			row.seen:SetText(seen)
			row.note:SetText(rec.note or "")
			local confirming = players.confirm == item.key
			row.del:SetLabel(confirming and "Sure?" or "x")
			row.del:SetWidth(confirming and 46 or 20)
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
		page.thumb:SetPoint("TOPRIGHT", page, "TOPRIGHT", -6, -(LIST_TOP + y))
		page.thumb:Show()
	else
		page.thumb:Hide()
	end

	for _, chip in ipairs(page.chips) do chip:SetOn(chip.family == players.family) end
	page.sortName:SetOn(players.sort == "name")
	page.sortSeen:SetOn(players.sort == "seen")
end

local function makePlayerRow(page, index)
	local row = CreateFrame("Button", nil, page)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -(LIST_TOP + (index - 1) * ROW_H))
	row:SetPoint("RIGHT", page, "RIGHT", -16, 0)

	row.hover = row:CreateTexture(nil, "BACKGROUND")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.06)
	row.hover:Hide()

	local line = row:CreateTexture(nil, "BORDER")
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	line:SetColorTexture(0.11, 0.14, 0.18, 1)

	row.name = UI.Text(row, "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
	row.name:SetWidth(168)
	row.name:SetWordWrap(false)

	row.tags = ns.CreateBadgeRow(row, 16, 2)
	row.tags:SetPoint("LEFT", row, "LEFT", 182, 0)

	row.seen = UI.Text(row, "GameFontHighlightSmall")
	row.seen:SetPoint("LEFT", row, "LEFT", 322, 0)
	row.seen:SetWidth(150)
	row.seen:SetWordWrap(false)

	row.note = UI.Text(row, "GameFontDisableSmall")
	row.note:SetPoint("LEFT", row, "LEFT", 480, 0)
	row.note:SetPoint("RIGHT", row, "RIGHT", -56, 0)
	row.note:SetWordWrap(false)

	row.del = UI.Button(row, "x", 20, 18)
	row.del:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.del.tip = "Remove this player and their tags"
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

	row:SetScript("OnEnter", function(self) self.hover:Show() end)
	row:SetScript("OnLeave", function(self) self.hover:Hide() end)
	row:SetScript("OnClick", function(self)
		local rec = self.key and ns.GetRecord(self.key)
		if not rec then return end
		local id = ns.IdentifyName(rec.name or self.key, rec.guid)
		if id then
			id.class, id.level, id.race = rec.class, rec.level, rec.race
			ns.OpenQuickTag(id, frame)
		end
	end)
	return row
end

local function buildPlayers(page)
	page.search = UI.Edit(page, 210, 22, "Search a name, tag or note")
	page.search:SetPoint("TOPLEFT", 12, -8)
	page.search.onChange = function(self)
		players.search = ns.Trim(self:GetText())
		players.offset = 0
		refreshPlayers()
	end

	page.chips = {}
	local previous
	local function chip(label, family)
		local b = UI.Button(page, label, 8 + #label * 6.4, 22)
		b.family = family
		if previous then
			b:SetPoint("LEFT", previous, "RIGHT", 4, 0)
		else
			b:SetPoint("LEFT", page.search, "RIGHT", 10, 0)
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

	-- column headers; Player and Last seen sort the list
	local function header(label, x, sort)
		if not sort then
			local text = UI.Text(page, "GameFontDisableSmall", label)
			text:SetPoint("TOPLEFT", page, "TOPLEFT", x, -(LIST_TOP - 18))
			return text
		end
		local b = UI.Button(page, label, 8 + #label * 6.4, 18)
		b:SetPoint("TOPLEFT", page, "TOPLEFT", x - 4, -(LIST_TOP - 22))
		b.tip = "Sort by " .. label:lower()
		b:SetScript("OnClick", function()
			players.sort = sort
			players.offset = 0
			refreshPlayers()
		end)
		return b
	end
	page.sortName = header("PLAYER", 14, "name")
	header("TAGS", 190)
	page.sortSeen = header("LAST SEEN", 330, "seen")
	header("NOTE", 488)

	for i = 1, VISIBLE do players.rows[i] = makePlayerRow(page, i) end

	page.thumb = page:CreateTexture(nil, "ARTWORK")
	page.thumb:SetWidth(4)
	page.thumb:SetColorTexture(0.35, 0.40, 0.46, 1)
	page.thumb:Hide()

	page.empty = UI.Text(page, "GameFontDisable")
	page.empty:SetPoint("TOP", page, "TOP", 0, -(LIST_TOP + 60))
	page.empty:SetWidth(460)
	page.empty:SetJustifyH("CENTER")
	page.empty:Hide()

	page.count = UI.Text(page, "GameFontDisableSmall")
	page.count:SetPoint("BOTTOMLEFT", 14, 14)

	local import = UI.Button(page, "Import", 76, 22)
	import:SetPoint("BOTTOMRIGHT", -12, 10)
	import.tip = "Paste a backup made with Export."
	import:SetScript("OnClick", function() ns.ShowShare("import") end)
	local export = UI.Button(page, "Export", 76, 22)
	export:SetPoint("RIGHT", import, "LEFT", -6, 0)
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
local TAG_COLS, TAG_ROWS, CELL_W, CELL_H = 2, 17, 160, 22
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
			cell.label:SetText(tag.name .. (tag.hidden and " |cff777777(hidden)|r" or ""))
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
	for _, b in ipairs(page.familyButtons) do b:SetOn(b.family == e.family) end
	for index, b in ipairs(page.glyphButtons) do
		b.badge:SetGlyph(index - 1, family.r, family.g, family.b)
		b.badge:SetDim(index - 1 ~= e.glyph)
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
		page.nameEdit:Refresh()
		page.message:SetText("")
	end
	refreshTags()
end

local function buildTags(page)
	local hint = UI.Text(page, "GameFontDisableSmall", "Click a tag to edit it. Hidden tags stay on players but leave the tagging popup.")
	hint:SetPoint("TOPLEFT", 12, -10)

	for i = 1, TAG_COLS * TAG_ROWS do
		local col = (i - 1) % TAG_COLS
		local row = math.floor((i - 1) / TAG_COLS)
		local cell = UI.Button(page, "", CELL_W, CELL_H)
		cell:SetPoint("TOPLEFT", page, "TOPLEFT", 12 + col * (CELL_W + 4), -(32 + row * (CELL_H + 2)))
		cell.badge = ns.CreateBadge(cell, 16)
		cell.badge:SetPoint("LEFT", cell, "LEFT", 4, 0)
		cell.label:ClearAllPoints()
		cell.label:SetPoint("LEFT", cell.badge, "RIGHT", 6, 0)
		cell.label:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
		cell.label:SetJustifyH("LEFT")
		cell.label:SetWordWrap(false)
		cell:SetScript("OnClick", function(self)
			if self.tag then editTag(ns.GetTag(self.tag.id)) end
		end)
		tagsPage.cells[i] = cell
	end
	page:EnableMouseWheel(true)
	page:SetScript("OnMouseWheel", function(_, delta)
		tagsPage.offset = tagsPage.offset - delta
		refreshTags()
	end)

	-- editor
	local X = 360
	page.editorTitle = UI.Text(page, "GameFontNormal", "New tag")
	page.editorTitle:SetPoint("TOPLEFT", X, -32)

	local nameLabel = UI.Text(page, "GameFontDisableSmall", "NAME")
	nameLabel:SetPoint("TOPLEFT", X, -58)
	page.nameEdit = UI.Edit(page, 220, 22, "Tag name")
	page.nameEdit:SetPoint("TOPLEFT", X, -72)
	page.nameEdit:SetMaxLetters(24)
	page.nameEdit.onChange = function(self)
		if tagsPage.editing then tagsPage.editing.name = self:GetText() end
	end

	local familyLabel = UI.Text(page, "GameFontDisableSmall", "FAMILY")
	familyLabel:SetPoint("TOPLEFT", X, -106)
	page.familyButtons = {}
	for i, family in ipairs(ns.FAMILIES) do
		local b = UI.Button(page, family.name, 86, 22)
		b.family = family.id
		b:SetPoint("TOPLEFT", page, "TOPLEFT", X + (i - 1) * 90, -120)
		b:SetScript("OnClick", function()
			if not tagsPage.editing then return end
			tagsPage.editing.family = family.id
			paintEditor()
		end)
		page.familyButtons[i] = b
	end

	local glyphLabel = UI.Text(page, "GameFontDisableSmall", "PICTURE")
	glyphLabel:SetPoint("TOPLEFT", X, -154)
	page.glyphButtons = {}
	for index = 0, ns.GLYPH_COUNT - 1 do
		local col, row = index % 8, math.floor(index / 8)
		local b = UI.Button(page, "", 32, 32)
		b:SetPoint("TOPLEFT", page, "TOPLEFT", X + col * 36, -(168 + row * 36))
		b.badge = ns.CreateBadge(b, 24)
		b.badge:SetPoint("CENTER")
		b:SetScript("OnClick", function()
			if not tagsPage.editing then return end
			tagsPage.editing.glyph = index
			paintEditor()
		end)
		page.glyphButtons[index + 1] = b
	end

	page.showCheck = UI.Check(page, "Show in the tagging popup")
	page.showCheck:SetPoint("TOPLEFT", X, -322)
	page.showCheck.onChange = function(checked)
		if tagsPage.editing then tagsPage.editing.hidden = not checked end
	end

	local save = UI.Button(page, "Save", 86, 24)
	save:SetPoint("TOPLEFT", X, -356)
	save:SetScript("OnClick", function()
		local e = tagsPage.editing
		if not e then return end
		e.name = page.nameEdit:GetText()
		page.nameEdit:ClearFocus()
		local id, problem = ns.SaveTag(e.id, e)
		if not id then
			page.message:SetText("|cffff5a52" .. (problem or "That did not save.") .. "|r")
			return
		end
		ns.SetTagHidden(id, e.hidden)
		editTag(ns.GetTag(id))
		page.message:SetText("|cff4bdb69Saved.|r")
	end)

	local new = UI.Button(page, "New tag", 86, 24)
	new:SetPoint("LEFT", save, "RIGHT", 6, 0)
	new:SetScript("OnClick", function() editTag(nil) end)

	page.third = UI.Button(page, "Delete", 86, 24)
	page.third:SetPoint("LEFT", new, "RIGHT", 6, 0)
	page.third:SetScript("OnClick", function()
		local e = tagsPage.editing
		if not e or not e.id then return end
		if e.builtin then
			ns.ResetTag(e.id)
			ns.SetTagHidden(e.id, false)
			editTag(ns.GetTag(e.id))
			page.message:SetText("|cff4bdb69Back to the original.|r")
			return
		end
		if not tagsPage.deleteArmed then
			tagsPage.deleteArmed = true
			paintEditor()
			return
		end
		ns.DeleteTag(e.id)
		editTag(nil)
		page.message:SetText("|cff4bdb69Deleted.|r")
	end)

	page.message = UI.Text(page, "GameFontHighlightSmall")
	page.message:SetPoint("TOPLEFT", X, -390)
	page.message:SetWidth(340)

	editTag(nil)
end

refreshers.tags = refreshTags

---------------------------------------------------------------------------
-- Options tab
---------------------------------------------------------------------------
local CHECKS = {
	{ key = "nameplates", label = "Tag icons on nameplates",
		help = "Enemy players, and friendly players if they have nameplates." },
	{ key = "friendly", label = "Give friendly players nameplates",
		help = "Changes every friendly player's name into nameplate text." },
	{ key = "tooltip", label = "Tags and notes in tooltips" },
	{ key = "chat", label = "Tag icons in chat",
		help = "Not inside dungeons and raids, where the game hides who is speaking." },
	{ key = "frames", label = "Tag icons on target, party and raid frames" },
	{ key = "groupAlert", label = "Tell me when tagged players are in my group" },
	{ key = "alertSound", label = "Play a sound when one of them is tagged Avoid" },
	{ key = "finder", label = "Marks on Group Finder listings" },
	{ key = "menu", label = "\"Tag player\" in right-click menus" },
	{ key = "minimap", label = "Button on the minimap" },
	{ key = "popupAtCursor", label = "Open the tagging popup at the mouse pointer",
		help = "Otherwise it opens mid-screen, or where you last dragged it." },
}

local function refreshOptions()
	local page = pages.options
	if not page then return end
	for _, check in ipairs(page.checks) do
		if check.key == "friendly" then
			check:SetChecked(ns.settings.friendlyPlates == "on")
		else
			check:SetChecked(ns.settings[check.key] == true)
		end
	end
	for _, b in ipairs(page.sizeButtons) do b:SetOn(ns.settings.plateSize == b.value) end
	for _, b in ipairs(page.maxButtons) do b:SetOn(ns.settings.plateMax == b.value) end

	local lines = {}
	for _, name in ipairs(ns.moduleOrder) do
		local state = ns.moduleState[name] or "?"
		local color = (state:sub(1, 2) == "ok") and "|cff4bdb69" or "|cffff5a52"
		lines[#lines + 1] = name .. ": " .. color .. state .. "|r"
	end
	lines[#lines + 1] = " "
	if #ns.errors == 0 then
		lines[#lines + 1] = "Problems: |cff4bdb69none|r"
	else
		lines[#lines + 1] = "|cffff5a52Problems: " .. #ns.errors .. "|r. Type /tags status to list them."
	end
	page.status:SetText(table.concat(lines, "\n"))
end

local function buildOptions(page)
	page.checks = {}
	local y = 12
	for i, def in ipairs(CHECKS) do
		local check = UI.Check(page, def.label, def.help)
		check.key = def.key
		check:SetPoint("TOPLEFT", 14, -y)
		y = y + (def.help and 42 or 26)
		check.onChange = function(checked)
			if def.key == "friendly" then
				ns.settings.friendlyPlates = checked and "on" or "off"
				ns.ApplyFriendlyPlates()
			else
				ns.settings[def.key] = checked
			end
			ns.Fire("SETTINGS_CHANGED")
		end
		page.checks[i] = check
	end

	local function choice(label, top, key, options, store)
		local text = UI.Text(page, "GameFontHighlightSmall", label)
		text:SetPoint("TOPLEFT", 14, -top - 5)
		for i, option in ipairs(options) do
			local b = UI.Button(page, option[1], 70, 22)
			b.value = option[2]
			b:SetPoint("TOPLEFT", page, "TOPLEFT", 200 + (i - 1) * 74, -top)
			b:SetScript("OnClick", function()
				ns.settings[key] = option[2]
				ns.Fire("SETTINGS_CHANGED")
				refreshOptions()
			end)
			store[i] = b
		end
	end
	page.sizeButtons, page.maxButtons = {}, {}
	y = y + 8
	choice("Icon size on nameplates", y, "plateSize", { { "Small", 14 }, { "Medium", 17 }, { "Large", 21 } }, page.sizeButtons)
	choice("Most icons on a nameplate", y + 30, "plateMax", { { "2", 2 }, { "3", 3 }, { "4", 4 } }, page.maxButtons)

	local statusTitle = UI.Text(page, "GameFontNormal", "Status")
	statusTitle:SetPoint("TOPLEFT", 440, -12)
	page.status = UI.Text(page, "GameFontHighlightSmall")
	page.status:SetPoint("TOPLEFT", statusTitle, "BOTTOMLEFT", 0, -8)
	page.status:SetWidth(280)
	page.status:SetJustifyV("TOP")
	if page.status.SetSpacing then page.status:SetSpacing(3) end

	-- Sits under the status list, which grows and shrinks.
	local keys = UI.Text(page, "GameFontDisableSmall",
		"Set your tagging key under Options > Keybindings > AddOns > Player Tags.\n\n"
		.. "Without a key, target a player and type /tag.\n\n"
		.. "Everything you tag is stored on this computer only.")
	keys:SetPoint("TOPLEFT", page.status, "BOTTOMLEFT", 0, -22)
	keys:SetWidth(280)
	keys:SetJustifyV("TOP")
	if keys.SetSpacing then keys:SetSpacing(2) end
end

refreshers.options = refreshOptions

---------------------------------------------------------------------------
-- Window shell
---------------------------------------------------------------------------
local TABS = {
	{ id = "players", label = "Players", build = buildPlayers },
	{ id = "tags", label = "Tags", build = buildTags },
	{ id = "options", label = "Options", build = buildOptions },
}

local function selectTab(id)
	currentTab = id
	for _, tab in ipairs(TABS) do
		local page = pages[tab.id]
		if tab.id == id then page:Show() else page:Hide() end
		tabButtons[tab.id]:SetOn(tab.id == id)
	end
	players.confirm = nil
	refreshers[id]()
end

local function build()
	frame = UI.Panel("PlayerTagsFrame")
	frame:SetFrameStrata("HIGH")
	frame:SetSize(W, H)
	UI.Movable(frame, "window")
	UI.Place(frame, "window")
	frame:Hide()
	table.insert(UISpecialFrames, "PlayerTagsFrame")

	local title = UI.Text(frame, "GameFontNormalLarge", "Player Tags")
	title:SetPoint("TOPLEFT", 14, -14)

	local close = UI.Button(frame, "x", 22, 22)
	close:SetPoint("TOPRIGHT", -10, -10)
	close:SetScript("OnClick", function() frame:Hide() end)

	local rule = frame:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 1, -TOP)
	rule:SetPoint("TOPRIGHT", -1, -TOP)
	rule:SetHeight(1)
	rule:SetColorTexture(0.17, 0.20, 0.25, 1)

	for i, tab in ipairs(TABS) do
		local b = UI.Button(frame, tab.label, 84, 24)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", 150 + (i - 1) * 88, -12)
		b:SetScript("OnClick", function() selectTab(tab.id) end)
		tabButtons[tab.id] = b

		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TOP)
		page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		page:Hide()
		pages[tab.id] = page
		tab.build(page)
	end

	frame:SetScript("OnShow", function() selectTab(currentTab) end)
	frame:SetScript("OnHide", function()
		players.confirm = nil
		ns.CloseQuickTag()
	end)
end

--- Opens the window on a tab ("players", "tags", "options"), optionally
--- with the player search filled in.
function ns.ShowWindow(tab, search)
	if not frame then build() end
	if tab and pages[tab] then currentTab = tab end
	if search and pages.players then
		players.search = ns.Trim(search)
		players.offset = 0
		pages.players.search:SetText(players.search)
		pages.players.search:Refresh()
	end
	if frame:IsShown() then selectTab(currentTab) else frame:Show() end
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
ns.Listen("SETTINGS_CHANGED", refreshIfOpen, "window")
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
	share = UI.Panel("PlayerTagsShare")
	share:SetFrameStrata("DIALOG")
	share:SetSize(520, 380)
	share:SetPoint("CENTER")
	share:Hide()
	UI.Movable(share)
	table.insert(UISpecialFrames, "PlayerTagsShare")

	share.title = UI.Text(share, "GameFontNormalLarge", "Export")
	share.title:SetPoint("TOPLEFT", 14, -14)
	share.hint = UI.Text(share, "GameFontDisableSmall")
	share.hint:SetPoint("TOPLEFT", share.title, "BOTTOMLEFT", 0, -6)
	share.hint:SetWidth(490)

	local close = UI.Button(share, "x", 22, 22)
	close:SetPoint("TOPRIGHT", -10, -10)
	close:SetScript("OnClick", function() share:Hide() end)

	local box = CreateFrame("Frame", nil, share)
	box:SetPoint("TOPLEFT", 14, -62)
	box:SetPoint("BOTTOMRIGHT", -14, 46)
	UI.Fill(box, 0.03, 0.04, 0.055, 1)
	UI.Edges(box, 0.17, 0.20, 0.25, 1)

	local scroll = CreateFrame("ScrollFrame", nil, box)
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -6, 6)
	scroll:EnableMouse(true)
	scroll:EnableMouseWheel(true)

	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(GameFontHighlightSmall)
	edit:SetWidth(476)
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
	share.message:SetPoint("BOTTOMLEFT", 14, 16)
	share.message:SetWidth(380)

	share.action = UI.Button(share, "Import", 100, 24)
	share.action:SetPoint("BOTTOMRIGHT", -14, 12)
	share.action:SetScript("OnClick", function()
		if share.mode == "import" then
			local summary, problem = ns.Import(edit:GetText())
			if summary then
				share.message:SetText("|cff4bdb69" .. summary .. "|r")
			else
				share.message:SetText("|cffff5a52" .. (problem or "That did not import.") .. "|r")
			end
		else
			edit:SetFocus()
			edit:HighlightText()
		end
	end)
end

--- Opens the export or import dialog.
function ns.ShowShare(mode)
	if not share then buildShare() end
	share.mode = mode
	share.message:SetText("")
	if mode == "import" then
		share.title:SetText("Import")
		share.hint:SetText("Paste a Player Tags export below, then press Import. Your own tags and notes are kept; only what is missing gets added.")
		share.action:SetLabel("Import")
		share.edit:SetText("")
		share:Show()
		share.edit:SetFocus()
	else
		local text, count = ns.Export()
		share.title:SetText("Export")
		share.hint:SetText(count .. (count == 1 and " player. " or " players. ") .. "Press Ctrl+C to copy, then paste it into a text file to keep.")
		share.action:SetLabel("Select all")
		share.edit:SetText(text)
		share:Show()
		share.edit:SetFocus()
		share.edit:HighlightText()
	end
end
