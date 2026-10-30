--!strict
-- ServerScriptService/Server/Services/LeaderboardService.luau
-- Hall of Champions leaderboards (game.md Step SP-6), one OrderedDataStore per board:
--   Deepest Room (Stats.HighestRoom), Hunter Power (Rebirth x 1000 + Hunter Level) and Monsters Slain (Stats.Kills).
-- Scores are written for everyone in the server every PUBLISH_INTERVAL and when a player leaves; the top 10 are
-- cached for CACHE_SECONDS. Without DataStore access (Studio) the boards rank the players in this server instead.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

export type Entry = { Rank: number, Name: string, Value: number, UserId: number } -- UserId: for avatar headshots
export type Board = { Key: string, Title: string, Icon: string, Format: string, Entries: { Entry }, You: number }

type BoardSpec = { Key: string, Title: string, Icon: string, Format: string, Score: (PlayerProfileData) -> number }

local LeaderboardService = {}

local PUBLISH_INTERVAL = 120
local CACHE_SECONDS = 60
local TOP_COUNT = 10

local BOARDS: { BoardSpec } = {
	{ Key = "HighestRoom", Title = "Deepest Room", Icon = "🌀", Format = "Room",
		Score = function(profile)
			return profile.Stats.HighestRoom or 0
		end },
	{ Key = "HunterPower", Title = "Hunter Power", Icon = "👑", Format = "Power",
		Score = function(profile)
			return profile.RebirthTier * 1000 + profile.HunterLevel
		end },
	{ Key = "Kills", Title = "Monsters Slain", Icon = "⚔️", Format = "Number",
		Score = function(profile)
			return profile.Stats.Kills or 0
		end },
}

local stores: { [string]: OrderedDataStore } = {}
local cache: { [string]: { At: number, Entries: { Entry } } } = {}
local names: { [number]: string } = {}
local available = true

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		names[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else ("Hunter %d"):format(userId)
	names[userId] = name
	return name
end

local function publish(player: Player)
	local profile = PlayerDataService.Get(player)
	if not profile or not available or PlayerDataService.IsEphemeral(player) then
		return
	end
	for _, spec in BOARDS do
		local store = stores[spec.Key]
		local score = math.floor(spec.Score(profile))
		if store and score > 0 then
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), score)
			end)
			if not ok then
				warn("[LeaderboardService] publish failed: " .. tostring(err))
				local message = tostring(err)
				if string.find(message, "Studio access", 1, true) or string.find(message, "API access is not enabled", 1, true) then
					available = false
				end
				return
			end
		end
	end
end

-- Ranks the players in this server (Studio fallback).
local function localEntries(spec: BoardSpec): { Entry }
	local rows: { { Name: string, Value: number, UserId: number } } = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerDataService.Get(player)
		if profile then
			table.insert(rows, { Name = player.DisplayName, Value = spec.Score(profile), UserId = player.UserId })
		end
	end
	table.sort(rows, function(a, b)
		return a.Value > b.Value
	end)
	local entries: { Entry } = {}
	for index = 1, math.min(TOP_COUNT, #rows) do
		table.insert(entries, { Rank = index, Name = rows[index].Name, Value = rows[index].Value, UserId = rows[index].UserId })
	end
	return entries
end

local function fetch(spec: BoardSpec): { Entry }
	local cached = cache[spec.Key]
	if cached and os.clock() - cached.At < CACHE_SECONDS then
		return cached.Entries
	end
	local store = stores[spec.Key]
	local entries: { Entry } = {}
	local ok = false
	if store and available then
		ok = pcall(function()
			local page = store:GetSortedAsync(false, TOP_COUNT):GetCurrentPage()
			for index, row in page do
				local userId = tonumber(row.key) or 0
				table.insert(entries, { Rank = index, Name = nameOf(userId), Value = row.value, UserId = userId })
			end
		end)
	end
	if not ok then
		entries = localEntries(spec)
	end
	cache[spec.Key] = { At = os.clock(), Entries = entries }
	return entries
end

function LeaderboardService.GetBoards(player: Player): { Board }
	local profile = PlayerDataService.Get(player)
	local boards: { Board } = {}
	for _, spec in BOARDS do
		table.insert(boards, {
			Key = spec.Key, Title = spec.Title, Icon = spec.Icon, Format = spec.Format, Entries = fetch(spec),
			You = if profile then spec.Score(profile) else 0,
		})
	end
	return boards
end

function LeaderboardService.Init()
	for _, spec in BOARDS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("RiftRush_LB_" .. spec.Key)
		end)
		if ok then
			stores[spec.Key] = store
		end
	end
	PlayerDataService.BeforeRelease(function(player: Player, _reason: string)
		task.spawn(publish, player) -- the profile table outlives the release, so this may finish afterwards
	end)
	task.spawn(function()
		while true do
			task.wait(PUBLISH_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(publish, player)
			end
		end
	end)
end

return LeaderboardService
