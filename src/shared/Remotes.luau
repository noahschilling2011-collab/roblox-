--!strict
-- Zentrale Definition aller RemoteEvents und RemoteFunctions.
-- Der Server erstellt die Instanzen einmalig über Remotes.init(),
-- Server und Client holen sie über Remotes.getEvent() / Remotes.getFunction().
--
-- Konventionen für Signaturen:
--
--   RemoteEvents (Server -> Client):
--     EnergyChanged(newEnergy: number, lifetimeEnergy: number)
--     PlanetUpdated(snapshot: { biomes: {...}, collectibles: {...}, visits: number, likes: number })
--     LootObtained(collectibleId: string, rarity: string, uid: string)
--     GlobalEventStarted(eventId: string, endsAt: number)
--     GlobalEventEnded(eventId: string)
--     TradeUpdated(tradeSnapshot: any?) -- nil = keine aktive Handelssitzung
--     Notification(message: string, kind: "info" | "success" | "error")
--
--   RemoteFunctions (Client -> Server), geben immer (ok: boolean, payload: any?) zurück:
--     PlaceBiome(biomeId: string, slot: number)
--     UpgradeBiome(slot: number)
--     CollectEnergy()
--     RollLoot()
--     RequestVisit(targetUserId: number)
--     GoHome()
--     LikePlanet(targetUserId: number)
--     TradeAction(action: "invite" | "acceptInvite" | "setOffer" | "toggleAccept" | "cancel", payload: any?)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "PlanetForgeRemotes"

local EVENT_NAMES = {
	"EnergyChanged",
	"PlanetUpdated",
	"LootObtained",
	"GlobalEventStarted",
	"GlobalEventEnded",
	"TradeUpdated",
	"Notification",
}

local FUNCTION_NAMES = {
	"PlaceBiome",
	"UpgradeBiome",
	"CollectEnergy",
	"RollLoot",
	"RequestVisit",
	"GoHome",
	"LikePlanet",
	"TradeAction",
}

local Remotes = {}

local function getFolder(): Folder
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Erstellt alle Remote-Instanzen. Darf nur einmal und nur auf dem Server laufen.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init() darf nur auf dem Server aufgerufen werden")
	assert(
		ReplicatedStorage:FindFirstChild(FOLDER_NAME) == nil,
		"Remotes.init() wurde bereits aufgerufen"
	)

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for _, name in EVENT_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end

	for _, name in FUNCTION_NAMES do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end

	folder.Parent = ReplicatedStorage
end

function Remotes.getEvent(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.getFunction(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
