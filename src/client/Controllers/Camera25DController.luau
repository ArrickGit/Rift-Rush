--!strict
-- StarterPlayerScripts/Client/Controllers/Camera25DController.luau
-- 2.5D side-scrolling camera (Section 7): narrow 35° FOV from Z=+42, critically damped springs with a
-- snappy horizontal follow and a softer vertical follow. While airborne the vertical target only moves
-- once the character leaves a dead-zone, so ordinary jumps don't bob the view but tall climbs and long
-- falls are tracked. Optional room bounds (Step 3) and screen shake (Step 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Physics25D = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Physics25D"))

local RENDER_STEP_NAME = "RiftCamera25D"
local FOV = 35
local CAMERA_DISTANCE = 42 -- along +Z from the combat plane
local HEIGHT_OFFSET = 3 -- camera sits slightly above its focus for a gentle downward tilt
local FOCUS_Y_OFFSET = 2 -- frame a little above the root so upper platforms stay visible
local LOOK_AHEAD = 4 -- studs of lead in the facing direction
local X_FREQUENCY = 8
local Y_FREQUENCY = 4.5
local AIR_UP_WINDOW = 5 -- rise this far above the last ground height before the camera follows up
local AIR_DOWN_WINDOW = 2 -- fall this far below it before the camera follows down
local SNAP_DISTANCE = 60 -- teleports (respawn, room change) cut instead of panning

export type Bounds = { MinX: number, MaxX: number, MinY: number, MaxY: number }

local Camera25DController = {}

local player = Players.LocalPlayer
local bounds: Bounds? = nil
local initialized = false
local focusX, focusY = 0, 0
local velocityX, velocityY = 0, 0
local anchorY = 0
local shakeIntensity, shakeDuration, shakeTimeLeft = 0, 0, 0
local rng = Random.new()

-- Exact critically damped spring step: stable for any dt, so frame hitches never overshoot.
local function stepSpring(position: number, velocity: number, target: number, frequency: number, dt: number): (number, number)
	local offset = position - target
	local decay = math.exp(-frequency * dt)
	local drive = velocity + frequency * offset
	return target + (offset + drive * dt) * decay, (velocity - frequency * drive * dt) * decay
end

local function clampAxis(value: number, low: number, high: number, halfExtent: number): number
	if high - low <= halfExtent * 2 then
		return (low + high) / 2
	end
	return math.clamp(value, low + halfExtent, high - halfExtent)
end

-- Keeps the visible rectangle on the combat plane inside the room bounds.
local function clampToBounds(x: number, y: number, camera: Camera): (number, number)
	local b = bounds
	if not b then
		return x, y
	end
	local halfHeight = CAMERA_DISTANCE * math.tan(math.rad(FOV / 2))
	local viewport = camera.ViewportSize
	local halfWidth = halfHeight * (viewport.X / math.max(1, viewport.Y))
	return clampAxis(x, b.MinX, b.MaxX, halfWidth), clampAxis(y, b.MinY, b.MaxY, halfHeight)
end

local function updateFocus(camera: Camera, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return
	end

	local position = root.Position
	if not initialized or humanoid.FloorMaterial ~= Enum.Material.Air then
		anchorY = position.Y
	elseif position.Y > anchorY + AIR_UP_WINDOW then
		anchorY = position.Y - AIR_UP_WINDOW
	elseif position.Y < anchorY - AIR_DOWN_WINDOW then
		anchorY = position.Y + AIR_DOWN_WINDOW
	end

	local lookX = root.CFrame.LookVector.X
	local lead = if math.abs(lookX) > 0.5 then math.sign(lookX) * LOOK_AHEAD else 0
	local targetX, targetY = clampToBounds(position.X + lead, anchorY + FOCUS_Y_OFFSET, camera)

	local distance = math.max(math.abs(targetX - focusX), math.abs(targetY - focusY))
	if not initialized or distance > SNAP_DISTANCE then
		focusX, focusY = targetX, targetY
		velocityX, velocityY = 0, 0
		initialized = true
	else
		focusX, velocityX = stepSpring(focusX, velocityX, targetX, X_FREQUENCY, dt)
		focusY, velocityY = stepSpring(focusY, velocityY, targetY, Y_FREQUENCY, dt)
	end
end

local function onRenderStep(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- The default camera scripts can reset these on respawn; enforce every frame (cheap property reads).
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if camera.FieldOfView ~= FOV then
		camera.FieldOfView = FOV
	end

	updateFocus(camera, dt)

	local focus = Vector3.new(focusX, focusY, Physics25D.PLANE_Z)
	local cframe = CFrame.lookAt(focus + Vector3.new(0, HEIGHT_OFFSET, CAMERA_DISTANCE), focus)

	if shakeTimeLeft > 0 then
		shakeTimeLeft = math.max(0, shakeTimeLeft - dt)
		local strength = shakeIntensity * (shakeTimeLeft / shakeDuration)
		cframe *= CFrame.new(rng:NextNumber(-1, 1) * strength, rng:NextNumber(-1, 1) * strength, 0)
	end

	camera.CFrame = cframe
end

-- Room extents on the combat plane, in studs. RunManagerService/RoomBuilderService set these per room.
function Camera25DController.SetBounds(minX: number, maxX: number, minY: number, maxY: number)
	bounds = { MinX = minX, MaxX = maxX, MinY = minY, MaxY = maxY }
end

function Camera25DController.ClearBounds()
	bounds = nil
end

-- Linearly decaying shake; a weaker shake never overrides a stronger one still in progress.
function Camera25DController.Shake(intensity: number, duration: number)
	local remaining = if shakeTimeLeft > 0 then shakeIntensity * (shakeTimeLeft / shakeDuration) else 0
	if intensity >= remaining and duration > 0 then
		shakeIntensity, shakeDuration, shakeTimeLeft = intensity, duration, duration
	end
end

function Camera25DController.Init()
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, onRenderStep)
end

return Camera25DController
