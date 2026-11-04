--!strict
-- ServerScriptService/Server/Services/DevCommandsService.luau
-- Studio-only test hooks (never created in a live server). Call from the Studio command bar / MCP on the server:
--   game.ServerStorage.RiftDev:Invoke({ Cmd = "Grant", Dust = 5000, Cores = 20, Shards = 50 })
--   { Cmd = "Equip", Weapon = "Bow" }            unlocks + equips, even mid-run
--   { Cmd = "Relic", Id = "REL_04", Stars = 3 }    adds to the collection and the current run
--   { Cmd = "Mastery", Weapon = "Bow", Level = 10 }
--   { Cmd = "GiveUpgrade", Id = "Gigantism" }      adds one stack of a run card (must be inside a run)
--   { Cmd = "StartRun", World = 1, Corruption = 0 } solo run, as if through the Rift Gate
--   { Cmd = "Reforge", Weapon = "Bow", Tier = "Mythic" } sets a weapon's reforge tier directly (Tier = nil clears it)
--   { Cmd = "SetProfile", Level = 1, Stats = { RoomsCleared = 0 } } returns the previous values as JSON
--   { Cmd = "Ascension", Id = "AS_T1_03", Level = 3 } sets a node level, returns the previous one
--   { Cmd = "Offline", Minutes = 200 }             pretend the player was away; shows the offline training card
-- The first player in the server is the target unless Player = <name> is given.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CombatService = require(script.Parent:WaitForChild("CombatService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RelicService = require(script.Parent:WaitForChild("RelicService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))
local SanctuaryService = require(script.Parent:WaitForChild("SanctuaryService"))
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
	elseif cmd == "GiveUpgrade" and type(request.Id) == "string" then
		if not CombatService.GiveUpgrade(player, request.Id) then
			return "not in a run, or unknown upgrade id"
		end
	elseif cmd == "Reforge" and type(request.Weapon) == "string" then
		PlayerDataService.Mutate(player, function(data)
			local entry: PlayerDataService.ReforgeEntry = data.WeaponReforge[request.Weapon]
				or { Tier = nil, Rolls = 0, PityEpic = 0, PityLegend = 0, Pending = nil }
			entry.Tier = if type(request.Tier) == "string" then request.Tier else nil
			entry.Pending = nil
			data.WeaponReforge[request.Weapon] = entry
		end)
		WeaponHoldService.Refresh(player)
	elseif cmd == "SetProfile" then
		-- { Level = n?, Stats = { RoomsCleared = n, ... }? } — returns the previous values so a test can restore them.
		local before: { [string]: any } = { Level = profile.HunterLevel, Stats = {} }
		PlayerDataService.Mutate(player, function(data)
			if tonumber(request.Level) then
				data.HunterLevel = math.max(1, math.floor(tonumber(request.Level) :: number))
			end
			if type(request.Stats) == "table" then
				for key, value in request.Stats do
					if type(key) == "string" and tonumber(value) then
						before.Stats[key] = data.Stats[key] or 0
						data.Stats[key] = tonumber(value) :: number
					end
				end
			end
		end)
		return game:GetService("HttpService"):JSONEncode(before)
	elseif cmd == "Ascension" and type(request.Id) == "string" then
		-- { Id, Level } — returns the previous level so a test can restore it.
		local previous = profile.AscensionNodes[request.Id] or 0
		PlayerDataService.Mutate(player, function(data)
			local level = math.max(0, math.floor(tonumber(request.Level) or 0))
			data.AscensionNodes[request.Id] = (if level > 0 then level else nil) :: any
		end)
		return tostring(previous)
	elseif cmd == "Offline" then -- Minutes = 0 clears the pending card
		return tostring(SanctuaryService.DevAway(player, tonumber(request.Minutes) or 60))
	elseif cmd == "StartRun" then
		local ok, message = RunManagerService.StartRun({ player }, tonumber(request.World) or 1, tonumber(request.Corruption) or 0)
		if not ok then
			return message
		end
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
