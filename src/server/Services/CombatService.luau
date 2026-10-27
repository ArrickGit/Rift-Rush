--!strict
-- ServerScriptService/Server/Services/CombatService.luau
-- Server-authoritative combat (Sections 8-14, 24.2 and 0.1 rule 2). Clients only send *intent* — "I pressed
-- Attack/Ability, facing left/right" and "I dashed" — and the server decides targets, damage, crits, statuses,
-- cooldowns and kills through FormulaEngine. Everything cosmetic goes back out on CombatFx / DamageNumber.
--
-- What lives here:
--   * Basic attacks + the Q ability for Greatsword, Daggers and Staff (WeaponConfig profiles), the weapon passives,
--     dash i-frames, the Rift Combo counter and Burn / Shock status effects.
--   * Projectiles for both teams (player bolts / abilities, boss shockwaves / boulders). Spore boulders can be
--     smacked back with a basic attack to stun the Mushroom Titan.
--   * Run upgrades: rolling cards on RoomCleared, Pick / Reroll / Banish, and the build's stat totals.
--   * Player damage, so EnemyAIService can hurt players without knowing about i-frames.
--
-- Player attributes this service publishes for the HUD: Combo, AttackInterval, Ability1ReadyAt (server time),
-- Ability1Cooldown. Gamepass attributes it reads (set by MonetizationService in Step 5): HasVIPArchitect (4th card),
-- HasBanishPass (+3 Banish charges per run). Reroll Pack charges (profile.BonusRerolls) are spent once the run's
-- free rerolls are gone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local Physics25D = require(Shared:WaitForChild("Physics25D"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RoomAsciiTemplates = require(Shared:WaitForChild("RoomAsciiTemplates"))
local UpgradePoolConfig = require(Shared:WaitForChild("UpgradePoolConfig"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local EnemyAIService = require(script.Parent:WaitForChild("EnemyAIService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData
type DamageParams = FormulaEngine.DamageParams
type EnemyState = EnemyAIService.EnemyState
type Upgrade = UpgradePoolConfig.Upgrade
type WeaponInfo = WeaponConfig.WeaponInfo
type AttackProfile = WeaponConfig.AttackProfile
type AbilityProfile = WeaponConfig.AbilityProfile

type Offer = {
	Id: number,
	Cards: { Upgrade },
}

type PlayerCombat = {
	Player: Player,
	RunId: number,
	NextBasicAt: number,
	NextAbilityAt: number,
	Combo: number,
	ComboExpiresAt: number,
	DashCharges: number,
	DashRecharge: number,
	InvulnUntil: number,
	HurtUntil: number,
	ShadowStepUntil: number,
	MomentumUntil: number,
	Stacks: { [string]: number },
	Mods: { [string]: number },
	Banished: { [string]: boolean },
	Rerolls: number,
	Banishes: number,
	Offer: Offer?,
	QueuedOffers: number,
	Zones: number,
}

type Projectile = {
	Id: number,
	Team: "Player" | "Enemy",
	RunId: number,
	Pos: Vector3,
	StartPos: Vector3,
	Vel: Vector3,
	HalfX: number,
	HalfY: number,
	ExpiresAt: number,
	Style: string,
	Owner: Player?,
	SourceEnemy: EnemyState?,
	Damage: number, -- enemy projectiles: flat damage
	SkillMult: number, -- player projectiles
	Pierce: boolean,
	ExplodeRadius: number?,
	Burn: boolean,
	Shock: boolean,
	Trail: boolean,
	ForceCrit: boolean, -- Shadow Step carried onto a thrown projectile
	CanReflect: boolean, -- a basic-attack bolt that can smack back a boulder
	Reflectable: boolean,
	Reflected: boolean,
	Hit: { [any]: boolean },
}

type Zone = {
	RunId: number,
	Owner: Player,
	CenterX: number,
	CenterY: number,
	HalfX: number,
	HalfY: number,
	ExpiresAt: number,
	NextTickAt: number,
}

type AttackCtx = {
	Player: Player,
	PC: PlayerCombat,
	Profile: PlayerProfileData,
	Weapon: WeaponInfo,
	RunId: number,
	Params: DamageParams,
	Mods: { [string]: number },
	CritRate: number,
	NormalBonus: number,
	BossBonus: number,
	ForceCrit: boolean,
}

type StrikeFlags = {
	NoChain: boolean?,
	NoStatus: boolean?,
	NativeBurn: boolean?,
	NativeShock: boolean?,
}

type DamageOpts = {
	Crit: boolean?,
	Primary: number?,
	Lines: { number }?,
	Kind: string?,
	Dir: number?,
}

local CombatService = {}

-- Tuning ------------------------------------------------------------------------------------------------------

local BASE_CRIT_RATE = 0.05
local BASE_CRIT_DAMAGE = 1.5
local COMBO_WINDOW = 4
local ATTACK_LATENCY_CREDIT = 0.1 -- a basic attack may land this early without being rejected
local ABILITY_LATENCY_CREDIT = 0.1
local MIN_REMOTE_GAP = 0.03
local DASH_IFRAMES = 0.24
local HURT_IFRAMES = 0.4
local SHADOW_STEP_WINDOW = 0.22
local SHADOW_STEP_SECONDS = 6
local MOMENTUM_SECONDS = 3
local MOMENTUM_ATTACK_SPEED = 0.15

local BURN_PCT_PER_SECOND = 0.40
local BURN_SECONDS = 4
local BURN_TICK = 0.5
local BURN_STACK_BONUS = 0.5
local BURN_SPREAD_RADIUS = 10
local SHOCK_SECONDS = 5
local CHAIN_TARGETS = 3
local CHAIN_RANGE = 18
local CHAIN_MULT = 0.45
local CHAIN_STACK_BONUS = 0.15
local NOVA_MULT = 1.5
local NOVA_RADIUS = 10
local NOVA_COOLDOWN = 4
local BLAST_MULT = 1.6
local BLAST_RADIUS = 12

local TRAIL_SECONDS = 4
local TRAIL_MULT_PER_TICK = 0.225 -- 45% Weapon Damage per second, ticked every 0.5s
local ZONE_TICK = 0.5
local MAX_ZONES_PER_PLAYER = 6
local ABILITY_MULTI_CAST_MULT = 0.75

local REFLECT_SPEED_MULT = 1.4
local REFLECT_STUN_SECONDS = 4
local REFLECT_HP_FRACTION = 0.05

local STEP_SECONDS = 1 / 30
local MAX_FRAME_SECONDS = 0.2
local NUMBER_FLUSH_SECONDS = 0.1

local OFFER_CARDS = 3
local OFFER_CARDS_VIP = 4

-- Ascension Shop node ids (Section 23)
local NODE_MIGHT = "AS_T1_01"
local NODE_FATE = "AS_T2_02"
local NODE_RELIC_RESONANCE = "AS_T3_02"
local NODE_LIMIT_BREAKER = "AS_T4_01"
local NODE_OMNIPOTENCE = "AS_INF_01"

-- State -------------------------------------------------------------------------------------------------------

local rng = Random.new()
local combat: { [Player]: PlayerCombat } = {}
local projectiles: { [number]: Projectile } = {}
local zones: { Zone } = {}
local numberQueue: { [number]: { { [string]: any } } } = {}
local lastRemoteAt: { [Player]: { [string]: number } } = {}
local nextProjectileId = 1
local nextOfferId = 1

local fxRemote: RemoteEvent
local numberRemote: RemoteEvent
local offerRemote: RemoteEvent
local notifyRemote: RemoteEvent

-- Helpers -----------------------------------------------------------------------------------------------------

local function nodeLevel(profile: PlayerProfileData, nodeId: string): number
	return profile.AscensionNodes[nodeId] or 0
end

local function signOf(value: number): number
	return if value >= 0 then 1 else -1
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

-- Cosmetics go to everyone in the run (optionally skipping the player who predicted them locally).
local function fx(runId: number, payload: { [string]: any }, exclude: Player?)
	for _, player in RunManagerService.GetPlayersInRun(runId, false) do
		if player ~= exclude then
			fxRemote:FireClient(player, payload)
		end
	end
end

local function queueNumber(runId: number, entry: { [string]: any })
	local list = numberQueue[runId]
	if not list then
		list = {}
		numberQueue[runId] = list
	end
	table.insert(list, entry)
end

local function flushNumbers()
	for runId, list in numberQueue do
		for _, player in RunManagerService.GetPlayersInRun(runId, false) do
			numberRemote:FireClient(player, list)
		end
	end
	table.clear(numberQueue)
end

-- Returns true when `player` may fire `action` now (a flood guard on top of the real cooldowns).
local function passesRateLimit(player: Player, action: string): boolean
	local now = os.clock()
	local record = lastRemoteAt[player]
	if not record then
		record = {}
		lastRemoteAt[player] = record
	end
	if now - (record[action] or 0) < MIN_REMOTE_GAP then
		return false
	end
	record[action] = now
	return true
end

local function livingEnemies(runId: number): { EnemyState }
	local list: { EnemyState } = {}
	for _, state in EnemyAIService.States do
		if state.RunId == runId and not state.Dead then
			table.insert(list, state)
		end
	end
	return list
end

-- Living enemies whose body is within `radius` of a point.
local function enemiesInRadius(runId: number, cx: number, cy: number, radius: number, except: EnemyState?): { EnemyState }
	local list: { EnemyState } = {}
	for _, state in livingEnemies(runId) do
		if state ~= except then
			local ex, ey, hx, hy = EnemyAIService.Box(state)
			local dx = math.max(0, math.abs(ex - cx) - hx)
			local dy = math.max(0, math.abs(ey - cy) - hy)
			if dx * dx + dy * dy <= radius * radius then
				table.insert(list, state)
			end
		end
	end
	return list
end

-- Player context ----------------------------------------------------------------------------------------------

local function recomputeMods(pc: PlayerCombat)
	pc.Mods = UpgradePoolConfig.SumMods(pc.Stacks)
end

local function getWeapon(profile: PlayerProfileData): WeaponInfo
	return WeaponConfig.Weapons[profile.EquippedWeapon] or WeaponConfig.Weapons[WeaponConfig.DEFAULT_WEAPON]
end

local function linkBonus(profile: PlayerProfileData, stat: string): number
	return RunManagerService.GetLinkBonus(profile, stat)
end

local function newPlayerCombat(player: Player, runId: number, profile: PlayerProfileData): PlayerCombat
	local mobility = Physics25D.GetMobility(profile.AscensionNodes[Physics25D.SKYWALKER_NODE_ID] or 0)
	local fate = nodeLevel(profile, NODE_FATE)
	local banishPass = if player:GetAttribute("HasBanishPass") == true then 3 else 0
	local pc: PlayerCombat = {
		Player = player,
		RunId = runId,
		NextBasicAt = 0,
		NextAbilityAt = 0,
		Combo = 0,
		ComboExpiresAt = 0,
		DashCharges = mobility.DashCharges,
		DashRecharge = 0,
		InvulnUntil = 0,
		HurtUntil = 0,
		ShadowStepUntil = 0,
		MomentumUntil = 0,
		Stacks = {},
		Mods = {},
		Banished = {},
		Rerolls = fate + (if profile.RebirthTier >= 2 then 1 else 0),
		Banishes = fate + banishPass,
		Offer = nil,
		QueuedOffers = 0,
		Zones = 0,
	}
	player:SetAttribute("Combo", 0)
	return pc
end

-- The combat state for a player currently inside a run, or nil (combat only exists inside portal runs).
local function getPlayerCombat(player: Player): PlayerCombat?
	local run = RunManagerService.GetRunOf(player)
	if not run or run.Phase == "Ended" then
		combat[player] = nil
		return nil
	end
	local existing = combat[player]
	if existing and existing.RunId == run.Id then
		return existing
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	local created = newPlayerCombat(player, run.Id, profile)
	combat[player] = created
	return created
end

local function isRunAlive(player: Player, runId: number): boolean
	local run = RunManagerService.GetRunById(runId)
	local runPlayer = if run then run.Players[player] else nil
	return runPlayer ~= nil and runPlayer.Status == "Alive"
end

-- DamageParams for one player/weapon (Section 24.2). SkillMultiplier / TargetBonus / CritRate are filled in per hit.
local function makeParams(profile: PlayerProfileData, weapon: WeaponInfo, pc: PlayerCombat?): DamageParams
	local mastery = profile.WeaponMastery[weapon.Id]
	local mods: { [string]: number } = if pc then pc.Mods else {}
	return {
		WeaponBaseDmg = weapon.BaseDamage,
		HunterLevel = profile.HunterLevel,
		LegacyBonusLevels = profile.LegacyBonusLevels,
		WeaponMasteryLevel = if mastery then mastery.Level else 1,
		WeaponParagonRank = if mastery then mastery.ParagonRank else 0,
		SkillMultiplier = 1,
		RebirthTier = profile.RebirthTier,
		IsPureRun = false,
		AscendantMightLv = nodeLevel(profile, NODE_MIGHT),
		InfOmnipotenceLv = nodeLevel(profile, NODE_OMNIPOTENCE),
		LinkSkillDmgBonus = 0,
		RelicDmgBonus = 0,
		RelicResonanceLv = nodeLevel(profile, NODE_RELIC_RESONANCE),
		RunAdditiveBonus = mods.AdditiveDmg or 0,
		ComboCount = if pc then pc.Combo else 0,
		CurseDmgMultiplier = 1,
		TargetBonus = 0,
		CritRate = BASE_CRIT_RATE,
		CritDamageMult = BASE_CRIT_DAMAGE + (mods.CritDamage or 0) + linkBonus(profile, "CritDamage"),
		LimitBreakerLv = nodeLevel(profile, NODE_LIMIT_BREAKER),
		PartyHostBaselinePower = nil,
	}
end

local function makeAttackCtx(player: Player): AttackCtx?
	local pc = getPlayerCombat(player)
	local profile = PlayerDataService.Get(player)
	if not pc or not profile or not isRunAlive(player, pc.RunId) then
		return nil
	end
	local run = RunManagerService.GetRunById(pc.RunId)
	if not run then
		return nil
	end
	local weapon = getWeapon(profile)
	local params = makeParams(profile, weapon, pc)

	-- Rift Sidekick Sync (Section 18.2): lift weaker party members to 70% of the host's combat power.
	if run.Host ~= player and RunManagerService.GetPartySize(run) > 1 then
		local hostProfile = PlayerDataService.Get(run.Host)
		if hostProfile then
			local hostWeapon = getWeapon(hostProfile)
			params.PartyHostBaselinePower = FormulaEngine.GetCorePower(makeParams(hostProfile, hostWeapon, nil))
		end
	end

	local mods = pc.Mods
	return {
		Player = player,
		PC = pc,
		Profile = profile,
		Weapon = weapon,
		RunId = pc.RunId,
		Params = params,
		Mods = mods,
		CritRate = BASE_CRIT_RATE + (mods.CritRate or 0) + linkBonus(profile, "CritRate"),
		NormalBonus = linkBonus(profile, "NormalEliteDamage"),
		BossBonus = linkBonus(profile, "BossDamage"),
		ForceCrit = false,
	}
end

local function attackInterval(ctx: AttackCtx): number
	local speed = 1 + (ctx.Mods.AttackSpeed or 0) + linkBonus(ctx.Profile, "AttackSpeedCooldown")
	if os.clock() < ctx.PC.MomentumUntil then
		speed += MOMENTUM_ATTACK_SPEED
	end
	return 1 / (ctx.Weapon.AttacksPerSecond * speed)
end

local function publishAttackInterval(ctx: AttackCtx)
	ctx.Player:SetAttribute("AttackInterval", attackInterval(ctx))
end

local function bumpCombo(pc: PlayerCombat, hits: number)
	pc.Combo += hits
	pc.ComboExpiresAt = os.clock() + COMBO_WINDOW
	pc.Player:SetAttribute("Combo", pc.Combo)
end

-- Damage rolling ----------------------------------------------------------------------------------------------

local function rollDamage(ctx: AttackCtx, skillMult: number, targetBonus: number, critRate: number): (number, boolean, { number })
	local params = ctx.Params
	params.SkillMultiplier = skillMult
	params.TargetBonus = targetBonus
	params.CritRate = critRate
	params.ComboCount = ctx.PC.Combo
	return FormulaEngine.CalculateHitDamage(params, rng)
end

local function targetBonusFor(ctx: AttackCtx, enemy: EnemyState): number
	return if enemy.Kind == "Boss" then ctx.BossBonus else ctx.NormalBonus
end

local killEnemy: (EnemyState, Player?) -> ()

-- Applies finished damage to an enemy, mirrors HP onto the model for clients, and kills it at zero.
local function damageEnemy(enemy: EnemyState, amount: number, source: Player?, opts: DamageOpts?)
	if enemy.Dead or amount <= 0 then
		return
	end
	local options: DamageOpts = opts or {}
	enemy.HP = math.max(0, enemy.HP - amount)
	enemy.Model:SetAttribute("HP", enemy.HP)
	if options.Dir then
		enemy.Model:SetAttribute("HitDir", options.Dir)
	end

	queueNumber(enemy.RunId, {
		Pos = enemy.Feet + Vector3.new(0, enemy.Half.Y * 2, 0),
		Amount = options.Primary or amount,
		Crit = options.Crit == true,
		Lines = options.Lines,
		Kind = options.Kind or "Hit",
		Owner = if source then source.UserId else 0,
	})

	if enemy.HP <= 0 then
		killEnemy(enemy, source)
	end
end

-- Statuses ----------------------------------------------------------------------------------------------------

local function applyBurn(ctx: AttackCtx, enemy: EnemyState, stacks: number)
	local perSecond = rollDamage(ctx, BURN_PCT_PER_SECOND, targetBonusFor(ctx, enemy), 0)
	local dps = perSecond * (1 + BURN_STACK_BONUS * (stacks - 1))
	local now = os.clock()
	local existing = enemy.Burn
	enemy.Burn = {
		Until = now + BURN_SECONDS,
		Dps = if existing then math.max(existing.Dps, dps) else dps,
		NextTick = if existing then existing.NextTick else now + BURN_TICK,
		Source = ctx.Player,
	}
	enemy.Model:SetAttribute("Burning", true)
end

local function applyShock(enemy: EnemyState, source: Player)
	enemy.Shock = { Until = os.clock() + SHOCK_SECONDS, Source = source }
	enemy.Model:SetAttribute("Shocked", true)
end

local strikeEnemy: (AttackCtx, EnemyState, number, StrikeFlags?) -> number

-- Shock: hits on a Shocked enemy arc to nearby enemies (Section 9). Chain damage is a flat share of the hit.
local function chainLightning(ctx: AttackCtx, from: EnemyState, hitDamage: number, stacks: number)
	local fx0, fy0 = from.Feet.X, from.Feet.Y + from.Half.Y
	local candidates = enemiesInRadius(ctx.RunId, fx0, fy0, CHAIN_RANGE, from)
	table.sort(candidates, function(a: EnemyState, b: EnemyState)
		return math.abs(a.Feet.X - fx0) < math.abs(b.Feet.X - fx0)
	end)
	local share = CHAIN_MULT + CHAIN_STACK_BONUS * math.max(0, stacks - 1)
	for index = 1, math.min(CHAIN_TARGETS, #candidates) do
		local target = candidates[index]
		local tx, ty = target.Feet.X, target.Feet.Y + target.Half.Y
		fx(ctx.RunId, {
			Kind = "Chain", From = Vector3.new(fx0, fy0, 0), To = Vector3.new(tx, ty, 0), Owner = ctx.Player.UserId,
		})
		damageEnemy(target, math.max(1, math.round(hitDamage * share)), ctx.Player,
			{ Kind = "Chain", Dir = signOf(tx - fx0) })
	end
end

-- Staff passive: an enemy carrying two different statuses detonates an Arcane Nova.
local function checkResonance(ctx: AttackCtx, enemy: EnemyState)
	if ctx.Weapon.Id ~= "Staff" or enemy.Dead or not enemy.Burn or not enemy.Shock then
		return
	end
	local now = os.clock()
	if now < enemy.NovaReadyAt then
		return
	end
	enemy.NovaReadyAt = now + NOVA_COOLDOWN
	local cx, cy = enemy.Feet.X, enemy.Feet.Y + enemy.Half.Y
	fx(ctx.RunId, { Kind = "Burst", Pos = Vector3.new(cx, cy, 0), Radius = NOVA_RADIUS, Style = "Nova", Owner = ctx.Player.UserId })
	for _, victim in enemiesInRadius(ctx.RunId, cx, cy, NOVA_RADIUS, nil) do
		strikeEnemy(ctx, victim, NOVA_MULT, { NoChain = true, NoStatus = true })
	end
end

local function applyOnHitEffects(ctx: AttackCtx, enemy: EnemyState, primary: number, flags: StrikeFlags?)
	local options: StrikeFlags = flags or {}
	local burnStacks = ctx.Mods.BurnOnHit or 0
	if options.NativeBurn then
		burnStacks = math.max(burnStacks, 1)
	end
	if burnStacks > 0 then
		applyBurn(ctx, enemy, burnStacks)
	end

	local shockStacks = ctx.Mods.ShockOnHit or 0
	if options.NativeShock then
		shockStacks = math.max(shockStacks, 1)
	end
	if shockStacks > 0 then
		applyShock(enemy, ctx.Player)
	end

	if enemy.Shock and not options.NoChain then
		chainLightning(ctx, enemy, primary, math.max(1, shockStacks))
	end
	checkResonance(ctx, enemy)
end

-- One full hit from a player on an enemy: formula damage (+ Limit Breaker shadow lines), combo, on-hit effects.
strikeEnemy = function(ctx: AttackCtx, enemy: EnemyState, skillMult: number, flags: StrikeFlags?): number
	if enemy.Dead then
		return 0
	end
	local critRate = if ctx.ForceCrit then 1 else ctx.CritRate
	local primary, crit, lines = rollDamage(ctx, skillMult, targetBonusFor(ctx, enemy), critRate)
	local total = primary
	for _, line in lines do
		total += line
	end

	local root = getRoot(ctx.Player)
	local dir = if root then signOf(enemy.Feet.X - root.Position.X) else 1
	damageEnemy(enemy, total, ctx.Player, { Crit = crit, Primary = primary, Lines = lines, Dir = dir })
	bumpCombo(ctx.PC, 1)

	if not enemy.Dead and not (flags and flags.NoStatus) then
		applyOnHitEffects(ctx, enemy, primary, flags)
	end
	return total
end

-- Kills ------------------------------------------------------------------------------------------------------

local function burnBlast(source: Player, enemy: EnemyState)
	local ctx = makeAttackCtx(source)
	if not ctx then
		return
	end
	local cx, cy = enemy.Feet.X, enemy.Feet.Y + enemy.Half.Y
	fx(enemy.RunId, { Kind = "Burst", Pos = Vector3.new(cx, cy, 0), Radius = BLAST_RADIUS, Style = "Cinders", Owner = source.UserId })
	for _, victim in enemiesInRadius(enemy.RunId, cx, cy, BLAST_RADIUS, enemy) do
		strikeEnemy(ctx, victim, BLAST_MULT, { NoChain = true, NoStatus = true })
		if not victim.Dead and enemy.Burn then
			applyBurn(ctx, victim, 1)
		end
	end
end

killEnemy = function(enemy: EnemyState, killer: Player?)
	if enemy.Dead then
		return
	end
	enemy.Dead = true
	enemy.HP = 0

	local burn = enemy.Burn
	if burn then
		local source = burn.Source
		local pc = combat[source]
		local ctx = makeAttackCtx(source)
		if ctx then
			-- Burn spreads to everything nearby when its host dies (Section 9).
			local cx, cy = enemy.Feet.X, enemy.Feet.Y + enemy.Half.Y
			for _, neighbour in enemiesInRadius(enemy.RunId, cx, cy, BURN_SPREAD_RADIUS, enemy) do
				applyBurn(ctx, neighbour, 1)
			end
		end
		if pc and (pc.Mods.BurnBlast or 0) > 0 then
			burnBlast(source, enemy)
		end
	end

	RunManagerService.ReportEnemyDefeated(enemy.Model, killer or (if burn then burn.Source else nil))
end

-- Player damage -----------------------------------------------------------------------------------------------

-- Hurts a player unless dash i-frames, post-hit i-frames, a Revive ForceField or death protect them.
local function damagePlayer(player: Player, amount: number, source: string): boolean
	local pc = getPlayerCombat(player)
	local humanoid = getHumanoid(player)
	local root = getRoot(player)
	if not pc or not humanoid or not root or humanoid.Health <= 0 or not isRunAlive(player, pc.RunId) then
		return false
	end
	local now = os.clock()
	if now < pc.InvulnUntil or now < pc.HurtUntil or (player.Character and player.Character:FindFirstChildOfClass("ForceField")) then
		return false
	end

	local damage = math.max(1, math.round(amount))
	humanoid:TakeDamage(damage)
	pc.HurtUntil = now + HURT_IFRAMES
	fxRemote:FireClient(player, { Kind = "Shake", Intensity = 0.5, Duration = 0.25 })
	queueNumber(pc.RunId, {
		Pos = root.Position + Vector3.new(0, 3, 0), Amount = damage, Crit = false, Kind = "Hurt", Owner = player.UserId,
	})
	return true
end

-- Projectiles -------------------------------------------------------------------------------------------------

local PIERCING_ENEMY_STYLES: { [string]: boolean } = { Shockwave = true }

local function newProjectile(fields: { [string]: any }): Projectile
	local id = nextProjectileId
	nextProjectileId += 1
	local pos = fields.Pos :: Vector3
	local projectile: Projectile = {
		Id = id,
		Team = fields.Team or "Player",
		RunId = fields.RunId,
		Pos = pos,
		StartPos = pos,
		Vel = fields.Vel,
		HalfX = fields.HalfX,
		HalfY = fields.HalfY,
		ExpiresAt = os.clock() + fields.Life,
		Style = fields.Style,
		Owner = fields.Owner,
		SourceEnemy = fields.SourceEnemy,
		Damage = fields.Damage or 0,
		SkillMult = fields.SkillMult or 1,
		Pierce = fields.Pierce == true,
		ExplodeRadius = fields.ExplodeRadius,
		Burn = fields.Burn == true,
		Shock = fields.Shock == true,
		Trail = fields.Trail == true,
		ForceCrit = fields.ForceCrit == true,
		CanReflect = fields.CanReflect == true,
		Reflectable = fields.Reflectable == true,
		Reflected = false,
		Hit = {},
	}
	projectiles[id] = projectile
	fx(projectile.RunId, {
		Kind = "Proj", Id = id, Style = projectile.Style, Pos = pos, Vel = projectile.Vel,
		Life = fields.Life, HalfX = projectile.HalfX, HalfY = projectile.HalfY,
		Owner = if projectile.Owner then projectile.Owner.UserId else 0,
	})
	return projectile
end

local function spawnEnemyProjectile(spec: EnemyAIService.EnemyProjectileSpec)
	newProjectile({
		Team = "Enemy",
		RunId = spec.RunId,
		Pos = spec.Pos,
		Vel = spec.Vel,
		HalfX = spec.HalfX,
		HalfY = spec.HalfY,
		Life = spec.Life,
		Style = spec.Style,
		SourceEnemy = spec.Owner,
		Damage = spec.Damage,
		Reflectable = spec.Reflectable,
		Pierce = PIERCING_ENEMY_STYLES[spec.Style] == true,
	})
end

local function addZone(owner: Player, runId: number, cx: number, cy: number, halfX: number, halfY: number)
	local pc = combat[owner]
	if not pc then
		return
	end
	local now = os.clock()
	if pc.Zones >= MAX_ZONES_PER_PLAYER then
		for index, zone in zones do
			if zone.Owner == owner then
				table.remove(zones, index)
				pc.Zones -= 1
				break
			end
		end
	end
	pc.Zones += 1
	table.insert(zones, {
		RunId = runId, Owner = owner, CenterX = cx, CenterY = cy, HalfX = halfX, HalfY = halfY,
		ExpiresAt = now + TRAIL_SECONDS, NextTickAt = now + ZONE_TICK,
	})
	fx(runId, {
		Kind = "Zone", Pos = Vector3.new(cx, cy, 0), HalfX = halfX, HalfY = halfY, Duration = TRAIL_SECONDS, Owner = owner.UserId,
	})
end

local function endProjectile(projectile: Projectile, hit: boolean)
	if not projectiles[projectile.Id] then
		return
	end
	projectiles[projectile.Id] = nil
	fx(projectile.RunId, { Kind = "ProjEnd", Id = projectile.Id, Pos = projectile.Pos, Hit = hit })

	if projectile.Trail and projectile.Owner and combat[projectile.Owner] then
		local a, b = projectile.StartPos, projectile.Pos
		addZone(projectile.Owner, projectile.RunId, (a.X + b.X) / 2, (a.Y + b.Y) / 2, math.abs(b.X - a.X) / 2 + 3, 3.5)
	end
end

-- A basic attack knocks a spore boulder back at the boss that threw it.
local function reflectProjectile(projectile: Projectile, player: Player)
	local source = projectile.SourceEnemy
	if not projectile.Reflectable or projectile.Reflected or not source or source.Dead then
		return
	end
	projectile.Team = "Player"
	projectile.Owner = player
	projectile.Reflected = true
	projectile.Pierce = true
	projectile.Hit = {}
	local dir = signOf(source.Feet.X - projectile.Pos.X)
	projectile.Vel = Vector3.new(dir * projectile.Vel.Magnitude * REFLECT_SPEED_MULT, 0, 0)
	projectile.ExpiresAt = os.clock() + 3
	fx(projectile.RunId, { Kind = "ProjReflect", Id = projectile.Id, Pos = projectile.Pos, Vel = projectile.Vel })
end

local function explodeProjectile(projectile: Projectile, ctx: AttackCtx)
	local radius = projectile.ExplodeRadius or 6
	local cx, cy = projectile.Pos.X, projectile.Pos.Y
	fx(projectile.RunId, {
		Kind = "Burst", Pos = Vector3.new(cx, cy, 0), Radius = radius, Style = projectile.Style, Owner = ctx.Player.UserId,
	})
	for _, victim in enemiesInRadius(projectile.RunId, cx, cy, radius, nil) do
		strikeEnemy(ctx, victim, projectile.SkillMult, { NativeBurn = projectile.Burn, NativeShock = projectile.Shock })
	end
end

-- Player-team projectile touched an enemy.
local function onPlayerProjectileHit(projectile: Projectile, enemy: EnemyState): boolean
	local owner = projectile.Owner
	local ctx = if owner then makeAttackCtx(owner) else nil
	if not ctx then
		return true -- owner left the run; drop the projectile
	end
	ctx.ForceCrit = projectile.ForceCrit

	if projectile.Reflected then
		-- A smacked-back boulder only cares about the boss that threw it.
		if enemy ~= projectile.SourceEnemy then
			return false
		end
		EnemyAIService.Stun(enemy, REFLECT_STUN_SECONDS)
		damageEnemy(enemy, math.max(1, math.round(enemy.MaxHP * REFLECT_HP_FRACTION)), owner,
			{ Crit = true, Kind = "Reflect", Dir = signOf(projectile.Vel.X) })
		fx(projectile.RunId, { Kind = "Burst", Pos = projectile.Pos, Radius = 9, Style = "Slam", Owner = ctx.Player.UserId })
		fx(projectile.RunId, { Kind = "Shake", Intensity = 1.0, Duration = 0.4 })
		return true
	end

	if projectile.ExplodeRadius then
		explodeProjectile(projectile, ctx)
	else
		strikeEnemy(ctx, enemy, projectile.SkillMult, { NativeBurn = projectile.Burn, NativeShock = projectile.Shock })
	end
	return not projectile.Pierce
end

local function stepProjectile(projectile: Projectile, dt: number, now: number): boolean
	local run = RunManagerService.GetRunById(projectile.RunId)
	if not run then
		endProjectile(projectile, false)
		return true
	end
	if now >= projectile.ExpiresAt then
		endProjectile(projectile, false)
		return true
	end

	local oldPos = projectile.Pos
	local newPos = oldPos + projectile.Vel * dt
	local origin = run.Origin
	local tile = RoomAsciiTemplates.TILE_SIZE
	local minX = origin.X + tile.X
	local maxX = origin.X + RoomAsciiTemplates.COLUMNS * tile.X - tile.X
	local hitWall = newPos.X < minX or newPos.X > maxX
	if hitWall then
		newPos = Vector3.new(math.clamp(newPos.X, minX, maxX), newPos.Y, 0)
	end
	projectile.Pos = newPos

	-- Swept box so fast projectiles can't tunnel through small enemies or a player.
	local midX, midY = (oldPos.X + newPos.X) / 2, (oldPos.Y + newPos.Y) / 2
	local halfX = math.abs(newPos.X - oldPos.X) / 2 + projectile.HalfX
	local halfY = math.abs(newPos.Y - oldPos.Y) / 2 + projectile.HalfY
	local finished = false

	if projectile.Team == "Player" then
		-- Reflect a boulder on contact (basic-attack bolts and anything that already reflected one stay clean).
		if projectile.CanReflect and projectile.Owner then
			for _, other in projectiles do
				if other.Team == "Enemy" and other.Reflectable and other.RunId == projectile.RunId
					and EnemyAIService.Overlap(midX, midY, halfX, halfY, other.Pos.X, other.Pos.Y, other.HalfX, other.HalfY) then
					reflectProjectile(other, projectile.Owner)
					finished = true
					break
				end
			end
		end
		if not finished then
			for _, enemy in livingEnemies(projectile.RunId) do
				if not projectile.Hit[enemy] then
					local ex, ey, ehx, ehy = EnemyAIService.Box(enemy)
					if EnemyAIService.Overlap(midX, midY, halfX, halfY, ex, ey, ehx, ehy) then
						projectile.Hit[enemy] = true
						if onPlayerProjectileHit(projectile, enemy) then
							finished = true
							break
						end
					end
				end
			end
		end
	else
		for _, player in RunManagerService.GetPlayersInRun(projectile.RunId, true) do
			local root = getRoot(player)
			if root and not projectile.Hit[player] then
				local feet = EnemyAIService.PLAYER_FEET_OFFSET
				local head = EnemyAIService.PLAYER_HEAD_OFFSET
				local py = root.Position.Y + (head - feet) / 2
				if EnemyAIService.Overlap(midX, midY, halfX, halfY, root.Position.X, py,
					EnemyAIService.PLAYER_HALF_WIDTH, (head + feet) / 2) then
					projectile.Hit[player] = true
					if damagePlayer(player, projectile.Damage, projectile.Style) and not projectile.Pierce then
						finished = true
						break
					end
				end
			end
		end
	end

	if finished or hitWall then
		endProjectile(projectile, finished)
		return true
	end
	return false
end

-- Statuses & zones -------------------------------------------------------------------------------------------

local function tickStatuses(now: number)
	for _, enemy in EnemyAIService.States do
		if enemy.Dead then
			continue
		end
		local burn = enemy.Burn
		if burn then
			if now >= burn.Until then
				enemy.Burn = nil
				enemy.Model:SetAttribute("Burning", nil)
			elseif now >= burn.NextTick then
				burn.NextTick += BURN_TICK
				damageEnemy(enemy, math.max(1, math.round(burn.Dps * BURN_TICK)), burn.Source, { Kind = "Dot" })
			end
		end
		local shock = enemy.Shock
		if shock and now >= shock.Until then
			enemy.Shock = nil
			enemy.Model:SetAttribute("Shocked", nil)
		end
	end
end

local function tickZones(now: number)
	for index = #zones, 1, -1 do
		local zone = zones[index]
		local pc = combat[zone.Owner]
		if now >= zone.ExpiresAt or not pc or pc.RunId ~= zone.RunId or not RunManagerService.GetRunById(zone.RunId) then
			table.remove(zones, index)
			if pc then
				pc.Zones = math.max(0, pc.Zones - 1)
			end
		elseif now >= zone.NextTickAt then
			zone.NextTickAt += ZONE_TICK
			local ctx = makeAttackCtx(zone.Owner)
			if ctx then
				for _, enemy in livingEnemies(zone.RunId) do
					local ex, ey, ehx, ehy = EnemyAIService.Box(enemy)
					if EnemyAIService.Overlap(zone.CenterX, zone.CenterY, zone.HalfX, zone.HalfY, ex, ey, ehx, ehy) then
						strikeEnemy(ctx, enemy, TRAIL_MULT_PER_TICK, { NoChain = true, NoStatus = true })
					end
				end
			end
		end
	end
end

local function tickPlayers(dt: number, now: number)
	for player, pc in combat do
		if not player.Parent then
			combat[player] = nil
			continue
		end
		if pc.Combo > 0 and now > pc.ComboExpiresAt then
			pc.Combo = 0
			player:SetAttribute("Combo", 0)
		end
		local profile = PlayerDataService.Get(player)
		if profile then
			local mobility = Physics25D.GetMobility(profile.AscensionNodes[Physics25D.SKYWALKER_NODE_ID] or 0)
			if pc.DashCharges < mobility.DashCharges then
				pc.DashRecharge += dt
				if pc.DashRecharge >= mobility.DashCooldown then
					pc.DashRecharge = 0
					pc.DashCharges += 1
				end
			else
				pc.DashRecharge = 0
			end
		end
	end
end

-- Attacks -----------------------------------------------------------------------------------------------------

local function doMeleeAttack(ctx: AttackCtx, profile: AttackProfile, facing: number, root: BasePart)
	local rx, ry = root.Position.X, root.Position.Y
	local reach = profile.Range * (1 + (ctx.Mods.RangeMult or 0))
	local back = profile.Back or 1
	local minX = if facing > 0 then rx - back else rx - reach
	local maxX = if facing > 0 then rx + reach else rx + back
	local cx, hx = (minX + maxX) / 2, (maxX - minX) / 2

	fx(ctx.RunId, {
		Kind = "Swing", Owner = ctx.Player.UserId, Weapon = ctx.Weapon.Id, Style = profile.Style,
		Pos = Vector3.new(rx, ry, 0), Facing = facing, Range = reach, Height = profile.Height,
	}, ctx.Player)

	local hits: { EnemyState } = {}
	for _, enemy in livingEnemies(ctx.RunId) do
		local ex, ey, ehx, ehy = EnemyAIService.Box(enemy)
		if EnemyAIService.Overlap(cx, ry, hx, profile.Height, ex, ey, ehx, ehy) then
			table.insert(hits, enemy)
		end
	end
	table.sort(hits, function(a: EnemyState, b: EnemyState)
		return math.abs(a.Feet.X - rx) < math.abs(b.Feet.X - rx)
	end)

	local limit = profile.MaxTargets + (ctx.Mods.ExtraTargets or 0)
	local struck = 0
	for index = 1, math.min(limit, #hits) do
		strikeEnemy(ctx, hits[index], profile.Mult)
		struck += 1
	end

	-- Smack back any boulders inside the swing.
	for _, projectile in projectiles do
		if projectile.Team == "Enemy" and projectile.Reflectable and projectile.RunId == ctx.RunId
			and EnemyAIService.Overlap(cx, ry, hx, profile.Height, projectile.Pos.X, projectile.Pos.Y, projectile.HalfX, projectile.HalfY) then
			reflectProjectile(projectile, ctx.Player)
		end
	end

	-- Greatsword passive: Berserker's Momentum
	if ctx.Weapon.Id == "Greatsword" and struck >= 3 then
		ctx.PC.MomentumUntil = os.clock() + MOMENTUM_SECONDS
	end
end

local function doProjectileAttack(ctx: AttackCtx, profile: AttackProfile, facing: number, root: BasePart)
	local speed = profile.Speed or 70
	local half = profile.HalfSize or 1.4
	newProjectile({
		Team = "Player",
		RunId = ctx.RunId,
		Pos = root.Position + Vector3.new(facing * 2, 0.5, 0),
		Vel = Vector3.new(facing * speed, 0, 0),
		HalfX = half,
		HalfY = half,
		Life = profile.Range / speed,
		Style = profile.Style,
		Owner = ctx.Player,
		SkillMult = profile.Mult,
		CanReflect = true,
		ForceCrit = ctx.ForceCrit,
		Shock = ctx.Weapon.Id == "Staff", -- the Staff's arcane bolts Shock; its Fireball Burns
	})
end

local function castAbility(ctx: AttackCtx, ability: AbilityProfile, facing: number, root: BasePart)
	local extra = ctx.Mods.AbilityCasts or 0
	local count = ability.Count + extra
	local perMult = ability.Mult * (if ability.Count == 1 and extra > 0 then ABILITY_MULTI_CAST_MULT else 1)
	local origin = root.Position + Vector3.new(facing * 2, 0.5, 0)

	for index = 1, count do
		local angle = math.rad((index - (count + 1) / 2) * ability.FanDeg)
		local velocity = Vector3.new(facing * math.cos(angle), math.sin(angle), 0) * ability.Speed
		newProjectile({
			Team = "Player",
			RunId = ctx.RunId,
			Pos = origin,
			Vel = velocity,
			HalfX = ability.HalfX,
			HalfY = ability.HalfY,
			Life = ability.Life,
			Style = ability.Style,
			Owner = ctx.Player,
			SkillMult = perMult,
			Pierce = ability.Pierce,
			ExplodeRadius = ability.ExplodeRadius,
			Burn = ability.Burn == true,
			Trail = (ctx.Mods.AbilityTrail or 0) > 0,
			ForceCrit = ctx.ForceCrit,
		})
	end
end

local function consumeShadowStep(ctx: AttackCtx)
	local pc = ctx.PC
	if os.clock() < pc.ShadowStepUntil then
		ctx.ForceCrit = true
		pc.ShadowStepUntil = 0
	end
end

local function onAttack(player: Player, slot: any, facingInput: any)
	if slot ~= "Basic" and slot ~= "Ability1" then
		return
	end
	if type(facingInput) ~= "number" or facingInput ~= facingInput then
		return
	end
	if not passesRateLimit(player, "Attack" .. slot) then
		return
	end
	local ctx = makeAttackCtx(player)
	local humanoid = getHumanoid(player)
	local root = getRoot(player)
	if not ctx or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local facing = signOf(facingInput)
	local pc = ctx.PC
	local now = os.clock()

	if slot == "Basic" then
		local interval = attackInterval(ctx)
		if now < pc.NextBasicAt - ATTACK_LATENCY_CREDIT then
			return
		end
		pc.NextBasicAt = math.max(pc.NextBasicAt, now - ATTACK_LATENCY_CREDIT) + interval
		consumeShadowStep(ctx)

		local profile = ctx.Weapon.Attack or WeaponConfig.GenericAttack
		if profile.Kind == "Projectile" then
			doProjectileAttack(ctx, profile, facing, root)
		else
			doMeleeAttack(ctx, profile, facing, root)
		end
		publishAttackInterval(ctx)
	else
		local ability = ctx.Weapon.Ability
		if not ability or now < pc.NextAbilityAt - ABILITY_LATENCY_CREDIT then
			return
		end
		local cooldown = ability.Cooldown / (1 + linkBonus(ctx.Profile, "AttackSpeedCooldown"))
		pc.NextAbilityAt = now + cooldown
		player:SetAttribute("Ability1Cooldown", cooldown)
		player:SetAttribute("Ability1ReadyAt", Workspace:GetServerTimeNow() + cooldown)
		consumeShadowStep(ctx)
		castAbility(ctx, ability, facing, root)
	end
end

-- Dash: i-frames are server-timed, so a spoofed dash can only ever spend real charges.
local function onDash(player: Player, directionInput: any)
	if type(directionInput) ~= "number" or directionInput ~= directionInput then
		return
	end
	if not passesRateLimit(player, "Dash") then
		return
	end
	local pc = getPlayerCombat(player)
	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	if not pc or not root or not humanoid or humanoid.Health <= 0 or not isRunAlive(player, pc.RunId) then
		return
	end
	if pc.DashCharges <= 0 then
		return
	end
	pc.DashCharges -= 1
	pc.InvulnUntil = os.clock() + DASH_IFRAMES

	-- Daggers passive: dashing *through* an enemy guarantees the next attack crits.
	local profile = PlayerDataService.Get(player)
	if profile and profile.EquippedWeapon == "Daggers" then
		local startX, startY = root.Position.X, root.Position.Y
		local runId = pc.RunId
		task.delay(SHADOW_STEP_WINDOW, function()
			local endRoot = getRoot(player)
			local current = combat[player]
			if not endRoot or not current or current.RunId ~= runId then
				return
			end
			local lowX = math.min(startX, endRoot.Position.X) - 1
			local highX = math.max(startX, endRoot.Position.X) + 1
			for _, enemy in livingEnemies(runId) do
				local ex, ey, ehx, ehy = EnemyAIService.Box(enemy)
				if ex + ehx >= lowX and ex - ehx <= highX and math.abs(ey - startY) <= ehy + 4 then
					current.ShadowStepUntil = os.clock() + SHADOW_STEP_SECONDS
					break
				end
			end
		end)
	end
end

-- Upgrades ----------------------------------------------------------------------------------------------------

local function cardPayload(pc: PlayerCombat, card: Upgrade): { [string]: any }
	return {
		Id = card.Id, Name = card.Name, Desc = card.Desc, Rarity = card.Rarity, Icon = card.Icon,
		Stacks = pc.Stacks[card.Id] or 0, MaxStacks = card.MaxStacks,
	}
end

local function bankedRerolls(player: Player): number
	local profile = PlayerDataService.Get(player)
	return if profile then profile.BonusRerolls else 0
end

local function sendOffer(pc: PlayerCombat)
	local offer = pc.Offer
	if not offer then
		offerRemote:FireClient(pc.Player, { Kind = "Closed", OfferId = 0 })
		return
	end
	local cards = {}
	for _, card in offer.Cards do
		table.insert(cards, cardPayload(pc, card))
	end
	offerRemote:FireClient(pc.Player, {
		Kind = "Offer", OfferId = offer.Id, Cards = cards, Rerolls = pc.Rerolls + bankedRerolls(pc.Player),
		Banishes = pc.Banishes,
	})
end

local function rollCards(pc: PlayerCombat, count: number, exclude: { [string]: boolean }?): { Upgrade }
	local run = RunManagerService.GetRunById(pc.RunId)
	local profile = PlayerDataService.Get(pc.Player)
	return UpgradePoolConfig.RollCards(count, rng, {
		Stacks = pc.Stacks,
		Banished = pc.Banished,
		Exclude = exclude,
		Depth = if run then run.Depth else 1,
		Luck = if profile then linkBonus(profile, "RareUpgradeRate") else 0,
	})
end

local function presentNextOffer(pc: PlayerCombat)
	if pc.Offer or pc.QueuedOffers <= 0 then
		return
	end
	pc.QueuedOffers -= 1
	local count = if pc.Player:GetAttribute("HasVIPArchitect") == true then OFFER_CARDS_VIP else OFFER_CARDS
	local cards = rollCards(pc, count, nil)
	if #cards == 0 then
		pc.QueuedOffers = 0
		notify(pc.Player, "Your build has no upgrades left to find!")
		return
	end
	pc.Offer = { Id = nextOfferId, Cards = cards }
	nextOfferId += 1
	sendOffer(pc)
end

local function refreshMaxHealth(pc: PlayerCombat)
	local humanoid = getHumanoid(pc.Player)
	local profile = PlayerDataService.Get(pc.Player)
	if not humanoid or not profile then
		return
	end
	local newMax = FormulaEngine.GetPlayerMaxHP(profile.HunterLevel, profile.LegacyBonusLevels, profile.RebirthTier,
		nodeLevel(profile, NODE_MIGHT), 1 + (pc.Mods.MaxHPMult or 0))
	local gained = newMax - humanoid.MaxHealth
	humanoid.MaxHealth = newMax
	if gained > 0 then
		humanoid.Health = math.min(newMax, humanoid.Health + gained) -- the bonus arrives full
	end
end

local function applyUpgrade(pc: PlayerCombat, card: Upgrade)
	pc.Stacks[card.Id] = (pc.Stacks[card.Id] or 0) + 1
	recomputeMods(pc)
	if (card.Mods.MaxHPMult or 0) > 0 then
		refreshMaxHealth(pc)
	end
	local stacks = pc.Stacks[card.Id]
	notify(pc.Player, ("%s %s%s"):format(card.Icon, card.Name, if card.MaxStacks > 1 then (" x%d"):format(stacks) else ""))

	local profile = PlayerDataService.Get(pc.Player)
	local weapon = if profile then getWeapon(profile) else nil
	if weapon then
		local interval = 1 / (weapon.AttacksPerSecond * (1 + (pc.Mods.AttackSpeed or 0)))
		pc.Player:SetAttribute("AttackInterval", interval)
	end
end

local function onUpgradeChosen(player: Player, payload: any)
	if type(payload) ~= "table" or not passesRateLimit(player, "Upgrade") then
		return
	end
	local pc = combat[player]
	local offer = if pc then pc.Offer else nil
	local action = payload.Action
	local index = payload.Index
	if not pc or not offer or payload.OfferId ~= offer.Id or type(action) ~= "string" then
		return
	end
	if action == "Pick" then
		if type(index) ~= "number" or index ~= index then
			return
		end
		local card = offer.Cards[math.floor(index)]
		if not card then
			return
		end
		pc.Offer = nil
		applyUpgrade(pc, card)
		offerRemote:FireClient(player, { Kind = "Closed", OfferId = offer.Id })
		presentNextOffer(pc)
	elseif action == "Reroll" then
		if pc.Rerolls <= 0 and bankedRerolls(player) <= 0 then
			return
		end
		local exclude: { [string]: boolean } = {}
		for _, card in offer.Cards do
			exclude[card.Id] = true
		end
		local cards = rollCards(pc, #offer.Cards, exclude)
		if #cards == 0 then
			return
		end
		if pc.Rerolls > 0 then
			pc.Rerolls -= 1
		else
			PlayerDataService.Mutate(player, function(data)
				data.BonusRerolls -= 1
			end)
		end
		offer.Cards = cards
		sendOffer(pc)
	elseif action == "Banish" then
		if pc.Banishes <= 0 or type(index) ~= "number" or index ~= index then
			return
		end
		local slot = math.floor(index)
		local card = offer.Cards[slot]
		if not card then
			return
		end
		pc.Banishes -= 1
		pc.Banished[card.Id] = true
		local exclude: { [string]: boolean } = {}
		for _, shown in offer.Cards do
			exclude[shown.Id] = true
		end
		local replacement = rollCards(pc, 1, exclude)[1]
		if replacement then
			offer.Cards[slot] = replacement
		else
			table.remove(offer.Cards, slot)
		end
		if #offer.Cards == 0 then
			pc.Offer = nil
			offerRemote:FireClient(player, { Kind = "Closed", OfferId = offer.Id })
			presentNextOffer(pc)
		else
			sendOffer(pc)
		end
	end
end

-- Cleared combat / jump / treasure rooms drop an Upgrade Orb (Section 6.1); boss rooms go straight to the Anchor.
local function onRoomCleared(runId: number, _roomNumber: number, players: { Player })
	local run = RunManagerService.GetRunById(runId)
	local room = if run then run.Room else nil
	if not run or (room and room.Type == "Boss") then
		return
	end
	for _, player in players do
		local pc = getPlayerCombat(player)
		if pc then
			pc.QueuedOffers += 1
			presentNextOffer(pc)
		end
	end
end

-- Public API --------------------------------------------------------------------------------------------------

-- Stack counts of the player's current run build (read-only copy).
function CombatService.GetBuild(player: Player): { [string]: number }
	local pc = combat[player]
	local copy: { [string]: number } = {}
	if pc then
		for id, count in pc.Stacks do
			copy[id] = count
		end
	end
	return copy
end

CombatService.DamagePlayer = damagePlayer

function CombatService.Init()
	Remotes.Init()
	fxRemote = Remotes.GetEvent("CombatFx")
	numberRemote = Remotes.GetEvent("DamageNumber")
	offerRemote = Remotes.GetEvent("UpgradeOffer")
	notifyRemote = Remotes.GetEvent("Notify")

	RunManagerService.RunHpMultProvider = function(player: Player): number
		local pc = combat[player]
		local run = RunManagerService.GetRunOf(player)
		if pc and run and pc.RunId == run.Id then
			return 1 + (pc.Mods.MaxHPMult or 0)
		end
		return 1
	end

	EnemyAIService.Init({
		DamagePlayer = damagePlayer,
		SpawnProjectile = spawnEnemyProjectile,
		Fx = function(runId: number, payload: { [string]: any })
			fx(runId, payload, nil)
		end,
	})

	Remotes.GetEvent("CombatAttack").OnServerEvent:Connect(onAttack)
	Remotes.GetEvent("CombatDash").OnServerEvent:Connect(onDash)
	Remotes.GetEvent("UpgradeChosen").OnServerEvent:Connect(onUpgradeChosen)
	RunManagerService.RoomCleared:Connect(onRoomCleared)

	Players.PlayerRemoving:Connect(function(player: Player)
		combat[player] = nil
		lastRemoteAt[player] = nil
	end)

	local accumulator, statusClock, numberClock = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += math.min(dt, MAX_FRAME_SECONDS)
		if accumulator < STEP_SECONDS then
			return
		end
		local step = accumulator
		accumulator = 0
		local now = os.clock()

		local ok, err = pcall(function()
			for _, projectile in projectiles do
				stepProjectile(projectile, step, now)
			end
			tickPlayers(step, now)
			statusClock += step
			if statusClock >= 0.1 then
				statusClock = 0
				tickStatuses(now)
				tickZones(now)
			end
			numberClock += step
			if numberClock >= NUMBER_FLUSH_SECONDS then
				numberClock = 0
				flushNumbers()
			end
		end)
		if not ok then
			warn("[CombatService] tick failed: " .. tostring(err))
		end
	end)
end

return CombatService
