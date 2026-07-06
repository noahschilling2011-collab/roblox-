--!strict
-- DeckService: zufällige Teilvergabe und die Hotbar jedes Spielers.
--
-- Während der Bauphase erhält jeder Spieler alle PART_DROP_INTERVAL_SECONDS
-- ein zufälliges Teil (gewichtete Verteilung aus PartCatalog.dropWeight).
-- Die Hotbar fasst maximal HOTBAR_MAX_ITEMS Teile - ist sie voll, verfällt
-- der Drop (mit Hinweis). Der Server ist die einzige Wahrheit über den
-- Hotbar-Inhalt; consumePart() ist die atomare Entnahme beim Platzieren.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared.Network)
local GameConfig = require(Shared.Config.GameConfig)
local PartCatalog = require(Shared.Config.PartCatalog)

local DeckService = {}

local hotbars: { [Player]: { string } } = {}
local dropsActive = false

local hotbarChangedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

local rng = Random.new()

local function fireHotbar(player: Player)
	local event = hotbarChangedEvent
	if event ~= nil then
		(event :: RemoteEvent):FireClient(player, table.clone(hotbars[player] or {}))
	end
end

local function notify(player: Player, message: string, kind: string)
	if notificationEvent ~= nil then
		(notificationEvent :: RemoteEvent):FireClient(player, message, kind)
	end
end

-- Gewichtete Zufallswahl eines Teiltyps.
local function rollPartType(): string
	local totalWeight = 0
	for _, def in PartCatalog.Parts do
		totalWeight += def.dropWeight
	end
	local roll = rng:NextNumber(0, totalWeight)
	local runningSum = 0
	-- Sortierte IDs für deterministische Reihenfolge der Kumulation.
	for _, id in PartCatalog.getSortedIds() do
		runningSum += PartCatalog.Parts[id].dropWeight
		if roll <= runningSum then
			return id
		end
	end
	return "leichtblock" -- numerischer Randfall
end

-- Gibt einem Spieler ein Teil (false, wenn die Hotbar voll ist).
function DeckService.grantPart(player: Player, partTypeId: string): boolean
	local hotbar = hotbars[player]
	if hotbar == nil then
		hotbar = {}
		hotbars[player] = hotbar
	end
	if #hotbar >= GameConfig.HOTBAR_MAX_ITEMS then
		return false
	end
	table.insert(hotbar, partTypeId)
	fireHotbar(player)
	return true
end

-- Atomare Entnahme beim Platzieren (TowerService).
function DeckService.consumePart(player: Player, partTypeId: string): boolean
	local hotbar = hotbars[player]
	if hotbar == nil then
		return false
	end
	local index = table.find(hotbar, partTypeId)
	if index == nil then
		return false
	end
	table.remove(hotbar, index)
	fireHotbar(player)
	return true
end

function DeckService.setDropsActive(active: boolean)
	dropsActive = active
end

-- Neue Runde: alle Hotbars leeren und jedem ein Startteil geben.
function DeckService.resetRound(withStartingPart: boolean)
	for _, player in Players:GetPlayers() do
		hotbars[player] = {}
		if withStartingPart then
			DeckService.grantPart(player, rollPartType())
		else
			fireHotbar(player)
		end
	end
end

function DeckService.init()
	hotbarChangedEvent = Network.getEvent("HotbarChanged")
	notificationEvent = Network.getEvent("Notification")

	Players.PlayerAdded:Connect(function(player)
		hotbars[player] = {}
	end)
	Players.PlayerRemoving:Connect(function(player)
		hotbars[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if hotbars[player] == nil then
			hotbars[player] = {}
		end
	end

	-- Drop-Schleife: läuft immer, wirkt nur während der Bauphase.
	task.spawn(function()
		while true do
			task.wait(GameConfig.PART_DROP_INTERVAL_SECONDS)
			if not dropsActive then
				continue
			end
			for _, player in Players:GetPlayers() do
				local partTypeId = rollPartType()
				if DeckService.grantPart(player, partTypeId) then
					local def = PartCatalog.Parts[partTypeId]
					notify(player, `Neues Teil: {def.icon} {def.displayName}`, "info")
				else
					notify(player, "Hotbar voll - Teil verfallen! Bau schneller!", "error")
				end
			end
		end
	end)
end

return DeckService
