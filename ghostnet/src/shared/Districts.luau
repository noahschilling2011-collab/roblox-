-- ReplicatedStorage/Shared/Districts.luau
--!strict
-- GHOSTNET :: Die Bezirke von Vantorra.
--
-- LEITREGEL AUS DEM BAUPLAN
--   Erst EIN Bezirk fertig und dicht, dann der naechste. Eine grosse leere
--   Stadt ist schlimmer als ein kleiner voller Block. Deshalb hat jeder
--   Bezirk hier eine "Dense"-Angabe: nur die dichten werden voll ausgebaut,
--   die anderen bleiben Rohbau, bis sie dran sind.
--
-- Bezirke sind Daten. Ein neuer Stadtteil = ein Eintrag, kein neues Skript.

local Districts = {}

export type District = {
	Id: string,
	Name: string,
	Character: string,
	-- Mittelpunkt in Gitterkoordinaten (Kreuzungen), nicht in Studs.
	GridX: number,
	GridZ: number,
	Radius: number, -- in Bloecken
	MinDifficulty: number,
	MaxDifficulty: number,
	-- Grundton der Haeuser. Vantorra ist eine HELLE Stadt bei Tag - diese
	-- Werte liegen deshalb im Bereich echter Baumaterialien und nicht mehr
	-- knapp ueber Schwarz. Wer die Stadt abdunkeln will, aendert sie hier
	-- und in Config.Palette, sonst nirgends.
	Tint: Color3,
	Neon: Color3, -- Leitfarbe der Schilder (bleibt kraeftig, auch bei Tag)
	Dense: boolean, -- true = voll ausgebaut
}

Districts.List = {
	{
		Id = "OLDTOWN",
		Name = "Altstadt",
		Character = "Enge Gassen, Putzfassaden, Marktstaende.",
		GridX = 0,
		GridZ = 0,
		Radius = 1,
		MinDifficulty = 1,
		MaxDifficulty = 3,
		Tint = Color3.fromRGB(214, 196, 168), -- warmer Altbau-Putz
		Neon = Color3.fromRGB(255, 45, 149),
		Dense = true, -- der erste fertige Bezirk
	},
	{
		Id = "DOCKS",
		Name = "Hafen",
		Character = "Container, Lagerhallen, kaum Deckung.",
		GridX = -2,
		GridZ = 1,
		Radius = 1,
		MinDifficulty = 3,
		MaxDifficulty = 5,
		Tint = Color3.fromRGB(154, 162, 168), -- verwitterter Beton, Stahlgrau
		Neon = Color3.fromRGB(0, 229, 255),
		Dense = false,
	},
	{
		Id = "FINANCE",
		Name = "Finanzviertel",
		Character = "Glas, Kameras ueberall, alles einsehbar.",
		GridX = 2,
		GridZ = -1,
		Radius = 1,
		MinDifficulty = 5,
		MaxDifficulty = 7,
		Tint = Color3.fromRGB(190, 206, 220), -- Glasfassade, kuehl
		Neon = Color3.fromRGB(198, 214, 226),
		Dense = false,
	},
	{
		Id = "HEIGHTS",
		Name = "Hoehenzug",
		Character = "Villen, Serpentinen, wenig Verkehr.",
		GridX = 1,
		GridZ = 2,
		Radius = 1,
		MinDifficulty = 6,
		MaxDifficulty = 8,
		Tint = Color3.fromRGB(208, 192, 164), -- Sandstein, Villenputz
		Neon = Color3.fromRGB(255, 176, 0),
		Dense = false,
	},
	{
		Id = "INDUSTRY",
		Name = "Industriegebiet",
		Character = "Weite Flaechen, Zaeune.",
		GridX = -1,
		GridZ = -2,
		Radius = 1,
		MinDifficulty = 4,
		MaxDifficulty = 6,
		Tint = Color3.fromRGB(168, 160, 150), -- Betonplatten, Blechhallen
		Neon = Color3.fromRGB(0, 230, 118),
		Dense = false,
	},
} :: { District }

--==========================================================================

function Districts.Get(id: string): District?
	for _, district in Districts.List do
		if district.Id == id then
			return district
		end
	end
	return nil
end

function Districts.Count(): number
	return #Districts.List
end

-- Welcher Bezirk liegt auf diesen Gitterkoordinaten? nil = Niemandsland.
function Districts.At(gridX: number, gridZ: number): District?
	local best: District? = nil
	local bestDistance = math.huge
	for _, district in Districts.List do
		local dx = gridX - district.GridX
		local dz = gridZ - district.GridZ
		local distance = math.max(math.abs(dx), math.abs(dz))
		if distance <= district.Radius and distance < bestDistance then
			best, bestDistance = district, distance
		end
	end
	return best
end

function Districts.Validate(list: { District }?): (boolean, { string })
	local districts = list or Districts.List
	local errors: { string } = {}
	local seen: { [string]: boolean } = {}
	local occupied: { [string]: string } = {}

	for _, district in districts do
		local label = if typeof(district.Id) == "string" and district.Id ~= "" then district.Id else "#?"

		if typeof(district.Id) ~= "string" or district.Id == "" then
			table.insert(errors, "Id fehlt")
		elseif seen[district.Id] then
			table.insert(errors, ("%s: Id doppelt vergeben"):format(label))
		else
			seen[district.Id] = true
		end

		if typeof(district.Name) ~= "string" or district.Name == "" then
			table.insert(errors, ("%s: Name fehlt"):format(label))
		end
		if district.MinDifficulty < 1 or district.MaxDifficulty > 10 then
			table.insert(errors, ("%s: Schwierigkeit ausserhalb 1-10"):format(label))
		end
		if district.MinDifficulty > district.MaxDifficulty then
			table.insert(errors, ("%s: Min groesser als Max"):format(label))
		end
		if district.Radius < 1 then
			table.insert(errors, ("%s: Radius unter 1"):format(label))
		end

		-- Zwei Bezirke duerfen nicht auf demselben Block liegen, sonst
		-- ueberschreibt einer den anderen beim Bauen.
		local key = ("%d,%d"):format(district.GridX, district.GridZ)
		if occupied[key] then
			table.insert(errors, ("%s ueberlappt %s"):format(label, occupied[key]))
		else
			occupied[key] = label
		end
	end

	-- Genau ein dichter Bezirk zum Start: mehr gleichzeitig anzufangen ist
	-- laut Bauplan ausdruecklich verboten.
	local dense = 0
	for _, district in districts do
		if district.Dense then
			dense += 1
		end
	end
	if dense == 0 then
		table.insert(errors, "kein einziger Bezirk ist ausgebaut")
	end

	return #errors == 0, errors
end

return Districts
