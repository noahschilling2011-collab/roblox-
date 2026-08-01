-- ReplicatedStorage/Shared/Remotes.luau
--!strict
-- GHOSTNET :: Erzeugt (Server) bzw. wartet auf (Client) alle Netzwerkobjekte.
-- Neue Remotes werden ausschliesslich in den Listen unten eingetragen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "GhostNetRemotes"

-- C->S : Client schickt ausschliesslich Eingaben, niemals Ergebnisse.
-- S->C : Server schickt Zustand und Ergebnisse.
local EVENT_NAMES = {
	"HackRequestStart", -- C->S  { targetId }
	"HackInput", -- C->S  { sessionId, step, payload }
	"HackAbort", -- C->S  { sessionId }
	"HackSessionStarted", -- S->C  { sessionId, hackType, public, deadline, attempts, ... }
	"HackDenied", -- S->C  { targetId, reason, seconds }  Start abgelehnt
	"HackFeedback", -- S->C  { sessionId, step, ok, reason, ... }
	"HackResolved", -- S->C  { sessionId, success, reason, reward, traceDelta, effect }
	"EconomySync", -- S->C  { banked, unsold, rig, tier }
	"SellRequest", -- C->S  { }            Verkauf beim Hehler
	"SellResult", -- S->C  { ok, reason, gross, fee, net, seconds }
	"TraceSync", -- S->C  { trace, max, locked, lockSeconds, bust? }
	"MissionSync", -- S->C  { active, title, briefing, stepIndex, stepText, steps, progress }
	"MissionAccept", -- C->S  { missionId }
	"MissionAbandon", -- C->S  { }
	"MissionInteract", -- C->S  { contactId }   loest TALK-Schritte aus
	"MissionSkip", -- C->S  { }            Tutorial ueberspringen
	"WaypointSync", -- S->C  { position, label }  Marker fuer GOTO/HACK/TALK
	"AlarmSync", -- S->C  { active, label, remaining, total, coop, triggered? }
	"MarketSync", -- S->C  { goods, event, tickSeconds }   serverweite Kurse
	"MarketEvent", -- S->C  { text, group }                Kursereignis
	"InventorySync", -- S->C  { stash, used, slots, tier }
	"AdminReady", -- S->C  { studio }   nur an autorisierte Spieler
	"StoreSync", -- S->C  { passes, products }
	"StorePrompt", -- C->S  { kind, key }   bittet um den Kaufdialog
}

local FUNCTION_NAMES: { string } = {
	"ShopPurchase", -- C->S->C  { component } -> { ok, reason, level, cost, ... }
	"Trade", -- C->S->C  { action, goodId, amount } -> { ok, reason, unit, total, ... }
	"AdminCommand", -- C->S->C  { command, ... } -> { ok, text, ... }
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
	end
	for _, name in FUNCTION_NAMES do
		if not folder:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) :: Folder
	if not folder then
		error("[GHOSTNET] Remotes-Ordner nicht gefunden - laeuft der Server-Bootstrap?")
	end
end

-- Zugriff: Remotes.HackInput usw.
setmetatable(Remotes, {
	__index = function(_, key: string): any
		local inst = folder:FindFirstChild(key)
		if not inst then
			if RunService:IsClient() then
				inst = folder:WaitForChild(key, 15)
			end
		end
		if not inst then
			error(("[GHOSTNET] Unbekanntes Remote '%s'"):format(key), 2)
		end
		return inst
	end,
})

return Remotes
