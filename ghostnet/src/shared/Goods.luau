-- ReplicatedStorage/Shared/Goods.luau
--!strict
-- GHOSTNET :: Warenkatalog fuers Darknet.
--
-- Je Ware drei Zahlen, die zusammen ihren Charakter ergeben:
--   Base        Ankerpreis. Der Kurs kehrt langfristig dorthin zurueck.
--   Volatility  wie stark er pro Tick springt (0.04 = bis zu +-4%).
--   Risk        Wahrscheinlichkeit, dass eine Einheit sich als Faelschung
--               entpuppt und beim Verkauf nichts bringt. Sinkt mit dem
--               Analyse-Modul im Rig.
--
-- Die Mischung ist Absicht: billige, ruhige Ware zum Lernen; teure, wilde
-- Ware, bei der man richtig danebenliegen kann. Ohne dieses Gefaelle waere
-- Handel nur Warten.

local Goods = {}

export type Good = {
	Id: string,
	Name: string,
	Blurb: string,
	Base: number,
	Volatility: number,
	Risk: number,
	Group: string, -- fuer Markt-Events ("Razzia: Ausweise +60%")
}

Goods.List = {
	{
		Id = "CREDS",
		Name = "Zugangsdaten",
		Blurb = "Frische Logins. Schnell verderblich, aber immer gefragt.",
		Base = 90,
		Volatility = 0.05,
		Risk = 0.04,
		Group = "DATEN",
	},
	{
		Id = "DATAPACK",
		Name = "Datenpakete",
		Blurb = "Rohdaten aus geknackten Systemen. Ruhiger Kurs.",
		Base = 140,
		Volatility = 0.035,
		Risk = 0.02,
		Group = "DATEN",
	},
	{
		Id = "HARDWARE",
		Name = "Hardware-Teile",
		Blurb = "Ausgebaute Module. Schwer zu faelschen, dafuer traege.",
		Base = 260,
		Volatility = 0.03,
		Risk = 0.01,
		Group = "TECHNIK",
	},
	{
		Id = "EXPLOIT",
		Name = "Exploit-Kits",
		Blurb = "Fertige Einbruchswerkzeuge. Kurs haengt an Razzien.",
		Base = 420,
		Volatility = 0.08,
		Risk = 0.07,
		Group = "TECHNIK",
	},
	{
		Id = "IDCARD",
		Name = "Gefaelschte Ausweise",
		Blurb = "Teuer, wild, und jede zehnte taugt nichts.",
		Base = 610,
		Volatility = 0.11,
		Risk = 0.12,
		Group = "PAPIERE",
	},
} :: { Good }

--==========================================================================

function Goods.Get(id: string): Good?
	for _, good in Goods.List do
		if good.Id == id then
			return good
		end
	end
	return nil
end

function Goods.Count(): number
	return #Goods.List
end

function Goods.Exists(id: any): boolean
	return typeof(id) == "string" and Goods.Get(id) ~= nil
end

-- Pruefung der Katalogdaten. Laeuft beim Serverstart und im Testlauf.
function Goods.Validate(list: { Good }?): (boolean, { string })
	local goods = list or Goods.List
	local errors: { string } = {}
	local seen: { [string]: boolean } = {}

	for index, good in goods do
		local label = if typeof(good.Id) == "string" and good.Id ~= "" then good.Id else ("#" .. index)

		if typeof(good.Id) ~= "string" or good.Id == "" then
			table.insert(errors, ("%s: Id fehlt"):format(label))
		elseif seen[good.Id] then
			table.insert(errors, ("%s: Id doppelt vergeben"):format(label))
		else
			seen[good.Id] = true
		end

		if typeof(good.Name) ~= "string" or good.Name == "" then
			table.insert(errors, ("%s: Name fehlt"):format(label))
		end
		if typeof(good.Group) ~= "string" or good.Group == "" then
			table.insert(errors, ("%s: Group fehlt"):format(label))
		end
		if typeof(good.Base) ~= "number" or good.Base <= 0 then
			table.insert(errors, ("%s: Base muss groesser 0 sein"):format(label))
		end
		if typeof(good.Volatility) ~= "number" or good.Volatility <= 0 or good.Volatility >= 0.5 then
			table.insert(errors, ("%s: Volatility muss zwischen 0 und 0.5 liegen"):format(label))
		end
		if typeof(good.Risk) ~= "number" or good.Risk < 0 or good.Risk >= 1 then
			table.insert(errors, ("%s: Risk muss zwischen 0 und 1 liegen"):format(label))
		end
	end

	return #errors == 0, errors
end

return Goods
