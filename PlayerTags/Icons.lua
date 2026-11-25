-- Icons: the glyph atlas, inline icons for text, and badge widgets.
local ADDON, ns = ...

-- 512x256, 8 columns of 64px cells, white on transparent so one picture
-- can be tinted to any family colour.
local ATLAS = "Interface\\AddOns\\" .. ADDON .. "\\Media\\glyphs"
local ATLAS_W, ATLAS_H, CELL, COLS = 512, 256, 64, 8

ns.ATLAS = ATLAS

local function cell(index)
	local col = index % COLS
	local row = (index - col) / COLS
	return col * CELL, (col + 1) * CELL, row * CELL, (row + 1) * CELL
end

--- Texture coordinates (0..1) for a glyph.
function ns.GlyphCoords(index)
	local x1, x2, y1, y2 = cell(index)
	return x1 / ATLAS_W, x2 / ATLAS_W, y1 / ATLAS_H, y2 / ATLAS_H
end

local escapes = {}

--- A tag's icon as text markup, for chat lines, tooltips and labels.
--- size 0 means "as tall as the surrounding text".
function ns.TagEscape(tagId, size)
	size = size or 0
	local cacheKey = tagId .. ":" .. size
	local found = escapes[cacheKey]
	if found then return found end
	local tag = ns.GetTag(tagId)
	if not tag then return "" end
	local x1, x2, y1, y2 = cell(tag.glyph)
	local r, g, b = ns.TagColor(tagId)
	found = string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d:%d:%d:%d|t",
		ATLAS, size, size, ATLAS_W, ATLAS_H, x1, x2, y1, y2,
		math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
	escapes[cacheKey] = found
	return found
end

--- Several tags as text markup. Shows at most `max`, then "+N".
function ns.TagsEscape(ids, size, max)
	local n = #ids
	if n == 0 then return "" end
	local shown = (max and n > max) and max or n
	local parts = {}
	for i = 1, shown do parts[i] = ns.TagEscape(ids[i], size) end
	local text = table.concat(parts)
	if n > shown then text = text .. "|cffbbbbbb+" .. (n - shown) .. "|r" end
	return text
end

--- "Rude, Great Tank"
function ns.TagNames(ids)
	local parts = {}
	for i = 1, #ids do
		local tag = ns.GetTag(ids[i])
		parts[#parts + 1] = tag and tag.name or ids[i]
	end
	return table.concat(parts, ", ")
end

ns.Listen("TAGS_CHANGED", function() escapes = {} end, "icons")

---------------------------------------------------------------------------
-- Badge: a small dark square with a family-coloured border and glyph.
---------------------------------------------------------------------------
local function setEdge(tex, r, g, b)
	tex:SetColorTexture(r, g, b, 1)
end

function ns.CreateBadge(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetColorTexture(0.05, 0.07, 0.09, 0.92)

	local top, bottom = f:CreateTexture(nil, "BORDER"), f:CreateTexture(nil, "BORDER")
	local left, right = f:CreateTexture(nil, "BORDER"), f:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT") top:SetPoint("TOPRIGHT") top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT") bottom:SetHeight(1)
	left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(1)
	right:SetPoint("TOPRIGHT") right:SetPoint("BOTTOMRIGHT") right:SetWidth(1)
	f.edges = { top, bottom, left, right }

	f.glyph = f:CreateTexture(nil, "ARTWORK")
	f.glyph:SetPoint("TOPLEFT", 1, -1)
	f.glyph:SetPoint("BOTTOMRIGHT", -1, 1)
	f.glyph:SetTexture(ATLAS)

	function f:SetGlyph(index, r, g, b)
		self.glyph:SetTexCoord(ns.GlyphCoords(index))
		self.glyph:SetVertexColor(r, g, b)
		for i = 1, 4 do setEdge(self.edges[i], r, g, b) end
	end

	function f:SetTag(tagId)
		local tag = ns.GetTag(tagId)
		self.tagId = tag and tagId or nil
		if not tag then
			self:Hide()
			return
		end
		self:SetGlyph(tag.glyph, ns.TagColor(tagId))
		self:Show()
	end

	--- Dims a badge that is "off" (used by the tagging popup and editor).
	function f:SetDim(dim)
		self.glyph:SetAlpha(dim and 0.55 or 1)
		for i = 1, 4 do self.edges[i]:SetAlpha(dim and 0.25 or 1) end
	end

	--- A tag from someone's shared list, not your own: a fainter border
	--- and icon, so the two can be told apart at a glance.
	function f:SetShared(shared)
		self.glyph:SetAlpha(shared and 0.7 or 1)
		for i = 1, 4 do self.edges[i]:SetAlpha(shared and 0.35 or 1) end
		self.bg:SetAlpha(shared and 0.5 or 1)
	end

	return f
end

---------------------------------------------------------------------------
-- Badge row: several badges side by side, with "+N" when there are more.
---------------------------------------------------------------------------
function ns.CreateBadgeRow(parent, size, spacing)
	local row = CreateFrame("Frame", nil, parent)
	row.size = size
	row.spacing = spacing or 2
	row.badges = {}
	row.count = 0
	row:SetSize(size, size)

	row.more = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.more:Hide()

	function row:SetBadgeSize(newSize)
		if newSize == self.size then return end
		self.size = newSize
		for i, badge in ipairs(self.badges) do
			badge:SetSize(newSize, newSize)
			badge:ClearAllPoints()
			badge:SetPoint("LEFT", self, "LEFT", (i - 1) * (newSize + self.spacing), 0)
		end
		self:SetHeight(newSize)
	end

	--- Shows the given tag ids, at most `max` of them. Hides itself when
	--- empty. `shared` marks ids that come from someone's shared list.
	function row:SetTags(ids, max, shared)
		local n = ids and #ids or 0
		local shown = (max and n > max) and max or n
		for i = 1, shown do
			local badge = self.badges[i]
			if not badge then
				badge = ns.CreateBadge(self, self.size)
				badge:SetPoint("LEFT", self, "LEFT", (i - 1) * (self.size + self.spacing), 0)
				self.badges[i] = badge
			end
			badge:SetTag(ids[i])
			badge:SetShared(shared ~= nil and shared[ids[i]] == true)
		end
		for i = shown + 1, #self.badges do self.badges[i]:Hide() end

		local width = shown * self.size + math.max(0, shown - 1) * self.spacing
		if n > shown then
			self.more:SetText("+" .. (n - shown))
			self.more:ClearAllPoints()
			self.more:SetPoint("LEFT", self, "LEFT", width + 2, 0)
			self.more:Show()
			width = width + 2 + (self.more:GetStringWidth() or 12)
		else
			self.more:Hide()
		end

		self.count = n
		self:SetWidth(math.max(width, 1))
		if n == 0 then self:Hide() else self:Show() end
	end

	row:Hide()
	return row
end
