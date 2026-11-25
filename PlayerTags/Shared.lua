-- Shared: tag lists other players gave you (they use Share, you Import).
--
-- They are kept apart from your own tags, on purpose:
--   * your own list never changes when you import someone else's;
--   * a list you were given is never in what you export or share, so lists
--     cannot snowball from player to player;
--   * shared tags look different (dimmer icons, "From <list>" in tooltips)
--     and do not set off alerts unless you turn alerts on for that list;
--   * a whole list goes away with one click.
--
-- Everything in a shared list is text from someone else, so every name,
-- note and list name is cleaned of the game's colour, texture and link
-- codes before it is stored, and lists and notes are capped in size.
local _, ns = ...

local MAX_PLAYERS, MAX_NOTE, MAX_NAME = 2000, 200, 60
ns.SHARED_LIMITS = { players = MAX_PLAYERS, note = MAX_NOTE, name = MAX_NAME }

--- Text from someone else, made safe to show. "|" starts the game's codes
--- for colours, icons and links, so those are taken out, and any "|" left
--- over is doubled, which the game shows as a plain "|". No control
--- characters; trimmed and cut to a length.
function ns.CleanText(value, max)
	if type(value) ~= "string" then return nil end
	local PIPE = "\1\1"
	value = value:gsub("||", PIPE)
	-- Whole codes first, so their letters do not end up in the text:
	-- colours, links (keeping the link's words), icons and atlases.
	value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|n", " ")
	-- Any other code the game might read: a "|" followed by a letter or digit.
	value = value:gsub("|[%w]", "")
	value = value:gsub("%c", function(c) return c == "\1" and c or " " end)
	value = value:gsub("|", "||"):gsub(PIPE, "||")
	value = ns.Trim(value)
	if value == "" then return nil end
	if max and #value > max then value = ns.Trim(value:sub(1, max)) end
	return value
end

ns.sharedIndex = {} -- player key -> { list id, ... }
ns.sharedGuid = {}  -- GUID -> player key

function ns.RebuildShared()
	local index, byGuid = {}, {}
	for listId, list in pairs(ns.db.shared or {}) do
		if type(list) == "table" and type(list.players) == "table" then
			for key, p in pairs(list.players) do
				local entry = index[key] or {}
				entry[#entry + 1] = listId
				index[key] = entry
				if type(p) == "table" and ns.IsText(p.guid) then byGuid[p.guid] = key end
			end
		end
	end
	ns.sharedIndex, ns.sharedGuid = index, byGuid
end

--- Shared lists, sorted by when they were added.
function ns.SharedLists()
	local lists = {}
	for listId, list in pairs(ns.db.shared or {}) do
		if type(list) == "table" then lists[#lists + 1] = { id = listId, list = list } end
	end
	table.sort(lists, function(a, b) return (a.list.added or 0) < (b.list.added or 0) end)
	return lists
end

function ns.SharedPlayerCount(list)
	local n = 0
	for _ in pairs(list.players or {}) do n = n + 1 end
	return n
end

function ns.RemoveSharedList(listId)
	if not ns.db.shared[listId] then return false end
	ns.db.shared[listId] = nil
	ns.RebuildShared()
	ns.Fire("RECORD_CHANGED")
	return true
end

function ns.SetSharedAlerts(listId, on)
	local list = ns.db.shared[listId]
	if not list then return end
	list.alerts = on and true or false
end

local function hasAvoid(ids)
	for _, tagId in ipairs(ids) do
		local tag = ns.GetTag(tagId)
		if tag and tag.family == "avoid" then return true end
	end
	return false
end
ns.HasAvoid = hasAvoid

--- Everything known about a player: your own record and tags, and what
--- any shared lists say. `id` is an identity (key and maybe GUID); a
--- record and key can be passed when already known. Returns nil when
--- there is nothing at all. The table:
---   rec, key       your own record, if any
---   ids            your own tag ids, Avoid first
---   shared         { { list = name, listId, ids, note, alerts }, ... }
---   avoid          one of your own tags is Avoid
---   sharedAvoid    a shared list with alerts on says Avoid
function ns.TagsFor(id, rec, key)
	if not rec and id then rec, key = ns.Lookup(id) end
	local info = { rec = rec, key = key or (id and id.key), ids = rec and ns.TagIds(rec) or {}, shared = {} }

	if ns.settings.showShared ~= false and next(ns.sharedIndex) ~= nil then
		local skey = (id and id.guid and ns.sharedGuid[id.guid]) or (id and id.key) or key
		local lists = skey and ns.sharedIndex[skey]
		if lists then
			local own = {}
			for _, tagId in ipairs(info.ids) do own[tagId] = true end
			for _, listId in ipairs(lists) do
				local list = ns.db.shared[listId]
				local p = list and list.players[skey]
				if p then
					local ids = {}
					for tagId in pairs(p.tags or {}) do
						if ns.GetTag(tagId) and not own[tagId] then ids[#ids + 1] = tagId end
					end
					ns.SortTagIds(ids)
					if #ids > 0 or ns.IsText(p.note) then
						info.shared[#info.shared + 1] = { list = list.name, listId = listId, ids = ids, note = p.note, alerts = list.alerts == true }
					end
				end
			end
		end
	end

	info.avoid = hasAvoid(info.ids)
	info.sharedAvoid = false
	for _, from in ipairs(info.shared) do
		if from.alerts and hasAvoid(from.ids) then info.sharedAvoid = true end
	end
	if #info.ids == 0 and #info.shared == 0 and not (rec and ns.IsText(rec.note)) then return nil end
	return info
end

--- The icons to draw for a player: your own tags first, then shared ones
--- you do not already have. The second value marks which are shared.
function ns.DisplayIds(info)
	if not info then return {}, nil end
	if #info.shared == 0 then return info.ids, nil end
	local ids, sharedSet, seen = {}, {}, {}
	for _, tagId in ipairs(info.ids) do
		ids[#ids + 1] = tagId
		seen[tagId] = true
	end
	for _, from in ipairs(info.shared) do
		for _, tagId in ipairs(from.ids) do
			if not seen[tagId] then
				ids[#ids + 1] = tagId
				sharedSet[tagId] = true
				seen[tagId] = true
			end
		end
	end
	return ids, sharedSet
end

--- True when an alert should fire for this player: one of your own tags
--- is Avoid, or a shared list you turned alerts on for says Avoid.
function ns.ShouldWarn(info)
	return info ~= nil and (info.avoid or info.sharedAvoid)
end
