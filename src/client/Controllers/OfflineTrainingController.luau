--!strict
-- StarterPlayerScripts/Client/Controllers/OfflineTrainingController.luau
-- The "🌙 WHILE YOU WERE AWAY — YOUR HUNTER TRAINED!" claim card (game.md 3.7). SanctuaryService works out the
-- rewards; on start this asks for them (ClaimOfflineTraining { Action = "Query" }) and the server answers with an
-- OfflineTraining { Kind = "Show" } payload only when something is waiting. [Claim Rewards] pays it out;
-- [2x with Robux] goes through the usual RequestPurchase flow (the OfflineDouble product).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local OfflineTrainingController = {}

local player = Players.LocalPlayer

local FONT = Enum.Font.FredokaOne
local GOLD = Color3.fromRGB(255, 215, 70)
local MOON = Color3.fromRGB(170, 140, 255)
local PANEL = Color3.fromRGB(26, 22, 52)
local STROKE = Color3.fromRGB(14, 10, 30)
local QUERY_DELAY = 3 -- let the HUD settle before the card pops

local gui: ScreenGui
local card: Frame
local cardScale: UIScale
local timeLabel: TextLabel
local dustLabel: TextLabel
local masteryLabel: TextLabel
local masteryIcon: TextLabel
local claimButton: TextButton
local claimRemote: RemoteEvent

local function commas(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function duration(minutes: number): string
	local hours = minutes // 60
	local rest = minutes % 60
	if hours <= 0 then
		return ("%dm"):format(rest)
	end
	return if rest > 0 then ("%dh %dm"):format(hours, rest) else ("%dh"):format(hours)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local created = Instance.new("TextLabel")
	created.BackgroundTransparency = 1
	created.Font = FONT
	created.TextColor3 = Color3.new(1, 1, 1)
	created.RichText = true
	for key, value in props do
		(created :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 2.5
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = created
	created.Parent = parent
	return created
end

local function rounded(instance: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function button(parent: Instance, text: string, color: Color3, position: UDim2, onClick: () -> ()): TextButton
	local created = Instance.new("TextButton")
	created.AnchorPoint = Vector2.new(0.5, 0)
	created.Position = position
	created.Size = UDim2.fromOffset(196, 52)
	created.BackgroundColor3 = color
	created.AutoButtonColor = true
	created.Font = FONT
	created.TextSize = 22
	created.TextColor3 = Color3.new(1, 1, 1)
	created.Text = text
	rounded(created, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = created
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = STROKE
	textStroke.Thickness = 2
	textStroke.Parent = created
	created.Activated:Connect(onClick)
	created.Parent = parent
	return created
end

-- One reward line: an image icon, or (no image) a glyph label returned second so it can be retitled per weapon.
local function rewardRow(parent: Instance, y: number, image: string?): (TextLabel, TextLabel?)
	local row = Instance.new("Frame")
	row.Position = UDim2.new(0, 28, 0, y)
	row.Size = UDim2.new(1, -56, 0, 50)
	row.BackgroundColor3 = Color3.fromRGB(44, 38, 84)
	rounded(row, 12)
	row.Parent = parent
	local glyph: TextLabel? = nil
	if image and image ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.fromOffset(10, 7)
		icon.Size = UDim2.fromOffset(36, 36)
		icon.Image = image
		icon.Parent = row
	else
		glyph = label(row, { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(40, 50), TextSize = 28, Text = "" })
	end
	return label(row, { Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -66, 1, 0), TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "" }), glyph
end

local function hide()
	if not gui.Enabled then
		return
	end
	TweenService:Create(cardScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.6 }):Play()
	task.delay(0.18, function()
		gui.Enabled = false
	end)
end

local function show(payload: { [string]: any })
	local minutes = tonumber(payload.Minutes) or 0
	local maxMinutes = tonumber(payload.MaxMinutes) or 480
	timeLabel.Text = ("Your hunter trained for <font color='#%s'>%s</font>%s"):format(MOON:ToHex(), duration(minutes),
		if minutes >= maxMinutes then (" <font color='#aaaaaa'>(max %s)</font>"):format(duration(maxMinutes)) else "")
	dustLabel.Text = ("<font color='#%s'>+%s</font> Rift Dust"):format(GOLD:ToHex(), commas(tonumber(payload.Dust) or 0))
	masteryIcon.Text = tostring(payload.Icon or "⚔️")
	masteryLabel.Text = ("<font color='#%s'>+%s</font> %s Mastery XP"):format(GOLD:ToHex(),
		commas(tonumber(payload.Mastery) or 0), tostring(payload.Weapon or "Weapon"))
	claimButton.Active = true
	gui.Enabled = true
	cardScale.Scale = 0.4
	TweenService:Create(cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Sfx.Play("UI_Popup", 0.6)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "RiftOfflineTraining"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = gui

	card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(480, 360)
	card.BackgroundColor3 = PANEL
	rounded(card, 20)
	local outline = Instance.new("UIStroke")
	outline.Color = MOON
	outline.Thickness = 4
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = card
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(70, 56, 140), Color3.new(1, 1, 1))
	gradient.Rotation = 90
	gradient.Parent = card
	cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	card.Parent = gui

	local glow = Instance.new("ImageLabel")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromOffset(240, 20)
	glow.Size = UDim2.fromOffset(240, 240)
	glow.BackgroundTransparency = 1
	glow.Image = AssetRegistry.VfxTextures.light_01 or ""
	glow.ImageColor3 = MOON
	glow.ImageTransparency = 0.5
	glow.ZIndex = 0
	glow.Parent = card

	label(card, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 38), TextSize = 32, TextColor3 = GOLD,
		Text = "🌙 WHILE YOU WERE AWAY" })
	label(card, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 28), TextSize = 24,
		Text = "YOUR HUNTER TRAINED!" })
	timeLabel = label(card, { Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 24), TextSize = 18,
		TextColor3 = Color3.fromRGB(220, 215, 240), Text = "" })
	dustLabel = rewardRow(card, 130, AssetRegistry.Icons.Cur_Dust)
	local masteryGlyph: TextLabel?
	masteryLabel, masteryGlyph = rewardRow(card, 188, nil)
	masteryIcon = masteryGlyph :: TextLabel

	claimButton = button(card, "Claim Rewards", Color3.fromRGB(70, 190, 90), UDim2.new(0.5, -104, 0, 270), function()
		if claimButton.Active then
			claimButton.Active = false
			Sfx.Play("UI_Confirm", 0.6)
			claimRemote:FireServer({ Action = "Claim" })
		end
	end)
	local price = MonetizationConfig.Products.OfflineDouble and MonetizationConfig.Products.OfflineDouble.Price or 25
	button(card, ("2x with  R$%d"):format(price), Color3.fromRGB(230, 160, 30), UDim2.new(0.5, 104, 0, 270), function()
		Sfx.Play("UI_Click", 0.5)
		Remotes.GetEvent("RequestPurchase"):FireServer({ Kind = "Product", Key = "OfflineDouble" })
	end)
end

function OfflineTrainingController.Init()
	claimRemote = Remotes.GetEvent("ClaimOfflineTraining")
	build()
	Remotes.GetEvent("OfflineTraining").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Kind == "Show" then
			show(payload)
		elseif payload.Kind == "Closed" then
			Sfx.Play("Currency_Gain", 0.7)
			hide()
		end
	end)
	task.delay(QUERY_DELAY, function()
		claimRemote:FireServer({ Action = "Query" })
	end)
end

return OfflineTrainingController
