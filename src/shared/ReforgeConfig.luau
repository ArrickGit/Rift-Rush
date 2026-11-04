--!strict
-- ReplicatedStorage/Shared/ReforgeConfig.luau
-- Weapon Reforge / Aura rolling at the Blacksmith (game.md 6.1 / 7.4 B). Every owned weapon can be rolled for a
-- tiered prefix with a permanent stat bonus and a visible aura. Odds are public (shown in the Blacksmith) and two
-- pity counters guarantee Epic+ by roll 13 and Legendary+ by roll 60 since the last such hit.
--
-- InventoryService rolls and stores the result in profile.WeaponReforge; CombatService reads the equipped weapon's
-- tier (damage via FormulaEngine ReforgeDmg, crit / attack speed / size / extra wave in its attack context) and
-- WeaponHoldService draws the aura on the held weapon.

export type Tier = {
	Id: string, -- rarity: Common | Rare | Epic | Legendary | Mythic
	Name: string, -- weapon prefix
	Weight: number, -- percent
	Dmg: number, -- +% damage (account multiplier)
	AtkSpeed: number, -- +% attack speed
	Crit: number, -- +crit chance
	Size: number, -- +% size of attacks (multiplies Gigantism)
	Extra: number, -- extra projectiles / slash waves per basic attack
	Color: Color3,
	Icon: string,
}

-- Mirrors PlayerDataService.ReforgeEntry (kept structural so the shared module needs no server types).
type Entry = { Tier: string?, Rolls: number, PityEpic: number, PityLegend: number, Pending: string? }

local ReforgeConfig = {}

ReforgeConfig.PITY_EPIC = 13 -- rolls since the last Epic+ that guarantee one
ReforgeConfig.PITY_LEGEND = 60 -- rolls since the last Legendary+ that guarantee one
ReforgeConfig.BASE_COST = 200
ReforgeConfig.COST_FRACTION = 0.25 -- of the weapon's forge price
ReforgeConfig.CORE_COST = 1

ReforgeConfig.Tiers = {
	{ Id = "Common", Name = "Sharp", Weight = 60, Dmg = 0.10, AtkSpeed = 0, Crit = 0, Size = 0, Extra = 0,
		Color = Color3.fromRGB(235, 240, 255), Icon = "⚪" },
	{ Id = "Rare", Name = "Stormforged", Weight = 25, Dmg = 0.25, AtkSpeed = 0.10, Crit = 0, Size = 0, Extra = 0,
		Color = Color3.fromRGB(90, 170, 255), Icon = "🌩️" },
	{ Id = "Epic", Name = "Void-Touched", Weight = 10, Dmg = 0.50, AtkSpeed = 0, Crit = 0, Size = 0, Extra = 1,
		Color = Color3.fromRGB(180, 90, 255), Icon = "🌌" },
	{ Id = "Legendary", Name = "Celestial", Weight = 4, Dmg = 1.00, AtkSpeed = 0, Crit = 0.20, Size = 0, Extra = 0,
		Color = Color3.fromRGB(255, 205, 60), Icon = "👼" },
	{ Id = "Mythic", Name = "Rift Sovereign", Weight = 1, Dmg = 2.00, AtkSpeed = 0, Crit = 0, Size = 0.40, Extra = 0,
		Color = Color3.fromRGB(255, 45, 70), Icon = "🔥" },
} :: { Tier }

local byId: { [string]: Tier } = {}
local rankOf: { [string]: number } = {}
for index, tier in ReforgeConfig.Tiers do
	byId[tier.Id] = tier
	rankOf[tier.Id] = index
end

function ReforgeConfig.Get(tierId: string?): Tier?
	return if tierId then byId[tierId] else nil
end

-- 1 = Common ... 5 = Mythic (0 for no tier).
function ReforgeConfig.Rank(tierId: string?): number
	return if tierId then rankOf[tierId] or 0 else 0
end

-- The tier applied to `weaponId` in a profile's WeaponReforge table, if any.
function ReforgeConfig.ForWeapon(reforges: { [string]: any }?, weaponId: string): Tier?
	local entry = if reforges then reforges[weaponId] else nil
	return if type(entry) == "table" then ReforgeConfig.Get(entry.Tier) else nil
end

-- Rift Dust per roll for a weapon with the given forge price (Boss Cores are always CORE_COST).
function ReforgeConfig.Cost(unlockCost: number): number
	return ReforgeConfig.BASE_COST + math.round(ReforgeConfig.COST_FRACTION * unlockCost)
end

-- Rolls one tier, honouring pity, and advances the entry's pity counters in place.
function ReforgeConfig.Roll(rng: Random, entry: Entry): Tier
	local minRank = 1
	if entry.PityLegend + 1 >= ReforgeConfig.PITY_LEGEND then
		minRank = rankOf.Legendary
	elseif entry.PityEpic + 1 >= ReforgeConfig.PITY_EPIC then
		minRank = rankOf.Epic
	end
	local total = 0
	for index, tier in ReforgeConfig.Tiers do
		if index >= minRank then
			total += tier.Weight
		end
	end
	local roll = rng:NextNumber() * total
	local picked = ReforgeConfig.Tiers[#ReforgeConfig.Tiers]
	for index, tier in ReforgeConfig.Tiers do
		if index >= minRank then
			roll -= tier.Weight
			if roll <= 0 then
				picked = tier
				break
			end
		end
	end
	local rank = rankOf[picked.Id]
	entry.PityEpic = if rank >= rankOf.Epic then 0 else entry.PityEpic + 1
	entry.PityLegend = if rank >= rankOf.Legendary then 0 else entry.PityLegend + 1
	return picked
end

return ReforgeConfig
