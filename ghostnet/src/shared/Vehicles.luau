-- ReplicatedStorage/Shared/Vehicles.luau
--!strict
-- GHOSTNET :: Fahrzeugklassen als Daten.
--
-- LEITREGEL AUS DEM BAUPLAN
--   Jede Klasse muss einen MECHANISCHEN Grund haben, gefahren zu werden.
--   Ein Auto, das nur schneller ist, macht alle anderen wertlos. Deshalb hat
--   hier jede Klasse genau eine Sache, die sie besser kann als alle anderen -
--   und mindestens eine, die sie schlechter kann.
--
--   Kompakt   billig und unauffaellig  -> weniger Polizei-Aufmerksamkeit
--   Limousine beste Strassenlage       -> bricht als einzige nicht aus
--   Sportwagen schnell                 -> faellt auf, hoher Fahndungszuschlag
--   Van       Lager                    -> traege, aber transportiert Ware
--   Motorrad  wendig                   -> kommt durch Gassen, kein Lager
--
-- Ein Fahrzeug ist wie alles andere in diesem Spiel ein Datensatz. Ein neues
-- Modell = ein Eintrag hier, kein neues Skript.

local Vehicles = {}

export type VehicleClass = {
	Id: string,
	Name: string,
	Blurb: string,
	Price: number, -- Kaufpreis beim Haendler (Phase 4)

	-- Fahrwerte. Alles, was hier fehlt, kommt aus Config.Vehicle.Defaults.
	MaxSpeed: number, -- Studs/s
	Acceleration: number, -- Drehmoment der Antriebsraeder
	BrakeForce: number,
	TurnAngle: number, -- maximaler Lenkeinschlag in Grad
	SuspensionStiffness: number,
	Mass: number, -- Dichte der Karosserie
	Grip: number, -- Reibung der Reifen

	-- Name der Vorlage unter ReplicatedStorage/Assets/Vehicles.
	-- Die Zuordnung steht als Daten hier und wird nicht aus der Id geraten.
	Asset: string,

	-- Masse. Seit der Asset-Pipeline ist das NICHT mehr die Bauanleitung,
	-- sondern nur noch die Groesse des magenta Platzhalters, solange die
	-- Vorlage fehlt - plus die Werte, die der Client fuer Tacho und
	-- Kamera braucht.
	BodySize: Vector3,
	WheelRadius: number,
	WheelWidth: number,
	Wheels: number, -- 2 = Motorrad, 4 = Auto
	Colour: Color3,

	-- Der mechanische Grund, diese Klasse zu fahren.
	StashBonus: number, -- zusaetzlicher Darknet-Lagerplatz im Fahrzeug
	HeatFactor: number, -- 1.0 = normal. Kleiner = unauffaelliger.
}

Vehicles.List = {
	{
		Id = "COMPACT",
		Asset = "Compact",
		Name = "Kompakt",
		Blurb = "Billig, langsam, faellt niemandem auf.",
		Price = 2500,
		MaxSpeed = 62,
		Acceleration = 5200,
		BrakeForce = 7000,
		TurnAngle = 32,
		SuspensionStiffness = 16000,
		Mass = 0.7,
		Grip = 1.6,
		BodySize = Vector3.new(6, 2.6, 11),
		WheelRadius = 1.5,
		WheelWidth = 1.2,
		Wheels = 4,
		Colour = Color3.fromRGB(96, 104, 118),
		StashBonus = 0,
		HeatFactor = 0.7, -- der Grund fuer diese Klasse
	},
	{
		Id = "SEDAN",
		Asset = "Sedan",
		Name = "Limousine",
		Blurb = "Klebt auf der Strasse. Kein Tempowunder, aber nichts bricht aus.",
		Price = 7500,
		MaxSpeed = 78,
		Acceleration = 7000,
		BrakeForce = 9000,
		TurnAngle = 30,
		SuspensionStiffness = 19000,
		Mass = 0.85,
		Grip = 2.4, -- der Grund fuer diese Klasse: beste Strassenlage
		BodySize = Vector3.new(6.4, 2.8, 13),
		WheelRadius = 1.6,
		WheelWidth = 1.3,
		Wheels = 4,
		Colour = Color3.fromRGB(38, 44, 58),
		StashBonus = 2,
		HeatFactor = 1.0,
	},
	{
		Id = "SPORT",
		Asset = "Sports",
		Name = "Sportwagen",
		Blurb = "Schnell und laut. Die Polizei liebt dich dafuer.",
		Price = 34000,
		MaxSpeed = 118,
		Acceleration = 11500,
		BrakeForce = 13000,
		TurnAngle = 27,
		SuspensionStiffness = 26000,
		Mass = 0.8,
		Grip = 2.05, -- schnell, aber zickiger als die Limousine
		BodySize = Vector3.new(6.6, 2.1, 13.5),
		WheelRadius = 1.6,
		WheelWidth = 1.6,
		Wheels = 4,
		Colour = Color3.fromRGB(180, 32, 74),
		StashBonus = 0,
		HeatFactor = 1.6, -- der Preis fuer das Tempo
	},
	{
		Id = "VAN",
		Asset = "Van",
		Name = "Transporter",
		Blurb = "Traege, aber es passt richtig was rein.",
		Price = 16000,
		MaxSpeed = 66,
		Acceleration = 8200,
		BrakeForce = 10000,
		TurnAngle = 26,
		SuspensionStiffness = 22000,
		Mass = 1.2,
		Grip = 1.7,
		BodySize = Vector3.new(7, 5, 15),
		WheelRadius = 1.8,
		WheelWidth = 1.4,
		Wheels = 4,
		Colour = Color3.fromRGB(70, 74, 80),
		StashBonus = 10, -- der Grund fuer diese Klasse
		HeatFactor = 0.9,
	},
	{
		Id = "BIKE",
		Asset = "Bike",
		Name = "Motorrad",
		Blurb = "Passt durch jede Gasse. Platz fuer nichts.",
		Price = 11000,
		MaxSpeed = 96,
		Acceleration = 6800,
		BrakeForce = 6500,
		TurnAngle = 38,
		SuspensionStiffness = 14000,
		Mass = 0.45,
		Grip = 1.9,
		BodySize = Vector3.new(2.2, 2, 8),
		WheelRadius = 1.5,
		WheelWidth = 0.7,
		Wheels = 2,
		Colour = Color3.fromRGB(28, 30, 36),
		StashBonus = -99, -- wird auf 0 geklemmt: kein Lager
		HeatFactor = 0.85,
	},
} :: { VehicleClass }

--==========================================================================

function Vehicles.Get(id: string): VehicleClass?
	for _, class in Vehicles.List do
		if class.Id == id then
			return class
		end
	end
	return nil
end

function Vehicles.Exists(id: any): boolean
	return typeof(id) == "string" and Vehicles.Get(id) ~= nil
end

function Vehicles.Count(): number
	return #Vehicles.List
end

-- Lagerplatz, den dieses Fahrzeug beisteuert. Nie negativ.
function Vehicles.StashBonus(id: string): number
	local class = Vehicles.Get(id)
	if not class then
		return 0
	end
	return math.max(0, class.StashBonus)
end

--==========================================================================
-- Pruefung des Katalogs. Laeuft beim Serverstart und im Testlauf.
--==========================================================================

function Vehicles.Validate(list: { VehicleClass }?): (boolean, { string })
	local classes = list or Vehicles.List
	local errors: { string } = {}
	local seen: { [string]: boolean } = {}

	for index, class in classes do
		local label = if typeof(class.Id) == "string" and class.Id ~= "" then class.Id else ("#" .. index)

		if typeof(class.Id) ~= "string" or class.Id == "" then
			table.insert(errors, ("%s: Id fehlt"):format(label))
		elseif seen[class.Id] then
			table.insert(errors, ("%s: Id doppelt vergeben"):format(label))
		else
			seen[class.Id] = true
		end

		if typeof(class.Name) ~= "string" or class.Name == "" then
			table.insert(errors, ("%s: Name fehlt"):format(label))
		end
		-- Ohne Asset-Namen findet VehicleChassis keine Vorlage und baut fuer
		-- diese Klasse immer nur einen Platzhalter.
		if typeof(class.Asset) ~= "string" or class.Asset == "" then
			table.insert(errors, ("%s: Asset-Name fehlt"):format(label))
		end
		for _, field in { "Price", "MaxSpeed", "Acceleration", "BrakeForce", "TurnAngle", "Mass", "Grip" } do
			local value = (class :: any)[field]
			if typeof(value) ~= "number" or value <= 0 then
				table.insert(errors, ("%s: %s muss groesser 0 sein"):format(label, field))
			end
		end
		if class.Wheels ~= 2 and class.Wheels ~= 4 then
			table.insert(errors, ("%s: Wheels muss 2 oder 4 sein"):format(label))
		end
		if typeof(class.HeatFactor) ~= "number" or class.HeatFactor <= 0 then
			table.insert(errors, ("%s: HeatFactor muss groesser 0 sein"):format(label))
		end
		if typeof(class.BodySize) ~= "Vector3" then
			table.insert(errors, ("%s: BodySize fehlt"):format(label))
		end
	end

	-- Die Leitregel als Pruefung: keine Klasse darf eine andere in JEDER
	-- Hinsicht schlagen, sonst ist die schwaechere tot.
	for _, a in classes do
		for _, b in classes do
			if a.Id == b.Id then
				continue
			end
			local betterEverywhere = a.MaxSpeed >= b.MaxSpeed
				and a.Acceleration >= b.Acceleration
				and Vehicles.StashBonus(a.Id) >= Vehicles.StashBonus(b.Id)
				and a.HeatFactor <= b.HeatFactor
				and a.Price <= b.Price
			if betterEverywhere then
				table.insert(errors, ("%s macht %s vollstaendig ueberfluessig"):format(a.Id, b.Id))
			end
		end
	end

	return #errors == 0, errors
end

return Vehicles
