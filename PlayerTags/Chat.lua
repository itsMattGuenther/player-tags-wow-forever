-- Chat: tag icons in front of a tagged player's name.
--
-- Inside dungeons and raids the game hides chat senders from addons, so
-- no icons appear in chat there. That is the game's rule.
local _, ns = ...

-- The filter receives (event, decoratedName, ...) where ... are the chat
-- event's own arguments: 1 is the text, 2 the sender, 12 the sender's GUID.
local function decorate(decorated, ...)
	if not ns.IsText(decorated) then return nil end
	local rec
	local guid = select(12, ...)
	if ns.IsText(guid) then rec = ns.GetRecordByGUID(guid) end
	if not rec then
		local sender = select(2, ...)
		if ns.IsText(sender) then rec = ns.GetRecord(ns.Key(sender)) end
	end
	if not rec or not ns.HasTags(rec) then return nil end
	return ns.TagsEscape(ns.TagIds(rec), 0, 3) .. decorated
end

ns.Module("chat", function()
	if not (ChatFrameUtil and ChatFrameUtil.AddSenderNameFilter) then
		return "the chat name hook was not found"
	end
	ChatFrameUtil.AddSenderNameFilter(function(_, decorated, ...)
		if not ns.settings.chat then return nil end
		local ok, result = pcall(decorate, decorated, ...)
		if ok then return result end
		ns.Fail("chat", result)
		return nil
	end)
end)
