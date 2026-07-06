--!strict
-- VisitService: Besuche fremder Planeten, Rückkehr nach Hause und Likes.
-- Der Server ist autoritativ: alle Client-Eingaben werden hier vollständig
-- validiert. Besuche und Likes zählen pro (Besucher, Ziel) nur EINMAL pro
-- Server-Session (In-Memory-Sets, Aufräumen bei PlayerRemoving).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local PlanetService = require(script.Parent.PlanetService)

-- Versatz beim Besuch: ~20 Studs neben dem Ziel-Plot-Ursprung, leicht erhöht,
-- damit der Charakter auf der Plaza der fremden Insel landet.
local VISIT_OFFSET = CFrame.new(20, 8, 0)

-- Session-Sets: pro Besucher die Ziele, die bereits gezählt wurden.
local countedVisits: { [Player]: { [Player]: boolean } } = {}
local countedLikes: { [Player]: { [Player]: boolean } } = {}

local VisitService = {}

local function notify(player: Player, message: string, kind: string)
	Remotes.getEvent("Notification"):FireClient(player, message, kind)
end

-- Markiert (visitor, target) im gegebenen Session-Set.
-- Gibt true zurück, wenn das Paar neu war (also gezählt werden darf).
local function markOnce(map: { [Player]: { [Player]: boolean } }, visitor: Player, target: Player): boolean
	local set = map[visitor]
	if set == nil then
		set = {}
		map[visitor] = set
	end
	if set[target] then
		return false
	end
	set[target] = true
	return true
end

-- Gemeinsame Validierung für RequestVisit und LikePlanet.
-- Rückgabe: (target, nil) bei Erfolg, sonst (nil, deutsche Fehlermeldung).
local function resolveTarget(player: Player, targetUserIdArg: unknown): (Player?, string?)
	if typeof(targetUserIdArg) ~= "number" or targetUserIdArg ~= math.floor(targetUserIdArg) then
		return nil, "Ungültige Spieler-ID."
	end
	if targetUserIdArg == player.UserId then
		return nil, "Das ist dein eigener Planet."
	end

	local target = Players:GetPlayerByUserId(targetUserIdArg)
	if target == nil then
		return nil, "Dieser Spieler ist nicht auf diesem Server."
	end
	if PlanetService.getPlotOrigin(target) == nil then
		return nil, "Der Planet dieses Spielers ist noch nicht bereit."
	end
	return target, nil
end

-- Charakter des Spielers, sofern er ein HumanoidRootPart besitzt (sonst nil).
local function getCharacterWithRoot(player: Player): Model?
	local character = player.Character
	if character == nil then
		return nil
	end
	if character:FindFirstChild("HumanoidRootPart") == nil then
		return nil
	end
	return character
end

-- Remote-Handler: RequestVisit(targetUserId) -> (ok, nil | Fehlermeldung)
local function handleRequestVisit(player: Player, targetUserIdArg: unknown): (boolean, any?)
	local target, errorMessage = resolveTarget(player, targetUserIdArg)
	if target == nil then
		return false, errorMessage
	end

	local character = getCharacterWithRoot(player)
	if character == nil then
		return false, "Dein Charakter ist gerade nicht bereit."
	end

	local origin = PlanetService.getPlotOrigin(target)
	if origin == nil then
		return false, "Der Planet dieses Spielers ist noch nicht bereit."
	end

	character:PivotTo(origin * VISIT_OFFSET)
	-- Wer eine Insel besucht, hat die Spawn-Villa verlassen: Respawns
	-- landen ab jetzt auf der eigenen Insel statt in der Villa.
	PlanetService.markEntered(player)

	-- Besuchszähler: nur einmal pro (Besucher, Ziel) und Session erhöhen.
	-- Ist das Zielprofil noch nicht geladen, wird NICHT markiert, damit ein
	-- späterer Besuch noch zählen kann.
	local targetProfile = DataService.getProfile(target)
	if targetProfile ~= nil and markOnce(countedVisits, player, target) then
		targetProfile.visits += 1
		DataService.markDirty(target)
		PlanetService.sendSnapshot(target)
	end

	notify(player, `Du besuchst den Planeten von {target.Name}.`, "info")
	notify(target, `{player.Name} besucht deinen Planeten!`, "info")
	return true
end

-- Remote-Handler: GoHome() -> (ok, nil | Fehlermeldung)
-- Nutzt PlanetService.teleportHome: landet auf der Plaza und merkt sich,
-- dass der Spieler die Spawn-Villa verlassen hat.
local function handleGoHome(player: Player): (boolean, any?)
	if not PlanetService.teleportHome(player) then
		return false, "Dein Planet oder Charakter ist gerade nicht bereit."
	end
	notify(player, "Willkommen zurück auf deiner Insel.", "info")
	return true
end

-- Remote-Handler: LikePlanet(targetUserId) -> (ok, nil | Fehlermeldung)
local function handleLikePlanet(player: Player, targetUserIdArg: unknown): (boolean, any?)
	local target, errorMessage = resolveTarget(player, targetUserIdArg)
	if target == nil then
		return false, errorMessage
	end

	local targetProfile = DataService.getProfile(target)
	if targetProfile == nil then
		return false, "Die Daten dieses Spielers sind noch nicht geladen. Versuche es gleich erneut."
	end

	if not markOnce(countedLikes, player, target) then
		return false, "Du hast diesen Planeten in dieser Session bereits bewertet."
	end

	targetProfile.likes += 1
	DataService.markDirty(target)
	PlanetService.sendSnapshot(target)

	notify(player, `Dir gefällt der Planet von {target.Name}.`, "success")
	notify(target, `{player.Name} gefällt dein Planet!`, "success")
	return true
end

-- Session-Sets aufräumen: sowohl als Besucher als auch als Ziel austragen.
local function onPlayerRemoving(player: Player)
	countedVisits[player] = nil
	countedLikes[player] = nil
	for _, set in countedVisits do
		set[player] = nil
	end
	for _, set in countedLikes do
		set[player] = nil
	end
end

function VisitService.init()
	Remotes.getFunction("RequestVisit").OnServerInvoke = handleRequestVisit
	Remotes.getFunction("GoHome").OnServerInvoke = handleGoHome
	Remotes.getFunction("LikePlanet").OnServerInvoke = handleLikePlanet

	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return VisitService
