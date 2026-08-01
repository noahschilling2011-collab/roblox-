-- ReplicatedStorage/Shared/AssetLibrary.luau
--!strict
-- GHOSTNET :: Vorlagen nachschlagen, klonen, Fehlendes sichtbar machen.
--
-- DIE REGEL, DIE DIESES MODUL DURCHSETZT
--   Code PLATZIERT Geometrie. Code BAUT keine Geometrie.
--   Alles, was ein Spieler bewusst ansieht - Autos, Haeuser, Menschen,
--   Strassenmoeblierung - liegt als fertiges Modell unter
--   ReplicatedStorage/Assets und wird von hier geklont.
--
--   Prozedural bleibt nur, wo Genauigkeit statt Aussehen zaehlt:
--   Strassenverlauf, Kollisionsboxen, unsichtbare Trigger, Wegpunkte.
--
-- WAS PASSIERT, WENN EINE VORLAGE FEHLT
--   Nichts wird "ersatzweise nachgebaut". Stattdessen entsteht ein
--   knallmagenta Platzhalter mit dem Namen MISSING_ASSET_<Kategorie>_<Name>,
--   in der richtigen Groesse, damit die Stadt begehbar und testbar bleibt.
--   Jeder fehlende Name landet in AssetLibrary.Missing() und wird beim
--   Serverstart einmal gesammelt ausgegeben.
--
--   Magenta ist Absicht: einen Platzhalter darf man nicht uebersehen und
--   schon gar nicht versehentlich veroeffentlichen.
--
-- ORDNERAUFBAU
--   ReplicatedStorage/Assets/
--       Vehicles/    Compact, Sedan, Sports, Van, Bike, Police
--       Buildings/   Base_*, Floor_*, Roof_*
--       Props/       Laterne, Ampel, Muelltonne, Poller, Verteiler, Schild
--       Characters/  Pedestrian, Guard
--
--   Fehlt der ganze Ordner, laeuft das Spiel trotzdem - eben magenta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local AssetLibrary = {}

local A = Config.Assets

-- Was gefehlt hat, jeweils nur einmal. Sonst spammt eine fehlende Vorlage
-- die Ausgabe mit hunderten Zeilen zu, sobald die Stadt gebaut wird.
local missing: { [string]: boolean } = {}
local missingOrder: { string } = {}

local function noteMissing(label: string)
	if missing[label] then
		return
	end
	missing[label] = true
	table.insert(missingOrder, label)
end

--==========================================================================
-- Nachschlagen
--==========================================================================

local function assetsFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(A.FolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

-- Die Vorlage selbst. NICHT veraendern und NICHT ins Workspace haengen -
-- dafuer gibt es Clone.
function AssetLibrary.Get(category: string, name: string): Model?
	local root = assetsFolder()
	if not root then
		return nil
	end
	local group = root:FindFirstChild(category)
	if not group then
		return nil
	end
	local template = group:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

function AssetLibrary.Has(category: string, name: string): boolean
	return AssetLibrary.Get(category, name) ~= nil
end

--==========================================================================
-- Platzhalter
--==========================================================================

-- Ein Klotz, der nicht so tut, als waere er fertig. Richtige Groesse, damit
-- Kollision, Wegfindung und Bildrate schon stimmen; magenta, damit klar ist,
-- dass hier noch ein Modell hingehoert.
function AssetLibrary.Placeholder(category: string, name: string, size: Vector3): Model
	local label = ("%s/%s"):format(category, name)
	noteMissing(label)

	local model = Instance.new("Model")
	model.Name = ("MISSING_ASSET_%s_%s"):format(category, name)

	local block = Instance.new("Part")
	block.Name = "Platzhalter"
	block.Size = size
	block.Color = A.PlaceholderColour
	block.Material = Enum.Material.SmoothPlastic
	block.Transparency = A.PlaceholderTransparency
	block.Anchored = true
	block.CanCollide = true
	block.CanQuery = false
	block.CanTouch = false
	block.TopSurface = Enum.SurfaceType.Smooth
	block.BottomSurface = Enum.SurfaceType.Smooth
	block.Parent = model
	model.PrimaryPart = block

	if A.PlaceholderLabels then
		local gui = Instance.new("BillboardGui")
		gui.Name = "FehltNoch"
		gui.Size = UDim2.fromOffset(220, 28)
		gui.StudsOffsetWorldSpace = Vector3.new(0, size.Y * 0.5 + 2, 0)
		gui.MaxDistance = A.PlaceholderLabelDistance

		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Code
		text.Text = label
		text.TextColor3 = A.PlaceholderColour
		text.TextSize = 14
		text.Size = UDim2.fromScale(1, 1)
		text.Parent = gui

		gui.Parent = block
	end

	model:SetAttribute("Placeholder", true)
	return model
end

--==========================================================================
-- Klonen
--==========================================================================

-- Der Normalfall. Gibt es die Vorlage, kommt ein Klon; gibt es sie nicht,
-- kommt ein Platzhalter in der uebergebenen Groesse. Der Aufrufer muss sich
-- nie mit dem Unterschied befassen - er stellt das Ergebnis einfach hin.
function AssetLibrary.Clone(category: string, name: string, fallbackSize: Vector3): Model
	local template = AssetLibrary.Get(category, name)
	if not template then
		return AssetLibrary.Placeholder(category, name, fallbackSize)
	end

	local clone = template:Clone()
	if not clone.PrimaryPart then
		-- Ohne PrimaryPart nimmt PivotTo den Mittelpunkt der Bounding-Box.
		-- Das wirft keinen Fehler, das Modell steht dann nur schief oder im
		-- Boden. Genau deshalb hier laut werden statt still weitermachen.
		warn(("[GHOSTNET] Vorlage %s/%s hat keinen PrimaryPart gesetzt."):format(category, name))
	end
	return clone
end

--==========================================================================
-- Vertrag pruefen
--
-- Ein Fahrzeugmodell muss bestimmte Teile mit bestimmten Namen enthalten,
-- sonst kann VehicleChassis es nicht verdrahten. Faellt das erst beim
-- Fahren auf, sucht man lange. Also vorher pruefen und klar sagen, WAS in
-- WELCHEM Modell fehlt.
--==========================================================================

-- Sucht "Wheels/FL" auch ueber mehrere Ebenen.
function AssetLibrary.Find(model: Model, path: string): Instance?
	local current: Instance = model
	for segment in string.gmatch(path, "[^/]+") do
		local nextInstance = current:FindFirstChild(segment)
		if not nextInstance then
			return nil
		end
		current = nextInstance
	end
	return current
end

-- Gibt zurueck: alles da? und die Liste dessen, was fehlt.
function AssetLibrary.Verify(model: Model, required: { string }): (boolean, { string })
	local gaps: { string } = {}
	for _, path in required do
		if not AssetLibrary.Find(model, path) then
			table.insert(gaps, path)
		end
	end
	return #gaps == 0, gaps
end

--==========================================================================
-- Bericht
--==========================================================================

function AssetLibrary.Missing(): { string }
	return table.clone(missingOrder)
end

-- Einmal beim Serverstart aufrufen. Sagt Noah in einer Zeile pro Modell,
-- was noch zu bauen oder zu besorgen ist.
function AssetLibrary.Report()
	if #missingOrder == 0 then
		print("[GHOSTNET] Alle Vorlagen gefunden.")
		return
	end
	warn(("[GHOSTNET] %d Vorlage(n) fehlen - im Spiel stehen dafuer magenta Platzhalter:"):format(#missingOrder))
	for _, label in missingOrder do
		warn(("            ReplicatedStorage/%s/%s"):format(A.FolderName, label))
	end
	warn("            Solange sie fehlen, sieht die Stadt absichtlich kaputt aus.")
end

return AssetLibrary
