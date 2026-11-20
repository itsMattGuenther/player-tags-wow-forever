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
check("all files listed in the toc load", #files == 17, #files)
H.fire("ADDON_LOADED", "PlayerTags")
H.fire("PLAYER_LOGIN")
check("database created", type(PlayerTagsDB) == "table" and type(PlayerTagsDB.players) == "table")
check("knows who I am", ns.me == "Matt Tester", ns.me)
for _, name in ipairs(ns.moduleOrder) do
	check("module " .. name .. " is running", (ns.moduleState[name] or ""):sub(1, 2) == "ok", ns.moduleState[name])
end
check("eight surfaces registered", #ns.moduleOrder == 8, #ns.moduleOrder)
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
check("clicking a tag button applies it at once", ns.GetRecord("tessa brightwell").tags.patient ~= nil and patientButton.isOn == true)
H.run(patientButton, "OnClick")
check("clicking again removes it", ns.GetRecord("tessa brightwell").tags.patient == nil and patientButton.isOn == false)
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
check("banner shown", #world.banner > 0)
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
check("tags, note and facts survive the round trip", back and back.tags.rude and back.tags.tank and back.note == "semi;colon, comma ~ tilde | pipe 100%" and back.class == "WARRIOR" and back.guid == "Player-1-GORRIM")
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
ns.ShowWindow("tags")
ns.ShowWindow("options")
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
local optionsPage = H.find(PlayerTagsFrame, function(o) return rawget(o, "checks") ~= nil end)[1]
check("every option fits inside the window", (function()
	local lowest = 0
	for _, child in ipairs(optionsPage.__children) do
		local a = child.__points and child.__points[1]
		if a and a.point == "TOPLEFT" and (a.rel == nil or a.rel == optionsPage) then
			lowest = math.max(lowest, -a.y + child:GetHeight())
		end
	end
	return lowest > 300 and lowest <= 520 - 46 - 12, lowest
end)())
ns.ToggleWindow()
check("window closes", not PlayerTagsFrame:IsShown())

section("minimap button")
local mini = PlayerTagsMinimapButton
check("the button exists, is showing and belongs to the minimap", mini ~= nil and mini:IsShown() and mini:GetParent() == Minimap)
at = H.anchor(mini)
check("it starts at the lower left of the minimap", at.point == "CENTER" and at.rel == Minimap and math.abs(at.x + 73.54) < 0.1 and math.abs(at.y + 73.54) < 0.1, tostring(at.x) .. "," .. tostring(at.y))
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
ns.ShowWindow("options")
local miniCheck = H.find(PlayerTagsFrame, function(o) return rawget(o, "key") == "minimap" end)[1]
check("options has a switch for it, ticked", miniCheck ~= nil and miniCheck:GetChecked() == true)
H.run(miniCheck, "OnClick")
check("unticking it hides the button", ns.settings.minimap == false and not mini:IsShown())
H.run(miniCheck, "OnClick")
check("ticking it brings the button back", ns.settings.minimap == true and mini:IsShown())
local cursorCheck = H.find(PlayerTagsFrame, function(o) return rawget(o, "key") == "popupAtCursor" end)[1]
check("options has a switch for opening the popup at the mouse, unticked", cursorCheck ~= nil and cursorCheck:GetChecked() == false)
ns.ToggleWindow()
local tocText = io.open("PlayerTags/PlayerTags.toc"):read("*a")
local listed = tocText:match("## AddonCompartmentFunc: ([%w_]+)")
check("the game's addon list is given a function that exists", listed ~= nil and type(_G[listed]) == "function", listed)
_G[listed]("PlayerTags", "LeftButton")
check("picking Player Tags in the game's addon list opens the list", PlayerTagsFrame:IsShown())
_G[listed]("PlayerTags", "LeftButton")
check("the minimap button's texture file exists", io.open("PlayerTags/Media/minimap.tga", "rb") ~= nil)
check("the minimap button ran without problems", #ns.errors == 0, ns.errors[1])

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
