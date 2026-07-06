--!strict
-- TradeService: sicheres 1:1-Handelssystem als Zustandsmaschine (Types.TradeSession).
--
-- Ablauf: invite -> acceptInvite -> (setOffer / toggleAccept)* -> locked -> completed.
--
-- DUPE-SCHUTZ:
--  * Während state == "locked" sind setOffer und erneutes toggleAccept verboten -
--    die Angebote können sich in der Sicherheitspause also nicht mehr ändern.
--  * Die Ausführung läuft in einem einzigen Thread OHNE Yields zwischen der
--    finalen Re-Validierung (Besitz, Energie, Online-Status) und dem Transfer.
--    Es kann daher kein anderer Code dazwischen Items entfernen oder Energie ausgeben.
--  * Schlägt irgendein Teil der Re-Validierung fehl, wird die Session komplett
--    abgebrochen - es gibt keine Teilausführung.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CollectibleConfig = require(ReplicatedStorage.Shared.Config.CollectibleConfig)

local DataService = require(script.Parent.DataService)
local EnergyService = require(script.Parent.EnergyService)
local PlanetService = require(script.Parent.PlanetService)
local EquipService = require(script.Parent.EquipService)

local TradeService = {}

-- Offene Einladungen: Ziel-UserId -> UserId des Einladenden.
-- Eine neue Einladung an dasselbe Ziel ersetzt die alte.
local pendingInvites: { [number]: number } = {}

-- Aktive Sessions: UserId -> TradeSession. Beide Seiten zeigen auf DIESELBE Session.
local sessions: { [number]: Types.TradeSession } = {}

local tradeUpdatedEvent: RemoteEvent? = nil
local notificationEvent: RemoteEvent? = nil

-- Beide Events werden in init() aufgelöst, bevor irgendein Handler laufen kann.
local function fireTradeUpdated(player: Player, snapshot: any)
	local event = assert(tradeUpdatedEvent, "TradeService.init() fehlt")
	event:FireClient(player, snapshot)
end

local function notify(player: Player, message: string, kind: string)
	local event = assert(notificationEvent, "TradeService.init() fehlt")
	event:FireClient(player, message, kind)
end

-- Sucht die Seite eines Spielers innerhalb einer Session.
local function findSide(session: Types.TradeSession, userId: number): Types.TradeSide?
	for _, side in session.sides do
		if side.userId == userId then
			return side
		end
	end
	return nil
end

-- Sucht ein Sammelobjekt per uid im Profil.
local function findOwned(profile: Types.PlayerProfile, uid: string): Types.OwnedCollectible?
	for _, owned in profile.collectibles do
		if owned.uid == uid then
			return owned
		end
	end
	return nil
end

-- Ansicht einer Seite fürs UI; liefert zu jeder uid zusätzlich die collectibleId,
-- damit der Client Namen anzeigen kann.
local function buildSideView(side: Types.TradeSide): { [string]: any }
	local owner = Players:GetPlayerByUserId(side.userId)
	local profile = if owner ~= nil then DataService.getProfile(owner) else nil
	local items = {}
	for _, uid in side.offeredUids do
		local owned = if profile ~= nil then findOwned(profile, uid) else nil
		table.insert(items, {
			uid = uid,
			collectibleId = if owned ~= nil then owned.collectibleId else "",
		})
	end
	return {
		offeredUids = table.clone(side.offeredUids),
		offeredItems = items,
		offeredEnergy = side.offeredEnergy,
		accepted = side.accepted,
	}
end

-- Baut den TradeUpdated-Snapshot aus Sicht eines Spielers.
local function buildSnapshotFor(session: Types.TradeSession, viewerUserId: number): any
	local youSide: Types.TradeSide? = nil
	local partnerSide: Types.TradeSide? = nil
	for _, side in session.sides do
		if side.userId == viewerUserId then
			youSide = side
		else
			partnerSide = side
		end
	end
	if youSide == nil or partnerSide == nil then
		return nil
	end

	local partnerPlayer = Players:GetPlayerByUserId(partnerSide.userId)
	local partnerView = buildSideView(partnerSide)
	partnerView.userId = partnerSide.userId
	partnerView.name = if partnerPlayer ~= nil then partnerPlayer.Name else "Unbekannt"
	return {
		id = session.id,
		state = session.state,
		you = buildSideView(youSide),
		partner = partnerView,
	}
end

-- Schickt beiden Teilnehmern den aktuellen Session-Stand.
local function sendSessionUpdate(session: Types.TradeSession)
	for _, side in session.sides do
		local player = Players:GetPlayerByUserId(side.userId)
		if player ~= nil then
			fireTradeUpdated(player, buildSnapshotFor(session, side.userId))
		end
	end
end

-- Bricht eine Session ab, räumt die Einträge auf und informiert beide Seiten.
local function cancelSession(session: Types.TradeSession, message: string?, kind: string?)
	if session.state == "completed" or session.state == "cancelled" then
		return
	end
	session.state = "cancelled"
	for _, side in session.sides do
		if sessions[side.userId] == session then
			sessions[side.userId] = nil
		end
		local player = Players:GetPlayerByUserId(side.userId)
		if player ~= nil then
			fireTradeUpdated(player, nil)
			if message ~= nil then
				notify(player, message, kind or "info")
			end
		end
	end
end

-- Validiert die rohe Client-Eingabe eines Angebots.
-- Rückgabe: (Fehlermeldung) ODER (nil, uids, energy).
local function validateOffer(player: Player, payload: any): (string?, { string }?, number?)
	if typeof(payload) ~= "table" then
		return "Ungültige Anfrage."
	end
	local rawUids = payload.uids
	local rawEnergy = payload.energy
	if typeof(rawUids) ~= "table" or typeof(rawEnergy) ~= "number" then
		return "Ungültige Anfrage."
	end

	local profile = DataService.getProfile(player)
	if profile == nil then
		return "Dein Spielstand wird noch geladen."
	end

	-- uids: echtes Array aus Strings, ohne Duplikate, begrenzte Länge.
	local uids: { string } = {}
	local seen: { [string]: boolean } = {}
	local count = 0
	for key, value in rawUids :: { [any]: any } do
		count += 1
		if count > GameConfig.MAX_TRADE_ITEMS_PER_SIDE then
			return `Maximal {GameConfig.MAX_TRADE_ITEMS_PER_SIDE} Objekte pro Seite.`
		end
		if typeof(key) ~= "number" or key ~= count or typeof(value) ~= "string" then
			return "Ungültige Objektliste."
		end
		if seen[value] then
			return "Doppelte Objekte im Angebot."
		end
		seen[value] = true
		table.insert(uids, value)
	end

	-- Besitz und Handelbarkeit jedes Objekts prüfen.
	for _, uid in uids do
		local owned = findOwned(profile, uid)
		if owned == nil then
			return "Du besitzt eines der angebotenen Objekte nicht."
		end
		local def = CollectibleConfig.Collectibles[owned.collectibleId]
		if def == nil or not def.tradable then
			return "Eines der angebotenen Objekte ist nicht handelbar."
		end
	end

	-- Energie: nicht-negative, endliche Ganzzahl innerhalb des Guthabens.
	if rawEnergy ~= rawEnergy or rawEnergy == math.huge or rawEnergy < 0 or rawEnergy ~= math.floor(rawEnergy) then
		return "Ungültiger Energiebetrag."
	end
	if rawEnergy > EnergyService.getEnergy(player) then
		return "So viel Energie hast du nicht."
	end

	return nil, uids, rawEnergy
end

-- Finale Prüfung einer Seite direkt vor dem Transfer (ohne Yields).
local function validateSideForExecution(profile: Types.PlayerProfile, side: Types.TradeSide): boolean
	if #side.offeredUids > GameConfig.MAX_TRADE_ITEMS_PER_SIDE then
		return false
	end
	for _, uid in side.offeredUids do
		local owned = findOwned(profile, uid)
		if owned == nil then
			return false
		end
		local def = CollectibleConfig.Collectibles[owned.collectibleId]
		if def == nil or not def.tradable then
			return false
		end
	end
	return side.offeredEnergy >= 0 and profile.energy >= side.offeredEnergy
end

-- Bewegt Sammelobjekte per uid von einem Profil ins andere (uid bleibt erhalten).
local function moveCollectibles(fromProfile: Types.PlayerProfile, toProfile: Types.PlayerProfile, uids: { string })
	local now = os.time()
	for _, uid in uids do
		for index, owned in fromProfile.collectibles do
			if owned.uid == uid then
				table.remove(fromProfile.collectibles, index)
				owned.source = "trade"
				owned.obtainedAt = now
				table.insert(toProfile.collectibles, owned)
				break
			end
		end
	end
end

local EXEC_FAILED_MESSAGE = "Der Handel konnte nicht ausgeführt werden und wurde abgebrochen."

-- Führt eine gesperrte Session atomar aus. Läuft nach TRADE_LOCK_SECONDS via task.delay.
local function executeTrade(session: Types.TradeSession)
	-- Wurde die Session inzwischen gecancelt oder ersetzt? Dann nichts tun.
	if session.state ~= "locked" then
		return
	end
	local sideA = session.sides[1]
	local sideB = session.sides[2]
	if sessions[sideA.userId] ~= session or sessions[sideB.userId] ~= session then
		return
	end

	local playerA = Players:GetPlayerByUserId(sideA.userId)
	local playerB = Players:GetPlayerByUserId(sideB.userId)
	local profileA = if playerA ~= nil then DataService.getProfile(playerA) else nil
	local profileB = if playerB ~= nil then DataService.getProfile(playerB) else nil
	if playerA == nil or playerB == nil or profileA == nil or profileB == nil then
		cancelSession(session, "Der Handel wurde abgebrochen, weil ein Spieler nicht mehr verfügbar ist.", "error")
		return
	end

	-- Ab hier KEINE Yields mehr bis zum Abschluss (siehe Dupe-Schutz im Kopfkommentar).
	if not validateSideForExecution(profileA, sideA) or not validateSideForExecution(profileB, sideB) then
		cancelSession(session, EXEC_FAILED_MESSAGE, "error")
		return
	end

	-- Energie zuerst abbuchen; trySpend prüft das Guthaben ein weiteres Mal.
	local spentA = sideA.offeredEnergy == 0 or EnergyService.trySpend(playerA, sideA.offeredEnergy)
	local spentB = spentA and (sideB.offeredEnergy == 0 or EnergyService.trySpend(playerB, sideB.offeredEnergy))
	if not (spentA and spentB) then
		if spentA then
			-- Bereits abgebuchte Energie von Seite A erstatten - keine Teilausführung.
			EnergyService.addRaw(playerA, sideA.offeredEnergy)
		end
		cancelSession(session, EXEC_FAILED_MESSAGE, "error")
		return
	end
	-- Gutschriften (addRaw ignoriert Beträge <= 0 selbst).
	EnergyService.addRaw(playerB, sideA.offeredEnergy)
	EnergyService.addRaw(playerA, sideB.offeredEnergy)

	-- Sammelobjekte in beide Richtungen bewegen (Besitz wurde oben final geprüft).
	moveCollectibles(profileA, profileB, sideA.offeredUids)
	moveCollectibles(profileB, profileA, sideB.offeredUids)

	session.state = "completed"
	sessions[sideA.userId] = nil
	sessions[sideB.userId] = nil
	DataService.markDirty(playerA)
	DataService.markDirty(playerB)

	for _, player in { playerA, playerB } do
		fireTradeUpdated(player, nil)
		notify(player, "Handel erfolgreich abgeschlossen!", "success")
		PlanetService.sendSnapshot(player)
		-- Weggehandelte Items dürfen nicht ausgerüstet bleiben.
		EquipService.validateEquipment(player)
	end
end

local function handleInvite(player: Player, payload: any): (boolean, any?)
	if typeof(payload) ~= "table" then
		return false, "Ungültige Anfrage."
	end
	local targetUserId = payload.targetUserId
	if typeof(targetUserId) ~= "number" or targetUserId ~= math.floor(targetUserId) or targetUserId < 1 or targetUserId == math.huge then
		return false, "Ungültige Spieler-ID."
	end
	if targetUserId == player.UserId then
		return false, "Du kannst nicht mit dir selbst handeln."
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if target == nil then
		return false, "Dieser Spieler ist nicht auf dem Server."
	end
	if sessions[player.UserId] ~= nil then
		return false, "Du bist bereits in einem Handel."
	end
	if sessions[targetUserId] ~= nil then
		return false, "Dieser Spieler ist bereits in einem Handel."
	end

	-- Ersetzt eine eventuell ältere Einladung an dasselbe Ziel.
	pendingInvites[targetUserId] = player.UserId
	notify(target, `{player.Name} möchte mit dir handeln - öffne das Handelsmenü.`, "info")
	return true, nil
end

local function handleAcceptInvite(player: Player, payload: any): (boolean, any?)
	if typeof(payload) ~= "table" or typeof(payload.fromUserId) ~= "number" then
		return false, "Ungültige Anfrage."
	end
	local fromUserId = payload.fromUserId
	if pendingInvites[player.UserId] ~= fromUserId then
		return false, "Diese Einladung existiert nicht (mehr)."
	end
	local fromPlayer = Players:GetPlayerByUserId(fromUserId)
	if fromPlayer == nil then
		pendingInvites[player.UserId] = nil
		return false, "Der Einladende ist nicht mehr online."
	end
	if sessions[fromUserId] ~= nil then
		return false, "Der Einladende ist bereits in einem Handel."
	end
	if sessions[player.UserId] ~= nil then
		return false, "Du bist bereits in einem Handel."
	end
	if DataService.getProfile(player) == nil or DataService.getProfile(fromPlayer) == nil then
		return false, "Ein Spielstand wird noch geladen."
	end

	pendingInvites[player.UserId] = nil
	local session: Types.TradeSession = {
		id = HttpService:GenerateGUID(false),
		sides = {
			{ userId = fromUserId, offeredUids = {}, offeredEnergy = 0, accepted = false },
			{ userId = player.UserId, offeredUids = {}, offeredEnergy = 0, accepted = false },
		},
		state = "negotiating",
		createdAt = os.time(),
	}
	sessions[fromUserId] = session
	sessions[player.UserId] = session
	sendSessionUpdate(session)
	return true, nil
end

local function handleSetOffer(player: Player, payload: any): (boolean, any?)
	local session = sessions[player.UserId]
	if session == nil then
		return false, "Du bist in keinem Handel."
	end
	if session.state ~= "negotiating" then
		return false, "Das Angebot ist bereits gesperrt."
	end
	local errorMessage, uids, energy = validateOffer(player, payload)
	if errorMessage ~= nil or uids == nil or energy == nil then
		return false, errorMessage or "Ungültige Anfrage."
	end
	local mySide = findSide(session, player.UserId)
	if mySide == nil then
		return false, "Interner Fehler in der Handelssitzung."
	end

	mySide.offeredUids = uids
	mySide.offeredEnergy = energy
	-- Jede Angebotsänderung setzt die Zustimmung BEIDER Seiten zurück.
	for _, side in session.sides do
		side.accepted = false
	end
	sendSessionUpdate(session)
	return true, nil
end

local function handleToggleAccept(player: Player): (boolean, any?)
	local session = sessions[player.UserId]
	if session == nil then
		return false, "Du bist in keinem Handel."
	end
	if session.state ~= "negotiating" then
		return false, "Das Angebot ist bereits gesperrt."
	end
	local mySide = findSide(session, player.UserId)
	if mySide == nil then
		return false, "Interner Fehler in der Handelssitzung."
	end

	mySide.accepted = not mySide.accepted
	local bothAccepted = session.sides[1].accepted and session.sides[2].accepted
	if bothAccepted then
		-- Beide haben zugestimmt: sperren und nach der Sicherheitspause ausführen.
		session.state = "locked"
	end
	sendSessionUpdate(session)
	if bothAccepted then
		task.delay(GameConfig.TRADE_LOCK_SECONDS, function()
			executeTrade(session)
		end)
	end
	return true, nil
end

local function handleCancel(player: Player): (boolean, any?)
	local session = sessions[player.UserId]
	if session == nil then
		return false, "Du bist in keinem Handel."
	end
	if session.state ~= "negotiating" and session.state ~= "locked" then
		return false, "Dieser Handel kann nicht mehr abgebrochen werden."
	end
	cancelSession(session, "Der Handel wurde abgebrochen.", "info")
	return true, nil
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId

	-- Einladungen AN diesen Spieler und VON diesem Spieler entfernen.
	pendingInvites[userId] = nil
	for targetUserId, fromUserId in pendingInvites do
		if fromUserId == userId then
			pendingInvites[targetUserId] = nil
		end
	end

	local session = sessions[userId]
	if session ~= nil then
		cancelSession(session, `{player.Name} hat den Handel verlassen.`, "info")
	end
end

function TradeService.init()
	tradeUpdatedEvent = Remotes.getEvent("TradeUpdated")
	notificationEvent = Remotes.getEvent("Notification")

	local tradeFunction = Remotes.getFunction("TradeAction")
	tradeFunction.OnServerInvoke = function(player: Player, action: any, payload: any): (boolean, any?)
		if typeof(action) ~= "string" then
			return false, "Ungültige Aktion."
		end
		if action == "invite" then
			return handleInvite(player, payload)
		elseif action == "acceptInvite" then
			return handleAcceptInvite(player, payload)
		elseif action == "setOffer" then
			return handleSetOffer(player, payload)
		elseif action == "toggleAccept" then
			return handleToggleAccept(player)
		elseif action == "cancel" then
			return handleCancel(player)
		end
		return false, "Unbekannte Aktion."
	end

	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return TradeService
