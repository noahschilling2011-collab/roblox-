--!strict
-- DailyRewardService: Tagesbonus mit Login-Streak.
--
-- Beim ersten Beitritt eines UTC-Tages erhält der Spieler automatisch Energie.
-- Aufeinanderfolgende Tage erhöhen den Streak (Tag 1..7); ein verpasster Tag
-- setzt auf Tag 1 zurück. Die Belohnungshöhen stehen in
-- GameConfig.DAILY_REWARDS (Tag 7+ = letzter Eintrag, der Streak-Zähler
-- läuft für die Anzeige weiter).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local MonetizationService = require(script.Parent.MonetizationService)

local SECONDS_PER_DAY = 24 * 60 * 60

local notificationEvent: RemoteEvent? = nil

local DailyRewardService = {}

-- UTC-Tagesnummer (ganze Tage seit Unix-Epoche).
local function currentDayNumber(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

-- Belohnung für einen Streak-Tag (über die Tabellenlänge hinaus: letzter Wert).
local function rewardForStreak(streak: number): number
	local rewards = GameConfig.DAILY_REWARDS
	local index = math.clamp(streak, 1, #rewards)
	return rewards[index]
end

local function claimIfDue(player: Player)
	local profile = DataService.waitForProfile(player)
	if profile == nil then
		return -- Spieler bereits weg
	end

	local today = currentDayNumber()
	if profile.lastDailyClaimDay >= today then
		return -- heute schon kassiert (oder Uhr lief rückwärts: nie doppelt zahlen)
	end

	local newStreak: number
	if profile.lastDailyClaimDay == today - 1 then
		newStreak = profile.dailyStreak + 1
	else
		newStreak = 1
	end

	local reward = rewardForStreak(newStreak)
	-- VIP-Gamepass: doppelter Tagesbonus.
	local isVip = MonetizationService.hasPass(player, "gp_vip")
	if isVip then
		reward *= 2
	end
	profile.lastDailyClaimDay = today
	profile.dailyStreak = newStreak
	DataService.markDirty(player)

	EnergyService.grantEnergy(player, reward)

	if notificationEvent ~= nil then
		local vipSuffix = if isVip then " (VIP: verdoppelt! 👑)" else ""
		(notificationEvent :: RemoteEvent):FireClient(
			player,
			`Tagesbonus Tag {newStreak}: +{reward} Energie!{vipSuffix} Komm morgen wieder.`,
			"success"
		)
	end
end

function DailyRewardService.init()
	notificationEvent = Remotes.getEvent("Notification")

	Players.PlayerAdded:Connect(function(player)
		task.spawn(claimIfDue, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(claimIfDue, player)
	end
end

return DailyRewardService
