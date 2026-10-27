--!strict
-- StarterPlayerScripts/Client/Controllers/RigAnimator.luau
-- Code-driven poses for imported humanoid-rigged monsters (the Quaternius "Big" monsters: Spore Golem, Mushroom Titan).
-- The imports have bones but no animation tracks, so they stand in a T-pose. This module bends the skeleton
-- (Bone.Transform) instead, and every pose doubles as a readable tell for the boss fight:
--   * idle / walk: arms hang and swing against the legs
--   * Windup: a different signature pose per move (arms raised for the slam, arms back for the charge, arms spread
--     for the poison wave, throwing arm cocked for the boulder) that builds up over the windup time
--   * release: a fast snap (the slam, the throw) the instant the telegraph lands
--   * Recovery: a slumped, tired pose, so players see the boss is exposed and can punish
-- ProceduralAnimController owns the visual copy and calls Update each frame; rigs without these bones return nil.
--
-- Rig space: the imports face -Z with +Y up, so their right hand is on +X and the left ("L") bones are on -X.

local RigAnimator = {}
RigAnimator.__index = RigAnimator

local JOINT_BONES: { [string]: string } = {
	Body = "Body",
	Hips = "Hips",
	Torso = "Torso",
	Head = "Head",
	ArmL = "UpperArm.L",
	ArmR = "UpperArm.R",
	ForeL = "LowerArm.L",
	ForeR = "LowerArm.R",
	LegL = "UpperLeg.L",
	LegR = "UpperLeg.R",
	ShinL = "LowerLeg.L",
	ShinR = "LowerLeg.R",
}

local FRONT = Vector3.new(0, 0, -1)

type Joint = { Bone: Bone, Rest: CFrame, Current: CFrame }

export type Context = {
	State: string, -- AIState attribute: Idle, Walk, Windup, Attack, Recovery, Stunned
	Move: string, -- boss move kind while winding up / recovering, "" otherwise
	StateTime: number, -- seconds spent in State
	WindupDuration: number,
	Speed: number, -- horizontal speed in studs/second
	Time: number,
	Enraged: boolean,
}

export type Rig = typeof(setmetatable({} :: { Joints: { [string]: Joint }, Walk: number }, RigAnimator))

type Pose = { [string]: CFrame }

local function ease(p: number): number
	return 1 - (1 - p) * (1 - p)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Tip an upright bone (spine, head, forearm) toward the front.
local function lean(degrees: number): CFrame
	return rot(-degrees, 0, 0)
end

-- Swing a hanging bone (leg, shin) toward the front.
local function swing(degrees: number): CFrame
	return rot(degrees, 0, 0)
end

-- Arm: `lift` degrees above horizontal (0 = T-pose, -90 = hanging, +90 = straight up); `fwd` then swings it toward
-- the front (positive) or the back (negative) around the axis that is perpendicular to the arm, so the swing works
-- whether the arm hangs or is held out sideways. `side` is +1 for the left arm.
local function arm(side: number, lift: number, fwd: number): CFrame
	local l = math.rad(lift)
	local roll = CFrame.Angles(0, 0, -side * l)
	if fwd == 0 then
		return roll
	end
	local direction = Vector3.new(-side * math.cos(l), math.sin(l), 0)
	local axis = direction:Cross(FRONT).Unit
	return CFrame.fromAxisAngle(axis, math.rad(fwd)) * roll
end

-- Builds the rig for a visual copy of the enemy, or nil when it is not a rig this module knows.
function RigAnimator.new(visual: Model): Rig?
	local bones: { [string]: Bone } = {}
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
		end
	end
	if not (bones["UpperArm.L"] and bones["UpperArm.R"] and bones["Body"]) then
		return nil
	end

	-- A joint's rest orientation relative to the model pivot lets a rotation written in the model's own axes become
	-- the local Bone.Transform that produces it.
	local pivot = visual:GetPivot()
	local joints: { [string]: Joint } = {}
	for joint, boneName in JOINT_BONES do
		local bone = bones[boneName]
		if bone then
			joints[joint] = {
				Bone = bone,
				Rest = pivot:ToObjectSpace(bone.WorldCFrame).Rotation,
				Current = CFrame.identity,
			}
		end
	end
	return setmetatable({ Joints = joints, Walk = 0 }, RigAnimator)
end

-- Pose targets ----------------------------------------------------------------------------------------------------

local function idlePose(ctx: Context): Pose
	local rate = if ctx.Enraged then 3.4 else 2
	local sway = math.sin(ctx.Time * rate)
	local lift = if ctx.Enraged then -58 else -74
	local amount = if ctx.Enraged then 6 else 3
	return {
		Body = lean(2 + 1.5 * sway),
		Torso = lean(2 * sway),
		Head = lean(-3 * sway),
		ArmL = arm(1, lift + amount * sway, 4 * sway),
		ArmR = arm(-1, lift - amount * sway, -4 * sway),
		ForeL = lean(10),
		ForeR = lean(10),
	}
end

local function walkPose(rig: Rig, ctx: Context, dt: number): Pose
	rig.Walk += dt * math.clamp(ctx.Speed, 3, 24) * 0.7
	local s = math.sin(rig.Walk)
	local c = math.cos(rig.Walk)
	local stride = math.clamp(ctx.Speed / 8, 0.7, 1.6)
	return {
		Body = lean(6 * stride) * rot(0, 4 * s, 0),
		Torso = lean(3) * rot(0, -7 * s, 0),
		Head = lean(-4),
		LegL = swing(30 * stride * s),
		LegR = swing(-30 * stride * s),
		ShinL = lean(math.max(0, -c) * 34 * stride),
		ShinR = lean(math.max(0, c) * 34 * stride),
		ArmL = arm(1, -70, -22 * stride * s),
		ArmR = arm(-1, -70, 22 * stride * s),
		ForeL = lean(18),
		ForeR = lean(18),
	}
end

local function windupPose(ctx: Context): Pose
	local p = math.clamp(ctx.StateTime / math.max(ctx.WindupDuration, 0.1), 0, 1)
	local e = ease(p)
	-- The last quarter of the windup trembles so the strike reads as imminent.
	local tremble = if p > 0.7 then math.sin(ctx.Time * 60) * (p - 0.7) / 0.3 else 0
	if ctx.Move == "GroundPound" then
		return {
			Body = lean(lerp(2, -11, e)),
			Torso = lean(lerp(0, -7, e)),
			Head = lean(lerp(0, -8, e)),
			LegL = swing(lerp(0, 10, e)),
			LegR = swing(lerp(0, 10, e)),
			ShinL = lean(lerp(0, -24, e)),
			ShinR = lean(lerp(0, -24, e)),
			ArmL = arm(1, lerp(-74, 66, e) + tremble * 4, 0),
			ArmR = arm(-1, lerp(-74, 66, e) - tremble * 4, 0),
			ForeL = lean(lerp(10, 25, e)),
			ForeR = lean(lerp(10, 25, e)),
		}
	elseif ctx.Move == "BoulderCharge" then
		-- Crouch with both arms dragged back, like a sprinter in the blocks.
		return {
			Body = lean(lerp(2, 10, e)) * rot(0, 0, tremble * 3),
			Torso = lean(lerp(0, 8, e)),
			Head = lean(lerp(0, -8, e)),
			LegL = swing(lerp(0, -22, e)),
			LegR = swing(lerp(0, 22, e)),
			ShinL = lean(lerp(0, 28, e)),
			ShinR = lean(lerp(0, -18, e)),
			ArmL = arm(1, lerp(-74, -40, e), lerp(0, -75, e)),
			ArmR = arm(-1, lerp(-74, -40, e), lerp(0, -75, e)),
			ForeL = lean(lerp(10, 20, e)),
			ForeR = lean(lerp(10, 20, e)),
		}
	elseif ctx.Move == "PoisonWave" then
		return {
			Body = lean(lerp(2, -6, e)),
			Torso = lean(lerp(0, -8, e)),
			Head = lean(lerp(0, -12, e)),
			ArmL = arm(1, lerp(-74, 12, e) + tremble * 5, 0),
			ArmR = arm(-1, lerp(-74, 12, e) - tremble * 5, 0),
			ForeL = lean(lerp(10, -10, e)),
			ForeR = lean(lerp(10, -10, e)),
		}
	elseif ctx.Move == "SporeBoulder" then
		return {
			Body = lean(lerp(2, -10, e)),
			Torso = lean(lerp(0, -6, e)) * rot(0, lerp(0, -24, e), 0),
			Head = lean(lerp(0, 8, e)),
			ArmL = arm(1, lerp(-74, -10, e), lerp(0, 40, e)),
			ArmR = arm(-1, lerp(-74, 120, e) - tremble * 4, lerp(0, -38, e)),
			ForeL = lean(10),
			ForeR = lean(lerp(10, 70, e)),
		}
	end
	return idlePose(ctx)
end

local function chargingPose(ctx: Context): Pose
	local run = math.sin(ctx.Time * 22)
	return {
		Body = lean(20),
		Torso = lean(8),
		Head = lean(-14),
		LegL = swing(34 * run),
		LegR = swing(-34 * run),
		ShinL = lean(math.max(0, -run) * 46),
		ShinR = lean(math.max(0, run) * 46),
		ArmL = arm(1, -35, -60),
		ArmR = arm(-1, -35, -60),
		ForeL = lean(30),
		ForeR = lean(30),
	}
end

-- The first instant of Recovery is the strike itself; after that the boss slumps and is open to attack.
local RELEASE_SECONDS = 0.28

local function recoveryPose(ctx: Context): (Pose, number)
	local R = ctx.StateTime
	if R < RELEASE_SECONDS then
		local k = ease(R / RELEASE_SECONDS)
		if ctx.Move == "GroundPound" then
			return {
				Body = lean(lerp(-11, 20, k)),
				Torso = lean(10),
				Head = lean(16),
				LegL = swing(14),
				LegR = swing(14),
				ShinL = lean(-30),
				ShinR = lean(-30),
				ArmL = arm(1, lerp(66, -82, k), 18),
				ArmR = arm(-1, lerp(66, -82, k), 18),
				ForeL = lean(20),
				ForeR = lean(20),
			}, 46
		elseif ctx.Move == "PoisonWave" then
			return {
				Body = lean(lerp(-6, 16, k)),
				Torso = lean(8),
				Head = lean(14),
				ArmL = arm(1, lerp(12, -78, k), 24),
				ArmR = arm(-1, lerp(12, -78, k), 24),
				ForeL = lean(20),
				ForeR = lean(20),
			}, 40
		elseif ctx.Move == "SporeBoulder" then
			-- The throw: the cocked arm whips forward and down.
			return {
				Body = lean(lerp(-10, 14, k)),
				Torso = lean(6) * rot(0, lerp(-24, 16, k), 0),
				Head = lean(8),
				ArmL = arm(1, -60, 10),
				ArmR = arm(-1, lerp(120, -35, k), lerp(-38, 80, k)),
				ForeL = lean(14),
				ForeR = lean(lerp(70, 10, k)),
			}, 42
		end
		return {
			Body = lean(lerp(20, 14, k)),
			Torso = lean(8),
			Head = lean(14),
			ArmL = arm(1, -70, 10),
			ArmR = arm(-1, -70, 10),
		}, 20
	end
	-- Exposed: slumped, head hanging, arms limp, breathing hard.
	local heave = math.sin(ctx.Time * 6)
	return {
		Body = lean(9 + 2 * heave),
		Torso = lean(6 + 2 * heave),
		Head = lean(22),
		LegL = swing(5),
		LegR = swing(5),
		ShinL = lean(-8),
		ShinR = lean(-8),
		ArmL = arm(1, -84 + 3 * heave, 12),
		ArmR = arm(-1, -84 - 3 * heave, 12),
		ForeL = lean(18),
		ForeR = lean(18),
	}, 7
end

local function stunnedPose(ctx: Context): Pose
	local wobble = math.sin(ctx.Time * 14)
	return {
		Body = lean(12) * rot(0, 0, 8 * wobble),
		Torso = lean(10) * rot(0, 0, -10 * wobble),
		Head = lean(22) * rot(0, 0, 18 * wobble),
		ArmL = arm(1, -45 + 25 * wobble, 10 * wobble),
		ArmR = arm(-1, -45 - 25 * wobble, -10 * wobble),
		ForeL = lean(30),
		ForeR = lean(30),
	}
end

-- Per-frame ---------------------------------------------------------------------------------------------------------

function RigAnimator.Update(self: Rig, ctx: Context, dt: number)
	local pose: Pose
	local rate = 14
	if ctx.State == "Windup" then
		pose, rate = windupPose(ctx), 26
	elseif ctx.State == "Attack" then
		pose, rate = chargingPose(ctx), 12
	elseif ctx.State == "Recovery" then
		pose, rate = recoveryPose(ctx)
	elseif ctx.State == "Stunned" then
		pose, rate = stunnedPose(ctx), 18
	elseif ctx.Speed > 1 then
		pose = walkPose(self, ctx, dt)
	else
		pose = idlePose(ctx)
	end

	local blend = 1 - math.exp(-rate * dt)
	for name, joint in self.Joints do
		local current = joint.Current:Lerp(pose[name] or CFrame.identity, blend)
		joint.Current = current
		joint.Bone.Transform = joint.Rest:Inverse() * current * joint.Rest
	end
end

return RigAnimator
