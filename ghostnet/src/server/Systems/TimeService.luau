-- ServerScriptService/Systems/TimeService.luau
--!strict
-- GHOSTNET :: Tag und Nacht.
--
-- WARUM UEBERHAUPT EIN ZYKLUS
--   Dauerhaftes Tageslicht wuerde den kompletten visuellen Aufbau zerstoeren:
--   Neon, Bloom und die Terminal-Aesthetik funktionieren nur im Dunkeln.
--   Dauerhafte Nacht macht die Stadt eintoenig. Also beides - aber als
--   Mechanik, nicht als Kulisse:
--
--     Nachts  +35 % auf jeden Hack-Ertrag, NPCs sehen kuerzer.
--     Tags    Haendler und Laeden offen, Kurse ruhiger.
--
--   Damit hat der Spieler einen Grund, auf die Uhr zu schauen.
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

local clock = Config.World.StartClock -- 0..24
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
	return clock >= Config.World.NightStartHour or clock < Config.World.DayStartHour
end

function TimeService.IsDay(): boolean
	return not TimeService.IsNight()
end

function TimeService.GetPhase(): string
	return if TimeService.IsNight() then "NIGHT" else "DAY"
end

-- Faktor auf Hack-Ertraege. Wird vom HackService gelesen.
function TimeService.RewardMultiplier(): number
	return if TimeService.IsNight() then 1 + Config.World.NightRewardBonus else 1
end

-- Wie weit NPCs sehen (Phase 5/6 nutzt das).
function TimeService.SightFactor(): number
	return if TimeService.IsNight() then Config.World.NightSightFactor else 1
end

-- Wie stark die Darknet-Kurse schwanken duerfen.
function TimeService.MarketVolatilityFactor(): number
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
		created.Haze = 2
		created.Glare = 0.2
		created.Color = Color3.fromRGB(150, 160, 175)
		created.Decay = Color3.fromRGB(60, 70, 90)
		created.Parent = Lighting
		atmosphere = created
	end
	bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	colour = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
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
	applyLighting()

	Players.PlayerAdded:Connect(function(player)
		task.defer(TimeService.SyncTo, player)
	end)
	for _, player in Players:GetPlayers() do
		task.defer(TimeService.SyncTo, player)
	end

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
