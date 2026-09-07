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
	slotFolder: Folder,
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
		base.Color = Theme.WORLD.PLATE
		base.Material = Theme.WORLD.PLATE_MATERIAL
		base.Parent = model

		-- Chassis: etwas groesser und dunkler, sitzt unter der Platte. Damit
		-- liest sich der Plot als Tastatur-Gehaeuse statt als schwebende
		-- Scheibe. Dieselbe Sprache wie die Knopf-Unterkante im HUD.
		local deck = Instance.new("Part")
		deck.Name = "Deck"
		deck.Size = Vector3.new(
			WorldConfig.PLOT_SIZE.X + WorldConfig.PLOT_DECK_OVERHANG * 2,
			WorldConfig.PLOT_DECK_HEIGHT,
			WorldConfig.PLOT_SIZE.Z + WorldConfig.PLOT_DECK_OVERHANG * 2
		)
		deck.Position = base.Position
			- Vector3.new(0, WorldConfig.PLOT_SIZE.Y / 2 + WorldConfig.PLOT_DECK_HEIGHT / 2, 0)
		deck.Anchored = true
		deck.TopSurface = Enum.SurfaceType.Smooth
		deck.BottomSurface = Enum.SurfaceType.Smooth
		deck.Color = Theme.WORLD.CHASSIS
		deck.Material = Theme.WORLD.CHASSIS_MATERIAL
		deck.Parent = model

		-- Leere Steckplaetze als flache Mulden. Sie werden EINMAL gebaut und
		-- danach nur ein- und ausgeblendet - renderKeys darf sie nicht
		-- zerstoeren, sonst kostet jeder Kauf und jeder Klau 20 Instanzen
		-- mehr.
		local slotFolder = Instance.new("Folder")
		slotFolder.Name = "Slots"
		for slot = 1, EconomyConfig.MAX_KEY_SLOTS do
			local marker = Instance.new("Part")
			marker.Name = "Slot" .. slot
			marker.Size = Vector3.new(
				WorldConfig.KEY_SIZE.X * WorldConfig.SLOT_MARKER_SCALE,
				WorldConfig.SLOT_MARKER_HEIGHT,
				WorldConfig.KEY_SIZE.Z * WorldConfig.SLOT_MARKER_SCALE
			)
			local raster = WorldLayout.slotPosition(base.Position, slot)
			marker.Position = Vector3.new(
				raster.X,
				base.Position.Y + WorldConfig.PLOT_SIZE.Y / 2 + WorldConfig.SLOT_MARKER_HEIGHT / 2,
				raster.Z
			)
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.TopSurface = Enum.SurfaceType.Smooth
			marker.Color = Theme.WORLD.SOCKET
			marker.Material = Theme.WORLD.SOCKET_MATERIAL
			marker.Parent = slotFolder
		end
		slotFolder.Parent = model

		-- Schild: echte Tafel statt unsichtbarer Part. Der Text haengt
		-- weiterhin als BillboardGui darueber, damit er aus der Entfernung
		-- lesbar bleibt.
		local sign = Instance.new("Part")
		sign.Name = "Sign"
		sign.Size = WorldConfig.SIGN_BOARD_SIZE
		sign.Position = WorldLayout.signPosition(base.Position)
		sign.Anchored = true
		sign.CanCollide = false
		sign.TopSurface = Enum.SurfaceType.Smooth
		sign.Color = Theme.WORLD.PLATE
		sign.Material = Theme.WORLD.PLATE_MATERIAL
		sign.Parent = model

		local signEdge = Instance.new("SelectionBox")
		signEdge.Adornee = sign
		signEdge.Color3 = Theme.WORLD.SEAM
		signEdge.LineThickness = 0.06
		signEdge.SurfaceTransparency = 1
		signEdge.Parent = sign

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
			slotFolder = slotFolder,
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

-- Belegte Steckplaetze verstecken ihre Mulde, freie zeigen sie. Die Parts
-- werden dabei nur ein- und ausgeblendet, nicht erzeugt oder zerstoert.
local function updateSlotMarkers(plot: Plot, belegt: number, slots: number)
	for slot = 1, EconomyConfig.MAX_KEY_SLOTS do
		local marker = plot.slotFolder:FindFirstChild("Slot" .. slot)
		if marker and marker:IsA("BasePart") then
			if slot <= belegt then
				marker.Transparency = 1 -- unter der Taste, nicht sichtbar
			elseif slot <= slots then
				marker.Transparency = 0 -- frei und kaufbar
			else
				marker.Transparency = 1 -- Steckplatz noch nicht gekauft
			end
		end
	end
end

-- Baut die Tasten-Parts eines Plots neu. `keys` ist die Liste, die dieser
-- Plot gerade haelt - beim Spieler das Profil, beim NPC die NPC-Liste.
function PlotService.renderKeys(plot: Plot, keys: { { rarity: string, vorrat: number } }, slots: number?)
	clearKeys(plot)
	updateSlotMarkers(plot, #keys, slots or #keys)

	for index, key in keys do
		-- Hoehe, Kantenlicht und Material haengen an der Seltenheit. Eine
		-- Legendary muss sich aus 20 m von einer Common unterscheiden
		-- lassen - daran haengt, ob ein Dieb weiss, wo der Weg sich lohnt.
		local rank = Theme.RARITY_RANK[key.rarity] or 1
		local crown = Theme.KEY_CROWN[key.rarity] or 1
		local extra = WorldConfig.KEY_SIZE.Y * (crown - 1)

		local part = Instance.new("Part")
		part.Name = "Key" .. index
		part.Size = Vector3.new(WorldConfig.KEY_SIZE.X, WorldConfig.KEY_SIZE.Y * crown, WorldConfig.KEY_SIZE.Z)
		-- Grundflaeche bleibt, die Taste waechst nach oben: das Raster aus
		-- WorldLayout.slotPosition passt weiter.
		part.Position = WorldLayout.slotPosition(plot.base.Position, index) + Vector3.new(0, extra / 2, 0)
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.Material = Theme.RARITY_MATERIAL[key.rarity] or Enum.Material.SmoothPlastic
		part.Color = Theme.RARITY_COLORS[key.rarity] or Theme.WORLD.PLATE

		-- Deckplatte: schmaler als der Koerper, sitzt oben drauf. Der
		-- Absatz dazwischen IST die Keycap-Silhouette.
		local top = Instance.new("Part")
		top.Name = "Top"
		top.Size = Vector3.new(
			WorldConfig.KEY_SIZE.X * WorldConfig.KEY_TOP_INSET,
			WorldConfig.KEY_TOP_HEIGHT,
			WorldConfig.KEY_SIZE.Z * WorldConfig.KEY_TOP_INSET
		)
		top.Position = part.Position
			+ Vector3.new(0, part.Size.Y / 2 + WorldConfig.KEY_TOP_HEIGHT / 2, 0)
		top.Anchored = true
		top.CanCollide = false
		top.TopSurface = Enum.SurfaceType.Smooth
		top.Material = part.Material
		top.Color = part.Color
		top.Parent = plot.keyFolder

		-- Stem-Ring: dunkel, schmaler, setzt die Kappe vom Sockel ab.
		local stem = Instance.new("Part")
		stem.Name = "Stem"
		stem.Size = Vector3.new(
			WorldConfig.KEY_SIZE.X * WorldConfig.KEY_STEM_INSET,
			WorldConfig.KEY_STEM_HEIGHT,
			WorldConfig.KEY_SIZE.Z * WorldConfig.KEY_STEM_INSET
		)
		stem.Position = part.Position
			- Vector3.new(0, part.Size.Y / 2 - WorldConfig.KEY_STEM_HEIGHT / 2, 0)
		stem.Anchored = true
		stem.CanCollide = false
		stem.TopSurface = Enum.SurfaceType.Smooth
		stem.Material = Theme.WORLD.SOCKET_MATERIAL
		stem.Color = Theme.RARITY_EDGE[key.rarity] or Theme.WORLD.SEAM
		stem.Parent = plot.keyFolder

		-- Licht ab Rare. Das ist keine Deko: Rare und Epic schaffen gegen
		-- die Tastaturplatte nur 2,89 bzw. 2,82:1 - ohne eigenes Licht
		-- verschwinden sie auf dem dunklen Untergrund.
		local reichweite = Theme.RARITY_LIGHT_RANGE[key.rarity] or 0
		if reichweite > 0 then
			local glow = Instance.new("PointLight")
			glow.Color = Theme.RARITY_COLORS[key.rarity] or Theme.WORLD.SIGNAL
			glow.Range = reichweite
			glow.Brightness = Theme.RARITY_LIGHT_BRIGHTNESS
			glow.Shadows = false -- Schatten von 192 Lichtern waeren nicht bezahlbar
			glow.Parent = top
		end

		-- Kantenlicht statt Schatten: Roblox-UI kann keinen Schatten, und
		-- in der Welt zeichnet eine SelectionBox die Kanten sauber nach.
		local rim = Instance.new("SelectionBox")
		rim.Adornee = part
		rim.Color3 = Theme.RARITY_EDGE[key.rarity] or Theme.WORLD.SEAM
		rim.LineThickness = Theme.KEY_RIM_BASE + Theme.KEY_RIM_STEP * rank
		rim.SurfaceTransparency = 1
		rim.Parent = part

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Info"
		billboard.Size = UDim2.new(0, 190, 0, 68)
		billboard.StudsOffset = Vector3.new(0, 2.6 + extra / 2, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = Theme.KEY_LABEL_DISTANCE

		-- Seltenheit klein darueber, Vorrat gross darunter. Aus der Ferne
		-- bleibt nur die Zahl lesbar - und genau die entscheidet.
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarity"
		rarityLabel.Size = UDim2.new(1, 0, 0.36, 0)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Font = Theme.FONT
		rarityLabel.TextScaled = true
		rarityLabel.TextColor3 = Theme.RARITY_COLORS[key.rarity] or Theme.PANEL
		rarityLabel.TextStrokeTransparency = 0.25
		rarityLabel.Text = string.upper(key.rarity)
		rarityLabel.Parent = billboard

		local label = Instance.new("TextLabel")
		label.Name = "Vorrat"
		label.Size = UDim2.new(1, 0, 0.64, 0)
		label.Position = UDim2.new(0, 0, 0.36, 0)
		label.BackgroundTransparency = 1
		label.Font = Theme.FONT
		label.TextScaled = true
		label.TextColor3 = Theme.PANEL
		label.TextStrokeTransparency = 0.2
		label.Text = "0"
		label.Parent = billboard
		billboard.Parent = part

		-- Buchstabe auf der Oberseite: macht aus dem Wuerfel eine Taste.
		local legend = Instance.new("SurfaceGui")
		legend.Name = "Legend"
		legend.Face = Enum.NormalId.Top
		legend.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		legend.PixelsPerStud = 50

		local letter = Instance.new("TextLabel")
		-- Nicht randlos mittig, sondern leicht nach oben-links - so sitzt
		-- die Legende auf einer echten Tastatur.
		letter.Position = UDim2.new(WorldConfig.KEY_LEGEND_OFFSET.X, 0, WorldConfig.KEY_LEGEND_OFFSET.Y, 0)
		letter.Size = UDim2.new(1, 0, 1, 0)
		letter.BackgroundTransparency = 1
		letter.Font = Theme.FONT
		letter.TextScaled = true
		letter.TextColor3 = Theme.RARITY_INK[key.rarity] or Theme.TEXT
		letter.Text = WorldConfig.KEY_LEGENDS[index] or "?"
		letter.Parent = legend
		legend.Parent = top

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
	PlotService.renderKeys(plot, profile.keys, profile.slots)
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
			-- Nur noch die Zahl: die Seltenheit steht im eigenen Label
			-- darueber und aendert sich nicht.
			label.Text = tostring(math.floor(key.vorrat))
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
	updateSlotMarkers(plot, 0, 0)
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
