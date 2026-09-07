--!strict
-- Beleuchtung. Zielgruppe jung, Stil hell und freundlich - kein
-- Daemmerlicht, keine harten Schatten.
--
-- Wird beim Serverstart gesetzt statt in Studio geklickt, damit die Werte
-- versioniert sind und nicht beim naechsten Rojo-Sync verschwinden.
-- Keine Asset-IDs: eine Sky-Textur braeuchte eine hochgeladene Datei, und
-- eine erfundene ID waere ein grauer Himmel ohne Fehlermeldung.

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local WorldConfig = require(Shared.Config.WorldConfig)

local LightingService = {}

function LightingService.start()
	local config = WorldConfig.LIGHTING

	Lighting.Ambient = config.AMBIENT
	Lighting.OutdoorAmbient = config.OUTDOOR_AMBIENT
	Lighting.Brightness = config.BRIGHTNESS
	Lighting.ClockTime = config.CLOCK_TIME
	Lighting.GeographicLatitude = config.GEOGRAPHIC_LATITUDE
	Lighting.EnvironmentDiffuseScale = config.ENVIRONMENT_DIFFUSE
	Lighting.EnvironmentSpecularScale = config.ENVIRONMENT_SPECULAR

	-- Vorhandene Effekte ersetzen, nicht stapeln: sonst haengt nach einem
	-- zweiten Serverstart in Studio alles doppelt drin.
	local oldAtmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if oldAtmosphere then
		oldAtmosphere:Destroy()
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = config.ATMOSPHERE_DENSITY
	atmosphere.Haze = config.ATMOSPHERE_HAZE
	atmosphere.Glare = config.ATMOSPHERE_GLARE
	atmosphere.Color = config.ATMOSPHERE_COLOR
	atmosphere.Decay = config.ATMOSPHERE_DECAY
	atmosphere.Parent = Lighting

	local oldBloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if oldBloom then
		oldBloom:Destroy()
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = config.BLOOM_INTENSITY
	bloom.Size = config.BLOOM_SIZE
	bloom.Threshold = config.BLOOM_THRESHOLD
	bloom.Parent = Lighting

	print(("[KEYCAP] LightingService: Helligkeit %.1f, Uhrzeit %d"):format(config.BRIGHTNESS, config.CLOCK_TIME))
end

return LightingService
