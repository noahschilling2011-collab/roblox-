-- ServerScriptService/Systems/MissionService.luau
--!strict
-- GHOSTNET :: Das Missions-Rueckgrat.
--
-- WAS ER TUT
--   Haelt pro Spieler die aktive Mission und den Schritt-Index IM PROFIL,
--   prueft serverseitig, ob ein Schritt erfuellt ist, und schaltet beim
--   Abschluss dauerhafte Unlocks frei.
--
-- WAS ER NICHT TUT
--   Er kennt keine einzelne Mission. Missionsinhalte stehen als Daten in
--   Shared/Missions.luau; die Regeln dazu sind dort pur und ohne Roblox
--   pruefbar. Dieses Modul ist nur die Mechanik drumherum.
--
-- SERVER-AUTORITAET
--   Der Client meldet NIE "Schritt fertig". Er darf genau drei Dinge sagen:
--   "ich nehme Mission X an", "ich breche ab", "ich spreche Kontakt Y an".
--   Alles andere leitet der Server aus dem ab, was ohnehin schon passiert:
--   geloeste Hacks, Verkaeufe, Distanz zu Wegpunkten, Ablauf von Wartezeiten.
--
-- KEIN REQUIRE-KREIS
--   HackService und SellService kennen den MissionService nicht. Er meldet
--   sich bei ihnen per OnHackResolved / OnSell an - dasselbe Muster, das
--   TraceService.OnBust bereits vormacht.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Geometry = require(ReplicatedStorage.Shared.Geometry)
local Missions = require(ReplicatedStorage.Shared.Missions)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local EconomyService = require(script.Parent.EconomyService)
local HackService = require(script.Parent.HackService)
local HackTargets = require(script.Parent.HackTargets)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local SellService = require(script.Parent.SellService)

type Mission = Missions.Mission
type Step = Missions.Step
type Story = Types.Story

local MissionService = {}

-- Damit der Marker nicht jeden Takt neu geschickt wird.
local lastMarker: { [Player]: string } = {}

-- Wer mitbekommen will, dass eine Mission fertig ist (Phase B fuer das
-- Tutorial, Phase C fuer Darknet-Freischaltungen).
local completeCallbacks: { (Player, Mission) -> () } = {}

function MissionService.OnMissionComplete(callback: (Player, Mission) -> ())
	table.insert(completeCallbacks, callback)
end

--==========================================================================
-- Zugriff aufs Profil
--==========================================================================

local function storyOf(player: Player): Story?
	local profile = SaveService.Get(player)
	return if profile then profile.Story else nil
end

local function activeMission(story: Story): Mission?
	if story.Active == "" then
		return nil
	end
	return Missions.Get(story.Active)
end

local function currentStep(mission: Mission, story: Story): Step?
	return mission.Steps[story.Step]
end

-- Fuer Phase B und C: "darf der Spieler Ladenueberfaelle / das Darknet?"
function MissionService.HasUnlock(player: Player, key: string): boolean
	local story = storyOf(player)
	if not story then
		return false
	end
	return Missions.HasUnlock(story, key)
end

function MissionService.IsCompleted(player: Player, missionId: string): boolean
	local story = storyOf(player)
	if not story then
		return false
	end
	return Missions.IsCompleted(story, missionId)
end

--==========================================================================
-- Weltobjekte zu einem Schritt finden
--==========================================================================

local function taggedPartWithAttribute(tag: string, attribute: string, value: string): BasePart?
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(workspace) and inst:GetAttribute(attribute) == value then
			return inst
		end
	end
	return nil
end

function MissionService.FindWaypoint(id: string): BasePart?
	return taggedPartWithAttribute(Config.WaypointTag, "WaypointId", id)
end

function MissionService.FindContact(id: string): BasePart?
	return taggedPartWithAttribute(Config.ContactTag, "ContactId", id)
end

-- Wohin der Marker im HUD zeigen soll. nil = kein Marker fuer diesen Schritt.
local function markerFor(player: Player, step: Step): (Vector3?, string)
	if step.Type == "GOTO" and step.Target then
		local part = MissionService.FindWaypoint(step.Target)
		return (if part then part.Position else nil), step.Text
	elseif step.Type == "HACK" and step.TargetId then
		local target = HackTargets.Get(step.TargetId)
		return (if target and target.Part.Parent then target.Part.Position else nil), step.Text
	elseif step.Type == "TALK" and step.ContactId then
		local part = MissionService.FindContact(step.ContactId)
		return (if part then part.Position else nil), step.Text
	elseif step.Type == "SELL" then
		local fence = SellService.NearestFence(player)
		return (if fence then fence.Position else nil), step.Text
	end
	return nil, step.Text
end

--==========================================================================
-- An den Client schicken
--==========================================================================

local function syncWaypoint(player: Player, step: Step?)
	if not player.Parent then
		return
	end

	local position: Vector3? = nil
	local label = ""
	if step then
		position, label = markerFor(player, step)
	end

	-- Nur bei echter Aenderung senden, sonst laeuft der Takt als Paketflut.
	local key = if position then ("%d|%d|%d|%s"):format(position.X, position.Y, position.Z, label) else ""
	if lastMarker[player] == key then
		return
	end
	lastMarker[player] = key

	Remotes.WaypointSync:FireClient(player, {
		Position = position,
		Label = label,
	})
end

function MissionService.Sync(player: Player)
	if not player.Parent then
		return
	end
	local story = storyOf(player)
	if not story then
		return
	end

	local mission = activeMission(story)
	if not mission then
		local available = Missions.FirstAvailable(story)
		Remotes.MissionSync:FireClient(player, {
			Active = "",
			Completed = table.clone(story.Completed),
			Unlocks = table.clone(story.Unlocks),
			Available = if available then available.Id else "",
			AvailableTitle = if available then available.Title else "",
		})
		syncWaypoint(player, nil)
		return
	end

	local step = currentStep(mission, story)
	local texts: { string } = {}
	for _, entry in mission.Steps do
		table.insert(texts, entry.Text)
	end

	Remotes.MissionSync:FireClient(player, {
		Active = mission.Id,
		Title = mission.Title,
		Briefing = mission.Briefing,
		StepIndex = story.Step,
		StepCount = #mission.Steps,
		StepText = if step then step.Text else "",
		StepType = if step then step.Type else "",
		StepProgress = story.StepProgress,
		StepRequired = if step then Missions.Required(step) else 1,
		StepSeconds = if step and step.Type == "WAIT" then step.Seconds else nil,
		StepStartedAt = story.StepStartedAt,
		ContactId = if step then step.ContactId else nil,
		Steps = texts,
		Completed = table.clone(story.Completed),
		Unlocks = table.clone(story.Unlocks),
	})

	syncWaypoint(player, step)
end

--==========================================================================
-- Missionen starten und abschliessen
--==========================================================================

local startMission: (Player, Story, string) -> boolean

local function completeMission(player: Player, story: Story, mission: Mission)
	if not Missions.IsCompleted(story, mission.Id) then
		table.insert(story.Completed, mission.Id)
	end
	story.Active = ""
	story.Step = 1
	story.StepProgress = 0
	story.StepStartedAt = 0

	local reward = mission.Reward
	if typeof(reward) == "table" then
		local crypto = reward.Crypto
		if typeof(crypto) == "number" and crypto > 0 then
			-- Standard: die Belohnung ist heiss und muss erst zum Hehler.
			-- Das haelt den Verkaufs-Loop auch bei Story-Geld relevant.
			if Config.Mission.RewardToBank then
				EconomyService.AwardBanked(player, crypto)
			else
				EconomyService.AwardUnsold(player, crypto)
			end
		end
		local unlock = reward.Unlock
		if typeof(unlock) == "string" and unlock ~= "" and not Missions.HasUnlock(story, unlock) then
			table.insert(story.Unlocks, unlock)
		end
	end

	print(("[GHOSTNET] %s hat Mission '%s' abgeschlossen."):format(player.Name, mission.Id))
	SaveService.RequestSave(player)

	for _, callback in completeCallbacks do
		task.spawn(function()
			local ok, err = pcall(callback, player, mission)
			if not ok then
				warn(("[GHOSTNET] OnMissionComplete-Callback fehlgeschlagen: %s"):format(tostring(err)))
			end
		end)
	end

	-- Direkt die naechste anbieten, damit die Story nicht stehen bleibt.
	if Config.Mission.AutoStart then
		local next_ = Missions.FirstAvailable(story)
		if next_ then
			startMission(player, story, next_.Id)
			return
		end
	end

	MissionService.Sync(player)
end

startMission = function(player: Player, story: Story, missionId: string): boolean
	if not Missions.IsAvailable(story, missionId) then
		return false
	end
	story.Active = missionId
	story.Step = 1
	story.StepProgress = 0
	story.StepStartedAt = os.time()
	lastMarker[player] = nil
	SaveService.RequestSave(player)
	MissionService.Sync(player)
	return true
end

local function advance(player: Player, story: Story, mission: Mission)
	story.Step += 1
	story.StepProgress = 0
	story.StepStartedAt = os.time()
	lastMarker[player] = nil

	if story.Step > #mission.Steps then
		completeMission(player, story, mission)
	else
		SaveService.RequestSave(player)
		MissionService.Sync(player)
	end
end

--==========================================================================
-- Ereignisse verarbeiten
-- Der einzige Weg, wie ein Schritt vorankommt. Ob ein Ereignis passt,
-- entscheidet Missions.Progress - pur und im Testlauf abgedeckt.
--==========================================================================

local function applyEvent(player: Player, event: { [string]: any })
	local story = storyOf(player)
	if not story then
		return
	end
	local mission = activeMission(story)
	if not mission then
		return
	end
	local step = currentStep(mission, story)
	if not step then
		-- Kaputter Index (z.B. Mission nachtraeglich gekuerzt): sauber beenden,
		-- statt den Spieler in einer toten Mission haengen zu lassen.
		completeMission(player, story, mission)
		return
	end

	local gain = Missions.Progress(step, event)
	if gain <= 0 then
		return
	end

	story.StepProgress += gain
	if story.StepProgress >= Missions.Required(step) then
		advance(player, story, mission)
	else
		SaveService.RequestSave(player)
		MissionService.Sync(player)
	end
end

-- Oeffentlicher Haken fuer Phase C: der InventoryService meldet Kaeufe hier,
-- statt dass dieses Modul ihn requiret.
function MissionService.NotifyBuy(player: Player, goodId: string, amount: number)
	if typeof(goodId) ~= "string" or typeof(amount) ~= "number" or amount <= 0 then
		return
	end
	applyEvent(player, { Type = "BUY", GoodId = goodId, Amount = math.floor(amount) })
end

--==========================================================================
-- Remote-Handler
--==========================================================================

local function onAccept(player: Player, payload: any)
	if not RateLimiter.Check(player, "MissionAccept") then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local missionId = (payload :: any).MissionId
	if typeof(missionId) ~= "string" or missionId == "" or #missionId > 48 then
		return
	end

	local story = storyOf(player)
	if not story then
		return
	end
	if story.Active ~= "" then
		MissionService.Sync(player) -- laeuft schon eine; Client neu ausrichten
		return
	end

	if not startMission(player, story, missionId) then
		MissionService.Sync(player)
	end
end

local function onAbandon(player: Player, payload: any)
	if not RateLimiter.Check(player, "MissionAbandon") then
		return
	end
	if payload ~= nil and typeof(payload) ~= "table" then
		return
	end
	local story = storyOf(player)
	if not story or story.Active == "" then
		return
	end

	story.Active = ""
	story.Step = 1
	story.StepProgress = 0
	story.StepStartedAt = 0
	lastMarker[player] = nil
	SaveService.RequestSave(player)
	MissionService.Sync(player)
end

local function onInteract(player: Player, payload: any)
	if not RateLimiter.Check(player, "MissionInteract") then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local contactId = (payload :: any).ContactId
	if typeof(contactId) ~= "string" or contactId == "" or #contactId > 48 then
		return
	end

	local part = MissionService.FindContact(contactId)
	if not part then
		return
	end

	-- Distanz serverseitig, wie ueberall sonst auch.
	local position = Geometry.AlivePosition(player)
	if not position then
		return
	end
	local distance = Geometry.SurfaceDistance(part, position)
	if distance > Config.Mission.ContactRange + Config.Mission.ContactTolerance then
		return
	end

	applyEvent(player, { Type = "TALK", ContactId = contactId })
end

--==========================================================================
-- Takt: GOTO-Distanz und WAIT-Timer
-- Beides kann der Client nicht melden, also schaut der Server selbst nach.
--==========================================================================

local function tick()
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Config.Mission.TickSeconds then
			return
		end
		accumulator = 0

		for _, player in Players:GetPlayers() do
			local story = storyOf(player)
			if not story then
				continue
			end
			local mission = activeMission(story)
			if not mission then
				continue
			end
			local step = currentStep(mission, story)
			if not step then
				continue
			end

			if step.Type == "WAIT" then
				local seconds = step.Seconds or 0
				if story.StepStartedAt > 0 and os.time() - story.StepStartedAt >= seconds then
					applyEvent(player, { Type = "WAIT" })
				end
			elseif step.Type == "GOTO" and step.Target then
				local part = MissionService.FindWaypoint(step.Target)
				local position = Geometry.AlivePosition(player)
				if part and position then
					local distance = Geometry.SurfaceDistance(part, position)
					if distance <= Config.Mission.WaypointRange + Config.Mission.WaypointTolerance then
						applyEvent(player, { Type = "GOTO", WaypointId = step.Target })
					end
				end
			end

			-- Der Marker kann sich bewegen (Hehler in der Naehe, Ziel-Part neu
			-- registriert), deshalb bei jedem Takt nachziehen. syncWaypoint
			-- sendet nur, wenn sich wirklich etwas geaendert hat.
			syncWaypoint(player, step)
		end
	end)
end

--==========================================================================

function MissionService.Init()
	-- Datenfehler sollen beim Hochfahren auffallen, nicht wenn ein Spieler
	-- in einer kaputten Mission feststeckt.
	local valid, errors = Missions.Validate(nil, Config.Mission.MaxSteps)
	if not valid then
		for _, message in errors do
			warn(("[GHOSTNET] Missionsdaten: %s"):format(message))
		end
	end

	HackService.OnHackResolved(function(player, data)
		applyEvent(player, {
			Type = "HACK",
			TargetId = data.TargetId,
			Success = data.Success,
		})
	end)

	SellService.OnSell(function(player, data)
		applyEvent(player, { Type = "SELL", Net = data.Net })
	end)

	Remotes.MissionAccept.OnServerEvent:Connect(onAccept)
	Remotes.MissionAbandon.OnServerEvent:Connect(onAbandon)
	Remotes.MissionInteract.OnServerEvent:Connect(onInteract)

	SaveService.OnReady(function(player, profile)
		lastMarker[player] = nil
		local story = profile.Story

		-- Aktive Mission zeigt auf etwas, das es nicht mehr gibt (Mission
		-- umbenannt oder entfernt): stillschweigend loesen statt crashen.
		if story.Active ~= "" and not Missions.Get(story.Active) then
			warn(("[GHOSTNET] %s hatte die unbekannte Mission '%s' aktiv - zurueckgesetzt."):format(
				player.Name,
				story.Active
			))
			story.Active = ""
			story.Step = 1
			story.StepProgress = 0
		end

		if Config.Mission.AutoStart and story.Active == "" then
			local next_ = Missions.FirstAvailable(story)
			if next_ then
				startMission(player, story, next_.Id)
				return
			end
		end

		MissionService.Sync(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastMarker[player] = nil
	end)

	tick()

	print(("[GHOSTNET] MissionService bereit. %d Missionen registriert%s."):format(
		Missions.Count(),
		if valid then "" else " (mit Datenfehlern, siehe oben)"
	))
end

return MissionService
