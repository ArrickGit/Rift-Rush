--!strict
-- ServerScriptService/Server/Services/RunManagerService.luau
-- Portal run state machine (Sections 5.2, 6.2, 18, 19, 20): room sequencing, enemy spawning, Rift Anchors
-- (Rooms 5/10/15...), individual extraction, defeat penalties and the Anchor Token / paid recovery hooks.
--
-- Everything economic is decided here on the server through FormulaEngine. Hunter XP is credited straight to the
-- profile (never lost); Rift Dust / Relic Shards / Boss Cores wait in a per-player Unsecured Pouch until a Rift
-- Anchor secures them or the player is defeated.
--
-- Hooks for later steps:
--   * CombatService calls RunManagerService.ReportEnemyDefeated(enemyModel, killer) when an enemy dies. Enemies
--     are tagged ENEMY_TAG and carry MaxHP / HP / Attack / XPValue / EnemyKind attributes; EnemyAIService picks
--     them up from the tag and moves them.
--   * CombatService sets RunManagerService.RunHpMultProvider so run upgrades (Vital Surge) survive Revive / Rewind.
--   * MonetizationService calls ResolveDefeat(player, "Revive" | "Rewind" | "Insure", "Robux") after it has
--     validated the purchase receipt, and sets the HasInsurancePass / HasDoubleXP / HasDoubleDust player attributes.
--   * TownHubService provides a BasePart named "TownSpawn" in Workspace for extraction landings.
--   * MonetizationService calls HoldDefeat while a Robux recovery prompt is open, and sets the Workspace
--     RiftSurgeEndsAt attribute that boosts everyone's XP / Dust. Supercharged Run Tokens are spent in StartRun.
--   * CombatService listens to RoomCleared to offer Upgrade cards, and LootEvent ("Chest" / "Anchor") for Treasure
--     Tooth. It sets DustMultProvider (Hungry Coin) alongside RunHpMultProvider.
--   * RelicService sets RelicDropHandler(player, run, source) and is called for every boss Anchor
--     ("MiniBoss" / "WorldBoss") and opened chest ("Chest"); it rolls the drop itself.
--   * Treasure rooms raise Rift Shrine curse altars (CurseConfig); accepted curses live on the RunPlayer and are
--     read back through GetCurseMods. HazardService reads GetActiveRuns / GetPoisonTop for the acid flood.
--   * Kills award Weapon Mastery XP (MasteryService) and feed lifetime stats / quests (QuestService).
--   * PlayerDataService.BeforeRelease settles a leaving player's pouch before their final save.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local CurseConfig = require(Shared:WaitForChild("CurseConfig"))
local EnemyConfig = require(Shared:WaitForChild("EnemyConfig"))
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local Physics25D = require(Shared:WaitForChild("Physics25D"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RoomAsciiTemplates = require(Shared:WaitForChild("RoomAsciiTemplates"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local MasteryService = require(script.Parent:WaitForChild("MasteryService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))
local RoomBuilderService = require(script.Parent:WaitForChild("RoomBuilderService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData
type BuiltRoom = RoomBuilderService.BuiltRoom

export type LootBag = { Dust: number, BossCores: number, RelicShards: number }
type EnemyKind = "Normal" | "Elite" | "Boss"
type SettleMode = "All" | "Defeat" | "None"

type RunPlayer = {
	Player: Player,
	Status: "Alive" | "Defeated",
	Secured: LootBag,
	Unsecured: LootBag,
	Decision: ("Extract" | "Push")?,
	DefeatDeadline: number,
	DeathCFrame: CFrame?,
	PendingSpawn: CFrame?, -- where the next character spawns (Revive); nil = room spawn
	Shielded: boolean, -- Revive grants a short ForceField on the next spawn
	Supercharged: boolean, -- a Supercharged Run Token was spent on this run
	Curses: { string }, -- CurseConfig ids accepted at Rift Shrine altars this run
}

type ActiveRoom = {
	Built: BuiltRoom,
	Type: RoomAsciiTemplates.RoomType,
	Objective: string,
	Cleared: boolean,
	PaidOut: boolean,
	ExitOpen: boolean,
	ExitEnteredAt: number?,
	Enemies: { [Model]: boolean },
	EnemiesTotal: number,
	EnemiesLeft: number,
	Chests: { BasePart },
	ChestsForfeited: boolean,
	PoisonTop: number,
	CurseOffers: { string }, -- curse ids on this room's altars that nobody has taken yet
}

export type Run = {
	Id: number,
	Slot: number,
	Host: Player, -- the party leader whose power Rift Sidekick Sync compares teammates against
	Folder: Folder,
	Origin: Vector3,
	WorldIndex: number,
	Corruption: number,
	Depth: number,
	Phase: "Room" | "Anchor" | "Ended",
	LastAnchorDepth: number,
	AnchorDeadline: number,
	Players: { [Player]: RunPlayer },
	Rng: Random,
	Room: ActiveRoom?,
}

local RunManagerService = {}

RunManagerService.ENEMY_TAG = EnemyConfig.TAG

-- Tuning ------------------------------------------------------------------------------------------------------

local ROOM_DUST_BASE = 40
local ROOM_DUST_PER_ROOM = 4
local ROOM_DUST_FACTOR: { [string]: number } = { Combat = 1.0, Boss = 1.5, Jump = 0.4, Treasure = 0.4 }
local CHEST_DUST_FACTOR = 0.6
local CHEST_SHARD_CHANCE = 0.3
local BOSS_SHARD_BASE = 1

local MAX_PLAYERS = 4
local MAX_CORRUPTION = 999
local MAX_WORLD = 8
local ANCHOR_DECISION_SECONDS = 45
local DEFEAT_CHOICE_SECONDS = 60
local EXIT_STRAGGLER_SECONDS = 6
local REVIVE_SHIELD_SECONDS = 4
local OUT_OF_RUN_RESPAWN_SECONDS = 3
local RESPAWN_TIME_OVERRIDE = 3600 -- we respawn players ourselves so the defeat screen can decide where they land
local PARTY_SPAWN_SCALE_PER_PLAYER = 0.25
-- Early-room mercy (game.md 2.4 / B25): World 1, Corruption 0, non-boss enemies hit softer in the first rooms and
-- ramp back to full strength by Room 9. Index = room number; rooms past the table use 1.0.
local EARLY_ATK_MULT: { number } = { 0.65, 0.65, 0.65, 0.65, 0.70, 0.78, 0.86, 0.93 }

local RUN_ORIGIN = Vector3.new(2000, 300, 0)
local RUN_SLOT_SPACING = 400
local TICK_SECONDS = 0.1
local START_REQUEST_COOLDOWN = 1

-- Ascension Shop node ids (Section 23)
local NODE_MIGHT = "AS_T1_01"
local NODE_SCHOLAR = "AS_T1_02"
local NODE_POCKET = "AS_T1_05"
local NODE_GUARDIAN = "AS_T2_03"
local NODE_TROPHY = "AS_T2_04"
local NODE_PROSPERITY = "AS_INF_02"

-- State -------------------------------------------------------------------------------------------------------

local runs: { [number]: Run } = {}
local playerRun: { [Player]: Run } = {}
local usedSlots: { [number]: boolean } = {}
local nextRunId = 1

-- Set by CombatService: (player) -> multiplier applied to Max HP by run upgrades (1 = none).
RunManagerService.RunHpMultProvider = nil :: ((Player) -> number)?
-- Set by CombatService: (player) -> extra Rift Dust multiplier from run relics (Hungry Coin; 1 = none).
RunManagerService.DustMultProvider = nil :: ((Player) -> number)?
-- Set by RelicService: rolls (and grants) a relic drop. source: "MiniBoss" | "WorldBoss" | "Chest".
RunManagerService.RelicDropHandler = nil :: ((Player, Run, string) -> ())?

local lootEvent = Instance.new("BindableEvent")
-- Fires (player: Player, kind: "Chest" | "Anchor") when a player opens a chest or reaches a Rift Anchor alive.
RunManagerService.LootEvent = lootEvent.Event :: RBXScriptSignal

local runStateRemote: RemoteEvent
local notifyRemote: RemoteEvent

local roomClearedEvent = Instance.new("BindableEvent")
-- Fires (runId: number, roomNumber: number, players: { Player }) when a room is cleared / its exit is reached.
RunManagerService.RoomCleared = roomClearedEvent.Event :: RBXScriptSignal

-- Forward declarations
local loadRoom: (Run) -> ()
local leaveRun: (Run, Player, string, SettleMode, boolean) -> ()
local reportEnemyDefeated: (Model, Player?) -> ()

-- Helpers -----------------------------------------------------------------------------------------------------

local function emptyBag(): LootBag
	return { Dust = 0, BossCores = 0, RelicShards = 0 }
end

local function addBag(target: LootBag, extra: LootBag)
	target.Dust += extra.Dust
	target.BossCores += extra.BossCores
	target.RelicShards += extra.RelicShards
end

local function copyBag(bag: LootBag): LootBag
	return { Dust = bag.Dust, BossCores = bag.BossCores, RelicShards = bag.RelicShards }
end

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local function nodeLevel(profile: PlayerProfileData, nodeId: string): number
	return profile.AscensionNodes[nodeId] or 0
end

local function partySize(run: Run): number
	local count = 0
	for _ in run.Players do
		count += 1
	end
	return math.max(1, count)
end

local function snapshotPlayers(run: Run): { Player }
	local list = {}
	for player in run.Players do
		table.insert(list, player)
	end
	return list
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isCharacterAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function hasInsurancePass(player: Player): boolean
	return player:GetAttribute("HasInsurancePass") == true
end

local function curseMods(run: Run, player: Player): CurseConfig.CurseMods
	local runPlayer = run.Players[player]
	return CurseConfig.Combine(if runPlayer then runPlayer.Curses else {})
end

-- Server Rift Surge (Robux / milestone): everyone in the server earns extra XP & Dust while it lasts.
local function surgeMult(): number
	local endsAt = Workspace:GetAttribute(MonetizationConfig.RIFT_SURGE_ATTRIBUTE)
	return if MonetizationConfig.IsRiftSurgeActive(Workspace:GetServerTimeNow(), endsAt)
		then MonetizationConfig.RIFT_SURGE_ECO_MULT else 1
end

local function respawn(player: Player)
	task.spawn(function()
		if player.Parent then
			player:LoadCharacterAsync()
		end
	end)
end

local function getTownCFrame(): CFrame
	local named = Workspace:FindFirstChild("TownSpawn")
	if named and named:IsA("BasePart") then
		return named.CFrame + Vector3.new(0, named.Size.Y / 2 + 3, 0)
	end
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		return spawnLocation.CFrame + Vector3.new(0, spawnLocation.Size.Y / 2 + 3, 0)
	end
	return CFrame.new(0, 5, 0)
end

local function placeCharacter(player: Player, destination: CFrame)
	local character = player.Character
	local root = getRoot(player)
	if character and root then
		character:PivotTo(destination)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function returnToTown(player: Player)
	if isCharacterAlive(player) then
		placeCharacter(player, getTownCFrame())
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	else
		respawn(player)
	end
end

-- Profile math ------------------------------------------------------------------------------------------------

local function getHighestUnlocked(profile: PlayerProfileData): (number, number)
	local bestWorld, bestTier = 1, 0
	for world, tier in profile.UnlockedWorlds do
		if world > bestWorld then
			bestWorld, bestTier = world, tier
		end
	end
	return bestWorld, bestTier
end

local function getLinkBonus(profile: PlayerProfileData, stat: string): number
	return WeaponConfig.GetTotalLinkBonus(profile.ActiveLinkSkills, profile.WeaponMastery, stat)
end

-- M_World x M_CorrEco, ceilinged by the player's own highest unlocked tier (Rift Sidekick Sync, Section 18.2).
local function getEnvMult(profile: PlayerProfileData, run: Run): number
	local ownWorld, ownTier = getHighestUnlocked(profile)
	return FormulaEngine.GetCappedEnvMult(run.WorldIndex, run.Corruption, ownWorld, ownTier)
end

-- Section 24.1 XP_Gain
local function computeXP(player: Player, profile: PlayerProfileData, run: Run, baseXP: number): number
	local rebEco = FormulaEngine.GetRebirthInfo(profile.RebirthTier).EcoMult
	local sparkEco = 1 + 0.12 * nodeLevel(profile, NODE_SCHOLAR) + 0.05 * nodeLevel(profile, NODE_PROSPERITY)
	local passXP = if player:GetAttribute("HasDoubleXP") == true then 2 else 1
	local xp = baseXP * getEnvMult(profile, run) * FormulaEngine.GetDepthEcoMult(run.Depth) * rebEco
		* sparkEco * passXP * FormulaEngine.GetPartyXPMult(partySize(run)) * surgeMult()
	return math.max(1, math.round(xp))
end

-- Section 24.4 RoomDust, scaled by `factor` (room type / chest value)
local function computeDust(player: Player, profile: PlayerProfileData, run: Run, factor: number): number
	local rebEco = FormulaEngine.GetRebirthInfo(profile.RebirthTier).EcoMult
	local sparkEco = 1 + 0.05 * nodeLevel(profile, NODE_PROSPERITY)
	local mastery = profile.WeaponMastery[profile.EquippedWeapon]
	local paragon = if mastery then 0.005 * mastery.ParagonRank else 0
	local linkDust = 1 + getLinkBonus(profile, "DustDropRate") + paragon
	local passDust = if player:GetAttribute("HasDoubleDust") == true then 2 else 1
	local runPlayer = run.Players[player]
	local supercharge = if runPlayer and runPlayer.Supercharged then MonetizationConfig.SUPERCHARGE_DUST_MULT else 1
	local relicDust = if RunManagerService.DustMultProvider then RunManagerService.DustMultProvider(player) else 1
	local baseDust = ROOM_DUST_BASE + ROOM_DUST_PER_ROOM * run.Depth
	local dust = baseDust * factor * getEnvMult(profile, run) * FormulaEngine.GetDepthEcoMult(run.Depth) * rebEco
		* sparkEco * linkDust * passDust * supercharge * surgeMult() * relicDust * curseMods(run, player).DustMult
	return math.max(1, math.round(dust))
end

-- Adds XP and processes level-ups; XP stops at the level required for the next Rebirth. Returns levels gained.
local function addHunterXP(profile: PlayerProfileData, amount: number): number
	local levelCap = FormulaEngine.GetRebirthInfo(profile.RebirthTier + 1).ReqLevel
	local gained = 0
	profile.HunterXP += amount
	while profile.HunterLevel < levelCap do
		local needed = FormulaEngine.GetHunterXPRequired(profile.HunterLevel)
		if profile.HunterXP < needed then
			break
		end
		profile.HunterXP -= needed
		profile.HunterLevel += 1
		gained += 1
	end
	if profile.HunterLevel >= levelCap then
		profile.HunterXP = 0
	end
	return gained
end

local function creditLoot(player: Player, bag: LootBag)
	PlayerDataService.Mutate(player, function(profile)
		-- Dimensional Pocket routes a share of earned Dust into the Rebirth-safe vault.
		local pocketShare = math.min(1, 0.15 * nodeLevel(profile, NODE_POCKET))
		local vaulted = math.floor(bag.Dust * pocketShare)
		profile.ProtectedDustVault += vaulted
		profile.RiftDust += bag.Dust - vaulted
		profile.BossCores += bag.BossCores
		profile.RelicShards += bag.RelicShards
	end)
	if bag.Dust > 0 then
		PlayerDataService.BumpStat(player, "DustBanked", bag.Dust)
		QuestService.Track(player, "DustBanked", bag.Dust)
	end
end

-- Move a player's pouch into their profile according to `mode`; returns what was actually credited.
local function settle(run: Run, runPlayer: RunPlayer, mode: SettleMode): LootBag
	local credited = emptyBag()
	if mode == "All" then
		credited = copyBag(runPlayer.Unsecured)
	elseif mode == "Defeat" then
		local profile = PlayerDataService.Get(runPlayer.Player)
		local guardian = if profile then nodeLevel(profile, NODE_GUARDIAN) else 0
		local insured = hasInsurancePass(runPlayer.Player)
		local pouch = runPlayer.Unsecured
		credited = {
			Dust = FormulaEngine.CalculateDefeatDustKept(pouch.Dust, run.Depth, guardian, insured),
			BossCores = FormulaEngine.CalculateDefeatNonDustKept(pouch.BossCores, run.Depth, guardian, insured),
			RelicShards = FormulaEngine.CalculateDefeatNonDustKept(pouch.RelicShards, run.Depth, guardian, insured),
		}
	end
	runPlayer.Unsecured = emptyBag()
	if credited.Dust > 0 or credited.BossCores > 0 or credited.RelicShards > 0 then
		creditLoot(runPlayer.Player, credited)
		addBag(runPlayer.Secured, credited)
	end
	return credited
end

-- Client state ------------------------------------------------------------------------------------------------

local function buildPayload(run: Run, state: string, runPlayer: RunPlayer?): { [string]: any }
	local room = run.Room
	local profile = if runPlayer then PlayerDataService.Get(runPlayer.Player) else nil
	return {
		State = state,
		RunId = run.Id,
		World = run.WorldIndex,
		Corruption = run.Corruption,
		Room = run.Depth,
		RoomName = if room then room.Built.Template.Name else "",
		RoomType = if room then room.Type else "",
		Objective = if room then room.Objective else "",
		EnemiesLeft = if room then room.EnemiesLeft else 0,
		EnemiesTotal = if room then room.EnemiesTotal else 0,
		ExitOpen = if room then room.ExitOpen else false,
		PartySize = partySize(run),
		Secured = if runPlayer then runPlayer.Secured else emptyBag(),
		Unsecured = if runPlayer then runPlayer.Unsecured else emptyBag(),
		-- Kill XP only replicates the full profile on level-up, so the HUD XP bar reads these mid-run.
		HunterLevel = if profile then profile.HunterLevel else nil,
		HunterXP = if profile then profile.HunterXP else nil,
	}
end

local function pushState(run: Run, player: Player, state: string, extra: { [string]: any }?)
	local payload = buildPayload(run, state, run.Players[player])
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end
	runStateRemote:FireClient(player, payload)
end

local function pushStateAll(run: Run, state: string, extra: { [string]: any }?)
	for player in run.Players do
		pushState(run, player, state, extra)
	end
end

-- Enemies -----------------------------------------------------------------------------------------------------

local function spawnEnemy(run: Run, room: ActiveRoom, position: Vector3, kind: EnemyKind, enemyKey: string)
	local info = EnemyConfig.Get(enemyKey)
	local elite = EnemyConfig.Elite
	local hpMult, atkMult, xpMult, scale = 1, 1, 1, 1
	if kind == "Elite" then
		hpMult, atkMult, xpMult, scale = elite.HP, elite.Atk, elite.XP, elite.Scale
	elseif kind == "Boss" then
		scale = info.BossScale or EnemyConfig.DEFAULT_BOSS_SCALE
	end

	local model = AssetRegistry.CreateEnemyModel(info.Id, scale)
	local primary = model.PrimaryPart
	if not primary then
		model:Destroy()
		return
	end
	local _, extents = model:GetBoundingBox()
	model:PivotTo(CFrame.new(position + Vector3.new(0, extents.Y / 2, 0)))

	local maxHP = FormulaEngine.GetMonsterMaxHP(info.BaseHP * hpMult, run.WorldIndex, run.Corruption, run.Depth, partySize(run))
	model:SetAttribute("EnemyKey", info.Id)
	model:SetAttribute("EnemyKind", kind)
	model:SetAttribute("RunId", run.Id)
	model:SetAttribute("MaxHP", maxHP)
	model:SetAttribute("HP", maxHP)
	local mercy = if run.WorldIndex == 1 and run.Corruption == 0 and kind ~= "Boss" then (EARLY_ATK_MULT[run.Depth] or 1) else 1
	local attack = FormulaEngine.GetMonsterAttack(info.BaseAtk * atkMult, run.WorldIndex, run.Corruption, run.Depth)
	model:SetAttribute("Attack", math.max(1, math.round(attack * mercy)))
	model:SetAttribute("XPValue", math.round(info.BaseXP * xpMult))
	CollectionService:AddTag(model, RunManagerService.ENEMY_TAG)

	model.Parent = room.Built.Folder
	Physics25D.SetupActor(model, primary)

	room.Enemies[model] = true
	room.EnemiesTotal += 1
	room.EnemiesLeft += 1
end

local function spawnRoomEnemies(run: Run, room: ActiveRoom)
	local world = RoomAsciiTemplates.GetWorld(run.WorldIndex)
	if not world then
		return
	end
	local built = room.Built

	if room.Type == "Boss" then
		local bossKey = if run.Depth % 10 == 5 then world.MiniBoss else world.WorldBoss
		for _, position in built.BossSpawns do
			spawnEnemy(run, room, position, "Boss", bossKey)
		end
		return
	end

	local normals = built.MobSpawns
	if #normals > 0 then
		local scale = 1 + PARTY_SPAWN_SCALE_PER_PLAYER * (partySize(run) - 1)
		local total = math.round(#normals * scale)
		for index = 1, total do
			local position = normals[(index - 1) % #normals + 1]
			if index > #normals then
				position += Vector3.new(run.Rng:NextNumber(-2, 2), 0, 0) -- extras share spawners with a little spread
			end
			local key = world.NormalEnemies[run.Rng:NextInteger(1, #world.NormalEnemies)]
			spawnEnemy(run, room, position, "Normal", key)
		end
	end
	for _, position in built.EliteSpawns do
		spawnEnemy(run, room, position, "Elite", world.EliteEnemy)
	end
end

-- Chests ------------------------------------------------------------------------------------------------------

local function spawnChest(run: Run, room: ActiveRoom, position: Vector3)
	local chest, prompt = RoomBuilderService.CreateChest(room.Built, position)
	table.insert(room.Chests, chest)

	local opened: { [Player]: boolean } = {}
	prompt.Triggered:Connect(function(player: Player)
		local runPlayer = run.Players[player]
		local profile = PlayerDataService.Get(player)
		if not runPlayer or not profile or runPlayer.Status ~= "Alive" or opened[player] or room.ChestsForfeited then
			return
		end
		opened[player] = true

		local dust = computeDust(player, profile, run, CHEST_DUST_FACTOR)
		runPlayer.Unsecured.Dust += dust
		local shards = 0
		if run.Rng:NextNumber() < CHEST_SHARD_CHANCE then
			shards = 1
			runPlayer.Unsecured.RelicShards += shards
		end
		pushState(run, player, "ChestOpened", { Dust = dust, RelicShards = shards })
		PlayerDataService.BumpStat(player, "ChestsOpened", 1)
		QuestService.Track(player, "ChestsOpened", 1)
		lootEvent:Fire(player, "Chest")
		local dropHandler = RunManagerService.RelicDropHandler
		if dropHandler then
			task.spawn(dropHandler, player, run, "Chest")
		end

		-- The chest disappears once every living player has opened it.
		for otherPlayer, other in run.Players do
			if other.Status == "Alive" and not opened[otherPlayer] then
				return
			end
		end
		chest:Destroy()
	end)
end

-- Rift Shrine curses -------------------------------------------------------------------------------------------

-- Re-applies Max HP after a curse changed it, keeping the player's current health fraction.
local function refreshRunHealth(run: Run, player: Player)
	local profile = PlayerDataService.Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not humanoid or humanoid.Health <= 0 then
		return
	end
	local provider = RunManagerService.RunHpMultProvider
	local fraction = humanoid.Health / math.max(1, humanoid.MaxHealth)
	local maxHP = FormulaEngine.GetPlayerMaxHP(profile.HunterLevel, profile.LegacyBonusLevels, profile.RebirthTier,
		nodeLevel(profile, NODE_MIGHT), if provider then provider(player) else 1, curseMods(run, player).HpMult)
	humanoid.MaxHealth = maxHP
	humanoid.Health = math.max(1, maxHP * fraction)
end

local function acceptCurse(run: Run, room: ActiveRoom, player: Player, curseId: string, altar: Model)
	local runPlayer = run.Players[player]
	local info = CurseConfig.Curses[curseId]
	if not runPlayer or runPlayer.Status ~= "Alive" or not info or not table.find(room.CurseOffers, curseId) then
		return
	end
	if #runPlayer.Curses >= CurseConfig.MAX_CURSES then
		notify(player, ("You already carry %d curses — the shrine refuses you."):format(CurseConfig.MAX_CURSES))
		return
	end
	table.remove(room.CurseOffers, table.find(room.CurseOffers, curseId) :: number)
	table.insert(runPlayer.Curses, curseId)
	player:SetAttribute("RunCurses", table.concat(runPlayer.Curses, ","))
	altar:Destroy()
	refreshRunHealth(run, player)
	PlayerDataService.BumpStat(player, "CursesAccepted", 1)
	QuestService.Track(player, "CursesAccepted", 1)
	notify(player, ("%s %s accepted: %s, %s"):format(info.Icon, info.Name, info.Boon, info.Bane))
	pushState(run, player, "CurseAccepted", { Curse = curseId })
end

-- Two altars stand on the floor of every Treasure room, each offering a different pact for the rest of the run.
local function spawnCurseAltars(run: Run, room: ActiveRoom)
	local pool = table.clone(CurseConfig.Order)
	local built = room.Built
	for index = 1, CurseConfig.ALTARS_PER_SHRINE do
		if #pool == 0 then
			break
		end
		local curseId = table.remove(pool, run.Rng:NextInteger(1, #pool)) :: string
		local info = CurseConfig.Curses[curseId]
		local x = built.Origin.X + built.Width * (if index == 1 then 0.33 else 0.62)
		local altar, prompt = RoomBuilderService.CreateCurseAltar(built, Vector3.new(x, built.Origin.Y + RoomAsciiTemplates.TILE_SIZE.Y, 0), info)
		table.insert(room.CurseOffers, curseId)
		prompt.Triggered:Connect(function(player: Player)
			acceptCurse(run, room, player, curseId, altar)
		end)
	end
end

-- Rewards & unlocks -------------------------------------------------------------------------------------------

local function payRoom(run: Run)
	local room = run.Room
	if not room or room.PaidOut then
		return
	end
	room.PaidOut = true

	local factor = ROOM_DUST_FACTOR[room.Type] or 1
	local survivors: { Player } = {}
	for player, runPlayer in run.Players do
		local profile = PlayerDataService.Get(player)
		if runPlayer.Status == "Alive" and profile then
			runPlayer.Unsecured.Dust += computeDust(player, profile, run, factor)
			PlayerDataService.Replicate(player) -- XP / level-ups earned this room
			table.insert(survivors, player)
		end
	end
	roomClearedEvent:Fire(run.Id, run.Depth, survivors)
end

-- Clearing Room 10 on a player's highest corruption tier unlocks the next tier; on Normal it opens the next World.
local function applyAnchorUnlocks(player: Player, profile: PlayerProfileData, run: Run)
	if run.Depth ~= 10 then
		return
	end
	local unlockedTier = profile.UnlockedWorlds[run.WorldIndex]
	if unlockedTier ~= nil and unlockedTier == run.Corruption and unlockedTier < MAX_CORRUPTION then
		profile.UnlockedWorlds[run.WorldIndex] = unlockedTier + 1
		notify(player, ("Corruption Tier %d unlocked!"):format(unlockedTier + 1))
	end
	local nextWorld = run.WorldIndex + 1
	if unlockedTier ~= nil and run.Corruption == 0 and nextWorld <= MAX_WORLD and profile.UnlockedWorlds[nextWorld] == nil then
		profile.UnlockedWorlds[nextWorld] = 0
		notify(player, ("World %d unlocked!"):format(nextWorld))
	end
end

-- Boss defeated: drops, secure the pouch, heal, unlocks, then ask each player to extract or push deeper.
local function reachAnchor(run: Run)
	run.Phase = "Anchor"
	run.LastAnchorDepth = run.Depth
	run.AnchorDeadline = os.clock() + ANCHOR_DECISION_SECONDS

	local cores = math.max(1, run.Depth // 5)
	local shards = BOSS_SHARD_BASE + run.Depth // 10
	local bossSource = if run.Depth % 10 == 5 then "MiniBoss" else "WorldBoss"

	for player, runPlayer in run.Players do
		runPlayer.Decision = nil
		local profile = PlayerDataService.Get(player)
		if runPlayer.Status == "Alive" and profile then
			-- Boss Hunter's Trophy: +20% per level for an extra Core and Shard.
			local bonus = if run.Rng:NextNumber() < 0.20 * nodeLevel(profile, NODE_TROPHY) then 1 else 0
			runPlayer.Unsecured.BossCores += cores + bonus
			runPlayer.Unsecured.RelicShards += shards + bonus
			settle(run, runPlayer, "All")
			lootEvent:Fire(player, "Anchor")
			local dropHandler = RunManagerService.RelicDropHandler
			if dropHandler then
				task.spawn(dropHandler, player, run, bossSource)
			end

			applyAnchorUnlocks(player, profile, run)
			PlayerDataService.Replicate(player)

			-- Anchor Guardian heals 25% Max HP per level.
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local healFraction = 0.25 * nodeLevel(profile, NODE_GUARDIAN)
			if humanoid and healFraction > 0 then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * healFraction)
			end
		end
	end

	local room = run.Room
	if room then
		room.ExitOpen = true
		RoomBuilderService.SetExitOpen(room.Built, true)
	end
	pushStateAll(run, "Anchor", { DecisionSeconds = ANCHOR_DECISION_SECONDS, CoresDropped = cores, ShardsDropped = shards })
end

local function clearRoom(run: Run)
	local room = run.Room
	if not room or room.Cleared then
		return
	end
	room.Cleared = true
	payRoom(run)
	for player, runPlayer in run.Players do
		if runPlayer.Status == "Alive" then
			PlayerDataService.BumpStat(player, "RoomsCleared", 1)
			QuestService.Track(player, "RoomsCleared", 1)
		end
	end

	if room.Type == "Boss" then
		reachAnchor(run)
		return
	end

	room.ExitOpen = true
	RoomBuilderService.SetExitOpen(room.Built, true)
	for _, position in room.Built.ChestSpawns do
		spawnChest(run, room, position) -- room completion chests
	end
	pushStateAll(run, "RoomCleared")
end

-- Run lifecycle -----------------------------------------------------------------------------------------------

local function teardownRoom(run: Run)
	local room = run.Room
	if room then
		RoomBuilderService.DestroyRoom(room.Built)
		run.Room = nil
	end
end

local function endRun(run: Run)
	if run.Phase == "Ended" then
		return
	end
	run.Phase = "Ended"
	teardownRoom(run)
	run.Folder:Destroy()
	usedSlots[run.Slot] = nil
	runs[run.Id] = nil
end

local function applyRunHealth(player: Player, humanoid: Humanoid)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end
	local provider = RunManagerService.RunHpMultProvider
	local run = playerRun[player]
	local maxHP = FormulaEngine.GetPlayerMaxHP(profile.HunterLevel, profile.LegacyBonusLevels, profile.RebirthTier,
		nodeLevel(profile, NODE_MIGHT), if provider then provider(player) else 1,
		if run then curseMods(run, player).HpMult else 1)
	humanoid.MaxHealth = maxHP
	humanoid.Health = maxHP
end

leaveRun = function(run: Run, player: Player, reason: string, mode: SettleMode, silent: boolean)
	local runPlayer = run.Players[player]
	if not runPlayer then
		return
	end
	local credited = settle(run, runPlayer, mode)
	PlayerDataService.Replicate(player)

	run.Players[player] = nil
	playerRun[player] = nil
	player:SetAttribute("RunId", nil)
	player:SetAttribute("RunCurses", nil)

	if not silent then
		runStateRemote:FireClient(player, {
			State = "Left",
			Reason = reason,
			RunId = run.Id,
			Room = run.Depth,
			Credited = credited,
			Secured = runPlayer.Secured,
		})
		returnToTown(player)
	end

	if next(run.Players) == nil then
		endRun(run)
	end
end

local function nextTemplateRoom(run: Run): BuiltRoom?
	local templateId = RoomAsciiTemplates.GetTemplateId(run.WorldIndex, run.Depth, run.Rng)
	if not templateId then
		return nil
	end
	return RoomBuilderService.BuildRoom(templateId, run.Origin, run.Folder, run.WorldIndex)
end

loadRoom = function(run: Run)
	if run.Phase == "Ended" then
		return
	end
	teardownRoom(run)

	local built = nextTemplateRoom(run)
	if not built then
		warn("[RunManagerService] Could not build a room; ending run " .. run.Id)
		for _, player in snapshotPlayers(run) do
			leaveRun(run, player, "RoomError", "All", false)
		end
		return
	end

	local template = built.Template
	local room: ActiveRoom = {
		Built = built,
		Type = template.Type,
		Objective = template.Objective,
		Cleared = false,
		PaidOut = false,
		ExitOpen = false,
		ExitEnteredAt = nil,
		Enemies = {},
		EnemiesTotal = 0,
		EnemiesLeft = 0,
		Chests = {},
		ChestsForfeited = false,
		PoisonTop = built.Origin.Y,
		CurseOffers = {},
	}
	run.Room = room
	run.Phase = "Room"

	if room.Type == "Combat" or room.Type == "Boss" then
		spawnRoomEnemies(run, room)
		room.Objective = room.Objective:gsub("{N}", tostring(room.EnemiesTotal))
	else
		-- Jump Quests and Shrines are open from the start; chests are the bonus.
		room.Cleared = true
		room.ExitOpen = true
		RoomBuilderService.SetExitOpen(built, true)
		for _, position in built.ChestSpawns do
			spawnChest(run, room, position)
		end
		if room.Type == "Treasure" then
			spawnCurseAltars(run, room)
		end
	end
	for player, runPlayer in run.Players do
		if runPlayer.Status == "Alive" then
			PlayerDataService.BumpStat(player, "HighestRoom", run.Depth, true)
		end
	end

	for player, runPlayer in run.Players do
		if runPlayer.Status == "Alive" and isCharacterAlive(player) then
			placeCharacter(player, built.PlayerSpawn)
		end
	end
	pushStateAll(run, "RoomStart")

	if (room.Type == "Combat" or room.Type == "Boss") and room.EnemiesTotal == 0 then
		clearRoom(run)
	end
end

local function advanceRoom(run: Run)
	payRoom(run)
	run.Depth += 1
	loadRoom(run)
end

-- Anchor decisions: Extractors leave immediately; pushers wait until nobody alive is still undecided.
local function resolveAnchor(run: Run, force: boolean)
	if run.Phase ~= "Anchor" then
		return
	end
	for _, player in snapshotPlayers(run) do
		local runPlayer = run.Players[player]
		if runPlayer and runPlayer.Status == "Alive" and (runPlayer.Decision == "Extract" or (force and runPlayer.Decision == nil)) then
			PlayerDataService.BumpStat(player, "Extractions", 1)
			QuestService.Track(player, "Extractions", 1)
			leaveRun(run, player, "Extract", "All", false)
		end
	end
	if run.Phase ~= "Anchor" then
		return -- everyone left and the run ended
	end

	local pushers = 0
	for _, runPlayer in run.Players do
		if runPlayer.Status == "Alive" then
			if runPlayer.Decision == nil then
				return
			end
			pushers += 1
		end
	end
	if pushers > 0 then
		advanceRoom(run)
	end
end

-- Defeat ------------------------------------------------------------------------------------------------------

local function canRewind(run: Run, player: Player): boolean
	for otherPlayer, other in run.Players do
		if otherPlayer ~= player and other.Status == "Alive" then
			return false
		end
	end
	return true
end

local function onPlayerDied(player: Player)
	local run = playerRun[player]
	if not run then
		task.delay(OUT_OF_RUN_RESPAWN_SECONDS, function()
			if player.Parent and not playerRun[player] and not isCharacterAlive(player) then
				player:LoadCharacterAsync()
			end
		end)
		return
	end
	local runPlayer = run.Players[player]
	if not runPlayer or runPlayer.Status ~= "Alive" then
		return
	end

	runPlayer.Status = "Defeated"
	runPlayer.Decision = nil
	runPlayer.DefeatDeadline = os.clock() + DEFEAT_CHOICE_SECONDS
	local root = getRoot(player)
	runPlayer.DeathCFrame = if root then root.CFrame else nil

	-- Preview what Accept Defeat would keep (the pouch is only settled when the player chooses).
	local profile = PlayerDataService.Get(player)
	local guardian = if profile then nodeLevel(profile, NODE_GUARDIAN) else 0
	local insured = hasInsurancePass(player)
	local pouch = runPlayer.Unsecured
	pushState(run, player, "Defeat", {
		DecisionSeconds = DEFEAT_CHOICE_SECONDS,
		AnchorTokens = if profile then profile.AnchorTokens else 0,
		CanRewind = canRewind(run, player),
		RewindToRoom = run.LastAnchorDepth + 1,
		KeptIfAccepted = {
			Dust = FormulaEngine.CalculateDefeatDustKept(pouch.Dust, run.Depth, guardian, insured),
			BossCores = FormulaEngine.CalculateDefeatNonDustKept(pouch.BossCores, run.Depth, guardian, insured),
			RelicShards = FormulaEngine.CalculateDefeatNonDustKept(pouch.RelicShards, run.Depth, guardian, insured),
		},
	})

	if run.Phase == "Anchor" then
		resolveAnchor(run, false) -- the dead player no longer blocks the decision
	end
end

local function reviveInPlace(run: Run, player: Player, runPlayer: RunPlayer)
	runPlayer.Status = "Alive"
	runPlayer.Shielded = true
	runPlayer.PendingSpawn = if runPlayer.DeathCFrame then runPlayer.DeathCFrame + Vector3.new(0, 2, 0) else nil
	respawn(player)
	pushState(run, player, "Revived")
end

local function rewindToAnchor(run: Run, player: Player, runPlayer: RunPlayer)
	runPlayer.Status = "Alive"
	runPlayer.PendingSpawn = nil
	run.Depth = run.LastAnchorDepth + 1
	loadRoom(run) -- teleports living players; the respawned character is placed by bindCharacter
	respawn(player)
end

-- Pushes the defeat screen's auto-accept deadline out by at least `seconds` (a Robux prompt is open).
function RunManagerService.HoldDefeat(player: Player, seconds: number)
	local run = playerRun[player]
	local runPlayer = if run then run.Players[player] else nil
	if runPlayer and runPlayer.Status == "Defeated" then
		runPlayer.DefeatDeadline = math.max(runPlayer.DefeatDeadline, os.clock() + seconds)
	end
end

function RunManagerService.IsDefeated(player: Player): boolean
	local run = playerRun[player]
	local runPlayer = if run then run.Players[player] else nil
	return runPlayer ~= nil and runPlayer.Status == "Defeated"
end

-- choice: "Accept" | "Revive" | "Rewind" | "Insure".
-- payment: "Free" (Accept only), "Token" (Rewind / Insure, consumes an Anchor Token) or "Robux" (the caller,
-- MonetizationService, has already validated the purchase).
function RunManagerService.ResolveDefeat(player: Player, choice: string, payment: string): (boolean, string)
	local run = playerRun[player]
	local runPlayer = if run then run.Players[player] else nil
	local profile = PlayerDataService.Get(player)
	if not run or not runPlayer or not profile or runPlayer.Status ~= "Defeated" then
		return false, "You are not defeated"
	end

	if choice == "Accept" then
		if payment ~= "Free" then
			return false, "Invalid payment"
		end
		leaveRun(run, player, "Defeat", "Defeat", false)
		return true, "Defeat accepted"
	end

	if choice ~= "Revive" and choice ~= "Rewind" and choice ~= "Insure" then
		return false, "Unknown choice"
	end
	if payment == "Token" then
		if choice == "Revive" then
			return false, "Revive requires Robux"
		end
		if profile.AnchorTokens < 1 then
			return false, "No Anchor Tokens"
		end
	elseif payment ~= "Robux" then
		return false, "Invalid payment"
	end
	if choice == "Rewind" and not canRewind(run, player) then
		return false, "Teammates are still fighting; revive instead"
	end

	if payment == "Token" then
		PlayerDataService.Mutate(player, function(data)
			data.AnchorTokens -= 1
		end)
	end

	if choice == "Revive" then
		reviveInPlace(run, player, runPlayer)
	elseif choice == "Rewind" then
		rewindToAnchor(run, player, runPlayer)
	else
		leaveRun(run, player, "Insured", "All", false)
	end
	return true, choice
end

-- Enemy kills -------------------------------------------------------------------------------------------------

reportEnemyDefeated = function(enemy: Model, killer: Player?)
	local runId = enemy:GetAttribute("RunId")
	local run = if type(runId) == "number" then runs[runId] else nil
	local room = if run then run.Room else nil
	if not run or not room or not room.Enemies[enemy] then
		return
	end
	room.Enemies[enemy] = nil
	room.EnemiesLeft -= 1
	enemy:Destroy()

	local baseXP = enemy:GetAttribute("XPValue")
	local kind = enemy:GetAttribute("EnemyKind")
	local masteryKind = if kind == "Boss" then (if run.Depth % 10 == 5 then "MiniBoss" else "WorldBoss")
		elseif kind == "Elite" then "Elite" else "Normal"
	for player, runPlayer in run.Players do
		local profile = PlayerDataService.Get(player)
		if runPlayer.Status == "Alive" and profile then
			if type(baseXP) == "number" then
				local levels = addHunterXP(profile, computeXP(player, profile, run, baseXP))
				if levels > 0 then
					notify(player, ("Level Up! Hunter Level %d"):format(profile.HunterLevel))
					PlayerDataService.Replicate(player)
				end
			end
			MasteryService.AwardKill(player, masteryKind, run.WorldIndex, run.Corruption)
			PlayerDataService.BumpStat(player, "Kills", 1)
			QuestService.Track(player, "Kills", 1)
			if kind == "Elite" then
				PlayerDataService.BumpStat(player, "EliteKills", 1)
				QuestService.Track(player, "EliteKills", 1)
			elseif kind == "Boss" then
				PlayerDataService.BumpStat(player, "BossKills", 1)
				QuestService.Track(player, "BossKills", 1)
			end
		end
	end

	pushStateAll(run, "Progress")
	if room.EnemiesLeft <= 0 then
		clearRoom(run)
	end
end

RunManagerService.ReportEnemyDefeated = reportEnemyDefeated

-- Per-tick room logic -----------------------------------------------------------------------------------------

local function isInsideZone(position: Vector3, zone: BasePart): boolean
	local offset = position - zone.Position
	return math.abs(offset.X) <= zone.Size.X / 2 and math.abs(offset.Y) <= zone.Size.Y / 2
end

local function tickPoison(run: Run, room: ActiveRoom, dt: number)
	local poison = room.Built.Poison
	if not poison or room.ChestsForfeited then
		return
	end
	local ceiling = room.Built.Origin.Y + room.Built.Height - 6
	room.PoisonTop = math.min(ceiling, room.PoisonTop + room.Built.PoisonSpeed * dt)
	-- Clients animate the 3-layer acid flood toward this height (AmbientController); the part itself never moves.
	poison:SetAttribute("SurfaceY", room.PoisonTop)

	for _, chest in room.Chests do
		if chest.Parent and room.PoisonTop >= chest.Position.Y then
			room.ChestsForfeited = true
			for _, doomed in room.Chests do
				doomed:Destroy()
			end
			table.clear(room.Chests)
			pushStateAll(run, "ChestForfeited")
			return
		end
	end
end

local function tickExit(run: Run, room: ActiveRoom)
	if not room.ExitOpen or run.Phase ~= "Room" then
		return
	end
	local inZone, alive = 0, 0
	for player, runPlayer in run.Players do
		if runPlayer.Status == "Alive" then
			alive += 1
			local root = getRoot(player)
			if root and isInsideZone(root.Position, room.Built.Exit) then
				inZone += 1
			end
		end
	end
	if inZone == 0 then
		room.ExitEnteredAt = nil
		return
	end

	payRoom(run) -- Jump Quests and Shrines pay out when the first player reaches the exit
	local now = os.clock()
	if not room.ExitEnteredAt then
		room.ExitEnteredAt = now
		if room.Type == "Jump" then
			for player, runPlayer in run.Players do
				if runPlayer.Status == "Alive" then
					QuestService.Track(player, "JumpRooms", 1)
				end
			end
		end
	end
	if inZone >= alive or now - (room.ExitEnteredAt :: number) >= EXIT_STRAGGLER_SECONDS then
		advanceRoom(run)
	end
end

local function tickRun(run: Run, dt: number)
	local now = os.clock()

	for _, player in snapshotPlayers(run) do
		local runPlayer = run.Players[player]
		if runPlayer and runPlayer.Status == "Defeated" and now >= runPlayer.DefeatDeadline then
			RunManagerService.ResolveDefeat(player, "Accept", "Free")
		end
	end
	if run.Phase == "Ended" then
		return
	end

	local room = run.Room
	if not room then
		return
	end
	if run.Phase == "Anchor" then
		if now >= run.AnchorDeadline then
			resolveAnchor(run, true) -- undecided players extract (the safe default)
		end
		return
	end

	tickPoison(run, room, dt)
	tickExit(run, room)
end

-- Characters --------------------------------------------------------------------------------------------------

local function bindCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	humanoid.Died:Connect(function()
		onPlayerDied(player)
	end)

	local run = playerRun[player]
	local runPlayer = if run then run.Players[player] else nil
	if not run or not runPlayer or runPlayer.Status ~= "Alive" then
		return
	end

	-- A character spawned mid-run (Revive / Rewind): give it run stats and put it where it belongs.
	applyRunHealth(player, humanoid)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or player.Character ~= character then
		return
	end
	local room = run.Room
	local destination = runPlayer.PendingSpawn or (if room then room.Built.PlayerSpawn else nil)
	runPlayer.PendingSpawn = nil
	if destination then
		character:PivotTo(destination)
	end
	if runPlayer.Shielded then
		runPlayer.Shielded = false
		local shield = Instance.new("ForceField")
		shield.Parent = character
		task.delay(REVIVE_SHIELD_SECONDS, function()
			shield:Destroy()
		end)
	end
end

local function trackPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then
		task.spawn(bindCharacter, player, player.Character)
	end
end

-- Public API --------------------------------------------------------------------------------------------------

function RunManagerService.GetRunOf(player: Player): Run?
	return playerRun[player]
end

function RunManagerService.GetPartySize(run: Run): number
	return partySize(run)
end

function RunManagerService.GetRunById(runId: number): Run?
	return runs[runId]
end

-- Everyone in the run, or only those currently Alive (not waiting on the Defeat screen).
function RunManagerService.GetPlayersInRun(runId: number, aliveOnly: boolean): { Player }
	local list: { Player } = {}
	local run = runs[runId]
	if run then
		for player, runPlayer in run.Players do
			if not aliveOnly or runPlayer.Status == "Alive" then
				table.insert(list, player)
			end
		end
	end
	return list
end

RunManagerService.GetLinkBonus = getLinkBonus

-- Combined multipliers of every curse the player accepted this run (all 1 / 0 outside a run).
function RunManagerService.GetCurseMods(player: Player): CurseConfig.CurseMods
	local run = playerRun[player]
	return if run then curseMods(run, player) else CurseConfig.Combine({})
end

function RunManagerService.GetCurses(player: Player): { string }
	local run = playerRun[player]
	local runPlayer = if run then run.Players[player] else nil
	return if runPlayer then table.clone(runPlayer.Curses) else {}
end

-- Adds loot to a living player's Unsecured Pouch (relic duplicates, Loaded Deck gold) and refreshes their HUD.
function RunManagerService.AddUnsecured(player: Player, bag: LootBag)
	local run = playerRun[player]
	local runPlayer = if run then run.Players[player] else nil
	if not run or not runPlayer or runPlayer.Status ~= "Alive" then
		return
	end
	addBag(runPlayer.Unsecured, bag)
	pushState(run, player, "Progress")
end

-- Every live run (HazardService walks them for the acid flood).
function RunManagerService.GetActiveRuns(): { Run }
	local list: { Run } = {}
	for _, run in runs do
		if run.Phase ~= "Ended" then
			table.insert(list, run)
		end
	end
	return list
end

-- Surface height of the current room's rising acid, or nil when the room has none.
function RunManagerService.GetPoisonTop(run: Run): number?
	local room = run.Room
	if room and room.Built.Poison and run.Phase == "Room" then
		return room.PoisonTop
	end
	return nil
end

-- Starts a run for 1-4 players. The first player is the host whose World / Corruption unlocks gate the request;
-- the rest join through Rift Sidekick Sync. Returns (success, message).
function RunManagerService.StartRun(players: { Player }, worldIndex: number, corruptionTier: number): (boolean, string)
	if #players < 1 or #players > MAX_PLAYERS then
		return false, "Parties have 1-4 players"
	end
	worldIndex = math.floor(worldIndex)
	corruptionTier = math.clamp(math.floor(corruptionTier), 0, MAX_CORRUPTION)
	if not RoomAsciiTemplates.GetWorld(worldIndex) then
		return false, "That world is not available yet"
	end

	for _, player in players do
		if playerRun[player] then
			return false, player.Name .. " is already in a run"
		end
		if not PlayerDataService.Get(player) then
			return false, "Your profile is still loading"
		end
		if not isCharacterAlive(player) then
			return false, "Wait until you have respawned"
		end
	end
	local hostProfile = PlayerDataService.Get(players[1]) :: PlayerProfileData
	local unlockedTier = hostProfile.UnlockedWorlds[worldIndex]
	if unlockedTier == nil then
		return false, "World locked"
	elseif corruptionTier > unlockedTier then
		return false, "Corruption tier locked"
	end

	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true

	local runsFolder = Workspace:FindFirstChild("RiftRuns") or Instance.new("Folder")
	runsFolder.Name = "RiftRuns"
	runsFolder.Parent = Workspace
	local runId = nextRunId
	nextRunId += 1
	local folder = Instance.new("Folder")
	folder.Name = "Run_" .. runId
	folder.Parent = runsFolder

	local run: Run = {
		Id = runId,
		Slot = slot,
		Host = players[1],
		Folder = folder,
		Origin = RUN_ORIGIN + Vector3.new(slot * RUN_SLOT_SPACING, 0, 0),
		WorldIndex = worldIndex,
		Corruption = corruptionTier,
		Depth = 1,
		Phase = "Room",
		LastAnchorDepth = 0,
		AnchorDeadline = 0,
		Players = {},
		Rng = Random.new(),
		Room = nil,
	}
	runs[runId] = run

	for _, player in players do
		run.Players[player] = {
			Player = player,
			Status = "Alive",
			Secured = emptyBag(),
			Unsecured = emptyBag(),
			Decision = nil,
			DefeatDeadline = 0,
			DeathCFrame = nil,
			PendingSpawn = nil,
			Shielded = false,
			Supercharged = false,
			Curses = {},
		}
		local runPlayer = run.Players[player]
		playerRun[player] = run
		player:SetAttribute("RunId", runId)
		PlayerDataService.Mutate(player, function(profile)
			profile.RunsSinceLastRebirth += 1
			if profile.SuperchargedTokens > 0 then
				profile.SuperchargedTokens -= 1
				runPlayer.Supercharged = true
			end
		end)
		if runPlayer.Supercharged then
			notify(player, ("Supercharged Run! x%d Rift Dust this run"):format(MonetizationConfig.SUPERCHARGE_DUST_MULT))
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			applyRunHealth(player, humanoid)
		end
	end

	RoomBuilderService.BuildVista(run.Origin, RoomAsciiTemplates.COLUMNS * RoomAsciiTemplates.TILE_SIZE.X, folder, run.WorldIndex * 101 + slot)
	pushStateAll(run, "RunStart")
	loadRoom(run)
	return true, "Run started"
end

function RunManagerService.Init()
	Remotes.Init()
	runStateRemote = Remotes.GetEvent("RunStateChanged")
	notifyRemote = Remotes.GetEvent("Notify")

	Players.RespawnTime = RESPAWN_TIME_OVERRIDE

	local lastStartRequest: { [Player]: number } = {}
	Remotes.GetFunction("StartRun").OnServerInvoke = function(player: Player, worldIndex: any, corruptionTier: any)
		local now = os.clock()
		if now - (lastStartRequest[player] or 0) < START_REQUEST_COOLDOWN then
			return { Success = false, Message = "Please wait a moment" }
		end
		lastStartRequest[player] = now
		if type(worldIndex) ~= "number" or type(corruptionTier) ~= "number" or worldIndex ~= worldIndex or corruptionTier ~= corruptionTier then
			return { Success = false, Message = "Invalid request" }
		end
		local success, message = RunManagerService.StartRun({ player }, worldIndex, corruptionTier)
		return { Success = success, Message = message }
	end

	Remotes.GetEvent("AnchorDecision").OnServerEvent:Connect(function(player: Player, decision: any)
		if decision ~= "Extract" and decision ~= "Push" then
			return
		end
		local run = playerRun[player]
		local runPlayer = if run then run.Players[player] else nil
		if not run or not runPlayer or run.Phase ~= "Anchor" or runPlayer.Status ~= "Alive" or runPlayer.Decision ~= nil then
			return
		end
		runPlayer.Decision = decision
		if decision == "Push" then
			pushState(run, player, "AnchorWaiting")
		end
		resolveAnchor(run, false)
	end)

	-- Clients may only pick free options; paid ones arrive through MonetizationService.
	local freeChoices: { [string]: { string } } = {
		Accept = { "Accept", "Free" },
		TokenRewind = { "Rewind", "Token" },
		TokenInsure = { "Insure", "Token" },
	}
	Remotes.GetEvent("DefeatChoice").OnServerEvent:Connect(function(player: Player, choice: any)
		local mapped = if type(choice) == "string" then freeChoices[choice] else nil
		if not mapped then
			return
		end
		local success, message = RunManagerService.ResolveDefeat(player, mapped[1], mapped[2])
		if not success then
			notify(player, message)
		end
	end)

	Players.PlayerAdded:Connect(trackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	-- Settle the pouch before PlayerDataService's final save: a disconnect counts as a defeat, but a server
	-- shutdown is never the player's fault, so it banks everything.
	PlayerDataService.BeforeRelease(function(player: Player, reason: string)
		local run = playerRun[player]
		if run then
			leaveRun(run, player, if reason == "Shutdown" then "Shutdown" else "Disconnected",
				if reason == "Shutdown" then "All" else "Defeat", true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastStartRequest[player] = nil
		local run = playerRun[player]
		if run then
			leaveRun(run, player, "Disconnected", "Defeat", true)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for _, run in runs do
				local ok, err = pcall(function(): any
					tickRun(run, TICK_SECONDS)
					return nil
				end)
				if not ok then
					warn(("[RunManagerService] run %d tick failed: %s"):format(run.Id, tostring(err)))
				end
			end
		end
	end)
end

return RunManagerService
