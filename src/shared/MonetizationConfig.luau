--!strict
-- ReplicatedStorage/Shared/MonetizationConfig.luau
-- Every Developer Product and Gamepass from Section 27. Ids are 0 until you create them on the Creator Dashboard
-- (Monetization > Developer Products / Passes) and paste them here; MonetizationService skips any id that is 0.
-- Clients may read this to label buttons, but only the server decides what a purchase grants.

export type ProductInfo = {
	Key: string,
	Name: string,
	Price: number, -- R$ (display only; the real price is set on the dashboard)
	Id: number,
}

export type PassInfo = {
	Key: string,
	Name: string,
	Price: number,
	Id: number,
	Attribute: string, -- player attribute set to true while owned (read by the gameplay services)
}

local MonetizationConfig = {}

-- Repeatable Developer Products (Section 27.1). The five Instant Rebirth keys match
-- FormulaEngine.GetInstantRebirthSkipQuote so the server can prompt the tier that fits the player's progress.
MonetizationConfig.Products = {
	SKIP_TIER_1_49R = { Key = "SKIP_TIER_1_49R", Name = "Instant Rebirth (80%+ progress)", Price = 49, Id = 0 },
	SKIP_TIER_2_99R = { Key = "SKIP_TIER_2_99R", Name = "Instant Rebirth (60%+ progress)", Price = 99, Id = 0 },
	SKIP_TIER_3_179R = { Key = "SKIP_TIER_3_179R", Name = "Instant Rebirth (40%+ progress)", Price = 179, Id = 0 },
	SKIP_TIER_4_279R = { Key = "SKIP_TIER_4_279R", Name = "Instant Rebirth (20%+ progress)", Price = 279, Id = 0 },
	SKIP_TIER_5_399R = { Key = "SKIP_TIER_5_399R", Name = "Instant Rebirth", Price = 399, Id = 0 },
	KeepEverythingSeal = { Key = "KeepEverythingSeal", Name = "Keep Everything Seal", Price = 99, Id = 0 },
	RiftRevive = { Key = "RiftRevive", Name = "Rift Revive", Price = 39, Id = 0 },
	CheckpointRewind = { Key = "CheckpointRewind", Name = "Checkpoint Rewind", Price = 49, Id = 0 },
	InsureExtract = { Key = "InsureExtract", Name = "Insure & Extract", Price = 29, Id = 0 },
	SuperchargedRunToken = { Key = "SuperchargedRunToken", Name = "Supercharged Run Token", Price = 79, Id = 0 },
	RiftSurge = { Key = "RiftSurge", Name = "Server Rift Surge", Price = 99, Id = 0 },
	RerollPack5 = { Key = "RerollPack5", Name = "Upgrade Reroll Pack (5x)", Price = 25, Id = 0 },
	StarForceSafeguardPack = { Key = "StarForceSafeguardPack", Name = "Star-Force Safeguard Pack", Price = 49, Id = 0 },
} :: { [string]: ProductInfo }

-- Permanent Gamepasses (Section 27.2)
MonetizationConfig.Passes = {
	TrueAscendant = { Key = "TrueAscendant", Name = "True Ascendant (Keep-On-Rebirth)", Price = 599, Id = 0,
		Attribute = "HasTrueAscendant" },
	DoubleXP = { Key = "DoubleXP", Name = "2x Hunter XP", Price = 399, Id = 0, Attribute = "HasDoubleXP" },
	DoubleDust = { Key = "DoubleDust", Name = "2x Rift Dust Collector", Price = 449, Id = 0, Attribute = "HasDoubleDust" },
	VIPArchitect = { Key = "VIPArchitect", Name = "VIP Architect (4th Upgrade Choice)", Price = 299, Id = 0,
		Attribute = "HasVIPArchitect" },
	BanishPass = { Key = "BanishPass", Name = "The Banish Pass", Price = 199, Id = 0, Attribute = "HasBanishPass" },
	RelicVaultKey = { Key = "RelicVaultKey", Name = "Starting Relic Vault Key", Price = 399, Id = 0,
		Attribute = "HasRelicVaultKey" },
	ExtraLinkSlots = { Key = "ExtraLinkSlots", Name = "Extra Link Skill Slots (+2)", Price = 249, Id = 0,
		Attribute = "HasExtraLinkSlots" },
	VaultInsurance = { Key = "VaultInsurance", Name = "Permanent Vault Insurance", Price = 299, Id = 0,
		Attribute = "HasInsurancePass" },
} :: { [string]: PassInfo }

-- Products that only make sense on the Rift Collapse (defeat) screen, mapped to RunManagerService.ResolveDefeat.
MonetizationConfig.DefeatProducts = {
	RiftRevive = "Revive",
	CheckpointRewind = "Rewind",
	InsureExtract = "Insure",
} :: { [string]: string }

-- Tuning for the consumables whose effect the spec leaves open.
MonetizationConfig.RIFT_SURGE_SECONDS = 15 * 60 -- each purchase adds this much (stacks by extending)
MonetizationConfig.RIFT_SURGE_ECO_MULT = 1.5 -- Hunter XP & Rift Dust for everyone in the server
MonetizationConfig.RIFT_SURGE_ATTRIBUTE = "RiftSurgeEndsAt" -- Workspace attribute, server time
MonetizationConfig.SUPERCHARGE_DUST_MULT = 2 -- Rift Dust multiplier for the run a Supercharged token is spent on
MonetizationConfig.REROLL_PACK_SIZE = 5
MonetizationConfig.SAFEGUARD_PACK_SIZE = 3

function MonetizationConfig.IsRiftSurgeActive(serverNow: number, endsAt: any): boolean
	return type(endsAt) == "number" and endsAt > serverNow
end

return MonetizationConfig
