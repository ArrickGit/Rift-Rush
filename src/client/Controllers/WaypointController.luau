--!strict
-- StarterPlayerScripts/Client/Controllers/WaypointController.luau
-- Off-screen waypoints for the Town Hub stations: when a station is outside the view, a round marker with its
-- AssetRegistry icon sits on the matching screen edge, with an arrow pointing at it and the distance in studs.
-- On-screen stations already show their floating name label, so their marker hides. Nothing shows during a run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))

type Marker = {
	Model: Model,
	Frame: Frame,
	Pivot: Frame,
	Distance: TextLabel,
}

type Placed = { Marker: Marker, Position: Vector2 }

local WaypointController = {}

local MARKER_SIZE = 46
local MARKER_SPACING = MARKER_SIZE + 22 -- room for the distance label under each marker
local EDGE_MARGIN = 40 -- keeps markers (and their arrows) clear of the screen edge
local TOP_MARGIN = 70 -- below the Roblox top bar and the HUD's status panel
-- UIController's town side menu (left) and wallet chips (right), in its 1280x720 design pixels; markers stay inside.
local LEFT_RESERVED = 130
local RIGHT_RESERVED = 175
local REF_WIDTH, REF_HEIGHT = 1280, 720
local MIN_SCALE, MAX_SCALE = 0.55, 1.25 -- the same clamp UIController uses
local TARGET_LIFT = Vector3.new(0, 4, 0) -- aim at the station's middle rather than its floor pivot

local player = Players.LocalPlayer
local gui: ScreenGui
local markers: { Marker } = {}

local function createMarker(model: Model)
	local look = AssetRegistry.TownStations[model.Name]
	if not look then
		return
	end
	local frame = Instance.new("Frame")
	frame.Name = model.Name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE)
	frame.BackgroundColor3 = Color3.fromRGB(22, 20, 36)
	frame.BackgroundTransparency = 0.15
	frame.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = look.Color
	stroke.Thickness = 2
	stroke.Parent = frame

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Text = look.Icon
	icon.TextSize = 24
	icon.Font = Enum.Font.GothamBold
	icon.Parent = frame

	-- The pivot spins around the marker's centre; its arrow sits just outside the circle.
	local pivot = Instance.new("Frame")
	pivot.BackgroundTransparency = 1
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Position = UDim2.fromScale(0.5, 0.5)
	pivot.Size = UDim2.fromScale(1, 1)
	pivot.Parent = frame
	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.AnchorPoint = Vector2.new(0, 0.5)
	arrow.Position = UDim2.new(1, 1, 0.5, 0)
	arrow.Size = UDim2.fromOffset(16, 16)
	arrow.Text = "▶"
	arrow.TextColor3 = look.Color
	arrow.TextSize = 16
	arrow.Font = Enum.Font.GothamBold
	arrow.Parent = pivot

	local distance = Instance.new("TextLabel")
	distance.BackgroundTransparency = 1
	distance.AnchorPoint = Vector2.new(0.5, 0)
	distance.Position = UDim2.new(0.5, 0, 1, 2)
	distance.Size = UDim2.fromOffset(80, 14)
	distance.Font = Enum.Font.GothamBold
	distance.TextSize = 12
	distance.TextColor3 = Color3.fromRGB(238, 236, 248)
	distance.TextStrokeTransparency = 0.4
	distance.Parent = frame

	frame.Parent = gui
	table.insert(markers, { Model = model, Frame = frame, Pivot = pivot, Distance = distance })
end

local function update()
	local camera = Workspace.CurrentCamera
	local inTown = player:GetAttribute("RunId") == nil
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not inTown or not (root and root:IsA("BasePart")) then
		for _, marker in markers do
			marker.Frame.Visible = false
		end
		return
	end

	local viewport = camera.ViewportSize
	local uiScale = math.clamp(math.min(viewport.X / REF_WIDTH, viewport.Y / REF_HEIGHT), MIN_SCALE, MAX_SCALE)
	local minX, maxX = EDGE_MARGIN + LEFT_RESERVED * uiScale, viewport.X - EDGE_MARGIN - RIGHT_RESERVED * uiScale
	local minY, maxY = TOP_MARGIN, viewport.Y - EDGE_MARGIN
	local halfX, halfY = (maxX - minX) / 2, (maxY - minY) / 2
	local boxCenter = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2)
	local edges: { [string]: { Placed } } = { Left = {}, Right = {}, Top = {}, Bottom = {} }

	for _, marker in markers do
		if not marker.Model.Parent then
			marker.Frame.Visible = false
			continue
		end
		local target = marker.Model:GetPivot().Position + TARGET_LIFT
		-- The second return of WorldToViewportPoint is "on screen", not "in front"; Z is the depth along the view.
		local point = camera:WorldToViewportPoint(target)
		local inFront = point.Z > 0
		local screen = Vector2.new(point.X, point.Y)
		if inFront and screen.X >= minX and screen.X <= maxX and screen.Y >= minY and screen.Y <= maxY then
			marker.Frame.Visible = false
			continue
		end

		-- Behind the camera the projection mirrors through the centre; flip it so the arrow still points the right way.
		local direction = if inFront then screen - boxCenter else boxCenter - screen
		if direction.Magnitude < 1 then
			direction = Vector2.new(0, -1)
		end
		-- Walk from the centre along `direction` until hitting the inset screen rectangle.
		local scaleX = if direction.X ~= 0 then halfX / math.abs(direction.X) else math.huge
		local scaleY = if direction.Y ~= 0 then halfY / math.abs(direction.Y) else math.huge
		local edge = boxCenter + direction * math.min(scaleX, scaleY)
		local side = if scaleX <= scaleY
			then (if direction.X < 0 then "Left" else "Right")
			else (if direction.Y < 0 then "Top" else "Bottom")

		marker.Pivot.Rotation = math.deg(math.atan2(direction.Y, direction.X))
		marker.Distance.Text = ("%dm"):format(math.round((target - root.Position).Magnitude))
		marker.Frame.Visible = true
		table.insert(edges[side], { Marker = marker, Position = edge })
	end

	-- Markers on the same edge are spread apart along it so their icons and distances never overlap.
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
		-- If the run spilled past the far end, slide everything back (never above the near end).
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
			entry.Marker.Frame.Position = UDim2.fromOffset(position.X, position.Y)
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

	RunService.RenderStepped:Connect(update)

	-- TownHubService builds the hub once at server start.
	local stations = Workspace:WaitForChild("TownHub"):WaitForChild("Stations")
	for _, child in stations:GetChildren() do
		if child:IsA("Model") then
			createMarker(child)
		end
	end
	stations.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Model") then
			createMarker(child)
		end
	end)
end

return WaypointController
