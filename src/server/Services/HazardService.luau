--!strict
-- ServerScriptService/Server/Services/HazardService.luau
-- "Floor is Lava" acid flood for Jump Quest rooms (game.md Section 33.5). Every HAZARD_TICK seconds, any living run
-- player whose root is at or below the acid surface (+1.5 studs) takes 6% of their Max HP as Poison damage and is
-- told to bounce: the client owns its character's physics, so it applies the upward launch and the green flash
-- (CombatFx "PoisonBounce"); a server velocity write would just be overwritten.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))

local HazardService = {}

local HAZARD_TICK = 0.5
local SURFACE_MARGIN = 1.5
local DAMAGE_FRACTION = 0.06 -- 12% Max HP/s (was 8% per 0.4s = 20%/s)
local BOUNCE_SPEED = 68

local fxRemote: RemoteEvent

local function tick()
	for _, run in RunManagerService.GetActiveRuns() do
		local surface = RunManagerService.GetPoisonTop(run)
		if not surface then
			continue
		end
		for _, player in RunManagerService.GetPlayersInRun(run.Id, true) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and root.Position.Y <= surface + SURFACE_MARGIN then
				if CombatService.DamageHazard(player, DAMAGE_FRACTION) then
					fxRemote:FireClient(player, { Kind = "PoisonBounce", Speed = BOUNCE_SPEED })
				end
			end
		end
	end
end

function HazardService.Init()
	Remotes.Init()
	fxRemote = Remotes.GetEvent("CombatFx")
	task.spawn(function()
		while true do
			task.wait(HAZARD_TICK)
			local ok, err = pcall(function(): any
				tick()
				return nil
			end)
			if not ok then
				warn("[HazardService] tick failed: " .. tostring(err))
			end
		end
	end)
end

return HazardService
