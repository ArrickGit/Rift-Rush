--!strict
-- ReplicatedStorage/Shared/AscensionShopConfig.luau
-- Every Ascension Shop node from Section 23. Costs are per level (index = level being bought).

export type AscensionNode = {
	Id: string,
	Name: string,
	Tier: number, -- 1-4 (gated by Rebirth tier below)
	MaxLevel: number, -- math.huge for infinite sinks (capped by InfiniteCap)
	Costs: { number }, -- Spark cost for each level; empty when FlatCost is used
	FlatCost: number?, -- infinite nodes: constant cost per level
	Desc: string,
	EffectPerLevel: string,
	ComingSoon: boolean?, -- shown in the tree but not sold until its effect is implemented
}

local AscensionShopConfig = {}

AscensionShopConfig.INFINITE_CAP = 999

-- Rebirth tier required to unlock each shop tier
AscensionShopConfig.TierUnlockRebirth = { [1] = 1, [2] = 3, [3] = 5, [4] = 10 } :: { [number]: number }

AscensionShopConfig.Order = {
	"AS_T1_01", "AS_T1_02", "AS_T1_03", "AS_T1_04", "AS_T1_05",
	"AS_T2_01", "AS_T2_02", "AS_T2_03", "AS_T2_04",
	"AS_T3_01", "AS_T3_02", "AS_T3_03", "AS_T3_04",
	"AS_T4_01", "AS_T4_02",
	"AS_INF_01", "AS_INF_02",
}

AscensionShopConfig.Nodes = {
	-- Tier 1: Initiate Ascendant
	AS_T1_01 = { Id = "AS_T1_01", Name = "Ascendant Might", Tier = 1, MaxLevel = 10,
		Costs = { 1, 1, 1, 2, 2, 2, 3, 3, 4, 5 },
		Desc = "Multiplicative Ascension Damage & HP.", EffectPerLevel = "+8% Damage & HP" },
	AS_T1_02 = { Id = "AS_T1_02", Name = "Rift Scholar", Tier = 1, MaxLevel = 5,
		Costs = { 1, 1, 2, 2, 3 },
		Desc = "Bonus Hunter XP & Weapon Mastery XP.", EffectPerLevel = "+12% Hunter & Mastery XP" },
	AS_T1_03 = { Id = "AS_T1_03", Name = "Vacuum Aura (Auto-Magnet)", Tier = 1, MaxLevel = 3,
		Costs = { 1, 2, 3 },
		Desc = "Lv1 +15 stud pickup radius, Lv2 +35, Lv3 full-room instant loot magnet (+10% Gold Find).",
		EffectPerLevel = "Larger loot magnet" },
	AS_T1_04 = { Id = "AS_T1_04", Name = "Headstart Blessing", Tier = 1, MaxLevel = 3,
		Costs = { 2, 3, 4 },
		Desc = "Free Upgrade Orb in Room 1: Common+, then Rare+, then Epic+.", EffectPerLevel = "Better Room 1 orb" },
	AS_T1_05 = { Id = "AS_T1_05", Name = "Dimensional Pocket", Tier = 1, MaxLevel = 4,
		Costs = { 1, 2, 2, 3 },
		Desc = "Routes earned Rift Dust into your Rebirth-safe vault after each run.", EffectPerLevel = "+15% Dust protected" },

	-- Tier 2: Rift Weaver
	AS_T2_01 = { Id = "AS_T2_01", Name = "Skywalker's Grace", Tier = 2, MaxLevel = 3,
		Costs = { 2, 3, 4 },
		Desc = "Lv1 +10% move/jump, Lv2 +1 Dash charge, Lv3 Triple Jump & -20% Dash cooldown.",
		EffectPerLevel = "Mobility" },
	AS_T2_02 = { Id = "AS_T2_02", Name = "Fate Manipulation", Tier = 2, MaxLevel = 3,
		Costs = { 2, 2, 3 },
		Desc = "Free Upgrade Reroll and Banish charge per run.", EffectPerLevel = "+1 Reroll & +1 Banish" },
	AS_T2_03 = { Id = "AS_T2_03", Name = "Anchor Guardian", Tier = 2, MaxLevel = 4,
		Costs = { 2, 2, 3, 3 },
		Desc = "Less Unsecured Loot lost on defeat; heals at every Rift Anchor.", EffectPerLevel = "-10% loot loss, +25% heal" },
	AS_T2_04 = { Id = "AS_T2_04", Name = "Boss Hunter's Trophy", Tier = 2, MaxLevel = 5,
		Costs = { 2, 2, 3, 4, 5 },
		Desc = "Chance for bosses to drop an extra Boss Core and Relic Shard.", EffectPerLevel = "+20% extra drop chance" },

	-- Tier 3: Sovereign of the Rift
	AS_T3_01 = { Id = "AS_T3_01", Name = "Elemental Crit Overload", Tier = 3, MaxLevel = 3,
		Costs = { 3, 4, 5 },
		Desc = "Status effects can Critically Hit for 33% / 66% / 100% of your Crit Damage.", EffectPerLevel = "+33% status crit" },
	AS_T3_02 = { Id = "AS_T3_02", Name = "Relic Resonance", Tier = 3, MaxLevel = 5,
		Costs = { 2, 3, 3, 4, 5 },
		Desc = "Boosts Relic passives and Star-Force success rates.", EffectPerLevel = "+10% Relic effect, +3% Star-Force" },
	AS_T3_03 = { Id = "AS_T3_03", Name = "Twin Relic Vessel", Tier = 3, MaxLevel = 1,
		Costs = { 10 },
		Desc = "Unlocks a 2nd permanent starting Relic slot.", EffectPerLevel = "+1 Starting Relic slot" },
	AS_T3_04 = { Id = "AS_T3_04", Name = "Legion Commander", Tier = 3, MaxLevel = 2,
		Costs = { 5, 7 },
		Desc = "Unlocks an extra active Hunter Legion Link Skill slot per level.", EffectPerLevel = "+1 Link slot" },

	-- Tier 4: Transcendent
	AS_T4_01 = { Id = "AS_T4_01", Name = "Limit Breaker (Multi-Strike)", Tier = 4, MaxLevel = 3,
		Costs = { 8, 10, 12 },
		Desc = "Every attack hits an additional time (Shadow Line) for 15% of hit damage.", EffectPerLevel = "+1 Shadow Line" },
	AS_T4_02 = { Id = "AS_T4_02", Name = "Miracle Evolution", Tier = 4, MaxLevel = 1,
		Costs = { 15 },
		Desc = "Upgrade Orbs have a 15% chance to be Double Orbs (pick 2).", EffectPerLevel = "15% Double Orb" },

	-- Infinite sinks (Rebirth XI+)
	AS_INF_01 = { Id = "AS_INF_01", Name = "Infinite Spark: Omnipotence", Tier = 4, MaxLevel = 999,
		Costs = {}, FlatCost = 3,
		Desc = "Additive Ascension Damage multiplier.", EffectPerLevel = "+5% Damage" },
	AS_INF_02 = { Id = "AS_INF_02", Name = "Infinite Spark: Prosperity", Tier = 4, MaxLevel = 999,
		Costs = {}, FlatCost = 3,
		Desc = "Additive Rift Dust & Hunter XP bonus.", EffectPerLevel = "+5% Dust & XP" },
} :: { [string]: AscensionNode }

function AscensionShopConfig.GetNode(nodeId: string): AscensionNode?
	return AscensionShopConfig.Nodes[nodeId]
end

-- Spark cost to buy the NEXT level (currentLevel -> currentLevel + 1), or nil if maxed / invalid.
function AscensionShopConfig.GetNextCost(nodeId: string, currentLevel: number): number?
	local node = AscensionShopConfig.Nodes[nodeId]
	if not node or currentLevel >= node.MaxLevel then
		return nil
	end
	if node.FlatCost then
		return node.FlatCost
	end
	return node.Costs[currentLevel + 1]
end

function AscensionShopConfig.IsTierUnlocked(tier: number, rebirthTier: number): boolean
	local required = AscensionShopConfig.TierUnlockRebirth[tier]
	return required ~= nil and rebirthTier >= required
end

-- Total sparks spent given a levels table (used by respec refunds).
function AscensionShopConfig.GetTotalSpent(levels: { [string]: number }): number
	local total = 0
	for nodeId, lv in levels do
		local node = AscensionShopConfig.Nodes[nodeId]
		if node then
			for i = 1, lv do
				total += if node.FlatCost then node.FlatCost else (node.Costs[i] or 0)
			end
		end
	end
	return total
end

return AscensionShopConfig
