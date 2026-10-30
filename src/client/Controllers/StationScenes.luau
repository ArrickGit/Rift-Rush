--!strict
-- StarterPlayerScripts/Client/Controllers/StationScenes.luau
-- The station windows drawn as game scenes instead of text lists:
--   * Spark Sanctum: the Ascension Shop as a skill tree. One row per tier, each node an icon with level pips, and a
--     detail card that shows the selected node's effect and its Upgrade button. Bought levels burst on the node.
--   * Quest Board: daily quests as parchment cards pinned to the board (big progress counter, reward icons, a
--     DONE stamp once claimed) and bounties as wanted posters. Claimed rewards fly up out of the button.
--
-- Uses the same kit as StationPanels (UIController's drawing helpers, passed in through StationPanels.Init) plus
-- SceneKit's shared helpers, and draws into kit.content(). Icons, textures and sounds come from AssetRegistry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AscensionShopConfig = require(Shared:WaitForChild("AscensionShopConfig"))
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local QuestConfig = require(Shared:WaitForChild("QuestConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Payload = { [string]: any }

local StationScenes = {}

local K: any = nil -- UIController's kit, set by Init
local purchaseRemote: RemoteEvent
local respecRemote: RemoteEvent
local claimQuestRemote: RemoteEvent

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local UiTex = AssetRegistry.UiTextures

local PULSE = SceneKit.PULSE
local POP = SceneKit.POP
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon
local hoverGrow = SceneKit.hoverGrow
local burst = SceneKit.burst
local currencyColor = SceneKit.currencyColor

-- Spark Sanctum ---------------------------------------------------------------------------------------------------

local TIER_ROWS: { { Label: string, Ids: { string } } } = {
	{ Label = "I", Ids = { "AS_T1_01", "AS_T1_02", "AS_T1_03", "AS_T1_04", "AS_T1_05" } },
	{ Label = "II", Ids = { "AS_T2_01", "AS_T2_02", "AS_T2_03", "AS_T2_04" } },
	{ Label = "III", Ids = { "AS_T3_01", "AS_T3_02", "AS_T3_03", "AS_T3_04" } },
	{ Label = "IV", Ids = { "AS_T4_01", "AS_T4_02" } },
	{ Label = "∞", Ids = { "AS_INF_01", "AS_INF_02" } },
}
local INFINITE_UNLOCK_REBIRTH = 11 -- mirrors AscensionShopService
local ROW_HEIGHT = 76
local NODE_SIZE = 56
local MAX_PIPS = 5 -- longer nodes show "4/10" instead of a row of dots

local SANCTUM_COLORS = {
	Locked = Color3.fromHex("3a4258"),
	Open = Color3.fromHex("5d4a8f"),
	Owned = Color3.fromHex("8a6bf0"),
	Maxed = Color3.fromHex("ffb724"),
	Soon = Color3.fromHex("4a5068"),
	Line = Color3.fromHex("2a2f40"),
	LineLit = Color3.fromHex("ffcf5a"),
	Spark = Color3.fromHex("ff6fa0"),
}

local selectedNode: string? = nil
local respecArmed = false
local lastNodeLevels: { [string]: number } = {}

type NodeState = { Id: string, Level: number, NextCost: number?, Unlocked: boolean }

local function nodeStates(): { [string]: NodeState }
	local states: { [string]: NodeState } = {}
	local data = K.stationData()
	if type(data) == "table" then
		for _, state in data do
			if type(state) == "table" and type(state.Id) == "string" then
				states[state.Id] = { Id = state.Id, Level = tonumber(state.Level) or 0, NextCost = tonumber(state.NextCost),
					Unlocked = state.Unlocked == true }
			end
		end
	end
	return states
end

local function sparks(): number
	local data = K.profile()
	return if data then tonumber(data.RebirthSparksAvailable) or 0 else 0
end

local function shortName(name: string): string
	return (name:gsub("%s*%b()", ""):gsub("^Infinite Spark: ", ""))
end

local function rebirthNeeded(node: AscensionShopConfig.AscensionNode): number
	return if node.FlatCost then INFINITE_UNLOCK_REBIRTH else AscensionShopConfig.TierUnlockRebirth[node.Tier] or 0
end

-- What the node's circle looks like: fill, ring and icon colours.
local function nodeLook(node: AscensionShopConfig.AscensionNode, state: NodeState): (Color3, Color3, Color3)
	if node.ComingSoon then
		return SANCTUM_COLORS.Soon, SANCTUM_COLORS.Line, Color3.fromHex("8890a8")
	elseif not state.Unlocked then
		return SANCTUM_COLORS.Locked, SANCTUM_COLORS.Line, Color3.fromHex("7a8299")
	elseif not state.NextCost then
		return SANCTUM_COLORS.Maxed, Color3.fromHex("fff1b8"), Color3.fromHex("4a2a00")
	elseif state.Level > 0 then
		return SANCTUM_COLORS.Owned, SANCTUM_COLORS.LineLit, Color3.new(1, 1, 1)
	end
	return SANCTUM_COLORS.Open, Color3.fromHex("b9a6ff"), Color3.fromHex("e9e2ff")
end

local function pips(parent: Instance, node: AscensionShopConfig.AscensionNode, level: number)
	local holder: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, NODE_SIZE + 6),
		Size = UDim2.fromOffset(NODE_SIZE + 30, 14), BackgroundTransparency = 1 }, parent)
	if node.MaxLevel > MAX_PIPS then
		local text = if node.MaxLevel > AscensionShopConfig.INFINITE_CAP - 1 then ("Lv %d"):format(level)
			else ("%d/%d"):format(level, node.MaxLevel)
		K.newLabel(holder, { Size = UDim2.fromScale(1, 1), Text = text, Font = K.DISPLAY_FONT, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2,
			TextColor3 = if level > 0 then SANCTUM_COLORS.LineLit else K.COLORS.Muted })
		return
	end
	local layout = K.list(holder, Enum.FillDirection.Horizontal, 3)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local size = 9
	for index = 1, node.MaxLevel do
		local lit = index <= level
		local pip = circle(holder, { Size = UDim2.fromOffset(size, size), LayoutOrder = index,
			BackgroundColor3 = if lit then SANCTUM_COLORS.LineLit else SANCTUM_COLORS.Line })
		K.outline(pip, K.COLORS.Stroke, 1.5)
	end
end

local renderSanctum: () -> ()

local function buildDetail(card: Frame, states: { [string]: NodeState })
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local id = selectedNode
	local node = if id then AscensionShopConfig.GetNode(id) else nil
	local state = if id then states[id] else nil
	if not node or not state or not id then
		return
	end
	local fill, ring, iconColor = nodeLook(node, state)
	local badge = circle(card, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(78, 78), BackgroundColor3 = fill, LayoutOrder = 1 })
	K.outline(badge, ring, 4)
	icon(badge, Icons["Asc_" .. id], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62), ImageColor3 = iconColor })

	K.newLabel(card, { Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 48), Text = shortName(node.Name),
		Font = K.DISPLAY_FONT, TextSize = 21, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, TextStrokeTransparency = 0.1 })
	local maxText = if node.FlatCost then "∞" else tostring(node.MaxLevel)
	K.newLabel(card, { Position = UDim2.fromOffset(0, 134), Size = UDim2.new(1, 0, 0, 20),
		Text = ("Level %d / %s"):format(state.Level, maxText), TextSize = 16, TextColor3 = K.COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Center })
	K.newLabel(card, { Position = UDim2.fromOffset(0, 160), Size = UDim2.new(1, 0, 0, 46), Text = node.EffectPerLevel,
		Font = K.DISPLAY_FONT, TextSize = 19, TextWrapped = true, TextColor3 = SANCTUM_COLORS.LineLit,
		TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.1 })
	K.newLabel(card, { Position = UDim2.fromOffset(0, 206), Size = UDim2.new(1, 0, 1, -276), Text = node.Desc,
		TextSize = 14, TextWrapped = true, TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top })

	local text: string, enabled: boolean, color: Color3 = "", false, K.COLORS.PanelLight
	if node.ComingSoon then
		text = "Coming Soon"
	elseif not state.Unlocked then
		text = ("🔒 Rebirth %s"):format(K.toRoman(rebirthNeeded(node)))
	elseif not state.NextCost then
		text, color = "★ MAXED", K.COLORS.Gold
	else
		local cost = state.NextCost :: number
		enabled = sparks() >= cost
		text = if enabled then ("Upgrade  ✨%d"):format(cost) else ("Need ✨%d"):format(cost)
		color = K.COLORS.Good
	end
	local button = K.newButton(card, text, color, function()
		Sfx.Play("UI_Confirm")
		purchaseRemote:FireServer(id)
	end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -8, 0, 58),
		TextSize = 19 })
	K.setEnabled(button, enabled, color)
end

local function sanctumHeader(order: number)
	local header: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, LayoutOrder = order },
		K.content())
	local pill = K.newPanel(header, { Size = UDim2.fromOffset(220, 50), BackgroundColor3 = Color3.fromHex("3b2a55") })
	local sparkIcon = icon(pill, Icons.Cur_Sparks, { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(40, 40),
		ImageColor3 = SANCTUM_COLORS.Spark })
	tween(sparkIcon, PULSE, { Rotation = 12 })
	K.newLabel(pill, { Position = UDim2.fromOffset(56, 0), Size = UDim2.new(0, 80, 1, 0), Text = K.formatNumber(sparks()),
		Font = K.DISPLAY_FONT, TextSize = 32, TextStrokeTransparency = 0 })
	K.newLabel(pill, { Position = UDim2.fromOffset(128, 0), Size = UDim2.new(1, -132, 1, 0), Text = "Rebirth\nSparks",
		TextSize = 14, TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Left })

	local respec = K.newButton(header, if respecArmed then "Confirm respec?" else "↺ Respec", if respecArmed then K.COLORS.Bad else K.COLORS.PanelLight,
		function()
			if respecArmed then
				respecArmed = false
				respecRemote:FireServer()
				Sfx.Play("UI_Confirm")
			else
				respecArmed = true
				Sfx.Play("UI_Popup")
			end
			K.renderStation()
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(180, 44),
			TextSize = 16 })
	K.setEnabled(respec, not K.inRun(), K.COLORS.PanelLight)
end

renderSanctum = function()
	sanctumHeader(1)
	local states = nodeStates()
	if next(states) == nil then
		K.paragraph(2, "Loading…", K.COLORS.Muted)
		return
	end

	-- Default selection: the first node you could buy right now, else the first unlocked one.
	if not selectedNode or not states[selectedNode] then
		for _, nodeId in AscensionShopConfig.Order do
			local state = states[nodeId]
			local node = AscensionShopConfig.Nodes[nodeId]
			if state and state.Unlocked and state.NextCost and not node.ComingSoon then
				selectedNode = nodeId
				break
			end
		end
		selectedNode = selectedNode or AscensionShopConfig.Order[1]
	end

	local body: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, #TIER_ROWS * ROW_HEIGHT), BackgroundTransparency = 1,
		LayoutOrder = 2 }, K.content())
	local tree: Frame = K.create("Frame", { Size = UDim2.new(0.63, 0, 1, 0), BackgroundTransparency = 1 }, body)
	local card = K.newPanel(body, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.35, 0, 1, 0), BackgroundColor3 = Color3.fromHex("33294d") })
	K.pad(card, 10)

	local profile = K.profile()
	local rebirth = if profile then tonumber(profile.RebirthTier) or 0 else 0
	local nodeRings: { [string]: UIStroke } = {}
	local function refreshSelection()
		for nodeId, ring in nodeRings do
			local node = AscensionShopConfig.Nodes[nodeId]
			local _, ringColor = nodeLook(node, states[nodeId])
			ring.Color = if nodeId == selectedNode then Color3.new(1, 1, 1) else ringColor
			ring.Thickness = if nodeId == selectedNode then 5 else 3
		end
		buildDetail(card, states)
	end

	for rowIndex, row in TIER_ROWS do
		local firstNode = AscensionShopConfig.Nodes[row.Ids[1]]
		local needed = rebirthNeeded(firstNode)
		local rowUnlocked = rebirth >= needed
		local rowFrame: Frame = K.create("Frame", { Position = UDim2.fromOffset(0, (rowIndex - 1) * ROW_HEIGHT),
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT), BackgroundTransparency = 1 }, tree)

		-- Tier badge on the left: the numeral, or a padlock with the Rebirth it needs.
		local badge = circle(rowFrame, { Position = UDim2.fromOffset(0, 10), Size = UDim2.fromOffset(40, 40),
			BackgroundColor3 = if rowUnlocked then SANCTUM_COLORS.Maxed else SANCTUM_COLORS.Locked })
		K.outline(badge, K.COLORS.Stroke, 2.5)
		if rowUnlocked then
			K.newLabel(badge, { Size = UDim2.fromScale(1, 1), Text = row.Label, Font = K.DISPLAY_FONT, TextSize = 18,
				TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromHex("4a2a00"), TextStrokeTransparency = 1 })
		else
			icon(badge, Icons.UI_Lock, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.55, 0.55), ImageColor3 = Color3.fromHex("aab2c8") })
			K.newLabel(rowFrame, { Position = UDim2.fromOffset(-8, 51), Size = UDim2.fromOffset(56, 26),
				Text = ("Rebirth\n<b>%s</b>"):format(K.toRoman(needed)), TextSize = 11, TextColor3 = K.COLORS.Muted,
				TextXAlignment = Enum.TextXAlignment.Center, LineHeight = 0.9 })
		end

		local nodesFrame: Frame = K.create("Frame", { Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -48, 1, 0),
			BackgroundTransparency = 1 }, rowFrame)
		local count = #row.Ids
		local anyOwned = false
		for _, nodeId in row.Ids do
			if states[nodeId] and states[nodeId].Level > 0 then
				anyOwned = true
			end
		end
		-- The branch joining this row's nodes, and the trunk down to the next tier.
		if count > 1 then
			K.create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5 / count, 0, 0, NODE_SIZE / 2 + 2),
				Size = UDim2.new((count - 1) / count, 0, 0, 5), BorderSizePixel = 0,
				BackgroundColor3 = if anyOwned then SANCTUM_COLORS.LineLit else SANCTUM_COLORS.Line }, nodesFrame)
		end
		if rowIndex < #TIER_ROWS then
			K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, NODE_SIZE / 2 + 2),
				Size = UDim2.new(0, 5, 0, ROW_HEIGHT), BorderSizePixel = 0, ZIndex = 0,
				BackgroundColor3 = if anyOwned then SANCTUM_COLORS.LineLit else SANCTUM_COLORS.Line }, nodesFrame)
		end

		for index, nodeId in row.Ids do
			local node = AscensionShopConfig.Nodes[nodeId]
			local state = states[nodeId] or { Id = nodeId, Level = 0, NextCost = nil, Unlocked = false }
			local fill, ringColor, iconColor = nodeLook(node, state)
			local holder: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new((index - 0.5) / count, 0, 0, 2), Size = UDim2.fromOffset(NODE_SIZE, NODE_SIZE),
				BackgroundTransparency = 1, ZIndex = 2 }, nodesFrame)
			local affordable = state.Unlocked and state.NextCost ~= nil and not node.ComingSoon
				and sparks() >= (state.NextCost :: number)
			if affordable then
				-- A soft glow that breathes behind nodes you can buy right now.
				local glow = icon(holder, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1.9, 1.9), ImageColor3 = SANCTUM_COLORS.LineLit, ImageTransparency = 0.6, ZIndex = 1 })
				tween(glow, PULSE, { ImageTransparency = 0.15, Size = UDim2.fromScale(2.2, 2.2) })
			end
			local button: TextButton = K.create("TextButton", { Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false,
				BackgroundColor3 = fill, ZIndex = 3 }, holder)
			K.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, button)
			local ring: UIStroke = K.create("UIStroke", { Color = ringColor, Thickness = 3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
			local scale: UIScale = K.create("UIScale", {}, button)
			nodeRings[nodeId] = ring
			icon(button, Icons["Asc_" .. nodeId], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.6, 0.6), ImageColor3 = iconColor, ZIndex = 4 })
			if node.ComingSoon then
				local tag: TextLabel = K.newLabel(button, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.86),
					Size = UDim2.fromOffset(48, 16), Text = "SOON", Font = K.DISPLAY_FONT, TextSize = 12, ZIndex = 5,
					TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0, BackgroundColor3 = K.COLORS.Bad,
					TextStrokeTransparency = 0.3 })
				K.round(tag, 6)
			end
			pips(holder, node, state.Level)
			hoverGrow(button, scale, 1.1)
			button.Activated:Connect(function()
				if selectedNode ~= nodeId then
					selectedNode = nodeId
					Sfx.Play("UI_Tab", 0.4)
					refreshSelection()
				end
			end)

			local before = lastNodeLevels[nodeId]
			if before and state.Level > before then
				Sfx.Play("UI_Unlock")
				burst(holder, SANCTUM_COLORS.LineLit)
				scale.Scale = 1.4
				tween(scale, POP, { Scale = 1 })
			end
			lastNodeLevels[nodeId] = state.Level
		end
	end
	refreshSelection()
end

-- Quest Board -----------------------------------------------------------------------------------------------------

local INK = Color3.fromHex("4a2e14") -- dark brown "ink" on parchment
local INK_LIGHT = Color3.fromHex("7a5530")
local REWARD_KEYS: { { Field: string, Icon: string, Currency: string } } = {
	{ Field = "Dust", Icon = "Cur_Dust", Currency = "RiftDust" },
	{ Field = "BossCores", Icon = "Cur_BossCores", Currency = "BossCores" },
	{ Field = "RelicShards", Icon = "Cur_RelicShards", Currency = "RelicShards" },
	{ Field = "AnchorTokens", Icon = "Cur_AnchorTokens", Currency = "AnchorToken" },
}

local lastClaimed: { [string]: boolean } = {}

-- Parchment from the Kenney RPG pack, nine-sliced so its border stays crisp at any size.
local function parchment(parent: Instance, image: string?, props: Payload): ImageLabel
	local base: Payload = { BackgroundTransparency = 1, Image = image or UiTex.panel_beige, ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(16, 16, 84, 84) }
	for key, value in props do
		base[key] = value
	end
	return K.create("ImageLabel", base, parent)
end

-- A dark disc with a white icon: reads on parchment and on slate alike.
local function iconDisc(parent: Instance, image: string?, size: number, color: Color3, props: Payload): Frame
	local disc = circle(parent, { Size = UDim2.fromOffset(size, size), BackgroundColor3 = INK })
	for key, value in props do
		(disc :: any)[key] = value
	end
	K.outline(disc, color, 2.5)
	icon(disc, image, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64), ImageColor3 = color })
	return disc
end

local function questBar(parent: Instance, fraction: number, props: Payload): Frame
	local track: Frame = K.create("Frame", { BackgroundColor3 = Color3.fromHex("c9a77a"), BorderSizePixel = 0 }, parent)
	for key, value in props do
		(track :: any)[key] = value
	end
	K.round(track, 7)
	K.outline(track, INK, 2)
	local fill: Frame = K.create("Frame", { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1), BorderSizePixel = 0,
		BackgroundColor3 = if fraction >= 1 then K.COLORS.Good else K.COLORS.Gold }, track)
	K.round(fill, 7)
	K.topLit(fill, 0.75)
	return track
end

local function rewardRow(parent: Instance, reward: QuestConfig.Reward, props: Payload, align: Enum.HorizontalAlignment?): Frame
	local row: Frame = K.create("Frame", { BackgroundTransparency = 1 }, parent)
	for key, value in props do
		(row :: any)[key] = value
	end
	local layout = K.list(row, Enum.FillDirection.Horizontal, 8)
	layout.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	for index, entry in REWARD_KEYS do
		local amount = (reward :: any)[entry.Field]
		if amount then
			local chip: Frame = K.create("Frame", { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1, LayoutOrder = index }, row)
			K.list(chip, Enum.FillDirection.Horizontal, 3).VerticalAlignment = Enum.VerticalAlignment.Center
			iconDisc(chip, Icons[entry.Icon], 26, currencyColor(entry.Currency), { LayoutOrder = 1 })
			K.newLabel(chip, { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Text = K.formatNumber(amount),
				Font = K.DISPLAY_FONT, TextSize = 19, TextColor3 = INK, TextStrokeTransparency = 1, LayoutOrder = 2 })
		end
	end
	return row
end

-- Reward icons that float up out of `from` and fade (drawn on their own layer so a re-render cannot cut them off).
local function flyRewards(from: GuiObject, reward: QuestConfig.Reward)
	local root = SceneKit.overlay()
	local origin = SceneKit.overlayPoint(from)
	local n = 0
	for _, entry in REWARD_KEYS do
		if (reward :: any)[entry.Field] then
			for _ = 1, 3 do
				n += 1
				local delay = n * 0.06
				local chip = icon(root, Icons[entry.Icon], { AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(origin.X, origin.Y), Size = UDim2.fromOffset(34, 34),
					ImageColor3 = currencyColor(entry.Currency), ZIndex = 50 })
				local target = origin + Vector2.new(math.random(-110, 110), -math.random(120, 200))
				task.delay(delay, function()
					tween(chip, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Position = UDim2.fromOffset(target.X, target.Y), Rotation = math.random(-40, 40) })
					tween(chip, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45),
						{ ImageTransparency = 1, Size = UDim2.fromOffset(16, 16) })
					task.delay(0.9, function()
						chip:Destroy()
					end)
				end)
			end
		end
	end
end

local function claimButton(parent: Instance, quest: Payload, reward: QuestConfig.Reward, props: Payload): GuiButton
	-- A glow breathing behind the button (the button's own UIScale belongs to its press animation).
	local size: UDim2 = props.Size
	local glow = icon(parent, Vfx.light_01, { AnchorPoint = props.AnchorPoint, Position = props.Position,
		Size = UDim2.new(size.X.Scale, size.X.Offset + 40, size.Y.Scale, size.Y.Offset + 40), ScaleType = Enum.ScaleType.Stretch,
		ImageColor3 = K.COLORS.Gold, ImageTransparency = 0.7 })
	tween(glow, PULSE, { ImageTransparency = 0.2 })
	local button: GuiButton
	button = K.newButton(parent, "Claim!", K.COLORS.Gold, function()
		Sfx.Play("Quest_Claim")
		Sfx.Play("Currency_Gain", 0.45)
		flyRewards(button, reward)
		claimQuestRemote:FireServer(quest.Id)
	end, props)
	return button
end

local function questCard(parent: Instance, quest: Payload, index: number)
	local info = QuestConfig.Quests[quest.Id]
	local reward: QuestConfig.Reward = if info then info.Reward else {}
	local goal = tonumber(quest.Goal) or 1
	local progress = math.min(goal, tonumber(quest.Progress) or 0)
	local done = progress >= goal
	local claimed = quest.Claimed == true

	local card = parchment(parent, nil, { Size = UDim2.new(0.31, 0, 1, -6), LayoutOrder = index })
	-- The pin holding it to the board.
	local pin = circle(card, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromHex("d8433a"), ZIndex = 3 })
	K.outline(pin, INK, 2)

	iconDisc(card, Icons["Quest_" .. tostring(quest.Id)], 56, Color3.fromHex("ffd27a"), {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16) })
	local title = K.newLabel(card, { Position = UDim2.fromOffset(6, 74), Size = UDim2.new(1, -12, 0, 24),
		Text = tostring(quest.Name), Font = K.DISPLAY_FONT, TextSize = 19, TextColor3 = INK, TextStrokeTransparency = 1,
		TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
	K.create("UITextSizeConstraint", { MaxTextSize = 21, MinTextSize = 13 }, title)
	K.newLabel(card, { Position = UDim2.fromOffset(6, 98), Size = UDim2.new(1, -12, 0, 28),
		Text = ("%s <font size='17' color='#%s'>/ %s</font>"):format(K.formatNumber(progress), INK_LIGHT:ToHex(), K.formatNumber(goal)),
		Font = K.DISPLAY_FONT, TextSize = 28, TextColor3 = INK, TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center })
	questBar(card, progress / goal, { Position = UDim2.new(0, 14, 0, 130), Size = UDim2.new(1, -28, 0, 14) })
	rewardRow(card, reward, { Position = UDim2.new(0, 6, 0, 150), Size = UDim2.new(1, -12, 0, 30) })

	if done and not claimed then
		claimButton(card, quest, reward, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.new(1, -20, 0, 44), TextSize = 18 })
	elseif not done then
		K.newLabel(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -12, 0, 22),
			Text = ("%d%% done"):format(math.floor(progress / goal * 100)), TextSize = 15, TextColor3 = INK_LIGHT,
			TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center })
	end

	if claimed then
		card.ImageColor3 = Color3.fromHex("bdb3a0")
		local stamp: TextLabel = K.newLabel(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.fromOffset(130, 48), Text = "DONE", Font = K.DISPLAY_FONT, TextSize = 34,
			TextColor3 = Color3.fromHex("c8302a"), TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6 })
		K.round(stamp, 8)
		K.create("UIStroke", { Color = Color3.fromHex("c8302a"), Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			stamp)
		if lastClaimed[quest.Id] == false then
			-- Just claimed: slam the stamp down.
			local scale: UIScale = K.create("UIScale", { Scale = 2.4 }, stamp)
			stamp.TextTransparency = 1
			tween(scale, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 })
			tween(stamp, TweenInfo.new(0.15), { TextTransparency = 0 })
			task.delay(0.22, function()
				Sfx.Play("Item_Drop", 0.7)
				burst(card, Color3.fromHex("ffd27a"))
			end)
		end
	end
	lastClaimed[quest.Id] = claimed
end

local function bountyPoster(parent: Instance, quest: Payload, index: number)
	local info = QuestConfig.Quests[quest.Id]
	local reward: QuestConfig.Reward = if info then info.Reward else {}
	local goal = tonumber(quest.Goal) or 1
	local progress = math.min(goal, tonumber(quest.Progress) or 0)
	local done = progress >= goal

	local poster = parchment(parent, UiTex.panel_beigeLight, { Size = UDim2.new(0.49, 0, 1, 0), LayoutOrder = index })
	iconDisc(poster, Icons["Quest_" .. tostring(quest.Id)], 62, Color3.fromHex("ff9b7a"), {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
	local right = if done then 116 else 12 -- room for the Claim button
	local column: Frame = K.create("Frame", { Position = UDim2.fromOffset(82, 6), Size = UDim2.new(1, -82 - right, 1, -12),
		BackgroundTransparency = 1 }, poster)
	K.newLabel(column, { Size = UDim2.new(1, 0, 0, 16), Text = "WANTED", Font = K.DISPLAY_FONT, TextSize = 14,
		TextColor3 = Color3.fromHex("a8392c"), TextStrokeTransparency = 1 })
	-- A full bar already says "done", so a claimable poster keeps the whole line for the name.
	local name = K.newLabel(column, { Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 22),
		Text = if done then tostring(quest.Name) else ("%s  <font color='#%s'>%s / %s</font>"):format(tostring(quest.Name),
			INK_LIGHT:ToHex(), K.formatNumber(progress), K.formatNumber(goal)), Font = K.DISPLAY_FONT, TextSize = 18,
		TextColor3 = INK, TextStrokeTransparency = 1, TextScaled = true })
	K.create("UITextSizeConstraint", { MaxTextSize = 19, MinTextSize = 12 }, name)
	questBar(column, progress / goal, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 10) })
	rewardRow(column, reward, { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 28) },
		Enum.HorizontalAlignment.Left)
	if done then
		claimButton(poster, quest, reward, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(100, 44), TextSize = 16 })
	end
end

local function renderQuestBoard()
	local board = K.stationData()
	if type(board) ~= "table" or type(board.Quests) ~= "table" then
		K.paragraph(1, "Loading…", K.COLORS.Muted)
		return
	end
	local resets = tonumber(board.ResetsIn) or 0

	local header: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 1 },
		K.content())
	K.newLabel(header, { Size = UDim2.new(0.5, 0, 1, 0), Text = "Daily Quests", Font = K.DISPLAY_FONT, TextSize = 26,
		TextColor3 = K.COLORS.Gold, TextStrokeTransparency = 0 })
	local timer = K.newPanel(header, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(200, 38) })
	icon(timer, Icons.UI_Timer, { Position = UDim2.fromOffset(8, 5), Size = UDim2.fromOffset(28, 28) })
	K.newLabel(timer, { Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -46, 1, 0),
		Text = ("New in %dh %02dm"):format(resets // 3600, (resets % 3600) // 60), Font = K.DISPLAY_FONT, TextSize = 17,
		TextStrokeTransparency = 0.2 })

	local dailies: { Payload } = {}
	local bounties: { Payload } = {}
	for _, quest in board.Quests do
		if type(quest) == "table" then
			table.insert(if quest.Repeatable then bounties else dailies, quest)
		end
	end

	local cards: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 246), BackgroundTransparency = 1, LayoutOrder = 2 },
		K.content())
	local layout = K.list(cards, Enum.FillDirection.Horizontal, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	for index, quest in dailies do
		questCard(cards, quest, index)
	end

	if #bounties > 0 then
		local title: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 3 },
			K.content())
		K.newLabel(title, { Size = UDim2.fromScale(1, 1), Text = "Bounties  <font size='15' color='#cfdaf0'>· repeat forever</font>",
			Font = K.DISPLAY_FONT, TextSize = 21, TextColor3 = K.COLORS.Gold, TextStrokeTransparency = 0 })
		local posters: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 98), BackgroundTransparency = 1, LayoutOrder = 4 },
			K.content())
		local posterLayout = K.list(posters, Enum.FillDirection.Horizontal, 10)
		posterLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for index, quest in bounties do
			bountyPoster(posters, quest, index)
		end
	end
end

StationScenes.Renderers = {
	SparkSanctum = function()
		renderSanctum()
	end,
	QuestBoard = renderQuestBoard,
} :: { [string]: () -> () }

-- Called when the station window closes, so a half-confirmed respec never survives a reopen.
function StationScenes.Reset()
	respecArmed = false
end

function StationScenes.Init(kit: any)
	K = kit
	purchaseRemote = Remotes.GetEvent("AscensionPurchase")
	respecRemote = Remotes.GetEvent("AscensionRespec")
	claimQuestRemote = Remotes.GetEvent("ClaimQuest")
end

return StationScenes
