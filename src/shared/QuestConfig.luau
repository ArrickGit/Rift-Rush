--!strict
-- ReplicatedStorage/Shared/QuestConfig.luau
-- Quest Board (game.md Step SP-6): 3 daily quests drawn from a pool each UTC day, plus repeatable bounties that
-- restart as soon as they are claimed. Progress is counted from lifetime-stat events (QuestService.Track) and
-- rewards are paid by the server only.

export type Reward = { Dust: number?, BossCores: number?, RelicShards: number?, AnchorTokens: number? }

export type QuestInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Stat: string, -- event key passed to QuestService.Track
	Goal: number,
	Reward: Reward,
	Repeatable: boolean,
}

local QuestConfig = {}

QuestConfig.DAILY_COUNT = 3
QuestConfig.DAY_SECONDS = 86400

QuestConfig.Quests = {
	D_Sweeper = { Id = "D_Sweeper", Name = "Spore Sweeper", Icon = "🍄", Stat = "Kills", Goal = 60,
		Reward = { Dust = 250 }, Repeatable = false },
	D_Elites = { Id = "D_Elites", Name = "Elite Hunter", Icon = "⚔️", Stat = "EliteKills", Goal = 6,
		Reward = { Dust = 150, BossCores = 1 }, Repeatable = false },
	D_Giants = { Id = "D_Giants", Name = "Giant Slayer", Icon = "👹", Stat = "BossKills", Goal = 2,
		Reward = { BossCores = 2 }, Repeatable = false },
	D_Diver = { Id = "D_Diver", Name = "Deep Diver", Icon = "🌀", Stat = "RoomsCleared", Goal = 12,
		Reward = { Dust = 350 }, Repeatable = false },
	D_Treasure = { Id = "D_Treasure", Name = "Treasure Seeker", Icon = "🎁", Stat = "ChestsOpened", Goal = 5,
		Reward = { RelicShards = 5 }, Repeatable = false },
	D_Extract = { Id = "D_Extract", Name = "Safe Return", Icon = "🏁", Stat = "Extractions", Goal = 2,
		Reward = { AnchorTokens = 1 }, Repeatable = false },
	D_Banker = { Id = "D_Banker", Name = "Dust Banker", Icon = "🔮", Stat = "DustBanked", Goal = 1500,
		Reward = { RelicShards = 3, AnchorTokens = 1 }, Repeatable = false },
	D_Pact = { Id = "D_Pact", Name = "Pact Maker", Icon = "🍷", Stat = "CursesAccepted", Goal = 1,
		Reward = { RelicShards = 4 }, Repeatable = false },
	D_Jumper = { Id = "D_Jumper", Name = "Spore Climber", Icon = "🧗", Stat = "JumpRooms", Goal = 2,
		Reward = { Dust = 200, RelicShards = 2 }, Repeatable = false },

	B_Monsters = { Id = "B_Monsters", Name = "Monster Bounty", Icon = "📜", Stat = "Kills", Goal = 40,
		Reward = { Dust = 120 }, Repeatable = true },
	B_Boss = { Id = "B_Boss", Name = "Boss Bounty", Icon = "💀", Stat = "BossKills", Goal = 1,
		Reward = { Dust = 80, BossCores = 1 }, Repeatable = true },
} :: { [string]: QuestInfo }

QuestConfig.DailyPool = { "D_Sweeper", "D_Elites", "D_Giants", "D_Diver", "D_Treasure", "D_Extract", "D_Banker", "D_Pact", "D_Jumper" }
QuestConfig.Bounties = { "B_Monsters", "B_Boss" }

-- UTC day number for a unix time.
function QuestConfig.DayOf(unixTime: number): number
	return unixTime // QuestConfig.DAY_SECONDS
end

-- The same 3 daily quests for everyone on a given day.
function QuestConfig.RollDaily(day: number): { string }
	local rng = Random.new(day * 7919 + 17)
	local pool = table.clone(QuestConfig.DailyPool)
	local picked: { string } = {}
	for _ = 1, math.min(QuestConfig.DAILY_COUNT, #pool) do
		table.insert(picked, table.remove(pool, rng:NextInteger(1, #pool)) :: string)
	end
	return picked
end

function QuestConfig.RewardText(reward: Reward): string
	local parts: { string } = {}
	if reward.Dust then
		table.insert(parts, ("🔮 %d"):format(reward.Dust))
	end
	if reward.BossCores then
		table.insert(parts, ("☀️ %d"):format(reward.BossCores))
	end
	if reward.RelicShards then
		table.insert(parts, ("💎 %d"):format(reward.RelicShards))
	end
	if reward.AnchorTokens then
		table.insert(parts, ("⏳ %d"):format(reward.AnchorTokens))
	end
	return table.concat(parts, "  ")
end

return QuestConfig
