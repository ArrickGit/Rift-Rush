--!strict
-- StarterPlayerScripts/Client/Controllers/CombatInputController.luau
-- Turns player input into combat *intent* (Section 8): Attack (holdable), Ability 1 and the dash i-frame request.
-- The server owns cooldowns, damage and targets; this controller only paces requests with the same intervals the
-- server publishes (AttackInterval / Ability1ReadyAt player attributes) so a held button doesn't spam the remote.
--
--   PC: Left Click or J = Attack, Q = Ability 1, Shift/K = Dash (bound by Movement25DController)
--   Controller: X = Attack, LB/RB = Ability 1     Mobile: MobileControlsController's on-screen buttons call
--   SetAttackHeld / PressAbility.
-- Gauntlets punches nudge the local character forward (Lunge); the client owns its physics, so it does that here.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local Movement25DController = require(script.Parent:WaitForChild("Movement25DController"))
local CombatVFXController = require(script.Parent:WaitForChild("CombatVFXController"))

local ATTACK_ACTION = "RiftAttack"
local ABILITY_ACTION = "RiftAbility1"
local ABILITY_SEND_SLACK = 0.1 -- send slightly early; the server forgives the same amount

local CombatInputController = {}

local player = Players.LocalPlayer
local attackRemote: RemoteEvent
local dashRemote: RemoteEvent
local equippedWeapon = WeaponConfig.DEFAULT_WEAPON
local attackHeld = false
local nextAttackAt = 0

local function inRun(): boolean
	return player:GetAttribute("RunId") ~= nil
end

local function currentInterval(): number
	local published = player:GetAttribute("AttackInterval")
	if type(published) == "number" and published > 0 then
		return published
	end
	return WeaponConfig.GetAttackInterval(equippedWeapon)
end

local function aliveHumanoid(): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function tryAttack()
	local now = os.clock()
	if now < nextAttackAt or not inRun() or not aliveHumanoid() then
		return
	end
	nextAttackAt = now + currentInterval()
	local facing = Movement25DController.GetFacing()
	CombatVFXController.PlaySwing(equippedWeapon, facing)
	attackRemote:FireServer("Basic", facing)

	local weapon = WeaponConfig.Weapons[equippedWeapon]
	local lunge = weapon and weapon.Attack and weapon.Attack.Lunge
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if lunge and root and root:IsA("BasePart") then
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(facing * math.max(math.abs(velocity.X), lunge), velocity.Y, 0)
	end
end

local function tryAbility()
	if not inRun() or not aliveHumanoid() then
		return
	end
	local readyAt = player:GetAttribute("Ability1ReadyAt")
	if type(readyAt) == "number" and Workspace:GetServerTimeNow() < readyAt - ABILITY_SEND_SLACK then
		return
	end
	attackRemote:FireServer("Ability1", Movement25DController.GetFacing())
end

local function onAttackAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		attackHeld = true
		tryAttack()
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		attackHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local function onAbilityAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		tryAbility()
	end
	return Enum.ContextActionResult.Sink
end

-- On-screen buttons (MobileControlsController).
function CombatInputController.SetAttackHeld(held: boolean)
	attackHeld = held
	if held then
		tryAttack()
	end
end

function CombatInputController.PressAbility()
	tryAbility()
end

local function applyProfile(profile: any)
	if type(profile) == "table" and type(profile.EquippedWeapon) == "string" then
		equippedWeapon = profile.EquippedWeapon
	end
end

function CombatInputController.Init()
	attackRemote = Remotes.GetEvent("CombatAttack")
	dashRemote = Remotes.GetEvent("CombatDash")

	ContextActionService:BindAction(ATTACK_ACTION, onAttackAction, false,
		Enum.UserInputType.MouseButton1, Enum.KeyCode.J, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction(ABILITY_ACTION, onAbilityAction, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1)

	-- Holding the button keeps attacking at the weapon's rate.
	RunService.Heartbeat:Connect(function()
		if attackHeld then
			tryAttack()
		end
	end)

	-- Tell the server when we dash so it can grant i-frames (it tracks its own dash charges).
	Movement25DController.DashStarted:Connect(function(direction: number)
		if inRun() then
			dashRemote:FireServer(direction)
		end
	end)

	Remotes.GetEvent("ProfileUpdated").OnClientEvent:Connect(applyProfile)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Remotes.GetFunction("GetProfile"):InvokeServer()
		end)
		if ok then
			applyProfile(profile)
		end
	end)

	player.CharacterRemoving:Connect(function()
		attackHeld = false
	end)
end

return CombatInputController
