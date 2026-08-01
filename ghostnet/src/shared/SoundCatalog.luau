-- ReplicatedStorage/Shared/SoundCatalog.luau
--!strict
-- GHOSTNET :: Alle Klaenge an einem Ort.
--
-- ACHTUNG: ALLE IDs SIND LEER. Noah traegt sie manuell ein.
-- Nutze ausschliesslich Assets aus der offiziellen Roblox Creator Marketplace
-- Audio-Bibliothek oder eigene Uploads. ERFINDE KEINE ASSET-IDS - falsche IDs
-- fuehren zu stummen Sounds ohne Fehlermeldung und sind schwer zu finden.
--
-- So traegt man eine ID ein:
--   Creator Marketplace -> Audio -> Sound anhoeren -> "Asset ID" kopieren
--   und hier als "rbxassetid://DEINE_ID" einsetzen, also die Zahl direkt
--   hinter die beiden Schraegstriche.
--
-- Solange ein Eintrag leer ist, spielt der SoundController ihn einfach nicht
-- ab. Das Spiel laeuft also auch ohne eine einzige ID - es klingt nur nach
-- nichts.

local SoundCatalog = {}

SoundCatalog.Ids = {
	UI = {
		NodeSelect = "", -- kurzer Klick beim Setzen eines Knotens
		NodeInvalid = "", -- dumpfer Fehlton
		IceHit = "", -- harter Treffer, verstecktes ICE
		HackStart = "", -- Terminal faehrt hoch
		HackSuccess = "", -- aufsteigend, befriedigend
		HackFail = "", -- absteigend
		Countdown = "", -- Ticken unter 10 s
		PanelOpen = "", -- Fenster faehrt auf
		PanelClose = "",
		Type = "", -- Tippgeraeusch im Terminal
	},
	Trace = {
		Warn = "", -- ab 70 %
		Critical = "", -- ab 90 %, Loop
		Bust = "", -- Alarm
	},
	Market = {
		Buy = "",
		Sell = "",
		PriceAlert = "", -- Markt-Event
	},
	Vehicle = {
		Engine = "", -- Loop, Tonhoehe steigt mit dem Tempo
		TyreSqueal = "", -- Loop, Lautstaerke steigt mit dem Seitwaertsdrift
		Crash = "", -- Aufprall
		DoorClose = "", -- Einsteigen
	},
	World = {
		Ambience = "", -- dunkler Stadt-Loop
		Rain = "",
		CameraDown = "",
		DoorOpen = "",
		SafeOpen = "",
		Alarm = "",
		Upgrade = "",
	},
}

--==========================================================================
-- Lautstaerken und Verhalten. Diese Zahlen darf man anfassen, die IDs nicht.
--==========================================================================

SoundCatalog.Settings = {
	UIVolume = 0.45,
	WorldVolume = 0.5,
	AmbienceVolume = 0.28,

	-- Waehrend eines Hacks wird die Ambience leiser, damit die UI-Sounds
	-- tragen. Beim Alarm kehrt sie schlagartig laut zurueck.
	AmbienceDuckFactor = 0.25,
	AmbienceDuckTime = 0.4,
	AmbienceAlarmFactor = 1.4,

	-- Die Tonhoehe der Knoten-Klicks steigt mit der Pfadlaenge: jeder
	-- gesetzte Knoten einen Halbton hoeher. Aus Klickgeraeuschen wird eine
	-- aufsteigende Melodie, und ein geloestes Raetsel klingt nach Erfolg
	-- statt nach Klicken.
	SemitoneRatio = 1.059463, -- 2^(1/12)
	MaxSemitones = 14, -- danach wird es schrill

	-- Countdown unter dieser Marke, Frequenz steigt zum Ende hin.
	CountdownFrom = 10,
	CountdownMinInterval = 0.25,
	CountdownMaxInterval = 1.0,
}

--==========================================================================

-- Liefert die Id oder nil, wenn sie noch nicht eingetragen ist.
function SoundCatalog.Get(group: string, key: string): string?
	local bucket = (SoundCatalog.Ids :: any)[group]
	if typeof(bucket) ~= "table" then
		return nil
	end
	local id = bucket[key]
	if typeof(id) ~= "string" or id == "" then
		return nil
	end
	return id
end

-- Wie viele IDs schon eingetragen sind - fuer die Startmeldung.
function SoundCatalog.Count(): (number, number)
	local filled, total = 0, 0
	for _, bucket in SoundCatalog.Ids do
		for _, id in bucket do
			total += 1
			if typeof(id) == "string" and id ~= "" then
				filled += 1
			end
		end
	end
	return filled, total
end

return SoundCatalog
