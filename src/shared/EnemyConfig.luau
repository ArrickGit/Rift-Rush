--!strict
-- ReplicatedStorage/Shared/EnemyConfig.luau
-- Base HP / Attack / XP and behaviour for every enemy archetype (Sections 9, 17 & 24.3). RunManagerService scales
-- the base numbers with FormulaEngine (World, Corruption, Depth, Party) when it spawns an enemy; EnemyAIService
-- reads the behaviour fields. Visual looks live in AssetRegistry.EnemyLooks.

export type MoveKind = "GroundPound" | "BoulderCharge" | "PoisonWave" | "SporeBoulder"

export type MoveSpec = {
	Kind: MoveKind,
	Windup: number, -- seconds of telegraph before the attack lands
	Recovery: number, -- seconds the boss is exposed afterwards
	DamageMult: number, -- x the enemy's Attack attribute
	Range: number?, -- GroundPound: half-width of the slam zone
	Speed: number?, -- BoulderCharge dash speed / SporeBoulder projectile speed
}

export type EnemyInfo = {
	Id: string,
	Name: string,
	Archetype: "Hopper" | "Boss",
	BaseHP: number,
	BaseAtk: number,
	BaseXP: number,
	MoveSpeed: number, -- studs/second (hop travel speed, or boss walk speed)
	HopPower: number, -- vertical launch speed of a hop (Hopper only)
	HopInterval: number, -- seconds between hops (Hopper only)
	ContactMult: number, -- touching the enemy deals Attack x this
	ContactCooldown: number,
	BossScale: number?, -- size multiplier when spawned as a Boss
	ThinkDelay: number?, -- seconds a boss walks between moves
	EnrageAt: number?, -- HP fraction that starts the boss's second phase
	Moves: { MoveSpec }?,
}

local EnemyConfig = {}

-- CollectionService tag every enemy model carries (RunManagerService.ENEMY_TAG); clients use it to find enemies.
EnemyConfig.TAG = "RiftEnemy"
EnemyConfig.FALLBACK = "SporeBlob"
EnemyConfig.DEFAULT_BOSS_SCALE = 2.5

-- Elites (Section 5.2) are tougher, bigger versions of a normal archetype.
EnemyConfig.Elite = { HP = 4, Atk = 1.5, XP = 4, Scale = 1.5 }

local golemMoves: { MoveSpec } = {
	{ Kind = "GroundPound", Windup = 1.0, Recovery = 0.9, DamageMult = 1.4, Range = 16 },
	{ Kind = "BoulderCharge", Windup = 1.1, Recovery = 1.5, DamageMult = 1.6, Speed = 58 },
}

local titanMoves: { MoveSpec } = {
	{ Kind = "PoisonWave", Windup = 1.3, Recovery = 0.9, DamageMult = 1.3 },
	{ Kind = "SporeBoulder", Windup = 0.9, Recovery = 0.7, DamageMult = 1.0, Speed = 38 },
	{ Kind = "GroundPound", Windup = 1.1, Recovery = 1.0, DamageMult = 1.5, Range = 19 },
}

local enemies: { [string]: EnemyInfo } = {
	SporeBlob = {
		Id = "SporeBlob", Name = "Spore Blob", Archetype = "Hopper",
		BaseHP = 60, BaseAtk = 10, BaseXP = 30,
		MoveSpeed = 22, HopPower = 32, HopInterval = 1.3,
		ContactMult = 1.0, ContactCooldown = 1.0,
	},
	MushroomHop = {
		Id = "MushroomHop", Name = "Mushroom Hopper", Archetype = "Hopper",
		BaseHP = 80, BaseAtk = 12, BaseXP = 40,
		MoveSpeed = 28, HopPower = 38, HopInterval = 0.95,
		ContactMult = 1.0, ContactCooldown = 1.0,
	},
	SporeGolem = {
		Id = "SporeGolem", Name = "Spore Golem", Archetype = "Boss",
		BaseHP = 1200, BaseAtk = 25, BaseXP = 1500,
		MoveSpeed = 7, HopPower = 0, HopInterval = 0,
		ContactMult = 0.6, ContactCooldown = 1.2,
		BossScale = 1.6, ThinkDelay = 1.2, EnrageAt = 0.5,
		Moves = golemMoves,
	},
	MushroomTitan = {
		Id = "MushroomTitan", Name = "Mushroom Titan", Archetype = "Boss",
		BaseHP = 3600, BaseAtk = 40, BaseXP = 4000,
		MoveSpeed = 6, HopPower = 0, HopInterval = 0,
		ContactMult = 0.6, ContactCooldown = 1.2,
		BossScale = 2.2, ThinkDelay = 1.1, EnrageAt = 0.5,
		Moves = titanMoves,
	},
}
EnemyConfig.Enemies = enemies

function EnemyConfig.Get(key: string): EnemyInfo
	return EnemyConfig.Enemies[key] or EnemyConfig.Enemies[EnemyConfig.FALLBACK]
end

return EnemyConfig
