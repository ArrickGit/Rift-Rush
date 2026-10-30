--!strict
-- StarterPlayerScripts/Client/Controllers/HallScene.luau
-- The Hall of Champions window drawn as a podium: banner tabs for the 3 leaderboards, the top 3 standing on gold /
-- silver / bronze pedestals (avatar headshots, the champion crowned), ranks 4-10 as a compact two-column list, and
-- your own score pinned at the bottom. The pedestals rise when a board opens.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetRegistry"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Payload = { [string]: any }

local HallScene = {}

local K: any = nil -- UIController's kit, set by Init
local player = Players.LocalPlayer

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon

local HALL_COLORS = {
	Hall = Color3.fromHex("2a2440"),
	Row = Color3.fromHex("332c4f"),
	RowYou = Color3.fromHex("27456b"),
	Tab = Color3.fromHex("3a3358"),
	Empty = Color3.fromHex("4a4466"),
}
-- Podium places, left to right: 2nd, 1st, 3rd.
local PLACES = {
	{ Rank = 2, Height = 52, Color = Color3.fromHex("c9d3e0"), Ink = Color3.fromHex("3c4656") },
	{ Rank = 1, Height = 72, Color = Color3.fromHex("ffcf4a"), Ink = Color3.fromHex("6a4300") },
	{ Rank = 3, Height = 38, Color = Color3.fromHex("d9905a"), Ink = Color3.fromHex("5a2e10") },
}
local BOARD_ICONS: { [string]: string } = { HighestRoom = "UI_Portal", HunterPower = "UI_Rebirth", Kills = "UI_Damage" }
local PODIUM_HEIGHT = 196

local selectedBoard = 1
local animatedBoard: number? = nil -- the board whose pedestals already rose (only rise once per open / switch)

local function boardValue(format: string, value: number): string
	if format == "Room" then
		return ("Room %d"):format(value)
	elseif format == "Power" then
		local tier, level = value // 1000, value % 1000
		return if tier > 0 then ("Rebirth %s · Lv %d"):format(K.toRoman(tier), level) else ("Lv %d"):format(level)
	end
	return K.formatNumber(value)
end

local function headshot(userId: number?): string
	return if userId and userId > 0 then ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId) else ""
end

-- A round avatar with a coloured ring.
local function avatar(parent: Instance, userId: number?, size: number, ring: Color3, props: Payload): Frame
	local disc = circle(parent, { Size = UDim2.fromOffset(size, size), BackgroundColor3 = HALL_COLORS.Empty })
	for key, value in props do
		(disc :: any)[key] = value
	end
	K.outline(disc, ring, if size > 50 then 3 else 2)
	local image = icon(disc, headshot(userId), { Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop })
	K.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, image)
	if not userId or userId <= 0 then
		K.newLabel(disc, { Size = UDim2.fromScale(1, 1), Text = "?", Font = K.DISPLAY_FONT, TextSize = math.floor(size * 0.45),
			TextColor3 = Color3.fromHex("8a84a8"), TextXAlignment = Enum.TextXAlignment.Center })
	end
	return disc
end

local function tabs(order: number, boards: { Payload })
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = order }, K.content())
	local layout = K.list(row, Enum.FillDirection.Horizontal, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for index, board in boards do
		local selected = index == selectedBoard
		local tab: TextButton = K.create("TextButton", { Size = UDim2.new(1 / #boards, -6, 1, 0), Text = "", AutoButtonColor = false,
			BackgroundColor3 = if selected then K.COLORS.Gold else HALL_COLORS.Tab, LayoutOrder = index }, row)
		K.round(tab, 10)
		K.outline(tab, K.COLORS.Stroke, 2.5)
		local inner: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, tab)
		K.list(inner, Enum.FillDirection.Horizontal, 6).VerticalAlignment = Enum.VerticalAlignment.Center
		icon(inner, Icons[BOARD_ICONS[tostring(board.Key)] or "UI_Podium"], { Size = UDim2.fromOffset(24, 24), LayoutOrder = 1,
			ImageColor3 = if selected then Color3.fromHex("4a2a00") else Color3.new(1, 1, 1) })
		K.newLabel(inner, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = tostring(board.Title),
			Font = K.DISPLAY_FONT, TextSize = 18, LayoutOrder = 2, TextColor3 = if selected then Color3.fromHex("4a2a00") else Color3.new(1, 1, 1),
			TextStrokeTransparency = if selected then 1 else 0.2 })
		local scale: UIScale = K.create("UIScale", {}, tab)
		if not selected then
			SceneKit.hoverGrow(tab, scale, 1.04)
		end
		tab.Activated:Connect(function()
			if selectedBoard ~= index then
				selectedBoard = index
				Sfx.Play("UI_Tab", 0.5)
				K.renderStation()
			end
		end)
	end
end

local function podium(order: number, board: Payload)
	local entries: { Payload } = if type(board.Entries) == "table" then board.Entries else {}
	local byRank: { [number]: Payload } = {}
	for _, entry in entries do
		byRank[tonumber(entry.Rank) or 0] = entry
	end
	local hall = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, PODIUM_HEIGHT), BackgroundColor3 = HALL_COLORS.Hall, LayoutOrder = order })
	hall.ClipsDescendants = true
	icon(hall, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.35), Size = UDim2.fromOffset(460, 300),
		ScaleType = Enum.ScaleType.Stretch, ImageColor3 = K.COLORS.Gold, ImageTransparency = 0.82 })

	local rise = animatedBoard ~= selectedBoard
	animatedBoard = selectedBoard
	for index, place in PLACES do
		local entry = byRank[place.Rank]
		local column: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(index / 4, 0, 1, 0),
			Size = UDim2.new(0.28, 0, 1, -8), BackgroundTransparency = 1 }, hall)
		-- The pedestal with its rank carved in.
		local pedestal: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, place.Height), BackgroundColor3 = place.Color, BorderSizePixel = 0 }, column)
		K.round(pedestal, 8)
		K.outline(pedestal, K.COLORS.Stroke, 3)
		K.topLit(pedestal, 0.6)
		K.newLabel(pedestal, { Size = UDim2.fromScale(1, 1), Text = tostring(place.Rank), Font = K.DISPLAY_FONT, TextSize = 40,
			TextColor3 = place.Ink, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1 })
		-- Who stands on it.
		local stand: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -place.Height - 2),
			Size = UDim2.new(1, 0, 0, 100), BackgroundTransparency = 1 }, column)
		local size = if place.Rank == 1 then 64 else 54
		local face = avatar(stand, if entry then tonumber(entry.UserId) else nil, size, place.Color,
			{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64 - size) })
		if place.Rank == 1 and entry then
			local glow = icon(face, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(2, 2), ImageColor3 = place.Color, ImageTransparency = 0.5, ZIndex = 0 })
			tween(glow, SceneKit.PULSE, { ImageTransparency = 0.2 })
			K.newLabel(face, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(40, 26),
				Text = "👑", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
		end
		local name = K.newLabel(stand, { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 20),
			Text = if entry then tostring(entry.Name) else "—", Font = K.DISPLAY_FONT, TextSize = 17, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.1,
			TextColor3 = if entry and tonumber(entry.UserId) == player.UserId then Color3.fromHex("7ad7ff") else Color3.new(1, 1, 1) })
		K.create("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 10 }, name)
		K.newLabel(stand, { Position = UDim2.fromOffset(0, 81), Size = UDim2.new(1, 0, 0, 18),
			Text = if entry then boardValue(tostring(board.Format), tonumber(entry.Value) or 0) else "", TextSize = 14,
			TextColor3 = place.Color, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2 })

		if rise then
			-- Pedestals rise in, champion last.
			local finalPedestal, finalStand = pedestal.Size, stand.Position
			pedestal.Size = UDim2.new(1, 0, 0, 0)
			stand.Position = UDim2.new(0.5, 0, 1, 0)
			local delay = ({ 0.1, 0.25, 0 })[index]
			local info = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
			tween(pedestal, info, { Size = finalPedestal })
			tween(stand, info, { Position = finalStand })
		end
	end
	if #entries == 0 then
		K.newLabel(hall, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(1, 0, 0, 24),
			Text = "No champions yet — be the first!", Font = K.DISPLAY_FONT, TextSize = 18, TextColor3 = K.COLORS.Muted,
			TextXAlignment = Enum.TextXAlignment.Center })
	end
end

-- Ranks 4-10 in two columns.
local function ribbons(order: number, board: Payload)
	local entries: { Payload } = if type(board.Entries) == "table" then board.Entries else {}
	local rest: { Payload } = {}
	for _, entry in entries do
		if (tonumber(entry.Rank) or 0) > 3 then
			table.insert(rest, entry)
		end
	end
	if #rest == 0 then
		return
	end
	local rows = math.ceil(#rest / 2)
	local grid: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, rows * 34 - 4), BackgroundTransparency = 1, LayoutOrder = order }, K.content())
	local layout: UIGridLayout = K.create("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 30), CellPadding = UDim2.fromOffset(8, 4),
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	layout.FillDirection = Enum.FillDirection.Horizontal
	for index, entry in rest do
		local you = tonumber(entry.UserId) == player.UserId
		local row: Frame = K.create("Frame", { BackgroundColor3 = if you then HALL_COLORS.RowYou else HALL_COLORS.Row, LayoutOrder = index }, grid)
		K.round(row, 8)
		K.outline(row, K.COLORS.Stroke, 2)
		K.newLabel(row, { Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(34, 30), Text = ("#%d"):format(tonumber(entry.Rank) or 0),
			Font = K.DISPLAY_FONT, TextSize = 16, TextColor3 = K.COLORS.Muted })
		avatar(row, tonumber(entry.UserId), 24, K.COLORS.Stroke, { Position = UDim2.fromOffset(40, 3) })
		K.newLabel(row, { Position = UDim2.fromOffset(70, 0), Size = UDim2.new(1, -170, 1, 0), Text = tostring(entry.Name), Font = K.DISPLAY_FONT,
			TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, TextStrokeTransparency = 0.2 })
		K.newLabel(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 96, 1, 0),
			Text = boardValue(tostring(board.Format), tonumber(entry.Value) or 0), TextSize = 14, TextColor3 = K.COLORS.Gold,
			TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.2 })
	end
end

-- Your own score and rank, always visible.
local function youBar(order: number, board: Payload)
	local rank: number? = nil
	for _, entry in (if type(board.Entries) == "table" then board.Entries else {}) :: { Payload } do
		if tonumber(entry.UserId) == player.UserId then
			rank = tonumber(entry.Rank)
		end
	end
	local bar = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = HALL_COLORS.RowYou, LayoutOrder = order })
	avatar(bar, player.UserId, 34, Color3.fromHex("7ad7ff"), { Position = UDim2.fromOffset(8, 5) })
	K.newLabel(bar, { Position = UDim2.fromOffset(54, 0), Size = UDim2.new(0.4, 0, 1, 0), Text = "You", Font = K.DISPLAY_FONT, TextSize = 22,
		TextStrokeTransparency = 0 })
	K.newLabel(bar, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.4, 0, 1, 0),
		Text = boardValue(tostring(board.Format), tonumber(board.You) or 0), Font = K.DISPLAY_FONT, TextSize = 24,
		TextColor3 = K.COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0 })
	K.newLabel(bar, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0.3, 0, 1, 0),
		Text = if rank then ("Rank <b>#%d</b>"):format(rank) else "Not in the top 10 yet", TextSize = if rank then 20 else 14,
		Font = if rank then K.DISPLAY_FONT else nil, TextColor3 = if rank then Color3.new(1, 1, 1) else K.COLORS.Muted,
		TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.2 })
end

local function renderHall()
	local boards = K.stationData()
	if type(boards) ~= "table" or #boards == 0 then
		K.paragraph(1, "Loading…", K.COLORS.Muted)
		return
	end
	selectedBoard = math.clamp(selectedBoard, 1, #boards)
	local board = boards[selectedBoard]
	tabs(1, boards)
	podium(2, board)
	ribbons(3, board)
	youBar(4, board)
end

HallScene.Render = renderHall

-- Called when the station window closes, so the pedestals rise again on the next visit.
function HallScene.Reset()
	animatedBoard = nil
end

function HallScene.Init(kit: any)
	K = kit
end

return HallScene
