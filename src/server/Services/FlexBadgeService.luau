--!strict
-- ServerScriptService/Server/Services/FlexBadgeService.luau
-- Overhead flex badge above every player in Haven Outpost (game.md 6.5 / 7.4 C). A server-built BillboardGui on the
-- head (so everyone sees it) shows three lines:
--   [Rebirth V ⭐] Name   (or [Lv N] Name before the first rebirth)
--   a title earned from lifetime stats (best one wins, see TITLES)
--   🔥 Best: Room N       (Stats.HighestRoom)
-- The badge hides while the player is in a run (RunId attribute set) and replaces Roblox's default name tag in town.
-- It refreshes on spawn, rebirth, entering / leaving a run and after a reforge is applied or kept.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReforgeConfig = require(Shared:WaitForChild("ReforgeConfig"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local RebirthService = require(script.Parent:WaitForChild("RebirthService"))

type PlayerProfileData = PlayerDataService.PlayerProfileData

type Title = { Text: string, Color: Color3, Earned: (PlayerProfileData) -> boolean }

local FlexBadgeService = {}

local BADGE_NAME = "FlexBadge"
local FONT = Enum.Font.FredokaOne
local NAME_COLOR = Color3.fromRGB(255, 255, 255)
local REBIRTH_COLOR = Color3.fromRGB(255, 210, 80)
local BEST_COLOR = Color3.fromRGB(255, 150, 70)

local function stat(profile: PlayerProfileData, key: string): number
	return profile.Stats[key] or 0
end

local function ownsMythic(profile: PlayerProfileData): boolean
	if stat(profile, "MythicReforges") > 0 then
		return true
	end
	for _, entry in profile.WeaponReforge do
		if entry.Tier == "Mythic" then
			return true
		end
	end
	return false
end

-- Best first: the first title a player has earned is the one shown.
local TITLES: { Title } = {
	{ Text = "Rift Sovereign", Color = (ReforgeConfig.Get("Mythic") :: ReforgeConfig.Tier).Color, Earned = ownsMythic },
	{ Text = "Boss Breaker", Color = Color3.fromRGB(255, 120, 90), Earned = function(profile: PlayerProfileData): boolean
		return stat(profile, "BossKills") >= 10
	end },
	{ Text = "Mushroom Slayer", Color = Color3.fromRGB(140, 230, 110), Earned = function(profile: PlayerProfileData): boolean
		return stat(profile, "Kills") >= 1000
	end },
	{ Text = "Rift Delver", Color = Color3.fromRGB(150, 200, 255), Earned = function(profile: PlayerProfileData): boolean
		return stat(profile, "HighestRoom") >= 10
	end },
}

local function titleFor(profile: PlayerProfileData): Title?
	for _, title in TITLES do
		if title.Earned(profile) then
			return title
		end
	end
	return nil
end

local function line(parent: Instance, order: number, text: string, color: Color3, size: number)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, size + 4)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.RichText = true
	label.Text = text
	label.Parent = parent
end

-- Rebuilds (or removes) the badge for the player's current character.
function FlexBadgeService.Refresh(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local profile = PlayerDataService.Get(player)
	if not (head and head:IsA("BasePart")) or not profile then
		return
	end
	local old = head:FindFirstChild(BADGE_NAME)
	if old then
		old:Destroy()
	end
	local inRun = player:GetAttribute("RunId") ~= nil
	if humanoid then
		humanoid.DisplayDistanceType = if inRun then Enum.HumanoidDisplayDistanceType.Viewer else Enum.HumanoidDisplayDistanceType.None
	end
	if inRun then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = BADGE_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(260, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Parent = gui

	local tag = if profile.RebirthTier > 0
		then ("<font color='#%s'>[Rebirth %s ⭐]</font>"):format(REBIRTH_COLOR:ToHex(), RebirthService.ToRoman(profile.RebirthTier))
		else ("[Lv %d]"):format(profile.HunterLevel)
	line(gui, 1, ("%s %s"):format(tag, player.DisplayName), NAME_COLOR, 20)
	local title = titleFor(profile)
	if title then
		line(gui, 2, ("« %s »"):format(title.Text), title.Color, 16)
	end
	local best = stat(profile, "HighestRoom")
	if best > 0 then
		line(gui, 3, ("🔥 Best: Room %d"):format(best), BEST_COLOR, 14)
	end
	gui.Parent = head
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 10)
		PlayerDataService.Wait(player)
		if player.Character == character then
			FlexBadgeService.Refresh(player)
		end
	end)
	player:GetAttributeChangedSignal("RunId"):Connect(function()
		FlexBadgeService.Refresh(player)
	end)
	if player.Character then
		task.spawn(function()
			PlayerDataService.Wait(player)
			FlexBadgeService.Refresh(player)
		end)
	end
end

function FlexBadgeService.Init()
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	RebirthService.Rebirthed:Connect(function(player: Player)
		FlexBadgeService.Refresh(player)
	end)
	InventoryService.Reforged:Connect(function(player: Player)
		FlexBadgeService.Refresh(player)
	end)
end

return FlexBadgeService
