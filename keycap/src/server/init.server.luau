--!strict
-- Startet alle Services in fester Reihenfolge.
--
-- Die Reihenfolge ist nicht beliebig:
--   Remotes zuerst, sonst sucht ein Client sie vergeblich.
--   Plots bauen, dann NPC-Plots belegen, dann erst Spieler zulassen -
--   sonst nimmt ein frueh beigetretener Spieler den Platz eines NPC-Plots.
--   StealService vor allem, was Tasten erzeugen kann.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
require(Shared:WaitForChild("Remotes")) -- legt die RemoteEvents an

local WorldConfig = require(Shared:WaitForChild("Config"):WaitForChild("WorldConfig"))

local Services = script:WaitForChild("Services")

local DataService = require(Services.DataService)
local LightingService = require(Services.LightingService)
local BackdropService = require(Services.BackdropService)
local PlotService = require(Services.PlotService)
local NpcPlotService = require(Services.NpcPlotService)
local ProductionService = require(Services.ProductionService)
local SpeedService = require(Services.SpeedService)
local CarryService = require(Services.CarryService)
local TutorialService = require(Services.TutorialService)
local CourseService = require(Services.CourseService)
local StealService = require(Services.StealService)
local ShopService = require(Services.ShopService)
local RunTimerService = require(Services.RunTimerService)
local StateService = require(Services.StateService)

print("[KEYCAP] Server startet ...")

-- Die Studio-Datei enthaelt eine gebackene Vorschau der Welt, damit beim
-- Oeffnen nicht nur ein leerer Boden dasteht. Der Server baut dieselbe Welt
-- gleich selbst - die Vorschau muss also weg, sonst haengt alles doppelt drin.
local vorschau = workspace:FindFirstChild("WeltVorschau")
if vorschau then
	vorschau:Destroy()
	print("[KEYCAP] Gebackene Vorschau entfernt, Server baut die Welt neu")
end

DataService.start()
LightingService.start()
BackdropService.start()
PlotService.buildWorld()
NpcPlotService.start()
PlotService.start()
TutorialService.start()
CourseService.start()
ProductionService.start()
SpeedService.start()
CarryService.start()
StealService.start()
ShopService.start()
RunTimerService.start()
StateService.start()

-- Part-Budget: die Bewertung nennt 3000 als Ziel. Hier steht, wo wir
-- wirklich landen - wenn die Zahl beim Bauen der Karte steigt, faellt es
-- beim Serverstart auf und nicht erst auf dem Handy.
local zaehler = PlotService.countParts()
local gesamt = zaehler.parts
if gesamt > WorldConfig.PART_BUDGET then
	warn(("[KEYCAP] Part-Budget gerissen: %d von %d"):format(gesamt, WorldConfig.PART_BUDGET))
else
	print(("[KEYCAP] Parts %d von %d erlaubt"):format(gesamt, WorldConfig.PART_BUDGET))
end
print(("[KEYCAP] Dazu: %d ProximityPrompts, %d GUIs, %d Lichtquellen")
	:format(zaehler.prompts, zaehler.guis, zaehler.lights))

print("[KEYCAP] Server bereit.")
