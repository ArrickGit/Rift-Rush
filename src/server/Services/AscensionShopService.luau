--!strict
-- ServerScriptService/Server/Services/AscensionShopService.luau
-- Spark Sanctum (Section 23): validates and applies Rebirth Spark purchases and free respecs. Node effects are read
-- live from profile.AscensionNodes by the services that use them (RunManagerService, CombatService,
-- CharacterService), so buying a node only has to update the profile and refresh mobility.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AscensionShopConfig = require(Shared:WaitForChild("AscensionShopConfig"))
local Physics25D = require(Shared:WaitForChild("Physics25D"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local CharacterService = require(script.Parent:WaitForChild("CharacterService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

export type NodeState = {
	Id: string,
	Level: number,
	MaxLevel: number,
	NextCost: number?, -- nil when maxed
	Unlocked: boolean,
}

local AscensionShopService = {}

-- The two infinite sinks are for Rebirth XI+ (Section 23, Tier 4 table), one tier after the rest of Tier 4.
local INFINITE_UNLOCK_REBIRTH = 11
local REQUEST_COOLDOWN = 0.2

local notifyRemote: RemoteEvent
local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function throttled(player: Player): boolean
	local now = os.clock()
	if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
		return true
	end
	lastRequest[player] = now
	return false
end

local function isNodeUnlocked(nodeId: string, tier: number, rebirthTier: number): boolean
	if AscensionShopConfig.Nodes[nodeId].FlatCost then
		return rebirthTier >= INFINITE_UNLOCK_REBIRTH
	end
	return AscensionShopConfig.IsTierUnlocked(tier, rebirthTier)
end

function AscensionShopService.GetShopState(player: Player): { NodeState }?
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	local states: { NodeState } = {}
	for _, nodeId in AscensionShopConfig.Order do
		local node = AscensionShopConfig.Nodes[nodeId]
		local level = profile.AscensionNodes[nodeId] or 0
		table.insert(states, {
			Id = nodeId,
			Level = level,
			MaxLevel = node.MaxLevel,
			NextCost = AscensionShopConfig.GetNextCost(nodeId, level),
			Unlocked = isNodeUnlocked(nodeId, node.Tier, profile.RebirthTier),
		})
	end
	return states
end

-- Buys one level of `nodeId`. Returns (success, message).
function AscensionShopService.Purchase(player: Player, nodeId: string): (boolean, string)
	local profile = PlayerDataService.Get(player)
	local node = AscensionShopConfig.GetNode(nodeId)
	if not profile or not node then
		return false, "Unknown upgrade"
	end
	if not isNodeUnlocked(nodeId, node.Tier, profile.RebirthTier) then
		return false, node.Name .. " is locked: rebirth further to unlock it"
	end
	local level = profile.AscensionNodes[nodeId] or 0
	local cost = AscensionShopConfig.GetNextCost(nodeId, level)
	if not cost then
		return false, node.Name .. " is already maxed"
	end
	if profile.RebirthSparksAvailable < cost then
		return false, ("Need %d Rebirth Sparks (you have %d)"):format(cost, profile.RebirthSparksAvailable)
	end

	PlayerDataService.Mutate(player, function(data)
		data.RebirthSparksAvailable -= cost
		data.AscensionNodes[nodeId] = level + 1
	end)
	if nodeId == Physics25D.SKYWALKER_NODE_ID then
		CharacterService.RefreshMobility(player)
	end
	notify(player, ("%s upgraded to Lv. %d"):format(node.Name, level + 1))
	return true, "Purchased"
end

-- Refunds every Spark spent and clears all nodes. Town only, so a mid-run build never changes under the player.
function AscensionShopService.Respec(player: Player): (boolean, string)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return false, "Your profile is still loading"
	end
	if RunManagerService.GetRunOf(player) then
		return false, "Return to town before you respec"
	end
	local refund = AscensionShopConfig.GetTotalSpent(profile.AscensionNodes)
	if refund <= 0 then
		return false, "Nothing to refund"
	end
	PlayerDataService.Mutate(player, function(data)
		data.AscensionNodes = {}
		-- Never refund more than was ever earned (guards against hand-edited or corrupted saves).
		data.RebirthSparksAvailable = math.min(data.RebirthSparksTotalEarned, data.RebirthSparksAvailable + refund)
	end)
	CharacterService.RefreshMobility(player)
	InventoryService.TrimLoadout(player) -- Legion Commander / Twin Relic Vessel slots may be gone
	notify(player, ("Respec complete: %d Rebirth Sparks refunded"):format(refund))
	return true, "Respecced"
end

function AscensionShopService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")

	Remotes.GetEvent("AscensionPurchase").OnServerEvent:Connect(function(player: Player, nodeId: any)
		if type(nodeId) ~= "string" or #nodeId > 32 or throttled(player) then
			return
		end
		local success, message = AscensionShopService.Purchase(player, nodeId)
		if not success then
			notify(player, message)
		end
	end)

	Remotes.GetEvent("AscensionRespec").OnServerEvent:Connect(function(player: Player)
		if throttled(player) then
			return
		end
		local success, message = AscensionShopService.Respec(player)
		if not success then
			notify(player, message)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return AscensionShopService
