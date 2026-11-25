-- Minimap: a small round button on the rim of the minimap, and an entry in
-- the game's own addon list (the numbered button beside the minimap).
--   left-click    open or close your list
--   right-click   tag your target
--   drag          slide the button around the minimap
local _, ns = ...

local ICON = "Interface\\AddOns\\PlayerTags\\Media\\minimap"
local DEFAULT_ANGLE = 225 -- degrees, counter-clockwise from the right: lower left
local button
local dragging = false

local function act(mouseButton)
	if mouseButton == "RightButton" then
		ns.QuickTag()
	else
		ns.ToggleWindow()
	end
end

local function place()
	if not button then return end
	local angle = math.rad(tonumber(ns.db.positions.minimap) or DEFAULT_ANGLE)
	local reach = (Minimap:GetWidth() or 140) / 2 + 5
	local x, y = math.cos(angle), math.sin(angle)
	-- Addons that make the minimap square announce it through this function.
	local shape = _G.GetMinimapShape and _G.GetMinimapShape()
	if shape == "SQUARE" then
		local longest = math.max(math.abs(x), math.abs(y))
		x, y = x / longest, y / longest
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * reach, y * reach)
end

---------------------------------------------------------------------------
-- A free spot. Most addons' minimap buttons (LibDBIcon) also start at the
-- lower left, and the last one made covers the rest. So the first time,
-- the button takes the nearest spot on the rim that nobody else uses, and
-- keeps it. Dragging it anywhere still works as before.
---------------------------------------------------------------------------
local CANDIDATES = { 225, 250, 200, 270, 180, 290, 160, 310, 140, 330, 120, 350, 100, 10, 80, 30, 60 }
local SPACING = 24 -- degrees between two buttons' centres so they don't overlap

--- Angles of the other buttons sitting on the minimap's rim.
local function takenAngles()
	local taken = {}
	local mx, my = Minimap:GetCenter()
	if not (mx and my) then return taken end
	local radius = (Minimap:GetWidth() or 140) / 2
	for _, child in ipairs({ Minimap:GetChildren() }) do
		-- Only button-sized things count. The game also puts small pins on
		-- the rim (quest arrows and the like) that come and go.
		local width = child.GetWidth and child:GetWidth() or 0
		if child ~= button and child.IsShown and child:IsShown() and width >= 26 and width <= 40
			and child.GetObjectType and child:GetObjectType() == "Button" then
			local cx, cy = child:GetCenter()
			if cx and cy then
				local dx, dy = cx - mx, cy - my
				local distance = math.sqrt(dx * dx + dy * dy)
				if distance > radius - 15 and distance < radius + 30 then
					taken[#taken + 1] = math.deg(math.atan2(dy, dx)) % 360
				end
			end
		end
	end
	return taken
end

local function freeAngle()
	local taken = takenAngles()
	for _, angle in ipairs(CANDIDATES) do
		local clear = true
		for _, other in ipairs(taken) do
			if math.abs((angle - other + 180) % 360 - 180) < SPACING then
				clear = false
				break
			end
		end
		if clear then return angle end
	end
	return DEFAULT_ANGLE
end

--- Follows the mouse around the minimap while the button is being dragged.
local function follow()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	if not (mx and my and cx and cy and scale and scale > 0) then return end
	local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	ns.db.positions.minimap = math.floor(angle + 0.5)
	place()
end

--- The tooltip opens towards the middle of the screen, so it sits right
--- beside the button wherever the minimap is.
local function showTip(self)
	if dragging then return end
	local right, top = true, true
	local x, y = self:GetCenter()
	local cx, cy = UIParent:GetCenter()
	if x and y and cx and cy then
		local ratio = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
		right, top = x * ratio > cx, y * ratio > cy
	end
	local tip = GameTooltip
	tip:SetOwner(self, "ANCHOR_NONE")
	tip:ClearAllPoints()
	tip:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), self,
		(top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"), 0, 0)
	tip:SetText("Player Tags", 1, 0.82, 0)
	local count = ns.PlayerCount()
	tip:AddLine(count == 1 and "1 player tagged" or (count .. " players tagged"), 1, 1, 1)
	tip:AddLine(" ")
	tip:AddLine("Left-click: open your list", 0.75, 0.78, 0.82)
	tip:AddLine("Right-click: tag your target", 0.75, 0.78, 0.82)
	tip:AddLine("Drag: move this button", 0.75, 0.78, 0.82)
	tip:Show()
end

local function build()
	button = CreateFrame("Button", "PlayerTagsMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	-- Keeps the button above the map itself whatever the minimap is doing.
	if button.SetFixedFrameStrata then button:SetFixedFrameStrata(true) end
	if button.SetFixedFrameLevel then button:SetFixedFrameLevel(true) end
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetSize(24, 24)
	back:SetPoint("CENTER", 0, 1)
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetSize(20, 20)
	button.icon:SetPoint("CENTER", 0, 1)
	button.icon:SetTexture(ICON)

	local ring = button:CreateTexture(nil, "OVERLAY")
	ring:SetSize(50, 50)
	ring:SetPoint("TOPLEFT")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

	button:SetScript("OnClick", function(_, mouseButton)
		GameTooltip:Hide()
		ns.Safe("minimap button", act, mouseButton)
	end)
	button:SetScript("OnDragStart", function(self)
		dragging = true
		GameTooltip:Hide()
		self:SetScript("OnUpdate", follow)
	end)
	button:SetScript("OnDragStop", function(self)
		dragging = false
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", showTip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function apply()
	if ns.settings.minimap then
		if not button then build() end
		place()
		button:Show()
		-- Other addons make their buttons around login too; look once
		-- they are all there.
		if ns.db.positions.minimap == nil then
			C_Timer.After(2, function()
				if ns.db.positions.minimap ~= nil or not button then return end
				ns.db.positions.minimap = freeAngle()
				place()
			end)
		end
	elseif button then
		button:Hide()
	end
end

ns.Module("minimap button", function()
	if not _G.Minimap then return "this client has no minimap to attach to" end
	apply()
	ns.Listen("SETTINGS_CHANGED", apply, "minimap button")
end)

--- Named in the .toc: the game calls this when Player Tags is picked from
--- its addon list beside the minimap. That entry is there even when the
--- button above is switched off.
_G.PlayerTags_OnAddonCompartmentClick = function(_, mouseButton)
	ns.Safe("minimap button", act, mouseButton)
end
