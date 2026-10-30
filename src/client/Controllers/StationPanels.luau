--!strict
-- StarterPlayerScripts/Client/Controllers/StationPanels.luau
-- The loadout panels UIController shows in its station window (game.md Steps SP-2 / SP-3 / SP-5 / SP-6):
--   Blacksmith (forge / reactivate weapons), Legion Hall (Mastery & Link Skills), Hall of Champions and the Bag
--   (Inventory, usable anywhere). The Spark Sanctum and Quest Board (StationScenes) and the Star-Forge
--   (StarForgeScene) are drawn as scenes and routed through Renderers here.
-- Also the centre-screen Celebrate banner (new relics, Mastery levels / Link Skills, quest rewards).
--
-- UIController owns the window and passes its drawing helpers in as a kit (Init); renderers draw into kit.content()
-- and every button fires a validated remote (LoadoutAction, StarForce, ClaimQuest). Kept apart from UIController
-- so neither module comes near Luau's 200-local limit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CurseConfig = require(Shared:WaitForChild("CurseConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local StarForgeScene = require(script.Parent:WaitForChild("StarForgeScene"))
local StationScenes = require(script.Parent:WaitForChild("StationScenes"))

type Payload = { [string]: any }

local StationPanels = {}

local player = Players.LocalPlayer
local K: any = nil -- UIController's kit, set by Init
local loadoutRemote: RemoteEvent

local celebrateFrame: Frame
local celebrateIcon: TextLabel
local celebrateTitle: TextLabel
local celebrateBody: TextLabel
local celebrateStroke: UIStroke
local celebrateQueue: { Payload } = {}
local celebrating = false

-- Loadout panels (Blacksmith, Legion Hall, Star-Forge, Bag) ------------------------------------------------------

type RowButton = { Text: string, Color: Color3, Enabled: boolean, OnClick: () -> () }

local LINK_STAT_NAMES: { [string]: string } = {
	NormalEliteDamage = "Normal & Elite Dmg",
	CritDamage = "Crit Damage",
	StatusDamageDuration = "Status Dmg & Duration",
	CritRate = "Crit Rate",
	BossDamage = "Boss Damage",
	AttackSpeedCooldown = "Atk Speed & CDR",
	DustDropRate = "Rift Dust Find",
	RareUpgradeRate = "Rare/Epic Upgrades",
}
local REACTIVATION_FEE_FRACTION = 0.25 -- mirrors RebirthService (display only)

local function loadoutAction(action: string, fields: Payload)
	local payload = table.clone(fields)
	payload.Action = action
	loadoutRemote:FireServer(payload)
end

local function profileTable(key: string): { [any]: any }
	local data = K.profile()
	local value = if data then data[key] else nil
	return if type(value) == "table" then value else {}
end

local function profileNumber(key: string): number
	local data = K.profile()
	return if data then tonumber(data[key]) or 0 else 0
end

-- (level, xp, paragon) of a weapon's Mastery, preferring the live MasteryUpdated numbers for the equipped weapon.
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

local function masteryRequired(level: number, paragon: number): number
	return WeaponConfig.GetMasteryXPRequired(if level >= WeaponConfig.MAX_MASTERY then WeaponConfig.MAX_MASTERY + paragon else level)
end

local function masteryText(level: number, xp: number, paragon: number): string
	local required = masteryRequired(level, paragon)
	local rank = if paragon > 0 then ("Paragon %d"):format(paragon) else ("Mastery %d"):format(level)
	return ("%s · %s / %s XP"):format(rank, K.formatNumber(xp), K.formatNumber(required))
end

local function stars(count: number): string
	return string.rep("★", count) .. string.rep("☆", RelicConfig.MAX_STARS - count)
end

-- A row like itemRow, with any number of buttons on the right (and an optional taller body for long text).
local function actionRow(order: number, title: string, desc: string, buttons: { RowButton }, height: number?)
	local rowHeight = height or 78
	local buttonWidth = 132
	local reserved = #buttons * (buttonWidth + 8) + 6
	local frame: Frame = K.create("Frame", { Size = UDim2.new(1, -6, 0, rowHeight), BackgroundColor3 = K.COLORS.PanelLight,
		LayoutOrder = order }, K.content())
	K.round(frame, 12)
	K.outline(frame, K.COLORS.Stroke, 2.5)
	K.topLit(frame, 0.78)
	K.pad(frame, 10)
	K.newLabel(frame, { Size = UDim2.new(1, -reserved, 0, 22), Text = title, Font = K.DISPLAY_FONT, TextSize = 18,
		TextStrokeTransparency = 0.2, TextTruncate = Enum.TextTruncate.AtEnd })
	K.newLabel(frame, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -reserved, 1, -24), Text = desc,
		TextColor3 = K.COLORS.Muted, TextSize = 13, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	for index, spec in buttons do
		local button = K.newButton(frame, spec.Text, spec.Color, spec.OnClick, { AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(#buttons - index) * (buttonWidth + 8), 0.5, 0), Size = UDim2.fromOffset(buttonWidth, 42),
			TextSize = 15 })
		K.setEnabled(button, spec.Enabled, spec.Color)
	end
end

local function weaponButtons(weaponId: string, allowForge: boolean): { RowButton }
	local info = WeaponConfig.Weapons[weaponId]
	local state = profileTable("UnlockedWeapons")[weaponId]
	local equipped = K.profile() ~= nil and (K.profile() :: Payload).EquippedWeapon == weaponId
	if state == true then
		if equipped then
			return { { Text = "✔ Equipped", Color = K.COLORS.Good, Enabled = false, OnClick = function() end } }
		end
		return { { Text = "Equip", Color = K.COLORS.Accent, Enabled = not K.inRun(), OnClick = function()
			loadoutAction("Equip", { Weapon = weaponId })
		end } }
	end
	if not allowForge then
		return { { Text = "🔒 Blacksmith", Color = K.COLORS.PanelLight, Enabled = false, OnClick = function() end } }
	end
	local dust, cores = info.UnlockCost, info.UnlockCores
	local label: string
	if state == false then
		dust, cores = math.round(info.UnlockCost * REACTIVATION_FEE_FRACTION), 0
		label = ("Reactivate · %s %s"):format(K.formatNumber(dust), K.currencyIcon("RiftDust"))
	else
		label = ("Forge · %s%s %d%s"):format(K.formatNumber(dust), K.currencyIcon("RiftDust"), cores, K.currencyIcon("BossCores"))
	end
	local affordable = profileNumber("RiftDust") >= dust and profileNumber("BossCores") >= cores
	return { { Text = label, Color = K.COLORS.Gold, Enabled = affordable and not K.inRun(), OnClick = function()
		loadoutAction("Unlock", { Weapon = weaponId })
	end } }
end

local function weaponDesc(info: WeaponConfig.WeaponInfo): string
	local ability = info.Ability
	return ("%d dmg · %.1f atk/s · <b>Q</b> %s · <b>%s</b>: %s"):format(info.BaseDamage, info.AttacksPerSecond,
		if ability then ability.Name else "—", info.PassiveName, info.PassiveDesc)
end

local function renderBlacksmith()
	K.section(1, "Forge & Reactivate Weapons")
	K.paragraph(2, ("Your wallet: %s %s   %s %s   ·   Forged weapons stay yours; a Standard Rebirth only switches them off until you pay a 25%% reactivation fee."):format(
		K.currencyIcon("RiftDust"), K.formatNumber(profileNumber("RiftDust")), K.currencyIcon("BossCores"), K.formatNumber(profileNumber("BossCores"))),
		K.COLORS.Muted)
	for index, weaponId in WeaponConfig.Order do
		local info = WeaponConfig.Weapons[weaponId]
		actionRow(2 + index, ("%s %s  <font color='#%s'>%s</font>"):format(info.Icon, info.Name, K.COLORS.Muted:ToHex(), info.Archetype),
			weaponDesc(info), weaponButtons(weaponId, true), 84)
	end
end

local function linkSlots(): number
	local nodes = profileTable("AscensionNodes")
	return WeaponConfig.GetLinkSlots(tonumber(nodes.AS_T3_04) or 0, player:GetAttribute("HasExtraLinkSlots") == true)
end

local function linkRow(order: number, weaponId: string)
	local info = WeaponConfig.Weapons[weaponId]
	local link = info.Link
	local level, xp, paragon = masteryOf(weaponId)
	local active = profileTable("ActiveLinkSkills")
	local equipped = table.find(active, link.Id) ~= nil
	local value = WeaponConfig.GetLinkValue(weaponId, level)
	local tier = if level >= WeaponConfig.LINK_TIER2_LEVEL then "Tier 2" elseif level >= WeaponConfig.LINK_TIER1_LEVEL then "Tier 1" else "Locked"
	local title = ("%s %s  <font color='#%s'>%s%s</font>"):format(info.Icon, link.Name, K.COLORS.Muted:ToHex(), tier,
		if value > 0 then (" · +%d%% %s"):format(math.round(value * 100), LINK_STAT_NAMES[link.Stat] or link.Stat) else "")
	local desc = ("%s %s · +%d%% / +%d%% %s at Mastery 10 / 20"):format(info.Name, masteryText(level, xp, paragon),
		math.round(link.Lv10 * 100), math.round(link.Lv20 * 100), LINK_STAT_NAMES[link.Stat] or link.Stat)
	local button: RowButton
	if level < WeaponConfig.LINK_TIER1_LEVEL then
		button = { Text = ("🔒 Mastery %d"):format(WeaponConfig.LINK_TIER1_LEVEL), Color = K.COLORS.PanelLight, Enabled = false,
			OnClick = function() end }
	elseif equipped then
		button = { Text = "Unequip", Color = K.COLORS.Bad, Enabled = not K.inRun(), OnClick = function()
			loadoutAction("UnequipLink", { Link = link.Id })
		end }
	else
		button = { Text = "Equip Link", Color = K.COLORS.Accent, Enabled = #active < linkSlots() and not K.inRun(), OnClick = function()
			loadoutAction("EquipLink", { Link = link.Id })
		end }
	end
	actionRow(order, title, desc, { button })
end

local function renderLegionHall()
	local active = profileTable("ActiveLinkSkills")
	K.section(1, ("Hunter Legion Link Skills  ·  %d / %d slots"):format(#active, linkSlots()))
	K.paragraph(2, "Kills award Mastery XP to your equipped weapon. At Mastery 10 its Link Skill unlocks (Tier 2 at 20) and buffs you with ANY weapon. Past 20, Paragon ranks add +0.5% damage & Dust each.",
		K.COLORS.Muted)
	for index, weaponId in WeaponConfig.Order do
		linkRow(2 + index, weaponId)
	end
end

local function relicSlots(): number
	local nodes = profileTable("AscensionNodes")
	return RelicConfig.GetStartingSlots(tonumber(nodes.AS_T3_03) or 0, player:GetAttribute("HasRelicVaultKey") == true)
end

local function relicRow(order: number, relicId: string)
	local info = RelicConfig.Relics[relicId]
	local owned = profileTable("RelicStars")[relicId]
	if type(owned) ~= "table" then
		actionRow(order, "❔ Undiscovered Relic", "Drops from bosses (Room 5: 35%, Room 10: guaranteed) and Treasure Chests (25%).", {}, 60)
		return
	end
	local count = tonumber(owned.Stars) or 1
	local equipped = table.find(profileTable("EquippedStartingRelics"), relicId) ~= nil
	local buttons: { RowButton } = {}
	if equipped then
		table.insert(buttons, { Text = "Unequip", Color = K.COLORS.Bad, Enabled = not K.inRun(), OnClick = function()
			loadoutAction("UnequipRelic", { Relic = relicId })
		end })
	else
		table.insert(buttons, { Text = "Start With", Color = K.COLORS.Accent,
			Enabled = #profileTable("EquippedStartingRelics") < relicSlots() and not K.inRun(), OnClick = function()
				loadoutAction("EquipRelic", { Relic = relicId })
			end })
	end
	actionRow(order, ("%s %s  <font color='#%s'>%s</font>%s"):format(info.Icon, info.Name, K.COLORS.Gold:ToHex(), stars(count),
		if equipped then "  🎒" else ""), RelicConfig.Describe(relicId, count), buttons, 96)
end

local MEDALS = { "🥇", "🥈", "🥉" }

local function boardValue(format: string, value: number): string
	if format == "Room" then
		return ("Room %d"):format(value)
	elseif format == "Power" then
		local tier, level = value // 1000, value % 1000
		return if tier > 0 then ("Rebirth %s · Lv %d"):format(K.toRoman(tier), level) else ("Lv %d"):format(level)
	end
	return K.formatNumber(value)
end

local function renderHallOfChampions()
	local boards = K.stationData()
	if type(boards) ~= "table" then
		K.paragraph(1, "Loading…", K.COLORS.Muted)
		return
	end
	local order = 0
	for _, board in boards do
		order += 1
		K.section(order, ("%s %s"):format(tostring(board.Icon), tostring(board.Title)))
		local lines: { string } = {}
		for _, entry in board.Entries or {} do
			table.insert(lines, ("%s  <b>%s</b>   <font color='#%s'>%s</font>"):format(MEDALS[entry.Rank] or ("#%d"):format(entry.Rank),
				tostring(entry.Name), K.COLORS.Gold:ToHex(), boardValue(board.Format, tonumber(entry.Value) or 0)))
		end
		if #lines == 0 then
			table.insert(lines, "No champions yet — be the first!")
		end
		table.insert(lines, ("<font color='#%s'>You: %s</font>"):format(K.COLORS.XP:ToHex(), boardValue(board.Format, tonumber(board.You) or 0)))
		order += 1
		K.paragraph(order, table.concat(lines, "\n"))
	end
end

-- The Bag: loadout at a glance, usable anywhere (I / B / Select or the HUD button). Changes are town-only.
local function renderInventory()
	local data = K.profile()
	if not data then
		K.paragraph(1, "Loading…", K.COLORS.Muted)
		return
	end
	local weapon = WeaponConfig.Weapons[data.EquippedWeapon] or WeaponConfig.Weapons[WeaponConfig.DEFAULT_WEAPON]
	local level, xp, paragon = masteryOf(weapon.Id)
	K.section(1, ("%s %s  ·  equipped"):format(weapon.Icon, weapon.Name))
	local bar = K.newBar(K.content(), weapon.Accent, 2)
	K.setBar(bar, xp / math.max(1, masteryRequired(level, paragon)), masteryText(level, xp, paragon))
	K.paragraph(3, weaponDesc(weapon))
	local order = 3
	if K.inRun() then
		order += 1
		K.section(order, "This Run")
		local relicText: { string } = {}
		local runRelics = player:GetAttribute("RunRelics")
		if type(runRelics) == "string" then
			for entry in runRelics:gmatch("[^,]+") do
				local id, count = entry:match("^(.-):(%d+)$")
				local info = if id then RelicConfig.Relics[id] else nil
				if info and id and count then
					table.insert(relicText, ("%s <b>%s</b> %s — %s"):format(info.Icon, info.Name, stars(tonumber(count) or 1),
						RelicConfig.Describe(id, tonumber(count) or 1)))
				end
			end
		end
		local curses = player:GetAttribute("RunCurses")
		if type(curses) == "string" then
			for id in curses:gmatch("[^,]+") do
				local curse = CurseConfig.Curses[id]
				if curse then
					table.insert(relicText, ("%s <b>%s</b>: %s, %s"):format(curse.Icon, curse.Name, curse.Boon, curse.Bane))
				end
			end
		end
		order += 1
		K.paragraph(order, if #relicText > 0 then table.concat(relicText, "\n") else "No relics or curses yet — bosses, chests and Rift Shrines grant them.")
		order += 1
		K.paragraph(order, "Loadout changes unlock when you are back in Haven Outpost.", K.COLORS.Muted)
	end
	order += 1
	K.section(order, "Weapons")
	for _, weaponId in WeaponConfig.Order do
		if profileTable("UnlockedWeapons")[weaponId] ~= nil then
			local info = WeaponConfig.Weapons[weaponId]
			local wLevel, wXP, wParagon = masteryOf(weaponId)
			order += 1
			actionRow(order, ("%s %s"):format(info.Icon, info.Name), masteryText(wLevel, wXP, wParagon), weaponButtons(weaponId, false), 64)
		end
	end
	order += 1
	K.paragraph(order, "Forge more weapons at the ⚒️ Blacksmith.", K.COLORS.Muted)
	order += 1
	K.section(order, ("Link Skills  ·  %d / %d slots"):format(#profileTable("ActiveLinkSkills"), linkSlots()))
	local anyLink = false
	for _, weaponId in WeaponConfig.Order do
		local wLevel = masteryOf(weaponId)
		if wLevel >= WeaponConfig.LINK_TIER1_LEVEL then
			anyLink = true
			order += 1
			linkRow(order, weaponId)
		end
	end
	if not anyLink then
		order += 1
		K.paragraph(order, "Reach Mastery 10 with any weapon to unlock its Link Skill.", K.COLORS.Muted)
	end
	order += 1
	K.section(order, ("Starting Relics  ·  %d / %d"):format(#profileTable("EquippedStartingRelics"), relicSlots()))
	local anyRelic = false
	for _, relicId in RelicConfig.Order do
		if profileTable("RelicStars")[relicId] then
			anyRelic = true
			order += 1
			relicRow(order, relicId)
		end
	end
	if not anyRelic then
		order += 1
		K.paragraph(order, "Relics drop from bosses and chests. Star-Force them at the 🔨 Star-Forge.", K.COLORS.Muted)
	end
end

-- Big centre-screen banner for new relics, Mastery levels / Link Skills and quest rewards; shown one at a time.
local function showNextCelebration()
	local nextUp = table.remove(celebrateQueue, 1)
	if not nextUp then
		celebrating = false
		return
	end
	celebrating = true
	local color = if typeof(nextUp.Color) == "Color3" then nextUp.Color else K.COLORS.Gold
	celebrateIcon.Text = tostring(nextUp.Icon or "✨")
	celebrateTitle.Text = tostring(nextUp.Title or "")
	celebrateBody.Text = tostring(nextUp.Body or "")
	celebrateStroke.Color = color
	celebrateTitle.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
	celebrateFrame.Visible = true
	local scale = celebrateFrame:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.4
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(3.2, function()
		local shrink = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 })
		shrink.Completed:Connect(function()
			celebrateFrame.Visible = false
			showNextCelebration()
		end)
		shrink:Play()
	end)
end

local function celebrate(payload: any)
	if type(payload) ~= "table" then
		return
	end
	table.insert(celebrateQueue, payload)
	if not celebrating then
		showNextCelebration()
	end
end

local function buildCelebration()
	local layer = K.newLayer("RiftCelebrate", 45, false)
	celebrateFrame = K.newPanel(layer, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(520, 0), AutomaticSize = Enum.AutomaticSize.Y, Visible = false })
	celebrateStroke = celebrateFrame:FindFirstChildOfClass("UIStroke") :: UIStroke
	celebrateStroke.Thickness = 4
	K.create("UIScale", {}, celebrateFrame)
	K.pad(celebrateFrame, 14)
	local layout = K.list(celebrateFrame, Enum.FillDirection.Vertical, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	celebrateIcon = K.newLabel(celebrateFrame, { Size = UDim2.new(1, 0, 0, 52), TextSize = 46, TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1 })
	celebrateTitle = K.newLabel(celebrateFrame, { Size = UDim2.new(1, 0, 0, 32), Font = K.DISPLAY_FONT, TextSize = 28,
		TextStrokeTransparency = 0, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
	celebrateBody = K.newLabel(celebrateFrame, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 16,
		TextWrapped = true, TextColor3 = K.COLORS.Muted, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3 })
end

-- Run relics and curses as one short line for the HUD (RelicService / RunManagerService attributes).
function StationPanels.RunInfoText(): string
	local parts: { string } = {}
	local relics = player:GetAttribute("RunRelics")
	if type(relics) == "string" then
		for entry in relics:gmatch("[^,]+") do
			local id, count = entry:match("^(.-):(%d+)$")
			local info = if id then RelicConfig.Relics[id] else nil
			if info then
				table.insert(parts, ("%s%s"):format(info.Icon, string.rep("★", tonumber(count) or 1)))
			end
		end
	end
	local curses = player:GetAttribute("RunCurses")
	if type(curses) == "string" then
		for id in curses:gmatch("[^,]+") do
			local curse = CurseConfig.Curses[id]
			if curse then
				table.insert(parts, ("<font color='#%s'>%s</font>"):format(K.COLORS.Bad:ToHex(), curse.Icon))
			end
		end
	end
	return table.concat(parts, "  ")
end

StationPanels.Renderers = {
	Blacksmith = renderBlacksmith,
	LegionHall = renderLegionHall,
	StarForge = StarForgeScene.Render,
	QuestBoard = StationScenes.Renderers.QuestBoard,
	SparkSanctum = StationScenes.Renderers.SparkSanctum,
	HallOfChampions = renderHallOfChampions,
	Inventory = renderInventory,
} :: { [string]: () -> () }

StationPanels.Celebrate = celebrate
StationPanels.Sfx = Sfx
function StationPanels.Reset()
	StationScenes.Reset()
	StarForgeScene.Reset()
end

function StationPanels.Init(kit: any)
	K = kit
	loadoutRemote = Remotes.GetEvent("LoadoutAction")
	buildCelebration()
	SceneKit.Init(kit)
	StationScenes.Init(kit)
	StarForgeScene.Init(kit)
end

return StationPanels
