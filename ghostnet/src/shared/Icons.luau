-- ReplicatedStorage/Shared/Icons.luau
--!strict
-- GHOSTNET :: Ein Symbol je Bedeutung, ueberall dasselbe.
--
-- WARUM AUS FRAMES UND NICHT AUS BILDERN
--   Ein ImageLabel braucht eine hochgeladene Asset-Id. Die gibt es hier
--   nicht, und erfinden darf man sie nicht. Also werden die Symbole aus
--   wenigen Frames zusammengesetzt: ein Haus sind zwei Rechtecke, ein Stern
--   sind zwei gedrehte Quadrate. Das kostet ein paar Instanzen und ist
--   dafuer sofort da, ohne dass jemand etwas eintragen muss.
--
-- WARUM ZENTRAL
--   Dasselbe Symbol taucht auf der Minikarte, auf der grossen Karte, in der
--   Legende und auf der Kompassleiste auf. Vier Orte, an denen ein Haus wie
--   ein Haus aussehen muss - also wird es genau einmal beschrieben.
--
-- Jede Form zeichnet sich in ein Quadrat der Kantenlaenge `size` und faerbt
-- sich in `colour`. Der Aufrufer setzt Position und ZIndex am Rueckgabewert.

local Icons = {}

export type Shape = "Haus" | "Schein" | "Schluessel" | "Tresor" | "Chip" | "Stern" | "Auto" | "Schild" | "Punkt"

local function piece(parent: Frame, colour: Color3, x: number, y: number, w: number, h: number, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Alles in Anteilen der Kantenlaenge, damit dieselbe Form in jeder
	-- Groesse funktioniert - Minikarte, Legende und Kompass sind verschieden.
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
	f.ZIndex = parent.ZIndex + 1
	f.Parent = parent
	return f
end

local function round(frame: Frame, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = frame
end

--==========================================================================
-- Die Formen
--==========================================================================

local shapes: { [string]: (Frame, Color3) -> () } = {}

-- Haus: Wand plus gekipptes Quadrat als Dach.
shapes.Haus = function(root: Frame, colour: Color3)
	piece(root, colour, 0.5, 0.66, 0.62, 0.46)
	piece(root, colour, 0.5, 0.34, 0.5, 0.5, 45)
end

-- Geldschein: liegendes Rechteck mit heller Mitte.
shapes.Schein = function(root: Frame, colour: Color3)
	piece(root, colour, 0.5, 0.5, 0.92, 0.56)
	local hole = piece(root, colour, 0.5, 0.5, 0.24, 0.3)
	hole.BackgroundTransparency = 0.75
	round(hole, 0.5)
end

-- Schluessel: Ring plus Bart.
shapes.Schluessel = function(root: Frame, colour: Color3)
	local ring = piece(root, colour, 0.3, 0.5, 0.44, 0.44)
	round(ring, 0.5)
	piece(root, colour, 0.66, 0.5, 0.5, 0.16)
	piece(root, colour, 0.82, 0.64, 0.14, 0.28)
end

-- Tresor: Kasten mit Griffrad.
shapes.Tresor = function(root: Frame, colour: Color3)
	local box = piece(root, colour, 0.5, 0.5, 0.86, 0.86)
	round(box, 0.12)
	local dial = piece(root, colour, 0.5, 0.5, 0.34, 0.34)
	dial.BackgroundTransparency = 0.7
	round(dial, 0.5)
end

-- Chip: Quadrat mit Beinchen links und rechts.
shapes.Chip = function(root: Frame, colour: Color3)
	piece(root, colour, 0.5, 0.5, 0.56, 0.56)
	for _, y in { 0.32, 0.5, 0.68 } do
		piece(root, colour, 0.16, y, 0.2, 0.09)
		piece(root, colour, 0.84, y, 0.2, 0.09)
	end
end

-- Stern: zwei gekippte Quadrate uebereinander.
shapes.Stern = function(root: Frame, colour: Color3)
	piece(root, colour, 0.5, 0.5, 0.58, 0.58, 45)
	piece(root, colour, 0.5, 0.5, 0.5, 0.5, 0)
end

-- Auto: Karosserie, Dach, zwei Raeder.
shapes.Auto = function(root: Frame, colour: Color3)
	local body = piece(root, colour, 0.5, 0.54, 0.92, 0.34)
	round(body, 0.25)
	local roof = piece(root, colour, 0.5, 0.32, 0.5, 0.26)
	round(roof, 0.3)
	local left = piece(root, colour, 0.27, 0.78, 0.22, 0.22)
	round(left, 0.5)
	local right = piece(root, colour, 0.73, 0.78, 0.22, 0.22)
	round(right, 0.5)
end

-- Schild: oben eckig, unten spitz - ein gekipptes Quadrat unter einem Kasten.
shapes.Schild = function(root: Frame, colour: Color3)
	piece(root, colour, 0.5, 0.4, 0.72, 0.5)
	piece(root, colour, 0.5, 0.68, 0.5, 0.5, 45)
end

shapes.Punkt = function(root: Frame, colour: Color3)
	local dot = piece(root, colour, 0.5, 0.5, 0.8, 0.8)
	round(dot, 0.5)
end

--==========================================================================

function Icons.Has(shape: string): boolean
	return shapes[shape] ~= nil
end

-- Baut das Symbol und gibt den Container zurueck. Der Aufrufer setzt
-- Position, Groesse in Pixeln und ZIndex.
function Icons.Build(shape: string, colour: Color3, size: number): Frame
	local root = Instance.new("Frame")
	root.Name = shape
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(size, size)
	root.ZIndex = 1

	local draw = shapes[shape] or shapes.Punkt
	draw(root, colour)
	return root
end

-- Faerbt ein bestehendes Symbol um, ohne es neu zu bauen. Wird gebraucht,
-- wenn ein Marker blinken oder verblassen soll.
function Icons.Recolour(root: Frame, colour: Color3)
	for _, child in root:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundColor3 = colour
		end
	end
end

function Icons.SetTransparency(root: Frame, transparency: number)
	for _, child in root:GetChildren() do
		if child:IsA("Frame") then
			child.BackgroundTransparency = transparency
		end
	end
end

return Icons
