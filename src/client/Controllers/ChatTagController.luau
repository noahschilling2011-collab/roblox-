--!strict
-- ChatTagController: goldener [VIP]-Chat-Tag für Besitzer des VIP-Gamepasses.
-- Der Server setzt das Attribut "PlanetForgeVIP" (MonetizationService);
-- dieser Controller hängt den Tag clientseitig vor jede Chat-Nachricht.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTagController = {}

function ChatTagController.init()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if source == nil then
			return nil
		end
		local sender = Players:GetPlayerByUserId(source.UserId)
		if sender == nil or sender:GetAttribute("PlanetForgeVIP") ~= true then
			return nil
		end

		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = `<font color="#FFD25A">[VIP]</font> {message.PrefixText}`
		return properties
	end
end

return ChatTagController
