--!strict
-- Baut die Plots, vergibt sie an Spieler oder an NPC-Besitzer und haelt die
-- Tasten-Parts synchron mit der jeweiligen Tastenliste.
--
-- Ein Plot gehoert entweder niemandem, einem Spieler oder einem NPC. Die
-- Tasten-Parts sehen in allen Faellen gleich aus - ein Dieb soll nicht auf
-- den ersten Blick erkennen, ob es sich "lohnt", sondern hinlaufen muessen.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local Theme = require(Shared.Theme)
local WorldLayout = require(Shared.WorldLayout)
local DataService = require(script.Parent.DataService)

local PlotService = {}

export type OwnerKind = "none" | "player" | "npc"
export type Plot = {
	index: number,
	model: Model,
	base: BasePart,
	keyFolder: Folder,
	ownerKind: OwnerKind,
	ownerUserId: number?,
	signLabel: TextLabel,
}
export type KeyRef = { kind: OwnerKind, userId: number?, plotIndex: number, index: number }

local plots: { Plot } = {}
local plotByUser: { [number]: Plot } = {}
-- Rueckweg vom Part zum Eintrag, damit StealService nichts raten muss.
local keyOwner: { [BasePart]: KeyRef } = {}

function PlotService.buildWorld()
	if built then
		return
	end
	built = true

	local container = Instance.new("Folder")
	container.Name = "Plots"

	for index = 1, WorldConfig.PLOT_COUNT do
		local model = Instance.new("Model")
		model.Name = "Plot" .. index

		local base = Instance.new("Part")
		base.Name = "Base"
		base.Size = WorldConfig.PLOT_SIZE
		base.Position = WorldLayout.plotPosition(index)
		base.Anchored = true
		base.TopSurface = Enum.SurfaceType.Smooth
		base.BottomSurface = Enum.SurfaceType.Smooth
		base.Color = Theme.PANEL
		base.Material = Enum.Material.SmoothPlastic
		base.Parent = model

		local sign = Instance.new("Part")
		sign.Name = "Sign"
		sign.Size = Vector3.new(10, 1, 1)
		sign.Position = WorldLayout.signPosition(base.Position)
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
			ownerKind = "none",
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

-- Baut die Tasten-Parts eines Plots neu. `keys` ist die Liste, die dieser
-- Plot gerade haelt - beim Spieler das Profil, beim NPC die NPC-Liste.
function PlotService.renderKeys(plot: Plot, keys: { { rarity: string, vorrat: number } })
	clearKeys(plot)

	for index, key in keys do
		local part = Instance.new("Part")
		part.Name = "Key" .. index
		part.Size = WorldConfig.KEY_SIZE
		part.Position = WorldLayout.slotPosition(plot.base.Position, index)
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

		-- Buchstabe auf der Oberseite: macht aus dem Wuerfel eine Taste.
		local legend = Instance.new("SurfaceGui")
		legend.Name = "Legend"
		legend.Face = Enum.NormalId.Top
		legend.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		legend.PixelsPerStud = 50

		local letter = Instance.new("TextLabel")
		letter.Size = UDim2.new(1, 0, 1, 0)
		letter.BackgroundTransparency = 1
		letter.Font = Theme.FONT
		letter.TextScaled = true
		letter.TextColor3 = Theme.TEXT
		letter.Text = WorldConfig.KEY_LEGENDS[index] or "?"
		letter.Parent = legend
		legend.Parent = part

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Steal"
		prompt.ActionText = "Klauen"
		prompt.ObjectText = key.rarity
		prompt.HoldDuration = EconomyConfig.STEAL_HOLD_SECONDS
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = part

		part.Parent = plot.keyFolder
		keyOwner[part] = {
			kind = plot.ownerKind,
			userId = plot.ownerUserId,
			plotIndex = plot.index,
			index = index,
		}
	end
end

-- Bequemer Weg fuer den Spielerfall: Liste kommt aus dem Profil.
function PlotService.rebuildKeys(userId: number)
	local plot = plotByUser[userId]
	if not plot then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	local profile = if player then DataService.get(player) else nil
	if not profile then
		clearKeys(plot)
		return
	end
	PlotService.renderKeys(plot, profile.keys)
end

-- Beschriftungen aktualisieren (eigener Takt, damit nicht jede Sekunde
-- hunderte Labels repliziert werden).
function PlotService.refreshLabels(plot: Plot, keys: { { rarity: string, vorrat: number } })
	for _, part in plot.keyFolder:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local ref = keyOwner[part]
		local key = if ref then keys[ref.index] else nil
		local billboard = part:FindFirstChild("Info")
		local label = if billboard then billboard:FindFirstChild("Vorrat") else nil
		if key and label and label:IsA("TextLabel") then
			label.Text = ("%s\n%d"):format(key.rarity, math.floor(key.vorrat))
		end
	end
end

function PlotService.refreshKeyLabels(userId: number)
	local plot = plotByUser[userId]
	local player = Players:GetPlayerByUserId(userId)
	local profile = if player then DataService.get(player) else nil
	if plot and profile then
		PlotService.refreshLabels(plot, profile.keys)
	end
end

-- NPC-Plots belegen die letzten Plots der Reihe, damit die Spieler vorne
-- nebeneinander stehen.
function PlotService.claimForNpc(slot: number, name: string): Plot?
	local index = WorldConfig.PLOT_COUNT - slot + 1
	local plot = plots[index]
	if not plot or plot.ownerKind ~= "none" then
		return nil
	end
	plot.ownerKind = "npc"
	plot.ownerUserId = nil
	plot.signLabel.Text = name
	plot.signLabel.TextColor3 = Theme.TEXT_MUTED
	return plot
end

function PlotService.assign(player: Player): boolean
	for _, plot in plots do
		if plot.ownerKind == "none" then
			plot.ownerKind = "player"
			plot.ownerUserId = player.UserId
			plotByUser[player.UserId] = plot
			plot.signLabel.Text = player.DisplayName
			plot.signLabel.TextColor3 = Theme.TEXT
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
	plot.ownerKind = "none"
	plot.ownerUserId = nil
	plot.signLabel.Text = "Frei"
	plotByUser[userId] = nil
end

function PlotService.getPlot(userId: number): Plot?
	return plotByUser[userId]
end

function PlotService.plotAt(index: number): Plot?
	return plots[index]
end

function PlotService.keyRefFromPart(part: BasePart): KeyRef?
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

-- Zaehlt alles, was der Server gebaut hat - fuer das Part-Budget.
function PlotService.countParts(): number
	local count = 0
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
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
