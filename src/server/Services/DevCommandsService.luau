--!strict
-- ServerScriptService/Server/Services/DevCommandsService.luau
-- Studio-only test hooks (never created in a live server). Call from the Studio command bar / MCP on the server:
--   game.ServerStorage.RiftDev:Invoke({ Cmd = "Grant", Dust = 5000, Cores = 20, Shards = 50 })
--   { Cmd = "Equip", Weapon = "Bow" }            unlocks + equips, even mid-run
--   { Cmd = "Relic", Id = "REL_04", Stars = 3 }    adds to the collection and the current run
--   { Cmd = "Mastery", Weapon = "Bow", Level = 10 }
-- The first player in the server is the target unless Player = <name> is given.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RelicService = require(script.Parent:WaitForChild("RelicService"))
local WeaponHoldService = require(script.Parent:WaitForChild("WeaponHoldService"))

local DevCommandsService = {}

local function run(request: any): string
	if type(request) ~= "table" then
		return "bad request"
	end
	local player = if type(request.Player) == "string" then Players:FindFirstChild(request.Player) else Players:GetPlayers()[1]
	if not (player and player:IsA("Player")) then
		return "no player"
	end
	local profile = PlayerDataService.Get(player)
	if not profile then
		return "profile not loaded"
	end
	local cmd = request.Cmd
	if cmd == "Grant" then
		PlayerDataService.Mutate(player, function(data)
			data.RiftDust += tonumber(request.Dust) or 0
			data.BossCores += tonumber(request.Cores) or 0
			data.RelicShards += tonumber(request.Shards) or 0
			data.RebirthSparksAvailable += tonumber(request.Sparks) or 0
			data.AnchorTokens += tonumber(request.Tokens) or 0
		end)
	elseif cmd == "Equip" and type(request.Weapon) == "string" then
		PlayerDataService.Mutate(player, function(data)
			data.UnlockedWeapons[request.Weapon] = true
			data.WeaponMastery[request.Weapon] = data.WeaponMastery[request.Weapon] or { Level = 1, XP = 0, ParagonRank = 0 }
			data.EquippedWeapon = request.Weapon
		end)
		WeaponHoldService.Refresh(player)
	elseif cmd == "Relic" and type(request.Id) == "string" then
		local stars = tonumber(request.Stars) or 1
		PlayerDataService.Mutate(player, function(data)
			data.RelicStars[request.Id] = { Stars = stars, PityCount = 0 }
		end)
		RelicService.DevActivate(player, request.Id, stars)
	elseif cmd == "Mastery" and type(request.Weapon) == "string" then
		PlayerDataService.Mutate(player, function(data)
			data.WeaponMastery[request.Weapon] = { Level = tonumber(request.Level) or 1, XP = 0, ParagonRank = tonumber(request.Paragon) or 0 }
		end)
		WeaponHoldService.Refresh(player)
	else
		return "unknown command"
	end
	return "ok"
end

function DevCommandsService.Init()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "RiftDev"
	hook.OnInvoke = run
	hook.Parent = ServerStorage
end

return DevCommandsService
