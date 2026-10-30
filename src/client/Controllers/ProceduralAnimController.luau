--!strict
-- StarterPlayerScripts/Client/Controllers/ProceduralAnimController.luau
-- Code-driven MapleStory-style monster animation (Section 31.2) — no rigging or animation assets needed.
--
-- The server moves enemies as anchored models at ~20 Hz. For every enemy this controller hides the replicated model
-- (LocalTransparencyModifier) and renders a local visual copy that
--   * glides smoothly toward the server position every frame,
--   * breathes while idle, squashes before / stretches during / squashes after a hop, leans into movement,
--     crouches on boss wind-ups and wobbles when stunned,
--   * flashes (Highlight) and tilts back when hit, outlines Burning / Shocked enemies,
--   * shows an overhead HP bar on Elites and Bosses, and shrinks away when the enemy dies.
-- It reads only attributes the server already replicates: HP, MaxHP, EnemyKind, AIState, Airborne, HitDir, Burning,
-- Shocked, Phase. Any enemy model (procedural fallback or a dropped-in custom one) works the same.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EnemyConfig = require(Shared:WaitForChild("EnemyConfig"))
local RigAnimator = require(script.Parent:WaitForChild("RigAnimator"))

local FOLDER_NAME = "RiftEnemyVisuals"
local SMOOTHING = 22 -- exponential follow rate toward the server position
local SNAP_DISTANCE = 30 -- teleports (respawn at spawn point) cut instead of gliding
local BREATH_SPEED = 3
local BREATH_Y = 0.06
local BREATH_X = 0.03
local LAND_SQUASH_SECONDS = 0.14
local FLASH_SECONDS = 0.1
local TILT_SECONDS = 0.08
local TILT_RADIANS = math.rad(15)
local LEAN_PER_SPEED = 0.012
local MAX_LEAN = 0.25
local DEATH_SECONDS = 0.28
local DEATH_SPIN = 9
local TURN_ANGLE = math.rad(45) -- three-quarter view: turned this far from the camera toward the walk direction
local TURN_RATE = 10
local FACING_MIN_SPEED = 0.5 -- slower than this keeps the previous facing

local HIT_FLASH_COLOR = Color3.new(1, 1, 1)
local BURN_COLOR = Color3.fromRGB(255, 140, 40)
local SHOCK_COLOR = Color3.fromRGB(255, 240, 90)
local BAR_BACK = Color3.fromRGB(20, 20, 28)
local BAR_FILL = Color3.fromRGB(235, 70, 80)
local BAR_BOSS_FILL = Color3.fromRGB(190, 60, 255)
local ENRAGE_COLOR = Color3.fromRGB(255, 60, 50)
local CALLOUT_FONT = Enum.Font.FredokaOne
local CALLOUT_DANGER = Color3.fromRGB(255, 96, 70)
local CALLOUT_EXPOSED = Color3.fromRGB(110, 235, 130)
-- What the boss is about to do and how to answer it; shown above its health bar for the whole windup.
local MOVE_CALLOUTS: { [string]: string } = {
	GroundPound = "SLAM - JUMP!",
	BoulderCharge = "CHARGE - GET CLEAR!",
	PoisonWave = "POISON WAVE - JUMP!",
	SporeBoulder = "BOULDER - HIT IT BACK!",
}

type PartInfo = { Part: BasePart, Size: Vector3, Offset: CFrame }

type Proxy = {
	Model: Model,
	Visual: Model,
	Parts: { PartInfo },
	HalfY: number,
	Smoothed: Vector3,
	LastSmoothed: Vector3,
	VelX: number,
	VelY: number,
	Phase: number,
	BaseYaw: number,
	Facing: number,
	Turn: number,
	WasAirborne: boolean,
	LandUntil: number,
	FlashUntil: number,
	TiltUntil: number,
	HitDir: number,
	LastHP: number,
	Highlight: Highlight?,
	BarFill: Frame?,
	Rig: RigAnimator.Rig?,
	StateName: string,
	StateSince: number,
	Dying: boolean,
	DyingStart: number,
	DyingScale: Vector3,
	Connections: { RBXScriptConnection },
}

local ProceduralAnimController = {}

local proxies: { [Model]: Proxy } = {}
local visualFolder: Folder
local rng = Random.new()

-- Construction ------------------------------------------------------------------------------------------------

local function hideOriginal(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
		end
	end
end

local function buildVisual(model: Model): (Model, { PartInfo })
	local visual = model:Clone()
	CollectionService:RemoveTag(visual, EnemyConfig.TAG)
	local pivot = visual:GetPivot()
	local parts: { PartInfo } = {}
	for _, descendant in visual:GetDescendants() do
		-- Bones are Attachments too, but imported rigged meshes (skinned MeshParts) render wrong without them.
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("ClickDetector") or descendant:IsA("WeldConstraint")
			or descendant:IsA("Weld") or descendant:IsA("ProximityPrompt") or descendant:IsA("Constraint")
			or (descendant:IsA("Attachment") and not descendant:IsA("Bone")) then
			descendant:Destroy()
		end
	end
	for _, descendant in visual:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.LocalTransparencyModifier = 0
			table.insert(parts, { Part = descendant, Size = descendant.Size, Offset = pivot:ToObjectSpace(descendant.CFrame) })
		end
	end
	visual.Parent = visualFolder
	return visual, parts
end

local function buildHealthBar(proxy: Proxy, kind: string)
	local anchor = proxy.Visual.PrimaryPart
	if not anchor then
		return
	end
	local isBoss = kind == "Boss"
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = anchor
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Size = UDim2.fromOffset(if isBoss then 220 else 90, if isBoss then 16 else 9)
	gui.StudsOffsetWorldSpace = Vector3.new(0, proxy.HalfY + (if isBoss then 3 else 1.6), 0)
	gui.Parent = anchor

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = BAR_BACK
	back.BorderSizePixel = 0
	back.Parent = gui
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 4)
	backCorner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Parent = back

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if isBoss then BAR_BOSS_FILL else BAR_FILL
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill
	proxy.BarFill = fill
end

-- Boss callout: one banner at the top of the screen says what the boss is winding up and counts the telegraph
-- down, then flags the exposed recovery window. It lives on screen (not above the boss) because bosses are taller
-- than the close 2.5D camera frames them.
local bannerGui: ScreenGui
local bannerFrame: Frame
local bannerLabel: TextLabel
local bannerFill: Frame
local bannerText: string? = nil
local bannerColor = CALLOUT_DANGER
local bannerFraction = 1

local function buildBanner()
	bannerGui = Instance.new("ScreenGui")
	bannerGui.Name = "RiftBossCallout"
	bannerGui.ResetOnSpawn = false
	bannerGui.DisplayOrder = 6
	bannerGui.IgnoreGuiInset = true
	bannerGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	bannerFrame = Instance.new("Frame")
	bannerFrame.AnchorPoint = Vector2.new(0.5, 0)
	bannerFrame.Position = UDim2.new(0.5, 0, 0, 150)
	bannerFrame.Size = UDim2.fromOffset(340, 62)
	bannerFrame.BackgroundColor3 = Color3.fromRGB(13, 21, 36)
	bannerFrame.BackgroundTransparency = 0.12
	bannerFrame.BorderSizePixel = 0
	bannerFrame.Visible = false
	bannerFrame.Parent = bannerGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bannerFrame
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Thickness = 3
	stroke.Color = CALLOUT_DANGER
	stroke.Parent = bannerFrame

	bannerLabel = Instance.new("TextLabel")
	bannerLabel.Text = ""
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.Position = UDim2.fromOffset(0, 6)
	bannerLabel.Size = UDim2.new(1, 0, 0, 32)
	bannerLabel.Font = CALLOUT_FONT
	bannerLabel.TextSize = 28
	bannerLabel.TextColor3 = CALLOUT_DANGER
	bannerLabel.Parent = bannerFrame
	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.fromRGB(13, 21, 36)
	labelStroke.Thickness = 3
	labelStroke.Parent = bannerLabel

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, 42)
	track.Size = UDim2.new(1, -36, 0, 10)
	track.BackgroundColor3 = Color3.fromRGB(34, 44, 68)
	track.BorderSizePixel = 0
	track.Parent = bannerFrame
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	bannerFill = Instance.new("Frame")
	bannerFill.Size = UDim2.fromScale(1, 1)
	bannerFill.BackgroundColor3 = CALLOUT_DANGER
	bannerFill.BorderSizePixel = 0
	bannerFill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = bannerFill
end

-- Called per boss each frame; the most urgent request wins (a windup beats an exposed window).
local function requestCallout(stateName: string, move: string, stateTime: number, windup: number)
	if stateName == "Windup" and MOVE_CALLOUTS[move] then
		bannerText = MOVE_CALLOUTS[move]
		bannerColor = CALLOUT_DANGER
		bannerFraction = math.clamp(1 - stateTime / math.max(windup, 0.1), 0, 1)
	elseif stateName == "Recovery" and stateTime > 0.3 and bannerText == nil then
		bannerText = "EXPOSED - ATTACK!"
		bannerColor = CALLOUT_EXPOSED
		bannerFraction = 1
	end
end

local function applyBanner()
	local text = bannerText
	bannerFrame.Visible = text ~= nil
	if text then
		bannerLabel.Text = text
		bannerLabel.TextColor3 = bannerColor
		bannerFill.BackgroundColor3 = bannerColor
		bannerFill.Size = UDim2.fromScale(bannerFraction, 1)
		local edge = bannerFrame:FindFirstChild("Edge")
		if edge and edge:IsA("UIStroke") then
			edge.Color = bannerColor
		end
	end
	bannerText = nil
end

local function updateBar(proxy: Proxy)
	local fill = proxy.BarFill
	if not fill then
		return
	end
	local maxHP = proxy.Model:GetAttribute("MaxHP")
	local hp = proxy.Model:GetAttribute("HP")
	if type(maxHP) == "number" and type(hp) == "number" and maxHP > 0 then
		fill.Size = UDim2.fromScale(math.clamp(hp / maxHP, 0, 1), 1)
	end
end

local function getHighlight(proxy: Proxy): Highlight
	local existing = proxy.Highlight
	if existing then
		return existing
	end
	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Enabled = false
	highlight.Parent = proxy.Visual
	proxy.Highlight = highlight
	return highlight
end

local function onHPChanged(proxy: Proxy)
	local hp = proxy.Model:GetAttribute("HP")
	if type(hp) ~= "number" then
		return
	end
	if hp < proxy.LastHP then
		local now = os.clock()
		proxy.FlashUntil = now + FLASH_SECONDS
		proxy.TiltUntil = now + TILT_SECONDS
		local dir = proxy.Model:GetAttribute("HitDir")
		proxy.HitDir = if type(dir) == "number" then dir else 1
	end
	proxy.LastHP = hp
	updateBar(proxy)
end

local function createProxy(model: Model)
	if proxies[model] or not model.PrimaryPart then
		return
	end
	local visual, parts = buildVisual(model)
	hideOriginal(model)

	local _, size = model:GetBoundingBox()
	local pivot = model:GetPivot().Position
	local hp = model:GetAttribute("HP")
	local facingYaw = model:GetAttribute("FacingYaw")
	local facing = if rng:NextNumber() < 0.5 then -1 else 1
	local proxy: Proxy = {
		Model = model,
		Visual = visual,
		Parts = parts,
		HalfY = size.Y / 2,
		Smoothed = pivot,
		LastSmoothed = pivot,
		VelX = 0,
		VelY = 0,
		Phase = rng:NextNumber(0, math.pi * 2),
		BaseYaw = math.rad(if type(facingYaw) == "number" then facingYaw else 0),
		Facing = facing,
		Turn = facing * TURN_ANGLE,
		WasAirborne = false,
		LandUntil = 0,
		FlashUntil = 0,
		TiltUntil = 0,
		HitDir = 1,
		LastHP = if type(hp) == "number" then hp else 0,
		Highlight = nil,
		BarFill = nil,
		Rig = RigAnimator.new(visual),
		StateName = "Idle",
		StateSince = os.clock(),
		Dying = false,
		DyingStart = 0,
		DyingScale = Vector3.one,
		Connections = {},
	}
	proxies[model] = proxy

	local kind = model:GetAttribute("EnemyKind")
	if kind == "Elite" or kind == "Boss" then
		buildHealthBar(proxy, kind)
		updateBar(proxy)
	end
	table.insert(proxy.Connections, model:GetAttributeChangedSignal("HP"):Connect(function()
		onHPChanged(proxy)
	end))
end

local function onTagged(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	if instance.PrimaryPart then
		createProxy(instance)
		return
	end
	-- The model can arrive a moment before its PrimaryPart; wait briefly.
	task.spawn(function()
		for _ = 1, 20 do
			task.wait(0.1)
			if not instance.Parent then
				return
			end
			if instance.PrimaryPart then
				createProxy(instance)
				return
			end
		end
	end)
end

local function onUntagged(instance: Instance)
	local proxy = if instance:IsA("Model") then proxies[instance] else nil
	if proxy and not proxy.Dying then
		proxy.Dying = true
		proxy.DyingStart = os.clock()
		for _, connection in proxy.Connections do
			connection:Disconnect()
		end
		table.clear(proxy.Connections)
		if proxy.BarFill then
			proxy.BarFill.Parent = nil
		end
		local highlight = getHighlight(proxy)
		highlight.FillColor = HIT_FLASH_COLOR
		highlight.FillTransparency = 0.2
		highlight.Enabled = true
	end
end

-- Per-frame pose ---------------------------------------------------------------------------------------------

local function applyPose(proxy: Proxy, scaleX: number, scaleY: number, roll: number)
	local center = proxy.Smoothed + Vector3.new(0, proxy.HalfY * (scaleY - 1), 0)
	-- Lean / tilt (roll) is in the screen plane; the yaw turns the model toward the camera and its walk direction.
	local base = CFrame.new(center) * CFrame.Angles(0, 0, roll) * CFrame.Angles(0, proxy.BaseYaw + proxy.Turn, 0)
	local scale = Vector3.new(scaleX, scaleY, scaleX)
	for _, info in proxy.Parts do
		local offset = info.Offset
		info.Part.Size = info.Size * scale
		info.Part.CFrame = base * CFrame.new(offset.Position * scale) * offset.Rotation
	end
end

local function updateHighlight(proxy: Proxy, now: number)
	local highlight = proxy.Highlight
	if proxy.Dying then
		return
	end
	local burning = proxy.Model:GetAttribute("Burning") == true
	local shocked = proxy.Model:GetAttribute("Shocked") == true
	if now < proxy.FlashUntil then
		local flash = getHighlight(proxy)
		flash.FillColor = HIT_FLASH_COLOR
		flash.FillTransparency = 0.2
		flash.OutlineTransparency = 1
		flash.Enabled = true
	elseif burning or shocked then
		local status = getHighlight(proxy)
		local color = if burning then BURN_COLOR else SHOCK_COLOR
		status.FillColor = color
		status.FillTransparency = 0.85
		status.OutlineColor = color
		status.OutlineTransparency = 0.2
		status.Enabled = true
	elseif proxy.Model:GetAttribute("Phase") == 2 then
		-- A boss past its enrage threshold pulses a red outline so the faster second phase is obvious.
		local rage = getHighlight(proxy)
		rage.FillTransparency = 1
		rage.OutlineColor = ENRAGE_COLOR
		rage.OutlineTransparency = 0.45 + 0.3 * math.sin(now * 5)
		rage.Enabled = true
	elseif highlight and highlight.Enabled then
		highlight.Enabled = false
	end
end

local function stepProxy(proxy: Proxy, now: number, dt: number)
	local model = proxy.Model
	if proxy.Dying then
		local progress = (now - proxy.DyingStart) / DEATH_SECONDS
		if progress >= 1 then
			proxy.Visual:Destroy()
			proxies[model] = nil
			return
		end
		local shrink = 1 - progress
		applyPose(proxy, shrink * 1.15, shrink * 0.85, progress * DEATH_SPIN)
		return
	end

	local target = model:GetPivot().Position
	if (target - proxy.Smoothed).Magnitude > SNAP_DISTANCE then
		proxy.Smoothed = target
		proxy.LastSmoothed = target
	else
		proxy.Smoothed = proxy.Smoothed:Lerp(target, 1 - math.exp(-SMOOTHING * dt))
	end
	if dt > 0 then
		local velocity = (proxy.Smoothed - proxy.LastSmoothed) / dt
		proxy.VelX = velocity.X
		proxy.VelY = velocity.Y
	end
	proxy.LastSmoothed = proxy.Smoothed

	local facingAttribute = model:GetAttribute("Facing")
	if type(facingAttribute) == "number" and facingAttribute ~= 0 then
		-- Bosses publish which way they face (toward their target), also while standing still in a windup.
		proxy.Facing = if facingAttribute > 0 then 1 else -1
	elseif math.abs(proxy.VelX) > FACING_MIN_SPEED then
		proxy.Facing = if proxy.VelX > 0 then 1 else -1
	end
	-- Turning between left and right swings through "facing the camera", never through facing away.
	proxy.Turn += (proxy.Facing * TURN_ANGLE - proxy.Turn) * (1 - math.exp(-TURN_RATE * dt))

	local airborne = model:GetAttribute("Airborne") == true
	if proxy.WasAirborne and not airborne then
		proxy.LandUntil = now + LAND_SQUASH_SECONDS
	end
	proxy.WasAirborne = airborne

	local state = model:GetAttribute("AIState")
	local t = now + proxy.Phase
	local scaleX, scaleY, roll = 1, 1, 0

	if airborne then
		if proxy.VelY > 2 then
			scaleX, scaleY = 0.85, 1.25 -- stretch while rising
		else
			scaleX, scaleY = 0.92, 1.12
		end
	elseif now < proxy.LandUntil then
		local k = (proxy.LandUntil - now) / LAND_SQUASH_SECONDS
		scaleX, scaleY = 1 + 0.15 * k, 1 - 0.20 * k -- squash on landing
	elseif state == "Windup" then
		scaleX, scaleY = 1.1, 0.9 + 0.03 * math.sin(t * 40)
	elseif state == "Recovery" then
		scaleX, scaleY = 1.06, 0.94
	elseif state == "Stunned" then
		scaleX, scaleY = 1.04, 0.96
		roll = 0.12 * math.sin(t * 14)
	else
		local breath = math.sin(t * BREATH_SPEED)
		scaleY = 1 + BREATH_Y * breath
		scaleX = 1 - BREATH_X * breath
	end

	local rig = proxy.Rig
	if rig then
		-- A skeleton does the posing; the whole-body squash and stretch would fight it.
		scaleX, scaleY = 1, 1
		local stateName = if type(state) == "string" then state else "Idle"
		if stateName ~= proxy.StateName then
			proxy.StateName = stateName
			proxy.StateSince = now
		end
		local move = model:GetAttribute("Move")
		local windup = model:GetAttribute("WindupDur")
		local moveName = if type(move) == "string" then move else ""
		local windupSeconds = if type(windup) == "number" then windup else 1
		local stateTime = now - proxy.StateSince
		RigAnimator.Update(rig, {
			State = stateName,
			Move = moveName,
			StateTime = stateTime,
			WindupDuration = windupSeconds,
			Speed = math.abs(proxy.VelX),
			Time = t,
			Enraged = model:GetAttribute("Phase") == 2,
		}, dt)
		if model:GetAttribute("EnemyKind") == "Boss" then
			requestCallout(stateName, moveName, stateTime, windupSeconds)
		end
	end

	roll += -math.clamp(proxy.VelX * LEAN_PER_SPEED, -MAX_LEAN, MAX_LEAN)
	if now < proxy.TiltUntil then
		roll -= TILT_RADIANS * proxy.HitDir * ((proxy.TiltUntil - now) / TILT_SECONDS)
	end

	applyPose(proxy, scaleX, scaleY, roll)
	updateHighlight(proxy, now)
end

function ProceduralAnimController.Init()
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	visualFolder = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
	visualFolder.Name = FOLDER_NAME
	visualFolder.Parent = Workspace

	buildBanner()
	for _, instance in CollectionService:GetTagged(EnemyConfig.TAG) do
		onTagged(instance)
	end
	CollectionService:GetInstanceAddedSignal(EnemyConfig.TAG):Connect(onTagged)
	CollectionService:GetInstanceRemovedSignal(EnemyConfig.TAG):Connect(onUntagged)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		for _, proxy in proxies do
			stepProxy(proxy, now, dt)
		end
		applyBanner()
	end)
end

return ProceduralAnimController
