--!strict
-- ServerScriptService/Server/Services/TownHubService.luau
-- Builds Haven Outpost (RoomBuilderService.BuildTownHub) and wires each station's ProximityPrompt (Section 5.1).
-- Every station fires OpenStation { Station, Data } to open its UIController panel; the panel then acts through the
-- normal validated remotes (StartRun, RequestRebirth, AscensionPurchase, RequestPurchase, LoadoutAction, StarForce,
-- ClaimQuest). Panels refresh their Data through the GetStationData RemoteFunction (nil for panels that only read
-- the replicated profile: Blacksmith, Legion Hall, Star-Forge).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local ModelNormalizer = require(Shared:WaitForChild("ModelNormalizer"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local AscensionShopService = require(script.Parent:WaitForChild("AscensionShopService"))
local LeaderboardService = require(script.Parent:WaitForChild("LeaderboardService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))
local RebirthService = require(script.Parent:WaitForChild("RebirthService"))
local RoomBuilderService = require(script.Parent:WaitForChild("RoomBuilderService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))

type TownHub = RoomBuilderService.TownHub

local TownHubService = {}

-- Town sits on the baseplate around the world origin; runs are built far away (RunManagerService.RUN_ORIGIN).
local TOWN_ORIGIN = Vector3.new(-192, 0, 0)
local PROMPT_COOLDOWN = 0.5
local DATA_COOLDOWN = 0.25

local PANEL_STATIONS: { [string]: boolean } = {
	RiftGate = true,
	AscensionPedestal = true,
	SparkSanctum = true,
	RiftShrine = true,
	Blacksmith = true,
	LegionHall = true,
	StarForge = true,
	QuestBoard = true,
	HallOfChampions = true,
}

local ACTION_TEXT: { [string]: string } = {
	RiftGate = "Quick Start Run",
	AscensionPedestal = "Rift Rebirth",
	SparkSanctum = "Ascension Shop",
	Blacksmith = "Weapons",
	LegionHall = "Mastery & Link Skills",
	StarForge = "Star-Force Relics",
	QuestBoard = "Quests",
	HallOfChampions = "Leaderboards",
	RiftShrine = "Trigger Rift Surge",
}

-- Props from ReplicatedStorage.Assets.Decor scattered on the ground tier: { name, x offset from the Rift Gate,
-- depth behind the lane (studs), height in studs }. Stations keep a clear 12-stud margin so nothing hides them.
local DECOR: { { Name: string, X: number, Depth: number, Height: number } } = {
	{ Name = "Cabinet", X = -150, Depth = 7, Height = 6 },
	{ Name = "Barrel", X = -140, Depth = 5, Height = 4 },
	{ Name = "Crate_Wooden", X = -137, Depth = 6, Height = 3.2 },
	{ Name = "Torch_Metal", X = -104, Depth = 4, Height = 7 },
	{ Name = "Stall_Cart_Empty", X = -96, Depth = 8, Height = 8 },
	{ Name = "Bench", X = -80, Depth = 5, Height = 3 },
	{ Name = "Vase_2", X = -64, Depth = 4, Height = 3.5 },
	{ Name = "Workbench", X = -46, Depth = 7, Height = 4 },
	{ Name = "Barrel_Apples", X = -34, Depth = 5, Height = 4 },
	{ Name = "FarmCrate_Apple", X = -29, Depth = 6, Height = 3 },
	{ Name = "Torch_Metal", X = -20, Depth = 4, Height = 7 },
	{ Name = "Torch_Metal", X = 20, Depth = 4, Height = 7 },
	{ Name = "Table_Large", X = 34, Depth = 7, Height = 3.4 },
	{ Name = "Stool", X = 42, Depth = 5, Height = 2.2 },
	{ Name = "Pot_1", X = 52, Depth = 4, Height = 3 },
	{ Name = "Peg_Rack", X = 62, Depth = 7, Height = 5 },
	{ Name = "Chest_Wood", X = 98, Depth = 5, Height = 3 },
	{ Name = "Bucket_Wooden_1", X = 106, Depth = 4, Height = 2.6 },
	{ Name = "Dummy", X = 112, Depth = 6, Height = 7 },
	{ Name = "Vase_4", X = 144, Depth = 4, Height = 3.5 },
	{ Name = "Crate_Metal", X = 150, Depth = 6, Height = 3.4 },
	{ Name = "Cabinet", X = 162, Depth = 7, Height = 6 },
}

local openStationRemote: RemoteEvent
local notifyRemote: RemoteEvent
local lastUse: { [Player]: number } = {}
local lastDataRequest: { [Player]: number } = {}

TownHubService.Hub = nil :: TownHub?

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function stationData(player: Player, stationKey: string): any
	if stationKey == "AscensionPedestal" then
		return RebirthService.GetPreview(player)
	elseif stationKey == "SparkSanctum" then
		return AscensionShopService.GetShopState(player)
	elseif stationKey == "QuestBoard" then
		return QuestService.GetBoard(player)
	elseif stationKey == "HallOfChampions" then
		return LeaderboardService.GetBoards(player)
	end
	return nil
end

local function wireStation(stationKey: string, model: Model)
	local anchor = model.PrimaryPart
	if not anchor then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StationPrompt"
	local look = AssetRegistry.TownStations[stationKey]
	prompt.ObjectText = if look then look.Name else stationKey
	prompt.ActionText = ACTION_TEXT[stationKey] or "Open"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18 -- oversized landmarks: trigger comfortably from the front of the dais
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastUse[player] or 0) < PROMPT_COOLDOWN then
			return
		end
		lastUse[player] = now
		if RunManagerService.GetRunOf(player) then
			return -- the town is far from runs, but never act on a stale prompt mid-run
		end
		if PANEL_STATIONS[stationKey] then
			openStationRemote:FireClient(player, { Station = stationKey, Data = stationData(player, stationKey) })
		else
			notify(player, (if look then look.Name else stationKey) .. " opens in a later update")
		end
	end)
end

-- Anchored, non-colliding set dressing standing on the same ground as the Rift Gate, behind the 2.5D lane.
local function placeDecor(hub: TownHub)
	local gate = hub.Stations.RiftGate
	local decorAssets = ReplicatedStorage:FindFirstChild("Assets")
	local decorFolder = if decorAssets then decorAssets:FindFirstChild("Decor") else nil
	if not (gate and decorFolder) then
		return
	end
	local origin = gate:GetPivot().Position
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	folder.Parent = hub.Folder
	for _, entry in DECOR do
		local prefab = decorFolder:FindFirstChild(entry.Name)
		if not (prefab and prefab:IsA("Model")) then
			continue
		end
		local model = ModelNormalizer.SanitizeAndNormalize(prefab:Clone(), Vector3.new(entry.Height, entry.Height, entry.Height))
		local center, size = model:GetBoundingBox()
		local want = Vector3.new(origin.X + entry.X, origin.Y + size.Y / 2, origin.Z - entry.Depth)
		model:PivotTo(model:GetPivot() + (want - center.Position))
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
		model.Parent = folder
	end
end

function TownHubService.Init()
	Remotes.Init()
	openStationRemote = Remotes.GetEvent("OpenStation")
	notifyRemote = Remotes.GetEvent("Notify")

	Remotes.GetFunction("GetStationData").OnServerInvoke = function(player: Player, stationKey: any): any
		local now = os.clock()
		if type(stationKey) ~= "string" or not PANEL_STATIONS[stationKey] or now - (lastDataRequest[player] or 0) < DATA_COOLDOWN then
			return nil
		end
		lastDataRequest[player] = now
		return stationData(player, stationKey)
	end

	-- The Town Hub and every room bring their own ground and TownSpawn; Studio's template Baseplate and
	-- SpawnLocation would only show as stray slabs (and players could spawn inside the town floor).
	for _, name in { "Baseplate", "SpawnLocation" } do
		local leftover = Workspace:FindFirstChild(name)
		if leftover and leftover:IsA("BasePart") then
			leftover:Destroy()
		end
	end
	RoomBuilderService.SetupSky()

	local existing = Workspace:FindFirstChild("TownHub")
	if existing then
		existing:Destroy()
	end
	local hub = RoomBuilderService.BuildTownHub(TOWN_ORIGIN, Workspace)
	TownHubService.Hub = hub
	placeDecor(hub)
	for stationKey, model in hub.Stations do
		wireStation(stationKey, model)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		lastDataRequest[player] = nil
	end)
end

return TownHubService
