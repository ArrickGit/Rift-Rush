--!strict
-- ReplicatedStorage/Shared/WeaponConfig.luau
-- All 8 weapons, base stats & Hunter Legion Link Skills (Section 10)

export type LinkSkill = {
	Id: string,
	Name: string,
	Stat: string, -- key consumed by FormulaEngine / CombatService
	Lv10: number,
	Lv20: number,
}

-- Basic attack: a short melee box in front of the player, or a straight bolt. Reach/height are in studs; the melee box
-- starts `Back` studs behind the player's root part. Only Greatsword, Daggers and Staff have profiles so far
-- (Step 4); other weapons fall back to WeaponConfig.GenericAttack.
export type AttackProfile = {
	Kind: "Melee" | "Projectile",
	Range: number, -- Melee: reach in front. Projectile: travel distance.
	Back: number?,
	Height: number, -- Melee: half-height of the hit box
	MaxTargets: number,
	Mult: number, -- skill multiplier
	Speed: number?, -- Projectile
	HalfSize: number?, -- Projectile half-extent
	Style: string, -- visual style key for CombatVFXController
}

-- Active ability (Q): one or more projectiles in a fan. Mult is per projectile.
export type AbilityProfile = {
	Id: string,
	Name: string,
	Desc: string,
	Cooldown: number,
	Count: number,
	FanDeg: number, -- angle between neighbouring projectiles
	Mult: number,
	Speed: number,
	Life: number,
	HalfX: number,
	HalfY: number,
	Pierce: boolean,
	ExplodeRadius: number?, -- explodes on the first enemy hit
	Burn: boolean?,
	Style: string,
}

export type WeaponInfo = {
	Id: string,
	Name: string,
	Archetype: string,
	BaseDamage: number, -- W_Base
	AttacksPerSecond: number,
	PassiveName: string,
	PassiveDesc: string,
	Link: LinkSkill,
	UnlockCost: number, -- Rift Dust (0 = unlocked by default)
	Accent: Color3,
	Attack: AttackProfile?,
	Ability: AbilityProfile?,
}

local WeaponConfig = {}

WeaponConfig.DEFAULT_WEAPON = "Greatsword"
WeaponConfig.MAX_MASTERY = 20

WeaponConfig.GenericAttack = {
	Kind = "Melee", Range = 9, Back = 1, Height = 4.5, MaxTargets = 4, Mult = 1.0, Style = "Slash",
} :: AttackProfile

WeaponConfig.Order = { "Greatsword", "Daggers", "Staff", "Bow", "Hammer", "Gauntlets", "SummoningBell", "TrickCards" }

WeaponConfig.Weapons = {
	Greatsword = {
		Id = "Greatsword", Name = "Greatsword", Archetype = "Wide-arc melee cleaver",
		BaseDamage = 42, AttacksPerSecond = 1.1,
		PassiveName = "Berserker's Momentum",
		PassiveDesc = "Hitting 3+ enemies grants +15% Attack Speed for 3s.",
		Link = { Id = "TitansMight", Name = "Titan's Might", Stat = "NormalEliteDamage", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 0, Accent = Color3.fromRGB(255, 120, 90),
		Attack = { Kind = "Melee", Range = 11, Back = 1.5, Height = 4.5, MaxTargets = 8, Mult = 1.0, Style = "Slash" },
		Ability = {
			Id = "RiftCleave", Name = "Rift Cleave", Desc = "Send a piercing shockwave across the platform.",
			Cooldown = 4, Count = 1, FanDeg = 12, Mult = 2.6, Speed = 54, Life = 0.5,
			HalfX = 2.8, HalfY = 3.8, Pierce = true, Style = "Wave",
		},
	},
	Daggers = {
		Id = "Daggers", Name = "Daggers", Archetype = "Hyper-mobile assassin",
		BaseDamage = 18, AttacksPerSecond = 2.6,
		PassiveName = "Shadow Step",
		PassiveDesc = "Dashing through an enemy guarantees your next attack is a Critical Hit.",
		Link = { Id = "LethalInstinct", Name = "Lethal Instinct", Stat = "CritDamage", Lv10 = 0.10, Lv20 = 0.20 },
		UnlockCost = 1500, Accent = Color3.fromRGB(150, 110, 255),
		Attack = { Kind = "Melee", Range = 6.5, Back = 1, Height = 4.5, MaxTargets = 3, Mult = 1.0, Style = "Stab" },
		Ability = {
			Id = "ShurikenFan", Name = "Shuriken Fan", Desc = "Throw five blades in a fan.",
			Cooldown = 5, Count = 5, FanDeg = 14, Mult = 0.9, Speed = 80, Life = 0.32,
			HalfX = 1.0, HalfY = 1.0, Pierce = false, Style = "Blade",
		},
	},
	Staff = {
		Id = "Staff", Name = "Staff", Archetype = "Elemental mage",
		BaseDamage = 32, AttacksPerSecond = 1.4,
		PassiveName = "Elemental Resonance",
		PassiveDesc = "Inflicting 2 different status effects triggers an Arcane Nova (150% AoE).",
		Link = { Id = "ArcaneFlow", Name = "Arcane Flow", Stat = "StatusDamageDuration", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 1500, Accent = Color3.fromRGB(80, 200, 255),
		Attack = { Kind = "Projectile", Range = 42, Height = 1.5, MaxTargets = 1, Mult = 1.0, Speed = 70, HalfSize = 1.4, Style = "Bolt" },
		Ability = {
			Id = "Fireball", Name = "Fireball", Desc = "Hurl a blazing orb that explodes and sets enemies alight.",
			Cooldown = 3.5, Count = 1, FanDeg = 10, Mult = 2.2, Speed = 56, Life = 0.9,
			HalfX = 1.5, HalfY = 1.5, Pierce = false, ExplodeRadius = 8, Burn = true, Style = "Fireball",
		},
	},
	Bow = {
		Id = "Bow", Name = "Bow", Archetype = "Long-range sniper & volley",
		BaseDamage = 22, AttacksPerSecond = 2.2,
		PassiveName = "Hurricane Focus",
		PassiveDesc = "Consecutive hits on the same target add +3% damage per arrow (up to +30%).",
		Link = { Id = "EagleEye", Name = "Eagle Eye", Stat = "CritRate", Lv10 = 0.05, Lv20 = 0.10 },
		UnlockCost = 3000, Accent = Color3.fromRGB(120, 235, 130),
	},
	Hammer = {
		Id = "Hammer", Name = "Hammer", Archetype = "Heavy crowd-control",
		BaseDamage = 50, AttacksPerSecond = 0.9,
		PassiveName = "Seismic Impact",
		PassiveDesc = "Ground slams deal +40% stagger damage and grant a 5% Max HP shield.",
		Link = { Id = "CrushingForce", Name = "Crushing Force", Stat = "BossDamage", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 3000, Accent = Color3.fromRGB(255, 180, 60),
	},
	Gauntlets = {
		Id = "Gauntlets", Name = "Gauntlets", Archetype = "Rapid combo brawler",
		BaseDamage = 16, AttacksPerSecond = 3.0,
		PassiveName = "Combo Overdrive",
		PassiveDesc = "Combo never decays while dashing and grants +1% damage per 10 combo.",
		Link = { Id = "RelentlessFlurry", Name = "Relentless Flurry", Stat = "AttackSpeedCooldown", Lv10 = 0.06, Lv20 = 0.12 },
		UnlockCost = 6000, Accent = Color3.fromRGB(255, 90, 150),
	},
	SummoningBell = {
		Id = "SummoningBell", Name = "Summoning Bell", Archetype = "Spirit commander",
		BaseDamage = 26, AttacksPerSecond = 1.5,
		PassiveName = "Soul Pack",
		PassiveDesc = "Summons inherit 100% of your status-effect procs and attack speed bonuses.",
		Link = { Id = "RiftFortune", Name = "Rift Fortune", Stat = "DustDropRate", Lv10 = 0.10, Lv20 = 0.20 },
		UnlockCost = 10000, Accent = Color3.fromRGB(190, 95, 255),
	},
	TrickCards = {
		Id = "TrickCards", Name = "Trick Cards", Archetype = "High-roller gambler",
		BaseDamage = 25, AttacksPerSecond = 1.8,
		PassiveName = "Loaded Deck",
		PassiveDesc = "Every 6th basic attack draws a random Royal Card (Red = AoE, Blue = CDR, Gold = Dust).",
		Link = { Id = "LuckyDraw", Name = "Lucky Draw", Stat = "RareUpgradeRate", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 10000, Accent = Color3.fromRGB(255, 215, 80),
	},
} :: { [string]: WeaponInfo }

-- Link skill value earned at a given mastery level (0 below 10).
function WeaponConfig.GetLinkValue(weaponId: string, masteryLevel: number): number
	local info = WeaponConfig.Weapons[weaponId]
	if not info then
		return 0
	end
	if masteryLevel >= 20 then
		return info.Link.Lv20
	elseif masteryLevel >= 10 then
		return info.Link.Lv10
	end
	return 0
end

-- Sum of every equipped Link Skill that boosts `stat`, from each weapon's Mastery (Section 25).
function WeaponConfig.GetTotalLinkBonus(activeLinks: { string }, mastery: { [string]: any }, stat: string): number
	local total = 0
	for _, linkId in activeLinks do
		for weaponId, info in WeaponConfig.Weapons do
			if info.Link.Id == linkId and info.Link.Stat == stat then
				local entry = mastery[weaponId]
				total += WeaponConfig.GetLinkValue(weaponId, if entry then entry.Level :: number else 0)
			end
		end
	end
	return total
end

-- Seconds between basic attacks
function WeaponConfig.GetAttackInterval(weaponId: string): number
	local info = WeaponConfig.Weapons[weaponId]
	return if info then 1 / info.AttacksPerSecond else 1
end

return WeaponConfig
