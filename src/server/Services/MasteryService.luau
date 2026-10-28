--!strict
-- ServerScriptService/Server/Services/MasteryService.luau
-- Weapon Mastery XP (game.md Section 6.1 / Step SP-3). Every kill pays Mastery XP to the killer's equipped weapon:
--   Normal 12 / Elite 45 x WorldMult x (1 + 0.08 x Corruption), Mini-Boss 180 / World Boss 400 x WorldMult,
--   all x (1 + 12% per Rift Scholar level). Mastery climbs 1-20 on round(100 x M^1.5) XP per level, then keeps
--   going as Paragon ranks (each +0.5% weapon damage & Rift Dust, read by FormulaEngine / RunManagerService).
-- Mastery 10 unlocks the weapon's Link Skill (Tier 1) and Mastery 20 upgrades it (Tier 2).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local MasteryService = {}

local NODE_SCHOLAR = "AS_T1_02"

local masteryRemote: RemoteEvent
local celebrateRemote: RemoteEvent

local levelChangedEvent = Instance.new("BindableEvent")
-- Fires (player: Player, weaponId: string) after a Mastery level or Paragon rank is gained.
MasteryService.LevelChanged = levelChangedEvent.Event :: RBXScriptSignal

local function computeXP(profile: PlayerDataService.PlayerProfileData, killKind: string, worldIndex: number, corruption: number): number
	local base = WeaponConfig.KILL_MASTERY_XP[killKind] or WeaponConfig.KILL_MASTERY_XP.Normal
	local worldMult = FormulaEngine.GetWorldEcoMult(worldIndex)
	local corruptionMult = if killKind == "Normal" or killKind == "Elite" then 1 + 0.08 * math.max(0, corruption) else 1
	local scholar = 1 + 0.12 * (profile.AscensionNodes[NODE_SCHOLAR] or 0)
	return math.max(1, math.round(base * worldMult * corruptionMult * scholar))
end

-- XP still needed for the next level / rank of an entry.
function MasteryService.GetRequired(level: number, paragon: number): number
	return WeaponConfig.GetMasteryXPRequired(if level >= WeaponConfig.MAX_MASTERY then WeaponConfig.MAX_MASTERY + paragon else level)
end

-- Awards Mastery XP for one kill to the player's equipped weapon. killKind: Normal | Elite | MiniBoss | WorldBoss.
function MasteryService.AwardKill(player: Player, killKind: string, worldIndex: number, corruption: number)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local weaponId = profile.EquippedWeapon
	local info = WeaponConfig.Weapons[weaponId]
	if not info then
		return
	end
	local entry = profile.WeaponMastery[weaponId]
	if not entry then
		entry = { Level = 1, XP = 0, ParagonRank = 0 }
		profile.WeaponMastery[weaponId] = entry
	end
	local gained = computeXP(profile, killKind, worldIndex, corruption)
	entry.XP += gained

	local leveled = false
	local linkTier: number? = nil
	while true do
		local required = MasteryService.GetRequired(entry.Level, entry.ParagonRank)
		if entry.XP < required then
			break
		end
		if entry.Level < WeaponConfig.MAX_MASTERY then
			entry.XP -= required
			entry.Level += 1
			leveled = true
			if entry.Level == WeaponConfig.LINK_TIER1_LEVEL then
				linkTier = 1
			elseif entry.Level == WeaponConfig.LINK_TIER2_LEVEL then
				linkTier = 2
			end
		elseif entry.ParagonRank < WeaponConfig.MAX_PARAGON then
			entry.XP -= required
			entry.ParagonRank += 1
			leveled = true
		else
			entry.XP = 0
			break
		end
	end

	masteryRemote:FireClient(player, {
		Weapon = weaponId, Level = entry.Level, XP = entry.XP, Paragon = entry.ParagonRank, Gained = gained,
		Required = MasteryService.GetRequired(entry.Level, entry.ParagonRank), LevelUp = leveled, LinkTier = linkTier,
	})
	if not leveled then
		return
	end

	local title = if entry.ParagonRank > 0
		then ("%s Paragon %d"):format(info.Name, entry.ParagonRank)
		else ("%s Mastery %d"):format(info.Name, entry.Level)
	local body = if linkTier == 1
		then ("Link Skill unlocked: %s (+%d%%). Equip it in your Bag or at the Legion Hall!"):format(info.Link.Name, math.round(info.Link.Lv10 * 100))
		elseif linkTier == 2 then ("Link Skill maxed: %s (+%d%%)!"):format(info.Link.Name, math.round(info.Link.Lv20 * 100))
		elseif entry.ParagonRank > 0 then "+0.5% weapon damage & Rift Dust find"
		else "+2% weapon damage"
	celebrateRemote:FireClient(player, { Kind = "Mastery", Title = title, Body = body, Icon = info.Icon, Color = info.Accent })
	PlayerDataService.Replicate(player)
	levelChangedEvent:Fire(player, weaponId)
end

function MasteryService.Init()
	Remotes.Init()
	masteryRemote = Remotes.GetEvent("MasteryUpdated")
	celebrateRemote = Remotes.GetEvent("Celebrate")
end

return MasteryService
