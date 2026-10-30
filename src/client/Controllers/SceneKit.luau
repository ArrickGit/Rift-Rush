--!strict
-- StarterPlayerScripts/Client/Controllers/SceneKit.luau
-- Small drawing and animation helpers shared by the station scenes (StationScenes, StarForgeScene, ...): tweens,
-- round frames, icons, hover growth, flare bursts, and an overlay layer for effects that must not be clipped by the
-- station's scroll frame or cut off by a re-render. Builds on UIController's kit, passed in through Init.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetRegistry"))

type Payload = { [string]: any }

local SceneKit = {}

local K: any = nil -- UIController's kit, set by Init
local overlay: Frame

SceneKit.PULSE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
SceneKit.POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
SceneKit.HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function SceneKit.tween(instance: Instance, info: TweenInfo, goal: Payload): Tween
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

function SceneKit.circle(parent: Instance, props: Payload): Frame
	local frame: Frame = K.create("Frame", props, parent)
	K.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
	return frame
end

function SceneKit.icon(parent: Instance, image: string?, props: Payload): ImageLabel
	local base: Payload = { BackgroundTransparency = 1, Image = image or "", ScaleType = Enum.ScaleType.Fit }
	for key, value in props do
		base[key] = value
	end
	return K.create("ImageLabel", base, parent)
end

-- Grows on hover, like the kit's buttons.
function SceneKit.hoverGrow(button: GuiButton, scale: UIScale, amount: number)
	button.MouseEnter:Connect(function()
		SceneKit.tween(scale, SceneKit.HOVER, { Scale = amount })
	end)
	button.MouseLeave:Connect(function()
		SceneKit.tween(scale, SceneKit.HOVER, { Scale = 1 })
	end)
end

-- A flare that blooms and fades over `parent`'s centre (bought node levels, stamped quests, forged stars).
function SceneKit.burst(parent: GuiObject, color: Color3)
	local flare = SceneKit.icon(parent, AssetRegistry.VfxTextures.flare_01, { AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ImageColor3 = color, ZIndex = 20 })
	SceneKit.tween(flare, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(3, 3), ImageTransparency = 1 })
	task.delay(0.65, function()
		flare:Destroy()
	end)
end

-- A small flat button for secondary actions (the kit's gem buttons have fixed heights, too tall for a toggle row).
function SceneKit.pill(parent: Instance, text: string, color: Color3, enabled: boolean, onClick: () -> (), props: Payload): TextButton
	local base: Payload = { Text = text, Font = K.DISPLAY_FONT, TextSize = 14, RichText = true, AutoButtonColor = false,
		TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3,
		BackgroundColor3 = if enabled then color else color:Lerp(Color3.fromHex("2a2e3c"), 0.82) }
	for key, value in props do
		base[key] = value
	end
	local button: TextButton = K.create("TextButton", base, parent)
	K.round(button, 10)
	K.outline(button, K.COLORS.Stroke, 2)
	if enabled then
		SceneKit.hoverGrow(button, K.create("UIScale", {}, button), 1.05)
		button.Activated:Connect(onClick)
	else
		button.TextTransparency = 0.55
		button.TextStrokeTransparency = 0.8
	end
	return button
end

function SceneKit.currencyColor(key: string): Color3
	local info = AssetRegistry.Currencies[key]
	return if info then info.Color else K.COLORS.Gold
end

-- The overlay layer, for effects drawn above the station window (rotation renders here, unlike inside the
-- window's clipping scroll frame).
function SceneKit.overlay(): Frame
	return overlay
end

-- `gui`'s centre in the overlay's (unscaled) coordinates.
function SceneKit.overlayPoint(gui: GuiObject): Vector2
	local scale = overlay:FindFirstChildOfClass("UIScale")
	local factor = if scale then scale.Scale else 1
	return (gui.AbsolutePosition + gui.AbsoluteSize / 2 - overlay.AbsolutePosition) / factor
end

function SceneKit.Init(kit: any)
	K = kit
	overlay = K.newLayer("RiftRewardFly", 60, false)
end

return SceneKit
