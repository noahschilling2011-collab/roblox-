-- ServerScriptService/Systems/TimeService.luau
--!strict
-- GHOSTNET :: Das Licht ueber Vantorra.
--
-- ZWEI BETRIEBSARTEN, EIN SCHALTER: Config.World.PermanentDay
--
--   true (Standard)  Dauerhafter heller Tag. Die Sonne steht fest auf
--                    Config.World.DayClock, es gibt keinen Zyklus und
--                    keinen Heartbeat - das Licht wird EINMAL gesetzt.
--                    Alle Tageszeit-Faktoren sind neutral.
--
--   false            Der komplette alte Zyklus laeuft wieder: 24 Stunden
--                    in DayLengthMinutes, weiche Rampe um Auf- und
--                    Untergang, nachts mehr Ertrag und kuerzere NPC-Sicht.
--
--   Der ganze Zyklus-Code steht bewusst noch hier. Umschalten kostet dann
--   genau eine Zahl in Config und keine Zeile Code irgendwo sonst.
--
-- WO IST DER NACHTBONUS HIN
--   Er haengt jetzt am Ort statt an der Uhrzeit: Config.Cover. Ein Ziel mit
--   Attribut Exposed = true steht auf offener Strasse und zahlt mehr, kostet
--   aber auch mehr Trace. Bei dauerhaftem Tag ist das der ehrlichere Ort
--   dafuer - es gibt keine Dunkelheit mehr, in der man verschwinden koennte.
--
-- DER SERVER IST DIE UHR
--   Lighting-Eigenschaften werden vom Server gesetzt und replizieren zu
--   allen Clients. Kein Client rechnet seine eigene Zeit aus - sonst haetten
--   zwei Spieler unterschiedliche Boni.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TimeService = {}

local PERMANENT_DAY = Config.World.PermanentDay

local clock = if PERMANENT_DAY then Config.World.DayClock else Config.World.StartClock -- 0..24
local lastPhase = ""

-- Wer auf den Wechsel reagieren will (Haendler auf/zu, Verkehrsdichte).
local phaseCallbacks: { (string) -> () } = {}

function TimeService.OnPhaseChanged(callback: (string) -> ())
	table.insert(phaseCallbacks, callback)
end

--==========================================================================
-- Lesen
--==========================================================================

function TimeService.GetClock(): number
	return clock
end

function TimeService.IsNight(): boolean
	if PERMANENT_DAY then
		return false
	end
	return clock >= Config.World.NightStartHour or clock < Config.World.DayStartHour
end

function TimeService.IsDay(): boolean
	return not TimeService.IsNight()
end

function TimeService.GetPhase(): string
	return if TimeService.IsNight() then "NIGHT" else "DAY"
end

-- Faktor auf Hack-Ertraege. Bei dauerhaftem Tag immer 1 - der Bonus haengt
-- dann am Ziel (Config.Cover), nicht an der Uhrzeit.
function TimeService.RewardMultiplier(): number
	return if TimeService.IsNight() then 1 + Config.World.NightRewardBonus else 1
end

-- Wie weit NPCs sehen. Bei dauerhaftem Tag immer 1; abweichen kann eine
-- Wache dann nur noch ueber ihr eigenes Attribut "SightFactor".
function TimeService.SightFactor(): number
	return if TimeService.IsNight() then Config.World.NightSightFactor else 1
end

-- Wie stark die Darknet-Kurse schwanken duerfen.
-- Wichtig: bei dauerhaftem Tag ist das 1 und NICHT DayMarketCalm. Der
-- ruhige Tag war die Gegenseite einer bewegten Nacht - ohne Nacht waere
-- daraus eine dauerhafte Drosselung des Darknets geworden.
function TimeService.MarketVolatilityFactor(): number
	if PERMANENT_DAY then
		return 1
	end
	return if TimeService.IsNight() then 1 else Config.World.DayMarketCalm
end

function TimeService.FormatClock(): string
	local hours = math.floor(clock)
	local minutes = math.floor((clock - hours) * 60)
	return ("%02d:%02d"):format(hours, minutes)
end

--==========================================================================
-- Stimmung
-- Alles wird ueber einen weichen Faktor 0 (tiefe Nacht) bis 1 (heller Tag)
-- interpoliert, damit nichts springt.
--==========================================================================

local function daylight(): number
	-- Weiche Rampe um Sonnenauf- und -untergang statt harter Kante.
	local dayStart = Config.World.DayStartHour
	local nightStart = Config.World.NightStartHour
	local ramp = 2 -- Stunden Uebergang

	if clock >= dayStart + ramp and clock <= nightStart - ramp then
		return 1
	elseif clock >= dayStart and clock < dayStart + ramp then
		return (clock - dayStart) / ramp
	elseif clock > nightStart - ramp and clock <= nightStart then
		return (nightStart - clock) / ramp
	end
	return 0
end

local atmosphere: Atmosphere? = nil
local bloom: BloomEffect? = nil
local colour: ColorCorrectionEffect? = nil

local function ensureEffects()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		local created = Instance.new("Atmosphere")
		created.Name = "Atmosphere"
		created.Haze = if PERMANENT_DAY then 0.6 else 2
		created.Glare = if PERMANENT_DAY then 0.05 else 0.2
		created.Color = if PERMANENT_DAY
			then Color3.fromRGB(212, 220, 232)
			else Color3.fromRGB(150, 160, 175)
		created.Decay = if PERMANENT_DAY
			then Color3.fromRGB(150, 168, 190)
			else Color3.fromRGB(60, 70, 90)
		created.Parent = Lighting
		atmosphere = created
	end
	bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	colour = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
end

-- Dauerhafter Tag: einmal setzen, danach nie wieder anfassen.
local function applyDaylight()
	local W = Config.World

	Lighting.ClockTime = W.DayClock
	Lighting.GeographicLatitude = 12 -- Sonne hoch, aber nicht senkrecht
	Lighting.Brightness = W.SunBrightness
	Lighting.ExposureCompensation = 0
	Lighting.FogEnd = W.SunFog
	Lighting.FogStart = 0
	Lighting.OutdoorAmbient = W.SunOutdoorAmbient
	Lighting.Ambient = W.SunAmbient

	if atmosphere then
		atmosphere.Density = W.SunAtmosphere
	end
	if bloom then
		bloom.Intensity = W.SunBloom
	end
	if colour then
		colour.Saturation = W.SunSaturation
		colour.TintColor = W.SunTint
		colour.Brightness = 0
	end
end

local function applyLighting()
	local t = daylight()

	Lighting.ClockTime = clock
	Lighting.FogEnd = Config.World.FogNight + (Config.World.FogDay - Config.World.FogNight) * t

	-- Tagsueber kuehles Blaugrau statt sattem Blau: die Stadt soll auch bei
	-- Tag nicht freundlich wirken.
	Lighting.OutdoorAmbient = Color3.fromRGB(20, 23, 33):Lerp(Color3.fromRGB(96, 104, 116), t)
	Lighting.Ambient = Color3.fromRGB(13, 15, 20):Lerp(Color3.fromRGB(58, 63, 72), t)
	Lighting.Brightness = 1 + t * 1.4

	if atmosphere then
		atmosphere.Density = Config.World.AtmosphereDensityNight
			+ (Config.World.AtmosphereDensityDay - Config.World.AtmosphereDensityNight) * t
	end
	if bloom then
		bloom.Intensity = Config.World.BloomNight + (Config.World.BloomDay - Config.World.BloomNight) * t
	end
	if colour then
		colour.Saturation = 0.08 - t * 0.12 -- tagsueber ausgewaschener
		colour.TintColor = Color3.fromRGB(230, 248, 255):Lerp(Color3.fromRGB(226, 230, 234), t)
	end
end

--==========================================================================
-- Senden
--==========================================================================

local function payload(): { [string]: any }
	return {
		Clock = clock,
		Text = TimeService.FormatClock(),
		IsNight = TimeService.IsNight(),
		RewardBonus = TimeService.RewardMultiplier() - 1,
		DayLengthMinutes = Config.World.DayLengthMinutes,
		PermanentDay = PERMANENT_DAY,
	}
end

function TimeService.SyncTo(player: Player)
	if player.Parent then
		Remotes.TimeSync:FireClient(player, payload())
	end
end

local function broadcast()
	local data = payload()
	for _, player in Players:GetPlayers() do
		Remotes.TimeSync:FireClient(player, data)
	end
end

--==========================================================================

function TimeService.Init()
	-- Technology ist umschaltbar, damit man auf schwachen Geraeten von
	-- Future auf ShadowMap zurueckgehen kann, ohne Code anzufassen.
	local ok = pcall(function()
		Lighting.Technology = (Enum.Technology :: any)[Config.World.LightingTechnology]
	end)
	if not ok then
		warn(("[GHOSTNET] Unbekannte Lighting.Technology '%s' - Roblox-Standard bleibt."):format(
			tostring(Config.World.LightingTechnology)
		))
	end

	Lighting.GlobalShadows = true
	ensureEffects()

	Players.PlayerAdded:Connect(function(player)
		task.defer(TimeService.SyncTo, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(TimeService.SyncTo, player)
	end

	if PERMANENT_DAY then
		-- Kein Zyklus, also auch kein Heartbeat. Das Licht steht.
		applyDaylight()
		lastPhase = "DAY"
		print(("[GHOSTNET] TimeService bereit. Dauerhafter Tag (%s Uhr)."):format(TimeService.FormatClock()))
		return
	end

	applyLighting()

	-- 24 Spielstunden pro DayLengthMinutes Echtzeit.
	local hoursPerSecond = 24 / (Config.World.DayLengthMinutes * 60)
	local accumulator = 0
	local sinceBroadcast = 0

	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.World.TimeTick then
			return
		end
		local step = accumulator
		accumulator = 0

		clock = (clock + hoursPerSecond * step) % 24
		applyLighting()

		local phase = TimeService.GetPhase()
		if phase ~= lastPhase then
			lastPhase = phase
			print(("[GHOSTNET] Es wird %s (%s Uhr)."):format(
				if phase == "NIGHT" then "Nacht" else "Tag",
				TimeService.FormatClock()
			))
			for _, callback in phaseCallbacks do
				task.spawn(function()
					local success, err = pcall(callback, phase)
					if not success then
						warn(("[GHOSTNET] Tageszeit-Callback fehlgeschlagen: %s"):format(tostring(err)))
					end
				end)
			end
			broadcast()
			sinceBroadcast = 0
			return
		end

		-- Zwischendurch nur selten senden: der Client hat die Uhr ohnehin
		-- ueber Lighting.ClockTime und braucht das Paket nur fuer den Bonus.
		sinceBroadcast += step
		if sinceBroadcast >= 5 then
			sinceBroadcast = 0
			broadcast()
		end
	end)

	lastPhase = TimeService.GetPhase()
	print(("[GHOSTNET] TimeService bereit. %s Uhr, ein Tag dauert %d Minuten."):format(
		TimeService.FormatClock(),
		Config.World.DayLengthMinutes
	))
end

return TimeService
