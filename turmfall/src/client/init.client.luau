--!strict
-- Einstiegspunkt des Turmfall-Clients: startet alle Controller in fester
-- Reihenfolge. Konvention: Controller liegen unter Controllers/<Name> und
-- exportieren eine Tabelle mit init().

local CONTROLLER_STARTUP_ORDER = {
	"UIController", -- zuerst: HUD + Toast-API für alle anderen
	"SkinUIController", -- vor dem ReplayController (Kollaps-Effekt-Abfrage)
	"PlacementController",
	"ReplayController",
	"EffectsController", -- Stabilitäts-Feedback + Finale-Visuals
}

local controllersFolder = script:WaitForChild("Controllers")

for _, controllerName in CONTROLLER_STARTUP_ORDER do
	local moduleInstance = controllersFolder:WaitForChild(controllerName) :: ModuleScript
	local controller = (require)(moduleInstance) :: { init: () -> () }

	task.spawn(function()
		local ok, err = pcall(controller.init)
		if ok then
			print(`[Turmfall] {controllerName} gestartet`)
		else
			warn(`[Turmfall] {controllerName} konnte nicht starten: {err}`)
		end
	end)
end
