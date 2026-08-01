-- ServerScriptService/AdminList.luau
--!strict
-- GHOSTNET :: Wer Admin ist.
--
-- ACHTUNG - diese Datei liegt bewusst in ServerScriptService und NICHT in
-- ReplicatedStorage. Alles unter ReplicatedStorage kann jeder Client lesen.
-- Eine Admin-Liste dort waere eine oeffentliche Ansage, wen man angreifen
-- muss.
--
-- NOAH TRAEGT SEINE USERID HIER EIN.
-- Die eigene UserId findet man so: Roblox-Profil im Browser oeffnen, die
-- Zahl in der Adresszeile hinter /users/ ist es. Nicht der Nutzername -
-- Nutzernamen kann man aendern, UserIds nicht.
--
-- Solange die Liste leer ist, gibt es im Live-Spiel schlicht keine Admins.
-- Im Studio ist der Testspieler automatisch Admin (siehe unten), damit man
-- ohne Eintrag entwickeln kann.

local RunService = game:GetService("RunService")

local AdminList = {}

-- Beispiel: { 1234567, 7654321 }
local USER_IDS: { number } = {}

-- Im Studio ist jeder Admin. Der Pfad ist doppelt abgesichert (IsStudio UND
-- dieses Flag) und existiert im Live-Spiel nicht.
local STUDIO_IS_ADMIN = true

function AdminList.IsAdmin(player: Player): boolean
	if not player or not player.Parent then
		return false
	end

	for _, id in USER_IDS do
		if player.UserId == id then
			return true
		end
	end

	if STUDIO_IS_ADMIN and RunService:IsStudio() then
		return true
	end

	return false
end

-- Die gefaehrlichsten Befehle (Geld geben, Trace setzen, Profil
-- zuruecksetzen) gibt es NUR im Studio. Selbst ein echter Admin kann sie im
-- Live-Spiel nicht ausloesen - damit ein gestohlener Account keinen Schaden
-- an der Wirtschaft anrichten kann.
function AdminList.IsStudioOnlyAllowed(): boolean
	return RunService:IsStudio()
end

function AdminList.Count(): number
	return #USER_IDS
end

return AdminList
