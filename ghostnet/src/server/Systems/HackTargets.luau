-- ServerScriptService/Systems/HackTargets.luau
--!strict
-- GHOSTNET :: Registry aller hackbaren Objekte.
--
-- Ein Hack-Ziel ist NUR ein BasePart mit dem Tag "GhostNetHackable".
-- Alle Eigenschaften kommen aus Attributen, fehlende aus Config.TargetDefaults.
-- Ein neues Ziel = neuer Part + Tag. Kein Code.
--
-- ZEITEN
--   Cooldowns liegen im Profil und benutzen os.time() (Unix-Zeit), damit sie
--   einen Serverwechsel ueberleben. Nur DownUntil - "die Kamera ist noch 30
--   Sekunden aus" - bleibt bei os.clock(): das ist ein reiner Kurzzeit-Timer
--   dieses Serverlaufs und gilt fuer alle Spieler gleichzeitig.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Types = require(ReplicatedStorage.Shared.Types)

local SaveService = require(script.Parent.SaveService)

type HackTarget = Types.HackTarget

local HackTargets = {}

local registry: { [string]: HackTarget } = {}
local byPart: { [BasePart]: HackTarget } = {}
local idCounter = 0

--==========================================================================
-- Attribute lesen
--==========================================================================

local function attrNumber(part: BasePart, name: string, default: number): number
	local v = part:GetAttribute(name)
	if typeof(v) == "number" then
		return v
	end
	return default
end

local function attrString(part: BasePart, name: string, default: string): string
	local v = part:GetAttribute(name)
	if typeof(v) == "string" and v ~= "" then
		return v
	end
	return default
end

local function readTarget(part: BasePart, id: string): HackTarget
	local d = Config.TargetDefaults

	local difficulty = math.clamp(math.floor(attrNumber(part, "Difficulty", d.Difficulty)), 1, 10)

	local reward = attrNumber(part, "Reward", d.Reward)
	if reward < 0 then
		reward = Config.GetReward(difficulty)
	end

	local traceGain = attrNumber(part, "TraceGain", d.TraceGain)
	if traceGain < 0 then
		traceGain = difficulty * Config.Trace.GainPerDifficulty
	end

	local cooldown = attrNumber(part, "Cooldown", d.Cooldown)
	if cooldown < 0 then
		cooldown = Config.Cooldown.Default
	end

	local displayName = attrString(part, "DisplayName", d.DisplayName)
	if displayName == "" then
		displayName = part.Name
	end

	local existing = registry[id]
	return {
		Id = id,
		Part = part,
		DisplayName = displayName,
		Difficulty = difficulty,
		HackType = attrString(part, "HackType", d.HackType),
		Reward = math.floor(reward),
		TraceGain = traceGain,
		Cooldown = cooldown,
		RequiredLevel = math.max(1, math.floor(attrNumber(part, "RequiredLevel", d.RequiredLevel))),
		OnSuccess = attrString(part, "OnSuccess", d.OnSuccess),
		DownTime = attrNumber(part, "DownTime", d.DownTime),
		DownUntil = existing and existing.DownUntil or 0,
	}
end

--==========================================================================
-- Registrierung
--==========================================================================

-- Zaehlt hoch, bis eine Id wirklich frei ist. Frueher wurde nur einmal
-- generiert - ein Part mit gespeichertem Attribut "T0001" und ein Part ohne
-- Attribut bekamen dann dieselbe Id, und das erste Ziel war nicht mehr
-- erreichbar.
local function nextFreeId(): string
	repeat
		idCounter += 1
	until registry[("T%04d"):format(idCounter)] == nil
	return ("T%04d"):format(idCounter)
end

local function register(inst: Instance)
	if not inst:IsA("BasePart") then
		warn(("[GHOSTNET] '%s' hat den Hackable-Tag, ist aber kein BasePart."):format(inst:GetFullName()))
		return
	end
	local part = inst :: BasePart
	if byPart[part] then
		return
	end

	-- Stabile Id: bereits vergebene wiederverwenden, sonst eine freie neue.
	local id = part:GetAttribute("TargetId")
	if typeof(id) ~= "string" or id == "" or registry[id :: string] then
		id = nextFreeId()
		part:SetAttribute("TargetId", id)
	end

	local target = readTarget(part, id :: string)
	registry[id :: string] = target
	byPart[part] = target

	-- Live-Tuning im Studio: Attribut aendern -> sofort uebernommen.
	part.AttributeChanged:Connect(function(attribute: string)
		if attribute == "TargetId" then
			return
		end
		local current = byPart[part]
		if current then
			local refreshed = readTarget(part, current.Id)
			registry[current.Id] = refreshed
			byPart[part] = refreshed
		end
	end)
end

local function unregister(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart
	local target = byPart[part]
	if target then
		registry[target.Id] = nil
		byPart[part] = nil
	end
end

function HackTargets.Init()
	for _, inst in CollectionService:GetTagged(Config.HackableTag) do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal(Config.HackableTag):Connect(register)
	CollectionService:GetInstanceRemovedSignal(Config.HackableTag):Connect(unregister)

	print(("[GHOSTNET] HackTargets: %d Ziele registriert."):format(HackTargets.Count()))
end

function HackTargets.Count(): number
	local n = 0
	for _ in registry do
		n += 1
	end
	return n
end

function HackTargets.Get(id: string): HackTarget?
	return registry[id]
end

function HackTargets.All(): { [string]: HackTarget }
	return registry
end

--==========================================================================
-- Distanz
--==========================================================================

function HackTargets.DistanceTo(target: HackTarget, position: Vector3): number
	return Geometry.SurfaceDistance(target.Part, position)
end

-- Liefert Distanz oder nil, wenn der Spieler gerade keinen lebenden Character hat.
function HackTargets.DistanceFromPlayer(target: HackTarget, player: Player): number?
	local position = Geometry.AlivePosition(player)
	if not position then
		return nil
	end
	return Geometry.SurfaceDistance(target.Part, position)
end

--==========================================================================
-- Cooldowns (im Profil, damit ein Rejoin sie nicht loescht)
--==========================================================================

function HackTargets.CooldownLeft(player: Player, id: string): number
	local profile = SaveService.Get(player)
	if not profile then
		return 0
	end
	local until_ = profile.Cooldowns[id]
	if typeof(until_) ~= "number" then
		return 0
	end
	return math.max(0, until_ - os.time())
end

function HackTargets.SetCooldown(player: Player, id: string, seconds: number)
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	profile.Cooldowns[id] = os.time() + math.floor(seconds)
	SaveService.RequestSave(player)
end

--==========================================================================
-- "Down"-Zustand (Kamera aus, Tuer offen, ...)
-- Gilt fuer alle Spieler gleichzeitig und nur fuer diesen Serverlauf -
-- deshalb bewusst os.clock() statt os.time().
--==========================================================================

function HackTargets.IsDown(target: HackTarget): boolean
	return target.DownUntil > os.clock()
end

function HackTargets.MarkDown(target: HackTarget, seconds: number)
	target.DownUntil = os.clock() + seconds
	target.Part:SetAttribute("Offline", true)
	task.delay(seconds, function()
		if target.DownUntil <= os.clock() and target.Part.Parent then
			target.Part:SetAttribute("Offline", false)
		end
	end)
end

return HackTargets
