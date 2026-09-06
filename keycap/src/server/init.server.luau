--!strict
-- Startet alle Services in fester Reihenfolge. Reihenfolge ist wichtig:
-- Remotes muessen existieren, bevor ein Client sie sucht; Profile muessen
-- geladen werden koennen, bevor ein Plot vergeben wird.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
require(Shared:WaitForChild("Remotes")) -- legt die RemoteEvents an

local Services = script:WaitForChild("Services")

local DataService = require(Services.DataService)
local PlotService = require(Services.PlotService)
local ProductionService = require(Services.ProductionService)
local SpeedService = require(Services.SpeedService)
local CourseService = require(Services.CourseService)
local StealService = require(Services.StealService)
local ShopService = require(Services.ShopService)
local StateService = require(Services.StateService)

print("[KEYCAP] Server startet ...")

DataService.start()
PlotService.start()
CourseService.start()
ProductionService.start()
SpeedService.start()
StealService.start()
ShopService.start()
StateService.start()

print("[KEYCAP] Server bereit.")
