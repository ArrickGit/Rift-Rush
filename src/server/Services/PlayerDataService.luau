--!strict
-- ServerScriptService/Server/Services/PlayerDataService.luau
-- DataStore-backed player profile wrapper (Section 28.2). Swap the storage calls for ProfileStore later
-- without touching callers: everything goes through Get / Wait / Mutate / Save.
--
-- Studio without "Enable Studio Access to API Services" falls back to an unsaved in-memory profile.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))

export type PlayerProfileData = {
	HunterLevel: number,
	HunterXP: number,
	RebirthTier: number,
	LegacyBonusLevels: number,
	RebirthSparksAvailable: number,
	RebirthSparksTotalEarned: number,
	RunsSinceLastRebirth: number,

	RiftDust: number,
	ProtectedDustVault: number,
	BossCores: number,
	RelicShards: number,
	AnchorTokens: number,

	EquippedWeapon: string,
	UnlockedWeapons: { [string]: boolean },
	WeaponMastery: { [string]: { Level: number, XP: number, ParagonRank: number } },
	ActiveLinkSkills: { string },
	UnlockedWorlds: { [number]: number }, -- [WorldIndex] = HighestCorruptionTierUnlocked
	AscensionNodes: { [string]: number }, -- [NodeId] = Level
	RelicStars: { [string]: { Stars: number, PityCount: number } },
	EquippedStartingRelics: { string },

	-- Step 5 (monetization / rebirth bookkeeping; not in the Section 28.2 schema)
	KeepEverythingSeals: number, -- 99 R$ single-use "Keep Everything" rebirths
	SuperchargedTokens: number, -- spent automatically on the next run start
	BonusRerolls: number, -- banked Reroll Pack charges, used after the run's free rerolls
	StarForceSafeguards: number, -- consumed by the Star-Forge (later step)
	PendingSkipCredits: { number }, -- paid Instant Rebirth prices waiting for a matching progress tier
	ProcessedReceipts: { string }, -- recent PurchaseIds, so a retried ProcessReceipt never double-grants
}

local STORE_NAME = "RiftRushProfiles_v1"
local AUTOSAVE_INTERVAL = 90
local MAX_RETRIES = 4

local PlayerDataService = {}

local store: DataStore? = nil
local profiles: { [Player]: PlayerProfileData } = {}
local ephemeral: { [Player]: boolean } = {} -- true when load failed and the profile must NOT be saved
local loadedEvent = Instance.new("BindableEvent")
local profileUpdated: RemoteEvent? = nil

PlayerDataService.ProfileLoaded = loadedEvent.Event :: RBXScriptSignal

local function newDefaultProfile(): PlayerProfileData
	return {
		HunterLevel = 1,
		HunterXP = 0,
		RebirthTier = 0,
		LegacyBonusLevels = 0,
		RebirthSparksAvailable = 0,
		RebirthSparksTotalEarned = 0,
		RunsSinceLastRebirth = 0,

		RiftDust = 0,
		ProtectedDustVault = 0,
		BossCores = 0,
		RelicShards = 0,
		AnchorTokens = 0,

		EquippedWeapon = WeaponConfig.DEFAULT_WEAPON,
		UnlockedWeapons = { [WeaponConfig.DEFAULT_WEAPON] = true },
		WeaponMastery = { [WeaponConfig.DEFAULT_WEAPON] = { Level = 1, XP = 0, ParagonRank = 0 } },
		ActiveLinkSkills = {},
		UnlockedWorlds = { [1] = 0 },
		AscensionNodes = {},
		RelicStars = {},
		EquippedStartingRelics = {},

		KeepEverythingSeals = 0,
		SuperchargedTokens = 0,
		BonusRerolls = 0,
		StarForceSafeguards = 0,
		PendingSkipCredits = {},
		ProcessedReceipts = {},
	}
end

-- Fill in any key missing from `data` using `defaults`, recursing into plain dictionaries only.
-- Arrays and keyed collections (UnlockedWeapons, RelicStars, ...) keep whatever the player has.
local DICT_KEYS_NO_RECURSE: { [string]: boolean } = {
	UnlockedWeapons = true, WeaponMastery = true, ActiveLinkSkills = true, UnlockedWorlds = true,
	AscensionNodes = true, RelicStars = true, EquippedStartingRelics = true,
	PendingSkipCredits = true, ProcessedReceipts = true,
}

local function reconcile(data: { [any]: any }, defaults: { [any]: any })
	for key, defaultValue in defaults do
		if data[key] == nil then
			data[key] = if type(defaultValue) == "table" then table.clone(defaultValue) else defaultValue
		elseif type(defaultValue) == "table" and type(data[key]) == "table"
			and not (type(key) == "string" and DICT_KEYS_NO_RECURSE[key]) then
			reconcile(data[key], defaultValue)
		end
	end
end

-- DataStore cannot hold numeric-keyed sparse tables, so UnlockedWorlds is stored with string keys.
local function encode(data: PlayerProfileData): { [string]: any }
	local copy = table.clone(data) :: any
	local worlds: { [string]: number } = {}
	for index, tier in data.UnlockedWorlds do
		worlds[tostring(index)] = tier
	end
	copy.UnlockedWorlds = worlds
	return copy
end

local function decode(raw: { [string]: any }): PlayerProfileData
	local worlds: { [number]: number } = {}
	local stored = raw.UnlockedWorlds
	if type(stored) == "table" then
		for key, tier in stored do
			local index = tonumber(key)
			if index and type(tier) == "number" then
				worlds[index] = tier
			end
		end
	end
	raw.UnlockedWorlds = worlds
	reconcile(raw, newDefaultProfile() :: any)
	return raw :: any
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[PlayerDataService] %s failed (attempt %d/%d): %s"):format(label, attempt, MAX_RETRIES, tostring(result)))
		task.wait(2 ^ (attempt - 1))
	end
	return false, nil
end

function PlayerDataService.Replicate(player: Player)
	local data = profiles[player]
	if data and profileUpdated and player.Parent then
		profileUpdated:FireClient(player, data)
	end
end

local function loadProfile(player: Player)
	local data: PlayerProfileData? = nil

	if store then
		local ok, raw = withRetries("GetAsync " .. keyFor(player), function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok then
			data = if type(raw) == "table" then decode(raw :: any) else newDefaultProfile()
		end
	end

	if not data then
		-- Never overwrite a real save with defaults after a failed load.
		ephemeral[player] = true
		data = newDefaultProfile()
	end

	if not player.Parent then
		return -- left while loading
	end

	local loaded = data :: PlayerProfileData
	profiles[player] = loaded
	loadedEvent:Fire(player, loaded)
	PlayerDataService.Replicate(player)
end

function PlayerDataService.Save(player: Player): boolean
	local data = profiles[player]
	if not data or ephemeral[player] or not store then
		return false
	end
	local snapshot = encode(data)
	local ok = withRetries("SetAsync " .. keyFor(player), function()
		(store :: DataStore):UpdateAsync(keyFor(player), function()
			return snapshot
		end)
		return true
	end)
	return ok
end

-- True when the profile failed to load (or DataStores are off in Studio) and will never be saved.
function PlayerDataService.IsEphemeral(player: Player): boolean
	return ephemeral[player] == true or store == nil
end

-- Returns the live profile (mutable), or nil if not loaded yet.
function PlayerDataService.Get(player: Player): PlayerProfileData?
	return profiles[player]
end

-- Yields until the profile is loaded; nil if the player leaves first.
function PlayerDataService.Wait(player: Player): PlayerProfileData?
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

-- Safe mutation entry point: runs `fn` on the live profile, then replicates to the owning client.
function PlayerDataService.Mutate(player: Player, fn: (PlayerProfileData) -> ())
	local data = profiles[player]
	if not data then
		return
	end
	fn(data)
	PlayerDataService.Replicate(player)
end

function PlayerDataService.Init()
	Remotes.Init()
	profileUpdated = Remotes.GetEvent("ProfileUpdated")

	local getProfile = Remotes.GetFunction("GetProfile")
	getProfile.OnServerInvoke = function(player: Player)
		return PlayerDataService.Wait(player)
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerDataService] DataStore unavailable; profiles will not persist. " .. tostring(result))
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadProfile, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadProfile, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		PlayerDataService.Save(player)
		profiles[player] = nil
		ephemeral[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player in profiles do
				task.spawn(PlayerDataService.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() then
			task.wait(0.5)
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				PlayerDataService.Save(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
