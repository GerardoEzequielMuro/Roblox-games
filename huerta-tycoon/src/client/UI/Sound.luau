--!nonstrict
-- All game audio goes through here. The asset IDs live in Config.Sounds and ship EMPTY (0): with an id of 0 a
-- sound simply does not play and nothing is created, so the game is silent until the owner pastes IDs there.
--   Sound.play("click")   one-shot UI / gameplay sound
--   Sound.music()         starts the looping background track (Config.Sounds.music)
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Sound = {}

Sound.created = 0 -- Sound instances made so far (the test checks it stays 0 while every id is 0)
local cache: { [string]: Sound } = {}
local lastAt: { [string]: number } = {}
local MIN_GAP = 0.06 -- a Harvest All must not fire 30 copies of the same sound in one frame

function Sound.id(name: string): number?
	local v = (Config.Sounds :: any)[name]
	if type(v) == "number" and v > 0 then
		return v
	end
	return nil
end

local function get(name: string): Sound?
	local id = Sound.id(name)
	if not id then
		return nil
	end
	local s = cache[name]
	if not s then
		s = Instance.new("Sound")
		s.Name = "CK_" .. name
		s.SoundId = "rbxassetid://" .. tostring(id)
		s.Volume = (Config.SoundVolume :: any)[name] or 0.5
		s.Parent = SoundService
		cache[name] = s
		Sound.created += 1
	end
	return s
end

-- Returns true when a sound was actually started.
function Sound.play(name: string): boolean
	local s = get(name)
	if not s then
		return false
	end
	local now = os.clock()
	if now - (lastAt[name] or 0) < MIN_GAP then
		return false
	end
	lastAt[name] = now
	SoundService:PlayLocalSound(s)
	return true
end

function Sound.music(): boolean
	local s = get("music")
	if not s then
		return false
	end
	s.Looped = true
	if not s.IsPlaying then
		s:Play()
	end
	return true
end

return Sound
