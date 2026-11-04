--!strict
-- ServerScriptService/Server/Services/InventoryService.luau
-- Loadout actions from the Blacksmith, Legion Hall, Star-Forge and the Bag (game.md Step SP-2). Clients send
-- LoadoutAction { Action, ... }; every rule lives here:
--   Unlock { Weapon }      Blacksmith: pay Rift Dust + Boss Cores (or the reactivation fee after a Standard rebirth)
--   Equip { Weapon }       switch the equipped weapon (town only) and re-weld it in the hand
--   EquipLink { Link }     slot an unlocked Link Skill (Mastery 10+) into a free Hunter Legion slot
--   UnequipLink { Link }
--   EquipRelic { Relic }   carry an owned Relic into every run from Room 1 (Starting Relic slots)
--   UnequipRelic { Relic }
--   Reforge { Weapon }     Blacksmith: pay Dust + 1 Boss Core to roll a ReforgeConfig tier. The first roll applies;
--                          later rolls wait in Pending until ReforgeKeep / ReforgeDiscard { Weapon }. A Mythic roll
--                          is announced to the whole server (Celebrate Kind "Mythic").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReforgeConfig = require(Shared:WaitForChild("ReforgeConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RebirthService = require(script.Parent:WaitForChild("RebirthService"))
local RunManagerService = require(script.Parent:WaitForChild("RunManagerService"))
local WeaponHoldService = require(script.Parent:WaitForChild("WeaponHoldService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

local InventoryService = {}

local ACTION_COOLDOWN = 0.2
local NODE_TWIN_VESSEL = "AS_T3_03"
local NODE_LEGION_COMMANDER = "AS_T3_04"

local notifyRemote: RemoteEvent
local celebrateRemote: RemoteEvent
local lastAction: { [Player]: number } = {}
local rng = Random.new()

-- Fired after a reforge changes what a player shows off (FlexBadgeService listens).
local reforgedEvent = Instance.new("BindableEvent")
InventoryService.Reforged = reforgedEvent.Event :: RBXScriptSignal

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

function InventoryService.GetLinkSlots(player: Player, profile: PlayerProfileData): number
	return WeaponConfig.GetLinkSlots(profile.AscensionNodes[NODE_LEGION_COMMANDER] or 0,
		player:GetAttribute("HasExtraLinkSlots") == true)
end

function InventoryService.GetRelicSlots(player: Player, profile: PlayerProfileData): number
	return RelicConfig.GetStartingSlots(profile.AscensionNodes[NODE_TWIN_VESSEL] or 0,
		player:GetAttribute("HasRelicVaultKey") == true)
end

-- Drops equipped Link Skills / Starting Relics that no longer fit (a slot source was lost, e.g. a respec).
local function trimLoadout(player: Player, profile: PlayerProfileData)
	-- Unequip Link Skills whose weapon somehow lost its Mastery (corrupt saves) before trimming by slot count.
	for index = #profile.ActiveLinkSkills, 1, -1 do
		local weapon = WeaponConfig.GetWeaponForLink(profile.ActiveLinkSkills[index])
		local entry = if weapon then profile.WeaponMastery[weapon.Id] else nil
		if not entry or entry.Level < WeaponConfig.LINK_TIER1_LEVEL then
			table.remove(profile.ActiveLinkSkills, index)
		end
	end
	local linkSlots = InventoryService.GetLinkSlots(player, profile)
	while #profile.ActiveLinkSkills > linkSlots do
		table.remove(profile.ActiveLinkSkills)
	end
	local relicSlots = InventoryService.GetRelicSlots(player, profile)
	while #profile.EquippedStartingRelics > relicSlots do
		table.remove(profile.EquippedStartingRelics)
	end
end

function InventoryService.TrimLoadout(player: Player)
	local profile = PlayerDataService.Get(player)
	if profile then
		trimLoadout(player, profile)
		PlayerDataService.Replicate(player)
	end
end

local function unlockWeapon(player: Player, profile: PlayerProfileData, weaponId: string): string?
	local info = WeaponConfig.Weapons[weaponId]
	if not info then
		return "Unknown weapon"
	end
	local state = profile.UnlockedWeapons[weaponId]
	if state == true then
		return "You already own the " .. info.Name
	end
	local dust, cores = info.UnlockCost, info.UnlockCores
	if state == false then
		dust, cores = RebirthService.GetReactivationCost(weaponId), 0
	end
	if profile.RiftDust < dust or profile.BossCores < cores then
		return ("Need %d Rift Dust and %d Boss Cores"):format(dust, cores)
	end
	PlayerDataService.Mutate(player, function(data)
		data.RiftDust -= dust
		data.BossCores -= cores
		data.UnlockedWeapons[weaponId] = true
		if not data.WeaponMastery[weaponId] then
			data.WeaponMastery[weaponId] = { Level = 1, XP = 0, ParagonRank = 0 }
		end
	end)
	notify(player, ("%s %s %s! Equip it from your Bag."):format(info.Icon, info.Name,
		if state == false then "reactivated" else "forged"))
	return nil
end

local function equipWeapon(player: Player, profile: PlayerProfileData, weaponId: string): string?
	local info = WeaponConfig.Weapons[weaponId]
	if not info or profile.UnlockedWeapons[weaponId] ~= true then
		return "Unlock that weapon at the Blacksmith first"
	end
	if profile.EquippedWeapon == weaponId then
		return nil
	end
	PlayerDataService.Mutate(player, function(data)
		data.EquippedWeapon = weaponId
	end)
	WeaponHoldService.Refresh(player)
	notify(player, ("%s %s equipped"):format(info.Icon, info.Name))
	return nil
end

-- Equip from outside the Bag (the starter weapon rack, OnboardingService). Town only; reports errors as a toast.
function InventoryService.EquipWeapon(player: Player, weaponId: string)
	local profile = PlayerDataService.Get(player)
	if not profile or RunManagerService.GetRunOf(player) then
		return
	end
	local err = equipWeapon(player, profile, weaponId)
	if err then
		notify(player, err)
	end
end

local function equipLink(player: Player, profile: PlayerProfileData, linkId: string): string?
	local weapon = WeaponConfig.GetWeaponForLink(linkId)
	if not weapon then
		return "Unknown Link Skill"
	end
	local entry = profile.WeaponMastery[weapon.Id]
	if not entry or entry.Level < WeaponConfig.LINK_TIER1_LEVEL then
		return ("Reach %s Mastery %d to unlock %s"):format(weapon.Name, WeaponConfig.LINK_TIER1_LEVEL, weapon.Link.Name)
	end
	if table.find(profile.ActiveLinkSkills, linkId) then
		return nil
	end
	if #profile.ActiveLinkSkills >= InventoryService.GetLinkSlots(player, profile) then
		return "All Link Skill slots are full. Unequip one first."
	end
	PlayerDataService.Mutate(player, function(data)
		table.insert(data.ActiveLinkSkills, linkId)
	end)
	return nil
end

local function equipRelic(player: Player, profile: PlayerProfileData, relicId: string): string?
	if not RelicConfig.Relics[relicId] or not profile.RelicStars[relicId] then
		return "Find that Relic in a run first"
	end
	if table.find(profile.EquippedStartingRelics, relicId) then
		return nil
	end
	if #profile.EquippedStartingRelics >= InventoryService.GetRelicSlots(player, profile) then
		return "All Starting Relic slots are full. Unequip one first."
	end
	PlayerDataService.Mutate(player, function(data)
		table.insert(data.EquippedStartingRelics, relicId)
	end)
	return nil
end

local function reforgeEntryOf(data: PlayerProfileData, weaponId: string): PlayerDataService.ReforgeEntry
	local entry = data.WeaponReforge[weaponId]
	if not entry then
		entry = { Tier = nil, Rolls = 0, PityEpic = 0, PityLegend = 0, Pending = nil }
		data.WeaponReforge[weaponId] = entry
	end
	return entry
end

local function announceRoll(player: Player, info: WeaponConfig.WeaponInfo, tier: ReforgeConfig.Tier)
	local title = ("%s %s"):format(tier.Name, info.Name)
	if tier.Id == "Mythic" then
		celebrateRemote:FireAllClients({
			Kind = "Mythic", Icon = tier.Icon, Color = tier.Color, Forger = player.UserId,
			Title = "MYTHIC FORGED!",
			Body = ("🔥 %s just forged a MYTHIC [%s] (1 in 100)!"):format(player.DisplayName, title),
		})
	elseif tier.Id == "Legendary" then
		celebrateRemote:FireClient(player, { Kind = "Reforge", Icon = tier.Icon, Color = tier.Color,
			Title = "Legendary Reforge!", Body = title })
	else
		notify(player, ("%s %s · %s"):format(tier.Icon, tier.Id, title))
	end
end

-- Blacksmith reforge roll: the first roll applies, later ones wait for Keep / Discard.
local function reforgeWeapon(player: Player, profile: PlayerProfileData, weaponId: string): string?
	local info = WeaponConfig.Weapons[weaponId]
	if not info or profile.UnlockedWeapons[weaponId] ~= true then
		return "Forge that weapon before reforging it"
	end
	local current = profile.WeaponReforge[weaponId]
	if current and current.Pending then
		return "Keep or discard your last roll first"
	end
	local dust = ReforgeConfig.Cost(info.UnlockCost)
	if profile.RiftDust < dust or profile.BossCores < ReforgeConfig.CORE_COST then
		return ("Need %d Rift Dust and %d Boss Core"):format(dust, ReforgeConfig.CORE_COST)
	end
	local rolled: ReforgeConfig.Tier? = nil
	local applied = false
	PlayerDataService.Mutate(player, function(data)
		data.RiftDust -= dust
		data.BossCores -= ReforgeConfig.CORE_COST
		local entry = reforgeEntryOf(data, weaponId)
		local tier = ReforgeConfig.Roll(rng, entry)
		entry.Rolls += 1
		if entry.Tier == nil then
			entry.Tier = tier.Id
			applied = true
		else
			entry.Pending = tier.Id
		end
		if tier.Id == "Mythic" then
			data.Stats.MythicReforges = (data.Stats.MythicReforges or 0) + 1
		end
		rolled = tier
	end)
	if rolled then
		announceRoll(player, info, rolled)
	end
	if applied then
		WeaponHoldService.Refresh(player)
		reforgedEvent:Fire(player)
	end
	return nil
end

local function resolveReforge(player: Player, profile: PlayerProfileData, weaponId: string, keepNew: boolean): string?
	local entry = profile.WeaponReforge[weaponId]
	if not entry or not entry.Pending then
		return nil
	end
	PlayerDataService.Mutate(player, function(data)
		local live = data.WeaponReforge[weaponId]
		if live and live.Pending then
			if keepNew then
				live.Tier = live.Pending
			end
			live.Pending = nil
		end
	end)
	if keepNew then
		WeaponHoldService.Refresh(player)
		reforgedEvent:Fire(player)
	end
	return nil
end

local function removeFrom(player: Player, field: "ActiveLinkSkills" | "EquippedStartingRelics", id: string)
	PlayerDataService.Mutate(player, function(data)
		local list = data[field]
		local index = table.find(list, id)
		if index then
			table.remove(list, index)
		end
	end)
end

local function onAction(player: Player, payload: any)
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_COOLDOWN or type(payload) ~= "table" then
		return
	end
	lastAction[player] = now
	local profile = PlayerDataService.Get(player)
	local action = payload.Action
	if not profile or type(action) ~= "string" then
		return
	end
	-- Loadout changes happen in Haven Outpost; the Bag is read-only during a run.
	if RunManagerService.GetRunOf(player) then
		notify(player, "Return to Haven Outpost to change your loadout")
		return
	end

	local err: string? = nil
	if action == "Unlock" and type(payload.Weapon) == "string" then
		err = unlockWeapon(player, profile, payload.Weapon)
	elseif action == "Equip" and type(payload.Weapon) == "string" then
		err = equipWeapon(player, profile, payload.Weapon)
	elseif action == "EquipLink" and type(payload.Link) == "string" then
		err = equipLink(player, profile, payload.Link)
	elseif action == "UnequipLink" and type(payload.Link) == "string" then
		removeFrom(player, "ActiveLinkSkills", payload.Link)
	elseif action == "EquipRelic" and type(payload.Relic) == "string" then
		err = equipRelic(player, profile, payload.Relic)
	elseif action == "UnequipRelic" and type(payload.Relic) == "string" then
		removeFrom(player, "EquippedStartingRelics", payload.Relic)
	elseif action == "Reforge" and type(payload.Weapon) == "string" then
		err = reforgeWeapon(player, profile, payload.Weapon)
	elseif (action == "ReforgeKeep" or action == "ReforgeDiscard") and type(payload.Weapon) == "string" then
		err = resolveReforge(player, profile, payload.Weapon, action == "ReforgeKeep")
	end
	if err then
		notify(player, err)
	end
end

function InventoryService.Init()
	Remotes.Init()
	notifyRemote = Remotes.GetEvent("Notify")
	celebrateRemote = Remotes.GetEvent("Celebrate")
	Remotes.GetEvent("LoadoutAction").OnServerEvent:Connect(onAction)

	-- Slot counts depend on Ascension nodes and passes; re-check whenever the profile loads or a pass changes.
	PlayerDataService.ProfileLoaded:Connect(function(player: Player, profile: PlayerProfileData)
		task.delay(3, function() -- passes are cached as attributes shortly after join
			if player.Parent and PlayerDataService.Get(player) == profile then
				trimLoadout(player, profile)
				PlayerDataService.Replicate(player)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return InventoryService
