-- ReplicatedStorage/Shared/Config.luau
--!strict
-- GHOSTNET :: Zentrale Balancing-Datei.
-- Regel: Jede Zahl, die man zum Austarieren anfassen will, steht HIER und
-- nirgendwo sonst. Server und Client lesen dieselbe Datei.

local Config = {}

Config.Version = "0.3.0" -- Phase A: Missions-Rueckgrat

-- CollectionService-Tags. Ein Part mit dem Tag ist ein Hack-Ziel, ein Hehler,
-- ein Missions-Wegpunkt oder ein ansprechbarer Kontakt. Kein Code pro Objekt.
Config.HackableTag = "GhostNetHackable"
Config.FenceTag = "GhostNetFence"
Config.WaypointTag = "GhostNetWaypoint"
Config.ContactTag = "GhostNetContact"

--==========================================================================
-- 1. REICHWEITE (Netzwerkkarte)
--==========================================================================
Config.Range = {
	Base = 18, -- Studs auf NetCard 1
	PerNetCard = 6, -- pro weiterer Stufe
	Tolerance = 4, -- Lag-Puffer bei der Serverpruefung
}

function Config.GetRange(netCardLevel: number): number
	return Config.Range.Base + Config.Range.PerNetCard * (netCardLevel - 1)
end

--==========================================================================
-- 2. ZEIT (CPU)
--==========================================================================
Config.Time = {
	Base = 25, -- Sekunden auf CPU 1
	PerCPU = 4, -- pro weiterer Stufe
	PerDifficulty = 3, -- Zuschlag pro Schwierigkeitsgrad
}

function Config.GetTimeLimit(cpuLevel: number, difficulty: number): number
	return Config.Time.Base + Config.Time.PerCPU * (cpuLevel - 1) + Config.Time.PerDifficulty * difficulty
end

--==========================================================================
-- 3. VERSUCHE (RAM)
--==========================================================================
Config.Attempts = {
	Base = 3, -- auf RAM 1
	PerRAM = 1,
	Cap = 7,
}

function Config.GetAttempts(ramLevel: number): number
	return math.min(Config.Attempts.Cap, Config.Attempts.Base + Config.Attempts.PerRAM * (ramLevel - 1))
end

--==========================================================================
-- 4. TRACE (Kuehlung)
-- Die einzige Spannungsquelle des Spiels. Steigt bei jedem Hack, faellt im
-- Leerlauf und beim Verkauf. Bei 100 ist alles Unverkaufte weg.
--==========================================================================
Config.Trace = {
	Max = 100,
	GainPerDifficulty = 4.0, -- Default, wenn der Part kein TraceGain-Attribut hat
	CoolingReduction = 0.08, -- -8% Trace-Gewinn pro Kuehlungsstufe
	AbortFactor = 0.5, -- Abbruch kostet halben Trace, damit er kein Free-Retry ist
	FailFactor = 0.75, -- Fehlschlag kostet 75% Trace

	-- Abkuehlung. Hoeher = entspannter, niedriger = man muss oefter verkaufen.
	-- 0.25/s heisst: ein voller Balken braucht rund 6,5 Minuten Nichtstun.
	DecayPerSecond = 0.25, -- Grundabkuehlung auf Kuehlung 1
	DecayPerCooling = 0.15, -- zusaetzlich je Stufe darueber (Kuehlung 5 = 0.85/s)
	DecayDelay = 3.0, -- so viele Sekunden Ruhe, bevor die Abkuehlung einsetzt
	DecayTick = 0.25, -- Rechen-Takt des Abkuehl-Loops (reine Performance-Zahl)

	-- Bust bei 100.
	AfterBust = 25, -- hoeher = der naechste Bust kommt schneller
	BustLockSeconds = 15, -- so lange sind neue Hacks danach gesperrt

	-- Anzeige-Schwellen im HUD.
	WarnAt = 70, -- ab hier pulsiert der Balken
	CriticalAt = 90, -- ab hier rot und schneller

	-- Wie oft der Server den Balken zum Client schickt.
	SyncInterval = 0.4,
	SyncEpsilon = 0.4, -- kleinere Aenderungen werden gesammelt statt gesendet
}

function Config.GetTraceGain(baseGain: number, coolingLevel: number): number
	local reduction = 1 - Config.Trace.CoolingReduction * (coolingLevel - 1)
	return baseGain * math.max(0.2, reduction)
end

-- Abkuehlung pro Sekunde. Wird auch fuer die Offline-Zeit benutzt.
function Config.GetTraceDecay(coolingLevel: number): number
	return Config.Trace.DecayPerSecond + Config.Trace.DecayPerCooling * (coolingLevel - 1)
end

--==========================================================================
-- 5. BELOHNUNG
--==========================================================================
Config.Reward = {
	Base = 40,
	Exponent = 1.35,
}

function Config.GetReward(difficulty: number): number
	return math.floor(Config.Reward.Base * difficulty ^ Config.Reward.Exponent)
end

--==========================================================================
-- 6. COOLDOWN
--==========================================================================
Config.Cooldown = {
	Default = 90, -- Sekunden, pro Spieler und Ziel
	AfterFail = 20, -- kuerzer nach einem Fehlschlag, damit man es nochmal darf
	-- Cooldowns liegen seit Phase 1 im Profil. Alles, was laenger als das
	-- abgelaufen ist, fliegt beim Speichern raus, damit das Profil nicht waechst.
	KeepSeconds = 86400,
}

--==========================================================================
-- 7. RIG
--==========================================================================
Config.Rig = {
	MaxLevel = 5,
	Components = { "CPU", "RAM", "Cooling", "NetCard" },
	StartLevels = { CPU = 1, RAM = 1, Cooling = 1, NetCard = 1 },

	-- Anzeigetexte fuer den Shop. Stehen hier, damit die UI keine eigenen
	-- Strings erfindet.
	Labels = {
		CPU = "CPU",
		RAM = "RAM",
		Cooling = "KUEHLUNG",
		NetCard = "NETZKARTE",
	},
	Blurbs = {
		CPU = "mehr Zeit pro Einbruch",
		RAM = "mehr Versuche, bevor das Rig abstuerzt",
		Cooling = "weniger Trace, schnellere Abkuehlung",
		NetCard = "groessere Reichweite zum Ziel",
	},
}

-- Was eine Stufe konkret bringt - nur fuer die Shop-Anzeige.
function Config.GetRigEffect(component: string, level: number): string
	if component == "CPU" then
		return ("%d s Grundzeit"):format(Config.Time.Base + Config.Time.PerCPU * (level - 1))
	elseif component == "RAM" then
		return ("%d Versuche"):format(Config.GetAttempts(level))
	elseif component == "Cooling" then
		local reduction = math.floor((1 - Config.GetTraceGain(1, level)) * 100 + 0.5)
		return ("-%d%% Trace  //  %.2f/s Abkuehlung"):format(reduction, Config.GetTraceDecay(level))
	elseif component == "NetCard" then
		return ("%d m Reichweite"):format(Config.GetRange(level))
	end
	return "-"
end

--==========================================================================
-- 8. RIG-UPGRADES (Shop)
-- Vorgabe: das erste Upgrade soll nach 2-3 erfolgreichen Hacks drin sein.
-- Die Kamera (D2) bringt 101 CRY, nach 12% Hehler-Gebuehr 89 auf die Bank -
-- 220 CRY sind also rund 2,5 Kamera-Hacks.
-- Base runter = schnellerer Einstieg. Growth runter = flachere Kurve spaet.
--==========================================================================
Config.Upgrade = {
	Base = 220, -- Preis fuer die zweite Stufe bei Faktor 1.0
	Growth = 2.4, -- Preis mal diesem Wert je weiterer Stufe
	-- Feintuning je Bauteil. Kuehlung ist billig, weil sie sich nicht sofort
	-- belohnend anfuehlt und sonst nie gekauft wuerde.
	ComponentFactor = {
		CPU = 1.0,
		RAM = 1.15,
		Cooling = 0.9,
		NetCard = 1.05,
	},
}

-- Preis fuer den Sprung AUF targetLevel. Der Server rechnet das selbst aus,
-- der Client zeigt es nur an.
function Config.GetUpgradeCost(component: string, targetLevel: number): number
	local factor = (Config.Upgrade.ComponentFactor :: any)[component]
	if typeof(factor) ~= "number" then
		return math.huge
	end
	if targetLevel <= 1 or targetLevel > Config.Rig.MaxLevel then
		return math.huge
	end
	return math.floor(Config.Upgrade.Base * factor * Config.Upgrade.Growth ^ (targetLevel - 2))
end

--==========================================================================
-- 9. VERKAUF (Hehler)
-- Unsold ist heiss, Banked ist sicher. Der Weg zum Hehler kostet Zeit, der
-- Trace laeuft weiter - daraus entsteht "noch ein Ziel oder jetzt abliefern?".
--==========================================================================
Config.Sell = {
	Range = 12, -- Studs bis zur Oberflaeche des Hehler-Parts
	Tolerance = 4, -- gleicher Lag-Puffer wie beim Hacken
	FeePercent = 0.12, -- Hehler-Gebuehr. Hoch = Verkaufen tut weh, niedrig = egal.
	TraceRelief = 18, -- so viel Trace nimmt ein Verkauf weg
	MinAmount = 1, -- darunter lohnt der Klick nicht
}

-- Liefert (brutto, gebuehr, netto).
function Config.GetSellPayout(unsold: number): (number, number, number)
	local gross = math.max(0, math.floor(unsold))
	local fee = math.floor(gross * Config.Sell.FeePercent)
	return gross, fee, gross - fee
end

--==========================================================================
-- 10. SPEICHERN
--==========================================================================
Config.Save = {
	-- Hochzaehlen, wenn sich das Profil-Schema aendert. Zu JEDER neuen Version
	-- gehoert ein Eintrag in SaveService.MIGRATIONS.
	--   1 = Phase 1 (Bank, Unsold, Rig, Trace, Cooldowns, Stats)
	--   2 = Phase A (Story-Block)
	SchemaVersion = 2,
	StoreName = "GhostNetPlayers_v1",
	KeyFormat = "ghostnet_player_%d",

	Interval = 60, -- Autosave-Takt in Sekunden
	MinInterval = 8, -- Mindestabstand zwischen zwei Speicherungen desselben Profils
	MaxRetries = 4, -- danach gilt der Zugriff als gescheitert
	StudioRetries = 2, -- im Studio kuerzer: ohne API-Zugriff scheitert es sowieso
	RetryBase = 1.0, -- erste Wartezeit
	RetryFactor = 2.0, -- Verdopplung je Versuch (1s, 2s, 4s)
	BindToCloseSeconds = 20, -- so lange haelt der Server beim Herunterfahren an
	LeaveSaveWait = 6, -- so lange wartet der Abschluss-Save auf einen laufenden

	-- Wenn das Laden endgueltig scheitert, wird gekickt statt mit leerem Profil
	-- weitergespielt - sonst ueberschreibt der Save beim Verlassen echten
	-- Fortschritt mit Nullen.
	KickMessage = "GHOSTNET: Dein Profil konnte nicht geladen werden.\nBitte in ein paar Sekunden neu beitreten - so geht nichts verloren.",
	LockKickMessage = "GHOSTNET: Du spielst gerade auf einem anderen Server.\nDiese aeltere Sitzung wurde beendet, damit dein Fortschritt nicht doppelt laeuft.",

	-- NUR im Studio: sind DataStores nicht erreichbar (API-Zugriff aus), laeuft
	-- das Spiel mit einem Profil im Arbeitsspeicher weiter, damit man ueberhaupt
	-- testen kann. Live ist dieser Pfad durch RunService:IsStudio() gesperrt.
	StudioMemoryFallback = true,
}

--==========================================================================
-- 11. MISSIONEN (Story-Rueckgrat)
-- Die Missionsdaten selbst stehen in Shared/Missions.luau. Hier steht nur,
-- wie sich das System verhaelt.
--==========================================================================
Config.Mission = {
	-- true = die erste verfuegbare Mission startet von selbst, sobald das
	-- Profil geladen ist. Auf false gestellt muss der Spieler jede Mission
	-- ueber MissionAccept annehmen.
	AutoStart = true,

	TickSeconds = 0.5, -- Takt fuer GOTO-Distanz und WAIT-Timer (reine Performance)

	-- Reichweiten fuer GOTO- und TALK-Schritte. Beides wird serverseitig
	-- geprueft, genau wie beim Hacken. Groesser = grosszuegiger, aber ein
	-- Wegpunkt gilt dann schon aus der Ferne als erreicht.
	WaypointRange = 10,
	WaypointTolerance = 4,
	ContactRange = 10,
	ContactTolerance = 4,

	-- false = die Belohnung landet im heissen Wallet und muss erst zum Hehler.
	-- Das haelt den Verkaufs-Loop auch bei Story-Geld relevant. true zahlt
	-- direkt auf die Bank - bequemer, nimmt der Mission aber die Spannung.
	RewardToBank = false,

	MaxSteps = 24, -- Sicherheitsgrenze; groessere Missionen gelten als Datenfehler

	-- Nur diese Missionen darf man ueberspringen. Ueberspringen vergibt den
	-- Unlock, aber keine Crypto - sonst waere es ein Gratis-Geldautomat.
	-- Story-Missionen mit echtem Inhalt stehen bewusst NICHT hier.
	Skippable = {
		M01_FIRSTHACK = true,
	},
}

--==========================================================================
-- 12. UEBERFAELLE (mehrstufige Ziele mit Alarm)
-- Ein Ziel gehoert ueber das Attribut "AlarmGroup" zu einer Gruppe.
-- "AlarmStarts" am ersten Ziel startet die Uhr, "AlarmEnds" am letzten
-- stoppt sie. Kein Code pro Gebaeude.
--==========================================================================
Config.Raid = {
	-- Sekunden vom ersten geknackten Ziel bis zum Alarm. Runter = mehr Panik,
	-- hoch = der Ueberfall wird zur Formalitaet.
	AlarmSeconds = 60,
	AlarmWarnAt = 15, -- ab hier blinkt die Anzeige rot
	-- Trace-Sprung, wenn die Uhr durchlaeuft. Muss weh tun, sonst ignoriert
	-- man den Alarm einfach.
	AlarmTracePenalty = 35,
	AlarmSyncInterval = 0.5,

	-- Wiederholbarkeit. Genau das macht aus einer Mission dauerhaften Inhalt.
	StoreCooldown = 240, -- Ladenueberfall
	BankCooldown = 1800, -- Endgame-Ziel

	-- Bank: ein Fehlschlag ist kein normaler Fehlversuch, sondern sofort Bust.
	-- Ueber das Attribut "FailBusts" am Part aktiviert.
	FailBustTrace = 100,

	-- Co-Op. Ein zweiter Spieler in Reichweite eines Ziels mit dem Attribut
	-- "RequiresTwo" halbiert Trace-Anstieg und Alarmtempo. Auf Roblox holt
	-- niemand Freunde, wenn es auch allein geht - deshalb spuerbar machen.
	CoopRange = 40,
	CoopTraceFactor = 0.5,
	CoopAlarmFactor = 0.5,
}

--==========================================================================
-- 13. RATE-LIMITS (Token-Bucket pro Spieler und Remote)
-- Jede neue Remote braucht hier einen Eintrag, sonst wird sie verworfen.
--==========================================================================
Config.RateLimits = {
	HackRequestStart = { Rate = 2, Burst = 3 },
	HackInput = { Rate = 12, Burst = 20 },
	HackAbort = { Rate = 4, Burst = 6 },
	SellRequest = { Rate = 1, Burst = 3 },
	ShopPurchase = { Rate = 2, Burst = 4 },
	MissionAccept = { Rate = 1, Burst = 3 },
	MissionAbandon = { Rate = 1, Burst = 2 },
	MissionInteract = { Rate = 2, Burst = 4 },
	MissionSkip = { Rate = 0.5, Burst = 2 },
}

--==========================================================================
-- 14. NODE-BREACH
--==========================================================================
Config.NodeBreach = {
	-- Pro Schwierigkeitsband: Gittergroesse, Anzahl Relays, Anteil sichtbares
	-- ICE und Anteil verstecktes ICE (nur DAS kostet Versuche).
	Tiers = {
		{ MaxDifficulty = 2, Width = 5, Height = 5, Relays = 1, Ice = 0.15, MaskedIce = 0.06 },
		{ MaxDifficulty = 4, Width = 6, Height = 6, Relays = 2, Ice = 0.20, MaskedIce = 0.09 },
		{ MaxDifficulty = 6, Width = 6, Height = 6, Relays = 3, Ice = 0.25, MaskedIce = 0.12 },
		{ MaxDifficulty = 8, Width = 7, Height = 7, Relays = 3, Ice = 0.30, MaskedIce = 0.15 },
		{ MaxDifficulty = 10, Width = 8, Height = 8, Relays = 4, Ice = 0.32, MaskedIce = 0.18 },
	},
	PathSearchTries = 12, -- so viele Pfade werden erzeugt, der passendste gewinnt
	PathLengthBonus = 2, -- Wunschlaenge = Width + Height + Bonus
}

--==========================================================================
-- 15. DEFAULTS FUER HACK-ZIELE
-- Ein Part braucht KEIN einziges Attribut. Alles, was fehlt, kommt von hier.
--==========================================================================
Config.TargetDefaults = {
	Difficulty = 1,
	HackType = "NodeBreach",
	Reward = -1, -- -1 = aus Difficulty berechnen
	TraceGain = -1, -- -1 = aus Difficulty berechnen
	Cooldown = -1, -- -1 = Config.Cooldown.Default
	RequiredLevel = 1,
	OnSuccess = "Offline",
	DisplayName = "", -- "" = Instanzname benutzen
	DownTime = 30, -- wie lange der Welteffekt haelt
	-- Weitere Attribute, die ein Part optional tragen darf und die hier
	-- bewusst KEINEN Default brauchen (nicht gesetzt = Funktion aus):
	--   TargetId   fester Bezeichner, auf den Missionen zeigen koennen
	--   AlarmGroup Name der Ueberfall-Gruppe (siehe Config.Raid)
	--   AlarmStarts / AlarmEnds  startet bzw. stoppt die Alarm-Uhr
	--   FailBusts  true = ein Fehlschlag hier ist sofort ein Bust
	--   RequiresTwo true = zu zweit deutlich leichter (Co-Op)
	--   NoTrace    true = dieses Ziel erzeugt keinen Trace (nur Tutorial)
}

--==========================================================================
-- SESSION / LAUFZEIT
--==========================================================================
Config.Session = {
	TickRate = 0.25, -- Sekunden zwischen Ablauf- und Distanzpruefung
	GraceAfterStart = 0.5, -- kurze Schonfrist, bevor die Distanz geprueft wird
}

--==========================================================================
-- UI-FARBEN (Fake-OS)
--==========================================================================
Config.Theme = {
	Background = Color3.fromRGB(6, 8, 11),
	Panel = Color3.fromRGB(13, 17, 23),
	PanelLight = Color3.fromRGB(22, 28, 37),
	Line = Color3.fromRGB(38, 48, 62),
	Cyan = Color3.fromRGB(0, 229, 255),
	CyanDim = Color3.fromRGB(0, 120, 140),
	Magenta = Color3.fromRGB(255, 45, 149),
	Amber = Color3.fromRGB(255, 176, 0),
	Text = Color3.fromRGB(198, 214, 226),
	TextDim = Color3.fromRGB(96, 116, 134),
	Ice = Color3.fromRGB(64, 78, 96),
	Green = Color3.fromRGB(0, 230, 118), -- Verkauf und Bank
}

table.freeze(Config.Theme)

return Config
