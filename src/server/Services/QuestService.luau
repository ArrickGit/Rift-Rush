--!strict
-- ServerScriptService/Server/Services/QuestService.luau
-- Quest Board (game.md Step SP-6). Each UTC day every player gets the same 3 daily quests (QuestConfig.RollDaily);
-- bounties are always on the board and restart when claimed. Gameplay services report progress with
-- QuestService.Track(player, stat, amount); the client claims finished quests with the ClaimQuest remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local QuestConfig = require(Shared:WaitForChild("QuestConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

export type QuestState = {
	Id: string,
	Name: string,
	Icon: string,
	Goal: number,
	Progress: number,
	Claimed: boolean,
	Repeatable: boolean,
	RewardText: string,
}

local QuestService = {}

local CLAIM_COOLDOWN = 0.3

local notifyRemote: RemoteEvent
local celebrateRemote: RemoteEvent
local lastClaim: { [Player]: number } = {}

-- Rolls a fresh set of dailies when the UTC day changed. Returns true if it did.
local function ensureDay(profile: PlayerProfileData): boolean
	local today = QuestConfig.DayOf(os.time())
	local quests = profile.Quests
	if quests.Day == today and #quests.Daily > 0 then
		return false
	end
	quests.Day = today
	quests.Daily = QuestConfig.RollDaily(today)
	for _, id in QuestConfig.DailyPool do
		quests.Progress[id] = nil
		quests.Claimed[id] = nil
	end
	return true
end

local function activeIds(profile: PlayerProfileData): { string }
	local ids = table.clone(profile.Quests.Daily)
	for _, id in QuestConfig.Bounties do
		table.insert(ids, id)
	end
	return ids
end

-- Adds progress to every active quest counting `stat`. Does not replicate (the caller's next update will).
function QuestService.Track(player: Player, stat: string, amount: number)
	local profile = PlayerDataService.Get(player)
	if not profile or amount <= 0 then
		return
	end
	ensureDay(profile)
	for _, id in activeIds(profile) do
		local info = QuestConfig.Quests[id]
		if info and info.Stat == stat and not profile.Quests.Claimed[id] then
			local before = profile.Quests.Progress[id] or 0
			local after = math.min(info.Goal, before + amount)
			profile.Quests.Progress[id] = after
			if before < info.Goal and after >= info.Goal then
				notifyRemote:FireClient(player, ("%s Quest complete: %s — claim it at the Quest Board!"):format(info.Icon, info.Name))
			end
		end
	end
end

-- The board as the client shows it.
function QuestService.GetBoard(player: Player): { Quests: { QuestState }, ResetsIn: number }?
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	if ensureDay(profile) then
		PlayerDataService.Replicate(player)
	end
	local list: { QuestState } = {}
	for _, id in activeIds(profile) do
		local info = QuestConfig.Quests[id]
		if info then
			table.insert(list, {
				Id = id, Name = info.Name, Icon = info.Icon, Goal = info.Goal,
				Progress = profile.Quests.Progress[id] or 0, Claimed = profile.Quests.Claimed[id] == true,
				Repeatable = info.Repeatable, RewardText = QuestConfig.RewardText(info.Reward),
			})
		end
	end
	local resetsIn = (QuestConfig.DayOf(os.time()) + 1) * QuestConfig.DAY_SECONDS - os.time()
	return { Quests = list, ResetsIn = resetsIn }
end

local function claim(player: Player, questId: string)
	local profile = PlayerDataService.Get(player)
	local info = QuestConfig.Quests[questId]
	if not profile or not info then
		return
	end
	ensureDay(profile)
	if not table.find(activeIds(profile), questId) or profile.Quests.Claimed[questId] then
		return
	end
	if (profile.Quests.Progress[questId] or 0) < info.Goal then
		notifyRemote:FireClient(player, "That quest is not finished yet")
		return
	end
	local reward = info.Reward
	local ecoMult = FormulaEngine.GetRebirthInfo(profile.RebirthTier).EcoMult
	PlayerDataService.Mutate(player, function(data)
		if info.Repeatable then
			data.Quests.Progress[questId] = 0
		else
			data.Quests.Claimed[questId] = true
		end
		data.RiftDust += math.round((reward.Dust or 0) * ecoMult)
		data.BossCores += reward.BossCores or 0
		data.RelicShards += reward.RelicShards or 0
		data.AnchorTokens += reward.AnchorTokens or 0
	end)
	celebrateRemote:FireClient(player, { Kind = "Quest", Title = info.Name .. " complete!", Icon = info.Icon,
		Body = QuestConfig.RewardText(reward), Color = Color3.fromRGB(255, 205, 90) })
end

function QuestService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")
	celebrateRemote = Remotes.GetEvent("Celebrate")
	Remotes.GetEvent("ClaimQuest").OnServerEvent:Connect(function(player: Player, questId: any)
		local now = os.clock()
		if type(questId) ~= "string" or now - (lastClaim[player] or 0) < CLAIM_COOLDOWN then
			return
		end
		lastClaim[player] = now
		claim(player, questId)
	end)
	PlayerDataService.ProfileLoaded:Connect(function(_player: Player, profile: PlayerProfileData)
		ensureDay(profile)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
	end)
end

return QuestService
