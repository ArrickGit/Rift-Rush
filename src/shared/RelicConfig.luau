--!strict
-- ReplicatedStorage/Shared/RelicConfig.luau
-- The starter 8-Relic pool and the Star-Force Forge (game.md Section 7). Every number a relic uses comes from
-- RelicConfig.Value so the server (CombatService / RelicService) and the UI describe the same thing.
--
-- Drops: Room 5 boss 35%, Room 10 boss 100%, Treasure Chests 25%. First discovery unlocks the relic at 1 Star;
-- duplicates turn into Relic Shards. A relic found mid-run is active for the rest of that run; Starting Relics
-- (1 slot, +1 Twin Relic Vessel, +1 Starting Relic Vault Key pass) are active from Room 1.

export type RelicInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Color: Color3,
	Desc: string, -- uses %s placeholders filled by Describe()
	StarDesc: string, -- what each extra Star adds
}

local RelicConfig = {}

RelicConfig.MAX_STARS = 5
RelicConfig.DUPLICATE_SHARDS = 5
RelicConfig.BOSS_DROP_CHANCE = { MiniBoss = 0.35, WorldBoss = 1.0 } :: { [string]: number }
RelicConfig.CHEST_DROP_CHANCE = 0.25
RelicConfig.BASE_STARTING_SLOTS = 1
RelicConfig.PITY_PER_FAILURE = 0.25

RelicConfig.Order = { "REL_01", "REL_02", "REL_03", "REL_04", "REL_05", "REL_06", "REL_07", "REL_08" }

RelicConfig.Relics = {
	REL_01 = { Id = "REL_01", Name = "Frost Heart", Icon = "❄️", Color = Color3.fromRGB(140, 220, 255),
		Desc = "Taking damage freezes enemies within 12 studs for 2.5s (%s Weapon Damage) and grants a %s HP barrier. 8s cooldown.",
		StarDesc = "+20% freeze damage & barrier per Star" },
	REL_02 = { Id = "REL_02", Name = "Treasure Tooth", Icon = "🦷", Color = Color3.fromRGB(255, 205, 90),
		Desc = "Opening a chest or reaching a Rift Anchor grants +%s Damage for the run (stacks 10x).",
		StarDesc = "+2% per stack per Star" },
	REL_03 = { Id = "REL_03", Name = "Thunder Boots", Icon = "⚡", Color = Color3.fromRGB(255, 240, 110),
		Desc = "Every dash fires %s homing lightning bolts dealing %s Weapon Damage and inflicting Shock.",
		StarDesc = "+1 bolt and +15% damage per Star" },
	REL_04 = { Id = "REL_04", Name = "Hungry Coin", Icon = "🪙", Color = Color3.fromRGB(255, 190, 40),
		Desc = "+%s Rift Dust. 2 golden coins orbit you, dealing %s Weapon Damage per second to enemies they touch.",
		StarDesc = "+5% Dust and +15% orbit damage per Star" },
	REL_05 = { Id = "REL_05", Name = "Phoenix Feather", Icon = "🪶", Color = Color3.fromRGB(255, 120, 50),
		Desc = "Once per run, fatal damage instead heals you to %s Max HP and triggers a fiery 3s invulnerability blast.",
		StarDesc = "+10% heal per Star" },
	REL_06 = { Id = "REL_06", Name = "Vampiric Fang", Icon = "🧛", Color = Color3.fromRGB(220, 50, 80),
		Desc = "Critical hits heal you for %s of your Max HP (0.5s cooldown).",
		StarDesc = "+0.5% Max HP heal per Star" },
	REL_07 = { Id = "REL_07", Name = "Broken Crown", Icon = "👑", Color = Color3.fromRGB(230, 180, 255),
		Desc = "+%s damage to Bosses & Elites, and +35%% more damage while you are below 50%% HP.",
		StarDesc = "+6% Boss damage per Star" },
	REL_08 = { Id = "REL_08", Name = "Volatile Hourglass", Icon = "⏳", Color = Color3.fromRGB(150, 120, 255),
		Desc = "-%s Q Ability cooldown. Casting Q emits an arcane pulse dealing %s Weapon Damage.",
		StarDesc = "+4% CDR and +25% pulse damage per Star" },
} :: { [string]: RelicInfo }

-- The numbers each relic uses at a given star level (1-5). Keys are documented beside each relic's hook.
function RelicConfig.Value(relicId: string, stars: number): { [string]: number }
	local s = math.clamp(math.floor(stars), 1, RelicConfig.MAX_STARS) - 1 -- extra stars beyond the first
	if relicId == "REL_01" then
		return { Radius = 12, Freeze = 2.5, Mult = 0.8 * (1 + 0.2 * s), Barrier = 0.10 * (1 + 0.2 * s), Cooldown = 8 }
	elseif relicId == "REL_02" then
		return { PerStack = 0.06 + 0.02 * s, MaxStacks = 10 }
	elseif relicId == "REL_03" then
		return { Bolts = 2 + s, Mult = 0.55 + 0.15 * s }
	elseif relicId == "REL_04" then
		return { Dust = 0.15 + 0.05 * s, OrbitDps = 0.40 + 0.15 * s, OrbitRadius = 4.5 }
	elseif relicId == "REL_05" then
		return { Heal = 0.50 + 0.10 * s, Invuln = 3, BlastMult = 1.5, BlastRadius = 12 }
	elseif relicId == "REL_06" then
		return { Heal = 0.015 + 0.005 * s, Cooldown = 0.5 }
	elseif relicId == "REL_07" then
		return { BossElite = 0.25 + 0.06 * s, LowHp = 0.35 }
	elseif relicId == "REL_08" then
		return { Cdr = 0.18 + 0.04 * s, PulseMult = 1.0 + 0.25 * s, PulseRadius = 10 }
	end
	return {}
end

local function pct(value: number): string
	local scaled = value * 100
	return if math.abs(scaled - math.round(scaled)) < 0.05 then ("%d%%"):format(math.round(scaled)) else ("%.1f%%"):format(scaled)
end

-- Human-readable effect text for a relic at a star level.
function RelicConfig.Describe(relicId: string, stars: number): string
	local info = RelicConfig.Relics[relicId]
	if not info then
		return ""
	end
	local v = RelicConfig.Value(relicId, stars)
	if relicId == "REL_01" then
		return info.Desc:format(pct(v.Mult), pct(v.Barrier))
	elseif relicId == "REL_02" then
		return info.Desc:format(pct(v.PerStack))
	elseif relicId == "REL_03" then
		return info.Desc:format(tostring(v.Bolts), pct(v.Mult))
	elseif relicId == "REL_04" then
		return info.Desc:format(pct(v.Dust), pct(v.OrbitDps))
	elseif relicId == "REL_05" then
		return info.Desc:format(pct(v.Heal))
	elseif relicId == "REL_06" then
		return info.Desc:format(pct(v.Heal))
	elseif relicId == "REL_07" then
		return info.Desc:format(pct(v.BossElite))
	elseif relicId == "REL_08" then
		return info.Desc:format(pct(v.Cdr), pct(v.PulseMult))
	end
	return info.Desc
end

-- Star-Force cost and base success chance to go from `stars` to `stars + 1` (nil at max).
export type ForgeQuote = { Shards: number, Dust: number, BaseChance: number }

local FORGE_TABLE: { [number]: ForgeQuote } = {
	[1] = { Shards = 5, Dust = 250, BaseChance = 0.90 },
	[2] = { Shards = 10, Dust = 1000, BaseChance = 0.70 },
	[3] = { Shards = 15, Dust = 2500, BaseChance = 0.50 },
	[4] = { Shards = 25, Dust = 5000, BaseChance = 0.30 },
}

function RelicConfig.GetForgeQuote(stars: number): ForgeQuote?
	return FORGE_TABLE[stars]
end

-- Success chance including Relic Resonance (+3% per level) and the pity bar (+25% per failed attempt).
function RelicConfig.GetForgeChance(stars: number, pityCount: number, resonanceLevel: number): number
	local quote = FORGE_TABLE[stars]
	if not quote then
		return 0
	end
	return math.clamp(quote.BaseChance + 0.03 * resonanceLevel + RelicConfig.PITY_PER_FAILURE * pityCount, 0, 1)
end

-- Starting Relic slots: 1, +1 Twin Relic Vessel (AS_T3_03), +1 Starting Relic Vault Key pass.
function RelicConfig.GetStartingSlots(twinVesselLevel: number, hasVaultKey: boolean): number
	return RelicConfig.BASE_STARTING_SLOTS + math.min(1, twinVesselLevel) + (if hasVaultKey then 1 else 0)
end

return RelicConfig
