--!strict
-- Beleuchtung: Schreibtisch bei Nacht.
--
-- Die Szene wird NICHT von der Sonne beleuchtet, sondern von zwei Quellen:
-- der Monitorflaeche am linken Rand und den leuchtenden Tasten selbst.
-- Deshalb steht die Sonne fast aus und die Uhrzeit kurz nach Mitternacht.
--
-- Wird beim Serverstart gesetzt statt in Studio geklickt, damit die Werte
-- versioniert sind und beim naechsten Rojo-Sync nicht verschwinden.
-- Keine Asset-IDs: eine Sky-Textur braeuchte eine hochgeladene Datei.

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WorldConfig = require(Shared.Config.WorldConfig)

local LightingService = {}

-- Vorhandene Effekte ersetzen statt stapeln: sonst haengt nach einem
-- zweiten Serverstart in Studio alles doppelt drin.
local function ersetze(klasse: string): Instance
	local alt = Lighting:FindFirstChildOfClass(klasse)
	if alt then
		alt:Destroy()
	end
	return Instance.new(klasse)
end

function LightingService.start()
	local config = WorldConfig.LIGHTING

	Lighting.Ambient = config.AMBIENT
	Lighting.OutdoorAmbient = config.OUTDOOR_AMBIENT
	Lighting.Brightness = config.BRIGHTNESS
	Lighting.ClockTime = config.CLOCK_TIME
	Lighting.GeographicLatitude = config.GEOGRAPHIC_LATITUDE
	Lighting.EnvironmentDiffuseScale = config.ENVIRONMENT_DIFFUSE
	Lighting.EnvironmentSpecularScale = config.ENVIRONMENT_SPECULAR
	Lighting.ExposureCompensation = config.EXPOSURE_COMPENSATION

	local atmosphere = ersetze("Atmosphere") :: Atmosphere
	atmosphere.Density = config.ATMOSPHERE_DENSITY
	atmosphere.Haze = config.ATMOSPHERE_HAZE
	atmosphere.Glare = config.ATMOSPHERE_GLARE
	atmosphere.Color = config.ATMOSPHERE_COLOR
	atmosphere.Decay = config.ATMOSPHERE_DECAY
	atmosphere.Parent = Lighting

	local bloom = ersetze("BloomEffect") :: BloomEffect
	bloom.Intensity = config.BLOOM_INTENSITY
	bloom.Size = config.BLOOM_SIZE
	bloom.Threshold = config.BLOOM_THRESHOLD
	bloom.Parent = Lighting

	local correction = ersetze("ColorCorrectionEffect") :: ColorCorrectionEffect
	correction.Brightness = config.CC_BRIGHTNESS
	correction.Contrast = config.CC_CONTRAST
	correction.Saturation = config.CC_SATURATION
	correction.TintColor = config.CC_TINT
	correction.Parent = Lighting

	local sunRays = ersetze("SunRaysEffect") :: SunRaysEffect
	sunRays.Intensity = config.SUNRAYS_INTENSITY
	sunRays.Spread = config.SUNRAYS_SPREAD
	sunRays.Parent = Lighting

	local depth = ersetze("DepthOfFieldEffect") :: DepthOfFieldEffect
	depth.FarIntensity = config.DOF_FAR_INTENSITY
	depth.FocusDistance = config.DOF_FOCUS_DISTANCE
	depth.InFocusRadius = config.DOF_IN_FOCUS_RADIUS
	depth.NearIntensity = config.DOF_NEAR_INTENSITY
	depth.Parent = Lighting

	LightingService.buildMonitor()

	-- Lighting.Technology laesst sich nach meinem Kenntnisstand NICHT zur
	-- Laufzeit setzen - es ist eine Eigenschaft der Place-Datei, nicht der
	-- Szene. Deshalb steht hier keine Zuweisung, sondern eine Meldung:
	-- Noah muss das einmal in Studio klicken. Wo, steht in der README.
	-- ungeprueft: bitte verifizieren, ob Technology doch schreibbar ist
	print(("[KEYCAP] LightingService: Nacht (Uhrzeit %.1f, Helligkeit %.1f, Bloom-Schwelle %.2f)")
		:format(config.CLOCK_TIME, config.BRIGHTNESS, config.BLOOM_THRESHOLD))
	print("[KEYCAP] HINWEIS: Lighting.Technology muss EINMAL in Studio auf Future gestellt werden.")
end

-- Der Monitor am Rand. Kein Objekt zum Anschauen, sondern die Lichtquelle,
-- die der ganzen Szene ihre Richtung gibt.
function LightingService.buildMonitor()
	local alt = workspace:FindFirstChild("Monitor")
	if alt then
		alt:Destroy()
	end

	local config = WorldConfig.LIGHTING
	local screen = Instance.new("Part")
	screen.Name = "Monitor"
	screen.Size = config.MONITOR_SIZE
	screen.Position = config.MONITOR_POSITION
	screen.Anchored = true
	screen.CanCollide = false
	screen.CanQuery = false
	screen.CastShadow = false
	screen.Material = Enum.Material.Neon
	screen.Color = config.MONITOR_COLOR
	screen.Transparency = config.MONITOR_TRANSPARENCY

	-- SurfaceLight statt PointLight: das Licht soll von einer FLAECHE
	-- kommen und in eine Richtung fallen, nicht kugelfoermig abstrahlen.
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Right -- zeigt zur Spielflaeche
	light.Brightness = config.MONITOR_LIGHT_BRIGHTNESS
	light.Range = config.MONITOR_LIGHT_RANGE
	light.Color = config.MONITOR_COLOR
	light.Angle = 90
	light.Shadows = false -- Schatten von einer Flaechenquelle sind teuer
	light.Parent = screen

	screen.Parent = workspace
end

return LightingService
