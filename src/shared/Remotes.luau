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
--     CosmeticsUpdated(owned: { string }, equipped: { [string]: string })
--     LeaderboardUpdated(boards: { likes: { LBEntry }, energy: { LBEntry } })
--       mit LBEntry = { userId: number, name: string, value: number }
--     TutorialUpdated(step: number) -- 1..4 = offener Schritt, 5 = abgeschlossen
--     ObjectCollected(position: Vector3, value: number, color: Color3) -- für Sammel-Effekte
--     BackpackChanged(items: number, capacity: number, value: number)
--     SoldBackpack(gainedEnergy: number, itemsSold: number)
--     UpgradesUpdated(levels: { magnet: number, backpack: number })
--     MultiplierChanged(info: { total, biomeBonus, upgradeBonus, petBonus,
--       rebirthMultiplier, rebirths, nextThreshold, lifetimeEnergy })
--     EquipmentUpdated(equipped: { pets: { uid }, trail: uid?, skin: uid?, maxPetSlots: number })
--     OfflineEarnings(amount: number, minutes: number) -- Willkommens-Popup
--     QuestsUpdated(quests: { { text, progress, target, reward, done } })
--
--   RemoteFunctions (Client -> Server), geben immer (ok: boolean, payload: any?) zurück:
--     PlaceBiome(biomeId: string, slot: number) -- schaltet eine Insel-Zone frei
--     UpgradeBiome(slot: number)
--     BuyUpgrade(upgradeId: "magnet" | "backpack")
--     RollLoot()
--     RequestVisit(targetUserId: number)
--     GoHome()
--     LikePlanet(targetUserId: number)
--     TradeAction(action: "invite" | "acceptInvite" | "setOffer" | "toggleAccept" | "cancel", payload: any?)
--     EquipCosmetic(category: string, cosmeticId: string?) -- nil = Kategorie ablegen
--     RenamePlanet(name: string) -- gibt bei ok den gefilterten Namen zurück
--     TutorialAction(action: "advance" | "skip") -- Server validiert den Fortschritt
--     SimulatePurchase(kind: "gamepass" | "product", key: string)
--       NUR Studio-Testmodus (Server prüft RunService:IsStudio() hart)
--     DoRebirth() -- Wiedergeburt (Server prüft die lifetimeEnergy-Schwelle)
--     EquipItem(uid: string, equip: boolean) -- Loot-Item aus-/anlegen

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
	"CosmeticsUpdated",
	"LeaderboardUpdated",
	"TutorialUpdated",
	"ObjectCollected",
	"BackpackChanged",
	"SoldBackpack",
	"UpgradesUpdated",
	"MultiplierChanged",
	"EquipmentUpdated",
	"OfflineEarnings",
	"QuestsUpdated",
}

local FUNCTION_NAMES = {
	"PlaceBiome",
	"UpgradeBiome",
	"BuyUpgrade",
	"RollLoot",
	"RequestVisit",
	"GoHome",
	"LikePlanet",
	"TradeAction",
	"EquipCosmetic",
	"RenamePlanet",
	"TutorialAction",
	"SimulatePurchase",
	"DoRebirth",
	"EquipItem",
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
