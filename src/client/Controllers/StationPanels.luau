--!strict
-- StarterPlayerScripts/Client/Controllers/StationPanels.luau
-- Routes UIController's station window to the scene modules that draw each station: the Spark Sanctum and Quest
-- Board (StationScenes), the Star-Forge (StarForgeScene), the Blacksmith (BlacksmithScene), the Legion Hall
-- (LegionScene), the Hall of Champions (HallScene), the Rebirth pedestal (RebirthScene), the Bag (BagScene) and
-- the Central Rift Gate (RiftGateScene), plus the Settings & Credits screen (SettingsScene).
-- Also the centre-screen Celebrate banner (new relics, Mastery levels / Link Skills, quest rewards, reforges) and
-- the HUD's run relic / curse line. A Mythic reforge (Kind "Mythic", sent to the whole server) also posts a chat
-- system message, and flashes the screen for the player who forged it.
--
-- UIController owns the window and passes its drawing helpers in as a kit (Init); scenes draw into kit.content()
-- and every button fires a validated remote (LoadoutAction, StarForce, ClaimQuest, ...). Kept apart from
-- UIController so neither module comes near Luau's 200-local limit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CurseConfig = require(Shared:WaitForChild("CurseConfig"))
local RelicConfig = require(Shared:WaitForChild("RelicConfig"))
local BagScene = require(script.Parent:WaitForChild("BagScene"))
local BlacksmithScene = require(script.Parent:WaitForChild("BlacksmithScene"))
local HallScene = require(script.Parent:WaitForChild("HallScene"))
local LegionScene = require(script.Parent:WaitForChild("LegionScene"))
local RebirthScene = require(script.Parent:WaitForChild("RebirthScene"))
local RiftGateScene = require(script.Parent:WaitForChild("RiftGateScene"))
local SettingsScene = require(script.Parent:WaitForChild("SettingsScene"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local StarForgeScene = require(script.Parent:WaitForChild("StarForgeScene"))
local StationScenes = require(script.Parent:WaitForChild("StationScenes"))

type Payload = { [string]: any }

local StationPanels = {}

local player = Players.LocalPlayer
local K: any = nil -- UIController's kit, set by Init

local celebrateFrame: Frame
local celebrateIcon: TextLabel
local celebrateTitle: TextLabel
local celebrateBody: TextLabel
local celebrateStroke: UIStroke
local celebrateQueue: { Payload } = {}
local celebrating = false

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

-- Mythic reforge: a white-to-crimson full-screen flash for the forger only.
local function mythicFlash(color: Color3)
	local layer: ScreenGui = K.create("ScreenGui", { Name = "RiftMythicFlash", DisplayOrder = 60, IgnoreGuiInset = true,
		ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))
	local flash: Frame = K.create("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0 }, layer)
	local tween = TweenService:Create(flash, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundColor3 = color, BackgroundTransparency = 1 })
	tween.Completed:Connect(function()
		layer:Destroy()
	end)
	tween:Play()
	Sfx.Play("Forge_Success", 1)
end

local function celebrate(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.Kind == "Mythic" then
		local color = if typeof(payload.Color) == "Color3" then payload.Color else K.COLORS.Bad
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			pcall(function()
				general:DisplaySystemMessage(("<font color='#%s'><b>%s</b></font>"):format(color:ToHex(), tostring(payload.Body or "")))
			end)
		end
		if payload.Forger == player.UserId then
			mythicFlash(color)
		end
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
	Blacksmith = BlacksmithScene.Render,
	LegionHall = LegionScene.Render,
	StarForge = StarForgeScene.Render,
	QuestBoard = StationScenes.Renderers.QuestBoard,
	SparkSanctum = StationScenes.Renderers.SparkSanctum,
	HallOfChampions = HallScene.Render,
	AscensionPedestal = RebirthScene.Render,
	Inventory = BagScene.Render,
	RiftGate = RiftGateScene.Render,
	Settings = SettingsScene.Render,
} :: { [string]: () -> () }

StationPanels.Celebrate = celebrate
StationPanels.ApplySettings = SettingsScene.ApplySettings
StationPanels.Sfx = Sfx
function StationPanels.Reset()
	StationScenes.Reset()
	StarForgeScene.Reset()
	HallScene.Reset()
	RebirthScene.Reset()
end

function StationPanels.Init(kit: any)
	K = kit
	buildCelebration()
	SceneKit.Init(kit)
	StationScenes.Init(kit)
	StarForgeScene.Init(kit)
	BlacksmithScene.Init(kit)
	LegionScene.Init(kit)
	HallScene.Init(kit)
	RebirthScene.Init(kit)
	BagScene.Init(kit)
	RiftGateScene.Init(kit)
	SettingsScene.Init(kit)
end

return StationPanels
