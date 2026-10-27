--!strict
-- ServerScriptService/Server — bootstrap. Each build step adds its services to this list.

local Services = script:WaitForChild("Services")

local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local CharacterService = require(Services:WaitForChild("CharacterService"))
local RunManagerService = require(Services:WaitForChild("RunManagerService"))
local CombatService = require(Services:WaitForChild("CombatService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local AscensionShopService = require(Services:WaitForChild("AscensionShopService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))
local TownHubService = require(Services:WaitForChild("TownHubService"))

PlayerDataService.Init()
CharacterService.Init()
RunManagerService.Init()
CombatService.Init() -- also starts EnemyAIService
RebirthService.Init()
AscensionShopService.Init()
MonetizationService.Init() -- the only script that sets MarketplaceService.ProcessReceipt
TownHubService.Init() -- builds Haven Outpost and its TownSpawn

print("[RiftRush] Server started")
