--!strict
-- ServerScriptService/Server/Services/EnemyAIService.luau
-- Server-side brains and kinematics for every RiftEnemy (Sections 7, 9 & 17).
--
-- Enemies are anchored models that this service moves itself: the server integrates gravity and raycasts the room's
-- Terrain for floors, so nothing depends on Roblox character physics or network ownership, and every enemy stays
-- exactly on the Z=0 plane. Clients render a smoothed visual copy (ProceduralAnimController) driven by the
-- attributes written here: AIState, Facing, Airborne.
--
--   * Hoppers (Spore Blob, Mushroom Hopper) arc-hop toward the nearest living player and hurt on contact.
--   * Bosses (Spore Golem, Mushroom Titan) cycle through telegraphed moves defined in EnemyConfig, and enrage
--     at half HP. Every damaging move shows a Telegraph first so a well-timed jump or dash avoids it.
--
-- CombatService owns damage: it writes EnemyState.HP and supplies the Hooks (damage a player, spawn a projectile,
-- broadcast cosmetics). Nothing here trusts or reads the client.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("EnemyConfig"))
local Physics25D = require(Shared:WaitForChild("Physics25D"))
local RoomAsciiTemplates = require(Shared:WaitForChild("RoomAsciiTemplates"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))

type EnemyInfo = EnemyConfig.EnemyInfo
type MoveSpec = EnemyConfig.MoveSpec

export type BossState = {
	Phase: number,
	Stage: "Think" | "Windup" | "Active" | "Recovery",
	StageEndsAt: number,
	NextMoveAt: number,
	Move: MoveSpec?,
	LastKind: string?,
	AimDir: number,
	ChargeEndsAt: number,
	MoveHit: { [Player]: boolean },
}

export type EnemyState = {
	Model: Model,
	Root: BasePart,
	RunId: number,
	Key: string,
	Kind: string, -- "Normal" | "Elite" | "Boss"
	Info: EnemyInfo,
	Half: Vector2,
	Feet: Vector3,
	VelX: number,
	VelY: number,
	Airborne: boolean,
	JustLanded: boolean,
	Facing: number,
	HP: number,
	MaxHP: number,
	Attack: number,
	Dead: boolean,
	StunUntil: number,
	ContactReadyAt: number,
	NextHopAt: number,
	MinX: number,
	MaxX: number,
	KillY: number,
	SpawnFeet: Vector3,
	RayParams: RaycastParams,
	Attrs: { [string]: any },
	LastPivot: Vector3,
	Boss: BossState?,
	-- Status effects, managed by CombatService
	Burn: { Until: number, Dps: number, NextTick: number, Source: Player }?,
	Shock: { Until: number, Source: Player }?,
	NovaReadyAt: number,
}

export type Target = { Player: Player, Pos: Vector3, Humanoid: Humanoid }

export type EnemyProjectileSpec = {
	Style: string,
	RunId: number,
	Pos: Vector3,
	Vel: Vector3,
	HalfX: number,
	HalfY: number,
	Life: number,
	Damage: number,
	Reflectable: boolean,
	Owner: EnemyState?,
}

export type Hooks = {
	DamagePlayer: (Player, number, string) -> boolean,
	SpawnProjectile: (EnemyProjectileSpec) -> (),
	Fx: (number, { [string]: any }) -> (),
}

local EnemyAIService = {}

-- Player body relative to HumanoidRootPart (R15): feet 3 studs below, head 2.6 above.
EnemyAIService.PLAYER_FEET_OFFSET = 3
EnemyAIService.PLAYER_HEAD_OFFSET = 2.6
EnemyAIService.PLAYER_HALF_WIDTH = 1.1

-- Tuning ------------------------------------------------------------------------------------------------------

local STEP_SECONDS = 1 / 20
local MAX_FRAME_SECONDS = 0.25
local RAY_LIFT = 0.8
local SNAP_DOWN = 0.6
local HOP_MAX_POWER = 62 -- enough to clear two platform rows
local HOP_REACH_MARGIN = 2.5
local FIRST_MOVE_DELAY = 1.6
local ENRAGE_WINDUP_MULT = 0.8
local ENRAGE_THINK_MULT = 0.6
local ENRAGE_SPEED_MULT = 1.25
local POUND_HEIGHT = 3.5 -- players this far above the boss's floor dodge the slam
local WAVE_HEIGHT = 3.0 -- ...and the floor-wide poison wave
local SHOCKWAVE_SPEED = 34
local CHARGE_RECOVERY_SHAKE = 0.8

local rng = Random.new()
local hooks: Hooks
local states: { [Model]: EnemyState } = {}

EnemyAIService.States = states

local function sign(value: number): number
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end
	return 0
end

local function setAttr(state: EnemyState, name: string, value: any)
	if state.Attrs[name] ~= value then
		state.Attrs[name] = value
		state.Model:SetAttribute(name, value)
	end
end

local function setAIState(state: EnemyState, value: string)
	setAttr(state, "AIState", value)
end

-- Geometry ----------------------------------------------------------------------------------------------------

-- Centre and half-extents of the enemy's body on the combat plane.
function EnemyAIService.Box(state: EnemyState): (number, number, number, number)
	return state.Feet.X, state.Feet.Y + state.Half.Y, state.Half.X, state.Half.Y
end

function EnemyAIService.Overlap(ax: number, ay: number, ahx: number, ahy: number, bx: number, by: number, bhx: number, bhy: number): boolean
	return math.abs(ax - bx) <= ahx + bhx and math.abs(ay - by) <= ahy + bhy
end

local function playerOverlapsBox(target: Target, cx: number, cy: number, hx: number, hy: number): boolean
	local top = target.Pos.Y + EnemyAIService.PLAYER_HEAD_OFFSET
	local bottom = target.Pos.Y - EnemyAIService.PLAYER_FEET_OFFSET
	return math.abs(target.Pos.X - cx) <= hx + EnemyAIService.PLAYER_HALF_WIDTH and bottom <= cy + hy and top >= cy - hy
end

-- Targets ----------------------------------------------------------------------------------------------------

local function collectTargets(runId: number): { Target }
	local list: { Target } = {}
	for _, player in RunManagerService.GetPlayersInRun(runId, true) do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(list, { Player = player, Pos = root.Position, Humanoid = humanoid })
		end
	end
	return list
end

local function nearestTarget(state: EnemyState, targets: { Target }): Target?
	local best: Target? = nil
	local bestDistance = math.huge
	for _, target in targets do
		local distance = math.abs(target.Pos.X - state.Feet.X) + 2 * math.abs(target.Pos.Y - state.Feet.Y)
		if distance < bestDistance then
			best, bestDistance = target, distance
		end
	end
	return best
end

-- Kinematics --------------------------------------------------------------------------------------------------

local function raycastDown(state: EnemyState, x: number, y: number, length: number): RaycastResult?
	return Workspace:Raycast(Vector3.new(x, y, Physics25D.PLANE_Z), Vector3.new(0, -length, 0), state.RayParams)
end

-- Integrates one step of motion: ballistic while airborne (one-way platforms only catch a falling enemy),
-- floor-glued while walking, and walking off a ledge turns into a fall.
local function applyMotion(state: EnemyState, dt: number)
	local x = state.Feet.X
	local y = state.Feet.Y
	local newX = math.clamp(x + state.VelX * dt, state.MinX, state.MaxX)
	local blockedByWall = newX ~= x + state.VelX * dt

	if state.Airborne then
		state.VelY -= Workspace.Gravity * dt
		local dy = state.VelY * dt
		local newY = y + dy
		if state.VelY <= 0 then
			local hit = raycastDown(state, newX, y + RAY_LIFT, RAY_LIFT - dy + 0.05)
			if hit then
				newY = hit.Position.Y
				state.Airborne = false
				state.VelY = 0
				state.JustLanded = true
			end
		end
		y = newY
	elseif state.VelX ~= 0 then
		local hit = raycastDown(state, newX, y + RAY_LIFT, RAY_LIFT + SNAP_DOWN)
		if hit then
			y = hit.Position.Y
		else
			state.Airborne = true
			state.VelY = 0
		end
	end

	if y < state.KillY then
		-- Fell out of the room (e.g. over an edge into a pit): put it back where it spawned.
		state.Feet = state.SpawnFeet
		state.VelX, state.VelY, state.Airborne = 0, 0, false
		return
	end
	if blockedByWall then
		state.VelX = 0
	end
	state.Feet = Vector3.new(newX, y, Physics25D.PLANE_Z)
end

local function writePivot(state: EnemyState)
	local center = state.Feet + Vector3.new(0, state.Half.Y, 0)
	if (center - state.LastPivot).Magnitude > 0.01 then
		state.LastPivot = center
		state.Model:PivotTo(CFrame.new(center))
	end
	setAttr(state, "Airborne", state.Airborne)
	setAttr(state, "Facing", state.Facing)
end

-- Contact damage ----------------------------------------------------------------------------------------------

local function checkContact(state: EnemyState, now: number, targets: { Target })
	if now < state.ContactReadyAt then
		return
	end
	local cx, cy, hx, hy = EnemyAIService.Box(state)
	for _, target in targets do
		if playerOverlapsBox(target, cx, cy, hx, hy) then
			if hooks.DamagePlayer(target.Player, state.Attack * state.Info.ContactMult, "Contact") then
				state.ContactReadyAt = now + state.Info.ContactCooldown
				return
			end
		end
	end
end

-- Hoppers ---------------------------------------------------------------------------------------------------

local function stepHopper(state: EnemyState, now: number, target: Target?)
	if state.Airborne then
		return
	end
	local info = state.Info
	if state.JustLanded then
		state.JustLanded = false
		state.VelX = 0
		state.NextHopAt = now + info.HopInterval * rng:NextNumber(0.8, 1.25)
		setAIState(state, "Idle")
	end
	if not target or now < state.NextHopAt then
		return
	end

	local dx = target.Pos.X - state.Feet.X
	local rise = (target.Pos.Y - EnemyAIService.PLAYER_FEET_OFFSET) - state.Feet.Y
	local power = info.HopPower
	if rise > 3 then
		-- The player stands on a higher tier: hop hard enough to land on it.
		power = math.clamp(math.sqrt(2 * Workspace.Gravity * (rise + HOP_REACH_MARGIN)), info.HopPower, HOP_MAX_POWER)
	end
	local airTime = 2 * power / Workspace.Gravity
	state.VelX = math.clamp(dx / airTime, -info.MoveSpeed, info.MoveSpeed)
	state.VelY = power
	state.Airborne = true
	if state.VelX ~= 0 then
		state.Facing = sign(state.VelX)
	end
	setAIState(state, "Hop")
end

-- Bosses ----------------------------------------------------------------------------------------------------

local function telegraph(state: EnemyState, center: Vector3, size: Vector3, duration: number, style: string)
	hooks.Fx(state.RunId, { Kind = "Telegraph", Pos = center, Size = size, Duration = duration, Style = style })
end

local function enraged(state: EnemyState): boolean
	return state.Boss ~= nil and state.Boss.Phase >= 2
end

local function bossSpeed(state: EnemyState): number
	return state.Info.MoveSpeed * (if enraged(state) then ENRAGE_SPEED_MULT else 1)
end

local function pickMove(state: EnemyState, target: Target): MoveSpec?
	local boss = state.Boss :: BossState
	local moves = state.Info.Moves
	if not moves then
		return nil
	end
	local distance = math.abs(target.Pos.X - state.Feet.X)
	local candidates: { MoveSpec } = {}
	for _, move in moves do
		local usable = true
		if move.Kind == "GroundPound" then
			usable = distance <= (move.Range or 16) + 6
		elseif move.Kind == "BoulderCharge" then
			usable = distance >= 8
		elseif move.Kind == "SporeBoulder" then
			usable = distance >= 10
		end
		if usable and (move.Kind ~= boss.LastKind or #moves == 1) then
			table.insert(candidates, move)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

local function beginMove(state: EnemyState, move: MoveSpec, target: Target, now: number)
	local boss = state.Boss :: BossState
	boss.Stage = "Windup"
	boss.Move = move
	boss.LastKind = move.Kind
	boss.MoveHit = {}
	boss.AimDir = sign(target.Pos.X - state.Feet.X)
	if boss.AimDir == 0 then
		boss.AimDir = state.Facing
	end
	state.Facing = boss.AimDir
	state.VelX = 0

	local windup = move.Windup * (if enraged(state) then ENRAGE_WINDUP_MULT else 1)
	boss.StageEndsAt = now + windup
	setAIState(state, "Windup")

	local x, fy = state.Feet.X, state.Feet.Y
	if move.Kind == "GroundPound" then
		local range = move.Range or 16
		telegraph(state, Vector3.new(x, fy + 1.5, 0), Vector3.new(range * 2, 3, 10), windup, "Danger")
	elseif move.Kind == "BoulderCharge" then
		local wall = if boss.AimDir > 0 then state.MaxX else state.MinX
		local length = math.abs(wall - x)
		telegraph(state, Vector3.new(x + boss.AimDir * length / 2, fy + state.Half.Y, 0),
			Vector3.new(length, state.Half.Y * 2, 6), windup, "Danger")
	elseif move.Kind == "PoisonWave" then
		telegraph(state, Vector3.new((state.MinX + state.MaxX) / 2, fy + 1.2, 0),
			Vector3.new(state.MaxX - state.MinX + state.Half.X * 2, 2.4, 8), windup, "Poison")
	elseif move.Kind == "SporeBoulder" then
		telegraph(state, Vector3.new(x + boss.AimDir * 28, fy + 2.4, 0), Vector3.new(56, 1.2, 4), windup, "Warn")
	end
end

local function enterRecovery(state: EnemyState, move: MoveSpec, now: number)
	local boss = state.Boss :: BossState
	boss.Stage = "Recovery"
	boss.StageEndsAt = now + move.Recovery
	state.VelX = 0
	setAIState(state, "Recovery")
end

local function fireBoulder(state: EnemyState, move: MoveSpec, dir: number, lowY: number)
	hooks.SpawnProjectile({
		Style = "Boulder",
		RunId = state.RunId,
		Pos = Vector3.new(state.Feet.X + dir * (state.Half.X + 2.5), lowY, 0),
		Vel = Vector3.new(dir * (move.Speed or 38), 0, 0),
		HalfX = 2.4,
		HalfY = 2.4,
		Life = 4.5,
		Damage = state.Attack * move.DamageMult,
		Reflectable = true,
		Owner = state,
	})
end

-- The telegraph is over: apply the move's effect.
local function executeMove(state: EnemyState, move: MoveSpec, now: number, targets: { Target })
	local boss = state.Boss :: BossState
	local atk = state.Attack
	local x, fy = state.Feet.X, state.Feet.Y

	if move.Kind == "GroundPound" then
		local range = move.Range or 16
		for _, target in targets do
			local grounded = (target.Pos.Y - EnemyAIService.PLAYER_FEET_OFFSET) - fy < POUND_HEIGHT
			if grounded and math.abs(target.Pos.X - x) <= range + EnemyAIService.PLAYER_HALF_WIDTH then
				hooks.DamagePlayer(target.Player, atk * move.DamageMult, "Slam")
			end
		end
		for _, dir in { -1, 1 } do
			hooks.SpawnProjectile({
				Style = "Shockwave",
				RunId = state.RunId,
				Pos = Vector3.new(x + dir * range, fy + 1.4, 0),
				Vel = Vector3.new(dir * SHOCKWAVE_SPEED, 0, 0),
				HalfX = 1.2,
				HalfY = 1.4,
				Life = 1.6,
				Damage = atk * 0.6,
				Reflectable = false,
				Owner = state,
			})
		end
		hooks.Fx(state.RunId, { Kind = "Burst", Pos = Vector3.new(x, fy + 0.5, 0), Radius = range, Style = "Slam", Owner = 0 })
		hooks.Fx(state.RunId, { Kind = "Shake", Intensity = 1.1, Duration = 0.45 })
		enterRecovery(state, move, now)
	elseif move.Kind == "BoulderCharge" then
		boss.Stage = "Active"
		boss.MoveHit = {}
		local wall = if boss.AimDir > 0 then state.MaxX else state.MinX
		local speed = move.Speed or 58
		boss.ChargeEndsAt = now + math.abs(wall - x) / speed + 0.15
		state.VelX = boss.AimDir * speed
		setAIState(state, "Attack")
	elseif move.Kind == "PoisonWave" then
		for _, target in targets do
			if (target.Pos.Y - EnemyAIService.PLAYER_FEET_OFFSET) - fy < WAVE_HEIGHT then
				hooks.DamagePlayer(target.Player, atk * move.DamageMult, "Poison")
			end
		end
		hooks.Fx(state.RunId, {
			Kind = "Sweep", Pos = Vector3.new((state.MinX + state.MaxX) / 2, fy + 1.2, 0),
			HalfX = (state.MaxX - state.MinX) / 2 + state.Half.X, Style = "Poison", Duration = 0.45,
		})
		hooks.Fx(state.RunId, { Kind = "Shake", Intensity = 0.7, Duration = 0.4 })
		enterRecovery(state, move, now)
	elseif move.Kind == "SporeBoulder" then
		local lowY = fy + 2.4
		fireBoulder(state, move, boss.AimDir, lowY)
		if enraged(state) then
			task.delay(0.55, function()
				if not state.Dead and state.Model.Parent and os.clock() >= state.StunUntil then
					fireBoulder(state, move, boss.AimDir, lowY)
				end
			end)
		end
		enterRecovery(state, move, now)
	end
end

local function stepChargeHit(state: EnemyState, targets: { Target })
	local boss = state.Boss :: BossState
	local move = boss.Move
	if not move then
		return
	end
	local cx, cy, hx, hy = EnemyAIService.Box(state)
	for _, target in targets do
		if not boss.MoveHit[target.Player] and playerOverlapsBox(target, cx, cy, hx, hy) then
			boss.MoveHit[target.Player] = true
			hooks.DamagePlayer(target.Player, state.Attack * move.DamageMult, "Charge")
		end
	end
end

local function checkEnrage(state: EnemyState)
	local boss = state.Boss :: BossState
	local threshold = state.Info.EnrageAt
	if boss.Phase == 1 and threshold and state.HP > 0 and state.HP / state.MaxHP <= threshold then
		boss.Phase = 2
		setAttr(state, "Phase", 2)
		hooks.Fx(state.RunId, { Kind = "Roar", Pos = state.Feet + Vector3.new(0, state.Half.Y, 0) })
		hooks.Fx(state.RunId, { Kind = "Shake", Intensity = 1.4, Duration = 0.7 })
	end
end

local function stepBoss(state: EnemyState, now: number, targets: { Target }, target: Target?)
	local boss = state.Boss :: BossState
	checkEnrage(state)

	if boss.Stage == "Think" then
		if target then
			local dx = target.Pos.X - state.Feet.X
			local direction = sign(dx)
			if direction ~= 0 then
				state.Facing = direction
			end
			if math.abs(dx) > state.Half.X * 0.6 + 3 then
				state.VelX = direction * bossSpeed(state)
				setAIState(state, "Walk")
			else
				state.VelX = 0
				setAIState(state, "Idle")
			end
			if now >= boss.NextMoveAt then
				local move = pickMove(state, target)
				if move then
					beginMove(state, move, target, now)
				else
					boss.NextMoveAt = now + 0.4
				end
			end
		else
			state.VelX = 0
			setAIState(state, "Idle")
		end
	elseif boss.Stage == "Windup" then
		state.VelX = 0
		if now >= boss.StageEndsAt and boss.Move then
			executeMove(state, boss.Move, now, targets)
		end
	elseif boss.Stage == "Active" then
		stepChargeHit(state, targets)
		local atWall = state.VelX == 0
		if atWall or now >= boss.ChargeEndsAt then
			local move = boss.Move
			if move then
				hooks.Fx(state.RunId, { Kind = "Shake", Intensity = CHARGE_RECOVERY_SHAKE, Duration = 0.3 })
				enterRecovery(state, move, now)
			else
				boss.Stage = "Think"
			end
		end
	elseif boss.Stage == "Recovery" then
		state.VelX = 0
		if now >= boss.StageEndsAt then
			boss.Stage = "Think"
			local delay = (state.Info.ThinkDelay or 1.2) * (if enraged(state) then ENRAGE_THINK_MULT else 1)
			boss.NextMoveAt = now + delay
			boss.Move = nil
		end
	end
end

-- Registry --------------------------------------------------------------------------------------------------

local function numberAttribute(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function register(instance: Instance)
	if not instance:IsA("Model") or states[instance] then
		return
	end
	local model = instance
	local root = model.PrimaryPart
	local runId = model:GetAttribute("RunId")
	local run = if type(runId) == "number" then RunManagerService.GetRunById(runId) else nil
	if not root or not run then
		return
	end

	local key = tostring(model:GetAttribute("EnemyKey"))
	local info = EnemyConfig.Get(key)
	local pivot = model:GetPivot().Position
	local _, size = model:GetBoundingBox()
	local half = Vector2.new(size.X / 2, size.Y / 2)

	local tile = RoomAsciiTemplates.TILE_SIZE
	local origin = run.Origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.RespectCanCollide = true
	local terrain = if model.Parent then model.Parent:FindFirstChild("Terrain") else nil
	params.FilterDescendantsInstances = if terrain then { terrain } else {}

	local feet = Vector3.new(pivot.X, pivot.Y - half.Y, Physics25D.PLANE_Z)
	local now = os.clock()
	local state: EnemyState = {
		Model = model,
		Root = root,
		RunId = runId :: number,
		Key = key,
		Kind = tostring(model:GetAttribute("EnemyKind")),
		Info = info,
		Half = half,
		Feet = feet,
		VelX = 0,
		VelY = 0,
		Airborne = false,
		JustLanded = false,
		Facing = 1,
		HP = numberAttribute(model, "HP", 1),
		MaxHP = numberAttribute(model, "MaxHP", 1),
		Attack = numberAttribute(model, "Attack", 1),
		Dead = false,
		StunUntil = 0,
		ContactReadyAt = now + 0.5,
		NextHopAt = now + rng:NextNumber(0.4, 1.4),
		MinX = origin.X + tile.X + half.X,
		MaxX = origin.X + RoomAsciiTemplates.COLUMNS * tile.X - tile.X - half.X,
		KillY = origin.Y - 20,
		SpawnFeet = feet,
		RayParams = params,
		Attrs = {},
		LastPivot = pivot,
		Boss = nil,
		Burn = nil,
		Shock = nil,
		NovaReadyAt = 0,
	}
	if info.Archetype == "Boss" and info.Moves then
		state.Boss = {
			Phase = 1,
			Stage = "Think",
			StageEndsAt = 0,
			NextMoveAt = now + FIRST_MOVE_DELAY,
			Move = nil,
			LastKind = nil,
			AimDir = 1,
			ChargeEndsAt = 0,
			MoveHit = {},
		}
		setAttr(state, "Phase", 1)
	end
	states[model] = state
	setAIState(state, "Idle")
	model.Destroying:Once(function()
		states[model] = nil
	end)
end

-- Public API ------------------------------------------------------------------------------------------------

function EnemyAIService.GetState(model: Model): EnemyState?
	return states[model]
end

function EnemyAIService.IsStunned(state: EnemyState): boolean
	return os.clock() < state.StunUntil
end

-- Interrupts whatever the enemy was doing (Mushroom Titan's reflected boulder, Hammer stagger).
function EnemyAIService.Stun(state: EnemyState, seconds: number)
	local now = os.clock()
	state.StunUntil = math.max(state.StunUntil, now + seconds)
	state.VelX = 0
	local boss = state.Boss
	if boss and boss.Stage ~= "Think" then
		boss.Stage = "Think"
		boss.Move = nil
		boss.NextMoveAt = state.StunUntil + 0.6
	end
	setAIState(state, "Stunned")
end

local function stepEnemy(state: EnemyState, now: number, dt: number, targets: { Target })
	if state.Dead or not state.Model.Parent then
		return
	end
	local target = nearestTarget(state, targets)
	if now < state.StunUntil then
		state.VelX = 0
	elseif state.Attrs.AIState == "Stunned" and not state.Boss then
		setAIState(state, "Idle")
	elseif state.Boss then
		stepBoss(state, now, targets, target)
	else
		stepHopper(state, now, target)
	end

	applyMotion(state, dt)
	writePivot(state)
	if now >= state.StunUntil then
		checkContact(state, now, targets)
	end
end

function EnemyAIService.Init(newHooks: Hooks)
	hooks = newHooks
	local tag = RunManagerService.ENEMY_TAG
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(register, instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(register)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += math.min(dt, MAX_FRAME_SECONDS)
		if accumulator < STEP_SECONDS then
			return
		end
		local step = accumulator
		accumulator = 0

		local now = os.clock()
		local targetCache: { [number]: { Target } } = {}
		for _, state in states do
			local targets = targetCache[state.RunId]
			if not targets then
				targets = collectTargets(state.RunId)
				targetCache[state.RunId] = targets
			end
			local ok, err = pcall(function(): any
				stepEnemy(state, now, step, targets)
				return nil
			end)
			if not ok then
				warn(("[EnemyAIService] %s failed: %s"):format(state.Key, tostring(err)))
			end
		end
	end)
end

return EnemyAIService
