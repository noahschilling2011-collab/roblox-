--!strict
-- QuestService: drei Session-Aufträge mit Trümmer-Belohnung.
--
-- Kurzfristige, klare Ziele neben dem Runden-Loop (QuestConfig). Alles
-- wird SERVERSEITIG gezählt - über Hooks des TowerService (Platzierungen,
-- Gold) und des DisasterService (erlebte Katastrophen). Der Client zeigt
-- nur an (QuestsChanged) und kann nichts melden oder manipulieren.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local QuestConfig = require(Shared.Config.QuestConfig)

local DataService = require(script.Parent.DataService)
local SkinService = require(script.Parent.SkinService)
local TowerService = require(script.Parent.TowerService)
local DisasterService = require(script.Parent.DisasterService)

type QuestState = {
	progress: { [string]: number }, -- Quest-ID -> Zähler
	done: { [string]: boolean }, -- Quest-ID -> Belohnung ausgezahlt
}

local QuestService = {}

local states: { [Player]: QuestState } = {}

local questsChangedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

local function getState(player: Player): QuestState
	local state = states[player]
	if state == nil then
		state = { progress = {}, done = {} }
		states[player] = state
	end
	return state
end

local function fireQuests(player: Player)
	if questsChangedEvent == nil then
		return
	end
	local state = getState(player)
	local payload = {}
	for _, quest in QuestConfig.Quests do
		table.insert(payload, {
			text = quest.text,
			progress = math.min(state.progress[quest.id] or 0, quest.target),
			target = quest.target,
			reward = quest.rewardDebris,
			done = state.done[quest.id] == true,
		})
	end
	(questsChangedEvent :: RemoteEvent):FireClient(player, payload)
end

-- Zähler erhöhen; bei Zielerreichung Belohnung auszahlen (einmalig).
local function bump(player: Player, questId: string, amount: number)
	local state = getState(player)
	if state.done[questId] == true then
		return
	end
	state.progress[questId] = (state.progress[questId] or 0) + amount

	for _, quest in QuestConfig.Quests do
		if quest.id ~= questId or state.done[questId] == true then
			continue
		end
		if (state.progress[questId] or 0) >= quest.target then
			state.done[questId] = true
			local profile = DataService.getProfile(player)
			if profile ~= nil then
				profile.truemmer += quest.rewardDebris
				DataService.markDirty(player)
				SkinService.refresh(player)
			end
			if notificationEvent ~= nil then
				(notificationEvent :: RemoteEvent):FireClient(
					player,
					`✅ Auftrag geschafft: {quest.text} → +{quest.rewardDebris} 🧱!`,
					"success"
				)
			end
		end
	end
	fireQuests(player)
end

function QuestService.init()
	questsChangedEvent = Network.getEvent("QuestsChanged")
	notificationEvent = Network.getEvent("Notification")

	-- Hooks verdrahten (wir requiren die Quellen, nicht umgekehrt - kein Zyklus).
	local previousOnPlaced = TowerService.onPlaced
	TowerService.onPlaced = function(player: Player, golden: boolean)
		previousOnPlaced(player, golden)
		bump(player, "platzieren", 1)
		if golden then
			bump(player, "gold", 1)
		end
	end

	local previousOnEnded = DisasterService.onDisasterEnded
	DisasterService.onDisasterEnded = function(eventId: string)
		previousOnEnded(eventId)
		-- Alle anwesenden Spieler haben die Katastrophe miterlebt.
		for _, player in Players:GetPlayers() do
			bump(player, "katastrophe", 1)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			task.wait(2) -- UI zuerst aufbauen lassen
			fireQuests(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		fireQuests(player)
	end
end

return QuestService
