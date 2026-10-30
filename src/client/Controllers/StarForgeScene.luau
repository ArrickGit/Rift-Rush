--!strict
-- StarterPlayerScripts/Client/Controllers/StarForgeScene.luau
-- The Star-Forge window drawn as a forge: a shelf of relics along the top (undiscovered ones are dark silhouettes),
-- the selected relic resting on an anvil under its 5 star sockets, the success chance as a big number with the pity
-- "heat" on its bar, and a detail card with the cost, the Safeguard toggle and a STRIKE button.
--
-- STRIKE swings a hammer three times over the anvil (on the overlay layer, where rotation renders), then asks the
-- server. The reply arrives as a profile update; the re-render compares the relic's stars and pity with what they
-- were when the hammer fell, and slams a new star into its socket or fizzles and heats the bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Payload = { [string]: any }

local StarForgeScene = {}

local K: any = nil -- UIController's kit, set by Init
local player = Players.LocalPlayer
local starForceRemote: RemoteEvent
local loadoutRemote: RemoteEvent

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon

local FORGE_COLORS = {
	Stage = Color3.fromHex("2b1e1a"),
	Card = Color3.fromHex("2f2833"),
	Tile = Color3.fromHex("3a2e2a"),
	Silhouette = Color3.fromHex("161a24"),
	Iron = Color3.fromHex("5d6270"),
	Socket = Color3.fromHex("1c1416"),
	Star = Color3.fromHex("ffcc33"),
	Heat = Color3.fromHex("ff6a2a"),
	Bad = Color3.fromHex("ff6b6b"),
}
local NODE_RELIC_RESONANCE = "AS_T3_02" -- +3% Star-Force chance per level (mirrors RelicService)
local STRIKES = 3
local STRIKE_GAP = 0.3
local RESULT_TIMEOUT = 3 -- give the strike up if the server never answers (cooldown, a run started, ...)
local HAMMER_RAISED = -40 -- grip rotation with the head pointing up
local HAMMER_IMPACT = -135 -- head pointing left, onto the relic (the grip sits level with it, 110 to the right)

type RelicState = { Stars: number, Pity: number }
type Strike = { Relic: string, Stars: number, Pity: number, Token: number }

local selectedRelic: string? = nil
local useSafeguard = false
local pending: Strike? = nil -- the strike waiting for the server's answer
local strikeToken = 0
local anvilDisc: GuiObject? = nil -- the relic on the anvil in the latest render (the hammer squashes it)
local anvilScale: UIScale? = nil

local function profileTable(key: string): { [any]: any }
	local data = K.profile()
	local value = if data then data[key] else nil
	return if type(value) == "table" then value else {}
end

local function profileNumber(key: string): number
	local data = K.profile()
	return if data then tonumber(data[key]) or 0 else 0
end

local function relicState(relicId: string): RelicState?
	local owned = profileTable("RelicStars")[relicId]
	if type(owned) ~= "table" then
		return nil
	end
	return { Stars = tonumber(owned.Stars) or 1, Pity = tonumber(owned.PityCount) or 0 }
end

local function relicSlots(): number
	return RelicConfig.GetStartingSlots(tonumber(profileTable("AscensionNodes").AS_T3_03) or 0,
		player:GetAttribute("HasRelicVaultKey") == true)
end

local function resonance(): number
	return tonumber(profileTable("AscensionNodes")[NODE_RELIC_RESONANCE]) or 0
end

local function dim(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- A currency pill for the header: icon and a big number.
local function currencyPill(parent: Instance, iconKey: string, currency: string, amount: number, props: Payload): Frame
	local pill = K.newPanel(parent, props)
	icon(pill, Icons[iconKey], { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(36, 36),
		ImageColor3 = SceneKit.currencyColor(currency) })
	K.newLabel(pill, { Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -56, 1, 0), Text = K.formatNumber(amount),
		Font = K.DISPLAY_FONT, TextSize = 28, TextStrokeTransparency = 0 })
	return pill
end

local function header(order: number)
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = order },
		K.content())
	currencyPill(row, "Cur_RelicShards", "RelicShards", profileNumber("RelicShards"), { Size = UDim2.fromOffset(150, 46) })
	currencyPill(row, "Cur_Dust", "RiftDust", profileNumber("RiftDust"),
		{ Position = UDim2.fromOffset(160, 0), Size = UDim2.fromOffset(170, 46) })

	local slots = K.newPanel(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(200, 46) })
	icon(slots, Icons.UI_Bag, { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(32, 32) })
	K.newLabel(slots, { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -110, 1, 0), Text = "Starting\nRelics",
		TextSize = 13, TextColor3 = K.COLORS.Muted, LineHeight = 0.9 })
	K.newLabel(slots, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 70, 1, 0),
		Text = ("%d/%d"):format(#profileTable("EquippedStartingRelics"), relicSlots()), Font = K.DISPLAY_FONT, TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0 })
end

-- The shelf: every relic as a tile. Tapping one puts it on the anvil.
local function shelf(order: number)
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 1, LayoutOrder = order },
		K.content())
	local layout = K.list(row, Enum.FillDirection.Horizontal, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local equipped = profileTable("EquippedStartingRelics")
	for index, relicId in RelicConfig.Order do
		local info = RelicConfig.Relics[relicId]
		local state = relicState(relicId)
		local selected = relicId == selectedRelic
		local tile: TextButton = K.create("TextButton", { Size = UDim2.fromOffset(66, 66), Text = "", AutoButtonColor = false,
			BackgroundColor3 = if state then dim(info.Color, 0.6) else FORGE_COLORS.Silhouette, LayoutOrder = index }, row)
		K.round(tile, 14)
		K.create("UIStroke", { Color = if selected then Color3.new(1, 1, 1) elseif state then info.Color else K.COLORS.Stroke,
			Thickness = if selected then 4 else 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tile)
		local scale: UIScale = K.create("UIScale", { Scale = if selected then 1.08 else 1 }, tile)
		icon(tile, Icons["Relic_" .. relicId], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.44),
			Size = UDim2.fromScale(0.6, 0.6), ImageColor3 = if state then info.Color else Color3.fromHex("3a4152") })
		if state then
			K.newLabel(tile, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.new(1, 0, 0, 16),
				Text = string.rep("★", state.Stars), TextSize = 13, TextColor3 = FORGE_COLORS.Star,
				TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2 })
		else
			K.newLabel(tile, { Size = UDim2.fromScale(1, 0.9), Text = "?", Font = K.DISPLAY_FONT, TextSize = 30,
				TextColor3 = Color3.fromHex("8a93a8"), TextXAlignment = Enum.TextXAlignment.Center })
		end
		if table.find(equipped, relicId) then
			local badge = circle(tile, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4),
				Size = UDim2.fromOffset(24, 24), BackgroundColor3 = K.COLORS.Good, ZIndex = 3 })
			K.outline(badge, K.COLORS.Stroke, 2)
			icon(badge, Icons.UI_Bag, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.66, 0.66), ZIndex = 4 })
		end
		if not selected then
			SceneKit.hoverGrow(tile, scale, 1.08)
		end
		tile.Activated:Connect(function()
			if selectedRelic ~= relicId and not pending then
				selectedRelic = relicId
				Sfx.Play("UI_Tab", 0.4)
				K.renderStation()
			end
		end)
	end
end

-- Sparks thrown off the anvil at `point` (overlay coordinates).
local function sparks(point: Vector2, color: Color3)
	local root = SceneKit.overlay()
	for _ = 1, 7 do
		local angle = math.rad(math.random(200, 340))
		local distance = math.random(50, 110)
		local spark = icon(root, Vfx.spark_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(point.X, point.Y),
			Size = UDim2.fromOffset(26, 26), ImageColor3 = color, ZIndex = 62 })
		local target = point + Vector2.new(math.cos(angle), math.sin(angle)) * distance
		tween(spark, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(8, 8), ImageTransparency = 1 })
		task.delay(0.45, function()
			spark:Destroy()
		end)
	end
end

-- Three hammer blows on the relic on the anvil, then the request to the server.
local function strike(relicId: string, state: RelicState, relicDisc: GuiObject)
	strikeToken += 1
	local token = strikeToken
	pending = { Relic = relicId, Stars = state.Stars, Pity = state.Pity, Token = token }
	local safeguard = useSafeguard
	local root = SceneKit.overlay()
	local point = SceneKit.overlayPoint(relicDisc)
	-- The hammer is held by its handle end (the icon's bottom-left; the head is top-right), right of the relic,
	-- and swings around that grip: raised with the head up, down until the head lands on the relic.
	local pivot: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(point.X + 110, point.Y),
		Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Rotation = HAMMER_RAISED, ZIndex = 61 }, root)
	local hammer = icon(pivot, Icons.Weapon_Hammer, { AnchorPoint = Vector2.new(0.08, 0.92), Position = UDim2.fromOffset(1, 1),
		Size = UDim2.fromOffset(104, 104), ImageColor3 = Color3.fromHex("e8e2d6"), ImageTransparency = 1, ZIndex = 61 })
	tween(hammer, TweenInfo.new(0.15), { ImageTransparency = 0 })
	for blow = 1, STRIKES do
		task.delay(0.15 + (blow - 1) * STRIKE_GAP, function()
			tween(pivot, TweenInfo.new(STRIKE_GAP * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = HAMMER_RAISED })
			task.wait(STRIKE_GAP * 0.55)
			tween(pivot, TweenInfo.new(STRIKE_GAP * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Rotation = HAMMER_IMPACT })
			task.wait(STRIKE_GAP * 0.3)
			Sfx.Play("Forge_Hammer" .. blow, 0.6)
			sparks(point + Vector2.new(0, 10), if blow == STRIKES then FORGE_COLORS.Star else FORGE_COLORS.Heat)
			local scale = anvilScale
			if scale and scale.Parent then
				scale.Scale = 0.86
				tween(scale, SceneKit.POP, { Scale = 1 })
			end
		end)
	end
	task.delay(0.2 + STRIKES * STRIKE_GAP, function()
		tween(hammer, TweenInfo.new(0.25), { ImageTransparency = 1 })
		task.delay(0.3, function()
			pivot:Destroy()
		end)
		if pending and pending.Token == token then
			starForceRemote:FireServer({ Relic = relicId, Safeguard = safeguard })
		end
	end)
	task.delay(0.2 + STRIKES * STRIKE_GAP + RESULT_TIMEOUT, function()
		if pending and pending.Token == token then
			pending = nil
			K.renderStation()
		end
	end)
end

-- The anvil stage: star sockets, the relic on its anvil, and the success chance with its heat.
local function stage(parent: Instance, relicId: string, state: RelicState?, outcome: string?)
	local info = RelicConfig.Relics[relicId]
	local scene = K.newPanel(parent, { Size = UDim2.new(0.56, 0, 1, 0), BackgroundColor3 = FORGE_COLORS.Stage })
	scene.ClipsDescendants = true
	-- Forge glow rising from the bottom.
	icon(scene, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(420, 260), ScaleType = Enum.ScaleType.Stretch, ImageColor3 = FORGE_COLORS.Heat,
		ImageTransparency = 0.75 })

	local stars = if state then state.Stars else 0
	local sockets: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(1, -20, 0, 44), BackgroundTransparency = 1 }, scene)
	local socketLayout = K.list(sockets, Enum.FillDirection.Horizontal, 8)
	socketLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for index = 1, RelicConfig.MAX_STARS do
		local filled = index <= stars
		local socket = circle(sockets, { Size = UDim2.fromOffset(44, 44), LayoutOrder = index,
			BackgroundColor3 = if filled then dim(FORGE_COLORS.Star, 0.55) else FORGE_COLORS.Socket })
		local ring: UIStroke = K.create("UIStroke", { Color = if filled then FORGE_COLORS.Star else K.COLORS.Stroke, Thickness = 2.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, socket)
		local star: TextLabel = K.newLabel(socket, { Size = UDim2.fromScale(1, 1), Text = "★", Font = K.DISPLAY_FONT, TextSize = 32,
			TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = if filled then FORGE_COLORS.Star else Color3.fromHex("3a2e30"),
			TextStrokeTransparency = if filled then 0.3 else 1 })
		if state and index == stars + 1 then
			-- The socket the next strike aims at.
			ring.Color = FORGE_COLORS.Heat
			tween(ring, SceneKit.PULSE, { Transparency = 0.7 })
		end
		if outcome == "Success" and index == stars then
			local slam: UIScale = K.create("UIScale", { Scale = 2.6 }, star)
			star.TextTransparency = 1
			tween(slam, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 })
			tween(star, TweenInfo.new(0.15), { TextTransparency = 0 })
			task.delay(0.25, function()
				SceneKit.burst(socket, FORGE_COLORS.Star)
			end)
		end
	end

	-- The anvil and the relic resting on it.
	icon(scene, Icons.UI_Anvil, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 142),
		Size = UDim2.fromOffset(170, 96), ImageColor3 = FORGE_COLORS.Iron })
	local disc = circle(scene, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = if state then dim(info.Color, 0.5) else FORGE_COLORS.Silhouette, ZIndex = 3 })
	K.outline(disc, if state then info.Color else K.COLORS.Stroke, 3)
	anvilDisc = disc
	anvilScale = K.create("UIScale", {}, disc)
	if state then
		local glow = icon(disc, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(2, 2), ImageColor3 = info.Color, ImageTransparency = 0.55, ZIndex = 2 })
		tween(glow, SceneKit.PULSE, { ImageTransparency = 0.25 })
	end
	icon(disc, Icons["Relic_" .. relicId], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64), ImageColor3 = if state then info.Color else Color3.fromHex("3a4152"), ZIndex = 4 })
	if not state then
		K.newLabel(disc, { Size = UDim2.fromScale(1, 1), Text = "?", Font = K.DISPLAY_FONT, TextSize = 46, ZIndex = 5,
			TextColor3 = Color3.fromHex("8a93a8"), TextXAlignment = Enum.TextXAlignment.Center })
	end
	if outcome == "Success" then
		SceneKit.burst(disc, info.Color)
	elseif outcome == "Fail" then
		local smoke = icon(disc, Vfx.smoke_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
			Size = UDim2.fromScale(1, 1), ImageColor3 = Color3.fromHex("9a9aa6"), ImageTransparency = 0.2, ZIndex = 6 })
		tween(smoke, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(2.2, 2.2), Position = UDim2.fromScale(0.5, -0.3), ImageTransparency = 1 })
		task.delay(0.95, function()
			smoke:Destroy()
		end)
	end

	-- Success chance: a big number, and a bar whose orange end is the pity heat from failed strikes.
	local quote = if state then RelicConfig.GetForgeQuote(state.Stars) else nil
	local bottom: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -28, 0, 62), BackgroundTransparency = 1, ZIndex = 3 }, scene)
	if not state then
		K.newLabel(bottom, { Size = UDim2.fromScale(1, 1), Text = "Undiscovered", Font = K.DISPLAY_FONT, TextSize = 26,
			TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center })
		return
	elseif not quote then
		K.newLabel(bottom, { Size = UDim2.fromScale(1, 1), Text = "★ PERFECTED ★", Font = K.DISPLAY_FONT, TextSize = 30,
			TextColor3 = FORGE_COLORS.Star, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0 })
		return
	end
	local chance = RelicConfig.GetForgeChance(state.Stars, state.Pity, resonance())
	local heat = math.min(chance, RelicConfig.PITY_PER_FAILURE * state.Pity)
	local chanceColor = if chance >= 0.7 then K.COLORS.Good elseif chance >= 0.4 then FORGE_COLORS.Star else FORGE_COLORS.Bad
	K.newLabel(bottom, { Size = UDim2.new(0.5, 0, 0, 40), Text = ("%d%%"):format(math.round(chance * 100)),
		Font = K.DISPLAY_FONT, TextSize = 38, TextColor3 = chanceColor, TextStrokeTransparency = 0 })
	K.newLabel(bottom, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, 0, 0, 40),
		Text = if heat > 0 then ("🔥 +%d%% heat"):format(math.round(heat * 100)) else "success",
		TextSize = 16, TextColor3 = if heat > 0 then FORGE_COLORS.Heat else K.COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.3 })
	local track: Frame = K.create("Frame", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = FORGE_COLORS.Socket, BorderSizePixel = 0 }, bottom)
	K.round(track, 8)
	K.outline(track, K.COLORS.Stroke, 2)
	local base: Frame = K.create("Frame", { Size = UDim2.fromScale(chance - heat, 1), BorderSizePixel = 0,
		BackgroundColor3 = chanceColor }, track)
	K.round(base, 8)
	local heatFill: Frame = K.create("Frame", { Position = UDim2.fromScale(chance - heat, 0), Size = UDim2.fromScale(heat, 1),
		BorderSizePixel = 0, BackgroundColor3 = FORGE_COLORS.Heat }, track)
	K.round(heatFill, 8)
	if outcome == "Fail" and heat > 0 then
		-- The new heat pours in.
		local previous = math.max(0, heat - RelicConfig.PITY_PER_FAILURE)
		heatFill.Size = UDim2.fromScale(previous, 1)
		tween(heatFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(heat, 1) })
		local flame = icon(track, Vfx.fire_01, { AnchorPoint = Vector2.new(0.5, 0.8), Position = UDim2.fromScale(chance, 0.5),
			Size = UDim2.fromOffset(46, 46), ImageColor3 = FORGE_COLORS.Heat, ZIndex = 4 })
		tween(flame, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(70, 70), ImageTransparency = 1 })
		task.delay(0.95, function()
			flame:Destroy()
		end)
	end
end

-- A cost chip on the detail card: icon, amount, red if you can't afford it.
local function costChip(parent: Instance, iconKey: string, currency: string, amount: number, have: number, order: number)
	local chip: Frame = K.create("Frame", { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, LayoutOrder = order }, parent)
	K.list(chip, Enum.FillDirection.Horizontal, 4).VerticalAlignment = Enum.VerticalAlignment.Center
	icon(chip, Icons[iconKey], { Size = UDim2.fromOffset(28, 28), ImageColor3 = SceneKit.currencyColor(currency), LayoutOrder = 1 })
	K.newLabel(chip, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = K.formatNumber(amount),
		Font = K.DISPLAY_FONT, TextSize = 22, TextColor3 = if have >= amount then Color3.new(1, 1, 1) else FORGE_COLORS.Bad,
		TextStrokeTransparency = 0.1, LayoutOrder = 2 })
end

local function loadoutAction(action: string, relicId: string)
	loadoutRemote:FireServer({ Action = action, Relic = relicId })
end

local function detailCard(parent: Instance, relicId: string, state: RelicState?)
	local info = RelicConfig.Relics[relicId]
	local card = K.newPanel(parent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.42, 0, 1, 0), BackgroundColor3 = FORGE_COLORS.Card })
	K.pad(card, 10)
	K.newLabel(card, { Size = UDim2.new(1, 0, 0, 28), Text = if state then info.Name else "???", Font = K.DISPLAY_FONT,
		TextSize = 23, TextColor3 = if state then info.Color else K.COLORS.Muted, TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center })

	if not state then
		K.newLabel(card, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40),
			Text = "Not found yet.\n\nRelics drop from bosses\n<b>Room 5</b> · 35%\n<b>Room 10</b> · always\n\nand <b>Treasure Chests</b> · 25%",
			TextSize = 16, TextWrapped = true, TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top })
		return
	end

	-- Bottom up: the Safeguard / Starting Relic toggles, STRIKE, the cost, the next star's bonus; the effect text
	-- fills what is left under the name.
	local quote = RelicConfig.GetForgeQuote(state.Stars)
	K.newLabel(card, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 22),
		Text = string.rep("★", state.Stars) .. ("<font color='#4a3a3c'>%s</font>"):format(string.rep("★", RelicConfig.MAX_STARS - state.Stars)),
		Font = K.DISPLAY_FONT, TextSize = 22, TextColor3 = FORGE_COLORS.Star, TextXAlignment = Enum.TextXAlignment.Center })
	local desc = K.newLabel(card, { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -56 - 164),
		Text = RelicConfig.Describe(relicId, state.Stars), TextSize = 14, TextScaled = true, TextWrapped = true,
		TextColor3 = Color3.fromHex("d9d2e6"), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
	K.create("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 11 }, desc)
	K.newLabel(card, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -130), Size = UDim2.new(1, 0, 0, 32),
		Text = if quote then "Next ★  " .. info.StarDesc else "All 5 stars forged", TextSize = 14, TextWrapped = true,
		TextColor3 = FORGE_COLORS.Star, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Bottom })

	local inRun = K.inRun()
	local toggles: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, card)
	if quote then
		local costs: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -96),
			Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, card)
		local costLayout = K.list(costs, Enum.FillDirection.Horizontal, 14)
		costLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		costLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		local shards, dust = profileNumber("RelicShards"), profileNumber("RiftDust")
		costChip(costs, "Cur_RelicShards", "RelicShards", quote.Shards, shards, 1)
		costChip(costs, "Cur_Dust", "RiftDust", quote.Dust, dust, 2)

		local affordable = shards >= quote.Shards and dust >= quote.Dust
		local text = if pending then "Forging…" elseif inRun then "Back to town first" elseif affordable then "🔨 STRIKE!" else "Need more"
		local strikeButton = K.newButton(card, text, K.COLORS.Gold, function()
			local disc = anvilDisc
			if pending or inRun or not affordable or not disc then
				return
			end
			Sfx.Play("UI_Confirm", 0.5)
			strike(relicId, state, disc)
			K.renderStation()
		end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -36), Size = UDim2.new(1, 0, 0, 54), TextSize = 22 })
		K.setEnabled(strikeButton, affordable and not inRun and not pending, K.COLORS.Gold)

		local safeguards = profileNumber("StarForceSafeguards")
		local guardOn = useSafeguard and safeguards > 0
		SceneKit.pill(toggles, ("🛡 Guard %s ×%d"):format(if guardOn then "ON" else "OFF", safeguards),
			if guardOn then K.COLORS.Good else K.COLORS.PanelLight, safeguards > 0 and not inRun, function()
				useSafeguard = not useSafeguard
				Sfx.Play("UI_Toggle", 0.5)
				K.renderStation()
			end, { Size = UDim2.new(0.49, 0, 1, 0), TextSize = 13 })
	end

	local equipped = table.find(profileTable("EquippedStartingRelics"), relicId) ~= nil
	local canEquip = #profileTable("EquippedStartingRelics") < relicSlots()
	SceneKit.pill(toggles, if equipped then "🎒 Starting ✓" else "🎒 Start with", if equipped then K.COLORS.Good else K.COLORS.Accent,
		not inRun and (equipped or canEquip), function()
			Sfx.Play("Weapon_Equip", 0.5)
			loadoutAction(if equipped then "UnequipRelic" else "EquipRelic", relicId)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(if quote then 0.49 else 1, 0, 1, 0), TextSize = 13 })
end

local function renderStarForge()
	header(1)
	-- Default selection: the first relic you own, else the first on the shelf.
	if not selectedRelic then
		for _, relicId in RelicConfig.Order do
			if relicState(relicId) then
				selectedRelic = relicId
				break
			end
		end
		selectedRelic = selectedRelic or RelicConfig.Order[1]
	end
	shelf(2)

	local relicId = selectedRelic :: string
	local state = relicState(relicId)
	-- Did the strike we were waiting for land?
	local outcome: string? = nil
	local waiting = pending
	if waiting and state and waiting.Relic == relicId then
		if state.Stars > waiting.Stars then
			outcome = "Success"
		elseif state.Pity > waiting.Pity then
			outcome = "Fail"
		end
		if outcome then
			pending = nil
			Sfx.Play(if outcome == "Success" then "Forge_Success" else "Forge_Fail", 0.7)
		end
	end

	local body: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 306), BackgroundTransparency = 1, LayoutOrder = 3 },
		K.content())
	stage(body, relicId, state, outcome)
	detailCard(body, relicId, state)
end

StarForgeScene.Render = renderStarForge

-- Called when the station window closes: a strike still in the air is forgotten (its result shows next visit).
function StarForgeScene.Reset()
	pending = nil
end

function StarForgeScene.Init(kit: any)
	K = kit
	starForceRemote = Remotes.GetEvent("StarForce")
	loadoutRemote = Remotes.GetEvent("LoadoutAction")
end

return StarForgeScene
