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

DataService.start()
LightingService.start()
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
local parts = PlotService.countParts()
if parts > WorldConfig.PART_BUDGET then
	warn(("[KEYCAP] Part-Budget gerissen: %d von %d"):format(parts, WorldConfig.PART_BUDGET))
else
	print(("[KEYCAP] Parts in workspace: %d von %d erlaubt"):format(parts, WorldConfig.PART_BUDGET))
end

print("[KEYCAP] Server bereit.")
