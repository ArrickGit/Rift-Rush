--!strict
-- ReplicatedStorage/Shared/FormulaEngine.luau
-- Audited v2.6 Single Source of Truth for Rift Rush XP, Rebirth, Damage, Co-op Sync & Economy Math

export type RebirthInfo = {
	ReqLevel: number,
	DmgMult: number,
	EcoMult: number,
	Sparks: number,
}

export type DamageParams = {
	WeaponBaseDmg: number,
	HunterLevel: number,
	LegacyBonusLevels: number,
	WeaponMasteryLevel: number,
	WeaponParagonRank: number,
	SkillMultiplier: number,
	RebirthTier: number,
	IsPureRun: boolean,
	AscendantMightLv: number,
	InfOmnipotenceLv: number,
	LinkSkillDmgBonus: number,
	RelicDmgBonus: number,
	RelicResonanceLv: number,
	RunAdditiveBonus: number,
	ComboCount: number,
	CurseDmgMultiplier: number,
	TargetBonus: number,
	CritRate: number,
	CritDamageMult: number,
	LimitBreakerLv: number,
	PartyHostBaselinePower: number?,
	ReforgeDmg: number?, -- Weapon Reforge tier bonus (ReforgeConfig), an account-side multiplier like relics
}

local FormulaEngine = {}

FormulaEngine.REBIRTH_TABLE = {
	[0]  = { ReqLevel = 1,   DmgMult = 1.00, EcoMult = 1.00, Sparks = 0  },
	[1]  = { ReqLevel = 50,  DmgMult = 1.30, EcoMult = 1.25, Sparks = 2  },
	[2]  = { ReqLevel = 75,  DmgMult = 1.65, EcoMult = 1.55, Sparks = 3  },
	[3]  = { ReqLevel = 100, DmgMult = 2.10, EcoMult = 1.90, Sparks = 4  },
	[4]  = { ReqLevel = 130, DmgMult = 2.65, EcoMult = 2.35, Sparks = 5  },
	[5]  = { ReqLevel = 165, DmgMult = 3.35, EcoMult = 2.90, Sparks = 6  },
	[6]  = { ReqLevel = 200, DmgMult = 4.20, EcoMult = 3.55, Sparks = 7  },
	[7]  = { ReqLevel = 240, DmgMult = 5.25, EcoMult = 4.30, Sparks = 8  },
	[8]  = { ReqLevel = 285, DmgMult = 6.50, EcoMult = 5.20, Sparks = 9  },
	[9]  = { ReqLevel = 335, DmgMult = 8.00, EcoMult = 6.25, Sparks = 10 },
	[10] = { ReqLevel = 400, DmgMult = 10.0, EcoMult = 7.50, Sparks = 12 },
} :: { [number]: RebirthInfo }

FormulaEngine.WORLD_ECO_MULT = { 1.0, 1.8, 3.2, 5.5, 9.5, 16.0, 27.0, 45.0 }
FormulaEngine.WORLD_HP_MULT  = { 1.0, 2.2, 4.5, 9.0, 18.0, 35.0, 68.0, 130.0 }
FormulaEngine.WORLD_ATK_MULT = { 1.0, 1.6, 2.5, 3.8, 5.8, 8.8,  13.5, 20.0 }

function FormulaEngine.GetRebirthInfo(rebirthTier: number): RebirthInfo
	if rebirthTier <= 10 then
		return FormulaEngine.REBIRTH_TABLE[math.max(0, rebirthTier)]
	end
	local extra = rebirthTier - 10
	return {
		ReqLevel = 400 + 75 * extra,
		DmgMult  = 10.0 + 2.0 * extra,
		EcoMult  = 7.50 + 1.25 * extra,
		Sparks   = 12,
	}
end

function FormulaEngine.GetHunterXPRequired(level: number): number
	local clamped = math.max(1, level)
	return math.round(80 * (clamped ^ 1.65) + 40 * clamped)
end

function FormulaEngine.CalculateLegacyLevelsGained(nextRebirthTier: number, currentHunterLevel: number): number
	local reqLevel = FormulaEngine.GetRebirthInfo(nextRebirthTier).ReqLevel
	local effectiveLevel = math.clamp(currentHunterLevel, reqLevel, math.round(reqLevel * 1.25))
	return math.round(0.50 * effectiveLevel)
end

function FormulaEngine.GetInstantRebirthSkipQuote(nextRebirthTier: number, currentHunterLevel: number): (string, number, number)
	local nextInfo = FormulaEngine.GetRebirthInfo(nextRebirthTier)
	local reqLevel = nextInfo.ReqLevel
	local progress = math.clamp((currentHunterLevel - 1) / math.max(1, reqLevel - 1), 0, 0.90)

	if progress >= 0.80 then
		return "SKIP_TIER_1_49R", 49, progress
	elseif progress >= 0.60 then
		return "SKIP_TIER_2_99R", 99, progress
	elseif progress >= 0.40 then
		return "SKIP_TIER_3_179R", 179, progress
	elseif progress >= 0.20 then
		return "SKIP_TIER_4_279R", 279, progress
	else
		return "SKIP_TIER_5_399R", 399, progress
	end
end

-- BaseAtk x M_Rebirth x M_Ascension (Section 24.2) before the Rift Sidekick Sync floor. Party members compare this
-- against 70% of the host's value (Section 18.2).
function FormulaEngine.GetCorePower(p: DamageParams): number
	local levelFactor = 1 + 0.015 * math.max(0, p.HunterLevel - 1) + 0.0075 * p.LegacyBonusLevels
	local masteryFactor = 1 + 0.02 * p.WeaponMasteryLevel + 0.005 * p.WeaponParagonRank
	local baseAtk = p.WeaponBaseDmg * levelFactor * masteryFactor

	local rebInfo = FormulaEngine.GetRebirthInfo(p.RebirthTier)
	local rebMult = if p.IsPureRun then 1.0 else rebInfo.DmgMult
	local ascensionMult = if p.IsPureRun then 1.0 else (1 + 0.08 * p.AscendantMightLv + 0.05 * p.InfOmnipotenceLv)
	return baseAtk * rebMult * ascensionMult
end

function FormulaEngine.CalculateHitDamage(p: DamageParams, rng: Random?): (number, boolean, {number})
	local randomGen = rng or Random.new()

	local rawCorePower = FormulaEngine.GetCorePower(p)
	if not p.IsPureRun and p.PartyHostBaselinePower and rawCorePower < (0.70 * p.PartyHostBaselinePower) then
		rawCorePower = 0.70 * p.PartyHostBaselinePower
	end

	local relicBoosted = p.RelicDmgBonus * (1 + 0.10 * p.RelicResonanceLv)
	local reforge = if p.IsPureRun then 0 else (p.ReforgeDmg or 0)
	local accountMult = (1 + p.LinkSkillDmgBonus + relicBoosted) * (1 + reforge)

	local comboBonus = math.min(0.50, math.floor(p.ComboCount / 10) * 0.01)
	local runBuildMult = (1 + p.RunAdditiveBonus + comboBonus) * math.max(0.1, p.CurseDmgMultiplier)
	local targetMult = 1 + p.TargetBonus

	local isCrit = randomGen:NextNumber() <= math.clamp(p.CritRate, 0, 1.0)
	local critMult = if isCrit then math.max(1.5, p.CritDamageMult) else 1.0
	local variance = randomGen:NextNumber(0.95, 1.05)

	local primaryDamage = math.max(1, math.round(
		rawCorePower * p.SkillMultiplier * accountMult * runBuildMult * targetMult * critMult * variance
	))

	local shadowLines: { number } = {}
	if not p.IsPureRun and p.LimitBreakerLv > 0 then
		for _ = 1, math.clamp(p.LimitBreakerLv, 1, 3) do
			table.insert(shadowLines, math.max(1, math.round(primaryDamage * 0.15)))
		end
	end

	return primaryDamage, isCrit, shadowLines
end

-- Section 24.2 MaxHP (run/curse multipliers default to 1)
function FormulaEngine.GetPlayerMaxHP(hunterLevel: number, legacyLevels: number, rebirthTier: number, ascendantMightLv: number, runHpMult: number?, curseHpMult: number?): number
	local levelFactor = 1 + 0.015 * (math.max(1, hunterLevel) - 1) + 0.0075 * legacyLevels
	local rebMult = FormulaEngine.GetRebirthInfo(rebirthTier).DmgMult
	local ascMult = 1 + 0.08 * ascendantMightLv
	return math.max(1, math.round(250 * levelFactor * rebMult * ascMult * (runHpMult or 1) * (curseHpMult or 1)))
end

function FormulaEngine.GetMonsterMaxHP(baseHP: number, worldIndex: number, corruptionTier: number, roomNumber: number, partySize: number): number
	local wMult = FormulaEngine.WORLD_HP_MULT[math.clamp(worldIndex, 1, #FormulaEngine.WORLD_HP_MULT)] or 1.0
	local c = math.max(0, corruptionTier)
	local corrMult = (1 + 0.18 * c) * (1.055 ^ c)

	local d = math.max(1, roomNumber)
	local depthMult = 1.0
	if d <= 10 then
		depthMult = 1.11 ^ (d - 1)
	elseif d <= 20 then
		depthMult = (1.11 ^ 9) * (1.16 ^ (d - 10))
	else
		depthMult = (1.11 ^ 9) * (1.16 ^ 10) * (1.22 ^ (d - 20))
	end

	local p = math.clamp(partySize, 1, 4)
	local partyMult = 1 + 0.55 * (p - 1)

	return math.max(1, math.round(baseHP * wMult * corrMult * depthMult * partyMult))
end

-- Section 24.3 EnemyRawAtk
function FormulaEngine.GetMonsterAttack(baseAtk: number, worldIndex: number, corruptionTier: number, roomNumber: number): number
	local wMult = FormulaEngine.WORLD_ATK_MULT[math.clamp(worldIndex, 1, #FormulaEngine.WORLD_ATK_MULT)] or 1.0
	local c = math.max(0, corruptionTier)
	local d = math.max(1, roomNumber)
	return math.max(1, math.round(baseAtk * wMult * (1 + 0.12 * c) * (1.04 ^ c) * (1.07 ^ (d - 1))))
end

function FormulaEngine.GetWorldEcoMult(worldIndex: number): number
	return FormulaEngine.WORLD_ECO_MULT[math.clamp(worldIndex, 1, #FormulaEngine.WORLD_ECO_MULT)] or 1.0
end

function FormulaEngine.CalculateDefeatDustKept(unsecuredDust: number, roomNumber: number, anchorGuardianLv: number, hasInsurancePass: boolean): number
	local baseLoss = 0.30
	if roomNumber >= 11 then
		baseLoss = 0.75
	elseif roomNumber >= 6 then
		baseLoss = 0.50
	end

	local sparkReduction = 1 - (0.10 * math.clamp(anchorGuardianLv, 0, 4))
	local passFactor = if hasInsurancePass then 0.50 else 1.00
	local finalLoss = math.clamp(baseLoss * sparkReduction * passFactor, 0.05, 0.95)

	return math.round(unsecuredDust * (1 - finalLoss))
end

-- Relic Shards / Boss Cores in the Unsecured Pouch are safe in Rooms 1-5 and fully at risk from Room 6 (Section 19),
-- with the same Anchor Guardian / Insurance reductions as Dust.
function FormulaEngine.CalculateDefeatNonDustKept(unsecured: number, roomNumber: number, anchorGuardianLv: number, hasInsurancePass: boolean): number
	if roomNumber <= 5 then
		return unsecured
	end
	local sparkReduction = 1 - (0.10 * math.clamp(anchorGuardianLv, 0, 4))
	local passFactor = if hasInsurancePass then 0.50 else 1.00
	return math.round(unsecured * (1 - sparkReduction * passFactor))
end

-- M_CorrEco(C) and M_Depth(d) feed the XP / Dust formulas (Sections 24.1, 24.4); the spec leaves their exact
-- curves open, so these are the tunable defaults. M_Party(P) is the co-op XP bonus.
function FormulaEngine.GetCorruptionEcoMult(corruptionTier: number): number
	local c = math.max(0, corruptionTier)
	return (1 + 0.15 * c) * (1.03 ^ c)
end

function FormulaEngine.GetDepthEcoMult(roomNumber: number): number
	return 1.10 ^ (math.max(1, roomNumber) - 1)
end

function FormulaEngine.GetPartyXPMult(partySize: number): number
	return 1 + 0.10 * (math.clamp(partySize, 1, 4) - 1)
end

-- Section 18.2 Anti-Boost Reward Cap: World x Corruption reward factor a player may earn at, relative to the
-- highest World/Corruption Tier they have personally unlocked (ceiling = 3.0x that baseline).
function FormulaEngine.GetCappedEnvMult(runWorld: number, runCorruption: number, ownWorld: number, ownCorruption: number): number
	local runEnv = FormulaEngine.GetWorldEcoMult(runWorld) * FormulaEngine.GetCorruptionEcoMult(runCorruption)
	local ownEnv = FormulaEngine.GetWorldEcoMult(ownWorld) * FormulaEngine.GetCorruptionEcoMult(ownCorruption)
	return math.min(runEnv, 3.0 * ownEnv)
end

-- The parts of a profile Rift Power reads (kept structural so this shared module needs no server types).
export type PowerProfile = {
	EquippedWeapon: string,
	HunterLevel: number,
	LegacyBonusLevels: number,
	RebirthTier: number,
	WeaponMastery: { [string]: any }, -- entries have .Level
	WeaponReforge: { [string]: any },
	RelicStars: { [string]: any }, -- entries have .Stars
}

-- One big "⚡ Rift Power" number for the HUD and the town badge (game.md 3.2). The weapon base is its DPS x 20 so a
-- fresh hunter starts near 1,000. Legacy levels count as Hunter levels so a rebirth doesn't crater the number, and
-- mastery counts levels above 1 so only earned levels add. Each in-run upgrade card is worth +15%.
function FormulaEngine.CalculateRiftPower(profile: PowerProfile, inRunUpgrades: number?): number
	local WeaponConfig = require(script.Parent:WaitForChild("WeaponConfig")) :: any
	local ReforgeConfig = require(script.Parent:WaitForChild("ReforgeConfig")) :: any
	local weapon = WeaponConfig.Weapons[profile.EquippedWeapon] or WeaponConfig.Weapons[WeaponConfig.DEFAULT_WEAPON]
	local base = weapon.BaseDamage * weapon.AttacksPerSecond * 20
	local levels = 1 + 0.08 * (profile.HunterLevel + profile.LegacyBonusLevels)
	local rebirth = FormulaEngine.GetRebirthInfo(profile.RebirthTier).DmgMult
	local tier = ReforgeConfig.ForWeapon(profile.WeaponReforge, weapon.Id)
	local reforge = 1 + (if tier then tier.Dmg else 0)
	local mastery = 0
	for _, entry in profile.WeaponMastery do
		mastery += math.max(0, entry.Level - 1)
	end
	local stars = 0
	for _, relic in profile.RelicStars do
		stars += relic.Stars
	end
	return math.round(base * levels * rebirth * reforge * (1 + 0.05 * mastery) * (1 + 0.12 * stars)
		* (1 + 0.15 * (inRunUpgrades or 0)))
end

return FormulaEngine
