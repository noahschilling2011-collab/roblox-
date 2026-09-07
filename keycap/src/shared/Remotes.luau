--!strict
-- Einziger Ort, an dem RemoteEvents/-Functions entstehen. Server legt an,
-- Client wartet darauf. Der Client sendet nur ABSICHTEN - jede Pruefung
-- (Besitz, Kosten, Distanz, Cooldown) passiert im Service dahinter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "KeycapRemotes"

local EVENTS = {
	"StateChanged", -- Server -> Client: {wins, vorrat, rate, slots, keys, speed}
	"Notify", -- Server -> Client: kurze Meldung (Klau, Auszahlung, Fehler)
	"BuyKey", -- Client -> Server: rarityName
	"BuySlot", -- Client -> Server: (keine Argumente)
	"ActivateShield", -- Client -> Server: (keine Argumente)
	"Alert", -- Server -> Client: {kind, title, body} - grosse Einblendung
	"Announce", -- Server -> alle: {rarity, text} - serverweite Zeile
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		folder = created
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local cache: { [string]: RemoteEvent } = {}

function Remotes.get(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	local remote = folder:WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteEvent"), "Remote fehlt: " .. name)
	cache[name] = remote :: RemoteEvent
	return remote :: RemoteEvent
end

return Remotes
