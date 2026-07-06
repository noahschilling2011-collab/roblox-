--!strict
-- PlacementController: Ghost-Preview und Platzierungs-Eingabe.
--
-- Der Client zeigt eine halbtransparente Vorschau (grün = gültig,
-- rot = ungültig) und schickt beim Klick/Tipp NUR einen Platzierungs-
-- WUNSCH an den Server (PlacePart). Die Prüfungen hier sind reine
-- Anzeige-Hilfen - der Server validiert alles noch einmal komplett
-- und ist die einzige Autorität (siehe TowerService).
--
-- Eingabe: Maus bewegen = zielen, Linksklick = platzieren, R = drehen,
-- Tasten 1-3 = Hotbar-Slot. Touch: Tippen = zielen/platzieren (M4 baut
-- den Mobile-Support weiter aus).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig") :: ModuleScript) :: any
local PartCatalog = require(Shared:WaitForChild("Config"):WaitForChild("PartCatalog") :: ModuleScript) :: any

local ControllersFolder = script.Parent :: Instance
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: any

local VALID_COLOR = Color3.fromRGB(90, 220, 120)
local INVALID_COLOR = Color3.fromRGB(230, 80, 70)

local PlacementController = {}

local localPlayer = Players.LocalPlayer

local ghostModel: Model? = nil
local ghostHighlight: Highlight? = nil
local ghostTypeId: string? = nil
local ghostYaw = 0 -- Rotation in 45°-Schritten (Radiant)
local ghostValid = false
local placeInFlight = false

local placeFunction: RemoteFunction? = nil

--------------------------------------------------------------------------
-- Ghost-Verwaltung
--------------------------------------------------------------------------

local function destroyGhost()
	if ghostModel ~= nil then
		ghostModel:Destroy()
	end
	ghostModel = nil
	ghostHighlight = nil
	ghostTypeId = nil
end

-- Baut den Ghost für einen Teiltyp (transparent, ohne Kollision/Physik).
local function ensureGhost(partTypeId: string)
	if ghostTypeId == partTypeId and ghostModel ~= nil then
		return
	end
	destroyGhost()

	local model = PartCatalog.create(partTypeId) :: Model
	model.Name = "PlatzierGhost"
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Transparency = 0.55
		elseif descendant:IsA("Constraint") then
			descendant.Enabled = false -- Ghost braucht keine Physik
		end
	end

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0.1
	highlight.Adornee = model
	highlight.Parent = model

	model.Parent = Workspace
	ghostModel = model
	ghostHighlight = highlight
	ghostTypeId = partTypeId
end

-- Zielpunkt unter dem Cursor (bzw. der letzten Touch-Position).
local function raycastTarget(): RaycastResult?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local screenPosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if ghostModel ~= nil then
		table.insert(exclude, ghostModel :: Model)
	end
	local character = localPlayer.Character
	if character ~= nil then
		table.insert(exclude, character)
	end
	params.FilterDescendantsInstances = exclude

	return Workspace:Raycast(ray.Origin, ray.Direction * 200, params)
end

-- Grobe Client-Sicht der Gültigkeit (nur für die Farbe; Server entscheidet).
local function checkClientValidity(targetPosition: Vector3): boolean
	if UIController.getPhase() ~= "Bauphase" then
		return false
	end
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	return ((root :: BasePart).Position - targetPosition).Magnitude <= GameConfig.PLACE_REACH_STUDS
end

-- Position auf ein halbes Stud rastern (ordentliche Türme, weniger Kanten-Chaos).
local function snap(value: number): number
	return math.round(value * 2) / 2
end

local function updateGhost()
	local _, partTypeId = UIController.getSelected()
	if partTypeId == nil then
		destroyGhost()
		return
	end
	ensureGhost(partTypeId :: string)

	local model = ghostModel
	if model == nil then
		return
	end

	local hit = raycastTarget()
	if hit == nil then
		model:PivotTo(CFrame.new(0, -500, 0)) -- außer Sicht
		ghostValid = false
		return
	end

	-- Versatz entlang der Trefffläche, damit der Ghost AUF ihr sitzt.
	local def = PartCatalog.Parts[partTypeId]
	local normal = hit.Normal
	local halfExtent = (
		math.abs(normal.X) * def.size.x
		+ math.abs(normal.Y) * def.size.y
		+ math.abs(normal.Z) * def.size.z
	) / 2
	local position = hit.Position + normal * (halfExtent + 0.05)
	position = Vector3.new(snap(position.X), snap(position.Y), snap(position.Z))

	local cframe = CFrame.new(position) * CFrame.Angles(0, ghostYaw, 0)
	model:PivotTo(cframe)

	ghostValid = checkClientValidity(position)
	local highlight = ghostHighlight
	if highlight ~= nil then
		highlight.FillColor = if ghostValid then VALID_COLOR else INVALID_COLOR
		highlight.OutlineColor = highlight.FillColor
	end
end

--------------------------------------------------------------------------
-- Platzieren
--------------------------------------------------------------------------

local function tryPlace()
	local _, partTypeId = UIController.getSelected()
	local model = ghostModel
	if partTypeId == nil or model == nil or not ghostValid or placeInFlight then
		return
	end
	local remote = placeFunction
	if remote == nil then
		return
	end

	local targetCFrame = model:GetPivot()
	placeInFlight = true
	task.spawn(function()
		local ok, serverOk, err = pcall(function()
			return remote:InvokeServer(partTypeId, targetCFrame)
		end)
		placeInFlight = false
		if not ok then
			UIController.showToast("Verbindungsfehler - bitte erneut versuchen.", "error")
		elseif serverOk ~= true and typeof(err) == "string" then
			UIController.showToast(err, "error")
		end
	end)
end

--------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------

function PlacementController.init()
	placeFunction = Network.getFunction("PlacePart")

	-- Ghost jeden Frame nachführen.
	RunService.RenderStepped:Connect(updateGhost)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			tryPlace()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			-- Touch: erst zielen (Ghost springt zur Fingerposition), das
			-- Platzieren übernimmt derselbe Tipp, wenn der Ghost gültig ist.
			tryPlace()
		elseif input.KeyCode == Enum.KeyCode.R then
			ghostYaw += math.rad(45)
		elseif input.KeyCode == Enum.KeyCode.One then
			UIController.selectSlot(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			UIController.selectSlot(2)
		elseif input.KeyCode == Enum.KeyCode.Three then
			UIController.selectSlot(3)
		end
	end)

	-- Platzier-Sound für alle (Server bestätigt die Platzierung).
	Network.getEvent("PartPlaced").OnClientEvent:Connect(function(position: any)
		if typeof(position) ~= "Vector3" then
			return
		end
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxasset://sounds/snap.mp3"
		sound.Volume = 0.5
		sound.Parent = Workspace
		sound:Play()
		task.delay(2, function()
			sound:Destroy()
		end)
	end)
end

return PlacementController
