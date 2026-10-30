--!strict
-- StarterPlayerScripts/Client/Controllers/RiftGateScene.luau
-- The Central Rift Gate window drawn as a world map: 8 islands along a dotted path (worlds you can enter glow in
-- their colour, locked ones are dark with a padlock, worlds not built yet are shadowed "SOON"), a Corruption dial
-- with the reward multiplier as a big number, and the portal panel with the Open Portal button. The run itself is
-- started by UIController (kit.startRun), which owns the StartRun remote and closes the window on success.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local RoomAsciiTemplates = require(Shared:WaitForChild("RoomAsciiTemplates"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local RiftGateScene = {}

local K: any = nil -- UIController's kit, set by Init

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon

local MAX_WORLDS = 8
-- Planned worlds (game.md Section 4) shown on the map before their rooms exist.
local WORLD_NAMES = { "Mushroom Wilds", "Toy Kingdom", "Haunted Metro", "Frozen Citadel", "Neon Grid", "Dessert Wastes",
	"Sunken Archive", "Volcanic Factory" }
local WORLD_COLORS = { Color3.fromHex("8fd16a"), Color3.fromHex("ff9ad5"), Color3.fromHex("9b8cff"), Color3.fromHex("8fe3ff"),
	Color3.fromHex("3dffd0"), Color3.fromHex("ffcf7a"), Color3.fromHex("5aa8ff"), Color3.fromHex("ff7a4a") }
-- Island centres on the map (fractions of its size): a snake, left to right then back.
local ISLANDS = { Vector2.new(0.12, 0.3), Vector2.new(0.37, 0.24), Vector2.new(0.62, 0.3), Vector2.new(0.87, 0.24),
	Vector2.new(0.87, 0.72), Vector2.new(0.62, 0.78), Vector2.new(0.37, 0.72), Vector2.new(0.12, 0.78) }
local MAP_HEIGHT = 222
local ISLAND_SIZE = 62
local GATE_COLORS = {
	Sky = Color3.fromHex("141a33"),
	Panel = Color3.fromHex("232946"),
	Dark = Color3.fromHex("1b2035"),
	Path = Color3.fromHex("ffd27a"),
	PathDim = Color3.fromHex("3a4060"),
	Corrupt = Color3.fromHex("c04bff"),
}

local selectedWorld = 1
local selectedCorruption = 0

-- The highest Corruption tier unlocked in a world, or nil if the world is locked.
local function unlockedTierFor(world: number): number?
	local data = K.profile()
	local unlocked = if data then data.UnlockedWorlds else nil
	if type(unlocked) ~= "table" then
		return nil
	end
	local value = unlocked[world] or unlocked[tostring(world)]
	return if type(value) == "number" then value else nil
end

local function worldExists(world: number): boolean
	return RoomAsciiTemplates.GetWorld(world) ~= nil
end

local function worldMap(order: number)
	local map = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, MAP_HEIGHT), BackgroundColor3 = GATE_COLORS.Sky, LayoutOrder = order })
	map.ClipsDescendants = true
	-- A few stars.
	local rng = Random.new(7)
	for _ = 1, 26 do
		local size = rng:NextInteger(2, 4)
		local star = circle(map, { Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = rng:NextNumber(0.3, 0.8) })
		if rng:NextNumber() < 0.3 then
			tween(star, TweenInfo.new(rng:NextNumber(0.8, 1.6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 1 })
		end
	end

	-- The dotted path between islands, lit up to the furthest open world.
	for world = 1, MAX_WORLDS - 1 do
		local from, to = ISLANDS[world], ISLANDS[world + 1]
		local lit = unlockedTierFor(world + 1) ~= nil
		for step = 1, 4 do
			local t = step / 5
			local point = from:Lerp(to, t)
			circle(map, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(point.X, point.Y), Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = if lit then GATE_COLORS.Path else GATE_COLORS.PathDim })
		end
	end

	for world = 1, MAX_WORLDS do
		local tier = unlockedTierFor(world)
		local exists = worldExists(world)
		local open = tier ~= nil and exists
		local selected = world == selectedWorld
		local color = WORLD_COLORS[world]
		local center = ISLANDS[world]
		local holder: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(center.X, center.Y),
			Size = UDim2.fromOffset(ISLAND_SIZE, ISLAND_SIZE), BackgroundTransparency = 1, ZIndex = 2 }, map)
		if selected then
			local glow = icon(holder, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(2.3, 2.3), ImageColor3 = color, ImageTransparency = 0.45, ZIndex = 1 })
			tween(glow, SceneKit.PULSE, { ImageTransparency = 0.1 })
		end
		local island: TextButton = K.create("TextButton", { Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false, ZIndex = 3,
			BackgroundColor3 = if open then color:Lerp(Color3.new(0, 0, 0), 0.45) else GATE_COLORS.Dark }, holder)
		K.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, island)
		K.create("UIStroke", { Color = if selected then Color3.new(1, 1, 1) elseif open then color else K.COLORS.Stroke,
			Thickness = if selected then 4 else 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, island)
		local scale: UIScale = K.create("UIScale", { Scale = if selected then 1.1 else 1 }, island)
		if open then
			K.newLabel(island, { Size = UDim2.fromScale(1, 1), Text = tostring(world), Font = K.DISPLAY_FONT, TextSize = 30, ZIndex = 4,
				TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0 })
			local badge: TextLabel = K.newLabel(island, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Text = (" C%d "):format(tier :: number),
				Font = K.DISPLAY_FONT, TextSize = 12, BackgroundTransparency = 0, BackgroundColor3 = GATE_COLORS.Corrupt, ZIndex = 5 })
			K.round(badge, 6)
		elseif exists then
			icon(island, Icons.UI_Lock, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.42),
				ImageColor3 = Color3.fromHex("8a93a8"), ZIndex = 4 })
		else
			K.newLabel(island, { Size = UDim2.fromScale(1, 1), Text = "SOON", Font = K.DISPLAY_FONT, TextSize = 13, ZIndex = 4,
				TextColor3 = Color3.fromHex("6a7290"), TextXAlignment = Enum.TextXAlignment.Center })
		end
		K.newLabel(holder, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 4), Size = UDim2.fromOffset(130, 16),
			Text = WORLD_NAMES[world], Font = K.DISPLAY_FONT, TextSize = 13, ZIndex = 4, TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if open then Color3.new(1, 1, 1) else Color3.fromHex("6a7290"), TextStrokeTransparency = if open then 0.2 else 1 })

		if not selected then
			SceneKit.hoverGrow(island, scale, 1.08)
		end
		island.Activated:Connect(function()
			if not open then
				Sfx.Play("UI_Error", 0.5)
				return
			end
			if selectedWorld ~= world then
				selectedWorld = world
				selectedCorruption = math.min(selectedCorruption, tier :: number)
				Sfx.Play("UI_Tab", 0.5)
				K.renderStation()
			end
		end)
	end
end

local function corruptionDial(order: number)
	local maxTier = unlockedTierFor(selectedWorld) or 0
	selectedCorruption = math.clamp(selectedCorruption, 0, maxTier)
	local panel = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 84), BackgroundColor3 = GATE_COLORS.Panel, LayoutOrder = order })
	K.newLabel(panel, { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(140, 18), Text = "Corruption", TextSize = 14,
		TextColor3 = K.COLORS.Muted })
	K.newLabel(panel, { Position = UDim2.fromOffset(14, 26), Size = UDim2.fromOffset(140, 50),
		Text = ("Tier <b>%d</b><font size='15' color='#%s'> / %d</font>"):format(selectedCorruption, K.COLORS.Muted:ToHex(), maxTier),
		Font = K.DISPLAY_FONT, TextSize = 32, TextColor3 = if selectedCorruption > 0 then GATE_COLORS.Corrupt else Color3.new(1, 1, 1),
		TextStrokeTransparency = 0 })

	if maxTier == 0 then
		-- Nothing to choose yet: say how to unlock it instead of showing dead buttons.
		K.newLabel(panel, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(250, 40),
			Text = "Beat the Room 10 boss to unlock harder tiers with bigger rewards", TextSize = 14, TextWrapped = true,
			TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center })
	end
	local steps: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(240, 40), BackgroundTransparency = 1, Visible = maxTier > 0 }, panel)
	local layout = K.list(steps, Enum.FillDirection.Horizontal, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for index, delta in { -10, -1, 1, 10 } do
		local target = math.clamp(selectedCorruption + delta, 0, maxTier)
		local button = SceneKit.pill(steps, (if delta > 0 then "+" else "") .. tostring(delta), GATE_COLORS.Corrupt, target ~= selectedCorruption,
			function()
				selectedCorruption = target
				Sfx.Play("UI_Tab", 0.4)
				K.renderStation()
			end, { Size = UDim2.fromOffset(54, 38), TextSize = 17 })
		button.LayoutOrder = index
	end

	K.newLabel(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(150, 18), Text = "Rewards",
		TextSize = 14, TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Right })
	K.newLabel(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 26), Size = UDim2.fromOffset(150, 50),
		Text = ("x%.2f"):format(FormulaEngine.GetCorruptionEcoMult(selectedCorruption)), Font = K.DISPLAY_FONT, TextSize = 34,
		TextColor3 = K.COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0 })
end

local function portal(order: number)
	local panel = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 86), BackgroundColor3 = GATE_COLORS.Panel, LayoutOrder = order })
	panel.ClipsDescendants = true
	local color = WORLD_COLORS[selectedWorld]
	local glow = icon(panel, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 160),
		ScaleType = Enum.ScaleType.Stretch, ImageColor3 = color, ImageTransparency = 0.75 })
	tween(glow, SceneKit.PULSE, { ImageTransparency = 0.55 })

	local data = K.profile()
	local tokens = if data then tonumber(data.SuperchargedTokens) or 0 else 0
	local left = if tokens > 0
		then ("⚡ <b>Supercharged</b>\nx%d Dust this run (%d left)"):format(MonetizationConfig.SUPERCHARGE_DUST_MULT, tokens)
		else ("<b>World %d</b>\n%s"):format(selectedWorld, WORLD_NAMES[selectedWorld])
	K.newLabel(panel, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.27, 0, 1, 0), Text = left, TextSize = 15, TextWrapped = true,
		TextColor3 = if tokens > 0 then Color3.fromRGB(120, 255, 200) else Color3.new(1, 1, 1), TextStrokeTransparency = 0.2 })
	K.newLabel(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0.27, 0, 1, 0),
		Text = "Anchors on Rooms 5, 10, 15… bank your loot", TextSize = 13, TextWrapped = true, TextColor3 = K.COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Right })

	local starting = K.isStartingRun()
	local open = unlockedTierFor(selectedWorld) ~= nil and worldExists(selectedWorld)
	local button = K.newButton(panel, if starting then "Opening…" else "🌀 Open Portal", K.COLORS.Accent, function()
		if K.isStartingRun() or not open then
			return
		end
		Sfx.Play("Gate_Open", 0.7)
		K.startRun(selectedWorld, selectedCorruption)
		K.renderStation()
	end, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0.42, 0, 0, 56), TextSize = 22 })
	K.setEnabled(button, open and not starting, K.COLORS.Accent)
end

local function renderRiftGate()
	if unlockedTierFor(selectedWorld) == nil or not worldExists(selectedWorld) then
		selectedWorld = 1
	end
	worldMap(1)
	corruptionDial(2)
	portal(3)
end

RiftGateScene.Render = renderRiftGate

function RiftGateScene.Init(kit: any)
	K = kit
end

return RiftGateScene
