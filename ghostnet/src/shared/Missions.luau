-- ReplicatedStorage/Shared/Missions.luau
--!strict
-- GHOSTNET :: Missionsdaten und die reinen Regeln dazu.
--
-- WARUM DATEN UND NICHT SKRIPTE
--   Eine Mission ist ein Tabelleneintrag. Wer eine neue schreibt, fasst nur
--   diese Datei an - der MissionService bleibt unberuehrt. Das Modul kennt
--   weder Spieler noch Remotes noch die Welt: alles hier ist pur und damit
--   im Testlauf ohne Roblox pruefbar.
--
-- LEITREGEL AUS DEM BAUPLAN
--   Jede Mission ist gleichzeitig das Tutorial fuer ein System UND schaltet
--   dieses System dauerhaft frei. Nie eine Mission bauen, deren Inhalt danach
--   verschwindet.
--
-- SCHRITT-TYPEN (mehr gibt es nicht, alles andere setzt sich daraus zusammen)
--   GOTO   Target     = WaypointId eines Parts mit Tag GhostNetWaypoint
--   HACK   TargetId   = TargetId eines Parts mit Tag GhostNetHackable
--   SELL   Amount     = Anzahl Verkaeufe beim Hehler (Standard 1)
--   BUY    GoodId?    = Ware im Darknet, Amount = Stueckzahl (Phase C)
--   WAIT   Seconds    = Wartezeit, serverseitig ueber os.time() gemessen
--   TALK   ContactId  = Kontakt-Part mit Tag GhostNetContact

local Types = require(script.Parent.Types)

local Missions = {}

export type Step = {
	Type: string,
	Text: string,
	Target: string?, -- GOTO
	TargetId: string?, -- HACK
	ContactId: string?, -- TALK
	GoodId: string?, -- BUY
	Amount: number?, -- SELL / BUY
	Seconds: number?, -- WAIT
}

export type Reward = {
	Crypto: number?,
	Unlock: string?,
}

export type Mission = {
	Id: string,
	Title: string,
	Briefing: string,
	Requires: { string },
	Steps: { Step },
	Reward: Reward,
}

--==========================================================================
-- Die Registry
--==========================================================================

-- PHASE A liefert absichtlich das Geruest ohne Inhalt: erst das System, dann
-- die Missionen. Der MissionService muss mit einer leeren Liste sauber laufen.
-- Phase B traegt hier M01_FIRSTHACK bis M03_HOME ein, Phase D M04 und M05.
-- Das Schema steht in Missions.Example - dort abschauen, nicht raten.
Missions.List = {} :: { Mission }

-- Nur Doku und Testmaterial. Steht NICHT in der Registry und laeuft im Spiel
-- nie. Zeigt jeden Schritt-Typ genau einmal.
Missions.Example = {
	Id = "M00_BEISPIEL",
	Title = "Beispielmission",
	Briefing = "Zeigt das Schema. Wird nie gespielt.",
	Requires = {},
	Steps = {
		{ Type = "GOTO", Target = "STORE_FRONT", Text = "Geh zum Laden" },
		{ Type = "HACK", TargetId = "STORE_LOCK", Text = "Knack das Schloss" },
		{ Type = "WAIT", Seconds = 5, Text = "Warte, bis die Luft rein ist" },
		{ Type = "TALK", ContactId = "FIXER", Text = "Sprich mit dem Fixer" },
		{ Type = "BUY", GoodId = "EXPLOIT_KIT", Amount = 2, Text = "Kauf zwei Exploit-Kits" },
		{ Type = "SELL", Amount = 1, Text = "Bring die Beute zum Hehler" },
	},
	Reward = { Crypto = 400, Unlock = "STORE_RAIDS" },
} :: Mission

Missions.StepTypes = {
	GOTO = true,
	HACK = true,
	SELL = true,
	BUY = true,
	WAIT = true,
	TALK = true,
}

--==========================================================================
-- Nachschlagen
--==========================================================================

local function indexOf(list: { string }, value: string): number?
	for index, entry in list do
		if entry == value then
			return index
		end
	end
	return nil
end

function Missions.Contains(list: { string }, value: string): boolean
	return indexOf(list, value) ~= nil
end

function Missions.Get(id: string, list: { Mission }?): Mission?
	for _, mission in (list or Missions.List) do
		if mission.Id == id then
			return mission
		end
	end
	return nil
end

function Missions.Count(list: { Mission }?): number
	return #(list or Missions.List)
end

--==========================================================================
-- Verfuegbarkeit
--==========================================================================

-- story ist der Story-Block aus dem Profil. Es wird bewusst derselbe Typ
-- benutzt statt eine zweite Kopie der Form zu pflegen - sonst laufen die
-- beiden bei der naechsten Schema-Aenderung auseinander.
export type StoryView = Types.Story

function Missions.IsCompleted(story: StoryView, id: string): boolean
	return Missions.Contains(story.Completed, id)
end

function Missions.IsAvailable(story: StoryView, id: string, list: { Mission }?): boolean
	local mission = Missions.Get(id, list)
	if not mission then
		return false
	end
	if Missions.IsCompleted(story, id) then
		return false
	end
	for _, required in mission.Requires do
		if not Missions.IsCompleted(story, required) then
			return false
		end
	end
	return true
end

-- Erste Mission in Listenreihenfolge, die jetzt gespielt werden koennte.
function Missions.FirstAvailable(story: StoryView, list: { Mission }?): Mission?
	for _, mission in (list or Missions.List) do
		if Missions.IsAvailable(story, mission.Id, list) then
			return mission
		end
	end
	return nil
end

function Missions.HasUnlock(story: StoryView, key: string): boolean
	return Missions.Contains(story.Unlocks, key)
end

--==========================================================================
-- Fortschritt eines Schrittes
--==========================================================================

-- Wie viel ein Schritt braucht, um zu gelten.
function Missions.Required(step: Step): number
	if step.Type == "WAIT" then
		return 1 -- der Timer laeuft im Service, hier zaehlt nur "fertig"
	end
	local amount = step.Amount
	if typeof(amount) == "number" and amount > 0 then
		return math.floor(amount)
	end
	return 1
end

-- Was ein Ereignis zu diesem Schritt beitraegt. 0 = passt nicht.
--
-- event = { Type = "HACK"|"SELL"|"BUY"|"GOTO"|"TALK"|"WAIT",
--           TargetId?, WaypointId?, ContactId?, GoodId?, Amount?, Success? }
--
-- Diese Funktion ist der einzige Ort, an dem entschieden wird, ob ein Schritt
-- vorankommt. Sie ist pur - der Testlauf faehrt sie ohne Roblox durch.
function Missions.Progress(step: Step, event: { [string]: any }): number
	if typeof(event) ~= "table" or step.Type ~= event.Type then
		return 0
	end

	if step.Type == "GOTO" then
		return if event.WaypointId == step.Target then 1 else 0
	elseif step.Type == "HACK" then
		if event.Success ~= true then
			return 0 -- ein Fehlschlag bringt eine Mission nicht voran
		end
		return if event.TargetId == step.TargetId then 1 else 0
	elseif step.Type == "TALK" then
		return if event.ContactId == step.ContactId then 1 else 0
	elseif step.Type == "SELL" then
		return 1 -- jeder Verkauf zaehlt einmal
	elseif step.Type == "WAIT" then
		return 1 -- nur der Service schickt dieses Ereignis
	elseif step.Type == "BUY" then
		if step.GoodId ~= nil and event.GoodId ~= step.GoodId then
			return 0
		end
		local amount = event.Amount
		if typeof(amount) ~= "number" or amount <= 0 then
			return 0
		end
		return math.floor(amount)
	end

	return 0
end

--==========================================================================
-- Pruefung der Missionsdaten
-- Laeuft beim Serverstart UND im Testlauf. Eine kaputte Mission soll beim
-- Hochfahren auffallen und nicht erst, wenn ein Spieler darin feststeckt.
--==========================================================================

local REQUIRED_FIELD: { [string]: string } = {
	GOTO = "Target",
	HACK = "TargetId",
	TALK = "ContactId",
}

function Missions.Validate(list: { Mission }?, maxSteps: number?): (boolean, { string })
	local missions = list or Missions.List
	local limit = maxSteps or 64
	local errors: { string } = {}

	local seen: { [string]: boolean } = {}
	for index, mission in missions do
		local label = ("Mission #%d"):format(index)

		if typeof(mission.Id) ~= "string" or mission.Id == "" then
			table.insert(errors, ("%s: Id fehlt"):format(label))
			continue
		end
		label = mission.Id

		if seen[mission.Id] then
			table.insert(errors, ("%s: Id doppelt vergeben"):format(label))
		end
		seen[mission.Id] = true

		if typeof(mission.Title) ~= "string" or mission.Title == "" then
			table.insert(errors, ("%s: Title fehlt"):format(label))
		end
		if typeof(mission.Briefing) ~= "string" then
			table.insert(errors, ("%s: Briefing fehlt"):format(label))
		end
		if typeof(mission.Requires) ~= "table" then
			table.insert(errors, ("%s: Requires ist keine Liste"):format(label))
		end
		if typeof(mission.Reward) ~= "table" then
			table.insert(errors, ("%s: Reward fehlt"):format(label))
		end

		if typeof(mission.Steps) ~= "table" or #mission.Steps == 0 then
			table.insert(errors, ("%s: keine Schritte"):format(label))
		elseif #mission.Steps > limit then
			table.insert(errors, ("%s: %d Schritte, erlaubt sind %d"):format(label, #mission.Steps, limit))
		else
			for stepIndex, step in mission.Steps do
				local where = ("%s Schritt %d"):format(label, stepIndex)
				if typeof(step.Type) ~= "string" or not Missions.StepTypes[step.Type] then
					table.insert(errors, ("%s: unbekannter Typ '%s'"):format(where, tostring(step.Type)))
					continue
				end
				if typeof(step.Text) ~= "string" or step.Text == "" then
					table.insert(errors, ("%s: Text fehlt"):format(where))
				end
				local field = REQUIRED_FIELD[step.Type]
				if field and typeof((step :: any)[field]) ~= "string" then
					table.insert(errors, ("%s: %s fehlt fuer %s"):format(where, field, step.Type))
				end
				if step.Type == "WAIT" and (typeof(step.Seconds) ~= "number" or step.Seconds <= 0) then
					table.insert(errors, ("%s: Seconds fehlt oder ist <= 0"):format(where))
				end
				if step.Amount ~= nil and (typeof(step.Amount) ~= "number" or step.Amount <= 0) then
					table.insert(errors, ("%s: Amount muss groesser 0 sein"):format(where))
				end
			end
		end
	end

	-- Vorgaenger muessen existieren.
	for _, mission in missions do
		if typeof(mission.Requires) ~= "table" then
			continue
		end
		for _, required in mission.Requires do
			if not seen[required] then
				table.insert(errors, ("%s: Vorgaenger '%s' gibt es nicht"):format(mission.Id, tostring(required)))
			end
		end
	end

	-- Kreise in den Vorbedingungen. Ohne diese Pruefung waere eine Mission
	-- stumm nie erreichbar, und niemand fuende heraus warum.
	local WHITE, GREY, BLACK = 0, 1, 2
	local colour: { [string]: number } = {}
	local byId: { [string]: Mission } = {}
	for _, mission in missions do
		if typeof(mission.Id) == "string" then
			byId[mission.Id] = mission
			colour[mission.Id] = WHITE
		end
	end

	local function visit(id: string): boolean
		if colour[id] == GREY then
			return true
		end
		if colour[id] == BLACK then
			return false
		end
		colour[id] = GREY
		local mission = byId[id]
		if mission and typeof(mission.Requires) == "table" then
			for _, required in mission.Requires do
				if byId[required] and visit(required) then
					return true
				end
			end
		end
		colour[id] = BLACK
		return false
	end

	for id in byId do
		if colour[id] == WHITE and visit(id) then
			table.insert(errors, ("Kreis in den Vorbedingungen bei '%s'"):format(id))
		end
	end

	return #errors == 0, errors
end

return Missions
