--!strict
-- StarterPlayerScripts/Client/Controllers/LegionScene.luau
-- The Legion Hall window drawn as a mastery shrine: a bar of Link Skill gem sockets along the top (filled, open,
-- locked), the selected weapon inside a ring of 20 Mastery pips (the 10th and 20th are gems: they unlock the Link's
-- two tiers), its Link card beside it with the bonus as a big number and one Equip button, and a strip of the 8
-- weapons along the bottom to pick from. A newly socketed gem pops in; a weapon that levelled since the last look
-- flares.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

local LegionScene = {}

local K: any = nil -- UIController's kit, set by Init
local player = Players.LocalPlayer
local loadoutRemote: RemoteEvent

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon

local LEGION_COLORS = {
	Shrine = Color3.fromHex("1d2340"),
	Card = Color3.fromHex("262a45"),
	Socket = Color3.fromHex("14182c"),
	Pip = Color3.fromHex("2e3557"),
	PipLit = Color3.fromHex("ffcf5a"),
	Silhouette = Color3.fromHex("3a4260"),
	Dim = Color3.fromHex("5a6284"),
}
local LINK_STAT_NAMES: { [string]: string } = {
	NormalEliteDamage = "Normal & Elite Damage",
	CritDamage = "Crit Damage",
	StatusDamageDuration = "Status Damage & Duration",
	CritRate = "Crit Rate",
	BossDamage = "Boss Damage",
	AttackSpeedCooldown = "Attack Speed & Cooldowns",
	DustDropRate = "Rift Dust Find",
	RareUpgradeRate = "Rare / Epic Upgrade Chance",
}
local NODE_LEGION_COMMANDER = "AS_T3_04" -- +1 Link slot per level (mirrors InventoryService)
local RING_RADIUS = 92
local RING_CENTER_Y = 112

local selectedWeapon: string? = nil
local lastActive: { [string]: boolean }? = nil -- Link ids socketed at the last render (nil before the first)
local lastLevels: { [string]: number } = {}

local function profileTable(key: string): { [any]: any }
	local data = K.profile()
	local value = if data then data[key] else nil
	return if type(value) == "table" then value else {}
end

-- (level, xp, paragon), preferring the live MasteryUpdated numbers for the equipped weapon.
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

local function linkSlots(): number
	return WeaponConfig.GetLinkSlots(tonumber(profileTable("AscensionNodes")[NODE_LEGION_COMMANDER]) or 0,
		player:GetAttribute("HasExtraLinkSlots") == true)
end

local function owned(weaponId: string): boolean
	return profileTable("UnlockedWeapons")[weaponId] == true
end

local function percent(value: number): string
	return ("+%d%%"):format(math.round(value * 100))
end

-- The gem bar: one socket per possible Link slot.
local function socketBar(order: number)
	local active = profileTable("ActiveLinkSkills")
	local slots = linkSlots()
	local bar = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = LEGION_COLORS.Card, LayoutOrder = order })
	icon(bar, Icons.UI_Mastery, { Position = UDim2.fromOffset(12, 13), Size = UDim2.fromOffset(36, 36), ImageColor3 = LEGION_COLORS.PipLit })
	K.newLabel(bar, { Position = UDim2.fromOffset(54, 0), Size = UDim2.fromOffset(80, 62), Text = "Link\nSkills", TextSize = 15,
		TextColor3 = K.COLORS.Muted, LineHeight = 0.95 })
	K.newLabel(bar, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(80, 62),
		Text = ("%d/%d"):format(#active, slots), Font = K.DISPLAY_FONT, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0 })

	local row: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -260, 0, 48), BackgroundTransparency = 1 }, bar)
	local layout = K.list(row, Enum.FillDirection.Horizontal, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local nowActive: { [string]: boolean } = {}
	for index = 1, WeaponConfig.MAX_LINK_SLOTS do
		local linkId = active[index]
		local info = if type(linkId) == "string" then WeaponConfig.GetWeaponForLink(linkId) else nil
		local socket: TextButton = K.create("TextButton", { Size = UDim2.fromOffset(46, 46), Text = "", AutoButtonColor = false,
			BackgroundColor3 = if info then info.Accent:Lerp(Color3.new(0, 0, 0), 0.55) else LEGION_COLORS.Socket, LayoutOrder = index }, row)
		K.create("UICorner", { CornerRadius = UDim.new(0.5, 0) }, socket)
		K.create("UIStroke", { Color = if info then info.Accent elseif index <= slots then LEGION_COLORS.Dim else K.COLORS.Stroke,
			Thickness = if info then 3 else 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, socket)
		if info then
			nowActive[info.Link.Id] = true
			icon(socket, Icons["Link_" .. info.Link.Id], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.64, 0.64), ImageColor3 = info.Accent })
			if lastActive and not lastActive[info.Link.Id] then
				-- Just socketed: the gem pops in.
				local pop: UIScale = K.create("UIScale", { Scale = 1.8 }, socket)
				tween(pop, SceneKit.POP, { Scale = 1 })
				SceneKit.burst(socket, info.Accent)
			end
			local weaponId = info.Id
			socket.Activated:Connect(function()
				if selectedWeapon ~= weaponId then
					selectedWeapon = weaponId
					Sfx.Play("UI_Tab", 0.4)
					K.renderStation()
				end
			end)
		elseif index <= slots then
			K.newLabel(socket, { Size = UDim2.fromScale(1, 1), Text = "+", Font = K.DISPLAY_FONT, TextSize = 24,
				TextColor3 = LEGION_COLORS.Dim, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1 })
		else
			icon(socket, Icons.UI_Lock, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.45, 0.45), ImageColor3 = LEGION_COLORS.Silhouette })
		end
	end
	lastActive = nowActive
end

-- The selected weapon inside its ring of 20 Mastery pips, with the level and XP bar under it.
local function shrine(parent: Instance, weaponId: string)
	local info = WeaponConfig.Weapons[weaponId]
	local level, xp, paragon = masteryOf(weaponId)
	local isOwned = owned(weaponId)
	local panel = K.newPanel(parent, { Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = LEGION_COLORS.Shrine })
	panel.ClipsDescendants = true
	icon(panel, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, RING_CENTER_Y),
		Size = UDim2.fromOffset(300, 300), ImageColor3 = info.Accent, ImageTransparency = 0.8 })

	local ring: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, RING_CENTER_Y),
		Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }, panel)
	for pipLevel = 1, WeaponConfig.MAX_MASTERY do
		local angle = math.rad(-90 + (pipLevel - 1) * 360 / WeaponConfig.MAX_MASTERY)
		local milestone = pipLevel == WeaponConfig.LINK_TIER1_LEVEL or pipLevel == WeaponConfig.LINK_TIER2_LEVEL
		local lit = pipLevel <= level
		local size = if milestone then 22 else 13
		local pip = circle(ring, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromOffset(1 + math.cos(angle) * RING_RADIUS, 1 + math.sin(angle) * RING_RADIUS),
			BackgroundColor3 = if lit then (if milestone then info.Accent else LEGION_COLORS.PipLit) else LEGION_COLORS.Pip })
		K.outline(pip, if milestone then (if lit then Color3.new(1, 1, 1) else info.Accent) else K.COLORS.Stroke, if milestone then 2.5 else 1.5)
		if milestone then
			K.newLabel(pip, { Size = UDim2.fromScale(1, 1), Text = tostring(pipLevel), Font = K.DISPLAY_FONT, TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 })
		end
		if pipLevel == level + 1 then
			-- The level you're working towards.
			tween(pip, SceneKit.PULSE, { BackgroundColor3 = LEGION_COLORS.PipLit:Lerp(LEGION_COLORS.Pip, 0.4) })
		end
	end

	local disc = circle(panel, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, RING_CENTER_Y),
		Size = UDim2.fromOffset(118, 118), BackgroundColor3 = info.Accent:Lerp(Color3.new(0, 0, 0), if isOwned then 0.55 else 0.8) })
	K.outline(disc, if isOwned then info.Accent else K.COLORS.Stroke, 3)
	icon(disc, Icons["Weapon_" .. weaponId], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62), ImageColor3 = if isOwned then info.Accent else LEGION_COLORS.Silhouette })
	local before = lastLevels[weaponId]
	if before and level + paragon > before then
		Sfx.Play("UI_Unlock", 0.6)
		SceneKit.burst(disc, LEGION_COLORS.PipLit)
	end
	lastLevels[weaponId] = level + paragon

	local rankText = if paragon > 0 then ("Paragon <b>%d</b>"):format(paragon) else ("Mastery <b>%d</b>"):format(level)
	K.newLabel(panel, { Position = UDim2.fromOffset(0, 216), Size = UDim2.new(1, 0, 0, 26),
		Text = ("%s  <font size='15' color='#%s'>%s</font>"):format(rankText, K.COLORS.Muted:ToHex(), info.Name),
		Font = K.DISPLAY_FONT, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0 })
	local required = WeaponConfig.GetMasteryXPRequired(if level >= WeaponConfig.MAX_MASTERY then WeaponConfig.MAX_MASTERY + paragon else level)
	local track: Frame = K.create("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 246),
		Size = UDim2.new(1, -40, 0, 14), BackgroundColor3 = LEGION_COLORS.Socket, BorderSizePixel = 0 }, panel)
	K.round(track, 7)
	K.outline(track, K.COLORS.Stroke, 2)
	local fill: Frame = K.create("Frame", { Size = UDim2.fromScale(math.clamp(xp / math.max(1, required), 0, 1), 1),
		BackgroundColor3 = LEGION_COLORS.PipLit, BorderSizePixel = 0 }, track)
	K.round(fill, 7)
	K.newLabel(track, { Size = UDim2.fromScale(1, 1), Text = ("%s / %s XP"):format(K.formatNumber(xp), K.formatNumber(required)),
		TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2, ZIndex = 2 })
end

-- A tier milestone chip: "M10 · +8%", lit once reached.
local function tierChip(parent: Instance, mastery: number, value: number, reached: boolean, accent: Color3, order: number)
	local chip: Frame = K.create("Frame", { Size = UDim2.new(0.48, 0, 1, 0), LayoutOrder = order,
		BackgroundColor3 = if reached then accent:Lerp(Color3.new(0, 0, 0), 0.45) else LEGION_COLORS.Socket }, parent)
	K.round(chip, 10)
	K.outline(chip, if reached then accent else K.COLORS.Stroke, 2)
	K.newLabel(chip, { Size = UDim2.fromScale(1, 1), Text = ("M%d  <b>%s</b>"):format(mastery, percent(value)), Font = K.DISPLAY_FONT,
		TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = if reached then Color3.new(1, 1, 1) else LEGION_COLORS.Dim, TextStrokeTransparency = if reached then 0.2 else 1 })
end

local function linkCard(parent: Instance, weaponId: string)
	local info = WeaponConfig.Weapons[weaponId]
	local link = info.Link
	local level = masteryOf(weaponId)
	local active = profileTable("ActiveLinkSkills")
	local socketed = table.find(active, link.Id) ~= nil
	local value = WeaponConfig.GetLinkValue(weaponId, level)
	local unlocked = level >= WeaponConfig.LINK_TIER1_LEVEL

	local card = K.newPanel(parent, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.48, 0, 1, 0),
		BackgroundColor3 = LEGION_COLORS.Card })
	K.pad(card, 10)
	local gem = circle(card, { Size = UDim2.fromOffset(62, 62), BackgroundColor3 = info.Accent:Lerp(Color3.new(0, 0, 0), if unlocked then 0.5 else 0.8) })
	K.outline(gem, if unlocked then info.Accent else K.COLORS.Stroke, 3)
	icon(gem, Icons["Link_" .. link.Id], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.62), ImageColor3 = if unlocked then info.Accent else LEGION_COLORS.Dim })
	K.newLabel(card, { Position = UDim2.fromOffset(72, 4), Size = UDim2.new(1, -72, 0, 28), Text = link.Name, Font = K.DISPLAY_FONT,
		TextSize = 22, TextScaled = true, TextColor3 = if unlocked then info.Accent else Color3.new(1, 1, 1), TextStrokeTransparency = 0 })
	K.newLabel(card, { Position = UDim2.fromOffset(72, 34), Size = UDim2.new(1, -72, 0, 22), Text = "Link Skill · any weapon",
		TextSize = 13, TextColor3 = K.COLORS.Muted })

	K.newLabel(card, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 46),
		Text = if unlocked then percent(value) else "🔒", Font = K.DISPLAY_FONT, TextSize = 44,
		TextColor3 = if unlocked then LEGION_COLORS.PipLit else LEGION_COLORS.Dim, TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0 })
	K.newLabel(card, { Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, 0, 0, 20), Text = LINK_STAT_NAMES[link.Stat] or link.Stat,
		TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center })

	local tiers: Frame = K.create("Frame", { Position = UDim2.fromOffset(0, 144), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, card)
	local tierLayout = K.list(tiers, Enum.FillDirection.Horizontal, 8)
	tierLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tierChip(tiers, WeaponConfig.LINK_TIER1_LEVEL, link.Lv10, level >= WeaponConfig.LINK_TIER1_LEVEL, info.Accent, 1)
	tierChip(tiers, WeaponConfig.LINK_TIER2_LEVEL, link.Lv20, level >= WeaponConfig.LINK_TIER2_LEVEL, info.Accent, 2)

	local inRun = K.inRun()
	local text: string, color: Color3, enabled: boolean
	if not unlocked then
		text, color, enabled = ("Reach Mastery %d"):format(WeaponConfig.LINK_TIER1_LEVEL), K.COLORS.PanelLight, false
	elseif socketed then
		text, color, enabled = "Remove gem", K.COLORS.Bad, not inRun
	else
		local full = #active >= linkSlots()
		text, color, enabled = if full then "Slots full" else "💎 Socket it", K.COLORS.Accent, not inRun and not full
	end
	local button = K.newButton(card, text, color, function()
		if not unlocked then
			return
		end
		Sfx.Play(if socketed then "UI_Toggle" else "UI_Unlock", 0.6)
		loadoutRemote:FireServer({ Action = if socketed then "UnequipLink" else "EquipLink", Link = link.Id })
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 54), TextSize = 19 })
	K.setEnabled(button, enabled, color)
end

-- The 8 weapons to pick from, each with its Mastery level and a gem dot if its Link is socketed.
local function strip(order: number)
	local active = profileTable("ActiveLinkSkills")
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 1, LayoutOrder = order }, K.content())
	local layout = K.list(row, Enum.FillDirection.Horizontal, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	for index, weaponId in WeaponConfig.Order do
		local info = WeaponConfig.Weapons[weaponId]
		local level, _, paragon = masteryOf(weaponId)
		local selected = weaponId == selectedWeapon
		local isOwned = owned(weaponId)
		local tile: TextButton = K.create("TextButton", { Size = UDim2.fromOffset(66, 66), Text = "", AutoButtonColor = false,
			BackgroundColor3 = if isOwned then info.Accent:Lerp(Color3.new(0, 0, 0), 0.65) else LEGION_COLORS.Socket, LayoutOrder = index }, row)
		K.round(tile, 14)
		K.create("UIStroke", { Color = if selected then Color3.new(1, 1, 1) elseif isOwned then info.Accent else K.COLORS.Stroke,
			Thickness = if selected then 4 else 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tile)
		local scale: UIScale = K.create("UIScale", { Scale = if selected then 1.08 else 1 }, tile)
		icon(tile, Icons["Weapon_" .. weaponId], { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(38, 38), ImageColor3 = if isOwned then info.Accent else LEGION_COLORS.Silhouette })
		K.newLabel(tile, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, 0, 0, 18),
			Text = if paragon > 0 then ("P%d"):format(paragon) else ("M%d"):format(level), Font = K.DISPLAY_FONT, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2,
			TextColor3 = if level >= WeaponConfig.LINK_TIER1_LEVEL then LEGION_COLORS.PipLit else Color3.new(1, 1, 1) })
		if table.find(active, info.Link.Id) then
			local dot = circle(tile, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -5, 0, 5), Size = UDim2.fromOffset(20, 20),
				BackgroundColor3 = info.Accent, ZIndex = 3 })
			K.outline(dot, K.COLORS.Stroke, 2)
			icon(dot, Icons["Link_" .. info.Link.Id], { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.7, 0.7), ZIndex = 4 })
		end
		if not selected then
			SceneKit.hoverGrow(tile, scale, 1.08)
		end
		tile.Activated:Connect(function()
			if selectedWeapon ~= weaponId then
				selectedWeapon = weaponId
				Sfx.Play("UI_Tab", 0.4)
				K.renderStation()
			end
		end)
	end
end

local function renderLegionHall()
	local data = K.profile()
	selectedWeapon = selectedWeapon or (if data then data.EquippedWeapon else nil) or WeaponConfig.DEFAULT_WEAPON
	local weaponId = selectedWeapon :: string
	socketBar(1)
	local body: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 272), BackgroundTransparency = 1, LayoutOrder = 2 }, K.content())
	shrine(body, weaponId)
	linkCard(body, weaponId)
	strip(3)
end

LegionScene.Render = renderLegionHall

function LegionScene.Init(kit: any)
	K = kit
	loadoutRemote = Remotes.GetEvent("LoadoutAction")
end

return LegionScene
