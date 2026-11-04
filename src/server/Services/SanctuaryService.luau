--!strict
-- ServerScriptService/Server/Services/SanctuaryService.luau
-- Passive training (game.md 3.7):
--   * Training Sanctuary in Haven Outpost: a glowing rune circle on the main lane (between the Blacksmith and the
--     Rift Gate) with 3 Training Mushroom Dummies. Anyone standing in it swings at the nearest dummy every 1.5s (real
--     swing VFX + damage numbers sized by their Rift Power) and every 4s earns 20% of a typical run's Rift Dust and
--     Weapon Mastery XP rates, +10% for each other hunter training with them. Dummies pop after a few hits and
--     respawn. The Dust flies out of the dummy as magnetic orbs (LootOrbController).
--   * "While You Were Away": PlayerDataService stamps LastSeenAt on every save. When a profile loads >= 15 minutes
--     later, the time away (capped at 8 hours, together with anything still unclaimed) becomes OfflineTraining:
--     15 Dust/min x Rebirth EcoMult + 5 Mastery XP/min for the equipped weapon. The client asks for it on start
--     (ClaimOfflineTraining { Action = "Query" }) and shows the claim card; "Claim" pays it out, and the
--     OfflineDouble Robux product pays it twice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local MasteryService = require(script.Parent:WaitForChild("MasteryService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local TownHubService = require(script.Parent:WaitForChild("TownHubService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

local SanctuaryService = {}

-- Circle ------------------------------------------------------------------------------------------------------
local CIRCLE_X = -84 -- studs from the Rift Gate along the lane (clear of the Blacksmith and the jump pad)
local CIRCLE_RADIUS = 6 -- the town lane is only 10 studs deep
local CIRCLE_DEPTH = -3 -- circle centre z (the lane runs z -8..2, players walk at z 0)
local CIRCLE_REACH = 6.5 -- |x| from the centre that counts as standing in it
local CIRCLE_HEIGHT = 7 -- how far above the floor still counts
local DUMMY_OFFSETS = { -3.6, 0, 3.6 } -- x from the circle centre, behind the walking plane
local DUMMY_DEPTH = -5
local DUMMY_HITS = 6 -- swings until a dummy pops
local DUMMY_RESPAWN = 3
local SWING_EVERY = 1.5
local REWARD_EVERY = 4
local CRIT_CHANCE = 0.15
-- "20% of active-run" rates: a run pays roughly this much per minute of play at the start of World 1.
local ACTIVE_DUST_PER_MIN = 100
local ACTIVE_MASTERY_PER_MIN = 150
local SANCTUARY_SHARE = 0.20
local PARTY_BONUS = 0.10 -- per other hunter in the circle

-- Offline -----------------------------------------------------------------------------------------------------
local OFFLINE_MIN_MINUTES = 15
local OFFLINE_MAX_MINUTES = 480
local OFFLINE_DUST_PER_MIN = 15
local OFFLINE_MASTERY_PER_MIN = 5
local QUERY_COOLDOWN = 1

type Dummy = { Model: Model, Cap: BasePart, Hits: number, DownUntil: number, Base: CFrame }
type Trainee = { NextSwing: number, NextReward: number, DustCarry: number, XPCarry: number }

local notifyRemote: RemoteEvent
local fxRemote: RemoteEvent
local numberRemote: RemoteEvent
local offlineRemote: RemoteEvent
local center: Vector3? = nil
local statusLabel: TextLabel? = nil
local dummies: { Dummy } = {}
local trainees: { [Player]: Trainee } = {}
local lastQuery: { [Player]: number } = {}
local rng = Random.new()

local function part(parent: Instance, props: { [string]: any }): Part
	local created = Instance.new("Part")
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	created.CanTouch = false
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(created :: any)[key] = value
	end
	created.Parent = parent
	return created
end

local function buildDummy(folder: Folder, at: Vector3): Dummy
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"
	local stem = part(model, { Name = "Stem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.2, 1.8, 1.8),
		CFrame = CFrame.new(at + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(240, 226, 196), Material = Enum.Material.SmoothPlastic })
	local cap = part(model, { Name = "Cap", Shape = Enum.PartType.Ball, Size = Vector3.new(4.2, 4.2, 4.2),
		CFrame = CFrame.new(at + Vector3.new(0, 3.6, 0)), Color = Color3.fromRGB(120, 200, 255),
		Material = Enum.Material.SmoothPlastic })
	for _, spot in { Vector3.new(-0.9, 1.3, 1.5), Vector3.new(1, 1.1, 1.4), Vector3.new(0.1, 1.9, 0.9) } do
		local dot = part(model, { Name = "Spot", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9,
			CFrame = CFrame.new(cap.Position + spot), Color = Color3.fromRGB(235, 248, 255),
			Material = Enum.Material.Neon })
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = cap
		weld.Part1 = dot
		weld.Parent = dot
	end
	for _, x in { -0.4, 0.4 } do
		part(model, { Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.35,
			CFrame = CFrame.new(stem.Position + Vector3.new(x, 0.5, 0.85)), Color = Color3.fromRGB(30, 30, 40) })
	end
	model.PrimaryPart = stem
	model.Parent = folder
	return { Model = model, Cap = cap, Hits = 0, DownUntil = 0, Base = model:GetPivot() }
end

local function buildSanctuary(): Vector3?
	local hub = TownHubService.Hub
	local gate = hub and hub.Stations.RiftGate
	if not (hub and gate) then
		return nil
	end
	local floor = gate:GetPivot().Position
	local at = Vector3.new(floor.X + CIRCLE_X, floor.Y, 0)
	local folder = Instance.new("Folder")
	folder.Name = "TrainingSanctuary"

	-- Rune circle: stacked flat discs (each a little higher and smaller) leave a neon rim and a neon inner ring, with
	-- glowing runes in the band between them.
	local rim = Color3.fromRGB(150, 110, 255)
	local stone = Color3.fromRGB(40, 30, 70)
	local discs = {
		{ Radius = CIRCLE_RADIUS + 0.4, Color = rim, Material = Enum.Material.Neon },
		{ Radius = CIRCLE_RADIUS, Color = stone, Material = Enum.Material.Slate },
		{ Radius = CIRCLE_RADIUS - 2.4, Color = rim, Material = Enum.Material.Neon },
		{ Radius = CIRCLE_RADIUS - 2.8, Color = stone, Material = Enum.Material.Slate },
	}
	for index, disc in discs do
		part(folder, { Name = "Disc" .. index, Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, disc.Radius * 2, disc.Radius * 2),
			CFrame = CFrame.new(at + Vector3.new(0, 0.08 + 0.02 * index, CIRCLE_DEPTH)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = disc.Color, Material = disc.Material })
	end
	for index = 0, 7 do
		local angle = index * math.pi / 4
		local band = CIRCLE_RADIUS - 1.2
		part(folder, { Name = "Rune", Size = Vector3.new(0.5, 0.12, 1.1),
			CFrame = CFrame.new(at + Vector3.new(math.cos(angle) * band, 0.24, CIRCLE_DEPTH + math.sin(angle) * band))
				* CFrame.Angles(0, -angle, 0),
			Color = Color3.fromRGB(200, 170, 255), Material = Enum.Material.Neon })
	end
	local glow = part(folder, { Name = "Glow", Size = Vector3.one, Transparency = 1,
		CFrame = CFrame.new(at + Vector3.new(0, 2, CIRCLE_DEPTH)) })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(160, 120, 255)
	light.Range = 16
	light.Brightness = 1.5
	light.Parent = glow
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(180, 150, 255))
	motes.Rate = 8
	motes.Lifetime = NumberRange.new(1.5, 2.5)
	motes.Speed = NumberRange.new(1, 2.5)
	motes.SpreadAngle = Vector2.new(60, 60)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Size = NumberSequence.new(0.3, 0)
	motes.LightEmission = 1
	motes.Parent = glow

	local sign = part(folder, { Name = "SignAnchor", Size = Vector3.one, Transparency = 1,
		CFrame = CFrame.new(at + Vector3.new(0, 9.5, CIRCLE_DEPTH)) })
	local gui = Instance.new("BillboardGui")
	gui.Name = "SanctuarySign"
	gui.Size = UDim2.fromOffset(300, 54)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = sign
	gui.Parent = sign
	for index, text in { "🧘 TRAINING SANCTUARY", "Stand in the circle to train" } do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, (index - 1) * 28)
		label.Size = UDim2.new(1, 0, 0, if index == 1 then 28 else 22)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = if index == 1 then 24 else 16
		label.TextColor3 = if index == 1 then Color3.fromRGB(205, 180, 255) else Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = gui
		if index == 2 then
			statusLabel = label
		end
	end

	for _, offset in DUMMY_OFFSETS do
		table.insert(dummies, buildDummy(folder, at + Vector3.new(offset, 0, DUMMY_DEPTH)))
	end
	folder.Parent = hub.Folder
	return at
end

-- Training ----------------------------------------------------------------------------------------------------

local function townPlayers(): { Player }
	local list: { Player } = {}
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("RunId") == nil then
			table.insert(list, other)
		end
	end
	return list
end

local function inCircle(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local spot = center
	if not (spot and root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) or player:GetAttribute("RunId") ~= nil then
		return nil
	end
	local offset = root.Position - spot
	if math.abs(offset.X) <= CIRCLE_REACH and offset.Y >= -1 and offset.Y <= CIRCLE_HEIGHT then
		return root
	end
	return nil
end

local function nearestDummy(position: Vector3, now: number): Dummy?
	local best: Dummy? = nil
	local bestDistance = math.huge
	for _, dummy in dummies do
		local distance = math.abs(dummy.Base.Position.X - position.X)
		if now >= dummy.DownUntil and distance < bestDistance then
			best, bestDistance = dummy, distance
		end
	end
	return best
end

local function popDummy(dummy: Dummy, now: number)
	dummy.Hits = 0
	dummy.DownUntil = now + DUMMY_RESPAWN
	for _, child in dummy.Model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Transparency = 1
		end
	end
	for _, viewer in townPlayers() do
		fxRemote:FireClient(viewer, { Kind = "Burst", Pos = dummy.Cap.Position, Radius = 3.5, Style = "Spirit", Owner = 0 })
	end
	task.delay(DUMMY_RESPAWN, function()
		for _, child in dummy.Model:GetDescendants() do
			if child:IsA("BasePart") then
				child.Transparency = 0
			end
		end
	end)
end

local function swing(player: Player, root: BasePart, profile: PlayerProfileData, now: number)
	local dummy = nearestDummy(root.Position, now)
	local weapon = WeaponConfig.Weapons[profile.EquippedWeapon]
	if not (dummy and weapon) then
		return
	end
	local attack = weapon.Attack or WeaponConfig.GenericAttack
	local facing = if dummy.Base.Position.X >= root.Position.X then 1 else -1
	local crit = rng:NextNumber() < CRIT_CHANCE
	-- A hit sized like a real one: Rift Power is weapon DPS x 20, so one swing is Power / (20 x attacks per second).
	local hit = FormulaEngine.CalculateRiftPower(profile, nil) / (20 * weapon.AttacksPerSecond) * (if crit then 1.5 else 1)
	local entry = { Pos = dummy.Cap.Position + Vector3.new(0, 2, 0), Amount = math.max(1, math.round(hit)), Crit = crit,
		Kind = "Hit", Owner = player.UserId }
	for _, viewer in townPlayers() do
		fxRemote:FireClient(viewer, { Kind = "Swing", Owner = player.UserId, Weapon = weapon.Id, Style = attack.Style,
			Pos = root.Position, Facing = facing, Range = math.min(attack.Range, 12), Height = attack.Height })
		numberRemote:FireClient(viewer, { entry })
	end
	-- A little squash on the cap.
	dummy.Model:PivotTo(dummy.Base * CFrame.Angles(0, 0, math.rad(-10 * facing)))
	task.delay(0.15, function()
		if dummy.Model.Parent then
			dummy.Model:PivotTo(dummy.Base)
		end
	end)
	dummy.Hits += 1
	if dummy.Hits >= DUMMY_HITS then
		popDummy(dummy, now)
	end
end

local function reward(player: Player, trainee: Trainee, profile: PlayerProfileData, others: number)
	local mult = SANCTUARY_SHARE * (1 + PARTY_BONUS * others) * (REWARD_EVERY / 60)
	local eco = FormulaEngine.GetRebirthInfo(profile.RebirthTier).EcoMult
	trainee.DustCarry += ACTIVE_DUST_PER_MIN * mult * eco
	trainee.XPCarry += ACTIVE_MASTERY_PER_MIN * mult
	local dust = math.floor(trainee.DustCarry)
	local xp = math.floor(trainee.XPCarry)
	trainee.DustCarry -= dust
	trainee.XPCarry -= xp
	if dust > 0 then
		PlayerDataService.Mutate(player, function(data)
			data.RiftDust += dust
		end)
		PlayerDataService.BumpStat(player, "SanctuaryDust", dust)
		local dummy = center and nearestDummy(center, 0)
		if dummy then
			fxRemote:FireClient(player, { Kind = "DustOrbs", Pos = dummy.Cap.Position, Amount = dust, Count = math.clamp(dust, 1, 3) })
		end
	end
	if xp > 0 then
		MasteryService.AwardXP(player, xp)
	end
end

local function step(now: number)
	local training: { [Player]: BasePart } = {}
	local count = 0
	for _, player in Players:GetPlayers() do
		local root = inCircle(player)
		if root then
			training[player] = root
			count += 1
		end
	end
	for player in trainees do
		if not training[player] then
			trainees[player] = nil
		end
	end
	for player, root in training do
		local profile = PlayerDataService.Get(player)
		if not profile then
			continue
		end
		local trainee = trainees[player]
		if not trainee then
			trainee = { NextSwing = now + 0.4, NextReward = now + REWARD_EVERY, DustCarry = 0, XPCarry = 0 }
			trainees[player] = trainee
			notifyRemote:FireClient(player, "🧘 Training! Your hunter earns Rift Dust & Mastery XP while you stand here.")
		end
		if now >= trainee.NextSwing then
			trainee.NextSwing = now + SWING_EVERY
			swing(player, root, profile, now)
		end
		if now >= trainee.NextReward then
			trainee.NextReward = now + REWARD_EVERY
			reward(player, trainee, profile, count - 1)
		end
	end
	local status = statusLabel
	if status then
		status.Text = if count == 0 then "Stand in the circle to train"
			elseif count == 1 then "1 hunter training"
			else ("%d hunters training · +%d%% each"):format(count, math.round(PARTY_BONUS * (count - 1) * 100))
	end
end

-- Offline training ----------------------------------------------------------------------------------------------

-- Folds time away since the last save into the pending OfflineTraining (capped at 8 hours in total).
local function accrueOffline(profile: PlayerProfileData)
	local last = profile.LastSeenAt
	if last <= 0 then
		return
	end
	local away = math.floor((os.time() - last) / 60)
	if away < OFFLINE_MIN_MINUTES then
		return
	end
	local pending = profile.OfflineTraining
	local minutes = math.min(OFFLINE_MAX_MINUTES, pending.Minutes + away)
	local eco = FormulaEngine.GetRebirthInfo(profile.RebirthTier).EcoMult
	profile.OfflineTraining = {
		Minutes = minutes,
		Dust = math.floor(OFFLINE_DUST_PER_MIN * minutes * eco),
		Mastery = OFFLINE_MASTERY_PER_MIN * minutes,
	}
	profile.LastSeenAt = os.time() -- accrued; a crash before the next save must not count this stretch twice
end

local function showOffline(player: Player)
	local profile = PlayerDataService.Get(player)
	local pending = profile and profile.OfflineTraining
	if not (profile and pending) or pending.Minutes <= 0 then
		return
	end
	local weapon = WeaponConfig.Weapons[profile.EquippedWeapon]
	offlineRemote:FireClient(player, {
		Kind = "Show", Minutes = pending.Minutes, MaxMinutes = OFFLINE_MAX_MINUTES, Dust = pending.Dust,
		Mastery = pending.Mastery, Weapon = if weapon then weapon.Name else profile.EquippedWeapon,
		Icon = if weapon then weapon.Icon else "⚔️",
	})
end

-- Pays out the pending offline training x `mult` (2 = the OfflineDouble Robux product). False if nothing pending.
function SanctuaryService.ClaimOffline(player: Player, mult: number): boolean
	local profile = PlayerDataService.Get(player)
	local pending = profile and profile.OfflineTraining
	if not (profile and pending) or pending.Minutes <= 0 then
		return false
	end
	local dust = pending.Dust * mult
	local mastery = pending.Mastery * mult
	PlayerDataService.Mutate(player, function(data)
		data.RiftDust += dust
		data.OfflineTraining = { Minutes = 0, Dust = 0, Mastery = 0 }
	end)
	MasteryService.AwardXP(player, mastery)
	offlineRemote:FireClient(player, { Kind = "Closed", Dust = dust, Mastery = mastery, Mult = mult })
	notifyRemote:FireClient(player, ("🌙 Offline training claimed: +%d Rift Dust, +%d Mastery XP%s"):format(dust, mastery,
		if mult > 1 then " (2x!)" else ""))
	return true
end

function SanctuaryService.HasOffline(player: Player): boolean
	local profile = PlayerDataService.Get(player)
	return profile ~= nil and profile.OfflineTraining.Minutes > 0
end

-- Studio test hook (DevCommandsService "Offline"): pretend the player left `minutes` ago and re-run the accrual.
-- minutes <= 0 clears anything pending without paying it (restoring a test profile).
function SanctuaryService.DevAway(player: Player, minutes: number): number
	local profile = PlayerDataService.Get(player)
	if not profile then
		return 0
	end
	if minutes <= 0 then
		profile.OfflineTraining = { Minutes = 0, Dust = 0, Mastery = 0 }
		offlineRemote:FireClient(player, { Kind = "Closed", Dust = 0, Mastery = 0, Mult = 1 })
		return 0
	end
	profile.LastSeenAt = os.time() - math.floor(minutes * 60)
	accrueOffline(profile)
	showOffline(player)
	return profile.OfflineTraining.Minutes
end

function SanctuaryService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")
	fxRemote = Remotes.GetEvent("CombatFx")
	numberRemote = Remotes.GetEvent("DamageNumber")
	offlineRemote = Remotes.GetEvent("OfflineTraining")
	center = buildSanctuary()

	PlayerDataService.ProfileLoaded:Connect(function(_player: Player, profile: PlayerProfileData)
		accrueOffline(profile)
	end)
	for _, player in Players:GetPlayers() do
		local profile = PlayerDataService.Get(player)
		if profile then
			accrueOffline(profile)
		end
	end
	Remotes.GetEvent("ClaimOfflineTraining").OnServerEvent:Connect(function(player: Player, payload: any)
		local now = os.clock()
		if type(payload) ~= "table" or now - (lastQuery[player] or 0) < QUERY_COOLDOWN then
			return
		end
		lastQuery[player] = now
		if payload.Action == "Query" then
			if PlayerDataService.Wait(player) then
				showOffline(player)
			end
		elseif payload.Action == "Claim" then
			SanctuaryService.ClaimOffline(player, 1)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		trainees[player] = nil
		lastQuery[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function(): any
				step(os.clock())
				return nil
			end)
			if not ok then
				warn("[SanctuaryService] tick failed: " .. tostring(err))
			end
		end
	end)
end

return SanctuaryService
