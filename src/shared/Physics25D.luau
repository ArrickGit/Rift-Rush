--!strict
-- ReplicatedStorage/Shared/Physics25D.luau
-- 2.5D physics rules shared by server and client (Section 7): the Z=0 combat plane lock, the
-- ActorsNoCollide collision group, the one-way platform tag, and Skywalker's Grace mobility stats.
-- Server code calls SetupActor on every player character and monster; the client only reads constants.

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Physics25D = {}

Physics25D.PLANE_Z = 0
Physics25D.ACTOR_GROUP = "ActorsNoCollide"
Physics25D.ONE_WAY_TAG = "OneWayPlatform" -- RoomBuilderService tags '=' tiles with this
Physics25D.SKYWALKER_NODE_ID = "AS_T2_01"

local PLANE_ANCHOR_NAME = "RiftPlaneAnchor"
local PLANE_LOCK_NAME = "PlaneLock"

local BASE_WALK_SPEED = 20
local BASE_JUMP_HEIGHT = 8
local BASE_DASH_COOLDOWN = 1.0

export type Mobility = {
	WalkSpeed: number,
	JumpHeight: number,
	AirJumps: number, -- 1 = double jump, 2 = triple jump
	DashCharges: number,
	DashCooldown: number, -- seconds to regenerate one charge
}

-- Skywalker's Grace (AS_T2_01): Lv1 +10% move/jump, Lv2 +1 Dash charge, Lv3 Triple Jump & -20% Dash cooldown.
function Physics25D.GetMobility(skywalkerLevel: number): Mobility
	local level = math.clamp(skywalkerLevel, 0, 3)
	local boost = if level >= 1 then 1.10 else 1.0
	return {
		WalkSpeed = BASE_WALK_SPEED * boost,
		JumpHeight = BASE_JUMP_HEIGHT * boost,
		AirJumps = if level >= 3 then 2 else 1,
		DashCharges = if level >= 2 then 2 else 1,
		DashCooldown = BASE_DASH_COOLDOWN * (if level >= 3 then 0.8 else 1.0),
	}
end

-- Server only: actors pass through each other but still collide with the world.
function Physics25D.RegisterCollisionGroups()
	assert(RunService:IsServer(), "Physics25D.RegisterCollisionGroups must be called on the server")
	if not PhysicsService:IsCollisionGroupRegistered(Physics25D.ACTOR_GROUP) then
		PhysicsService:RegisterCollisionGroup(Physics25D.ACTOR_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(Physics25D.ACTOR_GROUP, Physics25D.ACTOR_GROUP, false)
end

-- One shared anchor in Terrain defines the combat plane. A PlaneConstraint uses Attachment0's primary
-- axis (its RightVector) as the plane normal, so that axis points along world Z.
local function getPlaneAnchor(): Attachment
	local terrain = Workspace.Terrain
	local existing = terrain:FindFirstChild(PLANE_ANCHOR_NAME)
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = PLANE_ANCHOR_NAME
	anchor.CFrame = CFrame.fromMatrix(Vector3.new(0, 0, Physics25D.PLANE_Z), Vector3.zAxis, Vector3.yAxis)
	anchor.Parent = terrain
	return anchor
end

local function assignActorGroup(instance: Instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = Physics25D.ACTOR_GROUP
	end
end

-- Puts every part (including accessories added later) in ActorsNoCollide until the model leaves the game.
function Physics25D.SetActorCollisionGroup(model: Model)
	for _, descendant in model:GetDescendants() do
		assignActorGroup(descendant)
	end
	local added = model.DescendantAdded:Connect(assignActorGroup)
	local ancestry: RBXScriptConnection? = nil
	ancestry = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			added:Disconnect()
			if ancestry then
				ancestry:Disconnect()
			end
		end
	end)
end

function Physics25D.LockToPlane(root: BasePart): PlaneConstraint
	local existing = root:FindFirstChild(PLANE_LOCK_NAME)
	if existing and existing:IsA("PlaneConstraint") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PlaneLockAttachment"
	attachment.Parent = root

	local constraint = Instance.new("PlaneConstraint")
	constraint.Name = PLANE_LOCK_NAME
	constraint.Attachment0 = getPlaneAnchor()
	constraint.Attachment1 = attachment
	constraint.Parent = root
	return constraint
end

-- Server only: snap onto the plane first so the constraint doesn't yank the actor, then lock + group it.
function Physics25D.SetupActor(model: Model, root: BasePart)
	local pivot = model:GetPivot()
	local offsetZ = Physics25D.PLANE_Z - pivot.Position.Z
	if math.abs(offsetZ) > 0.01 then
		model:PivotTo(pivot + Vector3.new(0, 0, offsetZ))
	end
	Physics25D.SetActorCollisionGroup(model)
	Physics25D.LockToPlane(root)
end

return Physics25D
