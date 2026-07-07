--!strict
-- DailyRewardService: Tages-Bonus in Trümmern (Login-Serie).
--
-- Tägliches Wiederkommen ist der stärkste Retention-Hebel der
-- Roblox-Topspiele. Die Regeln sind pur und getestet (DailyLogic);
-- dieser Service wendet sie beim Beitritt auf das Profil an. Der Bonus
-- wird automatisch gutgeschrieben (kein Extra-Klick, kein Popup-Spam).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local DailyLogic = require(Shared.DailyLogic)

local DataService = require(script.Parent.DataService)
local SkinService = require(script.Parent.SkinService)

local DailyRewardService = {}

local notificationEvent: RemoteEvent? = nil

local function onPlayerAdded(player: Player)
	local profile = DataService.waitForProfile(player)
	if profile == nil then
		return
	end
	-- Read-only-Sessions bekommen keinen Bonus (würde nicht gespeichert
	-- und beim nächsten Join doppelt kassiert werden können).
	if not DataService.isSaveable(player) then
		return
	end

	local today = DailyLogic.dayNumber(os.time())
	local reward, newStreak =
		DailyLogic.claim(profile.lastDailyClaimDay, today, profile.dailyStreak, GameConfig.DAILY_REWARDS)
	if reward == nil then
		return -- heute schon kassiert
	end

	profile.lastDailyClaimDay = today
	profile.dailyStreak = newStreak
	profile.truemmer += reward :: number
	DataService.markDirty(player)
	SkinService.refresh(player)

	if notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireClient(
			player,
			`🎁 Tages-Bonus (Tag {newStreak}): +{reward} 🧱 Trümmer! Komm morgen wieder für mehr!`,
			"success"
		)
	end
end

function DailyRewardService.init()
	notificationEvent = Network.getEvent("Notification")

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DailyRewardService
