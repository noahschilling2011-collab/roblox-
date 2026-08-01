-- ServerScriptService/Systems/TraceService.luau
--!strict
-- GHOSTNET :: Der Trace. Ohne Risiko ist Hacken nur Klicken.
--
-- SO FUNKTIONIERT ER
--   Jeder Spieler hat einen Wert von 0 bis Config.Trace.Max. Jeder Hack
--   treibt ihn hoch - ein Fehlschlag billiger als ein Erfolg, ein Abbruch am
--   billigsten, aber nie gratis. Im Leerlauf faellt er wieder, schneller mit
--   besserer Kuehlung. Ein Verkauf beim Hehler nimmt ein grosses Stueck weg.
--
--   Bei Max ist alles Unverkaufte weg, der Trace faellt auf Config.Trace.AfterBust
--   zurueck und Hacks sind kurz gesperrt. Genau diese Drohung macht die Frage
--   "noch ein Ziel oder jetzt abliefern?" zu einer echten Entscheidung.
--
-- ABHAENGIGKEITEN
--   Der Service kennt den HackService NICHT. Wer beim Bust etwas abbrechen
--   will, meldet sich per TraceService.OnBust an - so bleibt die Richtung
--   HackService -> TraceService und es entsteht kein Require-Kreis.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local EconomyService = require(script.Parent.EconomyService)
local SaveService = require(script.Parent.SaveService)

type Profile = Types.Profile

local TraceService = {}

-- Alle Zeiten hier sind os.clock(): reine Kurzzeit-Timer innerhalb dieses
-- Serverlaufs. Der Trace-WERT selbst liegt im Profil und wird gespeichert.
local lastActivity: { [Player]: number } = {}
local lockedUntil: { [Player]: number } = {}
local lastSyncAt: { [Player]: number } = {}
local lastSyncValue: { [Player]: number } = {}

local bustCallbacks: { (Player, number) -> () } = {}

--==========================================================================
-- Anzeige
--==========================================================================

local function lockSecondsLeft(player: Player): number
	local until_ = lockedUntil[player]
	if not until_ then
		return 0
	end
	return math.max(0, until_ - os.clock())
end

-- force = sofort schicken (Hack, Verkauf, Bust). Ohne force wird nur
-- geschickt, wenn sich sichtbar etwas geaendert hat - der Abkuehl-Loop
-- laeuft sonst mit 4 Paketen pro Sekunde und Spieler.
function TraceService.Sync(player: Player, force: boolean?, bustInfo: { [string]: any }?)
	if not player.Parent then
		return
	end
	local profile = SaveService.Get(player)
	if not profile then
		return
	end

	local now = os.clock()
	if not force then
		local sinceSync = now - (lastSyncAt[player] or 0)
		local delta = math.abs(profile.Trace - (lastSyncValue[player] or -1))
		if sinceSync < Config.Trace.SyncInterval or delta < Config.Trace.SyncEpsilon then
			return
		end
	end

	lastSyncAt[player] = now
	lastSyncValue[player] = profile.Trace

	Remotes.TraceSync:FireClient(player, {
		Trace = profile.Trace,
		Max = Config.Trace.Max,
		Locked = lockSecondsLeft(player) > 0,
		LockSeconds = lockSecondsLeft(player),
		Bust = bustInfo,
	})
end

--==========================================================================
-- Lesen
--==========================================================================

function TraceService.Get(player: Player): number
	local profile = SaveService.Get(player)
	return if profile then profile.Trace else 0
end

function TraceService.IsLocked(player: Player): boolean
	return lockSecondsLeft(player) > 0
end

function TraceService.LockSecondsLeft(player: Player): number
	return lockSecondsLeft(player)
end

-- Wird beim Bust aufgerufen: (spieler, verlorene Crypto).
function TraceService.OnBust(callback: (Player, number) -> ())
	table.insert(bustCallbacks, callback)
end

--==========================================================================
-- Schreiben
--==========================================================================

local function bust(player: Player, profile: Profile)
	local lost = EconomyService.WipeUnsold(player)
	EconomyService.CountBust(player)

	profile.Trace = Config.Trace.AfterBust
	lockedUntil[player] = os.clock() + Config.Trace.BustLockSeconds
	lastActivity[player] = os.clock()

	warn(("[GHOSTNET] BUST: %s verliert %d CRY."):format(player.Name, lost))

	for _, callback in bustCallbacks do
		task.spawn(callback, player, lost)
	end

	TraceService.Sync(player, true, { Lost = lost, LockSeconds = Config.Trace.BustLockSeconds })
	SaveService.RequestSave(player)
end

-- Der einzige Weg, den Trace zu erhoehen. Wird vom HackService mit dem dort
-- bereits berechneten traceDelta aufgerufen.
function TraceService.Add(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local profile = SaveService.Get(player)
	if not profile then
		return
	end

	lastActivity[player] = os.clock()
	profile.Trace = math.min(Config.Trace.Max, profile.Trace + amount)

	if profile.Trace >= Config.Trace.Max then
		bust(player, profile)
	else
		TraceService.Sync(player, true)
	end
end

-- Verkauf beim Hehler. Der Hehler ist damit nicht nur eine Bank, sondern der
-- sichere Hafen.
function TraceService.Relieve(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	profile.Trace = math.max(0, profile.Trace - amount)
	TraceService.Sync(player, true)
end

--==========================================================================
-- Abkuehlung
--==========================================================================

local function decayLoop()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Trace.DecayTick then
			return
		end
		local step = accumulator
		accumulator = 0

		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local profile = SaveService.Get(player)
			if not profile then
				continue
			end

			-- Sperre gerade abgelaufen: einmal melden, damit der HUD aufmacht.
			local until_ = lockedUntil[player]
			if until_ and now >= until_ then
				lockedUntil[player] = nil
				TraceService.Sync(player, true)
			end

			if profile.Trace <= 0 then
				continue
			end
			if now - (lastActivity[player] or 0) < Config.Trace.DecayDelay then
				continue
			end

			profile.Trace = math.max(0, profile.Trace - Config.GetTraceDecay(profile.Rig.Cooling) * step)
			TraceService.Sync(player, false)
		end
	end)
end

--==========================================================================

function TraceService.Init()
	SaveService.OnReady(function(player)
		lastActivity[player] = os.clock()
		TraceService.Sync(player, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastActivity[player] = nil
		lockedUntil[player] = nil
		lastSyncAt[player] = nil
		lastSyncValue[player] = nil
	end)

	decayLoop()

	print(("[GHOSTNET] TraceService bereit. Bust bei %d, Abkuehlung %.2f/s."):format(
		Config.Trace.Max,
		Config.Trace.DecayPerSecond
	))
end

return TraceService
