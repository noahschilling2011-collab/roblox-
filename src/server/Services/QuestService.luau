--!strict
-- QuestService: drei kleine Session-Quests, damit jede Session ein Ziel hat.
--
-- Die Quests sind bewusst session-basiert (kein Persistenz-Schema): Beim
-- Beitritt werden Baselines aus dem Profil gemerkt, der Fortschritt ergibt
-- sich aus der Differenz. Abschluss wird serverseitig erkannt und mit
-- Energie belohnt (grantEnergy, profitiert von Multiplikatoren).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)

local CHECK_INTERVAL_SECONDS = 3

type QuestDef = {
	id: string,
	text: string,
	target: number,
	reward: number,
	-- Fortschritt relativ zur Session-Baseline.
	measure: (profile: Types.PlayerProfile, baseline: { [string]: number }) -> number,
}

local QUESTS: { QuestDef } = {
	{
		id = "sammeln",
		text = "Sammle 60 Objekte",
		target = 60,
		reward = 150,
		measure = function(profile, baseline)
			return profile.stats.collected - baseline.collected
		end,
	},
	{
		id = "verkaufen",
		text = "Verkaufe 5-mal",
		target = 5,
		reward = 200,
		measure = function(profile, baseline)
			return profile.stats.sales - baseline.sales
		end,
	},
	{
		id = "bauen",
		text = "Kaufe 2 Upgrades oder Biome",
		target = 2,
		reward = 250,
		measure = function(profile, baseline)
			local builds = #profile.biomes + profile.upgrades.magnet + profile.upgrades.backpack
			return builds - baseline.builds
		end,
	},
}

type SessionState = {
	baseline: { [string]: number },
	done: { [string]: boolean },
	lastSent: string, -- Serialisierung des letzten Stands (nur bei Änderung senden)
}

local states: { [Player]: SessionState } = {}

local questsUpdatedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

local QuestService = {}

local function buildBaseline(profile: Types.PlayerProfile): { [string]: number }
	return {
		collected = profile.stats.collected,
		sales = profile.stats.sales,
		builds = #profile.biomes + profile.upgrades.magnet + profile.upgrades.backpack,
	}
end

-- Prüft Fortschritt, vergibt Belohnungen und meldet Änderungen an den Client.
local function updatePlayer(player: Player)
	local state = states[player]
	local profile = DataService.getProfile(player)
	if state == nil or profile == nil then
		return
	end

	local payload = {}
	local serialized = ""
	for _, quest in QUESTS do
		local progress = math.clamp(quest.measure(profile, state.baseline), 0, quest.target)
		local done = state.done[quest.id] == true

		if not done and progress >= quest.target then
			state.done[quest.id] = true
			done = true
			EnergyService.grantEnergy(player, quest.reward)
			if notificationEvent ~= nil then
				(notificationEvent :: RemoteEvent):FireClient(
					player,
					`Quest geschafft: {quest.text} (+{quest.reward} ⚡)`,
					"success"
				)
			end
		end

		table.insert(payload, {
			text = quest.text,
			progress = progress,
			target = quest.target,
			reward = quest.reward,
			done = done,
		})
		serialized ..= `{quest.id}:{progress}:{tostring(done)};`
	end

	if serialized ~= state.lastSent and questsUpdatedEvent ~= nil then
		state.lastSent = serialized;
		(questsUpdatedEvent :: RemoteEvent):FireClient(player, payload)
	end
end

function QuestService.init()
	questsUpdatedEvent = Remotes.getEvent("QuestsUpdated")
	notificationEvent = Remotes.getEvent("Notification")

	local function onPlayerAdded(player: Player)
		task.spawn(function()
			local profile = DataService.waitForProfile(player)
			if profile == nil then
				return
			end
			states[player] = {
				baseline = buildBaseline(profile),
				done = {},
				lastSent = "",
			}
			updatePlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL_SECONDS)
			for _, player in Players:GetPlayers() do
				updatePlayer(player)
			end
		end
	end)
end

return QuestService
