-- Tags: the four families, the starter tags, and custom or edited tags.
local _, ns = ...

-- Listed in the order they appear in the tagging popup.
ns.FAMILIES = {
	{ id = "good",  name = "Good people",  r = 0.29, g = 0.86, b = 0.41 },
	{ id = "skill", name = "Skilled",      r = 0.35, g = 0.66, b = 1.00 },
	{ id = "info",  name = "Good to know", r = 0.85, g = 0.87, b = 0.89 },
	{ id = "avoid", name = "Avoid",        r = 1.00, g = 0.35, b = 0.32 },
}
ns.familyById = {}
for i, family in ipairs(ns.FAMILIES) do
	family.order = i
	ns.familyById[family.id] = family
end

-- Where space is tight (nameplates, chat) warnings come first.
local PRIORITY = { avoid = 1, skill = 2, good = 3, info = 4 }

-- id, family, name, description, glyph index in Media/glyphs.tga.
-- Ids are saved with every tagged player: never rename or reuse one.
local BUILTIN = {
	{ "helpful",  "good",  "Helpful",      "Goes out of their way for you",       0 },
	{ "company",  "good",  "Good Company", "Fun to group with",                   1 },
	{ "generous", "good",  "Generous",     "Free portals, water, mats or tips",   2 },
	{ "reliable", "good",  "Reliable",     "Stays until the job is done",         3 },
	{ "patient",  "good",  "Patient",      "Explains fights, forgives wipes",     4 },

	{ "tank",     "skill", "Great Tank",   "Holds everything, knows the pulls",   5 },
	{ "healer",   "skill", "Great Healer", "Nobody dies on their watch",          6 },
	{ "damage",   "skill", "Big Damage",   "Things melt",                         7 },
	{ "pvp",      "skill", "PvP God",      "Beat you and made it look easy",      8 },
	{ "leader",   "skill", "Good Leader",  "Runs a tidy group",                   9 },

	{ "hitrun",   "info",  "Hit & Run",    "Gets what they need, then leaves",    10 },
	{ "quiet",    "info",  "Quiet",        "Never says a word",                   11 },
	{ "crafter",  "info",  "Crafter",      "Has a recipe you need",               12 },
	{ "rival",    "info",  "Rival",        "You keep meeting in PvP",             13 },
	{ "newbie",   "info",  "New Player",   "Still learning, go easy",             14 },
	{ "afk",      "info",  "Goes AFK",     "Wanders off in the middle of a run",  15 },

	{ "rude",     "avoid", "Rude",         "Abuse or profanity in chat",          16 },
	{ "leaver",   "avoid", "Leaver",       "Quits in the middle of a run",        17 },
	{ "ninja",    "avoid", "Ninja Looter", "Rolls Need on everything",            18 },
	{ "ganker",   "avoid", "Ganker",       "Camps low-level players",             19 },
	{ "scammer",  "avoid", "Scammer",      "Cheats on trades or crafts",          20 },
	{ "griefer",  "avoid", "Griefer",      "Steals tags and nodes, trains mobs",  21 },
}

ns.GLYPH_COUNT = 32 -- cells in the atlas; 22..31 are spares for custom tags

local defs = {}     -- id -> merged definition
local ordered = {}  -- every tag, in popup order

local function validFamily(id)
	return ns.familyById[id] and id or "info"
end

local function validGlyph(i)
	i = tonumber(i)
	if i and i >= 0 and i < ns.GLYPH_COUNT then return math.floor(i) end
	return 30 -- question mark
end

--- Rebuilds the merged tag list from the starter tags plus saved edits.
function ns.RebuildTags()
	local saved = ns.db and ns.db.tagdefs or { custom = {}, override = {}, hidden = {} }
	defs, ordered = {}, {}

	for index, row in ipairs(BUILTIN) do
		local id = row[1]
		local o = saved.override[id]
		defs[id] = {
			id = id,
			family = validFamily(o and o.family or row[2]),
			name = (o and ns.IsText(o.name) and o.name) or row[3],
			desc = row[4],
			glyph = validGlyph(o and o.glyph or row[5]),
			builtin = true,
			edited = o ~= nil,
			hidden = saved.hidden[id] == true,
			index = index,
		}
	end

	for id, c in pairs(saved.custom) do
		if type(c) == "table" and ns.IsText(c.name) and not defs[id] then
			defs[id] = {
				id = id,
				family = validFamily(c.family),
				name = c.name,
				desc = "Your own tag",
				glyph = validGlyph(c.glyph),
				builtin = false,
				hidden = saved.hidden[id] == true,
				index = 1000 + (tonumber(c.n) or 0),
			}
		end
	end

	for _, tag in pairs(defs) do ordered[#ordered + 1] = tag end
	table.sort(ordered, function(a, b)
		local fa, fb = ns.familyById[a.family].order, ns.familyById[b.family].order
		if fa ~= fb then return fa < fb end
		return a.index < b.index
	end)
	for position, tag in ipairs(ordered) do
		tag.position = position
		tag.rank = PRIORITY[tag.family] * 10000 + position
	end
end

function ns.GetTag(id)
	return id and defs[id] or nil
end

--- Every tag in popup order. Hidden tags are left out unless asked for.
function ns.AllTags(includeHidden)
	local list = {}
	for _, tag in ipairs(ordered) do
		if includeHidden or not tag.hidden then list[#list + 1] = tag end
	end
	return list
end

function ns.TagColor(id)
	local tag = defs[id]
	local family = ns.familyById[tag and tag.family or "info"]
	return family.r, family.g, family.b
end

--- Sorts tag ids the way small surfaces show them: Avoid first.
function ns.SortTagIds(ids)
	table.sort(ids, function(a, b)
		local ta, tb = defs[a], defs[b]
		return (ta and ta.rank or 0) < (tb and tb.rank or 0)
	end)
	return ids
end

local function squash(s)
	return (tostring(s):lower():gsub("[^%w]", ""))
end

--- Finds a tag from what someone typed: an id, a name, or the start of a name.
function ns.FindTag(text)
	local want = squash(text or "")
	if want == "" then return nil end
	local prefix, prefixCount
	for _, tag in ipairs(ordered) do
		local name = squash(tag.name)
		if tag.id == want or name == want then return tag.id end
		if name:sub(1, #want) == want then
			prefix = tag.id
			prefixCount = (prefixCount or 0) + 1
		end
	end
	if prefixCount == 1 then return prefix end
	return nil
end

--- Creates a custom tag (id nil) or edits an existing tag. Returns the id.
function ns.SaveTag(id, fields)
	local saved = ns.db.tagdefs
	local name = ns.Trim(fields.name)
	if name == "" then return nil, "A tag needs a name." end
	if #name > 24 then name = name:sub(1, 24) end

	local existing = id and defs[id]
	for _, tag in ipairs(ordered) do
		if tag.id ~= id and squash(tag.name) == squash(name) then
			return nil, "Another tag is already called " .. tag.name .. "."
		end
	end

	if existing and existing.builtin then
		saved.override[id] = { name = name, family = validFamily(fields.family), glyph = validGlyph(fields.glyph) }
	else
		if not existing then
			saved.nextCustom = (saved.nextCustom or 1)
			id = "c" .. saved.nextCustom
			while defs[id] or saved.custom[id] do
				saved.nextCustom = saved.nextCustom + 1
				id = "c" .. saved.nextCustom
			end
			saved.custom[id] = { n = saved.nextCustom }
			saved.nextCustom = saved.nextCustom + 1
		end
		local c = saved.custom[id]
		c.name, c.family, c.glyph = name, validFamily(fields.family), validGlyph(fields.glyph)
	end

	ns.RebuildTags()
	ns.Fire("TAGS_CHANGED")
	return id
end

--- Puts a starter tag back to its original name, family and picture.
function ns.ResetTag(id)
	if ns.db.tagdefs.override[id] then
		ns.db.tagdefs.override[id] = nil
		ns.RebuildTags()
		ns.Fire("TAGS_CHANGED")
	end
end

--- Hidden tags stay on players who already have them but leave the popup.
function ns.SetTagHidden(id, hidden)
	if not defs[id] then return end
	ns.db.tagdefs.hidden[id] = hidden and true or nil
	ns.RebuildTags()
	ns.Fire("TAGS_CHANGED")
end

--- Deletes a custom tag and takes it off every player who had it.
function ns.DeleteTag(id)
	local tag = defs[id]
	if not tag or tag.builtin then return false end
	ns.db.tagdefs.custom[id] = nil
	ns.db.tagdefs.hidden[id] = nil
	ns.RebuildTags()
	ns.StripTag(id)
	ns.Fire("TAGS_CHANGED")
	return true
end

function ns.BuiltinTagCount()
	return #BUILTIN
end
