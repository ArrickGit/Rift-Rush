--!strict
-- StarterPlayerScripts/Client/Controllers/AmbientController.luau
-- Local-only ambient animation, so the server never streams per-frame CFrames (game.md Section 33):
--   * "RiftSpin" (SpinSpeed, SpinAxis) / "RiftBob" (BobAmp, BobSpeed, BobPhase) parts or models on the station
--     daises and floating islands; "RiftDrift" (DriftSpeed, DriftMin, DriftMax) clouds sliding across the vista.
--   * "RiftAcidFlood": the Jump Quest acid. The server keeps an invisible marker whose SurfaceY attribute is the
--     authoritative height; here it becomes a 3-layer flood: an undulating neon crest with scrolling foam, a deep
--     emerald body glowing upward, and bubbles that swell and pop into splash rings, with toxic fumes rising.
-- Anything farther than CULL_DISTANCE from the camera is left alone.
--
-- Animation is geometry-based: each part's own CFrame is captured when the tag is seen and the whole set is moved
-- with BulkMoveTo around its bounding-box centre. Model pivots are never trusted, because a model's PrimaryPart
-- reference can replicate after its tag (GetPivot would then report the world origin).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

type Animated = {
	Instance: Instance,
	Parts: { BasePart },
	Bases: { CFrame },
	Center: Vector3,
	Spin: number,
	Axis: string,
	BobAmp: number,
	BobSpeed: number,
	BobPhase: number,
	Drift: number,
	DriftMin: number,
	DriftMax: number,
}

type Bubble = { Part: Part, Ring: Part, Born: number, Life: number, X: number, Z: number, Size: number, Popped: boolean }

type Flood = {
	Marker: BasePart,
	Folder: Folder,
	Body: Part,
	Crest: { Part },
	Foam: { Part },
	Fumes: Part,
	Bubbles: { Bubble },
	Width: number,
	Depth: number,
	CenterX: number,
	Bottom: number,
	Surface: number,
	NextBubble: number,
}

local AmbientController = {}

local CULL_DISTANCE = 320
local CREST_SEGMENTS = 14
local FOAM_STRIPS = 6
local MAX_BUBBLES = 16
local CREST_COLOR = Color3.fromRGB(115, 255, 45)
local BODY_COLOR = Color3.fromRGB(28, 125, 42)
local FOAM_COLOR = Color3.fromRGB(215, 255, 170)

local animated: { [Instance]: Animated } = {}
local floods: { [BasePart]: Flood } = {}
local rng = Random.new()

local function number(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

local function register(instance: Instance)
	if animated[instance] or not instance:IsDescendantOf(Workspace) then
		return
	end
	local parts: { BasePart } = {}
	local center: Vector3
	if instance:IsA("BasePart") then
		parts = { instance }
		center = instance.Position
	elseif instance:IsA("Model") then
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		if #parts == 0 then
			return
		end
		center = instance:GetBoundingBox().Position
	else
		return
	end
	local bases: { CFrame } = {}
	for index, part in parts do
		bases[index] = part.CFrame
	end
	animated[instance] = {
		Instance = instance,
		Parts = parts,
		Bases = bases,
		Center = center,
		Spin = if CollectionService:HasTag(instance, "RiftSpin") then number(instance, "SpinSpeed", 0.5) else 0,
		Axis = (instance:GetAttribute("SpinAxis") or "Y") :: any,
		BobAmp = if CollectionService:HasTag(instance, "RiftBob") then number(instance, "BobAmp", 0.5) else 0,
		BobSpeed = number(instance, "BobSpeed", 1),
		BobPhase = number(instance, "BobPhase", 0),
		Drift = if CollectionService:HasTag(instance, "RiftDrift") then number(instance, "DriftSpeed", 2) else 0,
		DriftMin = number(instance, "DriftMin", center.X - 100),
		DriftMax = number(instance, "DriftMax", center.X + 100),
	}
end

-- Tags can arrive a moment before the rest of a model's parts; register once it has settled.
local function registerSoon(instance: Instance)
	task.delay(0.5, register, instance)
end

local function unregister(instance: Instance)
	if instance.Parent == nil or not (CollectionService:HasTag(instance, "RiftSpin") or CollectionService:HasTag(instance, "RiftBob")
		or CollectionService:HasTag(instance, "RiftDrift")) then
		animated[instance] = nil
	end
end

local function stepAnimated(now: number, cameraPos: Vector3)
	local moveParts: { BasePart } = {}
	local moveFrames: { CFrame } = {}
	for instance, entry in animated do
		if instance.Parent == nil then
			animated[instance] = nil
			continue
		end
		local center = entry.Center
		local offset = Vector3.zero
		if entry.Drift ~= 0 then
			local span = math.max(1, entry.DriftMax - entry.DriftMin)
			local x = entry.DriftMin + ((center.X - entry.DriftMin + now * entry.Drift) % span)
			offset = Vector3.new(x - center.X, 0, 0)
		end
		if (center + offset - cameraPos).Magnitude > CULL_DISTANCE then
			continue
		end
		if entry.BobAmp ~= 0 then
			offset += Vector3.new(0, math.sin(now * entry.BobSpeed + entry.BobPhase) * entry.BobAmp, 0)
		end
		local turn = CFrame.identity
		if entry.Spin ~= 0 then
			local angle = now * entry.Spin
			turn = if entry.Axis == "X" then CFrame.Angles(angle, 0, 0)
				elseif entry.Axis == "Z" then CFrame.Angles(0, 0, angle)
				else CFrame.Angles(0, angle, 0)
		end
		-- Rotate about the centre in world space, then translate.
		local transform = CFrame.new(center + offset) * turn * CFrame.new(-center)
		for index, part in entry.Parts do
			table.insert(moveParts, part)
			table.insert(moveFrames, transform * entry.Bases[index])
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Acid flood -------------------------------------------------------------------------------------------------

local function localPart(parent: Instance, size: Vector3, color: Color3, material: Enum.Material, transparency: number, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function createFlood(marker: BasePart)
	if floods[marker] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "AcidFlood"
	folder.Parent = Workspace.CurrentCamera or Workspace
	local width, depth = marker.Size.X, marker.Size.Z
	local body = localPart(folder, Vector3.new(width, 1, depth), BODY_COLOR, Enum.Material.Glass, 0.15)
	local glowLight = Instance.new("SurfaceLight")
	glowLight.Face = Enum.NormalId.Top
	glowLight.Color = CREST_COLOR
	glowLight.Brightness = 2.2
	glowLight.Range = 16
	glowLight.Angle = 120
	glowLight.Parent = body

	local crest: { Part } = {}
	local segment = width / CREST_SEGMENTS
	for _ = 1, CREST_SEGMENTS do
		table.insert(crest, localPart(folder, Vector3.new(segment + 0.05, 0.7, depth + 0.6), CREST_COLOR, Enum.Material.Neon, 0.28))
	end
	local foam: { Part } = {}
	for _ = 1, FOAM_STRIPS do
		table.insert(foam, localPart(folder, Vector3.new(rng:NextNumber(4, 9), 0.12, rng:NextNumber(0.6, 1.4)), FOAM_COLOR, Enum.Material.Neon, 0.35))
	end
	local fumes = localPart(folder, Vector3.new(width, 0.2, depth), CREST_COLOR, Enum.Material.Neon, 1)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 255, 90), Color3.fromRGB(170, 80, 220))
	emitter.LightEmission = 0.4
	emitter.Rate = 14
	emitter.Lifetime = NumberRange.new(1.4, 2.4)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Parent = fumes

	local surface = number(marker, "SurfaceY", marker.Position.Y)
	floods[marker] = {
		Marker = marker, Folder = folder, Body = body, Crest = crest, Foam = foam, Fumes = fumes, Bubbles = {},
		Width = width, Depth = depth, CenterX = marker.Position.X, Bottom = marker.Position.Y - 3, Surface = surface,
		NextBubble = 0,
	}
end

local function destroyFlood(marker: BasePart)
	local flood = floods[marker]
	if flood then
		flood.Folder:Destroy()
		floods[marker] = nil
	end
end

local function stepFlood(flood: Flood, now: number, dt: number)
	local target = number(flood.Marker, "SurfaceY", flood.Surface) + number(flood.Marker, "RiseSpeed", 0) * 0.1
	flood.Surface += (target - flood.Surface) * math.min(1, dt * 5)
	local surface = flood.Surface
	local left = flood.CenterX - flood.Width / 2

	local height = math.max(0.2, surface - flood.Bottom)
	flood.Body.Size = Vector3.new(flood.Width, height, flood.Depth)
	flood.Body.CFrame = CFrame.new(flood.CenterX, flood.Bottom + height / 2 - 0.3, 0)
	flood.Fumes.CFrame = CFrame.new(flood.CenterX, surface + 0.4, 0)

	-- Undulating crest: each segment rides its own phase of a travelling wave.
	local segment = flood.Width / CREST_SEGMENTS
	for index, part in flood.Crest do
		local wave = math.sin(now * 2.4 + index * 0.75) * 0.28 + math.sin(now * 1.3 - index * 0.4) * 0.12
		part.CFrame = CFrame.new(left + (index - 0.5) * segment, surface + wave, 0)
		part.Transparency = 0.24 + 0.08 * math.sin(now * 3 + index)
	end
	-- Scrolling foam strips that wrap across the surface.
	for index, part in flood.Foam do
		local speed = 3 + index * 0.7
		local x = left + ((index * 23 + now * speed) % flood.Width)
		local z = ((index * 0.37) % 1 - 0.5) * (flood.Depth - 2)
		part.CFrame = CFrame.new(x, surface + 0.38 + math.sin(now * 2.4 + x * 0.1) * 0.25, z)
	end

	-- Bubbles swell, pop, and leave a splash ring.
	if now >= flood.NextBubble and #flood.Bubbles < MAX_BUBBLES then
		flood.NextBubble = now + rng:NextNumber(0.08, 0.22)
		local bubble = localPart(flood.Folder, Vector3.one * 0.3, CREST_COLOR:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.Neon, 0.2,
			Enum.PartType.Ball)
		local ring = localPart(flood.Folder, Vector3.new(0.1, 0.1, 0.1), FOAM_COLOR, Enum.Material.Neon, 1, Enum.PartType.Cylinder)
		table.insert(flood.Bubbles, {
			Part = bubble, Ring = ring, Born = now, Life = rng:NextNumber(0.5, 0.9),
			X = left + rng:NextNumber(1, flood.Width - 1), Z = rng:NextNumber(-flood.Depth / 2 + 1, flood.Depth / 2 - 0.5),
			Size = rng:NextNumber(0.7, 1.6), Popped = false,
		})
	end
	for index = #flood.Bubbles, 1, -1 do
		local bubble = flood.Bubbles[index]
		local age = now - bubble.Born
		if age < bubble.Life then
			local grow = age / bubble.Life
			local size = 0.3 + (bubble.Size - 0.3) * grow
			bubble.Part.Size = Vector3.one * size
			bubble.Part.CFrame = CFrame.new(bubble.X, surface + size * 0.3, bubble.Z)
		elseif age < bubble.Life + 0.3 then
			if not bubble.Popped then
				bubble.Popped = true
				bubble.Part.Transparency = 1
			end
			local spread = (age - bubble.Life) / 0.3
			local diameter = bubble.Size * (1 + 2.2 * spread)
			bubble.Ring.Size = Vector3.new(0.08, diameter, diameter)
			bubble.Ring.CFrame = CFrame.new(bubble.X, surface + 0.4, bubble.Z) * CFrame.Angles(0, 0, math.pi / 2)
			bubble.Ring.Transparency = 0.3 + 0.7 * spread
		else
			bubble.Part:Destroy()
			bubble.Ring:Destroy()
			table.remove(flood.Bubbles, index)
		end
	end
end

function AmbientController.Init()
	for _, tag in { "RiftSpin", "RiftBob", "RiftDrift" } do
		for _, instance in CollectionService:GetTagged(tag) do
			registerSoon(instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(registerSoon)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unregister)
	end
	local function addFlood(instance: Instance)
		if instance:IsA("BasePart") then
			createFlood(instance)
		end
	end
	for _, instance in CollectionService:GetTagged("RiftAcidFlood") do
		addFlood(instance)
	end
	CollectionService:GetInstanceAddedSignal("RiftAcidFlood"):Connect(addFlood)
	CollectionService:GetInstanceRemovedSignal("RiftAcidFlood"):Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			destroyFlood(instance)
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		stepAnimated(now, camera.CFrame.Position)
		for marker, flood in floods do
			if marker.Parent == nil then
				destroyFlood(marker)
			else
				stepFlood(flood, now, dt)
			end
		end
	end)
end

return AmbientController
