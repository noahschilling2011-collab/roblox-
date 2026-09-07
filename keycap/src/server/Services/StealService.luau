--!strict
-- Diebstahl und Schild.
--
-- Geklaut wird eine TASTE MITSAMT IHREM VORRAT (Abschnitt 6 der Bewertung).
-- Der Dieb bekommt nur einen Anteil, der Rest verfaellt - sonst waere ein
-- Klau bei einem Horter ein Sofortsieg.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local EconomyLogic = require(Shared.EconomyLogic)
local Remotes = require(Shared.Remotes)
local RateLimit = require(Shared.RateLimit)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local SpeedService = require(script.Parent.SpeedService)
local CarryService = require(script.Parent.CarryService)
local NpcPlotService = require(script.Parent.NpcPlotService)
local TutorialService = require(script.Parent.TutorialService)

local StealService = {}

local pairCooldown: { [string]: number } = {} -- "dieb|opfer" -> os.clock
local shieldUntil: { [number]: number } = {}
local shieldReadyAt: { [number]: number } = {}

local function notify(player: Player, text: string)
	Remotes.get("Notify"):FireClient(player, text)
end

function StealService.isShielded(userId: number): boolean
	return (shieldUntil[userId] or 0) > os.clock()
end

function StealService.shieldState(userId: number): (number, number)
	local now = os.clock()
	return math.max(0, (shieldUntil[userId] or 0) - now), math.max(0, (shieldReadyAt[userId] or 0) - now)
end

local function activateShield(player: Player)
	if not RateLimit.allow(player.UserId, "shield", EconomyConfig.REMOTE_RATE_LIMIT) then
		return
	end
	local now = os.clock()
	if (shieldReadyAt[player.UserId] or 0) > now then
		notify(player, "Schild laedt noch.")
		return
	end
	local duration, cooldown = EconomyLogic.shieldWindow()
	shieldUntil[player.UserId] = now + duration
	shieldReadyAt[player.UserId] = now + cooldown
	notify(player, ("Schild an - %ds geschuetzt."):format(duration))
end

-- Gemeinsame Vorpruefungen fuer jeden Klau. Gibt das Profil des Diebes
-- zurueck, oder nil mit dem Grund als Meldung.
local function checkThief(thief: Player, part: BasePart): any
	if not RateLimit.allow(thief.UserId, "steal", EconomyConfig.REMOTE_RATE_LIMIT) then
		return nil
	end
	local profile = DataService.get(thief)
	if not profile then
		return nil
	end
	if #profile.keys >= profile.slots then
		notify(thief, "Kein freier Steckplatz - erst einen Slot kaufen.")
		return nil
	end
	-- Distanz serverseitig pruefen, nicht dem Prompt vertrauen.
	local character = thief.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	if (root.Position - part.Position).Magnitude > 16 then
		return nil
	end
	return profile
end

local function stealFromNpc(thief: Player, part: BasePart, ref)
	local thiefProfile = checkThief(thief, part)
	if not thiefProfile then
		return
	end

	local pairId = thief.UserId .. "|npc" .. ref.plotIndex
	local now = os.clock()
	if (pairCooldown[pairId] or 0) > now then
		local left = math.ceil((pairCooldown[pairId] :: number) - now)
		notify(thief, ("An diesem Plot erst wieder in %ds."):format(left))
		return
	end

	local taken = NpcPlotService.takeKey(ref.plotIndex, ref.index)
	if not taken then
		notify(thief, "Diese Taste ist gerade leer.")
		return
	end

	table.insert(thiefProfile.keys, { rarity = taken.rarity, vorrat = taken.vorrat })
	thiefProfile.totalStolen += 1
	pairCooldown[pairId] = now + EconomyConfig.NPC_PAIR_COOLDOWN_SECONDS

	SpeedService.setCarrying(thief.UserId, EconomyConfig.CARRY_SECONDS)
	CarryService.show(thief, taken.rarity, taken.vorrat)
	PlotService.rebuildKeys(thief.UserId)
	DataService.syncLeaderstats(thief)
	TutorialService.report(thief, "steal")
	notify(thief, ("Mitgenommen: %s mit %d Vorrat."):format(taken.rarity, taken.vorrat))
end

local function stealFromPlayer(thief: Player, part: BasePart, ref)
	if ref.userId == thief.UserId then
		notify(thief, "Das ist deine eigene Taste.")
		return
	end

	local victim = Players:GetPlayerByUserId(ref.userId)
	local victimProfile = if victim then DataService.get(victim) else nil
	if not victim or not victimProfile then
		return
	end

	if StealService.isShielded(victim.UserId) then
		notify(thief, "Der Plot ist geschuetzt.")
		return
	end

	-- Abklingzeit pro Dieb-Opfer-Paar: verhindert, dass ein starker Spieler
	-- einen schwachen dauerhaft leerraeumt.
	local pairId = thief.UserId .. "|" .. victim.UserId
	local now = os.clock()
	if (pairCooldown[pairId] or 0) > now then
		local left = math.ceil((pairCooldown[pairId] :: number) - now)
		notify(thief, ("Bei diesem Spieler erst wieder in %ds."):format(left))
		return
	end

	local thiefProfile = checkThief(thief, part)
	if not thiefProfile then
		return
	end

	local key = victimProfile.keys[ref.index]
	if not key then
		return -- Liste hat sich zwischenzeitlich geaendert
	end

	local carried = EconomyLogic.stealTransfer(key.vorrat)
	local lost = math.floor(key.vorrat)
	table.remove(victimProfile.keys, ref.index)
	table.insert(thiefProfile.keys, { rarity = key.rarity, vorrat = carried })
	thiefProfile.totalStolen += 1

	pairCooldown[pairId] = now + EconomyConfig.STEAL_PAIR_COOLDOWN_SECONDS
	SpeedService.setCarrying(thief.UserId, EconomyConfig.CARRY_SECONDS)
	CarryService.show(thief, key.rarity, carried)

	PlotService.rebuildKeys(victim.UserId)
	PlotService.rebuildKeys(thief.UserId)
	DataService.syncLeaderstats(thief)

	TutorialService.report(thief, "steal")
	notify(thief, ("Geklaut: %s mit %d Vorrat."):format(key.rarity, carried))
	notify(victim, ("%s hat deine %s geklaut (%d Vorrat weg)."):format(thief.DisplayName, key.rarity, lost))

	-- Das Opfer soll nicht informiert werden, sondern wuetend: Name des
	-- Diebs gross, die verlorene Zahl darunter, rote Kante, Ruettler.
	Remotes.get("Alert"):FireClient(victim, {
		kind = "stolen",
		title = string.upper(thief.DisplayName),
		body = ("hat deine %s geklaut - %d Vorrat weg"):format(key.rarity, lost),
	})

	if EconomyConfig.ANNOUNCE_RARITIES[key.rarity] then
		Remotes.get("Announce"):FireAllClients({
			rarity = key.rarity,
			text = ("%s reisst bei %s eine %s - %d Vorrat unterwegs"):format(
				thief.DisplayName,
				victim.DisplayName,
				string.upper(key.rarity),
				carried
			),
		})
	end
end

local function attemptSteal(thief: Player, part: BasePart)
	local ref = PlotService.keyRefFromPart(part)
	if not ref then
		return
	end
	if ref.kind == "npc" then
		stealFromNpc(thief, part, ref)
	elseif ref.kind == "player" and ref.userId then
		stealFromPlayer(thief, part, ref)
	end
end

-- Anwesenheit des Besitzers verdoppelt die Klau-Dauer. ProximityPrompt hat
-- keine Einstellung pro Spieler, also wird die Dauer am Prompt selbst
-- nachgezogen.
local function refreshHoldDurations()
	-- Nur Spielerplots: an einem NPC-Plot ist nie jemand zuhause.
	for _, player in Players:GetPlayers() do
		local plot = PlotService.getPlot(player.UserId)
		if not plot then
			continue
		end
		local factor = if PlotService.isOwnerHome(player.UserId) then EconomyConfig.PRESENCE_HOLD_FACTOR else 1
		local duration = EconomyConfig.STEAL_HOLD_SECONDS * factor
		for _, part in plot.keyFolder:GetChildren() do
			local prompt = part:FindFirstChild("Steal")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.HoldDuration = duration
			end
		end
	end
end

function StealService.start()
	local plots = workspace:WaitForChild("Plots")

	local function hook(descendant: Instance)
		if not descendant:IsA("ProximityPrompt") or descendant.Name ~= "Steal" then
			return
		end
		local part = descendant.Parent
		if part and part:IsA("BasePart") then
			descendant.Triggered:Connect(function(thief)
				attemptSteal(thief, part)
			end)
		end
	end

	plots.DescendantAdded:Connect(hook)
	-- Prompts, die vor diesem Verbinden schon existierten, nachziehen:
	-- PlotService vergibt Plots asynchron und kann schneller sein.
	for _, descendant in plots:GetDescendants() do
		hook(descendant)
	end

	Remotes.get("ActivateShield").OnServerEvent:Connect(activateShield)

	Players.PlayerRemoving:Connect(function(player)
		shieldUntil[player.UserId] = nil
		shieldReadyAt[player.UserId] = nil
		RateLimit.forget(player.UserId)
		SpeedService.clearCarrying(player.UserId)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator >= 1 then
			accumulator = 0
			refreshHoldDurations()
		end
	end)

	print("[KEYCAP] StealService laeuft")
end

return StealService
