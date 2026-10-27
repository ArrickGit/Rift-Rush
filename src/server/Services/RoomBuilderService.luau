--!strict
-- ServerScriptService/Server/Services/RoomBuilderService.luau
-- Reads RoomAsciiTemplates (Section 31.1) and builds one 2.5D room: merged ground/platform strips, jump pads,
-- backdrop props, a portal exit and spawn points. It only builds geometry; RunManagerService decides what
-- spawns where and when the exit opens. BuildTownHub builds Haven Outpost (Section 5.1) from the same tile rules;
-- TownHubService wires its station prompts.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Physics25D = require(Shared:WaitForChild("Physics25D"))
local RoomAsciiTemplates = require(Shared:WaitForChild("RoomAsciiTemplates"))

type RoomTemplate = RoomAsciiTemplates.RoomTemplate
type WorldTheme = RoomAsciiTemplates.WorldTheme

export type BuiltRoom = {
	Template: RoomTemplate,
	Folder: Folder,
	Origin: Vector3, -- bottom-left corner of the room on the Z=0 plane
	PlayerSpawn: CFrame,
	Exit: BasePart, -- invisible trigger zone; players inside it are "at the exit"
	ExitVisual: BasePart,
	-- Positions are where the actor's feet rest (bottom-centre of the spawner's cell).
	MobSpawns: { Vector3 },
	EliteSpawns: { Vector3 },
	BossSpawns: { Vector3 },
	ChestSpawns: { Vector3 },
	Poison: BasePart?,
	PoisonSpeed: number,
	Width: number,
	Height: number,
}

export type TownHub = {
	Folder: Folder,
	Spawn: SpawnLocation, -- named "TownSpawn" and parented straight to Workspace (RunManagerService looks it up)
	Stations: { [string]: Model }, -- station key -> model; prompts go on the model's PrimaryPart
}

local RoomBuilderService = {}

local TILE = RoomAsciiTemplates.TILE_SIZE
local COLUMNS = RoomAsciiTemplates.COLUMNS
local ROWS = RoomAsciiTemplates.ROWS

local PLATFORM_THICKNESS = 1
local GRASS_THICKNESS = 0.8
-- Ground slabs sit behind the combat plane (Z = 0) so their front face is just in front of the actors. Centred
-- on the plane, half of the walkable top would draw in front of everyone and they would look sunk into it.
local LANE_Z = 2 - TILE.Z / 2
local BACKDROP_Z = -12 -- mushroom props stand in the meadow behind this depth
local SKIRT_WIDTH = 80 -- ground drawn past each side wall; wider than the camera ever sees
local BEDROCK_DEPTH = 40
local MEADOW_DEPTH = 220
-- The meadow spans width + 2 * margin. Run slots are RUN_SLOT_SPACING (400) apart and rooms are 128 wide, so 136
-- lets neighbouring runs' meadows meet without overlapping.
local MEADOW_MARGIN = 136
local EDGE_WALL_HEIGHT = 200

local EXIT_OPEN_COLOR = Color3.fromRGB(80, 235, 255)
local EXIT_LOCKED_COLOR = Color3.fromRGB(255, 70, 80)
local PAD_COLOR = Color3.fromRGB(255, 120, 200)

-- Grids are 16x9 for rooms and wider for the Town Hub, so sizes come from the grid itself.
local function cellAt(grid: { string }, column: number, row: number): string
	if row < 1 or row > #grid or column < 1 or column > #grid[row] then
		return "#"
	end
	return grid[row]:sub(column, column)
end

-- World position of a cell's bottom-centre (where something standing in the cell rests).
local function cellBottom(grid: { string }, origin: Vector3, column: number, row: number): Vector3
	return origin + Vector3.new((column - 0.5) * TILE.X, (#grid - row) * TILE.Y, 0)
end

local function newPart(parent: Instance, name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = center
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Calls `emit(firstColumn, length)` for each horizontal run of the `columns` cells where `matches(column)` holds.
local function forEachRun(columns: number, matches: (number) -> boolean, emit: (number, number) -> ())
	local column = 1
	while column <= columns do
		if matches(column) then
			local first = column
			while column + 1 <= columns and matches(column + 1) do
				column += 1
			end
			emit(first, column - first + 1)
		end
		column += 1
	end
end

-- Border walls and ceilings (a '#' on the grid edge whose inward neighbour is open) become invisible barriers,
-- so the scenery from buildBackdrop shows past the room's edges instead of a bare stone column. Ground that
-- reaches the edge (the bottom row, ledges touching the wall) stays visible.
local function isBarrier(grid: { string }, column: number, row: number): boolean
	local columns = #grid[row]
	if cellAt(grid, column, row) ~= "#" or row == #grid then
		return false
	end
	local dx = if column == 1 then 1 elseif column == columns then -1 else 0
	local dy = if row == 1 then 1 else 0
	if dx == 0 and dy == 0 then
		return false
	end
	return cellAt(grid, column + dx, row + dy) ~= "#"
end

local function isVisibleGround(grid: { string }, column: number, row: number): boolean
	return cellAt(grid, column, row) == "#" and not isBarrier(grid, column, row)
end

local function buildTerrain(room: Folder, grid: { string }, origin: Vector3, theme: WorldTheme)
	local terrain = Instance.new("Folder")
	terrain.Name = "Terrain"
	terrain.Parent = room

	local rows = #grid
	for row = 1, rows do
		local rowBottom = origin.Y + (rows - row) * TILE.Y
		local columns = #grid[row]

		-- Solid ground, merged per row, with a grass strip on every cell that has open air above it.
		forEachRun(columns, function(column)
			return isVisibleGround(grid, column, row)
		end, function(first, length)
			local centerX = origin.X + (first - 1 + length / 2) * TILE.X
			newPart(terrain, "Ground", Vector3.new(length * TILE.X, TILE.Y, TILE.Z),
				Vector3.new(centerX, rowBottom + TILE.Y / 2, LANE_Z), theme.Ground, Enum.Material.Slate)
		end)
		forEachRun(columns, function(column)
			return isBarrier(grid, column, row)
		end, function(first, length)
			local centerX = origin.X + (first - 1 + length / 2) * TILE.X
			local wall = newPart(terrain, "Barrier", Vector3.new(length * TILE.X, TILE.Y, TILE.Z),
				Vector3.new(centerX, rowBottom + TILE.Y / 2, 0), theme.Ground, Enum.Material.SmoothPlastic)
			wall.Transparency = 1
			wall.CastShadow = false
		end)
		-- The cap is sunk into the ground with its top flush with the walkable surface (a hair proud to avoid
		-- z-fighting), so feet and station models stand on the grass instead of inside it.
		forEachRun(columns, function(column)
			return isVisibleGround(grid, column, row) and not isVisibleGround(grid, column, row - 1)
		end, function(first, length)
			local centerX = origin.X + (first - 1 + length / 2) * TILE.X
			local cap = newPart(terrain, "GrassCap", Vector3.new(length * TILE.X, GRASS_THICKNESS, TILE.Z + 0.2),
				Vector3.new(centerX, rowBottom + TILE.Y - GRASS_THICKNESS / 2 + 0.02, LANE_Z), theme.Cap, Enum.Material.Grass)
			cap.CanCollide = false
			cap.CanQuery = false
		end)

		-- One-way platforms: a thin slab whose top is flush with the top of the row.
		forEachRun(columns, function(column)
			return cellAt(grid, column, row) == "="
		end, function(first, length)
			local centerX = origin.X + (first - 1 + length / 2) * TILE.X
			local platform = newPart(terrain, "OneWay", Vector3.new(length * TILE.X, PLATFORM_THICKNESS, TILE.Z),
				Vector3.new(centerX, rowBottom + TILE.Y - PLATFORM_THICKNESS / 2, LANE_Z), theme.Platform, Enum.Material.WoodPlanks)
			CollectionService:AddTag(platform, Physics25D.ONE_WAY_TAG)
		end)
	end
end

local function newScenery(parent: Instance, name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material): Part
	local part = newPart(parent, name, size, center, color, material)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- Scenery around the playable grid (Section 31.5): a grass meadow running back to the horizon under the open sky
-- (SetupSky), ground continuing past both side walls, bedrock under the floor, and mushroom props in the meadow.
-- Tall invisible walls on both sides stop jump pads from launching anyone over the edge.
local function buildBackdrop(room: Folder, origin: Vector3, theme: WorldTheme, seed: number, width: number, _height: number)
	local floorY = origin.Y + TILE.Y
	local centerX = origin.X + width / 2

	newScenery(room, "Bedrock", Vector3.new(width + 2 * SKIRT_WIDTH, BEDROCK_DEPTH, TILE.Z),
		Vector3.new(centerX, origin.Y - BEDROCK_DEPTH / 2, LANE_Z), theme.Ground, Enum.Material.Slate)
	newScenery(room, "Meadow", Vector3.new(width + 2 * MEADOW_MARGIN, TILE.Y + BEDROCK_DEPTH, MEADOW_DEPTH),
		Vector3.new(centerX, floorY - (TILE.Y + BEDROCK_DEPTH) / 2, LANE_Z - TILE.Z / 2 - MEADOW_DEPTH / 2),
		theme.Cap:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.Grass).CastShadow = false

	for side = -1, 1, 2 do
		local skirtX = centerX + side * (width / 2 + SKIRT_WIDTH / 2)
		newScenery(room, "SideGround", Vector3.new(SKIRT_WIDTH, TILE.Y, TILE.Z), Vector3.new(skirtX, origin.Y + TILE.Y / 2, LANE_Z),
			theme.Ground, Enum.Material.Slate)
		newScenery(room, "SideGrass", Vector3.new(SKIRT_WIDTH, GRASS_THICKNESS, TILE.Z + 0.2),
			Vector3.new(skirtX, floorY - GRASS_THICKNESS / 2 + 0.02, LANE_Z), theme.Cap, Enum.Material.Grass)

		local wall = newPart(room, "EdgeWall", Vector3.new(1, EDGE_WALL_HEIGHT, TILE.Z),
			Vector3.new(centerX + side * (width / 2 + 0.5), floorY + EDGE_WALL_HEIGHT / 2, 0), theme.Ground, Enum.Material.SmoothPlastic)
		wall.Transparency = 1
		wall.CastShadow = false
		wall.CanQuery = false
	end

	local rng = Random.new(seed)
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = room
	for _ = 1, math.max(9, math.round(width / 14)) do
		local x = origin.X + rng:NextNumber(4, width - 4)
		local z = BACKDROP_Z - rng:NextNumber(2, 14)
		local stemHeight = rng:NextNumber(8, 22)
		local stem = newPart(props, "Stem", Vector3.new(stemHeight, 3, 3), Vector3.new(x, floorY + stemHeight / 2, z),
			Color3.fromRGB(235, 225, 200), Enum.Material.SmoothPlastic)
		stem.Shape = Enum.PartType.Cylinder
		stem.CFrame = CFrame.new(x, floorY + stemHeight / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		local capSize = rng:NextNumber(10, 18)
		local cap = newPart(props, "Cap", Vector3.new(capSize, capSize * 0.55, capSize),
			Vector3.new(x, floorY + stemHeight, z), theme.Accent:Lerp(Color3.fromRGB(220, 80, 90), rng:NextNumber(0, 1)),
			Enum.Material.SmoothPlastic)
		cap.Shape = Enum.PartType.Ball
		for _, prop in { stem, cap } do
			prop.CanCollide = false
			prop.CanQuery = false
			prop.CanTouch = false
		end
	end
end

local function buildJumpPad(room: Folder, bottom: Vector3)
	local pad = newPart(room, "JumpPad", Vector3.new(6, 1, TILE.Z), Vector3.new(bottom.X, bottom.Y + 0.5, LANE_Z), PAD_COLOR, Enum.Material.Neon)
	pad.CanCollide = false

	local light = Instance.new("PointLight")
	light.Color = PAD_COLOR
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = pad

	-- Movement25DController launches the local character when it stands on a tagged pad.
	CollectionService:AddTag(pad, Physics25D.JUMP_PAD_TAG)
end

local function buildExit(room: Folder, bottom: Vector3): (BasePart, BasePart)
	local zone = newPart(room, "ExitZone", Vector3.new(TILE.X, 12, TILE.Z), bottom + Vector3.new(0, 6, 0),
		EXIT_LOCKED_COLOR, Enum.Material.SmoothPlastic)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false

	-- Neon disc facing the camera (a Cylinder's long axis is X, so turn it to point along Z).
	local visual = newPart(room, "ExitPortal", Vector3.new(0.6, 9, 9), bottom + Vector3.new(0, 5, -2),
		EXIT_LOCKED_COLOR, Enum.Material.Neon)
	visual.Shape = Enum.PartType.Cylinder
	visual.CFrame = CFrame.new(bottom + Vector3.new(0, 5, -2)) * CFrame.Angles(0, math.pi / 2, 0)
	visual.CanCollide = false
	visual.CanQuery = false
	visual.Transparency = 0.35

	local light = Instance.new("PointLight")
	light.Color = EXIT_LOCKED_COLOR
	light.Range = 18
	light.Brightness = 2
	light.Parent = visual
	return zone, visual
end

function RoomBuilderService.SetExitOpen(room: BuiltRoom, open: boolean)
	local color = if open then EXIT_OPEN_COLOR else EXIT_LOCKED_COLOR
	room.ExitVisual.Color = color
	room.ExitVisual.Transparency = if open then 0.1 else 0.55
	local light = room.ExitVisual:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
	end
end

-- Chest with a built-in hold-to-open prompt; the caller connects `Triggered` and destroys/marks the chest.
function RoomBuilderService.CreateChest(room: BuiltRoom, position: Vector3): (BasePart, ProximityPrompt)
	local chest = newPart(room.Folder, "Chest", Vector3.new(3.6, 2.6, 3), position + Vector3.new(0, 1.3, 0),
		Color3.fromRGB(150, 98, 50), Enum.Material.WoodPlanks)
	chest.CanCollide = false

	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Size = Vector3.new(3.8, 0.6, 3.2)
	trim.Color = Color3.fromRGB(255, 205, 70)
	trim.Material = Enum.Material.Neon
	trim.CanCollide = false
	trim.Massless = true
	trim.CFrame = chest.CFrame * CFrame.new(0, 0.9, 0)
	trim.Parent = chest
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chest
	weld.Part1 = trim
	weld.Parent = trim

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 205, 70)
	light.Range = 12
	light.Brightness = 1.2
	light.Parent = chest

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Treasure Chest"
	prompt.ActionText = "Open"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = chest
	return chest, prompt
end

-- Builds the template at `origin` (bottom-left corner of the room, Z=0 plane) under `parent`.
function RoomBuilderService.BuildRoom(templateId: string, origin: Vector3, parent: Instance, worldIndex: number): BuiltRoom?
	local template = RoomAsciiTemplates.GetRoom(templateId)
	local world = RoomAsciiTemplates.GetWorld(worldIndex)
	if not template or not world then
		warn(("[RoomBuilderService] Unknown template %s / world %d"):format(templateId, worldIndex))
		return nil
	end
	local valid, reason = RoomAsciiTemplates.Validate(template)
	if not valid then
		warn("[RoomBuilderService] " .. tostring(reason))
		return nil
	end

	local grid = template.Grid
	local folder = Instance.new("Folder")
	folder.Name = template.Id

	buildTerrain(folder, grid, origin, world.Theme)
	buildBackdrop(folder, origin, world.Theme, #templateId * 7919, COLUMNS * TILE.X, ROWS * TILE.Y)

	local mobSpawns: { Vector3 } = {}
	local eliteSpawns: { Vector3 } = {}
	local bossSpawns: { Vector3 } = {}
	local chestSpawns: { Vector3 } = {}
	local playerSpawn = CFrame.new(origin + Vector3.new(TILE.X * 1.5, TILE.Y * 2, 0))
	local exitZone: BasePart? = nil
	local exitVisual: BasePart? = nil

	for row = 1, ROWS do
		for column = 1, COLUMNS do
			local cell = cellAt(grid, column, row)
			local bottom = cellBottom(grid, origin, column, row)
			if cell == "S" then
				playerSpawn = CFrame.new(bottom + Vector3.new(0, 3.2, 0))
			elseif cell == "E" then
				exitZone, exitVisual = buildExit(folder, bottom)
			elseif cell == "^" then
				buildJumpPad(folder, bottom)
			elseif cell == "M" then
				table.insert(mobSpawns, bottom)
			elseif cell == "X" then
				table.insert(eliteSpawns, bottom)
			elseif cell == "B" then
				table.insert(bossSpawns, bottom)
			elseif cell == "C" then
				table.insert(chestSpawns, bottom)
			end
		end
	end

	-- Validate() guarantees an 'E', so these are always set.
	assert(exitZone and exitVisual, "room has no exit")

	local width = COLUMNS * TILE.X
	local height = ROWS * TILE.Y

	-- Jump Quest poison: a translucent plane that starts inside the floor and creeps upward.
	local poison: BasePart? = nil
	local poisonSpeed = template.RisingPoison or 0
	if poisonSpeed > 0 then
		local plane = newPart(folder, "RisingPoison", Vector3.new(width - TILE.X * 2, 4, TILE.Z + 4),
			Vector3.new(origin.X + width / 2, origin.Y - 2, 0), Color3.fromRGB(120, 255, 90), Enum.Material.Neon)
		plane.Transparency = 0.45
		plane.CanCollide = false
		plane.CanQuery = false
		plane.CanTouch = false
		poison = plane
	end

	folder.Parent = parent

	local built: BuiltRoom = {
		Template = template,
		Folder = folder,
		Origin = origin,
		PlayerSpawn = playerSpawn,
		Exit = exitZone,
		ExitVisual = exitVisual,
		MobSpawns = mobSpawns,
		EliteSpawns = eliteSpawns,
		BossSpawns = bossSpawns,
		ChestSpawns = chestSpawns,
		Poison = poison,
		PoisonSpeed = poisonSpeed,
		Width = width,
		Height = height,
	}
	RoomBuilderService.SetExitOpen(built, false)
	return built
end

-- Clear blue daytime sky shared by the town and every run. The skybox and Clouds render at infinity, so they
-- follow the camera everywhere; GlobalWind keeps the clouds drifting. Safe to call more than once.
function RoomBuilderService.SetupSky()
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 0
	sky.StarCount = 0
	sky.Parent = Lighting

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(190, 222, 255)
	atmosphere.Decay = Color3.fromRGB(110, 160, 230)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.8
	atmosphere.Parent = Lighting

	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.45
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(255, 255, 255)
	clouds.Parent = Workspace.Terrain
	Workspace.GlobalWind = Vector3.new(8, 0, 3)

	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 20
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 160, 180)
	Lighting.Ambient = Color3.fromRGB(70, 75, 90)
end

function RoomBuilderService.DestroyRoom(room: BuiltRoom)
	room.Folder:Destroy()
end

-- Builds Haven Outpost with its bottom-left corner at `origin`. Station letters in the town grid become
-- AssetRegistry station models standing in their cell, a little behind the combat plane so players walk in front.
function RoomBuilderService.BuildTownHub(origin: Vector3, parent: Instance): TownHub
	local town = RoomAsciiTemplates.TownHub
	local grid = town.Grid
	local rows = #grid
	local columns = #grid[1]
	local width = columns * TILE.X
	local height = rows * TILE.Y

	local folder = Instance.new("Folder")
	folder.Name = "TownHub"
	buildTerrain(folder, grid, origin, town.Theme)
	buildBackdrop(folder, origin, town.Theme, 4242, width, height)

	local stationFolder = Instance.new("Folder")
	stationFolder.Name = "Stations"
	stationFolder.Parent = folder

	local stations: { [string]: Model } = {}
	local spawnBottom = origin + Vector3.new(TILE.X * 1.5, TILE.Y, 0)
	for row = 1, rows do
		for column = 1, columns do
			local cell = cellAt(grid, column, row)
			local bottom = cellBottom(grid, origin, column, row)
			local stationKey = town.Stations[cell]
			if cell == "S" then
				spawnBottom = bottom
			elseif cell == "^" then
				buildJumpPad(folder, bottom)
			elseif stationKey then
				local model = AssetRegistry.CreateStationModel(stationKey)
				model:PivotTo(CFrame.new(bottom + Vector3.new(0, 0, -3)))
				model.Parent = stationFolder
				stations[stationKey] = model
			end
		end
	end

	folder.Parent = parent

	local existing = Workspace:FindFirstChild("TownSpawn")
	if existing then
		existing:Destroy()
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TownSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn ForceField in town
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = spawnBottom + Vector3.new(0, 0.5, 0)
	spawn.Color = town.Theme.Accent
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn.Parent = Workspace

	return { Folder = folder, Spawn = spawn, Stations = stations }
end

return RoomBuilderService
