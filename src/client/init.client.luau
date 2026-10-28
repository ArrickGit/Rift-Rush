--!strict
-- StarterPlayerScripts/Client — bootstrap. Each build step adds its controllers to this list.

local Controllers = script:WaitForChild("Controllers")

local Camera25DController = require(Controllers:WaitForChild("Camera25DController"))
local Movement25DController = require(Controllers:WaitForChild("Movement25DController"))
local ProceduralAnimController = require(Controllers:WaitForChild("ProceduralAnimController"))
local CombatVFXController = require(Controllers:WaitForChild("CombatVFXController"))
local CombatInputController = require(Controllers:WaitForChild("CombatInputController"))
local UIController = require(Controllers:WaitForChild("UIController"))
local WaypointController = require(Controllers:WaitForChild("WaypointController"))
local AmbientController = require(Controllers:WaitForChild("AmbientController"))
local MobileControlsController = require(Controllers:WaitForChild("MobileControlsController"))

-- Each Init runs in its own thread (in this order, up to its first yield), so one controller that yields or
-- errors can never stop the rest — e.g. the UI and its Town Hub panels — from starting.
local inits: { { Name: string, Init: () -> () } } = {
	{ Name = "Camera25DController", Init = Camera25DController.Init },
	{ Name = "Movement25DController", Init = Movement25DController.Init },
	{ Name = "ProceduralAnimController", Init = ProceduralAnimController.Init },
	{ Name = "CombatVFXController", Init = CombatVFXController.Init },
	{ Name = "CombatInputController", Init = CombatInputController.Init },
	{ Name = "UIController", Init = UIController.Init },
	{ Name = "WaypointController", Init = WaypointController.Init },
	{ Name = "AmbientController", Init = AmbientController.Init },
	{ Name = "MobileControlsController", Init = MobileControlsController.Init },
}
for _, entry in inits do
	task.spawn(function()
		local ok, err = pcall(function(): any
			entry.Init()
			return nil
		end)
		if not ok then
			warn(("[RiftRush] %s.Init failed: %s"):format(entry.Name, tostring(err)))
		end
	end)
end

print("[RiftRush] Client started")
