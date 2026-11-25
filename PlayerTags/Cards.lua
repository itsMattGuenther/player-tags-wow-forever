-- Cards: small windows that offer to tag a handful of players at once.
--   * After a group: everyone who was in it, including anyone who left
--     early, with your most-used tags as buttons.
--   * After a death in world PvP: the enemy players who were around you
--     in the last 30 seconds, with Ganker, Griefer, Rival and PvP God.
-- Each row also has a More button that opens the full tagging popup.
local _, ns = ...
local UI = ns.UI

local ROWS, ICON, ROW_H, WIDTH = 8, 22, 30, 480
local DEFAULT_GOOD = { "helpful", "company", "patient", "reliable" }
local DEFAULT_AVOID = { "leaver", "rude", "ninja" }
local GAP = 10 -- space between groups of buttons

-- The roles each class can play, as the Skilled tags for them. A Hunter
-- is never offered Great Healer; a Paladin or Druid gets all three.
local ROLE_TAGS = { tank = true, healer = true, damage = true }
local ROLES_BY_CLASS = {
	WARRIOR = { "tank", "damage" },
	PALADIN = { "tank", "healer", "damage" },
	DRUID = { "tank", "healer", "damage" },
	PRIEST = { "healer", "damage" },
	SHAMAN = { "healer", "damage" },
	HUNTER = { "damage" }, ROGUE = { "damage" }, MAGE = { "damage" }, WARLOCK = { "damage" },
}
local ALL_ROLES = { "tank", "healer", "damage" }
local KILLER_TAGS = { "ganker", "griefer", "rival", "pvp" }

---------------------------------------------------------------------------
-- The card window
---------------------------------------------------------------------------
local cards = {}

local function makeCard(name, title, key, defaultY)
	local card = UI.Window(name, title, WIDTH, 200)
	card:SetFrameStrata("DIALOG")
	card:Hide()
	UI.Movable(card, key, 0, defaultY)
	UI.Place(card, key, 0, defaultY)
	table.insert(UISpecialFrames, name)
	card.positionKey, card.defaultY = key, defaultY

	card.sub = UI.Text(card, "GameFontHighlightSmall")
	card.sub:SetPoint("TOPLEFT", card, "TOPLEFT", 64, -34)
	card.sub:SetPoint("RIGHT", card, "RIGHT", -10, 0)
	card.sub:SetWordWrap(false)

	card.more = UI.Text(card, "GameFontDisableSmall")
	card.hint = UI.Text(card, "GameFontDisableSmall", "Click a tag to add it. Esc closes.")
	card.hint:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 14, UI.BAR_TEXT_Y)
	card.done = UI.Button(card, "Done", 90, 22)
	card.done:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, UI.BAR_Y)
	card.done:SetScript("OnClick", function() card:Hide() end)

	card.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, card)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", card.Inset, "TOPLEFT", 8, -(6 + (i - 1) * ROW_H))
		row:SetPoint("RIGHT", card.Inset, "RIGHT", -8, 0)
		row.name = UI.Text(row, "GameFontHighlight")
		row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.name:SetWidth(150)
		row.name:SetWordWrap(false)
		row.buttons = {}
		row.open = UI.Button(row, "More", 56, 20, true)
		row.open:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.open.tip = "Open the full tagging popup for this player."
		card.rows[i] = row
	end
	cards[#cards + 1] = card
	return card
end

-- The state of one row's buttons from your list (or the card's own memory
-- when it is a test with made-up players).
local function paintRow(card, row)
	if not row.id then return end
	local rec = not card.test and ns.Lookup(row.id) or nil
	for _, b in ipairs(row.buttons) do
		if b:IsShown() then
			local on
			if card.test then on = row.testTags[b.tagId] == true else on = rec ~= nil and rec.tags[b.tagId] ~= nil end
			b:SetOn(on)
		end
	end
end

local function paint(card)
	for _, row in ipairs(card.rows) do
		if row:IsShown() then paintRow(card, row) end
	end
end

--- Fills a card. `players` is a list of identities (key, name, guid,
--- class...). `columns` is the tag ids in fixed columns, with false for a
--- small gap between groups, so the same tag lines up on every row.
--- `allowed(id, tagId)`, when given, leaves a column empty for a player
--- (a Hunter has no Great Healer button). `test` makes nothing stick.
local function fill(card, subtitle, players, columns, test, allowed)
	card.test = test
	card.sub:SetText(subtitle or "")
	local shown = math.min(#players, ROWS)
	for i, row in ipairs(card.rows) do
		local id = players[i]
		if i <= shown and id then
			row.id = id
			row.testTags = {}
			row.name:SetText(ns.ClassColorCode(id.class) .. (id.name or "?") .. "|r")
			local x, j = 160, 0
			for _, tagId in ipairs(columns) do
				if not tagId then
					x = x + GAP
				else
				j = j + 1
				local b = row.buttons[j]
				if not b then
					b = UI.IconToggle(row, ICON)
					b:SetSize(ICON, ICON)
					b:SetScript("OnClick", function(self)
						UI.Click()
						if card.test then
							row.testTags[self.tagId] = not row.testTags[self.tagId] or nil
						else
							ns.ToggleTag(row.id, self.tagId)
						end
						paintRow(card, row)
					end)
					b:HookScript("OnEnter", function(self)
						local tag = ns.GetTag(self.tagId)
						if not tag then return end
						GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
						GameTooltip:SetText(tag.name, ns.TagColor(self.tagId))
						GameTooltip:Show()
					end)
					b:HookScript("OnLeave", function() GameTooltip:Hide() end)
					row.buttons[j] = b
				end
				b.tagId = tagId
				b.badge:SetTag(tagId)
				b:ClearAllPoints()
				b:SetPoint("LEFT", row, "LEFT", x, 0)
				if ns.GetTag(tagId) and (not allowed or allowed(id, tagId)) then b:Show() else b:Hide() end
				x = x + ICON + 6
				end
			end
			for k = j + 1, #row.buttons do row.buttons[k]:Hide() end
			-- In a test the full popup would save a real record for a
			-- made-up player, so More is greyed out there.
			row.open:SetEnabled(not card.test)
			row.open.tip = card.test and "Not available in the test: it would save a made-up player."
				or "Open the full tagging popup for this player."
			row.open:SetScript("OnClick", function()
				if card.test then return end
				ns.OpenQuickTag(row.id, card)
			end)
			row:Show()
		else
			row.id = nil
			row:Hide()
		end
	end
	local height = 60 + shown * ROW_H + 12 + UI.BAR
	if #players > shown then
		card.more:ClearAllPoints()
		card.more:SetPoint("TOPLEFT", card.Inset, "TOPLEFT", 12, -(8 + shown * ROW_H))
		card.more:SetText("and " .. (#players - shown) .. " more. Find them in the game's Recent Allies list.")
		card.more:Show()
		height = height + 16
	else
		card.more:Hide()
	end
	card:SetHeight(height)
	UI.ApplyScale(card)
	paint(card)
	card:Show()
	card:Raise()
end

ns.Listen("RECORD_CHANGED", function()
	for _, card in ipairs(cards) do
		if card:IsShown() then paint(card) end
	end
end, "cards")

ns.Listen("SETTINGS_CHANGED", function()
	for _, card in ipairs(cards) do UI.ApplyScale(card) end
end, "cards")

--- Your most-used tags of one kind, for the after-group buttons: "good"
--- (anything that is not a role and not Avoid) or "avoid". Filled up from
--- sensible defaults when you have not used enough yet.
function ns.FavouriteTags(n, kind)
	n = n or 2
	local function fits(tagId)
		local tag = ns.GetTag(tagId)
		if not tag or ROLE_TAGS[tagId] then return false end
		if kind == "avoid" then return tag.family == "avoid" end
		return tag.family ~= "avoid" and tagId ~= "lowskill"
	end
	local counts = {}
	for _, rec in pairs(ns.db.players) do
		for tagId in pairs(rec.tags) do
			if fits(tagId) then counts[tagId] = (counts[tagId] or 0) + 1 end
		end
	end
	local ids = {}
	for tagId in pairs(counts) do ids[#ids + 1] = tagId end
	table.sort(ids, function(a, b)
		if counts[a] ~= counts[b] then return counts[a] > counts[b] end
		return a < b
	end)
	local picked, seen = {}, {}
	for _, tagId in ipairs(ids) do
		if #picked >= n then break end
		picked[#picked + 1] = tagId
		seen[tagId] = true
	end
	for _, tagId in ipairs(kind == "avoid" and DEFAULT_AVOID or DEFAULT_GOOD) do
		if #picked >= n then break end
		if not seen[tagId] and fits(tagId) then picked[#picked + 1] = tagId end
	end
	ns.SortTagIds(picked)
	return picked
end

--- The after-group columns: the three roles, then your two most-used good
--- tags, then the negatives: Low Skill and your two most-used Avoid tags.
function ns.GroupCardColumns()
	local columns = { "tank", "healer", "damage", false }
	for _, tagId in ipairs(ns.FavouriteTags(2, "good")) do columns[#columns + 1] = tagId end
	columns[#columns + 1] = false
	columns[#columns + 1] = "lowskill"
	for _, tagId in ipairs(ns.FavouriteTags(2, "avoid")) do columns[#columns + 1] = tagId end
	return columns
end

-- Role buttons only for roles the player's class can play.
local function roleAllowed(id, tagId)
	if not ROLE_TAGS[tagId] then return true end
	local roles = ROLES_BY_CLASS[id and id.class or ""]
	if not roles then return true end
	for _, role in ipairs(roles) do
		if role == tagId then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- After a group
---------------------------------------------------------------------------
local MIN_GROUP_TIME = 5 * 60
local runCard
local roster, rosterOrder = {}, {}
local groupSince, wasInDungeon, dungeonName, wasInPvP = nil, false, nil, false
local pendingCard = nil

local function groupUnits()
	local units = {}
	if IsInRaid() then
		local count = ns.Num(GetNumGroupMembers()) or 0
		for i = 1, count do units[#units + 1] = "raid" .. i end
	else
		for i = 1, 4 do units[#units + 1] = "party" .. i end
	end
	return units
end

local function noteRoster()
	if not IsInGroup() then return end
	groupSince = groupSince or GetTime()
	local ok, inside, kind = pcall(IsInInstance)
	if ok and inside == true and (kind == "pvp" or kind == "arena") then wasInPvP = true end
	if ok and inside == true and (kind == "party" or kind == "raid") then
		wasInDungeon = true
		local zone = GetRealZoneText and GetRealZoneText()
		if ns.IsText(zone) then dungeonName = zone end
	end
	for _, unit in ipairs(groupUnits()) do
		local id = ns.IdentifyUnit(unit)
		if id and not ns.IsMe(id) and not roster[id.key] then
			roster[id.key] = { key = id.key, name = id.name, guid = id.guid, class = id.class, level = id.level, race = id.race }
			rosterOrder[#rosterOrder + 1] = id.key
		end
	end
end

local function showRunCard(players, subtitle, test)
	if not runCard then runCard = makeCard("PlayerTagsRunCard", "Tag your group?", "runcard", 120) end
	fill(runCard, subtitle, players, ns.GroupCardColumns(), test, roleAllowed)
end

local function groupEnded()
	local players = {}
	for _, key in ipairs(rosterOrder) do players[#players + 1] = roster[key] end
	local minutes = groupSince and math.floor((GetTime() - groupSince) / 60 + 0.5) or 0
	local long = groupSince and (GetTime() - groupSince) >= MIN_GROUP_TIME
	local choice = ns.settings.runCard
	local subtitle = (wasInDungeon and dungeonName or "Your group") .. " · " .. minutes .. " min"
	-- Battleground and arena groups are strangers by design; no card there.
	if #players > 0 and long and not wasInPvP and choice ~= "off" and (choice ~= "dungeons" or wasInDungeon) then
		if InCombatLockdown() then
			pendingCard = { players = players, subtitle = subtitle }
		else
			showRunCard(players, subtitle)
		end
	end
	roster, rosterOrder, groupSince, wasInDungeon, dungeonName, wasInPvP = {}, {}, nil, false, nil, false
end

---------------------------------------------------------------------------
-- After a death in world PvP
---------------------------------------------------------------------------
local RECENT = 30
local killerCard
local recentEnemies = {} -- GUID -> { id, t }

local function noteEnemy(unit)
	if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return end
	local ok, isPlayer, enemy = pcall(function() return UnitIsPlayer(unit), UnitIsEnemy("player", unit) end)
	if not ok or isPlayer ~= true or enemy ~= true then return end
	local id = ns.IdentifyUnit(unit)
	if id and id.guid then recentEnemies[id.guid] = { id = id, t = GetTime() } end
end

local function showKillerCard(players, test)
	if not killerCard then killerCard = makeCard("PlayerTagsKillerCard", "Tag who was around?", "killercard", -120) end
	fill(killerCard, "Enemy players near you in the last " .. RECENT .. " seconds", players, KILLER_TAGS, test)
	-- Under the game's "Release spirit" box when it is showing.
	local death = type(_G.StaticPopup_FindVisible) == "function" and _G.StaticPopup_FindVisible("DEATH")
	if death and not test then
		killerCard:ClearAllPoints()
		killerCard:SetPoint("TOP", death, "BOTTOM", 0, -40)
	else
		UI.Place(killerCard, "killercard", 0, -120)
	end
end

local function onDeath()
	if not ns.settings.killerCard then return end
	local ok, inside = pcall(IsInInstance)
	if ok and inside == true then return end
	local now, list = GetTime(), {}
	for guid, seen in pairs(recentEnemies) do
		if now - seen.t <= RECENT then list[#list + 1] = seen else recentEnemies[guid] = nil end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	local players = {}
	for i = 1, math.min(#list, ROWS) do players[i] = list[i].id end
	if #players == 0 then return end
	C_Timer.After(0.3, function() ns.Safe("killer card", showKillerCard, players) end)
end

---------------------------------------------------------------------------
-- Test versions, with made-up players, for /tags test
---------------------------------------------------------------------------
function ns.TestRunCard()
	showRunCard({
		{ key = "lysa thornfield", name = "Lysa Thornfield", class = "PRIEST" },
		{ key = "bramm coppervein", name = "Bramm Coppervein", class = "WARRIOR" },
		{ key = "kael morrow", name = "Kael Morrow", class = "MAGE" },
		{ key = "jory pell", name = "Jory Pell", class = "HUNTER" },
	}, "The Deadmines · 42 min", true)
end

function ns.TestKillerCard()
	showKillerCard({
		{ key = "shade vexmoor", name = "Shade Vexmoor", class = "ROGUE" },
		{ key = "toruk blackhoof", name = "Toruk Blackhoof", class = "HUNTER" },
	}, true)
end

ns.Module("cards", function()
	ns.On("GROUP_ROSTER_UPDATE", function()
		if IsInGroup() then ns.Safe("group card", noteRoster) elseif groupSince then ns.Safe("group card", groupEnded) end
	end, "cards")
	ns.On("GROUP_LEFT", function() if groupSince then ns.Safe("group card", groupEnded) end end, "cards")
	ns.On("PLAYER_ENTERING_WORLD", function() ns.Safe("group card", noteRoster) end, "cards")
	ns.On("PLAYER_REGEN_ENABLED", function()
		if pendingCard then
			local card = pendingCard
			pendingCard = nil
			ns.Safe("group card", showRunCard, card.players, card.subtitle)
		end
	end, "cards")

	ns.On("NAME_PLATE_UNIT_ADDED", function(unit) ns.Safe("killer card", noteEnemy, unit) end, "cards")
	ns.On("UPDATE_MOUSEOVER_UNIT", function() ns.Safe("killer card", noteEnemy, "mouseover") end, "cards")
	ns.On("PLAYER_TARGET_CHANGED", function() ns.Safe("killer card", noteEnemy, "target") end, "cards")
	ns.On("PLAYER_DEAD", function() ns.Safe("killer card", onDeath) end, "cards")
	ns.On("PLAYER_UNGHOST", function() if killerCard then killerCard:Hide() end end, "cards")
end)
