--!strict
-- ServerScriptService/Server/Services/WeaponHoldService.luau
-- Welds the equipped weapon into every character's right hand, in Haven Outpost and in runs (game.md Section 0.1
-- rule 4 / Step SP-2). The server builds the held model so every client sees it.
--
-- The prefab comes from ReplicatedStorage.Assets.Weapons.<WeaponId> (or a procedural multi-part fallback). Its
-- longest side is scaled to WeaponConfig Hold.Length and laid along the hand's forward axis, tilted by Hold.Tilt;
-- its thinnest side faces the hand's X axis so blades show their flat to the side-on camera. The hand closes
-- Hold.Grip of the way along the long side. Paragon 25 / 50 / 100 weapons get a glowing aura (Section 6.1).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

type WeaponInfo = WeaponConfig.WeaponInfo

local WeaponHoldService = {}

local HELD_NAME = "HeldWeapon"
local DEFAULT_TILT = -30 -- tip forward and a little down: the classic ready stance seen from the side
local AURA_TIERS = { { Rank = 100, Rate = 40, Size = 0.5 }, { Rank = 50, Rate = 22, Size = 0.4 }, { Rank = 25, Rate = 12, Size = 0.3 } }

local heldKey: { [Player]: string } = {} -- weapon id + aura tier currently welded, so refreshes are cheap

local function getHand(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand and hand:IsA("BasePart") then
		return hand
	end
	return nil
end

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material,
	shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	if shape then
		part.Shape = shape
	end
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

-- A recognisable multi-part stand-in, built pointing up +Y with its grip at the bottom (used without a prefab).
local function buildFallback(info: WeaponInfo): Model
	local model = Instance.new("Model")
	model.Name = info.Id
	local accent = info.Accent
	local steel = Color3.fromRGB(205, 212, 226)
	local wood = Color3.fromRGB(110, 74, 46)
	local id = info.Id
	if id == "Bow" then
		newPart(model, "Grip", Vector3.new(0.35, 0.9, 0.35), CFrame.new(0, 0, 0), wood, Enum.Material.Wood)
		for side = -1, 1, 2 do
			newPart(model, "Limb", Vector3.new(0.25, 1.9, 0.3), CFrame.new(0.35, side * 1.25, 0) * CFrame.Angles(0, 0, side * 0.35),
				accent, Enum.Material.SmoothPlastic)
		end
		newPart(model, "String", Vector3.new(0.05, 4, 0.05), CFrame.new(0.8, 0, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
	elseif id == "Hammer" or id == "Greatsword" or id == "Daggers" then
		newPart(model, "Handle", Vector3.new(0.3, 1.4, 0.3), CFrame.new(0, 0.7, 0), wood, Enum.Material.Wood)
		if id == "Hammer" then
			newPart(model, "Head", Vector3.new(1.6, 1.0, 1.0), CFrame.new(0, 1.8, 0), steel, Enum.Material.Metal)
			newPart(model, "Band", Vector3.new(1.7, 0.25, 1.1), CFrame.new(0, 1.8, 0), accent, Enum.Material.Neon)
		else
			newPart(model, "Guard", Vector3.new(1.2, 0.2, 0.35), CFrame.new(0, 1.45, 0), accent, Enum.Material.Metal)
			newPart(model, "Blade", Vector3.new(0.5, 3, 0.12), CFrame.new(0, 3.0, 0), steel, Enum.Material.Metal)
			newPart(model, "Edge", Vector3.new(0.12, 3, 0.14), CFrame.new(0.25, 3.0, 0), accent, Enum.Material.Neon)
		end
	elseif id == "Staff" or id == "TrickCards" then
		newPart(model, "Shaft", Vector3.new(0.25, 4, 0.25), CFrame.new(0, 2, 0), wood, Enum.Material.Wood)
		newPart(model, "Orb", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 4.3, 0), accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif id == "SummoningBell" then
		newPart(model, "Handle", Vector3.new(0.25, 0.8, 0.25), CFrame.new(0, 1.4, 0), wood, Enum.Material.Wood)
		newPart(model, "Bell", Vector3.new(1.0, 1.0, 1.0), CFrame.new(0, 0.5, 0), accent, Enum.Material.Metal, Enum.PartType.Ball)
	else -- Gauntlets
		newPart(model, "Fist", Vector3.new(0.9, 0.9, 1.2), CFrame.new(0, 0, 0), accent, Enum.Material.Metal)
		newPart(model, "Knuckles", Vector3.new(0.95, 0.3, 0.4), CFrame.new(0, 0.2, -0.5), steel, Enum.Material.Neon)
	end
	return model
end

local function getPrefab(info: WeaponInfo): Model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Weapons")
	local prefab = folder and folder:FindFirstChild(info.Id)
	if prefab and prefab:IsA("Model") then
		local model = prefab:Clone()
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") or descendant:IsA("ClickDetector") or descendant:IsA("Sound") then
				descendant:Destroy()
			end
		end
		return model
	end
	return buildFallback(info)
end

-- Unit vector of a bounding-box local axis (1 = X, 2 = Y, 3 = Z).
local function axisVector(index: number): Vector3
	return if index == 1 then Vector3.xAxis elseif index == 2 then Vector3.yAxis else Vector3.zAxis
end

local function addAura(model: Model, info: WeaponInfo, paragon: number)
	local tier = nil
	for _, candidate in AURA_TIERS do
		if paragon >= candidate.Rank then
			tier = candidate
			break
		end
	end
	if not tier then
		return
	end
	local biggest: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and (biggest == nil or descendant.Size.Magnitude > biggest.Size.Magnitude) then
			biggest = descendant
		end
	end
	if not biggest then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ParagonAura"
	emitter.Color = ColorSequence.new(info.Accent, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Rate = tier.Rate
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(tier.Size, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Parent = biggest
	local light = Instance.new("PointLight")
	light.Color = info.Accent
	light.Range = 6
	light.Brightness = 1.2
	light.Parent = biggest
end

-- Builds the held model and welds it to `hand`.
local function attach(character: Model, hand: BasePart, info: WeaponInfo, paragon: number)
	local model = getPrefab(info)
	model.Name = HELD_NAME
	model:SetAttribute("WeaponId", info.Id)

	local _, rawSize = model:GetBoundingBox()
	local longest = math.max(rawSize.X, rawSize.Y, rawSize.Z)
	if longest > 0.01 then
		model:ScaleTo(model:GetScale() * (info.Hold.Length / longest))
	end
	local boxCFrame, size = model:GetBoundingBox()

	local dims = { size.X, size.Y, size.Z }
	local longIndex, thinIndex = 1, 1
	for index = 2, 3 do
		if dims[index] > dims[longIndex] then
			longIndex = index
		end
		if dims[index] < dims[thinIndex] then
			thinIndex = index
		end
	end
	if thinIndex == longIndex then
		thinIndex = if longIndex == 1 then 3 else 1
	end
	local longAxis = axisVector(longIndex) * (if info.Hold.Flip then -1 else 1)
	local thinAxis = axisVector(thinIndex)

	-- Prefab basis (long, thin, cross) -> hand basis (tip direction, hand X, cross).
	local tilt = math.rad(info.Hold.Tilt or DEFAULT_TILT)
	local tipDir = Vector3.new(0, math.sin(tilt), -math.cos(tilt))
	local prefabBasis = CFrame.fromMatrix(Vector3.zero, longAxis, thinAxis, longAxis:Cross(thinAxis))
	local handBasis = CFrame.fromMatrix(Vector3.zero, tipDir, Vector3.xAxis, tipDir:Cross(Vector3.xAxis))
	local rotation = handBasis * prefabBasis:Inverse()

	local gripLocal = longAxis * ((info.Hold.Grip - 0.5) * dims[longIndex])
	local gripAttachment = hand:FindFirstChild("RightGripAttachment")
	local palm = if gripAttachment and gripAttachment:IsA("Attachment") then gripAttachment.CFrame else CFrame.new(0, -hand.Size.Y / 2, 0)
	-- World (prefab) space -> bounding-box space -> grip at the origin -> hand orientation -> palm position.
	local toHand = CFrame.new(palm.Position) * rotation * CFrame.new(-gripLocal) * boxCFrame:Inverse()

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = false
			descendant.CFrame = hand.CFrame * toHand * descendant.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hand
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
	model.PrimaryPart = nil
	addAura(model, info, paragon)
	model.Parent = character
end

-- (Re)welds the player's equipped weapon if it changed. Safe to call often.
function WeaponHoldService.Refresh(player: Player)
	local character = player.Character
	local profile = PlayerDataService.Get(player)
	if not character or not profile then
		return
	end
	local hand = getHand(character)
	local info = WeaponConfig.Weapons[profile.EquippedWeapon]
	if not hand or not info then
		return
	end
	local mastery = profile.WeaponMastery[info.Id]
	local paragon = if mastery then mastery.ParagonRank else 0
	local key = ("%s:%d"):format(info.Id, if paragon >= 100 then 3 elseif paragon >= 50 then 2 elseif paragon >= 25 then 1 else 0)
	local existing = character:FindFirstChild(HELD_NAME)
	if existing and heldKey[player] == key then
		return
	end
	if existing then
		existing:Destroy()
	end
	heldKey[player] = key
	local ok, err = pcall(function(): any
		attach(character, hand, info, paragon)
		return nil
	end)
	if not ok then
		warn("[WeaponHoldService] could not attach " .. info.Id .. ": " .. tostring(err))
	end
end

local function onCharacterAdded(player: Player, character: Model)
	heldKey[player] = nil
	-- R15 limbs arrive with the appearance; wait for the hand, then for the profile.
	local hand = character:WaitForChild("RightHand", 10) or character:FindFirstChild("Right Arm")
	if not hand or player.Character ~= character then
		return
	end
	if not player:HasAppearanceLoaded() then
		player.CharacterAppearanceLoaded:Wait()
	end
	PlayerDataService.Wait(player)
	if player.Character == character then
		WeaponHoldService.Refresh(player)
	end
end

function WeaponHoldService.Init()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		heldKey[player] = nil
	end)
end

return WeaponHoldService
