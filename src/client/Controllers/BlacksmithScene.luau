--!strict
-- StarterPlayerScripts/Client/Controllers/BlacksmithScene.luau
-- The Blacksmith window drawn as a weapon rack: the 8 weapons hang on a wooden wall (never-forged ones are black
-- silhouettes, switched-off ones are grey), and tapping one shows its detail card: a big icon, damage / speed / Q
-- chips, the passive, and one action (Forge, Reactivate, Equip). A freshly forged weapon flares into colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Payload = { [string]: any }

local BlacksmithScene = {}

local K: any = nil -- UIController's kit, set by Init
local loadoutRemote: RemoteEvent

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local UiTex = AssetRegistry.UiTextures
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon

local RACK_COLORS = {
	Slot = Color3.fromHex("3b2617"),
	SlotLocked = Color3.fromHex("24170e"),
	Peg = Color3.fromHex("a9824f"),
	Card = Color3.fromHex("2e2219"),
	Silhouette = Color3.fromHex("0e0a07"),
	Off = Color3.fromHex("8c8478"),
	Bad = Color3.fromHex("ff6b6b"),
}
local REACTIVATION_FEE_FRACTION = 0.25 -- mirrors RebirthService (display only)
local SLOT_HEIGHT = 84

type WeaponState = string -- "Owned" | "Off" (switched off by a Rebirth) | "Locked" (never forged)

local selectedWeapon: string? = nil
local lastStates: { [string]: WeaponState } = {}
local lastEquipped: string? = nil

local function profileTable(key: string): { [any]: any }
	local data = K.profile()
	local value = if data then data[key] else nil
	return if type(value) == "table" then value else {}
end

local function profileNumber(key: string): number
	local data = K.profile()
	return if data then tonumber(data[key]) or 0 else 0
end

local function weaponState(weaponId: string): WeaponState
	local unlocked = profileTable("UnlockedWeapons")[weaponId]
	return if unlocked == true then "Owned" elseif unlocked == false then "Off" else "Locked"
end

local function equippedWeapon(): string?
	local data = K.profile()
	return if data then data.EquippedWeapon else nil
end

-- Mastery level (Paragon counts on top), preferring the live numbers for the equipped weapon.
local function masteryLevel(weaponId: string): number
	local live = K.liveMastery()
	if live and live.Weapon == weaponId then
		return live.Level + live.Paragon
	end
	local entry = profileTable("WeaponMastery")[weaponId]
	return if type(entry) == "table" then (tonumber(entry.Level) or 1) + (tonumber(entry.ParagonRank) or 0) else 1
end

-- What forging / reactivating costs right now (nil when there is nothing to pay for).
local function price(weaponId: string, state: WeaponState): (number, number)
	local info = WeaponConfig.Weapons[weaponId]
	if state == "Off" then
		return math.round(info.UnlockCost * REACTIVATION_FEE_FRACTION), 0
	end
	return info.UnlockCost, info.UnlockCores
end

local function iconColor(info: WeaponConfig.WeaponInfo, state: WeaponState): Color3
	return if state == "Owned" then info.Accent elseif state == "Off" then RACK_COLORS.Off else RACK_COLORS.Silhouette
end

local function currencyPill(parent: Instance, iconKey: string, currency: string, amount: number, props: Payload): Frame
	local pill = K.newPanel(parent, props)
	icon(pill, Icons[iconKey], { Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(36, 36),
		ImageColor3 = SceneKit.currencyColor(currency) })
	K.newLabel(pill, { Position = UDim2.fromOffset(50, 0), Size = UDim2.new(1, -56, 1, 0), Text = K.formatNumber(amount),
		Font = K.DISPLAY_FONT, TextSize = 28, TextStrokeTransparency = 0 })
	return pill
end

local function header(order: number)
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = order },
		K.content())
	currencyPill(row, "Cur_Dust", "RiftDust", profileNumber("RiftDust"), { Size = UDim2.fromOffset(170, 46) })
	currencyPill(row, "Cur_BossCores", "BossCores", profileNumber("BossCores"),
		{ Position = UDim2.fromOffset(180, 0), Size = UDim2.fromOffset(130, 46) })

	local owned = 0
	for _, weaponId in WeaponConfig.Order do
		if weaponState(weaponId) == "Owned" then
			owned += 1
		end
	end
	local count = K.newPanel(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(190, 46) })
	icon(count, Icons.UI_Anvil, { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(32, 32) })
	K.newLabel(count, { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -110, 1, 0), Text = "Weapons\nforged",
		TextSize = 13, TextColor3 = K.COLORS.Muted, LineHeight = 0.9 })
	K.newLabel(count, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 70, 1, 0),
		Text = ("%d/%d"):format(owned, #WeaponConfig.Order), Font = K.DISPLAY_FONT, TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0 })
end

-- One weapon hanging on the rack.
local function rackSlot(parent: Instance, weaponId: string, index: number, equipped: string?)
	local info = WeaponConfig.Weapons[weaponId]
	local state = weaponState(weaponId)
	local selected = weaponId == selectedWeapon
	local slot: TextButton = K.create("TextButton", { Size = UDim2.new(0.235, 0, 0, SLOT_HEIGHT), Text = "", AutoButtonColor = false,
		BackgroundColor3 = if state == "Locked" then RACK_COLORS.SlotLocked else RACK_COLORS.Slot, LayoutOrder = index }, parent)
	K.round(slot, 12)
	K.create("UIStroke", { Color = if selected then Color3.new(1, 1, 1) elseif state == "Owned" then info.Accent else K.COLORS.Stroke,
		Thickness = if selected then 4 else 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, slot)
	local scale: UIScale = K.create("UIScale", { Scale = if selected then 1.05 else 1 }, slot)
	-- The two pegs it hangs from.
	for _, x in { 0.3, 0.7 } do
		local peg = circle(slot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0), Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = RACK_COLORS.Peg, ZIndex = 3 })
		K.outline(peg, K.COLORS.Stroke, 1.5)
	end
	if state == "Owned" then
		local glow = icon(slot, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 32),
			Size = UDim2.fromOffset(84, 84), ImageColor3 = info.Accent, ImageTransparency = if selected then 0.45 else 0.7 })
		if weaponId == equipped then
			tween(glow, SceneKit.PULSE, { ImageTransparency = 0.3 })
		end
	end
	local weaponIcon = icon(slot, Icons["Weapon_" .. weaponId], { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(48, 48), ImageColor3 = iconColor(info, state), ZIndex = 2 })
	K.newLabel(slot, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -8, 0, 20),
		Text = info.Name, Font = K.DISPLAY_FONT, TextSize = 15, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if state == "Locked" then K.COLORS.Muted else Color3.new(1, 1, 1), TextStrokeTransparency = 0.2, ZIndex = 2 })

	if state == "Locked" then
		icon(slot, Icons.UI_Lock, { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(18, 18), ImageColor3 = Color3.fromHex("c9b08a"),
			ZIndex = 3 })
	elseif state == "Off" then
		local tag: TextLabel = K.newLabel(slot, { Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(34, 16), Text = "OFF",
			Font = K.DISPLAY_FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0,
			BackgroundColor3 = K.COLORS.Bad, ZIndex = 3 })
		K.round(tag, 6)
	else
		local badge: TextLabel = K.newLabel(slot, { Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X, Text = (" M%d "):format(masteryLevel(weaponId)), Font = K.DISPLAY_FONT, TextSize = 12,
			BackgroundTransparency = 0, BackgroundColor3 = Color3.fromHex("3d6fd6"), ZIndex = 3 })
		K.round(badge, 6)
	end
	if weaponId == equipped then
		local check = circle(slot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = K.COLORS.Good, ZIndex = 4 })
		K.outline(check, K.COLORS.Stroke, 2)
		K.newLabel(check, { Size = UDim2.fromScale(1, 1), Text = "✔", Font = K.DISPLAY_FONT, TextSize = 15, ZIndex = 5,
			TextXAlignment = Enum.TextXAlignment.Center })
		if lastEquipped ~= nil and lastEquipped ~= weaponId then
			local pop: UIScale = K.create("UIScale", { Scale = 2 }, check)
			tween(pop, SceneKit.POP, { Scale = 1 })
		end
	end

	-- Just forged or reactivated: flare from black into its colour.
	local before = lastStates[weaponId]
	if before and before ~= "Owned" and state == "Owned" then
		weaponIcon.ImageColor3 = Color3.new(1, 1, 1)
		tween(weaponIcon, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageColor3 = info.Accent })
		SceneKit.burst(slot, info.Accent)
		scale.Scale = 1.3
		tween(scale, SceneKit.POP, { Scale = if selected then 1.05 else 1 })
	end
	lastStates[weaponId] = state

	if not selected then
		SceneKit.hoverGrow(slot, scale, 1.05)
	end
	slot.Activated:Connect(function()
		if selectedWeapon ~= weaponId then
			selectedWeapon = weaponId
			Sfx.Play("UI_Tab", 0.4)
			K.renderStation()
		end
	end)
end

local function rack(order: number, equipped: string?)
	local wall = K.create("ImageLabel", { Size = UDim2.new(1, 0, 0, SLOT_HEIGHT * 2 + 34), BackgroundTransparency = 1,
		Image = UiTex.panel_brown, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(16, 16, 84, 84),
		LayoutOrder = order }, K.content())
	local grid: Frame = K.create("Frame", { Position = UDim2.fromOffset(12, 14), Size = UDim2.new(1, -24, 1, -24),
		BackgroundTransparency = 1 }, wall)
	local layout: UIGridLayout = K.create("UIGridLayout", { CellSize = UDim2.new(0.235, 0, 0, SLOT_HEIGHT),
		CellPadding = UDim2.new(0.02, 0, 0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	layout.FillDirectionMaxCells = 4
	for index, weaponId in WeaponConfig.Order do
		rackSlot(grid, weaponId, index, equipped)
	end
end

-- A stat chip on the detail card: an icon and a short value.
local function statChip(parent: Instance, image: string?, text: string, color: Color3, order: number)
	local chip: Frame = K.create("Frame", { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.fromHex("1f1712"), LayoutOrder = order }, parent)
	K.round(chip, 8)
	K.create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8) }, chip)
	K.list(chip, Enum.FillDirection.Horizontal, 5).VerticalAlignment = Enum.VerticalAlignment.Center
	icon(chip, image, { Size = UDim2.fromOffset(22, 22), ImageColor3 = color, LayoutOrder = 1 })
	K.newLabel(chip, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = text, Font = K.DISPLAY_FONT,
		TextSize = 17, TextStrokeTransparency = 0.2, LayoutOrder = 2 })
end

local function costChip(parent: Instance, iconKey: string, currency: string, amount: number, have: number, order: number)
	local chip: Frame = K.create("Frame", { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, LayoutOrder = order }, parent)
	K.list(chip, Enum.FillDirection.Horizontal, 4).VerticalAlignment = Enum.VerticalAlignment.Center
	icon(chip, Icons[iconKey], { Size = UDim2.fromOffset(26, 26), ImageColor3 = SceneKit.currencyColor(currency), LayoutOrder = 1 })
	K.newLabel(chip, { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, Text = K.formatNumber(amount),
		Font = K.DISPLAY_FONT, TextSize = 21, TextColor3 = if have >= amount then Color3.new(1, 1, 1) else RACK_COLORS.Bad,
		TextStrokeTransparency = 0.1, LayoutOrder = 2 })
end

local function detailCard(order: number, weaponId: string, equipped: string?)
	local info = WeaponConfig.Weapons[weaponId]
	local state = weaponState(weaponId)
	local card = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 176), BackgroundColor3 = RACK_COLORS.Card, LayoutOrder = order })

	-- The weapon, big.
	local disc = circle(card, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(124, 124),
		BackgroundColor3 = if state == "Owned" then info.Accent:Lerp(Color3.new(0, 0, 0), 0.6) else RACK_COLORS.SlotLocked })
	K.outline(disc, if state == "Owned" then info.Accent else K.COLORS.Stroke, 3)
	if state == "Owned" then
		local glow = icon(disc, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.9, 1.9), ImageColor3 = info.Accent, ImageTransparency = 0.6 })
		tween(glow, SceneKit.PULSE, { ImageTransparency = 0.3 })
	end
	local bigIcon = icon(disc, Icons["Weapon_" .. weaponId], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.64, 0.64), ImageColor3 = if state == "Locked" then Color3.fromHex("4a3a2c") else iconColor(info, state),
		ZIndex = 2 })
	if lastStates[weaponId .. "#card"] and lastStates[weaponId .. "#card"] ~= "Owned" and state == "Owned" then
		bigIcon.ImageColor3 = Color3.new(1, 1, 1)
		tween(bigIcon, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageColor3 = info.Accent })
		SceneKit.burst(disc, info.Accent)
	end
	lastStates[weaponId .. "#card"] = state

	-- Name, archetype, stat chips and the passive.
	local middle: Frame = K.create("Frame", { Position = UDim2.fromOffset(152, 10), Size = UDim2.new(1, -152 - 186, 1, -20),
		BackgroundTransparency = 1 }, card)
	K.newLabel(middle, { Size = UDim2.new(1, 0, 0, 28), Text = info.Name, Font = K.DISPLAY_FONT, TextSize = 26,
		TextColor3 = if state == "Locked" then Color3.new(1, 1, 1) else info.Accent, TextStrokeTransparency = 0 })
	K.newLabel(middle, { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 18), Text = info.Archetype, TextSize = 14,
		TextColor3 = K.COLORS.Muted })
	local chips: Frame = K.create("Frame", { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1 }, middle)
	K.list(chips, Enum.FillDirection.Horizontal, 6)
	statChip(chips, Icons.UI_Damage, tostring(info.BaseDamage), Color3.fromHex("ff8a5c"), 1)
	statChip(chips, Icons.UI_Timer, ("%.1f/s"):format(info.AttacksPerSecond), Color3.fromHex("7ad7ff"), 2)
	local ability = info.Ability
	if ability then
		statChip(chips, Icons["Ability_" .. ability.Id], ("Q · %ds"):format(math.round(ability.Cooldown)), Color3.fromHex("c9a6ff"), 3)
	end
	local passive = K.newLabel(middle, { Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 1, -88),
		Text = ("<font color='#%s'><b>%s</b></font>  %s%s"):format(K.COLORS.Gold:ToHex(), info.PassiveName, info.PassiveDesc,
			if ability then ("\n<font color='#c9a6ff'><b>Q · %s</b></font>"):format(ability.Name) else ""),
		TextSize = 14, TextScaled = true, TextWrapped = true, TextColor3 = Color3.fromHex("e6dccf"), TextYAlignment = Enum.TextYAlignment.Top })
	K.create("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 11 }, passive)

	-- The action: forge, reactivate, equip.
	local right: Frame = K.create("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 172, 1, -20), BackgroundTransparency = 1 }, card)
	local inRun = K.inRun()
	local text: string, color: Color3, enabled: boolean
	local action: string? = nil
	if state == "Owned" then
		if weaponId == equipped then
			text, color, enabled = "✔ Equipped", K.COLORS.Good, false
		else
			text, color, enabled, action = "Equip", K.COLORS.Accent, not inRun, "Equip"
		end
		K.newLabel(right, { Size = UDim2.new(1, 0, 0, 40), Text = ("Mastery <b>%d</b>"):format(masteryLevel(weaponId)),
			Font = K.DISPLAY_FONT, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2 })
	else
		local dust, cores = price(weaponId, state)
		local haveDust, haveCores = profileNumber("RiftDust"), profileNumber("BossCores")
		local costs: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, right)
		local costLayout = K.list(costs, Enum.FillDirection.Horizontal, 10)
		costLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		costLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		costChip(costs, "Cur_Dust", "RiftDust", dust, haveDust, 1)
		if cores > 0 then
			costChip(costs, "Cur_BossCores", "BossCores", cores, haveCores, 2)
		end
		local affordable = haveDust >= dust and haveCores >= cores
		action = "Unlock"
		color, enabled = K.COLORS.Gold, affordable and not inRun
		text = if inRun then "In a run" elseif not affordable then "Need more"
			elseif state == "Off" then "Reactivate" else "🔨 Forge"
		if state == "Off" then
			K.newLabel(right, { Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 40),
				Text = "Switched off by Rebirth.\n25% fee to wake it.", TextSize = 12, TextColor3 = K.COLORS.Muted,
				TextXAlignment = Enum.TextXAlignment.Center })
		end
	end
	local button = K.newButton(right, text, color, function()
		if not action then
			return
		end
		if action == "Unlock" then
			Sfx.Play("Forge_Hammer1", 0.6)
		else
			Sfx.Play("Weapon_Equip", 0.6)
		end
		loadoutRemote:FireServer({ Action = action, Weapon = weaponId })
	end, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 46), Size = UDim2.new(1, 0, 0, 54), TextSize = 20 })
	K.setEnabled(button, enabled, color)
end

local function renderBlacksmith()
	local equipped = equippedWeapon()
	selectedWeapon = selectedWeapon or equipped or WeaponConfig.DEFAULT_WEAPON
	-- A forge or reactivation that just landed rings out.
	local selectedId = selectedWeapon :: string
	local before = lastStates[selectedId .. "#card"]
	if before and before ~= "Owned" and weaponState(selectedId) == "Owned" then
		Sfx.Play("Forge_Success", 0.7)
	end
	header(1)
	rack(2, equipped)
	detailCard(3, selectedId, equipped)
	lastEquipped = equipped
end

BlacksmithScene.Render = renderBlacksmith

function BlacksmithScene.Init(kit: any)
	K = kit
	loadoutRemote = Remotes.GetEvent("LoadoutAction")
end

return BlacksmithScene
