--!strict
-- ReplicatedStorage/Shared/VistaBuilder.luau
-- The bright high-fantasy background vista (game.md Section 33.4), built once for Haven Outpost and once per run
-- between Z = -35 and Z = -180: floating sky-islands with waterfalls, a colossal World Tree, sunlit castle spires,
-- a stone aqueduct, rolling hills, drifting low-poly clouds and rising golden spirit motes.
-- Everything is anchored scenery (no collision / queries). Bobbing islands use the "RiftBob" tag and clouds the
-- "RiftDrift" tag (attrs DriftSpeed, DriftMin, DriftMax), animated on each client by AmbientController.

local CollectionService = game:GetService("CollectionService")

local VistaBuilder = {}

local STONE = Color3.fromRGB(196, 200, 214)
local ROOF = Color3.fromRGB(86, 104, 196)
local GOLD = Color3.fromRGB(255, 214, 110)
local BARK = Color3.fromRGB(116, 84, 60)
local LEAF = Color3.fromRGB(96, 196, 104)
local ROCK = Color3.fromRGB(140, 116, 96)
local WATER = Color3.fromRGB(150, 220, 255)

local function part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function drum(parent: Instance, diameter: number, height: number, center: Vector3, color: Color3, material: Enum.Material): Part
	return part(parent, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color,
		material, Enum.PartType.Cylinder)
end

local function ball(parent: Instance, diameter: number, center: Vector3, color: Color3, material: Enum.Material): Part
	return part(parent, Vector3.one * diameter, CFrame.new(center), color, material, Enum.PartType.Ball)
end

local function emitter(p: BasePart, color: Color3, rate: number, life: number, speed: number, size: number, direction: Enum.NormalId)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.6
	e.Rate = rate
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Speed = NumberRange.new(speed * 0.8, speed)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.EmissionDirection = direction
	e.SpreadAngle = Vector2.new(4, 4)
	e.Parent = p
end

local function tower(parent: Instance, base: Vector3, diameter: number, height: number)
	drum(parent, diameter, height, base + Vector3.new(0, height / 2, 0), STONE, Enum.Material.Limestone)
	drum(parent, diameter + 1.6, 2, base + Vector3.new(0, height, 0), STONE:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Limestone)
	-- Stepped spire roof.
	for step = 0, 4 do
		local d = (diameter + 1) * (1 - step * 0.2)
		drum(parent, d, 3, base + Vector3.new(0, height + 2.5 + step * 3, 0), ROOF, Enum.Material.SmoothPlastic)
	end
	local tip = ball(parent, 2, base + Vector3.new(0, height + 18, 0), GOLD, Enum.Material.Neon)
	tip.Name = "Spire"
	for index = 1, 3 do
		part(parent, Vector3.new(1.2, 2.4, 0.3), CFrame.new(base + Vector3.new(0, height * index / 4, diameter / 2 + 0.1)),
			Color3.fromRGB(255, 226, 150), Enum.Material.Neon)
	end
end

local function skyIsland(parent: Instance, center: Vector3, diameter: number, rng: Random)
	local island = Instance.new("Model")
	island.Name = "SkyIsland"
	island.Parent = parent
	island.PrimaryPart = drum(island, diameter, 2.4, center, LEAF, Enum.Material.Grass) -- the pivot travels with the island
	drum(island, diameter * 0.9, 4, center - Vector3.new(0, 3, 0), ROCK, Enum.Material.Rock)
	drum(island, diameter * 0.62, 5, center - Vector3.new(0, 7.5, 0), ROCK:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Rock)
	drum(island, diameter * 0.32, 5, center - Vector3.new(0, 12, 0), ROCK:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Rock)
	-- A little tree and glowing flowers on top.
	local tx = center.X + rng:NextNumber(-diameter * 0.25, diameter * 0.15)
	drum(island, 1.6, 7, Vector3.new(tx, center.Y + 4.5, center.Z - 1), BARK, Enum.Material.Wood)
	ball(island, 7, Vector3.new(tx, center.Y + 9.5, center.Z - 1), LEAF:Lerp(Color3.new(1, 1, 1), 0.1), Enum.Material.Grass)
	ball(island, 5, Vector3.new(tx + 2.4, center.Y + 8, center.Z), LEAF, Enum.Material.Grass)
	for index = 1, 4 do
		local flower = ball(island, 0.9, center + Vector3.new(rng:NextNumber(-diameter * 0.35, diameter * 0.35), 1.6, rng:NextNumber(-2, 3)),
			if index % 2 == 0 then Color3.fromRGB(255, 150, 210) else Color3.fromRGB(255, 240, 140), Enum.Material.Neon)
		flower.Name = "Flower"
	end
	-- Cascading waterfall off the front-right lip, with mist where it fades out.
	local fallHeight = rng:NextNumber(28, 46)
	local wx = center.X + diameter * 0.28
	local fall = part(island, Vector3.new(3, fallHeight, 1.2), CFrame.new(wx, center.Y - fallHeight / 2 + 1, center.Z + diameter * 0.3),
		WATER, Enum.Material.Glass)
	fall.Name = "Waterfall"
	fall.Transparency = 0.35
	emitter(fall, Color3.fromRGB(235, 248, 255), 26, fallHeight / 26, 26, 1.3, Enum.NormalId.Bottom)
	local mist = part(island, Vector3.new(4, 1, 2), CFrame.new(wx, center.Y - fallHeight + 2, center.Z + diameter * 0.3), WATER, Enum.Material.Glass)
	mist.Transparency = 1
	emitter(mist, Color3.fromRGB(255, 255, 255), 6, 2.5, 3, 4, Enum.NormalId.Top)
	CollectionService:AddTag(island, "RiftBob")
	island:SetAttribute("BobAmp", rng:NextNumber(0.8, 1.6))
	island:SetAttribute("BobSpeed", rng:NextNumber(0.25, 0.45))
	island:SetAttribute("BobPhase", rng:NextNumber(0, 6))
end

local function cloud(parent: Instance, center: Vector3, scale: number, minX: number, maxX: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Cloud"
	model.Parent = parent
	for index = 1, 4 do
		local puff = ball(model, scale * rng:NextNumber(0.7, 1.15), center + Vector3.new((index - 2.5) * scale * 0.55, rng:NextNumber(-0.15, 0.25) * scale, 0),
			Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
		puff.Transparency = 0.06
		if index == 2 then
			model.PrimaryPart = puff
		end
	end
	CollectionService:AddTag(model, "RiftDrift")
	model:SetAttribute("DriftSpeed", rng:NextNumber(1.2, 3))
	model:SetAttribute("DriftMin", minX)
	model:SetAttribute("DriftMax", maxX)
end

-- Builds the vista for a playfield whose bottom-left corner is `origin` and which is `width` studs wide.
function VistaBuilder.Build(origin: Vector3, width: number, parent: Instance, seed: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Vista"
	local rng = Random.new(seed)
	local floor = origin.Y + 6
	local left, right = origin.X - 130, origin.X + width + 130
	local cx = origin.X + width / 2

	-- Rolling hills on the horizon.
	for index = 0, 6 do
		local diameter = rng:NextNumber(70, 110)
		ball(folder, diameter, Vector3.new(left + (right - left) * index / 6 + rng:NextNumber(-15, 15), floor - diameter * 0.32, -190 - rng:NextNumber(0, 15)),
			Color3.fromRGB(116, 178, 128):Lerp(Color3.fromRGB(150, 190, 220), rng:NextNumber(0, 0.4)), Enum.Material.Grass)
	end

	-- The colossal World Tree.
	local treeX = cx + rng:NextNumber(-40, 50)
	local treeZ = -168
	drum(folder, 26, 12, Vector3.new(treeX, floor + 4, treeZ), BARK:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Wood)
	drum(folder, 15, 80, Vector3.new(treeX, floor + 40, treeZ), BARK, Enum.Material.Wood)
	for index = 1, 4 do
		local side = if index % 2 == 0 then 1 else -1
		part(folder, Vector3.new(30, 4, 4), CFrame.new(treeX + side * 12, floor + 52 + index * 6, treeZ) * CFrame.Angles(0, index, side * 0.45),
			BARK, Enum.Material.Wood)
	end
	local canopyRng = Random.new(seed + 3)
	for index = 1, 7 do
		local canopy = ball(folder, canopyRng:NextNumber(30, 46),
			Vector3.new(treeX + canopyRng:NextNumber(-30, 30), floor + 78 + canopyRng:NextNumber(-8, 22), treeZ + canopyRng:NextNumber(-6, 6)),
			LEAF:Lerp(Color3.fromRGB(170, 240, 150), canopyRng:NextNumber(0, 0.45)), Enum.Material.Grass)
		canopy.Name = "Canopy" .. index
	end
	for _ = 1, 8 do
		local fruit = ball(folder, 2.4, Vector3.new(treeX + canopyRng:NextNumber(-30, 30), floor + 66 + canopyRng:NextNumber(0, 30), treeZ + 18),
			GOLD, Enum.Material.Neon)
		fruit.Name = "GlowFruit"
	end
	local treeGlow = part(folder, Vector3.new(60, 30, 10), CFrame.new(treeX, floor + 85, treeZ + 12), GOLD, Enum.Material.Neon)
	treeGlow.Transparency = 1
	emitter(treeGlow, GOLD, 10, 6, 2, 1.2, Enum.NormalId.Top)

	-- Sunlit castle on the far left hill: three spires and their walls.
	local castleX = left + 60 + rng:NextNumber(0, 30)
	local castleZ = -150
	tower(folder, Vector3.new(castleX - 18, floor, castleZ), 9, 38)
	tower(folder, Vector3.new(castleX, floor, castleZ - 6), 12, 56)
	tower(folder, Vector3.new(castleX + 18, floor, castleZ), 9, 34)
	part(folder, Vector3.new(36, 18, 6), CFrame.new(castleX, floor + 9, castleZ + 1), STONE, Enum.Material.Limestone)
	for index = -3, 3 do
		part(folder, Vector3.new(3, 3, 6.2), CFrame.new(castleX + index * 5, floor + 19.5, castleZ + 1), STONE, Enum.Material.Limestone)
	end

	-- Stone aqueduct arches crossing toward the right.
	local aqueductX = right - 120 + rng:NextNumber(-10, 10)
	local aqueductZ = -122
	local span = 110
	for index = 0, 6 do
		part(folder, Vector3.new(4, 26, 5), CFrame.new(aqueductX + index * span / 6, floor + 13, aqueductZ), STONE, Enum.Material.Limestone)
		if index < 6 then
			-- Rounded arch head between pillars.
			local arch = drum(folder, span / 6 - 3, 5, Vector3.new(aqueductX + (index + 0.5) * span / 6, floor + 21, aqueductZ), STONE, Enum.Material.Limestone)
			arch.CFrame = CFrame.new(arch.Position) * CFrame.Angles(0, math.pi / 2, 0)
			arch.Size = Vector3.new(5, span / 6 - 3, span / 6 - 3)
		end
	end
	part(folder, Vector3.new(span + 6, 4, 6), CFrame.new(aqueductX + span / 2, floor + 27, aqueductZ), STONE:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Limestone)
	local channel = part(folder, Vector3.new(span + 6, 0.6, 3), CFrame.new(aqueductX + span / 2, floor + 29.2, aqueductZ), WATER, Enum.Material.Glass)
	channel.Transparency = 0.2

	-- Floating sky-islands with waterfalls, spread across the view at mid depth.
	local islandCount = 4
	for index = 1, islandCount do
		local x = left + 40 + (right - left - 80) * (index - 1) / (islandCount - 1) + rng:NextNumber(-20, 20)
		skyIsland(folder, Vector3.new(x, floor + rng:NextNumber(34, 58), -rng:NextNumber(62, 108)), rng:NextNumber(14, 22), rng)
	end

	-- Fluffy low-poly clouds drifting across the sky.
	for _ = 1, 9 do
		cloud(folder, Vector3.new(rng:NextNumber(left, right), floor + rng:NextNumber(55, 95), -rng:NextNumber(80, 175)),
			rng:NextNumber(9, 16), left - 40, right + 40, rng)
	end

	-- Rising golden spirit motes in front of it all.
	local motes = part(folder, Vector3.new(right - left, 30, 30), CFrame.new(cx, floor + 18, -50), GOLD, Enum.Material.Neon)
	motes.Transparency = 1
	emitter(motes, GOLD, 18, 7, 2, 0.5, Enum.NormalId.Top)

	folder.Parent = parent
	return folder
end

return VistaBuilder
