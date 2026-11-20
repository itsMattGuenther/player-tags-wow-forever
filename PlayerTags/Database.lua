-- Database: saved data, who a player is, and the tags on them.
--
-- PlayerTagsDB = {
--   players = { [key] = { name, guid, class, level, race, faction,
--                         tags = { [tagId] = { t, zone, by } },
--                         note, created, seen, seenZone } },
--   tagdefs = { custom, override, hidden, nextCustom },
--   settings = { ... },
--   positions = { window = { x, y }, popup = { x, y }, minimap = degrees },
-- }
-- The file lives in WTF/Account/<account>/SavedVariables/PlayerTags.lua and
-- is shared by every character. Nothing in this addon sends it anywhere.
local _, ns = ...

local DEFAULTS = {
	nameplates = true,      -- tag icons on nameplates
	plateSize = 17,         -- icon size on nameplates
	plateMax = 3,           -- most icons shown on one nameplate
	friendlyPlates = "off", -- "on" | "off": name-only plates for friendly players (opt-in)
	tooltip = true,
	chat = true,
	frames = true,          -- party, raid and target frames
	groupAlert = true,
	alertSound = true,
	finder = true,          -- Group Finder marks
	menu = true,            -- right-click "Tag player"
	minimap = true,         -- the button on the minimap
	popupAtCursor = false,  -- tagging popup opens at the mouse instead of its own spot
}

function ns.InitDB()
	local db = _G.PlayerTagsDB
	if type(db) ~= "table" then
		db = {}
		_G.PlayerTagsDB = db
	end
	local previous = tonumber(db.version) or 0
	if type(db.players) ~= "table" then db.players = {} end
	if type(db.settings) ~= "table" then db.settings = {} end
	for k, v in pairs(DEFAULTS) do
		if db.settings[k] == nil then db.settings[k] = v end
	end
	-- Beta 1 offered to turn on friendly nameplates at first login. That is
	-- now opt-in only, so a choice made through that prompt is reset to off.
	-- The game settings it changed are put back by ns.ApplyFriendlyPlates.
	if previous < 2 then db.settings.friendlyPlates = "off" end
	-- Window positions changed shape in beta 2 (now an offset from the centre
	-- of the screen). Older ones are dropped, so each window opens centred
	-- once and is remembered from the next time it is dragged.
	if previous < 3 or type(db.positions) ~= "table" then db.positions = {} end
	db.version = 3
	if type(db.tagdefs) ~= "table" then db.tagdefs = {} end
	local t = db.tagdefs
	if type(t.custom) ~= "table" then t.custom = {} end
	if type(t.override) ~= "table" then t.override = {} end
	if type(t.hidden) ~= "table" then t.hidden = {} end
	if type(db.cvars) ~= "table" then db.cvars = {} end

	ns.db = db
	ns.settings = db.settings
	ns.defaults = DEFAULTS

	ns.guidIndex = {}
	for key, rec in pairs(db.players) do
		if type(rec) ~= "table" then
			db.players[key] = nil
		else
			if type(rec.tags) ~= "table" then rec.tags = {} end
			if rec.guid then ns.guidIndex[rec.guid] = key end
		end
	end

	ns.RebuildTags()
end

---------------------------------------------------------------------------
-- Identity. Forever characters have a first name and usually a surname, on
-- one realm per ruleset, so the full name identifies a player. The game
-- joins the parts with a space in most places and a hyphen in a few, so
-- keys treat the two the same. The GUID is kept too: it never changes, so
-- it lets a tag follow someone through a name change.
---------------------------------------------------------------------------
local SEPARATOR = " "
do
	local consts = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
	if consts and type(consts.CHARACTERNAME_SURNAME_SEPARATOR) == "string" then
		SEPARATOR = consts.CHARACTERNAME_SURNAME_SEPARATOR
	end
end

function ns.FullName(name, surname)
	if not ns.IsText(name) then return nil end
	if ns.IsText(surname) then return name .. SEPARATOR .. surname end
	return name
end

function ns.Key(fullName)
	if not ns.IsText(fullName) then return nil end
	local key = fullName:lower():gsub("[%-%s]+", " ")
	key = ns.Trim(key)
	if key == "" then return nil end
	return key
end

ns.identifyMisses = 0

local function identify(unit)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
	local name, surname = UnitName(unit)
	if not ns.IsText(name) or name == _G.UNKNOWNOBJECT or name == _G.UNKNOWN then return nil end
	if surname ~= nil and ns.IsSecret(surname) then return nil end
	local full = ns.FullName(name, surname)
	local key = ns.Key(full)
	if not key then return nil end

	local id = { key = key, name = full, unit = unit, live = true }
	local guid = UnitGUID(unit)
	if ns.IsText(guid) then id.guid = guid end
	local _, class = UnitClass(unit)
	if ns.IsText(class) then id.class = class end
	local level = ns.Num(UnitLevel(unit))
	if level and level > 0 then id.level = level end
	local race = UnitRace(unit)
	if ns.IsText(race) then id.race = race end
	local faction = UnitFactionGroup(unit)
	if ns.IsText(faction) then id.faction = faction end
	return id
end

--- Who a unit token ("target", "nameplate3", "party1") is, or nil when it is
--- not a player or the game is hiding the answer.
function ns.IdentifyUnit(unit)
	if unit == nil or ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
	local ok, id = pcall(identify, unit)
	if not ok then
		ns.identifyMisses = ns.identifyMisses + 1
		return nil
	end
	return id
end

--- An identity built from a name alone (chat, lists, slash commands).
function ns.IdentifyName(fullName, guid)
	local key = ns.Key(fullName)
	if not key then return nil end
	local id = { key = key, name = ns.Trim(fullName) }
	if ns.IsText(guid) then id.guid = guid end
	return id
end

function ns.IsMe(id)
	return id ~= nil and id.key ~= nil and id.key == ns.myKey
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------
local function context()
	local zone = GetRealZoneText and GetRealZoneText() or nil
	if not ns.IsText(zone) then zone = GetZoneText and GetZoneText() or nil end
	if not ns.IsText(zone) then zone = nil end
	return { t = time(), zone = zone, by = ns.me }
end

function ns.GetRecord(key)
	return key and ns.db.players[key] or nil
end

function ns.GetRecordByGUID(guid)
	if not ns.IsText(guid) then return nil end
	local key = ns.guidIndex[guid]
	if not key then return nil end
	local rec = ns.db.players[key]
	if not rec then
		ns.guidIndex[guid] = nil
		return nil
	end
	return rec, key
end

-- A known GUID turned up under a new name: move the record to the new key.
local function rekey(oldKey, id)
	local players = ns.db.players
	local rec = players[oldKey]
	if not rec or players[id.key] then return rec, oldKey end
	players[oldKey] = nil
	players[id.key] = rec
	rec.formerName = rec.name
	rec.name = id.name
	ns.guidIndex[id.guid] = id.key
	ns.Fire("RECORD_CHANGED", oldKey)
	ns.Fire("RECORD_CHANGED", id.key)
	return rec, id.key
end

--- The record for an identity and its key, or nil. Follows renames by GUID.
function ns.Lookup(id)
	if not id then return nil end
	if id.guid then
		local rec, key = ns.GetRecordByGUID(id.guid)
		if rec then
			if id.live and id.key and key ~= id.key then
				return rekey(key, id)
			end
			return rec, key
		end
	end
	local rec = id.key and ns.db.players[id.key]
	if rec then return rec, id.key end
	return nil
end

-- Copies fresh facts from an identity onto its record.
local function absorb(rec, key, id)
	if id.live and id.name then rec.name = id.name end
	if id.guid then
		if rec.guid and rec.guid ~= id.guid then ns.guidIndex[rec.guid] = nil end
		rec.guid = id.guid
		ns.guidIndex[id.guid] = key
	end
	if id.class then rec.class = id.class end
	if id.level then rec.level = id.level end
	if id.race then rec.race = id.race end
	if id.faction then rec.faction = id.faction end
end

local function ensure(id)
	local rec, key = ns.Lookup(id)
	if not rec then
		key = id.key
		rec = { name = id.name, tags = {}, created = time() }
		ns.db.players[key] = rec
	end
	absorb(rec, key, id)
	return rec, key
end

-- A record with no tags and no note has nothing left to remember.
local function prune(rec, key)
	if next(rec.tags) == nil and not ns.IsText(rec.note) then
		ns.db.players[key] = nil
		if rec.guid then ns.guidIndex[rec.guid] = nil end
		return true
	end
	return false
end

function ns.HasTags(rec)
	return rec ~= nil and next(rec.tags) ~= nil
end

--- Tag ids on a record that still exist, sorted Avoid first.
function ns.TagIds(rec)
	local ids = {}
	if rec then
		for tagId in pairs(rec.tags) do
			if ns.GetTag(tagId) then ids[#ids + 1] = tagId end
		end
		ns.SortTagIds(ids)
	end
	return ids
end

function ns.SetTag(id, tagId, on)
	if not id or not id.key or not ns.GetTag(tagId) then return false end
	local rec, key
	if on then
		rec, key = ensure(id)
		if rec.tags[tagId] then return false end
		rec.tags[tagId] = context()
		rec.seen, rec.seenZone = rec.tags[tagId].t, rec.tags[tagId].zone
	else
		rec, key = ns.Lookup(id)
		if not rec or not rec.tags[tagId] then return false end
		rec.tags[tagId] = nil
		prune(rec, key)
	end
	ns.Fire("RECORD_CHANGED", key)
	return true
end

--- Flips a tag. Returns true when the tag is now on.
function ns.ToggleTag(id, tagId)
	local rec = ns.Lookup(id)
	local on = not (rec and rec.tags[tagId])
	ns.SetTag(id, tagId, on)
	return on
end

function ns.SetNote(id, text)
	if not id or not id.key then return false end
	text = ns.Trim(text)
	if #text > 200 then text = text:sub(1, 200) end
	local rec, key
	if text ~= "" then
		rec, key = ensure(id)
		if rec.note == text then return false end
		rec.note = text
	else
		rec, key = ns.Lookup(id)
		if not rec or rec.note == nil then return false end
		rec.note = nil
		prune(rec, key)
	end
	ns.Fire("RECORD_CHANGED", key)
	return true
end

function ns.DeleteRecord(key)
	local rec = ns.db.players[key]
	if not rec then return false end
	ns.db.players[key] = nil
	if rec.guid then ns.guidIndex[rec.guid] = nil end
	ns.Fire("RECORD_CHANGED", key)
	return true
end

--- Removes one tag from every player (used when a custom tag is deleted).
function ns.StripTag(tagId)
	for key, rec in pairs(ns.db.players) do
		if rec.tags[tagId] then
			rec.tags[tagId] = nil
			prune(rec, key)
		end
	end
	ns.Fire("RECORD_CHANGED")
end

local lastTouch = {}

--- Notes that a tagged player was just seen and refreshes class and level.
function ns.Touch(id)
	local rec, key = ns.Lookup(id)
	if not rec then return nil end
	local now = time()
	if (lastTouch[key] or 0) + 60 > now then return rec, key end
	lastTouch[key] = now
	absorb(rec, key, id)
	local c = context()
	rec.seen, rec.seenZone = c.t, c.zone
	return rec, key
end

function ns.PlayerCount()
	local n = 0
	for _ in pairs(ns.db.players) do n = n + 1 end
	return n
end

--- The newest tag on a record: when and where the player was last tagged.
function ns.LatestTag(rec)
	local best
	for _, info in pairs(rec.tags) do
		if type(info) == "table" and (not best or (info.t or 0) > (best.t or 0)) then best = info end
	end
	return best
end
