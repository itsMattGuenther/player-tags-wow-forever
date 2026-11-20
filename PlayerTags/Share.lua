-- Share: export and import as plain text, for backups and for moving your
-- list between computers. Nothing is ever sent anywhere: export fills a
-- text box you copy from, import reads a text box you paste into.
--
-- Format, one item per line:
--   PlayerTags export 1
--   T;<tag id>;<name>;<family>;<glyph>                        custom tags
--   P;<name>;<guid>;<class>;<level>;<seen>;<zone>;<note>;<tags>
-- where <tags> is  id~time~zone~taggedBy  joined by commas.
-- Free text is percent-encoded so it can never break the layout.
local _, ns = ...

local HEADER = "PlayerTags export 1"

local function enc(value)
	if value == nil then return "" end
	return (tostring(value):gsub("[%%;,~|%c]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

local function dec(value)
	if value == nil or value == "" then return nil end
	return (value:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function split(line, separator)
	local fields = {}
	for field in (line .. separator):gmatch("(.-)" .. separator) do
		fields[#fields + 1] = field
	end
	return fields
end

--- Everything you have tagged, as text.
function ns.Export()
	local lines = { HEADER }

	local usedCustom = {}
	local names = {}
	for key, rec in pairs(ns.db.players) do
		names[#names + 1] = key
		for tagId in pairs(rec.tags) do
			local tag = ns.GetTag(tagId)
			if tag and not tag.builtin then usedCustom[tagId] = tag end
		end
	end
	table.sort(names)

	local customIds = {}
	for tagId in pairs(usedCustom) do customIds[#customIds + 1] = tagId end
	table.sort(customIds)
	for _, tagId in ipairs(customIds) do
		local tag = usedCustom[tagId]
		lines[#lines + 1] = table.concat({ "T", enc(tagId), enc(tag.name), enc(tag.family), enc(tag.glyph) }, ";")
	end

	for _, key in ipairs(names) do
		local rec = ns.db.players[key]
		local tags = {}
		local ids = {}
		for tagId in pairs(rec.tags) do ids[#ids + 1] = tagId end
		table.sort(ids)
		for _, tagId in ipairs(ids) do
			local info = rec.tags[tagId]
			if type(info) ~= "table" then info = {} end
			tags[#tags + 1] = table.concat({ enc(tagId), enc(info.t), enc(info.zone), enc(info.by) }, "~")
		end
		lines[#lines + 1] = table.concat({
			"P", enc(rec.name), enc(rec.guid), enc(rec.class), enc(rec.level),
			enc(rec.seen), enc(rec.seenZone), enc(rec.note), table.concat(tags, ","),
		}, ";")
	end

	return table.concat(lines, "\n"), #names
end

--- Merges exported text into your list. Existing tags and notes are kept;
--- only what is missing gets added. Returns a summary, or nil and a reason.
function ns.Import(text)
	if type(text) ~= "string" then return nil, "There is nothing to import." end
	local lines = {}
	for line in text:gmatch("[^\r\n]+") do
		line = ns.Trim(line)
		if line ~= "" then lines[#lines + 1] = line end
	end
	if #lines == 0 then return nil, "There is nothing to import." end
	if lines[1]:sub(1, 17) ~= "PlayerTags export" then
		return nil, "That text is not a Player Tags export. It should start with \"" .. HEADER .. "\"."
	end

	local idMap = {} -- tag id in the text -> tag id here
	local added, merged, newTags, skipped = 0, 0, 0, 0

	for i = 2, #lines do
		local fields = split(lines[i], ";")
		local kind = fields[1]

		if kind == "T" then
			local theirId, name = dec(fields[2]), dec(fields[3])
			if theirId and name then
				local mine = ns.FindTag(name)
				local existing = mine and ns.GetTag(mine)
				if existing and existing.name:lower() == name:lower() then
					idMap[theirId] = mine
				else
					local created = ns.SaveTag(nil, { name = name, family = dec(fields[4]), glyph = tonumber(dec(fields[5]) or "") })
					if created then
						idMap[theirId] = created
						newTags = newTags + 1
					end
				end
			end

		elseif kind == "P" then
			local name = dec(fields[2])
			local id = name and ns.IdentifyName(name, dec(fields[3]))
			if not id then
				skipped = skipped + 1
			else
				local rec, key = ns.Lookup(id)
				local isNew = rec == nil
				if isNew then
					key = id.key
					rec = { name = id.name, tags = {}, created = time() }
				end

				local gained = false
				for _, part in ipairs(split(fields[9] or "", ",")) do
					if part ~= "" then
						local bits = split(part, "~")
						local theirId = dec(bits[1])
						local tagId = theirId and (idMap[theirId] or theirId)
						if tagId and ns.GetTag(tagId) and not rec.tags[tagId] then
							rec.tags[tagId] = { t = tonumber(dec(bits[2]) or "") or time(), zone = dec(bits[3]), by = dec(bits[4]) }
							gained = true
						end
					end
				end
				local note = dec(fields[8])
				if note and not ns.IsText(rec.note) then
					rec.note = note
					gained = true
				end

				if next(rec.tags) == nil and not ns.IsText(rec.note) then
					skipped = skipped + 1
				else
					if isNew then
						ns.db.players[key] = rec
						added = added + 1
					elseif gained then
						merged = merged + 1
					end
					if not rec.guid and id.guid then rec.guid = id.guid end
					if rec.guid then ns.guidIndex[rec.guid] = key end
					if not rec.class then rec.class = dec(fields[4]) end
					if not rec.level then rec.level = tonumber(dec(fields[5]) or "") end
					local seen = tonumber(dec(fields[6]) or "")
					if seen and (not rec.seen or seen > rec.seen) then
						rec.seen, rec.seenZone = seen, dec(fields[7])
					end
				end
			end
		end
	end

	ns.Fire("RECORD_CHANGED")
	local summary = string.format("Imported: %d new players, %d updated", added, merged)
	if newTags > 0 then summary = summary .. ", " .. newTags .. " new tags" end
	if skipped > 0 then summary = summary .. ", " .. skipped .. " lines skipped" end
	return summary .. "."
end
