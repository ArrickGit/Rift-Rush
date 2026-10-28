--!strict
-- ReplicatedStorage/Shared/WeaponConfig.luau
-- All 8 weapons (game.md Section 5): base stats, attack / ability profiles, Blacksmith unlock costs, how each model
-- is held in the hand, Hunter Legion Link Skills and the Weapon Mastery curve (Section 6).

export type LinkSkill = {
	Id: string,
	Name: string,
	Stat: string, -- key consumed by FormulaEngine / CombatService / RunManagerService
	Lv10: number,
	Lv20: number,
}

-- Basic attack: a short melee box in front of the player, or a straight bolt. Reach/height are in studs; the melee box
-- starts `Back` studs behind the player's root part.
export type AttackProfile = {
	Kind: "Melee" | "Projectile",
	Range: number, -- Melee: reach in front. Projectile: travel distance.
	Back: number?,
	Height: number, -- Melee: half-height of the hit box
	MaxTargets: number,
	Mult: number, -- skill multiplier
	Speed: number?, -- Projectile
	HalfSize: number?, -- Projectile half-extent
	Pierce: boolean?, -- Projectile passes through every enemy on its path
	Bounces: number?, -- Projectile jumps to the nearest other enemy this many times
	Stagger: number?, -- Melee: seconds of vertical stagger (micro-stun + hop) on normal enemies
	ComboFinisher: number?, -- Melee: every 3rd swing multiplies damage by this and reaches 40% further
	Lunge: number?, -- Melee: studs/s forward nudge the client applies to its own character
	Style: string, -- visual style key for CombatVFXController
}

-- Active ability (Q). Kind picks the server behaviour; the other fields are read by that behaviour only.
--   Projectile: Count projectiles in a fan (FanDeg apart), Mult each.
--   Rain: Count projectiles fall from RainHeight over a RainWidth-wide zone RainDistance ahead.
--   Pillars: Count rock pillars erupt Spacing studs apart along the facing, each a PillarHalfX x PillarHalfY box.
--   Uppercut: a box Range ahead and Height tall that launches enemies (and the caster) upward.
--   Summon: Count spirits follow the caster for Duration seconds, firing a bolt every FireInterval seconds.
export type AbilityProfile = {
	Id: string,
	Name: string,
	Desc: string,
	Kind: ("Projectile" | "Rain" | "Pillars" | "Uppercut" | "Summon")?, -- nil = Projectile
	Cooldown: number,
	Count: number,
	FanDeg: number,
	Mult: number,
	Speed: number,
	Life: number,
	HalfX: number,
	HalfY: number,
	Pierce: boolean,
	ExplodeRadius: number?, -- explodes on the first enemy hit
	Burn: boolean?,
	Shock: boolean?,
	DrawCard: boolean?, -- Trick Cards: draws a Loaded Deck card on cast
	RainWidth: number?,
	RainDistance: number?,
	RainHeight: number?,
	Spacing: number?,
	PillarHalfX: number?,
	PillarHalfY: number?,
	StunSeconds: number?,
	Range: number?,
	Height: number?,
	Duration: number?,
	FireInterval: number?,
	Style: string,
}

-- How the model sits in the right hand (WeaponHoldService). The model is scaled so its longest side is Length studs
-- and that side is laid along the hand's forward-down axis; Grip (0-1) is how far along that side the hand closes,
-- measured from the end that points down in the prefab. Flip swaps which end is the grip end.
export type HoldInfo = {
	Length: number,
	Grip: number,
	Flip: boolean?,
	Tilt: number?, -- extra degrees around the hand's X axis (positive raises the tip)
}

export type WeaponInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Archetype: string,
	BaseDamage: number, -- W_Base
	AttacksPerSecond: number,
	PassiveName: string,
	PassiveDesc: string,
	Link: LinkSkill,
	UnlockCost: number, -- Rift Dust at the Blacksmith (0 = starter weapon, unlocked for free)
	UnlockCores: number, -- Boss Cores at the Blacksmith
	Accent: Color3,
	Hold: HoldInfo,
	Attack: AttackProfile?,
	Ability: AbilityProfile?,
}

local WeaponConfig = {}

WeaponConfig.DEFAULT_WEAPON = "Greatsword"
WeaponConfig.MAX_MASTERY = 20
WeaponConfig.LINK_TIER1_LEVEL = 10
WeaponConfig.LINK_TIER2_LEVEL = 20
WeaponConfig.MAX_PARAGON = 979 -- Mastery 20 + Paragon 979 = level 999
WeaponConfig.BASE_LINK_SLOTS = 3
WeaponConfig.MAX_LINK_SLOTS = 6

-- Section 6.1 Mastery XP per kill (before World / Corruption scaling).
WeaponConfig.KILL_MASTERY_XP = { Normal = 12, Elite = 45, MiniBoss = 180, WorldBoss = 400 } :: { [string]: number }

WeaponConfig.GenericAttack = {
	Kind = "Melee", Range = 9, Back = 1, Height = 4.5, MaxTargets = 4, Mult = 1.0, Style = "Slash",
} :: AttackProfile

WeaponConfig.Order = { "Greatsword", "Daggers", "Staff", "Bow", "Hammer", "Gauntlets", "SummoningBell", "TrickCards" }

WeaponConfig.Weapons = {
	Greatsword = {
		Id = "Greatsword", Name = "Greatsword", Icon = "🗡️", Archetype = "Wide-arc melee cleaver",
		BaseDamage = 42, AttacksPerSecond = 1.1,
		PassiveName = "Berserker's Momentum",
		PassiveDesc = "Hitting 3+ enemies grants +15% Attack Speed for 3s.",
		Link = { Id = "TitansMight", Name = "Titan's Might", Stat = "NormalEliteDamage", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 0, UnlockCores = 0, Accent = Color3.fromRGB(255, 120, 90),
		Hold = { Length = 5.2, Grip = 0.12 },
		Attack = { Kind = "Melee", Range = 11, Back = 1.5, Height = 4.5, MaxTargets = 8, Mult = 1.0, Style = "Slash" },
		Ability = {
			Id = "RiftCleave", Name = "Rift Cleave", Desc = "Send a piercing shockwave across the platform.",
			Cooldown = 4, Count = 1, FanDeg = 12, Mult = 2.6, Speed = 54, Life = 0.5,
			HalfX = 2.8, HalfY = 3.8, Pierce = true, Style = "Wave",
		},
	},
	Daggers = {
		Id = "Daggers", Name = "Daggers", Icon = "🔪", Archetype = "Hyper-mobile assassin",
		BaseDamage = 18, AttacksPerSecond = 2.6,
		PassiveName = "Shadow Step",
		PassiveDesc = "Dashing through an enemy guarantees your next attack is a Critical Hit.",
		Link = { Id = "LethalInstinct", Name = "Lethal Instinct", Stat = "CritDamage", Lv10 = 0.10, Lv20 = 0.20 },
		UnlockCost = 0, UnlockCores = 0, Accent = Color3.fromRGB(150, 110, 255),
		Hold = { Length = 2.2, Grip = 0.2 },
		Attack = { Kind = "Melee", Range = 6.5, Back = 1, Height = 4.5, MaxTargets = 3, Mult = 1.0, Style = "Stab" },
		Ability = {
			Id = "ShurikenFan", Name = "Shuriken Fan", Desc = "Throw five blades in a fan.",
			Cooldown = 5, Count = 5, FanDeg = 14, Mult = 0.9, Speed = 80, Life = 0.32,
			HalfX = 1.0, HalfY = 1.0, Pierce = false, Style = "Blade",
		},
	},
	Staff = {
		Id = "Staff", Name = "Staff", Icon = "🪄", Archetype = "Elemental mage",
		BaseDamage = 32, AttacksPerSecond = 1.4,
		PassiveName = "Elemental Resonance",
		PassiveDesc = "Inflicting 2 different status effects triggers an Arcane Nova (150% AoE).",
		Link = { Id = "ArcaneFlow", Name = "Arcane Flow", Stat = "StatusDamageDuration", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 0, UnlockCores = 0, Accent = Color3.fromRGB(80, 200, 255),
		Hold = { Length = 5, Grip = 0.35, Tilt = 75 },
		Attack = { Kind = "Projectile", Range = 42, Height = 1.5, MaxTargets = 1, Mult = 1.0, Speed = 70, HalfSize = 1.4, Style = "Bolt" },
		Ability = {
			Id = "Fireball", Name = "Fireball", Desc = "Hurl a blazing orb that explodes and sets enemies alight.",
			Cooldown = 3.5, Count = 1, FanDeg = 10, Mult = 2.2, Speed = 56, Life = 0.9,
			HalfX = 1.5, HalfY = 1.5, Pierce = false, ExplodeRadius = 8, Burn = true, Style = "Fireball",
		},
	},
	Bow = {
		Id = "Bow", Name = "Bow", Icon = "🏹", Archetype = "Long-range sniper & volley",
		BaseDamage = 22, AttacksPerSecond = 2.2,
		PassiveName = "Hurricane Focus",
		PassiveDesc = "Consecutive hits on the same target add +3% damage per arrow (up to +30%).",
		Link = { Id = "EagleEye", Name = "Eagle Eye", Stat = "CritRate", Lv10 = 0.05, Lv20 = 0.10 },
		UnlockCost = 400, UnlockCores = 2, Accent = Color3.fromRGB(120, 235, 130),
		Hold = { Length = 4.2, Grip = 0.5, Tilt = 90 },
		Attack = { Kind = "Projectile", Range = 28, Height = 1.2, MaxTargets = 99, Mult = 1.0, Speed = 95, HalfSize = 0.9,
			Pierce = true, Style = "Arrow" },
		Ability = {
			Id = "ArrowRain", Name = "Arrow Rain", Desc = "Loose an arc into the sky that rains 8 arrows on a 12-stud zone.",
			Kind = "Rain", Cooldown = 6, Count = 8, FanDeg = 0, Mult = 0.45, Speed = 85, Life = 0.42,
			HalfX = 0.7, HalfY = 1.4, Pierce = false, RainWidth = 12, RainDistance = 11, RainHeight = 22, Style = "Arrow",
		},
	},
	Hammer = {
		Id = "Hammer", Name = "Hammer", Icon = "🔨", Archetype = "Heavy crowd-control",
		BaseDamage = 50, AttacksPerSecond = 0.9,
		PassiveName = "Seismic Impact",
		PassiveDesc = "Ground slams deal +40% damage to staggered enemies and grant a 5% Max HP shield for 4s.",
		Link = { Id = "CrushingForce", Name = "Crushing Force", Stat = "BossDamage", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 750, UnlockCores = 4, Accent = Color3.fromRGB(255, 180, 60),
		Hold = { Length = 4.4, Grip = 0.12 },
		Attack = { Kind = "Melee", Range = 8, Back = 1.5, Height = 5, MaxTargets = 6, Mult = 1.0, Stagger = 0.45, Style = "Smash" },
		Ability = {
			Id = "SeismicTremor", Name = "Seismic Tremor",
			Desc = "Slam the ground: 3 rock pillars erupt along the platform (260% + 1.5s stun).",
			Kind = "Pillars", Cooldown = 5, Count = 3, FanDeg = 0, Mult = 2.6, Speed = 0, Life = 0,
			HalfX = 0, HalfY = 0, Pierce = true, Spacing = 5.5, PillarHalfX = 2.6, PillarHalfY = 5, StunSeconds = 1.5,
			Style = "Pillar",
		},
	},
	Gauntlets = {
		Id = "Gauntlets", Name = "Gauntlets", Icon = "🥊", Archetype = "Rapid combo brawler",
		BaseDamage = 16, AttacksPerSecond = 3.0,
		PassiveName = "Combo Overdrive",
		PassiveDesc = "Your combo never decays while dashing and grants +1% damage per 10 combo (up to +30%).",
		Link = { Id = "RelentlessFlurry", Name = "Relentless Flurry", Stat = "AttackSpeedCooldown", Lv10 = 0.06, Lv20 = 0.12 },
		UnlockCost = 1200, UnlockCores = 6, Accent = Color3.fromRGB(255, 90, 150),
		Hold = { Length = 1.6, Grip = 0.5, Tilt = 0 },
		Attack = { Kind = "Melee", Range = 5.5, Back = 1, Height = 4, MaxTargets = 3, Mult = 1.0, ComboFinisher = 1.6,
			Lunge = 26, Style = "Punch" },
		Ability = {
			Id = "RisingUppercut", Name = "Rising Uppercut",
			Desc = "Launch yourself and nearby enemies skyward in a flaming dragon spiral (210% + Burn).",
			Kind = "Uppercut", Cooldown = 4.5, Count = 1, FanDeg = 0, Mult = 2.1, Speed = 0, Life = 0,
			HalfX = 0, HalfY = 0, Pierce = true, Burn = true, Range = 6.5, Height = 9, Style = "Dragon",
		},
	},
	SummoningBell = {
		Id = "SummoningBell", Name = "Summoning Bell", Icon = "🔔", Archetype = "Spirit commander",
		BaseDamage = 26, AttacksPerSecond = 1.5,
		PassiveName = "Soul Pack",
		PassiveDesc = "Summons inherit 100% of your Crit Rate, Attack Speed and status procs.",
		Link = { Id = "RiftFortune", Name = "Rift Fortune", Stat = "DustDropRate", Lv10 = 0.10, Lv20 = 0.20 },
		UnlockCost = 2000, UnlockCores = 10, Accent = Color3.fromRGB(190, 95, 255),
		Hold = { Length = 1.8, Grip = 0.85, Tilt = 90 },
		Attack = { Kind = "Melee", Range = 14, Back = 2, Height = 5, MaxTargets = 6, Mult = 1.0, Style = "Pulse" },
		Ability = {
			Id = "CallFamiliar", Name = "Call Rift Familiar",
			Desc = "Summon 2 Spirit Foxes for 12s that fire bolts every 0.8s (65% each).",
			Kind = "Summon", Cooldown = 14, Count = 2, FanDeg = 0, Mult = 0.65, Speed = 72, Life = 0.55,
			HalfX = 1, HalfY = 1, Pierce = false, Duration = 12, FireInterval = 0.8, Style = "Spirit",
		},
	},
	TrickCards = {
		Id = "TrickCards", Name = "Trick Cards", Icon = "🃏", Archetype = "High-roller gambler",
		BaseDamage = 25, AttacksPerSecond = 1.8,
		PassiveName = "Loaded Deck",
		PassiveDesc = "Every 6th attack draws a card: Red = 150% Burn blast, Blue = -2s Q cooldown, Gold = +15 Rift Dust.",
		Link = { Id = "LuckyDraw", Name = "Lucky Draw", Stat = "RareUpgradeRate", Lv10 = 0.08, Lv20 = 0.15 },
		UnlockCost = 3500, UnlockCores = 15, Accent = Color3.fromRGB(255, 215, 80),
		Hold = { Length = 2.2, Grip = 0.3, Tilt = 20 },
		Attack = { Kind = "Projectile", Range = 20, Height = 1.2, MaxTargets = 1, Mult = 1.0, Speed = 85, HalfSize = 1.1,
			Bounces = 1, Style = "Card" },
		Ability = {
			Id = "RoyalFlush", Name = "Royal Flush", Desc = "Throw a 5-card spread (85% each) and draw a random card buff.",
			Cooldown = 5, Count = 5, FanDeg = 9, Mult = 0.85, Speed = 85, Life = 0.3,
			HalfX = 1.0, HalfY = 1.0, Pierce = false, DrawCard = true, Style = "Card",
		},
	},
} :: { [string]: WeaponInfo }

-- Starter weapons (UnlockCost 0) are always owned.
function WeaponConfig.IsStarter(weaponId: string): boolean
	local info = WeaponConfig.Weapons[weaponId]
	return info ~= nil and info.UnlockCost == 0 and info.UnlockCores == 0
end

-- Section 6.1: XP needed to go from Mastery `level` to the next. Paragon ranks continue the curve past 20.
function WeaponConfig.GetMasteryXPRequired(level: number): number
	return math.round(100 * math.max(1, level) ^ 1.5)
end

-- Link skill value earned at a given mastery level (0 below 10).
function WeaponConfig.GetLinkValue(weaponId: string, masteryLevel: number): number
	local info = WeaponConfig.Weapons[weaponId]
	if not info then
		return 0
	end
	if masteryLevel >= WeaponConfig.LINK_TIER2_LEVEL then
		return info.Link.Lv20
	elseif masteryLevel >= WeaponConfig.LINK_TIER1_LEVEL then
		return info.Link.Lv10
	end
	return 0
end

-- The weapon that owns a Link Skill id.
function WeaponConfig.GetWeaponForLink(linkId: string): WeaponInfo?
	for _, info in WeaponConfig.Weapons do
		if info.Link.Id == linkId then
			return info
		end
	end
	return nil
end

-- Sum of every equipped Link Skill that boosts `stat`, from each weapon's Mastery (Section 6.2).
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

-- Active Link Skill slots: 3, +1 per Legion Commander level, +2 with the Extra Link Slots pass (max 6).
function WeaponConfig.GetLinkSlots(legionCommanderLevel: number, hasExtraSlotsPass: boolean): number
	local slots = WeaponConfig.BASE_LINK_SLOTS + legionCommanderLevel + (if hasExtraSlotsPass then 2 else 0)
	return math.min(WeaponConfig.MAX_LINK_SLOTS, slots)
end

-- Seconds between basic attacks
function WeaponConfig.GetAttackInterval(weaponId: string): number
	local info = WeaponConfig.Weapons[weaponId]
	return if info then 1 / info.AttacksPerSecond else 1
end

return WeaponConfig
