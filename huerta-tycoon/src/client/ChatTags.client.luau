-- VIP chat tag (the server sets the "VIP" attribute on players who own the pass).
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local props = Instance.new("TextChatMessageProperties")
	local source = message.TextSource
	if source then
		local player = Players:GetPlayerByUserId(source.UserId)
		if player and player:GetAttribute("VIP") then
			props.PrefixText = "<font color='#FFC83D'>[VIP]</font> " .. message.PrefixText
		end
	end
	return props
end
