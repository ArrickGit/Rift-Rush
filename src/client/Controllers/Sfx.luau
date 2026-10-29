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

function Sfx.Play(name: string, volume: number?, pitch: number?)
	local id = AssetRegistry.Sounds[name]
	if not id or id == "" then
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
	sound.Volume = volume or DEFAULT_VOLUME
	sound.PlaybackSpeed = pitch or 1
	sound.TimePosition = 0
	sound:Play()
end

return Sfx
