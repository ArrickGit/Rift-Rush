--!strict
-- StarterPlayerScripts/Client/Controllers/RiftPowerController.luau
-- The big "⚡ Power: N" badge beside the HUD vitals and the "⚡ RIFT POWER UP!" toast (game.md 3.2). The server owns
-- the number (FlexBadgeService sets the player's RiftPower attribute); this only draws it. Rises close together
-- (several cards in a row, a level up mid-toast) merge into one toast that keeps counting up from the first value.
-- Lives in UIController's RiftHUD layer so it follows the HUD's screen scaling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AssetRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetRegistry"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local RiftPowerController = {}

local player = Players.LocalPlayer

local FONT = Enum.Font.FredokaOne
local GOLD = Color3.fromRGB(255, 215, 70)
local STROKE = Color3.fromRGB(40, 24, 6)
local TICK_TIME = 0.7 -- seconds for a counter to roll up to its new value
local TOAST_HOLD = 2.2 -- seconds a toast stays after its last rise

local badgeLabel: TextLabel
local badgeScale: UIScale
local toast: Frame
local toastScale: UIScale
local toastTitle: TextLabel
local toastLine: TextLabel
local toastFlare: ImageLabel

local shown = 0 -- the value the badge currently displays (mid-tick it lags the attribute)
local toastFrom = 0 -- the value the current toast started from
local toastUntil = 0
local tickToken = 0

local function commas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
		:Play()
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local created = Instance.new("TextLabel")
	created.BackgroundTransparency = 1
	created.Font = FONT
	created.TextColor3 = GOLD
	created.RichText = true
	for key, value in props do
		(created :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 3
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = created
	created.Parent = parent
	return created
end

-- UIController's vitals column: the top-left frame stacked by a UIListLayout (the wallet on the right is anchored
-- at x = 1). The badge joins its list on top, so it moves with the column when the run info line grows.
local function vitalsColumn(root: Instance): Instance
	for _, child in root:GetChildren() do
		if child:IsA("Frame") and child.AnchorPoint.X == 0 and child:FindFirstChildOfClass("UIListLayout") then
			return child
		end
	end
	return root
end

local function build(root: Instance)
	local badge = Instance.new("Frame")
	badge.Name = "RiftPowerBadge"
	badge.LayoutOrder = 0
	badge.Size = UDim2.fromOffset(0, 30) -- compact: the column's Bag button sits just above the Shop stack
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = Color3.fromRGB(46, 30, 10)
	badge.BackgroundTransparency = 0.15
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = badge
	local outline = Instance.new("UIStroke")
	outline.Color = GOLD
	outline.Thickness = 2
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = badge
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = badge
	badgeScale = Instance.new("UIScale")
	badgeScale.Parent = badge
	badgeLabel = label(badge, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextSize = 20,
		Text = "⚡ Power: —" })
	badge.Parent = vitalsColumn(root)

	toast = Instance.new("Frame")
	toast.Name = "RiftPowerToast"
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Position = UDim2.fromScale(0.5, 0.8) -- under the character, clear of the notify toasts up top
	toast.Size = UDim2.fromOffset(520, 110)
	toast.BackgroundTransparency = 1
	toast.Visible = false
	toastScale = Instance.new("UIScale")
	toastScale.Parent = toast
	toastFlare = Instance.new("ImageLabel")
	toastFlare.AnchorPoint = Vector2.new(0.5, 0.5)
	toastFlare.Position = UDim2.fromScale(0.5, 0.5)
	toastFlare.Size = UDim2.fromOffset(200, 200)
	toastFlare.BackgroundTransparency = 1
	toastFlare.Image = AssetRegistry.VfxTextures.flare_01
	toastFlare.ImageColor3 = GOLD
	toastFlare.Parent = toast
	toastTitle = label(toast, { Size = UDim2.new(1, 0, 0, 52), TextSize = 44, Text = "⚡ RIFT POWER UP!" })
	toastLine = label(toast, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 40), TextSize = 30,
		TextColor3 = Color3.new(1, 1, 1) })
	toast.Parent = root
end

local function toastText(from: number, value: number): string
	return ("%s <font color='#ffd746'>»</font> %s <font color='#7dff8a'>(+%s)</font>"):format(commas(from),
		commas(value), commas(value - from))
end

-- Rolls the badge (and the toast, when open) from what is shown now up to `target`.
local function rollTo(target: number)
	tickToken += 1
	local token = tickToken
	local start = shown
	local began = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local alpha = math.min(1, (os.clock() - began) / TICK_TIME)
		local eased = 1 - (1 - alpha) ^ 3
		local value = math.round(start + (target - start) * eased)
		if token ~= tickToken then
			if connection then
				connection:Disconnect()
			end
			return
		end
		shown = value
		badgeLabel.Text = "⚡ Power: " .. commas(value)
		if toast.Visible then
			toastLine.Text = toastText(toastFrom, value)
		end
		if alpha >= 1 and connection then
			connection:Disconnect()
		end
	end)
end

local function showToast(from: number)
	local now = os.clock()
	local fresh = not toast.Visible or now > toastUntil
	toastUntil = now + TOAST_HOLD
	if fresh then
		toastFrom = from
		toast.Visible = true
		toastTitle.TextTransparency = 0
		toastLine.TextTransparency = 0
		toastLine.Text = toastText(from, from)
		toastScale.Scale = 0.4
	end
	toastScale.Scale = math.min(toastScale.Scale, 0.85)
	tween(toastScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	toastFlare.Size = UDim2.fromOffset(160, 160)
	toastFlare.ImageTransparency = 0.1
	tween(toastFlare, 0.7, { Size = UDim2.fromOffset(620, 620), ImageTransparency = 1 })
	local hideAt = toastUntil
	task.delay(TOAST_HOLD, function()
		if toastUntil ~= hideAt then
			return -- a later rise extended it
		end
		tween(toastTitle, 0.4, { TextTransparency = 1 })
		tween(toastLine, 0.4, { TextTransparency = 1 })
		task.delay(0.4, function()
			if toastUntil == hideAt then
				toast.Visible = false
			end
		end)
	end)
end

local function onPower()
	local value = tonumber(player:GetAttribute("RiftPower"))
	if not value then
		return
	end
	if shown <= 0 then
		shown = value -- first value on join: no toast
		badgeLabel.Text = "⚡ Power: " .. commas(value)
		return
	end
	if value > shown then
		showToast(shown)
		Sfx.Play("UI_Unlock", 0.6, 1 + math.min(0.4, (value - toastFrom) / math.max(1, toastFrom)))
		badgeScale.Scale = 1.25
		tween(badgeScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	rollTo(value)
end

function RiftPowerController.Init()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("RiftHUD")
	build(hud:WaitForChild("ScaleRoot"))
	player:GetAttributeChangedSignal("RiftPower"):Connect(onPower)
	onPower()
end

return RiftPowerController
