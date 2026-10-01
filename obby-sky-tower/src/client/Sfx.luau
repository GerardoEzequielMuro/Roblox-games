--!strict
-- Sound hooks: Sfx.play("coin"). Ids live in Shared/Sounds and are empty (no uploaded audio), so
-- every call is a silent no-op until real ids are pasted there. A small pool of Sound objects is
-- reused so a burst of pickups never creates more than POOL instances.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local Sfx = {}

local POOL = 6
local pool: { Sound } = {}
local nextSlot = 1
local last: { [string]: number } = {}

function Sfx.play(name: string, pitch: number?)
	local asset = Sounds.assetFor(name)
	if not asset then
		return
	end
	-- the same sound at most every 60 ms (many coins in one frame = one sound)
	local now = os.clock()
	if now - (last[name] or -1) < 0.06 then
		return
	end
	last[name] = now
	local existing = pool[nextSlot]
	local s: Sound
	if existing and existing.Parent then
		s = existing
	else
		s = Instance.new("Sound")
		s.Name = "SkyTowerSfx"
		s.Parent = SoundService
		pool[nextSlot] = s
	end
	nextSlot = nextSlot % POOL + 1
	s.SoundId = asset
	s.Volume = Sounds.volume[name] or 0.6
	s.PlaybackSpeed = pitch or 1
	s:Play()
end

return Sfx
