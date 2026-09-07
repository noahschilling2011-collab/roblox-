--!strict
-- Parcours: Speed-Tore und Cash-Out-Pads.
--
-- Auszahlen ist bewusst ein ProximityPrompt, kein Beruehrungs-Trigger:
-- ein versehentlicher Vorrat-Reset waere der schlimmste Moment im Spiel.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyLogic = require(Shared.EconomyLogic)
local WorldConfig = require(Shared.Config.WorldConfig)
local Theme = require(Shared.Theme)
local WorldLayout = require(Shared.WorldLayout)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local ProductionService = require(script.Parent.ProductionService)
local RunTimerService = require(script.Parent.RunTimerService)
local TutorialService = require(script.Parent.TutorialService)

local CourseService = {}

local pads: { BasePart } = {}
local lastBlock: { [number]: number } = {} -- userId -> os.clock, entprellt das Tor

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

-- Kein Tor mehr, sondern ein Schild. Die alte Wand war CanCollide = false
-- und schob bei Beruehrung 12 Studs zurueck, entprellt mit 1,5 s - ein
-- Spieler mit Basis-Speed 16 legt in dieser Zeit 24 Studs zurueck und kam
-- mit +12 Studs pro Zyklus einfach durch. Jetzt ist die Sprungweite das
-- Gate, und das Schild sagt nur, was man dafuer braucht.
local function buildSign(stageIndex: number)
	-- Die Diagonale, nicht die Luecke - sonst nennt das Schild eine zu
	-- niedrige Zahl und der Spieler faellt trotzdem.
	local noetig = WorldLayout.speedForGap(WorldLayout.stageJumpDistance(stageIndex))

	local board = Instance.new("Part")
	board.Name = "StageSign" .. stageIndex
	board.Size = WorldConfig.STAGE_GATE_SIZE
	board.Position = WorldConfig.STAGE_GATE_POSITIONS[stageIndex]
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.Material = Enum.Material.Neon
	board.Color = Theme.WORLD.SIGNAL_DIM
	board.Transparency = 0.35
	board.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 320, 0, 90)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 400

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT
	label.TextScaled = true
	label.TextColor3 = Theme.WORLD.SIGNAL
	label.TextStrokeTransparency = 0.3
	label.Text = ("STAGE %d\nSpruenge ab Tempo %d"):format(stageIndex, math.ceil(noetig))
	label.Parent = billboard
	billboard.Parent = board
end

local function cashOut(player: Player, stageIndex: number, pad: BasePart)
	local profile = DataService.get(player)
	if not profile then
		return
	end

	-- Distanz serverseitig nachpruefen, nicht dem Prompt vertrauen.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - pad.Position).Magnitude > pad.Size.X then
		return
	end

	local vorrat = ProductionService.totalVorrat(profile)
	if not EconomyLogic.canEnterStage(vorrat, stageIndex) then
		notify(player, "Du bist zu langsam fuer dieses Pad.")
		return
	end

	local wins = EconomyLogic.payout(vorrat, stageIndex)
	if wins <= 0 then
		notify(player, "Zu wenig Vorrat - das lohnt sich noch nicht.")
		return
	end

	profile.wins += wins
	profile.totalCashedOut += wins
	for _, key in profile.keys do
		key.vorrat = 0 -- Auszahlen leert ALLE Tasten
	end

	DataService.syncLeaderstats(player)
	PlotService.collapseBeacon(player.UserId)
	RunTimerService.markCashOut(player, stageIndex)
	TutorialService.report(player, "cashout")
	notify(player, ("+%d Wins ausgezahlt (Stage %d)."):format(wins, stageIndex))
	-- Die Belohnung braucht mehr als eine Zeile oben am Rand: der Vorrat
	-- ist gerade komplett weg, das muss sich gross anfuehlen.
	Remotes.get("Alert"):FireClient(player, {
		kind = "cashout",
		title = ("+%d"):format(wins),
		body = ("Wins - Vorrat %d geleert an Stage %d"):format(vorrat, stageIndex),
	})
end

local function buildPad(stageIndex: number)
	local pad = Instance.new("Part")
	pad.Name = "CashOut" .. stageIndex
	pad.Size = WorldConfig.STAGE_PAD_SIZE
	pad.Position = WorldConfig.STAGE_PAD_POSITIONS[stageIndex]
	pad.Anchored = true
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.Material = Enum.Material.Neon
	pad.Color = Theme.WORLD.SIGNAL
	pad.Parent = workspace
	pads[stageIndex] = pad

	-- Podest unter dem Pad: derselbe Aufbau wie Plotplatte auf Chassis und
	-- Knopf auf Unterkante. Aus der Entfernung wird daraus ein Ziel statt
	-- eines Flecks im Boden.
	local ring = Instance.new("Part")
	ring.Name = "CashOutRing" .. stageIndex
	ring.Size = Vector3.new(
		WorldConfig.STAGE_PAD_SIZE.X + WorldConfig.PAD_RING_OVERHANG * 2,
		WorldConfig.PAD_RING_HEIGHT,
		WorldConfig.STAGE_PAD_SIZE.Z + WorldConfig.PAD_RING_OVERHANG * 2
	)
	ring.Position = pad.Position
		- Vector3.new(0, WorldConfig.STAGE_PAD_SIZE.Y / 2 + WorldConfig.PAD_RING_HEIGHT / 2, 0)
	ring.Anchored = true
	ring.TopSurface = Enum.SurfaceType.Smooth
	ring.BottomSurface = Enum.SurfaceType.Smooth
	ring.Material = Theme.WORLD.PLATE_MATERIAL
	ring.Color = Theme.WORLD.SIGNAL_DIM
	ring.Parent = workspace

	local factors = EconomyLogic.payoutFactors()

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 280, 0, 80)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 300

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT
	label.TextScaled = true
	label.TextColor3 = Theme.TEXT
	label.TextStrokeTransparency = 0.4
	label.Text = ("AUSZAHLEN %d\n%.1f%% vom Vorrat"):format(stageIndex, factors[stageIndex] * 100)
	label.Parent = billboard
	billboard.Parent = pad

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Auszahlen"
	prompt.ObjectText = "Stage " .. stageIndex
	prompt.HoldDuration = EconomyConfig.CASHOUT_HOLD_SECONDS
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(function(player)
		cashOut(player, stageIndex, pad)
	end)
end

-- Boden. Die Plots stehen mit Luecke nebeneinander und der Parcours haengt
-- in der Luft - ohne diese beiden Flaechen faellt jeder Spieler beim ersten
-- Schritt vom Plot herunter.
-- Boden. Die Plots stehen mit Luecke nebeneinander und der Parcours haengt
-- in der Luft - ohne diese beiden Flaechen faellt jeder Spieler beim ersten
-- Schritt vom Plot herunter. Die Masse kommen aus WorldLayout, damit die
-- Vorschau in der Studio-Datei exakt dasselbe zeigt.
local function slab(name: string, box, farbe: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = box.size
	part.Position = box.position
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material
	part.Color = farbe
	part.Parent = workspace
	return part
end

-- Die Promenade verbindet die Plots. Der lange, ebene Weg dahinter ist
-- WEG - an seiner Stelle steht jetzt der Parcours. Ein huebscher leerer
-- Gang bleibt ein leerer Gang.
local function buildGround()
	slab("Promenade", WorldLayout.promenade(), Theme.WORLD.PATH, Theme.WORLD.PATH_MATERIAL)
end

-- Eine Plattform ist eine Riesen-Tastenkappe: Koerper plus schmalere
-- Deckplatte, dieselbe Silhouette wie die Tasten auf den Plots.
local function buildPlatform(stageIndex: number, index: number, platform): BasePart
	local koerper = Instance.new("Part")
	koerper.Name = ("Stage%dPlatform%d"):format(stageIndex, index)
	koerper.Size = platform.size
	koerper.Position = platform.position
	koerper.Anchored = true
	koerper.TopSurface = Enum.SurfaceType.Smooth
	koerper.Material = Theme.WORLD.PLATE_MATERIAL
	koerper.Color = Theme.WORLD.PLATE
	koerper.Parent = workspace

	local deckel = Instance.new("Part")
	deckel.Name = koerper.Name .. "Top"
	deckel.Size = Vector3.new(
		platform.size.X * WorldConfig.KEY_TOP_INSET,
		WorldConfig.KEY_TOP_HEIGHT,
		platform.size.Z * WorldConfig.KEY_TOP_INSET
	)
	deckel.Position = platform.position
		+ Vector3.new(0, platform.size.Y / 2 + WorldConfig.KEY_TOP_HEIGHT / 2, 0)
	deckel.Anchored = true
	deckel.TopSurface = Enum.SurfaceType.Smooth
	deckel.Material = Theme.WORLD.CHASSIS_MATERIAL
	deckel.Color = Theme.WORLD.CHASSIS
	deckel.Parent = workspace

	if platform.moves then
		-- Senkrecht, langsam, kleine Amplitude.
		-- ungeprueft: ob ein verankerter Part per CFrame-Tween den Spieler
		-- zuverlaessig traegt. Die Recherche sagt: waagerecht nein,
		-- senkrecht ueber die Kollisionsaufloesung ruckelig ja. Deshalb
		-- nur 4 Studs Hub und 2,6 s pro Richtung.
		local info = TweenInfo.new(
			WorldConfig.MOVING_SECONDS,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1, -- endlos
			true -- hin und zurueck
		)
		local hub = Vector3.new(0, WorldConfig.MOVING_AMPLITUDE, 0)
		TweenService:Create(koerper, info, { Position = platform.position + hub }):Play()
		TweenService:Create(deckel, info, { Position = deckel.Position + hub }):Play()
	end

	return koerper
end

-- Absturz setzt an den Anfang DER STAGE zurueck, nicht auf den Plot.
-- Fehler kostet Zeit, nicht den Lauf.
function CourseService.startFallWatch()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < 0.25 then
			return
		end
		accumulator = 0

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") or root.Position.Y > WorldConfig.FALL_Y then
				continue
			end
			-- Welche Stage war das? Die, deren Plattformen den Absturzort
			-- in Z umschliessen; sonst zurueck auf die Promenade.
			local ziel = WorldLayout.promenade().position + Vector3.new(0, 6, 0)
			for stageIndex = 1, #WorldConfig.STAGES do
				local platforms = WorldLayout.stagePlatforms(stageIndex)
				local erste, letzte = platforms[1], platforms[#platforms]
				if erste and letzte and root.Position.Z <= erste.position.Z and root.Position.Z >= letzte.position.Z then
					ziel = erste.position + Vector3.new(0, 6, 0)
					break
				end
			end
			character:PivotTo(CFrame.new(ziel))
		end
	end)
end

function CourseService.start()
	buildGround()
	local plattformen = 0
	for stageIndex = 1, #WorldConfig.STAGES do
		buildSign(stageIndex)
		buildPad(stageIndex)
		for index, platform in WorldLayout.stagePlatforms(stageIndex) do
			buildPlatform(stageIndex, index, platform)
			plattformen += 1
		end
	end
	CourseService.startFallWatch()
	local duration, cooldown = EconomyLogic.shieldWindow()
	print(("[KEYCAP] CourseService: %d Stages, %d Plattformen, Schild %ds/%ds"):format(#pads, plattformen, duration, cooldown))
end

return CourseService
