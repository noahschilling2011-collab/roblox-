-- ServerScriptService/Systems/ContractService.luau
--!strict
-- GHOSTNET :: Drei Auftraege pro Tag.
--
-- WARUM DAS DER STAERKSTE HEBEL FUER WIEDERKEHR IST
--   Ein Spiel, das man durchspielen kann, spielt man einmal. Drei Ziele,
--   die morgen andere sind, geben einen Grund, nochmal reinzusehen - und
--   zwar ohne dass irgendetwas Neues gebaut werden muesste.
--
-- KEIN NEUES WIRTSCHAFTSSYSTEM
--   Die Auftraege zaehlen mit, was der Spieler ohnehin tut: hacken,
--   abliefern, verdienen, Autos kurzschliessen, entkommen. Sie zahlen in
--   dieselbe Waehrung ueber denselben EconomyService. Es gibt keine
--   zweite Punkteart und keinen zweiten Laden.
--
-- ZEIT UEBERLEBT DEN SERVERWECHSEL
--   Der Tag kommt aus os.time(), nie aus os.clock(). Genau dafuer ist die
--   Regel da: os.clock() faengt bei jedem Serverstart neu an, und dann
--   haette man nach jedem Serverwechsel wieder drei frische Auftraege.
--
-- ANGEHAENGT, NICHT EINGEBAUT
--   Der Fortschritt kommt ueber die vorhandenen Callbacks
--   (HackService.OnHackResolved, SellService.OnSell). Kein bestehendes
--   Modul muss dafuer angefasst werden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local EconomyService = require(script.Parent.EconomyService)
local HackService = require(script.Parent.HackService)
local RateLimiter = require(script.Parent.RateLimiter)
local SaveService = require(script.Parent.SaveService)
local SellService = require(script.Parent.SellService)

local ContractService = {}

local C = Config.Contracts
type Contract = Types.Contract

local SECONDS_PER_DAY = 86400

local function today(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

--==========================================================================
-- Wuerfeln
--==========================================================================

local function rollFor(player: Player): { Contract }
	-- Aus der UserId und dem Tag: derselbe Spieler bekommt an einem Tag
	-- ueberall dieselben drei Auftraege, egal auf welchem Server er landet.
	-- Ohne das koennte man durch Serverwechsel neu wuerfeln.
	local rng = Random.new(player.UserId * 1000003 + today())

	local pool = table.clone(C.Kinds)
	local list: { Contract } = {}

	for _ = 1, math.min(C.PerDay, #pool) do
		local index = rng:NextInteger(1, #pool)
		local kind = pool[index]
		table.remove(pool, index)

		local target = rng:NextInteger(kind.Min, kind.Max)
		table.insert(list, {
			Kind = kind.Kind,
			Target = target,
			Progress = 0,
			Reward = math.floor(target * kind.RewardPer),
			Claimed = false,
		})
	end

	return list
end

-- Tageswechsel: neue Auftraege, Serie fortschreiben oder abreissen.
local function refresh(player: Player)
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	local contracts = profile.Contracts
	local day = today()
	if contracts.Day == day then
		return
	end

	-- Serie nur halten, wenn GESTERN alles abgeholt war. Wer zwei Tage weg
	-- war, faengt wieder bei eins an - sonst ist die Serie keine Serie.
	local allDone = #contracts.List > 0
	for _, contract in contracts.List do
		if not contract.Claimed then
			allDone = false
			break
		end
	end
	if allDone and contracts.Day == day - 1 then
		contracts.Streak = math.min(contracts.Streak + 1, C.StreakCap)
	else
		contracts.Streak = 0
	end

	contracts.Day = day
	contracts.List = rollFor(player)
	SaveService.RequestSave(player)
end

--==========================================================================
-- Anzeigen
--==========================================================================

local function textFor(contract: Contract): string
	for _, kind in C.Kinds do
		if kind.Kind == contract.Kind then
			return (kind.Text):format(contract.Target)
		end
	end
	return contract.Kind
end

function ContractService.Sync(player: Player)
	local profile = SaveService.Get(player)
	if not profile or not player.Parent then
		return
	end

	local list = {}
	for index, contract in profile.Contracts.List do
		table.insert(list, {
			Index = index,
			Text = textFor(contract),
			Progress = math.min(contract.Progress, contract.Target),
			Target = contract.Target,
			Reward = contract.Reward,
			Claimed = contract.Claimed,
			Done = contract.Progress >= contract.Target,
		})
	end

	Remotes.ContractSync:FireClient(player, {
		List = list,
		Streak = profile.Contracts.Streak,
		StreakBonus = profile.Contracts.Streak * C.StreakBonus,
	})
end

--==========================================================================
-- Fortschritt
--==========================================================================

local function advance(player: Player, kind: string, amount: number)
	if amount <= 0 then
		return
	end
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	refresh(player)

	local changed = false
	for _, contract in profile.Contracts.List do
		if contract.Kind ~= kind or contract.Claimed then
			continue
		end
		if contract.Progress >= contract.Target then
			continue
		end
		contract.Progress += amount
		changed = true
	end

	if changed then
		SaveService.RequestSave(player)
		ContractService.Sync(player)
	end
end

-- Oeffentlich, damit TrafficService und PursuitService melden koennen, ohne
-- dass dieses Modul sie kennen muss. Die Richtung bleibt damit einwaertig.
function ContractService.Report(player: Player, kind: string, amount: number?)
	advance(player, kind, amount or 1)
end

--==========================================================================
-- Abholen
--==========================================================================

local function claim(player: Player, index: any)
	local profile = SaveService.Get(player)
	if not profile then
		return
	end
	if typeof(index) ~= "number" or index % 1 ~= 0 then
		return
	end

	local contract = profile.Contracts.List[index]
	if not contract then
		return
	end
	-- Beides serverseitig geprueft: der Client sagt nur, WELCHEN er meint.
	if contract.Claimed or contract.Progress < contract.Target then
		return
	end

	contract.Claimed = true

	local bonus = 1 + profile.Contracts.Streak * C.StreakBonus
	local payout = math.floor(contract.Reward * bonus)
	if C.ToBank then
		EconomyService.AwardBanked(player, payout)
	else
		EconomyService.AwardUnsold(player, payout)
	end

	SaveService.RequestSave(player)
	ContractService.Sync(player)
	print(("[GHOSTNET] %s hat ein Tagesziel abgeholt (%d CRY)."):format(player.Name, payout))
end

--==========================================================================

function ContractService.Init()
	Remotes.ContractClaim.OnServerEvent:Connect(function(player: Player, payload: any)
		if not RateLimiter.Check(player, "ContractClaim") then
			return
		end
		if typeof(payload) ~= "table" then
			return
		end
		claim(player, (payload :: any).Index)
	end)

	-- An die vorhandenen Callbacks haengen statt in fremde Module zu greifen.
	HackService.OnHackResolved(function(player: Player, info: { [string]: any })
		if info.Success == true then
			advance(player, "HACK", 1)
			local reward = info.Reward
			if typeof(reward) == "number" and reward > 0 then
				advance(player, "EARN", reward)
			end
		end
	end)

	SellService.OnSell(function(player: Player)
		advance(player, "SELL", 1)
	end)

	SaveService.OnReady(function(player: Player)
		refresh(player)
		ContractService.Sync(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		-- Falls das Profil schon vor dieser Anmeldung fertig war.
		task.defer(function()
			if SaveService.IsReady(player) then
				refresh(player)
				ContractService.Sync(player)
			end
		end)
	end)

	print(("[GHOSTNET] ContractService bereit. %d Auftraege pro Tag."):format(C.PerDay))
end

return ContractService
