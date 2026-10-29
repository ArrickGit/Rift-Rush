--!strict
-- ReplicatedStorage/Shared/AssetRegistry.luau
-- Central lookup table for all 3D Prefabs, 2D Icons, Colors, and Audio.
-- If a custom 3D model is not found in ReplicatedStorage.Assets, builds a stylized Neon/SmoothPlastic procedural fallback!

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LandmarkBuilder = require(script.Parent.LandmarkBuilder)
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

-- Uploaded images (assets/*/picked, uploaded via Studio 2026-10-29). Icons are white on transparent: tint them with
-- ImageColor3. Keyed by game id (Weapon_<WeaponId>, Relic_<RelicId>, Asc_<NodeId>, Quest_<QuestId>, Curse_<CurseId>,
-- Card_<UpgradeId>, Link_<SkillId>, Ability_<AbilityId>, Cur_*, UI_*). Icons from game-icons.net (CC BY 3.0, credit
-- required; authors in assets/icons/picked/CREDITS.txt).
AssetRegistry.Icons = {
	Ability_ArrowRain      = "rbxassetid://74102725144490",
	Ability_CallFamiliar   = "rbxassetid://120047303635981",
	Ability_Fireball       = "rbxassetid://87595724082098",
	Ability_RiftCleave     = "rbxassetid://102821409574049",
	Ability_RisingUppercut = "rbxassetid://123635665507501",
	Ability_RoyalFlush     = "rbxassetid://98026427515665",
	Ability_SeismicTremor  = "rbxassetid://114037926786191",
	Ability_ShurikenFan    = "rbxassetid://119896648660053",
	Asc_AS_INF_01          = "rbxassetid://101518232544859",
	Asc_AS_INF_02          = "rbxassetid://125765242716926",
	Asc_AS_T1_01           = "rbxassetid://122672197084585",
	Asc_AS_T1_02           = "rbxassetid://114533957510024",
	Asc_AS_T1_03           = "rbxassetid://134133863653540",
	Asc_AS_T1_04           = "rbxassetid://112165808987074",
	Asc_AS_T1_05           = "rbxassetid://129975354427416",
	Asc_AS_T2_01           = "rbxassetid://139123164430379",
	Asc_AS_T2_02           = "rbxassetid://80757386890194",
	Asc_AS_T2_03           = "rbxassetid://77802378366769",
	Asc_AS_T2_04           = "rbxassetid://119751476880630",
	Asc_AS_T3_01           = "rbxassetid://81977585096080",
	Asc_AS_T3_02           = "rbxassetid://123409771271861",
	Asc_AS_T3_03           = "rbxassetid://71580934805894",
	Asc_AS_T3_04           = "rbxassetid://121848296426875",
	Asc_AS_T4_01           = "rbxassetid://98440549541530",
	Asc_AS_T4_02           = "rbxassetid://112363296485045",
	Card_CleavingGale      = "rbxassetid://126481212364816",
	Card_EmberEdge         = "rbxassetid://119187610323555",
	Card_KeenEye           = "rbxassetid://70546651745185",
	Card_NapalmWake        = "rbxassetid://85481756329623",
	Card_SharpenedEdge     = "rbxassetid://129271568827568",
	Card_StormConduit      = "rbxassetid://104610751015382",
	Card_SwiftHands        = "rbxassetid://126179969098135",
	Card_TripleThreat      = "rbxassetid://87568179351741",
	Card_VitalSurge        = "rbxassetid://108642020954984",
	Card_VolatileCinders   = "rbxassetid://102403291707872",
	Cur_AnchorTokens       = "rbxassetid://115484791100460",
	Cur_BossCores          = "rbxassetid://92268319946238",
	Cur_Dust               = "rbxassetid://127005343069894",
	Cur_RelicShards        = "rbxassetid://72862805569162",
	Cur_Safeguard          = "rbxassetid://126676002142833",
	Cur_Sparks             = "rbxassetid://128700092032544",
	Curse_Famine           = "rbxassetid://112772611450105",
	Curse_Frenzy           = "rbxassetid://85752496288396",
	Curse_GlassCannon      = "rbxassetid://108756317188973",
	Curse_Greed            = "rbxassetid://90922604997751",
	Curse_Hubris           = "rbxassetid://104542297925170",
	Link_ArcaneFlow        = "rbxassetid://125073611542530",
	Link_CrushingForce     = "rbxassetid://129598341170551",
	Link_EagleEye          = "rbxassetid://124528640098711",
	Link_LethalInstinct    = "rbxassetid://134241200065380",
	Link_LuckyDraw         = "rbxassetid://89365167344063",
	Link_RelentlessFlurry  = "rbxassetid://89205901883629",
	Link_RiftFortune       = "rbxassetid://115978114142987",
	Link_TitansMight       = "rbxassetid://72126088072551",
	Quest_B_Boss           = "rbxassetid://95036033883542",
	Quest_B_Monsters       = "rbxassetid://77402462688750",
	Quest_D_Banker         = "rbxassetid://111606991313138",
	Quest_D_Diver          = "rbxassetid://74221990881539",
	Quest_D_Elites         = "rbxassetid://91286467548994",
	Quest_D_Extract        = "rbxassetid://88804483136064",
	Quest_D_Giants         = "rbxassetid://132770217202714",
	Quest_D_Jumper         = "rbxassetid://133358280619026",
	Quest_D_Pact           = "rbxassetid://100509795542750",
	Quest_D_Sweeper        = "rbxassetid://134905689312718",
	Quest_D_Treasure       = "rbxassetid://134263104339934",
	Relic_REL_01           = "rbxassetid://96125987249092",
	Relic_REL_02           = "rbxassetid://75580257638956",
	Relic_REL_03           = "rbxassetid://85863532271419",
	Relic_REL_04           = "rbxassetid://132378090107651",
	Relic_REL_05           = "rbxassetid://113475736796335",
	Relic_REL_06           = "rbxassetid://131123551914037",
	Relic_REL_07           = "rbxassetid://106016677990840",
	Relic_REL_08           = "rbxassetid://130563189159130",
	UI_Anvil               = "rbxassetid://124567239944333",
	UI_Bag                 = "rbxassetid://98876267591171",
	UI_Chest               = "rbxassetid://122613360022334",
	UI_Damage              = "rbxassetid://102821409574049",
	UI_Gift                = "rbxassetid://100466928494948",
	UI_Health              = "rbxassetid://81285223500592",
	UI_Lock                = "rbxassetid://88906915385474",
	UI_Mastery             = "rbxassetid://88738781583671",
	UI_Podium              = "rbxassetid://113165614725015",
	UI_Portal              = "rbxassetid://131838522978065",
	UI_Quest               = "rbxassetid://71924992045337",
	UI_Rebirth             = "rbxassetid://89242123879001",
	UI_Settings            = "rbxassetid://118686659871592",
	UI_Timer               = "rbxassetid://113854801508234",
	UI_Upgrade             = "rbxassetid://113608136506745",
	Weapon_Bow             = "rbxassetid://85787947109343",
	Weapon_Daggers         = "rbxassetid://80320480133452",
	Weapon_Gauntlets       = "rbxassetid://139976567760049",
	Weapon_Greatsword      = "rbxassetid://98846070547889",
	Weapon_Hammer          = "rbxassetid://76660364143718",
	Weapon_Staff           = "rbxassetid://95508043270024",
	Weapon_SummoningBell   = "rbxassetid://115224989613946",
	Weapon_TrickCards      = "rbxassetid://89989387780114",
} :: { [string]: string }

-- Kenney Particle Pack (CC0) textures for ParticleEmitters and reward bursts
AssetRegistry.VfxTextures = {
	circle_05 = "rbxassetid://74218128985958",
	fire_01   = "rbxassetid://103075230443905",
	flare_01  = "rbxassetid://97424109099664",
	light_01  = "rbxassetid://76924088015555",
	magic_01  = "rbxassetid://97182490078113",
	magic_03  = "rbxassetid://95101147455198",
	scorch_01 = "rbxassetid://103701063087244",
	slash_02  = "rbxassetid://86955345937655",
	smoke_01  = "rbxassetid://134789860212770",
	spark_01  = "rbxassetid://98055133986496",
	spark_04  = "rbxassetid://113260492213178",
	star_01   = "rbxassetid://82027585255328",
	star_04   = "rbxassetid://124727012255767",
	star_06   = "rbxassetid://114374120768418",
	trace_02  = "rbxassetid://96729696542381",
	twirl_01  = "rbxassetid://70864435028926",
} :: { [string]: string }

-- Kenney UI Pack RPG Expansion (CC0) panel and button textures (use with SliceCenter)
AssetRegistry.UiTextures = {
	buttonLong_brown         = "rbxassetid://97496117996129",
	buttonLong_brown_pressed = "rbxassetid://131480767936014",
	buttonRound_beige        = "rbxassetid://109745857086282",
	iconCheck_bronze         = "rbxassetid://111637388339678",
	panelInset_beige         = "rbxassetid://135715082367412",
	panelInset_beigeLight    = "rbxassetid://76668008204432",
	panel_beige              = "rbxassetid://82043823991128",
	panel_beigeLight         = "rbxassetid://74985952927834",
	panel_brown              = "rbxassetid://123730090805324",
} :: { [string]: string }

-- Optional rbxassetid:// sound overrides. Leave "" for silence.
AssetRegistry.Sounds = {
	Hit              = "",
	Crit             = "",
	LevelUp          = "",
	Pickup           = "",
	BossRoar         = "",
	Rebirth          = "",
	-- Kenney Interface Sounds / UI Audio / RPG Audio (CC0), uploaded 2026-10-29
	Bag_Open         = "rbxassetid://136044055314636",
	Combat_Chop      = "rbxassetid://138629116329646",
	Combat_Swing1    = "rbxassetid://74872112387410",
	Combat_Swing2    = "rbxassetid://100155187207965",
	Currency_Gain    = "rbxassetid://112457593930083",
	Forge_Fail       = "rbxassetid://90744447602157",
	Forge_Hammer1    = "rbxassetid://116737900709178",
	Forge_Hammer2    = "rbxassetid://137601866128813",
	Forge_Hammer3    = "rbxassetid://140644085661049",
	Forge_Success    = "rbxassetid://101397735792150",
	Gate_Open        = "rbxassetid://121396265598131",
	Item_Drop        = "rbxassetid://99315215745532",
	Quest_BoardClose = "rbxassetid://83534969898122",
	Quest_BoardOpen  = "rbxassetid://132808870188001",
	Quest_CardFlip   = "rbxassetid://112490784004944",
	Quest_Claim      = "rbxassetid://79936323470392",
	Shop_Buy         = "rbxassetid://107849495811042",
	UI_Click         = "rbxassetid://101259929279509",
	UI_Confirm       = "rbxassetid://103018333508655",
	UI_Error         = "rbxassetid://80232623660843",
	UI_Hover         = "rbxassetid://79006065577716",
	UI_PanelClose    = "rbxassetid://86536600125100",
	UI_PanelOpen     = "rbxassetid://104724216749010",
	UI_Popup         = "rbxassetid://131970873505500",
	UI_ProgressTick  = "rbxassetid://123488399402536",
	UI_Tab           = "rbxassetid://120277369201383",
	UI_Toggle        = "rbxassetid://116855791031644",
	UI_Unlock        = "rbxassetid://126011737388709",
	Weapon_Equip     = "rbxassetid://111192202991197",
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
		local model = ModelNormalizer.SanitizeAndNormalize(customPrefab:Clone(), look.Size * s)
		-- ProceduralAnimController turns enemies by FacingYaw (degrees) so their face points at the camera (+Z).
		-- Imported glTF/FBX creatures (Quaternius, KayKit) face away from it, so default to 180; set a FacingYaw
		-- number attribute on a prefab in Assets.Enemies to override.
		if type(model:GetAttribute("FacingYaw")) ~= "number" then
			model:SetAttribute("FacingYaw", 180)
		end
		return model
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

-- Town Hub stations (Section 5.1). Custom models go in ReplicatedStorage.Assets.Town.<Key>. Every station except the
-- Rift Gate is a Hero Landmark (Section 33.1): fitted into LandmarkBuilder.LANDMARK_SIZE (12-16 studs tall) on top
-- of its own themed Sanctuary Dais.
export type StationLook = { Name: string, Color: Color3, Size: Vector3, Icon: string }

local LANDMARK = LandmarkBuilder.LANDMARK_SIZE

AssetRegistry.TownStations = {
	RiftGate = { Name = "Central Rift Gate", Color = Color3.fromRGB(190, 95, 255), Size = Vector3.new(9, 12, 2), Icon = "🌀" },
	AscensionPedestal = { Name = "Ascension Pedestal", Color = Color3.fromRGB(255, 75, 110), Size = LANDMARK, Icon = "✨" },
	SparkSanctum = { Name = "Spark Sanctum", Color = Color3.fromRGB(255, 150, 60), Size = LANDMARK, Icon = "⭐" },
	Blacksmith = { Name = "Blacksmith", Color = Color3.fromRGB(255, 120, 40), Size = LANDMARK, Icon = "⚒️" },
	LegionHall = { Name = "Mastery & Legion Hall", Color = Color3.fromRGB(90, 200, 255), Size = LANDMARK, Icon = "🛡️" },
	StarForge = { Name = "Star-Forge & Relic Vault", Color = Color3.fromRGB(170, 110, 255), Size = LANDMARK, Icon = "🔨" },
	QuestBoard = { Name = "Quest Board", Color = Color3.fromRGB(240, 220, 120), Size = LANDMARK, Icon = "📜" },
	HallOfChampions = { Name = "Hall of Champions", Color = Color3.fromRGB(255, 210, 70), Size = LANDMARK, Icon = "🏆" },
	RiftShrine = { Name = "Rift Shrine", Color = Color3.fromRGB(120, 255, 200), Size = LANDMARK, Icon = "🔮" },
} :: { [string]: StationLook }

-- Persistent overhead waypoint (WaypointController) for any interactable: tag + display attributes.
function AssetRegistry.TagWaypoint(instance: Instance, name: string, icon: string, color: Color3)
	instance:SetAttribute("WaypointName", name)
	instance:SetAttribute("WaypointIcon", icon)
	instance:SetAttribute("WaypointColor", color)
	CollectionService:AddTag(instance, "RiftWaypoint")
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

-- A Model with a PrimaryPart ignores WorldPivot and pivots on its PrimaryPart (plus PivotOffset), so the
-- bottom-centre pivot has to be set as the PrimaryPart's PivotOffset. Without it, PivotTo(floor) buries half the model.
local function setBottomPivot(model: Model, pivot: CFrame)
	local primary = model.PrimaryPart
	if primary then
		primary.PivotOffset = primary.CFrame:ToObjectSpace(pivot)
	else
		model.WorldPivot = pivot
	end
end

-- Procedural landmark (no prefab in Assets.Town): a stone shrine with pillars, a roof and a floating crystal, built
-- standing on Y = 0 and filling `size`.
local function buildFallbackLandmark(model: Model, look: StationLook)
	local size = look.Size
	local stone = look.Color:Lerp(Color3.fromRGB(60, 55, 70), 0.65)
	newStationPart(model, "Base", Vector3.new(size.X * 0.8, size.Y * 0.18, size.Z * 0.8), CFrame.new(0, size.Y * 0.09, 0),
		stone, Enum.Material.Slate)
	for _, x in { -1, 1 } do
		for _, z in { -1, 1 } do
			newStationPart(model, "Pillar", Vector3.new(1.2, size.Y * 0.55, 1.2),
				CFrame.new(x * size.X * 0.32, size.Y * 0.455, z * size.Z * 0.28), stone:Lerp(Color3.new(1, 1, 1), 0.25), Enum.Material.Marble)
		end
	end
	newStationPart(model, "Roof", Vector3.new(size.X * 0.85, size.Y * 0.08, size.Z * 0.85), CFrame.new(0, size.Y * 0.77, 0),
		look.Color, Enum.Material.Neon)
	local crystal = newStationPart(model, "Crystal", Vector3.new(2.2, 3.2, 2.2), CFrame.new(0, size.Y * 0.9, 0) * CFrame.Angles(0, math.pi / 4, 0),
		look.Color, Enum.Material.Glass)
	addGlow(crystal, look.Color, 16, 1.8)
end

-- Station whose pivot is its bottom-centre, so callers can PivotTo the floor point directly. The prompt hangs on the
-- PrimaryPart (an invisible anchor in the landmark's middle). Everything is anchored and non-colliding so stations
-- never block the 2.5D lane. Landmark stations are their Sanctuary Dais plus the prefab fitted on top.
function AssetRegistry.CreateStationModel(stationKey: string): Model
	local look = AssetRegistry.TownStations[stationKey] or AssetRegistry.TownStations.QuestBoard
	if stationKey ~= "RiftGate" then
		local station = Instance.new("Model")
		station.Name = stationKey
		local floorY = LandmarkBuilder.BuildDais(stationKey, station)
		local landmark: Model
		local customPrefab = findCustomPrefab("Town", stationKey)
		if customPrefab then
			landmark = ModelNormalizer.FitInBox(customPrefab:Clone(), look.Size)
		else
			landmark = Instance.new("Model")
			buildFallbackLandmark(landmark, look)
		end
		landmark.Name = "Landmark"
		local cf, size = landmark:GetBoundingBox()
		landmark:PivotTo(landmark:GetPivot() + (Vector3.new(0, floorY + size.Y / 2, 0) - cf.Position))
		landmark.Parent = station
		local anchor = newStationPart(station, "PromptAnchor", Vector3.new(2, 2, 2), CFrame.new(0, floorY + size.Y / 2, 0),
			look.Color, Enum.Material.SmoothPlastic)
		anchor.Transparency = 1
		station.PrimaryPart = anchor
		setBottomPivot(station, CFrame.new())
		AssetRegistry.TagWaypoint(station, look.Name, look.Icon, look.Color)
		return station
	end

	local model = Instance.new("Model")
	model.Name = stationKey
	local base: Part

	do
		-- Stone frame with a neon portal disc facing the camera (a Cylinder's long axis is X; turn it onto Z).
		base = newStationPart(model, "PrimaryPart", Vector3.new(look.Size.X, look.Size.Y, 1.5),
			CFrame.new(0, look.Size.Y / 2, -1), Color3.fromRGB(70, 60, 90), Enum.Material.Slate)
		local disc = newStationPart(model, "Portal", Vector3.new(0.6, look.Size.X - 1.5, look.Size.X - 1.5),
			CFrame.new(0, look.Size.Y / 2, 0) * CFrame.Angles(0, math.pi / 2, 0), look.Color, Enum.Material.Neon)
		disc.Shape = Enum.PartType.Cylinder
		disc.Transparency = 0.15
		addGlow(disc, look.Color, 24, 2.5)
	end

	model.PrimaryPart = base
	setBottomPivot(model, CFrame.new()) -- parts were built around the origin, standing on Y = 0
	AssetRegistry.TagWaypoint(model, look.Name, look.Icon, look.Color)
	return model
end

return AssetRegistry
