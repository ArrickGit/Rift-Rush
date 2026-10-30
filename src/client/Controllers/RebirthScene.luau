--!strict
-- StarterPlayerScripts/Client/Controllers/RebirthScene.luau
-- The Rebirth (Ascension Pedestal) window drawn as a before → after: your Hunter Level racing towards the level the
-- next Rebirth needs, a NOW card and an AFTER card with the multipliers and Sparks as big numbers, two choice cards
-- (Standard / Keep Everything) whose buttons need a second tap to confirm, and the Robux options as small pills.
-- A Rebirth that just happened bursts the AFTER card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local FormulaEngine = require(Shared:WaitForChild("FormulaEngine"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Payload = { [string]: any }

local RebirthScene = {}

local K: any = nil -- UIController's kit, set by Init
local rebirthRemote: RemoteEvent

local Icons = AssetRegistry.Icons
local Vfx = AssetRegistry.VfxTextures
local tween = SceneKit.tween
local circle = SceneKit.circle
local icon = SceneKit.icon

local REBIRTH_COLORS = {
	Now = Color3.fromHex("2b2f45"),
	After = Color3.fromHex("3a2560"),
	Card = Color3.fromHex("2c2740"),
	Spark = Color3.fromHex("ff6fa0"),
	Up = Color3.fromHex("7dff9a"),
	Track = Color3.fromHex("161a2a"),
	Portal = Color3.fromHex("b28cff"),
}

local armed: string? = nil -- the Rebirth mode waiting for its confirming second tap
local lastTier: number? = nil

-- "x1.5", "x10", "x2.25": two decimals at most, no trailing zeros.
local function multiplier(value: number): string
	local text = ("%.2f"):format(value)
	text = text:gsub("0+$", "")
	text = text:gsub("%.$", "")
	return "x" .. text
end

-- Level progress towards the next Rebirth, with the portal at the end of the bar.
local function hero(order: number, preview: Payload)
	local level = tonumber(preview.HunterLevel) or 1
	local reqLevel = math.max(1, tonumber(preview.ReqLevel) or 50)
	local eligible = preview.Eligible == true
	local panel = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 74), BackgroundColor3 = REBIRTH_COLORS.Card, LayoutOrder = order })
	K.newLabel(panel, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -110, 0, 30),
		Text = ("Hunter Level <b>%d</b> <font size='18' color='#%s'>/ %d</font>"):format(level, K.COLORS.Muted:ToHex(), reqLevel),
		Font = K.DISPLAY_FONT, TextSize = 26, TextStrokeTransparency = 0 })
	local track: Frame = K.create("Frame", { Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -112, 0, 18),
		BackgroundColor3 = REBIRTH_COLORS.Track, BorderSizePixel = 0 }, panel)
	K.round(track, 9)
	K.outline(track, K.COLORS.Stroke, 2)
	local fill: Frame = K.create("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0,
		BackgroundColor3 = if eligible then K.COLORS.Good else K.COLORS.XP }, track)
	K.round(fill, 9)
	K.topLit(fill, 0.7)
	tween(fill, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(math.clamp(level / reqLevel, 0, 1), 1) })

	local portal = circle(panel, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = if eligible then REBIRTH_COLORS.After else REBIRTH_COLORS.Track })
	K.outline(portal, if eligible then REBIRTH_COLORS.Portal else K.COLORS.Stroke, 3)
	if eligible then
		local glow = icon(portal, Vfx.light_01, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(2.2, 2.2), ImageColor3 = REBIRTH_COLORS.Portal, ImageTransparency = 0.5 })
		tween(glow, SceneKit.PULSE, { ImageTransparency = 0.1 })
	end
	icon(portal, Icons.UI_Portal, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.62, 0.62),
		ImageColor3 = if eligible then Color3.new(1, 1, 1) else Color3.fromHex("5a6284") })
	if eligible then
		K.newLabel(panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 6), Size = UDim2.fromOffset(90, 30),
			Text = "READY!", Font = K.DISPLAY_FONT, TextSize = 22, TextColor3 = K.COLORS.Good, TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 0 })
	end
end

-- One stat line on a NOW / AFTER card: icon, value, small label.
local function statLine(parent: Instance, iconKey: string, iconColor: Color3, value: string, label: string, valueColor: Color3, order: number)
	local line: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	icon(line, Icons[iconKey], { Position = UDim2.fromOffset(0, 3), Size = UDim2.fromOffset(24, 24), ImageColor3 = iconColor })
	K.newLabel(line, { Position = UDim2.fromOffset(30, 0), Size = UDim2.new(0, 90, 1, 0), Text = value, Font = K.DISPLAY_FONT, TextSize = 24,
		TextColor3 = valueColor, TextStrokeTransparency = 0 })
	K.newLabel(line, { Position = UDim2.fromOffset(118, 0), Size = UDim2.new(1, -118, 1, 0), Text = label, TextSize = 13,
		TextColor3 = K.COLORS.Muted })
end

local function compareCard(parent: Instance, after: boolean, tier: number, dmg: number, eco: number, sparks: number?): Frame
	local card = K.newPanel(parent, { AnchorPoint = Vector2.new(if after then 1 else 0, 0), Position = UDim2.fromScale(if after then 1 else 0, 0),
		Size = UDim2.new(0.43, 0, 1, 0), BackgroundColor3 = if after then REBIRTH_COLORS.After else REBIRTH_COLORS.Now })
	K.pad(card, 10)
	K.newLabel(card, { Size = UDim2.new(1, 0, 0, 26),
		Text = ("%s  <font color='#%s'>%s</font>"):format(if after then "AFTER" else "NOW", (if after then REBIRTH_COLORS.Portal else K.COLORS.Muted):ToHex(),
			if tier > 0 then "Rebirth " .. K.toRoman(tier) else "No Rebirth"),
		Font = K.DISPLAY_FONT, TextSize = 20, TextStrokeTransparency = 0 })
	local lines: Frame = K.create("Frame", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32), BackgroundTransparency = 1 }, card)
	K.list(lines, Enum.FillDirection.Vertical, 2)
	local valueColor = if after then REBIRTH_COLORS.Up else Color3.new(1, 1, 1)
	statLine(lines, "UI_Damage", Color3.fromHex("ff8a5c"), multiplier(dmg), "Damage & HP", valueColor, 1)
	statLine(lines, "Cur_Dust", SceneKit.currencyColor("RiftDust"), multiplier(eco), "Rift Dust & XP", valueColor, 2)
	if sparks then
		statLine(lines, "Cur_Sparks", REBIRTH_COLORS.Spark, ("+%d"):format(sparks), "Rebirth Sparks", REBIRTH_COLORS.Spark, 3)
	end
	return card
end

local function compare(order: number, preview: Payload)
	local current = tonumber(preview.CurrentTier) or 0
	local nextTier = tonumber(preview.NextTier) or (current + 1)
	local now = FormulaEngine.GetRebirthInfo(current)
	local body: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 138), BackgroundTransparency = 1, LayoutOrder = order }, K.content())
	compareCard(body, false, current, if current > 0 then now.DmgMult else 1, if current > 0 then now.EcoMult else 1, nil)
	local afterCard = compareCard(body, true, nextTier, tonumber(preview.NextDmgMult) or 1, tonumber(preview.NextEcoMult) or 1,
		tonumber(preview.SparksGain) or 0)
	local arrow: TextLabel = K.newLabel(body, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(70, 60),
		Text = "»", Font = K.DISPLAY_FONT, TextSize = 60, TextColor3 = K.COLORS.Gold, TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0 })
	tween(arrow, SceneKit.PULSE, { Position = UDim2.new(0.5, 8, 0.5, 0) })
	if lastTier and current > lastTier then
		Sfx.Play("UI_Unlock", 0.8)
		Sfx.Play("Currency_Gain", 0.5)
		SceneKit.burst(afterCard, REBIRTH_COLORS.Portal)
	end
	lastTier = current
end

-- A choice card: title, 3 short icon lines, and a button that needs a second tap (or says why it can't be used).
local function choiceCard(parent: Instance, mode: string, title: string, lines: { { string } }, color: Color3, enabled: boolean,
	lockedText: string)
	local right = mode == "KeepEverything"
	local card = K.newPanel(parent, { AnchorPoint = Vector2.new(if right then 1 else 0, 0), Position = UDim2.fromScale(if right then 1 else 0, 0),
		Size = UDim2.new(0.49, 0, 1, 0), BackgroundColor3 = REBIRTH_COLORS.Card })
	K.pad(card, 10)
	K.newLabel(card, { Size = UDim2.new(1, 0, 0, 24), Text = title, Font = K.DISPLAY_FONT, TextSize = 21, TextColor3 = color,
		TextStrokeTransparency = 0 })
	for index, line in lines do
		K.newLabel(card, { Position = UDim2.fromOffset(0, 26 + (index - 1) * 18), Size = UDim2.new(1, 0, 0, 18), Text = line[1] .. "  " .. line[2],
			TextSize = 14, TextColor3 = Color3.fromHex("dcd6ee") })
	end
	local confirming = armed == mode
	local text = if not enabled then lockedText elseif confirming then "Tap again to Rebirth!" else "✨ Rebirth"
	local buttonColor = if confirming then K.COLORS.Bad else color
	local button = K.newButton(card, text, buttonColor, function()
		if not enabled then
			return
		end
		if armed == mode then
			armed = nil
			Sfx.Play("UI_Confirm", 0.7)
			rebirthRemote:FireServer({ Mode = mode })
		else
			armed = mode
			Sfx.Play("UI_Popup", 0.6)
		end
		K.renderStation()
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 54), TextSize = if confirming then 16 else 19 })
	K.setEnabled(button, enabled, buttonColor)
end

local function choices(order: number, preview: Payload)
	local eligible = preview.Eligible == true
	local body: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 158), BackgroundTransparency = 1, LayoutOrder = order }, K.content())
	choiceCard(body, "Standard", "Standard · Free", {
		{ "⬇", "Hunter Level → 1, Dust spent" },
		{ "🔒", "Worlds 2-8 & extra weapons sleep" },
		{ "★", "Relics, Mastery, Sparks nodes kept" },
	}, K.COLORS.Accent, eligible, ("Reach Lv %d"):format(tonumber(preview.ReqLevel) or 0))
	choiceCard(body, "KeepEverything", "👑 Keep Everything", {
		{ "★", "Keeps Dust, Worlds & Weapons" },
		{ "⬆", ("+%d Legacy levels"):format(tonumber(preview.LegacyGain) or 0) },
		{ "✨", ("+%d bonus Sparks"):format(tonumber(preview.KeepBonusSparks) or 0) },
	}, K.COLORS.Gold, eligible and preview.CanKeepEverything == true,
		if preview.CanKeepEverything ~= true then "Needs a Seal" else ("Reach Lv %d"):format(tonumber(preview.ReqLevel) or 0))
end

-- The Robux options as a row of pills.
local function robux(order: number, preview: Payload)
	local row: Frame = K.create("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, K.content())
	local layout = K.list(row, Enum.FillDirection.Horizontal, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local function pill(text: string, enabled: boolean, onClick: () -> (), index: number)
		local button = SceneKit.pill(row, text, K.COLORS.Robux, enabled, onClick, { Size = UDim2.new(0.32, 0, 1, 0), TextSize = 14 })
		button.LayoutOrder = index
	end
	if preview.Eligible ~= true then
		pill(("⚡ Instant · R$ %d"):format(tonumber(preview.SkipPrice) or 0), true, function()
			K.requestPurchase("Product", "InstantRebirth")
		end, 1)
	end
	local seal = MonetizationConfig.Products.KeepEverythingSeal
	pill(("👑 Seal · R$ %d"):format(seal.Price), true, function()
		K.requestPurchase("Product", seal.Key)
	end, 2)
	local pass = MonetizationConfig.Passes.TrueAscendant
	pill(if preview.HasTrueAscendant then "True Ascendant ✔" else ("True Ascendant · R$ %d"):format(pass.Price), preview.HasTrueAscendant ~= true,
		function()
			K.requestPurchase("Pass", pass.Key)
		end, 3)
	local credits = preview.PendingSkipCredits
	if type(credits) == "table" and #credits > 0 then
		K.paragraph(order + 1, ("⏳ %d Instant Rebirth credit(s) apply in town once your level matches."):format(#credits),
			Color3.fromRGB(120, 255, 200))
	end
end

local function renderRebirth()
	local preview = K.stationData()
	if type(preview) ~= "table" then
		K.paragraph(1, "Loading…", K.COLORS.Muted)
		return
	end
	hero(1, preview)
	compare(2, preview)
	choices(3, preview)
	robux(4, preview)
end

RebirthScene.Render = renderRebirth

-- Called when the station window closes, so a half-confirmed Rebirth never survives a reopen.
function RebirthScene.Reset()
	armed = nil
end

function RebirthScene.Init(kit: any)
	K = kit
	rebirthRemote = Remotes.GetEvent("RequestRebirth")
end

return RebirthScene
