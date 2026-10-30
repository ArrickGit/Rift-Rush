--!strict
-- StarterPlayerScripts/Client/Controllers/SettingsScene.luau
-- The Settings screen (opened from the Bag, in town or in a run): SFX volume and Screen Shake as big tap-to-pick
-- pills, saved with the profile (SaveSettings), plus the Credits card. The game-icons.net icons are CC BY 3.0, so
-- their authors must be credited in-game; this is where that happens.
--
-- ApplySettings runs on every profile update (from UIController), so saved settings take effect on join even if
-- this screen is never opened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetRegistry = require(Shared:WaitForChild("AssetRegistry"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Camera25DController = require(script.Parent:WaitForChild("Camera25DController"))
local SceneKit = require(script.Parent:WaitForChild("SceneKit"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))

type Payload = { [string]: any }

local SettingsScene = {}

local K: any = nil -- UIController's kit, set by Init
local saveRemote: RemoteEvent

local Icons = AssetRegistry.Icons
local icon = SceneKit.icon

local VOLUMES = { { Label = "Off", Value = 0 }, { Label = "25%", Value = 0.25 }, { Label = "50%", Value = 0.5 },
	{ Label = "75%", Value = 0.75 }, { Label = "100%", Value = 1 } }
local ICON_AUTHORS = "caro-asercion, darkzaitzev, delapouite, faithtoken, lorc, sbed, skoll, willdabeast, zeromancer"
local SETTINGS_COLORS = {
	Panel = Color3.fromHex("262b44"),
	Off = Color3.fromHex("3a4060"),
}

-- Shown immediately while the save round-trips, so taps feel instant.
local pending: Payload? = nil

local function current(): (number, boolean)
	local data = K.profile()
	local settings = if data and type(data.Settings) == "table" then data.Settings else {}
	local volume = if pending and pending.SfxVolume ~= nil then pending.SfxVolume else tonumber(settings.SfxVolume) or 1
	local shake = if pending and pending.ScreenShake ~= nil then pending.ScreenShake else settings.ScreenShake ~= false
	return volume, shake
end

local function save(change: Payload)
	pending = pending or {}
	for key, value in change do
		(pending :: Payload)[key] = value
	end
	local volume, shake = current()
	Sfx.SetVolumeScale(volume)
	Camera25DController.SetShakeEnabled(shake)
	saveRemote:FireServer({ SfxVolume = volume, ScreenShake = shake })
	K.renderStation()
end

-- A settings row: icon, label, and a strip of choice pills.
local function row(order: number, iconKey: string, label: string, choices: { { Label: string, Selected: boolean, OnClick: () -> () } })
	local panel = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = SETTINGS_COLORS.Panel, LayoutOrder = order })
	icon(panel, Icons[iconKey], { Position = UDim2.fromOffset(14, 17), Size = UDim2.fromOffset(36, 36) })
	K.newLabel(panel, { Position = UDim2.fromOffset(60, 0), Size = UDim2.fromOffset(180, 70), Text = label, Font = K.DISPLAY_FONT, TextSize = 22,
		TextStrokeTransparency = 0 })
	local strip: Frame = K.create("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(1, -250, 0, 44),
		BackgroundTransparency = 1 }, panel)
	local layout = K.list(strip, Enum.FillDirection.Horizontal, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	for index, choice in choices do
		local button = SceneKit.pill(strip, choice.Label, if choice.Selected then K.COLORS.Good else SETTINGS_COLORS.Off, true, choice.OnClick,
			{ Size = UDim2.new(1 / #choices, -6, 1, 0), TextSize = 17 })
		button.LayoutOrder = index
		if choice.Selected then
			K.create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
		end
	end
end

local function credits(order: number)
	local panel = K.newPanel(K.content(), { Size = UDim2.new(1, 0, 0, 172), BackgroundColor3 = SETTINGS_COLORS.Panel, LayoutOrder = order })
	K.pad(panel, 12)
	K.newLabel(panel, { Size = UDim2.new(1, 0, 0, 26), Text = "Credits", Font = K.DISPLAY_FONT, TextSize = 22, TextColor3 = K.COLORS.Gold,
		TextStrokeTransparency = 0 })
	K.newLabel(panel, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), TextWrapped = true, TextSize = 14,
		TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromHex("dcd6ee"),
		Text = ("<b>Icons</b> by %s. Available on game-icons.net under CC BY 3.0.\n\n<b>Sounds, particles and UI panels</b> by Kenney (kenney.nl), CC0.\n\n<b>Interface kit</b>: UIPack Plus. Built with Rojo."):format(ICON_AUTHORS) })
end

local function renderSettings()
	local volume, shake = current()
	local volumeChoices = {}
	for _, option in VOLUMES do
		table.insert(volumeChoices, { Label = option.Label, Selected = math.abs(volume - option.Value) < 0.01, OnClick = function()
			save({ SfxVolume = option.Value })
			Sfx.Play("UI_Click") -- a preview at the new volume
		end })
	end
	row(1, "UI_Settings", "Sound Effects", volumeChoices)
	row(2, "UI_Damage", "Screen Shake", {
		{ Label = "On", Selected = shake, OnClick = function()
			save({ ScreenShake = true })
			Sfx.Play("UI_Toggle", 0.6)
		end },
		{ Label = "Off", Selected = not shake, OnClick = function()
			save({ ScreenShake = false })
			Sfx.Play("UI_Toggle", 0.6)
		end },
	})
	credits(3)
end

SettingsScene.Render = renderSettings

-- Applies the profile's saved settings (called on every ProfileUpdated). Once the server echoes a change back,
-- the optimistic copy is dropped.
function SettingsScene.ApplySettings(profile: any)
	local settings = if type(profile) == "table" and type(profile.Settings) == "table" then profile.Settings else nil
	if not settings then
		return
	end
	if pending and (pending.SfxVolume == nil or pending.SfxVolume == settings.SfxVolume)
		and (pending.ScreenShake == nil or pending.ScreenShake == settings.ScreenShake) then
		pending = nil
	end
	if not pending then
		Sfx.SetVolumeScale(tonumber(settings.SfxVolume) or 1)
		Camera25DController.SetShakeEnabled(settings.ScreenShake ~= false)
	end
end

function SettingsScene.Init(kit: any)
	K = kit
	saveRemote = Remotes.GetEvent("SaveSettings")
end

return SettingsScene
