--!strict
-- ReplicatedStorage/Shared/OnboardingConfig.luau
-- "First 60 Seconds" rules (game.md 3.1 / 3.3): who counts as a brand-new hunter, and which Haven Outpost stations
-- are highlighted at each progress tier. The gate is visual only: locked stations lose their waypoint and show a
-- hint when you walk up, but their prompts still open. OnboardingService publishes the tier as the player's
-- TownTier attribute; WaypointController reads it.

-- The parts of a profile the tier reads (kept structural so this shared module needs no server types).
export type TierProfile = {
	HunterLevel: number,
	Stats: { [string]: number },
	RelicStars: { [string]: any },
	WeaponMastery: { [string]: any }, -- entries have .Level
}

local OnboardingConfig = {}

OnboardingConfig.MAX_TIER = 4

-- Station key -> the tier that highlights it.
OnboardingConfig.StationTier = {
	RiftGate = 1,
	Blacksmith = 2,
	QuestBoard = 2,
	StarForge = 3,
	HallOfChampions = 3,
	LegionHall = 4,
	AscensionPedestal = 4,
	SparkSanctum = 4,
	RiftShrine = 4,
} :: { [string]: number }

-- Shown over a locked station when the player walks up to it, by the tier it needs.
OnboardingConfig.Hint = {
	[2] = "🔒 Unlocks after you clear your first Rift room!",
	[3] = "🔒 Unlocks after defeating your first Boss (Room 5)!",
	[4] = "🔒 Unlocks at Hunter Lv 10 or Mastery 5!",
} :: { [number]: string }

-- Brand-new hunters land in front of the Rift Gate with the starter rack (game.md 3.1 Option A).
function OnboardingConfig.IsNewHunter(profile: TierProfile): boolean
	return (profile.Stats.RoomsCleared or 0) == 0 and profile.HunterLevel <= 1
end

function OnboardingConfig.TierFor(profile: TierProfile): number
	local bestMastery = 0
	for _, entry in profile.WeaponMastery do
		bestMastery = math.max(bestMastery, entry.Level)
	end
	if profile.HunterLevel >= 10 or bestMastery >= 5 then
		return 4
	end
	if (profile.Stats.BossKills or 0) >= 1 or next(profile.RelicStars) ~= nil then
		return 3
	end
	if (profile.Stats.RoomsCleared or 0) >= 1 then
		return 2
	end
	return 1
end

return OnboardingConfig
