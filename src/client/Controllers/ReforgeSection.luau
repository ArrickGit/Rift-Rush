--!strict
-- StarterPlayerScripts/Client/Controllers/ReforgeSection.luau
-- The Rift Reforge panel under the Blacksmith's detail card (game.md 6.1 / 7.4 B): the weapon's current prefix,
-- the public odds, both pity counters, the roll cost and the Reforge button. After the first roll every new roll
-- waits as "Pending" until the player keeps it or keeps the current one. InventoryService decides everything; this
-- only draws profile.WeaponReforge and fires LoadoutAction { Action = "Reforge" | "ReforgeKeep" | "ReforgeDiscard" }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReforgeConfig = require(Shared:WaitForChild("ReforgeConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type CostChip = (parent: Instance, iconKey: string, currency: string, amount: number, have: number, order: number) -> ()

local ReforgeSection = {}

local K: any = nil
local loadoutRemote: RemoteEvent
local lastRolls: { [string]: number } = {} -- weapon id -> roll count seen at the last render (plays the reveal)

local PANEL_COLOR = Color3.fromHex("2a1f2e")
local NONE_COLOR = Color3.fromHex("8c8478")

local function tierText(tierId: string?): (string, Color3)
	local tier = ReforgeConfig.Get(tierId)
	if not tier then
		return "Unforged", NONE_COLOR
	end
	return ("%s %s · %s"):format(tier.Icon, tier.Name, tier.Id), tier.Color
end

-- One-line stat summary for a tier ("+50% dmg · +1 wave").
local function bonusText(tierId: string?): string
	local tier = ReforgeConfig.Get(tierId)
	if not tier then
		return "Roll for a permanent prefix and aura"
	end
	local parts = { ("+%d%% dmg"):format(math.round(tier.Dmg * 100)) }
	if tier.AtkSpeed > 0 then
		table.insert(parts, ("+%d%% atk speed"):format(math.round(tier.AtkSpeed * 100)))
	end
	if tier.Crit > 0 then
		table.insert(parts, ("+%d%% crit"):format(math.round(tier.Crit * 100)))
	end
	if tier.Size > 0 then
		table.insert(parts, ("+%d%% size"):format(math.round(tier.Size * 100)))
	end
	if tier.Extra > 0 then
		table.insert(parts, ("+%d slash wave / shot"):format(tier.Extra))
	end
	return table.concat(parts, " · ")
end

local function send(action: string, weaponId: string)
	loadoutRemote:FireServer({ Action = action, Weapon = weaponId })
end

-- `order` is the LayoutOrder in the station content; `costChip` is the Blacksmith's cost chip helper.
function ReforgeSection.Render(order: number, weaponId: string, costChip: CostChip)
	local data = K.profile()
	if not data then
		return
	end
	local info = WeaponConfig.Weapons[weaponId]
	local reforges = if type(data.WeaponReforge) == "table" then data.WeaponReforge else {}
	local entry = if type(reforges[weaponId]) == "table" then reforges[weaponId] else {}
	local current: string? = entry.Tier
	local pending: string? = entry.Pending
	local rolls = tonumber(entry.Rolls) or 0
	local inRun = K.inRun()

	local panel = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = PANEL_COLOR, LayoutOrder = order })
	K.pad(panel, 12)
	K.list(panel, Enum.FillDirection.Vertical, 6)

	-- Title + current prefix.
	local text, color = tierText(current)
	K.newLabel(panel, { Size = UDim2.new(1, 0, 0, 26), Text = "⚒️ Rift Reforge", Font = K.DISPLAY_FONT, TextSize = 22,
		TextColor3 = K.COLORS.Gold, TextStrokeTransparency = 0, LayoutOrder = 1 })
	local currentLabel: TextLabel = K.newLabel(panel, { Size = UDim2.new(1, 0, 0, 24),
		Text = ("Current: <b>%s</b>   <font color='#%s'>%s</font>"):format(text, K.COLORS.Muted:ToHex(), bonusText(current)),
		TextSize = 16, TextColor3 = color, LayoutOrder = 2 })

	-- Odds, with the pity rows underneath.
	local odds: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 3 }, panel)
	K.list(odds, Enum.FillDirection.Horizontal, 6)
	for index, tier in ReforgeConfig.Tiers do
		local chip: TextLabel = K.newLabel(odds, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
			Text = (" %s %s %d%% "):format(tier.Icon, tier.Id, tier.Weight), TextSize = 13, Font = K.DISPLAY_FONT,
			TextColor3 = tier.Color, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromHex("1a1320"), LayoutOrder = index })
		K.round(chip, 6)
	end
	local epicLeft = math.max(1, ReforgeConfig.PITY_EPIC - (tonumber(entry.PityEpic) or 0))
	local legendLeft = math.max(1, ReforgeConfig.PITY_LEGEND - (tonumber(entry.PityLegend) or 0))
	K.newLabel(panel, { Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = K.COLORS.Muted, LayoutOrder = 4,
		Text = ("Pity: Epic+ guaranteed within <b>%d</b> rolls · Legendary+ within <b>%d</b> · %d rolls so far"):format(
			epicLeft, legendLeft, rolls) })

	-- Action row: either Keep New / Keep Current, or the cost and the Reforge button.
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, LayoutOrder = 5 }, panel)
	if pending then
		local newText, newColor = tierText(pending)
		local reveal: TextLabel = K.newLabel(row, { Size = UDim2.new(0.5, -8, 1, 0), TextSize = 16, TextColor3 = newColor,
			Text = ("New roll: <b>%s</b>\n<font color='#%s'>%s</font>"):format(newText, K.COLORS.Muted:ToHex(), bonusText(pending)) })
		local keepNew = K.newButton(row, "Keep New", newColor, function()
			Sfx.Play("Forge_Success", 0.6)
			send("ReforgeKeep", weaponId)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -124, 0, 2), Size = UDim2.fromOffset(116, 46), TextSize = 17 })
		K.setEnabled(keepNew, not inRun, newColor)
		local keepOld = K.newButton(row, "Keep Current", K.COLORS.Accent, function()
			Sfx.Play("UI_Click", 0.5)
			send("ReforgeDiscard", weaponId)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(116, 46), TextSize = 15 })
		K.setEnabled(keepOld, not inRun, K.COLORS.Accent)
		if rolls > (lastRolls[weaponId] or rolls) then
			SceneKit.burst(reveal, newColor)
			Sfx.Play(if ReforgeConfig.Rank(pending) >= ReforgeConfig.Rank("Epic") then "Forge_Success" else "Forge_Hammer2", 0.7)
		end
	else
		local dust = ReforgeConfig.Cost(info.UnlockCost)
		local haveDust, haveCores = tonumber(data.RiftDust) or 0, tonumber(data.BossCores) or 0
		local costs: Frame = K.create("Frame", { Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1 }, row)
		K.list(costs, Enum.FillDirection.Horizontal, 10).VerticalAlignment = Enum.VerticalAlignment.Center
		costChip(costs, "Cur_Dust", "RiftDust", dust, haveDust, 1)
		costChip(costs, "Cur_BossCores", "BossCores", ReforgeConfig.CORE_COST, haveCores, 2)
		local affordable = haveDust >= dust and haveCores >= ReforgeConfig.CORE_COST
		local label = if inRun then "In a run" elseif not affordable then "Need more" elseif current then "🎲 Reforge" else "🎲 First Roll"
		local button = K.newButton(row, label, K.COLORS.Gold, function()
			Sfx.Play("Forge_Hammer1", 0.6)
			send("Reforge", weaponId)
		end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), Size = UDim2.fromOffset(200, 46), TextSize = 19 })
		K.setEnabled(button, affordable and not inRun, K.COLORS.Gold)
		if current and rolls > (lastRolls[weaponId] or rolls) then -- the first roll applied straight away
			SceneKit.burst(currentLabel, color)
			Sfx.Play(if ReforgeConfig.Rank(current) >= ReforgeConfig.Rank("Epic") then "Forge_Success" else "Forge_Hammer2", 0.7)
		end
	end
	lastRolls[weaponId] = rolls
end

function ReforgeSection.Init(kit: any)
	K = kit
	loadoutRemote = Remotes.GetEvent("LoadoutAction")
end

return ReforgeSection
