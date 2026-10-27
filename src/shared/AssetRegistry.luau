--!strict
-- ReplicatedStorage/Shared/AssetRegistry.luau
-- Central lookup table for all 3D Prefabs, 2D Icons, Colors, and Audio.
-- If a custom 3D model is not found in ReplicatedStorage.Assets, builds a stylized Neon/SmoothPlastic procedural fallback!

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModelNormalizer = require(script.Parent.ModelNormalizer)

export type RarityStyle = { Color: Color3, Glow: Color3 }
export type CurrencyInfo = {
	Name: string,
	FallbackIcon: string,
	ImageId: string,
	Color: Color3,
	Shape: Enum.PartType,
}

local AssetRegistry = {}

AssetRegistry.RarityStyles = {
	Common    = { Color = Color3.fromRGB(180, 190, 205), Glow = Color3.fromRGB(120, 130, 145) },
	Rare      = { Color = Color3.fromRGB(65, 155, 255),  Glow = Color3.fromRGB(30, 100, 220)  },
	Epic      = { Color = Color3.fromRGB(185, 85, 255),  Glow = Color3.fromRGB(130, 40, 210)  },
	Legendary = { Color = Color3.fromRGB(255, 195, 45),  Glow = Color3.fromRGB(255, 140, 0)   },
	Corrupted = { Color = Color3.fromRGB(255, 55, 95),   Glow = Color3.fromRGB(180, 10, 40)   },
} :: { [string]: RarityStyle }

AssetRegistry.Currencies = {
	RiftDust     = { Name = "Rift Dust",     FallbackIcon = "🔮", ImageId = "", Color = Color3.fromRGB(190, 95, 255),  Shape = Enum.PartType.Block    },
	BossCores    = { Name = "Boss Core",     FallbackIcon = "☀️", ImageId = "", Color = Color3.fromRGB(255, 200, 50),  Shape = Enum.PartType.Ball     },
	RelicShards  = { Name = "Relic Shard",   FallbackIcon = "💎", ImageId = "", Color = Color3.fromRGB(70, 200, 255),  Shape = Enum.PartType.Cylinder },
	RebirthSpark = { Name = "Rebirth Spark", FallbackIcon = "✨", ImageId = "", Color = Color3.fromRGB(255, 75, 110),  Shape = Enum.PartType.Ball     },
	AnchorToken  = { Name = "Anchor Token",  FallbackIcon = "⏳", ImageId = "", Color = Color3.fromRGB(60, 240, 200),  Shape = Enum.PartType.Cylinder },
} :: { [string]: CurrencyInfo }

-- Optional rbxassetid:// overrides. Leave "" to use the procedural/emoji fallback.
AssetRegistry.Icons = {} :: { [string]: string }
AssetRegistry.Sounds = {
	Hit       = "",
	Crit      = "",
	LevelUp   = "",
	Pickup    = "",
	BossRoar  = "",
	Rebirth   = "",
} :: { [string]: string }

-- Per-archetype look for procedural enemies (used until a model is dropped into Assets.Enemies)
AssetRegistry.EnemyLooks = {
	SporeBlob   = { Color = Color3.fromRGB(150, 220, 110), Shape = Enum.PartType.Ball,  Size = Vector3.new(3, 3, 3) },
	MushroomHop = { Color = Color3.fromRGB(235, 110, 90),  Shape = Enum.PartType.Ball,  Size = Vector3.new(3.5, 3.5, 3.5) },
	SporeGolem  = { Color = Color3.fromRGB(110, 150, 90),  Shape = Enum.PartType.Block, Size = Vector3.new(7, 8, 5) },
	MushroomTitan = { Color = Color3.fromRGB(190, 80, 70), Shape = Enum.PartType.Block, Size = Vector3.new(8, 9, 6) },
	Default     = { Color = Color3.fromRGB(200, 90, 200),  Shape = Enum.PartType.Ball,  Size = Vector3.new(3, 3, 3) },
} :: { [string]: { Color: Color3, Shape: Enum.PartType, Size: Vector3 } }

local function findCustomPrefab(folderName: string, key: string): Model?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assetsFolder and assetsFolder:FindFirstChild(folderName)
	local prefab = folder and folder:FindFirstChild(key)
	if prefab and prefab:IsA("Model") then
		return prefab
	end
	return nil
end

local function addGlow(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = part
end

function AssetRegistry.GetCurrencyIcon(currencyKey: string): string
	local info = AssetRegistry.Currencies[currencyKey]
	if info and info.ImageId ~= "" then
		return info.ImageId
	end
	return if info then info.FallbackIcon else "❔"
end

function AssetRegistry.GetRarityStyle(rarity: string): RarityStyle
	return AssetRegistry.RarityStyles[rarity] or AssetRegistry.RarityStyles.Common
end

-- Spawns either a custom model from ReplicatedStorage.Assets.Drops OR a clean stylized Neon drop orb
function AssetRegistry.CreateCurrencyDropModel(currencyKey: string): Model
	local customPrefab = findCustomPrefab("Drops", currencyKey)
	if customPrefab then
		return ModelNormalizer.SanitizeAndNormalize(customPrefab:Clone(), Vector3.new(1.5, 1.5, 1.5))
	end

	-- Procedural Stylized Fallback (looks great out-of-the-box!)
	local info = AssetRegistry.Currencies[currencyKey] or AssetRegistry.Currencies.RiftDust
	local model = Instance.new("Model")
	model.Name = currencyKey .. "_Drop"

	local core = Instance.new("Part")
	core.Name = "PrimaryPart"
	core.Shape = info.Shape
	core.Size = Vector3.new(1.4, 1.4, 1.4)
	core.Color = info.Color
	core.Material = Enum.Material.Neon
	core.Anchored = true
	core.CanCollide = false
	core.Parent = model
	addGlow(core, info.Color, 8, 1.5)

	model.PrimaryPart = core
	return model
end

-- Enemy prefab: custom model from Assets.Enemies, else a glowing blob with eyes.
-- `scale` is 1 for normal, 1.5 for Elites, 2.5 for Bosses (Section 31.2).
function AssetRegistry.CreateEnemyModel(enemyKey: string, scale: number?): Model
	local s = scale or 1
	local look = AssetRegistry.EnemyLooks[enemyKey] or AssetRegistry.EnemyLooks.Default

	local customPrefab = findCustomPrefab("Enemies", enemyKey)
	if customPrefab then
		return ModelNormalizer.SanitizeAndNormalize(customPrefab:Clone(), look.Size * s)
	end

	local model = Instance.new("Model")
	model.Name = enemyKey

	local body = Instance.new("Part")
	body.Name = "PrimaryPart"
	body.Shape = look.Shape
	body.Size = look.Size * s
	body.Color = look.Color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model

	for _, side in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.one * (0.5 * s)
		eye.Color = Color3.new(1, 1, 1)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.Massless = true
		eye.CFrame = body.CFrame * CFrame.new(side * 0.6 * s, 0.4 * s, body.Size.Z / 2)
		eye.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = eye
		weld.Parent = eye
	end

	model.PrimaryPart = body
	return model
end

-- Weapon prefab: custom model from Assets.Weapons, else a simple neon blade/orb.
function AssetRegistry.CreateWeaponModel(weaponKey: string, accent: Color3?): Model
	local customPrefab = findCustomPrefab("Weapons", weaponKey)
	if customPrefab then
		return ModelNormalizer.SanitizeAndNormalize(customPrefab:Clone(), Vector3.new(1, 4, 1))
	end

	local color = accent or Color3.fromRGB(220, 230, 255)
	local model = Instance.new("Model")
	model.Name = weaponKey

	local handle = Instance.new("Part")
	handle.Name = "PrimaryPart"
	handle.Size = Vector3.new(0.4, 4, 0.4)
	handle.Color = color
	handle.Material = Enum.Material.Neon
	handle.Anchored = true
	handle.CanCollide = false
	handle.Parent = model
	addGlow(handle, color, 6, 1)

	model.PrimaryPart = handle
	return model
end

-- Town Hub stations (Section 5.1). Custom models go in ReplicatedStorage.Assets.Town.<Key>.
export type StationLook = { Name: string, Color: Color3, Size: Vector3, Icon: string }

AssetRegistry.TownStations = {
	RiftGate = { Name = "Central Rift Gate", Color = Color3.fromRGB(190, 95, 255), Size = Vector3.new(9, 12, 2), Icon = "🌀" },
	AscensionPedestal = { Name = "Ascension Pedestal", Color = Color3.fromRGB(255, 75, 110), Size = Vector3.new(5, 4, 5), Icon = "✨" },
	SparkSanctum = { Name = "Spark Sanctum", Color = Color3.fromRGB(255, 150, 60), Size = Vector3.new(6, 4, 4), Icon = "⭐" },
	Blacksmith = { Name = "Blacksmith", Color = Color3.fromRGB(255, 120, 40), Size = Vector3.new(6, 4, 4), Icon = "⚒️" },
	LegionHall = { Name = "Mastery & Legion Hall", Color = Color3.fromRGB(90, 200, 255), Size = Vector3.new(6, 4, 4), Icon = "🛡️" },
	StarForge = { Name = "Star-Forge & Relic Vault", Color = Color3.fromRGB(80, 160, 255), Size = Vector3.new(6, 4, 4), Icon = "🔨" },
	QuestBoard = { Name = "Quest Board", Color = Color3.fromRGB(240, 220, 120), Size = Vector3.new(5, 5, 1), Icon = "📜" },
	HallOfChampions = { Name = "Hall of Champions", Color = Color3.fromRGB(255, 210, 70), Size = Vector3.new(7, 3, 4), Icon = "🏆" },
	RiftShrine = { Name = "Rift Shrine", Color = Color3.fromRGB(120, 255, 200), Size = Vector3.new(4, 5, 4), Icon = "🔮" },
} :: { [string]: StationLook }

local function addLabel(part: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StationLabel"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 3.5, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = color:Lerp(Color3.new(0, 0, 0), 0.6)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
end

local function newStationPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- Station prefab whose pivot is its bottom-centre, so callers can PivotTo the floor point directly. Prompts hang on
-- the PrimaryPart. Everything is anchored and non-colliding so stations never block the 2.5D lane.
function AssetRegistry.CreateStationModel(stationKey: string): Model
	local look = AssetRegistry.TownStations[stationKey] or AssetRegistry.TownStations.QuestBoard
	local title = look.Icon .. " " .. look.Name

	local customPrefab = findCustomPrefab("Town", stationKey)
	if customPrefab then
		local model = ModelNormalizer.SanitizeAndNormalize(customPrefab:Clone(), look.Size)
		local cf, size = model:GetBoundingBox()
		model.WorldPivot = cf * CFrame.new(0, -size.Y / 2, 0)
		if model.PrimaryPart then
			addLabel(model.PrimaryPart, title, look.Color)
		end
		return model
	end

	local model = Instance.new("Model")
	model.Name = stationKey
	local stone = look.Color:Lerp(Color3.fromRGB(60, 55, 70), 0.65)
	local base: Part

	if stationKey == "RiftGate" then
		-- Stone frame with a neon portal disc facing the camera (a Cylinder's long axis is X; turn it onto Z).
		base = newStationPart(model, "PrimaryPart", Vector3.new(look.Size.X, look.Size.Y, 1.5),
			CFrame.new(0, look.Size.Y / 2, -1), Color3.fromRGB(70, 60, 90), Enum.Material.Slate)
		local disc = newStationPart(model, "Portal", Vector3.new(0.6, look.Size.X - 1.5, look.Size.X - 1.5),
			CFrame.new(0, look.Size.Y / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), look.Color, Enum.Material.Neon)
		disc.Shape = Enum.PartType.Cylinder
		disc.Transparency = 0.15
		addGlow(disc, look.Color, 24, 2.5)
	else
		base = newStationPart(model, "PrimaryPart", look.Size, CFrame.new(0, look.Size.Y / 2, 0), stone, Enum.Material.Slate)
		newStationPart(model, "Trim", Vector3.new(look.Size.X + 0.3, 0.4, look.Size.Z + 0.3),
			CFrame.new(0, look.Size.Y - 0.2, 0), look.Color, Enum.Material.Neon)
		local crystal = newStationPart(model, "Crystal", Vector3.one * 1.8, CFrame.new(0, look.Size.Y + 1.4, 0),
			look.Color, Enum.Material.Neon)
		crystal.Shape = Enum.PartType.Ball
		addGlow(crystal, look.Color, 14, 1.6)
	end

	addLabel(base, title, look.Color)
	model.PrimaryPart = base
	model.WorldPivot = CFrame.new()
	return model
end

return AssetRegistry
