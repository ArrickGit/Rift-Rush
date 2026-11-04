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
--
-- Auto-Attack (game.md 3.4, Settings.AutoAttack, toggled by the HUD's "⚔️ AUTO" pill or the Settings screen): in a run,
-- when a live enemy is inside the weapon's reach (melee) or AUTO_RANGED studs (projectiles), the character turns to
-- it and attacks at the normal rate. Movement, jumping, dashing and Q stay manual.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("EnemyConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local Movement25DController = require(script.Parent:WaitForChild("Movement25DController"))
local CombatVFXController = require(script.Parent:WaitForChild("CombatVFXController"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local ATTACK_ACTION = "RiftAttack"
local ABILITY_ACTION = "RiftAbility1"
local ABILITY_SEND_SLACK = 0.1 -- send slightly early; the server forgives the same amount
local AUTO_RANGED = 28 -- projectile weapons auto-fire at enemies this close along the lane
local AUTO_MELEE_SLACK = 1.5 -- studs past the swing's reach that still count (enemies are wide)
local AUTO_ON = Color3.fromRGB(70, 190, 100)
local AUTO_OFF = Color3.fromRGB(58, 64, 96)

local CombatInputController = {}

local player = Players.LocalPlayer
local attackRemote: RemoteEvent
local dashRemote: RemoteEvent
local saveSettingsRemote: RemoteEvent
local equippedWeapon = WeaponConfig.DEFAULT_WEAPON
local attackHeld = false
local nextAttackAt = 0
local autoAttack = false
local autoButton: TextButton? = nil

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

-- Direction (+1 / -1) to the nearest live enemy the equipped weapon can reach, or nil.
local function autoTarget(): number?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local weapon = WeaponConfig.Weapons[equippedWeapon]
	local attack = weapon and weapon.Attack
	if not (root and root:IsA("BasePart") and attack) then
		return nil
	end
	local melee = attack.Kind == "Melee"
	local size = tonumber(player:GetAttribute("SizeScale")) or 1
	local reach = if melee then attack.Range * size + AUTO_MELEE_SLACK else AUTO_RANGED
	local height = if melee then math.max(attack.Height * size, 4) else 5
	local origin = root.Position
	local best: number? = nil
	local bestDistance = math.huge
	for _, enemy in CollectionService:GetTagged(EnemyConfig.TAG) do
		if not enemy:IsA("Model") or not enemy:IsDescendantOf(Workspace) or (tonumber(enemy:GetAttribute("HP")) or 1) <= 0 then
			continue
		end
		local offset = enemy:GetPivot().Position - origin
		local distance = math.abs(offset.X)
		if distance <= reach and math.abs(offset.Y) <= height and distance < bestDistance then
			best, bestDistance = if offset.X < 0 then -1 else 1, distance
		end
	end
	return best
end

local function refreshAutoButton()
	local button = autoButton
	if button then
		button.Visible = inRun()
		button.Text = if autoAttack then "⚔️ AUTO: ON" else "⚔️ AUTO: OFF"
		button.BackgroundColor3 = if autoAttack then AUTO_ON else AUTO_OFF
	end
end

-- From the Settings screen / the saved profile.
function CombatInputController.SetAutoAttack(enabled: boolean)
	autoAttack = enabled
	refreshAutoButton()
end

function CombatInputController.IsAutoAttack(): boolean
	return autoAttack
end

-- The HUD pill, bottom-centre left of the Q cooldown label, shown in runs.
local function buildAutoButton()
	local root = player:WaitForChild("PlayerGui"):WaitForChild("RiftHUD"):WaitForChild("ScaleRoot")
	local button = Instance.new("TextButton")
	button.Name = "AutoAttackToggle"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(0.5, -130, 1, -14)
	button.Size = UDim2.fromOffset(150, 34)
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 18
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.3
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(13, 21, 36)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.Activated:Connect(function()
		autoAttack = not autoAttack
		refreshAutoButton()
		Sfx.Play("UI_Toggle", 0.6)
		saveSettingsRemote:FireServer({ AutoAttack = autoAttack })
	end)
	button.Parent = root
	autoButton = button
	refreshAutoButton()
	player:GetAttributeChangedSignal("RunId"):Connect(refreshAutoButton)
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

local profileSeen = false -- the first snapshot on join must not play the equip sound

local function applyProfile(profile: any)
	if type(profile) == "table" and type(profile.EquippedWeapon) == "string" then
		if profileSeen and profile.EquippedWeapon ~= equippedWeapon then
			Sfx.Play("Weapon_Equip", 0.5)
		end
		profileSeen = true
		equippedWeapon = profile.EquippedWeapon
	end
	if type(profile) == "table" and type(profile.Settings) == "table" then
		CombatInputController.SetAutoAttack(profile.Settings.AutoAttack == true)
	end
end

function CombatInputController.Init()
	attackRemote = Remotes.GetEvent("CombatAttack")
	dashRemote = Remotes.GetEvent("CombatDash")
	saveSettingsRemote = Remotes.GetEvent("SaveSettings")
	task.spawn(buildAutoButton) -- waits for UIController's HUD layer

	ContextActionService:BindAction(ATTACK_ACTION, onAttackAction, false,
		Enum.UserInputType.MouseButton1, Enum.KeyCode.J, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction(ABILITY_ACTION, onAbilityAction, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1)

	-- Holding the button keeps attacking at the weapon's rate; Auto-Attack does the same while a target is in reach.
	RunService.Heartbeat:Connect(function()
		if attackHeld then
			tryAttack()
		elseif autoAttack and inRun() and os.clock() >= nextAttackAt then
			local direction = autoTarget()
			if direction then
				Movement25DController.SetFacing(direction)
				tryAttack()
			end
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
