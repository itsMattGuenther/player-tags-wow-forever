-- Core: namespace, safe calls, events, internal messages, module startup.
local ADDON, ns = ...

_G.PlayerTags = ns
ns.addon = ADDON
ns.TITLE = "Player Tags"

-- Key binding labels (Options > Keybindings > AddOns).
_G.BINDING_HEADER_PLAYERTAGS = "Player Tags"
_G.BINDING_NAME_PLAYERTAGS_TAG = "Tag target or mouseover player"
_G.BINDING_NAME_PLAYERTAGS_WINDOW = "Open the Player Tags list"

---------------------------------------------------------------------------
-- Secrets. Forever inherits Midnight's rule that some values reach addons
-- as "secrets" that cannot be read, compared or joined. Everything that
-- comes from a unit, a chat line or a tooltip goes through these checks.
---------------------------------------------------------------------------
local issecretvalue = _G.issecretvalue

function ns.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

--- A plain, readable, non-empty string.
function ns.IsText(v)
	if v == nil or ns.IsSecret(v) then return false end
	return type(v) == "string" and v ~= ""
end

--- A plain, readable number, or nil.
function ns.Num(v)
	if v == nil or ns.IsSecret(v) then return nil end
	if type(v) == "number" then return v end
	return nil
end

---------------------------------------------------------------------------
-- Output and error capture. Errors inside the addon are caught so one
-- broken surface never takes the others down. They are kept for
-- "/tags status" so they can be reported.
---------------------------------------------------------------------------
function ns.Print(msg)
	local frame = _G.DEFAULT_CHAT_FRAME
	if frame and frame.AddMessage then
		frame:AddMessage("|cffffd100Player Tags|r: " .. tostring(msg))
	end
end

ns.errors = {}
local errorCounts = {}
local errorNotices = 0

function ns.Fail(where, err)
	local text = tostring(where) .. ": " .. tostring(err)
	if errorCounts[text] then
		errorCounts[text] = errorCounts[text] + 1
		return
	end
	errorCounts[text] = 1
	ns.errors[#ns.errors + 1] = text
	if #ns.errors > 20 then table.remove(ns.errors, 1) end
	if errorNotices < 3 then
		errorNotices = errorNotices + 1
		ns.Print("|cffff5a52something went wrong in " .. tostring(where) .. ".|r Type |cffffd100/tags status|r to see it.")
	end
end

function ns.ErrorCount(text)
	return errorCounts[text] or 0
end

--- Calls fn(...) and returns its results, or nil after recording the error.
function ns.Safe(where, fn, ...)
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		ns.Fail(where, a)
		return nil
	end
	return a, b, c, d
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn, where)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			ns.Fail("events", "the game does not know the event " .. event)
		end
	end
	list[#list + 1] = { fn = fn, where = where or event }
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local h = list[i]
		local ok, err = pcall(h.fn, ...)
		if not ok then ns.Fail(h.where, err) end
	end
end)

---------------------------------------------------------------------------
-- Internal messages (RECORD_CHANGED, TAGS_CHANGED, SETTINGS_CHANGED)
---------------------------------------------------------------------------
local listeners = {}

function ns.Listen(message, fn, where)
	local list = listeners[message]
	if not list then
		list = {}
		listeners[message] = list
	end
	list[#list + 1] = { fn = fn, where = where or message }
end

function ns.Fire(message, ...)
	local list = listeners[message]
	if not list then return end
	for i = 1, #list do
		local h = list[i]
		local ok, err = pcall(h.fn, ...)
		if not ok then ns.Fail(h.where, err) end
	end
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
function ns.After(seconds, fn, where)
	C_Timer.After(seconds, function()
		local ok, err = pcall(fn)
		if not ok then ns.Fail(where or "timer", err) end
	end)
end

local pending = {}

--- Runs fn once after `seconds`, however many times it is requested meanwhile.
function ns.Debounce(key, seconds, fn)
	if pending[key] then return end
	pending[key] = true
	C_Timer.After(seconds, function()
		pending[key] = nil
		local ok, err = pcall(fn)
		if not ok then ns.Fail(key, err) end
	end)
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
function ns.Trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- "3 days ago" style age for a time() stamp.
function ns.Ago(stamp)
	if type(stamp) ~= "number" then return "" end
	local s = time() - stamp
	if s < 90 then return "just now" end
	if s < 3600 then return math.floor(s / 60) .. " min ago" end
	if s < 7200 then return "1 hour ago" end
	if s < 86400 then return math.floor(s / 3600) .. " hours ago" end
	local d = math.floor(s / 86400)
	if d < 2 then return "yesterday" end
	if d < 14 then return d .. " days ago" end
	if d < 60 then return math.floor(d / 7) .. " weeks ago" end
	if d < 730 then return math.floor(d / 30.4) .. " months ago" end
	return math.floor(d / 365) .. " years ago"
end

-- A name whose class is not known yet. Not white: white is the priest colour.
ns.UNKNOWN_CLASS_COLOR = "|cffa7afb8"

--- "|cffRRGGBB" for a class file name such as "WARRIOR", or a neutral grey
--- when the class is not known.
function ns.ClassColorCode(class)
	local c = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
	if c and c.r then
		return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
	end
	return ns.UNKNOWN_CLASS_COLOR
end

function ns.ColoredName(rec, fallback)
	local name = (rec and rec.name) or fallback or "?"
	return ns.ClassColorCode(rec and rec.class) .. name .. "|r"
end

---------------------------------------------------------------------------
-- Modules. Each surface registers an init function. A surface that fails
-- or finds its game hook missing is reported and skipped; the rest load.
---------------------------------------------------------------------------
local modules = {}
ns.moduleOrder = {}
ns.moduleState = {}

--- init returns nothing when it is running, or a string saying why it is not.
function ns.Module(name, init)
	modules[#modules + 1] = { name = name, init = init }
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	ns.InitDB()
	ns.ready = true
end, "startup")

ns.On("PLAYER_LOGIN", function()
	if not ns.ready then
		ns.InitDB()
		ns.ready = true
	end
	ns.me = ns.FullName(UnitName("player"))
	ns.myKey = ns.Key(ns.me)
	for i = 1, #modules do
		local m = modules[i]
		local ok, result = pcall(m.init)
		ns.moduleOrder[#ns.moduleOrder + 1] = m.name
		if not ok then
			ns.moduleState[m.name] = "failed"
			ns.Fail(m.name, result)
		elseif type(result) == "string" then
			ns.moduleState[m.name] = "off: " .. result
		else
			ns.moduleState[m.name] = "ok"
		end
	end
	ns.Fire("READY")
end, "startup")
