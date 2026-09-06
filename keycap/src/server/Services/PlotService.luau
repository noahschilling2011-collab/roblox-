--!strict
-- Baut die Plots, vergibt sie an Spieler und haelt die Tasten-Parts
-- synchron mit dem Profil. Jede Taste ist ein Part mit eigenem Vorrat.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local Theme = require(Shared.Theme)
local DataService = require(script.Parent.DataService)

local PlotService = {}

type Plot = {
	index: number,
	model: Model,
	base: BasePart,
	keyFolder: Folder,
	ownerUserId: number?,
	signLabel: TextLabel,
}

local plots: { Plot } = {}
local plotByUser: { [number]: Plot } = {}
-- Rueckweg vom Part zum Profil-Eintrag, damit StealService nichts raten muss.
local keyOwner: { [BasePart]: { userId: number, index: number } } = {}

local function plotPosition(index: number): Vector3
	local origin = WorldConfig.PLOT_ORIGIN
	local offset = (index - 1) * WorldConfig.PLOT_SPACING
	local centering = (WorldConfig.PLOT_COUNT - 1) * WorldConfig.PLOT_SPACING / 2
	return Vector3.new(origin.X + offset - centering, origin.Y, origin.Z)
end

local function slotPosition(plot: Plot, slotIndex: number): Vector3
	local columns = WorldConfig.SLOT_COLUMNS
	local col = (slotIndex - 1) % columns
	local row = math.floor((slotIndex - 1) / columns)
	local spacing = WorldConfig.SLOT_SPACING
	local center = plot.base.Position
	local xOffset = (col - (columns - 1) / 2) * spacing
	local zOffset = (row - 1) * spacing
	local top = center.Y + WorldConfig.PLOT_SIZE.Y / 2 + WorldConfig.KEY_SIZE.Y / 2
	return Vector3.new(center.X + xOffset, top, center.Z + zOffset)
end

function PlotService.buildWorld()
	local container = Instance.new("Folder")
	container.Name = "Plots"

	for index = 1, WorldConfig.PLOT_COUNT do
		local model = Instance.new("Model")
		model.Name = "Plot" .. index

		local base = Instance.new("Part")
		base.Name = "Base"
		base.Size = WorldConfig.PLOT_SIZE
		base.Position = plotPosition(index)
		base.Anchored = true
		base.TopSurface = Enum.SurfaceType.Smooth
		base.BottomSurface = Enum.SurfaceType.Smooth
		base.Color = Theme.PANEL
		base.Material = Enum.Material.SmoothPlastic
		base.Parent = model

		local sign = Instance.new("Part")
		sign.Name = "Sign"
		sign.Size = Vector3.new(10, 1, 1)
		sign.Position = base.Position + Vector3.new(0, 8, WorldConfig.PLOT_SIZE.Z / 2)
		sign.Anchored = true
		sign.CanCollide = false
		sign.Transparency = 1
		sign.Parent = model

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.new(0, 260, 0, 60)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 220

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Theme.FONT
		label.TextScaled = true
		label.TextColor3 = Theme.TEXT
		label.TextStrokeTransparency = 0.4
		label.Text = "Frei"
		label.Parent = billboard
		billboard.Parent = sign

		local keyFolder = Instance.new("Folder")
		keyFolder.Name = "Keys"
		keyFolder.Parent = model

		model.PrimaryPart = base
		model.Parent = container

		plots[index] = {
			index = index,
			model = model,
			base = base,
			keyFolder = keyFolder,
			ownerUserId = nil,
			signLabel = label,
		}
	end

	container.Parent = workspace
end

local function clearKeys(plot: Plot)
	for _, child in plot.keyFolder:GetChildren() do
		if child:IsA("BasePart") then
			keyOwner[child] = nil
		end
		child:Destroy()
	end
end

-- Baut die Tasten-Parts neu aus dem Profil. Wird nach jeder Aenderung an
-- der Tastenliste aufgerufen (Kauf, Klau, Verlust).
function PlotService.rebuildKeys(userId: number)
	local plot = plotByUser[userId]
	if not plot then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	local profile = if player then DataService.get(player) else nil
	clearKeys(plot)
	if not profile then
		return
	end

	for index, key in profile.keys do
		local part = Instance.new("Part")
		part.Name = "Key" .. index
		part.Size = WorldConfig.KEY_SIZE
		part.Position = slotPosition(plot, index)
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Theme.RARITY_COLORS[key.rarity] or Theme.PANEL

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Info"
		billboard.Size = UDim2.new(0, 150, 0, 44)
		billboard.StudsOffset = Vector3.new(0, 3, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = 120

		local label = Instance.new("TextLabel")
		label.Name = "Vorrat"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Theme.FONT
		label.TextScaled = true
		label.TextColor3 = Theme.TEXT
		label.TextStrokeTransparency = 0.5
		label.Text = key.rarity
		label.Parent = billboard
		billboard.Parent = part

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Steal"
		prompt.ActionText = "Klauen"
		prompt.ObjectText = key.rarity
		prompt.HoldDuration = EconomyConfig.STEAL_HOLD_SECONDS
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = part

		part.Parent = plot.keyFolder
		keyOwner[part] = { userId = userId, index = index }
	end
end

-- Beschriftung der Tasten aktualisieren (eigener Takt, damit nicht jede
-- Sekunde 240 Labels repliziert werden).
function PlotService.refreshKeyLabels(userId: number)
	local plot = plotByUser[userId]
	local player = Players:GetPlayerByUserId(userId)
	local profile = if player then DataService.get(player) else nil
	if not plot or not profile then
		return
	end
	for part, ref in keyOwner do
		if ref.userId ~= userId or part.Parent == nil then
			continue
		end
		local key = profile.keys[ref.index]
		local billboard = part:FindFirstChild("Info")
		local label = if billboard then billboard:FindFirstChild("Vorrat") else nil
		if key and label and label:IsA("TextLabel") then
			label.Text = ("%s\n%d"):format(key.rarity, math.floor(key.vorrat))
		end
	end
end

function PlotService.assign(player: Player): boolean
	for _, plot in plots do
		if plot.ownerUserId == nil then
			plot.ownerUserId = player.UserId
			plotByUser[player.UserId] = plot
			plot.signLabel.Text = player.DisplayName
			PlotService.rebuildKeys(player.UserId)
			return true
		end
	end
	return false
end

-- Verlassene Plots: Plot und Tasten verschwinden mit dem Besitzer.
-- Entscheidung (im Konzept undefiniert): sonst waeren herrenlose Plots
-- unbewachte Beutekisten und der Anwesenheits-Bonus haette keinen Wert.
function PlotService.release(userId: number)
	local plot = plotByUser[userId]
	if not plot then
		return
	end
	clearKeys(plot)
	plot.ownerUserId = nil
	plot.signLabel.Text = "Frei"
	plotByUser[userId] = nil
end

function PlotService.getPlot(userId: number)
	return plotByUser[userId]
end

function PlotService.keyRefFromPart(part: BasePart)
	return keyOwner[part]
end

-- Ist der Besitzer zuhause? Verdoppelt die Klau-Dauer.
function PlotService.isOwnerHome(userId: number): boolean
	local plot = plotByUser[userId]
	local player = Players:GetPlayerByUserId(userId)
	if not plot or not player then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - plot.base.Position).Magnitude <= WorldConfig.PRESENCE_RADIUS
end

function PlotService.spawnPositionFor(userId: number): Vector3?
	local plot = plotByUser[userId]
	if not plot then
		return nil
	end
	return plot.base.Position + Vector3.new(0, 6, WorldConfig.PLOT_SIZE.Z / 2 - 4)
end

-- Plot zuweisen, sobald das Profil geladen ist, und den Spieler dorthin
-- setzen. Das Profil kommt asynchron aus dem DataStore, deshalb warten
-- wir kurz darauf statt anzunehmen, dass es schon da ist.
local function onPlayerAdded(player: Player)
	local deadline = os.clock() + 20
	while os.clock() < deadline do
		if DataService.get(player) then
			break
		end
		task.wait(0.25)
	end
	if not player.Parent or not DataService.get(player) then
		return
	end
	if not PlotService.assign(player) then
		player:Kick("Der Server ist voll - alle Plots sind vergeben.")
		return
	end

	local function place(character: Model)
		local target = PlotService.spawnPositionFor(player.UserId)
		if target then
			character:PivotTo(CFrame.new(target))
		end
	end
	if player.Character then
		place(player.Character)
	end
	player.CharacterAdded:Connect(place)
end

function PlotService.start()
	PlotService.buildWorld()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		PlotService.release(player.UserId)
	end)
	print("[KEYCAP] PlotService: " .. WorldConfig.PLOT_COUNT .. " Plots gebaut")
end

return PlotService
