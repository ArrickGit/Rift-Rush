--!strict
-- ReplicatedStorage/Shared/ModelNormalizer.luau
-- Automatically strips malicious/broken scripts from free Toolbox models, scales them to targetSize,
-- creates a clean PrimaryPart hitbox, and welds all parts together for 2.5D combat!

local ModelNormalizer = {}

function ModelNormalizer.SanitizeAndNormalize(rawModel: Model, targetSize: Vector3): Model
	-- 1. Strip any hidden scripts, ClickDetectors, or TouchTransmitters from free online models
	for _, desc in rawModel:GetDescendants() do
		if desc:IsA("LuaSourceContainer") or desc:IsA("ClickDetector") or desc:IsA("Fire") or desc:IsA("Smoke") then
			desc:Destroy()
		end
	end

	-- 2. Scale model proportionally to fit targetSize height
	local _, currentSize = rawModel:GetBoundingBox()
	if currentSize.Y > 0.05 then
		local scaleFactor = targetSize.Y / currentSize.Y
		rawModel:ScaleTo(rawModel:GetScale() * scaleFactor)
	end

	-- 3. Create a clean invisible PrimaryPart root at the bounding box center
	local cf, newSize = rawModel:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "NormalizedRoot"
	root.Size = newSize
	root.CFrame = cf
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = true
	root.Parent = rawModel

	-- 4. Weld all visual parts to NormalizedRoot and disable internal collisions
	for _, desc in rawModel:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= root then
			desc.Anchored = false
			desc.CanCollide = false
			desc.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = desc
			weld.Parent = root
		end
	end

	rawModel.PrimaryPart = root
	return rawModel
end

return ModelNormalizer
