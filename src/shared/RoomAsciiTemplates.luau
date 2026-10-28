--!strict
-- ReplicatedStorage/Shared/RoomAsciiTemplates.luau
-- 2.5D ASCII tilemap rooms (Section 31.1). Every room is 16 columns x 9 rows; each tile is 8x6x10 studs
-- (X, Y, Z) and the grid lies on the Z=0 combat plane. Row 1 is the ceiling, row 9 the floor.
--
--   '#' Solid ground block (grass-topped)       '.' Empty air
--   '=' One-way drop-through platform           '^' Jump pad (launches the player upward)
--   'S' Player spawn                            'E' Portal exit
--   'M' Normal mob spawner                      'X' Elite mob spawner
--   'B' Boss spawner                            'C' Chest spawner
--
-- A spawner letter marks the cell the actor stands in, so the tile directly below it must be '#' or '='.
-- Platforms sit 1 row (6 studs) or 2 rows (12 studs, needs a double jump) apart; use '^' for bigger climbs.

export type RoomType = "Combat" | "Jump" | "Treasure" | "Boss"

export type RoomTemplate = {
	Id: string,
	Name: string,
	Type: RoomType,
	Objective: string, -- "{N}" is replaced by the number of enemies to defeat
	Grid: { string },
	RisingPoison: number?, -- studs/second the Jump Quest acid climbs (it burns and bounces; the exit is at the top)
}

-- FloorTurf / FloorStone / PlatformTurf / PlatformFrame switch on the high-contrast rule (game.md Section 33.4): the
-- ground floor is dark emerald turf over slate, every elevated platform is sunlit lime grass in a warm timber frame.
export type WorldTheme = {
	Ground: Color3,
	Cap: Color3,
	Platform: Color3,
	Backdrop: Color3,
	Accent: Color3,
	FloorTurf: Color3?,
	FloorStone: Color3?,
	PlatformTurf: Color3?,
	PlatformFrame: Color3?,
}

export type WorldTemplates = {
	Name: string,
	Theme: WorldTheme,
	Sequence: { string }, -- fixed templates for Rooms 1-10
	EndlessCombat: { string }, -- weighted pool for Rooms 11+ (duplicates = higher weight)
	MiniBossRoom: string, -- Rift Anchor rooms 5, 15, 25...
	WorldBossRoom: string, -- Rift Anchor rooms 10, 20, 30...
	NormalEnemies: { string },
	EliteEnemy: string,
	MiniBoss: string,
	WorldBoss: string,
}

local RoomAsciiTemplates = {}

RoomAsciiTemplates.COLUMNS = 16
RoomAsciiTemplates.ROWS = 9
RoomAsciiTemplates.TILE_SIZE = Vector3.new(8, 6, 10)

RoomAsciiTemplates.Rooms = {} :: { [string]: RoomTemplate }

local function add(template: RoomTemplate)
	RoomAsciiTemplates.Rooms[template.Id] = template
end

-- Rooms 1-4: Entry ------------------------------------------------------------------------------------------

add({
	Id = "MushroomWilds_Room01", Name = "Spore Meadow", Type = "Combat",
	Objective = "Clear {N} Corrupted Spores",
	Grid = {
		"################",
		"#..............#",
		"#..............#",
		"#....M....M....#",
		"#...===..===...#",
		"#..M........M..#",
		"#.====....====.#",
		"#S..^.M.M.M...E#",
		"################",
	},
})

add({
	Id = "MushroomWilds_Room02", Name = "Mushroom Grove", Type = "Combat",
	Objective = "Clear {N} Corrupted Spores",
	Grid = {
		"################",
		"#..............#",
		"#..............#",
		"#........M..M..#",
		"#......======..#",
		"#..M..M........#",
		"#.=====........#",
		"#S.==.M..MM.^.E#",
		"################",
	},
})

add({
	Id = "MushroomWilds_Room03", Name = "Rising Spores", Type = "Jump",
	Objective = "Climb to the portal before the acid rises!",
	RisingPoison = 0.9,
	Grid = {
		"################",
		"#.............E#",
		"#....C...======#",
		"#...====.......#",
		"#.......====...#",
		"#...====.......#",
		"#.......====...#",
		"#S.====........#",
		"################",
	},
})

add({
	Id = "MushroomWilds_Room04", Name = "Rift Shrine", Type = "Treasure",
	Objective = "Open the Rift Shrine Chests",
	Grid = {
		"################",
		"#..............#",
		"#..............#",
		"#...C........C.#",
		"#.===......===.#",
		"#..............#",
		"#.......C......#",
		"#S.^..===..^..E#",
		"################",
	},
})

-- Room 5: First Rift Anchor (Mini-Boss) ----------------------------------------------------------------------

add({
	Id = "MushroomWilds_Room05", Name = "Golem Hollow", Type = "Boss",
	Objective = "Defeat the Spore Golem!",
	Grid = {
		"################",
		"#..............#",
		"#..............#",
		"#..............#",
		"#...====..====.#",
		"#..............#",
		"#.===......===.#",
		"#S.^....B...^.E#",
		"################",
	},
})

-- Rooms 6-9: Deep Rift ---------------------------------------------------------------------------------------

add({
	Id = "MushroomWilds_Room06", Name = "Deeper Spores", Type = "Combat",
	Objective = "Clear {N} Corrupted Spores",
	Grid = {
		"################",
		"#..............#",
		"#..............#",
		"#...M.......M..#",
		"#.====....====.#",
		"#......X.......#",
		"#....======....#",
		"#S.^.M..M.^.M.E#",
		"################",
	},
})

add({
	Id = "MushroomWilds_Room07", Name = "Elite Hunt", Type = "Combat",
	Objective = "Hunt Down {N} Corrupted Spores",
	Grid = {
		"################",
		"#..............#",
		"#...M.......X..#",
		"#.===......===.#",
		"#....M..X......#",
		"#...=======....#",
		"#..............#",
		"#S.M..^...^.M.E#",
		"################",
	},
})

add({
	Id = "MushroomWilds_Room08", Name = "Spore Spire", Type = "Jump",
	Objective = "Climb to the portal before the acid rises!",
	RisingPoison = 1.2,
	Grid = {
		"################",
		"#E.............#",
		"#=====...C.....#",
		"#......====....#",
		"#...====..====.#",
		"#..............#",
		"#..............#",
		"#S.^........^..#",
		"################",
	},
})

add({
	Id = "MushroomWilds_Room09", Name = "Treasure Hunt", Type = "Combat",
	Objective = "Clear {N} Corrupted Spores",
	Grid = {
		"################",
		"#..............#",
		"#...MC....X....#",
		"#.====..====...#",
		"#.....X..M.....#",
		"#....=======...#",
		"#..............#",
		"#S..M.^.....M.E#",
		"################",
	},
})

-- Room 10: Main Rift Anchor (World Boss) ---------------------------------------------------------------------

add({
	Id = "MushroomWilds_Room10", Name = "Titan's Cap", Type = "Boss",
	Objective = "Defeat the Mushroom Titan!",
	Grid = {
		"################",
		"#..............#",
		"#..............#",
		"#..............#",
		"#...===....===.#",
		"#..............#",
		"#.....======...#",
		"#S.^...B....^.E#",
		"################",
	},
})

-- Worlds -----------------------------------------------------------------------------------------------------

RoomAsciiTemplates.Worlds = {
	[1] = {
		Name = "Mushroom Wilds",
		Theme = {
			Ground = Color3.fromRGB(112, 80, 54),
			Cap = Color3.fromRGB(92, 172, 72),
			Platform = Color3.fromRGB(172, 122, 72),
			Backdrop = Color3.fromRGB(66, 112, 92),
			Accent = Color3.fromRGB(255, 210, 120),
			FloorTurf = Color3.fromRGB(46, 108, 54),
			FloorStone = Color3.fromRGB(52, 54, 66),
			PlatformTurf = Color3.fromRGB(118, 222, 78),
			PlatformFrame = Color3.fromRGB(155, 118, 78),
		},
		Sequence = {
			"MushroomWilds_Room01", "MushroomWilds_Room02", "MushroomWilds_Room03", "MushroomWilds_Room04",
			"MushroomWilds_Room05", "MushroomWilds_Room06", "MushroomWilds_Room07", "MushroomWilds_Room08",
			"MushroomWilds_Room09", "MushroomWilds_Room10",
		},
		EndlessCombat = {
			"MushroomWilds_Room01", "MushroomWilds_Room01", "MushroomWilds_Room02", "MushroomWilds_Room02",
			"MushroomWilds_Room06", "MushroomWilds_Room06", "MushroomWilds_Room07", "MushroomWilds_Room07",
			"MushroomWilds_Room09", "MushroomWilds_Room09",
			"MushroomWilds_Room03", "MushroomWilds_Room08", "MushroomWilds_Room04",
		},
		MiniBossRoom = "MushroomWilds_Room05",
		WorldBossRoom = "MushroomWilds_Room10",
		NormalEnemies = { "SporeBlob", "MushroomHop" },
		EliteEnemy = "MushroomHop",
		MiniBoss = "SporeGolem",
		WorldBoss = "MushroomTitan",
	},
} :: { [number]: WorldTemplates }

-- Town Hub (Section 5.1) -------------------------------------------------------------------------------------
-- Haven Outpost: a wider (48-column) three-tier layout. Station letters are Town Hub stations built by
-- RoomBuilderService.BuildTownHub; '^' pads launch players through the one-way '=' tiers above them.
--   S spawn   G Central Rift Gate   P Ascension Pedestal   A Spark Sanctum (Ascension Shop)   K Blacksmith
--   L Mastery & Legion Hall   F Star-Forge & Relic Vault   Q Quest Board   H Hall of Champions   R Rift Shrine

export type TownTemplate = {
	Name: string,
	Theme: WorldTheme,
	Grid: { string },
	Stations: { [string]: string }, -- grid letter -> station key (AssetRegistry.TownStations)
}

RoomAsciiTemplates.TownHub = {
	Name = "Haven Outpost",
	Theme = {
		Ground = Color3.fromRGB(128, 104, 82),
		Cap = Color3.fromRGB(120, 196, 96),
		Platform = Color3.fromRGB(196, 150, 96),
		Backdrop = Color3.fromRGB(120, 168, 214),
		Accent = Color3.fromRGB(255, 196, 120),
		FloorTurf = Color3.fromRGB(62, 138, 70),
		FloorStone = Color3.fromRGB(122, 102, 86),
		PlatformTurf = Color3.fromRGB(118, 222, 78),
		PlatformFrame = Color3.fromRGB(155, 118, 78),
	},
	Grid = {
		"#..............................................#",
		"#...........H.......................R..........#",
		"#........=======.................=======.......#",
		"#..............................................#",
		"#......L..^......F.............Q..^............#",
		"#...=======...=======.......=======............#",
		"#..............................................#",
		"#.S..^..K......^.......G.....^...P.....A.......#",
		"################################################",
	},
	Stations = {
		G = "RiftGate",
		P = "AscensionPedestal",
		A = "SparkSanctum",
		K = "Blacksmith",
		L = "LegionHall",
		F = "StarForge",
		Q = "QuestBoard",
		H = "HallOfChampions",
		R = "RiftShrine",
	},
} :: TownTemplate

function RoomAsciiTemplates.GetWorld(worldIndex: number): WorldTemplates?
	return RoomAsciiTemplates.Worlds[worldIndex]
end

function RoomAsciiTemplates.GetRoom(templateId: string): RoomTemplate?
	return RoomAsciiTemplates.Rooms[templateId]
end

-- Rift Anchors (and their bosses) sit on every 5th room: 5 and 15 are mini-boss rooms, 10 and 20 world-boss rooms.
function RoomAsciiTemplates.IsAnchorRoom(roomNumber: number): boolean
	return roomNumber >= 5 and roomNumber % 5 == 0
end

function RoomAsciiTemplates.GetTemplateId(worldIndex: number, roomNumber: number, rng: Random): string?
	local world = RoomAsciiTemplates.Worlds[worldIndex]
	if not world then
		return nil
	end
	if roomNumber <= #world.Sequence then
		return world.Sequence[roomNumber]
	end
	if RoomAsciiTemplates.IsAnchorRoom(roomNumber) then
		return if roomNumber % 10 == 5 then world.MiniBossRoom else world.WorldBossRoom
	end
	return world.EndlessCombat[rng:NextInteger(1, #world.EndlessCombat)]
end

-- Returns (ok, reason). Catches malformed grids when a template is edited.
function RoomAsciiTemplates.Validate(template: RoomTemplate): (boolean, string?)
	local grid = template.Grid
	if #grid ~= RoomAsciiTemplates.ROWS then
		return false, ("%s has %d rows, expected %d"):format(template.Id, #grid, RoomAsciiTemplates.ROWS)
	end
	local spawns, exits = 0, 0
	for rowIndex, row in grid do
		if #row ~= RoomAsciiTemplates.COLUMNS then
			return false, ("%s row %d has %d columns, expected %d"):format(template.Id, rowIndex, #row, RoomAsciiTemplates.COLUMNS)
		end
		for _ in row:gmatch("S") do
			spawns += 1
		end
		for _ in row:gmatch("E") do
			exits += 1
		end
	end
	if spawns ~= 1 or exits ~= 1 then
		return false, ("%s needs exactly one 'S' and one 'E'"):format(template.Id)
	end
	return true, nil
end

return RoomAsciiTemplates
