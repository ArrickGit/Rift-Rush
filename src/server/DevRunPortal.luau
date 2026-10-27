--!strict
-- ServerScriptService/Server/DevRunPortal.luau
-- Studio-only stand-in for the Town Hub's Central Rift Gate (Step 5): a spawn pad plus a portal that starts a
-- solo Mushroom Wilds run. Delete this file and its call in init.server.luau once the Town Hub exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Physics25D = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Physics25D"))
local RunManagerService = require(script.Parent:WaitForChild("Services"):WaitForChild("RunManagerService"))

local DevRunPortal = {}

function DevRunPortal.Build()
	if Workspace:FindFirstChild("DevRunPortal") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevRunPortal"

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "DevSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, 0.5, Physics25D.PLANE_Z)
	spawn.Parent = folder

	local portal = Instance.new("Part")
	portal.Name = "RiftGate"
	portal.Anchored = true
	portal.CanCollide = false
	portal.Material = Enum.Material.Neon
	portal.Color = Color3.fromRGB(190, 95, 255)
	portal.Size = Vector3.new(6, 9, 1)
	portal.Position = Vector3.new(14, 5, Physics25D.PLANE_Z)
	portal.Parent = folder

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Rift Gate"
	prompt.ActionText = "Enter Mushroom Wilds"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = portal
	prompt.Triggered:Connect(function(player: Player)
		local success, message = RunManagerService.StartRun({ player }, 1, 0)
		if not success then
			warn("[DevRunPortal] " .. message)
		end
	end)

	folder.Parent = Workspace
end

return DevRunPortal
