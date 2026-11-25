-- Finder: marks on Group Finder listings. Shows the leader's tags after
-- their name, and how many other members you have tagged.
--
-- Forever's Group Finder is loaded by the game only when first opened, so
-- this hooks in when that happens.
local _, ns = ...

local overlays = setmetatable({}, { __mode = "k" }) -- listing row -> our label
local hooked = false

local function clear(entry)
	local label = overlays[entry]
	if label then label:SetText("") end
end

local function mark(entry)
	if not ns.settings.finder then return clear(entry) end
	local resultID = entry.resultID
	if resultID == nil or ns.IsSecret(resultID) then return clear(entry) end

	local info = C_LFGList.GetSearchResultInfo(resultID)
	if type(info) ~= "table" then return clear(entry) end

	-- Your own tags, and shared lists' tags, for a name on the listing.
	local function idsFor(key)
		local ids = ns.DisplayIds(ns.TagsFor({ key = key }, ns.GetRecord(key), key))
		return ids
	end

	local leaderKey, leaderIds
	local leader = info.leaderName
	if ns.IsText(leader) then
		leaderKey = ns.Key(leader)
		leaderIds = leaderKey and idsFor(leaderKey)
		if leaderIds and #leaderIds == 0 then leaderIds = nil end
	end

	local others = 0
	if C_LFGList.GetSearchResultPlayerInfo then
		for i = 1, 40 do
			local ok, member = pcall(C_LFGList.GetSearchResultPlayerInfo, resultID, i)
			if not ok or type(member) ~= "table" then break end
			local name = member.name
			if ns.IsText(name) then
				local key = ns.Key(name)
				if key ~= leaderKey then
					if key and #idsFor(key) > 0 then others = others + 1 end
				end
			end
		end
	end

	local text = ""
	if leaderIds then text = ns.TagsEscape(leaderIds, 14, 3) end
	if others > 0 then text = text .. " |cffffd100+" .. others .. " tagged|r" end
	if text == "" then return clear(entry) end

	local label = overlays[entry]
	if not label then
		label = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		overlays[entry] = label
	end
	label:ClearAllPoints()
	local name = entry.Name
	if name then
		local ok, width = pcall(name.GetStringWidth, name)
		width = ok and ns.Num(width) or 0
		label:SetPoint("LEFT", name, "LEFT", width + 6, 0)
	else
		label:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
	end
	label:SetText(text)
end

local function safeMark(entry)
	local ok, err = pcall(mark, entry)
	if not ok then ns.Fail("group finder", err) end
end

local function refreshVisible()
	if not hooked then return end
	local browse = _G.LFGBrowseFrame
	local box = browse and browse.ScrollBox
	if not (browse and browse.IsVisible and browse:IsVisible() and box and box.GetFrames) then return end
	for _, entry in ipairs(box:GetFrames()) do
		if entry.resultID ~= nil then safeMark(entry) end
	end
end

local function tryHook()
	if hooked then return true end
	if type(_G.LFGBrowseSearchEntry_Update) ~= "function" then return false end
	if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return false end
	hooksecurefunc("LFGBrowseSearchEntry_Update", safeMark)
	hooked = true
	ns.moduleState["group finder"] = "ok"
	return true
end

ns.Module("group finder", function()
	if not tryHook() then
		ns.On("ADDON_LOADED", function() tryHook() end, "group finder")
	end
	ns.Listen("RECORD_CHANGED", refreshVisible, "group finder")
	ns.Listen("TAGS_CHANGED", refreshVisible, "group finder")
	ns.Listen("SETTINGS_CHANGED", refreshVisible, "group finder")
	ns.Listen("READY", function()
		if not hooked then ns.moduleState["group finder"] = "ok (starts when you first open the Group Finder)" end
	end, "group finder")
end)
