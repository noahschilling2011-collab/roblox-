-- StarterPlayer/StarterPlayerScripts/UI/TargetBeacons.client.luau
--!strict
-- GHOSTNET :: Hack-Ziele auf Distanz erkennbar machen.
--
-- Ohne das laeuft man an einem Ziel vorbei, ohne zu merken, dass es eins ist -
-- die Objekte sehen aus wie Kulisse, weil sie welche sind. Ein dezent
-- pulsierendes Akzentlicht loest das, ohne die Ruhe des Spiels zu zerstoeren.
--
-- Laeuft rein clientseitig auf vorhandenen Lichtern. Es werden keine neuen
-- Instanzen erzeugt und nichts an der Welt veraendert, was der Server sieht.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

type Beacon = {
	Part: BasePart,
	Light: PointLight,
	BaseBrightness: number,
	Phase: number,
}

local beacons: { [BasePart]: Beacon } = {}
local nextPhase = 0

local function track(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	local part = inst :: BasePart
	if beacons[part] then
		return
	end
	local light = part:FindFirstChildOfClass("PointLight")
	if not light then
		return -- kein Akzentlicht, also nichts zu pulsieren
	end

	-- Versetzte Phase, damit nicht die halbe Stadt im Gleichtakt blinkt.
	nextPhase += 1.7
	beacons[part] = {
		Part = part,
		Light = light,
		BaseBrightness = light.Brightness,
		Phase = nextPhase,
	}
end

local function untrack(inst: Instance)
	if inst:IsA("BasePart") then
		beacons[inst :: BasePart] = nil
	end
end

for _, inst in CollectionService:GetTagged(Config.HackableTag) do
	track(inst)
end
CollectionService:GetInstanceAddedSignal(Config.HackableTag):Connect(track)
CollectionService:GetInstanceRemovedSignal(Config.HackableTag):Connect(untrack)

-- Hehler bekommen denselben Effekt, damit man den Rueckweg findet.
for _, inst in CollectionService:GetTagged(Config.FenceTag) do
	track(inst)
end
CollectionService:GetInstanceAddedSignal(Config.FenceTag):Connect(track)
CollectionService:GetInstanceRemovedSignal(Config.FenceTag):Connect(untrack)

local accumulator = 0
RunService.RenderStepped:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.06 then
		return
	end
	accumulator = 0

	local now = os.clock()
	for part, beacon in beacons do
		if not part.Parent then
			beacons[part] = nil
			continue
		end

		-- Offline heisst dunkel. Das ist die einzige Rueckmeldung, die man
		-- aus der Ferne braucht.
		if part:GetAttribute("Offline") == true then
			beacon.Light.Enabled = false
			continue
		end

		beacon.Light.Enabled = true
		local pulse = 0.5 + 0.5 * math.sin(now * Config.World.TargetPulseSpeed + beacon.Phase)
		beacon.Light.Brightness = beacon.BaseBrightness * (1 - Config.World.TargetPulseDepth + Config.World.TargetPulseDepth * pulse * 2)
	end
end)
