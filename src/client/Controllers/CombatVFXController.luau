--!strict
-- StarterPlayerScripts/Client/Controllers/CombatVFXController.luau
-- All combat cosmetics (Sections 9 & 28.3). The server decides every hit; this controller only draws what it is told:
--
--   * DamageNumber batches -> an object pool of 60 BillboardGui slots. Each hit renders its primary number and up to
--     3 Limit-Breaker shadow lines in one stacked container that cascades upward over 0.55s and returns to the pool.
--   * CombatFx events: Swing, Proj / ProjEnd / ProjReflect, Burst, Telegraph, Sweep, Chain, Zone, Shake, Roar.
--     Telegraphs are the bold red / green warning zones that precede every boss attack.
--   * Teammate VFX opacity throttling: the local player's effects render at full strength, everyone else's at 25%
--     opacity, so boss telegraphs stay readable with 4 players on mobile.
--
-- Effect parts are pooled and driven from a single RenderStepped loop (no per-effect tweens or connections).
-- The local player's own melee swing is drawn instantly from CombatInputController (predictive VFX); the server
-- never echoes a swing back to the player who swung.
--
-- CombatFx payload shapes (all fields set by CombatService / EnemyAIService):
--   Swing{Owner,Weapon,Style,Pos,Facing,Range,Height}  Proj{Id,Style,Pos,Vel,Life,HalfX,HalfY,Owner}  ProjEnd{Id,Pos,Hit}
--   ProjReflect{Id,Pos,Vel}  Burst{Pos,Radius,Style,Owner}  Telegraph{Pos,Size,Duration,Style}
--   Sweep{Pos,HalfX,Style,Duration}  Chain{From,To,Owner}  Zone{Pos,HalfX,HalfY,Duration,Owner}
--   Shake{Intensity,Duration}  Roar{Pos}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local Camera25DController = require(script.Parent:WaitForChild("Camera25DController"))

local localPlayer = Players.LocalPlayer
local localUserId = localPlayer.UserId

local NUMBER_POOL_SIZE = 60
local NUMBER_LIFE = 0.55
local NUMBER_RISE = 3.6
local NUMBER_MAX_LINES = 3
local TEAMMATE_OPACITY = 0.25
local MAX_EFFECTS = 140
local PART_POOL_LIMIT = 90

local STYLE_COLORS: { [string]: Color3 } = {
	Slash = Color3.fromRGB(255, 160, 120),
	Stab = Color3.fromRGB(185, 140, 255),
	Bolt = Color3.fromRGB(100, 215, 255),
	Fireball = Color3.fromRGB(255, 135, 45),
	Wave = Color3.fromRGB(255, 110, 75),
	Blade = Color3.fromRGB(180, 130, 255),
	Boulder = Color3.fromRGB(120, 160, 85),
	Shockwave = Color3.fromRGB(150, 235, 95),
	Slam = Color3.fromRGB(215, 185, 120),
	Nova = Color3.fromRGB(195, 115, 255),
	Cinders = Color3.fromRGB(255, 95, 60),
	Roar = Color3.fromRGB(255, 85, 165),
	Poison = Color3.fromRGB(125, 255, 95),
	Danger = Color3.fromRGB(255, 65, 75),
	Warn = Color3.fromRGB(255, 175, 65),
	Chain = Color3.fromRGB(150, 235, 255),
	Default = Color3.fromRGB(235, 240, 255),
}

local NUMBER_STYLES: { [string]: { Color: Color3, Size: number } } = {
	Hit = { Color = Color3.fromRGB(255, 255, 255), Size = 26 },
	Crit = { Color = Color3.fromRGB(255, 215, 70), Size = 36 },
	Dot = { Color = Color3.fromRGB(255, 150, 60), Size = 19 },
	Chain = { Color = Color3.fromRGB(125, 230, 255), Size = 21 },
	Hurt = { Color = Color3.fromRGB(255, 85, 85), Size = 30 },
	Reflect = { Color = Color3.fromRGB(150, 255, 120), Size = 40 },
	Shadow = { Color = Color3.fromRGB(205, 175, 255), Size = 19 },
}

type Effect = {
	Born: number,
	Life: number,
	Update: (alpha: number, dt: number) -> (),
	Cleanup: () -> (),
}

type ProjVisual = {
	Part: Part,
	Pos: Vector3,
	Vel: Vector3,
	Born: number,
	Life: number,
	Style: string,
	Owner: number,
	Dir: number,
}

type NumberSlot = {
	Anchor: Part,
	Gui: BillboardGui,
	Labels: { TextLabel },
	Scales: { UIScale },
	Active: boolean,
	Born: number,
	Used: number,
	Opacity: number,
}

local CombatVFXController = {}

local fxFolder: Folder
local numberFolder: Folder
local partPool: { Part } = {}
local effects: { Effect } = {}
local projVisuals: { [number]: ProjVisual } = {}
local freeSlots: { NumberSlot } = {}
local activeSlots: { NumberSlot } = {}
local rng = Random.new()

-- Pools -------------------------------------------------------------------------------------------------------

local function acquirePart(shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local pooled: Part? = table.remove(partPool)
	local fresh: Part
	if pooled then
		fresh = pooled
	else
		fresh = Instance.new("Part")
		fresh.Anchored = true
		fresh.CanCollide = false
		fresh.CanTouch = false
		fresh.CanQuery = false
		fresh.CastShadow = false
		fresh.Material = Enum.Material.Neon
		fresh.TopSurface = Enum.SurfaceType.Smooth
		fresh.BottomSurface = Enum.SurfaceType.Smooth
	end
	fresh.Shape = shape
	fresh.Size = size
	fresh.CFrame = cframe
	fresh.Color = color
	fresh.Transparency = transparency
	fresh.Parent = fxFolder
	return fresh
end

local function releasePart(part: Part)
	part.Parent = nil
	if #partPool < PART_POOL_LIMIT then
		table.insert(partPool, part)
	else
		part:Destroy()
	end
end

-- Teammates' effects render at TEAMMATE_OPACITY of full strength (transparency pushed toward 1).
local function opacityOf(owner: number): number
	if owner == 0 or owner == localUserId then
		return 1
	end
	return TEAMMATE_OPACITY
end

local function throttled(transparency: number, opacity: number): number
	return 1 - (1 - transparency) * opacity
end

local function colorOf(style: string?): Color3
	return STYLE_COLORS[style or "Default"] or STYLE_COLORS.Default
end

local function addEffect(life: number, owner: number, update: (alpha: number, dt: number) -> (), cleanup: () -> ()): boolean
	if #effects >= MAX_EFFECTS and owner ~= localUserId then
		cleanup()
		return false
	end
	table.insert(effects, { Born = os.clock(), Life = math.max(life, 0.02), Update = update, Cleanup = cleanup })
	return true
end

-- Effects ------------------------------------------------------------------------------------------------------

local function spawnBurst(pos: Vector3, radius: number, style: string, owner: number)
	local color = colorOf(style)
	local opacity = opacityOf(owner)
	local part = acquirePart(Enum.PartType.Ball, Vector3.one, CFrame.new(pos), color, throttled(0.3, opacity))
	addEffect(0.34, owner, function(alpha: number)
		local diameter = math.max(0.5, radius * 2 * (1 - (1 - alpha) ^ 2))
		part.Size = Vector3.one * diameter
		part.Transparency = throttled(0.3 + 0.7 * alpha, opacity)
	end, function()
		releasePart(part)
	end)
end

local function spawnSwing(style: string, color: Color3, pos: Vector3, facing: number, range: number, owner: number)
	local opacity = opacityOf(owner)
	local origin = pos + Vector3.new(0, 0.5, 0)
	if style == "Stab" then
		local part = acquirePart(Enum.PartType.Block, Vector3.new(range, 0.7, 1.4), CFrame.new(origin), color, throttled(0.1, opacity))
		addEffect(0.14, owner, function(alpha: number)
			local length = range * (0.4 + 0.6 * math.min(1, alpha * 2.5))
			part.Size = Vector3.new(length, 0.7, 1.4)
			part.CFrame = CFrame.new(origin + Vector3.new(facing * length / 2, 0, 0))
			part.Transparency = throttled(0.1 + 0.9 * alpha ^ 1.5, opacity)
		end, function()
			releasePart(part)
		end)
		return
	end
	local part = acquirePart(Enum.PartType.Block, Vector3.new(range, 0.9, 6), CFrame.new(origin), color, throttled(0.1, opacity))
	addEffect(0.15, owner, function(alpha: number)
		local angle = facing * math.rad(60 - 120 * alpha)
		part.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, angle) * CFrame.new(facing * range / 2, 0, 0)
		part.Transparency = throttled(0.1 + 0.9 * alpha ^ 1.5, opacity)
	end, function()
		releasePart(part)
	end)
end

local function spawnTelegraph(pos: Vector3, size: Vector3, duration: number, style: string)
	local color = colorOf(style)
	local outline = acquirePart(Enum.PartType.Block, size, CFrame.new(pos), color, 0.82)
	local fill = acquirePart(Enum.PartType.Block, size * 0.02, CFrame.new(pos), color, 0.55)
	addEffect(duration + 0.12, 0, function(alpha: number)
		local progress = math.min(1, alpha * (duration + 0.12) / duration)
		fill.Size = size * math.max(0.02, progress)
		outline.Transparency = 0.82 - 0.12 * math.sin(progress * math.pi * 6) ^ 2
		if progress >= 1 then
			fill.Transparency = 0.35 + 0.65 * ((alpha * (duration + 0.12) - duration) / 0.12)
			outline.Transparency = 1
		end
	end, function()
		releasePart(outline)
		releasePart(fill)
	end)
end

local function spawnSweep(pos: Vector3, halfX: number, style: string, duration: number)
	local color = colorOf(style)
	local part = acquirePart(Enum.PartType.Block, Vector3.new(0.5, 3.4, 8), CFrame.new(pos + Vector3.new(0, 0.6, 0)), color, 0.3)
	addEffect(duration, 0, function(alpha: number)
		part.Size = Vector3.new(math.max(0.5, halfX * 2 * alpha), 3.4, 8)
		part.Transparency = 0.3 + 0.7 * alpha ^ 2
	end, function()
		releasePart(part)
	end)
end

-- Jagged lightning bar between two points.
local function spawnChain(from: Vector3, to: Vector3, owner: number)
	local opacity = opacityOf(owner)
	local color = colorOf("Chain")
	local segments = 4
	local points: { Vector3 } = { from }
	local direction = to - from
	local normal = Vector3.new(-direction.Y, direction.X, 0)
	if normal.Magnitude > 0 then
		normal = normal.Unit
	end
	for index = 1, segments - 1 do
		local jitter = normal * rng:NextNumber(-1.6, 1.6)
		table.insert(points, from + direction * (index / segments) + jitter)
	end
	table.insert(points, to)

	local parts: { Part } = {}
	for index = 1, segments do
		local a, b = points[index], points[index + 1]
		local length = math.max(0.1, (b - a).Magnitude)
		local part = acquirePart(Enum.PartType.Block, Vector3.new(length, 0.35, 0.35),
			CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, throttled(0, opacity))
		table.insert(parts, part)
	end
	addEffect(0.18, owner, function(alpha: number)
		for _, part in parts do
			part.Transparency = throttled(alpha ^ 1.5, opacity)
		end
	end, function()
		for _, part in parts do
			releasePart(part)
		end
	end)
end

local function spawnZone(pos: Vector3, halfX: number, halfY: number, duration: number, owner: number)
	local opacity = opacityOf(owner)
	local color = colorOf("Fireball")
	local part = acquirePart(Enum.PartType.Block, Vector3.new(halfX * 2, halfY * 2, 8), CFrame.new(pos), color, throttled(0.75, opacity))
	addEffect(duration, owner, function(alpha: number)
		local flicker = 0.72 + 0.08 * math.sin(alpha * duration * 14)
		local fade = if alpha > 0.88 then (alpha - 0.88) / 0.12 else 0
		part.Transparency = throttled(flicker + (1 - flicker) * fade, opacity)
	end, function()
		releasePart(part)
	end)
end

-- Projectiles ---------------------------------------------------------------------------------------------------

local function projectileShape(style: string, halfX: number, halfY: number): (Enum.PartType, Vector3)
	if style == "Fireball" then
		return Enum.PartType.Ball, Vector3.one * (halfX * 2.4)
	elseif style == "Boulder" then
		return Enum.PartType.Ball, Vector3.one * (halfX * 2)
	elseif style == "Wave" then
		return Enum.PartType.Block, Vector3.new(0.9, halfY * 2, 5)
	elseif style == "Blade" then
		return Enum.PartType.Block, Vector3.new(2.4, 0.35, 1)
	elseif style == "Shockwave" then
		return Enum.PartType.Block, Vector3.new(halfX * 2, halfY * 2, 8)
	end
	return Enum.PartType.Ball, Vector3.one * (halfX * 2)
end

local function removeProjectile(id: number)
	local visual = projVisuals[id]
	if visual then
		projVisuals[id] = nil
		releasePart(visual.Part)
	end
end

local function spawnProjectile(payload: { [string]: any })
	local id = payload.Id :: number
	removeProjectile(id)
	local style = payload.Style :: string
	local owner = payload.Owner :: number
	local shape, size = projectileShape(style, payload.HalfX, payload.HalfY)
	local vel = payload.Vel :: Vector3
	local part = acquirePart(shape, size, CFrame.new(payload.Pos), colorOf(style), throttled(0.05, opacityOf(owner)))
	projVisuals[id] = {
		Part = part, Pos = payload.Pos, Vel = vel, Born = os.clock(), Life = payload.Life, Style = style, Owner = owner,
		Dir = if vel.X >= 0 then 1 else -1,
	}
end

local function stepProjectiles(dt: number, now: number)
	for id, visual in projVisuals do
		if now - visual.Born > visual.Life + 0.6 then
			removeProjectile(id)
			continue
		end
		visual.Pos += visual.Vel * dt
		local rotation = CFrame.identity
		if visual.Style == "Blade" then
			rotation = CFrame.Angles(0, 0, math.atan2(visual.Vel.Y, visual.Vel.X))
		elseif visual.Style == "Boulder" then
			rotation = CFrame.Angles(0, 0, -visual.Dir * (now - visual.Born) * 7)
		end
		visual.Part.CFrame = CFrame.new(visual.Pos) * rotation
	end
end

-- Damage numbers -----------------------------------------------------------------------------------------------

local function formatNumber(amount: number): string
	local n = math.floor(amount + 0.5)
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e7 then
		return string.format("%.2fM", n / 1e6)
	end
	local text = tostring(n)
	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

local function createSlot(): NumberSlot
	local anchor = Instance.new("Part")
	anchor.Name = "NumberAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(0, -1000, 0)
	anchor.Parent = numberFolder

	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(240, 150)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 320
	gui.Enabled = false
	gui.Parent = anchor

	local labels: { TextLabel } = {}
	local scales: { UIScale } = {}
	for index = 1, NUMBER_MAX_LINES + 1 do
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -(index - 1) * 27)
		label.Size = UDim2.new(1, 0, 0, 36)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Visible = false
		label.Parent = gui
		local scale = Instance.new("UIScale")
		scale.Parent = label
		table.insert(labels, label)
		table.insert(scales, scale)
	end
	return { Anchor = anchor, Gui = gui, Labels = labels, Scales = scales, Active = false, Born = 0, Used = 0, Opacity = 1 }
end

local function recycleSlot(slot: NumberSlot)
	slot.Active = false
	slot.Gui.Enabled = false
	for _, label in slot.Labels do
		label.Visible = false
	end
	slot.Anchor.CFrame = CFrame.new(0, -1000, 0)
	local index = table.find(activeSlots, slot)
	if index then
		table.remove(activeSlots, index)
	end
	table.insert(freeSlots, slot)
end

local function acquireSlot(): NumberSlot
	local slot = table.remove(freeSlots)
	if not slot then
		local oldest = activeSlots[1]
		recycleSlot(oldest)
		slot = table.remove(freeSlots)
	end
	return slot :: NumberSlot
end

local function styleLabel(label: TextLabel, text: string, style: { Color: Color3, Size: number }, opacity: number)
	label.Text = text
	label.TextColor3 = style.Color
	label.TextSize = style.Size * (if opacity < 1 then 0.8 else 1)
	label.Visible = true
end

local function showNumber(entry: { [string]: any })
	local owner = if type(entry.Owner) == "number" then entry.Owner else 0
	local kind = if type(entry.Kind) == "string" then entry.Kind else "Hit"
	local amount = if type(entry.Amount) == "number" then entry.Amount else 0
	local pos = entry.Pos :: Vector3
	local opacity = if kind == "Hurt" then 1 else opacityOf(owner)

	local slot = acquireSlot()
	slot.Active = true
	slot.Born = os.clock()
	slot.Opacity = if opacity < 1 then 0.6 else 1
	slot.Anchor.CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.2, 1.2), 0, 0))
	slot.Gui.StudsOffsetWorldSpace = Vector3.zero
	slot.Gui.Enabled = true

	local isCrit = entry.Crit == true
	local style = if isCrit then NUMBER_STYLES.Crit else (NUMBER_STYLES[kind] or NUMBER_STYLES.Hit)
	local text = formatNumber(amount)
	if kind == "Hurt" then
		text = "-" .. text
	elseif isCrit then
		text ..= "!"
	end
	styleLabel(slot.Labels[1], text, style, opacity)
	slot.Used = 1

	local lines = entry.Lines
	if type(lines) == "table" then
		for index = 1, math.min(NUMBER_MAX_LINES, #lines) do
			styleLabel(slot.Labels[index + 1], formatNumber(lines[index]), NUMBER_STYLES.Shadow, opacity)
			slot.Used += 1
		end
	end
	for index = slot.Used + 1, #slot.Labels do
		slot.Labels[index].Visible = false
	end
	table.insert(activeSlots, slot)
end

local function stepNumbers(now: number)
	for index = #activeSlots, 1, -1 do
		local slot = activeSlots[index]
		local age = now - slot.Born
		if age >= NUMBER_LIFE + 0.07 * slot.Used then
			recycleSlot(slot)
		else
			local rise = 1 - (1 - math.min(1, age / NUMBER_LIFE)) ^ 2
			slot.Gui.StudsOffsetWorldSpace = Vector3.new(0, NUMBER_RISE * rise, 0)
			for lineIndex = 1, slot.Used do
				-- Shadow lines start slightly later, so the stack cascades upward.
				local t = (age - (lineIndex - 1) * 0.07) / NUMBER_LIFE
				local label = slot.Labels[lineIndex]
				if t < 0 then
					label.TextTransparency = 1
					label.TextStrokeTransparency = 1
				else
					local fade = math.clamp((t - 0.55) / 0.45, 0, 1)
					local transparency = throttled(fade, slot.Opacity)
					label.TextTransparency = transparency
					label.TextStrokeTransparency = transparency
					slot.Scales[lineIndex].Scale = 1 + 0.45 * math.max(0, 1 - t * 14)
				end
			end
		end
	end
end

-- Dispatch -----------------------------------------------------------------------------------------------------

local function handleFx(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.Kind
	if kind == "Swing" then
		local weapon = WeaponConfig.Weapons[payload.Weapon]
		local color = if weapon then weapon.Accent else colorOf(payload.Style)
		spawnSwing(payload.Style, color, payload.Pos, payload.Facing, payload.Range, payload.Owner)
	elseif kind == "Proj" then
		spawnProjectile(payload)
	elseif kind == "ProjEnd" then
		local visual = projVisuals[payload.Id]
		if visual and payload.Hit and visual.Style ~= "Fireball" then
			spawnBurst(payload.Pos, 2.5, visual.Style, visual.Owner)
		end
		removeProjectile(payload.Id)
	elseif kind == "ProjReflect" then
		local visual = projVisuals[payload.Id]
		if visual then
			visual.Pos = payload.Pos
			visual.Vel = payload.Vel
			visual.Dir = if payload.Vel.X >= 0 then 1 else -1
			visual.Born = os.clock()
			visual.Life = 3
			visual.Part.Color = colorOf("Slam")
			spawnBurst(payload.Pos, 4, "Slam", 0)
		end
	elseif kind == "Burst" then
		spawnBurst(payload.Pos, payload.Radius, payload.Style, payload.Owner or 0)
	elseif kind == "Telegraph" then
		spawnTelegraph(payload.Pos, payload.Size, payload.Duration, payload.Style)
	elseif kind == "Sweep" then
		spawnSweep(payload.Pos, payload.HalfX, payload.Style, payload.Duration)
	elseif kind == "Chain" then
		spawnChain(payload.From, payload.To, payload.Owner or 0)
	elseif kind == "Zone" then
		spawnZone(payload.Pos, payload.HalfX, payload.HalfY, payload.Duration, payload.Owner or 0)
	elseif kind == "Shake" then
		Camera25DController.Shake(payload.Intensity, payload.Duration)
	elseif kind == "Roar" then
		spawnBurst(payload.Pos, 22, "Roar", 0)
	end
end

-- Predictive swing for the local player (called by CombatInputController the instant the button is pressed).
function CombatVFXController.PlaySwing(weaponId: string, facing: number)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local weapon = WeaponConfig.Weapons[weaponId]
	if not root or not root:IsA("BasePart") or not weapon then
		return
	end
	local profile = weapon.Attack or WeaponConfig.GenericAttack
	if profile.Kind ~= "Melee" then
		return -- projectile weapons are drawn from the server's Proj event
	end
	spawnSwing(profile.Style, weapon.Accent, root.Position, facing, profile.Range, localUserId)
end

function CombatVFXController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "RiftCombatFx"
	fxFolder.Parent = Workspace
	numberFolder = Instance.new("Folder")
	numberFolder.Name = "RiftDamageNumbers"
	numberFolder.Parent = Workspace

	for _ = 1, NUMBER_POOL_SIZE do
		table.insert(freeSlots, createSlot())
	end

	Remotes.GetEvent("CombatFx").OnClientEvent:Connect(handleFx)
	Remotes.GetEvent("DamageNumber").OnClientEvent:Connect(function(batch: any)
		if type(batch) ~= "table" then
			return
		end
		for _, entry in batch do
			if type(entry) == "table" and typeof(entry.Pos) == "Vector3" then
				showNumber(entry)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local now = os.clock()
		stepProjectiles(dt, now)
		stepNumbers(now)
		for index = #effects, 1, -1 do
			local effect = effects[index]
			local alpha = (now - effect.Born) / effect.Life
			if alpha >= 1 then
				effect.Cleanup()
				effects[index] = effects[#effects]
				effects[#effects] = nil
			else
				effect.Update(alpha, dt)
			end
		end
	end)
end

return CombatVFXController
