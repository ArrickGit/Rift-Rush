--!strict
-- StarterPlayerScripts/Client/Controllers/BagScene.luau
-- The Bag drawn as a paper doll: your avatar with the equipped weapon slot beside it, Starting Relic slots down the
-- other side and the socketed Link gems underneath; the weapon's Mastery and stats on a card next to it; during a run
-- a strip of the relics and curses you carry; and a quick-swap grid of your weapons (tap to equip) and relics (tap to
-- start runs with it). Loadout changes are town-only, like the server's rules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local CurseConfig = require(Shared:WaitForChild("CurseConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Payload = { [string]: any }

local BagScene = {}

local K: any = nil -- UIController's kit, set by Init
local player = Players.LocalPlayer
local loadoutRemote: RemoteEvent

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon

local BAG_COLORS = {
	Doll = Color3.fromHex("23283f"),
	Card = Color3.fromHex("2a2f48"),
	Slot = Color3.fromHex("161a2c"),
	Dim = Color3.fromHex("5a6284"),
	Star = Color3.fromHex("ffcc33"),
	Curse = Color3.fromHex("c04bff"),
}
local NODE_TWIN_RELIC = "AS_T3_03" -- +1 Starting Relic slot (mirrors InventoryService)
local NODE_LEGION_COMMANDER = "AS_T3_04" -- +1 Link slot per level
local MAX_RELIC_SLOTS = 3 -- base + Twin Relic Vessel + Relic Vault Key pass

local lastWeapon: string? = nil
local lastRelics: { [string]: boolean }? = nil

local function profileTable(key: string): { [any]: any }
	local data = K.profile()
	local value = if data then data[key] else nil
	return if type(value) == "table" then value else {}
end

local function masteryOf(weaponId: string): (number, number, number)
	local live = K.liveMastery()
	if live and live.Weapon == weaponId then
		return live.Level, live.XP, live.Paragon
	end
	local entry = profileTable("WeaponMastery")[weaponId]
	if type(entry) ~= "table" then
		return 1, 0, 0
	end
	return tonumber(entry.Level) or 1, tonumber(entry.XP) or 0, tonumber(entry.ParagonRank) or 0
end

local function relicSlots(): number
	return RelicConfig.GetStartingSlots(tonumber(profileTable("AscensionNodes")[NODE_TWIN_RELIC]) or 0,
		player:GetAttribute("HasRelicVaultKey") == true)
end

local function linkSlots(): number
	return WeaponConfig.GetLinkSlots(tonumber(profileTable("AscensionNodes")[NODE_LEGION_COMMANDER]) or 0,
		player:GetAttribute("HasExtraLinkSlots") == true)
end

local function relicStars(relicId: string): number?
	local owned = profileTable("RelicStars")[relicId]
	return if type(owned) == "table" then tonumber(owned.Stars) or 1 else nil
end

local function pop(gui: GuiObject, color: Color3)
	local scale: UIScale = K.create("UIScale", { Scale = 1.5 }, gui)
	tween(scale, SceneKit.POP, { Scale = 1 })
	SceneKit.burst(gui, color)
end

-- A square slot with an icon (or a "+" / padlock when empty).
local function slot(parent: Instance, size: number, image: string?, color: Color3?, props: Payload): Frame
	local frame: Frame = K.create("Frame", { Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = if color then color:Lerp(Color3.new(0, 0, 0), 0.6) else BAG_COLORS.Slot }, parent)
	for key, value in props do
		(frame :: any)[key] = value
	end
	K.round(frame, 12)
	K.create("UIStroke", { Color = color or K.COLORS.Stroke, Thickness = if color then 3 else 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		frame)
	if image then
		icon(frame, image, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.64, 0.64),
			ImageColor3 = color or BAG_COLORS.Dim, ZIndex = 2 })
	end
	return frame
end

-- The paper doll: avatar, weapon slot, Starting Relic slots and Link gems.
local function doll(parent: Instance, weapon: WeaponConfig.WeaponInfo)
	local panel = K.newPanel(parent, { Size = UDim2.new(0.6, 0, 1, 0), BackgroundColor3 = BAG_COLORS.Doll })
	panel.ClipsDescendants = true
	icon(panel, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(260, 220),
		ScaleType = Enum.ScaleType.Stretch, ImageColor3 = weapon.Accent, ImageTransparency = 0.78 })
	-- Full-body thumbnails carry a lot of empty margin, so this one is drawn larger than the space it seems to fill.
	icon(panel, ("rbxthumb://type=Avatar&id=%d&w=420&h=420"):format(player.UserId), { AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, -4, 0, -14), Size = UDim2.fromOffset(204, 204) })

	-- Weapon slot on the left.
	local level, _, paragon = masteryOf(weapon.Id)
	local weaponSlot = slot(panel, 82, Icons["Weapon_" .. weapon.Id], weapon.Accent, { Position = UDim2.fromOffset(12, 34) })
	local badge: TextLabel = K.newLabel(weaponSlot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
		Text = if paragon > 0 then (" P%d "):format(paragon) else (" M%d "):format(level), Font = K.DISPLAY_FONT, TextSize = 13,
		BackgroundTransparency = 0, BackgroundColor3 = Color3.fromHex("3d6fd6"), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	K.round(badge, 6)
	K.newLabel(panel, { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(82, 18), Text = "Weapon", TextSize = 13,
		TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center })
	if lastWeapon and lastWeapon ~= weapon.Id then
		pop(weaponSlot, weapon.Accent)
	end
	lastWeapon = weapon.Id

	-- Starting Relic slots on the right.
	K.newLabel(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.fromOffset(70, 16), Text = "Relics",
		TextSize = 13, TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center })
	local equipped = profileTable("EquippedStartingRelics")
	local slots = relicSlots()
	local nowRelics: { [string]: boolean } = {}
	for index = 1, MAX_RELIC_SLOTS do
		local relicId = equipped[index]
		local info = if type(relicId) == "string" then RelicConfig.Relics[relicId] else nil
		local relicSlot = slot(panel, 48, if info then Icons["Relic_" .. (relicId :: string)] elseif index > slots then Icons.UI_Lock else nil,
			if info then info.Color else nil, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -19, 0, 22 + (index - 1) * 54) })
		if info then
			local id = relicId :: string
			nowRelics[id] = true
			K.newLabel(relicSlot, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.new(1, 0, 0, 12),
				Text = string.rep("★", relicStars(id) or 1), TextSize = 10, TextColor3 = BAG_COLORS.Star,
				TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, ZIndex = 3 })
			if lastRelics and not lastRelics[id] then
				pop(relicSlot, info.Color)
			end
		elseif index <= slots then
			K.newLabel(relicSlot, { Size = UDim2.fromScale(1, 1), Text = "+", Font = K.DISPLAY_FONT, TextSize = 24, TextColor3 = BAG_COLORS.Dim,
				TextXAlignment = Enum.TextXAlignment.Center })
		end
	end
	lastRelics = nowRelics

	-- Socketed Link gems along the bottom.
	local gems: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 32),
		BackgroundTransparency = 1 }, panel)
	local layout = K.list(gems, Enum.FillDirection.Horizontal, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local active = profileTable("ActiveLinkSkills")
	local links = linkSlots()
	for index = 1, WeaponConfig.MAX_LINK_SLOTS do
		local linkId = active[index]
		local info = if type(linkId) == "string" then WeaponConfig.GetWeaponForLink(linkId) else nil
		local gem = circle(gems, { Size = UDim2.fromOffset(30, 30), LayoutOrder = index,
			BackgroundColor3 = if info then info.Accent:Lerp(Color3.new(0, 0, 0), 0.55) else BAG_COLORS.Slot })
		K.outline(gem, if info then info.Accent else K.COLORS.Stroke, 2)
		if info then
			icon(gem, Icons["Link_" .. info.Link.Id], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.66, 0.66), ImageColor3 = info.Accent })
		elseif index > links then
			icon(gem, Icons.UI_Lock, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5),
				ImageColor3 = BAG_COLORS.Dim })
		end
	end
end

local function statChip(parent: Instance, image: string?, text: string, color: Color3, order: number)
	local chip: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = BAG_COLORS.Slot, LayoutOrder = order }, parent)
	K.round(chip, 8)
	icon(chip, image, { Position = UDim2.fromOffset(6, 3), Size = UDim2.fromOffset(22, 22), ImageColor3 = color })
	K.newLabel(chip, { Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -38, 1, 0), Text = text, Font = K.DISPLAY_FONT, TextSize = 16,
		TextStrokeTransparency = 0.2, TextTruncate = Enum.TextTruncate.AtEnd })
end

-- The equipped weapon's card: name, Mastery bar, stat chips.
local function weaponCard(parent: Instance, weapon: WeaponConfig.WeaponInfo)
	local card = K.newPanel(parent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, 0, 1, 0),
		BackgroundColor3 = BAG_COLORS.Card })
	K.pad(card, 10)
	K.newLabel(card, { Size = UDim2.new(1, 0, 0, 26), Text = weapon.Name, Font = K.DISPLAY_FONT, TextSize = 23, TextColor3 = weapon.Accent,
		TextStrokeTransparency = 0 })
	local level, xp, paragon = masteryOf(weapon.Id)
	local required = WeaponConfig.GetMasteryXPRequired(if level >= WeaponConfig.MAX_MASTERY then WeaponConfig.MAX_MASTERY + paragon else level)
	local track: Frame = K.create("Frame", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = BAG_COLORS.Slot, BorderSizePixel = 0 }, card)
	K.round(track, 8)
	K.outline(track, K.COLORS.Stroke, 2)
	local fill: Frame = K.create("Frame", { Size = UDim2.fromScale(math.clamp(xp / math.max(1, required), 0, 1), 1), BorderSizePixel = 0,
		BackgroundColor3 = weapon.Accent }, track)
	K.round(fill, 8)
	K.newLabel(track, { Size = UDim2.fromScale(1, 1), Text = if paragon > 0 then ("Paragon %d"):format(paragon) else ("Mastery %d"):format(level),
		Font = K.DISPLAY_FONT, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.1, ZIndex = 2 })

	local chips: Frame = K.create("Frame", { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -58), BackgroundTransparency = 1 }, card)
	K.list(chips, Enum.FillDirection.Vertical, 5)
	statChip(chips, Icons.UI_Damage, ("%d damage"):format(weapon.BaseDamage), Color3.fromHex("ff8a5c"), 1)
	statChip(chips, Icons.UI_Timer, ("%.1f hits / s"):format(weapon.AttacksPerSecond), Color3.fromHex("7ad7ff"), 2)
	local ability = weapon.Ability
	if ability then
		statChip(chips, Icons["Ability_" .. ability.Id], ("%s · %ds"):format(ability.Name, math.round(ability.Cooldown)), Color3.fromHex("c9a6ff"), 3)
	end
	statChip(chips, Icons.UI_Mastery, weapon.PassiveName, K.COLORS.Gold, 4)
end

-- During a run: the relics and curses you carry.
local function runStrip(order: number)
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = order }, K.content())
	local layout = K.list(row, Enum.FillDirection.Horizontal, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	K.newLabel(row, { Size = UDim2.fromOffset(78, 44), Text = "This run", Font = K.DISPLAY_FONT, TextSize = 17, TextColor3 = K.COLORS.Gold,
		LayoutOrder = 0, TextStrokeTransparency = 0 })
	local count = 0
	local runRelics = player:GetAttribute("RunRelics")
	if type(runRelics) == "string" then
		for entry in runRelics:gmatch("[^,]+") do
			local id, stars = entry:match("^(.-):(%d+)$")
			local info = if id then RelicConfig.Relics[id] else nil
			if info and id and stars then
				count += 1
				local chip = slot(row, 40, Icons["Relic_" .. id], info.Color, { LayoutOrder = count })
				K.newLabel(chip, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.new(1, 0, 0, 11),
					Text = string.rep("★", tonumber(stars) or 1), TextSize = 9, TextColor3 = BAG_COLORS.Star,
					TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
			end
		end
	end
	local curses = player:GetAttribute("RunCurses")
	if type(curses) == "string" then
		for id in curses:gmatch("[^,]+") do
			if CurseConfig.Curses[id] then
				count += 1
				slot(row, 40, Icons["Curse_" .. id], BAG_COLORS.Curse, { LayoutOrder = count })
			end
		end
	end
	if count == 0 then
		K.newLabel(row, { Size = UDim2.fromOffset(400, 44), Text = "Nothing yet — bosses, chests and altars grant relics and curses.",
			TextSize = 14, TextColor3 = K.COLORS.Muted, LayoutOrder = 1 })
	end
end

-- A row of tappable tiles under a small heading.
local function tileRow(order: number, heading: string): Frame
	K.newLabel(K.content(), { Size = UDim2.new(1, 0, 0, 20), Text = heading, Font = K.DISPLAY_FONT, TextSize = 17, TextColor3 = K.COLORS.Gold,
		TextStrokeTransparency = 0, LayoutOrder = order })
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, LayoutOrder = order + 1 }, K.content())
	local layout = K.list(row, Enum.FillDirection.Horizontal, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	return row
end

local function tile(row: Instance, index: number, image: string?, color: Color3, label: string, marked: boolean, enabled: boolean,
	onClick: () -> ())
	local button: TextButton = K.create("TextButton", { Size = UDim2.fromOffset(58, 58), Text = "", AutoButtonColor = false,
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.62), LayoutOrder = index }, row)
	K.round(button, 12)
	K.create("UIStroke", { Color = if marked then Color3.new(1, 1, 1) else color, Thickness = if marked then 3.5 else 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
	icon(button, image, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.fromOffset(34, 34), ImageColor3 = color })
	K.newLabel(button, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -1), Size = UDim2.new(1, 0, 0, 16), Text = label,
		TextSize = 12, TextColor3 = if marked then Color3.new(1, 1, 1) else K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2 })
	if marked then
		local check = circle(button, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(18, 18),
			BackgroundColor3 = K.COLORS.Good, ZIndex = 3 })
		K.outline(check, K.COLORS.Stroke, 1.5)
	end
	local scale: UIScale = K.create("UIScale", {}, button)
	if enabled then
		SceneKit.hoverGrow(button, scale, 1.08)
		button.Activated:Connect(onClick)
	end
end

local function quickSwap(order: number)
	local inRun = K.inRun()
	local data = K.profile() :: Payload
	local weapons = tileRow(order, if inRun then "Weapons  ·  swap in town" else "Weapons  ·  tap to equip")
	local count = 0
	for _, weaponId in WeaponConfig.Order do
		if profileTable("UnlockedWeapons")[weaponId] == true then
			count += 1
			local info = WeaponConfig.Weapons[weaponId]
			local level, _, paragon = masteryOf(weaponId)
			local equipped = data.EquippedWeapon == weaponId
			tile(weapons, count, Icons["Weapon_" .. weaponId], info.Accent, if paragon > 0 then ("P%d"):format(paragon) else ("M%d"):format(level),
				equipped, not inRun and not equipped, function()
					Sfx.Play("Weapon_Equip", 0.6)
					loadoutRemote:FireServer({ Action = "Equip", Weapon = weaponId })
				end)
		end
	end

	local relics = tileRow(order + 2, if inRun then "Relics  ·  change in town" else "Relics  ·  tap to start runs with")
	local equippedRelics = profileTable("EquippedStartingRelics")
	local full = #equippedRelics >= relicSlots()
	count = 0
	for _, relicId in RelicConfig.Order do
		local stars = relicStars(relicId)
		if stars then
			count += 1
			local info = RelicConfig.Relics[relicId]
			local starting = table.find(equippedRelics, relicId) ~= nil
			tile(relics, count, Icons["Relic_" .. relicId], info.Color, string.rep("★", stars), starting, not inRun and (starting or not full),
				function()
					Sfx.Play(if starting then "UI_Toggle" else "Weapon_Equip", 0.6)
					loadoutRemote:FireServer({ Action = if starting then "UnequipRelic" else "EquipRelic", Relic = relicId })
				end)
		end
	end
	if count == 0 then
		K.newLabel(relics, { Size = UDim2.fromOffset(420, 58), Text = "No relics yet — bosses and chests drop them.", TextSize = 14,
			TextColor3 = K.COLORS.Muted })
	end
end

local function renderBag()
	local data = K.profile()
	if not data then
		K.paragraph(1, "Loading…", K.COLORS.Muted)
		return
	end
	local weapon = WeaponConfig.Weapons[data.EquippedWeapon] or WeaponConfig.Weapons[WeaponConfig.DEFAULT_WEAPON]
	local body: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 214), BackgroundTransparency = 1, LayoutOrder = 1 }, K.content())
	doll(body, weapon)
	weaponCard(body, weapon)
	if K.inRun() then
		runStrip(2)
	end
	quickSwap(3)
end

BagScene.Render = renderBag

function BagScene.Init(kit: any)
	K = kit
	loadoutRemote = Remotes.GetEvent("LoadoutAction")
end

return BagScene
