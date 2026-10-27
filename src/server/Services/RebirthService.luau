--!strict
-- ServerScriptService/Server/Services/RebirthService.luau
-- Rift Rebirths (Section 22): Standard (free), "Keep Everything" (True Ascendant pass or a single-use Seal) and
-- Instant Skip (Robux). All eligibility and payouts come from FormulaEngine; clients only ask.
--
-- 3-Bucket Reset Rule (Section 22.3):
--   1. Hunter Level resets to 1. Keep Everything also banks Legacy levels (FormulaEngine.CalculateLegacyLevelsGained).
--   2. Standard: unspent Rift Dust is consumed (ProtectedDustVault survives), Worlds 2-8 re-lock (World 1 keeps its
--      Corruption progress), and every non-default weapon goes inactive until its reactivation fee is paid.
--      Keep Everything keeps all of that and pays +2 bonus Sparks.
--   3. Relics, Star-Force, Mastery, Link Skills, Ascension nodes, Boss Cores: always kept.
--
-- Instant Skip receipts are stored as PendingSkipCredits (the price paid). A credit applies once the player is in
-- town and the price covers their current skip quote, so prompting a cheaper tier from the client gains nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local CharacterService = require(script.Parent:WaitForChild("CharacterService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

export type RebirthMode = "Standard" | "KeepEverything"

export type RebirthPreview = {
	CurrentTier: number,
	NextTier: number,
	HunterLevel: number,
	ReqLevel: number,
	Eligible: boolean,
	SparksGain: number,
	KeepBonusSparks: number,
	NextDmgMult: number,
	NextEcoMult: number,
	LegacyGain: number,
	CanKeepEverything: boolean,
	HasTrueAscendant: boolean,
	KeepEverythingSeals: number,
	SkipKey: string,
	SkipPrice: number,
	SkipProgress: number,
	PendingSkipCredits: { number },
}

local RebirthService = {}

local KEEP_BONUS_SPARKS = 2
local REACTIVATION_FEE_FRACTION = 0.25 -- of WeaponConfig UnlockCost, after a Standard rebirth
local REQUEST_COOLDOWN = 1

local notifyRemote: RemoteEvent
local lastRequest: { [Player]: number } = {}

local rebirthedEvent = Instance.new("BindableEvent")
-- Fires (player: Player, newTier: number, mode: RebirthMode) after a rebirth is applied.
RebirthService.Rebirthed = rebirthedEvent.Event :: RBXScriptSignal

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function hasTrueAscendant(player: Player): boolean
	return player:GetAttribute("HasTrueAscendant") == true
end

local function isInRun(player: Player): boolean
	return RunManagerService.GetRunOf(player) ~= nil
end

local function toRoman(n: number): string
	local values = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 }
	local symbols = { "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I" }
	local out = ""
	for index, value in values do
		while n >= value do
			out ..= symbols[index]
			n -= value
		end
	end
	return out
end

-- Dust needed to re-activate a weapon that a Standard rebirth switched off (0 for the default weapon).
function RebirthService.GetReactivationCost(weaponId: string): number
	local weapon = WeaponConfig.Weapons[weaponId]
	if not weapon or weaponId == WeaponConfig.DEFAULT_WEAPON then
		return 0
	end
	return math.round(weapon.UnlockCost * REACTIVATION_FEE_FRACTION)
end

function RebirthService.GetPreview(player: Player): RebirthPreview?
	local profile = PlayerDataService.Get(player)
	if not profile then
		return nil
	end
	local nextTier = profile.RebirthTier + 1
	local nextInfo = FormulaEngine.GetRebirthInfo(nextTier)
	local skipKey, skipPrice, skipProgress = FormulaEngine.GetInstantRebirthSkipQuote(nextTier, profile.HunterLevel)
	local owned = hasTrueAscendant(player)
	return {
		CurrentTier = profile.RebirthTier,
		NextTier = nextTier,
		HunterLevel = profile.HunterLevel,
		ReqLevel = nextInfo.ReqLevel,
		Eligible = profile.HunterLevel >= nextInfo.ReqLevel,
		SparksGain = nextInfo.Sparks,
		KeepBonusSparks = KEEP_BONUS_SPARKS,
		NextDmgMult = nextInfo.DmgMult,
		NextEcoMult = nextInfo.EcoMult,
		LegacyGain = FormulaEngine.CalculateLegacyLevelsGained(nextTier, profile.HunterLevel),
		CanKeepEverything = owned or profile.KeepEverythingSeals > 0,
		HasTrueAscendant = owned,
		KeepEverythingSeals = profile.KeepEverythingSeals,
		SkipKey = skipKey,
		SkipPrice = skipPrice,
		SkipProgress = skipProgress,
		PendingSkipCredits = table.clone(profile.PendingSkipCredits),
	}
end

-- Applies the 3-Bucket Reset Rule. Assumes every check has already passed.
local function applyRebirth(player: Player, profile: PlayerProfileData, mode: RebirthMode)
	local nextTier = profile.RebirthTier + 1
	local info = FormulaEngine.GetRebirthInfo(nextTier)

	if mode == "KeepEverything" then
		profile.LegacyBonusLevels += FormulaEngine.CalculateLegacyLevelsGained(nextTier, profile.HunterLevel)
		if not hasTrueAscendant(player) then
			profile.KeepEverythingSeals -= 1
		end
	else
		profile.RiftDust = 0
		profile.UnlockedWorlds = { [1] = profile.UnlockedWorlds[1] or 0 }
		for weaponId in profile.UnlockedWeapons do
			if weaponId ~= WeaponConfig.DEFAULT_WEAPON then
				profile.UnlockedWeapons[weaponId] = false
			end
		end
		if profile.UnlockedWeapons[profile.EquippedWeapon] ~= true then
			profile.EquippedWeapon = WeaponConfig.DEFAULT_WEAPON
		end
	end

	local sparks = info.Sparks + (if mode == "KeepEverything" then KEEP_BONUS_SPARKS else 0)
	profile.RebirthTier = nextTier
	profile.RebirthSparksAvailable += sparks
	profile.RebirthSparksTotalEarned += sparks
	profile.HunterLevel = 1
	profile.HunterXP = 0
	profile.RunsSinceLastRebirth = 0

	player:SetAttribute("RebirthTier", nextTier)
	notify(player, ("Rebirth %s! x%.2f Damage & HP, x%.2f Dust & XP, +%d Sparks%s"):format(
		toRoman(nextTier), info.DmgMult, info.EcoMult, sparks,
		if mode == "KeepEverything" then " (Everything kept!)" else ""))
end

local function commit(player: Player, mode: RebirthMode)
	local newTier = 0
	PlayerDataService.Mutate(player, function(profile)
		applyRebirth(player, profile, mode)
		newTier = profile.RebirthTier
	end)
	CharacterService.RefreshMobility(player)
	task.spawn(PlayerDataService.Save, player) -- big, irreversible change: persist right away
	rebirthedEvent:Fire(player, newTier, mode)
end

local function canKeep(player: Player, profile: PlayerProfileData): boolean
	return hasTrueAscendant(player) or profile.KeepEverythingSeals > 0
end

-- Level-gated rebirth from the Ascension Pedestal. Returns (success, message).
function RebirthService.TryRebirth(player: Player, mode: RebirthMode): (boolean, string)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return false, "Your profile is still loading"
	end
	if isInRun(player) then
		return false, "Return to town before you rebirth"
	end
	local reqLevel = FormulaEngine.GetRebirthInfo(profile.RebirthTier + 1).ReqLevel
	if profile.HunterLevel < reqLevel then
		return false, ("Reach Hunter Level %d to rebirth (you are %d)"):format(reqLevel, profile.HunterLevel)
	end
	if mode == "KeepEverything" and not canKeep(player, profile) then
		return false, "Keep Everything needs the True Ascendant pass or a Keep Everything Seal"
	end
	commit(player, mode)
	return true, "Rebirthed"
end

-- Pedestal default: Keep Everything when the player has the pass or a seal, otherwise Standard.
function RebirthService.GetDefaultMode(player: Player): RebirthMode
	local profile = PlayerDataService.Get(player)
	return if profile and canKeep(player, profile) then "KeepEverything" else "Standard"
end

-- Called by MonetizationService from ProcessReceipt. Only touches the profile, so it is safe to call anywhere.
function RebirthService.AddSkipCredit(player: Player, pricePaid: number)
	PlayerDataService.Mutate(player, function(profile)
		table.insert(profile.PendingSkipCredits, pricePaid)
	end)
end

-- Spends the cheapest pending credit that covers the current quote. Skip rebirths use the True Ascendant pass when
-- owned (seals are only spent when the player explicitly asks for Keep Everything at the Pedestal).
function RebirthService.ApplyPendingSkips(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile or #profile.PendingSkipCredits == 0 or isInRun(player) then
		return
	end
	local _, quote = FormulaEngine.GetInstantRebirthSkipQuote(profile.RebirthTier + 1, profile.HunterLevel)
	local bestIndex: number? = nil
	for index, price in profile.PendingSkipCredits do
		if price >= quote and (bestIndex == nil or price < profile.PendingSkipCredits[bestIndex]) then
			bestIndex = index
		end
	end
	if not bestIndex then
		notify(player, ("Your Instant Rebirth credit applies once your progress matches its tier (now %d R$)."):format(quote))
		return
	end
	local chosen = bestIndex
	PlayerDataService.Mutate(player, function(data)
		table.remove(data.PendingSkipCredits, chosen)
	end)
	commit(player, if hasTrueAscendant(player) then "KeepEverything" else "Standard")
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		local profile = PlayerDataService.Wait(player)
		if not profile then
			return
		end
		player:SetAttribute("RebirthTier", profile.RebirthTier)
		RebirthService.ApplyPendingSkips(player)
	end)
	-- Credits bought mid-run apply when the player gets back to town.
	player:GetAttributeChangedSignal("RunId"):Connect(function()
		if player:GetAttribute("RunId") == nil then
			RebirthService.ApplyPendingSkips(player)
		end
	end)
end

function RebirthService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")

	Remotes.GetEvent("RequestRebirth").OnServerEvent:Connect(function(player: Player, request: any)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
			return
		end
		lastRequest[player] = now
		local mode = if type(request) == "table" then request.Mode else nil
		if mode ~= "Standard" and mode ~= "KeepEverything" then
			return
		end
		local success, message = RebirthService.TryRebirth(player, mode)
		if not success then
			notify(player, message)
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return RebirthService
