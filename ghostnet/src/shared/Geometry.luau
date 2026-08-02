-- ReplicatedStorage/Shared/Geometry.luau
--!strict
-- GHOSTNET :: Die eine Abstandsrechnung, die Server und Client benutzen.
--
-- Warum geteilt: Der HUD zeigt "3 m" an und der Server entscheidet "zu weit".
-- Rechnen beide unterschiedlich, sieht das im Spiel nach einem Bug aus.
-- Deshalb liegt die Formel genau einmal hier.

local Players = game:GetService("Players")

local Geometry = {}

-- Abstand zur OBERFLAECHE des Parts, nicht zum Mittelpunkt. Sonst waeren
-- grosse Objekte (Tueren, Werbetafeln, Tresen) unfair weit weg.
function Geometry.SurfaceDistance(part: BasePart, position: Vector3): number
	if not part.Parent then
		return math.huge
	end
	local rel = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	local clamped = Vector3.new(
		math.clamp(rel.X, -half.X, half.X),
		math.clamp(rel.Y, -half.Y, half.Y),
		math.clamp(rel.Z, -half.Z, half.Z)
	)
	return (rel - clamped).Magnitude
end

-- Position des Spielers, aber nur wenn er wirklich lebendig in der Welt steht.
-- nil heisst: gerade kein gueltiger Character (respawnt, tot, noch nicht geladen).
function Geometry.AlivePosition(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root.Position
end

-- Steht IRGENDEIN anderer lebender Spieler nah genug an diesem Part?
-- Liegt hier und nicht in einem der Services, weil sowohl HackService (fuer
-- den halbierten Trace) als auch RaidService (fuer die langsamere Alarm-Uhr)
-- die Antwort brauchen - und die beiden duerfen sich nicht gegenseitig
-- requiren.
function Geometry.HasNearbyOtherPlayer(player: Player, part: BasePart, range: number): boolean
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local position = Geometry.AlivePosition(other)
		if position and Geometry.SurfaceDistance(part, position) <= range then
			return true
		end
	end
	return false
end

return Geometry
