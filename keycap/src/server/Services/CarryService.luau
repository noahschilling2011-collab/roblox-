--!strict
-- Sichtbares Tragen der Beute.
--
-- Die Bewertung nennt das den Clip-Moment: "Diebstahl muss fuer Umstehende
-- lesbar sein, sonst passiert er sozial gar nicht." Wer klaut, traegt die
-- Taste ueber dem Kopf, ist langsamer (SpeedService) und ist damit fuer
-- alle als Dieb erkennbar.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local WorldConfig = require(Shared.Config.WorldConfig)
local Theme = require(Shared.Theme)

local CarryService = {}

local active: { [number]: Model } = {} -- userId -> Trage-Modell

local function clear(userId: number)
	local model = active[userId]
	if model then
		model:Destroy()
		active[userId] = nil
	end
end

-- Haengt eine sichtbare Taste ueber den Kopf des Diebes. Wird nach
-- CARRY_SECONDS automatisch entfernt.
function CarryService.show(player: Player, rarity: string, vorrat: number)
	clear(player.UserId)

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local model = Instance.new("Model")
	model.Name = "Beute"

	local part = Instance.new("Part")
	part.Name = "Key"
	part.Size = WorldConfig.KEY_SIZE * 0.5
	part.CFrame = head.CFrame * CFrame.new(0, 3.5, 0)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true -- darf die Physik des Diebes nicht veraendern
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Theme.RARITY_COLORS[rarity] or Theme.WORLD.PLATE
	part.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 190, 0, 46)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 260

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT
	label.TextScaled = true
	label.TextColor3 = Theme.RED
	label.TextStrokeTransparency = 0.35
	label.Text = ("BEUTE: %s (%d)"):format(rarity, vorrat)
	label.Parent = billboard
	billboard.Parent = part

	-- Reihenfolge zaehlt: erst in die Welt haengen, dann schweissen. Andersherum
	-- ist das Teil einen Frame lang ein freier Koerper und faellt sichtbar weg.
	-- Zwischen diesen Zeilen wird nicht geyieldet, also sieht die Physik nie
	-- einen ungeschweissten Zustand.
	model.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = part
	weld.Parent = part

	active[player.UserId] = model

	task.delay(EconomyConfig.CARRY_SECONDS, function()
		if active[player.UserId] == model then
			clear(player.UserId)
		end
	end)
end

function CarryService.start()
	Players.PlayerRemoving:Connect(function(player)
		clear(player.UserId)
	end)
	-- Beim Respawn haengt nichts mehr am neuen Charakter - Zustand
	-- aufraeumen, damit kein verwaistes Modell zurueckbleibt.
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			clear(player.UserId)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	print("[KEYCAP] CarryService laeuft (" .. EconomyConfig.CARRY_SECONDS .. "s sichtbar)")
end

return CarryService
