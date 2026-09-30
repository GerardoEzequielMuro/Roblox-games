--!strict
-- Sound. Every cue looks up Config.Audio: a Roblox audio id set by the owner wins, then a
-- built-in rbxasset sound (ships with every client), otherwise the cue is silent. Music
-- tracks only exist once the owner fills their ids in; the suspense never depends on them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(script.Parent.Net)

local Audio = {}

local sounds: { [string]: Sound } = {}
local music: { [string]: Sound } = {}
local currentTrack: string? = nil
Audio.played = {} :: { [string]: number } -- cue counters (the playtest checks the tension cues fire)

local function idFor(name: string): string?
	local id = (Config.Audio.sfx :: any)[name]
	if type(id) == "number" and id ~= 0 then
		return "rbxassetid://" .. id
	end
	return (Config.Audio.builtin :: any)[name]
end

local function sfxVolume(): number
	local v = Net.setting("sfx")
	return if type(v) == "number" then v else 0.8
end

local function musicVolume(): number
	local v = Net.setting("music")
	return if type(v) == "number" then v else 0.5
end

function Audio.play(name: string, volume: number?, pitch: number?)
	Audio.played[name] = (Audio.played[name] or 0) + 1
	local id = idFor(name)
	local vol = (volume or 0.5) * sfxVolume()
	if not id or vol <= 0 then
		return
	end
	local snd = sounds[name]
	if not snd then
		local created = Instance.new("Sound")
		created.Name = "Sfx_" .. name
		created.SoundId = id
		created.Parent = SoundService
		sounds[name] = created
		snd = created
	end
	snd.Volume = vol
	snd.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(snd)
end

-- Cross-fades to a music track ("lobby", "match", "sudden", "win") or to silence (nil).
function Audio.music(track: string?)
	if track == currentTrack then
		return
	end
	local old = if currentTrack then music[currentTrack] else nil
	currentTrack = track
	if old then
		local t = TweenService:Create(old, TweenInfo.new(0.8), { Volume = 0 })
		t:Play()
		t.Completed:Once(function()
			if currentTrack ~= old.Name then
				old:Stop()
			end
		end)
	end
	if not track then
		return
	end
	local id = (Config.Audio.music :: any)[track]
	if type(id) ~= "number" or id == 0 then
		return
	end
	local snd = music[track]
	if not snd then
		local created = Instance.new("Sound")
		created.Name = track
		created.SoundId = "rbxassetid://" .. id
		created.Looped = true
		created.Volume = 0
		created.Parent = SoundService
		music[track] = created
		snd = created
	end
	snd:Play()
	TweenService:Create(snd, TweenInfo.new(1.2), { Volume = musicVolume() * 0.6 }):Play()
end

function Audio.refreshVolume()
	if currentTrack and music[currentTrack] then
		music[currentTrack].Volume = musicVolume() * 0.6
	end
end

return Audio
