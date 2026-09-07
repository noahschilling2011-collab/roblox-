--!strict
-- Parcours: Speed-Tore und Cash-Out-Pads.
--
-- Auszahlen ist bewusst ein ProximityPrompt, kein Beruehrungs-Trigger:
-- ein versehentlicher Vorrat-Reset waere der schlimmste Moment im Spiel.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyLogic = require(Shared.EconomyLogic)
local WorldConfig = require(Shared.Config.WorldConfig)
local Theme = require(Shared.Theme)
local WorldLayout = require(Shared.WorldLayout)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ProductionService = require(script.Parent.ProductionService)
local RunTimerService = require(script.Parent.RunTimerService)
local TutorialService = require(script.Parent.TutorialService)

local CourseService = {}

local pads: { BasePart } = {}
local lastBlock: { [number]: number } = {} -- userId -> os.clock, entprellt das Tor

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

local function buildGate(stageIndex: number)
	local gate = Instance.new("Part")
	gate.Name = "Gate" .. stageIndex
	gate.Size = WorldConfig.STAGE_GATE_SIZE
	gate.Position = WorldConfig.STAGE_GATE_POSITIONS[stageIndex]
	gate.Anchored = true
	gate.CanCollide = false
	gate.Transparency = 0.55
	gate.Material = Enum.Material.Neon
	gate.Color = Theme.BLUE
	gate.Parent = workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 260, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 300

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT
	label.TextScaled = true
	label.TextColor3 = Theme.TEXT
	label.TextStrokeTransparency = 0.4
	label.Text = ("Stage %d\nab Tempo %d"):format(stageIndex, EconomyConfig.STAGE_GATES[stageIndex])
	label.Parent = billboard
	billboard.Parent = gate

	-- Wer zu langsam ist, wird zurueckgesetzt. Kein Kick, kein Schaden -
	-- das Tor ist eine Mautstation, keine Strafe.
	gate.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		local profile = DataService.get(player)
		if not profile then
			return
		end
		local vorrat = ProductionService.totalVorrat(profile)
		if EconomyLogic.canEnterStage(vorrat, stageIndex) then
			return
		end
		local now = os.clock()
		if (lastBlock[player.UserId] or 0) + 1.5 > now then
			return
		end
		lastBlock[player.UserId] = now
		root.CFrame = root.CFrame + Vector3.new(0, 0, 12) -- zurueck Richtung Plots
		local needed = EconomyLogic.vorratForStage(stageIndex)
		notify(player, ("Zu langsam fuer Stage %d - du brauchst %d Vorrat."):format(stageIndex, needed))
	end)
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
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = Theme.GOLD
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
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Theme.PAD_RING
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
local function buildGround()
	local function slab(name: string, box)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = box.size
		part.Position = box.position
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Theme.GROUND
		part.Parent = workspace
	end

	slab("Promenade", WorldLayout.promenade())
	slab("Path", WorldLayout.path())
end

function CourseService.start()
	buildGround()
	for stageIndex = 1, #EconomyConfig.STAGE_GATES do
		buildGate(stageIndex)
		buildPad(stageIndex)
	end
	local duration, cooldown = EconomyLogic.shieldWindow()
	print(("[KEYCAP] CourseService: %d Stages gebaut, Schild %ds/%ds"):format(#pads, duration, cooldown))
end

return CourseService
