--!strict
-- ServerScriptService/Server — bootstrap. Each build step adds its services to this list.

local Services = script:WaitForChild("Services")

local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local CharacterService = require(Services:WaitForChild("CharacterService"))
local QuestService = require(Services:WaitForChild("QuestService"))
local MasteryService = require(Services:WaitForChild("MasteryService"))
local RunManagerService = require(Services:WaitForChild("RunManagerService"))
local RelicService = require(Services:WaitForChild("RelicService"))
local CombatService = require(Services:WaitForChild("CombatService"))
local HazardService = require(Services:WaitForChild("HazardService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local AscensionShopService = require(Services:WaitForChild("AscensionShopService"))
local MonetizationService = require(Services:WaitForChild("MonetizationService"))
local WeaponHoldService = require(Services:WaitForChild("WeaponHoldService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))
local LeaderboardService = require(Services:WaitForChild("LeaderboardService"))
local FlexBadgeService = require(Services:WaitForChild("FlexBadgeService"))
local TownHubService = require(Services:WaitForChild("TownHubService"))
local DevCommandsService = require(Services:WaitForChild("DevCommandsService"))

PlayerDataService.Init()
CharacterService.Init()
QuestService.Init()
MasteryService.Init()
RunManagerService.Init() -- registers its pre-release pouch settle with PlayerDataService
RelicService.Init() -- relic drops / run relics / Star-Force
CombatService.Init() -- also starts EnemyAIService
HazardService.Init() -- Jump Quest acid flood damage
RebirthService.Init()
AscensionShopService.Init()
MonetizationService.Init() -- the only script that sets MarketplaceService.ProcessReceipt
WeaponHoldService.Init() -- equipped weapon welded into every character's hand
InventoryService.Init() -- Blacksmith / loadout actions
LeaderboardService.Init()
FlexBadgeService.Init() -- overhead Rebirth / title / best-room badge in Haven Outpost
TownHubService.Init() -- builds Haven Outpost and its TownSpawn
DevCommandsService.Init() -- Studio only: ServerStorage.RiftDev test hooks

print("[RiftRush] Server started")
