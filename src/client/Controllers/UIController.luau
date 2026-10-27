--!strict
-- StarterPlayerScripts/Client/Controllers/UIController.luau
-- Every screen from Section 29 Step 6, built in code (nothing needs to exist in StarterGui):
--   * HUD: Hunter Level / HP / XP, currencies, run banner (room, objective, Secured vs At-Risk loot), Ability 1
--     cooldown, Rift Combo, Rift Surge timer and Notify toasts.
--   * 3/4-card Upgrade modal (UpgradeOffer / UpgradeChosen): click or press 1-4, Reroll, Banish mode.
--   * Rift Anchor modal (RunStateChanged "Anchor"): Extract vs Push Deeper with the decision timer.
--   * Rift Collapse defeat screen (Section 20): Accept, Anchor Token options and the three Robux recoveries.
--   * Town Hub panels (OpenStation): Rift Gate world / corruption picker, Ascension Pedestal (rebirth), Spark
--     Sanctum (Ascension Shop) and the Rift Shrine store.
-- The client is display-only: every button fires a validated remote, and the server's replies (ProfileUpdated,
-- RunStateChanged, UpgradeOffer, Notify) are what change the screen. Robux buttons send RequestPurchase { Kind, Key }
-- and the server picks the product id. A UIScale per layer keeps the 1280x720 layout readable on phones.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AscensionShopConfig = require(Shared:WaitForChild("AscensionShopConfig"))
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RoomAsciiTemplates = require(Shared:WaitForChild("RoomAsciiTemplates"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))

type Payload = { [string]: any }
type Bar = { Fill: Frame, Label: TextLabel }

local UIController = {}

local player = Players.LocalPlayer

local REF_WIDTH, REF_HEIGHT = 1280, 720
local MIN_SCALE, MAX_SCALE = 0.55, 1.25
local TOAST_SECONDS = 3.5
local MAX_TOASTS = 4
local UPDATE_INTERVAL = 0.1
local MAX_WORLDS = 8
local CARD_WIDTH = 180
local CARD_GAP = 12
local STATION_REFRESH_DELAY = 0.3 -- coalesces ProfileUpdated bursts into one GetStationData call
local CHOICE_RETRY_SECONDS = 2 -- defeat buttons re-enable if the server rejected the choice

local COLORS = {
	Panel = Color3.fromRGB(22, 20, 36),
	PanelLight = Color3.fromRGB(40, 36, 62),
	Stroke = Color3.fromRGB(110, 80, 170),
	Text = Color3.fromRGB(238, 236, 248),
	Muted = Color3.fromRGB(165, 160, 190),
	Accent = Color3.fromRGB(150, 80, 230),
	Gold = Color3.fromRGB(255, 210, 90),
	Good = Color3.fromRGB(60, 180, 110),
	Bad = Color3.fromRGB(215, 65, 90),
	Robux = Color3.fromRGB(0, 150, 95),
	HP = Color3.fromRGB(230, 65, 85),
	XP = Color3.fromRGB(80, 180, 255),
	Disabled = Color3.fromRGB(70, 68, 86),
}

local TIER_NAMES: { [number]: string } = {
	[1] = "Initiate Ascendant",
	[2] = "Rift Weaver",
	[3] = "Sovereign of the Rift",
	[4] = "Transcendent",
}

local LEAVE_MESSAGES: { [string]: string } = {
	Extract = "🏁 Extracted safely!",
	Insured = "🛡️ Insured & extracted!",
	Defeat = "💀 The rift collapsed.",
	RoomError = "⚠️ The run ended early (room error).",
}

-- Left-edge buttons shown in town (buildTownMenu); each opens that station's panel from anywhere.
local TOWN_MENU: { { Station: string, Label: string } } = {
	{ Station = "RiftShrine", Label = "Shop" },
	{ Station = "SparkSanctum", Label = "Ascend" },
	{ Station = "AscensionPedestal", Label = "Rebirth" },
}

local SHRINE_PRODUCTS = { "RiftSurge", "SuperchargedRunToken", "RerollPack5", "KeepEverythingSeal", "StarForceSafeguardPack" }
local SHRINE_PASSES = {
	"TrueAscendant", "DoubleXP", "DoubleDust", "VIPArchitect", "BanishPass", "VaultInsurance", "RelicVaultKey",
	"ExtraLinkSlots",
}
local SHOP_BLURBS: { [string]: string } = {
	RiftSurge = "x1.5 Hunter XP & Rift Dust for the whole server (15 min, stacks)",
	SuperchargedRunToken = "Your next run pays x2 Rift Dust",
	RerollPack5 = "+5 Upgrade Rerolls, used after your free ones",
	KeepEverythingSeal = "One Rebirth that keeps Dust, Worlds & Weapons",
	StarForceSafeguardPack = "3 Star-Force safeguards for the Star-Forge",
	TrueAscendant = "Every Rebirth keeps everything (+2 bonus Sparks)",
	DoubleXP = "Permanent x2 Hunter XP",
	DoubleDust = "Permanent x2 Rift Dust",
	VIPArchitect = "A 4th card in every Upgrade offer",
	BanishPass = "Banish unwanted upgrades for the rest of the run",
	VaultInsurance = "Keep more Unsecured loot when defeated",
	RelicVaultKey = "Start runs with an equipped Relic",
	ExtraLinkSlots = "+2 Hunter Legion Link Skill slots",
}

local LABEL_DEFAULTS: Payload = {
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextColor3 = COLORS.Text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	RichText = true,
}

local NUMBER_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

-- Remotes
local upgradeChosenRemote: RemoteEvent
local anchorRemote: RemoteEvent
local defeatRemote: RemoteEvent
local rebirthRemote: RemoteEvent
local ascensionPurchaseRemote: RemoteEvent
local ascensionRespecRemote: RemoteEvent
local purchaseRemote: RemoteEvent
local startRunFunction: RemoteFunction
local stationDataFunction: RemoteFunction

-- Server state mirrors (display only)
local profile: Payload? = nil
local runState: Payload? = nil
local liveLevel = 1
local liveXP = 0

local scaleObjects: { UIScale } = {}

-- HUD
local hpBar: Bar
local xpBar: Bar
local levelLabel: TextLabel
local currencyLabels: { [string]: TextLabel } = {}
local bannerTitle: TextLabel
local bannerObjective: TextLabel
local bannerLoot: TextLabel
local abilityLabel: TextLabel
local comboLabel: TextLabel
local surgeLabel: TextLabel
local toastList: Frame
local toasts: { TextLabel } = {}
local toastOrder = 0
local healthConnections: { RBXScriptConnection } = {}

-- Upgrade modal
local upgradeFrame: Frame
local upgradeTitle: TextLabel
local cardRow: Frame
local rerollButton: TextButton
local banishButton: TextButton
local offerId = 0
local offerCards: { Payload } = {}
local offerRerolls = 0
local offerBanishes = 0
local banishMode = false

-- Anchor modal
local anchorFrame: Frame
local anchorTitle: TextLabel
local anchorBody: TextLabel
local anchorTimer: TextLabel
local anchorButtons: Frame
local anchorDeadline: number? = nil

-- Defeat screen
local defeatGui: ScreenGui
local defeatTimer: TextLabel
local defeatSafe: TextLabel
local defeatRisk: TextLabel
local defeatButtons: { [string]: TextButton } = {}
local defeatDeadline: number? = nil
local defeatOpen = false

-- Station panels
local stationFrame: Frame
local townMenu: Frame
local stationTitle: TextLabel
local stationContent: ScrollingFrame
local openStation: string? = nil
local stationData: any = nil
local stationRefreshToken = 0
local selectedWorld = 1
local selectedCorruption = 0
local startingRun = false
local respecArmed = false

-- Helpers --------------------------------------------------------------------------------------------------------

local function create(className: string, props: Payload, parent: Instance?): any
	local instance = (Instance.new :: any)(className)
	for key, value in props do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function merged(defaults: Payload, props: Payload): Payload
	local result = table.clone(defaults)
	for key, value in props do
		result[key] = value
	end
	return result
end

local function round(parent: Instance, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function outline(parent: Instance, color: Color3, thickness: number)
	create("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function pad(parent: Instance, px: number)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	}, parent)
end

local function list(parent: Instance, direction: Enum.FillDirection, spacing: number): UIListLayout
	return create("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, spacing),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

local function newLabel(parent: Instance, props: Payload): TextLabel
	return create("TextLabel", merged(LABEL_DEFAULTS, props), parent)
end

local function newPanel(parent: Instance, props: Payload): Frame
	local frame: Frame = create("Frame", merged({ BackgroundColor3 = COLORS.Panel, BackgroundTransparency = 0.1 }, props), parent)
	round(frame, 10)
	outline(frame, COLORS.Stroke, 1.5)
	return frame
end

local function setEnabled(button: TextButton, enabled: boolean, color: Color3)
	button:SetAttribute("Enabled", enabled)
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then color else COLORS.Disabled
	button.TextTransparency = if enabled then 0 else 0.4
end

local function newButton(parent: Instance, label: string, color: Color3, onClick: () -> (), props: Payload?): TextButton
	local button: TextButton = create("TextButton", merged({
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		Text = label,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 15,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.fromOffset(160, 40),
	}, props or {}), parent)
	round(button, 8)
	button.Activated:Connect(function()
		if button:GetAttribute("Enabled") ~= false then
			onClick()
		end
	end)
	return button
end

local function newBar(parent: Instance, color: Color3, order: number): Bar
	local back: Frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = Color3.fromRGB(10, 8, 18),
		LayoutOrder = order,
	}, parent)
	round(back, 5)
	local fill: Frame = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color }, back)
	round(fill, 5)
	local label = newLabel(back, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		ZIndex = 2,
	})
	return { Fill = fill, Label = label }
end

local function setBar(bar: Bar, ratio: number, label: string)
	bar.Fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	bar.Label.Text = label
end

local function clearGuiChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function newLayer(name: string, displayOrder: number, ignoreInset: boolean): ScreenGui
	local gui: ScreenGui = create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder,
		IgnoreGuiInset = ignoreInset,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	table.insert(scaleObjects, create("UIScale", {}, gui))
	return gui
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local scale = math.clamp(math.min(viewport.X / REF_WIDTH, viewport.Y / REF_HEIGHT), MIN_SCALE, MAX_SCALE)
	for _, uiScale in scaleObjects do
		uiScale.Scale = scale
	end
end

local function focusFirstButton(container: Instance)
	if not UserInputService.GamepadEnabled then
		return
	end
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Visible and descendant:GetAttribute("Enabled") ~= false then
			GuiService.SelectedObject = descendant
			return
		end
	end
end

-- Formatting -----------------------------------------------------------------------------------------------------

local function formatNumber(value: number): string
	local n = math.floor(value)
	local magnitude = math.abs(n)
	if magnitude >= 1e9 then
		return ("%.2fB"):format(n / 1e9)
	elseif magnitude >= 1e6 then
		return ("%.2fM"):format(n / 1e6)
	end
	local digits = tostring(magnitude):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if digits:sub(1, 1) == "," then
		digits = digits:sub(2)
	end
	return (if n < 0 then "-" else "") .. digits
end

local function formatTime(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

local function toRoman(n: number): string
	local values = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }
	local numerals = { "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" }
	local result = ""
	for index, value in values do
		while n >= value do
			result ..= numerals[index]
			n -= value
		end
	end
	return result
end

local function currencyIcon(key: string): string
	local info = AssetRegistry.Currencies[key]
	return if info then info.FallbackIcon else "❔"
end

local function bagText(bag: any): string
	if type(bag) ~= "table" then
		return "nothing"
	end
	local parts = { ("%s %s"):format(currencyIcon("RiftDust"), formatNumber(tonumber(bag.Dust) or 0)) }
	if (tonumber(bag.BossCores) or 0) > 0 then
		table.insert(parts, ("%s %s"):format(currencyIcon("BossCores"), formatNumber(bag.BossCores)))
	end
	if (tonumber(bag.RelicShards) or 0) > 0 then
		table.insert(parts, ("%s %s"):format(currencyIcon("RelicShards"), formatNumber(bag.RelicShards)))
	end
	return table.concat(parts, "   ")
end

local function inRun(): boolean
	return runState ~= nil
end

local function requestPurchase(kind: "Product" | "Pass", key: string)
	purchaseRemote:FireServer({ Kind = kind, Key = key })
end

-- Toasts ---------------------------------------------------------------------------------------------------------

local function toast(message: string, color: Color3?)
	toastOrder += 1
	local label = newLabel(toastList, {
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.15,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = message,
		LayoutOrder = toastOrder,
	})
	round(label, 8)
	pad(label, 7)
	outline(label, color or COLORS.Stroke, 1.5)
	table.insert(toasts, label)
	while #toasts > MAX_TOASTS do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(TOAST_SECONDS, function()
		if not label.Parent then
			return
		end
		local fade = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade.Completed:Connect(function()
			local index = table.find(toasts, label)
			if index then
				table.remove(toasts, index)
			end
			label:Destroy()
		end)
		fade:Play()
	end)
end

-- HUD ------------------------------------------------------------------------------------------------------------

local function refreshProfileHud()
	local data = profile
	if not data then
		return
	end
	local rebirthTier = tonumber(data.RebirthTier) or 0
	local weapon = WeaponConfig.Weapons[data.EquippedWeapon]
	levelLabel.Text = ("<b>Lv. %d</b>%s   <font color='#%s'>%s</font>"):format(
		liveLevel,
		if rebirthTier > 0 then ("  ·  Rebirth %s"):format(toRoman(rebirthTier)) else "",
		COLORS.Muted:ToHex(),
		if weapon then weapon.Name else "")

	local levelCap = FormulaEngine.GetRebirthInfo(rebirthTier + 1).ReqLevel
	if liveLevel >= levelCap then
		setBar(xpBar, 1, "MAX LEVEL — Rebirth at the Ascension Pedestal!")
	else
		local needed = FormulaEngine.GetHunterXPRequired(liveLevel)
		setBar(xpBar, liveXP / needed, ("XP %s / %s"):format(formatNumber(liveXP), formatNumber(needed)))
	end

	local vault = tonumber(data.ProtectedDustVault) or 0
	currencyLabels.RiftDust.Text = formatNumber(data.RiftDust or 0)
		.. (if vault > 0 then (" <font color='#%s'>(+%s vault)</font>"):format(COLORS.Muted:ToHex(), formatNumber(vault)) else "")
	currencyLabels.BossCores.Text = formatNumber(data.BossCores or 0)
	currencyLabels.RelicShards.Text = formatNumber(data.RelicShards or 0)
	currencyLabels.RebirthSpark.Text = formatNumber(data.RebirthSparksAvailable or 0)
	currencyLabels.AnchorToken.Text = formatNumber(data.AnchorTokens or 0)
end

local function refreshRunBanner()
	local state = runState
	if not state then
		bannerTitle.Text = "🏠 <b>Haven Outpost</b>"
		bannerObjective.Text = "Walk to the Central Rift Gate 🌀 to open a portal"
		bannerLoot.Visible = false
		return
	end
	local world = RoomAsciiTemplates.GetWorld(tonumber(state.World) or 1)
	bannerTitle.Text = ("<b>%s</b>  ·  Corruption %d  ·  <b>Room %d</b>%s"):format(
		if world then world.Name else "Rift", tonumber(state.Corruption) or 0, tonumber(state.Room) or 1,
		if state.RoomName ~= "" then ": " .. tostring(state.RoomName) else "")

	local total = tonumber(state.EnemiesTotal) or 0
	local objective = tostring(state.Objective or ""):gsub("{N}", tostring(total))
	if state.ExitOpen then
		bannerObjective.Text = "✅ Room clear — head for the exit ➜"
	elseif total > 0 then
		bannerObjective.Text = ("%s  <font color='#%s'>(%d left)</font>"):format(objective, COLORS.Gold:ToHex(),
			tonumber(state.EnemiesLeft) or 0)
	else
		bannerObjective.Text = objective
	end
	bannerLoot.Visible = true
	bannerLoot.Text = ("🔒 Secured %s      <font color='#%s'>⚠️ At risk %s</font>"):format(
		bagText(state.Secured), COLORS.Gold:ToHex(), bagText(state.Unsecured))
end

local function bindCharacter(character: Model)
	for _, connection in healthConnections do
		connection:Disconnect()
	end
	table.clear(healthConnections)
	local found = character:WaitForChild("Humanoid", 10)
	if not found or not found:IsA("Humanoid") then
		return
	end
	local humanoid = found
	local function update()
		setBar(hpBar, humanoid.Health / math.max(humanoid.MaxHealth, 1), ("HP %s / %s"):format(
			formatNumber(math.ceil(humanoid.Health)), formatNumber(humanoid.MaxHealth)))
	end
	table.insert(healthConnections, humanoid.HealthChanged:Connect(update))
	table.insert(healthConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update))
	update()
end

local function buildHud()
	local gui = newLayer("RiftHUD", 10, false)

	local status = newPanel(gui, { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y })
	pad(status, 8)
	list(status, Enum.FillDirection.Vertical, 5)
	levelLabel = newLabel(status, { Size = UDim2.new(1, 0, 0, 18), TextSize = 16, LayoutOrder = 1 })
	hpBar = newBar(status, COLORS.HP, 2)
	xpBar = newBar(status, COLORS.XP, 3)

	local wallet: Frame = create("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
	local walletLayout = list(wallet, Enum.FillDirection.Vertical, 4)
	walletLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	for order, key in { "RiftDust", "BossCores", "RelicShards", "RebirthSpark", "AnchorToken" } do
		local info = AssetRegistry.Currencies[key]
		local pill = newPanel(wallet, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = order })
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, pill)
		local row = list(pill, Enum.FillDirection.Horizontal, 6)
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		newLabel(pill, { Size = UDim2.fromOffset(20, 20), Text = currencyIcon(key), TextSize = 16, LayoutOrder = 1 })
		currencyLabels[key] = newLabel(pill, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
			Text = "0", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = info.Color:Lerp(Color3.new(1, 1, 1), 0.45),
			LayoutOrder = 2 })
	end

	local banner = newPanel(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(560, 0), AutomaticSize = Enum.AutomaticSize.Y })
	pad(banner, 8)
	local bannerLayout = list(banner, Enum.FillDirection.Vertical, 3)
	bannerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	bannerTitle = newLabel(banner, { Size = UDim2.new(1, 0, 0, 20), TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	bannerObjective = newLabel(banner, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
	bannerLoot = newLabel(banner, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold, LayoutOrder = 3 })
	surgeLabel = newLabel(banner, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = Color3.fromRGB(120, 255, 200),
		TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold, LayoutOrder = 4, Visible = false })

	toastList = create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 },
		newLayer("RiftToasts", 50, false))
	local toastLayout = list(toastList, Enum.FillDirection.Vertical, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	abilityLabel = newLabel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.15,
		BackgroundColor3 = COLORS.Panel, Font = Enum.Font.GothamBold, TextSize = 15, Visible = false })
	round(abilityLabel, 8)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, abilityLabel)

	comboLabel = newLabel(gui, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.42, 0),
		Size = UDim2.fromOffset(220, 40), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBlack,
		TextSize = 30, TextColor3 = COLORS.Gold, TextStrokeTransparency = 0.3, Visible = false })

	refreshRunBanner()
end

-- Upgrade modal --------------------------------------------------------------------------------------------------

local function sendUpgrade(action: string, index: number?)
	if offerId > 0 then
		upgradeChosenRemote:FireServer({ OfferId = offerId, Action = action, Index = index })
	end
end

local function chooseCard(index: number)
	if index <= #offerCards then
		sendUpgrade(if banishMode then "Banish" else "Pick", index)
	end
end

local function renderOffer()
	clearGuiChildren(cardRow)
	local count = #offerCards
	upgradeTitle.Text = if banishMode
		then ("<font color='#%s'>🚫 Choose a card to BANISH for this run</font>"):format(COLORS.Bad:ToHex())
		else "⬆️ <b>Choose an Upgrade</b>"
	upgradeFrame.Size = UDim2.fromOffset(count * CARD_WIDTH + (count - 1) * CARD_GAP + 32, 360)

	for index, card in offerCards do
		local style = AssetRegistry.GetRarityStyle(card.Rarity)
		local button: TextButton = create("TextButton", {
			Size = UDim2.new(0, CARD_WIDTH, 1, 0),
			BackgroundColor3 = COLORS.PanelLight,
			AutoButtonColor = true,
			Text = "",
			LayoutOrder = index,
		}, cardRow)
		round(button, 10)
		outline(button, if banishMode then COLORS.Bad else style.Color, 3)
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(style.Glow:Lerp(COLORS.PanelLight, 0.35), COLORS.PanelLight),
			Transparency = NumberSequence.new(0, 0),
		}, button)
		pad(button, 10)
		local layout = list(button, Enum.FillDirection.Vertical, 6)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

		local stacks = tonumber(card.Stacks) or 0
		local maxStacks = tonumber(card.MaxStacks) or 1
		newLabel(button, { Size = UDim2.new(1, 0, 0, 16), Text = ("[%d]"):format(index), TextColor3 = COLORS.Muted,
			TextSize = 12, LayoutOrder = 1, Visible = UserInputService.KeyboardEnabled })
		newLabel(button, { Size = UDim2.new(1, 0, 0, 44), Text = tostring(card.Icon), TextSize = 38,
			TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
		newLabel(button, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = tostring(card.Name),
			Font = Enum.Font.GothamBold, TextSize = 17, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 3 })
		newLabel(button, { Size = UDim2.new(1, 0, 0, 16), TextColor3 = style.Color, Font = Enum.Font.GothamBold,
			TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 4,
			Text = tostring(card.Rarity):upper() .. (if maxStacks > 1 then ("  ·  %d/%d"):format(stacks, maxStacks) else "") })
		newLabel(button, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = tostring(card.Desc),
			TextColor3 = COLORS.Text, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 5 })

		button.Activated:Connect(function()
			chooseCard(index)
		end)
	end

	rerollButton.Text = ("🎲 Reroll (%d)"):format(offerRerolls)
	setEnabled(rerollButton, offerRerolls > 0 and not banishMode, COLORS.Accent)
	banishButton.Visible = offerBanishes > 0
	banishButton.Text = if banishMode then "Cancel Banish" else ("🚫 Banish (%d)"):format(offerBanishes)
	upgradeFrame.Visible = true
	focusFirstButton(cardRow)
end

local function onUpgradeOffer(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.Kind == "Offer" and type(payload.Cards) == "table" then
		if payload.OfferId ~= offerId then
			banishMode = false
		end
		offerId = tonumber(payload.OfferId) or 0
		offerCards = payload.Cards
		offerRerolls = tonumber(payload.Rerolls) or 0
		offerBanishes = tonumber(payload.Banishes) or 0
		if offerBanishes <= 0 then
			banishMode = false
		end
		renderOffer()
	elseif payload.OfferId == 0 or payload.OfferId == offerId then
		offerId = 0
		offerCards = {}
		banishMode = false
		upgradeFrame.Visible = false
	end
end

local function buildUpgradeModal()
	local gui = newLayer("RiftUpgrade", 20, false)
	upgradeFrame = newPanel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(600, 360), Visible = false })
	pad(upgradeFrame, 16)
	upgradeTitle = newLabel(upgradeFrame, { Size = UDim2.new(1, 0, 0, 24), TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center })
	cardRow = create("Frame", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -86),
		BackgroundTransparency = 1 }, upgradeFrame)
	list(cardRow, Enum.FillDirection.Horizontal, CARD_GAP).HorizontalAlignment = Enum.HorizontalAlignment.Center

	local footer: Frame = create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, upgradeFrame)
	list(footer, Enum.FillDirection.Horizontal, 12).HorizontalAlignment = Enum.HorizontalAlignment.Center
	rerollButton = newButton(footer, "Reroll", COLORS.Accent, function()
		sendUpgrade("Reroll", nil)
	end, { LayoutOrder = 1 })
	banishButton = newButton(footer, "Banish", COLORS.Bad, function()
		banishMode = not banishMode
		renderOffer()
	end, { LayoutOrder = 2 })

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or offerId == 0 or not upgradeFrame.Visible then
			return
		end
		local index = NUMBER_KEYS[input.KeyCode]
		if index then
			chooseCard(index)
		end
	end)
end

-- Rift Anchor modal ----------------------------------------------------------------------------------------------

local function closeAnchor()
	anchorDeadline = nil
	anchorFrame.Visible = false
end

local function showAnchor(state: Payload)
	local room = tonumber(state.Room) or 5
	anchorTitle.Text = ("⚓ <b>RIFT ANCHOR</b> — Room %d cleared"):format(room)
	anchorBody.Text = ("Your loot is now safe:  <b>%s</b>\n<font color='#%s'>Push deeper for bigger rewards — new loot stays at risk until the next Anchor (Room %d).</font>"):format(
		bagText(state.Secured), COLORS.Muted:ToHex(), room + 5)
	anchorDeadline = os.clock() + (tonumber(state.DecisionSeconds) or 45)
	anchorButtons.Visible = true
	for _, child in anchorButtons:GetChildren() do
		if child:IsA("TextButton") then
			setEnabled(child, true, child:GetAttribute("Color") :: Color3)
		end
	end
	anchorFrame.Visible = true
	focusFirstButton(anchorButtons)
end

local function sendAnchor(decision: "Extract" | "Push")
	for _, child in anchorButtons:GetChildren() do
		if child:IsA("TextButton") then
			setEnabled(child, false, COLORS.Disabled)
		end
	end
	anchorRemote:FireServer(decision)
end

local function buildAnchorModal()
	local gui = newLayer("RiftAnchor", 25, false)
	anchorFrame = newPanel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(520, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
	pad(anchorFrame, 14)
	local layout = list(anchorFrame, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	anchorTitle = newLabel(anchorFrame, { Size = UDim2.new(1, 0, 0, 24), TextSize = 20, TextColor3 = COLORS.Gold,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	anchorBody = newLabel(anchorFrame, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
	anchorTimer = newLabel(anchorFrame, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
	anchorButtons = create("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 4 },
		anchorFrame)
	list(anchorButtons, Enum.FillDirection.Horizontal, 14).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local extract = newButton(anchorButtons, "🏁 Extract to Town", COLORS.Good, function()
		sendAnchor("Extract")
	end, { Size = UDim2.fromOffset(210, 44), LayoutOrder = 1 })
	extract:SetAttribute("Color", COLORS.Good)
	local push = newButton(anchorButtons, "⚔️ Push Deeper", COLORS.Accent, function()
		sendAnchor("Push")
	end, { Size = UDim2.fromOffset(210, 44), LayoutOrder = 2 })
	push:SetAttribute("Color", COLORS.Accent)
end

-- Rift Collapse (defeat) screen ----------------------------------------------------------------------------------

local function closeDefeat()
	defeatOpen = false
	defeatDeadline = nil
	defeatGui.Enabled = false
end

local DEFEAT_COLORS: { [string]: Color3 } = {
	Accept = COLORS.Disabled:Lerp(COLORS.Muted, 0.4),
	TokenRewind = Color3.fromRGB(30, 150, 140),
	TokenInsure = Color3.fromRGB(30, 150, 140),
	RiftRevive = COLORS.Robux,
	CheckpointRewind = COLORS.Robux,
	InsureExtract = COLORS.Robux,
}

local function lockDefeatButtons()
	for key, button in defeatButtons do
		setEnabled(button, false, DEFEAT_COLORS[key])
	end
	-- If the server rejected the choice it says why in a toast; let the player try another option.
	task.delay(CHOICE_RETRY_SECONDS, function()
		if defeatOpen then
			for key, button in defeatButtons do
				setEnabled(button, button:GetAttribute("Allowed") == true, DEFEAT_COLORS[key])
			end
		end
	end)
end

local function showDefeat(state: Payload)
	local tokens = tonumber(state.AnchorTokens) or 0
	local canRewind = state.CanRewind == true
	local rewindRoom = tonumber(state.RewindToRoom) or 1
	defeatSafe.Text = ("🔒 <b>SAFE</b> (secured)\n%s"):format(bagText(state.Secured))
	defeatRisk.Text = ("⚠️ <b>AT RISK</b> (unsecured)\n%s\n<font color='#%s'>Accepting keeps: %s</font>"):format(
		bagText(state.Unsecured), COLORS.Muted:ToHex(), bagText(state.KeptIfAccepted))

	local products = MonetizationConfig.Products
	local options: { [string]: { Text: string, Allowed: boolean, Visible: boolean } } = {
		Accept = { Text = "Accept Defeat — return to town  ·  Free", Allowed = true, Visible = true },
		TokenRewind = { Text = ("⏳ Rewind to Room %d  ·  1 Anchor Token (have %d)"):format(rewindRoom, tokens),
			Allowed = tokens > 0, Visible = canRewind },
		TokenInsure = { Text = ("⏳ Insure & Extract  ·  1 Anchor Token (have %d)"):format(tokens),
			Allowed = tokens > 0, Visible = true },
		RiftRevive = { Text = ("💖 Rift Revive — revive here, 4s shield + full Ultimate  ·  R$ %d"):format(
			products.RiftRevive.Price), Allowed = true, Visible = true },
		CheckpointRewind = { Text = ("⏪ Checkpoint Rewind — back to Room %d, build & loot intact  ·  R$ %d"):format(
			rewindRoom, products.CheckpointRewind.Price), Allowed = true, Visible = canRewind },
		InsureExtract = { Text = ("🛡️ Insure & Extract Now — keep 100%% of at-risk loot  ·  R$ %d"):format(
			products.InsureExtract.Price), Allowed = true, Visible = true },
	}
	for key, option in options do
		local button = defeatButtons[key]
		button.Text = option.Text
		button.Visible = option.Visible
		button:SetAttribute("Allowed", option.Allowed)
		setEnabled(button, option.Allowed, DEFEAT_COLORS[key])
	end

	defeatDeadline = os.clock() + (tonumber(state.DecisionSeconds) or 60)
	defeatOpen = true
	defeatGui.Enabled = true
	closeAnchor()
	focusFirstButton(defeatGui)
end

local function buildDefeatScreen()
	defeatGui = newLayer("RiftCollapse", 40, true)
	defeatGui.Enabled = false
	create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		Active = true }, defeatGui)

	local panel = newPanel(defeatGui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.02 })
	pad(panel, 16)
	local layout = list(panel, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	newLabel(panel, { Size = UDim2.new(1, 0, 0, 34), Text = "💀 RIFT COLLAPSE", Font = Enum.Font.GothamBlack,
		TextSize = 30, TextColor3 = COLORS.Bad, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	defeatTimer = newLabel(panel, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })

	local columns: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 3 }, panel)
	list(columns, Enum.FillDirection.Horizontal, 10)
	local function column(order: number, color: Color3): TextLabel
		local label = newLabel(columns, { Size = UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 0, BackgroundColor3 = COLORS.PanelLight, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center, TextSize = 15, LayoutOrder = order })
		round(label, 8)
		pad(label, 8)
		outline(label, color, 1.5)
		return label
	end
	defeatSafe = column(1, COLORS.Good)
	defeatRisk = column(2, COLORS.Gold)

	local buttons: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 4 }, panel)
	list(buttons, Enum.FillDirection.Vertical, 6)
	local order = { "Accept", "TokenRewind", "TokenInsure", "RiftRevive", "CheckpointRewind", "InsureExtract" }
	for index, key in order do
		defeatButtons[key] = newButton(buttons, key, DEFEAT_COLORS[key], function()
			if MonetizationConfig.DefeatProducts[key] then
				-- The server holds the defeat open while the Robux prompt is up, so stop the local countdown.
				defeatDeadline = nil
				defeatTimer.Text = "Purchase window open…"
				requestPurchase("Product", key)
			else
				defeatRemote:FireServer(key)
			end
			lockDefeatButtons()
		end, { Size = UDim2.new(1, 0, 0, 40), TextSize = 14, LayoutOrder = index })
	end
end

-- Town Hub station panels ----------------------------------------------------------------------------------------

local function section(order: number, label: string): TextLabel
	return newLabel(stationContent, { Size = UDim2.new(1, 0, 0, 24), Text = label, Font = Enum.Font.GothamBold,
		TextSize = 16, TextColor3 = COLORS.Gold, LayoutOrder = order })
end

local function paragraph(order: number, label: string, color: Color3?): TextLabel
	return newLabel(stationContent, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = label,
		TextWrapped = true, TextColor3 = color or COLORS.Text, TextSize = 14, LayoutOrder = order })
end

local function itemRow(order: number, title: string, desc: string, buttonText: string, buttonColor: Color3,
	enabled: boolean, onClick: () -> ()): TextButton
	local frame: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = COLORS.PanelLight,
		LayoutOrder = order }, stationContent)
	round(frame, 8)
	pad(frame, 8)
	newLabel(frame, { Size = UDim2.new(1, -160, 0, 20), Text = title, Font = Enum.Font.GothamBold, TextSize = 15 })
	newLabel(frame, { Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, -160, 0, 28), Text = desc,
		TextColor3 = COLORS.Muted, TextSize = 12, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local button = newButton(frame, buttonText, buttonColor, onClick, { AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(150, 38), TextSize = 13 })
	setEnabled(button, enabled, buttonColor)
	return button
end

local function unlockedTierFor(world: number): number?
	local unlocked = profile and profile.UnlockedWorlds
	if type(unlocked) ~= "table" then
		return nil
	end
	local value = unlocked[world] or unlocked[tostring(world)]
	return if type(value) == "number" then value else nil
end

local function closeStation()
	openStation = nil
	stationData = nil
	respecArmed = false
	stationFrame.Visible = false
end

local function startRun()
	if startingRun then
		return
	end
	startingRun = true
	local world, corruption = selectedWorld, selectedCorruption
	task.spawn(function()
		local ok, result = pcall(function(): any
			return startRunFunction:InvokeServer(world, corruption)
		end)
		startingRun = false
		if not ok or type(result) ~= "table" then
			toast("The Rift Gate did not respond. Try again.", COLORS.Bad)
		elseif result.Success then
			closeStation()
		else
			toast(tostring(result.Message), COLORS.Bad)
		end
	end)
end

local renderStation: () -> ()

local function renderRiftGate()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	section(nextOrder(), "Choose a World")
	for world = 1, MAX_WORLDS do
		local info = RoomAsciiTemplates.GetWorld(world)
		if info then
			local tier = unlockedTierFor(world)
			local selected = world == selectedWorld
			local label = if tier
				then ("%s  World %d · %s   (Corruption 0-%d)"):format(if selected then "▶" else "  ", world, info.Name, tier)
				else ("🔒 World %d · %s — clear World %d's boss to unlock"):format(world, info.Name, world - 1)
			local color = if selected then COLORS.Accent else COLORS.PanelLight
			local button = newButton(stationContent, label, color, function()
				selectedWorld = world
				selectedCorruption = math.min(selectedCorruption, tier or 0)
				renderStation()
			end, { Size = UDim2.new(1, 0, 0, 38), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = nextOrder() })
			setEnabled(button, tier ~= nil, color)
		end
	end

	local maxTier = unlockedTierFor(selectedWorld) or 0
	selectedCorruption = math.clamp(selectedCorruption, 0, maxTier)
	section(nextOrder(), "Corruption Tier")
	local stepper: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1,
		LayoutOrder = nextOrder() }, stationContent)
	local stepLayout = list(stepper, Enum.FillDirection.Horizontal, 8)
	stepLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local function stepButton(text: string, delta: number, layoutOrder: number)
		local target = math.clamp(selectedCorruption + delta, 0, maxTier)
		local button = newButton(stepper, text, COLORS.PanelLight, function()
			selectedCorruption = target
			renderStation()
		end, { Size = UDim2.fromOffset(48, 36), LayoutOrder = layoutOrder })
		setEnabled(button, target ~= selectedCorruption, COLORS.PanelLight)
	end
	stepButton("-10", -10, 1)
	stepButton("-1", -1, 2)
	newLabel(stepper, { Size = UDim2.fromOffset(250, 36), TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold, TextSize = 16, LayoutOrder = 3,
		Text = ("Tier %d  ·  <font color='#%s'>x%.2f rewards</font>"):format(selectedCorruption, COLORS.Gold:ToHex(),
			FormulaEngine.GetCorruptionEcoMult(selectedCorruption)) })
	stepButton("+1", 1, 4)
	stepButton("+10", 10, 5)

	local data = profile
	if data and (tonumber(data.SuperchargedTokens) or 0) > 0 then
		paragraph(nextOrder(), ("⚡ A Supercharged Run Token will be spent: x%d Rift Dust this run (%d left)."):format(
			MonetizationConfig.SUPERCHARGE_DUST_MULT, data.SuperchargedTokens), Color3.fromRGB(120, 255, 200))
	end
	paragraph(nextOrder(), "Rift Anchors on Rooms 5, 10, 15… secure your loot. Push past them for bigger multipliers.",
		COLORS.Muted)
	local start = newButton(stationContent, if startingRun then "Opening…" else "🌀 Open Portal", COLORS.Accent,
		startRun, { Size = UDim2.new(1, 0, 0, 46), TextSize = 18, LayoutOrder = nextOrder() })
	setEnabled(start, unlockedTierFor(selectedWorld) ~= nil, COLORS.Accent)
end

local function renderPedestal()
	local preview = stationData
	if type(preview) ~= "table" then
		paragraph(1, "Loading…", COLORS.Muted)
		return
	end
	local current = tonumber(preview.CurrentTier) or 0
	local nextTier = tonumber(preview.NextTier) or (current + 1)
	local level = tonumber(preview.HunterLevel) or 1
	local reqLevel = tonumber(preview.ReqLevel) or 50
	local eligible = preview.Eligible == true

	section(1, ("Rebirth %s  ➜  Rebirth %s"):format(if current > 0 then toRoman(current) else "—", toRoman(nextTier)))
	local progress = newBar(stationContent, if eligible then COLORS.Good else COLORS.XP, 2)
	setBar(progress, level / reqLevel, ("Hunter Level %d / %d%s"):format(level, reqLevel, if eligible then "  ✔" else ""))
	paragraph(3, ("Rewards:  <b>x%.2f</b> Damage & HP   ·   <b>x%.2f</b> Rift Dust & XP   ·   <b>+%d</b> %s Rebirth Sparks"):format(
		tonumber(preview.NextDmgMult) or 1, tonumber(preview.NextEcoMult) or 1, tonumber(preview.SparksGain) or 0,
		currencyIcon("RebirthSpark")))

	section(4, "Standard Rebirth (Free)")
	paragraph(5, "Hunter Level resets to 1. Unspent Rift Dust is consumed (your Protected Vault is safe), Worlds 2-8 re-lock and extra weapons need a reactivation fee. Relics, Mastery, Link Skills, Ascension nodes and Boss Cores are always kept.",
		COLORS.Muted)
	local standard = newButton(stationContent, "✨ Rebirth (Standard)", COLORS.Accent, function()
		rebirthRemote:FireServer({ Mode = "Standard" })
	end, { Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 6 })
	setEnabled(standard, eligible, COLORS.Accent)

	section(7, "Keep Everything Rebirth")
	local seals = tonumber(preview.KeepEverythingSeals) or 0
	paragraph(8, ("Keeps Rift Dust, Worlds and Weapons, banks <b>+%d Legacy levels</b> and pays <b>+%d bonus Sparks</b>. Needs the True Ascendant pass or a Keep Everything Seal (you have %d)."):format(
		tonumber(preview.LegacyGain) or 0, tonumber(preview.KeepBonusSparks) or 0, seals), COLORS.Muted)
	local keep = newButton(stationContent, "👑 Rebirth (Keep Everything)", COLORS.Gold:Lerp(COLORS.Accent, 0.35),
		function()
			rebirthRemote:FireServer({ Mode = "KeepEverything" })
		end, { Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 9 })
	setEnabled(keep, eligible and preview.CanKeepEverything == true, COLORS.Gold:Lerp(COLORS.Accent, 0.35))

	section(10, "Robux")
	local order = 10
	if not eligible then
		order += 1
		itemRow(order, "Instant Rebirth", ("Rebirth now at %d%% progress. The price drops as you level."):format(
			math.floor((tonumber(preview.SkipProgress) or 0) * 100)), ("R$ %d"):format(tonumber(preview.SkipPrice) or 0),
			COLORS.Robux, true, function()
				requestPurchase("Product", "InstantRebirth")
			end)
	end
	local credits = preview.PendingSkipCredits
	if type(credits) == "table" and #credits > 0 then
		order += 1
		paragraph(order, ("⏳ %d Instant Rebirth credit(s) waiting — they apply in town once your progress matches."):format(
			#credits), Color3.fromRGB(120, 255, 200))
	end
	local seal = MonetizationConfig.Products.KeepEverythingSeal
	order += 1
	itemRow(order, seal.Name, SHOP_BLURBS.KeepEverythingSeal, ("R$ %d"):format(seal.Price), COLORS.Robux, true, function()
		requestPurchase("Product", seal.Key)
	end)
	local pass = MonetizationConfig.Passes.TrueAscendant
	order += 1
	itemRow(order, pass.Name, SHOP_BLURBS.TrueAscendant, if preview.HasTrueAscendant then "Owned" else ("R$ %d"):format(pass.Price),
		COLORS.Robux, preview.HasTrueAscendant ~= true, function()
			requestPurchase("Pass", pass.Key)
		end)
end

local function renderSanctum()
	local data = profile
	section(1, ("%s %s Rebirth Sparks available"):format(currencyIcon("RebirthSpark"),
		formatNumber(if data then data.RebirthSparksAvailable or 0 else 0)))
	local nodes = stationData
	if type(nodes) ~= "table" then
		paragraph(2, "Loading…", COLORS.Muted)
		return
	end
	local sparks = if data then tonumber(data.RebirthSparksAvailable) or 0 else 0
	local order = 2
	local lastTier = 0
	for _, state in nodes do
		local node = AscensionShopConfig.GetNode(state.Id)
		if node then
			local tier = if node.FlatCost then -1 else node.Tier -- the infinite sinks get their own heading
			if tier ~= lastTier then
				lastTier = tier
				order += 1
				local required = AscensionShopConfig.TierUnlockRebirth[node.Tier] or 0
				section(order, if tier == -1
					then "Infinite Sinks (Rebirth XI+)"
					else ("Tier %d · %s (Rebirth %s)"):format(tier, TIER_NAMES[tier] or "", toRoman(required)))
			end
			local level = tonumber(state.Level) or 0
			local maxText = if node.FlatCost then "∞" else tostring(node.MaxLevel)
			local cost = tonumber(state.NextCost)
			local buttonText: string, enabled: boolean
			if not state.Unlocked then
				buttonText, enabled = "🔒 Locked", false
			elseif not cost then
				buttonText, enabled = "MAX", false
			else
				buttonText, enabled = ("Buy  ·  %d %s"):format(cost, currencyIcon("RebirthSpark")), sparks >= cost
			end
			order += 1
			itemRow(order, ("%s  <font color='#%s'>Lv. %d/%s</font>"):format(node.Name, COLORS.Muted:ToHex(), level, maxText),
				("%s (%s)"):format(node.Desc, node.EffectPerLevel), buttonText, COLORS.Accent, enabled, function()
					ascensionPurchaseRemote:FireServer(node.Id)
				end)
		end
	end

	order += 1
	section(order, "Respec")
	order += 1
	paragraph(order, "Refund every spent Spark for free and rebuild your tree.", COLORS.Muted)
	order += 1
	newButton(stationContent, if respecArmed then "Click again to confirm respec" else "↺ Respec Ascension Tree",
		if respecArmed then COLORS.Bad else COLORS.PanelLight, function()
			if respecArmed then
				respecArmed = false
				ascensionRespecRemote:FireServer()
			else
				respecArmed = true
			end
			renderStation()
		end, { Size = UDim2.new(1, 0, 0, 40), LayoutOrder = order })
end

local function renderShrine()
	local surge = MonetizationConfig.Products.RiftSurge
	section(1, "🔮 Rift Shrine")
	paragraph(2, ("Trigger a <b>Server Rift Surge</b> and everyone here earns x%.1f Hunter XP & Rift Dust."):format(
		MonetizationConfig.RIFT_SURGE_ECO_MULT), COLORS.Muted)
	local order = 2
	for _, key in SHRINE_PRODUCTS do
		local product = MonetizationConfig.Products[key]
		order += 1
		itemRow(order, product.Name, SHOP_BLURBS[key] or "", ("R$ %d"):format(product.Price), COLORS.Robux, true, function()
			requestPurchase("Product", key)
		end)
	end
	order += 1
	section(order, "Permanent Gamepasses")
	for _, key in SHRINE_PASSES do
		local pass = MonetizationConfig.Passes[key]
		local owned = player:GetAttribute(pass.Attribute) == true
		order += 1
		itemRow(order, pass.Name, SHOP_BLURBS[key] or "", if owned then "Owned" else ("R$ %d"):format(pass.Price),
			COLORS.Robux, not owned, function()
				requestPurchase("Pass", key)
			end)
	end
	if surge.Id == 0 then
		order += 1
		paragraph(order, "Store items go live once their ids are set in MonetizationConfig.", COLORS.Muted)
	end
end

local STATION_RENDERERS: { [string]: () -> () } = {
	RiftGate = renderRiftGate,
	AscensionPedestal = renderPedestal,
	SparkSanctum = renderSanctum,
	RiftShrine = renderShrine,
}

local STATION_FETCHES_DATA: { [string]: boolean } = { AscensionPedestal = true, SparkSanctum = true }

renderStation = function()
	local key = openStation
	local renderer = if key then STATION_RENDERERS[key] else nil
	if not key or not renderer then
		return
	end
	local look = AssetRegistry.TownStations[key]
	stationTitle.Text = if look then ("%s  <b>%s</b>"):format(look.Icon, look.Name) else key
	local scroll = stationContent.CanvasPosition
	clearGuiChildren(stationContent)
	renderer()
	stationContent.CanvasPosition = scroll
end

local function scheduleStationRefresh()
	local key = openStation
	if not key then
		return
	end
	renderStation()
	if not STATION_FETCHES_DATA[key] then
		return
	end
	stationRefreshToken += 1
	local token = stationRefreshToken
	task.delay(STATION_REFRESH_DELAY, function()
		if token ~= stationRefreshToken or openStation ~= key then
			return
		end
		local ok, result = pcall(function(): any
			return stationDataFunction:InvokeServer(key)
		end)
		if ok and result ~= nil and token == stationRefreshToken and openStation == key then
			stationData = result
			renderStation()
		end
	end)
end

local function onOpenStation(payload: any)
	if type(payload) ~= "table" or type(payload.Station) ~= "string" or inRun() then
		return
	end
	local key = payload.Station
	if not STATION_RENDERERS[key] then
		return
	end
	if openStation ~= key then
		respecArmed = false
		stationContent.CanvasPosition = Vector2.zero
	end
	openStation = key
	stationData = payload.Data
	if key == "RiftGate" and unlockedTierFor(selectedWorld) == nil then
		selectedWorld = 1
	end
	renderStation()
	stationFrame.Visible = true
	focusFirstButton(stationContent)
end

-- Town side menu: the stations players use most open from the left edge of the screen while in town, like the
-- shop buttons in other experiences. The panels behave exactly as if the station's prompt had been used.
local function openStationFromMenu(key: string)
	if openStation == key then
		closeStation()
		return
	end
	task.spawn(function()
		local ok, data = pcall(function(): any
			return stationDataFunction:InvokeServer(key)
		end)
		onOpenStation({ Station = key, Data = if ok then data else nil })
		if openStation == key and STATION_FETCHES_DATA[key] and stationData == nil then
			scheduleStationRefresh() -- the data request was throttled; fetch again shortly
		end
	end)
end

local function buildTownMenu()
	local gui = newLayer("RiftTownMenu", 12, false)
	townMenu = create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(76, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
	list(townMenu, Enum.FillDirection.Vertical, 10)
	for order, entry in TOWN_MENU do
		local look = AssetRegistry.TownStations[entry.Station]
		local color = if look then look.Color else COLORS.Accent
		local button = newButton(townMenu, "", COLORS.Panel, function()
			openStationFromMenu(entry.Station)
		end, { Size = UDim2.fromOffset(76, 76), LayoutOrder = order, BackgroundTransparency = 0.1 })
		outline(button, color, 2)
		newLabel(button, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 6), Text = if look then look.Icon else "?",
			TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center })
		newLabel(button, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 16),
			Text = entry.Label, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center })
	end
end

local function buildStationPanel()
	local gui = newLayer("RiftStations", 30, false)
	stationFrame = newPanel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(600, 480), BackgroundTransparency = 0.04, Visible = false })
	pad(stationFrame, 14)
	stationTitle = newLabel(stationFrame, { Size = UDim2.new(1, -50, 0, 30), TextSize = 22 })
	newButton(stationFrame, "✕", COLORS.Bad, closeStation, { AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(36, 30) })
	stationContent = create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = COLORS.Stroke,
	}, stationFrame)
	create("UIPadding", { PaddingRight = UDim.new(0, 10) }, stationContent)
	list(stationContent, Enum.FillDirection.Vertical, 8)
end

-- Server events --------------------------------------------------------------------------------------------------

local function onProfileUpdated(data: any)
	if type(data) ~= "table" then
		return
	end
	profile = data
	liveLevel = tonumber(data.HunterLevel) or liveLevel
	liveXP = tonumber(data.HunterXP) or liveXP
	refreshProfileHud()
	scheduleStationRefresh()
end

local function onRunState(state: any)
	if type(state) ~= "table" or type(state.State) ~= "string" then
		return
	end
	local kind = state.State

	if kind == "Left" then
		runState = nil
		closeAnchor()
		closeDefeat()
		local message = LEAVE_MESSAGES[state.Reason] or "Run over."
		toast(("%s  Banked: %s"):format(message, bagText(state.Credited)), if state.Reason == "Defeat" then COLORS.Bad else COLORS.Good)
		refreshRunBanner()
		return
	end

	runState = state
	if type(state.HunterLevel) == "number" and type(state.HunterXP) == "number" then
		liveLevel = state.HunterLevel
		liveXP = state.HunterXP
		refreshProfileHud()
	end
	refreshRunBanner()

	if kind == "RunStart" then
		closeStation()
	elseif kind == "Anchor" then
		if not defeatOpen then
			showAnchor(state)
		end
	elseif kind == "AnchorWaiting" then
		anchorButtons.Visible = false
		anchorBody.Text = "⚔️ You chose to push deeper. Waiting for the rest of the party…"
	elseif kind == "RoomStart" then
		closeAnchor()
	elseif kind == "Defeat" then
		showDefeat(state)
	elseif kind == "Revived" then
		closeDefeat()
	elseif kind == "ChestOpened" then
		toast(("🎁 Bonus chest!  %s +%s%s"):format(currencyIcon("RiftDust"), formatNumber(tonumber(state.Dust) or 0),
			if (tonumber(state.RelicShards) or 0) > 0 then ("   %s +%d"):format(currencyIcon("RelicShards"), state.RelicShards) else ""),
			COLORS.Gold)
	elseif kind == "ChestForfeited" then
		toast("☠️ The rising spores claimed the bonus chest.", COLORS.Bad)
	end
end

-- Per-tick updates (timers, cooldowns, combo, surge) -------------------------------------------------------------

local function updateTick()
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()

	local data = profile
	local weapon = if data then WeaponConfig.Weapons[data.EquippedWeapon] else nil
	local ability = if weapon then weapon.Ability else nil
	if inRun() and ability then
		local readyAt = player:GetAttribute("Ability1ReadyAt")
		local remaining = if type(readyAt) == "number" then readyAt - serverNow else 0
		local hint = if UserInputService.KeyboardEnabled then "[Q] " else ""
		abilityLabel.Text = if remaining > 0
			then ("%s%s  <font color='#%s'>%.1fs</font>"):format(hint, ability.Name, COLORS.Muted:ToHex(), remaining)
			else ("%s%s  <font color='#%s'>READY</font>"):format(hint, ability.Name, Color3.fromRGB(120, 255, 160):ToHex())
		abilityLabel.Visible = true
	else
		abilityLabel.Visible = false
	end

	townMenu.Visible = not inRun()

	local combo = player:GetAttribute("Combo")
	comboLabel.Visible = inRun() and type(combo) == "number" and combo >= 2
	if comboLabel.Visible then
		comboLabel.Text = ("%d COMBO"):format(combo :: number)
	end

	local surgeEnds = Workspace:GetAttribute(MonetizationConfig.RIFT_SURGE_ATTRIBUTE)
	local surgeActive = MonetizationConfig.IsRiftSurgeActive(serverNow, surgeEnds)
	surgeLabel.Visible = surgeActive
	if surgeActive then
		surgeLabel.Text = ("⚡ Rift Surge x%.1f XP & Dust  ·  %s"):format(MonetizationConfig.RIFT_SURGE_ECO_MULT,
			formatTime((surgeEnds :: number) - serverNow))
	end

	local anchorEnds = anchorDeadline
	if anchorEnds and anchorFrame.Visible then
		anchorTimer.Text = if anchorButtons.Visible
			then ("Auto-extract in %s"):format(formatTime(anchorEnds - now))
			else ("Party decision closes in %s"):format(formatTime(anchorEnds - now))
	end

	local defeatEnds = defeatDeadline
	if defeatOpen and defeatEnds then
		defeatTimer.Text = ("Auto-accept in %s"):format(formatTime(defeatEnds - now))
	end
end

-- Init -----------------------------------------------------------------------------------------------------------

function UIController.Init()
	upgradeChosenRemote = Remotes.GetEvent("UpgradeChosen")
	anchorRemote = Remotes.GetEvent("AnchorDecision")
	defeatRemote = Remotes.GetEvent("DefeatChoice")
	rebirthRemote = Remotes.GetEvent("RequestRebirth")
	ascensionPurchaseRemote = Remotes.GetEvent("AscensionPurchase")
	ascensionRespecRemote = Remotes.GetEvent("AscensionRespec")
	purchaseRemote = Remotes.GetEvent("RequestPurchase")
	startRunFunction = Remotes.GetFunction("StartRun")
	stationDataFunction = Remotes.GetFunction("GetStationData")

	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) -- the HUD draws its own HP bar
	end)

	buildHud()
	buildUpgradeModal()
	buildAnchorModal()
	buildDefeatScreen()
	buildStationPanel()
	buildTownMenu()

	updateScale()
	local function watchCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
			updateScale()
		end
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	Remotes.GetEvent("ProfileUpdated").OnClientEvent:Connect(onProfileUpdated)
	Remotes.GetEvent("RunStateChanged").OnClientEvent:Connect(onRunState)
	Remotes.GetEvent("UpgradeOffer").OnClientEvent:Connect(onUpgradeOffer)
	Remotes.GetEvent("OpenStation").OnClientEvent:Connect(onOpenStation)
	Remotes.GetEvent("Notify").OnClientEvent:Connect(function(message: any)
		if type(message) == "string" then
			toast(message)
		end
	end)

	player.CharacterAdded:Connect(function(character: Model)
		-- A fresh character mid-defeat means Revive / Rewind went through.
		if defeatOpen then
			closeDefeat()
		end
		task.spawn(bindCharacter, character)
	end)
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end

	-- Pass purchases flip ownership attributes; keep the Shrine's "Owned" labels current.
	player.AttributeChanged:Connect(function(name: string)
		if openStation == "RiftShrine" and string.sub(name, 1, 3) == "Has" then
			renderStation()
		elseif name == "RunId" and player:GetAttribute("RunId") ~= nil then
			closeStation()
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= UPDATE_INTERVAL then
			elapsed = 0
			updateTick()
		end
	end)

	task.spawn(function()
		local ok, snapshot = pcall(function(): any
			return Remotes.GetFunction("GetProfile"):InvokeServer()
		end)
		if ok and profile == nil then
			onProfileUpdated(snapshot)
		end
	end)
end

return UIController
