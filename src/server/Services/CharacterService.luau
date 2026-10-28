--!strict
-- ServerScriptService/Server/Services/CharacterService.luau
-- Server half of the 2.5D movement rules: locks every player character to the Z=0 plane, puts it in the
-- ActorsNoCollide group, and applies Skywalker's Grace walk speed / jump height from the profile.
-- Call RefreshMobility after anything changes the player's Skywalker's Grace level (AscensionShopService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Physics25D = require(Shared:WaitForChild("Physics25D"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local CharacterService = {}

local function getSkywalkerLevel(player: Player): number
	local profile = PlayerDataService.Get(player)
	if not profile then
		return 0
	end
	return profile.AscensionNodes[Physics25D.SKYWALKER_NODE_ID] or 0
end

function CharacterService.RefreshMobility(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local mobility = Physics25D.GetMobility(getSkywalkerLevel(player))
	humanoid.UseJumpPower = false
	humanoid.WalkSpeed = mobility.WalkSpeed
	humanoid.JumpHeight = mobility.JumpHeight
end

local function onCharacterAdded(player: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (root and root:IsA("BasePart")) or player.Character ~= character then
		return
	end
	Physics25D.SetupActor(character, root)
	CharacterService.RefreshMobility(player)

	-- Falling out of the world destroys the body parts but can leave the Humanoid "alive" forever, so no respawn
	-- ever happens. Treat a lost root part as a death so the normal defeat / respawn flow takes over.
	root.AncestryChanged:Connect(function()
		-- Respawns and leaving players remove the whole character; only a root lost from a live character counts.
		if root:IsDescendantOf(game) or player.Character ~= character or not character:IsDescendantOf(game) or not player.Parent then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)

	-- First spawn can beat the profile load; re-apply once it arrives.
	if not PlayerDataService.Get(player) then
		PlayerDataService.Wait(player)
		if player.Character == character then
			CharacterService.RefreshMobility(player)
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function CharacterService.Init()
	Physics25D.RegisterCollisionGroups()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return CharacterService
