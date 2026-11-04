--!strict
-- ReplicatedStorage/Shared/UpgradePoolConfig.luau
-- Run upgrades, rarities & card rolling (Section 12). Every upgrade is data: `Mods` are summed per stack into the
-- run build, and CombatService reads the totals. Only CombatService (server) rolls and applies cards; clients just
-- display the card tables it sends.
--
-- Mods keys (all additive across stacks):
--   AdditiveDmg   +% damage                   AttackSpeed  +% attack speed
--   CritRate      +crit chance                CritDamage   +crit damage multiplier
--   MaxHPMult     +% max HP                   RangeMult    +% basic-attack reach
--   ExtraTargets  +targets per basic attack   BurnOnHit    stacks of Burn applied by every hit
--   ShockOnHit    stacks of Shock applied     AbilityCasts +projectiles on the active ability (Triple Threat)
--   AbilityTrail  abilities leave flames      BurnBlast    burning enemies explode on death
-- Screen-breaking cards (game.md 6.2):
--   SizeMult      +% size of attacks / pets   EchoCast     the active ability recasts (summons double)
--   ChainReaction kills detonate (chains)     Ricochet     +bounces on projectiles, melee fires a shard
--   PinataChance  crit chance to burst Dust   Afterimage   basic attacks repeat as a phantom
--   MeteorShower  periodic meteor volleys     OrbitBlades  blades orbit and shred
--   BarrageBolts  periodic ring of bolts      AbilityCdr   -% active ability cooldown

export type Upgrade = {
	Id: string,
	Name: string,
	Desc: string,
	Rarity: string,
	Icon: string,
	MaxStacks: number,
	Mods: { [string]: number },
}

export type RollContext = {
	Stacks: { [string]: number }, -- upgrade id -> stacks already owned
	Banished: { [string]: boolean },
	Exclude: { [string]: boolean }?, -- ids already on offer
	Depth: number, -- current room number
	Luck: number, -- extra weight on Rare+ (Lucky Draw link skill, Ascension perks)
}

local UpgradePoolConfig = {}

UpgradePoolConfig.RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Corrupted" }
UpgradePoolConfig.BASE_WEIGHTS = { Common = 53, Rare = 28, Epic = 12, Legendary = 6, Corrupted = 1 } :: { [string]: number }

-- Every 5 rooms cleared moves 5 weight points out of Common (Section 12): split across the higher rarities.
local DEPTH_SHIFT_PER_5_ROOMS = 5
local DEPTH_SHIFT_SPLIT: { [string]: number } = { Rare = 0.50, Epic = 0.30, Legendary = 0.20 }
local MAX_COMMON_SHIFT = 40

UpgradePoolConfig.Upgrades = {
	{
		Id = "SharpenedEdge", Name = "Sharpened Edge", Rarity = "Common", Icon = "🗡️", MaxStacks = 5,
		Desc = "+12% damage.", Mods = { AdditiveDmg = 0.12 },
	},
	{
		Id = "SwiftHands", Name = "Swift Hands", Rarity = "Common", Icon = "⚡", MaxStacks = 5,
		Desc = "+10% attack speed.", Mods = { AttackSpeed = 0.10 },
	},
	{
		Id = "KeenEye", Name = "Keen Eye", Rarity = "Common", Icon = "🎯", MaxStacks = 5,
		Desc = "+8% critical hit rate.", Mods = { CritRate = 0.08 },
	},
	{
		Id = "VitalSurge", Name = "Vital Surge", Rarity = "Common", Icon = "❤️", MaxStacks = 5,
		Desc = "+15% Max HP and heal for the bonus.", Mods = { MaxHPMult = 0.15 },
	},
	{
		Id = "EmberEdge", Name = "Ember Edge", Rarity = "Rare", Icon = "🔥", MaxStacks = 3,
		Desc = "Attacks inflict Burn (40% Base Attack per second for 4s). Each stack adds +50% Burn damage.",
		Mods = { BurnOnHit = 1 },
	},
	{
		Id = "StormConduit", Name = "Storm Conduit", Rarity = "Rare", Icon = "🌩️", MaxStacks = 3,
		Desc = "Attacks inflict Shock: hits on a Shocked enemy chain lightning to 3 nearby enemies for 45% damage (+15% per extra stack).",
		Mods = { ShockOnHit = 1 },
	},
	{
		Id = "CleavingGale", Name = "Cleaving Gale", Rarity = "Rare", Icon = "🌀", MaxStacks = 3,
		Desc = "+20% basic attack reach and +2 targets hit per attack.", Mods = { RangeMult = 0.20, ExtraTargets = 2 },
	},
	{
		Id = "TripleThreat", Name = "Triple Threat", Rarity = "Epic", Icon = "✴️", MaxStacks = 1,
		Desc = "Your active ability fires 3 times in a fan, each for 75% damage (fan abilities gain +2 projectiles).",
		Mods = { AbilityCasts = 2 },
	},
	{
		Id = "NapalmWake", Name = "Napalm Wake", Rarity = "Epic", Icon = "♨️", MaxStacks = 1,
		Desc = "Your active ability leaves scorching flames for 4s (45% Weapon Damage per second).",
		Mods = { AbilityTrail = 1 },
	},
	{
		Id = "VolatileCinders", Name = "Volatile Cinders", Rarity = "Legendary", Icon = "💥", MaxStacks = 1,
		Desc = "Enemies that die while Burning explode for 160% damage and spread their Burn.",
		Mods = { BurnBlast = 1 },
	},

	-- Screen-breaking cards (game.md 6.2 / 7.4) ----------------------------------------------------------------
	{
		Id = "Gigantism", Name = "Gigantism", Rarity = "Legendary", Icon = "🦣", MaxStacks = 1,
		Desc = "Your swings, projectiles, pillars and spirit bolts grow 100% LARGER and deal +40% damage.",
		Mods = { SizeMult = 1.0, AdditiveDmg = 0.40 },
	},
	{
		Id = "EchoChamber", Name = "Echo Chamber", Rarity = "Epic", Icon = "🔁", MaxStacks = 1,
		Desc = "Your active ability casts again 0.25s later for 85% damage. Summons are doubled instead.",
		Mods = { EchoCast = 1 },
	},
	{
		Id = "ChainReaction", Name = "Chain Reaction", Rarity = "Legendary", Icon = "☢️", MaxStacks = 1,
		Desc = "Kills detonate a nova for 60% damage. Novas that kill detonate again (up to 5 links, 10% weaker each).",
		Mods = { ChainReaction = 1 },
	},
	{
		Id = "RicochetFrenzy", Name = "Ricochet Frenzy", Rarity = "Rare", Icon = "🪃", MaxStacks = 2,
		Desc = "Projectiles bounce to +2 more enemies. Melee hits fling a ricocheting blade shard for 40% damage.",
		Mods = { Ricochet = 2 },
	},
	{
		Id = "GoldenPinata", Name = "Golden Piñata", Rarity = "Epic", Icon = "🪅", MaxStacks = 2,
		Desc = "Critical hits have a 20% chance to burst into a fountain of Rift Dust.",
		Mods = { PinataChance = 0.20 },
	},
	{
		Id = "Afterimage", Name = "Afterimage", Rarity = "Epic", Icon = "👥", MaxStacks = 1,
		Desc = "A phantom repeats every basic attack 0.18s later for 50% damage.",
		Mods = { Afterimage = 1 },
	},
	{
		Id = "MeteorShower", Name = "Meteor Shower", Rarity = "Legendary", Icon = "☄️", MaxStacks = 1,
		Desc = "Every 6s, up to 5 meteors crash onto nearby enemies for 120% damage, exploding and Burning.",
		Mods = { MeteorShower = 1 },
	},
	{
		Id = "WhirlingBlades", Name = "Whirling Blades", Rarity = "Epic", Icon = "⚔️", MaxStacks = 3,
		Desc = "2 spectral blades orbit you, shredding nearby enemies for 35% damage per blade each second (+2 blades per stack).",
		Mods = { OrbitBlades = 2 },
	},
	{
		Id = "PrismaticBarrage", Name = "Prismatic Barrage", Rarity = "Rare", Icon = "🌈", MaxStacks = 2,
		Desc = "Every 3.5s in combat, fire a ring of 8 piercing rainbow bolts for 55% damage each (+8 bolts per stack).",
		Mods = { BarrageBolts = 8 },
	},
	{
		Id = "RiftOverdrive", Name = "Rift Overdrive", Rarity = "Rare", Icon = "⏩", MaxStacks = 2,
		Desc = "-25% active ability cooldown.",
		Mods = { AbilityCdr = 0.25 },
	},
} :: { Upgrade }

local byId: { [string]: Upgrade } = {}
for _, upgrade in UpgradePoolConfig.Upgrades do
	byId[upgrade.Id] = upgrade
end

function UpgradePoolConfig.Get(id: string): Upgrade?
	return byId[id]
end

-- Sums every owned upgrade's Mods (x stacks) into one table.
function UpgradePoolConfig.SumMods(stacks: { [string]: number }): { [string]: number }
	local totals: { [string]: number } = {}
	for id, count in stacks do
		local upgrade = byId[id]
		if upgrade then
			for key, value in upgrade.Mods do
				totals[key] = (totals[key] or 0) + value * count
			end
		end
	end
	return totals
end

local function rarityWeights(depth: number, luck: number): { [string]: number }
	local weights: { [string]: number } = {}
	for rarity, weight in UpgradePoolConfig.BASE_WEIGHTS do
		weights[rarity] = weight
	end
	local shift = math.min(MAX_COMMON_SHIFT, (math.max(1, depth) // 5) * DEPTH_SHIFT_PER_5_ROOMS)
	weights.Common -= shift
	for rarity, share in DEPTH_SHIFT_SPLIT do
		weights[rarity] += shift * share
	end
	for _, rarity in { "Rare", "Epic", "Legendary", "Corrupted" } do
		weights[rarity] *= 1 + math.max(0, luck)
	end
	return weights
end

-- Cards still available: not maxed, not banished, not already on the table.
local function availableByRarity(ctx: RollContext): { [string]: { Upgrade } }
	local buckets: { [string]: { Upgrade } } = {}
	for _, upgrade in UpgradePoolConfig.Upgrades do
		local excluded = ctx.Exclude ~= nil and ctx.Exclude[upgrade.Id] == true
		if not ctx.Banished[upgrade.Id] and not excluded and (ctx.Stacks[upgrade.Id] or 0) < upgrade.MaxStacks then
			local bucket = buckets[upgrade.Rarity]
			if not bucket then
				bucket = {}
				buckets[upgrade.Rarity] = bucket
			end
			table.insert(bucket, upgrade)
		end
	end
	return buckets
end

-- Picks one card: roll a rarity by weight (empty rarities are skipped), then a random card of that rarity.
local function rollOne(rng: Random, buckets: { [string]: { Upgrade } }, weights: { [string]: number }): Upgrade?
	local total = 0
	for rarity, bucket in buckets do
		if #bucket > 0 then
			total += weights[rarity] or 0
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, rarity in UpgradePoolConfig.RARITY_ORDER do
		local bucket = buckets[rarity]
		if bucket and #bucket > 0 then
			roll -= weights[rarity] or 0
			if roll <= 0 then
				return bucket[rng:NextInteger(1, #bucket)]
			end
		end
	end
	for _, bucket in buckets do
		if #bucket > 0 then
			return bucket[1]
		end
	end
	return nil
end

-- Returns up to `count` distinct cards (fewer when the pool is nearly exhausted).
function UpgradePoolConfig.RollCards(count: number, rng: Random, ctx: RollContext): { Upgrade }
	local weights = rarityWeights(ctx.Depth, ctx.Luck)
	local buckets = availableByRarity(ctx)
	local cards: { Upgrade } = {}
	for _ = 1, count do
		local card = rollOne(rng, buckets, weights)
		if not card then
			break
		end
		table.insert(cards, card)
		local bucket = buckets[card.Rarity]
		local index = table.find(bucket, card)
		if index then
			table.remove(bucket, index)
		end
	end
	return cards
end

return UpgradePoolConfig
