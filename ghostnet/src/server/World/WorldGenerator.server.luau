-- ServerScriptService/World/WorldGenerator.server.luau
--!strict
-- GHOSTNET :: Hack-Ziele ueber die ganze Stadt verteilen.
--
-- WARUM
--   Bisher standen die Ziele von Hand gesetzt am Spawn und in der Story-Welt:
--   vier Stueck. Wer die durch hat, hat nichts mehr zu tun. Der Generator
--   fuellt die Stadt mit Zielen, deren Schwierigkeit vom BEZIRK kommt -
--   damit schliesst Rig-Fortschritt neue Stadtteile auf, statt nur groessere
--   Zahlen zu erlauben.
--
-- WAS ER NICHT ANFASST
--   Die Story-Ziele aus StoryWorld, TestTargets und BankInterior bleiben,
--   wo sie sind. Missionen zeigen auf feste TargetIds - ein Generator, der
--   die ueberschreibt, macht die Story unspielbar. Er ERGAENZT nur.
--
-- KEIN CODE PRO OBJEKT
--   Jedes Ziel ist ein geklontes Prop mit Tag GhostNetHackable und
--   Attributen. HackService liest die Attribute und weiss dann alles.
--   Fehlt die Vorlage, kommt ein magenta Platzhalter - so wie ueberall.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetLibrary = require(ReplicatedStorage.Shared.AssetLibrary)
local Config = require(ReplicatedStorage.Shared.Config)
local Districts = require(ReplicatedStorage.Shared.Districts)

local RoadNetwork = require(ServerScriptService:WaitForChild("Systems"):WaitForChild("RoadNetwork"))

local FOLDER_NAME = "GhostNet_Generated"

if workspace:FindFirstChild(FOLDER_NAME) then
	return
end

RoadNetwork.Build()

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder.Parent = workspace

local G = Config.Generator
local rng = Random.new(Config.World.Seed + 7)

--==========================================================================
-- Ein Ziel setzen
--==========================================================================

local placed = 0

local function place(archetype: any, position: Vector3, difficulty: number, exposed: boolean, index: number)
	local model = AssetLibrary.Clone("Props", archetype.Asset, archetype.Size)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))

	local anchor: BasePart? = model.PrimaryPart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			if not anchor then
				anchor = descendant
			end
		end
	end
	if not anchor then
		model:Destroy()
		return
	end

	-- Nur der Ankerpart traegt Tag und Attribute. Ein Hack-Ziel ist genau
	-- EIN BasePart - so steht es in der Architekturregel.
	anchor.CanQuery = true
	anchor:SetAttribute("TargetId", ("GEN_%s_%d"):format(archetype.Id, index))
	anchor:SetAttribute("DisplayName", ("%s // %s"):format(archetype.Label, archetype.Suffix))
	anchor:SetAttribute("Difficulty", difficulty)
	anchor:SetAttribute("HackType", archetype.HackType)
	anchor:SetAttribute("RequiredLevel", math.clamp(math.ceil(difficulty / G.LevelPerDifficulty), 1, Config.Rig.MaxLevel))
	anchor:SetAttribute("OnSuccess", archetype.OnSuccess)
	anchor:SetAttribute("DownTime", archetype.DownTime)
	anchor:SetAttribute("Cooldown", G.Cooldown)
	anchor:SetAttribute("Exposed", exposed)
	anchor:SetAttribute("Offline", false)

	-- Akzentlicht, damit man das Ziel auf Distanz erkennt. Neonflaeche waere
	-- billiger, aber ein Prop bringt seine eigene Form mit - ein Licht ist
	-- der einzige Weg, das von aussen zu markieren.
	if rng:NextNumber() < G.LightChance then
		local light = Instance.new("PointLight")
		light.Color = if exposed then Config.Theme.Amber else Config.Theme.Cyan
		light.Brightness = G.LightBrightness
		light.Range = G.LightRange
		light.Parent = anchor
	end

	model.Parent = folder
	CollectionService:AddTag(anchor, Config.HackableTag)
	placed += 1
end

--==========================================================================
-- Verteilen
--
-- Entlang der Strassenkanten, abwechselnd links und rechts. Das gibt Ziele
-- an Fassaden statt mitten auf der Kreuzung - und es braucht keine
-- Kollisionsabfrage, weil der Abstand zur Strasse fest ist.
--==========================================================================

local seen: { [string]: boolean } = {}

for _, node in RoadNetwork.All() do
	for _, linkId in node.Links do
		local key = if node.Id < linkId
			then ("%d-%d"):format(node.Id, linkId)
			else ("%d-%d"):format(linkId, node.Id)
		if seen[key] then
			continue
		end
		seen[key] = true

		local other = RoadNetwork.Get(linkId)
		if not other then
			continue
		end

		local middle = (node.Position + other.Position) * 0.5
		local district = Districts.At(
			math.round(middle.X / Config.City.BlockSize),
			math.round(middle.Z / Config.City.BlockSize)
		)
		if not district then
			continue
		end

		for step = 1, G.PerEdge do
			if rng:NextNumber() > G.Chance then
				continue
			end
			if placed >= G.MaxTargets then
				break
			end

			local alpha = step / (G.PerEdge + 1)
			local along = node.Position:Lerp(other.Position, alpha)
			local delta = other.Position - node.Position
			local horizontal = math.abs(delta.X) > math.abs(delta.Z)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local lateral = Config.City.RoadWidth * 0.5 + Config.City.SidewalkWidth + G.WallOffset
			local offset = if horizontal
				then Vector3.new(0, 0, side * lateral)
				else Vector3.new(side * lateral, 0, 0)

			-- Schwierigkeit aus dem Bezirk. Genau daran haengt der Fortschritt:
			-- mit einem besseren Rig werden neue Stadtteile ueberhaupt erst
			-- knackbar.
			local difficulty = rng:NextInteger(district.MinDifficulty, district.MaxDifficulty)
			local archetype = G.Archetypes[rng:NextInteger(1, #G.Archetypes)]

			-- Hoch an der Fassade = gedeckt ist Unsinn; was oben haengt, sieht
			-- jeder. Bodennahes in der Gasse gilt als gedeckt.
			local exposed = archetype.Height > G.ExposedHeight

			place(
				archetype,
				along + offset + Vector3.new(0, Config.City.RoadThickness * 0.5 + archetype.Height, 0),
				difficulty,
				exposed,
				placed + 1
			)
		end
	end
end

print(("[GHOSTNET] Weltgenerator: %d Ziele verteilt (Obergrenze %d)."):format(placed, G.MaxTargets))
