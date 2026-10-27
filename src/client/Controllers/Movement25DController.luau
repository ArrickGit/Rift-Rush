--!strict
-- StarterPlayerScripts/Client/Controllers/Movement25DController.luau
-- 2.5D side-scroller movement for the local character (Sections 7 & 8):
--   * X-only movement layered on the default PlayerModule, so keyboard, gamepad and the mobile
--     thumbstick / jump button all work without custom input code
--   * Double jump (Triple with Skywalker's Grace Lv3) — each air jump needs a fresh press
--   * Down + Jump drops through one-way platforms (parts tagged Physics25D.ONE_WAY_TAG)
--   * Dash on the ground / Flash Jump in the air, with regenerating charges
--
-- The server owns the Z=0 PlaneConstraint and collision group (CharacterService). This controller only
-- snaps the spawn pose onto the plane and corrects drift if the constraint is ever missing.
--
-- One-way platforms toggle CanCollide locally. The client simulates its own character, so a platform can
-- be solid for one player while another drops through it, and server-simulated monsters still stand on it.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Physics25D = require(Shared:WaitForChild("Physics25D"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local INPUT_STEP_NAME = "RiftMovement25D"
local DASH_ACTION = "RiftDash"
local STICK_DEADZONE = 0.15
local FULL_SPEED_INPUT = 0.7 -- diagonal keyboard input (0.707) still walks at full speed
local DOWN_THRESHOLD = 0.5
local GROUND_DASH_SPEED = 75
local GROUND_DASH_TIME = 0.16
local FLASH_JUMP_SPEED = 70
local FLASH_JUMP_TIME = 0.22
local FLASH_JUMP_LIFT = 22
local DASH_MAX_FORCE = 1e6
local DROP_IGNORE_TIME = 0.3
local DROP_NUDGE_SPEED = -12
local SAME_TIER_EPSILON = 0.25 -- platforms whose tops match this closely are dropped through together
local PLATFORM_STAND_TOLERANCE = 0.6
local PLATFORM_RISING_TOLERANCE = 0.1
local DRIFT_TOLERANCE = 1

type CharacterState = {
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	DashVelocity: LinearVelocity,
	Connections: { RBXScriptConnection },
}

local Movement25DController = {}

local player = Players.LocalPlayer
local controls: any = nil
local current: CharacterState? = nil
local mobility = Physics25D.GetMobility(0)
local enabled = true

local facing = 1
local jumpWasHeld = false
local suppressJumpUntilRelease = false
local airJumpsUsed = 0
local dashCharges = mobility.DashCharges
local dashRecharge = 0
local dashTimeLeft = 0

local platforms: { [BasePart]: boolean } = {}
local platformIgnoredUntil: { [BasePart]: number } = {}
local platformListDirty = true
local platformRaycastParams = RaycastParams.new()
platformRaycastParams.FilterType = Enum.RaycastFilterType.Include

local dashStartedEvent = Instance.new("BindableEvent")

-- Fires (direction: number, inAir: boolean) — used by Shadow Step / Combo Overdrive in Step 4.
Movement25DController.DashStarted = dashStartedEvent.Event :: RBXScriptSignal

local function isGrounded(state: CharacterState): boolean
	return state.Humanoid.FloorMaterial ~= Enum.Material.Air
end

local function getFeetOffset(state: CharacterState): number
	if state.Humanoid.RigType == Enum.HumanoidRigType.R6 then
		return state.Root.Size.Y * 1.5 -- R6 legs hang a full torso-height below the root
	end
	return state.Root.Size.Y / 2 + state.Humanoid.HipHeight
end

local function getPlatformTop(platform: BasePart): number
	return platform.Position.Y + platform.Size.Y / 2
end

local function addPlatform(instance: Instance)
	if instance:IsA("BasePart") then
		platforms[instance] = true
		platformListDirty = true
	end
end

local function removePlatform(instance: Instance)
	if instance:IsA("BasePart") then
		platforms[instance] = nil
		platformIgnoredUntil[instance] = nil
		platformListDirty = true
	end
end

local function findPlatformUnderFeet(state: CharacterState): BasePart?
	if platformListDirty then
		local list: { Instance } = {}
		for platform in platforms do
			table.insert(list, platform)
		end
		platformRaycastParams.FilterDescendantsInstances = list
		platformListDirty = false
	end
	local result = Workspace:Raycast(state.Root.Position, Vector3.new(0, -(getFeetOffset(state) + 1), 0), platformRaycastParams)
	local hit = result and result.Instance
	if hit and hit:IsA("BasePart") and platforms[hit] then
		return hit
	end
	return nil
end

-- Solid only while the feet are above the platform top, so jumping up passes through and landing sticks.
local function updatePlatformCollision(state: CharacterState)
	local feetY = state.Root.Position.Y - getFeetOffset(state)
	local tolerance = if state.Root.AssemblyLinearVelocity.Y > 1 then PLATFORM_RISING_TOLERANCE else PLATFORM_STAND_TOLERANCE
	local now = os.clock()
	for platform in platforms do
		local solid = feetY >= getPlatformTop(platform) - tolerance and (platformIgnoredUntil[platform] or 0) <= now
		if platform.CanCollide ~= solid then
			platform.CanCollide = solid
		end
	end
end

local function dropThrough(state: CharacterState, standingOn: BasePart)
	-- Ignore every platform on this tier, so standing on a seam between segments still drops.
	local tierTop = getPlatformTop(standingOn)
	local ignoreUntil = os.clock() + DROP_IGNORE_TIME
	for platform in platforms do
		if math.abs(getPlatformTop(platform) - tierTop) <= SAME_TIER_EPSILON then
			platformIgnoredUntil[platform] = ignoreUntil
			platform.CanCollide = false
		end
	end
	state.Humanoid.Jump = false
	suppressJumpUntilRelease = true
	local velocity = state.Root.AssemblyLinearVelocity
	state.Root.AssemblyLinearVelocity = Vector3.new(velocity.X, DROP_NUDGE_SPEED, 0)
end

local function canAirJump(humanoid: Humanoid): boolean
	local humanoidState = humanoid:GetState()
	return humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.Jumping
end

-- Runs right after the PlayerModule's ControlModule (RenderPriority.Input), overriding its Move call and
-- reading the Humanoid.Jump value it just wrote — that value is "jump held" for every input device.
local function onInputStep()
	local state = current
	if not state then
		return
	end
	local humanoid = state.Humanoid

	if not enabled or humanoid.Health <= 0 then
		humanoid:Move(Vector3.zero, false)
		humanoid.Jump = false
		jumpWasHeld = true -- a key still held when re-enabled must not count as a fresh press
		return
	end

	local moveVector: Vector3 = if controls then controls:GetMoveVector() else Vector3.zero
	local horizontal = moveVector.X
	if math.abs(horizontal) < STICK_DEADZONE then
		horizontal = 0
	else
		horizontal = math.clamp(horizontal / FULL_SPEED_INPUT, -1, 1)
	end
	if horizontal ~= 0 and dashTimeLeft <= 0 then
		facing = if horizontal > 0 then 1 else -1
	end
	humanoid:Move(Vector3.new(horizontal, 0, 0), false)

	local jumpHeld = humanoid.Jump
	local jumpPressed = jumpHeld and not jumpWasHeld
	jumpWasHeld = jumpHeld

	local grounded = isGrounded(state)
	if grounded then
		airJumpsUsed = 0
	end

	if suppressJumpUntilRelease then
		if jumpHeld then
			humanoid.Jump = false
			return
		end
		suppressJumpUntilRelease = false
	end

	if not jumpPressed then
		return
	end
	if grounded then
		-- moveVector.Z > 0 is "back"/down: S key, stick down, thumbstick down.
		if moveVector.Z > DOWN_THRESHOLD then
			local platform = findPlatformUnderFeet(state)
			if platform then
				dropThrough(state, platform)
			end
		end
		-- Otherwise the Humanoid performs the normal ground jump itself.
	elseif airJumpsUsed < mobility.AirJumps and canAirJump(humanoid) then
		airJumpsUsed += 1
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

local function tryDash()
	local state = current
	if not (enabled and state) or dashTimeLeft > 0 or dashCharges <= 0 or state.Humanoid.Health <= 0 then
		return
	end
	local inAir = not isGrounded(state)
	dashCharges -= 1
	dashTimeLeft = if inAir then FLASH_JUMP_TIME else GROUND_DASH_TIME
	state.DashVelocity.LineVelocity = facing * (if inAir then FLASH_JUMP_SPEED else GROUND_DASH_SPEED)
	state.DashVelocity.Enabled = true
	if inAir then
		local velocity = state.Root.AssemblyLinearVelocity
		state.Root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, FLASH_JUMP_LIFT), 0)
	end
	dashStartedEvent:Fire(facing, inAir)
end

local function onDashAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		tryDash()
	end
	return Enum.ContextActionResult.Sink
end

local function updateDash(state: CharacterState, dt: number)
	if dashTimeLeft > 0 then
		dashTimeLeft -= dt
		if dashTimeLeft <= 0 then
			dashTimeLeft = 0
			state.DashVelocity.Enabled = false
		end
	end
	if dashCharges < mobility.DashCharges then
		dashRecharge += dt
		if dashRecharge >= mobility.DashCooldown then
			dashCharges += 1
			dashRecharge = 0
		end
	else
		dashRecharge = 0
	end
end

local function onPreSimulation(dt: number)
	local state = current
	if not state then
		return
	end
	updateDash(state, dt)
	updatePlatformCollision(state)

	local z = state.Root.Position.Z
	if math.abs(z - Physics25D.PLANE_Z) > DRIFT_TOLERANCE then
		state.Root.CFrame += Vector3.new(0, 0, Physics25D.PLANE_Z - z)
	end
end

local function cleanupCharacter()
	local state = current
	if not state then
		return
	end
	current = nil
	for _, connection in state.Connections do
		connection:Disconnect()
	end
end

local function onCharacterAdded(character: Model)
	cleanupCharacter()
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) or player.Character ~= character then
		return
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	-- Face +X on the combat plane before the server's PlaneConstraint takes over.
	local planePosition = Vector3.new(root.Position.X, root.Position.Y, Physics25D.PLANE_Z)
	character:PivotTo(CFrame.lookAt(planePosition, planePosition + Vector3.xAxis))

	-- Local-only constraint: the client owns its character's physics, so it never needs to replicate.
	local attachment = Instance.new("Attachment")
	attachment.Name = "DashAttachment"
	attachment.Parent = root
	local dashVelocity = Instance.new("LinearVelocity")
	dashVelocity.Name = "DashVelocity"
	dashVelocity.Attachment0 = attachment
	dashVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	dashVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	dashVelocity.LineDirection = Vector3.xAxis
	dashVelocity.MaxForce = DASH_MAX_FORCE
	dashVelocity.Enabled = false
	dashVelocity.Parent = root

	facing = 1
	jumpWasHeld = false
	suppressJumpUntilRelease = false
	airJumpsUsed = 0
	dashCharges = mobility.DashCharges
	dashRecharge = 0
	dashTimeLeft = 0

	local state: CharacterState = {
		Character = character,
		Humanoid = humanoid,
		Root = root,
		DashVelocity = dashVelocity,
		Connections = {},
	}
	table.insert(state.Connections, humanoid.Died:Connect(function()
		dashTimeLeft = 0
		dashVelocity.Enabled = false
	end))
	current = state
end

local function applyProfile(profile: any)
	if type(profile) ~= "table" or type(profile.AscensionNodes) ~= "table" then
		return
	end
	local level = profile.AscensionNodes[Physics25D.SKYWALKER_NODE_ID]
	mobility = Physics25D.GetMobility(if type(level) == "number" then level else 0)
	dashCharges = math.min(dashCharges, mobility.DashCharges)
end

-- Pauses player control (upgrade modal, cutscenes). Jump input held across the pause is ignored.
function Movement25DController.SetEnabled(isEnabled: boolean)
	enabled = isEnabled
	if not isEnabled then
		dashTimeLeft = 0
		if current then
			current.DashVelocity.Enabled = false
		end
	end
end

function Movement25DController.GetFacing(): number
	return facing
end

function Movement25DController.IsDashing(): boolean
	return dashTimeLeft > 0
end

-- (available, max, seconds until the next charge) for the HUD.
function Movement25DController.GetDashCharges(): (number, number, number)
	local untilNext = if dashCharges < mobility.DashCharges then mobility.DashCooldown - dashRecharge else 0
	return dashCharges, mobility.DashCharges, untilNext
end

function Movement25DController.Init()
	local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
	controls = (require :: any)(playerModule):GetControls()

	for _, instance in CollectionService:GetTagged(Physics25D.ONE_WAY_TAG) do
		addPlatform(instance)
	end
	CollectionService:GetInstanceAddedSignal(Physics25D.ONE_WAY_TAG):Connect(addPlatform)
	CollectionService:GetInstanceRemovedSignal(Physics25D.ONE_WAY_TAG):Connect(removePlatform)

	ContextActionService:BindAction(DASH_ACTION, onDashAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.K, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle(DASH_ACTION, "Dash")

	RunService:BindToRenderStep(INPUT_STEP_NAME, Enum.RenderPriority.Input.Value + 1, onInputStep)
	RunService.PreSimulation:Connect(onPreSimulation)

	Remotes.GetEvent("ProfileUpdated").OnClientEvent:Connect(applyProfile)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Remotes.GetFunction("GetProfile"):InvokeServer()
		end)
		if ok then
			applyProfile(profile)
		end
	end)

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		cleanupCharacter()
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
end

return Movement25DController
