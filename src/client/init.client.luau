--!strict
-- Einstiegspunkt des Clients: startet alle Controller in fester Reihenfolge.
-- Konvention: Jeder Controller liegt unter Controllers/<Name>.luau und exportiert
-- eine Tabelle mit einer init()-Funktion.

local CONTROLLER_STARTUP_ORDER = {
	"UIController",
	"PlanetBuilderController",
	"EventNotifierController",
	"ShopController",
	"LeaderboardController",
	"PlanetNameController",
	"TutorialController",
}

local controllersFolder = script:WaitForChild("Controllers")

for _, controllerName in CONTROLLER_STARTUP_ORDER do
	local moduleInstance = controllersFolder:WaitForChild(controllerName) :: ModuleScript
	local controller = (require)(moduleInstance) :: { init: () -> () }

	-- Controller dürfen in init() auf Remotes warten, deshalb entkoppelt starten.
	task.spawn(function()
		local ok, err = pcall(controller.init)
		if ok then
			print(`[PlanetForge] {controllerName} gestartet`)
		else
			warn(`[PlanetForge] {controllerName} konnte nicht starten: {err}`)
		end
	end)
end
