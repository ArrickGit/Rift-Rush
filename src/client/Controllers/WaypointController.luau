--!strict
-- StarterPlayerScripts/Client/Controllers/WaypointController.luau
-- Persistent, always-pointing waypoints (game.md Section 33.3) for every interactable tagged "RiftWaypoint"
-- (AssetRegistry.TagWaypoint: Town Hub stations, chests, pact altars, the open exit portal). They never hide:
--   * Near (<= NEAR_DISTANCE studs) or on screen: a bobbing downward chevron hovers over the interactable's apex
--     (InteractableTop + 4.5 + sin(t * 3.5) * 1.1) with its floating name badge; far ones also show the distance.
--   * Off screen: a round marker with the icon on the matching screen edge, an arrow pointing at it, plus the name
--     and distance, spread apart so markers never overlap.
-- Waypoints whose WaypointActive attribute is false (a locked exit) and anything farther than MAX_DISTANCE (the
-- town while you are in a run, and vice versa) are skipped.
-- Decluttering (game.md 3.3): in town only the Rift Gate and the nearest other station unlocked for the player's
-- TownTier (OnboardingConfig) point at all; other stations only show their hover when you walk up, and locked ones
-- show a grey 🔒 unlock hint instead (OnboardingService also toasts it the first time you walk up). In runs, chests and altars only show within RUN_NEAR studs; the exit always shows.
-- New hunters (NewHunter attribute) also get a golden "ENTER THE RIFT ➜" guide beside the gate.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local OnboardingConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OnboardingConfig"))

type Marker = {
	Target: Instance,
	Adornee: BasePart,
	TopOffset: number, -- apex height above the adornee's position
	Edge: Frame,
	Pivot: Frame,
	EdgeDistance: TextLabel,
	Hover: BillboardGui,
	HoverName: TextLabel,
	Chevron: TextLabel,
	Color: Color3,
	Phase: number,
}

type Placed = { Marker: Marker, Position: Vector2 }

local WaypointController = {}

local TAG = "RiftWaypoint"
local NEAR_DISTANCE = 30
local MAX_DISTANCE = 240
local MARKER_SIZE = 46
local MARKER_SPACING = MARKER_SIZE + 34 -- room for the name and distance under each marker
local EDGE_MARGIN = 44
local TOP_MARGIN = 70 -- below the Roblox top bar and the HUD's status panel
-- UIController's town side menu (left) and wallet chips (right), in its 1280x720 design pixels; markers stay inside.
local LEFT_RESERVED = 130
local RIGHT_RESERVED = 175
local REF_WIDTH, REF_HEIGHT = 1280, 720
local MIN_SCALE, MAX_SCALE = 0.55, 1.25 -- the same clamp UIController uses
local HOVER_LIFT = 4.5
local BOB_SPEED = 3.5
local BOB_HEIGHT = 1.1
-- Hero landmarks are taller than the side-on camera's frame; the hover never rises above this fraction of the
-- half-height above the view centre (it stays clear of the top HUD banner and keeps pointing down at the station).
local HOVER_VIEW_LIMIT = 0.6
local RUN_NEAR = 45 -- chests / altars inside a run only point when this close
local EXIT_NAME = "Exit Portal" -- RoomBuilderService's exit waypoint, always shown once open
local LOCKED_COLOR = Color3.fromRGB(150, 156, 172)

local player = Players.LocalPlayer
local gui: ScreenGui
local markers: { [Instance]: Marker } = {}
local guide: BillboardGui? = nil

local function attribute<T>(instance: Instance, name: string, default: T): T
	local value = instance:GetAttribute(name)
	return if value ~= nil then value :: any else default
end

local function findAdornee(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function apexOffset(target: Instance, adornee: BasePart): number
	if target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		return cf.Y + size.Y / 2 - adornee.Position.Y
	end
	return adornee.Size.Y / 2
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.Text = ""
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeColor3 = Color3.fromRGB(13, 21, 36)
	text.TextStrokeTransparency = 0.2
	for key, value in props do
		(text :: any)[key] = value
	end
	text.Parent = parent
	return text
end

local function createMarker(target: Instance)
	if markers[target] then
		return
	end
	local adornee = findAdornee(target)
	if not adornee then
		return
	end
	local color: Color3 = attribute(target, "WaypointColor", Color3.fromRGB(255, 220, 120))
	local icon: string = attribute(target, "WaypointIcon", "❗")
	local name: string = attribute(target, "WaypointName", target.Name)

	-- Off-screen edge marker.
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE)
	edge.BackgroundColor3 = Color3.fromRGB(22, 20, 36)
	edge.BackgroundTransparency = 0.15
	edge.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = edge
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2.5
	stroke.Parent = edge
	label(edge, { Size = UDim2.fromScale(1, 1), Text = icon, TextSize = 24, TextStrokeTransparency = 1 })
	local pivot = Instance.new("Frame")
	pivot.BackgroundTransparency = 1
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Position = UDim2.fromScale(0.5, 0.5)
	pivot.Size = UDim2.fromScale(1, 1)
	pivot.Parent = edge
	label(pivot, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(1, 1, 0.5, 0), Size = UDim2.fromOffset(16, 16),
		Text = "▶", TextColor3 = color, TextSize = 18, TextStrokeTransparency = 0.5 })
	label(edge, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.fromOffset(150, 15),
		Text = name, TextSize = 13 })
	local edgeDistance = label(edge, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 17),
		Size = UDim2.fromOffset(80, 13), TextSize = 12, TextColor3 = Color3.fromRGB(220, 226, 240) })
	edge.Parent = gui

	-- World-space hover: name badge with a bobbing chevron pointing straight down at the interactable.
	local hover = Instance.new("BillboardGui")
	hover.Name = name .. "Hover"
	hover.Adornee = adornee
	hover.AlwaysOnTop = true
	hover.LightInfluence = 0
	hover.Size = UDim2.fromOffset(220, 92)
	hover.SizeOffset = Vector2.new(0, 0.5) -- the chevron's tip sits on the anchor point
	hover.MaxDistance = MAX_DISTANCE
	hover.Enabled = false
	local badge = Instance.new("Frame")
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.fromScale(0.5, 0)
	badge.Size = UDim2.fromOffset(0, 30)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = Color3.fromRGB(22, 20, 36)
	badge.BackgroundTransparency = 0.2
	badge.Parent = hover
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(0, 10)
	badgeCorner.Parent = badge
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = color
	badgeStroke.Thickness = 2
	badgeStroke.Parent = badge
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = badge
	local hoverName = label(badge, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Text = icon .. " " .. name,
		TextSize = 18 })
	local chevron = label(hover, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(60, 56),
		Text = "▼", TextColor3 = color, TextSize = 52, TextStrokeTransparency = 0 })
	hover.Parent = gui

	markers[target] = {
		Target = target, Adornee = adornee, TopOffset = apexOffset(target, adornee), Edge = edge, Pivot = pivot,
		EdgeDistance = edgeDistance, Hover = hover, HoverName = hoverName, Chevron = chevron, Color = color,
		Phase = math.random() * 6,
	}
end

-- The tier a Town Hub station needs (nil for anything that isn't a station).
local function stationTier(target: Instance): number?
	if target:IsA("Model") and target.Parent and target.Parent.Name == "Stations" then
		return OnboardingConfig.StationTier[target.Name]
	end
	return nil
end

-- New hunters: a pulsing "ENTER THE RIFT ➜" sign standing on the lane just left of the Rift Gate.
local function updateGuide(gate: Marker?, now: number)
	local show = gate ~= nil and player:GetAttribute("NewHunter") == true and player:GetAttribute("RunId") == nil
	if not show then
		if guide then
			guide.Enabled = false
		end
		return
	end
	local marker = gate :: Marker
	local sign = guide
	if not sign or sign.Adornee ~= marker.Adornee then
		if sign then
			sign:Destroy()
		end
		local created = Instance.new("BillboardGui")
		created.Name = "RiftGuide"
		created.Adornee = marker.Adornee
		created.Size = UDim2.fromOffset(220, 56)
		created.LightInfluence = 0
		created.MaxDistance = MAX_DISTANCE
		label(created, { Name = "Title", Size = UDim2.new(1, 0, 0, 28), Text = "ENTER THE RIFT", TextSize = 26,
			TextColor3 = Color3.fromRGB(255, 215, 70), TextStrokeTransparency = 0 })
		label(created, { Name = "Arrows", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 30), Text = "▶ ▶ ▶",
			TextSize = 26, TextColor3 = Color3.fromRGB(255, 215, 70), TextStrokeTransparency = 0 })
		created.Parent = gui
		guide = created
		sign = created
	end
	local active = sign :: BillboardGui
	active.Enabled = true
	-- Gate centre is ~6 studs up; the sign sits low on the lane, just left of the portal, sliding into it.
	local slide = (now * 1.6) % 1
	active.StudsOffsetWorldSpace = Vector3.new(-8.5 + slide * 1.5, -4.6, marker.Adornee.Position.Z * -1)
	local arrows = active:FindFirstChild("Arrows")
	if arrows and arrows:IsA("TextLabel") then
		arrows.TextTransparency = 0.5 - 0.5 * math.sin(slide * math.pi)
	end
end

local function removeMarker(target: Instance)
	local marker = markers[target]
	if marker then
		marker.Edge:Destroy()
		marker.Hover:Destroy()
		markers[target] = nil
	end
end

local function hide(marker: Marker)
	marker.Edge.Visible = false
	marker.Hover.Enabled = false
end

local function update()
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not (root and root:IsA("BasePart")) then
		for _, marker in markers do
			hide(marker)
		end
		return
	end

	local now = os.clock()
	local viewport = camera.ViewportSize
	local uiScale = math.clamp(math.min(viewport.X / REF_WIDTH, viewport.Y / REF_HEIGHT), MIN_SCALE, MAX_SCALE)
	local inRun = player:GetAttribute("RunId") ~= nil
	local minX = EDGE_MARGIN + (if inRun then 0 else LEFT_RESERVED * uiScale)
	local maxX = viewport.X - EDGE_MARGIN - RIGHT_RESERVED * uiScale
	local minY, maxY = TOP_MARGIN, viewport.Y - EDGE_MARGIN - 20
	local halfX, halfY = (maxX - minX) / 2, (maxY - minY) / 2
	local boxCenter = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2)
	local edges: { [string]: { Placed } } = { Left = {}, Right = {}, Top = {}, Bottom = {} }

	-- Town declutter: the Rift Gate plus the nearest other unlocked station are the only ones that point.
	local townTier = tonumber(player:GetAttribute("TownTier")) or OnboardingConfig.MAX_TIER
	local gateMarker: Marker? = nil
	local nearestStation: Instance? = nil
	local nearestDistance = math.huge
	for target, marker in markers do
		local tier = stationTier(target)
		if target.Name == "RiftGate" and tier then
			gateMarker = marker
		elseif tier and tier <= townTier and marker.Adornee.Parent then
			local distance = (marker.Adornee.Position - root.Position).Magnitude
			if distance < nearestDistance then
				nearestStation, nearestDistance = target, distance
			end
		end
	end
	updateGuide(gateMarker, now)

	for target, marker in markers do
		if target.Parent == nil or marker.Adornee.Parent == nil then
			removeMarker(target)
			continue
		end
		local apex = marker.Adornee.Position + Vector3.new(0, marker.TopOffset, 0)
		local distance = (apex - root.Position).Magnitude
		if target:GetAttribute("WaypointActive") == false or distance > MAX_DISTANCE then
			hide(marker)
			continue
		end

		local point = camera:WorldToViewportPoint(apex)
		local inFront = point.Z > 0
		local screen = Vector2.new(point.X, point.Y)
		local onScreen = inFront and screen.X >= minX and screen.X <= maxX and screen.Y >= minY and screen.Y <= maxY
		local near = distance <= NEAR_DISTANCE

		local tier = stationTier(target)
		local locked = tier ~= nil and tier > townTier
		local name: string = attribute(target, "WaypointName", target.Name)
		-- Quiet markers never point from afar; they only show their hover when the player is right there.
		local quiet = if inRun
			then name ~= EXIT_NAME and distance > RUN_NEAR
			else tier ~= nil and (locked or (target.Name ~= "RiftGate" and target ~= nearestStation))
		if quiet and not near then
			hide(marker)
			continue
		end
		marker.Chevron.TextColor3 = if locked then LOCKED_COLOR else marker.Color

		if near or onScreen then
			marker.Edge.Visible = false
			marker.Hover.Enabled = true
			local lift = HOVER_LIFT + math.sin(now * BOB_SPEED + marker.Phase) * BOB_HEIGHT
			local depth = math.max(1, (marker.Adornee.Position - camera.CFrame.Position):Dot(camera.CFrame.LookVector))
			local viewTop = camera.CFrame.Position.Y + math.tan(math.rad(camera.FieldOfView / 2)) * depth * HOVER_VIEW_LIMIT
			local height = math.min(marker.TopOffset + lift, viewTop - marker.Adornee.Position.Y + math.sin(now * BOB_SPEED + marker.Phase) * BOB_HEIGHT)
			marker.Hover.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
			local icon: string = attribute(target, "WaypointIcon", "❗")
			marker.HoverName.Text = if locked
				then ("%s  <font size='14' color='#cfdaf0'>%s</font>"):format(name, OnboardingConfig.Hint[tier :: number] or "🔒")
				elseif near then ("%s %s"):format(icon, name)
				else ("%s %s  <font color='#cfdaf0'>%dm</font>"):format(icon, name, math.round(distance))
			marker.HoverName.RichText = true
			local pulse = if near then 1 + 0.08 * math.sin(now * 6) else 0.8
			marker.Chevron.TextSize = 52 * pulse
			continue
		end

		marker.Hover.Enabled = false
		-- Behind the camera the projection mirrors through the centre; flip it so the arrow still points the right way.
		local direction = if inFront then screen - boxCenter else boxCenter - screen
		if direction.Magnitude < 1 then
			direction = Vector2.new(0, -1)
		end
		local scaleX = if direction.X ~= 0 then halfX / math.abs(direction.X) else math.huge
		local scaleY = if direction.Y ~= 0 then halfY / math.abs(direction.Y) else math.huge
		local edgePoint = boxCenter + direction * math.min(scaleX, scaleY)
		local side = if scaleX <= scaleY
			then (if direction.X < 0 then "Left" else "Right")
			else (if direction.Y < 0 then "Top" else "Bottom")
		marker.Pivot.Rotation = math.deg(math.atan2(direction.Y, direction.X))
		marker.EdgeDistance.Text = ("%dm"):format(math.round(distance))
		marker.Edge.Visible = true
		table.insert(edges[side], { Marker = marker, Position = edgePoint })
	end

	-- Markers on the same edge are spread apart along it so their icons and labels never overlap.
	for side, placed in edges do
		local vertical = side == "Left" or side == "Right"
		local low, high = if vertical then minY else minX, if vertical then maxY else maxX
		local function along(entry: Placed): number
			return if vertical then entry.Position.Y else entry.Position.X
		end
		table.sort(placed, function(a: Placed, b: Placed): boolean
			return along(a) < along(b)
		end)
		local coords: { number } = {}
		for index, entry in placed do
			coords[index] = math.max(along(entry), if index > 1 then coords[index - 1] + MARKER_SPACING else low)
		end
		local overflow = (coords[#coords] or high) - high
		for index = #coords, 1, -1 do
			if overflow <= 0 then
				break
			end
			local limit = if index < #coords then coords[index + 1] - MARKER_SPACING else high
			coords[index] = math.max(low, math.min(coords[index], limit))
		end
		for index, entry in placed do
			local position = if vertical
				then Vector2.new(entry.Position.X, coords[index])
				else Vector2.new(coords[index], entry.Position.Y)
			entry.Marker.Edge.Position = UDim2.fromOffset(position.X, position.Y)
		end
	end
end

function WaypointController.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "RiftWaypoints"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- WorldToViewportPoint measures from the very top of the window
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	for _, instance in CollectionService:GetTagged(TAG) do
		createMarker(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(instance: Instance)
		-- Models stream their parts in after the tag; give them a moment so the apex is measured on the full model.
		task.delay(0.2, function()
			if instance.Parent then
				createMarker(instance)
			end
		end)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(removeMarker)

	RunService.RenderStepped:Connect(update)

	-- Safety net: anything tagged that still has no marker (it replicated before its parts, or the added signal
	-- raced the join) is picked up here.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, instance in CollectionService:GetTagged(TAG) do
				if not markers[instance] and instance:IsDescendantOf(Workspace) then
					createMarker(instance)
				end
			end
		end
	end)
end

return WaypointController
