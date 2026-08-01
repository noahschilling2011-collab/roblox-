-- ServerScriptService/World/TestVehicles.server.luau
--!strict
-- GHOSTNET :: Ein Fahrzeug jeder Klasse zum Ausprobieren.
--
-- Steht bewusst getrennt vom Rest der Welt: Phase 4 baut den Autohaendler
-- und den Fahrzeugbesitz im Profil. Bis dahin ist das hier der Weg, das
-- Fahrgefuehl zu testen - und danach bleibt es als Uebungsgelaende stehen.
--
-- Attribut "Permanent" verhindert, dass der Leerlauf-Aufraeumer sie
-- wegraeumt. Bei spaeter gekauften Fahrzeugen ist das genau umgekehrt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Vehicles = require(ReplicatedStorage.Shared.Vehicles)

local VehicleChassis = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("VehicleChassis"))

local FOLDER_NAME = "GhostNet_TestVehicles"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

-- Kleiner Parkstreifen neben dem Spawn.
local base = Vector3.new(26, 3, 30)

local pad = Instance.new("Part")
pad.Name = "Parkstreifen"
pad.Size = Vector3.new(20, 1, 14 * Vehicles.Count())
pad.CFrame = CFrame.new(base + Vector3.new(0, -2.5, 14 * Vehicles.Count() * 0.5 - 7))
pad.Color = Config.Palette.Asphalt
pad.Material = Enum.Material.Concrete
pad.Anchored = true
pad.CanQuery = false
pad.TopSurface = Enum.SurfaceType.Smooth
pad.Parent = folder

local built = 0
for index, class in Vehicles.List do
	local position = base + Vector3.new(0, 0, (index - 1) * 14)
	local model = VehicleChassis.Build(class.Id, CFrame.new(position) * CFrame.Angles(0, math.rad(-90), 0))
	if model then
		model:SetAttribute("Permanent", true)
		built += 1

		-- Schild, damit man sieht, welche Klasse man gerade faehrt.
		local body = model.PrimaryPart
		if body then
			local sign = Instance.new("BillboardGui")
			sign.Name = "Sign"
			sign.Size = UDim2.fromOffset(220, 40)
			sign.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
			sign.MaxDistance = 90

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.Code
			title.Text = class.Name
			title.TextColor3 = Config.Theme.Cyan
			title.TextSize = 16
			title.Size = UDim2.new(1, 0, 0.55, 0)
			title.Parent = sign

			local blurb = Instance.new("TextLabel")
			blurb.BackgroundTransparency = 1
			blurb.Font = Enum.Font.Code
			blurb.Text = class.Blurb
			blurb.TextColor3 = Config.Theme.TextDim
			blurb.TextSize = 11
			blurb.Position = UDim2.new(0, 0, 0.55, 0)
			blurb.Size = UDim2.new(1, 0, 0.45, 0)
			blurb.Parent = sign

			sign.Parent = body
		end
	end
end

print(("[GHOSTNET] %d Testfahrzeuge gebaut."):format(built))
