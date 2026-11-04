--!strict
-- ServerScriptService/Server/Services/PlayerDataService.luau
-- DataStore-backed player profile wrapper (Section 28.2) with session locking (game.md Step SP-6). Everything goes
-- through Get / Wait / Mutate / Save, so callers never touch the DataStore.
--
-- Session locking: the stored record is { Data, Lock = { JobId, Time }, Version }. Loading claims the lock with
-- UpdateAsync; if another live server holds it (refreshed within LOCK_STALE_SECONDS) we wait for it to release,
-- then take it over. Every save checks the lock is still ours, so two servers can never write the same profile.
--
-- Save / loot race: services that hold unsettled rewards (RunManagerService's Unsecured Pouch) register with
-- BeforeRelease. When a player leaves or the server shuts down those hooks run first, then the final save writes
-- the settled profile and releases the lock. Saves for one player are serialized, and nothing saves after release.
--
-- Studio without "Enable Studio Access to API Services" falls back to an unsaved in-memory profile.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))

export type MasteryEntry = { Level: number, XP: number, ParagonRank: number }
-- Weapon Reforge (ReforgeConfig): the applied tier, roll count, pity counters and an un-kept new roll.
export type ReforgeEntry = { Tier: string?, Rolls: number, PityEpic: number, PityLegend: number, Pending: string? }

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
	UnlockedWeapons: { [string]: boolean }, -- false = owned but switched off by a Standard rebirth
	WeaponMastery: { [string]: MasteryEntry },
	WeaponReforge: { [string]: ReforgeEntry }, -- [WeaponId] = reforge state (game.md 7.4 B)
	ActiveLinkSkills: { string },
	UnlockedWorlds: { [number]: number }, -- [WorldIndex] = HighestCorruptionTierUnlocked
	AscensionNodes: { [string]: number }, -- [NodeId] = Level
	RelicStars: { [string]: { Stars: number, PityCount: number } }, -- the permanent Relic Collection
	EquippedStartingRelics: { string },

	-- Monetization / rebirth bookkeeping
	KeepEverythingSeals: number, -- 99 R$ single-use "Keep Everything" rebirths
	SuperchargedTokens: number, -- spent automatically on the next run start
	BonusRerolls: number, -- banked Reroll Pack charges, used after the run's free rerolls
	StarForceSafeguards: number, -- refund the Relic Shards of a failed Star-Force attempt
	PendingSkipCredits: { number }, -- paid Instant Rebirth prices waiting for a matching progress tier
	ProcessedReceipts: { string }, -- recent PurchaseIds, so a retried ProcessReceipt never double-grants

	-- Step SP-6
	Stats: { [string]: number }, -- lifetime counters (Kills, BossKills, HighestRoom, ...) for quests & leaderboards
	Quests: { Day: number, Daily: { string }, Progress: { [string]: number }, Claimed: { [string]: boolean } },

	-- Settings screen (client preferences, saved with the profile)
	Settings: { SfxVolume: number, ScreenShake: boolean, AutoAttack: boolean },

	-- "While You Were Away" (game.md 3.7, SanctuaryService): stamped on every save; unclaimed offline training waits
	-- here (Minutes = 0 means nothing pending) so leaving before claiming never loses it.
	LastSeenAt: number, -- os.time() of the last save, 0 = never saved
	OfflineTraining: { Minutes: number, Dust: number, Mastery: number },
}

type LockInfo = { JobId: string, Time: number, Session: string }

local STORE_NAME = "RiftRushProfiles_v1"
local RECORD_VERSION = 2
local AUTOSAVE_INTERVAL = 90
local MAX_RETRIES = 4
local LOCK_STALE_SECONDS = 3 * AUTOSAVE_INTERVAL + 60 -- a lock not refreshed for this long belongs to a dead server
local LOCK_WAIT_ATTEMPTS = 6
local LOCK_WAIT_SECONDS = 5

local PlayerDataService = {}

local store: DataStore? = nil
local sessionId = HttpService:GenerateGUID(false) -- unique even in Studio, where every JobId is ""
local profiles: { [Player]: PlayerProfileData } = {}
local ephemeral: { [Player]: boolean } = {} -- true when load failed and the profile must NOT be saved
local saving: { [Player]: boolean } = {}
local released: { [Player]: boolean } = {}
local releaseHooks: { (Player, string) -> () } = {}
local loadedEvent = Instance.new("BindableEvent")
local profileUpdated: RemoteEvent? = nil

PlayerDataService.ProfileLoaded = loadedEvent.Event :: RBXScriptSignal
local replicatedEvent = Instance.new("BindableEvent")
-- Fires after every replication to the owner (i.e. after each Mutate), so derived values like Rift Power can follow.
PlayerDataService.Replicated = replicatedEvent.Event :: RBXScriptSignal

local function newDefaultProfile(): PlayerProfileData
	local unlocked: { [string]: boolean } = {}
	local mastery: { [string]: MasteryEntry } = {}
	for _, weaponId in WeaponConfig.Order do
		if WeaponConfig.IsStarter(weaponId) then
			unlocked[weaponId] = true
			mastery[weaponId] = { Level = 1, XP = 0, ParagonRank = 0 }
		end
	end
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
		UnlockedWeapons = unlocked,
		WeaponMastery = mastery,
		WeaponReforge = {},
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

		Stats = {},
		Quests = { Day = 0, Daily = {}, Progress = {}, Claimed = {} },
		Settings = { SfxVolume = 1, ScreenShake = true, AutoAttack = false },
		LastSeenAt = 0,
		OfflineTraining = { Minutes = 0, Dust = 0, Mastery = 0 },
	}
end

-- Fill in any key missing from `data` using `defaults`, recursing into plain dictionaries only.
-- Arrays and keyed collections (UnlockedWeapons, RelicStars, ...) keep whatever the player has.
local DICT_KEYS_NO_RECURSE: { [string]: boolean } = {
	UnlockedWeapons = true, WeaponMastery = true, WeaponReforge = true, ActiveLinkSkills = true, UnlockedWorlds = true,
	AscensionNodes = true, RelicStars = true, EquippedStartingRelics = true,
	PendingSkipCredits = true, ProcessedReceipts = true, Stats = true,
	Daily = true, Progress = true, Claimed = true,
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

-- Profiles saved before weapons 2-3 became starters (or before mastery entries were created lazily) catch up here.
local function migrate(data: PlayerProfileData)
	for _, weaponId in WeaponConfig.Order do
		if WeaponConfig.IsStarter(weaponId) then
			data.UnlockedWeapons[weaponId] = true
		end
		if data.UnlockedWeapons[weaponId] ~= nil and not data.WeaponMastery[weaponId] then
			data.WeaponMastery[weaponId] = { Level = 1, XP = 0, ParagonRank = 0 }
		end
	end
	if not WeaponConfig.Weapons[data.EquippedWeapon] or data.UnlockedWeapons[data.EquippedWeapon] ~= true then
		data.EquippedWeapon = WeaponConfig.DEFAULT_WEAPON
	end
end

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value :: any do
		copy[key] = deepCopy(inner)
	end
	return copy :: any
end

-- DataStore cannot hold numeric-keyed sparse tables, so UnlockedWorlds is stored with string keys. The snapshot is
-- a deep copy, so gameplay mutating the live profile while UpdateAsync yields cannot tear the saved record.
local function encode(data: PlayerProfileData): { [string]: any }
	local copy = deepCopy(data) :: any
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
	local data = raw :: any
	migrate(data)
	return data
end

local function keyFor(player: Player): string
	return "Player_" .. player.UserId
end

-- Records written before session locking were the bare profile table.
local function unwrap(record: any): ({ [string]: any }?, LockInfo?)
	if type(record) ~= "table" then
		return nil, nil
	end
	if record.Version ~= nil and (type(record.Data) == "table" or record.Data == nil) then
		local lock = record.Lock
		return record.Data, if type(lock) == "table" then lock :: any else nil
	end
	return record, nil
end

-- A lock held by another live server. Studio sessions (JobId "") never block each other: the previous playtest
-- is always gone by the time the next one loads.
local function isForeignLock(lock: LockInfo?): boolean
	if lock == nil or lock.Session == sessionId then
		return false
	end
	if RunService:IsStudio() and lock.JobId == "" then
		return false
	end
	return os.time() - (tonumber(lock.Time) or 0) < LOCK_STALE_SECONDS
end

local function ourLock(): LockInfo
	return { JobId = game.JobId, Time = os.time(), Session = sessionId }
end

-- Studio without "Enable Studio Access to API Services" fails every call; retrying only delays the profile.
local function isStudioAccessDenied(err: string): boolean
	if not RunService:IsStudio() then
		return false
	end
	-- Roblox has used several wordings for this over time.
	for _, needle in { "Studio access to APIs is not allowed", "API access is not enabled", "StudioAccessToApisNotAllowed" } do
		if string.find(err, needle, 1, true) then
			return true
		end
	end
	return false
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if isStudioAccessDenied(tostring(result)) then
			warn("[PlayerDataService] Studio API access is off (Game Settings > Security); using unsaved profiles.")
			store = nil
			return false, nil
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
		replicatedEvent:Fire(player)
	end
end

-- Claims the session lock and returns the stored profile. ok=false means the DataStore failed (use an unsaved
-- profile); locked=true means another server still holds the lock after waiting.
local function claimProfile(player: Player): (boolean, { [string]: any }?, boolean)
	local finalData: { [string]: any }? = nil
	for attempt = 1, LOCK_WAIT_ATTEMPTS do
		local locked = false
		local force = attempt == LOCK_WAIT_ATTEMPTS
		local ok = withRetries("Load " .. keyFor(player), function()
			(store :: DataStore):UpdateAsync(keyFor(player), function(old: any)
				local data, lock = unwrap(old)
				finalData = data
				locked = false
				if isForeignLock(lock) and not force then
					locked = true
					return nil -- leave the record alone and wait for the other server
				end
				if lock and isForeignLock(lock) then
					warn(("[PlayerDataService] Taking over %s's session from server %s"):format(player.Name, tostring(lock.JobId)))
				end
				return { Version = RECORD_VERSION, Data = data, Lock = ourLock() }
			end)
			return true
		end)
		if not ok then
			return false, nil, false
		end
		if not locked then
			return true, finalData, false
		end
		if not player.Parent then
			return true, nil, true
		end
		task.wait(LOCK_WAIT_SECONDS)
	end
	return true, finalData, true
end

local function loadProfile(player: Player)
	local data: PlayerProfileData? = nil

	if store then
		local ok, raw = claimProfile(player)
		if ok then
			data = if raw then decode(raw) else newDefaultProfile()
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

-- Writes the profile if this server still owns its session. `release` drops the lock (the player is leaving).
local function writeProfile(player: Player, release: boolean): boolean
	local data = profiles[player]
	if not data or ephemeral[player] or not store then
		return false
	end
	data.LastSeenAt = os.time() -- offline training counts from the last save (autosave keeps it within 90s)
	local snapshot = encode(data)
	local lostLock = false
	local ok = withRetries("Save " .. keyFor(player), function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old: any)
			local _, lock = unwrap(old)
			lostLock = false
			if lock and lock.Session ~= sessionId then
				lostLock = true
				return nil
			end
			return { Version = RECORD_VERSION, Data = snapshot, Lock = if release then nil else ourLock() }
		end)
		return true
	end)
	if lostLock then
		warn(("[PlayerDataService] %s's profile is now owned by another server; this copy will not be saved."):format(player.Name))
		ephemeral[player] = true
		if player.Parent and not release then
			player:Kick("Your Rift Rush profile was opened on another server. Please rejoin.")
		end
		return false
	end
	return ok
end

-- Saves are serialized per player; nothing saves after the final release.
local function saveSerial(player: Player, release: boolean): boolean
	while saving[player] do
		task.wait(0.1)
	end
	if released[player] then
		return false
	end
	saving[player] = true
	local ok, result = pcall(writeProfile, player, release)
	if release then
		released[player] = true
	end
	saving[player] = nil
	if not ok then
		warn("[PlayerDataService] save error: " .. tostring(result))
		return false
	end
	return result
end

function PlayerDataService.Save(player: Player): boolean
	return saveSerial(player, false)
end

-- Registers a hook that runs before a profile's final save (reason: "Leaving" | "Shutdown"). Hooks must not yield;
-- they settle anything still owed to the player (e.g. the run's Unsecured Pouch) through Mutate.
function PlayerDataService.BeforeRelease(hook: (Player, string) -> ())
	table.insert(releaseHooks, hook)
end

local function release(player: Player, reason: string)
	if not profiles[player] or released[player] then
		return
	end
	for _, hook in releaseHooks do
		local ok, err = pcall(function(): any
			hook(player, reason)
			return nil
		end)
		if not ok then
			warn("[PlayerDataService] release hook failed: " .. tostring(err))
		end
	end
	saveSerial(player, true)
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

-- Adds `amount` to a lifetime stat (or raises it to `amount` when `isMax`). Does not replicate.
function PlayerDataService.BumpStat(player: Player, stat: string, amount: number, isMax: boolean?)
	local data = profiles[player]
	if not data then
		return
	end
	local current = data.Stats[stat] or 0
	data.Stats[stat] = if isMax then math.max(current, amount) else current + amount
end

function PlayerDataService.Init()
	Remotes.Init()
	profileUpdated = Remotes.GetEvent("ProfileUpdated")

	local getProfile = Remotes.GetFunction("GetProfile")
	getProfile.OnServerInvoke = function(player: Player)
		return PlayerDataService.Wait(player)
	end

	-- SaveSettings { SfxVolume = 0..1 in quarter steps, ScreenShake = boolean, AutoAttack = boolean }: client-side
	-- preferences (Auto-Attack only paces the client's own attack requests), so only shape-checked. Missing keys stay.
	local lastSettings: { [Player]: number } = {}
	Remotes.GetEvent("SaveSettings").OnServerEvent:Connect(function(player: Player, payload: any)
		local now = os.clock()
		if type(payload) ~= "table" or now - (lastSettings[player] or 0) < 0.25 or not profiles[player] then
			return
		end
		lastSettings[player] = now
		local volume = tonumber(payload.SfxVolume)
		PlayerDataService.Mutate(player, function(data)
			if volume and volume == volume then
				data.Settings.SfxVolume = math.clamp(math.round(volume * 4) / 4, 0, 1)
			end
			if type(payload.ScreenShake) == "boolean" then
				data.Settings.ScreenShake = payload.ScreenShake
			end
			if type(payload.AutoAttack) == "boolean" then
				data.Settings.AutoAttack = payload.AutoAttack
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSettings[player] = nil
	end)

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
		release(player, "Leaving")
		profiles[player] = nil
		ephemeral[player] = nil
		released[player] = nil
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
				release(player, "Shutdown")
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
