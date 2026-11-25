-- Offline checks. Run from the project root:  lua5.1 tests/run.lua
package.path = "tests/?.lua;" .. package.path
local H = require("harness")
local world = H.world

local passed, failed = 0, 0
local function check(name, condition, detail)
	if condition then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL  " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
	end
end
local function section(name) print("-- " .. name) end
local function chatHas(text)
	for _, line in ipairs(world.chat) do
		if line:find(text, 1, true) then return true end
	end
	return false
end

H.install()
world.cvars.nameplateShowFriendlyPlayers = "0"
world.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits = "0"
world.units.player = { name = "Matt", surname = "Tester", guid = "Player-1-ME", class = "MAGE", level = 30 }

local ns, files = H.load("PlayerTags")
local GORRIM = { name = "Gorrim", surname = "Ashmantle", guid = "Player-1-GORRIM", class = "WARRIOR", level = 34, race = "Dwarf", faction = "Alliance" }
local TESSA = { name = "Tessa", surname = "Brightwell", guid = "Player-1-TESSA", class = "MAGE", level = 31, race = "Skyborne", faction = "Alliance" }
local VELRA = { name = "Velra", surname = "Duskwhisper", guid = "Player-1-VELRA", class = "ROGUE", level = 36, race = "Orc", faction = "Horde" }

section("startup")
check("all files listed in the toc load", #files == 23, #files)
H.fire("ADDON_LOADED", "PlayerTags")
H.fire("PLAYER_LOGIN")
check("database created", type(PlayerTagsDB) == "table" and type(PlayerTagsDB.players) == "table")
check("knows who I am", ns.me == "Matt Tester", ns.me)
for _, name in ipairs(ns.moduleOrder) do
	check("module " .. name .. " is running", (ns.moduleState[name] or ""):sub(1, 2) == "ok", ns.moduleState[name])
end
check("every surface registered", #ns.moduleOrder == 11, #ns.moduleOrder)
check("slash commands registered", SLASH_PLAYERTAGS1 == "/tags" and SLASH_PLAYERTAGSTAG1 == "/tag" and type(SlashCmdList.PLAYERTAGS) == "function")
check("key binding functions exist", type(PlayerTags_QuickTag) == "function" and type(PlayerTags_ToggleWindow) == "function")

section("tags")
check("22 starter tags", #ns.AllTags(true) == 22, #ns.AllTags(true))
check("every starter tag has a valid family and glyph", (function()
	local seen = {}
	for _, tag in ipairs(ns.AllTags(true)) do
		if not ns.familyById[tag.family] or tag.glyph < 0 or tag.glyph > 31 or seen[tag.glyph] then return false end
		seen[tag.glyph] = true
	end
	return true
end)())
check("find tag by name", ns.FindTag("Great Tank") == "tank")
check("find tag ignores case and spaces", ns.FindTag("ninjalooter") == "ninja" and ns.FindTag("PVP GOD") == "pvp")
check("find tag by unique prefix", ns.FindTag("rud") == "rude")
check("ambiguous prefix finds nothing", ns.FindTag("g") == nil)
check("unknown tag finds nothing", ns.FindTag("wizard") == nil)

section("identity")
check("space and hyphen names share a key", ns.Key("Gorrim Ashmantle") == ns.Key("gorrim-ashmantle"))
check("key trims and lowercases", ns.Key("  Tessa  Brightwell ") == "tessa brightwell")
world.units.target = GORRIM
local gorrim = ns.IdentifyUnit("target")
check("identify a player unit", gorrim and gorrim.key == "gorrim ashmantle" and gorrim.name == "Gorrim Ashmantle" and gorrim.class == "WARRIOR")
world.units.mouseover = { name = "Stormwind Guard", npc = true }
check("an NPC is not a player", ns.IdentifyUnit("mouseover") == nil)
check("a missing unit is nobody", ns.IdentifyUnit("focus") == nil)
world.units.focus = { name = H.SECRET, guid = H.SECRET }
check("a hidden name is nobody, without an error", ns.IdentifyUnit("focus") == nil)
check("a hidden unit token is nobody", ns.IdentifyUnit(H.SECRET) == nil)
world.units.focus = nil
check("I am recognised as me", ns.IsMe(ns.IdentifyUnit("player")))

section("tagging")
check("tag a player", ns.SetTag(gorrim, "tank", true) == true)
check("tagging twice changes nothing", ns.SetTag(gorrim, "tank", true) == false)
ns.SetTag(gorrim, "rude", true)
local rec = ns.GetRecord("gorrim ashmantle")
check("record stored with facts", rec and rec.class == "WARRIOR" and rec.level == 34 and rec.guid == "Player-1-GORRIM")
check("tag remembers where and who", rec.tags.tank.zone == "Riverglades" and rec.tags.tank.by == "Matt Tester")
local ids = ns.TagIds(rec)
check("Avoid tags sort first", ids[1] == "rude" and ids[2] == "tank", table.concat(ids, ","))
check("unknown tag refused", ns.SetTag(gorrim, "nope", true) == false)
ns.SetNote(gorrim, "  Held four packs.  ")
check("note trimmed and saved", rec.note == "Held four packs.")
check("toggle turns a tag off", ns.ToggleTag(gorrim, "rude") == false and rec.tags.rude == nil)
check("toggle turns it back on", ns.ToggleTag(gorrim, "rude") == true and rec.tags.rude ~= nil)
check("lookup by guid alone", ns.GetRecordByGUID("Player-1-GORRIM") == rec)

section("rename follows the GUID")
world.units.target = { name = "Gorrim", surname = "Ironmantle", guid = "Player-1-GORRIM", class = "WARRIOR", level = 35 }
local renamed = ns.IdentifyUnit("target")
local found, key = ns.Lookup(renamed)
check("record found under the new name", found == rec and key == "gorrim ironmantle", key)
check("old key is gone", ns.GetRecord("gorrim ashmantle") == nil)
check("former name kept", rec.formerName == "Gorrim Ashmantle" and rec.name == "Gorrim Ironmantle")
world.units.target = GORRIM
ns.Lookup(ns.IdentifyUnit("target")) -- rename back for the rest of the checks
rec = ns.GetRecord("gorrim ashmantle")
check("renamed back", rec ~= nil)

section("pruning")
world.units.target = TESSA
local tessa = ns.IdentifyUnit("target")
ns.SetTag(tessa, "helpful", true)
ns.SetTag(tessa, "helpful", false)
check("a record with nothing left is removed", ns.GetRecord("tessa brightwell") == nil and ns.GetRecordByGUID("Player-1-TESSA") == nil)
ns.SetNote(tessa, "note only")
check("a note alone keeps a record", ns.GetRecord("tessa brightwell") ~= nil)
ns.SetNote(tessa, "")
check("clearing the note removes it", ns.GetRecord("tessa brightwell") == nil)
ns.SetTag(tessa, "helpful", true)
ns.SetTag(tessa, "generous", true)

section("chat")
local filter = H.senderFilters[1]
check("chat filter registered", type(filter) == "function")
local function chatArgs(sender, guid)
	return "hello", sender, "", "", "", "", 0, 0, "", 0, 7, guid
end
local out = filter("CHAT_MSG_SAY", "[Gorrim Ashmantle]", chatArgs("Gorrim Ashmantle", "Player-1-GORRIM"))
check("tagged sender gets icons before the name", type(out) == "string" and out:sub(1, 2) == "|T" and out:sub(-18) == "[Gorrim Ashmantle]", out)
check("two icons for two tags", select(2, out:gsub("|T", "")) == 2)
check("found by name when the GUID is missing", filter("CHAT_MSG_SAY", "[Gorrim]", chatArgs("Gorrim-Ashmantle", nil)) ~= nil)
check("untagged sender is left alone", filter("CHAT_MSG_SAY", "[Odo Fennick]", chatArgs("Odo Fennick", "Player-1-ODO")) == nil)
check("hidden sender is left alone", filter("CHAT_MSG_SAY", "[x]", chatArgs(H.SECRET, H.SECRET)) == nil)
check("hidden name is left alone", filter("CHAT_MSG_SAY", H.SECRET, chatArgs("Gorrim Ashmantle", "Player-1-GORRIM")) == nil)
ns.settings.chat = false
check("chat icons can be turned off", filter("CHAT_MSG_SAY", "[Gorrim Ashmantle]", chatArgs("Gorrim Ashmantle", "Player-1-GORRIM")) == nil)
ns.settings.chat = true

section("tooltip")
local post = H.tooltipCalls[1]
GameTooltip.__lines = {}
GameTooltip.__unit = "mouseover"
world.units.mouseover = GORRIM
post(GameTooltip, { guid = "Player-1-GORRIM" })
local tip = table.concat(GameTooltip.__lines, "\n")
check("tooltip lists tags", tip:find("Rude", 1, true) and tip:find("Great Tank", 1, true), tip)
check("tooltip shows the note", tip:find("Held four packs.", 1, true) ~= nil)
check("tooltip says where", tip:find("Tagged in Riverglades", 1, true) ~= nil)
GameTooltip.__lines = {}
post(GameTooltip, { guid = H.SECRET })
check("hidden GUID falls back to the mouseover unit", #GameTooltip.__lines > 0)
GameTooltip.__lines = {}
world.units.mouseover = { name = "Odo", surname = "Fennick", guid = "Player-1-ODO", class = "MAGE" }
post(GameTooltip, { guid = "Player-1-ODO" })
check("untagged player adds nothing", #GameTooltip.__lines == 0)
local other = H.new("GameTooltip")
post(other, { guid = "Player-1-GORRIM" })
check("other tooltips are left alone", other.__lines == nil)

section("nameplates")
world.units.nameplate1 = GORRIM
local plate = H.plate("nameplate1")
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
local row = H.badgeRow(plate)
check("tagged player's plate gets a badge row", row ~= nil and row:IsShown())
check("the row shows both tags, Avoid first", row and row.count == 2 and row.badges[1].tagId == "rude" and row.badges[2].tagId == "tank")
ns.settings.plateMax = 1
ns.RefreshNameplates()
check("the per-plate limit is respected", row.count == 2 and not row.badges[2]:IsShown() and row.more:IsShown() and row.more:GetText() == "+1")
ns.settings.plateMax = 3
ns.settings.nameplates = false
ns.RefreshNameplates()
check("nameplate icons can be turned off", not row:IsShown())
ns.settings.nameplates = true
ns.RefreshNameplates()
check("and back on", row:IsShown())
check("no errors after showing a plate", #ns.errors == 0, ns.errors[1])
world.units.nameplate2 = { name = "Stormwind Guard", npc = true }
H.plate("nameplate2")
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
check("an NPC plate gets nothing", H.badgeRow(world.plates.nameplate2) == nil)
H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check("the row hides when the plate goes away", not row:IsShown())
world.units.nameplate1 = { name = "Odo", surname = "Fennick", guid = "Player-1-ODO", class = "MAGE" }
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
check("a recycled plate does not keep the old player's icons", not row:IsShown())
H.fire("NAME_PLATE_UNIT_ADDED", H.SECRET)
check("plates for NPCs, removals and hidden units cause no errors", #ns.errors == 0, ns.errors[1])
check("seeing a tagged player updates last seen", rec.seen == world.now and rec.seenZone == "Riverglades")

section("friendly nameplates are opt-in")
H.fire("PLAYER_ENTERING_WORLD", true, false)
H.flush()
check("off by default", ns.settings.friendlyPlates == "off")
check("no prompt is ever shown", PlayerTagsFriendlyPrompt == nil)
check("a fresh install leaves the game's settings alone", world.cvars.nameplateShowFriendlyPlayers == "0" and world.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "0" and next(ns.db.cvars) == nil)
-- Someone who said yes to the beta 1 prompt: the game settings are on and
-- the originals are remembered. Loading this version must undo all of it.
PlayerTagsDB.version = 1
PlayerTagsDB.settings.friendlyPlates = "on"
PlayerTagsDB.cvars = { nameplateShowFriendlyPlayers = "0", nameplateShowOnlyNameForFriendlyPlayerUnits = "0" }
PlayerTagsDB.positions = { window = { "CENTER", "CENTER", -271.6, 28.3 } } -- the shape beta 1 saved
world.cvars.nameplateShowFriendlyPlayers, world.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits = "1", "1"
ns.InitDB()
ns.ApplyFriendlyPlates()
check("upgrading from beta 1 switches it off", ns.settings.friendlyPlates == "off" and PlayerTagsDB.version == 3)
check("upgrading forgets old window positions", type(PlayerTagsDB.positions) == "table" and next(PlayerTagsDB.positions) == nil)
check("new options get their defaults", ns.settings.minimap == true and ns.settings.popupAtCursor == false)
check("and puts the game's settings back", world.cvars.nameplateShowFriendlyPlayers == "0" and world.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "0" and next(ns.db.cvars) == nil)
ns.InitDB()
check("a later choice survives reloads", (function()
	ns.settings.friendlyPlates = "on"
	ns.InitDB()
	local kept = ns.settings.friendlyPlates == "on"
	ns.settings.friendlyPlates = "off"
	return kept
end)())
rec = ns.GetRecord("gorrim ashmantle")
ns.settings.friendlyPlates = "on"
ns.ApplyFriendlyPlates()
check("turning it on sets both game settings", world.cvars.nameplateShowFriendlyPlayers == "1" and world.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "1")
check("original values remembered", ns.db.cvars.nameplateShowFriendlyPlayers == "0")
ns.settings.friendlyPlates = "off"
ns.ApplyFriendlyPlates()
check("turning it off restores them", world.cvars.nameplateShowFriendlyPlayers == "0" and world.cvars.nameplateShowOnlyNameForFriendlyPlayerUnits == "0" and next(ns.db.cvars) == nil)
world.combat = true
ns.settings.friendlyPlates = "on"
ns.ApplyFriendlyPlates()
check("no setting changes during combat", world.cvars.nameplateShowFriendlyPlayers == "0")
world.combat = false
H.fire("PLAYER_REGEN_ENABLED")
check("applied when combat ends", world.cvars.nameplateShowFriendlyPlayers == "1")

section("slash commands")
world.units.target = VELRA
world.units.mouseover = nil
SlashCmdList.PLAYERTAGSTAG("ganker, pvp god, wizard")
local velra = ns.GetRecord("velra duskwhisper")
check("/tag adds several tags", velra and velra.tags.ganker and velra.tags.pvp)
check("/tag reports an unknown tag", chatHas("no tag called \"wizard\""))
SlashCmdList.PLAYERTAGSTAG("note Camped the flight path")
check("/tag note saves a note", velra.note == "Camped the flight path")
SlashCmdList.PLAYERTAGSUNTAG("pvp god")
check("/untag removes one tag", velra.tags.pvp == nil and velra.tags.ganker ~= nil)
SlashCmdList.PLAYERTAGSUNTAG("")
check("/untag alone removes the rest but keeps the note", ns.GetRecord("velra duskwhisper") ~= nil and next(velra.tags) == nil)
SlashCmdList.PLAYERTAGSTAG("ganker")
world.units.target = nil
world.chat = {}
H.world.chat = world.chat
SlashCmdList.PLAYERTAGSTAG("rude")
check("/tag with no target explains what to do", #ns.errors == 0)
SlashCmdList.PLAYERTAGS("status")
SlashCmdList.PLAYERTAGS("help")
check("/tags status and help run", #ns.errors == 0, ns.errors[1])

section("tagging popup")
world.units.target = TESSA
PlayerTags_QuickTag()
local popup = PlayerTagsPopup
check("popup opens for the target", popup ~= nil and popup:IsShown())
local at = H.anchor(popup)
check("the popup opens in the middle of the screen the first time", at.point == "CENTER" and at.rel == UIParent and at.relPoint == "CENTER" and at.x == 0 and at.y == 0, tostring(at.point) .. " " .. tostring(at.x) .. "," .. tostring(at.y))
local before = ns.GetRecord("tessa brightwell").tags.reliable
local tagButtons = H.find(popup, function(o) return rawget(o, "tagId") ~= nil and rawget(o, "badge") ~= nil end)
check("popup has a button for every visible tag", #tagButtons == #ns.AllTags(false), #tagButtons)
local patientButton
for _, b in ipairs(tagButtons) do if b.tagId == "patient" then patientButton = b end end
H.run(patientButton, "OnClick")
check("clicking a tag button applies it at once", ns.GetRecord("tessa brightwell").tags.patient ~= nil and patientButton.on == true and patientButton:GetChecked())
H.run(patientButton, "OnClick")
check("clicking again removes it", ns.GetRecord("tessa brightwell").tags.patient == nil and patientButton.on == false and not patientButton:GetChecked())
popup.note:SetText("Ported us for free")
H.run(popup.note, "OnEnterPressed")
check("the note box saves on Enter", ns.GetRecord("tessa brightwell").note == "Ported us for free")
SlashCmdList.PLAYERTAGSTAG("reliable")
check("popup survives a change made elsewhere", #ns.errors == 0, ns.errors[1])
PlayerTags_QuickTag()
check("pressing the key again closes it", not popup:IsShown())
PlayerTags_QuickTag()
H.drag(popup, 1300, 400)
check("dragging the popup remembers where it was dropped", ns.db.positions.popup and ns.db.positions.popup.x == 300 and ns.db.positions.popup.y == -200)
check("the game's own position memory is switched off for it", popup.__userPlaced == false)
PlayerTags_QuickTag()
PlayerTags_QuickTag()
at = H.anchor(popup)
check("the popup reopens where it was left", popup:IsShown() and at.point == "CENTER" and at.rel == UIParent and at.x == 300 and at.y == -200, tostring(at.x) .. "," .. tostring(at.y))
PlayerTags_QuickTag()
ns.settings.popupAtCursor = true
PlayerTags_QuickTag()
at = H.anchor(popup)
check("with the option on, the popup opens at the mouse", at.point == "TOPLEFT" and at.rel == UIParent and at.relPoint == "BOTTOMLEFT" and at.x == 416 and at.y == 316, tostring(at.point) .. " " .. tostring(at.x) .. "," .. tostring(at.y))
PlayerTags_QuickTag()
ns.settings.popupAtCursor = false
world.units.target = world.units.player
world.units.mouseover = nil
PlayerTags_QuickTag()
check("cannot tag yourself", not popup:IsShown())
check("reliable tag was added", before == nil and ns.GetRecord("tessa brightwell").tags.reliable ~= nil)

section("right-click menu")
local made = {}
local root = {
	CreateDivider = function() end,
	CreateTitle = function(_, text) made[#made + 1] = "title:" .. text end,
	CreateButton = function(_, text, fn) made[#made + 1] = text made[text] = fn end,
}
check("menu hooks registered", type(H.menuHooks.MENU_UNIT_PLAYER) == "function" and type(H.menuHooks.MENU_UNIT_FRIEND) == "function")
world.units.target = GORRIM
H.menuHooks.MENU_UNIT_TARGET(nil, root, { unit = "target", name = "Gorrim", surname = "Ashmantle" })
check("menu offers Tag player and Remove tags", made["Tag player"] ~= nil and made["Remove tags"] ~= nil, table.concat(made, ","))
made = {}
world.units.target = { name = "Stormwind Guard", npc = true }
H.menuHooks.MENU_UNIT_TARGET(nil, root, { unit = "target", name = "Stormwind Guard" })
check("no menu entry for an NPC", #made == 0)
made = {}
world.chatGuids = { [7] = "Player-1-ODO" }
H.menuHooks.MENU_UNIT_FRIEND(nil, root, { name = "Odo", surname = "Fennick", lineID = 7 })
check("menu works from a chat name", made["Tag player"] ~= nil and made["Remove tags"] == nil)
made["Tag player"]()
check("Tag player opens the popup", PlayerTagsPopup:IsShown())
ns.CloseQuickTag()
-- A chat name the game knows nothing else about: no level, race or class.
made = {}
world.chatGuids = { [8] = "Player-1-WREN" }
H.menuHooks.MENU_UNIT_FRIEND(nil, root, { name = "Wren", surname = "Hollis", lineID = 8 })
local function sub() return PlayerTagsPopup.sub:GetText() or "" end
made["Tag player"]()
check("a chat name nobody has tagged says so", sub() == "Not tagged yet", sub())
local helpfulButton = H.find(PlayerTagsPopup, function(o) return rawget(o, "tagId") == "helpful" end)[1]
H.run(helpfulButton, "OnClick")
check("after the first tag it says when and where, like the list", sub():find("^Last seen just now") ~= nil, sub())
ns.CloseQuickTag()
world.now = world.now + 300
made["Tag player"]()
check("reopened later, the popup gives the age", sub():find("^Last seen 5 min ago") ~= nil, sub())
H.run(helpfulButton, "OnClick")
check("taking the only tag off forgets the player again", sub() == "Not tagged yet", sub())
world.now = world.now - 300
ns.CloseQuickTag()
made = {}
H.menuHooks.MENU_UNIT_PLAYER(nil, root, { name = "Matt", surname = "Tester" })
check("no menu entry for yourself", #made == 0)
H.menuHooks.MENU_UNIT_PLAYER(nil, root, { name = H.SECRET, unit = H.SECRET })
check("hidden menu data causes no errors", #ns.errors == 0, ns.errors[1])

section("group alert")
world.chat = {}
world.inGroup = true
world.units.party1, world.units.party2 = GORRIM, { name = "Odo", surname = "Fennick", guid = "Player-1-ODO", class = "MAGE" }
world.now = world.now + 100
H.fire("GROUP_ROSTER_UPDATE")
H.flush()
check("alert names the tagged member", chatHas("1 tagged player in your group") and chatHas("Gorrim Ashmantle"))
check("Avoid tag plays the warning sound", world.lastSound == 8959)
check("the alert box shows it", ns.IsAlertShown() and PlayerTagsAlert.title:GetText():find("1 tagged player", 1, true) ~= nil)
check("nothing goes to the game's error-message area", #world.banner == 0)
world.chat = {}
H.fire("GROUP_ROSTER_UPDATE")
H.flush()
check("not repeated for the same group", not chatHas("tagged player"))
world.inGroup = false
H.fire("GROUP_ROSTER_UPDATE")
H.flush()
world.inGroup = true
world.units.party1 = TESSA
world.lastSound = nil
H.fire("GROUP_ROSTER_UPDATE")
H.flush()
check("a new group is announced again", chatHas("Tessa Brightwell"))
check("no warning sound for good tags", world.lastSound == nil)

section("unit frames")
TargetFrame = H.new("Frame")
TargetFrame.TargetFrameContent = H.new("Frame")
TargetFrame.TargetFrameContent.TargetFrameContentMain = H.new("Frame")
local targetName = H.new("FontString")
targetName:SetJustifyH("CENTER")
TargetFrame.TargetFrameContent.TargetFrameContentMain.Name = targetName
world.units.target = GORRIM
H.fire("PLAYER_TARGET_CHANGED")
H.flush()
local raidFrame = H.new("Button")
raidFrame.unit = "party1"
CompactUnitFrame_UpdateName(raidFrame)
local plateFrame = H.new("Button")
plateFrame.unit = "nameplate3"
CompactUnitFrame_UpdateName(plateFrame)
CompactUnitFrame_UpdateName({ unit = H.SECRET })
H.flush()
local targetRow = H.badgeRow(TargetFrame)
check("target frame shows the target's tags", targetRow ~= nil and targetRow:IsShown() and targetRow.count == 2)
local raidRow = H.badgeRow(raidFrame)
check("raid-style frame shows tags for its unit", raidRow ~= nil and raidRow:IsShown())
check("nameplate frames are ignored by the raid-frame hook", H.badgeRow(plateFrame) == nil)
world.units.target = { name = "Odo", surname = "Fennick", guid = "Player-1-ODO", class = "MAGE" }
H.fire("PLAYER_TARGET_CHANGED")
H.flush()
check("icons clear when the target changes to someone untagged", not targetRow:IsShown())
ns.settings.frames = false
world.units.target = GORRIM
H.fire("PLAYER_TARGET_CHANGED")
H.flush()
check("frame icons can be turned off", not targetRow:IsShown())
ns.settings.frames = true
check("target, party and raid frames update without errors", #ns.errors == 0, ns.errors[1])

section("group finder")
world.listings = { [11] = { leaderName = "Gorrim Ashmantle", members = { "Gorrim Ashmantle", "Tessa Brightwell", "Odo Fennick" } },
	[12] = { leaderName = "Odo Fennick", members = { "Odo Fennick" } },
	[13] = { leaderName = H.SECRET, members = {} } }
local entry = H.new("Button")
entry.resultID = 11
entry.Name = H.new("FontString")
LFGBrowseSearchEntry_Update(entry)
local mark = H.find(entry, function(o) return o.__kind == "FontString" end)[1]
check("listing shows the leader's icons and the other tagged member", mark ~= nil and mark:GetText():find("|T", 1, true) ~= nil and mark:GetText():find("+1 tagged", 1, true) ~= nil, mark and mark:GetText())
check("no errors marking a listing", #ns.errors == 0, ns.errors[1])
local entry2 = H.new("Button")
entry2.resultID = 12
entry2.Name = H.new("FontString")
LFGBrowseSearchEntry_Update(entry2)
local entry3 = H.new("Button")
entry3.resultID = 13
entry3.Name = H.new("FontString")
LFGBrowseSearchEntry_Update(entry3)
check("an untagged listing gets no mark", #H.find(entry2, function(o) return o.__kind == "FontString" end) == 0)
entry.resultID = 12
LFGBrowseSearchEntry_Update(entry)
check("a recycled listing row is cleared", mark:GetText() == "")
check("untagged and hidden listings cause no errors", #ns.errors == 0, ns.errors[1])

section("custom tags")
local customId, problem = ns.SaveTag(nil, { name = "Guild Recruit", family = "good", glyph = 22 })
check("create a custom tag", customId ~= nil and ns.GetTag(customId).name == "Guild Recruit", problem)
check("duplicate names refused", ns.SaveTag(nil, { name = "guild recruit", family = "info", glyph = 1 }) == nil)
check("empty names refused", ns.SaveTag(nil, { name = "  ", family = "info", glyph = 1 }) == nil)
check("custom tag sorts after starters in its family", ns.GetTag(customId).position > ns.GetTag("patient").position and ns.GetTag(customId).position < ns.GetTag("tank").position)
ns.SetTag(tessa, customId, true)
ns.SaveTag("rude", { name = "Toxic", family = "avoid", glyph = 16 })
check("rename a starter tag", ns.GetTag("rude").name == "Toxic" and ns.FindTag("toxic") == "rude")
ns.ResetTag("rude")
check("reset a starter tag", ns.GetTag("rude").name == "Rude")
ns.SetTagHidden("quiet", true)
check("hidden tags leave the popup list only", #ns.AllTags(false) == 22 and #ns.AllTags(true) == 23)
ns.SetTagHidden("quiet", false)

section("export and import")
local text, count = ns.Export()
check("export has a header and every player", text:sub(1, 19) == "PlayerTags export 1" and count == ns.PlayerCount(), count)
check("export never contains a pipe or raw separators in notes", not text:find("|", 1, true))
ns.SetNote(gorrim, "semi;colon, comma ~ tilde | pipe 100%")
text = ns.Export()
local savedPlayers, savedDefs = PlayerTagsDB.players, PlayerTagsDB.tagdefs
PlayerTagsDB.players = {}
PlayerTagsDB.tagdefs = { custom = {}, override = {}, hidden = {} }
ns.InitDB()
check("fresh database is empty", ns.PlayerCount() == 0 and #ns.AllTags(true) == 22)
local summary, reason = ns.Import(text)
check("import succeeds", summary ~= nil, reason)
check("import restores every player", ns.PlayerCount() == count, ns.PlayerCount())
local back = ns.GetRecord("gorrim ashmantle")
check("tags, note and facts survive the round trip", back and back.tags.rude and back.tags.tank and back.note == "semi;colon, comma ~ tilde || pipe 100%" and back.class == "WARRIOR" and back.guid == "Player-1-GORRIM")
check("tag details survive", back.tags.tank.zone == "Riverglades" and back.tags.tank.by == "Matt Tester" and type(back.tags.tank.t) == "number")
local tessaBack = ns.GetRecord("tessa brightwell")
local recreated = ns.FindTag("Guild Recruit")
check("custom tag recreated and reattached", recreated ~= nil and tessaBack.tags[recreated] ~= nil)
local again = ns.Import(text)
check("importing twice adds nothing", again ~= nil and again:find("0 new players, 0 updated", 1, true) ~= nil, again)
check("junk text is refused politely", ns.Import("hello there") == nil and ns.Import("") == nil)
check("guid index rebuilt", ns.GetRecordByGUID("Player-1-GORRIM") == back)
rec = back

section("deleting a custom tag")
check("delete custom tag", ns.DeleteTag(recreated) == true and ns.GetTag(recreated) == nil)
check("it is stripped from players", tessaBack.tags[recreated] == nil)
check("starter tags cannot be deleted", ns.DeleteTag("rude") == false)

section("main window")
ns.ShowWindow()
check("window opens", PlayerTagsFrame ~= nil and PlayerTagsFrame:IsShown())
at = H.anchor(PlayerTagsFrame)
check("the window opens in the middle of the screen the first time", at.point == "CENTER" and at.rel == UIParent and at.relPoint == "CENTER" and at.x == 0 and at.y == 0, tostring(at.point) .. " " .. tostring(at.x) .. "," .. tostring(at.y))
check("only one anchor holds the window", #PlayerTagsFrame.__points == 1, #PlayerTagsFrame.__points)
check("the window is the game's standard frame", PlayerTagsFrame.CloseButton ~= nil and PlayerTagsFrame.Inset ~= nil and PlayerTagsFrame:GetTitleText():GetText() == "Player Tags")
check("three tabs along the bottom", #PlayerTagsFrame.Tabs == 3 and PlayerTagsFrame.selectedTab == 1, PlayerTagsFrame.selectedTab)
H.run(PlayerTagsFrame.Tabs[2], "OnClick")
check("the Tags tab is chosen from its tab", PlayerTagsFrame.selectedTab == 2)
ns.ShowWindow("tags")
ns.ShowWindow("players", "gorrim")
local shownRows = H.find(PlayerTagsFrame, function(o) return rawget(o, "del") ~= nil and rawget(o, "key") ~= nil and o:IsShown() end)
check("search narrows the list to one player", #shownRows == 1 and shownRows[1].key == "gorrim ashmantle", #shownRows)
check("the row shows name, tags and note", shownRows[1].name:GetText():find("Gorrim Ashmantle", 1, true) ~= nil and shownRows[1].tags.count == 2 and shownRows[1].note:GetText() ~= "")
H.run(shownRows[1], "OnClick")
check("clicking a row opens the popup for that player", PlayerTagsPopup:IsShown() and PlayerTagsPopup.who:GetText():find("Gorrim", 1, true) ~= nil)
at = H.anchor(PlayerTagsPopup)
check("opened from the list, the popup sits beside the window", at.point == "TOPLEFT" and at.rel == PlayerTagsFrame and at.relPoint == "TOPRIGHT")
ns.CloseQuickTag()
ns.ShowWindow("players", "")
check("clearing the search shows everyone", #H.find(PlayerTagsFrame, function(o) return rawget(o, "del") ~= nil and rawget(o, "key") ~= nil and o:IsShown() end) == ns.PlayerCount())
check("tabs and search run without errors", #ns.errors == 0, ns.errors[1])
ns.ShowShare("export")
check("export dialog opens with text", PlayerTagsShare:IsShown() and PlayerTagsShare.edit:GetText():sub(1, 10) == "PlayerTags")
ns.ShowShare("import")
PlayerTagsShare.edit:SetText(text)
H.run(PlayerTagsShare.action, "OnClick")
check("import button runs", #ns.errors == 0, ns.errors[1])
ns.DeleteRecord("velra duskwhisper")
check("deleting a player with the window open is fine", ns.GetRecord("velra duskwhisper") == nil and #ns.errors == 0, ns.errors[1])
H.drag(PlayerTagsFrame, 700, 650)
at = H.anchor(PlayerTagsFrame)
check("dragging the window remembers where it was dropped", ns.db.positions.window and ns.db.positions.window.x == -300 and ns.db.positions.window.y == 50)
check("the dropped window is held by its own anchor", #PlayerTagsFrame.__points == 1 and at.point == "CENTER" and at.rel == UIParent and at.x == -300 and at.y == 50)
check("the game's own position memory is switched off for the window", PlayerTagsFrame.__userPlaced == false)
local fresh = CreateFrame("Frame")
ns.UI.Place(fresh, "window")
check("after a reload the window opens where it was left", H.anchor(fresh).x == -300 and H.anchor(fresh).y == 50)
ns.InitDB()
check("remembered positions survive a reload", ns.db.positions.window.x == -300 and ns.db.positions.popup.x == 300)
-- The close button must not go through the game's panel manager, which
-- addons may not use in combat.
local realHide = HideUIPanel
HideUIPanel = function() error("HideUIPanel is blocked for addons in combat") end
world.combat = true
H.run(PlayerTagsFrame.CloseButton, "OnClick")
check("the close button works in combat", not PlayerTagsFrame:IsShown())
world.combat = false
HideUIPanel = realHide
ns.ShowWindow()
ns.ToggleWindow()
check("window closes", not PlayerTagsFrame:IsShown())

section("minimap button")
local mini = PlayerTagsMinimapButton
check("the button exists, is showing and belongs to the minimap", mini ~= nil and mini:IsShown() and mini:GetParent() == Minimap)
at = H.anchor(mini)
check("it starts at the lower left of the minimap", at.point == "CENTER" and at.rel == Minimap and math.abs(at.x + 73.54) < 0.1 and math.abs(at.y + 73.54) < 0.1, tostring(at.x) .. "," .. tostring(at.y))
-- Another addon's button (LibDBIcon starts at the lower left too).
local other = CreateFrame("Button", "LibDBIcon10_FishFry", Minimap)
other:SetSize(31, 31)
local pin = CreateFrame("Button", nil, Minimap) -- a small quest pin on the rim
pin:SetSize(16, 16)
pin.__center = { 1850 + math.cos(math.rad(250)) * 100, 1050 + math.sin(math.rad(250)) * 100 }
other.__center = { 1850 + math.cos(math.rad(225)) * 104, 1050 + math.sin(math.rad(225)) * 104 }
ns.db.positions.minimap = nil
ns.Fire("SETTINGS_CHANGED")
H.flush()
local chosen = ns.db.positions.minimap
check("a first-time button moves off a spot another addon's button uses", chosen ~= nil and math.abs((chosen - 225 + 180) % 360 - 180) >= 24, tostring(chosen))
check("and takes the nearest free spot, then keeps it", chosen == 250 and H.anchor(mini).x ~= at.x)
other:Hide()
pin:Hide()
ns.db.positions.minimap = 225
ns.Fire("SETTINGS_CHANGED")
H.flush()
check("a spot that was chosen is not changed again", ns.db.positions.minimap == 225)
H.run(mini, "OnClick", "LeftButton")
check("left-click opens the list", PlayerTagsFrame:IsShown())
H.run(mini, "OnClick", "LeftButton")
check("left-click again closes it", not PlayerTagsFrame:IsShown())
world.units.target = TESSA
H.run(mini, "OnClick", "RightButton")
check("right-click opens the tagging popup for your target", PlayerTagsPopup:IsShown() and PlayerTagsPopup.who:GetText():find("Tessa", 1, true) ~= nil)
ns.CloseQuickTag()
world.units.target = nil
world.chat = {}
H.world.chat = world.chat
H.run(mini, "OnClick", "RightButton")
check("right-click with no target says what to do", not PlayerTagsPopup:IsShown() and chatHas("Target a player") and #ns.errors == 0)
local realCursor = GetCursorPosition
GetCursorPosition = function() return 1950, 1050 end -- straight to the right of the minimap's middle
H.run(mini, "OnDragStart")
H.run(mini, "OnUpdate")
at = H.anchor(mini)
check("dragging slides the button around the minimap", ns.db.positions.minimap == 0 and math.abs(at.x - 104) < 0.01 and math.abs(at.y) < 0.01, tostring(ns.db.positions.minimap))
GetCursorPosition = function() return 1850, 1300 end -- straight above
H.run(mini, "OnUpdate")
H.run(mini, "OnDragStop")
at = H.anchor(mini)
check("and stays where it is dropped", ns.db.positions.minimap == 90 and mini:GetScript("OnUpdate") == nil and math.abs(at.x) < 0.01 and math.abs(at.y - 104) < 0.01, tostring(ns.db.positions.minimap))
GetCursorPosition = realCursor
GameTooltip.__lines = {}
mini.__center = { 1800, 1100 }
H.run(mini, "OnEnter")
at = H.anchor(GameTooltip)
check("its tooltip explains the clicks", table.concat(GameTooltip.__lines, "|"):find("Left%-click") ~= nil and table.concat(GameTooltip.__lines, "|"):find("Right%-click") ~= nil)
check("the tooltip opens right beside the button", at.point == "TOPRIGHT" and at.rel == mini and at.relPoint == "BOTTOMLEFT")
mini.__center = nil
H.run(mini, "OnLeave")
local miniSetting = H.settings.byVariable.PLAYERTAGS_MINIMAP
check("settings have a switch for it, ticked", miniSetting ~= nil and miniSetting:GetValue() == true)
miniSetting:SetValue(false)
check("unticking it hides the button", ns.settings.minimap == false and not mini:IsShown())
miniSetting:SetValue(true)
check("ticking it brings the button back", ns.settings.minimap == true and mini:IsShown())
local cursorSetting = H.settings.byVariable.PLAYERTAGS_POPUPATCURSOR
check("settings have a switch for opening the popup at the mouse, unticked", cursorSetting ~= nil and cursorSetting:GetValue() == false)
local tocText = io.open("PlayerTags/PlayerTags.toc"):read("*a")
local listed = tocText:match("## AddonCompartmentFunc: ([%w_]+)")
check("the game's addon list is given a function that exists", listed ~= nil and type(_G[listed]) == "function", listed)
_G[listed]("PlayerTags", "LeftButton")
check("picking Player Tags in the game's addon list opens the list", PlayerTagsFrame:IsShown())
_G[listed]("PlayerTags", "LeftButton")
check("the minimap button's texture file exists", io.open("PlayerTags/Media/minimap.tga", "rb") ~= nil)
check("the minimap button ran without problems", #ns.errors == 0, ns.errors[1])

section("class from the game's memory")
-- Players tagged from a chat name used to stay classless, and the list drew
-- them white, the priest colour. These are the ways a class now arrives.
world.playerCache = {}
local function known(name) return ns.GetRecord(ns.Key(name)) end
check("an unknown class is not drawn in the priest colour", ns.ClassColorCode(nil) ~= ns.ClassColorCode("PRIEST"))

-- A chat line: the record learns its GUID, then its class once the game knows it.
ns.SetTag(ns.IdentifyName("Lark Pembrook"), "helpful", true)
local lark = known("Lark Pembrook")
check("a player tagged from a bare name starts with no class", lark and lark.class == nil and lark.guid == nil)
ns.settings.chat = false
filter("CHAT_MSG_SAY", "[Lark Pembrook]", chatArgs("Lark Pembrook", "Player-1-LARK"))
check("a chat line gives a bare-name record its GUID, even with chat icons off", lark.guid == "Player-1-LARK" and ns.GetRecordByGUID("Player-1-LARK") == lark)
check("when the game knows nothing yet, the class stays unknown", lark.class == nil)
world.playerCache["Player-1-LARK"] = { class = "ROGUE", race = "Human", level = 22 }
filter("CHAT_MSG_SAY", "[Lark Pembrook]", chatArgs("Lark Pembrook", "Player-1-LARK"))
check("the next chat line fills in class, race and level", lark.class == "ROGUE" and lark.race == "Human" and lark.level == 22)
ns.settings.chat = true
H.flush()
ns.SetTag(ns.IdentifyName("Moss Tanner"), "quiet", true)
local moss = known("Moss Tanner")
check("a GUID that belongs to another record is not handed out", ns.Learn(moss, "moss tanner", "Player-1-LARK") == false and moss.guid == nil)
filter("CHAT_MSG_SAY", "[Moss Tanner]", chatArgs("Moss Tanner", H.SECRET))
check("a hidden GUID in chat changes nothing", moss.guid == nil and #ns.errors == 0, ns.errors[1])
world.playerCache["Player-1-LARK"] = { class = "PRIEST", race = "Gnome", level = 60 }
ns.Learn(lark, "lark pembrook")
check("what a record already knows is never overwritten", lark.class == "ROGUE" and lark.race == "Human" and lark.level == 22)

-- Tagging from a chat name or a friends list now saves the class at once.
made = {}
world.chatGuids = { [9] = "Player-1-BRIN" }
world.playerCache["Player-1-BRIN"] = { class = "MAGE", race = "Skyborne", level = 28 }
H.menuHooks.MENU_UNIT_FRIEND(nil, root, { name = "Brin", surname = "Talmore", lineID = 9 })
made["Tag player"]()
check("the popup for a chat name gives level, race and class", sub() == "Level 28 Skyborne Mage", sub())
H.run(helpfulButton, "OnClick")
check("tagging from a chat name saves the class", known("Brin Talmore") and known("Brin Talmore").class == "MAGE")
ns.CloseQuickTag()
made = {}
world.playerCache["Player-1-CAEL"] = { class = "WARRIOR", race = "Dwarf", level = 40 }
H.menuHooks.MENU_UNIT_FRIEND(nil, root, { name = "Cael", surname = "Vorn", guid = "Player-1-CAEL" })
made["Tag player"]()
H.run(helpfulButton, "OnClick")
local cael = known("Cael Vorn")
check("a menu that hands over a GUID saves it and the class", cael and cael.guid == "Player-1-CAEL" and cael.class == "WARRIOR")
ns.CloseQuickTag()

-- Seeing them: pointing at them or targeting them fills in the class.
ns.SetTag(ns.IdentifyName("Ivy Corran", "Player-1-IVY"), "patient", true)
local ivy = known("Ivy Corran")
check("tagged with a GUID the game did not know", ivy.guid == "Player-1-IVY" and ivy.class == nil)
world.units.mouseover = { name = "Ivy", surname = "Corran", guid = "Player-1-IVY", class = "PRIEST", level = 33, race = "Human" }
GameTooltip.__lines = {}
post(GameTooltip, { guid = "Player-1-IVY" })
check("pointing at them fills in the class", ivy.class == "PRIEST" and ivy.level == 33 and #GameTooltip.__lines > 0)
world.units.mouseover = { name = "Moss", surname = "Tanner", guid = "Player-1-MOSS", class = "ROGUE", level = 19, race = "Dwarf" }
GameTooltip.__lines = {}
post(GameTooltip, { guid = "Player-1-MOSS" })
check("pointing at a bare-name player gives them a GUID and a class", moss.guid == "Player-1-MOSS" and moss.class == "ROGUE" and #GameTooltip.__lines > 0)
world.units.mouseover = nil
ns.SetTag(ns.IdentifyName("Rook Hale"), "tank", true)
world.units.target = { name = "Rook", surname = "Hale", guid = "Player-1-ROOK", class = "WARRIOR", level = 38, race = "Human" }
H.fire("PLAYER_TARGET_CHANGED")
H.flush()
check("targeting them fills in the class", known("Rook Hale").class == "WARRIOR" and known("Rook Hale").guid == "Player-1-ROOK")
world.units.target = nil
H.fire("PLAYER_TARGET_CHANGED")
H.flush()

-- The list asks the game about everyone still missing a class.
ns.SetTag(ns.IdentifyName("Fen Marlow", "Player-1-FEN"), "generous", true)
ns.ShowWindow("players", "fen marlow")
local fenRow = H.find(PlayerTagsFrame, function(o) return rawget(o, "del") ~= nil and rawget(o, "key") == "fen marlow" and o:IsShown() end)[1]
check("an unknown class shows grey in the list, not white", fenRow and fenRow.name:GetText():sub(1, 10) == ns.UNKNOWN_CLASS_COLOR, fenRow and fenRow.name:GetText())
world.playerCache["Player-1-FEN"] = { class = "MAGE", race = "Skyborne", level = 30 }
H.flush()
check("a moment after the list opens it asks again and colours the name", fenRow.name:GetText():sub(1, 10) == ns.ClassColorCode("MAGE") and known("Fen Marlow").class == "MAGE", fenRow.name:GetText())
H.run(fenRow, "OnClick")
check("the popup from the list keeps what the game knows", PlayerTagsPopup.sub:GetText() == "Level 30 Skyborne Mage", PlayerTagsPopup.sub:GetText())
ns.CloseQuickTag()
ns.ShowWindow("players", "")
ns.ToggleWindow()

for _, name in ipairs({ "Lark Pembrook", "Moss Tanner", "Brin Talmore", "Cael Vorn", "Ivy Corran", "Rook Hale", "Fen Marlow" }) do
	ns.DeleteRecord(ns.Key(name))
end
world.playerCache, world.chatGuids = nil, nil
check("learning classes ran without problems", #ns.errors == 0, ns.errors[1])

section("friendly names look like the game's own")
-- With friendly nameplates on, the game draws friendly names white,
-- outlined and cut to the plate's width. Ours replace them: the game's
-- blue, its name font with a shadow, <Away>, the guild underneath.
ns.settings.friendlyPlates = "on"
world.cvars.UnitNameGuild = "1"
world.units.nameplate5 = { name = "Darkchylde", surname = "Ravenshadowmere", guid = "Player-1-DARK", class = "MAGE", guild = "Hearthfire", afk = true }
local fplate = H.plate("nameplate5")
fplate.UnitFrame.unit = "nameplate5"
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
local gameName = fplate.UnitFrame.name
local ourName, guildLine = fplate.UnitFrame.ptName, fplate.UnitFrame.ptGuild
check("our name line replaces the game's, which is hidden but untouched", ourName ~= nil and ourName:IsShown() and gameName:GetAlpha() == 0 and gameName.__font == nil)
check("it is the game's blue", math.abs(ourName.__color[1] - 96 / 255) < 0.001 and ourName.__color[3] == 1, table.concat(ourName.__color, ","))
check("at full strength, not faded with the nameplate", ourName.__ignoreParentAlpha == true and guildLine.__ignoreParentAlpha == true)
check("in the game's name font, with a shadow and no outline", ourName.__font[1] == UNIT_NAME_FONT and ourName.__font[3] == "" and ourName.__shadow[1] == 1)
check("the full name, never cut short, with <Away> in front", ourName:GetText() == "<Away>Darkchylde Ravenshadowmere" and ourName.__w == nil, ourName:GetText())
check("the guild shows underneath in the same blue", guildLine:IsShown() and guildLine:GetText() == "<Hearthfire>" and guildLine.__color[3] == 1)
local plateRow = H.badgeRow(fplate)
CompactUnitFrame_UpdateName(fplate.UnitFrame)
check("after the game redraws its name, ours is still the one showing", ourName:IsShown() and gameName:GetAlpha() == 0)
world.units.nameplate5.afk = false
H.fire("PLAYER_FLAGS_CHANGED", "nameplate5")
check("coming back from away drops <Away>", ourName:GetText() == "Darkchylde Ravenshadowmere", ourName:GetText())
world.cvars.UnitNameGuild = "0"
ns.Fire("SETTINGS_CHANGED")
check("with the game's guild names off, no guild line", not guildLine:IsShown())
world.cvars.UnitNameGuild = "1"
H.settings.byVariable.PLAYERTAGS_FRIENDLYNAMECOLOR:SetValue("class")
check("class colours can be chosen instead", ourName.__color[1] == RAID_CLASS_COLORS.MAGE.r and ourName.__color[3] == RAID_CLASS_COLORS.MAGE.b)
H.settings.byVariable.PLAYERTAGS_FRIENDLYNAMECOLOR:SetValue("white")
check("or plain white", ourName.__color[1] == 1 and ourName.__color[2] == 1)
H.settings.byVariable.PLAYERTAGS_FRIENDLYNAMECOLOR:SetValue("game")
local normal = ourName.__font[2]
H.settings.byVariable.PLAYERTAGS_FRIENDLYNAMESIZE:SetValue(1.3)
check("the size setting makes the names bigger", math.abs(ourName.__font[2] - normal * 1.3) < 0.01 and math.abs(guildLine.__font[2] - normal * 1.3) < 0.01, ourName.__font[2])
H.settings.byVariable.PLAYERTAGS_FRIENDLYNAMESIZE:SetValue(1)
world.units.nameplate6 = { name = "Grukk", guid = "Player-1-GRUKK", class = "WARRIOR", hostile = true }
local eplate = H.plate("nameplate6")
eplate.UnitFrame.unit = "nameplate6"
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
check("enemy players' names are left as the game draws them", eplate.UnitFrame.ptName == nil and eplate.UnitFrame.name:GetAlpha() == 1)
ns.settings.friendlyPlates = "off"
ns.Fire("SETTINGS_CHANGED")
check("turning friendly nameplates off brings the game's own name back", gameName:GetAlpha() == 1 and not ourName:IsShown() and not guildLine:IsShown())
H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate5")
H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate6")
world.units.nameplate5, world.units.nameplate6 = nil, nil
check("friendly names ran without problems", #ns.errors == 0, ns.errors[1])

section("the game's settings page")
local page = H.settings.categories[1]
check("Player Tags has a page in the game's Settings, under AddOns", page ~= nil and page.name == "Player Tags" and page.registered == true)
check("every setting is on it", (function()
	for _, key in ipairs({ "tooltip", "chat", "frames", "finder", "nameplates", "platesize", "platemax", "friendlyplates", "friendlynamecolor", "friendlynamesize",
		"groupalert", "alertsound", "scale", "compactpopup", "popupatcursor", "menu", "minimap" }) do
		if not H.settings.byVariable["PLAYERTAGS_" .. key:upper()] then return false, key end
	end
	return true
end)())
check("every label fits the Settings panel's label column", (function()
	for _, setting in pairs(H.settings.byVariable) do
		if #setting.name > 27 then return false, setting.name end
	end
	return true
end)())
check("every option has an explanation", (function()
	for _, row in ipairs(H.settings.rows) do
		if row.control and not ns.IsText(row.tooltip) then return false end
	end
	return true
end)())
local heard = 0
ns.Listen("SETTINGS_CHANGED", function() heard = heard + 1 end, "test")
H.settings.byVariable.PLAYERTAGS_CHAT:SetValue(false)
check("a change is saved and announced", ns.settings.chat == false and heard > 0)
H.settings.byVariable.PLAYERTAGS_CHAT:SetValue(true)
check("friendly nameplates keep their on/off form", H.settings.byVariable.PLAYERTAGS_FRIENDLYPLATES:GetValue() == (ns.settings.friendlyPlates == "on"), tostring(ns.settings.friendlyPlates))
local plates = H.settings.byVariable.PLAYERTAGS_FRIENDLYPLATES
local platesBefore = ns.settings.friendlyPlates
plates:SetValue(false)
local offForm = ns.settings.friendlyPlates
plates:SetValue(true)
check("ticking and unticking it stores on and off", offForm == "off" and ns.settings.friendlyPlates == "on")
plates:SetValue(platesBefore == "on")
H.settings.byVariable.PLAYERTAGS_PLATESIZE:SetValue(21)
check("nameplate icon size is a choice of sizes", ns.settings.plateSize == 21)
H.settings.byVariable.PLAYERTAGS_PLATESIZE:SetValue(17)
check("the Avoid sound keeps its old default", ns.defaults.alertSound == true)
local openRow
for _, row in ipairs(H.settings.rows) do if row.control == "button" and row.text == "Open" then openRow = row end end
ns.ShowWindow("tags")
ns.ToggleWindow()
openRow.click()
check("Players you've tagged opens the Players tab, not the last one used", PlayerTagsFrame:IsShown() and PlayerTagsFrame.selectedTab == 1, PlayerTagsFrame.selectedTab)
ns.ShowWindow("tags")
ns.ShowWindow()
check("so does opening the list while it shows the Tags tab", PlayerTagsFrame.selectedTab == 1)
ns.ToggleWindow()
local moveRow
for _, row in ipairs(H.settings.rows) do if row.control == "button" and row.text == "Move" then moveRow = row end end
check("the alert box can be moved from settings", moveRow ~= nil)
moveRow.click()
check("Move shows the box with a Done button", ns.IsAlertShown() and PlayerTagsAlert.done:IsShown())
H.drag(PlayerTagsAlert, 1000, 900)
check("where it is dropped is remembered", ns.db.positions.alert and ns.db.positions.alert.y == 300, ns.db.positions.alert and ns.db.positions.alert.y)
H.run(PlayerTagsAlert.done, "OnClick")
check("Done puts it away", not ns.IsAlertShown())

H.settings.opened = nil
SlashCmdList.PLAYERTAGS("options")
check("/tags options opens the settings page", H.settings.opened == page.id)
H.settings.opened = nil
world.chat = {}
world.combat = true
SlashCmdList.PLAYERTAGS("options")
check("in combat it says why it can't open", H.settings.opened == nil and chatHas("during combat"))
world.combat = false
ns.ShowWindow()
local settingsButton = H.find(PlayerTagsFrame, function(o) return o:GetText() == "Settings" and o.__kind == "Button" end)[1]
H.run(settingsButton, "OnClick")
check("the list's Settings button opens it too", H.settings.opened == page.id)
ns.ToggleWindow()

H.settings.byVariable.PLAYERTAGS_SCALE:SetValue(1.2)
ns.ShowWindow()
check("window size applies to the list", PlayerTagsFrame:GetScale() == 1.2, PlayerTagsFrame:GetScale())
world.units.target = TESSA
PlayerTags_QuickTag()
check("and to the tagging popup", PlayerTagsPopup:GetScale() == 1.2)
local fullWidth = PlayerTagsPopup:GetWidth()
H.settings.byVariable.PLAYERTAGS_COMPACTPOPUP:SetValue(true)
local compactButtons = H.find(PlayerTagsPopup, function(o) return rawget(o, "tagId") ~= nil and o:IsShown() end)
check("the compact popup is narrower and shows icons only", PlayerTagsPopup:GetWidth() < fullWidth and not compactButtons[1].text:IsShown(), PlayerTagsPopup:GetWidth())
H.settings.byVariable.PLAYERTAGS_COMPACTPOPUP:SetValue(false)
check("back to full size with names", PlayerTagsPopup:GetWidth() == fullWidth and compactButtons[1].text:IsShown())
check("the popup's title is the player's name and its portrait is them", PlayerTagsPopup.who:GetText():find("Tessa Brightwell", 1, true) ~= nil and PlayerTagsPopup.__portrait == "unit:target")
PlayerTags_QuickTag()
H.settings.byVariable.PLAYERTAGS_SCALE:SetValue(1)
ns.ToggleWindow()
check("settings ran without problems", #ns.errors == 0, ns.errors[1])

section("warnings at the moment it matters")
world.combat, world.inGroup, world.instance = false, false, nil
world.units.party1, world.units.party2, world.units.target, world.units.mouseover = nil, nil, nil, nil
local GRIM = { name = "Grimbold", surname = "Ashjaw", guid = "Player-1-GRIM", class = "WARRIOR", level = 40, race = "Orc", hostile = true }
local LYSA = { name = "Lysa", surname = "Thornfield", guid = "Player-1-LYSA", class = "PRIEST", level = 30, race = "Human" }
local grim = ns.IdentifyName("Grimbold Ashjaw", "Player-1-GRIM")
ns.SetTag(grim, "ganker", true)
ns.SetNote(grim, "Camped the flight path")
local lysa = ns.IdentifyName("Lysa Thornfield", "Player-1-LYSA")
ns.SetTag(lysa, "healer", true)
local function alertTitle() return ns.IsAlertShown() and PlayerTagsAlert.title:GetText() or "" end
local warning = function() return _G.PlayerTagsWarning end

-- group invites: the event names the inviter's GUID
H.fire("PARTY_INVITE_REQUEST", "Grimbold Ashjaw", false, false, false, true, false, false, "Player-1-GRIM", false)
local invitePopup = StaticPopup_Show("PARTY_INVITE", "Grimbold Ashjaw invites you to join a group.")
world.lastSound = nil
H.flush()
check("an invite from a tagged player shows their tags under the invite box", warning() and warning():IsShown() and warning().anchor == invitePopup and warning().title:GetText():find("invites you", 1, true) ~= nil)
check("and plays the Avoid sound", world.lastSound == 8959)
invitePopup:Hide()
check("the warning goes when the invite box does", (function() H.run(warning(), "OnUpdate") return not warning():IsShown() end)())
H.fire("PARTY_INVITE_REQUEST", "Lysa Thornfield", false, false, false, true, false, false, "Player-1-LYSA", false)
invitePopup = StaticPopup_Show("PARTY_INVITE", "Lysa Thornfield invites you.")
world.lastSound = nil
H.flush()
check("good tags show on invites too, without the warning sound", warning():IsShown() and world.lastSound == nil)
invitePopup:Hide()
H.run(warning(), "OnUpdate")
H.fire("PARTY_INVITE_REQUEST", "Odo Fennick", false, false, false, true, false, false, "Player-1-ODO", false)
StaticPopup_Show("PARTY_INVITE", "Odo invites you.")
H.flush()
check("an untagged inviter shows nothing", not warning():IsShown())
world.popups.PARTY_INVITE:Hide()
H.fire("PARTY_INVITE_REQUEST", H.SECRET, false, false, false, true, false, false, H.SECRET, false)
H.flush()
check("a hidden inviter causes no errors", #ns.errors == 0, ns.errors[1])

-- duels give a name only; trades name the other player as the unit "NPC"
H.fire("DUEL_REQUESTED", "Grimbold Ashjaw")
local duelPopup = StaticPopup_Show("DUEL_REQUESTED", "Grimbold Ashjaw")
H.flush()
check("a duel request shows their tags under the duel box", warning():IsShown() and warning().anchor == duelPopup)
duelPopup:Hide()
H.run(warning(), "OnUpdate")
TradeFrame = H.new("Frame")
world.units.NPC = GRIM
H.fire("TRADE_SHOW")
check("the trade window shows their tags under it", warning():IsShown() and warning().anchor == TradeFrame and warning().title:GetText():find("trade", 1, true) ~= nil)
TradeFrame:Hide()
H.run(warning(), "OnUpdate")
world.units.NPC = nil

-- whispers from someone tagged Avoid
ns.ResetAlertWaits()
world.chat = {}
H.fire("CHAT_MSG_WHISPER", "hey", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 10, "Player-1-GRIM")
check("a whisper from someone tagged Avoid sets off a heads-up", alertTitle():find("whispering you", 1, true) ~= nil and chatHas("whispering you"))
world.chat = {}
H.fire("CHAT_MSG_WHISPER", "hey again", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 11, "Player-1-GRIM")
check("but only once in a while", not chatHas("whispering you"))
world.chat = {}
H.fire("CHAT_MSG_WHISPER", "hi", "Lysa Thornfield", "", "", "", "", 0, 0, "", 0, 12, "Player-1-LYSA")
check("whispers from good players are left alone", not chatHas("whispering you"))

-- good players looking for a group, in public channels
world.chat = {}
H.fire("CHAT_MSG_CHANNEL", "LFM SFK need tank", "Lysa Thornfield", "", "4. LookingForGroup", "", "", 26, 4, "LookingForGroup", 0, 13, "Player-1-LYSA")
check("a good player posting LFM gets a line with their name", chatHas("is looking for a group") and chatHas("|Hplayer:Lysa Thornfield"))
check("as a chat line only, never the alert box", not alertTitle():find("looking for a group", 1, true))
world.chat = {}
ns.ResetAlertWaits()
H.fire("CHAT_MSG_CHANNEL", "WTS mageweave cloth", "Lysa Thornfield", "", "2. Trade", "", "", 2, 2, "Trade - City", 0, 14, "Player-1-LYSA")
check("trade chatter does not count", not chatHas("is looking for a group"))
H.fire("CHAT_MSG_CHANNEL", "LFG anything", "Grimbold Ashjaw", "", "4. LookingForGroup", "", "", 26, 4, "LookingForGroup", 0, 15, "Player-1-GRIM")
check("Avoid-tagged players are never pointed out as good", not chatHas("is looking for a group"))
check("the group-search check knows the usual words", ns.LooksLikeGroupSearch("LF2M BFD") and ns.LooksLikeGroupSearch("anyone need a healer?") and not ns.LooksLikeGroupSearch("selling linen"))
check("and not trade requests like LF enchanter or need a port", not ns.LooksLikeGroupSearch("LF enchanter for crusader") and not ns.LooksLikeGroupSearch("need a port to SW"))
H.fire("CHAT_MSG_CHANNEL", H.SECRET, H.SECRET, "", "x", "", "", 0, 0, "x", 0, 16, H.SECRET)
check("hidden channel messages cause no errors", #ns.errors == 0, ns.errors[1])

section("avoid player nearby")
ns.ResetAlertWaits()
ns.StopMovingAlert()
world.chat = {}
world.units.nameplate7 = GRIM
H.plate("nameplate7")
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
check("their nameplate appearing sets off a heads-up", alertTitle():find("is nearby", 1, true) ~= nil and chatHas("Camped the flight path"))
world.chat = {}
H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate7")
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
check("it waits before alerting about the same player again", not chatHas("is nearby"))
ns.ResetAlertWaits()
world.instance = "party"
world.chat = {}
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
check("not inside dungeons", not chatHas("is nearby"))
world.instance = nil
world.groupGuids = { ["Player-1-GRIM"] = true }
H.fire("CHAT_MSG_SAY", "hello", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 17, "Player-1-GRIM")
check("not for your own group (the group alert covers them)", not chatHas("nearby"))
world.groupGuids = nil
H.fire("CHAT_MSG_YELL", "HELLO", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 18, "Player-1-GRIM")
check("talking nearby counts too", chatHas("is talking nearby"))
ns.ResetAlertWaits()
ns.settings.alertHoldCombat = true
world.combat = true
world.chat = {}
H.fire("CHAT_MSG_SAY", "hi", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 19, "Player-1-GRIM")
check("with hold in combat on, a fight holds the alert", not chatHas("talking nearby"))
world.combat = false
H.fire("PLAYER_REGEN_ENABLED")
check("and shows it when the fight ends", chatHas("talking nearby"))
ns.settings.alertHoldCombat = false
ns.ResetAlertWaits()
ns.settings.alertStyle = "chat"
PlayerTagsAlert:Hide()
world.chat = {}
H.fire("CHAT_MSG_SAY", "hi", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 20, "Player-1-GRIM")
check("chat-only alerts skip the box", chatHas("talking nearby") and not ns.IsAlertShown())
ns.settings.alertStyle = "both"
ns.settings.nearbyAlert = false
ns.ResetAlertWaits()
world.chat = {}
H.fire("CHAT_MSG_SAY", "hi", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 21, "Player-1-GRIM")
check("the nearby alert can be turned off", not chatHas("nearby"))
ns.settings.nearbyAlert = true
ns.ResetAlertWaits()
ns.SetTag(grim, "griefer", true)
world.chat = {}
H.fire("CHAT_MSG_SAY", "hi", "Grimbold Ashjaw", "", "", "", "", 0, 0, "", 0, 23, "Player-1-GRIM")
check("tagging someone does not set off an alert about them a moment later", not chatHas("nearby"))
ns.SetTag(grim, "griefer", false)
H.fire("NAME_PLATE_UNIT_ADDED", H.SECRET)
H.fire("CHAT_MSG_SAY", H.SECRET, H.SECRET, "", "", "", "", 0, 0, "", 0, 22, H.SECRET)
check("hidden units and senders cause no errors", #ns.errors == 0, ns.errors[1])
H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate7")
world.units.nameplate7 = nil

section("tag your group afterwards")
local runCard = function() return _G.PlayerTagsRunCard end
world.inGroup = true
world.units.party1 = LYSA
world.units.party2 = { name = "Bramm", surname = "Coppervein", guid = "Player-1-BRAMM", class = "WARRIOR" }
H.fire("GROUP_ROSTER_UPDATE")
H.flush()
world.units.party2 = nil -- left early
H.fire("GROUP_ROSTER_UPDATE")
world.now = world.now + 600
world.inGroup = false
world.units.party1 = nil
H.fire("GROUP_LEFT")
check("when a group of 10 minutes ends, a card lists who was in it", runCard() and runCard():IsShown())
local cardRows = H.find(runCard(), function(o) return rawget(o, "buttons") ~= nil and o:IsShown() end)
local bramRow, lysaRow
for _, row in ipairs(cardRows) do
	if row.id and row.id.key == "bramm coppervein" then bramRow = row end
	if row.id and row.id.key == "lysa thornfield" then lysaRow = row end
end
check("including the player who left early", bramRow ~= nil and lysaRow ~= nil, #cardRows)
local firstButton = bramRow and bramRow.buttons[1]
H.run(firstButton, "OnClick")
check("a tag clicked on the card is saved for that player", ns.GetRecord("bramm coppervein") and ns.GetRecord("bramm coppervein").tags[firstButton.tagId] ~= nil and firstButton.on)
check("the card offers your most-used tags", #bramRow.buttons >= 5)
runCard():Hide()
world.inGroup = true
world.units.party1 = LYSA
H.fire("GROUP_ROSTER_UPDATE")
world.now = world.now + 60
world.inGroup = false
world.units.party1 = nil
H.fire("GROUP_LEFT")
check("a short group gets no card", not runCard():IsShown())
ns.settings.runCard = "dungeons"
world.inGroup = true
world.units.party1 = LYSA
H.fire("GROUP_ROSTER_UPDATE")
world.now = world.now + 900
world.inGroup = false
world.units.party1 = nil
H.fire("GROUP_LEFT")
check("set to dungeons only, an open-world group gets no card", not runCard():IsShown())
ns.settings.runCard = "always"
world.inGroup = true
world.instance = "pvp"
world.units.party1 = LYSA
H.fire("GROUP_ROSTER_UPDATE")
world.now = world.now + 900
world.inGroup = false
world.instance = nil
world.units.party1 = nil
H.fire("GROUP_LEFT")
check("battleground groups get no card", not runCard():IsShown())
ns.DeleteRecord("bramm coppervein")

section("tag who killed you")
local killerCard = function() return _G.PlayerTagsKillerCard end
world.units.nameplate8 = { name = "Shade", surname = "Vexmoor", guid = "Player-1-SHADE", class = "ROGUE", hostile = true }
H.plate("nameplate8")
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
H.fire("PLAYER_DEAD")
H.flush()
check("after a death, a card lists enemy players who were near", killerCard() and killerCard():IsShown())
local killerRows = H.find(killerCard(), function(o) return rawget(o, "buttons") ~= nil and o:IsShown() end)
check("with Ganker among the buttons", killerRows[1] and killerRows[1].id.key == "shade vexmoor" and killerRows[1].buttons[1].tagId == "ganker")
killerCard():Hide()
world.now = world.now + 60
H.fire("PLAYER_DEAD")
H.flush()
check("enemies seen more than 30 seconds ago are not listed", not killerCard():IsShown())
world.instance = "pvp"
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
H.fire("PLAYER_DEAD")
H.flush()
check("not in battlegrounds or dungeons", not killerCard():IsShown())
world.instance = nil
H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate8")
world.units.nameplate8 = nil
check("cards ran without problems", #ns.errors == 0, ns.errors[1])

section("sharing")
local ownBefore = ns.PlayerCount()
local shareText, shareCount = ns.ExportShare({ families = { avoid = true }, notes = false })
check("a share holds only the families chosen", shareText:find("Grimbold", 1, true) ~= nil and not shareText:find("Lysa", 1, true))
check("and no notes unless asked", not shareText:find("flight", 1, true))
check("and nothing about where or when you tagged them", not shareText:find("Riverglades", 1, true) and not shareText:find("Matt Tester~", 1, true))
local withNotes = ns.ExportShare({ notes = true })
check("notes go in when asked", withNotes:find("flight", 1, true) ~= nil)
-- someone else's share, with sneaky text in it
local theirs = table.concat({
	"PlayerTags share 1;Kael",
	"P;Vex|cffff0000Red|r Morrow;Player-1-00AB;ROGUE;rude,ninja;|Hitem:1234|h[Free gold]|h",
	"P;Grimbold Ashjaw;Player-1-GRIM;WARRIOR;leaver;",
	"P;Pip Quill;;MAGE;c~Bard~info~25;",
}, "\n")
local summary, listId = ns.Import(theirs, "Kael's list")
check("a share imports as a separate list", summary ~= nil and ns.db.shared[listId] ~= nil and ns.PlayerCount() == ownBefore, summary)
local sharedList = ns.db.shared[listId]
local vex = sharedList.players["vexred morrow"]
check("colour and link codes are taken out whole", vex ~= nil and vex.name == "VexRed Morrow" and vex.note == "[Free gold]", vex and (vex.name .. " / " .. tostring(vex.note)))
check("game codes are stripped from names and notes", (function()
	for _, p in pairs(sharedList.players) do
		if (p.name and p.name:find("|", 1, true)) or (p.note and p.note:find("|", 1, true)) then return false end
	end
	return true
end)())
check("custom tags you don't have are left out", sharedList.players["pip quill"] == nil)
local info = ns.TagsFor(ns.IdentifyName("Grimbold Ashjaw", "Player-1-GRIM"))
check("shared tags sit beside your own, marked with the list", info and #info.ids == 1 and info.shared[1] and info.shared[1].list == "Kael's list" and info.shared[1].ids[1] == "leaver")
local ids, sharedSet = ns.DisplayIds(info)
check("icons show your own first, then shared ones marked as shared", ids[1] == "ganker" and ids[2] == "leaver" and sharedSet.leaver == true and not sharedSet.ganker)
GameTooltip.__lines = {}
world.units.mouseover = GRIM
post(GameTooltip, { guid = "Player-1-GRIM" })
check("the tooltip says whose list a shared tag is from", table.concat(GameTooltip.__lines, "\n"):find("From Kael's list", 1, true) ~= nil)
world.units.mouseover = nil
local again = ns.ExportShare({})
check("a list you were given is never in what you share", not again:find("Leaver", 1, true) and not again:find("leaver", 1, true) and not again:find("Vex", 1, true))
check("or in a backup", not ns.Export():find("Vex", 1, true))
-- a shared-only Avoid player does not alert until the list's alerts are on
ns.ResetAlertWaits()
world.chat = {}
H.fire("CHAT_MSG_SAY", "hi", "VexRed Morrow", "", "", "", "", 0, 0, "", 0, 30, "Player-1-00AB")
check("shared lists don't set off alerts by default", not chatHas("nearby"))
ns.SetSharedAlerts(listId, true)
H.fire("CHAT_MSG_SAY", "hi", "VexRed Morrow", "", "", "", "", 0, 0, "", 0, 31, "Player-1-00AB")
check("until you turn alerts on for that list", chatHas("talking nearby"))
ns.ShowWindow("shared")
local listRow = H.find(PlayerTagsFrame, function(o) return rawget(o, "listId") == listId and o:IsShown() end)[1]
check("the Shared lists tab shows the list", listRow ~= nil and listRow.name:GetText() == "Kael's list")
H.run(listRow.remove, "OnClick")
H.run(listRow.remove, "OnClick")
check("Remove takes the whole list away, and nothing of yours", ns.db.shared[listId] == nil and ns.PlayerCount() == ownBefore and ns.TagsFor(ns.IdentifyName("Vexred Morrow")) == nil)
ns.ToggleWindow()
check("junk is refused", ns.Import("PlayerTags share 1;x\nnot a line") == nil)
local firstId = select(2, ns.Import("PlayerTags share 1;Kael\nP;Pip Quill;;MAGE;helpful;", "Kael's list"))
local secondSummary, secondId = ns.Import("PlayerTags share 1;Kael\nP;Pip Quill;;MAGE;helpful,patient;", "Kael's list")
check("the same list again replaces the old copy", firstId == secondId and secondSummary:find("Updated", 1, true) ~= nil and #ns.SharedLists() == 1)
ns.RemoveSharedList(secondId)
local backup = "PlayerTags export 1\nP;Rook|cffff0000 Hale;Player-1-ROOKX;WARRIOR;30;;;note |Hitem:1|h[x]|h;helpful~1~Zone|T:1|t~Me"
ns.Import(backup)
local rook = ns.GetRecord("rook hale")
check("a backup from someone else is cleaned the same way", rook ~= nil and not rook.name:find("|c", 1, true) and rook.note == "note [x]" and rook.tags.helpful.zone == "Zone", rook and rook.note)
ns.DeleteRecord("rook hale")
ns.ShowShare("share")
check("the share dialog opens with its choices", PlayerTagsShare:IsShown() and PlayerTagsShare.options:IsShown() and PlayerTagsShare.edit:GetText():sub(1, 16) == "PlayerTags share")
ns.ShowShare("import")
check("the import dialog asks for a list name", PlayerTagsShare.listName:IsShown())
PlayerTagsShare:Hide()
check("sharing ran without problems", #ns.errors == 0, ns.errors[1])

section("where tags show: new choices")
ns.settings.hideInCombat = true
world.combat = true
world.units.nameplate9 = GRIM
local hplate = H.plate("nameplate9")
H.fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
check("icons can hide during fights", H.badgeRow(hplate) == nil or not H.badgeRow(hplate):IsShown())
world.combat = false
H.fire("PLAYER_REGEN_ENABLED")
check("and come back after", H.badgeRow(hplate) ~= nil and H.badgeRow(hplate):IsShown())
ns.settings.hideInCombat = false
H.fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
world.units.nameplate9 = nil
ns.settings.tooltipNote = "shift"
GameTooltip.__lines = {}
world.units.mouseover = GRIM
post(GameTooltip, { guid = "Player-1-GRIM" })
check("notes can wait for Shift", table.concat(GameTooltip.__lines, "\n"):find("Hold Shift", 1, true) ~= nil and not table.concat(GameTooltip.__lines, "\n"):find("flight", 1, true))
world.shift = true
GameTooltip.__lines = {}
post(GameTooltip, { guid = "Player-1-GRIM" })
check("and show while Shift is held", table.concat(GameTooltip.__lines, "\n"):find("flight", 1, true) ~= nil)
world.shift, world.units.mouseover = false, nil
ns.settings.tooltipNote = "always"

section("/tags test")
local countBefore = ns.PlayerCount()
for _, what in ipairs({ "invite", "duel", "trade", "whisper", "nearby", "lfg", "group", "run", "killer" }) do
	SlashCmdList.PLAYERTAGS("test " .. what)
end
check("every test runs without problems", #ns.errors == 0, ns.errors[1])
check("tests use the addon's own stand-in box, not the game's popups", next(StaticPopupDialogs) == nil and PlayerTagsTestBox ~= nil)
check("and saves nothing", ns.PlayerCount() == countBefore)
local testRow = H.find(PlayerTagsRunCard, function(o) return rawget(o, "buttons") ~= nil and o:IsShown() end)[1]
H.run(testRow.buttons[1], "OnClick")
check("tags clicked on a test card are not saved", ns.PlayerCount() == countBefore and testRow.buttons[1].on)
world.chat = {}
SlashCmdList.PLAYERTAGS("test")
check("/tags test alone lists what can be tested", chatHas("invite, duel, trade"))
PlayerTagsRunCard:Hide()
PlayerTagsKillerCard:Hide()
ns.DeleteRecord("grimbold ashjaw")
ns.DeleteRecord("lysa thornfield")

section("saved data stays clean")
local function plain(value, path)
	local kind = type(value)
	if kind == "table" then
		for k, v in pairs(value) do
			local bad = plain(k, path .. ".<key>") or plain(v, path .. "." .. tostring(k))
			if bad then return bad end
		end
	elseif kind ~= "string" and kind ~= "number" and kind ~= "boolean" then
		return path .. " is a " .. kind
	end
	return nil
end
check("only plain data is saved (no frames or functions)", plain(PlayerTagsDB, "PlayerTagsDB") == nil, plain(PlayerTagsDB, "PlayerTagsDB"))
check("no live unit tokens saved on players", (function()
	for _, r in pairs(PlayerTagsDB.players) do
		if r.unit ~= nil or r.live ~= nil or r.key ~= nil then return false end
	end
	return true
end)())

section("result")
check("no problems were recorded during the whole run", #ns.errors == 0, table.concat(ns.errors, " || "))
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
