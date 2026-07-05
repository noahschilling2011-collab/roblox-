--!strict
-- GlobalEventService: serverweite Live-Events (Meteoritenschauer, Goldener Regen, ...).
-- Ein Scheduler würfelt gemäß GameConfig regelmäßig, ob ein Event startet.
-- Aktive Events liefern Energie- und Loot-Glück-Multiplikatoren für andere Services.
--
-- Cross-Server-Synchronisation läuft über MessagingService (Topic PF_GLOBAL_EVENT):
-- Der startende Server publiziert das Event, alle anderen übernehmen es.
-- HINWEIS FÜR PRODUKTION: Für echte Eindeutigkeit (genau EIN Server startet Events)
-- braucht es eine MemoryStore-basierte Wahl eines Leader-Servers.
-- Hier bewusst einfach gehalten: identische startedAt-Werte werden nicht doppelt
-- übernommen, seltene Kollisionen zweier Server sind für dieses Skelett akzeptabel.

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local WeightedRandom = require(ReplicatedStorage.Shared.Util.WeightedRandom)

local MESSAGING_TOPIC = "PF_GLOBAL_EVENT"

local rng = Random.new()

-- Aktuell laufendes Event (nil = keines aktiv).
local activeEvent: Types.ActiveGlobalEvent? = nil
-- 0 bedeutet: noch nie ein Event gelaufen -> der Mindestabstand ist sofort erfüllt.
local lastEventEndedAt = 0

-- Gewichtete Auswahl-Liste einmalig aus der Konfiguration aufbauen.
local weightedEvents: { WeightedRandom.WeightedEntry<EventConfig.GlobalEventDef> } = {}
for _, def in EventConfig.Events do
	table.insert(weightedEvents, { value = def, weight = def.weight })
end

local GlobalEventService = {}

-- Beendet das übergebene Event, falls es noch das aktive ist.
-- Der Identitätsvergleich verhindert Doppel-Enden (task.delay UND Watchdog).
local function endEvent(expected: Types.ActiveGlobalEvent)
	if activeEvent ~= expected then
		return
	end
	activeEvent = nil
	lastEventEndedAt = os.time()

	Remotes.getEvent("GlobalEventEnded"):FireAllClients(expected.eventId)

	local def = EventConfig.Events[expected.eventId]
	if def ~= nil then
		Remotes.getEvent("Notification"):FireAllClients(`{def.displayName} ist vorbei.`, "info")
	end
end

-- Setzt ein Event als aktiv, informiert alle Clients und plant das Ende.
-- publish = true nur beim lokal gestarteten Event (nicht beim Übernehmen von anderen Servern).
local function startEvent(def: EventConfig.GlobalEventDef, startedAt: number, endsAt: number, publish: boolean)
	local newEvent: Types.ActiveGlobalEvent = {
		eventId = def.id,
		startedAt = startedAt,
		endsAt = endsAt,
	}
	activeEvent = newEvent

	Remotes.getEvent("GlobalEventStarted"):FireAllClients(def.id, endsAt)
	Remotes.getEvent("Notification"):FireAllClients(def.announceText, "info")

	-- Ende präzise planen; der Watchdog im Scheduler fängt verpasste Enden ab.
	task.delay(math.max(endsAt - os.time(), 0), function()
		endEvent(newEvent)
	end)

	if publish then
		local ok, err = pcall(function()
			MessagingService:PublishAsync(MESSAGING_TOPIC, {
				eventId = def.id,
				startedAt = startedAt,
				endsAt = endsAt,
			})
		end)
		if not ok then
			warn(`[PlanetForge] Event-Broadcast fehlgeschlagen: {err}`)
		end
	end
end

-- Nachricht eines anderen Servers (oder das Echo der eigenen) verarbeiten.
local function onCrossServerMessage(message: { Data: any })
	local data = message.Data
	if typeof(data) ~= "table" then
		return
	end

	local eventId = data.eventId
	local startedAt = data.startedAt
	local endsAt = data.endsAt
	if typeof(eventId) ~= "string" or typeof(startedAt) ~= "number" or typeof(endsAt) ~= "number" then
		return
	end

	local def = EventConfig.Events[eventId]
	if def == nil or endsAt <= os.time() then
		return
	end

	local current = activeEvent
	if current ~= nil then
		-- Dasselbe Event läuft bereits (u. a. das Echo der eigenen Publish-Nachricht):
		-- identische startedAt-Werte nicht doppelt übernehmen. Läuft lokal ein
		-- anderes Event, wird es bewusst nicht unterbrochen.
		return
	end

	startEvent(def, startedAt, endsAt, false)
end

-- Scheduler-Tick: Watchdog für das laufende Event bzw. Startwurf für ein neues.
local function schedulerTick()
	local current = activeEvent
	if current ~= nil then
		-- Watchdog: falls task.delay das Ende verpasst hat (endsAt erreicht).
		if os.time() >= current.endsAt then
			endEvent(current)
		end
		return
	end

	if os.time() - lastEventEndedAt < GameConfig.EVENT_MIN_GAP_SECONDS then
		return
	end
	if rng:NextNumber() >= GameConfig.EVENT_START_CHANCE then
		return
	end

	local def = WeightedRandom.pick(weightedEvents, rng)
	local startedAt = os.time()
	startEvent(def, startedAt, startedAt + def.durationSeconds, true)
end

function GlobalEventService.init()
	-- Cross-Server-Nachrichten abonnieren (SubscribeAsync yieldet -> task.spawn).
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(MESSAGING_TOPIC, onCrossServerMessage)
		end)
		if not ok then
			warn(`[PlanetForge] Event-Subscribe fehlgeschlagen: {err}`)
		end
	end)

	-- Später beitretende Spieler bekommen ein laufendes Event direkt gemeldet.
	Players.PlayerAdded:Connect(function(player)
		local current = activeEvent
		if current ~= nil and os.time() < current.endsAt then
			Remotes.getEvent("GlobalEventStarted"):FireClient(player, current.eventId, current.endsAt)
			local def = EventConfig.Events[current.eventId]
			if def ~= nil then
				Remotes.getEvent("Notification"):FireClient(player, def.announceText, "info")
			end
		end
	end)

	-- Endlosschleife des Schedulers gehört nicht in init selbst -> task.spawn.
	task.spawn(function()
		while true do
			task.wait(GameConfig.EVENT_CHECK_INTERVAL_SECONDS)
			schedulerTick()
		end
	end)
end

-- Das aktuell laufende Event oder nil.
function GlobalEventService.getActiveEvent(): Types.ActiveGlobalEvent?
	return activeEvent
end

-- Energie-Multiplikator des aktiven Events, sonst 1.
function GlobalEventService.getEnergyMultiplier(): number
	local current = activeEvent
	if current == nil then
		return 1
	end
	local def = EventConfig.Events[current.eventId]
	if def == nil then
		return 1
	end
	return def.energyMultiplier
end

-- Loot-Glück-Multiplikator des aktiven Events, sonst 1.
function GlobalEventService.getLootLuckMultiplier(): number
	local current = activeEvent
	if current == nil then
		return 1
	end
	local def = EventConfig.Events[current.eventId]
	if def == nil then
		return 1
	end
	return def.lootLuckMultiplier
end

return GlobalEventService
