-- Chat: tag icons in front of a tagged player's name.
--
-- Inside dungeons and raids the game hides chat senders from addons, so
-- no icons appear in chat there. That is the game's rule.
local _, ns = ...

-- The filter receives (event, decoratedName, ...) where ... are the chat
-- event's own arguments: 1 is the text, 2 the sender, 12 the sender's GUID.
local function onSender(decorated, ...)
	local rec, key
	local guid = select(12, ...)
	if ns.IsText(guid) then
		rec, key = ns.GetRecordByGUID(guid)
	else
		guid = nil
	end
	if not rec then
		local sender = select(2, ...)
		if ns.IsText(sender) then
			key = ns.Key(sender)
			rec = ns.GetRecord(key)
		end
	end
	if not rec then return nil end

	-- A chat line names the sender's GUID, and the game knows their class
	-- from it. Someone tagged from a name gets their class this way. The
	-- repaint waits a moment so it never runs inside the chat frame's work.
	if ns.Learn(rec, key, guid) then
		ns.Debounce("chat learned", 0.5, function() ns.Fire("RECORD_CHANGED") end)
	end

	if not ns.settings.chat or not ns.IsText(decorated) or not ns.HasTags(rec) then return nil end
	return ns.TagsEscape(ns.TagIds(rec), 0, 3) .. decorated
end

ns.Module("chat", function()
	if not (ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter) then
		return "the chat name hook was not found"
	end
	ChatFrameUtil.AddSenderNameFilter(function(_, decorated, ...)
		local ok, result = pcall(onSender, decorated, ...)
		if ok then return result end
		ns.Fail("chat", result)
		return nil
	end)
end)
