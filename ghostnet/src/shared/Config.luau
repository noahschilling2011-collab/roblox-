-- ReplicatedStorage/Shared/Config.luau
--!strict
-- GHOSTNET :: Zentrale Balancing-Datei.
-- Regel: Jede Zahl, die man zum Austarieren anfassen will, steht HIER und
-- nirgendwo sonst. Server und Client lesen dieselbe Datei.

local Config = {}

Config.Version = "2.2.0" -- Rework: Verkehrsbugs behoben, Geometrie kommt aus Assets

-- CollectionService-Tags. Ein Part mit dem Tag ist ein Hack-Ziel, ein Hehler,
-- ein Missions-Wegpunkt oder ein ansprechbarer Kontakt. Kein Code pro Objekt.
Config.HackableTag = "GhostNetHackable"
Config.FenceTag = "GhostNetFence"
Config.WaypointTag = "GhostNetWaypoint"
Config.ContactTag = "GhostNetContact"
Config.VehicleTag = "GhostNetVehicle" -- fahrbares Fahrzeug
Config.VehicleSpawnTag = "GhostNetVehicleSpawn" -- erlaubter Ausparkplatz
Config.DealerTag = "GhostNetDealer" -- Autohaendler-Tresen
Config.GuardTag = "GhostNetGuard" -- Wache mit Sichtkegel
-- Modelle, deren CFrame der Server nur im Takt setzt und die der Client
-- dazwischen weich nachzieht. Siehe Client/World/TrafficSmoother.
Config.SmoothTag = "GhostNetSmoothed"

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
	--   3 = Phase C (Darknet-Lager)
	--   4 = Phase F (PurchaseLog gegen Doppelvergabe)
	--   5 = Open World (Fahrzeugbesitz, Endgame-Entscheidung)
	SchemaVersion = 5,
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
-- 13. DARKNET-MARKT
-- Ohne Preisbewegung ist Handel ein Knopf, der 100 in 120 verwandelt. Der
-- Markt bewegt sich serverweit - alle Spieler sehen denselben Kurs, damit
-- man sich darueber unterhalten kann.
--==========================================================================
Config.Market = {
	-- Das Darknet ist erst offen, wenn M03 diesen Unlock vergeben hat.
	-- Wird serverseitig geprueft, nicht nur in der UI ausgeblendet.
	RequiredUnlock = "DARKNET",

	TickSeconds = 12, -- wie oft sich die Preise bewegen
	HistoryPoints = 24, -- Laenge des Mini-Charts (24 x 12 s = rund 5 Minuten)

	-- Rueckkehr zum Basispreis. Ohne das driften Kurse nach ein paar Stunden
	-- ins Absurde. 0.08 = pro Tick werden 8% der Abweichung abgebaut.
	MeanReversion = 0.08,
	-- Harte Grenzen, damit kein Kurs voellig entgleist.
	MinFactor = 0.45,
	MaxFactor = 2.2,

	-- Spanne zwischen An- und Verkauf. Der Markt verdient immer mit; ohne
	-- Spanne koennte man ohne Kursbewegung durch reines Hin-und-Her Geld
	-- drucken.
	Spread = 0.08,

	-- Events. Bewegen eine ganze Warengruppe und werden serverweit
	-- angekuendigt - das erzeugt Gespraeche und kostet nichts.
	EventChancePerTick = 0.03, -- rund alle 7 Minuten eins
	EventDurationTicks = 10,
	EventStrengthMin = 0.25,
	EventStrengthMax = 0.6,

	-- Lager. Begrenzt erzwingt Entscheidungen statt Alles-Kaufen.
	SlotsBase = 12, -- Einheiten insgesamt
	SlotsPerRig = 4, -- zusaetzlich je Tier-Stufe
	MaxPerTrade = 25, -- Obergrenze pro Klick, gegen Zahlen-Unfug

	-- Ware im Lager ist heiss wie Unsold-Crypto: ein Bust kostet auch davon
	-- einen Teil. Damit haengt der Handel am Trace-System statt danebenher
	-- zu laufen. 0 = Lager ist beim Bust sicher (dann fehlt dem Handel aber
	-- jedes Risiko).
	BustStashLossPercent = 0.5,

	-- Faelschungsrisiko. Das Analyse-Modul ist der zweite Zweck des
	-- Rig-Upgrades: je hoeher das Tier, desto seltener Ausschuss.
	RiskReductionPerTier = 0.18, -- -18% relatives Risiko je Tier ueber 1
	MinRiskFactor = 0.15, -- darunter geht es nie
}

-- Aktueller Preis aus Basispreis und Kursfaktor.
function Config.GetMarketPrice(base: number, factor: number): number
	return math.max(1, math.floor(base * factor + 0.5))
end

-- Was der Spieler zahlt bzw. bekommt. Der Server rechnet das selbst - ein
-- vom Client geschickter Preis wird nirgends gelesen.
function Config.GetBuyPrice(base: number, factor: number): number
	return math.max(1, math.floor(Config.GetMarketPrice(base, factor) * (1 + Config.Market.Spread) + 0.5))
end

function Config.GetSellPrice(base: number, factor: number): number
	return math.max(1, math.floor(Config.GetMarketPrice(base, factor) * (1 - Config.Market.Spread)))
end

function Config.GetStashSlots(tier: number): number
	return Config.Market.SlotsBase + Config.Market.SlotsPerRig * (tier - 1)
end

-- Tatsaechliches Faelschungsrisiko einer Ware bei diesem Rig-Tier.
function Config.GetFakeRisk(baseRisk: number, tier: number): number
	local factor = math.max(Config.Market.MinRiskFactor, 1 - Config.Market.RiskReductionPerTier * (tier - 1))
	return baseRisk * factor
end

--==========================================================================
-- 14. MONETARISIERUNG
-- Die IDs selbst stehen in MonetizationService (und sind alle 0). Hier
-- stehen nur die Zahlen, die man austarieren will.
--
-- Regel fuer alles, was hier dazukommt: Zeitersparnis, Kosmetik, Komfort
-- oder Kapazitaet - niemals etwas, das ein Raetsel loest.
--==========================================================================
Config.Monetization = {
	ColdRigTrace = 0.25, -- Gamepass: -25% Trace-Anstieg
	BigStashBonus = 0.5, -- Gamepass: +50% Lagerplatz
	Crypto1k = 1000, -- Produkt: Betrag direkt auf die Bank
	Crypto5k = 5000,

	-- Besitzpruefung. UserOwnsGamePassAsync kann fehlschlagen; bei einem
	-- Fehler wird NICHT angenommen, der Spieler besitze nichts.
	OwnershipRetries = 3,
	OwnershipRetryDelay = 2,
	OwnershipRecheckSeconds = 120,

	-- Verarbeitete Belege im Profil. Gegen Doppelvergabe. Gross genug, dass
	-- ein Vielkaeufer keine alten Eintraege verliert, klein genug fuers Profil.
	PurchaseLogLimit = 50,
}

--==========================================================================
-- 15. STADTKULISSE
-- Reine Optik. Wer auf schwachen Geraeten Probleme hat, dreht hier die
-- Anzahl runter - das kostet Atmosphaere, aber keine Spielmechanik.
--==========================================================================
Config.World = {
	Seed = 20260801, -- feste Zahl: die Stadt sieht auf jedem Server gleich aus

	--== TAGESLICHT ========================================================
	-- ENTSCHEIDUNG: Vantorra ist eine HELLE Stadt bei Tag.
	--
	-- Frueher lief hier ein Tag-/Nachtzyklus, und die Nacht war die Mechanik
	-- (+35 % Ertrag, NPCs sehen kuerzer). Das ist jetzt umgezogen: der Bonus
	-- haengt am ORT statt an der Uhrzeit - siehe Config.Cover. Bei Tageslicht
	-- ist das sogar der logischere Ort dafuer, weil es keine Dunkelheit mehr
	-- gibt, hinter der man sich verstecken koennte. Wer auf offener Strasse
	-- arbeitet, verdient mehr und wird eher gesehen.
	--
	-- PermanentDay = false schaltet den kompletten alten Zyklus wieder an,
	-- ohne dass irgendwo sonst Code angefasst werden muss. Alle Nacht-Werte
	-- darunter bleiben deshalb stehen und sind weiter gueltig.
	PermanentDay = true,
	DayClock = 13.5, -- Uhrzeit, auf der die Sonne steht. 12 = senkrecht.

	DayLengthMinutes = 24, -- voller Zyklus. 24 = eine Minute pro Stunde.
	StartClock = 13.5, -- womit ein frischer Server anfaengt
	TimeTick = 0.25, -- wie oft die Uhr gestellt wird (reine Performance)

	DayStartHour = 6, -- ab hier gilt "Tag"
	NightStartHour = 20, -- ab hier gilt "Nacht"

	-- Nur noch wirksam, wenn PermanentDay auf false steht.
	NightRewardBonus = 0.35, -- +35 % auf jeden Hack-Ertrag nachts
	NightSightFactor = 0.6, -- NPCs sehen nachts kuerzer
	DayMarketCalm = 0.6, -- tagsueber schwanken die Kurse nur 60 %

	-- Lighting. Future sieht deutlich besser aus, kostet auf schwachen
	-- Geraeten aber spuerbar Bildrate. Auf "ShadowMap" stellen, wenn es
	-- auf dem Handy ruckelt - der Rest des Spiels aendert sich nicht.
	LightingTechnology = "Future",
	FogNight = 380,
	FogDay = 900,
	AtmosphereDensityNight = 0.42,
	AtmosphereDensityDay = 0.28,
	BloomNight = 0.9,
	BloomDay = 0.35,

	-- Werte fuer den dauerhaften Tag. Bewusst kraeftiger als die alten
	-- "Day"-Werte oben: die waren nur das helle Ende einer Rampe, die
	-- meistens woanders stand. Jetzt ist das der Normalzustand.
	--   Brightness hoch  = harte Sonne, tiefe Schatten
	--   Brightness runter= flacher, weicher, aber matschiger
	SunBrightness = 3,
	SunFog = 2200, -- Sichtweite. Runter = Dunst, hoch = klare Fernsicht.
	SunAtmosphere = 0.12, -- wenig Dunst. Hoch = milchig.
	SunBloom = 0.25, -- sparsam: bei Tag wird Bloom schnell zu Matsch.
	SunAmbient = Color3.fromRGB(138, 142, 150), -- Licht im Schatten
	SunOutdoorAmbient = Color3.fromRGB(168, 174, 184),
	SunSaturation = 0.05, -- leicht kraeftigere Farben, nicht knallig
	SunTint = Color3.fromRGB(255, 252, 244), -- Hauch warm

	--== STREAMING =========================================================
	-- Pflicht fuer eine grosse Karte: ohne laedt jeder Spieler die ganze
	-- Stadt in den Speicher und Handys brechen zusammen.
	StreamingEnabled = true,
	StreamingMinRadius = 128, -- was immer geladen ist
	StreamingTargetRadius = 512, -- was angestrebt wird

	RoadWidth = 46,
	RoadLength = 320,
	-- Bei Tag ist eine spiegelnde Fahrbahn nur grell. Frueher stand das auf
	-- 0.28 (nasse Nachtstrasse). 0 = trocken und matt, 0.3 = frisch geregnet.
	RoadReflectance = 0.08,

	MaxBuildingHeight = 78,
	WindowChance = 0.55, -- Anteil Fensterbaender an einer Fassade
	-- Wie stark Fenster spiegeln. Bei Tag ersetzt das die frueher leuchtenden
	-- Neonfenster. Hoch = Glaspalast, 0 = mattes Fensterband.
	WindowReflectance = 0.35,
	SignChance = 0.45, -- Anteil Haeuser mit Neonschild
	SignBrightness = 3,
	SignRange = 26,

	-- Hack-Ziele sollen auf Distanz erkennbar sein: ihr Akzentlicht pulsiert
	-- dezent und geht aus, wenn das Ziel offline ist.
	TargetPulseSpeed = 1.6,
	TargetPulseDepth = 0.35,
}

--==========================================================================
-- 16. FAHRZEUGE
-- Die Klassen selbst stehen in Shared/Vehicles.luau. Hier steht, was fuer
-- alle gilt, und die Defaults fuer fehlende Attribute.
--
-- WICHTIG ZUR SICHERHEIT: Sobald jemand einsteigt, bekommt der Client den
-- Netzwerkbesitz ueber das Chassis - sonst faehrt sich das Auto wie durch
-- Sirup. Damit besitzt der Client die Fahrzeugphysik. Deshalb darf NIE eine
-- Fahrzeugposition oder -geschwindigkeit als Beweis fuer eine Belohnung
-- dienen. Ankommen wird ueber serverseitige Trigger-Parts geprueft.
--==========================================================================
Config.Vehicle = {
	MaxSpawned = 1, -- pro Spieler gleichzeitig ausgeparkt. Hoch = Server erstickt.
	IdleDespawn = 120, -- Sekunden ohne Fahrer, dann verschwindet es
	SpawnRange = 24, -- so nah muss man an einem Ausparkplatz stehen
	EnterRange = 12, -- Reichweite des Einsteigen-Prompts

	-- Raeder kollidieren mit dem Boden, aber nicht miteinander. Ohne eigene
	-- Gruppe verhaken sich zwei Autos, sobald sie sich beruehren.
	WheelCollisionGroup = "GhostNetWheels",

	-- Fahrwerk. Diese Zahlen bestimmen das Fahrgefuehl mehr als MaxSpeed.
	SuspensionLength = 2.2, -- Ruhelaenge der Feder
	SuspensionTravel = 1.1, -- wie weit sie ein- und ausfedern darf
	SuspensionDamping = 900, -- zu wenig = Wackelpudding, zu viel = Brett
	SteerSpeed = 6, -- wie schnell der Lenkeinschlag folgt (Grad/Tick-Faktor)
	SteerSpeedFalloff = 0.55, -- bei Tempo weniger Einschlag, sonst ueberschlaegt es

	WheelDensity = 0.4,
	CarrierDensity = 0.05, -- Radtraeger fast masselos, sonst schlingert es
	WheelFriction = 2.0,
	WheelElasticity = 0.1,

	-- Antriebsdrehmoment wird mit diesem Faktor auf die Raeder verteilt.
	TorqueScale = 1.0,
	BrakeTorqueScale = 1.6,

	--== FAHRGEFUEHL (Client) ==============================================
	-- Ohne das fuehlt sich kein Auto schnell an, egal wie hoch MaxSpeed steht.
	CameraFovBase = 70,
	CameraFovFast = 85,
	CameraFovLerp = 0.06,
	CameraDistanceBase = 18,
	CameraDistanceFast = 26,

	EngineVolume = 0.4,
	EnginePitchIdle = 0.8,
	EnginePitchMax = 2.4,

	SkidThreshold = 14, -- Seitwaertstempo, ab dem die Reifen quietschen
	SkidLifetime = 6, -- wie lange eine Bremsspur liegen bleibt
	SkidMaxMarks = 60, -- Obergrenze, sonst wachsen die Spuren endlos

	-- Schaden ist rein optisch: sichtbare Verfaerbung, keine Reparatur.
	-- Kostet fast nichts und wirkt stark.
	DamageEnabled = true,
	DamageSpeedThreshold = 55, -- ab diesem Aufpralltempo wird es sichtbar
	DamageMax = 1.0,
	DamagePerHit = 0.25,
}

--==========================================================================
-- 17. STADT UND STRASSENNETZ
-- Die Stadt wird aus Bezirken gebaut, jeder mit eigenem Charakter und
-- eigener Schwierigkeit. Die Strassenmittellinien sind gleichzeitig der
-- Graph, auf dem in Phase 3 der Verkehr und in Phase 6 die Polizei faehrt -
-- deshalb werden sie mitgebaut und nicht spaeter nachgezogen.
--==========================================================================
Config.City = {
	BlockSize = 120, -- Abstand zwischen zwei Strassenkreuzungen
	Grid = 5, -- Kreuzungen je Achse. 5 = 4x4 Bloecke. Hoch = riesige leere Stadt.
	RoadWidth = 34,
	LaneOffset = 8, -- Abstand der Fahrspur von der Strassenmitte
	SidewalkWidth = 8,
	-- Dicke der Fahrbahnplatte. Die Knoten liegen auf y = 0, die Platte ist
	-- um sie zentriert - die Oberkante liegt also bei RoadThickness / 2.
	-- Genau darauf setzen Verkehr und Streifenwagen auf; frueher stand da
	-- eine geratene 2.4 und die Autos hingen einen halben Stud im Boden.
	RoadThickness = 1,
	SidewalkThickness = 1.4,
	-- Wie viel hoeher die Gehwegkante als die Fahrbahn liegt. Fussgaenger
	-- rechnen damit, City baut damit - eine Zahl, zwei Nutzer.
	SidewalkLift = 0.5,

	BuildingMinHeight = 26,
	BuildingMaxHeight = 92,
	BuildingInset = 14, -- Abstand der Haeuser zur Strasse
	RoofAccessChance = 0.35, -- Anteil Haeuser mit Feuerleiter aufs Dach

	-- Wenige, dafuer starke Lichter. PointLight ist teuer, Neonflaechen sind
	-- gratis. Runterdrehen, wenn die Bildrate einbricht.
	SignChance = 0.4,
	LightChance = 0.25,
}

--==========================================================================
-- 18. VERKEHR UND FUSSGAENGER
-- Der performancekritischste Teil des Projekts. NIEDRIG starten und mit dem
-- MicroProfiler hochtasten - nicht raten.
--==========================================================================
Config.Traffic = {
	MaxActive = 20, -- harte Obergrenze fahrender Autos. Der wichtigste Regler.
	MaxPedestrians = 16,
	ActiveRadius = 320, -- ausserhalb davon wird angehalten und recycelt
	Tick = 0.1, -- Bewegungstakt. Groesser = ruckeliger, kleiner = teurer.
	SpawnTick = 2, -- wie oft nachgefuellt wird

	Speed = 34, -- Studs/s
	SpeedJitter = 8,
	StopDistance = 22, -- Abstand, ab dem hinter einem anderen gebremst wird
	PedestrianSpeed = 7,
	-- Nur die Groesse des magenta Platzhalters, solange
	-- Assets/Characters/Pedestrian fehlt.
	PedestrianSize = Vector3.new(1.8, 5.4, 1),

	-- Autodiebstahl. Haengt am Trace, damit er nicht neben der zentralen
	-- Risiko-Mechanik herlaeuft.
	-- Wie hoch ein Modell ueber der Fahrbahn schwebt. Die halbe Modellhoehe
	-- rechnet der Code aus (Model:GetExtentsSize), das hier ist nur der
	-- Rest-Spalt. Hoch = schwebt sichtbar, 0 = Raeder stecken in der Platte.
	GroundClearance = 0.15,

	-- Der Server setzt die CFrame nur alle Tick Sekunden (10x/s). Ohne
	-- Glaettung sieht das auf dem Client aus wie Ruckeln. Der Client zieht
	-- deshalb zwischen zwei Serverschritten weich nach.
	-- Zeitkonstante in Sekunden: hoch = butterweich, aber traege und der
	-- Wagen "haengt" hinter seiner echten Position. 0 = Glaettung aus.
	-- WICHTIG: das ist reine Optik. Alle Pruefungen (Diebstahl-Reichweite,
	-- Sicht der Polizei) laufen serverseitig gegen die echte Position.
	ClientSmoothing = 0.09,
	-- Ab diesem Sprung wird nicht mehr nachgezogen, sondern hart gesetzt.
	-- Sonst sieht man ein recyceltes Auto quer durch die Stadt gleiten.
	-- Muss groesser sein als die Strecke, die ein Auto in einem Tick macht.
	SnapDistance = 24,

	StealHoldSeconds = 2.5,
	StealTrace = 12,
	StealRange = 12,
}

--==========================================================================
-- 19. FAHRZEUGBESITZ UND HAENDLER
--==========================================================================
Config.Dealer = {
	OpenHour = 8, -- Haendler haben nur tagsueber auf
	CloseHour = 20,
	TestDriveSeconds = 45, -- Probefahrt auf abgesperrtem Gelaende
	ColourOptions = {
		"Schwarz", "Anthrazit", "Weiss", "Rot", "Cyan", "Gold",
	},
	-- Kosmetik kostet, damit Geld auch spaet noch einen Zweck hat.
	RepaintCost = 900,
}

--==========================================================================
-- 20. BANK
-- Drei Ebenen, drei Wege hinein. Die Wachen MELDEN, sie greifen nicht an -
-- das haelt die Mechanik bei Flucht statt Kampf.
--==========================================================================
Config.Bank = {
	GuardSightRange = 60,
	GuardSightAngle = 70, -- Halbwinkel des Sichtkegels in Grad
	GuardTick = 0.4, -- Sichtpruefung nur so oft, und nur wenn jemand im Raum ist
	GuardPatrolSpeed = 9,
	GuardSpotSeconds = 0.8, -- so lange muss man sichtbar sein, bevor Alarm kommt
	-- Wachen im Gebaeude sehen kuerzer als die Sichtweite draussen. Wird als
	-- Attribut "SightFactor" an die Wache geschrieben, siehe Config.Cover.
	-- Runter = drinnen wird zur sicheren Bank, hoch = die Halle wird zaeh.
	IndoorSightFactor = 0.7,

	VaultBoxes = 6, -- Schliessfaecher zusaetzlich zum Haupttresor
	BoxReward = 900,
	BoxCooldown = 1800,

	-- Der Weg ueber das Dach umgeht die Schalterhalle, braucht aber ein
	-- besseres Rig. Sonst waere er immer die beste Wahl.
	VentRequiredTier = 3,
}

--==========================================================================
-- 21. POLIZEI
-- Verfolgung statt Schiesserei. Kein Schusswechsel, keine Waffen.
--==========================================================================
Config.Pursuit = {
	MaxLevel = 5,
	-- Ab welchem Trace welche Fahndungsstufe. Runter = die Polizei ist
	-- staendig da, hoch = sie ist irrelevant.
	-- 20 ist kein Zufall: 20 * MaxLevel = 100 = Config.Trace.Max. Sonst waere
	-- die hoechste Stufe allein ueber den Trace nie erreichbar.
	TracePerLevel = 20,
	Decay = 0.15, -- Stufenabbau pro Sekunde ohne Sichtkontakt
	EscapeSeconds = 12, -- so lange ausser Sicht, dann ist man raus
	SpotRange = 220,
	CatchRange = 14, -- so nah heisst gefasst
	CatchSeconds = 2.5, -- und zwar so lange am Stueck

	UnitsPerLevel = 1, -- Streifenwagen je Stufe
	MaxUnits = 5,
	UnitSpeed = 46,

	-- Streifenwagen benutzt dieselbe Asset-Pipeline wie alles andere.
	-- Fehlt Assets/Vehicles/Police, steht dort ein magenta Platzhalter.
	UnitAsset = "Police",
	UnitSize = Vector3.new(6.4, 2.9, 13), -- nur Platzhaltergroesse
	LightBarSize = Vector3.new(1.6, 0.5, 1.2),
	LightBlue = Color3.fromRGB(40, 90, 255),
	LightRed = Color3.fromRGB(255, 40, 60),
	LightBrightness = 4,
	LightRange = 30,
	RoadblockLevel = 4,
	HelicopterLevel = 5,
	Tick = 0.25,
}

--==========================================================================
-- 22. ENDGAME-ENTSCHEIDUNG (Mission 10)
--==========================================================================
Config.Endgame = {
	-- "CASH"  = bei Meridian anheuern: halber Trace, aber weniger Beute.
	-- "BURN"  = alles veroeffentlichen: mehr Ertrag, haerteres Spiel.
	CashTraceFactor = 0.5,
	CashRewardFactor = 0.75,
	BurnRewardFactor = 1.3,
	BurnPursuitFactor = 1.4,
	BurnMarketFactor = 1.2,
	-- Einmal pro Woche umstellbar. Ohne das fuehlen sich Spieler eingesperrt
	-- und hoeren auf.
	SwitchCooldown = 604800,
}

--==========================================================================
-- 23. DECKUNG (ersetzt den alten Nachtbonus)
--
-- Frueher hing der Risiko-Bonus an der Uhrzeit: nachts mehr Ertrag, NPCs
-- sehen kuerzer. Seit die Stadt dauerhaft hell ist, haengt er am ORT.
--
--   Ein Ziel mit Attribut  Exposed = true  steht auf offener Strasse:
--   Schaufenster, Geldautomat am Gehweg, Kamera an der Fassade. Man sieht
--   den Spieler dort von weitem.
--     -> mehr Ertrag UND mehr Trace
--
--   Alles andere ist gedeckt: drinnen, im Hinterhof, auf dem Dach, im
--   Schacht. Sicherer, aber normal bezahlt - und man muss erst hinkommen.
--
-- Das ist derselbe Tausch wie frueher (mehr Geld gegen mehr Risiko), nur
-- trifft der Spieler die Entscheidung jetzt beim WOHIN statt beim WANN.
-- Ein Wann kann man aussitzen, ein Wohin nicht.
--==========================================================================
Config.Cover = {
	-- Hoch = offene Ziele lohnen deutlich, runter = die Deckung wird egal.
	ExposedRewardBonus = 0.35, -- +35 % auf offene Ziele
	-- Der Preis dafuer. Muss spuerbar sein, sonst ist "offen" gratis Geld.
	ExposedTraceFactor = 1.3,
	-- Sichtweite von Wachen. Eine Wache darf ueber ihr Attribut
	-- "SightFactor" davon abweichen (drinnen sieht man weniger weit).
	DefaultGuardSight = 1,
	MinGuardSight = 0.25, -- Untergrenze, damit eine Wache nie blind ist
}

--==========================================================================
-- 24. RATE-LIMITS (Token-Bucket pro Spieler und Remote)
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
	Trade = { Rate = 2, Burst = 5 },
	AdminCommand = { Rate = 4, Burst = 8 },
	StorePrompt = { Rate = 1, Burst = 3 },
	VehicleAction = { Rate = 1, Burst = 4 },
	StealVehicle = { Rate = 1, Burst = 2 },
	EndgameChoice = { Rate = 0.2, Burst = 2 },
}

--==========================================================================
-- 25. NODE-BREACH
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
-- 26. DEFAULTS FUER HACK-ZIELE
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
	-- Steht das Ziel auf offener Strasse? Siehe Config.Cover.
	-- false = gedeckt (drinnen, Hinterhof, Dach): normal bezahlt, sicherer.
	Exposed = false,
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
-- VORLAGEN (ReplicatedStorage/Assets)
--
-- Code platziert Geometrie, Code baut keine Geometrie. Alles Sichtbare liegt
-- als fertiges Modell unter ReplicatedStorage/Assets und wird geklont.
-- Fehlt eine Vorlage, entsteht ein magenta Platzhalter - siehe AssetLibrary.
--==========================================================================
Config.Assets = {
	FolderName = "Assets",

	-- Knallmagenta, damit man einen Platzhalter niemals uebersieht und
	-- niemals versehentlich veroeffentlicht. Bewusst NICHT aus der Palette:
	-- das hier ist kein Weltton, das ist eine Warnung.
	PlaceholderColour = Color3.fromRGB(255, 0, 200),
	PlaceholderTransparency = 0.15,
	PlaceholderLabels = true, -- Schrift ueber dem Platzhalter mit dem Namen
	PlaceholderLabelDistance = 260,

	--== Fahrzeuge =========================================================
	-- Teile, die ein Fahrzeugmodell tragen MUSS, damit VehicleChassis es
	-- verdrahten kann. Fehlt eines, gibt es eine klare Meldung mit
	-- Modellname und fehlendem Teil - keinen stillen Absturz.
	VehicleRequired = {
		"Chassis", -- unsichtbare Kollisionsbox, PrimaryPart
		"Body", -- sichtbare Karosserie
		"Wheels/FL",
		"Wheels/FR",
		"Wheels/RL",
		"Wheels/RR",
		"DriveSeat",
	},
	-- Zweiraeder: F vorne (gelenkt), R hinten (angetrieben).
	VehicleRequiredTwoWheel = {
		"Chassis",
		"Body",
		"Wheels/F",
		"Wheels/R",
		"DriveSeat",
	},
	-- Wie gross die Platzhalter-Karosserie im Verhaeltnis zur Kollisionsbox
	-- ist. Etwas kleiner, damit man den Unterschied sieht.
	PlaceholderBodyScale = 0.92,
	-- Nice-to-have. Fehlen sie, faehrt das Auto trotzdem.
	VehicleOptional = {
		"Glass",
		"Lights/HeadL",
		"Lights/HeadR",
		"Lights/TailL",
		"Lights/TailR",
	},

	--== Gebaeudebaukasten =================================================
	-- Module werden gestapelt: Sockel -> n x Etage -> Dach. Alle Module
	-- haben dieselbe Grundflaeche und eine feste Hoehe, sonst passt der
	-- Stapel nicht. Aus acht Modulen entstehen hunderte Haeuser.
	BuildingFootprint = 28, -- Kantenlaenge eines Moduls in Studs
	BaseHeight = 14, -- Hoehe eines Sockelmoduls
	FloorHeight = 11, -- Hoehe einer Standardetage
	RoofHeight = 4, -- Hoehe des Dachabschlusses
	RoofOverhang = 1.2, -- wie weit die Dachkante uebersteht. 0 = Klotz.

	Bases = { "Base_Shop", "Base_Entry", "Base_Garage" },
	Floors = { "Floor_A", "Floor_B", "Floor_C" },
	Roofs = { "Roof_Flat", "Roof_Tech" },

	-- Wie hoch gestapelt wird. Hoch = Schluchten, runter = Vorstadt.
	MinFloors = 2,
	MaxFloors = 7,
	-- Wie viel dunkler der Sockel ist. 0 = kein Absatz, 1 = fast schwarz.
	BaseDarken = 0.45,
	-- Kein Raster: jedes Haus etwas versetzt und leicht gedreht. Ohne das
	-- sieht die Strasse nach Computer aus, und das faellt sofort auf.
	BuildingJitter = 2.5, -- Studs
	BuildingYaw = 4, -- Grad

	-- Feuerleiter aufs Dach. Ohne die ist ein begehbares Dach nur Deko -
	-- und "von oben" ist im Bankraub ein echter Weg.
	RoofAccess = "Feuerleiter",
	RoofAccessChance = 0.35,
	RoofAccessSize = Vector3.new(2.6, 1, 1.2),
	RoofAccessStep = 4, -- Abstand der Sprossen in Studs

	--== Strassenmoeblierung ===============================================
	-- Eine leere Strasse mit perfekten Haeusern wirkt tot, eine
	-- durchschnittliche Strasse mit Kram darauf wirkt echt.
	Props = { "Laterne", "Ampel", "Muelltonne", "Poller", "Verteiler", "Schild" },
	PropSize = Vector3.new(1.6, 8, 1.6), -- Platzhaltergroesse
	PropSpacing = 26, -- Abstand entlang des Gehwegs
	PropChance = 0.55, -- Anteil der Plaetze, die belegt werden
	PropJitter = 3, -- zufaellige Verschiebung, damit nichts im Raster steht

	Characters = { "Pedestrian", "Guard" },
}

--==========================================================================
-- WELT-FARBEN (Vantorra bei Tag)
--
-- Zwei getrennte Paletten, und das mit Absicht:
--   Config.Palette  = die STADT. Hell, echte Baumaterialien.
--   Config.Theme    = das FAKE-OS in den Fenstern. Bleibt dunkel.
-- Der Kontrast ist der Witz: draussen heller Tag, im Terminal schwarzes
-- Bild mit Cyan. Wer die Stadt umfaerbt, faellt hier an EINER Stelle an.
--
-- Zum Abdunkeln der ganzen Stadt reicht es, diese Werte zu senken - kein
-- World-Skript enthaelt noch eine eigene Farbe.
--==========================================================================
Config.Palette = {
	--== Strasse ==========================================================
	Asphalt = Color3.fromRGB(112, 114, 120),
	Gehweg = Color3.fromRGB(182, 180, 174),
	Markierung = Color3.fromRGB(240, 232, 178),

	--== Gebaeude von aussen ==============================================
	BetonHell = Color3.fromRGB(206, 202, 194),
	Beton = Color3.fromRGB(172, 168, 160),
	BetonDunkel = Color3.fromRGB(126, 123, 118),
	Putz = Color3.fromRGB(216, 200, 172), -- warmer Altbau-Putz
	Ziegel = Color3.fromRGB(172, 112, 92),
	Dach = Color3.fromRGB(138, 136, 132),

	--== Bauteile =========================================================
	Metall = Color3.fromRGB(164, 168, 174),
	MetallDunkel = Color3.fromRGB(108, 112, 120),
	Glas = Color3.fromRGB(190, 212, 226),
	Holz = Color3.fromRGB(158, 118, 82),

	--== Innenraeume ======================================================
	-- Heller als frueher, aber merklich kuehler und matter als draussen:
	-- drinnen ist Deckung, und Deckung soll man sehen koennen.
	InnenBoden = Color3.fromRGB(146, 144, 148),
	InnenWand = Color3.fromRGB(178, 176, 178),
	InnenDecke = Color3.fromRGB(158, 157, 160),

	Haut = Color3.fromRGB(214, 176, 152), -- Wachen-Koepfe
}

table.freeze(Config.Palette)

--==========================================================================
-- UI-FARBEN (Fake-OS) - bleibt dunkel, siehe oben
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
