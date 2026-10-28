--!strict
-- StarterPlayerScripts/Client/Controllers/MobileControlsController.luau
-- Touch controls (game.md Section 4 / Step SP-6) for phones and tablets:
--   * Left side: a floating virtual joystick (appears where the thumb lands) driving Movement25DController.
--     Pull it down + Jump to drop through a platform. Hidden when the default PlayerModule already provides its
--     own thumbstick and jump button.
--   * Right side: a large Attack button (hold to keep attacking), Skill (with its cooldown), Dash and Jump.
-- The Bag button lives in UIController's HUD for every platform. Only runs on touch-first devices.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CombatInputController = require(script.Parent:WaitForChild("CombatInputController"))
local Movement25DController = require(script.Parent:WaitForChild("Movement25DController"))

local MobileControlsController = {}

local JOYSTICK_RADIUS = 64
local DEAD_ZONE = 0.18

local player = Players.LocalPlayer

local joystickInput: InputObject? = nil
local joystickOrigin = Vector2.zero
local moveVector = Vector3.zero
local jumpHeld = false

local function roundButton(parent: Instance, name: string, text: string, size: number, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = position
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.15
	button.AutoButtonColor = true
	button.Font = Enum.Font.FredokaOne
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = size * 0.3
	button.TextStrokeTransparency = 0.3
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(13, 21, 36)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	button.Parent = parent
	return button
end

-- Fires `onDown` / `onUp` for a held touch on the button.
local function bindHold(button: TextButton, onDown: () -> (), onUp: (() -> ())?)
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			onDown()
		end
	end)
	if onUp then
		local release = onUp
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				release()
			end
		end)
	end
end

function MobileControlsController.Init()
	if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RiftTouchControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Joystick visuals (shown while a thumb is down on the left side).
	local base = Instance.new("Frame")
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.Size = UDim2.fromOffset(JOYSTICK_RADIUS * 2, JOYSTICK_RADIUS * 2)
	base.BackgroundColor3 = Color3.fromRGB(22, 20, 36)
	base.BackgroundTransparency = 0.5
	base.Visible = false
	base.Parent = gui
	local baseCorner = Instance.new("UICorner")
	baseCorner.CornerRadius = UDim.new(1, 0)
	baseCorner.Parent = base
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(52, 52)
	knob.BackgroundColor3 = Color3.fromRGB(240, 240, 255)
	knob.BackgroundTransparency = 0.2
	knob.Parent = base
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local attack = roundButton(gui, "Attack", "⚔️", 110, UDim2.new(1, -95, 1, -110), Color3.fromRGB(240, 90, 80))
	local skill = roundButton(gui, "Skill", "Q", 76, UDim2.new(1, -205, 1, -80), Color3.fromRGB(140, 100, 240))
	local dash = roundButton(gui, "Dash", "💨", 70, UDim2.new(1, -195, 1, -175), Color3.fromRGB(60, 170, 220))
	local jump = roundButton(gui, "Jump", "⬆", 80, UDim2.new(1, -90, 1, -235), Color3.fromRGB(90, 200, 90))
	local cooldown = Instance.new("TextLabel")
	cooldown.Size = UDim2.fromScale(1, 1)
	cooldown.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldown.BackgroundTransparency = 0.45
	cooldown.Font = Enum.Font.FredokaOne
	cooldown.TextColor3 = Color3.new(1, 1, 1)
	cooldown.TextSize = 22
	cooldown.Visible = false
	cooldown.Parent = skill
	local cooldownCorner = Instance.new("UICorner")
	cooldownCorner.CornerRadius = UDim.new(1, 0)
	cooldownCorner.Parent = cooldown

	bindHold(attack, function()
		CombatInputController.SetAttackHeld(true)
	end, function()
		CombatInputController.SetAttackHeld(false)
	end)
	bindHold(skill, CombatInputController.PressAbility)
	bindHold(dash, Movement25DController.Dash)
	bindHold(jump, function()
		jumpHeld = true
	end, function()
		jumpHeld = false
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.Touch or joystickInput then
			return
		end
		local camera = Workspace.CurrentCamera
		if camera and input.Position.X < camera.ViewportSize.X * 0.42 and not Movement25DController.HasPlayerControls() then
			joystickInput = input
			joystickOrigin = Vector2.new(input.Position.X, input.Position.Y)
			base.Position = UDim2.fromOffset(joystickOrigin.X, joystickOrigin.Y)
			base.Visible = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input ~= joystickInput then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - joystickOrigin
		local clamped = if delta.Magnitude > JOYSTICK_RADIUS then delta.Unit * JOYSTICK_RADIUS else delta
		knob.Position = UDim2.new(0.5, clamped.X, 0.5, clamped.Y)
		local stick = clamped / JOYSTICK_RADIUS
		moveVector = if stick.Magnitude < DEAD_ZONE then Vector3.zero else Vector3.new(stick.X, 0, stick.Y)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == joystickInput then
			joystickInput = nil
			moveVector = Vector3.zero
			base.Visible = false
			knob.Position = UDim2.fromScale(0.5, 0.5)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local inRun = player:GetAttribute("RunId") ~= nil
		attack.Visible = inRun
		skill.Visible = inRun
		dash.Visible = true
		jump.Visible = not Movement25DController.HasPlayerControls()
		Movement25DController.SetVirtualInput(moveVector, jumpHeld)
		local readyAt = player:GetAttribute("Ability1ReadyAt")
		local remaining = if type(readyAt) == "number" then readyAt - Workspace:GetServerTimeNow() else 0
		cooldown.Visible = remaining > 0
		if remaining > 0 then
			cooldown.Text = ("%.1f"):format(remaining)
		end
	end)
end

return MobileControlsController
