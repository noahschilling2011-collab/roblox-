--!strict
-- Network: das EINZIGE Remote-Modul von Turmfall.
--
-- Alle RemoteEvents/RemoteFunctions werden hier zentral deklariert und vom
-- Server in init() erzeugt (Ordner ReplicatedStorage.TurmfallNetwork).
-- Keine verstreuten RemoteEvents irgendwo im Baum - wer ein neues Remote
-- braucht, trägt es HIER in die Namenslisten ein.
--
-- Konvention für RemoteFunctions: Rückgabe immer (ok: boolean, payload: any?);
-- bei ok=false ist payload eine deutsche Fehlermeldung für den Spieler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "TurmfallNetwork"

-- Server -> Client (RemoteEvents).
local EVENT_NAMES = {
	"RoundStateChanged", -- (phase: string, secondsLeft: number, info: {}) Rundenzustand + Timer
	"HotbarChanged", -- (items: {string}) aktuelle Hotbar des Spielers
	"PartPlaced", -- (position: Vector3, partTypeId: string) für Sound/Effekt bei allen
	"CollapseHappened", -- (replayData: {}) Kollaps + Schuld-Replay-Daten
	"ScoreboardChanged", -- (entries: {{userId, name, points, culprit}})
	"Notification", -- (message: string, kind: "info"|"success"|"error")
	"SkinsChanged", -- (ownedSkins: {string}, equipped: {slot: skinId}, truemmer: number)
}

-- Client -> Server (RemoteFunctions).
local FUNCTION_NAMES = {
	"PlacePart", -- (partTypeId: string, cframe: CFrame) -> (ok, err?)
	"EquipSkin", -- (slot: string, skinId: string?) -> (ok, err?)
}

local Network = {}

local initialized = false

local function getFolder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing ~= nil and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Erzeugt alle Remotes (nur Server, genau einmal beim Start).
function Network.init()
	assert(RunService:IsServer(), "Network.init() darf nur der Server aufrufen")
	assert(not initialized, "Network.init() wurde bereits aufgerufen")
	initialized = true

	local folder = getFolder()
	for _, name in EVENT_NAMES do
		if folder:FindFirstChild(name) == nil then
			local event = Instance.new("RemoteEvent")
			event.Name = name
			event.Parent = folder
		end
	end
	for _, name in FUNCTION_NAMES do
		if folder:FindFirstChild(name) == nil then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
		end
	end
end

function Network.getEvent(name: string): RemoteEvent
	local folder = getFolder()
	local remote = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(remote ~= nil and remote:IsA("RemoteEvent"), `Unbekanntes RemoteEvent: {name}`)
	return remote
end

function Network.getFunction(name: string): RemoteFunction
	local folder = getFolder()
	local remote = if RunService:IsServer() then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(remote ~= nil and remote:IsA("RemoteFunction"), `Unbekannte RemoteFunction: {name}`)
	return remote
end

-- Für Selbsttests: deklarierte Namen (Kopien, unveränderlich von außen).
function Network.getEventNames(): { string }
	return table.clone(EVENT_NAMES)
end

function Network.getFunctionNames(): { string }
	return table.clone(FUNCTION_NAMES)
end

return Network
