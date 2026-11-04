--!strict
-- StarterPlayerScripts/Client/Controllers/LootOrbController.luau
-- Physical loot (game.md 3.5). The server credits the Dust first; this controller only makes it feel physical:
--   * DustOrbs{Pos,Amount,Count} (CombatFx, sent to the player who earned it): glowing Rift Dust crystals burst out of
--     the kill / chest / Training Sanctuary dummy, bounce for 0.25s, then wait until the player is inside the pickup radius and zoom into their
--     chest. Base radius 18 studs; the Vacuum Aura Ascension node (AS_T1_03) adds +15 / +35 / whole room. Orbs nobody
--     walks to fly in on their own after a few seconds. Each pickup plays a tick whose pitch climbs through a combo
--     and bumps the "+N Rift Dust" ticker under the run banner.
--   * LootBeam{Pos,Title,Gold,Owner} (sent to the whole party): a tall neon light pillar (purple, or gold for Room 10
--     relics) with a floating title and a chime, for Boss Cores and Relics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local localPlayer = Players.LocalPlayer

local NODE_VACUUM = "AS_T1_03"
local BASE_RADIUS = 18
local VACUUM_RADIUS: { number } = { 33, 53, 1000 } -- by Vacuum Aura level; Lv3 = the whole room
local BOUNCE_SECONDS = 0.25
local AUTO_COLLECT_SECONDS = 6 -- orbs outside the radius come to you anyway after this long
local MAX_ORBS = 60
local ORB_COLOR = Color3.fromRGB(60, 190, 255)
local ORB_CORE = Color3.fromRGB(215, 245, 255)
local COMBO_WINDOW = 0.7
local TICKER_HOLD = 1.6
local BEAM_SECONDS = 6
local BEAM_HEIGHT = 70
local BEAM_COLORS = { Purple = Color3.fromRGB(160, 70, 255), Gold = Color3.fromRGB(255, 185, 30) }

type Orb = {
	Part: Part,
	Pos: Vector3,
	Vel: Vector3,
	Born: number,
	Value: number,
	Homing: boolean,
}

local LootOrbController = {}

local folder: Folder
local orbs: { Orb } = {}
local vacuumLevel = 0
local comboCount = 0
local lastPickup = 0
local tickerTotal = 0
local tickerFrame: Frame
local tickerLabel: TextLabel
local tickerScale: UIScale
local beams: { { Pos: Vector3, Expires: number } } = {}
local rng = Random.new()

local function pickupRadius(): number
	return if vacuumLevel > 0 then VACUUM_RADIUS[math.min(vacuumLevel, #VACUUM_RADIUS)] else BASE_RADIUS
end

local function localRoot(): BasePart?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function sprite(texture: string, pos: Vector3, color: Color3, size: number, life: number, count: number, speed: number)
	local id = AssetRegistry.VfxTextures[texture]
	if not id or id == "" then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(pos)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = id
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(life * 0.7, life)
	emitter.Speed = NumberRange.new(0, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.25) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = anchor
	anchor.Parent = folder
	emitter:Emit(count)
	task.delay(life + 0.1, function()
		anchor:Destroy()
	end)
end

-- Ticker ------------------------------------------------------------------------------------------------------

local function buildTicker()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RiftDustTicker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 12
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 214) -- just under the run banner's "At risk" pouch line
	frame.Size = UDim2.fromOffset(190, 44)
	frame.BackgroundColor3 = Color3.fromRGB(18, 24, 40)
	frame.BackgroundTransparency = 0.25
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORB_COLOR
	stroke.Thickness = 2
	stroke.Parent = frame
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(8, 6)
	icon.Size = UDim2.fromOffset(32, 32)
	icon.Image = AssetRegistry.Icons.Cur_Dust or ""
	icon.ImageColor3 = ORB_COLOR
	icon.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(46, 0)
	label.Size = UDim2.new(1, -54, 1, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 22
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = ORB_CORE
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	tickerFrame, tickerLabel, tickerScale = frame, label, scale
end

local function bumpTicker(value: number)
	tickerTotal += value
	tickerLabel.Text = ("+%d Rift Dust"):format(tickerTotal)
	tickerFrame.Visible = true
	tickerScale.Scale = 1.18
end

-- Orbs --------------------------------------------------------------------------------------------------------

local function removeOrb(index: number)
	local orb = orbs[index]
	orb.Part:Destroy()
	orbs[index] = orbs[#orbs]
	orbs[#orbs] = nil
end

local function collect(orb: Orb)
	local now = os.clock()
	comboCount = if now - lastPickup <= COMBO_WINDOW then comboCount + 1 else 0
	lastPickup = now
	Sfx.Play("UI_ProgressTick", 0.45, math.min(2, 1 + comboCount * 0.06))
	sprite("star_04", orb.Pos, ORB_COLOR, 1.2, 0.25, 2, 6)
	bumpTicker(orb.Value)
end

local function spawnOrbs(pos: Vector3, amount: number, count: number)
	count = math.clamp(math.floor(count), 1, 8)
	if amount <= 0 then
		return
	end
	-- Split the Dust across the orbs (the last one takes the remainder) so the ticker adds up exactly.
	local each = amount // count
	local spare = amount - each * count
	sprite("flare_01", pos, ORB_COLOR, 4, 0.3, 1, 0)
	for index = 1, count do
		if #orbs >= MAX_ORBS then
			removeOrb(1) -- the oldest one lands early
		end
		local part = Instance.new("Part")
		part.Name = "RiftDustOrb"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = ORB_COLOR
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		part.CFrame = CFrame.new(pos)
		local mesh = Instance.new("SpecialMesh") -- stretched diamond crystal
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1.1, 1.9, 1.1)
		mesh.Parent = part
		local light = Instance.new("PointLight")
		light.Color = ORB_COLOR
		light.Range = 5
		light.Brightness = 1.2
		light.Parent = part
		part.Parent = folder
		table.insert(orbs, {
			Part = part,
			Pos = pos,
			Vel = Vector3.new(rng:NextNumber(-11, 11), rng:NextNumber(14, 24), rng:NextNumber(-1.5, 1.5)),
			Born = os.clock() + (index - 1) * 0.02,
			Value = each + (if index == count then spare else 0),
			Homing = false,
		})
	end
end

local function stepOrbs(dt: number, now: number)
	local root = localRoot()
	local radius = pickupRadius()
	for index = #orbs, 1, -1 do
		local orb = orbs[index]
		local age = now - orb.Born
		if orb.Homing and root then
			local target = root.Position + Vector3.new(0, 0.5, 0)
			local offset = target - orb.Pos
			local distance = offset.Magnitude
			if distance < 1.4 then
				collect(orb)
				removeOrb(index)
				continue
			end
			-- Accelerating magnet pull, with a little of the old velocity left for a curved swoop.
			local speed = math.max(orb.Vel.Magnitude, 20) + 140 * dt
			orb.Vel = orb.Vel:Lerp(offset.Unit * speed, math.min(1, dt * 10))
			orb.Pos += orb.Vel * math.min(dt, distance / math.max(speed, 1))
		elseif age < BOUNCE_SECONDS then
			orb.Vel += Vector3.new(0, -90 * dt, 0)
			orb.Pos += orb.Vel * dt
		else
			-- Hover and bob in place until the player comes close enough.
			orb.Vel = Vector3.zero
			orb.Pos += Vector3.new(0, math.sin(now * 4 + index) * 0.6 * dt, 0)
			local near = root and (root.Position - orb.Pos).Magnitude <= radius
			if near or age >= AUTO_COLLECT_SECONDS then
				orb.Homing = true
				orb.Vel = Vector3.new(0, 10, 0)
			end
		end
		orb.Part.CFrame = CFrame.new(orb.Pos) * CFrame.Angles(0, now * 5 + index, math.rad(20))
	end

	if tickerFrame.Visible then
		tickerScale.Scale += (1 - tickerScale.Scale) * math.min(1, dt * 12)
		if now - lastPickup > TICKER_HOLD and #orbs == 0 then
			tickerFrame.Visible = false
			tickerTotal = 0
		end
	end
end

-- Beams -------------------------------------------------------------------------------------------------------

local function spawnBeam(pos: Vector3, title: string, gold: boolean, owner: number)
	local now = os.clock()
	-- Titles from drops at the same spot (Boss Core + Relic) stack instead of overlapping.
	local stack = 0
	for index = #beams, 1, -1 do
		local other = beams[index]
		if other.Expires < now then
			table.remove(beams, index)
		elseif (other.Pos - pos).Magnitude < 6 then
			stack += 1
		end
	end
	table.insert(beams, { Pos = pos, Expires = now + BEAM_SECONDS })

	local color = if gold then BEAM_COLORS.Gold else BEAM_COLORS.Purple
	local base = pos - Vector3.new(0, 2, 0)
	local pillar = Instance.new("Part")
	pillar.Name = "LootBeam"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(BEAM_HEIGHT, 1.2, 1.2)
	pillar.CFrame = CFrame.new(base + Vector3.new(0, BEAM_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	pillar.Transparency = 0.35
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 18
	light.Brightness = 3
	light.Parent = pillar
	local halo = pillar:Clone()
	halo.Name = "LootBeamHalo"
	halo.Size = Vector3.new(BEAM_HEIGHT, 3.4, 3.4)
	halo.Material = Enum.Material.ForceField -- soft coloured glow around the hard neon core
	halo.Transparency = 0.8
	halo:ClearAllChildren()

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 6 + stack * 2.6, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 48)
	gui.AlwaysOnTop = true -- rooms put platforms and trees in front of drops
	gui.LightInfluence = 0
	gui.MaxDistance = 260
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 30
	label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	label.TextStrokeTransparency = 0
	label.Text = title
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label

	pillar.Parent = folder
	halo.Parent = folder
	anchor.Parent = folder
	sprite("light_01", pos, color, 14, 0.6, 1, 0)
	sprite("star_04", pos, color, 2, 1, 10, 18)
	if owner == localPlayer.UserId then
		Sfx.Play("Forge_Success", 0.6, if gold then 1.15 else 1)
	else
		Sfx.Play("UI_Popup", 0.35)
	end

	local born = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - born
		if t >= BEAM_SECONDS then
			connection:Disconnect()
			pillar:Destroy()
			halo:Destroy()
			anchor:Destroy()
			return
		end
		local fadeIn = math.min(1, t / 0.25)
		local fadeOut = math.clamp((BEAM_SECONDS - t) / 0.8, 0, 1)
		local pulse = 0.08 * math.sin(t * 6)
		pillar.Transparency = 1 - (0.88 + pulse) * fadeIn * fadeOut
		halo.Transparency = 1 - (0.75 + pulse) * fadeIn * fadeOut
		scale.Scale = if t < 0.3 then 0.3 + 0.9 * (t / 0.3) else 1.2 - 0.2 * math.min(1, (t - 0.3) / 0.2)
		label.TextTransparency = 1 - fadeOut
		label.TextStrokeTransparency = 1 - fadeOut
	end)
end

-- Init --------------------------------------------------------------------------------------------------------

local function applyProfile(profile: any)
	if type(profile) == "table" and type(profile.AscensionNodes) == "table" then
		vacuumLevel = tonumber(profile.AscensionNodes[NODE_VACUUM]) or 0
	end
end

function LootOrbController.Init()
	folder = Instance.new("Folder")
	folder.Name = "RiftLootOrbs"
	folder.Parent = Workspace
	buildTicker()

	Remotes.GetEvent("CombatFx").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or typeof(payload.Pos) ~= "Vector3" then
			return
		end
		if payload.Kind == "DustOrbs" then
			spawnOrbs(payload.Pos, tonumber(payload.Amount) or 0, tonumber(payload.Count) or 3)
		elseif payload.Kind == "LootBeam" then
			spawnBeam(payload.Pos, tostring(payload.Title or "✨ RARE DROP!"), payload.Gold == true,
				tonumber(payload.Owner) or 0)
		end
	end)
	-- Orbs belong to the place they dropped in: entering or leaving a run sweeps them away.
	localPlayer:GetAttributeChangedSignal("RunId"):Connect(function()
		for index = #orbs, 1, -1 do
			removeOrb(index)
		end
	end)
	Remotes.GetEvent("ProfileUpdated").OnClientEvent:Connect(applyProfile)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Remotes.GetFunction("GetProfile"):InvokeServer()
		end)
		if ok then
			applyProfile(profile)
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		stepOrbs(dt, os.clock())
	end)
end

return LootOrbController
