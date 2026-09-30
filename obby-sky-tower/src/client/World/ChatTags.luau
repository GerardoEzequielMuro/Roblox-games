--!strict
-- Chat prefixes: [VIP] for pass owners, [N Wins] for tower winners (TextChatService).
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Lang = require(script.Parent.Parent.Lang)

local ChatTags = {}

function ChatTags.init()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local props = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local p = Players:GetPlayerByUserId(source.UserId)
			if p then
				local prefix = ""
				if p:GetAttribute("VIP") == true then
					prefix ..= "<font color='#FFD24A'>[VIP]</font> "
				end
				local ls = p:FindFirstChild("leaderstats")
				local wins = ls and ls:FindFirstChild("Wins")
				if wins and wins:IsA("IntValue") and wins.Value > 0 then
					prefix ..= ("<font color='#7FD8FF'>[%s]</font> "):format(Lang.t("chat.wins", { n = wins.Value }))
				end
				if prefix ~= "" then
					props.PrefixText = prefix .. message.PrefixText
				end
			end
		end
		return props
	end
end

return ChatTags
