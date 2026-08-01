-- ReplicatedStorage/Shared/Types.luau
--!strict
-- GHOSTNET :: Gemeinsame Luau-Typen fuer Server und Client.

export type RigLevels = {
	CPU: number,
	RAM: number,
	Cooling: number,
	NetCard: number,
}

-- Zaehler fuers Profil. Phase 3 haengt hier Tagesziele und Ranglisten dran.
export type Stats = {
	Hacks: number, -- erfolgreiche Einbrueche
	Fails: number, -- gescheiterte oder abgebrochene Einbrueche
	Busts: number, -- wie oft der Trace 100 erreicht hat
	Sales: number, -- Verkaeufe beim Hehler
	Earned: number, -- gesamte netto Einnahmen
	Upgrades: number, -- gekaufte Rig-Stufen
	GoodsBought: number, -- im Darknet gekaufte Einheiten
	GoodsSold: number, -- im Darknet verkaufte Einheiten
}

-- Ein gekauftes Fahrzeug. Rein kosmetische Anpassung - keine Leistungsteile,
-- sonst muesste das Fahrverhalten mehrfach ausbalanciert werden.
export type OwnedVehicle = {
	ClassId: string,
	Colour: string,
}

-- Story-Fortschritt im Profil. Der Client bekommt davon nur eine Abschrift
-- ueber MissionSync und meldet nie selbst, dass ein Schritt fertig ist.
export type Story = {
	Active: string, -- "" = gerade keine Mission
	Step: number, -- 1-basierter Index in Mission.Steps
	StepProgress: number, -- fuer Schritte mit Amount > 1
	StepStartedAt: number, -- Unix-Zeit, gebraucht fuer WAIT-Schritte
	Completed: { string }, -- abgeschlossene Missions-Ids
	Unlocks: { string }, -- dauerhaft freigeschaltete Systeme
	Allegiance: string, -- "" | "CASH" | "BURN"  (Mission 10, seit Schema 5)
	AllegianceAt: number, -- Unix-Zeit der letzten Umstellung
}

-- Das gespeicherte Spielerprofil. Einzige Wahrheit fuer alles, was einen
-- Serverwechsel ueberleben muss. Alle Zeitstempel sind os.time() (Unix-Zeit).
export type Profile = {
	SchemaVersion: number,
	Banked: number, -- sicher
	Unsold: number, -- heiss, geht beim Bust verloren
	Rig: RigLevels,
	Trace: number, -- 0 .. Config.Trace.Max
	Cooldowns: { [string]: number }, -- [targetId] = Unix-Zeit, ab der wieder erlaubt
	Stats: Stats,
	Story: Story, -- seit SchemaVersion 2
	Stash: { [string]: number }, -- Darknet-Lager, seit SchemaVersion 3
	PurchaseLog: { string }, -- verarbeitete PurchaseIds, seit SchemaVersion 4
	Garage: { OwnedVehicle }, -- gekaufte Fahrzeuge, seit SchemaVersion 5
	LastSeen: number, -- Unix-Zeit des letzten Speicherns
	SessionId: string, -- Session-Lock gegen Doppel-Sitzungen
}

-- Ein registriertes Hack-Ziel in der Welt.
export type HackTarget = {
	Id: string,
	Part: BasePart,
	DisplayName: string,
	Difficulty: number,
	HackType: string,
	Reward: number,
	TraceGain: number,
	Cooldown: number,
	RequiredLevel: number,
	OnSuccess: string,
	DownTime: number,
	DownUntil: number, -- 0 = einsatzbereit (os.clock, rein serverintern)
}

-- Was der Client ueber ein Node-Breach-Gitter erfahren darf.
-- Verstecktes ICE ist hier als OPEN (0) getarnt.
export type NodeBreachPublic = {
	Width: number,
	Height: number,
	Cells: { number }, -- 0 Open, 1 Ice, 2 Relay, 3 Start, 4 Exit
	Start: number,
	Exit: number,
	Relays: number,
}

-- Serverseitiger Rätselzustand. Verlaesst den Server NIE.
export type NodeBreachState = {
	Width: number,
	Height: number,
	Cells: { number }, -- inkl. 5 = MaskedIce
	Start: number,
	Exit: number,
	RelayTotal: number,
	RelaysVisited: number,
	Path: { number },
	InPath: { [number]: boolean },
	Revealed: { [number]: boolean },
	Solution: { number }, -- fuer den Auto-Solver in Phase 3
}

-- Ergebnis einer einzelnen Spielereingabe, vom Minispiel zurueckgegeben.
export type InputResult = {
	Ok: boolean,
	Reason: string,
	CostsAttempt: boolean,
	Solved: boolean,
	Feedback: { [string]: any },
}

-- Eine laufende Hack-Session auf dem Server.
export type Session = {
	Id: string,
	Player: Player,
	TargetId: string,
	HackType: string,
	Difficulty: number,
	Range: number,
	ExpectedStep: number,
	AttemptsLeft: number,
	Deadline: number, -- workspace:GetServerTimeNow()
	StartedAt: number,
	State: any, -- minispielspezifisch
	Resolved: boolean,
}

return {}
