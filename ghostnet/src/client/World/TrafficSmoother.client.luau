-- StarterPlayerScripts/World/TrafficSmoother.client.luau
--!strict
-- GHOSTNET :: Weiches Nachziehen fuer servergesetzte Modelle.
--
-- DAS PROBLEM
--   Verkehr, Fussgaenger und Streifenwagen sind Anchored. Der Server setzt
--   ihre CFrame nur alle Config.Traffic.Tick Sekunden (10x/s) - haeufiger
--   waere zu teuer. Auf dem Client kommt das als Sprung alle 100 ms an, und
--   das sieht aus, als waere das Spiel kaputt. Nicht langsam: kaputt.
--
-- DIE LOESUNG
--   Der Server bleibt bei 10 Schritten pro Sekunde. Dieser Client zieht die
--   Modelle dazwischen weich nach. Kostet fast nichts und ist der
--   Unterschied zwischen "ruckelt" und "faehrt".
--
-- DAS IST REINE OPTIK
--   Der Client verschiebt die Modelle nur lokal. Jede Pruefung, die zaehlt -
--   Diebstahl-Reichweite, Sichtlinie der Wachen, Fassen durch die Polizei -
--   laeuft serverseitig gegen die echte Position. Wer hier manipuliert,
--   verschiebt ein Bild und sonst nichts.
--
-- KEINE SIGNALE, SONDERN VERGLEICH
--   Naheliegend waere GetPropertyChangedSignal("CFrame"). Damit faengt man
--   sich aber die eigenen Schreibvorgaenge wieder ein, und ob das Signal
--   sofort oder verzoegert feuert, haengt an SignalBehavior. Stattdessen
--   merkt sich der Client, was er selbst zuletzt geschrieben hat: weicht die
--   aktuelle CFrame davon ab, kam sie vom Server. Kein Timing-Verlass.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local SMOOTHING = Config.Traffic.ClientSmoothing

type Entry = {
	Model: Model,
	Pivot: BasePart,
	Target: CFrame, -- wohin der Server das Modell gestellt hat
	Shown: CFrame, -- wo es gerade gezeichnet wird
	Written: CFrame, -- was dieser Client zuletzt selbst geschrieben hat
}

local entries: { [Model]: Entry } = {}

--==========================================================================

-- Gleich genug? Fliesskomma-Rundung beim Replizieren darf nicht als
-- "der Server hat etwas Neues geschickt" durchgehen.
local function samePosition(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 0.01
		and a.LookVector:Dot(b.LookVector) > 0.9999
end

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local pivot = instance.PrimaryPart
	if not pivot then
		-- Ohne PrimaryPart nimmt PivotTo den Mittelpunkt der Bounding-Box.
		-- Das geht nicht schief, es sieht nur falsch aus - deshalb laut sein.
		warn(("[GHOSTNET] %s ist als geglaettet markiert, hat aber keinen PrimaryPart."):format(instance:GetFullName()))
		return
	end
	local now = instance:GetPivot()
	entries[instance] = {
		Model = instance,
		Pivot = pivot,
		Target = now,
		Shown = now,
		Written = now,
	}
end

local function untrack(instance: Instance)
	if instance:IsA("Model") then
		entries[instance] = nil
	end
end

--==========================================================================

local function step(deltaTime: number)
	-- Exponentielle Annaeherung statt fester Schrittweite: unabhaengig von
	-- der Bildrate landet man immer gleich schnell am Ziel.
	local alpha = 1 - math.exp(-deltaTime / SMOOTHING)

	for model, entry in entries do
		if not model.Parent or not entry.Pivot.Parent then
			entries[model] = nil
			continue
		end

		local current = entry.Pivot.CFrame
		if not samePosition(current, entry.Written) then
			-- Weicht von dem ab, was wir selbst geschrieben haben: das kam
			-- ueber die Replikation vom Server.
			entry.Target = model:GetPivot()
		end

		-- Grosser Sprung = das Modell wurde neu eingesetzt (Pool!) oder ist
		-- ueber die halbe Stadt gesprungen. Dann nicht hinterherfahren,
		-- sondern hart setzen - sonst sieht man es durch die Stadt gleiten.
		if (entry.Target.Position - entry.Shown.Position).Magnitude > Config.Traffic.SnapDistance then
			entry.Shown = entry.Target
		else
			entry.Shown = entry.Shown:Lerp(entry.Target, alpha)
		end

		model:PivotTo(entry.Shown)
		entry.Written = entry.Shown
	end
end

--==========================================================================

if SMOOTHING > 0 then
	for _, instance in CollectionService:GetTagged(Config.SmoothTag) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.SmoothTag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Config.SmoothTag):Connect(untrack)

	RunService.RenderStepped:Connect(step)
end
