--!strict
-- StarterPlayerScripts/Client/Controllers/UIController.luau
-- Every screen from Section 29 Step 6, built in code (nothing needs to exist in StarterGui):
--   * HUD: Hunter Level / HP / XP, currencies, run banner (room, objective, Secured vs At-Risk loot), Ability 1
--     cooldown, Rift Combo, Rift Surge timer and Notify toasts.
--   * 3/4-card Upgrade modal (UpgradeOffer / UpgradeChosen): click or press 1-4, Reroll, Banish mode.
--   * Rift Anchor modal (RunStateChanged "Anchor"): Extract vs Push Deeper with the decision timer.
--   * Rift Collapse defeat screen (Section 20): Accept, Anchor Token options and the three Robux recoveries.
--   * Town Hub panels (OpenStation): Rift Gate world / corruption picker, Ascension Pedestal (rebirth), Spark
--     Sanctum (Ascension Shop), the Rift Shrine store, Blacksmith (forge / reactivate weapons), Legion Hall (Mastery
--     & Link Skills), Star-Forge (relics, Star-Force, Starting Relics), Quest Board and Hall of Champions.
--   * The Bag (I / B / Select / HUD button): equipped weapon & Mastery, weapons, Link Skills, Starting Relics and,
--     during a run, the run's relics and curses. Usable anywhere; loadout changes are town-only.
--   * Weapon Mastery bar under the XP bar (MasteryUpdated), shield readout on the HP bar, and Celebrate banners
--     for new relics, Mastery levels and quest rewards.
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
local StationPanels = require(script.Parent:WaitForChild("StationPanels"))

-- UIPack Plus ("ShardUI", by sebattfg) lives in the place file under ReplicatedStorage, never in Rojo/git: its
-- license forbids redistributing it. With it, buttons, windows, bars, chips and cards are its image "gems"; without it
-- (e.g. a fresh `rojo build`) every helper below falls back to the flat style.
local Shard: any = nil
do
	local pack = ReplicatedStorage:WaitForChild("ShardUI", 5)
	if pack then
		local ok, result = pcall(function(): any
			local root = pack :: any
			local load = require :: any -- the pack is not in the Rojo sourcemap, so its modules are untyped
			return {
				Button = load(root.Button.Button),
				IconButton = load(root.IconButton.IconButton),
				Panel = load(root.Panel.Panel),
				Inset = load(root.Inset.Inset),
				Card = load(root.Card.Card),
				Chip = load(root.Chip.Chip),
				Bar = load(root.Bar.Bar),
				Badge = load(root.Badge.Badge),
				Icons = load(root.Shared.Icons),
				Palette = load(root.Shared.Palette),
			}
		end)
		if ok then
			Shard = result
		else
			warn("[UIController] ShardUI failed to load, using the flat UI style: " .. tostring(result))
		end
	else
		warn("[UIController] ReplicatedStorage.ShardUI not found, using the flat UI style")
	end
end

type Payload = { [string]: any }
type Bar = { Fill: Frame?, Label: TextLabel, Shard: any? }

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

-- Cartoon "simulator" look: saturated colours, thick dark outlines, top-lit gradients and a rounded display font.
local COLORS = {
	Panel = Color3.fromHex("4a5c86"), -- slate: HUD pills, toasts, rows
	PanelLight = Color3.fromHex("5d719a"),
	Stroke = Color3.fromHex("0d1524"), -- the one outline colour everything shares
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromHex("cfdaf0"),
	Accent = Color3.fromHex("8a6bf0"),
	Gold = Color3.fromHex("ffb724"),
	Good = Color3.fromHex("5fcf34"),
	Bad = Color3.fromHex("f4523f"),
	Robux = Color3.fromHex("5fcf34"),
	HP = Color3.fromHex("f4523f"),
	XP = Color3.fromHex("45cff0"),
	Disabled = Color3.fromHex("6b7896"),
}

-- Window body colours (a darker header strip and content inset are derived from each).
local WINDOW_COLORS = {
	Shop = Color3.fromHex("3fb4d8"),
	RiftGate = Color3.fromHex("8a6bf0"),
	AscensionPedestal = Color3.fromHex("f26a97"),
	SparkSanctum = Color3.fromHex("f0a81f"),
	Upgrade = Color3.fromHex("8a6bf0"),
	Anchor = Color3.fromHex("3fb4d8"),
	Defeat = Color3.fromHex("d24a4a"),
	Blacksmith = Color3.fromHex("e2733a"),
	LegionHall = Color3.fromHex("3f8fd8"),
	StarForge = Color3.fromHex("8a5cf0"),
	QuestBoard = Color3.fromHex("c99a2e"),
	HallOfChampions = Color3.fromHex("d8a520"),
	Inventory = Color3.fromHex("4a7fd0"),
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
local TOWN_MENU: { { Station: string, Label: string, PackIcon: string } } = {
	{ Station = "RiftShrine", Label = "Shop", PackIcon = "Cart" },
	{ Station = "SparkSanctum", Label = "Ascend", PackIcon = "Upgrade" },
	{ Station = "AscensionPedestal", Label = "Rebirth", PackIcon = "Crown" },
}

-- Rift Shrine store cards (renderShop). Price and ownership come from MonetizationConfig; this only styles them.
-- Kind "Product" / "Pass" are Robux purchases; a future in-game-currency item would add its own Kind.
type ShopItem = { Key: string, Kind: "Product" | "Pass", Title: string, Icon: string, Color: Color3, Tag: string?,
	Tabs: { string }, PackIcon: string? } -- PackIcon: a ShardUI Icons key, shown instead of the emoji when it exists

local SHOP_TABS = { "Featured", "Boosts", "Passes", "Rebirth" }
local SHOP_ITEMS: { ShopItem } = {
	{ Key = "RiftSurge", Kind = "Product", Title = "Rift Surge", Icon = "⚡", Color = Color3.fromRGB(40, 185, 230),
		Tag = "Server", Tabs = { "Featured", "Boosts" }, PackIcon = "Bolt" },
	{ Key = "TrueAscendant", Kind = "Pass", Title = "True Ascendant", Icon = "👑", Color = Color3.fromRGB(255, 170, 30),
		Tag = "Best", Tabs = { "Featured", "Rebirth", "Passes" }, PackIcon = "Crown" },
	{ Key = "DoubleXP", Kind = "Pass", Title = "2x Hunter XP", Icon = "⭐", Color = Color3.fromRGB(80, 200, 80),
		Tag = "x2", Tabs = { "Featured", "Passes" }, PackIcon = "Star" },
	{ Key = "DoubleDust", Kind = "Pass", Title = "2x Rift Dust", Icon = "🔮", Color = Color3.fromRGB(160, 80, 250),
		Tag = "x2", Tabs = { "Featured", "Passes" } },
	{ Key = "SuperchargedRunToken", Kind = "Product", Title = "Supercharge", Icon = "🚀", Color = Color3.fromRGB(255, 120, 50),
		Tag = "x2 Dust", Tabs = { "Featured", "Boosts" } },
	{ Key = "VIPArchitect", Kind = "Pass", Title = "4th Card", Icon = "🃏", Color = Color3.fromRGB(240, 70, 160),
		Tag = "VIP", Tabs = { "Featured", "Passes" }, PackIcon = "Gift" },
	{ Key = "RerollPack5", Kind = "Product", Title = "Rerolls", Icon = "🎲", Color = Color3.fromRGB(70, 130, 255),
		Tag = "x5", Tabs = { "Featured", "Boosts" }, PackIcon = "Dice" },
	{ Key = "KeepEverythingSeal", Kind = "Product", Title = "Keep Seal", Icon = "📜", Color = Color3.fromRGB(230, 60, 90),
		Tag = "1 use", Tabs = { "Featured", "Rebirth" } },
	{ Key = "StarForceSafeguardPack", Kind = "Product", Title = "Safeguards", Icon = "🛡️", Color = Color3.fromRGB(60, 170, 200),
		Tag = "x3", Tabs = { "Boosts" } },
	{ Key = "BanishPass", Kind = "Pass", Title = "Banish Pass", Icon = "🚫", Color = Color3.fromRGB(225, 70, 70),
		Tabs = { "Passes" }, PackIcon = "Warning" },
	{ Key = "VaultInsurance", Kind = "Pass", Title = "Insurance", Icon = "🏦", Color = Color3.fromRGB(40, 175, 150),
		Tabs = { "Passes" } },
	{ Key = "RelicVaultKey", Kind = "Pass", Title = "Relic Key", Icon = "🗝️", Color = Color3.fromRGB(230, 150, 40),
		Tabs = { "Passes" } },
	{ Key = "ExtraLinkSlots", Kind = "Pass", Title = "+2 Links", Icon = "🔗", Color = Color3.fromRGB(90, 110, 240),
		Tag = "+2", Tabs = { "Passes" }, PackIcon = "Friends" },
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
SHOP_BLURBS.RelicVaultKey = "+1 Starting Relic slot for every run"

local DISPLAY_FONT = Enum.Font.FredokaOne -- titles, buttons, numbers
local BODY_FONT = Enum.Font.FredokaOne -- the pack uses Fredoka One for every line of text

local LABEL_DEFAULTS: Payload = {
	BackgroundTransparency = 1,
	Font = BODY_FONT,
	TextColor3 = COLORS.Text,
	TextStrokeColor3 = COLORS.Stroke,
	TextStrokeTransparency = 0.55,
	TextSize = 15,
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
-- Mastery of the equipped weapon from the latest MasteryUpdated (kills only replicate the profile on level-ups).
local liveMastery: { Weapon: string, Level: number, XP: number, Paragon: number }? = nil

local scaleObjects: { UIScale } = {}

-- HUD
local hpBar: Bar
local xpBar: Bar
local masteryBar: Bar
local runInfoLabel: TextLabel
local toggleInventory: () -> () -- defined with the station panels
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
local upgradeWindow: Window
local upgradeTitle: TextLabel
local cardRow: Frame
local rerollButton: GuiButton
local banishButton: GuiButton
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
local defeatButtons: { [string]: GuiButton } = {}
local defeatDeadline: number? = nil
local defeatOpen = false

-- Station panels
local stationFrame: Frame
local stationWindow: Window
local shopFrame: Frame
local windowScrims: { GuiObject } = {}
local shopGrid: ScrollingFrame
local shopTabs: { [string]: GuiButton } = {}
local shopInfo: TextLabel
local shopWallet: { [string]: TextLabel } = {}
local shopTab = "Featured"
local renderShop: () -> ()
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

-- A UIGradient multiplies the background colour, so white -> grey keeps any BackgroundColor3 but lights it from the top.
local function topLit(parent: Instance, shade: number)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(shade, shade, shade)),
	}, parent)
end

local function edgeColor(color: Color3): Color3
	return color:Lerp(Color3.new(0, 0, 0), 0.62)
end

-- Soft diagonal stripes over the icon box, standing in for the sunburst art in cartoon stores.
local function addStripes(parent: GuiObject, radius: number)
	local stripes: Frame = create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0 }, parent)
	round(stripes, radius)
	local keypoints: { NumberSequenceKeypoint } = {}
	for index = 0, 19 do
		table.insert(keypoints, NumberSequenceKeypoint.new(index / 19, if index % 2 == 0 then 1 else 0.82))
	end
	create("UIGradient", { Rotation = 35, Transparency = NumberSequence.new(keypoints) }, stripes)
end

local function newPanel(parent: Instance, props: Payload): Frame
	local frame: Frame = create("Frame", merged({ BackgroundColor3 = COLORS.Panel, BackgroundTransparency = 0.04 }, props), parent)
	round(frame, 14)
	outline(frame, COLORS.Stroke, 3)
	topLit(frame, 0.72)
	return frame
end

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Grows on hover and squishes when pressed, springing back on release.
local function addPressFeedback(button: GuiButton)
	local scale: UIScale = create("UIScale", {}, button)
	local hovering = false
	local function enabled(): boolean
		return button:GetAttribute("Enabled") ~= false
	end
	button.MouseEnter:Connect(function()
		hovering = true
		if enabled() then
			TweenService:Create(scale, HOVER_TWEEN, { Scale = 1.05 }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		TweenService:Create(scale, HOVER_TWEEN, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		if enabled() then
			TweenService:Create(scale, PRESS_TWEEN, { Scale = 0.9 }):Play()
		end
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, RELEASE_TWEEN, { Scale = if hovering then 1.05 else 1 }):Play()
	end)
end

local function setFlatEnabled(button: TextButton, enabled: boolean, color: Color3)
	button:SetAttribute("Enabled", enabled)
	button.AutoButtonColor = false
	button.BackgroundColor3 = if enabled then color else COLORS.Disabled
	button.TextTransparency = if enabled then 0 else 0.35
	local stroke = button:FindFirstChild("Edge")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = edgeColor(button.BackgroundColor3)
	end
end

-- Chunky cartoon button: saturated top-lit fill, thick darker edge, a glossy highlight, outlined display text.
local function newFlatButton(parent: Instance, label: string, color: Color3, onClick: () -> (), props: Payload?): TextButton
	local button: TextButton = create("TextButton", merged({
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = DISPLAY_FONT,
		Text = label,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeColor3 = COLORS.Stroke,
		TextStrokeTransparency = 0.2,
		TextSize = 18,
		TextWrapped = true,
		RichText = true,
		Size = UDim2.fromOffset(160, 42),
	}, props or {}), parent)
	round(button, 12)
	create("UIStroke", { Name = "Edge", Color = edgeColor(color), Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	topLit(button, 0.7)
	local gloss = create("Frame", {
		Name = "Gloss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -10, 0.38, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Active = false,
	}, button)
	round(gloss, 9)
	addPressFeedback(button)
	button.Activated:Connect(function()
		if button:GetAttribute("Enabled") ~= false then
			onClick()
		end
	end)
	return button
end

-- ShardUI button handles, keyed by the gem's root. setEnabled / setButtonText repaint the same instance, so references
-- held by the screens (reroll, banish, defeat options...) stay valid.
local shardButtons: { [GuiObject]: any } = setmetatable({}, { __mode = "k" }) :: any

-- The ShardUI family whose middle band is closest to `color` (the screens still speak in Color3).
local function familyFor(color: Color3): string
	local best, bestDistance = "slate", math.huge
	for key, family in Shard.Palette.Families do
		local m: Color3 = family.m
		local distance = (m.R - color.R) ^ 2 + (m.G - color.G) ^ 2 + (m.B - color.B) ^ 2
		if distance < bestDistance then
			best, bestDistance = key, distance
		end
	end
	return best
end

local function newButton(parent: Instance, label: string, color: Color3, onClick: () -> (), props: Payload?): GuiButton
	if not Shard then
		return newFlatButton(parent, label, color, onClick, props)
	end
	local p: Payload = props or {}
	local size: UDim2 = p.Size or UDim2.fromOffset(160, 42)
	-- Gems have fixed heights per variant (sm 55, md 72, big 99): pick the one closest to what the screen asked for.
	local variant = if size.Y.Offset >= 86 then "big" elseif size.Y.Offset >= 62 then "md" else "sm"
	local gem = Shard.Button.new({ text = label, variant = variant, family = familyFor(color),
		width = if size.X.Scale == 0 then size.X.Offset else 200 })
	local root = gem.Root :: GuiButton
	root.Size = UDim2.new(size.X.Scale, size.X.Offset, 0, root.Size.Y.Offset)
	for _, key in { "AnchorPoint", "Position", "LayoutOrder", "Visible", "ZIndex" } do
		if p[key] ~= nil then
			(root :: any)[key] = p[key]
		end
	end
	local text: TextLabel = gem.Label
	text.RichText = true
	text.TextWrapped = true
	if p.TextSize then
		text.TextSize = p.TextSize
	end
	if p.TextXAlignment then
		text.TextXAlignment = p.TextXAlignment
	end
	shardButtons[root] = gem
	root:SetAttribute("Enabled", true)
	root.MouseButton1Click:Connect(function()
		if root:GetAttribute("Enabled") ~= false then
			onClick()
		end
	end)
	root.Parent = parent
	return root
end

-- Disabled gems are repainted slate with faded text (the pack's look), and recoloured when re-enabled.
local function setEnabled(button: GuiButton, enabled: boolean, color: Color3)
	local gem = shardButtons[button]
	if not gem then
		setFlatEnabled(button :: any, enabled, color)
		return
	end
	button:SetAttribute("Enabled", enabled)
	button.Active = enabled
	if enabled then
		gem.Family = Shard.Palette.Families[familyFor(color)]
		gem:SetSelected(false)
	else
		gem:SetSelected(true, "slate")
	end
	local text: TextLabel = gem.Label
	text.TextTransparency = if enabled then 0 else 0.4
	local stroke = text:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = if enabled then 0 else 0.4
	end
end

local function setButtonText(button: GuiButton, text: string)
	local gem = shardButtons[button]
	if gem then
		gem.Label.Text = text
	else
		(button :: TextButton).Text = text
	end
end

-- Window (the shop's layout, shared by every screen): coloured body, darker header strip with a big outlined title
-- and an optional red X, and a dark inset for the content.
type Window = { Frame: Frame, Header: GuiObject, Title: TextLabel, Body: Frame, Shard: any? }

local function headerColor(color: Color3): Color3
	return color:Lerp(Color3.new(0, 0, 0), 0.24)
end

local function insetColor(color: Color3): Color3
	return color:Lerp(Color3.fromHex("0d1524"), 0.62)
end

-- The pack panel's frame is a 3-band gradient (light / mid / dark) over the family's panel tints.
local function panelBands(color: Color3): ColorSequence
	local key = familyFor(color)
	local family = Shard.Palette.Panels[key] or Shard.Palette.Families[key]
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, family.l),
		ColorSequenceKeypoint.new(0.23, family.l),
		ColorSequenceKeypoint.new(0.24, family.m),
		ColorSequenceKeypoint.new(0.57, family.m),
		ColorSequenceKeypoint.new(0.58, family.d),
		ColorSequenceKeypoint.new(1.00, family.d),
	})
end

local function newWindow(parent: Instance, color: Color3, props: Payload, onClose: (() -> ())?): Window
	if Shard then
		local size: UDim2 = props.Size or UDim2.fromOffset(600, 450)
		local panel = Shard.Panel.new({ title = "", family = familyFor(color), width = size.X.Offset,
			height = size.Y.Offset, headHeight = 76 })
		local root = panel.Root :: Frame
		for _, key in { "AnchorPoint", "Position", "Visible" } do
			if props[key] ~= nil then
				(root :: any)[key] = props[key]
			end
		end
		local title = panel.Title :: TextLabel
		title.RichText = true
		title.TextSize = 30
		if onClose then
			Shard.IconButton.new({ icon = Shard.Icons.Close, variant = "sm", family = "red", parent = panel.Tools,
				onClick = onClose })
		end
		root.Parent = parent
		return { Frame = root, Header = panel.Head, Title = title, Body = panel.Body, Shard = panel }
	end
	local frame = newPanel(parent, merged({ BackgroundColor3 = color }, props))
	local header: Frame = create("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = headerColor(color) }, frame)
	round(header, 14)
	topLit(header, 0.8)
	local title = newLabel(header, { Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, if onClose then -96 else -40, 1, 0), Font = DISPLAY_FONT, TextSize = 32,
		TextStrokeTransparency = 0, TextTruncate = Enum.TextTruncate.AtEnd })
	if onClose then
		newButton(header, "X", COLORS.Bad, onClose, { AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(48, 48), TextSize = 28 })
	end
	local body: Frame = create("Frame", { Name = "Body", Position = UDim2.fromOffset(14, 76),
		Size = UDim2.new(1, -28, 1, -90), BackgroundTransparency = 1 }, frame)
	return { Frame = frame, Header = header, Title = title, Body = body }
end

local function setWindowColor(window: Window, color: Color3)
	if window.Shard then
		local gradient = window.Shard.Frame:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = panelBands(color)
		end
		return
	end
	window.Frame.BackgroundColor3 = color
	window.Header.BackgroundColor3 = headerColor(color)
end

local function newBar(parent: Instance, color: Color3, order: number): Bar
	if Shard then
		-- A pack gauge with the value written over it; it follows its container's width (it is sized in pixels).
		local holder: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1,
			LayoutOrder = order }, parent)
		local gauge = Shard.Bar.new({ family = familyFor(color), value = 0, width = 200, parent = holder })
		local function fit()
			local width = holder.AbsoluteSize.X / math.max(scaleObjects[1] and scaleObjects[1].Scale or 1, 0.01)
			if width > 40 then
				gauge:SetWidth(math.floor(width))
			end
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		task.defer(fit)
		local text = newLabel(holder, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
			Font = DISPLAY_FONT, TextSize = 16, ZIndex = 10 })
		create("UIStroke", { Color = COLORS.Stroke, Thickness = 2.5, LineJoinMode = Enum.LineJoinMode.Round }, text)
		return { Fill = nil, Label = text, Shard = gauge }
	end
	local back: Frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundColor3 = Color3.fromRGB(14, 10, 30),
		LayoutOrder = order,
	}, parent)
	round(back, 8)
	outline(back, COLORS.Stroke, 2)
	local fill: Frame = create("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color }, back)
	round(fill, 8)
	topLit(fill, 0.6)
	local label = newLabel(back, {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = DISPLAY_FONT,
		TextSize = 14,
		TextStrokeTransparency = 0.1,
		ZIndex = 2,
	})
	return { Fill = fill, Label = label }
end

local function setBar(bar: Bar, ratio: number, label: string)
	local fill = bar.Fill
	if bar.Shard then
		bar.Shard:Set(math.clamp(ratio, 0, 1))
	elseif fill then
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	end
	bar.Label.Text = label
end

local function clearGuiChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A ScreenGui ignores a UIScale, so each layer gets a full-screen root frame that carries it. The layout is designed
-- at REF_WIDTH x REF_HEIGHT; updateScale shrinks the root's Size by the same factor its UIScale grows it.
local scaleRoots: { Frame } = {}

local function newLayer(name: string, displayOrder: number, ignoreInset: boolean): Frame
	local gui: ScreenGui = create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		DisplayOrder = displayOrder,
		IgnoreGuiInset = ignoreInset,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	local root: Frame = create("Frame", { Name = "ScaleRoot", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	table.insert(scaleObjects, create("UIScale", {}, root))
	table.insert(scaleRoots, root)
	return root
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
	for _, root in scaleRoots do
		root.Size = UDim2.fromScale(1 / scale, 1 / scale)
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
		Font = DISPLAY_FONT,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = message,
		LayoutOrder = toastOrder,
	})
	round(label, 12)
	pad(label, 9)
	outline(label, color or COLORS.Stroke, 3)
	topLit(label, 0.72)
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

local function refreshMasteryBar()
	local data = profile
	if not data or not masteryBar then
		return
	end
	local weapon = WeaponConfig.Weapons[data.EquippedWeapon]
	if not weapon then
		return
	end
	local live = liveMastery
	local level, xp, paragon = 1, 0, 0
	if live and live.Weapon == weapon.Id then
		level, xp, paragon = live.Level, live.XP, live.Paragon
	else
		local entry = type(data.WeaponMastery) == "table" and data.WeaponMastery[weapon.Id]
		if type(entry) == "table" then
			level, xp, paragon = tonumber(entry.Level) or 1, tonumber(entry.XP) or 0, tonumber(entry.ParagonRank) or 0
		end
	end
	local required = WeaponConfig.GetMasteryXPRequired(if level >= WeaponConfig.MAX_MASTERY then WeaponConfig.MAX_MASTERY + paragon else level)
	setBar(masteryBar, xp / math.max(1, required), ("%s %s %d  ·  %s / %s"):format(weapon.Icon,
		if paragon > 0 then "Paragon" else "Mastery", if paragon > 0 then paragon else level, formatNumber(xp), formatNumber(required)))
end

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
	local function setCurrency(key: string, value: any)
		local label = currencyLabels[key]
		local amount = formatNumber(tonumber(value) or 0)
		label.Text = if Shard then currencyIcon(key) .. " " .. amount else amount
	end
	setCurrency("RiftDust", data.RiftDust)
	if vault > 0 and not Shard then -- the pack chips are fixed-width; the vault total shows at the Pedestal
		currencyLabels.RiftDust.Text ..= (" <font color='#%s'>(+%s vault)</font>"):format(COLORS.Muted:ToHex(),
			formatNumber(vault))
	end
	setCurrency("BossCores", data.BossCores)
	setCurrency("RelicShards", data.RelicShards)
	setCurrency("RebirthSpark", data.RebirthSparksAvailable)
	setCurrency("AnchorToken", data.AnchorTokens)
	refreshMasteryBar()
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
		local shield = tonumber(player:GetAttribute("Shield")) or 0
		setBar(hpBar, humanoid.Health / math.max(humanoid.MaxHealth, 1), ("HP %s / %s%s"):format(
			formatNumber(math.ceil(humanoid.Health)), formatNumber(humanoid.MaxHealth),
			if shield > 0 then ("  🛡 %s"):format(formatNumber(shield)) else ""))
	end
	table.insert(healthConnections, humanoid.HealthChanged:Connect(update))
	table.insert(healthConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update))
	table.insert(healthConnections, player:GetAttributeChangedSignal("Shield"):Connect(update))
	update()
end

local function buildHud()
	local gui = newLayer("RiftHUD", 10, false)

	-- With the pack the vitals sit straight on the screen (its HUD has no frame around them); otherwise in a panel.
	local status: Frame
	if Shard then
		status = create("Frame", { Position = UDim2.fromOffset(16, 14), Size = UDim2.fromOffset(300, 0),
			AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
	else
		status = newPanel(gui, { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(300, 0),
			AutomaticSize = Enum.AutomaticSize.Y })
		pad(status, 8)
	end
	list(status, Enum.FillDirection.Vertical, 6)
	levelLabel = newLabel(status, { Size = UDim2.new(1, 0, 0, 24), TextSize = if Shard then 22 else 16, LayoutOrder = 1 })
	if Shard then
		create("UIStroke", { Color = COLORS.Stroke, Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round }, levelLabel)
	end
	hpBar = newBar(status, COLORS.HP, 2)
	xpBar = newBar(status, COLORS.XP, 3)
	masteryBar = newBar(status, COLORS.Gold, 4)
	runInfoLabel = newLabel(status, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
		Font = DISPLAY_FONT, TextSize = 15, TextStrokeTransparency = 0.2, LayoutOrder = 5, Visible = false })
	newButton(status, "🎒 Bag", COLORS.Accent, function()
		toggleInventory()
	end, { Size = UDim2.fromOffset(120, 40), TextSize = 17, LayoutOrder = 6 })

	local wallet: Frame = create("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
	local walletLayout = list(wallet, Enum.FillDirection.Vertical, 4)
	walletLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	for order, key in { "RiftDust", "BossCores", "RelicShards", "RebirthSpark", "AnchorToken" } do
		if Shard then
			-- A static pack chip per currency; the emoji icon is part of its text (see setCurrency).
			local chip = Shard.Chip.new({ text = currencyIcon(key) .. " 0", variant = "sm", family = "slate", static = true,
				width = 150, parent = wallet })
			chip.Root.LayoutOrder = order
			currencyLabels[key] = chip.Label
			continue
		end
		local info = AssetRegistry.Currencies[key]
		local pill = newPanel(wallet, { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = order })
		create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, pill)
		local row = list(pill, Enum.FillDirection.Horizontal, 6)
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		newLabel(pill, { Size = UDim2.fromOffset(20, 20), Text = currencyIcon(key), TextSize = 16, LayoutOrder = 1 })
		currencyLabels[key] = newLabel(pill, { Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
			Text = "0", Font = DISPLAY_FONT, TextSize = 15, TextColor3 = info.Color:Lerp(Color3.new(1, 1, 1), 0.45),
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
		Font = DISPLAY_FONT, LayoutOrder = 3 })
	surgeLabel = newLabel(banner, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = Color3.fromRGB(120, 255, 200),
		TextXAlignment = Enum.TextXAlignment.Center, Font = DISPLAY_FONT, LayoutOrder = 4, Visible = false })

	toastList = create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(460, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 },
		newLayer("RiftToasts", 50, false))
	local toastLayout = list(toastList, Enum.FillDirection.Vertical, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	abilityLabel = newLabel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0.15,
		BackgroundColor3 = COLORS.Panel, Font = DISPLAY_FONT, TextSize = 15, Visible = false })
	round(abilityLabel, 8)
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, abilityLabel)

	comboLabel = newLabel(gui, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.42, 0),
		Size = UDim2.fromOffset(220, 40), TextXAlignment = Enum.TextXAlignment.Right, Font = DISPLAY_FONT,
		TextSize = 30, TextColor3 = COLORS.Gold, TextStrokeTransparency = 0.3, Visible = false })

	refreshRunBanner()
end

-- Upgrade modal --------------------------------------------------------------------------------------------------

-- Helpers used only by the modal stay scoped in this block (UIController is close to Luau's 200-local limit).
local onUpgradeOffer: (any) -> ()
local buildUpgradeModal: () -> ()
do
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

	-- Pack upgrade card: the pack's Card in the rarity's family, a rarity badge on its corner and the description below.
	local RARITY_FAMILIES: { [string]: string } = {
		Common = "slate",
		Rare = "cyan",
		Epic = "violet",
		Legendary = "amber",
		Corrupted = "magenta",
	}
	local SHARD_CARD_GAP = 18

	local function buildShardUpgradeCard(index: number, card: any)
		local size: Vector2 = Shard.Card.size("sm")
		local slot: Frame = create("Frame", { Size = UDim2.fromOffset(size.X, size.Y + 84), BackgroundTransparency = 1,
			LayoutOrder = index }, cardRow)
		local pick = function()
			chooseCard(index)
		end
		local hint = if UserInputService.KeyboardEnabled then (" [%d]"):format(index) else ""
		local gem = Shard.Card.new({ name = tostring(card.Name), variant = "sm",
			family = RARITY_FAMILIES[tostring(card.Rarity)] or "slate",
			price = (if banishMode then "Banish" else "Pick") .. hint, priceFamily = if banishMode then "red" else "green",
			activated = pick })
		gem.Button.Root.MouseButton1Click:Connect(pick)
		newLabel(gem.Thumb, { Size = UDim2.fromScale(1, 1), Text = tostring(card.Icon), TextSize = 62, ZIndex = 8,
			TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1 })
		gem.Root.Parent = slot

		local stacks = tonumber(card.Stacks) or 0
		local maxStacks = tonumber(card.MaxStacks) or 1
		Shard.Badge.attachTo(Shard.Badge.new({ text = tostring(card.Rarity) .. (if maxStacks > 1
			then (" %d/%d"):format(stacks, maxStacks) else ""), variant = "sm", family = "slate", static = true }), gem.Root)

		local desc = newLabel(slot, { Position = UDim2.fromOffset(0, size.Y + 10), Size = UDim2.new(1, 0, 0, 74),
			Text = tostring(card.Desc), TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top })
		create("UIStroke", { Color = COLORS.Stroke, Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round }, desc)
	end

	local function renderOffer()
		clearGuiChildren(cardRow)
		local count = #offerCards
		upgradeTitle.Text = if banishMode
			then ("<font color='#%s'>🚫 Choose a card to BANISH for this run</font>"):format(COLORS.Bad:ToHex())
			else "⬆️ <b>Choose an Upgrade</b>"
		if Shard then
			local cardWidth = Shard.Card.size("sm").X
			upgradeFrame.Size = UDim2.fromOffset(math.max(520, count * cardWidth + (count - 1) * SHARD_CARD_GAP + 64), 610)
		else
			upgradeFrame.Size = UDim2.fromOffset(math.max(420, count * CARD_WIDTH + (count - 1) * CARD_GAP + 44), 450)
		end

		for index, card in offerCards do
			if Shard then
				buildShardUpgradeCard(index, card)
				continue
			end
			local style = AssetRegistry.GetRarityStyle(card.Rarity)
			-- Shop-style card in the rarity colour: striped icon box, outlined text, red edge while banishing.
			local cardColor = style.Color:Lerp(Color3.new(0, 0, 0), 0.12)
			local button: TextButton = create("TextButton", {
				Size = UDim2.new(0, CARD_WIDTH, 1, 0),
				BackgroundColor3 = cardColor,
				AutoButtonColor = false,
				Text = "",
				LayoutOrder = index,
			}, cardRow)
			round(button, 12)
			outline(button, if banishMode then COLORS.Bad else COLORS.Stroke, if banishMode then 5 else 3)
			addPressFeedback(button)
			topLit(button, 0.7)
			pad(button, 10)
			local layout = list(button, Enum.FillDirection.Vertical, 6)
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

			local stacks = tonumber(card.Stacks) or 0
			local maxStacks = tonumber(card.MaxStacks) or 1
			newLabel(button, { Size = UDim2.new(1, 0, 0, 16), Text = ("[%d]"):format(index), TextColor3 = COLORS.Muted,
				TextSize = 12, LayoutOrder = 1, Visible = UserInputService.KeyboardEnabled })
			local iconBox: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 84), LayoutOrder = 2,
				BackgroundColor3 = cardColor:Lerp(Color3.new(1, 1, 1), 0.12) }, button)
			round(iconBox, 8)
			create("UIStroke", { Color = edgeColor(cardColor), Thickness = 2.5 }, iconBox)
			addStripes(iconBox, 8)
			newLabel(iconBox, { Size = UDim2.fromScale(1, 1), Text = tostring(card.Icon), TextSize = 50,
				TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1 })
			newLabel(button, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = tostring(card.Name),
				Font = DISPLAY_FONT, TextSize = 20, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
				TextStrokeTransparency = 0, LayoutOrder = 3 })
			newLabel(button, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = style.Color:Lerp(Color3.new(1, 1, 1), 0.7),
				Font = DISPLAY_FONT, TextSize = 15, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 4,
				Text = tostring(card.Rarity):upper() .. (if maxStacks > 1 then ("  ·  %d/%d"):format(stacks, maxStacks) else "") })
			newLabel(button, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = tostring(card.Desc),
				TextColor3 = COLORS.Text, TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
				TextStrokeTransparency = 0.3, LayoutOrder = 5 })

			button.Activated:Connect(function()
				chooseCard(index)
			end)
		end

		setButtonText(rerollButton, ("🎲 Reroll (%d)"):format(offerRerolls))
		setEnabled(rerollButton, offerRerolls > 0 and not banishMode, COLORS.Accent)
		banishButton.Visible = offerBanishes > 0
		setButtonText(banishButton, if banishMode then "Cancel Banish" else ("🚫 Banish (%d)"):format(offerBanishes))
		upgradeFrame.Visible = true
		focusFirstButton(cardRow)
	end

	onUpgradeOffer = function(payload: any)
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

	buildUpgradeModal = function()
		local gui = newLayer("RiftUpgrade", 20, false)
		upgradeWindow = newWindow(gui, WINDOW_COLORS.Upgrade, { AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(600, 450), Visible = false })
		upgradeFrame = upgradeWindow.Frame
		upgradeTitle = upgradeWindow.Title
		upgradeTitle.TextXAlignment = Enum.TextXAlignment.Center
		cardRow = create("Frame", { Position = UDim2.fromOffset(0, if Shard then 14 else 8),
			Size = UDim2.new(1, 0, 1, if Shard then -84 else -66), BackgroundTransparency = 1 }, upgradeWindow.Body)
		list(cardRow, Enum.FillDirection.Horizontal, if Shard then SHARD_CARD_GAP else CARD_GAP).HorizontalAlignment =
			Enum.HorizontalAlignment.Center

		local footer: Frame = create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, if Shard then 60 else 46), BackgroundTransparency = 1 }, upgradeWindow.Body)
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
		if child:IsA("GuiButton") then
			setEnabled(child, true, child:GetAttribute("Color") :: Color3)
		end
	end
	anchorFrame.Visible = true
	focusFirstButton(anchorButtons)
end

local function sendAnchor(decision: "Extract" | "Push")
	for _, child in anchorButtons:GetChildren() do
		if child:IsA("GuiButton") then
			setEnabled(child, false, COLORS.Disabled)
		end
	end
	anchorRemote:FireServer(decision)
end

local function buildAnchorModal()
	local gui = newLayer("RiftAnchor", 25, false)
	anchorFrame = newPanel(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(560, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = WINDOW_COLORS.Anchor,
		Visible = false })
	pad(anchorFrame, 14)
	local layout = list(anchorFrame, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	anchorTitle = newLabel(anchorFrame, { Size = UDim2.new(1, 0, 0, 34), Font = DISPLAY_FONT, TextSize = 30,
		TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	anchorBody = newLabel(anchorFrame, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true, TextSize = 17, TextStrokeTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2 })
	anchorTimer = newLabel(anchorFrame, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
	anchorButtons = create("Frame", { Size = UDim2.new(1, 0, 0, if Shard then 60 else 52), BackgroundTransparency = 1,
		LayoutOrder = 4 },
		anchorFrame)
	list(anchorButtons, Enum.FillDirection.Horizontal, 14).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local extract = newButton(anchorButtons, "🏁 Extract to Town", COLORS.Good, function()
		sendAnchor("Extract")
	end, { Size = UDim2.fromOffset(240, 50), TextSize = 21, LayoutOrder = 1 })
	extract:SetAttribute("Color", COLORS.Good)
	local push = newButton(anchorButtons, "⚔️ Push Deeper", COLORS.Accent, function()
		sendAnchor("Push")
	end, { Size = UDim2.fromOffset(240, 50), TextSize = 21, LayoutOrder = 2 })
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
		setButtonText(button, option.Text)
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
	local defeatRoot = newLayer("RiftCollapse", 40, true)
	defeatGui = defeatRoot.Parent :: ScreenGui
	defeatGui.Enabled = false
	create("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		Active = true }, defeatRoot)

	local panel = newPanel(defeatRoot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = WINDOW_COLORS.Defeat })
	pad(panel, 16)
	local layout = list(panel, Enum.FillDirection.Vertical, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	newLabel(panel, { Size = UDim2.new(1, 0, 0, 44), Text = "💀 RIFT COLLAPSE", Font = DISPLAY_FONT,
		TextSize = 40, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1 })
	defeatTimer = newLabel(panel, { Size = UDim2.new(1, 0, 0, 18), TextColor3 = COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })

	local columns: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, LayoutOrder = 3 }, panel)
	list(columns, Enum.FillDirection.Horizontal, 10)
	local function column(order: number, color: Color3): TextLabel
		local label = newLabel(columns, { Size = UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 0, BackgroundColor3 = insetColor(WINDOW_COLORS.Defeat), TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, LayoutOrder = order })
		round(label, 10)
		pad(label, 10)
		outline(label, color, 3)
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
		end, { Size = UDim2.new(1, 0, 0, 46), TextSize = 18, LayoutOrder = index })
	end
end

-- Town Hub station panels ----------------------------------------------------------------------------------------

local function section(order: number, label: string): TextLabel
	return newLabel(stationContent, { Size = UDim2.new(1, 0, 0, 28), Text = label, Font = DISPLAY_FONT,
		TextSize = 21, TextColor3 = COLORS.Gold, TextStrokeTransparency = 0.1, LayoutOrder = order })
end

local function paragraph(order: number, label: string, color: Color3?): TextLabel
	return newLabel(stationContent, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = label,
		TextWrapped = true, TextColor3 = color or COLORS.Text, TextSize = 14, LayoutOrder = order })
end

local function itemRow(order: number, title: string, desc: string, buttonText: string, buttonColor: Color3,
	enabled: boolean, onClick: () -> ()): GuiButton
	local frame: Frame = create("Frame", { Size = UDim2.new(1, -6, 0, 72), BackgroundColor3 = COLORS.PanelLight,
		LayoutOrder = order }, stationContent)
	round(frame, 12)
	outline(frame, COLORS.Stroke, 2.5)
	topLit(frame, 0.78)
	pad(frame, 10)
	newLabel(frame, { Size = UDim2.new(1, -170, 0, 22), Text = title, Font = DISPLAY_FONT, TextSize = 19,
		TextStrokeTransparency = 0.2 })
	newLabel(frame, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -170, 0, 28), Text = desc,
		TextColor3 = COLORS.Muted, TextSize = 14, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	local button = newButton(frame, buttonText, buttonColor, onClick, { AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(150, 44), TextSize = 18 })
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
	shopFrame.Visible = false
	for _, scrim in windowScrims do
		scrim.Visible = false
	end
end

-- The dark veil behind a station / shop window (the pack's Window does the same): it says the game is waiting for
-- an answer, and clicking it closes the window.
local function newScrim(layer: Frame): GuiObject
	local scrim: TextButton = create("TextButton", { Name = "Scrim", Size = UDim2.fromScale(1, 1), Text = "",
		AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
		BorderSizePixel = 0, Visible = false }, layer)
	scrim.Activated:Connect(closeStation)
	table.insert(windowScrims, scrim)
	return scrim
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
	local stepper: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, if Shard then 60 else 40), BackgroundTransparency = 1,
		LayoutOrder = nextOrder() }, stationContent)
	local stepLayout = list(stepper, Enum.FillDirection.Horizontal, 8)
	stepLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	local function stepButton(text: string, delta: number, layoutOrder: number)
		local target = math.clamp(selectedCorruption + delta, 0, maxTier)
		local button = newButton(stepper, text, COLORS.PanelLight, function()
			selectedCorruption = target
			renderStation()
		end, { Size = UDim2.fromOffset(if Shard then 76 else 48, 36), LayoutOrder = layoutOrder })
		setEnabled(button, target ~= selectedCorruption, COLORS.PanelLight)
	end
	stepButton("-10", -10, 1)
	stepButton("-1", -1, 2)
	newLabel(stepper, { Size = UDim2.fromOffset(if Shard then 200 else 250, 36), TextXAlignment = Enum.TextXAlignment.Center,
		Font = DISPLAY_FONT, TextSize = 16, LayoutOrder = 3,
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

local STATION_RENDERERS: { [string]: () -> () } = {
	RiftGate = renderRiftGate,
	AscensionPedestal = renderPedestal,
	SparkSanctum = renderSanctum,
	RiftShrine = function()
		renderShop()
	end,
	Blacksmith = StationPanels.Renderers.Blacksmith,
	LegionHall = StationPanels.Renderers.LegionHall,
	StarForge = StationPanels.Renderers.StarForge,
	QuestBoard = StationPanels.Renderers.QuestBoard,
	HallOfChampions = StationPanels.Renderers.HallOfChampions,
	Inventory = StationPanels.Renderers.Inventory,
}

local STATION_FETCHES_DATA: { [string]: boolean } = {
	AscensionPedestal = true, SparkSanctum = true, QuestBoard = true, HallOfChampions = true,
}

renderStation = function()
	if openStation == "RiftShrine" then
		renderShop() -- the store has its own window
		return
	end
	local key = openStation
	local renderer = if key then STATION_RENDERERS[key] else nil
	if not key or not renderer then
		return
	end
	local look = AssetRegistry.TownStations[key]
	stationTitle.Text = if key == "Inventory" then "🎒 Bag & Loadout" elseif look then ("%s %s"):format(look.Icon, look.Name) else key
	local color = WINDOW_COLORS[key] or WINDOW_COLORS.RiftGate
	setWindowColor(stationWindow, color)
	if not Shard then
		stationContent.BackgroundColor3 = insetColor(color)
	end
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
	if type(payload) ~= "table" or type(payload.Station) ~= "string" or (inRun() and payload.Station ~= "Inventory") then
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
	for _, scrim in windowScrims do
		scrim.Visible = scrim.Parent == (if key == "RiftShrine" then shopFrame.Parent else stationFrame.Parent)
	end
	if key == "RiftShrine" then
		stationFrame.Visible = false
		shopFrame.Visible = true
		focusFirstButton(shopGrid)
		return
	end
	shopFrame.Visible = false
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

toggleInventory = function()
	if openStation == "Inventory" then
		closeStation()
	else
		onOpenStation({ Station = "Inventory" })
	end
end

local function buildTownMenu()
	local gui = newLayer("RiftTownMenu", 12, false)
	-- Bottom-left, clear of the status column (bars + Bag button) above it.
	townMenu = create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(76, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, gui)
	list(townMenu, Enum.FillDirection.Vertical, 10)
	if Shard then
		townMenu.Size = UDim2.fromOffset(100, 0)
		for order, entry in TOWN_MENU do
			local look = AssetRegistry.TownStations[entry.Station]
			local slot: Frame = create("Frame", { Size = UDim2.fromOffset(100, 124), BackgroundTransparency = 1,
				LayoutOrder = order }, townMenu)
			Shard.IconButton.new({ icon = Shard.Icons[entry.PackIcon], variant = "lg",
				family = familyFor(if look then look.Color else COLORS.Accent), parent = slot, onClick = function()
					openStationFromMenu(entry.Station)
				end })
			local caption = newLabel(slot, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.new(1, 20, 0, 22), Text = entry.Label, Font = DISPLAY_FONT, TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Center })
			create("UIStroke", { Color = COLORS.Stroke, Thickness = 3, LineJoinMode = Enum.LineJoinMode.Round }, caption)
		end
		return
	end
	for order, entry in TOWN_MENU do
		local look = AssetRegistry.TownStations[entry.Station]
		local color = if look then look.Color else COLORS.Accent
		local button = newButton(townMenu, "", color:Lerp(Color3.new(0, 0, 0), 0.15), function()
			openStationFromMenu(entry.Station)
		end, { Size = UDim2.fromOffset(78, 78), LayoutOrder = order })
		newLabel(button, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 4), Text = if look then look.Icon else "?",
			TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center })
		newLabel(button, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -5), Size = UDim2.new(1, 0, 0, 18),
			Text = entry.Label, Font = DISPLAY_FONT, TextSize = 17, TextStrokeTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Center })
	end
end

-- Rift Shrine store -----------------------------------------------------------------------------------------------
-- A dedicated shop window: header with wallet pills and close button, category tabs on the left, a hover info bar
-- and a grid of colour-coded item cards (striped icon box, corner tag, big price button).

local SHOP_TAB_HINTS: { [string]: string } = {
	Featured = "The most popular boosts and passes. Hover a card to see what it does.",
	Boosts = "One-time boosts for your next runs, or for the whole server.",
	Passes = "Permanent upgrades that stay on your account forever.",
	Rebirth = "Keep your progress when you Rift Rebirth.",
}


-- Card builders stay scoped in this block (UIController is close to Luau's 200-local limit).
local buildShop: () -> ()
do
	local function shopItemInfo(item: ShopItem): (number, boolean, string)
		if item.Kind == "Pass" then
			local pass = MonetizationConfig.Passes[item.Key]
			return pass.Price, player:GetAttribute(pass.Attribute) == true, pass.Name
		end
		local product = MonetizationConfig.Products[item.Key]
		return product.Price, false, product.Name
	end

	local function buildShardShopCard(item: ShopItem, order: number)
		local price, owned, fullName = shopItemInfo(item)
		local buy = function()
			if not owned then
				requestPurchase(item.Kind, item.Key)
			end
		end
		local family = familyFor(item.Color)
		local card = Shard.Card.new({ name = item.Title, variant = "sm", family = family,
			icon = if item.PackIcon then Shard.Icons[item.PackIcon] else nil,
			price = if owned then "Owned" else ("R$ %s"):format(formatNumber(price)), layoutOrder = order,
			activated = buy })
		-- The price gem sits inside the card and swallows its own clicks, so it buys too.
		card.Button.Root.MouseButton1Click:Connect(buy)
		if owned then
			card.Button:Disable()
		end
		if not item.PackIcon then
			newLabel(card.Thumb, { Size = UDim2.fromScale(1, 1), Text = item.Icon, TextSize = 64, ZIndex = 8,
				TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1 })
		end
		card.Root.Parent = shopGrid
		if item.Tag then
			Shard.Badge.attachTo(Shard.Badge.new({ text = item.Tag, variant = "sm", family = if family == "red" then "amber" else "red",
				static = true }), card.Root)
		end
		local blurb = ("<b>%s</b>  ·  %s"):format(fullName, SHOP_BLURBS[item.Key] or "")
		card.Root.MouseEnter:Connect(function()
			shopInfo.Text = blurb
		end)
		card.Root.SelectionGained:Connect(function()
			shopInfo.Text = blurb
		end)
	end

	local function buildShopCard(item: ShopItem, order: number)
		local price, owned, fullName = shopItemInfo(item)
		local card: Frame = create("Frame", { BackgroundColor3 = item.Color, LayoutOrder = order }, shopGrid)
		round(card, 10)
		outline(card, COLORS.Stroke, 3)
		topLit(card, 0.72)

		local iconBox: Frame = create("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 110),
			BackgroundColor3 = item.Color:Lerp(Color3.new(1, 1, 1), 0.12) }, card)
		round(iconBox, 8)
		create("UIStroke", { Color = edgeColor(item.Color), Thickness = 2.5 }, iconBox)
		addStripes(iconBox, 8)
		newLabel(iconBox, { Size = UDim2.fromScale(1, 1), Text = item.Icon, TextSize = 62,
			TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1 })

		newLabel(card, { Position = UDim2.fromOffset(4, 122), Size = UDim2.new(1, -8, 0, 26), Text = item.Title,
			Font = DISPLAY_FONT, TextSize = 21, TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = false })

		local buy = newButton(card, if owned then "Owned" else ("R$ %s"):format(formatNumber(price)), COLORS.Robux, function()
			requestPurchase(item.Kind, item.Key)
		end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -9), Size = UDim2.new(1, -18, 0, 46),
			TextSize = 22 })
		setEnabled(buy, not owned, COLORS.Robux)

		if item.Tag then
			local tag: TextLabel = newLabel(card, { Position = UDim2.fromOffset(-6, -9), Size = UDim2.fromOffset(0, 24),
				AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = edgeColor(item.Color):Lerp(item.Color, 0.35),
				Text = item.Tag, Font = DISPLAY_FONT, TextSize = 15, TextStrokeTransparency = 0, ZIndex = 3 })
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tag)
			round(tag, 6)
			outline(tag, COLORS.Stroke, 2.5)
		end

		local blurb = ("<b>%s</b>  ·  %s"):format(fullName, SHOP_BLURBS[item.Key] or "")
		card.MouseEnter:Connect(function()
			shopInfo.Text = blurb
		end)
		buy.SelectionGained:Connect(function()
			shopInfo.Text = blurb
		end)
	end

	renderShop = function()
		local data = profile
		if data then
			local prefix = function(key: string): string
				return if Shard then currencyIcon(key) .. " " else ""
			end
			shopWallet.RiftDust.Text = prefix("RiftDust") .. formatNumber(tonumber(data.RiftDust) or 0)
			shopWallet.RebirthSpark.Text = prefix("RebirthSpark") .. formatNumber(tonumber(data.RebirthSparksAvailable) or 0)
		end
		for name, button in shopTabs do
			local selectedColor = if Shard then COLORS.Gold else Color3.fromRGB(95, 210, 255) -- cyan would vanish on the cyan panel
			setEnabled(button, true, if name == shopTab then selectedColor else Color3.fromRGB(84, 92, 140))
		end
		shopInfo.Text = SHOP_TAB_HINTS[shopTab] or ""
		local scroll = shopGrid.CanvasPosition
		clearGuiChildren(shopGrid)
		local order = 0
		for _, item in SHOP_ITEMS do
			if table.find(item.Tabs, shopTab) then
				order += 1
				if Shard then
					buildShardShopCard(item, order)
				else
					buildShopCard(item, order)
				end
			end
		end
		shopGrid.CanvasPosition = scroll
	end

	local function buildShardShop()
		local gui = newLayer("RiftShop", 31, false)
		newScrim(gui)
		local panel = Shard.Panel.new({ title = "🔮 Shop", family = "cyan", width = 1000, height = 620, headHeight = 80 })
		shopFrame = panel.Root :: Frame
		shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		shopFrame.Position = UDim2.fromScale(0.5, 0.5)
		shopFrame.Visible = false
		panel.Title.TextSize = 32

		for order, key in { "RiftDust", "RebirthSpark" } do
			local chip = Shard.Chip.new({ text = currencyIcon(key) .. " 0", variant = "sm", family = "slate", static = true,
				width = 140, parent = panel.Tools })
			chip.Root.LayoutOrder = order
			shopWallet[key] = chip.Label
		end
		Shard.IconButton.new({ icon = Shard.Icons.Close, variant = "sm", family = "red", parent = panel.Tools,
			onClick = closeStation }).Root.LayoutOrder = 3

		local body = panel.Body :: Frame
		local sidebar: Frame = create("Frame", { Size = UDim2.new(0, 180, 1, 0), BackgroundTransparency = 1 }, body)
		list(sidebar, Enum.FillDirection.Vertical, 12)
		for order, name in SHOP_TABS do
			shopTabs[name] = newButton(sidebar, name, Color3.fromRGB(84, 92, 140), function()
				shopTab = name
				shopGrid.CanvasPosition = Vector2.zero
				renderShop()
			end, { Size = UDim2.new(1, 0, 0, 54), TextSize = 22, LayoutOrder = order })
		end

		local infoBar = Shard.Inset.new({ family = "cyan", size = UDim2.new(1, -196, 0, 58), parent = body, scroll = false })
		infoBar.Root.Position = UDim2.fromOffset(196, 0)
		shopInfo = newLabel(infoBar.Body, { Size = UDim2.fromScale(1, 1), TextSize = 17, TextColor3 = COLORS.Muted,
			TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd })
		-- The inset's padding is tuned for lists; a one-line strip needs less.
		local infoPad = infoBar.Body:FindFirstChildOfClass("UIPadding")
		if infoPad then
			infoPad.PaddingTop = UDim.new(0, 6)
			infoPad.PaddingBottom = UDim.new(0, 6)
		end

		local grid = Shard.Inset.new({ family = "cyan", size = UDim2.new(1, -196, 1, -72), parent = body, scroll = true })
		grid.Root.Position = UDim2.fromOffset(196, 72)
		shopGrid = grid.Body :: ScrollingFrame
		if grid.Layout then
			grid.Layout:Destroy()
		end
		local cardSize: Vector2 = Shard.Card.size("sm")
		create("UIGridLayout", { CellSize = UDim2.fromOffset(cardSize.X, cardSize.Y), CellPadding = UDim2.fromOffset(18, 26),
			SortOrder = Enum.SortOrder.LayoutOrder }, shopGrid)

		panel.Root.Parent = gui
	end

	buildShop = function()
		if Shard then
			buildShardShop()
			return
		end
		local gui = newLayer("RiftShop", 31, false)
		newScrim(gui)
		shopFrame = newPanel(gui, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54),
			Size = UDim2.fromOffset(900, 610), BackgroundColor3 = WINDOW_COLORS.Shop, Visible = false })

		-- Header: title, wallet pills and the close button.
		local header: Frame = create("Frame", { Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = headerColor(WINDOW_COLORS.Shop) },
			shopFrame)
		round(header, 14)
		topLit(header, 0.8)
		newLabel(header, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0.5, 0, 1, 0), Text = "🔮 Shop",
			Font = DISPLAY_FONT, TextSize = 36, TextStrokeTransparency = 0 })
		local right: Frame = create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(0, 52), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, header)
		local rightLayout = list(right, Enum.FillDirection.Horizontal, 10)
		rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		for order, key in { "RiftDust", "RebirthSpark" } do
			local pill: Frame = create("Frame", { Size = UDim2.fromOffset(0, 44), AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Color3.fromRGB(70, 80, 125), LayoutOrder = order }, right)
			round(pill, 10)
			outline(pill, COLORS.Stroke, 3)
			topLit(pill, 0.75)
			create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }, pill)
			local row = list(pill, Enum.FillDirection.Horizontal, 6)
			row.VerticalAlignment = Enum.VerticalAlignment.Center
			newLabel(pill, { Size = UDim2.fromOffset(26, 30), Text = currencyIcon(key), TextSize = 22, LayoutOrder = 1,
				TextStrokeTransparency = 1 })
			shopWallet[key] = newLabel(pill, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = "0",
				Font = DISPLAY_FONT, TextSize = 22, TextStrokeTransparency = 0, LayoutOrder = 2 })
		end
		newButton(right, "X", COLORS.Bad, closeStation, { Size = UDim2.fromOffset(52, 52), TextSize = 30, LayoutOrder = 3 })

		-- Category tabs.
		local sidebar: Frame = create("Frame", { Position = UDim2.fromOffset(16, 90), Size = UDim2.new(0, 180, 1, -106),
			BackgroundTransparency = 1 }, shopFrame)
		list(sidebar, Enum.FillDirection.Vertical, 12)
		for order, name in SHOP_TABS do
			shopTabs[name] = newButton(sidebar, name, Color3.fromRGB(84, 92, 140), function()
				shopTab = name
				shopGrid.CanvasPosition = Vector2.zero
				renderShop()
			end, { Size = UDim2.new(1, 0, 0, 54), TextSize = 22, LayoutOrder = order })
		end

		-- Hover info bar and the card grid.
		local infoBar: Frame = create("Frame", { Position = UDim2.fromOffset(212, 90), Size = UDim2.new(1, -228, 0, 48),
			BackgroundColor3 = Color3.fromRGB(10, 14, 26) }, shopFrame)
		round(infoBar, 10)
		outline(infoBar, COLORS.Stroke, 2)
		shopInfo = newLabel(infoBar, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextSize = 16,
			TextColor3 = COLORS.Muted, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd })

		shopGrid = create("ScrollingFrame", {
			Position = UDim2.fromOffset(212, 150),
			Size = UDim2.new(1, -228, 1, -166),
			BackgroundColor3 = insetColor(WINDOW_COLORS.Shop),
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = Color3.fromRGB(120, 220, 255),
		}, shopFrame)
		round(shopGrid, 12)
		outline(shopGrid, COLORS.Stroke, 3)
		create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 18),
			PaddingBottom = UDim.new(0, 16) }, shopGrid)
		create("UIGridLayout", { CellSize = UDim2.fromOffset(148, 214), CellPadding = UDim2.fromOffset(14, 20),
			SortOrder = Enum.SortOrder.LayoutOrder }, shopGrid)
	end
end

local function buildStationPanel()
	local gui = newLayer("RiftStations", 30, false)
	newScrim(gui)
	stationWindow = newWindow(gui, WINDOW_COLORS.RiftGate, { AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromOffset(660, 540), Visible = false }, closeStation)
	stationFrame = stationWindow.Frame
	stationTitle = stationWindow.Title
	if Shard then
		-- The pack's recessed "creux": an untinted darkening of whatever panel colour sits behind it.
		local inset = Shard.Inset.new({ family = "violet", size = UDim2.fromScale(1, 1), parent = stationWindow.Body,
			scroll = true, padding = 10 })
		stationContent = inset.Body :: ScrollingFrame
		return
	end
	stationContent = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = insetColor(WINDOW_COLORS.RiftGate),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.new(1, 1, 1),
	}, stationWindow.Body)
	round(stationContent, 12)
	outline(stationContent, COLORS.Stroke, 3)
	create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 14) }, stationContent)
	list(stationContent, Enum.FillDirection.Vertical, 10)
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

	-- Run relics and curses under the bars.
	local runInfo = if inRun() then StationPanels.RunInfoText() else ""
	runInfoLabel.Visible = runInfo ~= ""
	runInfoLabel.Text = runInfo

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
	buildShop()
	buildTownMenu()
	-- StationPanels draws with UIController's own helpers, so every window looks the same.
	StationPanels.Init({
		create = create, newLabel = newLabel, round = round, outline = outline, topLit = topLit, pad = pad, list = list,
		newButton = newButton, setEnabled = setEnabled, newBar = newBar, setBar = setBar, section = section,
		paragraph = paragraph, currencyIcon = currencyIcon, formatNumber = formatNumber, toRoman = toRoman,
		inRun = inRun, newPanel = newPanel, newLayer = newLayer, COLORS = COLORS, DISPLAY_FONT = DISPLAY_FONT,
		renderStation = function()
			renderStation()
		end,
		profile = function(): Payload?
			return profile
		end,
		stationData = function(): any
			return stationData
		end,
		content = function(): ScrollingFrame
			return stationContent
		end,
		liveMastery = function(): any
			return liveMastery
		end,
	})

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
	Remotes.GetEvent("Celebrate").OnClientEvent:Connect(StationPanels.Celebrate)
	Remotes.GetEvent("MasteryUpdated").OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" or type(data.Weapon) ~= "string" then
			return
		end
		liveMastery = { Weapon = data.Weapon, Level = tonumber(data.Level) or 1, XP = tonumber(data.XP) or 0,
			Paragon = tonumber(data.Paragon) or 0 }
		refreshMasteryBar()
		if openStation == "Inventory" or openStation == "LegionHall" then
			renderStation()
		end
	end)

	-- I / B (or the gamepad's Select / D-pad down) open the Bag anywhere.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.I or key == Enum.KeyCode.B or key == Enum.KeyCode.ButtonSelect or key == Enum.KeyCode.DPadDown then
			toggleInventory()
		end
	end)
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
		elseif (name == "RunRelics" or name == "RunCurses" or string.sub(name, 1, 3) == "Has") and openStation ~= nil then
			renderStation() -- relic / curse lists and pass-granted slots
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
