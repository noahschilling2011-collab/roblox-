--!strict
-- HarvestController: Client-Effekte für das physische Sammeln.
--
-- Der Server entscheidet, WAS gesammelt/verkauft wird (HarvestService);
-- dieser Controller macht es fühlbar: Sammel-Sound + fliegende Wert-Zahl,
-- Verkaufs-Feedback und ein dezenter "Rucksack voll"-Hinweis.


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ControllersFolder = script.Parent :: Instance

local Remotes = require(Shared:WaitForChild("Remotes") :: ModuleScript) :: {
	getEvent: (name: string) -> RemoteEvent,
	getFunction: (name: string) -> RemoteFunction,
}
local UIController = require(ControllersFolder:WaitForChild("UIController") :: ModuleScript) :: {
	showToast: (message: string, kind: string) -> (),
}
local EffectsController = require(ControllersFolder:WaitForChild("EffectsController") :: ModuleScript) :: {
	playSound: (name: string, pitchOverride: number?) -> (),
}

local FULL_HINT_COOLDOWN_SECONDS = 45

local HarvestController = {}

local lastFullHintAt = 0
local collectPitch = 1

-- Kleine Wert-Zahl, die vom eingesammelten Objekt aufsteigt (3D-Billboard).
local function showFloatingValue(position: Vector3, value: number, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 26)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = `+{value}`
	label.Parent = billboard

	local rise = TweenService:Create(
		billboard,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 4.5, 0) }
	)
	local fade = TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 })
	rise:Play()
	task.delay(0.4, function()
		fade:Play()
	end)
	task.delay(0.9, function()
		anchor:Destroy()
	end)
end

function HarvestController.init()
	-- Sammel-Effekt: Sound (leicht steigende Tonhöhe bei Ketten) + Wert-Zahl.
	Remotes.getEvent("ObjectCollected").OnClientEvent:Connect(function(position: any, value: any, color: any)
		if typeof(position) ~= "Vector3" or typeof(value) ~= "number" then
			return
		end
		collectPitch = math.min(collectPitch + 0.04, 1.5)
		EffectsController.playSound("collect", collectPitch)
		task.delay(2, function()
			collectPitch = math.max(collectPitch - 0.04, 1)
		end)
		showFloatingValue(position, value, if typeof(color) == "Color3" then color else Color3.fromRGB(255, 224, 130))
	end)

	-- Verkaufs-Feedback.
	Remotes.getEvent("SoldBackpack").OnClientEvent:Connect(function(gained: any, itemsSold: any)
		if typeof(gained) ~= "number" then
			return
		end
		EffectsController.playSound("fanfare", 1.1)
		local items = if typeof(itemsSold) == "number" then itemsSold else 0
		UIController.showToast(`Verkauft: {items} Objekte für {gained} Energie! ⚡`, "success")
	end)

	-- Dezenter Hinweis, wenn der Rucksack voll ist (gedrosselt).
	Remotes.getEvent("BackpackChanged").OnClientEvent:Connect(function(items: any, capacity: any)
		if typeof(items) ~= "number" or typeof(capacity) ~= "number" then
			return
		end
		if items >= capacity and os.clock() - lastFullHintAt > FULL_HINT_COOLDOWN_SECONDS then
			lastFullHintAt = os.clock()
			UIController.showToast("Rucksack voll! Verkaufe am goldenen 💰-Pad auf deiner Insel.", "info")
		end
	end)
end

return HarvestController
