--!strict
-- ReplicatedStorage/Shared/LandmarkBuilder.luau
-- Bespoke Sanctuary Daises for every Town Hub station and the Rift Shrine pact altars (game.md Section 33.2).
-- Each builder adds multi-part, themed geometry to a Model around the origin: (0, 0, 0) is the dais's bottom-centre
-- and +Z faces the camera. It returns the height the station's landmark stands on.
--
-- Moving bits are animated on each client by AmbientController (nothing here runs per frame on the server):
--   tag "RiftSpin" (attrs SpinSpeed rad/s, SpinAxis "X"|"Y"|"Z")  tag "RiftBob" (attrs BobAmp, BobSpeed, BobPhase)
-- Either tag works on a BasePart or a Model (a Model turns around its pivot). Animated models always get a
-- PrimaryPart at their centre, so their pivot travels with them when the whole station is placed.

local CollectionService = game:GetService("CollectionService")

local LandmarkBuilder = {}

LandmarkBuilder.DAIS_WIDTH = 20
LandmarkBuilder.DAIS_DEPTH = 10
LandmarkBuilder.LANDMARK_SIZE = Vector3.new(13, 14, 8.5) -- station landmarks are fitted inside this box

local GOLD = Color3.fromRGB(255, 200, 70)

local function part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
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

-- A vertical disc / drum: Roblox cylinders run along X, so stand them up.
local function drum(parent: Instance, diameter: number, height: number, center: Vector3, color: Color3, material: Enum.Material): Part
	return part(parent, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color,
		material, Enum.PartType.Cylinder)
end

local function glow(p: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = p
end

type EmitterOpts = { Rate: number, Life: number, Speed: number, Size: number, Up: boolean?, Spread: number? }

local function emitter(p: BasePart, color: Color3, opts: EmitterOpts)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.5))
	e.LightEmission = 1
	e.Rate = opts.Rate
	e.Lifetime = NumberRange.new(opts.Life * 0.6, opts.Life)
	e.Speed = NumberRange.new(opts.Speed * 0.5, opts.Speed)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, opts.Size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1, 1)
	e.SpreadAngle = Vector2.new(opts.Spread or 25, opts.Spread or 25)
	if opts.Up ~= false then
		e.EmissionDirection = Enum.NormalId.Top
	end
	e.Parent = p
end

local function spin(instance: Instance, speed: number, axis: string?)
	instance:SetAttribute("SpinSpeed", speed)
	instance:SetAttribute("SpinAxis", axis or "Y")
	CollectionService:AddTag(instance, "RiftSpin")
end

local function bob(instance: Instance, amp: number, speed: number, phase: number?)
	instance:SetAttribute("BobAmp", amp)
	instance:SetAttribute("BobSpeed", speed)
	instance:SetAttribute("BobPhase", phase or 0)
	CollectionService:AddTag(instance, "RiftBob")
end

-- Invisible centre part used as an animated model's PrimaryPart.
local function hub(model: Model, at: CFrame)
	local center = part(model, Vector3.one * 0.2, at, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	center.Name = "Hub"
	center.Transparency = 1
	model.PrimaryPart = center
end

-- An approximate ring of `count` blocks in the XZ plane (rotate the model afterwards to tilt it).
local function ring(parent: Instance, radius: number, thickness: number, count: number, color: Color3, material: Enum.Material): Model
	local model = Instance.new("Model")
	model.Name = "Ring"
	local segment = 2 * math.pi * radius / count * 1.08
	for index = 1, count do
		local angle = (index / count) * math.pi * 2
		part(model, Vector3.new(segment, thickness, thickness), CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, radius), color, material)
	end
	hub(model, CFrame.new())
	model.Parent = parent
	return model
end

-- Octagonal deck from two squares turned 45 degrees apart.
local function octagon(parent: Instance, width: number, height: number, y: number, color: Color3, material: Enum.Material)
	local side = width / (1 + math.sqrt(2)) * math.sqrt(2) * 0.92
	for turn = 0, 1 do
		part(parent, Vector3.new(side, height, side), CFrame.new(0, y, 0) * CFrame.Angles(0, turn * math.pi / 4, 0), color, material)
	end
end

local Builders: { [string]: (Model) -> number } = {}

-- 1. Blacksmith: "Molten Obsidian Forge Deck"
Builders.Blacksmith = function(model)
	local basalt = Color3.fromRGB(38, 34, 40)
	local iron = Color3.fromRGB(80, 78, 86)
	local magma = Color3.fromRGB(255, 110, 30)
	octagon(model, 15, 1.6, 0.8, basalt, Enum.Material.Basalt)
	octagon(model, 13.6, 0.4, 1.8, Color3.fromRGB(56, 50, 54), Enum.Material.Slate)
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2 + math.pi / 8
		drum(model, 0.6, 0.3, Vector3.new(math.cos(angle) * 6.6, 1.65, math.sin(angle) * 6.6), iron, Enum.Material.DiamondPlate)
	end
	-- Glowing magma cracks running through the deck.
	local crackRng = Random.new(41)
	for _ = 1, 7 do
		local crack = part(model, Vector3.new(crackRng:NextNumber(2.5, 5), 0.12, 0.25),
			CFrame.new(crackRng:NextNumber(-5, 5), 2.02, crackRng:NextNumber(-3.5, 4)) * CFrame.Angles(0, crackRng:NextNumber(0, math.pi), 0),
			magma, Enum.Material.Neon)
		emitter(crack, magma, { Rate = 3, Life = 1.6, Speed = 3, Size = 0.25 })
	end
	-- Oversized runesmith anvil (front left).
	local ax, az = -7.2, 2.2
	part(model, Vector3.new(2.2, 1.2, 1.8), CFrame.new(ax, 2.6, az), iron, Enum.Material.Metal)
	part(model, Vector3.new(1.2, 1.2, 1.1), CFrame.new(ax, 3.8, az), iron, Enum.Material.Metal)
	part(model, Vector3.new(3.6, 0.9, 1.6), CFrame.new(ax + 0.3, 4.8, az), Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	part(model, Vector3.new(1.4, 0.5, 0.7), CFrame.new(ax + 2.6, 4.9, az), Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	part(model, Vector3.new(2.4, 0.08, 1.2), CFrame.new(ax + 0.3, 5.27, az), magma, Enum.Material.Neon)
	-- Quenching barrel (front right).
	local bx, bz = 7.4, 2.4
	drum(model, 2.6, 2.6, Vector3.new(bx, 3.3, bz), Color3.fromRGB(110, 72, 42), Enum.Material.WoodPlanks)
	drum(model, 2.75, 0.25, Vector3.new(bx, 2.6, bz), iron, Enum.Material.Metal)
	drum(model, 2.75, 0.25, Vector3.new(bx, 4.1, bz), iron, Enum.Material.Metal)
	local water = drum(model, 2.3, 0.1, Vector3.new(bx, 4.55, bz), Color3.fromRGB(90, 190, 255), Enum.Material.Glass)
	water.Transparency = 0.2
	emitter(water, Color3.fromRGB(230, 240, 255), { Rate = 2, Life = 2.2, Speed = 1.5, Size = 0.6 })
	-- Rack of glowing weapons (back right).
	local rx, rz = 6.2, -3.6
	for _, dx in { -1.6, 1.6 } do
		part(model, Vector3.new(0.35, 5, 0.35), CFrame.new(rx + dx, 4.5, rz), Color3.fromRGB(90, 60, 38), Enum.Material.Wood)
	end
	part(model, Vector3.new(3.8, 0.35, 0.35), CFrame.new(rx, 6.6, rz), Color3.fromRGB(90, 60, 38), Enum.Material.Wood)
	for index, color in { Color3.fromRGB(255, 140, 60), Color3.fromRGB(120, 210, 255), Color3.fromRGB(190, 120, 255) } do
		local blade = part(model, Vector3.new(0.3, 3.4, 0.12), CFrame.new(rx - 1.8 + index * 0.9, 4.6, rz + 0.3), color, Enum.Material.Neon)
		glow(blade, color, 5, 0.6)
	end
	local ember = part(model, Vector3.new(4, 0.2, 4), CFrame.new(0, 2.2, 0), magma, Enum.Material.Neon)
	ember.Transparency = 1
	emitter(ember, Color3.fromRGB(255, 160, 60), { Rate = 14, Life = 2.6, Speed = 6, Size = 0.22, Spread = 35 })
	glow(ember, magma, 16, 1.6)
	return 2.05
end

-- 2. Ascension Pedestal: "Celestial Marble Sanctum"
Builders.AscensionPedestal = function(model)
	local marble = Color3.fromRGB(242, 240, 236)
	drum(model, 17, 0.9, Vector3.new(0, 0.45, 0), marble, Enum.Material.Marble)
	drum(model, 17.3, 0.2, Vector3.new(0, 0.9, 0), GOLD, Enum.Material.Metal)
	drum(model, 14, 0.8, Vector3.new(0, 1.3, 0), marble, Enum.Material.Marble)
	drum(model, 14.3, 0.2, Vector3.new(0, 1.7, 0), GOLD, Enum.Material.Metal)
	drum(model, 11, 0.7, Vector3.new(0, 2.05, 0), marble, Enum.Material.Marble)
	-- Floating golden steps leading up the front.
	for index = 1, 3 do
		local step = part(model, Vector3.new(4, 0.35, 1.3), CFrame.new(0, 0.5 + index * 0.65, 6.6 + (3 - index) * 0.9), GOLD, Enum.Material.Metal)
		bob(step, 0.15, 2, index)
	end
	-- 4 ornate spiral pillars.
	for _, corner in { Vector3.new(-7.5, 0, -3.2), Vector3.new(7.5, 0, -3.2), Vector3.new(-6, 0, 3.6), Vector3.new(6, 0, 3.6) } do
		drum(model, 1.3, 11, corner + Vector3.new(0, 6.4, 0), marble, Enum.Material.Marble)
		for band = 0, 4 do
			local twist = part(model, Vector3.new(1.45, 0.3, 0.5), CFrame.new(corner + Vector3.new(0, 2 + band * 2.2, 0)) * CFrame.Angles(0, band * 0.9, 0.35),
				GOLD, Enum.Material.Metal)
			twist.Name = "Spiral"
		end
		drum(model, 1.9, 0.6, corner + Vector3.new(0, 12.1, 0), GOLD, Enum.Material.Metal)
		local orb = part(model, Vector3.one * 0.9, CFrame.new(corner + Vector3.new(0, 13, 0)), Color3.fromRGB(255, 240, 180),
			Enum.Material.Neon, Enum.PartType.Ball)
		glow(orb, GOLD, 8, 0.8)
	end
	-- Giant levitating gyroscope astrolabe overhead.
	local gyro = Instance.new("Model")
	gyro.Name = "Astrolabe"
	gyro.Parent = model
	local center = Vector3.new(0, 19, -1)
	for index, tilt in { 0, math.pi / 2.6, -math.pi / 2.6 } do
		local r = ring(gyro, 4.6 - index * 0.5, 0.3, 18, GOLD, Enum.Material.Metal)
		r:PivotTo(CFrame.new(center) * CFrame.Angles(tilt, index, math.pi / 2))
		spin(r, 0.4 + index * 0.25, if index == 2 then "X" else "Y")
	end
	local core = part(gyro, Vector3.one * 1.4, CFrame.new(center), Color3.fromRGB(255, 245, 200), Enum.Material.Neon, Enum.PartType.Ball)
	glow(core, GOLD, 14, 1.4)
	bob(core, 0.4, 1.1)
	local motes = part(model, Vector3.new(12, 0.2, 7), CFrame.new(0, 2.5, 0), GOLD, Enum.Material.Neon)
	motes.Transparency = 1
	emitter(motes, GOLD, { Rate = 10, Life = 4, Speed = 2.5, Size = 0.25, Spread = 10 })
	return 2.4
end

-- 3. Spark Sanctum: "Astral Constellation Dais"
Builders.SparkSanctum = function(model)
	local indigo = Color3.fromRGB(34, 28, 78)
	local starGold = Color3.fromRGB(255, 215, 90)
	drum(model, 16, 1.2, Vector3.new(0, 0.6, 0), indigo, Enum.Material.Slate)
	drum(model, 16.3, 0.25, Vector3.new(0, 1.15, 0), Color3.fromRGB(90, 70, 190), Enum.Material.Neon)
	drum(model, 12.5, 0.5, Vector3.new(0, 1.45, 0), Color3.fromRGB(22, 18, 54), Enum.Material.Marble)
	-- Constellation: neon-gold lines joining star points on the dais face.
	local stars = { Vector2.new(-5, -2), Vector2.new(-2.5, 3), Vector2.new(1, -1), Vector2.new(4.6, 2.6), Vector2.new(3.4, -3.6), Vector2.new(-1.2, -4.4) }
	for index, point in stars do
		local nextPoint = stars[index % #stars + 1]
		local a = Vector3.new(point.X, 1.73, point.Y)
		local b = Vector3.new(nextPoint.X, 1.73, nextPoint.Y)
		part(model, Vector3.new(0.14, 0.06, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), starGold, Enum.Material.Neon)
		local star = part(model, Vector3.one * 0.45, CFrame.new(a + Vector3.new(0, 0.05, 0)), Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Ball)
		glow(star, starGold, 4, 0.5)
	end
	-- Floating prism crystals.
	for index = 1, 4 do
		local angle = index / 4 * math.pi * 2 + 0.4
		local prism = part(model, Vector3.new(1.1, 2.6, 1.1), CFrame.new(math.cos(angle) * 8.2, 6 + (index % 2) * 2.5, math.sin(angle) * 3.8)
			* CFrame.Angles(0, angle, math.rad(18)), if index % 2 == 0 then Color3.fromRGB(150, 120, 255) else Color3.fromRGB(255, 190, 90),
			Enum.Material.Glass)
		prism.Transparency = 0.15
		glow(prism, prism.Color, 7, 0.9)
		bob(prism, 0.7, 1.4, index * 1.3)
		spin(prism, 0.8, "Y")
	end
	local sparks = part(model, Vector3.new(11, 0.2, 6), CFrame.new(0, 2, 0), starGold, Enum.Material.Neon)
	sparks.Transparency = 1
	emitter(sparks, Color3.fromRGB(255, 120, 150), { Rate = 8, Life = 3, Speed = 3, Size = 0.3, Spread = 20 })
	return 1.7
end

-- 4. Star-Forge: "Amethyst Geode Pedestal"
Builders.StarForge = function(model)
	local rock = Color3.fromRGB(58, 48, 72)
	local amethyst = Color3.fromRGB(175, 95, 255)
	local cyan = Color3.fromRGB(90, 230, 255)
	-- Split crystalline cavern base: two rock halves with a glowing seam between them.
	for side = -1, 1, 2 do
		part(model, Vector3.new(8.6, 2, 9), CFrame.new(side * 4.9, 1, 0) * CFrame.Angles(0, side * 0.05, side * 0.03), rock, Enum.Material.Rock)
	end
	local seam = part(model, Vector3.new(1, 1.6, 8.6), CFrame.new(0, 0.9, 0), amethyst, Enum.Material.Neon)
	glow(seam, amethyst, 12, 1.2)
	part(model, Vector3.new(15, 0.3, 8), CFrame.new(0, 2.05, 0), Color3.fromRGB(74, 62, 92), Enum.Material.Slate)
	-- Giant translucent crystal clusters.
	local rng = Random.new(77)
	for index = 1, 9 do
		local side = if index % 2 == 0 then 1 else -1
		local height = rng:NextNumber(2.5, 6)
		local crystal = part(model, Vector3.new(rng:NextNumber(0.8, 1.6), height, rng:NextNumber(0.8, 1.6)),
			CFrame.new(side * rng:NextNumber(6.5, 9.2), 1.6 + height / 2, rng:NextNumber(-3.8, 3)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), side * rng:NextNumber(0.1, 0.5)),
			if index % 3 == 0 then cyan else amethyst, Enum.Material.Glass)
		crystal.Transparency = 0.25
		if index % 3 == 1 then
			glow(crystal, crystal.Color, 6, 0.8)
		end
	end
	-- Levitating crystalline anvil (front) and orbiting star-shards.
	local anvil = Instance.new("Model")
	anvil.Name = "CrystalAnvil"
	anvil.Parent = model
	part(anvil, Vector3.new(2.6, 0.7, 1.3), CFrame.new(0, 5.4, 5.1), cyan, Enum.Material.Glass).Transparency = 0.2
	part(anvil, Vector3.new(1, 0.8, 0.9), CFrame.new(0, 4.7, 5.1), amethyst, Enum.Material.Glass).Transparency = 0.2
	glow(part(anvil, Vector3.new(1.2, 0.2, 0.6), CFrame.new(0, 5.85, 5.1), Color3.new(1, 1, 1), Enum.Material.Neon), cyan, 8, 1)
	hub(anvil, CFrame.new(0, 5.2, 5.1))
	bob(anvil, 0.4, 1.6)
	local shards = Instance.new("Model")
	shards.Name = "StarShards"
	shards.Parent = model
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		local shard = part(shards, Vector3.new(0.5, 1.1, 0.5), CFrame.new(math.cos(angle) * 8, 9, math.sin(angle) * 4.5) * CFrame.Angles(0.5, angle, 0.5),
			if index % 2 == 0 then cyan else Color3.fromRGB(255, 240, 160), Enum.Material.Neon)
		shard.Name = "Shard"
	end
	hub(shards, CFrame.new(0, 9, 0))
	spin(shards, 0.6, "Y")
	local dust = part(model, Vector3.new(12, 0.2, 6), CFrame.new(0, 2.3, 0), amethyst, Enum.Material.Neon)
	dust.Transparency = 1
	emitter(dust, cyan, { Rate = 7, Life = 3, Speed = 2, Size = 0.22, Spread = 30 })
	return 2.2
end

-- 5. Legion Hall: "Grand Podium of Blades"
Builders.LegionHall = function(model)
	local sandstone = Color3.fromRGB(214, 186, 132)
	local crimson = Color3.fromRGB(170, 28, 44)
	part(model, Vector3.new(19, 1.2, 9.5), CFrame.new(0, 0.6, 0), sandstone, Enum.Material.Sandstone)
	part(model, Vector3.new(15.5, 1, 8), CFrame.new(0, 1.7, -0.4), sandstone:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Sandstone)
	part(model, Vector3.new(19.3, 0.2, 9.8), CFrame.new(0, 1.25, 0), GOLD, Enum.Material.Metal)
	-- Crimson carpet down the front steps.
	part(model, Vector3.new(4.4, 0.08, 9.6), CFrame.new(0, 2.24, 0.3), crimson, Enum.Material.Fabric)
	part(model, Vector3.new(4.4, 1.2, 0.1), CFrame.new(0, 0.6, 4.8), crimson, Enum.Material.Fabric)
	-- Four towering golden war-banners.
	for index, x in { -8.6, -5.2, 5.2, 8.6 } do
		local z = if math.abs(x) > 6 then 2.6 else -3.6
		part(model, Vector3.new(0.35, 13, 0.35), CFrame.new(x, 8, z), Color3.fromRGB(120, 90, 50), Enum.Material.Wood)
		local tip = part(model, Vector3.new(0.8, 0.8, 0.8), CFrame.new(x, 14.8, z) * CFrame.Angles(0, math.pi / 4, math.pi / 4), GOLD, Enum.Material.Metal)
		tip.Name = "Finial"
		local cloth = part(model, Vector3.new(2.6, 6, 0.12), CFrame.new(x + (if x < 0 then 1.4 else -1.4), 10.6, z), crimson, Enum.Material.Fabric)
		part(model, Vector3.new(2.62, 0.4, 0.14), CFrame.new(cloth.Position + Vector3.new(0, -2.8, 0)), GOLD, Enum.Material.Metal)
		part(model, Vector3.new(1.2, 1.2, 0.15), CFrame.new(cloth.Position + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.pi / 4),
			GOLD, Enum.Material.Neon)
		if index == 1 then
			cloth.Name = "Banner"
		end
	end
	-- Crossed giant ancestral weapons behind the podium.
	for side = -1, 1, 2 do
		local blade = Instance.new("Model")
		blade.Name = "AncestralBlade"
		blade.Parent = model
		part(blade, Vector3.new(1.3, 12, 0.3), CFrame.new(0, 6, 0), Color3.fromRGB(200, 206, 220), Enum.Material.Metal)
		part(blade, Vector3.new(4, 0.6, 0.6), CFrame.new(0, -0.3, 0), GOLD, Enum.Material.Metal)
		part(blade, Vector3.new(0.6, 3, 0.6), CFrame.new(0, -2.1, 0), Color3.fromRGB(90, 50, 40), Enum.Material.Wood)
		blade.WorldPivot = CFrame.new()
		blade:PivotTo(CFrame.new(0, 7.5, -4.4) * CFrame.Angles(0, 0, side * math.rad(32)))
	end
	-- Brazier torches.
	for side = -1, 1, 2 do
		local x = side * 6.6
		drum(model, 1.6, 2.4, Vector3.new(x, 3.4, 3.6), Color3.fromRGB(70, 60, 50), Enum.Material.Metal)
		local bowl = drum(model, 2.4, 0.6, Vector3.new(x, 4.9, 3.6), GOLD, Enum.Material.Metal)
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 150, 50)
		fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
		fire.Parent = bowl
		glow(bowl, Color3.fromRGB(255, 160, 70), 14, 1.4)
	end
	return 2.2
end

-- 6. Rift Shrine: "Resonant Obelisk Fountain"
Builders.RiftShrine = function(model)
	local stone = Color3.fromRGB(110, 120, 112)
	local moss = Color3.fromRGB(72, 128, 64)
	local spirit = Color3.fromRGB(90, 255, 230)
	drum(model, 17, 1.4, Vector3.new(0, 0.7, 0), stone, Enum.Material.Cobblestone)
	drum(model, 17.4, 0.35, Vector3.new(0, 1.5, 0), moss, Enum.Material.Grass)
	drum(model, 13, 1.6, Vector3.new(0, 1.6, 0), Color3.fromRGB(96, 104, 98), Enum.Material.Slate)
	local water = drum(model, 12, 0.2, Vector3.new(0, 2.35, 0), spirit, Enum.Material.Neon)
	water.Transparency = 0.25
	glow(water, spirit, 18, 1.6)
	emitter(water, spirit, { Rate = 9, Life = 2.5, Speed = 3, Size = 0.35, Spread = 15 })
	-- Rune stones around the rim.
	for index = 1, 8 do
		local angle = index / 8 * math.pi * 2
		local rune = part(model, Vector3.new(0.9, 0.9, 0.15), CFrame.new(math.cos(angle) * 8.55, 1.0, math.sin(angle) * 8.55) * CFrame.Angles(0, -angle + math.pi / 2, 0),
			spirit, Enum.Material.Neon)
		rune.Name = "Rune"
	end
	-- Three floating obelisk shards.
	for index = 1, 3 do
		local angle = index / 3 * math.pi * 2 + 0.5
		local obelisk = part(model, Vector3.new(1.2, 5, 1.2), CFrame.new(math.cos(angle) * 8.6, 9 + index, math.sin(angle) * 3.8) * CFrame.Angles(0, angle, 0),
			Color3.fromRGB(60, 70, 90), Enum.Material.Slate)
		part(model, Vector3.new(1.25, 0.25, 1.25), obelisk.CFrame * CFrame.new(0, 1, 0), spirit, Enum.Material.Neon)
		bob(obelisk, 0.8, 1.2, index * 2)
		spin(obelisk, 0.5, "Y")
	end
	return 2.4
end

-- Quest Board: "Adventurer's Notice Pavilion"
Builders.QuestBoard = function(model)
	local wood = Color3.fromRGB(132, 92, 56)
	local plank = Color3.fromRGB(176, 128, 80)
	part(model, Vector3.new(18, 1.4, 9), CFrame.new(0, 0.7, 0), Color3.fromRGB(104, 96, 88), Enum.Material.Cobblestone)
	part(model, Vector3.new(16.5, 0.4, 7.8), CFrame.new(0, 1.6, 0), plank, Enum.Material.WoodPlanks)
	for _, x in { -7.6, 7.6 } do
		part(model, Vector3.new(0.6, 9, 0.6), CFrame.new(x, 6.2, 2.8), wood, Enum.Material.Wood)
		local lantern = part(model, Vector3.new(0.9, 1.2, 0.9), CFrame.new(x, 11.2, 2.8), Color3.fromRGB(255, 210, 120), Enum.Material.Neon)
		glow(lantern, Color3.fromRGB(255, 190, 110), 12, 1.2)
		bob(lantern, 0.1, 2.2, x)
	end
	-- Crates, a scroll pile and a pinned bounty poster stand.
	part(model, Vector3.new(2, 2, 2), CFrame.new(-7, 2.8, -2.6) * CFrame.Angles(0, 0.3, 0), plank, Enum.Material.WoodPlanks)
	part(model, Vector3.new(1.4, 1.4, 1.4), CFrame.new(-6.3, 4.5, -2.4) * CFrame.Angles(0, 0.8, 0), plank, Enum.Material.WoodPlanks)
	for index = 1, 4 do
		local scroll = part(model, Vector3.new(1.6, 0.4, 0.4), CFrame.new(6.5, 1.95 + index * 0.4, -2.2 + index * 0.2) * CFrame.Angles(0, index, 0),
			Color3.fromRGB(240, 226, 186), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		scroll.Name = "Scroll"
	end
	local glowSheet = part(model, Vector3.new(10, 0.2, 5), CFrame.new(0, 1.9, 0), Color3.fromRGB(255, 220, 140), Enum.Material.Neon)
	glowSheet.Transparency = 1
	emitter(glowSheet, Color3.fromRGB(255, 230, 160), { Rate = 4, Life = 3.5, Speed = 1.5, Size = 0.2 })
	return 1.8
end

-- Hall of Champions: "Golden Trophy Plinth"
Builders.HallOfChampions = function(model)
	local marble = Color3.fromRGB(236, 232, 222)
	local velvet = Color3.fromRGB(150, 20, 40)
	part(model, Vector3.new(19, 0.8, 9.5), CFrame.new(0, 0.4, 0), marble, Enum.Material.Marble)
	part(model, Vector3.new(16, 0.8, 8), CFrame.new(0, 1.2, -0.3), marble, Enum.Material.Marble)
	part(model, Vector3.new(13, 0.6, 6.6), CFrame.new(0, 1.9, -0.5), GOLD, Enum.Material.Metal)
	-- Velvet rope posts along the front.
	for index = -2, 2 do
		local x = index * 3.8
		drum(model, 0.5, 2.2, Vector3.new(x, 2.1, 4.3), GOLD, Enum.Material.Metal)
		local topper = part(model, Vector3.one * 0.6, CFrame.new(x, 3.3, 4.3), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
		topper.Name = "Topper"
		if index < 2 then
			part(model, Vector3.new(3.8, 0.25, 0.25), CFrame.new(x + 1.9, 2.75, 4.3), velvet, Enum.Material.Fabric)
		end
	end
	-- Champion statues on either side.
	for side = -1, 1, 2 do
		local x = side * 7.8
		part(model, Vector3.new(2.2, 2, 2.2), CFrame.new(x, 2.2, -2.4), marble, Enum.Material.Marble)
		part(model, Vector3.new(1.4, 4, 1), CFrame.new(x, 5.2, -2.4), Color3.fromRGB(200, 196, 186), Enum.Material.Marble)
		part(model, Vector3.one * 1.2, CFrame.new(x, 7.8, -2.4), Color3.fromRGB(200, 196, 186), Enum.Material.Marble, Enum.PartType.Ball)
		local laurel = part(model, Vector3.new(1.6, 0.3, 1.6), CFrame.new(x, 8.4, -2.4), GOLD, Enum.Material.Neon)
		glow(laurel, GOLD, 6, 0.7)
		part(model, Vector3.new(0.3, 5, 0.3), CFrame.new(x + side * 1, 6, -2.4) * CFrame.Angles(0, 0, side * 0.3), Color3.fromRGB(200, 206, 220), Enum.Material.Metal)
	end
	local confetti = part(model, Vector3.new(12, 0.2, 6), CFrame.new(0, 2.3, 0), GOLD, Enum.Material.Neon)
	confetti.Transparency = 1
	emitter(confetti, GOLD, { Rate = 6, Life = 3, Speed = 3, Size = 0.25 })
	return 2.2
end

-- Plain stone dais for anything without a bespoke one.
local function defaultDais(model: Model): number
	drum(model, 16, 1.6, Vector3.new(0, 0.8, 0), Color3.fromRGB(120, 116, 128), Enum.Material.Slate)
	drum(model, 16.3, 0.25, Vector3.new(0, 1.55, 0), GOLD, Enum.Material.Metal)
	return 1.6
end

-- Builds the dais for `stationKey` into `parent` (a folder-like Model at the origin). Returns the landmark floor height.
function LandmarkBuilder.BuildDais(stationKey: string, parent: Model): number
	local dais = Instance.new("Model")
	dais.Name = "Dais"
	dais.Parent = parent
	local builder = Builders[stationKey]
	return if builder then builder(dais) else defaultDais(dais)
end

-- Rift Shrine pact altar for Treasure rooms (a landmark on its own obsidian dais). Built around the origin with its
-- bottom-centre at (0, 0, 0); returns the altar model and the part to hang its prompt on.
function LandmarkBuilder.BuildPactAltar(name: string, icon: string, accent: Color3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "PactAltar"
	local obsidian = Color3.fromRGB(28, 22, 34)
	local blood = Color3.fromRGB(220, 40, 70)
	drum(model, 12, 1.2, Vector3.new(0, 0.6, 0), obsidian, Enum.Material.Basalt)
	drum(model, 12.3, 0.2, Vector3.new(0, 1.15, 0), blood, Enum.Material.Neon)
	part(model, Vector3.new(5, 1.6, 4), CFrame.new(0, 2, -0.5), Color3.fromRGB(46, 38, 54), Enum.Material.Slate)
	local obelisk = part(model, Vector3.new(2.4, 9, 2.4), CFrame.new(0, 7.3, -0.8) * CFrame.Angles(0, math.pi / 4, 0), obsidian, Enum.Material.Basalt)
	part(model, Vector3.new(2.5, 0.35, 2.5), obelisk.CFrame * CFrame.new(0, 2.5, 0), accent, Enum.Material.Neon)
	part(model, Vector3.new(2.5, 0.35, 2.5), obelisk.CFrame * CFrame.new(0, -1.5, 0), accent, Enum.Material.Neon)
	-- Candles.
	for index = 1, 6 do
		local angle = index / 6 * math.pi * 2
		local candle = part(model, Vector3.new(0.35, 0.9, 0.35), CFrame.new(math.cos(angle) * 4.6, 1.65, math.sin(angle) * 3.2),
			Color3.fromRGB(240, 230, 210), Enum.Material.SmoothPlastic)
		local flame = part(model, Vector3.new(0.25, 0.4, 0.25), candle.CFrame * CFrame.new(0, 0.6, 0), Color3.fromRGB(255, 170, 60), Enum.Material.Neon)
		flame.Name = "Flame"
	end
	-- Floating pact sigil: the curse's icon on a spinning, bobbing plate.
	local sigil = part(model, Vector3.new(3.4, 3.4, 0.2), CFrame.new(0, 14.2, -0.8) * CFrame.Angles(0, 0, math.pi / 4), accent, Enum.Material.Neon)
	sigil.Transparency = 0.2
	glow(sigil, accent, 18, 2)
	bob(sigil, 0.6, 1.5)
	spin(sigil, 0.7, "Y")
	emitter(sigil, blood, { Rate = 10, Life = 1.8, Speed = 2, Size = 0.3, Spread = 180 })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(70, 70)
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = sigil
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = icon
	label.Parent = gui
	local anchor = part(model, Vector3.new(2, 2, 2), CFrame.new(0, 5, 0), accent, Enum.Material.SmoothPlastic)
	anchor.Name = "PromptAnchor"
	anchor.Transparency = 1
	model.PrimaryPart = anchor
	model:SetAttribute("WaypointName", name)
	model:SetAttribute("WaypointIcon", icon)
	model:SetAttribute("WaypointColor", accent)
	CollectionService:AddTag(model, "RiftWaypoint")
	return model, anchor
end

return LandmarkBuilder
