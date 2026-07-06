--!strict
-- Einstiegspunkt des Turmfall-Servers.
-- Erzeugt zuerst alle Remotes (Network) und startet dann die Services in
-- fester Reihenfolge. Konvention: Jeder Service liegt unter Services/<Name>
-- und exportiert eine Tabelle mit init() (kehrt schnell zurück; lange
-- Schleifen gehören in task.spawn innerhalb des Services).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network") :: ModuleScript) :: any

Network.init()

-- Reihenfolge bewusst: erst die Bausteine, dann die StateMachine, die sie
-- orchestriert.
local SERVICE_STARTUP_ORDER = {
	"DataService", -- zuerst: Profile mit Session-Lock laden
	"DeckService",
	"CollapseService",
	"TowerService",
	"SkinService", -- nach TowerService (hängt den Optik-Hook ein)
	"MonetizationService", -- nach SkinService (vergibt Skins)
	"ScoreService",
	"RoundService", -- zuletzt: schaltet die anderen an/aus
}

local servicesFolder = script:WaitForChild("Services")

for _, serviceName in SERVICE_STARTUP_ORDER do
	local moduleInstance = servicesFolder:WaitForChild(serviceName) :: ModuleScript
	local service = (require)(moduleInstance) :: { init: () -> () }

	local ok, err = pcall(service.init)
	if ok then
		print(`[Turmfall] {serviceName} gestartet`)
	else
		warn(`[Turmfall] {serviceName} konnte nicht starten: {err}`)
	end
end

print("[Turmfall] Server bereit")
