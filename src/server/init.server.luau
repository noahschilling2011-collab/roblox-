--!strict
-- Einstiegspunkt des Servers.
-- Erstellt zuerst alle Remotes und startet danach die Services in fester Reihenfolge.
-- Konvention: Jeder Service liegt unter Services/<Name>.luau und exportiert
-- eine Tabelle mit einer init()-Funktion, die schnell zurückkehrt
-- (langlaufende Schleifen gehören in task.spawn innerhalb des Services).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: any

Remotes.init()

-- Reihenfolge ist bewusst gewählt: erst Daten, dann die darauf aufbauenden Systeme.
local SERVICE_STARTUP_ORDER = {
	"DataService",
	"PlanetService",
	"EnergyService",
	"LootService",
	"GlobalEventService",
	"HarvestService",
	"EquipService",
	"ProgressionService",
	"VisitService",
	"TradeService",
	"MonetizationService",
	"LeaderboardService",
	"LobbyService", -- Spawn-Villa (braucht PlanetService + LeaderboardService)
	"MeteorService", -- Meteor-Events auf der eigenen Insel
	"DailyRewardService",
	"QuestService",
	"TutorialService",
	"SelfCheckService", -- immer zuletzt: prüft den fertigen Aufbau
}

local servicesFolder = script:WaitForChild("Services")

for _, serviceName in SERVICE_STARTUP_ORDER do
	local moduleInstance = servicesFolder:WaitForChild(serviceName) :: ModuleScript
	local service = (require)(moduleInstance) :: { init: () -> () }

	local ok, err = pcall(service.init)
	if ok then
		print(`[PlanetForge] {serviceName} gestartet`)
	else
		warn(`[PlanetForge] {serviceName} konnte nicht starten: {err}`)
	end
end

print("[PlanetForge] Server bereit")
