-- ServerScriptService/GhostNetServer.server.luau
--!strict
-- GHOSTNET :: Server-Bootstrap. Startet die Systeme in fester Reihenfolge.
--
-- Die Reihenfolge ist kein Zufall: der SaveService haelt das Profil, aus dem
-- alle anderen lesen. Er muss stehen, bevor der erste Spieler etwas tun kann.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetLibrary = require(ReplicatedStorage.Shared.AssetLibrary)
local Config = require(ReplicatedStorage.Shared.Config)
-- Das Requiren legt die Remote-Objekte an, bevor irgendein Client sie sucht.
require(ReplicatedStorage.Shared.Remotes)

local Systems = script.Parent:WaitForChild("Systems")

local TimeService = require(Systems.TimeService)
local SaveService = require(Systems.SaveService)
local EconomyService = require(Systems.EconomyService)
local TraceService = require(Systems.TraceService)
local HackTargets = require(Systems.HackTargets)
local HackService = require(Systems.HackService)
local SellService = require(Systems.SellService)
local ShopService = require(Systems.ShopService)
local RaidService = require(Systems.RaidService)
local MissionService = require(Systems.MissionService)
local MarketService = require(Systems.MarketService)
local InventoryService = require(Systems.InventoryService)
local RoadNetwork = require(Systems.RoadNetwork)
local RouteService = require(Systems.RouteService)
local VehicleChassis = require(Systems.VehicleChassis)
local VehicleService = require(Systems.VehicleService)
local ArrestService = require(Systems.ArrestService)
local PursuitService = require(Systems.PursuitService)
local TrafficService = require(Systems.TrafficService)
local GuardService = require(Systems.GuardService)
local MapService = require(Systems.MapService)
local PhoneService = require(Systems.PhoneService)
local MonetizationService = require(Systems.MonetizationService)
local AdminService = require(Systems.AdminService)

TimeService.Init() -- ganz zuerst: Licht und Uhr, davon haengen Ertraege ab
SaveService.Init() -- dann das Profil
EconomyService.Init() -- liest aus dem Profil
TraceService.Init() -- braucht Economy fuers Wipe beim Bust
HackTargets.Init() -- braucht das Profil fuer Cooldowns
HackService.Init() -- meldet sich beim TraceService fuer den Bust an
SellService.Init()
ShopService.Init()
-- Die letzten beiden haengen sich per OnHackResolved / OnSell an die
-- fertigen Services, muessen also nach ihnen kommen.
RaidService.Init()
-- Vor dem MissionService: der setzt bei jedem Wegpunkt eine Route, und die
-- Wegsuche laeuft auf dem Strassengraphen.
RoadNetwork.Init() -- Strassengraph, den Verkehr und Polizei teilen
RouteService.Init() -- Wegsuche auf demselben Graphen
MissionService.Init()
MarketService.Init() -- Kurse laufen unabhaengig von Spielern
InventoryService.Init() -- braucht Markt und Missionen (Unlock-Pruefung)
VehicleChassis.Init()
VehicleService.Init() -- Besitz und Haendler
ArrestService.Init() -- Zelle und Konsequenzen, bevor jemand gefasst wird
PursuitService.Init() -- vor dem Verkehr: der meldet Diebstaehle dorthin
TrafficService.Init()
GuardService.Init() -- meldet Alarme an den RaidService
MapService.Init() -- nach der Welt: sammelt ein, was gebaut wurde
PhoneService.Init() -- haengt sich an MissionService, muss danach kommen
MonetizationService.Init()
AdminService.Init() -- zuletzt: greift auf alle anderen zu

print(("[GHOSTNET] Server hochgefahren - Version %s"):format(Config.Version))

-- Zum Schluss: was an Vorlagen gefehlt hat. Die World-Skripte sind zu diesem
-- Zeitpunkt durch, also ist die Liste vollstaendig. Steht hier ganz unten,
-- damit sie nicht zwischen den Startmeldungen untergeht.
task.defer(AssetLibrary.Report)
