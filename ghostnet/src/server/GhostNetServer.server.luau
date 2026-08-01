-- ServerScriptService/GhostNetServer.server.luau
--!strict
-- GHOSTNET :: Server-Bootstrap. Startet die Systeme in fester Reihenfolge.
--
-- Die Reihenfolge ist kein Zufall: der SaveService haelt das Profil, aus dem
-- alle anderen lesen. Er muss stehen, bevor der erste Spieler etwas tun kann.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
-- Das Requiren legt die Remote-Objekte an, bevor irgendein Client sie sucht.
require(ReplicatedStorage.Shared.Remotes)

local Systems = script.Parent:WaitForChild("Systems")

local SaveService = require(Systems.SaveService)
local EconomyService = require(Systems.EconomyService)
local TraceService = require(Systems.TraceService)
local HackTargets = require(Systems.HackTargets)
local HackService = require(Systems.HackService)
local SellService = require(Systems.SellService)
local ShopService = require(Systems.ShopService)

SaveService.Init() -- zuerst: haelt das Profil
EconomyService.Init() -- liest aus dem Profil
TraceService.Init() -- braucht Economy fuers Wipe beim Bust
HackTargets.Init() -- braucht das Profil fuer Cooldowns
HackService.Init() -- meldet sich beim TraceService fuer den Bust an
SellService.Init()
ShopService.Init()

print(("[GHOSTNET] Server hochgefahren - Version %s"):format(Config.Version))
