-- ServerScriptService/Systems/EconomyService.luau
--!strict
-- GHOSTNET :: Einzige Stelle, an der sich Crypto und Rig-Werte aendern.
--
-- Seit Phase 1 liegt der Zustand im Profil des SaveService statt in einem
-- eigenen Wallet im Arbeitsspeicher. Die Schnittstelle nach aussen ist
-- unveraendert geblieben: GetRig, GetTier, Snapshot, AwardUnsold, WipeUnsold,
-- Sync. Dazu kamen nur die Schreibwege, die Verkauf und Shop brauchen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local SaveService = require(script.Parent.SaveService)

type RigLevels = Types.RigLevels
type Profile = Types.Profile

local EconomyService = {}

-- Solange das Profil laedt, gibt es Startwerte zurueck statt zu crashen.
-- Geschrieben wird in dieser Zeit nichts - jeder Schreibweg prueft auf nil.
local function fallbackRig(): RigLevels
	local start = Config.Rig.StartLevels
	return { CPU = start.CPU, RAM = start.RAM, Cooling = start.Cooling, NetCard = start.NetCard }
end

--==========================================================================
-- Lesen
--==========================================================================

function EconomyService.GetRig(player: Player): RigLevels
	local profile = SaveService.Get(player)
	if not profile then
		return fallbackRig()
	end
	return table.clone(profile.Rig)
end

-- Tier ist abgeleitet, nicht gekauft: das SCHWAECHSTE Bauteil zaehlt.
-- Man kann sich also nicht mit einer einzelnen Komponente in eine hoehere
-- Zone schummeln.
function EconomyService.GetTier(player: Player): number
	local profile = SaveService.Get(player)
	if not profile then
		return 1
	end
	local rig = profile.Rig
	return math.min(rig.CPU, rig.RAM, rig.Cooling, rig.NetCard)
end

function EconomyService.GetRange(player: Player): number
	local profile = SaveService.Get(player)
	return Config.GetRange(if profile then profile.Rig.NetCard else Config.Rig.StartLevels.NetCard)
end

function EconomyService.GetBanked(player: Player): number
	local profile = SaveService.Get(player)
	return if profile then profile.Banked else 0
end

function EconomyService.GetUnsold(player: Player): number
	local profile = SaveService.Get(player)
	return if profile then profile.Unsold else 0
end

function EconomyService.Snapshot(player: Player): { [string]: any }
	local profile = SaveService.Get(player)
	if not profile then
		return { Banked = 0, Unsold = 0, Rig = fallbackRig(), Tier = 1, Ready = false }
	end
	-- Cooldowns als RESTSEKUNDEN, nicht als Zeitstempel: die Uhr des Clients
	-- kann anders gehen als die des Servers. Ohne das zeigt der HUD nach einem
	-- Rejoin "[E] BREACH" an, obwohl das Ziel noch gesperrt ist.
	local remaining: { [string]: number } = {}
	local now = os.time()
	for id, until_ in profile.Cooldowns do
		local left = until_ - now
		if left > 0 then
			remaining[id] = left
		end
	end

	return {
		Banked = profile.Banked,
		Unsold = profile.Unsold,
		Rig = table.clone(profile.Rig),
		Tier = EconomyService.GetTier(player),
		Stats = table.clone(profile.Stats),
		Cooldowns = remaining,
		Ready = true,
	}
end

--==========================================================================
-- Schreiben
--==========================================================================

function EconomyService.Sync(player: Player)
	if not player.Parent then
		return
	end
	Remotes.EconomySync:FireClient(player, EconomyService.Snapshot(player))
end

-- Belohnung aus einem Hack landet im heissen Wallet, nicht auf der Bank.
function EconomyService.AwardUnsold(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	profile.Unsold += math.floor(amount)
	EconomyService.Sync(player)
end

-- Wird beim Bust gebraucht. Liefert, wie viel verloren ging.
function EconomyService.WipeUnsold(player: Player): number
	local profile = SaveService.Get(player)
	if not profile then
		return 0
	end
	local lost = profile.Unsold
	profile.Unsold = 0
	EconomyService.Sync(player)
	return lost
end

-- Verkauf beim Hehler: alles Unverkaufte abzueglich Gebuehr auf die Bank.
-- Liefert (brutto, gebuehr, netto). Der Aufrufer prueft Distanz und Zustand,
-- gerechnet und gebucht wird ausschliesslich hier.
function EconomyService.SellUnsold(player: Player, feePercent: number): (number, number, number)
	local profile = SaveService.Get(player)
	if not profile or profile.Unsold <= 0 then
		return 0, 0, 0
	end

	local gross = math.floor(profile.Unsold)
	local fee = math.floor(gross * feePercent)
	local net = gross - fee

	profile.Unsold = 0
	profile.Banked += net
	profile.Stats.Sales += 1
	profile.Stats.Earned += net

	EconomyService.Sync(player)
	return gross, fee, net
end

-- Abbuchen von der Bank. false = zu wenig Guthaben, es wurde nichts gebucht.
function EconomyService.SpendBanked(player: Player, amount: number): boolean
	local profile = SaveService.Get(player)
	if not profile then
		return false
	end
	local cost = math.floor(amount)
	if cost <= 0 or profile.Banked < cost then
		return false
	end
	profile.Banked -= cost
	return true
end

-- Rueckbuchung, wenn ein Kauf nach dem Abbuchen doch nicht klappt. Damit
-- laeuft auch der Fehlerfall ueber den EconomyService und nicht am Profil vorbei.
function EconomyService.RefundBanked(player: Player, amount: number)
	local profile = SaveService.Get(player)
	if not profile or amount <= 0 then
		return
	end
	profile.Banked += math.floor(amount)
end

-- Rig-Stufe setzen. Prueft Bauteil und Grenzen selbst, damit sich hier kein
-- Aufrufer vertun kann.
function EconomyService.SetRigLevel(player: Player, component: string, level: number): boolean
	local profile = SaveService.Get(player)
	if not profile then
		return false
	end
	if typeof((profile.Rig :: any)[component]) ~= "number" then
		return false
	end
	local clamped = math.clamp(math.floor(level), 1, Config.Rig.MaxLevel)
	;(profile.Rig :: any)[component] = clamped
	profile.Stats.Upgrades += 1
	return true
end

-- Zaehler fuers Profil. Liegt hier, damit die Services nicht selbst im
-- Profil herumschreiben.
function EconomyService.CountHack(player: Player, success: boolean)
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	if success then
		profile.Stats.Hacks += 1
	else
		profile.Stats.Fails += 1
	end
end

function EconomyService.CountBust(player: Player)
	local profile = SaveService.Get(player)
	if profile then
		profile.Stats.Busts += 1
	end
end

function EconomyService.Init()
	-- Sobald das Profil steht, bekommt der Client seinen ersten Kontostand.
	SaveService.OnReady(function(player)
		EconomyService.Sync(player)
	end)

	-- Respawn: der Client baut sein HUD neu auf, also nochmal schicken.
	local function watchRespawn(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			if SaveService.IsReady(player) then
				EconomyService.Sync(player)
			end
		end)
	end

	Players.PlayerAdded:Connect(watchRespawn)
	for _, player in Players:GetPlayers() do
		watchRespawn(player)
	end

	print("[GHOSTNET] EconomyService bereit.")
end

return EconomyService
