--!strict
-- ServerScriptService/Server/Services/MonetizationService.luau
-- The only script that sets MarketplaceService.ProcessReceipt (Section 27). Rules:
--   * Idempotent: each PurchaseId is recorded in profile.ProcessedReceipts in the same step as the grant, and
--     PurchaseGranted is only returned once that profile has been saved. A retried receipt is acknowledged without
--     granting twice.
--   * Grants only touch the profile or run state through the owning services; failures return NotProcessedYet so
--     Roblox retries.
--   * Clients never pick product ids: RequestPurchase { Kind, Key } is validated and the server prompts. For
--     Instant Rebirth the server always prompts the tier that matches current progress.
--   * Gamepass ownership is cached as player attributes (MonetizationConfig.Passes[*].Attribute) on join and on
--     mid-session purchase; the gameplay services read those attributes.
--
-- Studio testing before ids exist: from the server command bar,
--   require(game.ServerScriptService.Server.Services.MonetizationService).DevGrant(game.Players.<Name>, "RiftSurge")
-- runs a product or pass grant directly (Studio only).

local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RebirthService = require(script.Parent:WaitForChild("RebirthService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))
local SanctuaryService = require(script.Parent:WaitForChild("SanctuaryService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData
type ProductInfo = MonetizationConfig.ProductInfo
type PassInfo = MonetizationConfig.PassInfo

-- Returns true when the purchase was fully applied. Must not leave partial changes behind when returning false.
type GrantFn = (player: Player, product: ProductInfo) -> boolean

local MonetizationService = {}

local MAX_RECEIPT_HISTORY = 100
local PROMPT_DEFEAT_HOLD_SECONDS = 45 -- keeps the defeat screen alive while the Robux prompt is open
local REQUEST_COOLDOWN = 1
local SURGE_TINT_NAME = "RiftSurgeTint"

local notifyRemote: RemoteEvent
local productsById: { [number]: ProductInfo } = {}
local passesById: { [number]: PassInfo } = {}
local inFlight: { [string]: boolean } = {}
local lastRequest: { [Player]: number } = {}

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function notifyAll(message: string)
	notifyRemote:FireAllClients(message)
end

-- Rift Surge -----------------------------------------------------------------------------------------------

local function surgeEndsAt(): number
	local value = Workspace:GetAttribute(MonetizationConfig.RIFT_SURGE_ATTRIBUTE)
	return if type(value) == "number" then value else 0
end

local function setSurgeVisuals(active: boolean)
	local tint = Lighting:FindFirstChild(SURGE_TINT_NAME)
	if not tint then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = SURGE_TINT_NAME
		effect.TintColor = Color3.fromRGB(235, 200, 255)
		effect.Saturation = 0.25
		effect.Contrast = 0.08
		effect.Parent = Lighting
		tint = effect
	end
	(tint :: ColorCorrectionEffect).Enabled = active
end

-- Starts or extends the server-wide Rift Surge. Used by the Robux product and later by milestone rewards.
function MonetizationService.StartRiftSurge(byPlayer: Player?)
	local now = Workspace:GetServerTimeNow()
	local endsAt = math.max(now, surgeEndsAt()) + MonetizationConfig.RIFT_SURGE_SECONDS
	Workspace:SetAttribute(MonetizationConfig.RIFT_SURGE_ATTRIBUTE, endsAt)
	setSurgeVisuals(true)
	notifyAll(("%s triggered a Rift Surge! x%.1f Hunter XP & Rift Dust for everyone (%d min left)"):format(
		if byPlayer then byPlayer.DisplayName else "The Rift", MonetizationConfig.RIFT_SURGE_ECO_MULT,
		math.ceil((endsAt - now) / 60)))
end

-- Product grants --------------------------------------------------------------------------------------------

local function addToProfile(field: "KeepEverythingSeals" | "SuperchargedTokens" | "BonusRerolls" | "StarForceSafeguards",
	amount: number, message: string): GrantFn
	return function(player: Player): boolean
		if not PlayerDataService.Get(player) then
			return false
		end
		PlayerDataService.Mutate(player, function(profile)
			local data = profile :: any
			data[field] += amount
		end)
		notify(player, message)
		return true
	end
end

-- Revive / Rewind / Insure only apply while the player is defeated. If the moment has passed (timer ran out,
-- teammates rewound...), the player gets an Anchor Token instead, which covers Rewind / Insure next time.
local function defeatGrant(product: ProductInfo): GrantFn
	return function(player: Player): boolean
		if not PlayerDataService.Get(player) then
			return false
		end
		local choice = MonetizationConfig.DefeatProducts[product.Key]
		local applied = false
		if RunManagerService.IsDefeated(player) then
			applied = RunManagerService.ResolveDefeat(player, choice, "Robux")
		end
		if not applied then
			PlayerDataService.Mutate(player, function(profile)
				profile.AnchorTokens += 1
			end)
			notify(player, product.Name .. " could not be used right now, so you received an Anchor Token instead.")
		end
		return true
	end
end

local function skipGrant(player: Player, product: ProductInfo): boolean
	if not PlayerDataService.Get(player) then
		return false
	end
	RebirthService.AddSkipCredit(player, product.Price)
	-- Applies now if the player is in town, otherwise when they get back (RebirthService watches RunId).
	task.defer(RebirthService.ApplyPendingSkips, player)
	return true
end

local GRANTS: { [string]: GrantFn } = {
	SKIP_TIER_1_49R = skipGrant,
	SKIP_TIER_2_99R = skipGrant,
	SKIP_TIER_3_179R = skipGrant,
	SKIP_TIER_4_279R = skipGrant,
	SKIP_TIER_5_399R = skipGrant,
	KeepEverythingSeal = addToProfile("KeepEverythingSeals", 1,
		"Keep Everything Seal added! Choose Keep Everything at the Ascension Pedestal."),
	SuperchargedRunToken = addToProfile("SuperchargedTokens", 1, "Supercharged Run Token added! It activates on your next run."),
	RerollPack5 = addToProfile("BonusRerolls", MonetizationConfig.REROLL_PACK_SIZE,
		("+%d Upgrade Rerolls banked"):format(MonetizationConfig.REROLL_PACK_SIZE)),
	StarForceSafeguardPack = addToProfile("StarForceSafeguards", MonetizationConfig.SAFEGUARD_PACK_SIZE,
		("+%d Star-Force Safeguards"):format(MonetizationConfig.SAFEGUARD_PACK_SIZE)),
	RiftSurge = function(player: Player): boolean
		MonetizationService.StartRiftSurge(player)
		return true
	end,
	-- Claims the waiting offline training twice over; if it was already claimed, an Anchor Token instead.
	OfflineDouble = function(player: Player): boolean
		if not PlayerDataService.Get(player) then
			return false
		end
		if not SanctuaryService.ClaimOffline(player, 2) then
			PlayerDataService.Mutate(player, function(profile)
				profile.AnchorTokens += 1
			end)
			notify(player, "Your offline training was already claimed, so you received an Anchor Token instead.")
		end
		return true
	end,
}
for key, product in MonetizationConfig.Products do
	if MonetizationConfig.DefeatProducts[key] then
		GRANTS[key] = defeatGrant(product)
	end
end

-- ProcessReceipt --------------------------------------------------------------------------------------------

local function hasProcessed(profile: PlayerProfileData, purchaseId: string): boolean
	return table.find(profile.ProcessedReceipts, purchaseId) ~= nil
end

local function recordReceipt(player: Player, purchaseId: string)
	PlayerDataService.Mutate(player, function(profile)
		table.insert(profile.ProcessedReceipts, purchaseId)
		while #profile.ProcessedReceipts > MAX_RECEIPT_HISTORY do
			table.remove(profile.ProcessedReceipts, 1)
		end
	end)
end

-- Granted once the record is durable; ephemeral (unsaved Studio) profiles count as durable for testing.
local function finalize(player: Player): Enum.ProductPurchaseDecision
	if PlayerDataService.IsEphemeral(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- Studio only; live ephemeral profiles never get here
	end
	if PlayerDataService.Save(player) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- The record is still in the live profile, so a retry this session acknowledges without re-granting.
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried when they rejoin
	end
	local profile = PlayerDataService.Wait(player)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if hasProcessed(profile, purchaseId) then
		return finalize(player)
	end
	if PlayerDataService.IsEphemeral(player) and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- the save failed to load; grant once it can persist
	end
	if inFlight[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = productsById[receiptInfo.ProductId]
	local grant = if product then GRANTS[product.Key] else nil
	if not product or not grant then
		warn(("[MonetizationService] No handler for product id %s"):format(tostring(receiptInfo.ProductId)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	inFlight[purchaseId] = true
	local ok, granted = pcall(grant, player, product)
	if ok and granted and player.Parent then
		recordReceipt(player, purchaseId)
	end
	inFlight[purchaseId] = nil

	if not ok then
		warn(("[MonetizationService] Grant %s for %s errored: %s"):format(product.Key, player.Name, tostring(granted)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted or not player.Parent then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	print(("[MonetizationService] Granted %s to %s (PurchaseId %s)"):format(product.Key, player.Name, purchaseId))
	return finalize(player)
end

-- Gamepasses ------------------------------------------------------------------------------------------------

local function refreshPasses(player: Player)
	for _, pass in MonetizationConfig.Passes do
		if pass.Id ~= 0 and player:GetAttribute(pass.Attribute) ~= true then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.Id)
			end)
			if ok and owns and player.Parent then
				player:SetAttribute(pass.Attribute, true)
			elseif not ok then
				warn(("[MonetizationService] Pass check %s for %s failed: %s"):format(pass.Key, player.Name, tostring(owns)))
			end
		end
	end
end

function MonetizationService.OwnsPass(player: Player, passKey: string): boolean
	local pass = MonetizationConfig.Passes[passKey]
	return pass ~= nil and player:GetAttribute(pass.Attribute) == true
end

-- Prompts -----------------------------------------------------------------------------------------------------

-- Validates context, then shows the Roblox purchase prompt. Returns (success, message).
function MonetizationService.PromptProduct(player: Player, key: string): (boolean, string)
	local product = MonetizationConfig.Products[key]
	if key == "InstantRebirth" then
		local profile = PlayerDataService.Get(player)
		if not profile then
			return false, "Your profile is still loading"
		end
		local quoteKey = FormulaEngine.GetInstantRebirthSkipQuote(profile.RebirthTier + 1, profile.HunterLevel)
		product = MonetizationConfig.Products[quoteKey]
	end
	if not product then
		return false, "Unknown product"
	end
	if product.Id == 0 then
		return false, product.Name .. " is not on sale yet"
	end
	if product.Key == "OfflineDouble" and not SanctuaryService.HasOffline(player) then
		return false, "No offline training to claim"
	end
	if MonetizationConfig.DefeatProducts[product.Key] then
		if not RunManagerService.IsDefeated(player) then
			return false, "That option is only available on the Rift Collapse screen"
		end
		RunManagerService.HoldDefeat(player, PROMPT_DEFEAT_HOLD_SECONDS)
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
	return true, "Prompted"
end

function MonetizationService.PromptPass(player: Player, key: string): (boolean, string)
	local pass = MonetizationConfig.Passes[key]
	if not pass then
		return false, "Unknown pass"
	end
	if pass.Id == 0 then
		return false, pass.Name .. " is not on sale yet"
	end
	if player:GetAttribute(pass.Attribute) == true then
		return false, "You already own " .. pass.Name
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	return true, "Prompted"
end

-- Studio-only: apply a product or pass grant without a real purchase (see header).
function MonetizationService.DevGrant(player: Player, key: string): boolean
	assert(RunService:IsStudio(), "DevGrant is Studio-only")
	local pass = MonetizationConfig.Passes[key]
	if pass then
		player:SetAttribute(pass.Attribute, true)
		return true
	end
	local product = MonetizationConfig.Products[key]
	local grant = GRANTS[key]
	if not product or not grant then
		return false
	end
	return grant(player, product)
end

function MonetizationService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")

	local configured = 0
	for _, product in MonetizationConfig.Products do
		if product.Id ~= 0 then
			productsById[product.Id] = product
			configured += 1
		end
	end
	for _, pass in MonetizationConfig.Passes do
		if pass.Id ~= 0 then
			passesById[pass.Id] = pass
			configured += 1
		end
	end
	if configured == 0 then
		warn("[MonetizationService] No product / pass ids set in MonetizationConfig yet; purchases are disabled.")
	end

	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local pass = passesById[passId]
		if purchased and pass then
			player:SetAttribute(pass.Attribute, true)
			notify(player, "Thank you! " .. pass.Name .. " is now active.")
		end
	end)

	Remotes.GetEvent("RequestPurchase").OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" or type(request.Key) ~= "string" or #request.Key > 40 then
			return
		end
		local now = os.clock()
		if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
			return
		end
		lastRequest[player] = now
		local success, message
		if request.Kind == "Pass" then
			success, message = MonetizationService.PromptPass(player, request.Key)
		elseif request.Kind == "Product" then
			success, message = MonetizationService.PromptProduct(player, request.Key)
		else
			return
		end
		if not success then
			notify(player, message)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(refreshPasses, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(refreshPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)

	-- Rift Surge expiry
	task.spawn(function()
		while true do
			task.wait(5)
			local active = MonetizationConfig.IsRiftSurgeActive(Workspace:GetServerTimeNow(), surgeEndsAt())
			local tint = Lighting:FindFirstChild(SURGE_TINT_NAME)
			if tint and (tint :: ColorCorrectionEffect).Enabled and not active then
				setSurgeVisuals(false)
				notifyAll("The Rift Surge has faded.")
			end
		end
	end)
end

return MonetizationService
