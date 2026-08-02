-- ServerScriptService/Systems/ArrestService.luau
--!strict
-- GHOSTNET :: Die Festnahme.
--
-- WARUM DAS FEHLTE
--   PursuitService hat verfolgt, aber niemanden festgenommen. Eine
--   Verfolgung ohne moegliches Ende ist keine Bedrohung - man faehrt
--   irgendwohin und irgendwann ist es vorbei. Erst mit einem Ort, an dem man
--   landet, und einem Preis, den man zahlt, wird die Polizei ernst.
--
-- KEINE NEUEN STRAFSYSTEME
--   Die Konsequenzen laufen ausschliesslich ueber das, was es schon gibt:
--     EconomyService  Unverkauftes weg, Gebuehr vom Guthaben
--     InventoryService ein Teil des Darknet-Lagers weg
--     TraceService    Trace auf Config.Trace.AfterBust
--   Hier wird nichts erfunden, nur zusammengefuehrt.
--
-- KEIN KAMPF
--   Man wird gegriffen, nicht verletzt. Es gibt keine Waffe und keinen
--   Schaden - wer entkommen will, entkommt durch Fahren, Laufen, Verstecken.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local SaveService = require(script.Parent.SaveService)
local TraceService = require(script.Parent.TraceService)

local ArrestService = {}

local P = Config.Pursuit

local jailed: { [Player]: number } = {} -- Player -> Sekunde der Entlassung

--==========================================================================
-- Die naechste Wache
--==========================================================================

type Station = {
	Model: Model,
	Name: string,
	Cell: Vector3,
	Exit: Vector3,
}

local function stations(): { Station }
	local list: { Station } = {}
	for _, instance in CollectionService:GetTagged(Config.PoliceStationTag) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then
			continue
		end
		local cell = instance:GetAttribute("CellPosition")
		local exit = instance:GetAttribute("ExitPosition")
		if typeof(cell) ~= "Vector3" or typeof(exit) ~= "Vector3" then
			continue
		end
		local name = instance:GetAttribute("DisplayName")
		table.insert(list, {
			Model = instance,
			Name = if typeof(name) == "string" then name else "Revier",
			Cell = cell,
			Exit = exit,
		})
	end
	return list
end

function ArrestService.NearestStation(position: Vector3): Station?
	local best: Station? = nil
	local bestDistance = math.huge
	for _, station in stations() do
		local distance = (station.Cell - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = station, distance
		end
	end
	return best
end

--==========================================================================
-- Zustand
--==========================================================================

function ArrestService.IsJailed(player: Player): boolean
	local until_ = jailed[player]
	return until_ ~= nil and os.time() < until_
end

local function sync(player: Player, state: string, seconds: number, stationName: string)
	if not player.Parent then
		return
	end
	Remotes.ArrestSync:FireClient(player, {
		State = state, -- "CAUGHT" | "JAILED" | "FREE"
		Seconds = math.max(0, math.floor(seconds)),
		Station = stationName,
	})
end

--==========================================================================
-- Die Konsequenzen
--
-- Alles ueber bestehende Systeme. Gedeckelt, damit ein Bust wehtut, aber
-- niemanden auf null setzt - wer nach einer Festnahme bei null steht, hoert
-- auf zu spielen.
--==========================================================================

local function applyConsequences(player: Player)
	local profile = SaveService.Get(player)
	if not profile then
		return
	end

	-- 1) Alles Unverkaufte ist weg. Das ist dieselbe Regel wie beim Bust
	--    durch Trace - eine Festnahme ist kein Sonderfall.
	EconomyService.WipeUnsold(player)

	-- 2) Ein Teil des Darknet-Lagers. Ware ist heiss, und heisse Ware
	--    nehmen sie mit.
	InventoryService.ConfiscateFraction(player, P.JailStashFraction)

	-- 3) Gebuehr vom Guthaben, gedeckelt.
	local fee = math.min(math.floor(profile.Banked * P.JailFeeFraction), P.JailFeeCap)
	if fee > 0 then
		EconomyService.SpendBanked(player, fee)
	end

	-- 4) Trace zurueck auf den Wert nach einem Bust.
	profile.Trace = Config.Trace.AfterBust
	TraceService.Sync(player)

	SaveService.RequestSave(player)
	return fee
end

--==========================================================================
-- Festnahme
--==========================================================================

-- Wird von PursuitService gerufen, wenn ein Polizist lange genug am Spieler
-- dran war. Gibt zurueck, ob es geklappt hat.
function ArrestService.Arrest(player: Player): boolean
	if ArrestService.IsJailed(player) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local station = ArrestService.NearestStation(root.Position)
	if not station then
		-- Ohne Wache waere die Festnahme nur ein Text. Dann lieber nichts
		-- tun und laut sein, damit der Fehler auffaellt.
		warn("[GHOSTNET] Festnahme ohne Polizeiwache - es ist keine getaggt.")
		return false
	end

	local releaseAt = os.time() + P.JailSeconds
	jailed[player] = releaseAt

	-- 1) Bildschirm friert kurz ein, "FESTGENOMMEN".
	sync(player, "CAUGHT", P.JailSeconds, station.Name)

	applyConsequences(player)

	-- 2) Kurze Blende, dann steht der Spieler in der Zelle. Keine echte
	--    Fahrt - die waere lange, langweilig und fehleranfaellig.
	task.delay(Config.Pursuit.TransportSeconds, function()
		if not player.Parent then
			return
		end
		local body = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if body and body:IsA("BasePart") then
			player.Character:PivotTo(CFrame.new(station.Cell + Vector3.new(0, 3, 0)))
		end
		sync(player, "JAILED", math.max(0, releaseAt - os.time()), station.Name)
	end)

	-- 3) Entlassung vor der Wache.
	task.delay(P.JailSeconds, function()
		if not player.Parent then
			return
		end
		jailed[player] = nil
		local character2 = player.Character
		if character2 then
			character2:PivotTo(CFrame.new(station.Exit + Vector3.new(0, 3, 0)))
		end
		sync(player, "FREE", 0, station.Name)
	end)

	print(("[GHOSTNET] %s wurde festgenommen (%s)."):format(player.Name, station.Name))
	return true
end

--==========================================================================

function ArrestService.Init()
	Players.PlayerRemoving:Connect(function(player)
		jailed[player] = nil
	end)

	-- Wer waehrend der Zellenzeit den Server wechselt, kommt frei. Das ist
	-- Absicht: eine Strafe ueber Sitzungen hinweg braeuchte ein neues
	-- Profilfeld und damit eine Migration - fuer 45 Sekunden nicht wert.
	print(("[GHOSTNET] ArrestService bereit. Zellenzeit %d s."):format(P.JailSeconds))
end

return ArrestService
