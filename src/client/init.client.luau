--!strict
-- StarterPlayerScripts/Client — bootstrap. Each build step adds its controllers to this list.

local Controllers = script:WaitForChild("Controllers")

local Camera25DController = require(Controllers:WaitForChild("Camera25DController"))
local Movement25DController = require(Controllers:WaitForChild("Movement25DController"))
local ProceduralAnimController = require(Controllers:WaitForChild("ProceduralAnimController"))
local CombatVFXController = require(Controllers:WaitForChild("CombatVFXController"))
local CombatInputController = require(Controllers:WaitForChild("CombatInputController"))
local UIController = require(Controllers:WaitForChild("UIController"))

Camera25DController.Init()
Movement25DController.Init()
ProceduralAnimController.Init()
CombatVFXController.Init()
CombatInputController.Init()
UIController.Init()

print("[RiftRush] Client started")
