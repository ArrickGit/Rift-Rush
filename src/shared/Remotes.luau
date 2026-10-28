--!strict
-- ReplicatedStorage/Shared/Remotes.luau
-- Single manifest of every RemoteEvent / RemoteFunction. Server calls Init() once; both sides use Get*().
-- Add new remotes here as later build steps need them. All server handlers must validate arguments.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	"ProfileUpdated", -- S->C: full profile snapshot
	"RunStateChanged", -- S->C: room number, anchor state, secured/unsecured loot
	"UpgradeOffer", -- S->C: { Kind = "Offer" | "Closed", OfferId, Cards, Rerolls, Banishes }
	"UpgradeChosen", -- C->S: { OfferId, Action = "Pick" | "Reroll" | "Banish", Index }
	"AnchorDecision", -- C->S: extract or push deeper
	"DefeatChoice", -- C->S: accept / token / paid options
	"RequestRebirth", -- C->S: { Mode = "Standard" | "KeepEverything" }
	"AscensionPurchase", -- C->S: node id
	"AscensionRespec", -- C->S: refund every spent Spark (town only)
	"RequestPurchase", -- C->S: { Kind = "Product" | "Pass", Key }; the server picks the id and prompts
	"OpenStation", -- S->C: { Station, Data } when a Town Hub station prompt is used (UIController opens its panel)
	"CombatAttack", -- C->S: (slot: "Basic" | "Ability1", facing: -1 | 1) intent; the server decides everything else
	"CombatDash", -- C->S: (direction: -1 | 1) dash intent; grants i-frames if the server has a charge
	"CombatFx", -- S->C: projectile / telegraph / burst / shake cosmetics for the run's players
	"DamageNumber", -- S->C: batched damage numbers { Pos, Amount, Crit, Lines, Kind, Owner }
	"Notify", -- S->C: toast message
	"LoadoutAction", -- C->S: { Action, ... } Blacksmith unlocks, weapon / Link Skill / Starting Relic equips (InventoryService)
	"StarForce", -- C->S: { Relic, Safeguard } one Star-Force attempt at the Star-Forge (RelicService)
	"ClaimQuest", -- C->S: quest id to claim at the Quest Board (QuestService)
	"MasteryUpdated", -- S->C: { Weapon, Level, XP, Paragon, Required, LevelUp?, LinkTier? } after Mastery XP is awarded
	"Celebrate", -- S->C: { Kind = "Relic" | "Mastery" | "Quest", Title, Body, Icon, Color } big centre-screen banner
}

local FUNCTIONS = {
	"GetProfile", -- C->S: current profile snapshot
	"StartRun", -- C->S: world / corruption / weapon request
	"GetStationData", -- C->S: refresh an open Town Hub panel's Data (same shape OpenStation sends)
}

local Remotes = {}

local function getFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		return existing :: Folder
	end
	if RunService:IsServer() then
		local folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Server only: create every remote up-front so clients can WaitForChild them safely.
function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init must be called on the server")
	local folder = getFolder()
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.GetEvent(name: string): RemoteEvent
	local remote = getFolder():WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), name .. " is not a RemoteEvent")
	return remote
end

function Remotes.GetFunction(name: string): RemoteFunction
	local remote = getFolder():WaitForChild(name)
	assert(remote:IsA("RemoteFunction"), name .. " is not a RemoteFunction")
	return remote
end

return Remotes
