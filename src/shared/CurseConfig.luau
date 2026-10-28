--!strict
-- ReplicatedStorage/Shared/CurseConfig.luau
-- Rift Shrine Curses (game.md Section 29 Step SP-5): optional pacts offered on altars in Treasure rooms. Each
-- trades a weakness for power for the rest of the run. Multipliers are applied by the server only:
--   DmgMult -> FormulaEngine CurseDmgMultiplier      HpMult -> GetPlayerMaxHP curseHpMult
--   DustMult -> RunManagerService room/chest Dust    TakenMult -> damage the player takes
--   AttackSpeed -> additive attack speed bonus

export type CurseInfo = {
	Id: string,
	Name: string,
	Icon: string,
	Boon: string,
	Bane: string,
	DmgMult: number,
	HpMult: number,
	DustMult: number,
	TakenMult: number,
	AttackSpeed: number,
}

export type CurseMods = { DmgMult: number, HpMult: number, DustMult: number, TakenMult: number, AttackSpeed: number }

local CurseConfig = {}

CurseConfig.ALTARS_PER_SHRINE = 2
CurseConfig.MAX_CURSES = 4

CurseConfig.Order = { "GlassCannon", "Greed", "Frenzy", "Hubris", "Famine" }

CurseConfig.Curses = {
	GlassCannon = { Id = "GlassCannon", Name = "Pact of Glass", Icon = "🍷", Boon = "+35% Damage", Bane = "-30% Max HP",
		DmgMult = 1.35, HpMult = 0.70, DustMult = 1, TakenMult = 1, AttackSpeed = 0 },
	Greed = { Id = "Greed", Name = "Pact of Greed", Icon = "💰", Boon = "+60% Rift Dust", Bane = "Take +25% damage",
		DmgMult = 1, HpMult = 1, DustMult = 1.60, TakenMult = 1.25, AttackSpeed = 0 },
	Frenzy = { Id = "Frenzy", Name = "Pact of Frenzy", Icon = "🌀", Boon = "+25% Attack Speed", Bane = "Take +20% damage",
		DmgMult = 1, HpMult = 1, DustMult = 1, TakenMult = 1.20, AttackSpeed = 0.25 },
	Hubris = { Id = "Hubris", Name = "Pact of Hubris", Icon = "☠️", Boon = "+60% Damage", Bane = "Take +50% damage",
		DmgMult = 1.60, HpMult = 1, DustMult = 1, TakenMult = 1.50, AttackSpeed = 0 },
	Famine = { Id = "Famine", Name = "Pact of Famine", Icon = "🦴", Boon = "+30% Damage & +30% Dust", Bane = "-40% Max HP",
		DmgMult = 1.30, HpMult = 0.60, DustMult = 1.30, TakenMult = 1, AttackSpeed = 0 },
} :: { [string]: CurseInfo }

function CurseConfig.Combine(curseIds: { string }): CurseMods
	local mods: CurseMods = { DmgMult = 1, HpMult = 1, DustMult = 1, TakenMult = 1, AttackSpeed = 0 }
	for _, id in curseIds do
		local info = CurseConfig.Curses[id]
		if info then
			mods.DmgMult *= info.DmgMult
			mods.HpMult *= info.HpMult
			mods.DustMult *= info.DustMult
			mods.TakenMult *= info.TakenMult
			mods.AttackSpeed += info.AttackSpeed
		end
	end
	return mods
end

return CurseConfig
