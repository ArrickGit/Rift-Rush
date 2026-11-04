--!strict
-- StarterPlayerScripts/Client/Controllers/Sfx.luau
-- One-shot interface sounds (clicks, panel open / close, quest claims, forge hits) from AssetRegistry.Sounds,
-- played locally. Each name keeps one Sound in SoundService and restarts it, with a short debounce so a burst of
-- identical events (several buttons wired to one click) does not stack into a roar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AssetRegistry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetRegistry"))

local Sfx = {}

local DEBOUNCE = 0.05
local DEFAULT_VOLUME = 0.5

local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local volumeScale = 1 -- the Settings screen's SFX volume
local rng = Random.new()
-- Gameplay sounds get a random pitch (0.92-1.08) so rapid repeats don't sound robotic (game.md 2.3); UI stays stable.
local VARIED: { [string]: boolean } = {
	Combat_Swing1 = true, Combat_Swing2 = true, Combat_Chop = true, Item_Drop = true,
	Weapon_Equip = true, Currency_Gain = true,
}

function Sfx.SetVolumeScale(scale: number)
	volumeScale = math.clamp(scale, 0, 1)
end

function Sfx.Play(name: string, volume: number?, pitch: number?)
	local id = AssetRegistry.Sounds[name]
	if not id or id == "" or volumeScale <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < DEBOUNCE then
		return
	end
	lastPlayed[name] = now
	local sound = sounds[name]
	if not sound then
		local created = Instance.new("Sound")
		created.Name = "Sfx_" .. name
		created.SoundId = id
		created.Parent = SoundService
		sounds[name] = created
		sound = created
	end
	sound.Volume = (volume or DEFAULT_VOLUME) * volumeScale
	local speed = pitch or 1
	if VARIED[name] then
		speed *= rng:NextNumber(0.92, 1.08)
	end
	sound.PlaybackSpeed = speed
	sound.TimePosition = 0
	sound:Play()
end

return Sfx
