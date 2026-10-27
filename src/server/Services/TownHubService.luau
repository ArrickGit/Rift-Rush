--!strict
-- ServerScriptService/Server/Services/TownHubService.luau
-- Builds Haven Outpost (RoomBuilderService.BuildTownHub) and wires each station's ProximityPrompt (Section 5.1).
-- Stations with a UIController panel (PANEL_STATIONS) fire OpenStation { Station, Data }; the panel then acts through
-- the normal validated remotes (StartRun, RequestRebirth, AscensionPurchase, RequestPurchase). Panels refresh their
-- Data through the GetStationData RemoteFunction. Stations without a panel yet just say so.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local AscensionShopService = require(script.Parent:WaitForChild("AscensionShopService"))
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
	prompt.MaxActivationDistance = 12
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
	for stationKey, model in hub.Stations do
		wireStation(stationKey, model)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		lastDataRequest[player] = nil
	end)
end

return TownHubService
