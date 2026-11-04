--!strict
-- ServerScriptService/Server/Services/OnboardingService.luau
-- "First 60 Seconds" onboarding in Haven Outpost (game.md 3.1 Option A / 3.3):
--   * A Starter Weapon Rack beside the Central Rift Gate: three pedestals (Greatsword, Daggers, Staff) with a floating
--     weapon, a name + playstyle tag and a one-press Equip prompt. Everyone can use it; it's built once.
--   * Brand-new hunters (OnboardingConfig.IsNewHunter: no room cleared yet, Lv 1) land in front of the rack, a few
--     steps from the gate, instead of the far town spawn — on every spawn and every return to town until they clear
--     their first room. Their NewHunter attribute makes the client draw the golden "ENTER THE RIFT" guide.
--   * The TownTier attribute (OnboardingConfig.TierFor) tells WaypointController which stations to highlight.
--     Walking up to a station above your tier toasts its unlock hint once per session (the gate is visual only:
--     the station still opens).
-- Both attributes follow every profile replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local OnboardingConfig = require(Shared:WaitForChild("OnboardingConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local TownHubService = require(script.Parent:WaitForChild("TownHubService"))
local WeaponHoldService = require(script.Parent:WaitForChild("WeaponHoldService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

local OnboardingService = {}

-- { weapon, playstyle tag, x offset from the Rift Gate }. The new-hunter spawn faces the middle pedestal.
local RACK = {
	{ Weapon = "Greatsword", Tag = "Heavy AoE", X = -22 },
	{ Weapon = "Daggers", Tag = "Fast Crit", X = -16 },
	{ Weapon = "Staff", Tag = "Arcane Nova", X = -10 },
}
local RACK_DEPTH = -8 -- behind the lane, clear of the torches at Z = -4
local SPAWN_X = -16
local PEDESTAL_HEIGHT = 2.6
local WEAPON_LENGTH = 4.2
local EQUIP_COOLDOWN = 0.5
local HINT_DISTANCE = 16 -- studs from a locked station's centre (along the lane) that trigger its hint
local HINT_FLOOR = 8 -- ...and vertically: same tier of the town only (stations stack on upper platforms)
local HINT_INTERVAL = 0.5

local notifyRemote: RemoteEvent
local spawnCFrame: CFrame? = nil
local lastEquip: { [Player]: number } = {}
local hinted: { [Player]: { [string]: boolean } } = {}

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

local function tagBillboard(adornee: BasePart, info: WeaponConfig.WeaponInfo, tag: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RackLabel"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(150, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	for index, text in { ("%s %s"):format(info.Icon, info.Name), tag } do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, (index - 1) * 21)
		label.Size = UDim2.new(1, 0, 0, if index == 1 then 21 else 18)
		label.Font = Enum.Font.FredokaOne
		label.TextSize = if index == 1 then 18 else 14
		label.TextColor3 = if index == 1 then Color3.new(1, 1, 1) else info.Accent
		label.TextStrokeTransparency = 0
		label.Text = text
		label.Parent = gui
	end
	gui.Parent = adornee
end

local function buildPedestal(folder: Folder, info: WeaponConfig.WeaponInfo, tag: string, floor: Vector3)
	local model = Instance.new("Model")
	model.Name = "Starter_" .. info.Id
	local base = part(model, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(PEDESTAL_HEIGHT, 4.4, 4.4),
		CFrame = CFrame.new(floor + Vector3.new(0, PEDESTAL_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(62, 58, 78), Material = Enum.Material.Slate })
	part(model, { Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4.8, 4.8),
		CFrame = CFrame.new(floor + Vector3.new(0, PEDESTAL_HEIGHT, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = info.Accent, Material = Enum.Material.Neon })
	local anchor = part(model, { Name = "Anchor", Size = Vector3.new(1, 1, 1), Transparency = 1,
		CFrame = CFrame.new(floor + Vector3.new(0, PEDESTAL_HEIGHT + 2.4, 0)) })
	model.PrimaryPart = base

	local display = WeaponHoldService.CreateDisplayModel(info.Id, WEAPON_LENGTH)
	if display then
		-- Diagonal, flat side to the camera, like a weapon on a display stand.
		display:PivotTo(CFrame.new(anchor.Position) * CFrame.Angles(0, 0, math.rad(45)))
		display.Parent = model
	end
	local light = Instance.new("PointLight")
	light.Color = info.Accent
	light.Range = 10
	light.Brightness = 1.6
	light.Parent = anchor
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(info.Accent)
	sparkles.Rate = 6
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Speed = NumberRange.new(0.6, 1.4)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new(0.35, 0)
	sparkles.LightEmission = 1
	sparkles.Parent = anchor
	tagBillboard(anchor, info, tag)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EquipPrompt"
	prompt.ActionText = "Equip"
	prompt.ObjectText = ("%s — %s"):format(info.Name, tag)
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 11 -- the rack stands behind the lane
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastEquip[player] or 0) < EQUIP_COOLDOWN then
			return
		end
		lastEquip[player] = now
		InventoryService.EquipWeapon(player, info.Id)
	end)
	model.Parent = folder
end

local function buildRack(): CFrame?
	local hub = TownHubService.Hub
	local gate = hub and hub.Stations.RiftGate
	if not (hub and gate) then
		return nil
	end
	local gateFloor = gate:GetPivot().Position
	local folder = Instance.new("Folder")
	folder.Name = "StarterRack"
	for _, entry in RACK do
		local info = WeaponConfig.Weapons[entry.Weapon]
		if info then
			buildPedestal(folder, info, entry.Tag, Vector3.new(gateFloor.X + entry.X, gateFloor.Y, RACK_DEPTH))
		end
	end
	folder.Parent = hub.Folder
	-- Root height above the floor, facing the gate (+X) along the lane.
	local at = Vector3.new(gateFloor.X + SPAWN_X, gateFloor.Y + 3, 0)
	return CFrame.lookAt(at, at + Vector3.new(1, 0, 0))
end

local function sync(player: Player, profile: PlayerProfileData)
	player:SetAttribute("TownTier", OnboardingConfig.TierFor(profile))
	player:SetAttribute("NewHunter", if OnboardingConfig.IsNewHunter(profile) then true else nil)
end

-- New hunters always land by the rack in town (spawn, death respawn, extraction).
local function placeNewHunter(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (spawnCFrame and character and root and root:IsA("BasePart")) or player:GetAttribute("NewHunter") ~= true
		or player:GetAttribute("RunId") ~= nil then
		return
	end
	character:PivotTo(spawnCFrame)
	root.AssemblyLinearVelocity = Vector3.zero
end

-- One toast per locked station per session when the player walks up to it in town.
local function hintLockedStations()
	local hub = TownHubService.Hub
	if not hub then
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local tier = tonumber(player:GetAttribute("TownTier"))
		if not (root and root:IsA("BasePart") and tier) or player:GetAttribute("RunId") ~= nil then
			continue
		end
		local seen = hinted[player] or {}
		hinted[player] = seen
		for stationKey, model in hub.Stations do
			local need = OnboardingConfig.StationTier[stationKey] or 1
			if need <= tier or seen[stationKey] then
				continue
			end
			local offset = model:GetPivot().Position - root.Position
			if math.abs(offset.X) <= HINT_DISTANCE and math.abs(offset.Y) <= HINT_FLOOR then
				seen[stationKey] = true
				local look = model:GetAttribute("WaypointName")
				notifyRemote:FireClient(player, ("%s — %s"):format(if type(look) == "string" then look else stationKey,
					OnboardingConfig.Hint[need] or "🔒 Locked"))
			end
		end
	end
end

local welcomed: { [Player]: boolean } = {}

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		local profile = PlayerDataService.Wait(player)
		if not profile or player.Character ~= character then
			return
		end
		sync(player, profile)
		task.wait(0.1) -- after Roblox's own spawn placement
		placeNewHunter(player)
		if player:GetAttribute("NewHunter") == true and not welcomed[player] then
			welcomed[player] = true
			notifyRemote:FireClient(player, "⚔️ Pick a starter weapon, then jump into the Rift Gate!")
		end
	end)
	player:GetAttributeChangedSignal("RunId"):Connect(function()
		if player:GetAttribute("RunId") == nil then
			task.wait(0.2) -- RunManagerService moves living players to the town spawn first
			placeNewHunter(player)
		end
	end)
end

function OnboardingService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")
	spawnCFrame = buildRack()

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	PlayerDataService.ProfileLoaded:Connect(function(player: Player, profile: PlayerProfileData)
		sync(player, profile)
	end)
	PlayerDataService.Replicated:Connect(function(player: Player)
		local profile = PlayerDataService.Get(player)
		if profile then
			sync(player, profile)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastEquip[player] = nil
		welcomed[player] = nil
		hinted[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(HINT_INTERVAL)
			hintLockedStations()
		end
	end)
end

return OnboardingService
