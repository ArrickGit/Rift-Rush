--!strict
-- ServerScriptService/Server/Services/RelicService.luau
-- Relics & the Star-Force Forge (game.md Section 7 / Step SP-5).
--   * Drops: RunManagerService calls RelicDropHandler on every boss Anchor (Room 5: 35%, Room 10: 100%) and opened
--     chest (25%). A new relic joins the permanent collection at 1 Star and is active for the rest of the run; a
--     duplicate becomes +5 Relic Shards in the Unsecured Pouch.
--   * Run relics: equipped Starting Relics are active from Room 1. GetActive(player) is what CombatService reads;
--     the list is mirrored to the "RunRelics" player attribute ("REL_01:2,REL_04:1") for the HUD.
--   * Star-Force: StarForce { Relic, Safeguard } spends Relic Shards + Rift Dust for a chance at the next Star.
--     Failure is non-destructive and adds +25% pity; a Safeguard refunds the Shards of a failed attempt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))

type Run = RunManagerService.Run

local RelicService = {}

local FORGE_COOLDOWN = 0.6
local NODE_RELIC_RESONANCE = "AS_T3_02"

type RunRelics = { RunId: number, Relics: { [string]: number } }

local active: { [Player]: RunRelics } = {}
local lastForge: { [Player]: number } = {}
local rng = Random.new()
local notifyRemote: RemoteEvent
local celebrateRemote: RemoteEvent

local function publishAttribute(player: Player)
	local state = active[player]
	if not state then
		player:SetAttribute("RunRelics", nil)
		return
	end
	local parts: { string } = {}
	for _, relicId in RelicConfig.Order do
		local stars = state.Relics[relicId]
		if stars then
			table.insert(parts, ("%s:%d"):format(relicId, stars))
		end
	end
	player:SetAttribute("RunRelics", table.concat(parts, ","))
end

-- Relics active for the player's current run: { [relicId] = stars }. Empty outside a run.
function RelicService.GetActive(player: Player): { [string]: number }
	local state = active[player]
	local runId = player:GetAttribute("RunId")
	if state and state.RunId == runId then
		return state.Relics
	end
	return {}
end

local function beginRun(player: Player, runId: number)
	local profile = PlayerDataService.Get(player)
	local relics: { [string]: number } = {}
	if profile then
		for _, relicId in profile.EquippedStartingRelics do
			local owned = profile.RelicStars[relicId]
			if owned then
				relics[relicId] = owned.Stars
			end
		end
	end
	active[player] = { RunId = runId, Relics = relics }
	publishAttribute(player)
end

local function onDrop(player: Player, run: Run, source: string)
	local chance = if source == "Chest" then RelicConfig.CHEST_DROP_CHANCE else (RelicConfig.BOSS_DROP_CHANCE[source] or 0)
	if run.Rng:NextNumber() >= chance then
		return
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local relicId = RelicConfig.Order[rng:NextInteger(1, #RelicConfig.Order)]
	local info = RelicConfig.Relics[relicId]
	local owned = profile.RelicStars[relicId]
	if owned then
		RunManagerService.AddUnsecured(player, { Dust = 0, BossCores = 0, RelicShards = RelicConfig.DUPLICATE_SHARDS })
		notifyRemote:FireClient(player, ("%s Duplicate %s converted into +%d Relic Shards!"):format(info.Icon, info.Name,
			RelicConfig.DUPLICATE_SHARDS))
	else
		PlayerDataService.Mutate(player, function(data)
			data.RelicStars[relicId] = { Stars = 1, PityCount = 0 }
		end)
		PlayerDataService.BumpStat(player, "RelicsFound", 1)
		celebrateRemote:FireClient(player, { Kind = "Relic", Title = "New Relic: " .. info.Name, Icon = info.Icon,
			Body = RelicConfig.Describe(relicId, 1), Color = info.Color })
	end
	-- Either way the relic powers the rest of this run (at the player's best Star level).
	local state = active[player]
	if state and state.RunId == run.Id then
		local stars = if profile.RelicStars[relicId] then profile.RelicStars[relicId].Stars else 1
		state.Relics[relicId] = math.max(state.Relics[relicId] or 0, stars)
		publishAttribute(player)
	end
	QuestService.Track(player, "RelicsFound", 1)
end

local function forge(player: Player, relicId: string, useSafeguard: boolean)
	local profile = PlayerDataService.Get(player)
	local info = RelicConfig.Relics[relicId]
	if not profile or not info then
		return
	end
	if RunManagerService.GetRunOf(player) then
		notifyRemote:FireClient(player, "The Star-Forge only works in Haven Outpost")
		return
	end
	local owned = profile.RelicStars[relicId]
	if not owned then
		notifyRemote:FireClient(player, "Find that Relic in a run first")
		return
	end
	local quote = RelicConfig.GetForgeQuote(owned.Stars)
	if not quote then
		notifyRemote:FireClient(player, info.Name .. " is already 5-Star!")
		return
	end
	if profile.RelicShards < quote.Shards or profile.RiftDust < quote.Dust then
		notifyRemote:FireClient(player, ("Need %d Relic Shards and %d Rift Dust"):format(quote.Shards, quote.Dust))
		return
	end
	local guarded = useSafeguard and profile.StarForceSafeguards > 0
	local chance = RelicConfig.GetForgeChance(owned.Stars, owned.PityCount, profile.AscensionNodes[NODE_RELIC_RESONANCE] or 0)
	local success = rng:NextNumber() < chance
	PlayerDataService.Mutate(player, function(data)
		data.RiftDust -= quote.Dust
		local entry = data.RelicStars[relicId]
		if success then
			entry.Stars += 1
			entry.PityCount = 0
			data.RelicShards -= quote.Shards
		else
			entry.PityCount += 1
			if guarded then
				data.StarForceSafeguards -= 1
			else
				data.RelicShards -= quote.Shards
			end
		end
	end)
	if success then
		local stars = owned.Stars
		celebrateRemote:FireClient(player, { Kind = "Relic", Title = ("%s reached %d★!"):format(info.Name, stars),
			Icon = info.Icon, Body = RelicConfig.Describe(relicId, stars), Color = info.Color })
	else
		notifyRemote:FireClient(player, ("💥 Star-Force failed%s. Pity +%d%% (next try %d%%)"):format(
			if guarded then " — Safeguard refunded your Shards" else "",
			math.round(RelicConfig.PITY_PER_FAILURE * 100),
			math.round(RelicConfig.GetForgeChance(owned.Stars, owned.PityCount, profile.AscensionNodes[NODE_RELIC_RESONANCE] or 0) * 100)))
	end
end

-- Studio test hook (DevCommandsService): make a relic active in the player's current run.
function RelicService.DevActivate(player: Player, relicId: string, stars: number)
	local state = active[player]
	if state then
		state.Relics[relicId] = stars
		publishAttribute(player)
	end
end

function RelicService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")
	celebrateRemote = Remotes.GetEvent("Celebrate")
	RunManagerService.RelicDropHandler = onDrop

	Remotes.GetEvent("StarForce").OnServerEvent:Connect(function(player: Player, payload: any)
		local now = os.clock()
		if type(payload) ~= "table" or type(payload.Relic) ~= "string" or now - (lastForge[player] or 0) < FORGE_COOLDOWN then
			return
		end
		lastForge[player] = now
		forge(player, payload.Relic, payload.Safeguard == true)
	end)

	local function watch(player: Player)
		player:GetAttributeChangedSignal("RunId"):Connect(function()
			local runId = player:GetAttribute("RunId")
			if type(runId) == "number" then
				beginRun(player, runId)
			else
				active[player] = nil
				publishAttribute(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		active[player] = nil
		lastForge[player] = nil
	end)
end

return RelicService
